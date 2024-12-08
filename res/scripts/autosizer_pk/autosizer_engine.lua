local asrHelper = require "autosizer_pk/autosizer_helper"
local asrEnum = require "autosizer_pk/autosizer_enums"

local asrEngine = {}

-- the main state variable, stored in savefiles 
local engineState = {}

-- local cache for some model properties, to avoid api calls
-- local modelCache = {}

-- local cache for industries and buildings to avoid api calls
local consumerCache = {}


-- local cache for train configs
local trainConfigCache = {}

-- version of the state, in case of breaking changes

local globalStateVersion = 2
-- coroutines

local coroutines = {
    updateSupplyChains = nil,
    checkTrainCapacities = nil,
}

local flags = {
    refreshNames = false,
    initDone = false,
    refreshEnabled = false,
    paused = false
}
-- industry related
-- local cargoTypes = {}

--temps
local fetchStockSystem = false
local trainsStatus = ""
local trainNameCache = {}

-- needed to get the in-game time
local worldId

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

    if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Configured"  or engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OK" then 
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = true
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = "All is well"
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
    -- engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Configured"
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
    -- check if all wagons have the same capacities
    local identicalWagons = true
    if engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] then
        local prevModelId
        for _, modelId in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS]) do
            if not prevModelId then
                prevModelId = modelId
            else
                -- log("engine: model comparison: " .. prevModelId .. " and " .. modelId)
                if not asrHelper.tablesAreIdentical(engineState[asrEnum.MODEL_CACHE][tostring(prevModelId)][asrEnum.modelCache.CAPACITIES], engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITIES]) then
                    identicalWagons = false
                end
            end
        end
    end
    log("engine: checkLineConfig: enabled: " .. enabledStations .. " valid: " .. validStations)
    if enabledStations > 0 and validStations == enabledStations  then
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "OK" then 
            if engineState[asrEnum.LINES][tostring(lineId)].enabled then 
                enableLine(lineId)
            end
        else
            log("engine: checkLineConfig: got to configured")
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Configured"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = _("status_configured")
            if engineState[asrEnum.LINES][tostring(lineId)].enabled then 
                enableLine(lineId)
            end
        end
    else
        log("engine: checkLineConfig: got to miconfigured stations")
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Misconfigured"
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = _("status_miconfigured_stations")
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] == true then 
            disableLine(lineId)
        end        
    end
    if not identicalWagons then
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Misconfigured"
        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = _("status_miconfigured_wagons")
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
                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil
                engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = nil
            end
        end
    else 
        -- flush all info
        engineState[asrEnum.CHECKED_TRAINS] = {}
        engineState[asrEnum.TRACKED_TRAINS] = {}
    end
end


local function increaseMemberInUseCounter(memberId, memberType)

    if memberType == "shippingContract" then
        if  engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] == nil then 
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = 1
       else
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] + 1
       end
    end
    if memberType == "cargoGroup" then
        if  engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] == nil then 
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = 1
       else
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] + 1
       end
    end
end

local function decreaseMemberInUseCounter(memberId, memberType)

    if memberType == "shippingContract" then
        if engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] and 
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] > 0 then
            engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] = engineState[asrEnum.SHIPPING_CONTRACTS][memberId][asrEnum.shippingContract.IN_USE] - 1
        end
    end
    if memberType == "cargoGroup" then
        if engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] and 
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] > 0 then
            engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] = engineState[asrEnum.CARGO_GROUPS][memberId][asrEnum.cargoGroup.IN_USE] - 1
        end
    end
end

local function updateStation(stationConfig) 

    log("engine: received station config: ")
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
                end
                if stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID] and engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID])] then
                    increaseMemberInUseCounter(stationConfig.config[asrEnum.station.SHIPPING_CONTRACT_ID], "shippingContract")
                end
            end
        end
        if stationConfig.config[asrEnum.station.SELECTOR] and stationConfig.config[asrEnum.station.SELECTOR] == "cargoGroup" then
            if stationConfig.config[asrEnum.station.CARGO_GROUP_ID] == asrEnum.value.DELETE then
                -- clear all cargo group related entries, free the id if set 
                local previousCargoGroupId = engineState[asrEnum.LINES][tostring(stationConfig.lineId)][asrEnum.line.STATIONS][tonumber(stationConfig.stopSequence)][asrEnum.station.CARGO_GROUP_ID]
                if previousCargoGroupId then 
                    decreaseMemberInUseCounter(previousCargoGroupId, "cargoGroup")
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
                end
                if stationConfig.config[asrEnum.station.CARGO_GROUP_ID] and engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig.config[asrEnum.station.CARGO_GROUP_ID])] then
                    increaseMemberInUseCounter(stationConfig.config[asrEnum.station.CARGO_GROUP_ID], "cargoGroup")
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
                print ("engine: wrong component (line id): " .. lineId)
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

    -- log("engine: state")
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

    log("engine: generate shipping contract name: ")

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
        log("engine: supplier: " .. shippingContract[asrEnum.shippingContract.SUPPLIER_ID] .. " consumer: " .. shippingContract[asrEnum.shippingContract.CONSUMER_ID])
        log("engine: supplier: " .. supplierName .. " consumer: " .. consumerName)
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
                log("engine: existing: " .. existingShippingContract[asrEnum.shippingContract.NAME])
                log("engine: new     : " .. newShippingContractName)
                if string.find(existingShippingContract[asrEnum.shippingContract.NAME], newShippingContractName, 0, true) then
                    -- existing, check if we have a #number 
                    local sequence = string.match(existingShippingContract[asrEnum.shippingContract.NAME], "#(%d+)$")
                    log("engine: existing (found): " .. existingShippingContract[asrEnum.shippingContract.NAME])
                    if not sequence then sequence = 1 end
                    if tonumber(sequence) > tonumber(maxSequence) then 
                        log("engine: found sequence: " .. sequence)
                        maxSequence = sequence
                    end
                end
            end
            if tonumber(maxSequence) ~= 0 then
                log("engine: using new name sequence: " .. (tonumber(maxSequence) + 1))
                newShippingContractName = newShippingContractName .. " #" .. (tonumber(maxSequence) + 1)
            end
            return newShippingContractName
        else
            log("not found")
        end
    end
end

local function generateCargoGroupName(cargoGroupId)

    log("engine: generate name for cargo group: " .. cargoGroupId)
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

    -- log("engine: checking members of: " .. cargoGroupId)
    if not currentList then 
        currentList = { cargoGroupId } 
    else
        table.insert(currentList, cargoGroupId)
    end
    local valid = true
    if engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
        for _, memberDetails in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
            if memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                -- log("engine: found sub-cargo group: " .. memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID] )
                if asrHelper.inTable(currentList, memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID]) then
                    -- we found the same id again
                    log("engine: checkCargoGroupMembers: duplicate found: " .. memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])
                    valid = false
                else
                    valid = valid and checkCargoGroupMembers(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID], currentList)
                end
            end
        end
    end
    if valid then
        -- log("engine: check for " .. cargoGroupId .. " result is valid")
    else
        log("engine: check for " .. cargoGroupId .. " result is not valid")
    end
    return valid

end

local function validateCargoGroups()

    if engineState[asrEnum.CARGO_GROUPS] then
        -- log("engine: checking cargo groups")
        for cargoGroupId, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
            -- if not cargoGroupDetails[asrEnum.cargoGroup.VALIDITY_CHECKED] and not cargoGroupDetails[asrEnum.cargoGroup.VALID] then
                -- log("engine: verfying main: " .. cargoGroupId)
                -- log("engine: verfying main: actually checking")
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
        print("engine: can't determine game entity for consumer: " .. consumerId)
    end
end

local function updateSupplyChains(runInForeground) 

    -- get cargo mappings

    -- log("engine: updateSupplyChains starting")
    local startTime = os.clock()
    local entryCounter = 1
    -- cargoTypes = game.interface.getCargoTypes()

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
        -- log("engine: updateSupplyChains running for more than 25ms - yielding - 1")
        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
        coroutine.yield()
        startTime = os.clock()
        entryCounter = entryCounter + 1
        -- log("engine: updateSupplyChains resuming")
    end

    -- log("engine: usc: got a stocklist")
    for cargoId, chainMap in pairs(stockList) do
        -- log("checking cargo " .. cargoTypes[cargoId])
        -- log("engine: usc: checking cargoid: " .. cargoId)
        if chainMap ~= nil and cargoId ~= 1 then -- no passegers for now
           for consumerId, suppliers in pairs (chainMap) do
                -- log("engine: usc: checking consumerid: " .. consumerId)

                -- check if the consumer is an industry or a town building
                local type, townId = getConsumerType(consumerId)

                -- log("engine: usc: checking type: " .. type)
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
                    print("engine: updateSupplyChains: can't identify the consumer: " .. consumerId)
                end
           end 
           if not runInForeground and  (os.clock() - startTime)*1000 >= 25 then
                -- log("engine: updateSupplyChains running for more than 25ms - yielding - 2")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("engine: updateSupplyChains resuming")
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
                -- log("engine: updateSupplyChains running for more than 25ms - yielding - 3")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("engine: updateSupplyChains resuming")
            end
        end
    end

    -- populate cargo groups with data
    if engineState[asrEnum.CARGO_GROUPS] then
        for cargoGroupId, cargoGroupDetails in pairs(engineState[asrEnum.CARGO_GROUPS]) do
            -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId)
            local totalAmount = 0
            if cargoGroupDetails[asrEnum.cargoGroup.VALID] and cargoGroupDetails[asrEnum.cargoGroup.MEMBERS] then 
                for _, memberDetails in pairs(cargoGroupDetails[asrEnum.cargoGroup.MEMBERS]) do
                    if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" then
                        -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry: " .. tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID]))
                        if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])] then
                            -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok")
                            if  memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "supplier" then
                                -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - supplier ")
                                if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER] and 
                                engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then
                                    -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - supplier - found amount")
                                    totalAmount = totalAmount + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.SUPPLIER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                end
                            elseif memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "consumer" then
                                -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - consumer ")
                                if engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER] and 
                                engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])] then
                                    -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " industry - is ok - consumer - found amount")
                                    totalAmount = totalAmount + engineState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.CONSUMER][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]
                                end
                           end
                        end
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
                        -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " shippingContract")
                        if engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])] and
                        engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT] then
                            totalAmount = totalAmount + engineState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                        end
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                        -- log("engine: updateSupplyChains: cargoGroupId: ".. cargoGroupId .. " cargoGroup")
                        if engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])] and
                        engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT] then
                            totalAmount = totalAmount + engineState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT]
                        end
                    end
                end
            end
            engineState[asrEnum.CARGO_GROUPS][tostring(cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] = totalAmount
            if not runInForeground and (os.clock() - startTime)*1000 >= 25 then
                -- log("engine: updateSupplyChains running for more than 25ms - yielding - 4")
                if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("updateSupplyChains", math.ceil((os.clock() - startTime)*1000000)/1000) end
                coroutine.yield()
                startTime = os.clock()
                entryCounter = entryCounter + 1
                -- log("engine: updateSupplyChains resuming")
            end
        end
    end

    -- log("engine: updateSupplyChains done after " .. math.ceil((os.clock() - startTime)*1000000)/1000 .. "ms ")
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
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "shippingContract" and stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID] and 
                                    engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])] and
                                    engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT] then                            
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = engineState[asrEnum.SHIPPING_CONTRACTS][tostring(stationConfig[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.CARGO_AMOUNT]
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "cargoGroup" and stationConfig[asrEnum.station.CARGO_GROUP_ID] and
                                engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])] and 
                                engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT] then                            
                                        engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = engineState[asrEnum.CARGO_GROUPS][tostring(stationConfig[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.CARGO_AMOUNT]
                                end

                                if stationConfig[asrEnum.station.SELECTOR] == "fixedAmount" and stationConfig[asrEnum.station.FIXED_AMOUNT_VALUE] then
                                    engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] = stationConfig[asrEnum.station.FIXED_AMOUNT_VALUE]
                                end
                            end
                            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] and 
                                engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopSequence][asrEnum.station.CARGO_AMOUNT] == 0 then
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
                            -- log("engine: refreshLinesTravelTimes: lineId: " .. lineId .. " travelTime1: " .. avgTripTime)
                        end
                        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                            if stationDetails[asrEnum.station.STOP_DURATION] then
                                avgTripTime = avgTripTime + asrHelper.average(stationDetails[asrEnum.station.STOP_DURATION])    
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
        if modelDetails.metadata.railVehicle and not passengers then -- only count trains with no passenger capability
            if not foundCompartments then
                engineState[asrEnum.MODEL_CACHE][tostring(modelId)] = {
                    [asrEnum.modelCache.TYPE] = "engine", 
                    [asrEnum.modelCache.CAPACITIES] = {},
                    [asrEnum.modelCache.CAPACITY] = 0,
                    [asrEnum.modelCache.LENGTH] = modelDetails.boundingInfo.bbMax.x - modelDetails.boundingInfo.bbMin.x,
                    [asrEnum.modelCache.COMPARTMENTS] = 0,
                }
            else 
                engineState[asrEnum.MODEL_CACHE][tostring(modelId)] = {
                    [asrEnum.modelCache.TYPE] = "wagon",
                    [asrEnum.modelCache.CAPACITIES] = cargoCapacities,
                    [asrEnum.modelCache.CAPACITY] = capacity * #modelDetails.metadata.transportVehicle.compartments,
                    [asrEnum.modelCache.LENGTH] = modelDetails.boundingInfo.bbMax.x - modelDetails.boundingInfo.bbMin.x,
                    [asrEnum.modelCache.COMPARTMENTS] =  #modelDetails.metadata.transportVehicle.compartments
                }
            end
        else 
            -- log("engine: not a rail vehicle")
        end
        -- log("engine: modelId:" .. modelId)
        -- asrHelper.tprint(engineState[asrEnum.MODEL_CACHE][modelId])
        return engineState[asrEnum.MODEL_CACHE][tostring(modelId)]
    end    
end

local function getTrainModels(trainId)
    -- determine the model 
    local trainInfo = {}
    if api.engine.entityExists(tonumber(trainId)) then
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
        -- log("engine: getTrainModels getComponent")
        local trainVehicleList = {}
        if trainDetails and trainDetails.transportVehicleConfig and trainDetails.transportVehicleConfig.vehicles then
            trainVehicleList = trainDetails.transportVehicleConfig.vehicles
        end

        -- log("models for train " .. trainId)
        for _, vehicle in pairs(trainVehicleList) do
            local modelInfo = getModelDetails(vehicle.part.modelId)
            if modelInfo then
                if modelInfo[asrEnum.modelCache.TYPE] == "engine" then
                    if  trainInfo.engines and not asrHelper.inTable(trainInfo.engines, vehicle.part.modelId ) then
                        table.insert(trainInfo.engines, vehicle.part.modelId )
                    else
                        trainInfo.engines = { vehicle.part.modelId }
                end
                elseif modelInfo[asrEnum.modelCache.TYPE] == "wagon" then
                    if  trainInfo.wagons and not asrHelper.inTable(trainInfo.wagons, vehicle.part.modelId ) then
                        table.insert(trainInfo.wagons, vehicle.part.modelId )
                    else
                        trainInfo.wagons = { vehicle.part.modelId }
                    end
                end
            end
        end
        return trainInfo
    end
end

local function generateTrainConfig(trainId, lineId, stopIndex)

    log("engine: train " .. getTrainName(trainId) .. " generating new train config")
    local startTime = os.clock()
    -- generate new train configuration 
    if engineState[asrEnum.LINES] and engineState[asrEnum.LINES][tostring(lineId)] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] and engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1] then
        
        local cargoAmount = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CARGO_AMOUNT]
        local travelTime = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.TRAVEL_TIME]
        
        if not travelTime then 
            print("engine: train " .. getTrainName(trainId) .. " no travel time")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)])
            return
        end
        if not cargoAmount then 
            print("engine: train " .. getTrainName(trainId) .. " no cargo amount")
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1])
            return
        end

        local capacityScaleFactor = 1

        -- check if we need to adjust the capacity 
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= 0 then 
                capacityScaleFactor = capacityScaleFactor + (engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]/100)
                log("engine: train " .. getTrainName(trainId) .. " capacity factor: " .. capacityScaleFactor)
        end


        local requiredWagonCount = math.ceil(capacityScaleFactor* travelTime / 720 * cargoAmount / engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY])
        local additionalWagonCount = 0
        local stage -- tells when to carry out the replacement

        -- check if we need to accomodate for waiting cargo
        if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_ENABLED] == true and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE] ~= nil and 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE] > 0 then 

            local requiredCapacity = requiredWagonCount *  engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY]

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
            log("engine: train " .. getTrainName(trainId) .. " total cargo waiting at " .. stopIndex .. " is " .. cargoEntityCounter)
            if cargoEntityCounter > requiredCapacity then 
                -- extra wagons needed
                additionalWagonCount = math.ceil((cargoEntityCounter - requiredCapacity) * engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.WAITING_CARGO_VALUE]/100/engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1])][asrEnum.modelCache.CAPACITY])
                log("engine: train " .. getTrainName(trainId) .. " adding extra " .. additionalWagonCount .. " wagon(s)")
            end
        end

        requiredWagonCount = requiredWagonCount + additionalWagonCount

        if engineState[asrEnum.SETTINGS] and engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] and 
            requiredWagonCount < engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] then
                requiredWagonCount = engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT]
                log("engine: train " .. getTrainName(trainId) .. " train would be shorter than minimal, adding wagons")
            end
        
        local trainDetails = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)

        -- check how many engines we have
        local engineCount = 0
        for _, vehicle in pairs(trainDetails.transportVehicleConfig.vehicles) do
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.TYPE] == "engine" then engineCount = engineCount + 1 end
        end
        log("engine: train " .. getTrainName(trainId) .. " has " .. engineCount .. " engine(s)" )

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

        log("engine: train " .. getTrainName(trainId) .. " current count: " .. currentWagonCount .. " new count: " .. requiredWagonCount)

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

            log("engine: train " .. getTrainName(trainId) .. " copying modelId: " .. vehicle.part.modelId)
            autoLoadConfig = {}
            loadConfig = {}
            if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS] == 0 then 
                autoLoadConfig = {1}
                loadConfig = {0}
            else 
                for i=1, engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.COMPARTMENTS] do 
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
                    -- log("engine: train " .. getTrainName(trainId) .. " train copy, got to " .. (vehicleCounter - 1 ) )
                    break
                end
            else
                trainTooLong = true
                break
            end
        end

        -- if any more wagons are required - add them based on what's been discovered  in other trains on the line
        math.randomseed(os.time())        
        for i = vehicleCounter, requiredWagonCount + engineCount do 
            local vehicleConfig = api.type.TransportVehiclePart.new()
            local vehiclePart = api.type.VehiclePart.new()

            local modelSeq = math.random(#engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS])
            log("engine: train " .. getTrainName(trainId) .. " adding new modelId: " .. engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq] .. " using seq of: " .. modelSeq)

            autoLoadConfig = {}
            loadConfig = {}
            if not engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])] then
                print("engine: train " .. getTrainName(trainId) .. " issue getting details of wagon no: " .. modelSeq .. " refreshing cache")
                getModelDetails(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])
            end

            if engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.COMPARTMENTS] == 0 then 
                autoLoadConfig = {1}
                loadConfig = {0}
            else
                for j=1, engineState[asrEnum.MODEL_CACHE][tostring(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][modelSeq])][asrEnum.modelCache.COMPARTMENTS] do
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

        log("engine: train " .. getTrainName(trainId) .. " total train length: " .. trainLength)
        if trainTooLong then
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = true
            log("engine: train " .. getTrainName(trainId) .. " would be too long")
        else
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS][stopIndex + 1][asrEnum.station.LENGTH_WARNING] = false
        end

        -- check all stations for flags

        local lengthWarning = false
        local lengthWarningMessage = "Required trains would be longer than allowed at:"
        for _, stationDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
            if stationDetails[asrEnum.station.LENGTH_WARNING] then
                local stationName = api.engine.getComponent(stationDetails[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME)
                if stationName and stationName.name then
                    lengthWarningMessage = lengthWarningMessage .. "\n" .. stationName.name
                end
                lengthWarning = true
            end
        end
        if lengthWarning then 
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "Warning"
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = lengthWarningMessage
        else
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] == "Warning" then
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS] = "OK"
                 engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATUS_MESSAGE] = "All is well"
            end
        end

        if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then storeTimings("generateTrainConfig", math.ceil((os.clock() - startTime)*1000000)/1000) end
        return trainConfig, stage
    else
        print("engine: train " .. getTrainName(trainId) .. " can't identify new config for train: " .. trainId, " line: " .. lineId .. " stopIndex: " .. stopIndex)
    end
end

local function checkIfCapacityAdjustmentNeeded(trainId, trainVehicles, stationConfig, travelTime, lineId)

    -- only run if trainId is not tracked already
    if not engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then
        -- check if the station has the requirements defined
        if stationConfig[asrEnum.station.ENABLED] == true then
            if not stationConfig[asrEnum.station.CARGO_AMOUNT]  then
                print("engine: train " .. getTrainName(trainId) .. " missing cargo amount")
                return
            end
            if not travelTime  then
                print("engine: train " .. getTrainName(trainId) .. " missing travel time")
                return
            end    

            -- if additional cargo pickup is enabled the train must be tracked
            if stationConfig[asrEnum.station.WAITING_CARGO_ENABLED] == true then 
                return true
            end

            -- if the line is set to "always track" (due to 0-sized trains)
            if engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ALWAYS_TRACK] == true then 
                return true
            end
            
            -- check the total capcity of all wagons 
            local currentCapacity = 0
            local currentWagonCount = #trainVehicles - 1 -- not counting the engine

            local capacityScaleFactor = 1

            -- check if we need to adjust the capacity 
            if stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true and stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] and stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= 0 then 
                    capacityScaleFactor = capacityScaleFactor + stationConfig[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]/100
                    log("engine: train " .. getTrainName(trainId) .. " capacity factor: " .. capacityScaleFactor)
            end
    
            for _, vehicle in pairs(trainVehicles) do
                if engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)] == nil then
                    print("engine: train " .. getTrainName(trainId) .. " no info about model: " .. vehicle.part.modelId .. " check not possible" )        
                    return nil
                end
                currentCapacity = currentCapacity + engineState[asrEnum.MODEL_CACHE][tostring(vehicle.part.modelId)][asrEnum.modelCache.CAPACITY]
            end
            
            -- required number of wagons 
            local modelId = engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS][1]
            local requiredWagonCount = math.ceil(capacityScaleFactor * travelTime / 720 * stationConfig[asrEnum.station.CARGO_AMOUNT] / engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITY])
            
            -- log("engine: train " .. getTrainName(trainId) .. " current capacity  is " .. currentCapacity .. ", wagon count: " .. currentWagonCount)
            if requiredWagonCount ~= currentWagonCount then
                -- log("engine: train " .. getTrainName(trainId) .. " wagons required: " .. requiredWagonCount .. ", wagon capacity: " .. engineState[asrEnum.MODEL_CACHE][tostring(modelId)][asrEnum.modelCache.CAPACITY] .. " using modelId: " .. modelId .. " travelTime: " .. travelTime)
                -- log("engine: train " .. getTrainName(trainId) .. " requires a capacity correction at the next station")
                return true
            else
                -- log("engine: train " .. getTrainName(trainId) .. " no capacity adjustment required")
                return false
            end
        else 
            -- log("engine: train " .. getTrainName(trainId) .. " next stop not configured, no adjustement necessary")
            return false
        end
    end
end

local function checkTrainsCapacity()

    local startTime = os.clock()
    -- loop through all enabled lines, check current train configs and if they need to be updated at the next station
    if engineState[asrEnum.LINES] then 
    for lineId, line in pairs(engineState[asrEnum.LINES]) do
            if line[asrEnum.line.ENABLED] == true then
                -- log ("engine: checking line " .. lineId )
                for _, trainId in pairs(api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))) do
                    -- log("engine: checking trainId: " .. trainId)
                    if api.engine.entityExists(tonumber(trainId)) then 
                        local trainInfo = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
                        if trainInfo then
                            if not engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] then engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = -1 end
                            -- log("engine: line " .. lineId .. " train: " .. getTrainName(trainId) .. " heading to stopIndex: " .. trainInfo.stopIndex .. " last checked:"  .. engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] )
                            if line[asrEnum.line.STATIONS][trainInfo.stopIndex + 1] and 
                                trainInfo.state ~= api.type.enum.TransportVehicleState.AT_TERMINAL and engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] ~= trainInfo.stopIndex  then -- ignore if train is already stopped at a station or has been checked already
                                -- at the next station train might require configuration adjustment, check if current config is sufficient
                                -- log("engine: will check again")
                                local checkResult = checkIfCapacityAdjustmentNeeded(trainId, trainInfo.transportVehicleConfig.vehicles, line[asrEnum.line.STATIONS][trainInfo.stopIndex + 1], line[asrEnum.line.TRAVEL_TIME], lineId)
                                if checkResult == true then
                                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = {}
                                    engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = trainInfo.stopIndex
                                elseif checkResult == false then
                                    engineState[asrEnum.CHECKED_TRAINS][tostring(trainId)] = trainInfo.stopIndex
                                end
                            end
                        else
                            print("engine: train " .. getTrainName(trainId) .. " couldn't get info from the API (" .. trainId .. ")")
                            -- flags.paused = true
                            break
                        end
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
            local trainCurrentInfo = api.engine.getComponent(tonumber(trainId), api.type.ComponentType.TRANSPORT_VEHICLE)
            -- train is arriving
            if trainCurrentInfo.timeUntilLoad > 0 then
                -- log("engine: train " .. trainId .. " is appraching a station (" .. trainCurrentInfo.timeUntilLoad .. ") " .. " index: " .. trainCurrentInfo.stopIndex )
                if not trainPrevInfo[asrEnum.trackedTrain.IN_STATION] and not trainPrevInfo[asrEnum.trackedTrain.GENERATED_CONFIG] then -- prepare new config as train pulls into the station

                    log("engine: train " .. getTrainName(trainId) .. " preparing vehicle replacement (at " .. trainCurrentInfo.timeUntilLoad .. ", trainId: " ..  trainId .. ")")
                    local replacementConfig, stage = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)

                    trainConfigCache[tostring(trainId)] = replacementConfig
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.GENERATED_CONFIG] = true
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] = stage
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.IN_STATION] = true
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] = getGameTime()

                    if stage == "arrival" then
                        local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), replacementConfig)
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                        api.cmd.sendCommand(replaceCmd, function () 
                            log ("engine: train " .. getTrainName(trainId) .. " replace sent on arrival, currently at stop " .. trainCurrentInfo.stopIndex)
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DELETE_ON_EXIT] = true    
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                        end)
                    end
                end
            end

            -- train is unloading
            if trainCurrentInfo.timeUntilLoad ~= trainPrevInfo[asrEnum.trackedTrain.TIME_UNTIL_LOAD] then
                -- log("engine: train " .. trainId .. " timeUntilLoad: " .. trainCurrentInfo.timeUntilLoad )
                if trainCurrentInfo.timeUntilLoad <= 0.25 and trainPrevInfo[asrEnum.trackedTrain.IN_STATION] and not trainPrevInfo[asrEnum.trackedTrain.REPLACED] then

                    if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "unload" then 
                        if not trainConfigCache[tostring(trainId)] then
                            -- config might got lost during save/restore
                            trainConfigCache[tostring(trainId)] = generateTrainConfig(trainId, trainCurrentInfo.line, trainCurrentInfo.stopIndex)
                        end
                        local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), trainConfigCache[tostring(trainId)])
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                        api.cmd.sendCommand(replaceCmd, function () 
                            log ("engine: train " .. getTrainName(trainId) .. " replace sent on unload, currently at stop " .. trainCurrentInfo.stopIndex)
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DELETE_ON_EXIT] = true    
                            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                        end)
                    end
                end
            end

            -- train is leaving
            if trainCurrentInfo.state == api.type.enum.TransportVehicleState.EN_ROUTE and trainPrevInfo[asrEnum.trackedTrain.STATE] == api.type.enum.TransportVehicleState.AT_TERMINAL then
                log("engine: train " .. getTrainName(trainId) .. " is leaving a station " .. " heading to index: " .. trainCurrentInfo.stopIndex )

                if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACE_ON] == "departure" and not trainPrevInfo[asrEnum.trackedTrain.REPLACED]  then 
                    if not trainConfigCache[tostring(trainId)] then
                        -- config might got lost during save/restore
                        trainConfigCache[tostring(trainId)] = generateTrainConfig(trainId, trainCurrentInfo.line, trainPrevInfo[asrEnum.trackedTrain.STOP_INDEX] + 1)
                    end
                    local replaceCmd = api.cmd.make.replaceVehicle(tonumber(trainId), trainConfigCache[tostring(trainId)])
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                    api.cmd.sendCommand(replaceCmd, function () 
                        log ("engine: train " .. getTrainName(trainId) .. " replace sent on departure, heading to stop " .. trainCurrentInfo.stopIndex)
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.REPLACED] = true
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DELETE_ON_EXIT] = true    
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STOP_INDEX] = trainCurrentInfo.stopIndex
                    end)
                end

                if trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP] then 
                    local stopDuration = (getGameTime() - trainPrevInfo[asrEnum.trackedTrain.ARRIVAL_TIMESTAMP])
                    log("engine: train " .. getTrainName(trainId) .. " spent " .. stopDuration .. " s")

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
                        engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.DEPARTURE_TIMESTAMP] = getGameTime()
                    else
                        log("engine: train " .. getTrainName(trainId) .. " no previous stop info")
                    end
                end
                if trainPrevInfo[asrEnum.trackedTrain.DELETE_ON_EXIT] then
                    log("engine: train " .. getTrainName(trainId) .. " is no longer tracked")
                   engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil 
                end
            end

            -- check if the line is still enabled and store the current state
            if engineState[asrEnum.LINES][tostring(trainCurrentInfo.line)][asrEnum.line.ENABLED] then 
                if engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] then 
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.STATE] = trainCurrentInfo.state
                    engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)][asrEnum.trackedTrain.TIME_UNTIL_LOAD] = trainCurrentInfo.timeUntilLoad
                end
            else
                -- line not enabled any more - stop tracking
                log("engine: train " .. getTrainName(trainId) .. " is no longer tracked (line disabled)")
                engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil 
            end
        else
            -- the train most likely got sold, stop tracking
            engineState[asrEnum.TRACKED_TRAINS][tostring(trainId)] = nil
        end
    end
    if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then  storeTimings("checkTrainsPositions", math.ceil((os.clock() - startTime)*1000000)/1000) end
end



local function updateLineStations(lineId)

    log("engine: updateLineStations: " .. lineId)
    if api.engine.entityExists(tonumber(lineId)) then
        local lineDetails = api.engine.getComponent(tonumber(lineId), api.type.ComponentType.LINE)
        -- log("engine: getLineStations getComponent")
        if lineDetails ~= nil then
            for stopOrder, stop in pairs(lineDetails.stops) do
                local stationGroupId = stop.stationGroup
                local stationGroupDetails = api.engine.getComponent(tonumber(stationGroupId), api.type.ComponentType.STATION_GROUP)
                -- log("engine: getLineStation2 getComponent")
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
end

local function updateLineIndustriesAndTowns(lineId)
    
    log("engine: updateLineIndustriesAndTowns: " .. lineId)
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
                        --     log("engine: broken entity: " .. entity.entity)
                        end
                    end
                    seenStationIds[tostring(station.stationId)] = true
                else
                    -- log("stationId: " .. stop.stationId .. " seen already")
                end
            end
        end
    else
        print("engine: can't get town to building map")
    end
    -- check for any industries that disappeared
    for industryId, industryDetails in pairs(engineState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES]) do
        if not seenEntityIds[tostring(industryId)] and industryDetails[asrEnum.lineIndustry.TYPE] == "industry" then 
            log("engine: industry id: " .. industryId .. " not found any more, removing")
            engineState[asrEnum.LINES][tostring(lineId)][asrEnum.INDUSTRIES][tostring(industryId)] = nil
        end
    end
end


local function getLineTrainSummary(lineId)

    log("engine: getLineTrainSummary for line: " .. lineId)
    local trainSummary = { 
        trainCount = 0,
        engines = {},
        wagons = {},
        -- trainList = {},
    }
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(tonumber(lineId))
    for _, trainId in  pairs(lineVehicles) do
        local models = getTrainModels(trainId)
        if models ~= nil then
            if models.engines ~= nil then 
                -- trainSummary.trainCount = trainSummary.trainCount + 1
                for _, modelId in pairs(models.engines) do 
                    -- log("engine: getLineTrainSummary: found engine: " .. modelId)
                    if trainSummary.engines[tostring(modelId)] == nil then
                        trainSummary.engines[tostring(modelId)] = 1
                    else 
                        trainSummary.engines[tostring(modelId)] = trainSummary.engines[tostring(modelId)] + 1
                    end
                end
            end
            if models.wagons ~= nil then
                for _, modelId in pairs(models.wagons) do 
                    -- log("engine: getLineTrainSummary: found wagon: " .. modelId)
                    if trainSummary.wagons[tostring(modelId)] == nil then
                        trainSummary.wagons[tostring(modelId)] = 1
                    else 
                        trainSummary.wagons[tostring(modelId)] = trainSummary.wagons[tostring(modelId)] + 1
                    end

                end
            else 
                -- log("engine: getLineTrainSummary: no wagons?")
            end
        end
    end

    return trainSummary
end

local function updateLineTrainsInfo(lineId) 

    log("engine: updateTrainsInfo lineId: " .. lineId)

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

    -- log("engine: line state")
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
        engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] = engineState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] + 1
    end
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

    log("engine: gatherLineInfo: " .. lineId)

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

    log("engine: updateShippingContract:")
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
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] = 0
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
            for memberId, memberDetails in pairs(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" or memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                    decreaseMemberInUseCounter(memberId, memberDetails[asrEnum.cargoGroupMember.TYPE])
                end
            end
        end
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] = nil
        increseObjectVersion(asrEnum.status.CARGO_GROUPS_VERSION)
    end
end

local function addCargoGroupMember(params)

    if params and params.cargoGroupId and params.values then
        if engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] == nil then
            engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] = {}
        end
        table.insert(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS], params.values)
        if params.values[asrEnum.cargoGroupMember.TYPE] and 
            (params.values[asrEnum.cargoGroupMember.TYPE] == "shippingContract" or params.values[asrEnum.cargoGroupMember.TYPE] == "cargoGroup") then
                increaseMemberInUseCounter(params.values[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID], params.values[asrEnum.cargoGroupMember.TYPE])
        end
        if not engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] or 
            string.find(engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] , "Cargo group #") then
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.NAME] =  generateCargoGroupName(params.cargoGroupId)
                engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MANUAL_NAME] = nil
        end
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.VALID] = false
        engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.VALIDITY_CHECKED] = false
        increseObjectVersion(asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION)
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

local function deleteCargoGroupMember(params)

    if params and params.cargoGroupId and params.memberId then
        if engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)] and 
           engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS] and 
           engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId] then
            local memberType = engineState[asrEnum.CARGO_GROUPS][tostring(params.cargoGroupId)][asrEnum.cargoGroup.MEMBERS][params.memberId][asrEnum.cargoGroupMember.TYPE]
            if memberType == "shippingContract" or memberType == "cargoGroup" then
                decreaseMemberInUseCounter(params.memberId, memberType)
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
        engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
    end
end

function asrEngine.handleEvent(id, params) 
    log("engine: comamnd received: " .. id)
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
            log("engine: command - no lineId")
        end
    elseif id == "asrInitLine" then
        gatherLineInfo(params.lineId)
    elseif id == "asrForceLineCheck" then
        log("engine: force line check")
        updateLinesInfo()
        updateLinesNames()
        updateTrainsInfo()
        flushTrackingInfo()
    elseif id == "asrStopRefresh" then
        log("engine: refresh disabled")
        flags.refreshEnabled = false
    elseif id == "asrStartRefresh" then
        log("engine: refresh enabled")
        flags.refreshEnabled = true
    elseif id == "asrIncreaseLastId" then
        engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] = engineState[asrEnum.STATUS][asrEnum.status.LAST_ID] + 1
    elseif id == "asrDumpLinesState" then
        log("engine: dump all lines")
        asrHelper.tprint(engineState[asrEnum.LINES])
    elseif id == "asrDumpIndustriesState" then
        log("engine: dump all industries")
        asrHelper.tprint(engineState[asrEnum.INDUSTRIES])
    elseif id == "asrDumpTrackedTrains" then
        log("engine: dump tracked trains")
        log("engine: tracked trains:")
        asrHelper.tprint(engineState[asrEnum.TRACKED_TRAINS])
        log("engine: checked trains:")
        asrHelper.tprint(engineState[asrEnum.CHECKED_TRAINS])
    elseif id == "asrDumpModelCache" then
        log("engine: dump model cache")
        asrHelper.tprint(engineState[asrEnum.MODEL_CACHE])
    elseif id == "asrDumpShippingContracts" then
        log("engine: dump shipping contracts")
        asrHelper.tprint(engineState[asrEnum.SHIPPING_CONTRACTS])
    elseif id == "asrDumpCargoGroups" then
        log("engine: dump cargo groups")
        asrHelper.tprint(engineState[asrEnum.CARGO_GROUPS])
    elseif id == "asrDumpLineState" then
        log("engine: dump line")
        if engineState[asrEnum.LINES][tostring(params.lineId)] ~= nil then
            asrHelper.tprint(engineState[asrEnum.LINES][tostring(params.lineId)])
        end
    elseif id == "asrEnableDebug" then
        log("engine: debug enabled")
        engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] = true
    elseif id == "asrDisableDebug" then
        log("engine: debug disabled")
        engineState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] = false
    elseif id == "asrEnableTimings" then
        log("engine: timings enabled")
        engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] = true
    elseif id == "asrDisableTimings" then
        log("engine: timings disabled")
        engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] = false
        engineState[asrEnum.TIMINGS] = {}
    elseif id == "asrUnpause" then
        log("engine: pause disabled")
        flags.paused = false        
    elseif id == "asrSettings" then
        log("engine: asrSettings")
        setGlobalSettings(params)
    elseif id == "asrLineSettings" then
        log("engine: asrLineSettings")
        setLineSettings(params)
    elseif id == "asrUpdateShippingContract" then
        log("engine: asrUpdateShippingContract")
        updateShippingContract(params)
    elseif id == "asrUpdateCargoGroup" then
        log("engine: asrUpdateCargoGroup")
        updateCargoGroup(params)
    elseif id == "asrDeleteShippingContract" then
        log("engine: asrDeleteShippingContract")
        deleteShippingContract(params)
    elseif id == "asrDeleteCargoGroup" then
        log("engine: asrDeleteCargoGroup")
        deleteCargoGroup(params)
    elseif id == "asrAddCargoGroupMember" then
        log("engine: asrAddCargoGroupMember")
        addCargoGroupMember(params)
    elseif id == "asrDeleteCargoGroupMember" then
        log("engine: asrDeleteCargoGroupMember")
        deleteCargoGroupMember(params)
    elseif id == "asrFetchStockSystem" then
        log("engine: fetch stock system")
        fetchStockSystem = true
    elseif id == "asrRefreshLinesNames" then
        log("engine: refreshLinesNames")
        flags.refreshNames = true
    elseif id == "asrRefreshLineVehicleInfo" then
        log("engine: asrRefreshLineVehicleInfo")
        refreshLineVehiclesInfo(params)
    elseif id == "asrUpdateStation" then
        log("engine: asrUpdateStation")        
        updateStation(params)
    elseif id == "asrDeleteLineState" then
        log("engine: asrDeleteLineState")        
        engineState[asrEnum.LINES][tostring(params.lineId)] = nil
    elseif id == "asrDeleteIndustriesState" then
        log("engine: asrDeleteIndustriesState")        
        engineState[asrEnum.INDUSTRIES] = {}
    elseif id == "asrCheckTrainConfigs" then
        log("engine: asrCheckTrainConfigs")        
        checkTrainsCapacity()
    elseif id == "asrEraseState" then
        log("engine: asrEraseState")        
        engineState = {}
        flags.initDone = false
    elseif id == "asrDumpState" then
        log("engine: asrDumpState")        
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
                -- log("engine: starting updateSupplyChains coroutine")
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
                checkTrainsCapacity()
                -- log("engine: resuming updateSupplyChains coroutine")
                coroutine.resume(coroutines.updateSupplyChains)
        
                validateCargoGroups()
                engineState[asrEnum.UPDATE_TIMESTAMP] = asrHelper.getUniqueTimestamp()
            end

            -- periodic refresh of the names of the lines - even less frequent 
            if flags.refreshEnabled and flags.refreshNames then
                log("engine: checking names")
                updateLinesNames()
                flags.refreshNames = false
            end

            if engineState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then  storeTimings("Total", math.ceil((os.clock() - startTime)*1000000)/1000) end
        end
    end

    -- initial setup
    if not flags.initDone then
        print("autosizer - initialising")
        -- check if we have the default settings
        if engineState[asrEnum.SETTINGS] == nil then
            engineState[asrEnum.SETTINGS] = {}
            engineState[asrEnum.SETTINGS][asrEnum.settings.EXTRA_CAPACITY] = 0
            engineState[asrEnum.SETTINGS][asrEnum.settings.ENABLE_TRAIN_PURCHASE] = false
            engineState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] = 160
            engineState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] = 1

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
        if engineState[asrEnum.MODEL_CACHE] == nil then
            engineState[asrEnum.MODEL_CACHE] = {}
        end
        if engineState[asrEnum.STATUS][asrEnum.status.STATE_VERSION] == nil then
            print("engine: no previous state version, using current of: " .. globalStateVersion)
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
        flags.initDone = true
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