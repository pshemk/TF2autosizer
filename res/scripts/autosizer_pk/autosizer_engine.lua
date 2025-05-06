local asrHelper = require "autosizer_pk/autosizer_helper"
local asrEnum = require "autosizer_pk/autosizer_enums"

local asrEngine = {}

-- the main state variable, stored in savefiles 
local engineState = {}

-- local cache for some model properties, to avoid api calls
-- local modelCache = {}

-- local cache for industries and buildings to avoid api calls
local consumerCache = {}

-- garbage collection timestamp
local lastGarbageCollection = os.time()

-- local cache for train configs
local trainConfigCache = {}

-- version of the state, in case of breaking changes

local globalStateVersion = 2
-- coroutines

local coroutines = {
    updateSupplyChains = nil,
    checkTrainsCapacity = nil,
}

local flags = {
    refreshNames = false,
    initDone = false,
    refreshEnabled = false,
    paused = false,
    initLine = false
}
-- industry related
local cargoTypes = {}

--temps
local fetchStockSystem = false
local trainsStatus = ""
local trainNameCache = {}

-- needed to get the in-game time
local worldId

-- strings
local i18Strings =  {
    length_warning = _("length_warning"),
    capacity_warning = _("capacity_warning"),
    unknown_cargo_warning = _("unknown_cargo_warning"),
    all_is_well = _("all_is_well"),
    status_misconfigured = _("status_misconfigured_stations"),
    status_configured = _("status_configured"),
}

local function getGameTime()

    if not worldId then worldId = api.engine.util.getWorld() end
    local gameTime = api.engine.getComponent(worldId, api.type.ComponentType.GAME_TIME)
    if gameTime then
        return gameTime.gameTime/1000
    end

end

local function getGameSpeed()

    if not worldId then worldId = api.engine.util.getWorld() end
    local gameSpeed = api.engine.getComponent(worldId, api.type.ComponentType.GAME_SPEED)
    if gameSpeed then
        return gameSpeed.speedup
    end
end

local function log(message) 
    if engineState[asrEnum.STATUS] and engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] then
        print(message)
    end
end


local function increseObjectVersion(objectType)
    if objectType then
        if not engineState[asrEnum.STATUS][objectType] then
            engineState[asrEnum.STATUS][objectType] = 1
        else
            engineState[asrEnum.STATUS][objectType] = engineState[asrEnum.STATUS][objectType] + 1
        end
    end
end

local function getTrainName(trainId)

    if not trainNameCache[tostring(trainId)] then
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.NAME)
        if  trainDetails then 
            trainNameCache[tostring(trainId)] = trainDetails.name
        else
            return trainId
        end
    end

    return trainNameCache[tostring(trainId)]
end

local function storeTimings(functionName, runDuration)

    if not engineState[asrEnum.TIMINGS] then engineState[asrEnum.TIMINGS] = {} end
    if not engineState[asrEnum.TIMINGS][functionName] then engineState[asrEnum.TIMINGS][functionName] = {} end
    engineState[asrEnum.TIMINGS][functionName][#engineState[asrEnum.TIMINGS][functionName] + 1 ] = runDuration
    if #engineState[asrEnum.TIMINGS][functionName] >= 20 then table.remove(engineState[asrEnum.TIMINGS][functionName], 1) end
end

local function enableLine(lineId)
    -- log("trying to enable line " .. lineId)

    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Configured"  or 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OK" or
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OverCapacity" or 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "UnknownCargo" or 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Warning" then 

        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = true
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.all_is_well
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()

        -- asrHelper.tprint(engineState, 0)
        return true
    else
        log("line: " .. lineId .. " not configured correctly can't enable")
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = false
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
        return false
    end
end

local function disableLine(lineId)
    log("disabling line " .. lineId)
    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = false
    -- engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Disabled"
    -- engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = "Configured"
    engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
end


local function checkLineConfig(lineId)

    local validStations = 0
    local enabledStations = 0
    -- check if at least one station is enabled and if each enabled station has a valid config
    if engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] then  -- in case the state got flushed in the meantime
        for _, stationConfig in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationConfig[asrEnum.station.ENABLED] == true then
                enabledStations = enabledStations + 1
                if stationConfig[asrEnum.station.ENABLED] then
                    if stationConfig[asrEnum.station.SELECTOR] == "industryShipping" and  stationConfig[asrEnum.station.INDUSTRY_ID] then
                        validStations = validStations + 1
                    elseif stationConfig[asrEnum.station.SELECTOR] == "shippingContract" and  stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID] then
                        validStations = validStations + 1
                    elseif stationConfig[asrEnum.station.SELECTOR] == "cargoGroup" and  stationConfig[asrEnum.station.CARGO_GROUP_ID] then
                        validStations = validStations + 1
                    elseif stationConfig[asrEnum.station.SELECTOR] == "fixedAmount" and stationConfig[asrEnum.station.FIXED_AMOUNT_VALUE] then
                        validStations = validStations + 1
                    end
                end
            end
        end
    end
    log("asrEngine: checkLineConfig: enabled: " .. enabledStations .. " valid: " .. validStations)
    if enabledStations > 0 and validStations == enabledStations  then
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OK" then 
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] then 
                enableLine(lineId)
            end
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Misconfigured" then
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Configured"
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.status_configured
            end
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] then 
                enableLine(lineId)
            end
        end
    else
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Misconfigured"
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.status_misconfigured
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] == true then 
            disableLine(lineId)
        end        
    end
    engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
end



local function flushTrackingInfo(lineId)

    if lineId then 
        -- find all trains on the line and invalidate their tracking info
        local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))
        if lineVehicles then
            for _, trainId in pairs(lineVehicles) do
                -- engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil
                engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = nil
            end
        end
    else 
        -- force all checks
        engineState[asrEnum.CHECKED_TRAINS] = {}
        -- engineState[asrEnum.TRACKED_TRAINS] = {}
    end
end


local function increaseMemberInUseCounter(memberId, memberType)

    log("asrEngine: imic: increasing for " .. memberType .. ": " .. memberId)
    if memberType == "shippingContract" then
        log("asrEngine: imic: increasing for shipping contract: " .. memberId)
        if  engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] == nil then 
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = 1
       else
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] + 1
       end
    end
    if memberType == "cargoGroup" then
        log("asrEngine: imic: increasing for cargo group: " .. memberId)
        if  engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] == nil then 
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = 1
       else
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] + 1
       end
    end
end

local function decreaseMemberInUseCounter(memberId, memberType)

    log("asrEngine: dmic: decreasing for " .. memberType .. ": " .. memberId)
    if memberType == "shippingContract" and engineState[asrEnum.SHIPPING_CONTRACTS][memberId] then
        log("asrEngine: dmic: decreasing for shipping contract: " .. memberId)
        if engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] and 
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] > 0 then
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] - 1
        end
    end
    if memberType == "cargoGroup" and engineState[asrEnum.CARGO_GROUPS][memberId] then
        log("asrEngine: dmic: decreasing for cargo group: " .. memberId)
        if engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] and 
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] > 0 then
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] - 1
        end
    end
end

local function checkMemberInUseCounter(memberId, memberType)

    if memberType == "shippingContract" and engineState[asrEnum.SHIPPING_CONTRACTS][memberId] then
        local currentCounter = engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE]
        if not currentCounter then 
            currentCounter = 0
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = 0
        end

        local discoveredCounter = 0
        -- loop through all lines and stations
        if engineState[asrEnum.LINES] then 
            for lineId, lineDetails in pairs(engineState[asrEnum.LINES]) do
                if lineDetails[asrEnum.line.STATIONS] then
                    for _, stationDetails in pairs(lineDetails[asrEnum.line.STATIONS]) do
                        if stationDetails[asrEnum.station.SHIPPING_CONTRACT_CARGO_ID] and stationDetails[asrEnum.station.SHIPPING_CONTRACT_CARGO_ID] == memberId then
                            discoveredCounter = discoveredCounter + 1
                        end
                    end
                end
            end
        end
        -- loop through all cargo groups
        if engineState[asrEnum.CARGO_GROUPS] then
            for _, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
                if cargoGroupDetails[asrEnum.cargoGroup.MEMBERS] then
                    for _, cargoGroupMemberDetails in pairs(cargoGroupDetails[asrEnum.cargoGroup.MEMBERS]) do
                        if cargoGroupMemberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID] and cargoGroupMemberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID] == memberId then
                            discoveredCounter = discoveredCounter + 1
                        end
                    end
                end
            end
        end
        if currentCounter ~= discoveredCounter then
            log("asrEngine: checkMemberInUseCounter: " .. memberType .. " " .. memberId .. " had incorrect reference count: " .. currentCounter .. " should be: " .. discoveredCounter)
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = discoveredCounter
        end
    end

    if memberType == "cargoGroup" and engineState[asrEnum.CARGO_GROUPS][memberId] then
        local currentCounter = engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE]
        if not currentCounter then 
            currentCounter = 0
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = 0
        end

        local discoveredCounter = 0
        -- loop through all lines and stations
        if engineState[asrEnum.LINES] then 
            for lineId, lineDetails in pairs(engineState[asrEnum.LINES]) do
                if lineDetails[asrEnum.line.STATIONS] then
                    for _, stationDetails in pairs(lineDetails[asrEnum.line.STATIONS]) do
                        if stationDetails[asrEnum.station.CARGO_GROUP_ID] and stationDetails[asrEnum.station.CARGO_GROUP_ID] == memberId then
                            discoveredCounter = discoveredCounter + 1
                        end
                    end
                end
            end
        end
        -- loop through all cargo groups
        if engineState[asrEnum.CARGO_GROUPS] then
            for _, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
                if cargoGroupDetails[asrEnum.cargoGroup.MEMBERS] then
                    for _, cargoGroupMemberDetails in pairs(cargoGroupDetails[asrEnum.cargoGroup.MEMBERS]) do
                        if cargoGroupMemberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID] and cargoGroupMemberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID] == memberId then
                            discoveredCounter = discoveredCounter + 1
                        end
                    end
                end
            end
        end
        if currentCounter ~= discoveredCounter then
            log("asrEngine: checkMemberInUseCounter: " .. memberType .. " " .. memberId .. " had incorrect reference count: " .. currentCounter .. " should be: " .. discoveredCounter)
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = discoveredCounter
        end
    end
end

local function asrCheckCargoTrackingReferences() 

    if engineState[asrEnum.SHIPPING_CONTRACTS] then
        for shippingContractId in pairs(engineState[asrEnum.SHIPPING_CONTRACTS]) do
            checkMemberInUseCounter(shippingContractId, "shippingContract")
        end
    end

    if engineState[asrEnum.CARGO_GROUPS] then
        for cargoGroupId in pairs(engineState[asrEnum.CARGO_GROUPS]) do
            checkMemberInUseCounter(cargoGroupId, "cargoGroup")
        end
    end
end

local function updateStation(stationConfig) 

    log("asrEngine: received station config: ")
    -- asrHelper.tprint(stationConfig)

    if engineState[asrEnum.LINES][tostring(stationConfig.lineId)] ~= nil and 
       engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)] ~= nil and
       engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.STATION_ID] == stationConfig.stationId then

        local storeAllProperties = true
        if stationConfig.config[asrEnum.station.SELECTOR] and stationConfig.config[asrEnum.station.SELECTOR] == "industryShipping" then
            if stationConfig.config[asrEnum.station.INDUSTRY_ID] == asrEnum.value.DELETE then
                -- clear all industry related entries
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SELECTOR] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.INDUSTRY_ID] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.INDUSTRY_KIND] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.INDUSTRY_CARGO_ID] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_AMOUNT] = 0
                storeAllProperties = false
            end
        end
        if stationConfig.config[asrEnum.station.SELECTOR] and stationConfig.config[asrEnum.station.SELECTOR] == "shippingContract" then
            if stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID] == asrEnum.value.DELETE then
                -- clear all shipping contract related entries, free the contract id if set 
                local previousShippingContractId = engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SHIPPING_CONTRACT_ID]
                if previousShippingContractId then 
                    decreaseMemberInUseCounter(previousShippingContractId, "shippingContract")
                    checkMemberInUseCounter(previousShippingContractId, "shippingContract")
                end
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SELECTOR] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SHIPPING_CONTRACT_ID] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SHIPPING_CONTRACT_CARGO_ID] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_AMOUNT] = 0
                storeAllProperties = false
            else
                -- check if there's a previous shipping contract, if so - decrease the reference counter
                local previousShippingContractId = engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SHIPPING_CONTRACT_ID]
                if previousShippingContractId then
                    decreaseMemberInUseCounter(previousShippingContractId, "shippingContract")
                    checkMemberInUseCounter(previousShippingContractId, "shippingContract")
                end
                if stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID] and engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID])] then
                    increaseMemberInUseCounter(stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID], "shippingContract")
                    checkMemberInUseCounter(stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID], "shippingContract")
                end
            end
        end
        if stationConfig.config[asrEnum.station.SELECTOR] and stationConfig.config[asrEnum.station.SELECTOR] == "cargoGroup" then
            if stationConfig.config[asrEnum.station.CARGO_GROUP_ID] == asrEnum.value.DELETE then
                -- clear all cargo group related entries, free the id if set 
                local previousCargoGroupId = engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_GROUP_ID]
                if previousCargoGroupId then 
                    decreaseMemberInUseCounter(previousCargoGroupId, "cargoGroup")
                    checkMemberInUseCounter(previousCargoGroupId, "cargoGroup")
                end
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.SELECTOR] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_GROUP_ID] = nil
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_AMOUNT] = 0
                storeAllProperties = false
            else 
                -- check if there's a previous cargo gorup, if so - decrease the reference counter
                local previousCargoGroupId = engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_GROUP_ID]
                if previousCargoGroupId then 
                    decreaseMemberInUseCounter(previousCargoGroupId, "cargoGroup")
                    checkMemberInUseCounter(previousCargoGroupId, "cargoGroup")
                end
                if stationConfig.config[asrEnum.station.CARGO_GROUP_ID] and engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig.config[asrEnum.station.CARGO_GROUP_ID])] then
                    increaseMemberInUseCounter(stationConfig.config[asrEnum.station.CARGO_GROUP_ID], "cargoGroup")
                    checkMemberInUseCounter(stationConfig.config[asrEnum.station.CARGO_GROUP_ID], "cargoGroup")
                end
            end
        end
        if storeAllProperties then 
            for propertyId, propertyValue in pairs(stationConfig.config) do
                engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][propertyId] = propertyValue
            end
        end
       engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
    -- asrHelper.tprint(engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS])
    flushTrackingInfo(stationConfig.lineId)
    checkLineConfig(stationConfig.lineId)
end

local function updateLinesNames()

    local linesUpdated = false

    if engineState[asrEnum.LINES] then
        for lineId in pairs(engineState[asrEnum.LINES]) do
            if api.engine.entityExists(tonumber(lineId)) then
                local lineName = api.engine.getComponent(tonumber(lineId), api.type.ComponentType.NAME)
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] == nil or engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] ~= lineName.name then
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] = lineName.name
                    linesUpdated = true
                end
            else
                print ("asrEngine: wrong component (line id): " .. lineId)
                break
            end
        end
        if linesUpdated then
            engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
        end
    end
end

local function updateLinesInfo()
        
    -- local lines = asrEngine.getAllRailLines()
    local lines = api.engine.system.lineSystem.getLines()
    local linesUpdated = false
    local linesIds = {}
    
    if engineState[asrEnum.STATUS] == nil then
        engineState[asrEnum.STATUS] = {
            [asrEnum.status.LINES_VERSION] = 0,
            [asrEnum.status.SHIPPING_CONTRACTS_VERSION] = 0,
            [asrEnum.status.CARGO_GROUPS_VERSION] = 0,
            [asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION] = 0
        }
    end

    -- log("asrEngine: state")
    -- asrHelper.tprint(engineState[asrEnum.STATUS])
    -- add any missing lines to the current state
    for _,lineId in pairs(lines) do
        linesIds[tostring(lineId)] = true
        if engineState[asrEnum.LINES] == nil then
            log("updateLinesInfo: no lines in state, initialising")
            engineState[asrEnum.LINES] = {}
        end
        if engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] == nil then
            engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = 0
        end
        if engineState[asrEnum.LINES][tostring(lineId)] == nil then
            log("updateLinesInfo: no info about line " .. lineId)
            linesUpdated = true
            engineState[asrEnum.LINES][tostring(lineId)] = {}
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = false
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] = {}
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] = {}
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] = {}
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Disabled"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] = {}
        end
    end

    local linesCounter = 0
    -- remove any lines no longer in the game
    if engineState[asrEnum.LINES] then
        for lineId, _ in pairs(engineState[asrEnum.LINES]) do
            if linesIds[tostring(lineId)] == nil then
                engineState[asrEnum.LINES][tostring(lineId)] = nil
                linesUpdated = true
            else
                linesCounter = linesCounter + 1
                -- log(lineId .. " c:" .. linesCounter)            
            end
        end
    end
    if linesUpdated then
        if engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] == nil then engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = 0 end
        engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] + 1
    end

    engineState[asrEnum.STATUS][asrEnum.status.LINES_COUNTER] = linesCounter
end

local function generateShippingContractName(shippingContractId)

    log("asrEngine: generate shipping contract name: ")

    -- get names of all the towns
    local townNames = {}
    
    api.engine.forEachEntityWithComponent(function (townId) 
        local townName = api.engine.getComponent(townId, api.type.ComponentType.NAME)
            if townName then
                table.insert(townNames, townName.name)
            end
    end, api.type.ComponentType.TOWN)

    local shippingContract = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(shippingContractId)]
    if shippingContract[asrEnum.shippingContract.SUPPLIER_ID] and shippingContract[asrEnum.shippingContract.CONSUMER_ID] then
        local supplierName = engineState[asrEnum.INDUSTRIES][tostring(shippingContract[asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.NAME]
        local consumerName = engineState[asrEnum.INDUSTRIES][tostring(shippingContract[asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.NAME]
        -- check if we can find the name of the town
        local supplierTown, consumerTown
        log("asrEngine: supplier: " .. shippingContract[asrEnum.shippingContract.SUPPLIER_ID] .. " consumer: " .. shippingContract[asrEnum.shippingContract.CONSUMER_ID])
        log("asrEngine: supplier: " .. supplierName .. " consumer: " .. consumerName)
        -- asrHelper.tprint(townNames)
        for _, townName in pairs(townNames) do
            if string.find(supplierName, townName) then
                supplierTown = townName
            end
            if string.find(consumerName, townName) then
                consumerTown = townName
            end
        end
        if supplierTown and consumerTown then
            local newShippingContractName =  supplierTown .. " - " .. consumerTown
            -- check if we don't have that name already
            local maxSequence = 0
            for _, existingShippingContract in pairs(engineState[asrEnum.SHIPPING_CONTRACTS]) do
                log("asrEngine: existing: " .. existingShippingContract[asrEnum.shippingContract.NAME])
                log("asrEngine: new     : " .. newShippingContractName)
                if string.find(existingShippingContract[asrEnum.shippingContract.NAME], newShippingContractName, 0, true) then
                    -- existing, check if we have a #number 
                    local sequence = string.match(existingShippingContract[asrEnum.shippingContract.NAME], "#(%d+)$")
                    log("asrEngine: existing (found): " .. existingShippingContract[asrEnum.shippingContract.NAME])
                    if not sequence then sequence = 1 end
                    if tonumber(sequence) > tonumber(maxSequence) then 
                        log("asrEngine: found sequence: " .. sequence)
                        maxSequence = sequence
                    end
                end
            end
            if tonumber(maxSequence) ~= 0 then
                log("asrEngine: using new name sequence: " .. (tonumber(maxSequence) + 1))
                newShippingContractName = newShippingContractName .. " #" .. (tonumber(maxSequence) + 1)
            end
            return newShippingContractName
        else
            log("not found")
        end
    end
end

local function generateCargoGroupName(cargoGroupId)

    log("asrEngine: generate name for cargo group: " .. cargoGroupId)
    -- find all the town names and join them
    -- get names of all the towns
    local townNames = {}
    
    api.engine.forEachEntityWithComponent(function (townId) 
        local townName = api.engine.getComponent(townId, api.type.ComponentType.NAME)
            if townName then
                table.insert(townNames, townName.name)
            end
    end, api.type.ComponentType.TOWN)

    
    local memberNames = {}
    for _, memberDetails in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
        local memberName
        if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" then
            if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])] and 
                engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.NAME] then 
                memberName = engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.NAME]
            end
        elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
            if engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])] and 
                engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME] then
                memberName = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME]
            end
        elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then 
            if engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])] and 
                engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME] then
                memberName = engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME]
            end
        end
        table.insert(memberNames, memberName)
    end

    local foundTowns = {}
    for _, memberName in pairs(memberNames) do
        for _, townName in pairs(townNames) do
            if string.find(memberName, townName) then
                if not asrHelper.inTable(foundTowns, townName) then
                    table.insert(foundTowns, townName)
                end
            end
        end
    end

    local newCargoGroupName = table.concat(foundTowns, " - ")
    -- check if we don't have that name already
    local maxSequence = 0
    for _, existingCargoGroup in pairs(engineState[asrEnum.CARGO_GROUPS]) do
        if string.find(existingCargoGroup[asrEnum.cargoGroup.NAME], newCargoGroupName, 0, true) then
            -- existing, check if we have a #number 
            local sequence = string.match(existingCargoGroup[asrEnum.cargoGroup.NAME], "#(%d+)$")
            if not sequence then sequence = 1 end
            if tonumber(sequence) > tonumber(maxSequence) then 
                maxSequence = sequence
            end
        end
    end
    if tonumber(maxSequence) ~= 0 then
        newCargoGroupName = newCargoGroupName .. " #" .. (tonumber(maxSequence) + 1)
    end
    return newCargoGroupName
end

local function checkCargoGroupMembers(cargoGroupId, currentList)

    -- log("asrEngine: checking members of: " .. cargoGroupId)
    if not currentList then 
        currentList = { cargoGroupId } 
    else
        table.insert(currentList, cargoGroupId)
    end
    local valid = true
    if engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
        for _, memberDetails in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
            if memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                -- log("asrEngine: found sub-cargo group: " .. memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID] )
                if asrHelper.inTable(currentList, memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID]) then
                    -- we found the same id again
                    log("asrEngine: checkCargoGroupMembers: duplicate found: " .. memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])
                    valid = false
                else
                    valid = valid and checkCargoGroupMembers(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID], currentList)
                end
            end
        end
    end
    if valid then
        -- log("asrEngine: check for " .. cargoGroupId .. " result is valid")
    else
        log("asrEngine: check for " .. cargoGroupId .. " result is not valid")
    end
    return valid

end

local function validateCargoGroups()

    if engineState[asrEnum.CARGO_GROUPS] then
        -- log("asrEngine: checking cargo groups")
        for cargoGroupId, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
            -- if not cargoGroupDetails[asrEnum.cargoGroup.VALIDITY_CHECKED] and not cargoGroupDetails[asrEnum.cargoGroup.VALID] then
                -- log("asrEngine: verfying main: " .. cargoGroupId)
                -- log("asrEngine: verfying main: actually checking")
                if checkCargoGroupMembers(cargoGroupId) then
                    engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.VALID] = true
                else
                    engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.VALID] = false
                    engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] = 0
                end
                engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.VALIDITY_CHECKED] = true
            -- end
        end
    end
end
local function getConsumerType(consumerId) 

    if consumerCache[tostring(consumerId)] ~= nil then
        return consumerCache[tostring(consumerId)][asrEnum.consumer.TYPE], consumerCache[tostring(consumerId)][asrEnum.consumer.TOWN]
    end
    local constructionEntity = api.engine.getComponent(tonumber(consumerId), api.type.ComponentType.CONSTRUCTION)
     if constructionEntity then
        if #constructionEntity.townBuildings > 0 then 
            -- a town building, make another call to identify the town 
            local townBuildingEntity = api.engine.getComponent(tonumber(constructionEntity.townBuildings[1]), api.type.ComponentType.TOWN_BUILDING)
            consumerCache[tostring(consumerId)] = {
                [asrEnum.consumer.TYPE] = "town",
                [asrEnum.consumer.TOWN] = townBuildingEntity.town
            }
            return "town", townBuildingEntity.town
        else 
            consumerCache[tostring(consumerId)] = {
                [asrEnum.consumer.TYPE] = "industry",
                [asrEnum.consumer.TOWN] = nil
            }
            return  "industry", nil
        end
    else
        print("asrEngine: can't determine game entity for consumer: " .. consumerId)
    end
end

local function updateSupplyChains(runInForeground) 

    -- get cargo mappings

    -- log("asrEngine: updateSupplyChains starting")
    local startTime = os.clock()
    local entryCounter = 1

    -- get the current list 
    if engineState[asrEnum.INDUSTRIES] == nil then
        engineState[asrEnum.INDUSTRIES] = {}
    end
    if engineState[asrEnum.STATUS][asrEnum.status.STOCK_ITERATION] == nil then
        engineState[asrEnum.STATUS][asrEnum.status.STOCK_ITERATION] = 0
    end
    local stockIteration = engineState[asrEnum.STATUS][asrEnum.status.STOCK_ITERATION] + 1
    local stockList = api.engine.system.stockListSystem.getCargoType2stockList2sourceAndCount()
    local stockListWithTowns = {}

    -- aggregate info about towns
    for cargoId, chainMap in pairs(stockList) do
        stockListWithTowns[cargoId] = {}
        if chainMap ~= nil then
            for consumerId, suppliers in pairs (chainMap) do
                local type, townId = getConsumerType(consumerId)
                if type == "industry" then
                    stockListWithTowns[cargoId][tostring(consumerId)] = {}
                    for supplierId, amount in pairs (suppliers) do
                        stockListWithTowns[cargoId][tostring(consumerId)][tostring(supplierId)] = amount
                    end
                elseif type == "town" then
                    if stockListWithTowns[cargoId][tostring(townId)] == nil then 
                        stockListWithTowns[cargoId][tostring(townId)] = {}
                    end
                    for supplierId, amount in pairs (suppliers) do
                        if stockListWithTowns[cargoId][tostring(townId)][tostring(supplierId)] == nil then
                            stockListWithTowns[cargoId][tostring(townId)][tostring(supplierId)] = amount
                        else
                            stockListWithTowns[cargoId][tostring(townId)][tostring(supplierId)] = stockListWithTowns[cargoId][tostring(townId)][tostring(supplierId)] + amount
                        end
                    end
                end
            end
        end
    end
    if not runInForeground and (os.clock() - startTime)*1000 >= 25 then
        -- log("asrEngine: updateSupplyChains running for more than 25ms - yielding - 1")
        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
        coroutine.yield()
        startTime = os.clock()
        entryCounter = entryCounter + 1
        -- log("asrEngine: updateSupplyChains resuming")
    end

    -- log("asrEngine: usc: got a stocklist")
    for cargoId, chainMap in pairs(stockList) do
        -- log("checking cargo " .. cargoTypes[cargoId])
        -- log("asrEngine: usc: checking cargoid: " .. cargoId)
        if chainMap ~= nil and cargoId ~= 1 then -- no passegers for now
           for consumerId, suppliers in pairs (chainMap) do
                -- log("asrEngine: usc: checking consumerid: " .. consumerId)

                -- check if the consumer is an industry or a town building
                local type, townId = getConsumerType(consumerId)

                -- log("asrEngine: usc: checking type: " .. type)
                if type == "industry" then 
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)] = {
                            [asrEnum.industry.CONSUMER] = {},  
                            [asrEnum.industry.CONSUMER_ITERATION] = {},
                            [asrEnum.industry.SUPPLIERS] = {}
                        }
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.NAME] == nil then 
                        local name = api.engine.getComponent(tonumber(consumerId), api.type.ComponentType.NAME)
                        if name then
                            engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.NAME] = name.name
                        end
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.TYPE] == nil then 
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.TYPE] = "industry"
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS] = {}
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER] = {}
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER_ITERATION] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER_ITERATION] = {}
                    end 
                    if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER][tostring(cargoId)] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = 0
                        engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] = stockIteration
                    end
                    if suppliers ~= nil then -- this check should not be neceesary
                        for supplierId, amount in pairs(suppliers) do
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)] = {
                                    [asrEnum.industry.SUPPLIER] = {},
                                    [asrEnum.industry.SUPPLIER_ITERATION] = {},
                                    [asrEnum.industry.CONSUMERS] = {}
                                }
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.NAME] == nil then 
                                local name = api.engine.getComponent(tonumber(supplierId), api.type.ComponentType.NAME)
                                if name then
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.NAME] = name.name
                                end
                            end    
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.TYPE] == nil then 
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.TYPE] = "industry"
                            end                                    
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(consumerId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)] = { supplierId }
                            else
                                if not asrHelper.inTable(engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)], supplierId) then 
                                    table.insert(engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)], supplierId)
                                end
                            end
                            -- record amount for the supplier
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = tonumber(amount)
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] = stockIteration
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)] = { consumerId }
                            else 
                                if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] ~= stockIteration then
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = tonumber(amount)
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] = stockIteration
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)] = { consumerId }
                                else
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] + tonumber(amount)
                                    if not asrHelper.inTable(engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)], consumerId) then
                                        table.insert(engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)], consumerId)
                                    end
                                end
                            end
                            -- record amount for the consumer too
                            if engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] ~= stockIteration then
                                engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = tonumber(amount)
                                engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] = stockIteration
                            else
                                engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = engineState[asrEnum.INDUSTRIES][tostring(consumerId)][asrEnum.industry.CONSUMER][tostring(cargoId)] + tonumber(amount)
                            end
                        end
                    end
                elseif type == "town" then
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(townId)] = {
                            [asrEnum.industry.CONSUMER] = {},  
                            [asrEnum.industry.CONSUMER_ITERATION] = {},
                            [asrEnum.industry.SUPPLIERS] = {}

                        }
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.NAME] == nil then 
                        local name = api.engine.getComponent(tonumber(townId), api.type.ComponentType.NAME)
                        if name then
                            engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.NAME] = name.name
                        end
                    end  
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.TYPE] == nil then 
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.TYPE] = "town"
                    end   
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS] = {}
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER] = {}
                    end
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER_ITERATION] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER_ITERATION] = {}
                    end 
                    if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER][tostring(cargoId)] == nil then
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = 0
                        engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] = stockIteration
                    end
                    if suppliers ~= nil then -- this check should not be neceesary
                        for supplierId, amount in pairs(suppliers) do
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)] = {
                                    [asrEnum.industry.SUPPLIER] = {},
                                    [asrEnum.industry.SUPPLIER_ITERATION] = {}
                                }
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.NAME] == nil then 
                                local name = api.engine.getComponent(tonumber(supplierId), api.type.ComponentType.NAME)
                                if name then
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.NAME] = name.name
                                end
                            end    
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(townId)] ~= nil and engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS] = {}
                            end
                            if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)] = { supplierId }
                            else
                                if not asrHelper.inTable(engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)], supplierId) then 
                                    table.insert(engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.SUPPLIERS][tostring(cargoId)], supplierId)
                                end
                            end
                            -- record amount for the supplier
                            if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] == nil then
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = tonumber(amount)
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] = stockIteration
                                engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)] = { townId }
                            else 
                                if engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] ~= stockIteration then
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = tonumber(amount)
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER_ITERATION][tostring(cargoId)] = stockIteration
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)] = { townId }
                                else
                                    engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] = engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.SUPPLIER][tostring(cargoId)] + tonumber(amount)
                                    if not asrHelper.inTable(engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)], townId) then
                                        table.insert(engineState[asrEnum.INDUSTRIES][tostring(supplierId)][asrEnum.industry.CONSUMERS][tostring(cargoId)], townId)
                                    end
                                end
                            end
                            -- record amount for the consumer too
                            if engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] ~= stockIteration then
                                engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = tonumber(amount)
                                engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER_ITERATION][tostring(cargoId)] = stockIteration
                            else
                                engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER][tostring(cargoId)] = engineState[asrEnum.INDUSTRIES][tostring(townId)][asrEnum.industry.CONSUMER][tostring(cargoId)] + tonumber(amount)
                            end
                        end
                    end
                else
                    print("asrEngine: updateSupplyChains: can't identify the consumer: " .. consumerId)
                end
           end 
           if not runInForeground and  (os.clock() - startTime)*1000 >= 25 then
                -- log("asrEngine: updateSupplyChains running for more than 25ms - yielding - 2")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("asrEngine: updateSupplyChains resuming")
            end
        end
    end

    -- populate shipping contracts with data
    if engineState[asrEnum.SHIPPING_CONTRACTS] then
        for shippingContractId, shippingContractDetails in pairs(engineState[asrEnum.SHIPPING_CONTRACTS]) do
            if shippingContractDetails[asrEnum.shippingContract.CARGO_ID] and shippingContractDetails[asrEnum.shippingContract.SUPPLIER_ID] and shippingContractDetails[asrEnum.shippingContract.CONSUMER_ID] and
                stockListWithTowns[tonumber(shippingContractDetails[asrEnum.shippingContract.CARGO_ID])] and
                stockListWithTowns[tonumber(shippingContractDetails[asrEnum.shippingContract.CARGO_ID])][tostring(shippingContractDetails[asrEnum.shippingContract.CONSUMER_ID])] and
                stockListWithTowns[tonumber(shippingContractDetails[asrEnum.shippingContract.CARGO_ID])][tostring(shippingContractDetails[asrEnum.shippingContract.CONSUMER_ID])][tostring(shippingContractDetails[asrEnum.shippingContract.SUPPLIER_ID])] then
                        engineState[asrEnum.SHIPPING_CONTRACTS][tostring(shippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT] = stockListWithTowns[tonumber(shippingContractDetails[asrEnum.shippingContract.CARGO_ID])][tostring(shippingContractDetails[asrEnum.shippingContract.CONSUMER_ID])][tostring(shippingContractDetails[asrEnum.shippingContract.SUPPLIER_ID])]
            end
            if not runInForeground and (os.clock() - startTime)*1000 >= 25 then
                -- log("asrEngine: updateSupplyChains running for more than 25ms - yielding - 3")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("asrEngine: updateSupplyChains resuming")
            end
        end
    end

    -- populate cargo groups with data
    if engineState[asrEnum.CARGO_GROUPS] then
        for cargoGroupId, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
            -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId)
            local totalAmount = 0
            local cargoAmounts = {}
            if cargoGroupDetails[asrEnum.cargoGroup.VALID] and cargoGroupDetails[asrEnum.cargoGroup.MEMBERS] then 
                if not engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNTS] then
                    engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNTS] = {}
                end
                for _, memberDetails in pairs(cargoGroupDetails[asrEnum.cargoGroup.MEMBERS]) do
                    if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" then
                        -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry: " .. tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID]))
                        if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])] then
                            -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok")
                            if  memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "supplier" then
                                -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - supplier ")
                                if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER] and 
                                engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then
                                    -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - supplier - found amount")
                                    totalAmount = totalAmount + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    if not cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then 
                                        cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    else
                                        cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    end
                                end
                            elseif memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "consumer" then
                                -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - consumer ")
                                if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER] and 
                                engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then
                                    -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - consumer - found amount")
                                    totalAmount = totalAmount + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    if not cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then 
                                        cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    else
                                        cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                    end
                                end
                           end
                        end
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
                        -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " shippingContract")
                        if engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])] and
                        engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT] then
                            totalAmount = totalAmount + engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                            if not cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then 
                                cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                            else
                                cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] = cargoAmounts[tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] + engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                            end
                        end
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                        -- log("asrEngine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " cargoGroup")
                        if engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])] and
                        engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT] then
                            totalAmount = totalAmount + engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT]
                            -- cargo groups might not just have the details
                            if engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNTS] then
                                for cargoId, cargoAmount in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNTS]) do
                                    if not cargoAmounts[tostring(cargoId)] then
                                        cargoAmounts[tostring(cargoId)] = cargoAmount
                                    else
                                        cargoAmounts[tostring(cargoId)] = cargoAmounts[tostring(cargoId)] + cargoAmount
                                    end
                                end
                            end
                        end
                    end
                end
            end
            engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] = totalAmount
            engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNTS] = cargoAmounts
            if not runInForeground and (os.clock() - startTime)*1000 >= 25 then
                -- log("asrEngine: updateSupplyChains running for more than 25ms - yielding - 4")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("asrEngine: updateSupplyChains resuming")
            end
        end
    end

    -- log("asrEngine: updateSupplyChains done after " .. math.ceil((os.clock() - startTime)*1000000)/1000 .. "ms ")
    if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
    engineState[asrEnum.STATUS][asrEnum.status.STOCK_ITERATION] = stockIteration
    
end


local function refreshLinesCargoAmounts()

    -- loop through all enabled lines and update shipping related data
    local startTime = os.clock()
    if engineState[asrEnum.LINES] then 
        for lineId, line in pairs(engineState[asrEnum.LINES]) do
            -- if line[asrEnum.line.ENABLED] == true then
                if engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] then  -- in case the state got flushed in the meantime
                    local alwaysTrack = false
                    for stopSequence, stationConfig in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                        if stationConfig[asrEnum.station.ENABLED] == true then
                            if stationConfig[asrEnum.station.SELECTOR] then
                                if stationConfig[asrEnum.station.SELECTOR] == "industryShipping" and stationConfig[asrEnum.station.INDUSTRY_ID] and
                                engineState[asrEnum.INDUSTRIES][tostring(stationConfig[asrEnum.station.INDUSTRY_ID])] and 
                                engineState[asrEnum.INDUSTRIES][tostring(stationConfig[asrEnum.station.INDUSTRY_ID])][stationConfig[asrEnum.station.INDUSTRY_KIND]] and 
                                engineState[asrEnum.INDUSTRIES][tostring(stationConfig[asrEnum.station.INDUSTRY_ID])][stationConfig[asrEnum.station.INDUSTRY_KIND]][stationConfig[asrEnum.station.INDUSTRY_CARGO_ID]] then                            
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = engineState[asrEnum.INDUSTRIES][stationConfig[asrEnum.station.INDUSTRY_ID]][stationConfig[asrEnum.station.INDUSTRY_KIND]][stationConfig[asrEnum.station.INDUSTRY_CARGO_ID]]
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNTS] = {
                                            [stationConfig[asrEnum.station.INDUSTRY_CARGO_ID]] = engineState[asrEnum.INDUSTRIES][stationConfig[asrEnum.station.INDUSTRY_ID]][stationConfig[asrEnum.station.INDUSTRY_KIND]][stationConfig[asrEnum.station.INDUSTRY_CARGO_ID]]
                                        }
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "shippingContract" and stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID] and 
                                    engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])] and
                                    engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT] then                            
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNTS] = {
                                            [stationConfig[asrEnum.station.SHIPPING_CONTRACT_CARGO_ID]] = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                                        }
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "cargoGroup" and stationConfig[asrEnum.station.CARGO_GROUP_ID] and
                                engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])] and 
                                engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT] then                            
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT]
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNTS] = engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNTS]
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "fixedAmount" and stationConfig[asrEnum.station.FIXED_AMOUNT_VALUE] then
                                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = stationConfig[asrEnum.station.FIXED_AMOUNT_VALUE]
                                end
                            end
                            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] and 
                                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] == 0 and 
                                engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] and 
                                engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] == 0 then
                                alwaysTrack = true
                            end
                        end
                    end
                    if alwaysTrack then
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ALWAYS_TRACK] = true
                    else
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ALWAYS_TRACK] = nil
                    end
                end
            -- end
        end
    end
    if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("refreshLinesCargoAmounts", math.ceil((os.clock() - startTime)*1000000)/1000) end
end

local function refreshLinesTravelTimes()

    -- loop through all enabled lines and update time related data
    if engineState[asrEnum.LINES] then 
        for lineId, line in pairs(engineState[asrEnum.LINES]) do
            if line[asrEnum.line.ENABLED] == true then
                if engineState[asrEnum.LINES][tostring(lineId)] then
                    if not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ALWAYS_TRACK] then
                        local lineDetails = game.interface.getEntity(lineId)
                        if lineDetails and lineDetails.frequency and lineDetails.frequency ~= 0 then
                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME] = 1 / lineDetails.frequency
                        end
                    else
                        -- manual time tracking
                        -- get line vehicles
                        local totalTravelTime = 0
                        local avgTripTime = 0
                        local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))
                        if vehicles then
                            for _, vehicleId in pairs(vehicles) do
                                local vehicleInfo = api.engine.getComponent(vehicleId, 70) -- vehicleInfo
                                if vehicleInfo then
                                    for i=1, #vehicleInfo.sectionTimes do 
                                        totalTravelTime = totalTravelTime + vehicleInfo.sectionTimes[i]
                                    end
                                end
                            end
                            avgTripTime = totalTravelTime/#vehicles/#vehicles
                            -- log("asrEngine: refreshLinesTravelTimes: lineId: " .. lineId .. " travelTime1: " .. avgTripTime)
                        end
                        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                            if stationDetails[asrEnum.station.STOP_DURATION] then
                                avgTripTime = avgTripTime + math.min(table.unpack(stationDetails[asrEnum.station.STOP_DURATION]))    
                            else
                                -- guess 20 sec per station
                                avgTripTime = avgTripTime + 20
                            end
                        end
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME] = avgTripTime
                    end
                end
            end
        end
    end
end

local function getModelDetails(modelId)
    local cargoCapacities = {}
    local foundCompartments = false
    local passengers = false

    if engineState[asrEnum.MODEL_CACHE][tostring(modelId)] ~= nil then
        return engineState[asrEnum.MODEL_CACHE][tostring(modelId)]
    else
        local modelDetails = api.res.modelRep.get(tonumber(modelId))
        -- log("checking modelId: " .. modelId)
    
        -- find the smallest capacity per vehicle, this will be the defaul
        local capacity = 9999
        if modelDetails.metadata.transportVehicle.compartments then 
            for i = 1, #modelDetails.metadata.transportVehicle.compartments do
                for j = 1, #modelDetails.metadata.transportVehicle.compartments[i].loadConfigs do 
                    for k = 1, #modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries do
                        if string.upper(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].type) ~= "PASSENGERS" then
                            cargoCapacities[string.upper(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].type)] = modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].capacity
                            -- log("model: " .. i .. ":" .. j .. ":" .. k .. " ->" )
                            -- asrHelper.tprint(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k])
                            foundCompartments = true
                            if modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].capacity < capacity then capacity = modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].capacity end
                            -- log(string.upper(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].type))
                        else
                            passengers = true
                        end
                    end
                end
            end
        elseif modelDetails.metadata.transportVehicle.compartmentsList then
            for j = 1, #modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs do 
                for k = 1, #modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries do
                    if string.upper(modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries[k].type) ~= "PASSENGERS" then
                        cargoCapacities[string.upper(modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries[k].type)] = modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries[k].capacity
                        -- log("model: " .. i .. ":" .. j .. ":" .. k .. " ->" )
                        -- asrHelper.tprint(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k])
                        foundCompartments = true
                        if modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries[k].capacity < capacity then capacity = modelDetails.metadata.transportVehicle.compartmentsList.loadConfigs[j].cargoEntries[k].capacity end
                        -- log(string.upper(modelDetails.metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntries[k].type))
                    else
                        passengers = true
                    end                    
                end
            end
        end
        if modelDetails.metadata.railVehicle and not passengers then -- only count trains with no passenger capability
            if not foundCompartments then
                engineState[asrEnum.MODEL_CACHE][tostring(modelId)] = {
                    [asrEnum.modelCache.TYPE] = "engine", 
                    [asrEnum.modelCache.CAPACITIES] = {},
                    [asrEnum.modelCache.CAPACITY] = 0,
                    [asrEnum.modelCache.LENGTH] = modelDetails.boundingInfo.bbMax.x - modelDetails.boundingInfo.bbMin.x,
                    [asrEnum.modelCache.COMPARTMENTS_COUNT] = 0,
                    [asrEnum.modelCache.USES_COMPARTMENTS] = false,
                }
            else 
                engineState[asrEnum.MODEL_CACHE][tostring(modelId)] = {
                    [asrEnum.modelCache.TYPE] = "wagon",
                    [asrEnum.modelCache.CAPACITIES] = cargoCapacities,
                    [asrEnum.modelCache.CAPACITY] = capacity * #modelDetails.metadata.transportVehicle.compartments,
                    [asrEnum.modelCache.LENGTH] = modelDetails.boundingInfo.bbMax.x - modelDetails.boundingInfo.bbMin.x,
                    [asrEnum.modelCache.COMPARTMENTS_COUNT] =  modelDetails.metadata.transportVehicle.compartments and #modelDetails.metadata.transportVehicle.compartments or 1,
                    [asrEnum.modelCache.USES_COMPARTMENTS] = modelDetails.metadata.transportVehicle.compartments and true or false,
                }
            end
        else 
            -- log("asrEngine: not a rail vehicle")
        end
        -- log("asrEngine: modelId:" .. modelId)
        -- asrHelper.tprint(engineState[asrEnum.MODEL_CACHE][modelId])
        return engineState[asrEnum.MODEL_CACHE][tostring(modelId)]
    end    
end

local function getTrainModels(trainId)
    -- determine the model 
    local trainInfo = {}
    if api.engine.entityExists(tonumber(trainId)) then
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
        -- log("asrEngine: getTrainModels getComponent")
        local trainVehicleList = {}
        if trainDetails and trainDetails.transportVehicleConfig and trainDetails.transportVehicleConfig.vehicles then
            trainVehicleList = trainDetails.transportVehicleConfig.vehicles
        end

        -- log("models for train " .. trainId)
        for _, vehicle in pairs(trainVehicleList) do
            -- log("found model id: " .. vehicle.part.modelId)
            local modelInfo = getModelDetails(vehicle.part.modelId)
            if modelInfo then
                if modelInfo[asrEnum.modelCache.TYPE] == "engine" then
                    if  trainInfo.engines then
                        if not asrHelper.inTable(trainInfo.engines, vehicle.part.modelId ) then
                            table.insert(trainInfo.engines, vehicle.part.modelId )
                        end
                    else
                        trainInfo.engines = { vehicle.part.modelId }
                    end
                elseif modelInfo[asrEnum.modelCache.TYPE] == "wagon" then
                    if  trainInfo.wagons then 
                        if not asrHelper.inTable(trainInfo.wagons, vehicle.part.modelId ) then
                            table.insert(trainInfo.wagons, vehicle.part.modelId )
                        end
                    else
                        trainInfo.wagons = { vehicle.part.modelId }
                    end
                end
            end
        end
        return trainInfo
    end
end

local function createCargoToWagonMap(lineId)

    -- loop through all stations on the line and fetch all the cargo ids
    if not cargoTypes then
        return
    end
    local cargosList = {}
    local filteredCargosList = {}
    local modelCargoCounters = {}

    if engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] then
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.CARGO_AMOUNTS] then
                for cargoId in pairs(stationDetails[asrEnum.station.CARGO_AMOUNTS]) do
                    if not asrHelper.inTable(cargosList, cargoId) then 
                        cargosList[cargoId] = {}
                    end
                end
            end
        end
    end
    -- find the wagons that can carry the cargo
    if engineState[asrEnum.LINES][tostring(lineId)] and 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] and 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] then
        for _, modelId in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS]) do 
            if not engineState[asrEnum.MODEL_CACHE][tostring(modelId)] then
                getModelDetails(tostring(modelId))          
            end
            if engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITIES] then
                for cargoId in pairs(cargosList) do 
                    for cargoName in pairs(engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITIES]) do
                        if cargoTypes[tonumber(cargoId)] and cargoName == string.upper(cargoTypes[tonumber(cargoId)]) then
                            table.insert(cargosList[cargoId], modelId)
                        end
                    end
                end
            end
        end
    else 
        log("asrEngine: createCargoToWagonMap: line: " .. lineId .. " no wagons found on the line:")
        asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES])
    end
    -- count how many times models appear for different cargos
    for _, modelList in pairs(cargosList) do 
        for _, modelId in pairs(modelList) do
            if not modelCargoCounters[modelId] then
                modelCargoCounters[modelId] = 1
            else 
                modelCargoCounters[modelId] = modelCargoCounters[modelId] + 1
            end
        end
    end
    -- sort them
    for cargoId, modelList in pairs(cargosList) do
        for _, modelId in pairs (modelList) do 
            if not filteredCargosList[cargoId] then
                filteredCargosList[cargoId] = {
                    [asrEnum.cargoWagonMap.GENERIC] = {},
                    [asrEnum.cargoWagonMap.SPECIFIC] = {},
                }
            end
            if modelCargoCounters[modelId] > 1 then 
                table.insert(filteredCargosList[cargoId][asrEnum.cargoWagonMap.GENERIC], modelId)
            else
                table.insert(filteredCargosList[cargoId][asrEnum.cargoWagonMap.SPECIFIC], modelId)
            end
        end 
    end
    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP] = filteredCargosList
end

local function generateTrainConfigForMultipleCargos(trainId, lineId, stopIndex)
    
    log("asrEngine: train " .. getTrainName(trainId) .. " generating new train config for multiple cargos")
    local startTime = os.clock()

    if engineState[asrEnum.LINES] and engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1] then
        
        local stationConfig = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1] 
        local cargoAmounts = stationConfig[asrEnum.station.CARGO_AMOUNTS] 
        local travelTime = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME]

        -- check for capacity scaling factor     
        local capacityScaleFactor = 1
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= 0 then 
                capacityScaleFactor = capacityScaleFactor + (engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]/100)
                log("asrEngine: train " .. getTrainName(trainId) .. " capacity factor: " .. capacityScaleFactor)
        end

        -- find max train length
        local maxTrainLength = 0
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR] == "manual" and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH] then
            maxTrainLength = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]
        elseif engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] then 
            maxTrainLength = engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]
        else
            maxTrainLength = 160
        end

        -- get the current make up of the train
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)

        local trainWagonModels = {}
        local trainCompartmentsUsed = {}
        local trainEngines = {}
        local cargoStatus = {}
        local engineCount = 0

        for idx, vehicle in pairs(trainDetails.transportVehicleConfig.vehicles) do
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)] == nil then
                print("asrEngine: train " .. getTrainName(trainId) .. " no info about model: " .. vehicle.part.modelId .. " refreshing cache" )
                getModelDetails(vehicle.part.modelId)
            end
            table.insert(trainWagonModels, vehicle.part.modelId)
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] == "engine" then 
                engineCount = engineCount + 1
                table.insert(trainEngines, idx)
            else
                for i = 1, engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] do 
                    table.insert(trainCompartmentsUsed, { inUse = false, wagonIdx = idx } )
                end
            end
        end

        -- for each cargo type - identify how much capacity we need
        for cargoId, cargoAmount in pairs(cargoAmounts) do
            -- get wagon models for the cargo and see if the train has enough wagons
            if not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP] or 
                not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] then
                createCargoToWagonMap(lineId)
            end
                        
            local requiredCapacity = math.ceil(capacityScaleFactor * travelTime / 720 * cargoAmount)                    
            local currentCapacity = 0
            local maxWagonCapacity = 0
            local wagonsFound = 0
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and 
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] then
                local validWagonModels = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC]
                for idx, compartment in pairs(trainCompartmentsUsed) do
                    if asrHelper.inTable(validWagonModels, tostring(trainWagonModels[compartment.wagonIdx])) then
                        if not compartment.inUse then 
                            currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]
                            if engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT] > maxWagonCapacity then 
                                maxWagonCapacity = engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT]
                            end
                            trainCompartmentsUsed[idx].inUse = true
                            trainCompartmentsUsed[idx].cargoId = cargoId
                            wagonsFound = wagonsFound + 1
                        end
                    end
                end
            end
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] then
                local validWagonModels = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC]
                for idx, compartment in pairs(trainCompartmentsUsed) do
                    if asrHelper.inTable(validWagonModels, tostring(trainWagonModels[compartment.wagonIdx])) then
                        if not compartment.inUse and currentCapacity < requiredCapacity then 
                            currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]
                            if engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT] > maxWagonCapacity then 
                                maxWagonCapacity = engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT]
                            end
                            trainCompartmentsUsed[idx].inUse = true
                            trainCompartmentsUsed[idx].cargoId = cargoId
                            wagonsFound = wagonsFound + 1
                        end
                    end
                end
            end                        
            cargoStatus[tostring(cargoId)] = { 
                requiredCapacity = requiredCapacity,
                currentCapacity = currentCapacity,
                maxWagonCapacity = maxWagonCapacity,
                wagonsFound = wagonsFound,
                priority = 0
            }
        end

        -- get current waiting cargo
        local cargoEntities = api.engine.system.simCargoSystem.getSimCargosForLine(tonumber(lineId))
        local waitingCargoCounter = {}
        if cargoEntities then
            for _, cargoEntityId in pairs(cargoEntities) do
                if api.engine.entityExists(cargoEntityId) then
                    local cargoDetailsAtTerminal = api.engine.getComponent(cargoEntityId, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL)
                    local cargoDetails = api.engine.getComponent(cargoEntityId, api.type.ComponentType.SIM_CARGO)
                    if cargoDetailsAtTerminal and cargoDetails then 
                        if cargoDetailsAtTerminal.lineStop0 == stopIndex then 
                            if not waitingCargoCounter[tostring(cargoDetails.cargoType + 1)] then waitingCargoCounter[tostring(cargoDetails.cargoType + 1)] = 0 end
                            waitingCargoCounter[tostring(cargoDetails.cargoType + 1)] = waitingCargoCounter[tostring(cargoDetails.cargoType + 1)] + 1
                        end
                    end
                end
            end
        end

        -- check if there's too much cargo (over what's expected)
        local tooMuchCargoWaiting = false
        for cargoId in pairs(cargoStatus) do
            if waitingCargoCounter[tostring(cargoId)] and cargoAmounts[tostring(cargoId)] and 
                waitingCargoCounter[tostring(cargoId)] > 3 * cargoAmounts[tostring(cargoId)] then
                tooMuchCargoWaiting = true
            end
        end
        if tooMuchCargoWaiting then
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] and 
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] >= 1 then 
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = true
            else
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] = 1
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = false
            end
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] then
                log("asrEngine: train " .. getTrainName(trainId) .. " clearing a one-off capacity warning at stop index: " .. stopIndex  .. ", line id: " .. lineId)
            end
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = false
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] = nil
        end

        -- check if there's some unexpected cargo waiting 
        local unknownCargoFound = false
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS] = nil
        for cargoId in pairs(waitingCargoCounter) do
            if not cargoStatus[tostring(cargoId)] then
                -- found cargo that we don't know about
                unknownCargoFound = true
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING] = true
                if not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS] then 
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS] = {}
                end
                if not asrHelper.inTable(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS], tostring(cargoId)) then
                    table.insert(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS], tostring(cargoId))
                    log("asrEngine: train " .. getTrainName(trainId) .. " picking up unexpected cargo at stop index: " .. stopIndex  .. ", cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]))
                end
            end
        end
        if not unknownCargoFound then
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS] = nil
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.UNKNOWN_CARGO_WARNING] = false
        end

        -- log("asrEngine: train " .. getTrainName(trainId) .. " cargo status 1: ")
        -- asrHelper.tprint(cargoStatus)

        -- check if we need to pick up waiting cargo
        if stationConfig[asrEnum.station.WAITING_CARGO_ENABLED] == true and 
            stationConfig[asrEnum.station.WAITING_CARGO_VALUE] ~= nil and 
            stationConfig[asrEnum.station.WAITING_CARGO_VALUE] > 0 then 

            local extraCargoWaiting = false
            local optionalCargoCounter = 0
            local reducableCargoCounter = 0
            log("asrEngine: train " .. getTrainName(trainId) .. " checking for waiting cargo")
            for cargoId, cargoStatusDetails in pairs(cargoStatus) do
                if waitingCargoCounter[tostring(cargoId)] then
                    log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " all cargo waiting: " .. waitingCargoCounter[tostring(cargoId)])
                    if waitingCargoCounter[tostring(cargoId)] > cargoStatusDetails.requiredCapacity then
                        log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " will pick up extra: " .. math.ceil((waitingCargoCounter[tostring(cargoId)] - cargoStatusDetails.requiredCapacity) * stationConfig[asrEnum.station.WAITING_CARGO_VALUE] / 100) .. " orginal requirement: " .. cargoStatusDetails.requiredCapacity) 
                        cargoStatus[tostring(cargoId)].requiredCapacity = cargoStatus[tostring(cargoId)].requiredCapacity + math.ceil((waitingCargoCounter[tostring(cargoId)] - cargoStatusDetails.requiredCapacity) * stationConfig[asrEnum.station.WAITING_CARGO_VALUE] / 100)
                        extraCargoWaiting = true
                    else
                        cargoStatus[tostring(cargoId)].reducableCargo = true
                        log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " could reduce requirement to waiting")
                        reducableCargoCounter = reducableCargoCounter + 1
                    end
                else 
                    log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " no cargo waiting")
                    -- if we have multiple cargo types here - mark cargo as optional
                    if asrHelper.getTableLength(cargoStatus) > 1 then
                        log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " could reduce requirement to 0")
                        cargoStatus[tostring(cargoId)].optionalCargo = true
                        cargoStatus[tostring(cargoId)].reducableCargo = true
                        optionalCargoCounter = optionalCargoCounter + 1
                        reducableCargoCounter = reducableCargoCounter + 1
                    end
                end
            end

            -- there is no backlog any more - clear the flag
            if stationConfig[asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] and not extraCargoWaiting then
                log("asrEngine: train " .. getTrainName(trainId) .. " backlog cleared - disabling automatic pick up")
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] = false
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] = false
                engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
            end
            -- log("asrEngine: train " .. getTrainName(trainId) .. " cargo status 2: ")
            -- asrHelper.tprint(cargoStatus)
            -- check if only some cargos are marked as optional, if so - remove their requrements, so others can grow
            if optionalCargoCounter ~= asrHelper.getTableLength(cargoStatus) then
                for cargoId, cargoStatusDetails in pairs(cargoStatus) do
                    if cargoStatusDetails.optionalCargo then
                        cargoStatus[cargoId].requiredCapacity = 0
                    end
                end
            end
            -- do the same for reducable amounts too             
            if reducableCargoCounter ~= asrHelper.getTableLength(cargoStatus) then
                for cargoId, cargoStatusDetails in pairs(cargoStatus) do
                    if cargoStatusDetails.reducableCargo then
                        cargoStatus[cargoId].requiredCapacity = waitingCargoCounter[tostring(cargoId)] and waitingCargoCounter[tostring(cargoId)] or 0
                    end
                end
            end
        end

        -- get cargo currently onboard of the train
        local cargoOnBoardAllTrains = api.engine.system.simEntityAtVehicleSystem.getVehicle2Cargo2SimEntitesMap()
        local cargoOnBoard = {}
        if cargoOnBoardAllTrains[tonumber(trainId)] then
            cargoOnBoard = cargoOnBoardAllTrains[tonumber(trainId)]
        end

        -- make sure that required capacity covers cargo alrady onboard - if not increase the requirement to match it
        for cargoId, cargoList in pairs(cargoOnBoard) do
            if #cargoList > 0 then 
                if cargoStatus[tostring(cargoId)] then 
                    if  cargoStatus[tostring(cargoId)].requiredCapacity and #cargoList > cargoStatus[tostring(cargoId)].requiredCapacity then
                        print("asrEngine: train " .. getTrainName(trainId) .. " onboard cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " amount: " .. #cargoList .. " currently required: " .. cargoStatus[tostring(cargoId)].requiredCapacity .. " increasing to match it")
                        cargoStatus[tostring(cargoId)].requiredCapacity = #cargoList
                        cargoStatus[tostring(cargoId)].priority = 2
                    end
                else 
                    print("asrEngine: train " .. getTrainName(trainId) .. " onboard cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " amount: " .. #cargoList .. " that was not expected, increasing to match it")
                    cargoStatus[tostring(cargoId)] = { requiredCapacity = #cargoList, currentCapacity = 0, maxWagonCapacity = 0, wagonsFound = 0, priority = 2 }
                end
            end
        end
        
        
        -- log("asrEngine: train " .. getTrainName(trainId) .. " cargo status 3: ")
        -- asrHelper.tprint(cargoStatus)

        local newTrainCompartmentsConfig = {}   -- list of compartments
        math.randomseed(os.time())  -- seed the generator

        -- generate the config, cargo by cargo
        local additionsOnly = true
        for cargoId, cargoStatusDetails in pairs(cargoStatus) do
            if cargoStatusDetails.currentCapacity > cargoStatusDetails.requiredCapacity and cargoStatusDetails.currentCapacity <  cargoStatusDetails.requiredCapacity + cargoStatusDetails.maxWagonCapacity then
                log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " reusing previous config, wagons found: " .. cargoStatusDetails.wagonsFound)
            elseif cargoStatusDetails.currentCapacity > cargoStatusDetails.requiredCapacity + cargoStatusDetails.maxWagonCapacity then
                log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " reducing from current: " .. cargoStatusDetails.currentCapacity .. " to required: " .. cargoStatusDetails.requiredCapacity .. ", wagons found: " .. cargoStatusDetails.wagonsFound .. " capacity: " .. cargoStatusDetails.maxWagonCapacity)
                additionsOnly = false
            elseif cargoStatusDetails.currentCapacity < cargoStatusDetails.requiredCapacity then
                log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " inceasing from current: " .. cargoStatusDetails.currentCapacity .. " to required: " .. cargoStatusDetails.requiredCapacity .. ", wagons found: " .. cargoStatusDetails.wagonsFound .. " capacity: " .. cargoStatusDetails.maxWagonCapacity)
            elseif cargoStatusDetails.requiredCapacity == 0 then
                log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " reducing from current: " .. cargoStatusDetails.currentCapacity .. " to none")
                additionsOnly = false
            end

            local addedCapacity = 0            
            if cargoStatusDetails.requiredCapacity > 0 then
                for _, compartmentDetails  in pairs(trainCompartmentsUsed) do
                    if compartmentDetails.cargoId == cargoId then

                        local trainWagonModelId = trainWagonModels[compartmentDetails.wagonIdx]
                        if not newTrainCompartmentsConfig[tostring(trainWagonModelId)] then newTrainCompartmentsConfig[tostring(trainWagonModelId)] = {} end
                        table.insert(newTrainCompartmentsConfig[tostring(trainWagonModelId)], { type = "copy", source = compartmentDetails.wagonIdx, cargoId = cargoId, priority = cargoStatusDetails.priority })
                        -- log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " ..  string.upper(cargoTypes[tonumber(cargoId)]) .. " idx: " .. idx .. " modelId: " .. trainWagonModels[idx])
                        addedCapacity = addedCapacity + engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModelId)][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]
                        if addedCapacity >= cargoStatusDetails.requiredCapacity then
                            -- we have enough
                            break
                        end
                    end
                end
            end
            -- check if we need to generate more compartments
            while addedCapacity < cargoStatusDetails.requiredCapacity do
                 -- prefer specific models
                 if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and 
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] and 
                    #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] > 0 then
                    local modelSeq = math.random(#engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC])
                    local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC][modelSeq]
                    if not newTrainCompartmentsConfig[tostring(modelId)] then newTrainCompartmentsConfig[tostring(modelId)] = {} end
                    table.insert(newTrainCompartmentsConfig[tostring(modelId)], { type = "new", kind = "specific", cargoId = cargoId, priority = cargoStatusDetails.priority })
                    addedCapacity = addedCapacity + engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]
                 elseif engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and 
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] and
                    #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] > 0 then
                    local modelSeq = math.random(#engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC])
                    local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC][modelSeq]
                    if not newTrainCompartmentsConfig[tostring(modelId)] then newTrainCompartmentsConfig[tostring(modelId)] = {} end
                    table.insert(newTrainCompartmentsConfig[tostring(modelId)], { type = "new", kind = "generic", cargoId = cargoId, priority = cargoStatusDetails.priority  })
                    addedCapacity = addedCapacity + engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]
                 else
                    log("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " can't find any wagons to choose from")
                    break
                 end
            end
        end

        -- check if there's at least one wagon for each cargo type
        -- to avoid breaking the supply chains, only if the minimal train length is not 0
        if engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] > 0 then 
            for cargoId, cargoWagonMap in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP]) do
                -- first check generic ones
                local wagonFound = false
                for _, wagonModelId in pairs(cargoWagonMap[asrEnum.cargoWagonMap.GENERIC]) do
                    if newTrainCompartmentsConfig[tostring(wagonModelId)] then 
                        wagonFound = true
                        break
                    end
                end
                if not wagonFound then 
                    -- look through specific
                    for _, wagonModelId in pairs(cargoWagonMap[asrEnum.cargoWagonMap.SPECIFIC]) do
                        if newTrainCompartmentsConfig[tostring(wagonModelId)] then 
                            wagonFound = true
                            break
                        end
                    end
                end

                -- still not found? - add a wagon - prefer a generic one
                if not wagonFound then
                    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and 
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] and
                        #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] > 0 then
                        local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC][1]
                        if not newTrainCompartmentsConfig[tostring(modelId)] then newTrainCompartmentsConfig[tostring(modelId)] = {} end
                        table.insert(newTrainCompartmentsConfig[tostring(modelId)], { type = "new", kind = "generic-extra", cargoId = cargoId, priority = 1  })
                    elseif engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] and 
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] and
                        #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] > 0 then
                        local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC][1]
                        if not newTrainCompartmentsConfig[tostring(modelId)] then newTrainCompartmentsConfig[tostring(modelId)] = {} end
                        table.insert(newTrainCompartmentsConfig[tostring(modelId)], { type = "new", kind = "specific-extra", cargoId = cargoId, priority = 1  })
                    end
                end
            end
        end
        

        -- log("asrEngine: train " .. getTrainName(trainId) .. " new compartments list created")
        -- asrHelper.tprint(newTrainCompartmentsConfig)

        local newTrainConfig = {}

        -- turn the list of compartments into wagon configs
        local wagonCounter = 0
        for wagonModelId, compartments in pairs(newTrainCompartmentsConfig) do 
            local modelCompartmentCount = engineState[asrEnum.MODEL_CACHE][tostring(wagonModelId)][asrEnum.modelCache.COMPARTMENTS_COUNT]

            for i=1, #compartments do
                if (i - 1) % modelCompartmentCount == 0  then
                    -- add a wagon 
                    if compartments[i].type == "copy" then
                        table.insert(newTrainConfig, { 
                            modelId = wagonModelId,
                            kind = { compartments[i].kind },
                            type = "copy",
                            source = compartments[i].source,
                            cargoId = { compartments[i].cargoId },
                            priority = compartments[i].priority
                         })    
                    elseif compartments[i].type == "new" then
                        table.insert(newTrainConfig, { 
                            modelId = wagonModelId,
                            kind = { compartments[i].kind },
                            type = "new",
                            cargoId = { compartments[i].cargoId },
                            priority = compartments[i].priority
                         })
                    end
                    wagonCounter = wagonCounter + 1
                    -- asrHelper.tprint(newTrainConfig)
                else 
                    -- wagon is existing - only add details 
                    table.insert(newTrainConfig[wagonCounter].kind, compartments[i].kind)
                    table.insert(newTrainConfig[wagonCounter].cargoId, compartments[i].cargoId)
                    if compartments[i].priority > newTrainConfig[wagonCounter].priority then
                        newTrainConfig[wagonCounter].priority = compartments[i].priority
                    end
                end
            end
        end

        -- check if we have the minimal number of wagons required 
        if engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] and 
            #newTrainConfig - engineCount < engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] then
            
            for cargoId, cargoWagonMap in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP]) do
                -- first check generic ones
                if #cargoWagonMap[asrEnum.cargoWagonMap.GENERIC] > 0 then
                    for i = 0, engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] - #newTrainConfig - engineCount + 1 do 
                        local modelId = cargoWagonMap[asrEnum.cargoWagonMap.GENERIC][1]
                        table.insert(newTrainConfig, { type = "new", modelId = modelId, kind = { "generic-zero" }, cargoId = { cargoId }, priority = 0 })
                    end
                elseif #cargoWagonMap[asrEnum.cargoWagonMap.SPECIFIC] > 0 then
                    for i = 0, engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] - #newTrainConfig - engineCount + 1 do 
                        local modelId = cargoWagonMap[asrEnum.cargoWagonMap.SPECIFIC][1]
                        table.insert(newTrainConfig, { type = "new", modelId = modelId, kind = { "specific-zero" }, cargoId = { cargoId }, priority = 0 })
                    end
                end
            end
        end

        table.sort(newTrainConfig, function(a, b) 
            if a.priority ~= b.priority then
                return a.priority > b.priority
            else
                return tonumber(a.modelId) > tonumber(b.modelId)
            end
        end)

        -- copy engine(s) from the original train
        for idx, engineIndex in pairs(trainEngines) do
            table.insert(newTrainConfig, idx, { type = "copy", source = engineIndex })
        end
        
        -- config generated, turn it into a train config
        log("asrEngine: train " .. getTrainName(trainId) .. " new train config created")
        -- asrHelper.tprint(newTrainConfig)

        local currentWagonCount  = #trainDetails.transportVehicleConfig.vehicles - engineCount
        local requiredWagonCount = #newTrainConfig - engineCount
        local stage

        if requiredWagonCount == 0 then
            stage = "departure"
        else
            if currentWagonCount == 0 or additionsOnly then
                stage = "arrival"
            else
                stage = "unload"
            end
        end

        local trainConfig =  api.type.TransportVehicleConfig.new()
        local trainLength = 0
        local trainTooLong = false

        local autoLoadConfig
        local loadConfig
        -- copy from existing train as many as needed
        for idx, vehicleDetails in pairs(newTrainConfig) do

            local vehicleConfig = api.type.TransportVehiclePart.new()
            local vehiclePart = api.type.VehiclePart.new()
            local modelId

            if vehicleDetails.type == "copy" then
                local vehicle = trainDetails.transportVehicleConfig.vehicles[vehicleDetails.source]
                modelId = vehicle.part.modelId
                local cargos = " "
                if vehicleDetails.cargoId then
                    for _, cargoId in pairs(vehicleDetails.cargoId) do
                        cargos = cargos .. string.upper(cargoTypes[tonumber(cargoId)]) .. " "
                    end
                end
                log("asrEngine: train " .. getTrainName(trainId) ..  " copying modelId: " .. vehicle.part.modelId .. (cargos ~= " " and  (" cargo:" .. cargos) or " ENGINE") .. ((vehicleDetails.priority and vehicleDetails.priority ~= 0)  and (" priority: " .. vehicleDetails.priority) or ""))
                autoLoadConfig = {}
                loadConfig = {}
                if engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.USES_COMPARTMENTS] == false or   -- need to accomodate for potentially stale data  and old way of counting compartments
                   engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] == 0 then 
                    autoLoadConfig = {1}
                    loadConfig = {0}
                else 
                    for i=1, engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] do 
                        table.insert(autoLoadConfig, 1)
                        table.insert(loadConfig, 0)
                    end
                end
                vehiclePart.modelId = modelId
                vehiclePart.reversed = vehicle.part.reversed
                vehiclePart.loadConfig = loadConfig
                vehicleConfig.part = vehiclePart
                vehicleConfig.purchaseTime = vehicle.purchaseTime
                vehicleConfig.maintenanceState = vehicle.maintenanceState
                vehicleConfig.targetMaintenanceState = vehicle.targetMaintenanceState
                vehicleConfig.autoLoadConfig = autoLoadConfig

            elseif vehicleDetails.type == "new" then
                modelId = vehicleDetails.modelId
                local cargos = " "
                if vehicleDetails.cargoId then
                    for _, cargoId in pairs(vehicleDetails.cargoId) do
                        cargos = cargos .. string.upper(cargoTypes[tonumber(cargoId)]) .. " "
                    end
                end
                local kinds = " "
                if vehicleDetails.kind then
                    for _, kind in pairs(vehicleDetails.kind) do
                        kinds = kinds .. kind .. " "
                    end
                end
                log("asrEngine: train " .. getTrainName(trainId) .. " new modelId: " .. modelId .. " cargos:" .. cargos .. " kind:" .. kinds .. ((vehicleDetails.priority and vehicleDetails.priority ~= 0)  and (" priority: " .. vehicleDetails.priority) or ""))
                autoLoadConfig = {}
                loadConfig = {}
                if engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.USES_COMPARTMENTS] == false then 
                    autoLoadConfig = {1}
                    loadConfig = {0}
                else
                    for j=1, engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] do
                        table.insert(autoLoadConfig, 1)
                        table.insert(loadConfig, 0)
                    end
                end
                vehiclePart.modelId = tonumber(modelId)
                vehiclePart.reversed = false
                vehiclePart.loadConfig = loadConfig
                vehicleConfig.part = vehiclePart
                vehicleConfig.autoLoadConfig = autoLoadConfig
            end

            if not engineState[asrEnum.MODEL_CACHE][tostring(modelId)] or not engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.LENGTH] then 
                print("asrEngine: train " .. getTrainName(trainId) .. " no info about model: " .. modelId .. " refreshing cache" )
                getModelDetails(modelId)
            end
            if trainLength + engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.LENGTH] < maxTrainLength then
                trainConfig.vehicles[idx] = vehicleConfig
                trainConfig.vehicleGroups[idx] = 1
                trainLength = trainLength + engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.LENGTH]
            else
                trainTooLong = true
                break
            end
        end

        if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then 
            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRAIN_LENGTH] = trainLength
        end

        log("asrEngine: train " .. getTrainName(trainId) .. " total train length: " .. trainLength)
        if trainTooLong then
            -- only if waiting cargo pickup is not enabled 
            if not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] then 
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] and 
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] >= 1 then
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = true
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] + 1
                    log("asrEngine: train " .. getTrainName(trainId) .. " would be too long (raising a warning), line id: " .. lineId)
                else
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = 1
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
                    log("asrEngine: train " .. getTrainName(trainId) .. " would be too long (not raising a warning yet), line id: " .. lineId)
                end
            else
                log("asrEngine: train " .. getTrainName(trainId) .. " would be too long, but not reporting it")
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = nil
            end
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] then
                log("asrEngine: train " .. getTrainName(trainId) .. " clearing a one-off length warning at stop index: " .. stopIndex .. ", line id: " .. lineId)
            end
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = nil
        end

        -- check all stations for flags
        local lengthWarning = false
        local lengthWarningMessage = i18Strings.length_warning
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.LENGTH_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    lengthWarningMessage = lengthWarningMessage .. "\n" .. stationName.name
                    if stationDetails[asrEnum.station.LENGTH_WARNING_COUNT] then
                        lengthWarningMessage = lengthWarningMessage .. " (x" .. stationDetails[asrEnum.station.LENGTH_WARNING_COUNT] .. ")"
                    end
                end
                lengthWarning = true
            end
        end

        local capacityWarning = false
        local capacityWarningMessage = i18Strings.capacity_warning
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.CAPACITY_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    capacityWarningMessage = capacityWarningMessage .. "\n" .. stationName.name
                    if stationDetails[asrEnum.station.CAPACITY_WARNING_COUNT] then
                        capacityWarningMessage = capacityWarningMessage .. " (x" .. stationDetails[asrEnum.station.CAPACITY_WARNING_COUNT] .. ")"
                    end
                end
                capacityWarning = true
            end
        end

        local unknownCargoWarning = false
        local unknownCargoWarningMessage = i18Strings.unknown_cargo_warning
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.UNKNOWN_CARGO_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    unknownCargoWarningMessage = unknownCargoWarningMessage .. "\n" .. stationName.name
                    if stationDetails[asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS] then
                        unknownCargoWarningMessage = unknownCargoWarningMessage .. " ("
                        for _, cargoId in pairs(stationDetails[asrEnum.station.UNKNOWN_CARGO_WARNING_CARGOS]) do
                            unknownCargoWarningMessage = unknownCargoWarningMessage .. string.upper(cargoTypes[tonumber(cargoId)]) .. " "
                        end
                        unknownCargoWarningMessage = string.sub(unknownCargoWarningMessage, 1, -2)
                        unknownCargoWarningMessage = unknownCargoWarningMessage .. ")"
                    end
                end
                unknownCargoWarning = true
            end
        end

        if capacityWarning then 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OverCapacity"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = capacityWarningMessage
        elseif lengthWarning then
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Warning"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = lengthWarningMessage
        elseif unknownCargoWarning then
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "UnknownCargo"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = unknownCargoWarningMessage
        else
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.all_is_well
        end

        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("generateTrainConfigForMultipleCargos", math.ceil((os.clock() - startTime)*1000000)/1000) end
        return trainConfig, stage
    else
        log("asrEngine: train " .. getTrainName(trainId) .. " no info about line: " .. lineId .. " stopIndex: " .. stopIndex)
    end
end

local function generateTrainConfigForASingleAmount(trainId, lineId, stopIndex)

    log("asrEngine: train " .. getTrainName(trainId) .. " generating new train config for a single amount ")
    local startTime = os.clock()
    -- generate new train configuration 
    if engineState[asrEnum.LINES] and engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1] then
        
        local cargoAmount = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CARGO_AMOUNT]
        local travelTime = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME]
        
        if not travelTime then 
            print("asrEngine: train " .. getTrainName(trainId) .. " no travel time")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)])
            return
        end
        if not cargoAmount then 
            print("asrEngine: train " .. getTrainName(trainId) .. " no cargo amount")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1])
            return
        end

        local capacityScaleFactor = 1

        -- check if we need to adjust the capacity 
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= 0 then 
                capacityScaleFactor = capacityScaleFactor + (engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]/100)
                log("asrEngine: train " .. getTrainName(trainId) .. " capacity factor: " .. capacityScaleFactor)
        end


        local requiredCapacity = capacityScaleFactor * travelTime / 720 * cargoAmount
        local requiredWagonCount = math.ceil(requiredCapacity / engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY])
        local additionalWagonCount = 0
        local stage -- tells when to carry out the replacement

        -- check how much cargo is waiting for this train
        local cargoEntities = api.engine.system.simCargoSystem.getSimCargosForLine(tonumber(lineId))
        local cargoEntityCounter = 0
        if cargoEntities then
            for _, cargoEntityId in pairs(cargoEntities) do
                if api.engine.entityExists(cargoEntityId) then
                    local cargoDetails = api.engine.getComponent(cargoEntityId, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL)
                    if cargoDetails then 
                        if cargoDetails.lineStop0 == stopIndex then 
                            cargoEntityCounter = cargoEntityCounter + 1
                        end
                    end
                end
            end
        end

        if cargoEntityCounter > 3 * cargoAmount then
            -- we have more cargo then expected - raise a warning
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] and 
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] >= 1 then 
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = true
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] + 1
                log("asrEngine: train " .. getTrainName(trainId) .. " at stop: " .. stopIndex .. " too much cargo waiting: " .. cargoEntityCounter .. " expected max of: " .. cargoAmount .. "(raising a warning), line id: " .. lineId)
            else
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] = 1
                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = false
                log("asrEngine: train " .. getTrainName(trainId) .. " at stop: " .. stopIndex .. " too much cargo waiting: " .. cargoEntityCounter .. " expected max of: " .. cargoAmount .. "(not raising a warning yet), line id: " .. lineId)
            end
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] then
                log("asrEngine: train " .. getTrainName(trainId) .. " clearing a one-off capacity warning at stop index: " .. stopIndex  .. ", line id: " .. lineId)
            end
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING] = false
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_WARNING_COUNT] = nil
        end
        
        -- check if we need to accomodate for waiting cargo
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] == true and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE] ~= nil and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE] > 0 then 

            local requiredCapacity = requiredWagonCount *  engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY]

            log("asrEngine: train " .. getTrainName(trainId) .. " total cargo waiting at " .. stopIndex .. " is " .. cargoEntityCounter)
            if cargoEntityCounter > requiredCapacity then 
                -- extra wagons needed
                additionalWagonCount = math.ceil((cargoEntityCounter - requiredCapacity) * engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE]/100/engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY])
                log("asrEngine: train " .. getTrainName(trainId) .. " adding extra " .. additionalWagonCount .. " wagon(s)")
            else 
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] then
                    -- there is no backlog any more - clear the flag
                    log("asrEngine: train " .. getTrainName(trainId) .. " backlog cleared - disabling automatic pick up")
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] = false
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] = false
                    engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
                end
            end
        end

        requiredWagonCount = requiredWagonCount + additionalWagonCount

        if engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] and 
            requiredWagonCount < engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] then
                requiredWagonCount = engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT]
                log("asrEngine: train " .. getTrainName(trainId) .. " train would be shorter than minimal, adding wagons")
            end
        
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)

        -- check how many engines we have
        local engineCount = 0
        for _, vehicle in pairs(trainDetails.transportVehicleConfig.vehicles) do
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] == "engine" then engineCount = engineCount + 1 end
        end
        log("asrEngine: train " .. getTrainName(trainId) .. " has " .. engineCount .. " engine(s)" )

        local currentWagonCount =  #trainDetails.transportVehicleConfig.vehicles - engineCount

        if requiredWagonCount == 0 then
            stage = "departure"
        else
            if currentWagonCount == 0 then
                stage = "arrival"
            else
                stage = "unload"
            end
        end

        log("asrEngine: train " .. getTrainName(trainId) .. " current count: " .. currentWagonCount .. " new count: " .. requiredWagonCount)

        local maxTrainLength = 0
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR] == "manual" and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH] then
            maxTrainLength = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]
        elseif engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] then 
            maxTrainLength = engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]
        else
            maxTrainLength = 160
        end

        local vehicleCounter = 1
        local trainConfig =  api.type.TransportVehicleConfig.new()
        local trainLength = 0
        local trainTooLong = false

        local autoLoadConfig
        local loadConfig
        -- copy from existing train as many as needed
        for _, vehicle in pairs(trainDetails.transportVehicleConfig.vehicles) do
            local vehicleConfig = api.type.TransportVehiclePart.new()
            local vehiclePart = api.type.VehiclePart.new()

            log("asrEngine: train " .. getTrainName(trainId) .. " copying modelId: " .. vehicle.part.modelId)
            autoLoadConfig = {}
            loadConfig = {}
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] == 0 then 
                autoLoadConfig = {1}
                loadConfig = {0}
            else 
                for i=1, engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] do 
                    table.insert(autoLoadConfig, 1)
                    table.insert(loadConfig, 0)
                end
            end
            vehiclePart.modelId = vehicle.part.modelId
            vehiclePart.reversed = vehicle.part.reversed
            vehiclePart.loadConfig = loadConfig
            vehicleConfig.part = vehiclePart
            vehicleConfig.purchaseTime = vehicle.purchaseTime
            vehicleConfig.maintenanceState = vehicle.maintenanceState
            vehicleConfig.targetMaintenanceState = vehicle.targetMaintenanceState
            vehicleConfig.autoLoadConfig = autoLoadConfig

            if trainLength + engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.LENGTH] < maxTrainLength then
                trainConfig.vehicles[vehicleCounter] = vehicleConfig
                trainConfig.vehicleGroups[vehicleCounter] = 1
                trainLength = trainLength + engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.LENGTH]
                vehicleCounter = vehicleCounter + 1
                if vehicleCounter > requiredWagonCount + engineCount then
                    -- log("asrEngine: train " .. getTrainName(trainId) .. " train copy, got to " .. (vehicleCounter - 1 ) )
                    break
                end
            else
                trainTooLong = true
                break
            end
        end

        if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then 
            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRAIN_LENGTH] = trainLength
        end

        -- if any more wagons are required - add them based on what's been discovered  in other trains on the line
        math.randomseed(os.time())        
        for i = vehicleCounter, requiredWagonCount + engineCount do 
            local vehicleConfig = api.type.TransportVehiclePart.new()
            local vehiclePart = api.type.VehiclePart.new()

            local modelSeq = math.random(#engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS])
            log("asrEngine: train " .. getTrainName(trainId) .. " adding new modelId: " .. engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq] .. " using seq of: " .. modelSeq)

            autoLoadConfig = {}
            loadConfig = {}
            if not engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])] then
                print("asrEngine: train " .. getTrainName(trainId) .. " issue getting details of wagon no: " .. modelSeq .. " refreshing cache")
                getModelDetails(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])
            end

            if engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.COMPARTMENTS_COUNT] == 0 then 
                autoLoadConfig = {1}
                loadConfig = {0}
            else
                for j=1, engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.COMPARTMENTS_COUNT] do
                    table.insert(autoLoadConfig, 1)
                    table.insert(loadConfig, 0)
                end
            end
            vehiclePart.modelId = tonumber(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])
            vehiclePart.reversed = false
            vehiclePart.loadConfig = loadConfig
            vehicleConfig.part = vehiclePart
            vehicleConfig.autoLoadConfig = autoLoadConfig
            if trainLength + engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.LENGTH] < maxTrainLength then
                trainLength = trainLength + engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.LENGTH]
                trainConfig.vehicles[i] = vehicleConfig
                trainConfig.vehicleGroups[i] = 1
            else
                trainTooLong = true
                break
            end

        end

        log("asrEngine: train " .. getTrainName(trainId) .. " total train length: " .. trainLength)
        if trainTooLong then
            -- only if waiting cargo pickup is not enabled 
            if not engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] then 
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] and 
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] >= 1 then
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = true
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] + 1
                    log("asrEngine: train " .. getTrainName(trainId) .. " would be too long (raising a warning), line id: " .. lineId)
                else
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = 1
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
                    log("asrEngine: train " .. getTrainName(trainId) .. " would be too long (not raising a warning yet), line id: " .. lineId)
                end
            end
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] then
                log("asrEngine: train " .. getTrainName(trainId) .. " clearing a one-off length warning at stop index: " .. stopIndex  .. ", line id: " .. lineId)
            end            
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING_COUNT] = nil
        end

        -- check all stations for flags
        local lengthWarning = false
        local lengthWarningMessage = i18Strings.length_warning
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.LENGTH_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    lengthWarningMessage = lengthWarningMessage .. "\n" .. stationName.name
                    if stationDetails[asrEnum.station.LENGTH_WARNING_COUNT] then
                        lengthWarningMessage = lengthWarningMessage .. " (x" .. stationDetails[asrEnum.station.LENGTH_WARNING_COUNT] .. ")"
                    end
                end
                lengthWarning = true
            end
        end

        local capacityWarning = false
        local capacityWarningMessage = "More cargo than expected was waiting at:"
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.CAPACITY_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    capacityWarningMessage = capacityWarningMessage .. "\n" .. stationName.name
                    if stationDetails[asrEnum.station.CAPACITY_WARNING_COUNT] then
                        capacityWarningMessage = capacityWarningMessage .. " (x" .. stationDetails[asrEnum.station.CAPACITY_WARNING_COUNT] .. ")"
                    end
                end
                capacityWarning = true
            end
        end

        if lengthWarning then 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Warning"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = lengthWarningMessage
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Warning" then
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.all_is_well
            end
        end

        if capacityWarning then 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OverCapacity"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = capacityWarningMessage
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OverCapacity" then
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = i18Strings.all_is_well
            end
        end

        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("generateTrainConfigForASingleAmount", math.ceil((os.clock() - startTime)*1000000)/1000) end
        return trainConfig, stage
    else
        print("asrEngine: train " .. getTrainName(trainId) .. " can't identify new config for train: " .. trainId, " line: " .. lineId .. " stopIndex: " .. stopIndex)
    end
end

local function generateTrainConfig(trainId, lineId, stopIndex)

    -- generate new train configuration 
    if engineState[asrEnum.LINES] and engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.ENABLED] then

        local travelTime = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME]
        local cargoAmount = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CARGO_AMOUNT]
        local cargoAmounts = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CARGO_AMOUNTS]
        if not travelTime then 
            print("asrEngine: train " .. getTrainName(trainId) .. " no travel time")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)])
            return
        end

        if not cargoAmount and not cargoAmounts then
            print("asrEngine: train " .. getTrainName(trainId) .. " no cargo amount(s)")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1])
            return    
        end
        if cargoAmounts then 
            return generateTrainConfigForMultipleCargos(trainId, lineId, stopIndex)
        else
            return generateTrainConfigForASingleAmount(trainId, lineId, stopIndex)
        end
    end
end


local function checkIfCapacityAdjustmentNeeded(trainId, trainVehicles, stationConfig, travelTime, lineId)

    -- only run if trainId is not tracked already
    if not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] or 
       not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED]  then
        -- check if the station has the requirements defined
        if stationConfig[asrEnum.station.ENABLED] == true then
            if not stationConfig[asrEnum.station.CARGO_AMOUNT]  then
                print("asrEngine: train " .. getTrainName(trainId) .. " missing cargo amount")
                return
            end
            if not travelTime  then
                print("asrEngine: train " .. getTrainName(trainId) .. " missing travel time")
                return
            end    
            
            -- check the total capcity of all wagons 
            local currentCapacity = 0


            print("asrEngine: train " .. getTrainName(trainId) .. " checking capacities")
            local currentWagonCount = 0
            local currentEngineCount = 0
            for _, vehicle in pairs(trainVehicles) do
                if not engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)] then
                    getModelDetails(tostring(vehicle.part.modelId))
                end 
                if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] == "engine" then currentEngineCount = currentEngineCount + 1 end
                if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] == "wagon" then currentWagonCount = currentWagonCount + 1 end
            end
        
            local capacityScaleFactor = 1

            -- check if we need to adjust the capacity 
            if stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true and stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] and stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= 0 then 
                    capacityScaleFactor = capacityScaleFactor + stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]/100
                    log("asrEngine: train " .. getTrainName(trainId) .. " capacity factor: " .. capacityScaleFactor)
            end
    
            -- for _, vehicle in pairs(trainVehicles) do
            --     if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)] == nil then
            --         print("asrEngine: train " .. getTrainName(trainId) .. " no info about model: " .. vehicle.part.modelId .. " refreshing cache" )
            --         getModelDetails(vehicle.part.modelId)
            --     end
            --     currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.CAPACITY]
            -- end
            
            if stationConfig[asrEnum.station.CARGO_AMOUNTS] then
               --  specific calculations - cargo types
                local trainWagonModels = {}
                local trainWagonCompartmentsCount = {}
                local trainCompartmentsUsed = {}
                for idx, vehicle in pairs(trainVehicles) do
                    if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)] == nil then
                        print("asrEngine: train " .. getTrainName(trainId) .. " no info about model: " .. vehicle.part.modelId .. " refreshing cache" )
                        getModelDetails(vehicle.part.modelId)
                    end
                    table.insert(trainWagonModels, vehicle.part.modelId)
                    if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] ~= "engine" then 
                        trainWagonCompartmentsCount[idx] = engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT]
                        for i = 1, engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS_COUNT] do 
                            table.insert(trainCompartmentsUsed, { inUse = false, wagonIdx = idx } )
                        end
                    end        
                end
                -- make sure we have a wagon to cargo map
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP] == nil or 
                   next(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP]) == nil then
                    -- print("asrEngine: train " .. getTrainName(trainId) .. " recreating cargo map")                    
                    createCargoToWagonMap(lineId)
                end

                local adjustmentNeeded = false
                local additionsOnly = true
                for cargoId, cargoAmount in pairs(stationConfig[asrEnum.station.CARGO_AMOUNTS]) do
                    -- get wagon models for the cargo and see if the train has enough compartments
                    -- print("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " checking capacity")                    
                    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP] and 
                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)] then
                            
                        local requiredCapacity = math.ceil(capacityScaleFactor * travelTime / 720 * cargoAmount)                            
                        local currentCapacity = 0
                        local maxWagonCapacity = 0
                        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC] then
                            local validWagonModels = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.SPECIFIC]
                            for idx, compartment in pairs(trainCompartmentsUsed) do
                                if asrHelper.inTable(validWagonModels, tostring(trainWagonModels[compartment.wagonIdx])) then
                                    if not compartment.inUse then 
                                        -- print("asrEngine: train " .. getTrainName(trainId) .. " compartment id: " .. idx .. " specific model id: " .. trainWagonModels[compartment.wagonIdx])
                                        currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]

                                        if engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT] > maxWagonCapacity then 
                                            maxWagonCapacity = engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT]
                                        end
                                        trainCompartmentsUsed[idx].inUse = true
                                        trainWagonCompartmentsCount[compartment.wagonIdx] = trainWagonCompartmentsCount[compartment.wagonIdx] - 1
                                    end
                                end
                            end
                        end
                        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC] then
                            local validWagonModels = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.CARGO_WAGON_MAP][tostring(cargoId)][asrEnum.cargoWagonMap.GENERIC]
                            for idx, compartment in pairs(trainCompartmentsUsed) do
                                if asrHelper.inTable(validWagonModels, tostring(trainWagonModels[compartment.wagonIdx])) then
                                    if not compartment.inUse and currentCapacity < requiredCapacity then 
                                        -- print("asrEngine: train " .. getTrainName(trainId) .. " compartment id: " .. idx .. " generic model id: " .. trainWagonModels[compartment.wagonIdx])
                                        currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])]

                                        if engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT] > maxWagonCapacity then 
                                            maxWagonCapacity = engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.CAPACITIES][string.upper(cargoTypes[tonumber(cargoId)])] * engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[compartment.wagonIdx])][asrEnum.modelCache.COMPARTMENTS_COUNT]
                                        end
                                        trainCompartmentsUsed[idx].inUse = true
                                        trainWagonCompartmentsCount[compartment.wagonIdx] = trainWagonCompartmentsCount[compartment.wagonIdx] - 1
                                    end
                                end
                            end
                        end                        

                        if currentCapacity >= requiredCapacity and currentCapacity <  requiredCapacity + maxWagonCapacity then
                            print("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " capacity is OK")
                        else
                            print("asrEngine: train " .. getTrainName(trainId) .. " cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]) .. " capacity must be adjusted, current: " .. currentCapacity .. " required: " .. requiredCapacity .. " wagon capacity: " .. maxWagonCapacity) 
                            adjustmentNeeded = true
                        end                
                        if not (requiredCapacity > currentCapacity) then
                            additionsOnly = false 
                        end
                    else
                        print("asrEngine: train " .. getTrainName(trainId) .. " no cargo map, cargo: " .. string.upper(cargoTypes[tonumber(cargoId)]))   
                    end
                end

                -- print("asrEngine: train " .. getTrainName(trainId) .. " compartment map: ")
                -- asrHelper.tprint(trainCompartmentsUsed)

                -- if we're only adding wagons - pretend the nubmer is 0 to trigger upgrade on arrival
                -- if additionsOnly then
                --     currentWagonCount = 0
                --     print("asrEngine: train " .. getTrainName(trainId) .. " will be increasing capacity")   
                -- end

                -- if additional cargo pickup is enabled the train must be tracked
                if stationConfig[asrEnum.station.WAITING_CARGO_ENABLED] == true then 
                    return true, currentWagonCount
                end

                -- if scheduled departuers are enabled - track the train
                if stationConfig[asrEnum.station.SCHEDULER_ENABLED] == true then 
                    return true, currentWagonCount
                end

                -- if the line is set to "always track" (due to engine-only trains)
                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ALWAYS_TRACK] == true then 
                    return true, currentWagonCount
                end

                -- check if we have any unclaimed compartments
                local spareWagonCount = 0
                for idx, freeCompartmentsCount in pairs(trainWagonCompartmentsCount) do
                    if freeCompartmentsCount ==  engineState[asrEnum.MODEL_CACHE][tostring(trainWagonModels[idx])][asrEnum.modelCache.COMPARTMENTS_COUNT] then
                        adjustmentNeeded = true
                        spareWagonCount = spareWagonCount + 1
                    end
                end
                if spareWagonCount > 0 then
                    print("asrEngine: train " .. getTrainName(trainId) .. " spare wagons found: " .. spareWagonCount)
                end
                if adjustmentNeeded then
                    return true, currentWagonCount
                else 
                    return false
                end
            else
                -- generic calculations - wagons 
                local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1]
                local requiredWagonCount = math.ceil(capacityScaleFactor * travelTime / 720 * stationConfig[asrEnum.station.CARGO_AMOUNT] / engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITY])
                
                -- log("asrEngine: train " .. getTrainName(trainId) .. " current capacity  is " .. currentCapacity .. ", wagon count: " .. currentWagonCount)
                if requiredWagonCount ~= currentWagonCount then
                    -- log("asrEngine: train " .. getTrainName(trainId) .. " wagons required: " .. requiredWagonCount .. ", wagon capacity: " .. engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITY] .. " using modelId: " .. modelId .. " travelTime: " .. travelTime)
                    -- log("asrEngine: train " .. getTrainName(trainId) .. " requires a capacity correction at the next station")
                    return true, currentWagonCount
                else
                    -- log("asrEngine: train " .. getTrainName(trainId) .. " no capacity adjustment required")
                    return false
                end
            end
        else 
            -- log("asrEngine: train " .. getTrainName(trainId) .. " next stop not configured, no adjustement necessary")
            return false
        end
    end
end

local function checkTrainsCapacity(runInForeground)

    local startTime = os.clock()
    local entryCounter = 1
    -- loop through all enabled lines, check current train configs and if they need to be updated at the next station
    if engineState[asrEnum.LINES] then 
    for lineId, line in pairs(engineState[asrEnum.LINES]) do
            if line[asrEnum.line.ENABLED] == true then
                -- log ("asrEngine: checking line " .. lineId )
                for _, trainId in pairs(api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))) do
                    -- log("asrEngine: checking trainId: " .. trainId)
                    if api.engine.entityExists(tonumber(trainId)) then 
                        local trainInfo = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
                        if trainInfo then
                            if not engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] then engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = -1 end
                            -- log("asrEngine: line " .. lineId .. " train: " .. getTrainName(trainId) .. " heading to stopIndex: " .. trainInfo.stopIndex .. " last checked:"  .. engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] )
                            if line[asrEnum.line.STATIONS][trainInfo.stopIndex + 1]  -- and  trainInfo.state ~= api.type.enum.TransportVehicleState.AT_TERMINAL 
                                and engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] ~= trainInfo.stopIndex  then -- ignore if train is already stopped at a station or has been checked already
                                -- at the next station train might require configuration adjustment, check if current config is sufficient
                                -- log("asrEngine: will check again")
                                local checkResult, currentWagonCount = checkIfCapacityAdjustmentNeeded(trainId, trainInfo.transportVehicleConfig.vehicles, line[asrEnum.line.STATIONS][trainInfo.stopIndex + 1], line[asrEnum.line.TRAVEL_TIME], lineId)
                                if not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then 
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = {} 
                                    log("asrEngine: train " .. getTrainName(trainId) .. " initialising tracking")
                                end
                                if checkResult == true then
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.WAGON_COUNT] = currentWagonCount
                                    engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = trainInfo.stopIndex

                                    -- figure out time when to start tracking the train
                                    if not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] and 
                                       not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] then 

                                        if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] then
                                            log("asrEngine: train " .. getTrainName(trainId) .. " missed replacement at the previous stop")    
                                        end
                                        local stopNumber = trainInfo.stopIndex + 1 -- off by one due to Lua conversions

                                        local previousStopNumber = stopNumber - 1
                                        if previousStopNumber <= 0  then
                                            previousStopNumber = #trainInfo.sectionTimes
                                        end

                                        local previousStopDepartureTime = trainInfo.lineStopDepartures[previousStopNumber]/1000
                                        local thisSectionTime = trainInfo.sectionTimes[previousStopNumber]
                                        local trackingDelaySetting 
                                        if engineState[asrEnum.SETTINGS][asrEnum.settings.TRACKING_DELAY] then 
                                            trackingDelaySetting = engineState[asrEnum.SETTINGS][asrEnum.settings.TRACKING_DELAY]/100
                                        else 
                                            trackingDelaySetting = 0.50
                                        end
                                        local trackingDelay = thisSectionTime * trackingDelaySetting - (getGameTime() - previousStopDepartureTime)
                                        if trackingDelay < 0 then trackingDelay = 0 end
                                        
                                        log("asrEngine: train " .. getTrainName(trainId) .. " will start to track in " .. trackingDelay .. "s")
                                        if previousStopDepartureTime + trackingDelay < getGameTime() then 
                                            log("asrEngine: train " .. getTrainName(trainId) .. " starting to track now")
                                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] = true
                                        elseif (getGameTime() - previousStopDepartureTime) > thisSectionTime * trackingDelaySetting then
                                            log("asrEngine: train " .. getTrainName(trainId) .. " starting to track now - timers are off")
                                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] = true
                                        else
                                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] = previousStopDepartureTime + trackingDelay
                                        end
                                    end
                                elseif checkResult == false then
                                    engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = trainInfo.stopIndex
                                    log("asrEngine: train " .. getTrainName(trainId) .. " no need to track")
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] = false
                                end
                            end

                            -- check if the train should start tracking now
                            if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] and 
                                not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] and 
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] and 
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] < getGameTime() then
                                log("asrEngine: train " .. getTrainName(trainId) .. " starting to track (after a delay)")
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_ENABLED] = true
                                -- engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] = nil
                            end

                            -- check if the train is stopped but shouldn't be, that starts all stopped trains that are not supposed to be stopped
                            -- local restartTrain = false
                            if trainInfo.userStopped == true then                                        -- trainInfo.state == api.type.enum.TransportVehicleState.AT_TERMINAL and
                                if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then
                                    if not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DELAY_DEPARTURE] then
                                        log("asrEngine: train " .. getTrainName(trainId) .. " is stopped - NO departure set, restarting")
                                        local startCmd = api.cmd.make.setUserStopped(tonumber(trainId), false)
                                            api.cmd.sendCommand(startCmd, function ()
                                            log ("asrEngine: train " .. getTrainName(trainId) .. " has been restarted" )
                                        end)
                                    end
                                end
                            end
                        else
                            print("asrEngine: train " .. getTrainName(trainId) .. " couldn't get info from the API (" .. trainId .. ")")
                            -- flags.paused = true
                            break
                        end
                    end
                    if not runInForeground and (os.clock() - startTime)*1000 >= 25 then
                        -- log("asrEngine: checkTrainsCapacity running for more than 25ms - yielding - 1")
                        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("checkTrainsCapacity", math.ceil((os.clock() - startTime)*1000000)/1000) end
                        coroutine.yield()
                        startTime = os.clock()
                        entryCounter = entryCounter + 1
                        -- log("asrEngine: checkTrainsCapacity resuming")
                    end                
                end
            end
        end
    end
    if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("checkTrainsCapacity", math.ceil((os.clock() - startTime)*1000000)/1000) end
end

local function checkTrainsPositions()

    local startTime = os.clock()
    for trainId, trainPrevInfo in pairs (engineState[asrEnum.TRACKED_TRAINS]) do

        if api.engine.entityExists(tonumber(trainId)) then 

            -- check if the train is still tracked
            if trainPrevInfo[asrEnum.trackedTrain.TRACKING_ENABLED] then 
                local trainCurrentInfo = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
                -- train is arriving
                if trainCurrentInfo and trainCurrentInfo.timeUntilLoad > 0 then
                    -- log("asrEngine: train " .. trainId .. " is appraching a station (" .. trainCurrentInfo.timeUntilLoad .. ") " .. " index: " .. trainCurrentInfo.stopIndex )
                    if not trainPrevInfo[asrEnum.trackedTrain.IN_STATION] and not trainPrevInfo[asrEnum.trackedTrain.GENERATED_CONFIG] then -- prepare new config as train pulls into the station

                        log("asrEngine: train " .. getTrainName(trainId) .. " is arriving, time to load: " .. trainCurrentInfo.timeUntilLoad .. ", (trainId: " ..  trainId .. ")")

                        log("asrEngine: train " .. getTrainName(trainId) .. " lineId: " .. trainCurrentInfo.line)

                        local lineName = api.engine.getComponent(trainCurrentInfo.line, api.type.ComponentType.NAME)
                        if lineName and lineName.name then 
                            log("asrEngine: train " .. getTrainName(trainId) .. " line name: " .. lineName.name)
                        end
                        local stationConfig = engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1] 
                
                        local stationName = api.engine.getComponent(stationConfig[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                        if stationName and stationName.name then
                            log("asrEngine: train " .. getTrainName(trainId) .. " station name: " .. stationName.name)
                        end
                
                        if trainPrevInfo[asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] then
                            log("asrEngine: train " .. getTrainName(trainId) .. " took " .. (getGameTime() - trainPrevInfo[asrEnum.trackedTrain.TRACKING_START_TIMESTAMP]) .. "s since tracking" )
                        end
                        if trainPrevInfo[asrEnum.trackedTrain.WAGON_COUNT] and trainPrevInfo[asrEnum.trackedTrain.WAGON_COUNT] > 0 then
                            -- do not generate the config just yet, we'll do it after unloading
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IN_STATION] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] = getGameTime()
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex    
                        else
                            log("asrEngine: train " .. getTrainName(trainId) .. " preparing vehicle replacement (arrival at " .. trainCurrentInfo.timeUntilLoad .. ", trainId: " ..  trainId .. ")")
                            local replacementConfig, stage = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)

                            trainConfigCache[tostring(trainId)] = replacementConfig
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.GENERATED_CONFIG] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] = stage
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IN_STATION] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] = getGameTime()
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex

                            if stage == "arrival" then
                                local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), replacementConfig)
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                                api.cmd.sendCommand(replaceCmd, function () 
                                    log ("asrEngine: train " .. getTrainName(trainId) .. " replace sent on arrival, currently at stop " .. trainCurrentInfo.stopIndex)
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] = true    
                                end)
                            end    
                        end

                    -- check if scheduler is enabled for this station
                    if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)] and 
                    engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS] and
                    engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1] and 
                    engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.SCHEDULER_ENABLED] and 
                    engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAIN_LIST] and #engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAIN_LIST] > 1 then 
                        if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] then
                            if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAIN_LIST] and engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME] then 
                                -- local stationDwellTime = 10
                                -- if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.STOP_DURATION] then 
                                --     stationDwellTime = math.min(table.unpack(engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.STOP_DURATION]))
                                -- end
                                local timeBetweenTrains = engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME]
                                local waitTime = engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] - getGameTime() + timeBetweenTrains
                                local scheduledDepartureTime =  engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] + timeBetweenTrains
                                log ("asrEngine: train " .. getTrainName(trainId) .. " frequency: " .. timeBetweenTrains .. "s")
                                log ("asrEngine: train " .. getTrainName(trainId) .. " last train was here: " .. getGameTime() - engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] .. 
                                        "s ago, we'll wait for: " .. waitTime) 
                                if scheduledDepartureTime <= getGameTime() then
                                    -- we're already too late, don't wait
                                    log ("asrEngine: train " .. getTrainName(trainId) .. " is already late, won't wait") 
                                else
                                    -- set the waiting flag
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DELAY_DEPARTURE] = true
                                    log ("asrEngine: train " .. getTrainName(trainId) .. " will wait here") 
                                end
                            else 
                                log ("asrEngine: train " .. getTrainName(trainId) .. " either no time or no count, can't schedule departure") 
                            end
                        else 
                            log ("asrEngine: train " .. getTrainName(trainId) .. " no unload timestamp") 
                        end
                    end
                end
            end

                -- train is unloading
                if trainCurrentInfo and trainCurrentInfo.timeUntilLoad ~= trainPrevInfo[asrEnum.trackedTrain.TIME_UNTIL_LOAD] and trainPrevInfo[asrEnum.trackedTrain.IN_STATION] then
                    -- log("asrEngine: train " .. trainId .. " timeUntilLoad: " .. trainCurrentInfo.timeUntilLoad )
                    if trainCurrentInfo.timeUntilLoad <= 0.25 then

                        if trainPrevInfo[asrEnum.trackedTrain.DELAY_DEPARTURE] and 
                            engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] and 
                            engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME] then
                            -- calculate the departure time
                            local departureTime = engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] + engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME]
                            if departureTime > getGameTime() and not trainPrevInfo[asrEnum.trackedTrain.IS_STOPPED] then
                                local stopCmd = api.cmd.make.setUserStopped(tonumber(trainId), true)
                                api.cmd.sendCommand(stopCmd, function ()
                                    log ("asrEngine: train " .. getTrainName(trainId) .. " is waiting  at index " .. trainCurrentInfo.stopIndex .. " (until load: " ..  trainCurrentInfo.timeUntilLoad)
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IS_STOPPED] = true
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.WAIT_START_TIMESTAMP] = getGameTime()
                                end)
                            end
                        end
            
                        if trainPrevInfo[asrEnum.trackedTrain.IN_STATION] and not trainPrevInfo[asrEnum.trackedTrain.REPLACED] and not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IS_STOPPED] then
                            if not trainPrevInfo[asrEnum.trackedTrain.GENERATED_CONFIG] then
                                log("asrEngine: train " .. getTrainName(trainId) .. " preparing vehicle replacement (unload at " .. trainCurrentInfo.timeUntilLoad .. ", trainId: " ..  trainId .. ")")
                                local replacementConfig, stage = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.GENERATED_CONFIG] = true
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] = stage
                                trainConfigCache[tostring(trainId)] = replacementConfig
                            end

                            if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "unload" or 
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "arrival" then -- the generation might be late
                                if not trainConfigCache[tostring(trainId)] then 
                                    log("asrEngine: train " .. getTrainName(trainId) .. " regenerating train config (unload at " .. trainCurrentInfo.timeUntilLoad .. ", trainId: " ..  trainId .. ")")
                                    trainConfigCache[tostring(trainId)] = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)
                                end
                                local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), trainConfigCache[tostring(trainId)])
                                api.cmd.sendCommand(replaceCmd, function () 
                                    log ("asrEngine: train " .. getTrainName(trainId) .. " replace sent on unload, currently at stop " .. trainCurrentInfo.stopIndex)
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] = true    
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                                end)
                            end
                        end

                        if not trainPrevInfo[asrEnum.trackedTrain.DELAY_DEPARTURE] and not trainPrevInfo[asrEnum.trackedTrain.UNLOAD_TIMESTAMP_RECORDED] then
                            engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] = getGameTime()
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.UNLOAD_TIMESTAMP_RECORDED] = true 
                            log ("asrEngine: train " .. getTrainName(trainId) .. " storing unload timestamp for index: " .. trainCurrentInfo.stopIndex)
                        end                            
                    end
                end


                -- check if the stopped train should be started again
                if trainCurrentInfo and trainPrevInfo[asrEnum.trackedTrain.IS_STOPPED] then
                    -- calculate departure time again, just in case
                    local departureTime
                    if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] and 
                        engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME] then 
                            departureTime = engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] + engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME] 
                    else
                        -- something went wrong - just start the train
                        departureTime = getGameTime() 
                    end

                    -- check if the train hasn't been here for more than 2 full round trips - it might be getting stuck due to other trains resetting station arrival times
                    if getGameTime() - trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] > 2 * engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME] then 
                        log("asrEngine: train " .. getTrainName(trainId) .. " seems to be stuck at a station, starting, travel time: " .. engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.TRAVEL_TIME])
                        departureTime = getGameTime()
                    end
                    if departureTime - 0.5 <= getGameTime()  then      
                        if not trainPrevInfo[asrEnum.trackedTrain.GENERATED_CONFIG] or not trainConfigCache[tostring(trainId)] then
                            log("asrEngine: train " .. getTrainName(trainId) .. " preparing vehicle replacement (restart at " .. trainCurrentInfo.timeUntilLoad .. ", trainId: " ..  trainId .. ")")
                            local replacementConfig, stage = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.GENERATED_CONFIG] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] = stage
                            trainConfigCache[tostring(trainId)] = replacementConfig
                        end

                        if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "unload" or 
                           engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "arrival" then 
                            local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), trainConfigCache[tostring(trainId)])
                            api.cmd.sendCommand(replaceCmd, function () 
                                log ("asrEngine: train " .. getTrainName(trainId) .. " replace sent on restart/unload, currently at stop " .. trainCurrentInfo.stopIndex)
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] = true    
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                            end)
                        end

                        -- make.setVehicleManualDeparture(entity, manual)
                        local startCmd = api.cmd.make.setUserStopped(tonumber(trainId), false)
                        api.cmd.sendCommand(startCmd, function ()
                            log ("asrEngine: train " .. getTrainName(trainId) .. " is restarting at " .. trainCurrentInfo.timeUntilLoad ..  "current time: " .. getGameTime())
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IS_STOPPED] = false
                            trainPrevInfo[asrEnum.trackedTrain.DELAY_DEPARTURE] = nil
                               engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainCurrentInfo.stopIndex + 1][asrEnum.station.UNLOAD_TIMESTAMP] = getGameTime()                    

                            if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.WAIT_START_TIMESTAMP] then
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.WAIT_DURATION] = getGameTime() - engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.WAIT_START_TIMESTAMP]
                            end
                        end)
                    end
                end

                -- train is leaving
                if trainCurrentInfo and trainCurrentInfo.state == api.type.enum.TransportVehicleState.EN_ROUTE and trainPrevInfo[asrEnum.trackedTrain.STATE] == api.type.enum.TransportVehicleState.AT_TERMINAL then
                    log("asrEngine: train " .. getTrainName(trainId) .. " is leaving the station " .. " heading to index: " .. trainCurrentInfo.stopIndex )
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] = getGameTime()
                    -- log("asrEngine: train " .. getTrainName(trainId) .. " departure timestamp: " .. getGameTime())

                    if trainPrevInfo[asrEnum.trackedTrain.REPLACE_ON] == "departure" and not trainPrevInfo[asrEnum.trackedTrain.REPLACED]  then 
                        if not trainConfigCache[tostring(trainId)] then
                            -- config might got lost during save/restore
                            trainConfigCache[tostring(trainId)] = generateTrainConfig(trainId, trainCurrentInfo.line, trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1)
                        end
                        if trainConfigCache[tostring(trainId)] then 
                            local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), trainConfigCache[tostring(trainId)])
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                            api.cmd.sendCommand(replaceCmd, function () 
                                log ("asrEngine: train " .. getTrainName(trainId) .. " replace sent on departure, heading to stop " .. trainCurrentInfo.stopIndex)
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] = true    
                                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                            end)
                        end
                    end

                    if trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] then 

                        local stopDuration
                        local waitDuration = 0
                        if trainPrevInfo[asrEnum.trackedTrain.WAIT_DURATION] then 
                            stopDuration = getGameTime() - trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] - trainPrevInfo[asrEnum.trackedTrain.WAIT_DURATION]
                            waitDuration = trainPrevInfo[asrEnum.trackedTrain.WAIT_DURATION]
                        else
                            stopDuration = getGameTime() - trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP]
                        end
                        log("asrEngine: train " .. getTrainName(trainId) .. " spent " .. stopDuration .. " s (plus waiting for: " .. waitDuration .. "s)")

                        if trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] then 
                            if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1] then 
                                if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1][asrEnum.station.STOP_DURATION] == nil then 
                                    engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1][asrEnum.station.STOP_DURATION] = {}
                                end
                            end
                            if stopDuration > 0 then 
                                table.insert(engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1][asrEnum.station.STOP_DURATION], stopDuration)
                                if #engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1][asrEnum.station.STOP_DURATION] > 5 then 
                                    table.remove(engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.STATIONS][trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1][asrEnum.station.STOP_DURATION], 1) 
                                end
                            end
                        else
                            log("asrEngine: train " .. getTrainName(trainId) .. " no previous stop info")
                        end
                    end
                    if trainPrevInfo[asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] then
                        log("asrEngine: train " .. getTrainName(trainId) .. " is no longer tracked")
                        -- asrHelper.tprint(engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)])
                        local trackedTrainDetails = {
                            [asrEnum.trackedTrain.TRACKING_ENABLED] = false,
                            [asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] = trainPrevInfo[asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] and trainPrevInfo[asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] or  getGameTime(),
                            [asrEnum.trackedTrain.WAGON_COUNT] = trainPrevInfo[asrEnum.trackedTrain.WAGON_COUNT] and trainPrevInfo[asrEnum.trackedTrain.WAGON_COUNT] or nil,
                            [asrEnum.trackedTrain.TRAIN_LENGTH] = trainPrevInfo[asrEnum.trackedTrain.TRAIN_LENGTH] and trainPrevInfo[asrEnum.trackedTrain.TRAIN_LENGTH] or nil,
                        }
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = trackedTrainDetails
                    --    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil 
                    end
                end

                -- check if the line is still enabled and store the current state
                if trainCurrentInfo then 
                    if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)] and 
                        engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.ENABLED] then 
                        if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then 
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STATE] = trainCurrentInfo.state
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TIME_UNTIL_LOAD] = trainCurrentInfo.timeUntilLoad
                        end
                    else
                        -- line not enabled any more - stop tracking
                        log("asrEngine: train " .. getTrainName(trainId) .. " is no longer tracked (line disabled)")
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil 
                    end
                end
                -- if the train is en route and in station - something went wrong - report this and correct it
                if trainCurrentInfo and trainCurrentInfo.state == api.type.enum.TransportVehicleState.EN_ROUTE and 
                    trainPrevInfo[asrEnum.trackedTrain.IN_STATION] and not trainPrevInfo[asrEnum.trackedTrain.STOP_TRACKING_ON_EXIT] and engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then
                    log("asrEngine: train " .. getTrainName(trainId) .. " tracking state error, correcting")
                    if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TRACKING_START_TIMESTAMP] then
                        log("asrEngine: train " .. getTrainName(trainId) .. " most likely missed replacement at the previous enabled stop")    
                    end
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = 
                    {
                        [asrEnum.trackedTrain.TRACKING_ENABLED] = false,
                        [asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] = trainPrevInfo[asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] and trainPrevInfo[asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] or  getGameTime(),
                        [asrEnum.trackedTrain.TRAIN_LENGTH] = trainPrevInfo[asrEnum.trackedTrain.TRAIN_LENGTH] and trainPrevInfo[asrEnum.trackedTrain.TRAIN_LENGTH] or nil,
                        [asrEnum.trackedTrain.TIME_UNTIL_LOAD] = trainPrevInfo[asrEnum.trackedTrain.TIME_UNTIL_LOAD],
                        [asrEnum.trackedTrain.STATE] = trainPrevInfo[asrEnum.trackedTrain.STATE],
                        [asrEnum.trackedTrain.WAGON_COUNT] = trainPrevInfo[asrEnum.trackedTrain.WAGON_COUNT],
                    }
                end
            end
        else
            -- the train most likely got sold, stop tracking
            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil
        end
    end
    if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then  storeTimings("checkTrainsPositions", math.ceil((os.clock() - startTime)*1000000)/1000) end
end

local function updateLineStations(lineId)

    log("asrEngine: updateLineStations: " .. lineId)
    local stopsIds = {}
    if api.engine.entityExists(tonumber(lineId)) then
        local lineDetails = api.engine.getComponent(tonumber(lineId), api.type.ComponentType.LINE)
        -- log("asrEngine: getLineStations getComponent")
        if lineDetails ~= nil then
            for stopOrder, stop in pairs(lineDetails.stops) do
                local stationGroupId = stop.stationGroup
                local stationGroupDetails = api.engine.getComponent(tonumber(stationGroupId), api.type.ComponentType.STATION_GROUP)

                table.insert(stopsIds, stopOrder)
                -- log("asrEngine: getLineStation2 getComponent")
                if stationGroupDetails ~= nil then
                    for _, stationId in pairs(stationGroupDetails.stations) do
                        -- log("lineId: " .. lineId .. " stationGroup: " .. stationGroupId .. " station: " .. stationId .. "order: " .. stopOrder)
                        if engineState[asrEnum.LINES][tostring(lineId)] == nil then 
                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = false
                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] = {}
                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] = {}
                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] = {}
                        end

                        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] == nil then engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] = {} end

                        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopOrder] == nil or engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopOrder][asrEnum.station.STATION_ID] ~= stationId then
                                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopOrder] = {
                                    [asrEnum.station.STATION_ID] =  stationId,
                                    [asrEnum.station.STATION_GROUP_ID] = stationGroupId,
                                    [asrEnum.station.ENABLED] = false
                                }
                        end
                    end
                end
            end
        end
    end

    -- loop through all lines stops and make sure they were not removed from the game
    local stopsChanged = false
    if engineState[asrEnum.LINES] then
        for stopId in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if not asrHelper.inTable(stopsIds, stopId) then
                log("asrEngine: updateLineStations: line " .. lineId .. " has extra stop " .. stopId .. " removing")
                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopId] = nil
                    stopsChanged = true
            end
        end
    end
    if stopsChanged then
        increseObjectVersion(asrEnum.status.LINE_SETTINGS_VERSION)
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

local function updateLineIndustriesAndTowns(lineId)
    
    log("asrEngine: updateLineIndustriesAndTowns: " .. lineId)
    local seenStationIds = {}
    local seenEntityIds = {}
    local buildingToTown = {}
    -- build cache of building to town map
    local townToBuildingMap = api.engine.system.townBuildingSystem.getTown2BuildingMap()
    if townToBuildingMap then 
        
        -- invert the map
        for townId, townBuildings in pairs(townToBuildingMap) do
            for _, townBuilding in pairs(townBuildings) do
                buildingToTown[tostring(townBuilding)] = townId
            end
        end

        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] ~= nil then 
            for _, station in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                if seenStationIds[tostring(station[asrEnum.station.STATION_ID])] == nil then 
                    local foundTown = false
                    local stationEdges = api.engine.system.catchmentAreaSystem.getStation2edgesMap()[tonumber(station[asrEnum.station.STATION_ID])]
                    for _, entity in pairs(stationEdges) do
                        if api.engine.entityExists(tonumber(entity.entity)) and seenEntityIds[tostring(entity.entity)] == nil then

                            local componentDetails = api.engine.getComponent(entity.entity, api.type.ComponentType.NAME) 
                            local constructionDetails = api.engine.getComponent(entity.entity, api.type.ComponentType.CONSTRUCTION)
                            
                            if not foundTown then
                                local edgeDetails = api.engine.getComponent(entity.entity, api.type.ComponentType.BASE_EDGE)
                                if edgeDetails ~= nil then
                                    local parcels = api.engine.system.parcelSystem.getSegment2ParcelData()[entity.entity]
                                    if parcels and parcels.leftEntities then
                                        for _, parcelId in pairs(parcels.leftEntities) do
                                            local buildingId = api.engine.system.townBuildingSystem.getParcel2BuildingMap()[parcelId]
                                            if buildingId then 
                                                local townId = buildingToTown[tostring(buildingId)]
                                                if townId then
                                                    foundTown = true
                                                    local townName = api.engine.getComponent(tonumber(townId), api.type.ComponentType.NAME)
                                                    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] == nil then engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] = {} end                    
                                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES][tostring(townId)] = { 
                                                        [asrEnum.lineIndustry.NAME] = townName.name,
                                                        [asrEnum.lineIndustry.STATION_ID] = station[asrEnum.station.STATION_ID],
                                                        [asrEnum.lineIndustry.TYPE] = "town"
                                                    }                                                    
                                                end
                                            end
                                        end
                                        if not foundTown and parcels.rightEntities then
                                            -- try the right entities
                                            for _, parcelId in pairs(parcels.rightEntities) do
                                                local buildingId = api.engine.system.townBuildingSystem.getParcel2BuildingMap()[parcelId]
                                                if buildingId then 
                                                    local townId = buildingToTown[tostring(buildingId)]
                                                    if townId then
                                                        foundTown = true
                                                        local townName = api.engine.getComponent(tonumber(townId), api.type.ComponentType.NAME)
                                                        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] == nil then engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] = {} end                    
                                                            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES][tostring(townId)] = { 
                                                            [asrEnum.lineIndustry.NAME] = townName.name,
                                                            [asrEnum.lineIndustry.STATION_ID] = station[asrEnum.station.STATION_ID],
                                                            [asrEnum.lineIndustry.TYPE] = "town"
                                                        }                                                    
                                                    end
                                                end
                                            end    
                                        end
                                    end
                                end
                            end
                            if constructionDetails ~= nil and string.find(constructionDetails.fileName,"industry", 1, true) and componentDetails ~= nil then 
                                if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] == nil then engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] = {} end
                                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES][tostring(entity.entity)] = { 
                                    [asrEnum.lineIndustry.NAME] = componentDetails.name,
                                    [asrEnum.lineIndustry.STATION_ID] = station[asrEnum.station.STATION_ID],
                                    [asrEnum.lineIndustry.TYPE] = "industry"
                                }
                            end
                            seenEntityIds[tostring(entity.entity)] = true
                        -- else
                        --     log("asrEngine: broken entity: " .. entity.entity)
                        end
                    end
                    seenStationIds[tostring(station.stationId)] = true
                else
                    -- log("stationId: " .. stop.stationId .. " seen already")
                end
            end
        end
    else
        print("asrEngine: can't get town to building map")
    end
    -- check for any industries that disappeared
    for industryId, industryDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES]) do
        if not seenEntityIds[tostring(industryId)] and industryDetails[asrEnum.lineIndustry.TYPE] == "industry" then 
            log("asrEngine: industry id: " .. industryId .. " not found any more, removing")
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.INDUSTRIES][tostring(industryId)] = nil
        end
    end
end


local function getLineTrainSummary(lineId)

    log("asrEngine: getLineTrainSummary for line: " .. lineId)
    local trainSummary = { 
        trainCount = 0,
        engines = {},
        wagons = {},
        -- trainList = {},
    }
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))
    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAIN_LIST] = {}
    for _, trainId in  pairs(lineVehicles) do
        table.insert(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAIN_LIST], trainId)
        local models = getTrainModels(trainId)
        if models ~= nil then
            -- asrHelper.tprint(models)
            if models.engines ~= nil then 
                -- trainSummary.trainCount = trainSummary.trainCount + 1
                for _, modelId in pairs(models.engines) do 
                    -- log("asrEngine: getLineTrainSummary: found asrEngine: " .. modelId)
                    if trainSummary.engines[tostring(modelId)] == nil then
                        trainSummary.engines[tostring(modelId)] = 1
                    else 
                        trainSummary.engines[tostring(modelId)] = trainSummary.engines[tostring(modelId)] + 1
                    end
                end
            end
            if models.wagons ~= nil then
                for _, modelId in pairs(models.wagons) do 
                    -- log("asrEngine: getLineTrainSummary: found wagon: " .. modelId)
                    if trainSummary.wagons[tostring(modelId)] == nil then
                        trainSummary.wagons[tostring(modelId)] = 1
                    else 
                        trainSummary.wagons[tostring(modelId)] = trainSummary.wagons[tostring(modelId)] + 1
                    end

                end
            else 
                -- log("asrEngine: getLineTrainSummary: no wagons?")
            end
        end
    end

    return trainSummary
end

local function updateLineTrainsInfo(lineId) 

    log("asrEngine: updateTrainsInfo lineId: " .. lineId)

    local validityStatusChange = false
    local lineVehicles = getLineTrainSummary(lineId)
    -- asrHelper.tprint(lineVehicles)
    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] == nil then 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] = { 
            [asrEnum.vehicle.WAGONS] = {},
            [asrEnum.vehicle.ENGINES] = {}
        }
    end 
    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES] == nil then 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES] = {}
    end
    for engineId, _ in pairs(lineVehicles.engines) do
        if not asrHelper.inTable(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES], engineId) then 
            table.insert(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES], engineId)
        end
    end
    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] == nil then 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] = {}
    end
    for wagonId, _ in pairs(lineVehicles.wagons) do
        if not asrHelper.inTable(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS], wagonId) then 
            table.insert(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS], wagonId)
        end
    end
    
    -- engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()

    -- log("asrEngine: line state")
    -- asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)])
    if #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES] == 0 and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] ~= "Invalid" then
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Invalid"
        validityStatusChange = true
    end
    if #engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.ENGINES] ~= 0 and ( engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == nil or engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Invalid") then
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Misconfigured"
        validityStatusChange = true
    end 

    if validityStatusChange then
        increseObjectVersion(asrEnum.status.LINES_VERSION)
        -- engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] + 1
    end
    createCargoToWagonMap(lineId)
    engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
end

local function updateTrainsInfo()
    local validityStatusChange = false
    if engineState[asrEnum.LINES] then 
        for lineId, _ in pairs(engineState[asrEnum.LINES]) do
            updateLineTrainsInfo(lineId)
        end
    end
end


local function gatherLineInfo(lineId)

    log("asrEngine: gatherLineInfo: " .. lineId)

    if engineState[asrEnum.LINES][tostring(lineId)] == nil then
        engineState[asrEnum.LINES][tostring(lineId)] = {
            [asrEnum.line.ENABLED] = false,
            [asrEnum.line.STATIONS] = {},
            [asrEnum.line.INDUSTRIES] = {},
        }
    end
    -- update the name, just in case
    if api.engine.entityExists(tonumber(lineId)) then
        local lineName = api.engine.getComponent(tonumber(lineId), api.type.ComponentType.NAME)
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] == nil or engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] ~= lineName.name then
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME] = lineName.name
        end
    end

    updateLineStations(lineId)
    updateLineIndustriesAndTowns(lineId)
    getLineTrainSummary(lineId)
    updateLineTrainsInfo(lineId)

    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()    
end

local function refreshLineVehiclesInfo(params)
 
    if params.lineId then
        engineState[asrEnum.LINES][tostring(params.lineId)][asrEnum.line.VEHICLES] = nil
        updateLineTrainsInfo(params.lineId)
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

local function setLineSettings(params)

    if params and params.property and params.lineId then 
        if not engineState[asrEnum.LINES][tostring(params.lineId)][asrEnum.line.SETTINGS] then engineState[asrEnum.LINES][tostring(params.lineId)][asrEnum.line.SETTINGS] = {} end
        engineState[asrEnum.LINES][tostring(params.lineId)][asrEnum.line.SETTINGS][params.property] = params.value
    end
end

local function setGlobalSettings(params)
    if params and params.property then 
        engineState[asrEnum.SETTINGS][params.property] = params.value
    end
end


local function updateShippingContract(params) 

    log("asrEngine: updateShippingContract:")
    -- asrHelper.tprint(params)
    if params and params.shippingContractId and params.property then 
        local newContract = false
        if not engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)] then 
            engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)] = {} 
            newContract = true
        end 
        if engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][params.property] and engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][params.property] ~= params.value and 
            params.property ~= asrEnum.shippingContract.NAME  then
            engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT] = 0
        end

        if params.property == asrEnum.shippingContract.NAME then
            engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.MANUAL_NAME] = true
        end

        engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][params.property] = params.value

        if not engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.MANUAL_NAME] or 
        string.find(engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.NAME] , "Shipping contract #") then
            local newName = generateShippingContractName(params.shippingContractId)
            if newName then 
                engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.NAME] =  newName
            end
            engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)][asrEnum.shippingContract.MANUAL_NAME] = nil
        end

        checkMemberInUseCounter(params.shippingContractId, "shippingContract")
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
        if newContract then
            increseObjectVersion(asrEnum.status.SHIPPING_CONTRACTS_VERSION)
        end
    end
end

local function deleteShippingContract(params)
    if params and params.shippingContractId then 
        engineState[asrEnum.SHIPPING_CONTRACTS][tostring(params.shippingContractId)] = nil
        increseObjectVersion(asrEnum.status.SHIPPING_CONTRACTS_VERSION)
    end
end

local function updateCargoGroup(params) 

    if params and params.cargoGroupId and params.property then 
        local newGroup = false
        if not engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] then 
            engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] = {} 
            newGroup = true
        end 

        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][params.property] = params.value
        -- engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] = 0
        if params.property == asrEnum.cargoGroup.NAME then
            engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] = true
        end

        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
        if newGroup then
            increseObjectVersion(asrEnum.status.CARGO_GROUPS_VERSION)
        end
    end
end

local function deleteCargoGroup(params)
    if params and params.cargoGroupId then 
        if engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] then 
            for _, memberDetails in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
                    decreaseMemberInUseCounter(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID], memberDetails[asrEnum.cargoGroupMember.TYPE])
                end
                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                    decreaseMemberInUseCounter(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID], memberDetails[asrEnum.cargoGroupMember.TYPE])
                end
            end
        end
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] = nil
        increseObjectVersion(asrEnum.status.CARGO_GROUPS_VERSION)
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

local function addCargoGroupMember(params)

    if params and params.cargoGroupId and params.values then
        if engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] == nil then
            engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] = {}
        end
        table.insert(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS], params.values)
        if params.values[asrEnum.cargoGroupMember.TYPE] and params.values[asrEnum.cargoGroupMember.TYPE] == "shippingContract"  then
            increaseMemberInUseCounter(params.values[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID], params.values[asrEnum.cargoGroupMember.TYPE])
            checkMemberInUseCounter(params.values[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID], params.values[asrEnum.cargoGroupMember.TYPE])
        end
        if params.values[asrEnum.cargoGroupMember.TYPE] and params.values[asrEnum.cargoGroupMember.TYPE] == "cargoGroup"  then
            increaseMemberInUseCounter(params.values[asrEnum.cargoGroupMember.CARGO_GROUP_ID], params.values[asrEnum.cargoGroupMember.TYPE])
            checkMemberInUseCounter(params.values[asrEnum.cargoGroupMember.CARGO_GROUP_ID], params.values[asrEnum.cargoGroupMember.TYPE])
        end
        if not engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] or 
            string.find(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] , "Cargo group #") then
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] =  generateCargoGroupName(params.cargoGroupId)
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] = nil
        end
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.VALID] = false
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.VALIDITY_CHECKED] = false
        increseObjectVersion(asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION)

        checkMemberInUseCounter(params.cargoGroupId, "cargoGroup")
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

local function deleteCargoGroupMember(params)

    if params and params.cargoGroupId and params.memberId then
        if engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] and 
           engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] and 
           engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId] then
            local memberType = engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId][asrEnum.cargoGroupMember.TYPE]
            if memberType == "shippingContract" then
                decreaseMemberInUseCounter(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId][asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID], memberType)
            end
            if memberType == "cargoGroup" then
                decreaseMemberInUseCounter(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId][asrEnum.cargoGroupMember.CARGO_GROUP_ID], memberType)
            end
            engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId] = nil
        end
        if not engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] or 
            string.find(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] , "Cargo group #") then
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] =  generateCargoGroupName(params.cargoGroupId)
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] = nil
        end
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.VALIDITY_CHECKED] = false
        increseObjectVersion(asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION)
        checkMemberInUseCounter(params.cargoGroupId, "cargoGroup")
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

function asrEngine.handleEvent(id, params) 
    log("asrEngine: comamnd received: " .. id)
    if id == "asrLineState" then
        if params[asrEnum.line.LINE_ID] then
            if params[asrEnum.line.ENABLED] == true then
                enableLine(params[asrEnum.line.LINE_ID])
            elseif params[asrEnum.line.ENABLED] == false then
                disableLine(params[asrEnum.line.LINE_ID])
            else
                log("unknown state " .. params.state .. " requested for line " .. params[asrEnum.line.LINE_ID])
            end
        else 
            log("asrEngine: command - no lineId")
        end
    elseif id == "asrInitLine" then
        flags.initLine = params.lineId
    elseif id == "asrForceLineCheck" then
        log("asrEngine: force line check")
        flags.refreshLines = true
    elseif id == "asrStopRefresh" then
        log("asrEngine: refresh disabled")
        flags.refreshEnabled = false
    elseif id == "asrStartRefresh" then
        log("asrEngine: refresh enabled")
        flags.refreshEnabled = true
    elseif id == "asrIncreaseLastId" then
        engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] = engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] + 1
    elseif id == "asrDumpLinesState" then
        log("asrEngine: dump all lines")
        asrHelper.tprint(engineState[asrEnum.LINES])
    elseif id == "asrDumpIndustriesState" then
        log("asrEngine: dump all industries")
        asrHelper.tprint(engineState[asrEnum.INDUSTRIES])
    elseif id == "asrDumpTrackedTrains" then
        log("asrEngine: dump tracked trains")
        log("asrEngine: tracked trains:")
        asrHelper.tprint(engineState[asrEnum.TRACKED_TRAINS])
        log("asrEngine: checked trains:")
        asrHelper.tprint(engineState[asrEnum.CHECKED_TRAINS])
    elseif id == "asrDumpModelCache" then
        log("asrEngine: dump model cache")
        asrHelper.tprint(engineState[asrEnum.MODEL_CACHE])
    elseif id == "asrDumpShippingContracts" then
        log("asrEngine: dump shipping contracts")
        asrHelper.tprint(engineState[asrEnum.SHIPPING_CONTRACTS])
    elseif id == "asrDumpCargoGroups" then
        log("asrEngine: dump cargo groups")
        asrHelper.tprint(engineState[asrEnum.CARGO_GROUPS])
    elseif id == "asrDumpLineState" then
        log("asrEngine: dump line")
        if engineState[asrEnum.LINES][tostring(params.lineId)] ~= nil then
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(params.lineId)])
        end
    elseif id == "asrEnableDebug" then
        log("asrEngine: debug enabled")
        engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] = true
    elseif id == "asrEnableGuiDebug" then
        log("asrEngine: gui debug enabled")
        engineState[asrEnum.STATUS][asrEnum.status.GUI_DEBUG] = true
    elseif id == "asrDisableDebug" then
        log("asrEngine: debug disabled")
        engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] = false
    elseif id == "asrEnableTimings" then
        log("asrEngine: timings enabled")
        engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] = true
    elseif id == "asrDisableTimings" then
        log("asrEngine: timings disabled")
        engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] = false
        engineState[asrEnum.TIMINGS] = {}
    elseif id == "asrUnpause" then
        log("asrEngine: pause disabled")
        flags.paused = false        
    elseif id == "asrSettings" then
        log("asrEngine: asrSettings")
        setGlobalSettings(params)
    elseif id == "asrLineSettings" then
        log("asrEngine: asrLineSettings")
        setLineSettings(params)
    elseif id == "asrUpdateShippingContract" then
        log("asrEngine: asrUpdateShippingContract")
        updateShippingContract(params)
    elseif id == "asrUpdateCargoGroup" then
        log("asrEngine: asrUpdateCargoGroup")
        updateCargoGroup(params)
    elseif id == "asrDeleteShippingContract" then
        log("asrEngine: asrDeleteShippingContract")
        deleteShippingContract(params)
    elseif id == "asrDeleteCargoGroup" then
        log("asrEngine: asrDeleteCargoGroup")
        deleteCargoGroup(params)
    elseif id == "asrAddCargoGroupMember" then
        log("asrEngine: asrAddCargoGroupMember")
        addCargoGroupMember(params)
    elseif id == "asrDeleteCargoGroupMember" then
        log("asrEngine: asrDeleteCargoGroupMember")
        deleteCargoGroupMember(params)
    elseif id == "asrFetchStockSystem" then
        log("asrEngine: fetch stock system")
        fetchStockSystem = true
    elseif id == "asrRefreshLinesNames" then
        log("asrEngine: refreshLinesNames")
        flags.refreshNames = true
    elseif id == "asrRefreshLineVehicleInfo" then
        log("asrEngine: asrRefreshLineVehicleInfo")
        refreshLineVehiclesInfo(params)
    elseif id == "asrUpdateStation" then
        log("asrEngine: asrUpdateStation")        
        updateStation(params)
    elseif id == "asrDeleteLineState" then
        log("asrEngine: asrDeleteLineState")        
        engineState[asrEnum.LINES][tostring(params.lineId)] = nil
    elseif id == "asrDeleteIndustriesState" then
        log("asrEngine: asrDeleteIndustriesState")        
        engineState[asrEnum.INDUSTRIES] = {}
    elseif id == "asrDeleteModelCache" then
        log("asrEngine: asrDeleteModelCache")
        engineState[asrEnum.MODEL_CACHE] = {}
    elseif id == "asrCheckTrainConfigs" then
        log("asrEngine: asrCheckTrainConfigs")        
        checkTrainsCapacity(true)
    elseif id == "asrCheckCargoTrackingReferences" then
        log("asrEngine: asrCheckCargoTrackingReferences")        
        asrCheckCargoTrackingReferences()
    elseif id == "asrEraseState" then
        log("asrEngine: asrEraseState")        
        engineState = {}
        flags.initDone = false
    elseif id == "asrDumpState" then
        log("asrEngine: asrDumpState")        
        asrHelper.tprint(engineState)
    else
        print("uknown message type:" .. id)
    end

end

-- main loop
function asrEngine.update()

    if getGameSpeed() > 0 and not flags.paused then 
        local startTime = os.clock()

        if flags.initDone then     
            checkTrainsPositions()

            if coroutines.updateSupplyChains == nil or coroutine.status(coroutines.updateSupplyChains) == "dead" then
                coroutines.updateSupplyChains = coroutine.create(updateSupplyChains)
                -- log("asrEngine: starting updateSupplyChains coroutine")
            end

            if coroutines.checkTrainsCapacity == nil or coroutine.status(coroutines.checkTrainsCapacity) == "dead" then
                coroutines.checkTrainsCapacity = coroutine.create(checkTrainsCapacity)
                -- log("asrEngine: starting updateSupplyChains coroutine")
            end

            -- check if we have current info about the lines 
            if engineState[asrEnum.LINES] == nil or #api.engine.system.lineSystem.getLines() ~= engineState[asrEnum.STATUS][asrEnum.status.LINES_COUNTER] then
                updateLinesInfo()
                updateLinesNames()
            end

            -- periodic refresh of data, every 1 sec or so
            if flags.initDone and engineState[asrEnum.UPDATE_TIMESTAMP] ~= nil and tonumber(asrHelper.getUniqueTimestamp()) -  tonumber(engineState[asrEnum.UPDATE_TIMESTAMP]) > 1 then
                refreshLinesCargoAmounts()
                refreshLinesTravelTimes()
                -- checkTrainsCapacity(true)
                -- updateSupplyChains(true)                
                -- log("asrEngine: resuming updateSupplyChains coroutine")
                coroutine.resume(coroutines.updateSupplyChains)
                coroutine.resume(coroutines.checkTrainsCapacity)

                validateCargoGroups()
                engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
            end

            -- periodic refresh of the names of the lines - even less frequent 
            if flags.refreshEnabled and flags.refreshNames then
                log("asrEngine: checking names")
                updateLinesNames()
                flags.refreshNames = false
            end

            if flags.refreshLines then
                log("asrEngine: refreshing lines")
                updateLinesInfo()
                updateLinesNames()
                updateTrainsInfo()
                flushTrackingInfo()                        
                flags.refreshLines = false
            end

            if flags.initLine then
                gatherLineInfo(flags.initLine)
                flags.initLine = false
            end

            if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then  storeTimings("Total", math.ceil((os.clock() - startTime)*1000000)/1000) end

            if os.time() - lastGarbageCollection > 60 then
                local memoryUsedBefore = api.util.getLuaUsedMemory()
                collectgarbage()
                lastGarbageCollection = os.time()
                local memoryUsedAfter = api.util.getLuaUsedMemory()
                log("asrEngine: garbage collection done, using: " .. math.ceil(memoryUsedAfter/1024) .. "kB, freed: " .. math.ceil((memoryUsedBefore - memoryUsedAfter)/1024) .. "kB")
                end
    
        end
    end

    -- initial setup
    if not flags.initDone then
        -- check if we have the default settings
        if engineState[asrEnum.SETTINGS] == nil then
            engineState[asrEnum.SETTINGS] = {}
            engineState[asrEnum.SETTINGS][asrEnum.settings.EXTRA_CAPACITY] = 0
            engineState[asrEnum.SETTINGS][asrEnum.settings.ENABLE_TRAIN_PURCHASE] = false
            engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] = 160
            engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] = 1
            engineState[asrEnum.SETTINGS][asrEnum.settings.TRACKING_DELAY] = 50

        end
        if engineState[asrEnum.STATUS] == nil then
            engineState[asrEnum.STATUS] = {}
            engineState[asrEnum.STATUS][asrEnum.status.LINES_COUNTER] = 0
            engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = 0
            engineState[asrEnum.STATUS][asrEnum.status.SHIPPING_CONTRACTS_VERSION] = 0
            engineState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_VERSION] = 0
            engineState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION] = 0
        end
        if engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] == nil then
            engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] = 100
        end        
        if engineState[asrEnum.TRACKED_TRAINS] == nil then
            engineState[asrEnum.TRACKED_TRAINS] = {}
        end
        if engineState[asrEnum.CHECKED_TRAINS] == nil then
            engineState[asrEnum.CHECKED_TRAINS] = {}
        end
        if engineState[asrEnum.SHIPPING_CONTRACTS] == nil then
            engineState[asrEnum.SHIPPING_CONTRACTS] = {}
        end
        if engineState[asrEnum.CARGO_GROUPS] == nil then
            engineState[asrEnum.CARGO_GROUPS] = {}
        end
        -- always clear model cache
        engineState[asrEnum.MODEL_CACHE] = {}
        if engineState[asrEnum.STATUS][asrEnum.status.STATE_VERSION] == nil then
            print("asrEngine: no previous state version, using current of: " .. globalStateVersion)
            engineState[asrEnum.STATUS][asrEnum.status.STATE_VERSION] = globalStateVersion
        end


        -- make sure previously stored lines are still valid
        updateLinesInfo()
        updateLinesNames()
        updateTrainsInfo()
        refreshLinesCargoAmounts()
        refreshLinesTravelTimes()
        -- engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] = true
        -- engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] = true

        cargoTypes = game.interface.getCargoTypes()
        flags.initDone = true
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

-- state load and save functions used by the game
function asrEngine.setState(state)
    engineState = state
end

function asrEngine.getState()
    return engineState
end


return asrEngine