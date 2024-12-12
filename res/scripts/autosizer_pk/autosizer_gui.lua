
local asrHelper = require "autosizer_pk/autosizer_helper"
local asrGuiHelper = require "autosizer_pk/autosizer_gui_helper"
local asrEnum = require "autosizer_pk/autosizer_enums"

local asrGui = {}

local asrGuiState = {
    initDone = false,
    isVisible = false,
    rebuildLinesTable = true,
    refreshLinesTable = false,
    rebuildSettingsWindow = false,
    refreshCargoAmounts = false,
    selectedLine = nil,
    selectedStation = nil,
    selectedStopSequence = nil,
    lineSettingsTableBuilt = false,
    settingsTableInitalising = false,
    settingsIsVisible = false,
    activeTab = "",
    lineRefreshTimestamp = {},
    shippingContractsRowMap = {},
    cargoGroupsRowMap = {},
    cargoGroupMembersRowMap = {},
    linesRowMap = {},
    linesFilterString = ""
}

-- state and gui objects
local asrGuiObjects = {}
local asrState = {}

-- engine commmunication
local asrLastEngineTimestamp = nil
local asrLastLinesVersion = nil
local asrLastShippingContractsVersion = nil
local asrLastCargoGroupsVersion = nil
local asrLastCargoGroupsMembersVersion = nil
local asrEngineMessageQueue = {}

local cargoTypes = {}

local i18Strings =  {
    add = _("add"),
    adjust_capacity = _("adjust_capacity"),
    adjust_capacity_tip = _("adjust_capacity_tip"),
    cargo_group = _("cargo_group"),
    cargo_tracking = _("cargo_tracking"),
    consumer = _("consumer"),
    default = _("default"),
    default_maximal_train_length = _("default_maximal_train_length"),
    default_maximal_train_length_tip = _("default_maximal_train_length_tip"),
    delete_cargo_group = _("delete_cargo_group"),
    delete_cargo_group_member = _("delete_cargo_group_member"),
    delete_shipping_contract = _("delete_shipping_contract"),
    disabled = _("disabled"),
    disabled_for_line = _("disabled_for_line"),
    enable_debug = _("enable_debug"),
    enable_timings = _("enable_timings"),
    enabled = _("enabled"),
    fixed_amount = _("fixed_amount"),
    in_use_cant_delete = _("in_use_cant_delete"),
    industry = _("industry"),
    line_name = _("line_name"),
    lines = _("lines"),
    manual = _("manual"),
    minimal_train_wagon_count = _("minimal_train_wagon_count"),
    minimal_train_wagon_count_tip = _("minimal_train_wagon_count_tip"),
    mod_desc = _("mod_desc"),
    name = _("name"),
    name_desc = _("name_desc"),
    new_cargo_group = _("new_cargo_group"),
    new_shipping_contract = _("new_shipping_contract"),
    pickup_waiting = _("pickup_waiting"),
    pickup_waiting_tip = _("pickup_waiting_tip"),
    pickup_waiting_backlog_label = _("pickup_waiting_backlog_label"),
    pickup_waiting_backlog_label_tip = _("pickup_waiting_backlog_label_tip"),
    rename_cargo_group = _("rename_cargo_group"),
    rename_shipping_contract = _("rename_shipping_contract"),
    search_for_line = _("search_for_line"),
    settings = _("settings"),
    shipping_contract = _("shipping_contract"),
    stations = _("stations"),
    status_configured = _("status_configured"),
    status_miconfigured_stations = _("status_miconfigured_stations"),
    status_miconfigured_wagons = _("status_miconfigured_wagons"),
    supplier = _("supplier"),
    train_length = _("train_length"),
    wagons = _("wagons"),
    wagons_refresh_tip = _("wagons_refresh_tip"),
}


local toggleGroups = {
    trainLength = {        
        "Global",
        -- "Automatic",
        "Manual", 
    },
    amountSelection = {
        "IndustryShipping",
        "CargoGroup",
        "ShippingContract",
        "FixedAmount"
    }
}

local asrGuiDimensions = {
    mainWindow = {
        width = 1200,
        height = 800,
    },
    linesScrollArea = {
        width = 490,
        height = 725,
    },
    lineSettingsScrollArea = {
        width = 690,
        height = 725,
    },
    lineSettingsTable = {
        columns = {100, 550}
    },
    lineSettingsInternalTable = {
        columns = {20, 150, 320}
    },
    lineSettingsDropDownList = {
        width = 350,
        height = 120,
    },
    shippingContractsScrollArea = {
        width = 490,
        height = 250,
    },    
    shippingContractSettingsTable = {
        columns = {100, 550}
    },
    shippingContractSettingsInternalTable = {
        columns = {150, 340}
    },
    shippingContractIndustryDropDownList = {
        width = 350,
        height = 200,
    },
    cargoGroupsScrollArea = {
        width = 490,
        height = 350,
    },
    cargoGroupSettingsTable = {
        columns = {100, 550}
    },
    cargoGroupSettingsInternalTable = {
        columns = {150, 340}
    },
    cargoGroupDropDownList = {
        width = 350,
        height = 240,
    },
    -- cargoGroupIndustryDropDownList = {
    --     width = 350,
    --     height = 240,
    -- },
    -- cargoGroupShippingContractDropDownList = {
    --     width = 350,
    --     height = 240,
    -- },
    -- cargoGroupCargoGroupDropDownList = {
    --     width = 350,
    --     height = 240,
    -- },
    cargoGroupMembersScrollArea = {
        width = 490,
        height = 200,
    },
    globalSettingsTable = {
        columns = {590, 590}
    },
}

-- drop down entries
local dropDownEntries = {}

function asrGui.getState()
    return asrState
end

function asrGui.setState(state)
    asrState = state
end

local function log(message) 

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.GUI_DEBUG] then
        print(message)
    end
end
local function sendEngineCommand(command, params)

    -- log("gui: sending command " .. command)
    if command ~= nil then
        if params == nil then params = {} end 
        table.insert(asrEngineMessageQueue, {
            id = command,
            params = params})
    end
end

local function getNewId() 
    sendEngineCommand("asrIncreaseLastId", {})
    return asrState[asrEnum.STATUS][asrEnum.status.LAST_ID]
end

-- get the distance from the top of the table to reqeusted position
local function getDistance(table, row) 

    local totalHeight = 0
    log("gui: distance ")
    if asrGuiObjects[table] ~= nil then
        log("gui: table is not nil ")
        for i=0, row do
            totalHeight = totalHeight + asrGuiObjects[table]:getRowHeight(i)
        end
    end
    log("gui: distance height: " .. totalHeight)
    return totalHeight
end

-- generate drop down list entries
local function showDropDownList(listName, entries, nameSort)

    log("gui: show industry list drop down")
    local list = asrGuiObjects[listName]
    list:clear(false)
    dropDownEntries = {}
    list:setVisible(true, false)

    list:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions[listName].width, asrGuiDimensions[listName].height))
    list:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions[listName].width, asrGuiDimensions[listName].height))

    if type(entries) ~= "table" then
        entries = {}
    end
    if #entries == 0 then
        table.insert(entries, 1, {
            text = "      --- No entries ---         "
        })
    end
    if nameSort then 
        table.sort(entries, function (a, b) 
            if a.text == b.text then
                return a.icon2Tip > b.icon2Tip
            else
                return a.text < b.text
            end
        end)
    else
        table.sort(entries, function (a, b) 
            if a.icon2Tip == b.icon2Tip then
                return a.text < b.text
            elseif a.icon2Tip == nil then
                return true
            elseif b.icon2Tip == nil then
                return false
            else
                return a.icon2Tip > b.icon2Tip
            end
        end)
    end

    for idx, entry in pairs(entries) do 
        if entry.value then
            dropDownEntries[idx] = entry.value
        end
        local label, icon, icon2, icon3
        if entry.text ~= nil then
            local labelText = entry.text
            local labelToolTip
            if #labelText > 40 then
                labelText = string.sub(entry.text, 0, 40) .. " ..."
                labelToolTip = entry.text
            end
            label = api.gui.comp.TextView.new(labelText)
            if labelToolTip then
                label:setTooltip(labelToolTip)           
            end
        end
        if entry.icon ~= nil then 
            icon = api.gui.comp.ImageView.new(entry.icon)
            icon:setMaximumSize(api.gui.util.Size.new(18, 18))
            if entry.iconTip ~= nil then
                icon:setTooltip(entry.iconTip)
            end
        else
            icon = api.gui.comp.ImageView.new("ui/empty15.tga")
            icon:setMaximumSize(api.gui.util.Size.new(15, 15))
        end
        if entry.icon2 ~= nil then 
            icon2 = api.gui.comp.ImageView.new(entry.icon2)
            icon2:setMaximumSize(api.gui.util.Size.new(15, 15))
            if entry.icon2Tip ~= nil then
                icon2:setTooltip(entry.icon2Tip)
            end
        else
            icon2 = api.gui.comp.ImageView.new("ui/empty15.tga")
            icon2:setMaximumSize(api.gui.util.Size.new(15, 15))
        end

        if entry.icon3 ~= nil then 
            icon3 = api.gui.comp.ImageView.new(entry.icon3)
            icon3:setMaximumSize(api.gui.util.Size.new(15, 15))
        else
            icon3 = api.gui.comp.ImageView.new("ui/empty15.tga")
            icon3:setMaximumSize(api.gui.util.Size.new(15, 15))
        end
 
        local lineLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
        lineLayout:addItem(icon2)
        lineLayout:addItem(icon)
        lineLayout:addItem(label)
        if entry.icon3 ~= nil then 
            lineLayout:addItem(icon3)        
        end
        local lineWrapper =  api.gui.comp.Component.new("asr.tableLine")
        lineWrapper:setLayout(lineLayout)
        lineWrapper:setTransparent(false)
        list:addItem(lineWrapper)
    end

    -- log("gui: drop down content")
    -- asrHelper.tprint(dropDownEntries)
    return list
end

-- generate a button with icons
local function createIndustryButtonLayout(name, cargoId, kind, type)

    local industryButtonText = "      --- Select ---         "
    local industryButtonIcon
    local industryButtonIcon2
    local industryButtonIcon3

    if name then 
        industryButtonText = name
    end

    if cargoId ~= nil then
        industryButtonIcon = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(cargoId)]) .. "@2x.tga")
        industryButtonIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
    end

    if kind ~= nil then
        if kind == asrEnum.industry.SUPPLIER then 
            industryButtonIcon2 = api.gui.comp.ImageView.new("ui/icons/game-menu/load_game@2x.tga")
            industryButtonIcon2:setMaximumSize(api.gui.util.Size.new(13, 13))
        elseif kind == asrEnum.industry.CONSUMER then
            industryButtonIcon2 = api.gui.comp.ImageView.new("ui/icons/game-menu/save_game@2x.tga")
            industryButtonIcon2:setMaximumSize(api.gui.util.Size.new(13, 13))
        elseif kind == "shippingContract" then
            industryButtonIcon2 = api.gui.comp.ImageView.new("ui/icons/game-menu/configure_line@2x.tga")
            industryButtonIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
        elseif kind == "cargoGroup" then
            industryButtonIcon2 = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
            industryButtonIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
        end            
    end

    if type ~= nil then 
        if  type == "town" then
            industryButtonIcon3 = api.gui.comp.ImageView.new("ui/ui/button/medium/towns@2x.tga")
            industryButtonIcon3:setMaximumSize(api.gui.util.Size.new(15, 15))
        end
    end
    
    local industryButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
    if industryButtonIcon2 ~= nil and name then
        industryButtonLayout:addItem(industryButtonIcon2)
    end
    if industryButtonIcon ~= nil then
        industryButtonLayout:addItem(industryButtonIcon)
    end
    local industryButtonToolTip
    if #industryButtonText > 29 then
        industryButtonToolTip = industryButtonText
        industryButtonText = string.sub(industryButtonText, 0, 29) .. " ..."
        
    end
    local industryButtonLabel = api.gui.comp.TextView.new(industryButtonText)
    if industryButtonToolTip then
        industryButtonLabel:setTooltip(industryButtonToolTip)
    end
    industryButtonLayout:addItem(industryButtonLabel)
    if industryButtonIcon3 then 
        industryButtonLayout:addItem(industryButtonIcon3)
    end

    return industryButtonLayout
end

-- enable/disable groups of controls
local function setToggle(toggleGroup, selectedRadio, suffix, checked)

    local radioList = toggleGroups[toggleGroup]
    if checked then
        for _, radioName in pairs(radioList) do
            local radio = api.gui.util.getById("asr." .. toggleGroup .. radioName .. "-" .. suffix)
            local input = api.gui.util.getById("asr." .. toggleGroup .. radioName .. "Input-" .. suffix)
            if radioName == selectedRadio then
                radio:setSelected(true, false)
                if input ~= nil then 
                    input:setEnabled(true)
                    input:setVisible(true, false)
                end
            else
                radio:setSelected(false, false)
                if input ~= nil then 
                    input:setEnabled(false)
                    input:setVisible(false, false)
                end
            end
        end
    end
end

-- settings for each line - complete rebuild
local function rebuildLineSettingsLayout() 

    -- log("gui: rebuildLineSettingsLayout")
    local lineSettingsScrollAreaLayout = asrGuiObjects.lineSettingsScrollAreaLayout
    local lineSettingsTable = asrGuiObjects.lineSettingsTable --  api.gui.util.getById("asr.lineSettingsTable")
    local lineSettingsColourLineTable = asrGuiObjects.lineSettingsColourLineTable
    local lineSettingsDropDownList = asrGuiObjects.lineSettingsDropDownList

    local lineId = asrGuiState.selectedLine

    -- create all the GUI elements 
    if lineSettingsTable == nil then
        lineSettingsTable = api.gui.comp.Table.new(2, 'NONE')
        lineSettingsTable:setId("asr.lineSettingsTable")
        lineSettingsTable:setColWidth(0,asrGuiDimensions.lineSettingsTable.columns[1])
        lineSettingsTable:setColWidth(1,asrGuiDimensions.lineSettingsTable.columns[2])
        lineSettingsTable:setGravity(0, 0)
        lineSettingsScrollAreaLayout:addItem(lineSettingsTable, api.gui.util.Rect.new(0,0,590,500))
        asrGuiObjects.lineSettingsTable = lineSettingsTable
    else
        if asrGuiState.lineSettingsTableBuilt == false and asrGuiState.settingsTableInitalising == true  then 
            lineSettingsTable:deleteAll() 
            lineSettingsTable:addRow({api.gui.comp.TextView.new(""), api.gui.comp.TextView.new("Please wait, collecting line information")})
        end
    end

    if lineSettingsColourLineTable == nil then
        lineSettingsColourLineTable = api.gui.comp.Table.new(1, 'NONE')
        lineSettingsColourLineTable:setColWidth(0,asrGuiDimensions.lineSettingsScrollArea.width)
        lineSettingsColourLineTable:setGravity(0, 0)
        asrGuiObjects.lineSettingsColourLineTable = lineSettingsColourLineTable
        lineSettingsScrollAreaLayout:addItem(lineSettingsColourLineTable, api.gui.util.Rect.new(0, 30, asrGuiDimensions.lineSettingsScrollArea.width,10))
    else
        if asrGuiState.lineSettingsTableBuilt == false then lineSettingsColourLineTable:deleteAll() end
    end


    if lineSettingsDropDownList == nil then
        lineSettingsDropDownList = api.gui.comp.List.new(false, 1 ,false)
        lineSettingsDropDownList:setGravity(0,0)
        lineSettingsDropDownList:setVisible(false,false)
        lineSettingsDropDownList:setStyleClassList({"asrDropList"})        
        asrGuiObjects.lineSettingsDropDownList = lineSettingsDropDownList
        lineSettingsScrollAreaLayout:addItem(lineSettingsDropDownList, api.gui.util.Rect.new(0,0,100,100))  -- dimesntions don't seem to matter here? 
        lineSettingsDropDownList:onSelect(function (row) 
            log("selected value:" .. row)
            if dropDownEntries[row + 1] ~= nil then
                log("found values: ")
                -- asrHelper.tprint(dropDownEntries[row + 1])
                local stationConfig = {}
                stationConfig[asrEnum.station.SELECTOR] = asrGuiState.selectedStation
                for propertyId, propertyValue in pairs(dropDownEntries[row + 1]) do
                    stationConfig[propertyId] = propertyValue
                end
                sendEngineCommand("asrUpdateStation", { lineId = asrGuiState.selectedLine, stopSequence = asrGuiState.selectedStopSequence, stationId = asrGuiState.selectedStation, config = stationConfig })
            else
                -- local stationConfig = {}
                -- stationConfig[asrEnum.station.SELECTOR] = asrGuiState.selectedStation
                -- sendEngineCommand("asrUpdateStation", { lineId = asrGuiState.selectedLine, stopSequence = asrGuiState.selectedStopSequence, stationId = asrGuiState.selectedStation, config  = stationConfig })
            end
            lineSettingsDropDownList:setVisible(false, false)
        end)
    end

    if lineId ~= nil and asrState[asrEnum.LINES][tostring(lineId)] ~= nil and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.UPDATE_TIMESTAMP] ~= nil  then

        if not asrGuiState.lineSettingsTableBuilt then
            
            log("gui: rebuildLineSettingsLayout, full build")
            if asrGuiState.settingsTableInitalising then
                log("gui: rebuildLineSettingsLayout, table was initialising")
                lineSettingsTable:deleteAll()
                asrGuiState.settingsTableInitalising = false
            end

            local lineNameLabel = api.gui.comp.TextView.new(i18Strings.line_name)
            
            local lineNameValue = api.gui.comp.TextView.new("")
            if asrGuiState.selectedLine ~= nil and asrState[asrEnum.LINES][tostring(lineId)] ~= nil then
                lineNameValue:setText(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME])
            end
            lineNameValue:setId("asr.settingsLineName")
            lineSettingsTable:addRow({lineNameLabel, lineNameValue})
        
            lineSettingsTable:addRow({api.gui.comp.TextView.new(""), api.gui.comp.TextView.new("")})

            local lineText = " "
            for i=1,10 do
                lineText = lineText .. lineText
            end
            local col0text = api.gui.comp.TextView.new(lineText)
            col0text:setStyleClassList({"asrBackgroundLineColour-" .. asrGuiHelper.getLineColour(tonumber(asrGuiState.selectedLine))})
            lineSettingsColourLineTable:addRow({col0text})
            lineSettingsScrollAreaLayout:setPosition(lineSettingsScrollAreaLayout:getIndex(lineSettingsColourLineTable),0, 45)

            local trainLengthTable = api.gui.comp.Table.new(3, 'NONE')
            trainLengthTable:setGravity(0,0)
            trainLengthTable:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsTable.columns[2] - 1 , 50))
            trainLengthTable:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsTable.columns[2] - 1 , 50))
            trainLengthTable:setId("asr.trainLengthTable-" .. lineId)
            trainLengthTable:setColWidth(0, asrGuiDimensions.lineSettingsInternalTable.columns[1])
            trainLengthTable:setColWidth(1, asrGuiDimensions.lineSettingsInternalTable.columns[2])
            trainLengthTable:setColWidth(2, asrGuiDimensions.lineSettingsInternalTable.columns[3])


            -- local trainLengthAutomaticCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
            -- trainLengthAutomaticCheckBox:setId("asr.trainLengthAutomatic-" .. lineId)
            -- local trainLengthAutomaticLabel = api.gui.comp.TextView.new("Automatic")

            local trainLengthGlobalCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
            trainLengthGlobalCheckBox:setId("asr.trainLengthGlobal-" .. lineId)
            local trainLengthGlobalLabel = api.gui.comp.TextView.new(i18Strings.default)

            local trainLengthManualCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
            trainLengthManualCheckBox:setId("asr.trainLengthManual-" .. lineId)
            local trainLengthManualLabel = api.gui.comp.TextView.new(i18Strings.manual)

            local trainLengthManualLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
            local trainLengthManualWrapper = api.gui.comp.Component.new("asr.trainLengthWrapper-" .. lineId)
            trainLengthManualWrapper:setLayout(trainLengthManualLayout)

            local trainLengthManualTextInput = api.gui.comp.TextInputField.new("000")
            trainLengthManualTextInput:setId("asr.trainLengthManualInput-" .. lineId)
            trainLengthManualTextInput:setMaxLength(3)
            if asrState[asrEnum.LINES][tostring(lineId)] and 
                asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and 
                asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.line.SETTINGS] and
                asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH] then
                trainLengthManualTextInput:setText(tostring(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]), false) 
            end

            trainLengthManualTextInput:onFocusChange(function (hasFocus) 
                if not hasFocus then
                    local amountValue = trainLengthManualTextInput:getText()
                    local amountValueNum = tonumber(amountValue)
                    if amountValueNum == nil then
                        trainLengthManualTextInput:setText("", false)
                        return
                    end
                    if amountValueNum ~= math.floor(amountValueNum) then
                        trainLengthManualTextInput:setText("", false)
                        return
                    end
                    -- send the value to the engine
                    sendEngineCommand("asrLineSettings", { lineId = lineId, property = asrEnum.lineSettngs.TRAIN_LENGTH, value = amountValueNum})
                end
            end)
            trainLengthManualTextInput:onEnter(function () 
                local amountValue = trainLengthManualTextInput:getText()
                local amountValueNum = tonumber(amountValue)
                if amountValueNum == nil then
                    trainLengthManualTextInput:setText("", false)
                    return
                end
                if amountValueNum ~= math.floor(amountValueNum) then
                    trainLengthManualTextInput:setText("", false)
                    return
                end
                -- send the value to the engine
                sendEngineCommand("asrLineSettings", { lineId = lineId, property = asrEnum.lineSettngs.TRAIN_LENGTH, value = amountValueNum})
            end)
            trainLengthManualTextInput:onCancel(function () 
                if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH] then
                    trainLengthManualTextInput:setText(tostring(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]), false) 
                end    
            end)
            -- trainLengthTable:addRow({trainLengthAutomaticCheckBox, trainLengthAutomaticLabel, api.gui.comp.TextView.new("000m")})
            local globalTrainLength = asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]
            local trainLengthGlobalValue = api.gui.comp.TextView.new("")
            trainLengthGlobalValue:setId("asr.trainLengthGLobalValue-" .. lineId)
            trainLengthGlobalValue:setText(tostring(globalTrainLength) .. " m")

            local trainLengthManualUnit = api.gui.comp.TextView.new("m")
            trainLengthManualUnit:setId("asr.trainLengthManualUnit-" .. lineId)

            trainLengthManualLayout:addItem(trainLengthManualTextInput)
            trainLengthManualLayout:addItem(trainLengthManualUnit)
            trainLengthTable:addRow({trainLengthGlobalCheckBox, trainLengthGlobalLabel, trainLengthGlobalValue})
            trainLengthTable:addRow({trainLengthManualCheckBox, trainLengthManualLabel, trainLengthManualWrapper })

            -- trainLengthAutomaticCheckBox:onToggle(function (checked) 
            --     setToggle("trainLength", "Automatic", lineId, checked)
            --     asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)
            -- end)
            trainLengthGlobalCheckBox:onToggle(function (checked) 
                setToggle("trainLength", "Global", lineId, checked)
                sendEngineCommand("asrLineSettings", { lineId = lineId, property = asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR, value = "global"})
                asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)
                if checked then
                    trainLengthManualUnit:setVisible(false, false)
                else
                    trainLengthManualUnit:setVisible(true, false)
                end

            end)
            trainLengthManualCheckBox:onToggle(function (checked)
                setToggle("trainLength", "Manual", lineId, checked)
                sendEngineCommand("asrLineSettings", { lineId = lineId, property = asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR, value = "manual"})
                asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)
                if checked then
                    trainLengthManualUnit:setVisible(true, false)
                else
                    trainLengthManualUnit:setVisible(false, false)
                end
            end)

            if not asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] or (asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR] ~= "manual")  then  -- catch all other cases
                trainLengthGlobalCheckBox:setSelected(true, false)
                trainLengthManualTextInput:setEnabled(false, false)
                trainLengthManualTextInput:setVisible(false, false)
                trainLengthManualUnit:setVisible(false, false)
            end
            if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR] == "manual"  then
                trainLengthManualCheckBox:setSelected(true, false)
                trainLengthManualTextInput:setEnabled(true, false)
                trainLengthManualTextInput:setVisible(true, false)
                trainLengthManualUnit:setVisible(true, false)
            end
            if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS] and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]  then
                trainLengthManualTextInput:setText(tostring(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.SETTINGS][asrEnum.lineSettngs.TRAIN_LENGTH]), false)
            end
            local trainLegthLabel = api.gui.comp.TextView.new(i18Strings.train_length)
            trainLegthLabel:setGravity(0,0)
            lineSettingsTable:addRow({trainLegthLabel, trainLengthTable})


            lineSettingsTable:addRow({api.gui.comp.TextView.new(""), api.gui.comp.TextView.new("")})
            lineSettingsTable:addRow({api.gui.comp.TextView.new(i18Strings.stations), api.gui.comp.TextView.new("")})

            -- loop through the stations and generate the setup
            if asrState[asrEnum.LINES][tostring(lineId)] ~= nil and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] ~= nil then 
                for stopSequence, station in pairs(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                    local stationName = ""
                    if station[asrEnum.station.STATION_GROUP_ID] ~=nil and api.engine.entityExists(station[asrEnum.station.STATION_GROUP_ID]) then
                        stationName = api.engine.getComponent(station[asrEnum.station.STATION_GROUP_ID], api.type.ComponentType.NAME).name
                    else
                        log("gui: getComponent can't find station name")
                    end

                    -- used to display the currently selected amount, rest of code at the end of the loop
                    local currentAmountWrapper = api.gui.comp.Component.new("asr.amountWrapper")

                    local stationNameLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                    local stationNameWrapper = api.gui.comp.Component.new("asr.stationNameWrapper-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    stationNameWrapper:setLayout(stationNameLayout)
                    local stationNameIcon = api.gui.comp.ImageView.new("ui/icons/windows/station_pool@2x.tga")
                    stationNameIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
                    stationNameLayout:addItem(stationNameIcon)
                    stationNameLayout:addItem(api.gui.comp.TextView.new(stationName))

                    local amountSelectionTable = api.gui.comp.Table.new(3, 'NONE')
                    amountSelectionTable:setGravity(0,0)
                    amountSelectionTable:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsTable.columns[2], 150))
                    amountSelectionTable:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsTable.columns[2], 150))
        
                    -- amountSelectionTable:setMinimumSize(api.gui.util.Size.new(580, 104))
                    -- amountSelectionTable:setMaximumSize(api.gui.util.Size.new(580, 104))
                    amountSelectionTable:setId("asr.amountSelectionTable-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    amountSelectionTable:setColWidth(0, asrGuiDimensions.lineSettingsInternalTable.columns[1])
                    amountSelectionTable:setColWidth(1, asrGuiDimensions.lineSettingsInternalTable.columns[2])
                    amountSelectionTable:setColWidth(2, asrGuiDimensions.lineSettingsInternalTable.columns[3])
                    
                    local stationEnabled = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
                    stationEnabled:setId("asr.stationEnabled-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    stationEnabled:setStyleClassList({"asrStationCheckbox"})
                    if station[asrEnum.station.ENABLED] == true then
                        stationEnabled:setSelected(true, false)
                        amountSelectionTable:setVisible(true, false)
                        currentAmountWrapper:setVisible(true, false)
                    else
                        stationEnabled:setSelected(false, false)
                        amountSelectionTable:setVisible(false, false)
                        currentAmountWrapper:setVisible(false, false)
                    end
                    -- stationEnabled:setStyleClassList({"asrCheckbox"})
                    stationEnabled:onToggle(function (checked)

                        if checked then
                            log("checkbox for station " .. station[asrEnum.station.STATION_ID] .. " set to true")
                            local stationConfig = {
                                [asrEnum.station.ENABLED] = true
                            }
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = stationConfig})
                            amountSelectionTable:setVisible(true, false)
                            currentAmountWrapper:setVisible(true, false)
                        else
                            log("checkbox for station " .. station[asrEnum.station.STATION_ID] .. " set to false")
                            local stationConfig = {}
                            stationConfig[asrEnum.station.ENABLED] = false
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = stationConfig})
                            amountSelectionTable:setVisible(false, false)
                            currentAmountWrapper:setVisible(false, false)
                        end
                        asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)

                    end)

                    lineSettingsTable:addRow({stationEnabled, stationNameWrapper})


                    -- amount selection elements
                    local lineSettingsCurrentRowCount = lineSettingsTable:getNumRows()

                    local amountSelectionIndustryShippingCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
                    amountSelectionIndustryShippingCheckBox:setId("asr.amountSelectionIndustryShipping-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)

                    local amountSelectionIndustryShippingLabel = api.gui.comp.TextView.new(i18Strings.industry)
                    local amountSelectionIndustryShippingButtonLayout = createIndustryButtonLayout(
                        station[asrEnum.station.INDUSTRY_ID] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])][asrEnum.industry.NAME] or nil,
                        station[asrEnum.station.INDUSTRY_CARGO_ID],
                        station[asrEnum.station.INDUSTRY_KIND], 
                        station[asrEnum.station.INDUSTRY_ID] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])][asrEnum.industry.TYPE] )
        
                    local amountSelectionIndustryShippingButton = api.gui.comp.Button.new(amountSelectionIndustryShippingButtonLayout, false)
                    amountSelectionIndustryShippingButton:setId("asr.amountSelectionIndustryShippingInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    amountSelectionTable:addRow({amountSelectionIndustryShippingCheckBox, amountSelectionIndustryShippingLabel, amountSelectionIndustryShippingButton})
                
                    if station[asrEnum.station.SELECTOR] ~= nil and station[asrEnum.station.SELECTOR] == "industryShipping" then
                        amountSelectionIndustryShippingCheckBox:setSelected(true, false)
                        amountSelectionIndustryShippingButton:setEnabled(true)
                        amountSelectionIndustryShippingButton:setVisible(true, false)
                    else
                        amountSelectionIndustryShippingCheckBox:setSelected(false, false)
                        amountSelectionIndustryShippingButton:setEnabled(false)
                        amountSelectionIndustryShippingButton:setVisible(false, false)
                    end

                    amountSelectionIndustryShippingButton:onClick(function ()

                        local list = asrGuiObjects.lineSettingsDropDownList
                        if list:isVisible() then
                            list:setVisible(false, false)
                        else

                            local settingsTabletHeight = getDistance("lineSettingsTable", lineSettingsCurrentRowCount - 1)
                            lineSettingsScrollAreaLayout:setPosition(lineSettingsScrollAreaLayout:getIndex(lineSettingsDropDownList), lineSettingsTable:getColWidth(0) + amountSelectionTable:getColWidth(0) + amountSelectionTable:getColWidth(1), settingsTabletHeight + amountSelectionTable:getRowHeight(0))
                            local stationIndustries = {}
                            if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES] ~= nil then 
                                for industryId, industry in pairs(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.INDUSTRIES]) do
                                    if asrState[asrEnum.INDUSTRIES] and asrState[asrEnum.INDUSTRIES][tostring(industryId)] ~= nil then 
                                        if asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.SUPPLIER] ~= nil then
                                            for cargoId, amount in pairs(asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.SUPPLIER]) do
                                                if station[asrEnum.station.STATION_ID] == industry[asrEnum.lineIndustry.STATION_ID] then
                                                    table.insert(stationIndustries, {
                                                        cargoId = cargoId,
                                                        industryId = industryId,
                                                        industryName = industry[asrEnum.lineIndustry.NAME],
                                                        industryKind = "supplier",
                                                        industryType = industry[asrEnum.lineIndustry.TYPE],
                                                    })
                                                end
                                            end
                                        end
                                        if asrState[asrEnum.INDUSTRIES] and asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.CONSUMER] ~= nil then
                                            for cargoId, amount in pairs(asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.CONSUMER]) do
                                                table.insert(stationIndustries, {
                                                    cargoId = cargoId,
                                                    industryId = industryId,
                                                    industryName = industry[asrEnum.lineIndustry.NAME],
                                                    industryKind = "consumer",
                                                    industryType = industry[asrEnum.lineIndustry.TYPE],
                                                })
                                            end
                                        end
                                    end
                                end
                            end
                            -- normalise the list
                            local dropDownEntries = {}
                            table.insert(dropDownEntries, {
                                text = "--- Clear ---",
                                icon2Tip = "supplier",
                                value = {                                
                                    [asrEnum.station.INDUSTRY_ID] = asrEnum.value.DELETE,
                                    [asrEnum.station.SELECTOR] = "industryShipping"
                                }
                            })
                            for _,industry in pairs(stationIndustries) do 
                                local selected = false
                                if station[asrEnum.station.INDUSTRY_ID] ~= nil and station[asrEnum.station.INDUSTRY_CARGO_ID] ~= nil and
                                station[asrEnum.station.INDUSTRY_ID] == industry.industryId and station[asrEnum.station.INDUSTRY_CARGO_ID] == industry.cargoId then
                                    selected = true
                                end
                                local industryKindIcon
                                if industry.industryKind == "supplier" then
                                    industryKindIcon = "ui/icons/game-menu/load_game@2x.tga"
                                elseif industry.industryKind == "consumer" then
                                    industryKindIcon = "ui/icons/game-menu/save_game@2x.tga"
                                end
                                local industryTypeIcon
                                if industry.industryType == "town" then
                                    industryTypeIcon = "ui/ui/button/medium/towns@2x.tga"
                                -- elseif industry.industryType == "industry" then
                                --     industryTypeIcon = "ui/ui/button/medium/industries@2x.tga"
                                end
                                table.insert(dropDownEntries, {
                                    text = industry.industryName,
                                    textTip = industry.industryKind, 
                                    icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(industry.cargoId)]) .. "@2x.tga",
                                    iconTip = string.lower(cargoTypes[tonumber(industry.cargoId)]),
                                    icon2 = industryKindIcon,
                                    icon2Tip = industry.industryKind,
                                    icon3 = industryTypeIcon,
                                    selected = selected,
                                    value = {
                                        [asrEnum.station.INDUSTRY_ID] = industry.industryId,
                                        [asrEnum.station.INDUSTRY_KIND] = industry.industryKind == "supplier" and asrEnum.industry.SUPPLIER or asrEnum.industry.CONSUMER,
                                        [asrEnum.station.INDUSTRY_CARGO_ID] = industry.cargoId,
                                        [asrEnum.station.SELECTOR] = "industryShipping"
                                    }
                                })
                            end
                            asrGuiState.selectedStopSequence = stopSequence
                            asrGuiState.selectedStation = station[asrEnum.station.STATION_ID]
                            showDropDownList("lineSettingsDropDownList", dropDownEntries)
                        end
                    end)

                    local amountSelectionShippingContractCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
                    amountSelectionShippingContractCheckBox:setId("asr.amountSelectionShippingContract-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionShippingContractLabel = api.gui.comp.TextView.new(i18Strings.shipping_contract)

                    local amountSelectionShippingContractButtonLayout = createIndustryButtonLayout(
                        station[asrEnum.station.SHIPPING_CONTRACT_ID] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(station[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME] or nil,
                        station[asrEnum.station.SHIPPING_CONTRACT_CARGO_ID],
                        "shippingContract", nil)
        
                    local amountSelectionShippingContractButton = api.gui.comp.Button.new(amountSelectionShippingContractButtonLayout, false)
                    amountSelectionShippingContractButton:setId("asr.amountSelectionShippingContractInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    amountSelectionTable:addRow({amountSelectionShippingContractCheckBox ,amountSelectionShippingContractLabel, amountSelectionShippingContractButton})
                    if station[asrEnum.station.SELECTOR] ~= nil and station[asrEnum.station.SELECTOR] == "shippingContract" then
                        amountSelectionShippingContractCheckBox:setSelected(true, false)
                        amountSelectionShippingContractButton:setEnabled(true)
                        amountSelectionShippingContractButton:setVisible(true, false)
                    else
                        amountSelectionShippingContractCheckBox:setSelected(false, false)
                        amountSelectionShippingContractButton:setEnabled(false)
                        amountSelectionShippingContractButton:setVisible(false, false)
                    end
                    amountSelectionShippingContractButton:onClick(function ()

                        local list = asrGuiObjects.lineSettingsDropDownList
                        if list:isVisible() then
                            list:setVisible(false, false)
                        else

                            local settingsTabletHeight = getDistance("lineSettingsTable", lineSettingsCurrentRowCount - 1)
                            lineSettingsScrollAreaLayout:setPosition(lineSettingsScrollAreaLayout:getIndex(lineSettingsDropDownList), lineSettingsTable:getColWidth(0) + amountSelectionTable:getColWidth(0) + amountSelectionTable:getColWidth(1), settingsTabletHeight + amountSelectionTable:getRowHeight(0) + amountSelectionTable:getRowHeight(1))
                            local shippingContracts = {}

                            if asrState[asrEnum.SHIPPING_CONTRACTS] then
                                for shippingContractId, shippingContractDetails in pairs(asrState[asrEnum.SHIPPING_CONTRACTS]) do
                                    table.insert(shippingContracts, {
                                        shippingContractId = shippingContractId,
                                        cargoId = shippingContractDetails[asrEnum.shippingContract.CARGO_ID],
                                        shippingContractName = shippingContractDetails[asrEnum.shippingContract.NAME]
                                        
                                    })
                                end
                            end
                            -- normalise the list
                            log("gui: shipping contracts")
                            local dropDownEntries = {}
                            table.insert(dropDownEntries, {
                                text = "--- Clear ---",
                                icon2Tip = "",
                                value = {                                
                                    [asrEnum.station.SHIPPING_CONTRACT_ID] = asrEnum.value.DELETE,
                                    [asrEnum.station.SELECTOR] = "shippingContract"
                                }
                            })
                            for _,shippingContract in pairs(shippingContracts) do 
        
                                table.insert(dropDownEntries, {
                                    text = shippingContract.shippingContractName,
                                    icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(shippingContract.cargoId)]) .. "@2x.tga",
                                    iconTip = string.lower(cargoTypes[tonumber(shippingContract.cargoId)]),
                                    icon2 = "ui/icons/game-menu/configure_line@2x.tga",
                                    icon2Tip = "",
                                    value = {

                                        [asrEnum.station.SHIPPING_CONTRACT_ID] = shippingContract.shippingContractId,
                                        [asrEnum.station.SHIPPING_CONTRACT_CARGO_ID] = shippingContract.cargoId,
                                        [asrEnum.station.SELECTOR] = "shippingContract",

                                }
                                })
                            end
                            asrGuiState.selectedStopSequence = stopSequence
                            asrGuiState.selectedStation = station[asrEnum.station.STATION_ID]
                            showDropDownList("lineSettingsDropDownList", dropDownEntries)
                        end
                    end)

                    local amountSelectionCargoGroupCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
                    amountSelectionCargoGroupCheckBox:setId("asr.amountSelectionCargoGroup-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionCargoGroupLabel = api.gui.comp.TextView.new(i18Strings.cargo_group)
                    local amountSelectionCargoGroupButtonLayout = createIndustryButtonLayout(
                        station[asrEnum.station.CARGO_GROUP_ID] and asrState[asrEnum.CARGO_GROUPS][tostring(station[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME] or nil,
                        nil,
                        "cargoGroup", nil)

                    local amountSelectionCargoGroupButton = api.gui.comp.Button.new(amountSelectionCargoGroupButtonLayout, false)
                    amountSelectionCargoGroupButton:setId("asr.amountSelectionCargoGroupInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    amountSelectionTable:addRow({amountSelectionCargoGroupCheckBox, amountSelectionCargoGroupLabel, amountSelectionCargoGroupButton})
                    if station[asrEnum.station.SELECTOR] ~= nil and station[asrEnum.station.SELECTOR] == "cargoGroup"  then
                        amountSelectionCargoGroupCheckBox:setSelected(true, false)
                        amountSelectionCargoGroupButton:setEnabled(true)
                        amountSelectionCargoGroupButton:setVisible(true, false)
                    else
                        amountSelectionCargoGroupCheckBox:setSelected(false, false)
                        amountSelectionCargoGroupButton:setEnabled(false)
                        amountSelectionCargoGroupButton:setVisible(false, false)
                    end

                    amountSelectionCargoGroupButton:onClick(function ()

                        local list = asrGuiObjects.lineSettingsDropDownList
                        if list:isVisible() then
                            list:setVisible(false, false)
                        else

                            local settingsTabletHeight = getDistance("lineSettingsTable", lineSettingsCurrentRowCount - 1)
                            lineSettingsScrollAreaLayout:setPosition(lineSettingsScrollAreaLayout:getIndex(lineSettingsDropDownList), lineSettingsTable:getColWidth(0) + amountSelectionTable:getColWidth(0) + amountSelectionTable:getColWidth(1), settingsTabletHeight + amountSelectionTable:getRowHeight(0) + amountSelectionTable:getRowHeight(1) + amountSelectionTable:getRowHeight(2))

                            local cargoGroups = {}

                            if asrState[asrEnum.CARGO_GROUPS] then
                                for cargoGroupId, cargoGroupDetails in pairs(asrState[asrEnum.CARGO_GROUPS]) do
                                    table.insert(cargoGroups, {
                                        cargoGroupName = cargoGroupDetails[asrEnum.cargoGroup.NAME],
                                        cargoGroupId = cargoGroupId
                                    })
                                end
                            end
                            -- normalise the list
                            log("gui: cargo groups")
                            local dropDownEntries = {}
                            table.insert(dropDownEntries, {
                                text = "--- Clear ---",
                                icon2Tip = "",
                                value = {                                
                                    [asrEnum.station.CARGO_GROUP_ID] = asrEnum.value.DELETE,
                                    [asrEnum.station.SELECTOR] = "cargoGroup"
                                }
                            })

                            for _,cargoGroup in pairs(cargoGroups) do 
                                table.insert(dropDownEntries, {
                                    text = cargoGroup.cargoGroupName,
                                    icon2 = "ui/icons/game-menu/cargo@2x.tga",
                                    iconTip = "",
                                    icon2Tip = "",
                                    value = {

                                        [asrEnum.station.CARGO_GROUP_ID] = cargoGroup.cargoGroupId,
                                        [asrEnum.station.SELECTOR] = "cargoGroup",
                                    }
                                })
                            end
        
                            asrGuiState.selectedStopSequence = stopSequence
                            asrGuiState.selectedStation = station[asrEnum.station.STATION_ID]
                            showDropDownList("lineSettingsDropDownList", dropDownEntries)
                        end
                    end)


                    local amountSelectionFixedAmountCheckBox = api.gui.comp.CheckBox.new("", "ui/design/components/checkbox_small_invalid@2x.tga", "ui/design/components/checkbox_small_valid@2x.tga")
                    amountSelectionFixedAmountCheckBox:setId("asr.amountSelectionFixedAmount-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionFixedAmountLabel = api.gui.comp.TextView.new(i18Strings.fixed_amount)
                    local amountSelectionFixedAmountTextInput = api.gui.comp.TextInputField.new("00000")
                    if station[asrEnum.station.FIXED_AMOUNT_VALUE] ~= nil then
                        amountSelectionFixedAmountTextInput:setText(tostring(station[asrEnum.station.FIXED_AMOUNT_VALUE]), false)
                    end
                    amountSelectionFixedAmountTextInput:setMaxLength(5)
                    amountSelectionFixedAmountTextInput:setMinimumSize(api.gui.util.Size.new(40, 18))
                    amountSelectionFixedAmountTextInput:setMaximumSize(api.gui.util.Size.new(40, 18))
                    amountSelectionFixedAmountTextInput:setId("asr.amountSelectionFixedAmountInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    amountSelectionFixedAmountTextInput:onFocusChange(function (hasFocus) 
                        if not hasFocus then
                            local amountValue = amountSelectionFixedAmountTextInput:getText()
                            local amountValueNum = tonumber(amountValue)
                            if amountValueNum == nil then
                                amountSelectionFixedAmountTextInput:setText("", false)
                                sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = {[asrEnum.station.SELECTOR] = "" }}) 
                                return
                            end
                            if amountValueNum ~= math.floor(amountValueNum) then
                                amountSelectionFixedAmountTextInput:setText("", false)
                                sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = {[asrEnum.station.SELECTOR] = "" }}) 
                                return
                            end
                            -- send the value to the engine
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = { [asrEnum.station.FIXED_AMOUNT_VALUE] = amountValueNum}})
                        end
                    end)
                    amountSelectionFixedAmountTextInput:onEnter(function () 
                        local amountValue = amountSelectionFixedAmountTextInput:getText()
                        local amountValueNum = tonumber(amountValue)
                        if amountValueNum == nil then
                            amountSelectionFixedAmountTextInput:setText("", false)
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = {[asrEnum.station.SELECTOR] = "" }}) 
                            return
                        end
                        if amountValueNum ~= math.floor(amountValueNum) then
                            amountSelectionFixedAmountTextInput:setText("", false)
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = {[asrEnum.station.SELECTOR] = "" }}) 
                            return
                        end
                        -- send the value to the engine
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = { [asrEnum.station.FIXED_AMOUNT_VALUE] = amountValueNum}})
                    end)
                    amountSelectionFixedAmountTextInput:onCancel(function () 
                        if station[asrEnum.station.FIXED_AMOUNT_VALUE] ~= nil then
                            amountSelectionFixedAmountTextInput:setText(tostring(station[asrEnum.station.FIXED_AMOUNT_VALUE]), false)
                        end    
                    end)

                    amountSelectionTable:addRow({amountSelectionFixedAmountCheckBox, amountSelectionFixedAmountLabel, amountSelectionFixedAmountTextInput})
                    if station[asrEnum.station.SELECTOR] ~= nil and station[asrEnum.station.SELECTOR] == "fixedAmount"  then
                        amountSelectionFixedAmountCheckBox:setSelected(true, false)
                        amountSelectionFixedAmountTextInput:setEnabled(true)
                        amountSelectionFixedAmountTextInput:setVisible(true, false)
                    else
                        amountSelectionFixedAmountCheckBox:setSelected(false, false)
                        amountSelectionFixedAmountTextInput:setEnabled(false)
                        amountSelectionFixedAmountTextInput:setVisible(false, false)
                    end

                    -- waiting cargo pickup
                    local waitingCargoCheckBox = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
                    waitingCargoCheckBox:setId("asr.waitingCargoCheckbox-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    -- waitingCargoCheckBox:setStyleClassList({"asrStationCheckbox"})
                    local waitingCargoLabel = api.gui.comp.TextView.new(i18Strings.pickup_waiting)
                    waitingCargoLabel:setTooltip(i18Strings.pickup_waiting_tip)

                    local waitingCargoSelectorLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                    local waitingCargoSelectorWrapper = api.gui.comp.Component.new("asr.waitingCargoWrapper")
                    waitingCargoSelectorWrapper:setLayout(waitingCargoSelectorLayout)

                    local waitingCargoSelectorSlider = api.gui.comp.Slider.new(true)
                    waitingCargoSelectorSlider:setId("asr.waitingCargoSelectorSlider-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoSelectorValue = api.gui.comp.TextView.new("")
                    waitingCargoSelectorValue:setId("asr.waitingCargoSelectorValue-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    waitingCargoSelectorValue:setMinimumSize(api.gui.util.Size.new(35, 18))
                    waitingCargoSelectorValue:setMaximumSize(api.gui.util.Size.new(35, 18))
                    if station[asrEnum.station.WAITING_CARGO_VALUE] ~= nil then
                        waitingCargoSelectorSlider:setDefaultValue(station[asrEnum.station.WAITING_CARGO_VALUE]/10)
                        waitingCargoSelectorSlider:setValue(tonumber(station[asrEnum.station.WAITING_CARGO_VALUE])/10, false)
                        waitingCargoSelectorValue:setText(tostring(tonumber(station[asrEnum.station.WAITING_CARGO_VALUE]))  .. "%")
                    else
                        waitingCargoSelectorValue:setText("  0%")
                    end
                    waitingCargoSelectorSlider:setMaximum(10)
                    waitingCargoSelectorSlider:setMinimum(0)
                    -- waitingCargoSelectorSlider:setStep(10)
                    waitingCargoSelectorSlider:setMinimumSize(api.gui.util.Size.new(140, 18))
                    waitingCargoSelectorSlider:setMaximumSize(api.gui.util.Size.new(140, 18))
                    waitingCargoSelectorSlider:onValueChanged(function (value) 
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = { [asrEnum.station.WAITING_CARGO_VALUE] = tonumber(value) * 10}})                        
                        waitingCargoSelectorValue:setText(tostring(value * 10).."%")
                    end)

                    local waitingCargoBacklogOnlyCheckBox = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
                    waitingCargoBacklogOnlyCheckBox:setId("asr.waitingCargoBacklogOnlyCheckbox-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoBacklogOnlyLabel = api.gui.comp.TextView.new(i18Strings.pickup_waiting_backlog_label)
                    waitingCargoBacklogOnlyLabel:setId("asr.waitingCargoBacklogOnlyLabel-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    waitingCargoBacklogOnlyLabel:setTooltip(i18Strings.pickup_waiting_backlog_label_tip)
                    if station[asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] then 
                        waitingCargoBacklogOnlyCheckBox:setSelected(true, false)
                    else
                        waitingCargoBacklogOnlyCheckBox:setSelected(false, false)
                    end
                    waitingCargoBacklogOnlyCheckBox:onToggle(function (checked)
                        if checked then
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] = true  }})
                        else
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.WAITING_CARGO_BACKLOG_ONLY] = false  }})
                        end
                    end)

                    waitingCargoSelectorLayout:addItem(waitingCargoSelectorSlider)
                    waitingCargoSelectorLayout:addItem(waitingCargoSelectorValue)
                    waitingCargoSelectorLayout:addItem(waitingCargoBacklogOnlyCheckBox)
                    waitingCargoSelectorLayout:addItem(waitingCargoBacklogOnlyLabel)

                    if station[asrEnum.station.WAITING_CARGO_ENABLED] == true then
                        waitingCargoCheckBox:setSelected(true, false)
                        waitingCargoSelectorSlider:setEnabled(true)
                        waitingCargoSelectorSlider:setVisible(true, false)
                        waitingCargoSelectorValue:setEnabled(true)
                        waitingCargoSelectorValue:setVisible(true, false)
                        waitingCargoBacklogOnlyCheckBox:setEnabled(true)
                        waitingCargoBacklogOnlyCheckBox:setVisible(true, false)
                        waitingCargoBacklogOnlyLabel:setEnabled(true)
                        waitingCargoBacklogOnlyLabel:setVisible(true, false)

                    else
                        waitingCargoCheckBox:setSelected(false, false)
                        waitingCargoSelectorSlider:setEnabled(false)
                        waitingCargoSelectorSlider:setVisible(false, false)
                        waitingCargoSelectorValue:setEnabled(false)
                        waitingCargoSelectorValue:setVisible(false, false)
                        waitingCargoBacklogOnlyCheckBox:setEnabled(false)
                        waitingCargoBacklogOnlyCheckBox:setVisible(false, false)
                        waitingCargoBacklogOnlyLabel:setEnabled(false)
                        waitingCargoBacklogOnlyLabel:setVisible(false, false)
                    end
                    waitingCargoCheckBox:onToggle(function (checked)
                        if checked then
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.WAITING_CARGO_ENABLED] = true  }})
                            waitingCargoSelectorSlider:setEnabled(true)
                            waitingCargoSelectorSlider:setVisible(true, false)
                            waitingCargoSelectorValue:setEnabled(true)
                            waitingCargoSelectorValue:setVisible(true, false)
                            waitingCargoBacklogOnlyCheckBox:setEnabled(true)
                            waitingCargoBacklogOnlyCheckBox:setVisible(true, false)
                            waitingCargoBacklogOnlyLabel:setEnabled(true)
                            waitingCargoBacklogOnlyLabel:setVisible(true, false)    
                        else
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.WAITING_CARGO_ENABLED] = false  }})
                            waitingCargoSelectorSlider:setEnabled(false)
                            waitingCargoSelectorSlider:setVisible(false, false)
                            waitingCargoSelectorValue:setEnabled(false)
                            waitingCargoSelectorValue:setVisible(false, false)
                            waitingCargoBacklogOnlyCheckBox:setEnabled(false)
                            waitingCargoBacklogOnlyCheckBox:setVisible(false, false)
                            waitingCargoBacklogOnlyLabel:setEnabled(false)
                            waitingCargoBacklogOnlyLabel:setVisible(false, false)
    
                        end
                        asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)

                    end)
                    amountSelectionTable:addRow({waitingCargoCheckBox, waitingCargoLabel, waitingCargoSelectorWrapper})

                    local capacityAdjustmentCheckBox = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
                    capacityAdjustmentCheckBox:setId("asr.capacityAdjustmentCheckbox-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local capacityAdjustmentLabel = api.gui.comp.TextView.new(i18Strings.adjust_capacity)
                    capacityAdjustmentLabel:setTooltip(i18Strings.adjust_capacity_tip)

                    local capacityAdjustmentSelectorLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                    local capacityAdjustmentSelectorWrapper = api.gui.comp.Component.new("asr.capacityAdjustmentWrapper")
                    capacityAdjustmentSelectorWrapper:setLayout(capacityAdjustmentSelectorLayout)

                    local capacityAdjustmentSelectorSlider = api.gui.comp.Slider.new(true)
                    local capacityAdjustmentSelectorValue = api.gui.comp.TextView.new("")
                    if station[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] ~= nil then
                        capacityAdjustmentSelectorSlider:setDefaultValue(tonumber(station[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE])/5)
                        capacityAdjustmentSelectorSlider:setValue(tonumber(station[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE])/5, false)
                        capacityAdjustmentSelectorValue:setText(tostring(station[asrEnum.station.CAPACITY_ADJUSTMENT_VALUE]) .. "%")
                    else
                        capacityAdjustmentSelectorSlider:setDefaultValue(0)
                        capacityAdjustmentSelectorSlider:setValue(0, false)
                        capacityAdjustmentSelectorValue:setText("0%")
                    end
                    capacityAdjustmentSelectorSlider:setMaximum(6)
                    capacityAdjustmentSelectorSlider:setMinimum(-6)
                    -- capacityAdjustmentSelectorSlider:setStep(10)
                    capacityAdjustmentSelectorSlider:setMinimumSize(api.gui.util.Size.new(140, 18))
                    capacityAdjustmentSelectorSlider:setMaximumSize(api.gui.util.Size.new(140, 18))
                    capacityAdjustmentSelectorSlider:onValueChanged(function (value) 
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  = { [asrEnum.station.CAPACITY_ADJUSTMENT_VALUE] = tonumber(value)*5}})                        
                        capacityAdjustmentSelectorValue:setText(tostring(value*5).."%")
                    end)
                    capacityAdjustmentSelectorLayout:addItem(capacityAdjustmentSelectorSlider)
                    capacityAdjustmentSelectorLayout:addItem(capacityAdjustmentSelectorValue)

                    if station[asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] == true then
                        capacityAdjustmentCheckBox:setSelected(true, false)
                        capacityAdjustmentSelectorSlider:setEnabled(true)
                        capacityAdjustmentSelectorSlider:setVisible(true, false)
                        capacityAdjustmentSelectorValue:setEnabled(true)
                        capacityAdjustmentSelectorValue:setVisible(true, false)
                    else
                        capacityAdjustmentCheckBox:setSelected(false, false)
                        capacityAdjustmentSelectorSlider:setEnabled(false)
                        capacityAdjustmentSelectorSlider:setVisible(false, false)
                        capacityAdjustmentSelectorValue:setEnabled(false)
                        capacityAdjustmentSelectorValue:setVisible(false, false)
                    end
                    capacityAdjustmentCheckBox:onToggle(function (checked)
                        if checked then
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] = true  }})
                            capacityAdjustmentSelectorSlider:setEnabled(true)
                            capacityAdjustmentSelectorSlider:setVisible(true, false)
                            capacityAdjustmentSelectorValue:setEnabled(true)
                            capacityAdjustmentSelectorValue:setVisible(true, false)
                        else
                            sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED] = false  }})
                            capacityAdjustmentSelectorSlider:setEnabled(false)
                            capacityAdjustmentSelectorSlider:setVisible(false, false)
                            capacityAdjustmentSelectorValue:setEnabled(false)
                            capacityAdjustmentSelectorValue:setVisible(false, false)
                        end
                        asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)

                    end)
                    amountSelectionTable:addRow({capacityAdjustmentCheckBox, capacityAdjustmentLabel, capacityAdjustmentSelectorWrapper})

                    amountSelectionIndustryShippingCheckBox:onToggle(function (checked) 
                        setToggle("amountSelection", "IndustryShipping", stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId, checked)
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.SELECTOR]  = "industryShipping" }})
                        end)
                    amountSelectionShippingContractCheckBox:onToggle(function (checked) 
                        setToggle("amountSelection", "ShippingContract", stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId, checked)
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = { [asrEnum.station.SELECTOR]  = "shippingContract" }})
                        end)
                    amountSelectionCargoGroupCheckBox:onToggle(function (checked) 
                        setToggle("amountSelection", "CargoGroup", stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId, checked)
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config  =  { [asrEnum.station.SELECTOR] = "cargoGroup" }})
                        end)
                    amountSelectionFixedAmountCheckBox:onToggle(function (checked) 
                        setToggle("amountSelection", "FixedAmount", stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId, checked)
                        sendEngineCommand("asrUpdateStation", { lineId = lineId, stopSequence = stopSequence, stationId = station[asrEnum.station.STATION_ID], config = {  [asrEnum.station.SELECTOR]  = "fixedAmount" }})
                        end)
                        
                    -- show the current values for the amount selection (if known)
                    currentAmountWrapper:setId("asr.currentAmountWrapper-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local currentAmountLayout = api.gui.layout.BoxLayout.new("VERTICAL");
                    currentAmountWrapper:setGravity(0,0)
                    currentAmountWrapper:setLayout(currentAmountLayout)

                    local currentTotalAmountLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                    local currentTotalAmountWrapper = api.gui.comp.Component.new("asr.totalAmountWrapper")
                    currentTotalAmountWrapper:setLayout(currentTotalAmountLayout)

                    local currentTotalAmountIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
                    currentTotalAmountIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
                    currentTotalAmountLayout:addItem(currentTotalAmountIcon)
                    
                    local currentValue = station[asrEnum.station.CARGO_AMOUNT]
                    if not currentValue then currentValue = 0 end

                    local currentTotalAmountText = api.gui.comp.TextView.new(tostring(currentValue))
                    currentTotalAmountText:setId("asr.currentTotalAmountText-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    currentTotalAmountLayout:addItem(currentTotalAmountText)

                    currentAmountLayout:addItem(currentTotalAmountWrapper)
                    -- currentAmountLayout:addItem(currentAmountList)
                    
                    lineSettingsTable:addRow({currentAmountWrapper, amountSelectionTable})
                end


                -- wagon list
                local trainWagonsLabel = api.gui.comp.TextView.new(i18Strings.wagons)
                trainWagonsLabel:setGravity(0,0)
                local trainWagonsLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
                local trainWagonsWrapper = api.gui.comp.Component.new("trainWagonsWrapper")
                trainWagonsWrapper:setLayout(trainWagonsLayout)

                local trainWagonsClearCacheIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/relocate_headquarter@2x.tga")
                trainWagonsClearCacheIcon:setMaximumSize(api.gui.util.Size.new(20, 20))
                trainWagonsClearCacheIcon:setTooltip(i18Strings.wagons_refresh_tip)
                local trainWagonsClearCacheButton = api.gui.comp.Button.new(trainWagonsClearCacheIcon, false)
                trainWagonsClearCacheButton:onClick(function ()
                    sendEngineCommand("asrRefreshLineVehicleInfo", { lineId = lineId })
                end)
                trainWagonsLayout:addItem(trainWagonsClearCacheButton)

                local trainWagonsListTable = api.gui.comp.Table.new(1, 'NONE')
                trainWagonsListTable:setId("asr.trainWagonsListTable-" .. lineId)
                local trainWagonsListLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
                -- trainWagonsListLayout:setId("asr.trainWagonsListLayout-" .. lineId)
                local trainWagonsListWrapper = api.gui.comp.Component.new("trainWagonsListWrapper")
                trainWagonsListWrapper:setLayout(trainWagonsListLayout)
    
                if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] and 
                    asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] then
                    for _, wagonId in pairs(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS]) do
                        local wagonDetails = api.res.modelRep.get(tonumber(wagonId))
                        local wagonInfo 
                        if wagonDetails and wagonDetails.metadata and wagonDetails.metadata.description then
                            wagonInfo = api.gui.comp.ImageView.new(wagonDetails.metadata.description.icon20)
                            wagonInfo:setGravity(0, 0.5)
                            wagonInfo:setTooltip(wagonDetails.metadata.description.name)
                            local imageSize = wagonInfo:calcMinimumSize()
                            wagonInfo:setMinimumSize(api.gui.util.Size.new(math.ceil(imageSize.w*1.5), math.ceil(imageSize.h*1.5)))
                            wagonInfo:setMaximumSize(api.gui.util.Size.new(math.ceil(imageSize.w*1.5), math.ceil(imageSize.h*1.5)))
                        else
                            wagonInfo = api.gui.comp.TextView.new("missing info: " .. wagonId)
                        end
                        trainWagonsListLayout:addItem(wagonInfo)
                    end
                end
                trainWagonsListTable:addRow({trainWagonsListWrapper})
                trainWagonsLayout:addItem(trainWagonsListTable)
    
                lineSettingsTable:addRow({trainWagonsLabel, trainWagonsWrapper})

                
                local showLineStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump line details"), false)
                showLineStateButton:onClick(function () 
                    sendEngineCommand("asrDumpLineState", { lineId = asrGuiState.selectedLine})
                end)
                local deleteLineStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Delete line details"), false)
                deleteLineStateButton:onClick(function () 
                    sendEngineCommand("asrDeleteLineState", { lineId = asrGuiState.selectedLine})
                end)    
                if asrState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] then 
                    lineSettingsTable:addRow({api.gui.comp.TextView.new("debug"), showLineStateButton})
                    lineSettingsTable:addRow({api.gui.comp.TextView.new("debug"), deleteLineStateButton})
                end
            end

            -- add top colour as a table
            local lineSettingsColourLine = api.gui.comp.Table.new(1, 'NONE')
            if asrGuiState.selectedLine ~= nil then 
                log("gui: adding colour line")
                local col0text = api.gui.comp.TextView.new("                                                      ")
                col0text:setStyleClassList({"asrBackgroundLineColour-" .. asrGuiHelper.getLineColour(tonumber(asrGuiState.selectedLine))})
                lineSettingsColourLine:addRow({col0text})
            end
            asrGuiState.lineSettingsTableBuilt = true
        else
            -- only doing a refresh of data

            -- log("gui: rebuildLineSettingsLayout, doing a refresh")
            if asrGuiState.selectedLine ~= nil and asrState[asrEnum.LINES][tostring(lineId)] ~= nil then
                local lineNameValue = api.gui.util.getById("asr.settingsLineName")
                if lineNameValue then
                    lineNameValue:setText(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.NAME])
                end

                local trainLengthGlobalValue = api.gui.util.getById("asr.trainLengthGLobalValue-" .. lineId)
                if trainLengthGlobalValue then 
                    trainLengthGlobalValue:setText(tostring(asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]) .. " m")
                end
            end

            -- refresh wagons

            local trainWagonsListTable = api.gui.util.getById("asr.trainWagonsListTable-" .. lineId)
            if trainWagonsListTable then
                trainWagonsListTable:deleteAll()
            
                local trainWagonsListLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
                local trainWagonsListWrapper = api.gui.comp.Component.new("trainWagonsListWrapper")
                trainWagonsListWrapper:setLayout(trainWagonsListLayout)

                if asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES] and 
                    asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS] then
                    for _, wagonId in pairs(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.VEHICLES][asrEnum.vehicle.WAGONS]) do
                        local wagonDetails = api.res.modelRep.get(tonumber(wagonId))
                        local wagonInfo 
                        if wagonDetails and wagonDetails.metadata and wagonDetails.metadata.description then
                            wagonInfo = api.gui.comp.ImageView.new(wagonDetails.metadata.description.icon20)
                            wagonInfo:setGravity(0, 0.5)
                            wagonInfo:setTooltip(wagonDetails.metadata.description.name)
                            local imageSize = wagonInfo:calcMinimumSize()
                            wagonInfo:setMinimumSize(api.gui.util.Size.new(math.ceil(imageSize.w*1.5), math.ceil(imageSize.h*1.5)))
                            wagonInfo:setMaximumSize(api.gui.util.Size.new(math.ceil(imageSize.w*1.5), math.ceil(imageSize.h*1.5)))
                        else
                            wagonInfo = api.gui.comp.TextView.new("missing info: " .. wagonId)
                        end
                        trainWagonsListLayout:addItem(wagonInfo)
                    end
                end
                trainWagonsListTable:addRow({trainWagonsListWrapper})
            end

            if asrState[asrEnum.LINES][tostring(lineId)] ~= nil and asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS] ~= nil then 
                for stopSequence, station in pairs(asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.STATIONS]) do
                    local stationEnabled = api.gui.util.getById("asr.stationEnabled-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionTable = api.gui.util.getById("asr.amountSelectionTable-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local currentAmountWrapper = api.gui.util.getById("asr.currentAmountWrapper-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if stationEnabled ~= nil and amountSelectionTable ~= nil and currentAmountWrapper ~= nil then 
                        if station[asrEnum.station.ENABLED] == true then
                            stationEnabled:setSelected(true, false)
                            amountSelectionTable:setVisible(true, false)
                            currentAmountWrapper:setVisible(true, false)
                        else
                            stationEnabled:setSelected(false, false)
                            amountSelectionTable:setVisible(false, false)
                            currentAmountWrapper:setVisible(false, false)
                        end                        
                    end
                    local amountSelectionIndustryShippingButton = api.gui.util.getById("asr.amountSelectionIndustryShippingInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionIndustryShippingCheckBox = api.gui.util.getById("asr.amountSelectionIndustryShipping-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if amountSelectionIndustryShippingButton ~= nil and amountSelectionIndustryShippingCheckBox ~= nil then
                        if station[asrEnum.station.SELECTOR] == "industryShipping" then
                            amountSelectionIndustryShippingCheckBox:setSelected(true, false)
                            amountSelectionIndustryShippingButton:setEnabled(true)
                            amountSelectionIndustryShippingButton:setVisible(true, false)
                        else
                            amountSelectionIndustryShippingCheckBox:setSelected(false, false)
                            amountSelectionIndustryShippingButton:setEnabled(false)
                            amountSelectionIndustryShippingButton:setVisible(false, false)
                        end

                        local amountSelectionIndustryShippingButtonLayout = createIndustryButtonLayout(
                            station[asrEnum.station.INDUSTRY_ID] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])][asrEnum.industry.NAME],
                            station[asrEnum.station.INDUSTRY_CARGO_ID],
                            station[asrEnum.station.INDUSTRY_KIND], 
                            station[asrEnum.station.INDUSTRY_ID] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])] and asrState[asrEnum.INDUSTRIES][tostring(station[asrEnum.station.INDUSTRY_ID])][asrEnum.industry.TYPE] )
    
                        amountSelectionIndustryShippingButton:setContent(amountSelectionIndustryShippingButtonLayout)
                    end

                    local amountSelectionShippingContractButton = api.gui.util.getById("asr.amountSelectionShippingContractInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionShippingContractCheckBox = api.gui.util.getById("asr.amountSelectionShippingContract-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if amountSelectionShippingContractButton ~= nil and amountSelectionShippingContractCheckBox ~= nil then
                        if station[asrEnum.station.SELECTOR] == "shippingContract" then
                            amountSelectionShippingContractCheckBox:setSelected(true, false)
                            amountSelectionShippingContractButton:setEnabled(true)
                            amountSelectionShippingContractButton:setVisible(true, false)
                        else
                            amountSelectionShippingContractCheckBox:setSelected(false, false)
                            amountSelectionShippingContractButton:setEnabled(false)
                            amountSelectionShippingContractButton:setVisible(false, false)
                        end

                        local amountSelectionShippingContractButtonLayout = createIndustryButtonLayout(
                            station[asrEnum.station.SHIPPING_CONTRACT_ID] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(station[asrEnum.station.SHIPPING_CONTRACT_ID])] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(station[asrEnum.station.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME],
                            station[asrEnum.station.SHIPPING_CONTRACT_CARGO_ID],
                            "shippingContract", nil)
                            
                        amountSelectionShippingContractButton:setContent(amountSelectionShippingContractButtonLayout)
                    end

                    local amountSelectionCargoGroupButton = api.gui.util.getById("asr.amountSelectionCargoGroupInput-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local amountSelectionCargoGroupCheckBox = api.gui.util.getById("asr.amountSelectionCargoGroup-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if amountSelectionCargoGroupButton ~= nil and amountSelectionCargoGroupCheckBox ~= nil then
                        if station[asrEnum.station.SELECTOR] == "cargoGroup" then
                            amountSelectionCargoGroupCheckBox:setSelected(true, false)
                            amountSelectionCargoGroupButton:setEnabled(true)
                            amountSelectionCargoGroupButton:setVisible(true, false)
                        else
                            amountSelectionCargoGroupCheckBox:setSelected(false, false)
                            amountSelectionCargoGroupButton:setEnabled(false)
                            amountSelectionCargoGroupButton:setVisible(false, false)
                        end

                        local amountSelectionCargoGroupButtonLayout = createIndustryButtonLayout(
                            station[asrEnum.station.CARGO_GROUP_ID] and asrState[asrEnum.CARGO_GROUPS][tostring(station[asrEnum.station.CARGO_GROUP_ID])] and asrState[asrEnum.CARGO_GROUPS][tostring(station[asrEnum.station.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME],
                            nil,
                            "cargoGroup", nil)
                            
                        amountSelectionCargoGroupButton:setContent(amountSelectionCargoGroupButtonLayout)
                    end

                    -- auto pickup
                    local waitingCargoCheckBox = api.gui.util.getById("asr.waitingCargoCheckbox-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoSelectorSlider = api.gui.util.getById("asr.waitingCargoSelectorSlider-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoSelectorValue = api.gui.util.getById("asr.waitingCargoSelectorValue-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoBacklogOnlyCheckBox = api.gui.util.getById("asr.waitingCargoBacklogOnlyCheckbox-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    local waitingCargoBacklogOnlyLabel = api.gui.util.getById("asr.waitingCargoBacklogOnlyLabel-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if waitingCargoCheckBox and waitingCargoSelectorSlider and waitingCargoSelectorValue and waitingCargoBacklogOnlyCheckBox and waitingCargoBacklogOnlyLabel then
                        if station[asrEnum.station.WAITING_CARGO_ENABLED] == true then
                            waitingCargoCheckBox:setSelected(true, false)
                            waitingCargoSelectorSlider:setEnabled(true)
                            waitingCargoSelectorSlider:setVisible(true, false)
                            waitingCargoSelectorValue:setEnabled(true)
                            waitingCargoSelectorValue:setVisible(true, false)
                            waitingCargoBacklogOnlyCheckBox:setEnabled(true)
                            waitingCargoBacklogOnlyCheckBox:setVisible(true, false)
                            waitingCargoBacklogOnlyLabel:setEnabled(true)
                            waitingCargoBacklogOnlyLabel:setVisible(true, false)
    
                        else
                            waitingCargoCheckBox:setSelected(false, false)
                            waitingCargoSelectorSlider:setEnabled(false)
                            waitingCargoSelectorSlider:setVisible(false, false)
                            waitingCargoSelectorValue:setEnabled(false)
                            waitingCargoSelectorValue:setVisible(false, false)
                            waitingCargoBacklogOnlyCheckBox:setEnabled(false)
                            waitingCargoBacklogOnlyCheckBox:setVisible(false, false)
                            waitingCargoBacklogOnlyLabel:setEnabled(false)
                            waitingCargoBacklogOnlyLabel:setVisible(false, false)
                        end
                    end
                    
                    local currentValue = station[asrEnum.station.CARGO_AMOUNT]
                    if not currentValue then currentValue = 0 end 

                    local currentTotalAmountText = api.gui.util.getById("asr.currentTotalAmountText-" .. stopSequence .. "-" .. station[asrEnum.station.STATION_ID] .. "-" .. lineId)
                    if currentTotalAmountText then 
                        currentTotalAmountText:setText(tostring(currentValue))
                    end
                    asrGuiState.refreshCargoAmounts = false
                    
                end
            end
        end
    end 
end

-- rebuild the lines table
local function  rebuildLinesTable()

    -- log("gui: rebuild lines Window")
    local linesTable = api.gui.util.getById("asr.linesTable")
    if linesTable ~= nil then

        local linesScrollArea = api.gui.util.getById("asr.linesScrollArea") 
        local linesScrollOffset = linesScrollArea:getScrollOffset()

        linesTable:deleteRows(0,linesTable:getNumRows())
        asrGuiState.linesRowMap = {}

        if asrState[asrEnum.LINES] == nil then
            log("no lines in the state found, do a quick init on the gui side")
            asrState[asrEnum.LINES] = {}
        end
        local validLines = asrHelper.filterOutInvalid(asrState[asrEnum.LINES])
        local filteredLines
        if asrGuiState.linesFilterString then
            filteredLines = asrHelper.filterTable(validLines, asrEnum.line.NAME, asrGuiState.linesFilterString)
        else 
            filteredLines = validLines
        end
        local firstLineId = asrHelper.getFirstSortedKey(filteredLines, asrEnum.line.NAME)
        if filteredLines then 
            for lineId,line in pairs(filteredLines) do

                table.insert(asrGuiState.linesRowMap, lineId)
                if asrGuiState.selectedLine == nil then
                    asrGuiState.selectedLine = firstLineId
                    log("gui: autoselcted line: " .. firstLineId)
                    sendEngineCommand("asrInitLine", { lineId = firstLineId })
                end

                local lineEnabled = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
                lineEnabled:setId("asr.lineEnabled-" .. lineId)
                if line[asrEnum.line.ENABLED] == true  then
                    lineEnabled:setSelected(true, false)
                    lineEnabled:setTooltip(i18Strings.enabled)
                else
                    lineEnabled:setSelected(false, false)
                    lineEnabled:setTooltip(i18Strings.disabled)
                end
                lineEnabled:setStyleClassList({"asrCheckbox"})
                lineEnabled:onToggle(function (checked)

                    if checked then
                        log("checkbox for line " .. lineId .. " set to true")
                        lineEnabled:setTooltip(i18Strings.enabled)
                        asrState[asrEnum.LINES][tostring(lineId)][asrEnum.line.ENABLED] = true
                        local lineState = {}
                        lineState[asrEnum.line.LINE_ID] = lineId
                        lineState[asrEnum.line.ENABLED] = true
                        sendEngineCommand("asrLineState", lineState)
                    else
                        log("checkbox for line " .. lineId .. " set to false")
                        lineEnabled:setTooltip(i18Strings.disabled)
                        local lineState = {}
                        lineState[asrEnum.line.LINE_ID] = lineId
                        lineState[asrEnum.line.ENABLED] = false
                        sendEngineCommand("asrLineState", lineState)
                    end
                    -- asrHelper.tlog(asrState, 1)

                end)

                local lineColour = api.gui.comp.TextView.new("●")
                lineColour:setId("asr.lineColour-" .. lineId)
                local lineStatus = api.gui.comp.TextView.new("●")
                lineStatus:setId("asr.lineStatus-" .. lineId)
                local lineName = api.gui.comp.TextView.new(tostring(line[asrEnum.line.NAME]))
                lineName:setStyleClassList({"asrLineName"})
                lineName:setId("asr.lineName-" .. lineId)

                lineColour:setStyleClassList({"asrLineColour-" .. asrGuiHelper.getLineColour(tonumber(lineId))})
                if line.status ~= nil then 
                    lineStatus:setStyleClassList({"asrLineStatus" .. line.status})
                    if line.statusMessage ~= nil then 
                        lineStatus:setTooltip(line.statusMessage)
                    end
                else
                    lineStatus:setStyleClassList({"asrLineStatusDisabled"})
                    lineStatus:setTooltip(i18Strings.disabled_for_line)    
                end
                
                local lineEditIcon = api.gui.comp.ImageView.new("ui/modify16.tga")
                local lineEditButton = api.gui.comp.Button.new(lineEditIcon, false)
                lineEditButton:onClick(function ()

                    local lineSettingsLayout = api.gui.util.getById("asr.settingsScrollAreaLayout")
                    asrGuiState.selectedLine = lineId
                    asrGuiState.lineSettingsTableBuilt = false
                    asrGuiState.settingsTableInitalising = true
                    if asrGuiObjects.lineSettingsDropDownList ~= nil then
                        asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)
                    end
                    rebuildLineSettingsLayout()

                    sendEngineCommand("asrInitLine", { lineId = lineId })
            
                end)

                lineEditIcon:setStyleClassList({"asrLineEditButton"})
                lineName:setTooltip(tostring(lineId))

                -- asrHelper.getLineDetails(line.id)
                linesTable:addRow({lineColour, lineEnabled, lineStatus, lineName})
            end
            if asrState[asrEnum.LINES] ~= nil then 
                linesTable:setOrder(asrHelper.getSortOrder(filteredLines, asrEnum.line.NAME))
            end
            -- hack to make sure the scrolling back to the right position happens after the table has been redrawn
            linesScrollArea:invokeLater(function () linesScrollArea:invokeLater(function () linesScrollArea:setScrollOffset(linesScrollOffset) end ) end )
        end
    else
        log(" can't get lines table" )
    end
end

-- refresh the lines table (status etc)
local function refreshLinesTable()

    -- log("gui: refresh lines Window")
    local linesTable = api.gui.util.getById("asr.linesTable")
    if linesTable ~= nil then


        local validLines = asrHelper.filterOutInvalid(asrState[asrEnum.LINES])
        local filteredLines
        if asrGuiState.linesFilterString then
            filteredLines = asrHelper.filterTable(validLines, asrEnum.line.NAME, asrGuiState.linesFilterString)
        else 
            filteredLines = validLines
        end
        local firstLineId = asrHelper.getFirstSortedKey(filteredLines, asrEnum.line.NAME)

        if filteredLines then
            for lineId,line in pairs(filteredLines) do

                if asrGuiState.selectedLine == nil then
                    asrGuiState.selectedLine = firstLineId
                    log("gui: autoselcted line: " .. firstLineId)
                    sendEngineCommand("asrInitLine", { lineId = firstLineId })
                end
        
                local lineEnabled = api.gui.util.getById("asr.lineEnabled-" .. lineId)
                if lineEnabled == nil then
                    -- the table might not exist yet, force a rebuild
                    log("forcing rebuild of the lines table")
                    asrGuiState.rebuildLinesTable = true
                    break
                end
                if line[asrEnum.line.ENABLED] == true then
                    lineEnabled:setSelected(true, false)
                    lineEnabled:setTooltip(i18Strings.enabled)
                else
                    lineEnabled:setSelected(false, false)
                    lineEnabled:setTooltip(i18Strings.disabled)
                end
                lineEnabled:setStyleClassList({"asrCheckbox"})

                local lineColour = api.gui.util.getById("asr.lineColour-" .. lineId)
                local lineStatus = api.gui.util.getById("asr.lineStatus-" .. lineId)
                local lineName = api.gui.util.getById("asr.lineName-" .. lineId)
            

                lineColour:setStyleClassList({"asrLineColour-" .. asrGuiHelper.getLineColour(tonumber(lineId))})
                if line[asrEnum.line.STATUS] ~= nil then 
                    lineStatus:setStyleClassList({"asrLineStatus" .. line[asrEnum.line.STATUS]})
                    if line[asrEnum.line.STATUS_MESSAGE] ~= nil then 
                        lineStatus:setTooltip(line[asrEnum.line.STATUS_MESSAGE])
                    end
                else
                    lineStatus:setStyleClassList({"asrLineStatusDisabled"})
                    lineStatus:setTooltip(i18Strings.disabled_for_line)    
                end
                lineName:setTooltip(tostring(lineId))
                if line[asrEnum.line.NAME] ~= nil then
                    lineName:setText(line[asrEnum.line.NAME])
                else
                    lineName:setText(" unknown line? ")
                    log("no info about line " .. lineId .. " force a re-init")
                    sendEngineCommand("asrInitLine", { lineId = lineId })
                end
            end
        end
    else
        log(" can't get lines table" )
    end
end


-- populate timings table
local function getTimings() 

    local timingsTable = api.gui.util.getById("asr.timingsTable")
    if timingsTable then
        if asrState[asrEnum.TIMINGS] then 
            local results = {}
            timingsTable:deleteAll()
            for functionName, timings in pairs(asrState[asrEnum.TIMINGS]) do
                if functionName ~= "Total" then 
                    table.insert(results, { name = functionName, value = asrHelper.average(timings)})
                    timingsTable:addRow({api.gui.comp.TextView.new(tostring(functionName)), api.gui.comp.TextView.new(tostring(math.ceil(asrHelper.average(timings))) .. "ms"),api.gui.comp.TextView.new(tostring(math.ceil(asrHelper.max(timings))) .. "ms") })
                end
            end
            timingsTable:setOrder(asrHelper.getSortOrder(results, "name"))
            -- table.insert(results, { name = "Total", value = average(asrState[asrEnum.TIMINGS]["Total"])})
            timingsTable:addRow({ 
                api.gui.comp.TextView.new("Total"), 
                api.gui.comp.TextView.new(tostring(math.ceil(asrHelper.average(asrState[asrEnum.TIMINGS]["Total"]))) .. "ms"),
                api.gui.comp.TextView.new(tostring(math.ceil(asrHelper.max(asrState[asrEnum.TIMINGS]["Total"]))) .. "ms") })

        end
        if asrState[asrEnum.TRACKED_TRAINS] then
            timingsTable:addRow({api.gui.comp.TextView.new("Tracked trains"), api.gui.comp.TextView.new(tostring( asrHelper.getTableLength(asrState[asrEnum.TRACKED_TRAINS]))),api.gui.comp.TextView.new("") })
        end
    end
end


-- contracts layout - complete
local function rebuildShippingContractsLayout() 

    -- log("gui: rebuildShippingContractsLayout")

    local cargoTrackingTabLayout = asrGuiObjects.cargoTrackingTabLayout
    local shippingContractsLayout = asrGuiObjects.shippingContractsLayout
    local shippingContractSettingsLayout = asrGuiObjects.shippingContractSettingsLayout
    local shippingContractsTable = asrGuiObjects.shippingContractsTable
    local shippingContractSettingsTable = asrGuiObjects.shippingContractSettingsTable
    local shippingContractIndustryDropDownList = asrGuiObjects.shippingContractIndustryDropDownList

    local selectedShippingContractId = asrGuiState.selectedShippingContract

    if shippingContractsLayout == nil then

        log("gui: rebuildShippingContractsLayout: building shipping contracts main layout")
        shippingContractsLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
        shippingContractsLayout:setId("asr.shippingContractsGroupsLayout")
        local shippingContractsWrapper = api.gui.comp.Component.new("asr.shippingContractsWrapper")
        shippingContractsWrapper:setLayout(shippingContractsLayout)

        local shippingContractsScrollLayout = api.gui.layout.BoxLayout.new("VERTICAL");
        local shippingContractsScrollWrapper = api.gui.comp.Component.new("asr.shippingContractsScrollWrapper")
        shippingContractsScrollWrapper:setLayout(shippingContractsScrollLayout)

        local shippingContractsScrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.TextView.new('shippingContractsScrollArea'), "asr.shippingContractsScrollArea")
        shippingContractsScrollArea:setId("asr.shippingContractsScrollArea")
        shippingContractsScrollArea:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.shippingContractsScrollArea.width, asrGuiDimensions.shippingContractsScrollArea.height))
        shippingContractsScrollArea:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.shippingContractsScrollArea.width, asrGuiDimensions.shippingContractsScrollArea.height))

        local newShippingContractButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
        local newShippingContractButtonIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/configure_line@2x.tga")
        newShippingContractButtonIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
        newShippingContractButtonIcon:setStyleClassList({"asrCargoButton"})
        newShippingContractButtonLayout:addItem(newShippingContractButtonIcon)
        newShippingContractButtonLayout:addItem(api.gui.comp.TextView.new(i18Strings.new_shipping_contract))
        local newShippingContractButton = api.gui.comp.Button.new(newShippingContractButtonLayout, false)
        newShippingContractButton:setStyleClassList({"asrNewButton"})
        newShippingContractButton:onClick(function ()
            local shippingContractId = getNewId()
            asrGuiState.selectedShippingContract = shippingContractId
            log("gui: rebuildShippingContractsLayout: selecting id: " .. shippingContractId)
            sendEngineCommand("asrUpdateShippingContract", { shippingContractId = shippingContractId, property = asrEnum.shippingContract.NAME, value = "Shipping contract #" .. shippingContractId })
            asrGuiState.rebuildShippingContractsSettingsTable = true
        end)

        shippingContractsTable = api.gui.comp.Table.new(4, 'SINGLE')
        shippingContractsTable:setColWidth(1,asrGuiDimensions.shippingContractsScrollArea.width - 100)
        shippingContractsTable:setId("asr.shippingContractsTable")
        asrGuiObjects.shippingContractsTable = shippingContractsTable
        shippingContractsTable:onHover(function (id) 
            for mapId, shippingContractId in pairs(asrGuiState.shippingContractsRowMap) do
                local shippingContractEditButton = api.gui.util.getById("asr.shippingContractEditButton-" .. tostring(shippingContractId))
                local shippingContractDeleteButton = api.gui.util.getById("asr.shippingContractDeleteButton-" .. tostring(shippingContractId))
                if shippingContractEditButton then
                    if id + 1 == mapId then
                        shippingContractEditButton:setVisible(true, false)
                    else
                        shippingContractEditButton:setVisible(false, false)
                    end
                end
                if shippingContractDeleteButton then
                    if id + 1 == mapId then
                        shippingContractDeleteButton:setVisible(true, false)
                    else
                        shippingContractDeleteButton:setVisible(false, false)
                    end
                end
            end
        end)
        shippingContractsTable:onSelect(function (id) 
            log("gui: rebuildShippingContractsLayout: on select: " .. id)
            if id >= 0 then 
                asrGuiState.rebuildShippingContractsSettingsTable = true
                asrGuiState.selectedShippingContract = asrGuiState.shippingContractsRowMap[id + 1]
                log("gui: rebuildShippingContractsLayout: forcing shipping contract layout refresh on select")
                rebuildShippingContractsLayout()            
            end            
        end)

        asrGuiObjects.shippingContractsTable = shippingContractsTable

        shippingContractsScrollArea:setContent(shippingContractsTable)
        shippingContractsScrollLayout:addItem(newShippingContractButton)
        shippingContractsScrollLayout:addItem(shippingContractsScrollArea)
        shippingContractsLayout:addItem(shippingContractsScrollWrapper)


        shippingContractSettingsLayout = api.gui.layout.AbsoluteLayout.new()
        shippingContractSettingsLayout:setId("asr.shippingContractSettingsLayout")
        local shippingContractSettingsWrapper = api.gui.comp.Component.new("asr.shippingContractSettingsWrapper")
        shippingContractSettingsWrapper:setLayout(shippingContractSettingsLayout)
        asrGuiObjects.shippingContractSettingsLayout = shippingContractSettingsLayout

        shippingContractSettingsTable = api.gui.comp.Table.new(2, 'NONE')
        shippingContractSettingsTable:setId("asr.shippingContractSettingsTable")
        shippingContractSettingsTable:setColWidth(0,asrGuiDimensions.shippingContractSettingsTable.columns[1])
        shippingContractSettingsTable:setColWidth(1,asrGuiDimensions.shippingContractSettingsTable.columns[2])
        shippingContractSettingsTable:setGravity(0, 0)
        shippingContractSettingsLayout:addItem(shippingContractSettingsTable, api.gui.util.Rect.new(0,0,590,500))
        asrGuiObjects.shippingContractSettingsTable = shippingContractSettingsTable

        shippingContractsLayout:addItem(shippingContractSettingsWrapper)

        cargoTrackingTabLayout:addItem(shippingContractsWrapper)

        asrGuiObjects.shippingContractsLayout = shippingContractsLayout
        asrGuiState.rebuildShippingContractsTable = true
        log("gui: rebuildShippingContractsLayout: done building shipping contracts main layout")
    end


    if asrGuiState.rebuildShippingContractsSettingsTable == true then
        shippingContractSettingsTable:deleteAll()
    end


    if shippingContractIndustryDropDownList == nil then
        log("gui: rebuildShippingContractsLayout: building industry drop down")
        shippingContractIndustryDropDownList = api.gui.comp.List.new(false, 1 ,false)
        shippingContractIndustryDropDownList:setGravity(0,0)
        shippingContractIndustryDropDownList:setVisible(false,false)
        shippingContractIndustryDropDownList:setStyleClassList({"asrDropList"})        
        asrGuiObjects.shippingContractIndustryDropDownList = shippingContractIndustryDropDownList
        shippingContractSettingsLayout:addItem(shippingContractIndustryDropDownList, api.gui.util.Rect.new(0,0,100,100))  -- dimesntions don't seem to matter here? 

        shippingContractIndustryDropDownList:onSelect(function (row) 
            if dropDownEntries[row + 1] ~= nil then
                for propertyId, value  in pairs(dropDownEntries[row + 1]) do
                    sendEngineCommand("asrUpdateShippingContract", { shippingContractId = asrGuiState.selectedShippingContract, property = propertyId, value = value })
                end
            end
            shippingContractIndustryDropDownList:setVisible(false, false)
        end)
        asrGuiObjects.shippingContractIndustryDropDownList = shippingContractIndustryDropDownList
        log("gui: rebuildShippingContractsLayout: done building industry drop down")
    end

    if asrGuiState.rebuildShippingContractsTable == true then
        log("gui: rebuildShippingContractsLayout: asrGuiState.rebuildShippingContractsTable is true")
        shippingContractsTable:deleteAll()
        asrGuiState.shippingContractsRowMap = {}

        -- select a row if nothing is selected
        if selectedShippingContractId == nil then
            selectedShippingContractId = asrHelper.getFirstSortedKey(asrState[asrEnum.SHIPPING_CONTRACTS], asrEnum.shippingContract.NAME)
            asrGuiState.selectedShippingContract = selectedShippingContractId
            asrGuiState.rebuildShippingContractsSettingsTable = true 
        end

        if asrState[asrEnum.SHIPPING_CONTRACTS] then 
            for shippingContractId, shippingContract in pairs(asrState[asrEnum.SHIPPING_CONTRACTS]) do
                local shippingContractCargoIcon
                if shippingContract[asrEnum.shippingContract.CARGO_ID] and cargoTypes and cargoTypes[tonumber(shippingContract[asrEnum.shippingContract.CARGO_ID])] then
                    shippingContractCargoIcon = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(shippingContract[asrEnum.shippingContract.CARGO_ID])]) .. "@2x.tga")
                else
                    shippingContractCargoIcon = api.gui.comp.ImageView.new("ui/empty15.tga")
                end
                shippingContractCargoIcon:setStyleClassList({"asrShippingContractIcon"})
                shippingContractCargoIcon:setId("asr.shippingContractCargoIcon-" .. tostring(shippingContractId))
                shippingContractCargoIcon:setMaximumSize(api.gui.util.Size.new(15, 15))

                local shippingContractNameLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
                local shippingContractNameWrapper = api.gui.comp.Component.new("asr.shippingContractNameWrapper")
                shippingContractNameWrapper:setLayout(shippingContractNameLayout)
                
                local shippingContractNameLabel = api.gui.comp.TextView.new(shippingContract[asrEnum.shippingContract.NAME])
                shippingContractNameLabel:setId("asr.shippingContractNameLabel-" .. tostring(shippingContractId))
                shippingContractNameLayout:addItem(shippingContractNameLabel)
                local shippingContractNameTextInput = api.gui.comp.TextInputField.new(shippingContract[asrEnum.shippingContract.NAME])
                shippingContractNameTextInput:setId("asr.shippingContractNameTextInput-" .. tostring(shippingContractId))
                shippingContractNameLayout:addItem(shippingContractNameTextInput)
                shippingContractNameTextInput:setVisible(false, false)
                shippingContractNameTextInput:setText(shippingContract[asrEnum.shippingContract.NAME], false)
                shippingContractNameTextInput:selectAll()
                shippingContractNameTextInput:setMaxLength(55)
                shippingContractNameTextInput:onFocusChange(function (hasFocus) 
                    if not hasFocus then
                        local value = shippingContractNameTextInput:getText()
                        sendEngineCommand("asrUpdateShippingContract", { shippingContractId = shippingContractId, property = asrEnum.shippingContract.NAME, value = value})
                        shippingContractNameTextInput:setVisible(false, false)
                        shippingContractNameLabel:setText(value, false)
                        shippingContractNameLabel:setVisible(true, false)
                    end
                end)
                shippingContractNameTextInput:onEnter(function () 
                    local value = shippingContractNameTextInput:getText()
                    sendEngineCommand("asrUpdateShippingContract", { shippingContractId = shippingContractId, property = asrEnum.shippingContract.NAME, value = value})
                    shippingContractNameTextInput:setVisible(false, false)
                    shippingContractNameLabel:setText(value, false)
                    shippingContractNameLabel:setVisible(true, false)
                end)
                shippingContractNameTextInput:onCancel(function () 
                    shippingContractNameTextInput:setText(shippingContract[asrEnum.shippingContract.NAME], false)
                    shippingContractNameTextInput:setVisible(false, false)
                    shippingContractNameLabel:setVisible(true, false)
                end)


                local shippingContractEditIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/edit.tga")
                shippingContractEditIcon:setId("asr.shippingContractEditIcon-" .. tostring(shippingContractId))
                shippingContractEditIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                local shippingContractEditButton = api.gui.comp.Button.new(shippingContractEditIcon, false)
                shippingContractEditButton:setId("asr.shippingContractEditButton-" .. tostring(shippingContractId))
                shippingContractEditButton:setStyleClassList({"asrMiniListButton"})
                shippingContractEditButton:setVisible(false, false)
                shippingContractEditButton:setTooltip(i18Strings.rename_shipping_contract)
                shippingContractEditButton:onClick(function ()
                    if shippingContractNameLabel:isVisible() then
                        shippingContractNameLabel:setVisible(false, false)
                        shippingContractNameTextInput:setVisible(true, false)
                    else
                        shippingContractNameLabel:setVisible(true, false)
                        shippingContractNameTextInput:setVisible(false, false)
                    end
                end)

                local shippingContractDeleteIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/sell_thin.tga")
                shippingContractDeleteIcon:setId("asr.shippingContractDeleteIcon-" .. tostring(shippingContractId))
                shippingContractDeleteIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                local shippingContractDeleteButton = api.gui.comp.Button.new(shippingContractDeleteIcon, false)
                shippingContractDeleteButton:setId("asr.shippingContractDeleteButton-" .. tostring(shippingContractId))
                shippingContractDeleteButton:setStyleClassList({"asrMiniListButton"})
                shippingContractDeleteButton:setVisible(false, false)
                if shippingContract[asrEnum.shippingContract.IN_USE] and shippingContract[asrEnum.shippingContract.IN_USE] ~= 0 then
                    shippingContractDeleteButton:setEnabled(false)
                    shippingContractDeleteButton:setTooltip(i18Strings.in_use_cant_delete)
                else 
                    shippingContractDeleteButton:setEnabled(true)
                    shippingContractDeleteButton:setTooltip(i18Strings.delete_shipping_contract)
                end
                shippingContractDeleteButton:onClick(function () 
                    sendEngineCommand("asrDeleteShippingContract", { shippingContractId = shippingContractId })
                    if shippingContractId == selectedShippingContractId then
                        asrGuiState.selectedShippingContract = nil
                    end
                end)
                shippingContractsTable:addRow({shippingContractCargoIcon, shippingContractNameWrapper , shippingContractEditButton, shippingContractDeleteButton})
                table.insert(asrGuiState.shippingContractsRowMap, shippingContractId)
            end
            shippingContractsTable:setOrder(asrHelper.getSortOrder(asrState[asrEnum.SHIPPING_CONTRACTS], asrEnum.shippingContract.NAME))

            for id, shippingContractId in pairs(asrGuiState.shippingContractsRowMap) do
                if tostring(shippingContractId) == tostring(selectedShippingContractId) then
                    log("gui: rebuildShippingContractsLayout: found selected id: " .. id)
                    shippingContractsTable:select(id - 1, false)
                end
            end
            asrGuiState.rebuildShippingContractsTable = false
        end
    end

    if selectedShippingContractId ~= nil and asrState[asrEnum.SHIPPING_CONTRACTS] ~= nil and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] ~= nil and shippingContractSettingsTable ~= nil then

        if asrGuiState.rebuildShippingContractsSettingsTable == true then 

            log("gui: rebuildShippingContractsLayout: initial build")

            shippingContractSettingsTable:deleteAll()
            local shippingContractNameLabel = api.gui.comp.TextView.new(i18Strings.name)
            local shippingContractSettingsNameLabel = api.gui.comp.TextView.new("")
            shippingContractSettingsNameLabel:setId("asr.shippingContractSettingsNameLabel-" .. selectedShippingContractId)
            if  asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] ~= nil then
                shippingContractSettingsNameLabel:setText(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.NAME], false)
            end
            shippingContractSettingsTable:addRow({shippingContractNameLabel, shippingContractSettingsNameLabel})
            shippingContractSettingsTable:addRow({api.gui.comp.TextView.new(""), api.gui.comp.TextView.new("")})

            local shippingContractSelectionTable = api.gui.comp.Table.new(2, 'NONE')
            shippingContractSelectionTable:setGravity(0,0)
            asrGuiObjects.shippingContractSelectionTable = shippingContractSelectionTable
            -- shippingContractSelectionTable:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.shippingContractSettingsTable.columns[2], 150))
            -- shippingContractSelectionTable:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.shippingContractSettingsTable.columns[2], 150))

            shippingContractSelectionTable:setId("asr.shippingContractSelectionTable-"  .. selectedShippingContractId)
            shippingContractSelectionTable:setColWidth(0, asrGuiDimensions.shippingContractSettingsInternalTable.columns[1])
            shippingContractSelectionTable:setColWidth(1, asrGuiDimensions.shippingContractSettingsInternalTable.columns[2])


            -- supplier
            local shippingindustryContractSupplierLabel = api.gui.comp.TextView.new(i18Strings.supplier)
            local shippingindustryContractSupplierButtonLayout = createIndustryButtonLayout(
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and 
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID] 
                and asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])] and 
                asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.NAME],
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and 
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                asrEnum.industry.SUPPLIER, "industry" )
        
            local shippingindustryContractSupplierButton = api.gui.comp.Button.new(shippingindustryContractSupplierButtonLayout, false)
            shippingindustryContractSupplierButton:setId("asr.shippingindustryContractSupplierInput-"  .. selectedShippingContractId)
            shippingContractSelectionTable:addRow({shippingindustryContractSupplierLabel, shippingindustryContractSupplierButton})

            local currentRowCount = shippingContractSettingsTable:getNumRows()
            shippingindustryContractSupplierButton:onClick(function ()
                
                local list = asrGuiObjects.shippingContractIndustryDropDownList
                if list:isVisible() then
                    list:setVisible(false, false)
                else

                    local settingsTabletHeight = getDistance("shippingContractSettingsTable", currentRowCount - 1)
                    local index = shippingContractSettingsLayout:getIndex(shippingContractIndustryDropDownList)
                    log("gui: rebuildShippingContractsLayout: height: " .. settingsTabletHeight .. " index: " .. index)
                    -- move the dropdown list into position
                    shippingContractSettingsLayout:setPosition(shippingContractSettingsLayout:getIndex(shippingContractIndustryDropDownList), shippingContractSettingsTable:getColWidth(0) + shippingContractSelectionTable:getColWidth(0), settingsTabletHeight + shippingContractSelectionTable:getRowHeight(0))

                    local supplierIndustries = {}
                    local keepConsumer = true

                    if asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] and 
                        not asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID] then
                            -- asrHelper.tlog(asrState[asrEnum.INDUSTRIES][asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID]])

                        log("gui: rebuildShippingContractsLayout: using filtered suppliers")
                        local suppliers
                        if asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])] and 
                            asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.SUPPLIERS] and
                            asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.SUPPLIERS][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID])] then 
                            suppliers = asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.SUPPLIERS][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID])]
                        end
                        if suppliers ~= nil then 
                            for _, industryId in pairs(suppliers) do 
                                table.insert(supplierIndustries, {
                                    cargoId = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                                    industryId = industryId,
                                    industryName = asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.NAME],
                                    industryKind = "supplier",
                                    industryType = asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.TYPE],
                                })
                            end
                        end
                    else 
                        keepConsumer = false
                        log("gui: rebuildShippingContractsLayout: using all suppliers")
                        if asrState[asrEnum.INDUSTRIES] ~= nil then 
                            for industryId, industry in pairs(asrState[asrEnum.INDUSTRIES]) do 
                                if industry[asrEnum.industry.SUPPLIER] then
                                    for cargoId, _ in pairs(industry[asrEnum.industry.SUPPLIER]) do
                                        table.insert(supplierIndustries, {
                                            cargoId = cargoId,
                                            industryId = industryId,
                                            industryName = industry[asrEnum.industry.NAME] ~= nil and industry[asrEnum.industry.NAME] or "unknown ???",
                                            industryKind = "supplier",
                                            industryType = industry[asrEnum.industry.TYPE],
                                        })
                                    end
                                end
                            end
                        end
                    end
                    
                    -- normalise the list
                    -- log("gui: rebuildShippingContractsLayout: supplierIndustries")
                    -- asrHelper.tprint(supplierIndustries)
                    local dropDownEntries = {}
                    for _,industry in pairs(supplierIndustries) do 
                        local industryKindIcon
                        if industry.industryKind == "supplier" then
                            industryKindIcon = "ui/icons/game-menu/load_game@2x.tga"
                        elseif industry.industryKind == "consumer" then
                            industryKindIcon = "ui/icons/game-menu/save_game@2x.tga"
                        end
                        local industryTypeIcon
                        if industry.industryType == "town" then
                            industryTypeIcon = "ui/ui/button/medium/towns@2x.tga"
                        -- elseif industry.industryType == "industry" then
                        --     industryTypeIcon = "ui/ui/button/medium/industries@2x.tga"
                        end
                        local consumerId
                        if keepConsumer then
                            consumerId = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID]
                        else
                            consumerId = false
                        end
                        table.insert(dropDownEntries, {
                            text = industry.industryName,
                            textTip = industry.industryKind, 
                            icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(industry.cargoId)]) .. "@2x.tga",
                            iconTip = string.lower(cargoTypes[tonumber(industry.cargoId)]),
                            icon2 = industryKindIcon,
                            icon2Tip = industry.industryKind,
                            icon3 = industryTypeIcon,
                            value = {
                                [asrEnum.shippingContract.SUPPLIER_ID] = industry.industryId,
                                [asrEnum.shippingContract.CONSUMER_ID] = consumerId,
                                [asrEnum.shippingContract.CARGO_ID] = industry.cargoId,
                            }
                        })
                    end
                    showDropDownList("shippingContractIndustryDropDownList", dropDownEntries)
                end
            end)

            -- consumer
            local shippingindustryContractConsumerLabel = api.gui.comp.TextView.new(i18Strings.consumer)
            local shippingindustryContractConsumerButtonLayout = createIndustryButtonLayout(
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and 
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] and 
                asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])] and 
                asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.NAME],
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                asrEnum.industry.CONSUMER,
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] and 
                asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])] and 
                asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.TYPE]
                )
        
            local shippingindustryContractConsumerButton = api.gui.comp.Button.new(shippingindustryContractConsumerButtonLayout, false)
            shippingindustryContractConsumerButton:setId("asr.shippingindustryContractConsumerInput-"  .. selectedShippingContractId)
            shippingContractSelectionTable:addRow({shippingindustryContractConsumerLabel, shippingindustryContractConsumerButton})

            local currentRowCount = shippingContractSettingsTable:getNumRows()
            shippingindustryContractConsumerButton:onClick(function ()
                log("gui: rebuildShippingContractsLayout: consumer click")
                local list = asrGuiObjects.shippingContractIndustryDropDownList
                if list:isVisible() then
                    list:setVisible(false, false)
                else

                    local settingsTabletHeight = getDistance("shippingContractSettingsTable", currentRowCount - 1)
                    local shippingContractSettingsTableHeight =  getDistance("shippingContractSelectionTable", 2)
                    local index = shippingContractSettingsLayout:getIndex(shippingContractIndustryDropDownList)
                    log("gui: rebuildShippingContractsLayout: height: (" .. settingsTabletHeight .. ", " .. shippingContractSettingsTableHeight .. ") index: " .. index)
                    -- move the dropdown list into position
                    shippingContractSettingsLayout:setPosition(shippingContractSettingsLayout:getIndex(shippingContractIndustryDropDownList), shippingContractSettingsTable:getColWidth(0) + shippingContractSelectionTable:getColWidth(0), settingsTabletHeight + getDistance("shippingContractSelectionTable", 2))

                    local consumerIndustries = {}
                    local keepSupplier = true

                    if asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID] and 
                         not asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] then
                        log("gui: rebuildShippingContractsLayout: using filtered consumers")
                        local consumers
                        if asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])] and 
                            asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.CONSUMERS] and 
                            asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.CONSUMERS][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID])] then
                           consumers = asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.CONSUMERS][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID])]
                        end
                        if consumers ~= nil then 
                            for _, industryId in pairs(consumers) do 
                                table.insert(consumerIndustries, {
                                    cargoId = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                                    industryId = industryId,
                                    industryName = asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.NAME],
                                    industryKind = "consumer",
                                    industryType = asrState[asrEnum.INDUSTRIES][tostring(industryId)][asrEnum.industry.TYPE],
                                })
                            end
                        end
                    else 
                        keepSupplier = false
                        log("gui: rebuildShippingContractsLayout: using all consumers")
                        if asrState[asrEnum.INDUSTRIES] ~= nil then 
                            for industryId, industry in pairs(asrState[asrEnum.INDUSTRIES]) do 
                                if industry[asrEnum.industry.CONSUMER] then
                                    for cargoId, _ in pairs(industry[asrEnum.industry.CONSUMER]) do
                                        table.insert(consumerIndustries, {
                                            cargoId = cargoId,
                                            industryId = industryId,
                                            industryName = industry[asrEnum.industry.NAME] ~= nil and industry[asrEnum.industry.NAME] or "unknown ???",
                                            industryKind = "consumer",
                                            industryType = industry[asrEnum.industry.TYPE],
                                        })
                                    end
                                end
                            end
                        end
                    end                    
                    -- normalise the list
                    -- log("gui: rebuildShippingContractsLayout: consumer list")
                    -- asrHelper.tprint(consumerIndustries)
                    local dropDownEntries = {}
                    for _,industry in pairs(consumerIndustries) do 
                        local industryKindIcon
                        if industry.industryKind == "supplier" then
                            industryKindIcon = "ui/icons/game-menu/load_game@2x.tga"
                        elseif industry.industryKind == "consumer" then
                            industryKindIcon = "ui/icons/game-menu/save_game@2x.tga"
                        end
                        local industryTypeIcon
                        if industry.industryType == "town" then
                            industryTypeIcon = "ui/ui/button/medium/towns@2x.tga"
                        -- elseif industry.industryType == "industry" then
                        --     industryTypeIcon = "ui/ui/button/medium/industries@2x.tga"
                        end
                        local supplierId
                        if keepSupplier then
                            supplierId = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID]
                        else
                            supplierId = false
                        end

                        table.insert(dropDownEntries, {
                            text = industry.industryName,
                            textTip = industry.industryKind, 
                            icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(industry.cargoId)]) .. "@2x.tga",
                            iconTip = string.lower(cargoTypes[tonumber(industry.cargoId)]),
                            icon2 = industryKindIcon,
                            icon2Tip = industry.industryKind,
                            icon3 = industryTypeIcon,
                            value = {
                                [asrEnum.shippingContract.CONSUMER_ID] = industry.industryId,
                                [asrEnum.shippingContract.SUPPLIER_ID] = supplierId,
                                [asrEnum.shippingContract.CARGO_ID] = industry.cargoId,
                            }
                        })
                    end
                    showDropDownList("shippingContractIndustryDropDownList", dropDownEntries)
                end
            end)

            -- current amount of cargo
            local currentAmountWrapper = api.gui.comp.Component.new("asr.amountWrapper")
            currentAmountWrapper:setId("asr.currentAmountWrapper-"  .. selectedShippingContractId)
            local currentAmountLayout = api.gui.layout.BoxLayout.new("VERTICAL");
            currentAmountWrapper:setGravity(0,0)
            currentAmountWrapper:setLayout(currentAmountLayout)

            local currentTotalAmountLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
            local currentTotalAmountWrapper = api.gui.comp.Component.new("asr.totalAmountWrapper")
            currentTotalAmountWrapper:setLayout(currentTotalAmountLayout)

            local currentTotalAmountIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
            currentTotalAmountIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
            currentTotalAmountLayout:addItem(currentTotalAmountIcon)

            local currentValue = 0

            if asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT] then
                currentValue = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT]
                    
            end

            local currentTotalAmountText = api.gui.comp.TextView.new(tostring(currentValue))
            currentTotalAmountText:setId("asr.currentTotalAmountText-"  .. selectedShippingContractId)
            currentTotalAmountLayout:addItem(currentTotalAmountText)

            currentAmountLayout:addItem(currentTotalAmountWrapper)

            shippingContractSettingsTable:addRow({currentAmountWrapper, shippingContractSelectionTable})

            asrGuiState.rebuildShippingContractsSettingsTable = false
        else
            -- just a refresh

            if asrState[asrEnum.SHIPPING_CONTRACTS] then 
                -- print("gui: rebuildShippingContractsLayout: running refresh of the shipping contract table")
                for shippingContractId, shippingContract in pairs(asrState[asrEnum.SHIPPING_CONTRACTS]) do    
                    local shippingContractCargoIcon = api.gui.util.getById("asr.shippingContractCargoIcon-" .. tostring(shippingContractId))
                    local shippingContractNameTextInput = api.gui.util.getById("asr.shippingContractNameTextInput-" .. tostring(shippingContractId))
                    local shippingContractNameLabel = api.gui.util.getById("asr.shippingContractNameLabel-" .. tostring(shippingContractId))
                    local shippingContractDeleteButton = api.gui.util.getById("asr.shippingContractDeleteButton-" .. tostring(shippingContractId))

                    if shippingContractCargoIcon then
                        if shippingContract[asrEnum.shippingContract.CARGO_ID] and cargoTypes[tonumber(shippingContract[asrEnum.shippingContract.CARGO_ID])] then
                            shippingContractCargoIcon:setImage("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(shippingContract[asrEnum.shippingContract.CARGO_ID])]) .. "@2x.tga", true)
                        end
                    end
                    if shippingContractNameLabel then
                        shippingContractNameLabel:setText(shippingContract[asrEnum.shippingContract.NAME], false)
                    else
                        log("gui: rebuildShippingContractsLayout: can't find name label")
                    end
                    if shippingContractNameTextInput then
                        if not shippingContractNameTextInput:isVisible() then
                            shippingContractNameTextInput:setText(shippingContract[asrEnum.shippingContract.NAME], false)
                        end
                    else
                        log("gui: rebuildShippingContractsLayout: can't find name text input")
                    end
                    if shippingContractDeleteButton then
                        if shippingContract[asrEnum.shippingContract.IN_USE] and shippingContract[asrEnum.shippingContract.IN_USE] ~= 0 then
                            shippingContractDeleteButton:setEnabled(false)
                            shippingContractDeleteButton:setTooltip(i18Strings.in_use_cant_delete)
                        else 
                            shippingContractDeleteButton:setEnabled(true)
                            shippingContractDeleteButton:setTooltip(i18Strings.delete_shipping_contract)
                        end    
                    end
                end
                shippingContractsTable:setOrder(asrHelper.getSortOrder(asrState[asrEnum.SHIPPING_CONTRACTS], asrEnum.shippingContract.NAME))
            end
    
            local shippingContractSettingsNameLabel = api.gui.util.getById("asr.shippingContractSettingsNameLabel-" .. selectedShippingContractId)
            if  shippingContractSettingsNameLabel and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] ~= nil then
                shippingContractSettingsNameLabel:setText(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.NAME], false)
            end

            local shippingindustryContractSupplierButtonLayout = createIndustryButtonLayout(
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID] and asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.SUPPLIER_ID])][asrEnum.industry.NAME] or nil,
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                asrEnum.industry.SUPPLIER,
                "industry")
            local shippingindustryContractSupplierButton = api.gui.util.getById("asr.shippingindustryContractSupplierInput-"  .. selectedShippingContractId)
            if shippingindustryContractSupplierButton then 
                shippingindustryContractSupplierButton:setContent(shippingindustryContractSupplierButtonLayout)
            end

            local shippingindustryContractConsumerButtonLayout = createIndustryButtonLayout(
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] and asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.NAME] or nil,
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_ID],
                asrEnum.industry.CONSUMER,
                asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID] and asrState[asrEnum.INDUSTRIES][tostring(asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CONSUMER_ID])][asrEnum.industry.TYPE] or nil)
            local shippingindustryContractConsumerButton = api.gui.util.getById("asr.shippingindustryContractConsumerInput-"  .. selectedShippingContractId)
            if shippingindustryContractConsumerButton then 
                shippingindustryContractConsumerButton:setContent(shippingindustryContractConsumerButtonLayout)
            end     

            -- current cargo
            local currentValue = 0

            if asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT] then
                currentValue = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)][asrEnum.shippingContract.CARGO_AMOUNT]
            end

            local currentTotalAmountText = api.gui.util.getById("asr.currentTotalAmountText-"  .. selectedShippingContractId)
            currentTotalAmountText:setText(tostring(currentValue), false)
            
        end
    else
        -- log("gui: rebuildShippingContractsLayout: nothing in the table to display")
        -- if selectedShippingContractId ~= nil then
        --     log("gui: rebuildShippingContractsLayout: selcted contract id ok")
        -- end
        -- if asrState[asrEnum.SHIPPING_CONTRACTS] and asrState[asrEnum.SHIPPING_CONTRACTS][tostring(selectedShippingContractId)] ~= nil then
        --     log("gui: rebuildShippingContractsLayout: selcted contract details ok")
        -- end
        if shippingContractSettingsTable ~= nil then
            -- log("gui: rebuildShippingContractsLayout: contract settings table ok")
            shippingContractSettingsTable:deleteAll()
        end        
    end
end

-- cargo groups layout - complete
local function rebuildCargoGroupsLayout() 

    -- log("gui: rebuildCargoGroupsLayout")

    local cargoTrackingTabLayout = asrGuiObjects.cargoTrackingTabLayout
    local cargoGroupsLayout = asrGuiObjects.cargoGroupsLayout
    local cargoGroupSettingsLayout = asrGuiObjects.cargoGroupSettingsLayout
    local cargoGroupsTable = asrGuiObjects.cargoGroupsTable
    local cargoGroupSettingsTable = asrGuiObjects.cargoGroupSettingsTable
    local cargoGroupDropDownList = asrGuiObjects.cargoGroupDropDownList

    local selectedCargoGroupId = asrGuiState.selectedCargoGroup

    if cargoGroupsLayout == nil then

        log("gui: rebuildCargoGroupsLayout: building cargo groups main layout")
        cargoGroupsLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
        cargoGroupsLayout:setId("asr.cargoGroupsGroupsLayout")
        local cargoGroupsWrapper = api.gui.comp.Component.new("asr.cargoGroupsWrapper")
        cargoGroupsWrapper:setLayout(cargoGroupsLayout)

        local cargoGroupsScrollLayout = api.gui.layout.BoxLayout.new("VERTICAL");
        local cargoGroupsScrollWrapper = api.gui.comp.Component.new("asr.cargoGroupsScrollWrapper")
        cargoGroupsScrollWrapper:setLayout(cargoGroupsScrollLayout)

        local cargoGroupsScrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.TextView.new('cargoGroupsScrollArea'), "asr.cargoGroupsScrollArea")
        cargoGroupsScrollArea:setId("asr.cargoGroupsScrollArea")
        cargoGroupsScrollArea:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupsScrollArea.width, asrGuiDimensions.cargoGroupsScrollArea.height))
        cargoGroupsScrollArea:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupsScrollArea.width, asrGuiDimensions.cargoGroupsScrollArea.height))

        local newCargoGroupButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
        local newCargoGroupButtonIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
        newCargoGroupButtonIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
        newCargoGroupButtonIcon:setStyleClassList({"asrCargoButton"})
        newCargoGroupButtonLayout:addItem(newCargoGroupButtonIcon)
        newCargoGroupButtonLayout:addItem(api.gui.comp.TextView.new(i18Strings.new_cargo_group))
        local newCargoGroupButton = api.gui.comp.Button.new(newCargoGroupButtonLayout, false)
        newCargoGroupButton:setStyleClassList({"asrNewButton"})
        newCargoGroupButton:onClick(function ()
            local cargoGroupId = getNewId()
            asrGuiState.selectedCargoGroup = cargoGroupId
            log("gui: rebuildCargoGroupsLayout: selecting id: " .. cargoGroupId)
            sendEngineCommand("asrUpdateCargoGroup", { cargoGroupId = cargoGroupId, property = asrEnum.cargoGroup.NAME, value = "Cargo group #" .. cargoGroupId })
            asrGuiState.rebuildCargoGroupsSettingsTable = true
        end)

        cargoGroupsTable = api.gui.comp.Table.new(4, 'SINGLE')
        cargoGroupsTable:setColWidth(1,asrGuiDimensions.cargoGroupsScrollArea.width - 100)
        cargoGroupsTable:setId("asr.cargoGroupsTable")
        asrGuiObjects.cargoGroupsTable = cargoGroupsTable
        cargoGroupsTable:onHover(function (id) 
            for mapId, cargoGroupId in pairs(asrGuiState.cargoGroupsRowMap) do
                local cargoGroupEditButton = api.gui.util.getById("asr.cargoGroupEditButton-" .. tostring(cargoGroupId))
                local cargoGroupDeleteButton = api.gui.util.getById("asr.cargoGroupDeleteButton-" .. tostring(cargoGroupId))
                if cargoGroupEditButton then
                    if id + 1 == mapId then
                        cargoGroupEditButton:setVisible(true, false)
                    else
                        cargoGroupEditButton:setVisible(false, false)
                    end
                end
                if cargoGroupDeleteButton then
                    if id + 1 == mapId then
                        cargoGroupDeleteButton:setVisible(true, false)
                    else
                        cargoGroupDeleteButton:setVisible(false, false)
                    end
                end
            end
        end)
        cargoGroupsTable:onSelect(function (id) 
            log("gui: rebuildCargoGroupsLayout: on select: " .. id)
            if id >= 0 then 
                asrGuiState.rebuildCargoGroupsSettingsTable = true
                asrGuiState.selectedCargoGroup = asrGuiState.cargoGroupsRowMap[id + 1]
                log("gui: rebuildCargoGroupsLayout: forcing cargo group layout refresh on select")
                rebuildCargoGroupsLayout()
            end            
        end)

        asrGuiObjects.cargoGroupsTable = cargoGroupsTable

        cargoGroupsScrollArea:setContent(cargoGroupsTable)
        cargoGroupsScrollLayout:addItem(newCargoGroupButton)
        cargoGroupsScrollLayout:addItem(cargoGroupsScrollArea)
        cargoGroupsLayout:addItem(cargoGroupsScrollWrapper)


        cargoGroupSettingsLayout = api.gui.layout.AbsoluteLayout.new()
        cargoGroupSettingsLayout:setId("asr.cargoGroupSettingsLayout")
        local cargoGroupSettingsWrapper = api.gui.comp.Component.new("asr.cargoGroupSettingsWrapper")
        cargoGroupSettingsWrapper:setLayout(cargoGroupSettingsLayout)
        asrGuiObjects.cargoGroupSettingsLayout = cargoGroupSettingsLayout

        cargoGroupSettingsTable = api.gui.comp.Table.new(2, 'NONE')
        cargoGroupSettingsTable:setId("asr.cargoGroupSettingsTable")
        cargoGroupSettingsTable:setColWidth(0,asrGuiDimensions.cargoGroupSettingsTable.columns[1])
        cargoGroupSettingsTable:setColWidth(1,asrGuiDimensions.cargoGroupSettingsTable.columns[2])
        cargoGroupSettingsTable:setGravity(0, 0)
        cargoGroupSettingsLayout:addItem(cargoGroupSettingsTable, api.gui.util.Rect.new(0,0,590,500))
        asrGuiObjects.cargoGroupSettingsTable = cargoGroupSettingsTable

        cargoGroupsLayout:addItem(cargoGroupSettingsWrapper)

        cargoTrackingTabLayout:addItem(cargoGroupsWrapper)

        asrGuiObjects.cargoGroupsLayout = cargoGroupsLayout
        asrGuiState.rebuildCargoGroupsTable = true
        log("gui: rebuildCargoGroupsLayout: done building cargo groups main layout")
    end


    if asrGuiState.rebuildCargoGroupsSettingsTable == true then
        cargoGroupSettingsTable:deleteAll()
    end


    if cargoGroupDropDownList == nil then
        log("gui: rebuildCargoGroupsLayout: building drop down")
        cargoGroupDropDownList = api.gui.comp.List.new(false, 1 ,false)
        cargoGroupDropDownList:setGravity(0,0)
        cargoGroupDropDownList:setVisible(false,false)
        cargoGroupDropDownList:setStyleClassList({"asrDropList"})        
        asrGuiObjects.cargoGroupDropDownList = cargoGroupDropDownList
        cargoGroupSettingsLayout:addItem(cargoGroupDropDownList, api.gui.util.Rect.new(0,0,100,100))  -- dimesntions don't seem to matter here? 

        cargoGroupDropDownList:onSelect(function (row) 
            if dropDownEntries[row + 1] ~= nil then
                sendEngineCommand("asrAddCargoGroupMember", { cargoGroupId = asrGuiState.selectedCargoGroup, values = dropDownEntries[row + 1] })
            end
            cargoGroupDropDownList:setVisible(false, false)
        end)
        asrGuiObjects.cargoGroupDropDownList = cargoGroupDropDownList
        log("gui: rebuildCargoGroupsLayout: done building drop down")
    end

    if asrGuiState.rebuildCargoGroupsTable == true then
        log("gui: rebuildCargoGroupsLayout: asrGuiState.rebuildCargoGroupsTable is true")
        cargoGroupsTable:deleteAll()
        asrGuiState.cargoGroupsRowMap = {}

        -- select a row if nothing is selected
        if selectedCargoGroupId == nil then
            selectedCargoGroupId = asrHelper.getFirstSortedKey(asrState[asrEnum.CARGO_GROUPS], asrEnum.cargoGroup.NAME)
            asrGuiState.selectedCargoGroup = selectedCargoGroupId
            asrGuiState.rebuildCargoGroupsSettingsTable = true 
        end

        if asrState[asrEnum.CARGO_GROUPS] then 
            log("gui: rebuildCargoGroupsLayout: cargo group table rebuild start here")
            for cargoGroupId, cargoGroup in pairs(asrState[asrEnum.CARGO_GROUPS]) do
                local cargoGroupCargoIcon
                -- if cargoGroup[asrEnum.cargoGroup.CARGO_ID] and cargoTypes and cargoTypes[tonumber(cargoGroup[asrEnum.cargoGroup.CARGO_ID])] then
                --     cargoGroupCargoIcon = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(cargoGroup[asrEnum.cargoGroup.CARGO_ID])]) .. "@2x.tga")
                -- else
                    cargoGroupCargoIcon = api.gui.comp.ImageView.new("ui/empty15.tga")
                -- end
                cargoGroupCargoIcon:setStyleClassList({"asrCargoGroupIcon"})
                cargoGroupCargoIcon:setId("asr.cargoGroupCargoIcon-" .. tostring(cargoGroupId))
                cargoGroupCargoIcon:setMaximumSize(api.gui.util.Size.new(15, 15))

                local cargoGroupNameLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
                local cargoGroupNameWrapper = api.gui.comp.Component.new("asr.cargoGroupNameWrapper")
                cargoGroupNameWrapper:setLayout(cargoGroupNameLayout)
                
                local cargoGroupNameLabel = api.gui.comp.TextView.new(cargoGroup[asrEnum.cargoGroup.NAME])
                cargoGroupNameLabel:setId("asr.cargoGroupNameLabel-" .. tostring(cargoGroupId))
                cargoGroupNameLayout:addItem(cargoGroupNameLabel)
                local cargoGroupNameTextInput = api.gui.comp.TextInputField.new(cargoGroup[asrEnum.cargoGroup.NAME])
                cargoGroupNameTextInput:setId("asr.cargoGroupNameTextInput-" .. tostring(cargoGroupId))
                cargoGroupNameLayout:addItem(cargoGroupNameTextInput)
                cargoGroupNameTextInput:setVisible(false, false)
                cargoGroupNameTextInput:setText(cargoGroup[asrEnum.cargoGroup.NAME], false)
                cargoGroupNameTextInput:selectAll()
                cargoGroupNameTextInput:setMaxLength(55)
                cargoGroupNameTextInput:onFocusChange(function (hasFocus) 
                    if not hasFocus then
                        local value = cargoGroupNameTextInput:getText()
                        sendEngineCommand("asrUpdateCargoGroup", { cargoGroupId = cargoGroupId, property = asrEnum.cargoGroup.NAME, value = value})
                        cargoGroupNameTextInput:setVisible(false, false)
                        cargoGroupNameLabel:setText(value, false)
                        cargoGroupNameLabel:setVisible(true, false)
                    end
                end)
                cargoGroupNameTextInput:onEnter(function () 
                    local value = cargoGroupNameTextInput:getText()
                    sendEngineCommand("asrUpdateCargoGroup", { cargoGroupId = cargoGroupId, property = asrEnum.cargoGroup.NAME, value = value})
                    cargoGroupNameTextInput:setVisible(false, false)
                    cargoGroupNameLabel:setText(value, false)
                    cargoGroupNameLabel:setVisible(true, false)
                end)
                cargoGroupNameTextInput:onCancel(function () 
                    cargoGroupNameTextInput:setText(cargoGroup[asrEnum.cargoGroup.NAME], false)
                    cargoGroupNameTextInput:setVisible(false, false)
                    cargoGroupNameLabel:setText(cargoGroup[asrEnum.cargoGroup.NAME], false)
                    cargoGroupNameLabel:setVisible(true, false)
                end)

                local cargoGroupEditIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/edit.tga")
                cargoGroupEditIcon:setId("asr.cargoGroupEditIcon-" .. tostring(cargoGroupId))
                cargoGroupEditIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                local cargoGroupEditButton = api.gui.comp.Button.new(cargoGroupEditIcon, false)
                cargoGroupEditButton:setId("asr.cargoGroupEditButton-" .. tostring(cargoGroupId))
                cargoGroupEditButton:setStyleClassList({"asrMiniListButton"})
                cargoGroupEditButton:setVisible(false, false)
                cargoGroupEditButton:setTooltip(i18Strings.rename_cargo_group)
                cargoGroupEditButton:onClick(function ()
                    if cargoGroupNameLabel:isVisible() then
                        cargoGroupNameLabel:setVisible(false, false)
                        cargoGroupNameTextInput:setVisible(true, false)
                    else
                        cargoGroupNameLabel:setVisible(true, false)
                        cargoGroupNameTextInput:setVisible(false, false)
                    end
                end)

                local cargoGroupDeleteIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/sell_thin.tga")
                cargoGroupDeleteIcon:setId("asr.cargoGroupDeleteIcon-" .. tostring(cargoGroupId))
                cargoGroupDeleteIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                local cargoGroupDeleteButton = api.gui.comp.Button.new(cargoGroupDeleteIcon, false)
                cargoGroupDeleteButton:setId("asr.cargoGroupDeleteButton-" .. tostring(cargoGroupId))
                cargoGroupDeleteButton:setStyleClassList({"asrMiniListButton"})
                cargoGroupDeleteButton:setVisible(false, false)
                if cargoGroup[asrEnum.cargoGroup.IN_USE] and cargoGroup[asrEnum.cargoGroup.IN_USE] ~= 0 then
                    cargoGroupDeleteButton:setEnabled(false)
                    cargoGroupDeleteButton:setTooltip(i18Strings.in_use_cant_delete)
                else 
                    cargoGroupDeleteButton:setEnabled(true)
                    cargoGroupDeleteButton:setTooltip(i18Strings.delete_cargo_group)
                end
                cargoGroupDeleteButton:onClick(function () 
                    sendEngineCommand("asrDeleteCargoGroup", { cargoGroupId = cargoGroupId })
                    if cargoGroupId == selectedCargoGroupId then
                        asrGuiState.selectedCargoGroup = nil
                    end
                end)
                cargoGroupsTable:addRow({cargoGroupCargoIcon, cargoGroupNameWrapper , cargoGroupEditButton, cargoGroupDeleteButton})
                table.insert(asrGuiState.cargoGroupsRowMap, cargoGroupId)
            end
            cargoGroupsTable:setOrder(asrHelper.getSortOrder(asrState[asrEnum.CARGO_GROUPS], asrEnum.cargoGroup.NAME))

            for id, cargoGroupId in pairs(asrGuiState.cargoGroupsRowMap) do
                if tostring(cargoGroupId) == tostring(selectedCargoGroupId) then
                    log("gui: rebuildCargoGroupsLayout: found selected id: " .. id)
                    cargoGroupsTable:select(id - 1, false)
                end
            end
            asrGuiState.rebuildCargoGroupsTable = false
        end
    end

    if selectedCargoGroupId ~= nil and asrState[asrEnum.CARGO_GROUPS] ~= nil and asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] ~= nil and cargoGroupSettingsTable ~= nil then

        if asrGuiState.rebuildCargoGroupsSettingsTable == true then 

            log("gui: rebuildCargoGroupsLayout: initial build of the settings table")
            if selectedCargoGroupId then
                log("gui: rebuildCargoGroupsLayout: cargo group id: " .. selectedCargoGroupId)
            end

            cargoGroupSettingsTable:deleteAll()
            local cargoGroupNameLabel = api.gui.comp.TextView.new(i18Strings.name)
            local cargoGroupSettingsNameLabel = api.gui.comp.TextView.new("")
            cargoGroupSettingsNameLabel:setId("asr.cargoGroupSettingsNameLabel-" .. selectedCargoGroupId)
            if  asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] ~= nil then
                cargoGroupSettingsNameLabel:setText(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.NAME], false)
            end
            cargoGroupSettingsTable:addRow({cargoGroupNameLabel, cargoGroupSettingsNameLabel})
            cargoGroupSettingsTable:addRow({api.gui.comp.TextView.new(""), api.gui.comp.TextView.new("")})

            local cargoGroupSelectionTable = api.gui.comp.Table.new(2, 'NONE')
            cargoGroupSelectionTable:setGravity(0,0)
            asrGuiObjects.cargoGroupSelectionTable = cargoGroupSelectionTable
            cargoGroupSelectionTable:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupSettingsTable.columns[2], 50))
            cargoGroupSelectionTable:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupSettingsTable.columns[2], 50))

            cargoGroupSelectionTable:setId("asr.cargoGroupSelectionTable-"  .. selectedCargoGroupId)
            cargoGroupSelectionTable:setColWidth(0, asrGuiDimensions.cargoGroupSettingsInternalTable.columns[1])
            cargoGroupSelectionTable:setColWidth(1, asrGuiDimensions.cargoGroupSettingsInternalTable.columns[2])

            -- industry
            local cargoGroupIndustryLabel = api.gui.comp.TextView.new(i18Strings.add)
            local cargoGroupIndustryButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
            local cargoGroupIndustryButtonIcon = api.gui.comp.ImageView.new("ui/button/large/industry.tga")
            cargoGroupIndustryButtonIcon:setMaximumSize(api.gui.util.Size.new(20, 20))
            cargoGroupIndustryButtonIcon:setMinimumSize(api.gui.util.Size.new(20, 20))
            cargoGroupIndustryButtonLayout:addItem(cargoGroupIndustryButtonIcon)
            cargoGroupIndustryButtonLayout:addItem(api.gui.comp.TextView.new(i18Strings.industry))
            local cargoGroupIndustryButton = api.gui.comp.Button.new(cargoGroupIndustryButtonLayout, false)
            cargoGroupIndustryButton:setId("asr.cargoGroupIndustryInput-"  .. selectedCargoGroupId)
            local currentSettingsRowCount = cargoGroupSettingsTable:getNumRows()
            cargoGroupSelectionTable:addRow({cargoGroupIndustryLabel, cargoGroupIndustryButton})
            local currentSelectionRowCount = cargoGroupSelectionTable:getNumRows()

            cargoGroupIndustryButton:onClick(function ()
                
                local list = asrGuiObjects.cargoGroupDropDownList
                if list:isVisible() then
                    list:setVisible(false, false)
                else

                    local settingsTabletHeight = getDistance("cargoGroupSettingsTable", currentSettingsRowCount - 1)
                    local selectionTabletHeight = getDistance("cargoGroupSelectionTable", currentSelectionRowCount - 1)
                    local index = cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList)
                    log("gui: height: " .. settingsTabletHeight .. " index: " .. index  )
                    -- move the dropdown list into position
                    cargoGroupSettingsLayout:setPosition(cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList), cargoGroupSettingsTable:getColWidth(0) + cargoGroupSelectionTable:getColWidth(0), settingsTabletHeight + selectionTabletHeight)

                    local industries = {}

                    if asrState[asrEnum.INDUSTRIES] ~= nil then 
                        for industryId, industry in pairs(asrState[asrEnum.INDUSTRIES]) do 
                            if industry[asrEnum.industry.SUPPLIER] then
                                for cargoId, _ in pairs(industry[asrEnum.industry.SUPPLIER]) do                                            
                                    table.insert(industries, {
                                        cargoId = cargoId,
                                        industryId = industryId,
                                        industryName = industry[asrEnum.industry.NAME] ~= nil and industry[asrEnum.industry.NAME] or "unknown ???",
                                        industryKind = "supplier",
                                        industryType = industry[asrEnum.industry.TYPE],
                                    })
                                end
                            end
                        end
                        for industryId, industry in pairs(asrState[asrEnum.INDUSTRIES]) do 
                            if industry[asrEnum.industry.CONSUMER] then
                                for cargoId, _ in pairs(industry[asrEnum.industry.CONSUMER]) do
                                    table.insert(industries, {
                                        cargoId = cargoId,
                                        industryId = industryId,
                                        industryName = industry[asrEnum.industry.NAME] ~= nil and industry[asrEnum.industry.NAME] or "unknown ???",
                                        industryKind = "consumer",
                                        industryType = industry[asrEnum.industry.TYPE],
                                    })
                                end
                            end
                        end

                    end

                    -- normalise the list
                    log("gui: supplierIndustries")
                    local dropDownEntries = {}
                    for _,industry in pairs(industries) do 
                        local industryKindIcon
                        if industry.industryKind == "supplier" then
                            industryKindIcon = "ui/icons/game-menu/load_game@2x.tga"
                        elseif industry.industryKind == "consumer" then
                            industryKindIcon = "ui/icons/game-menu/save_game@2x.tga"
                        end
                        local industryTypeIcon
                        if industry.industryType == "town" then
                            industryTypeIcon = "ui/ui/button/medium/towns@2x.tga"
                        -- elseif industry.industryType == "industry" then
                        --     industryTypeIcon = "ui/ui/button/medium/industries@2x.tga"
                        end
                        -- check if it's not in the members list already
                        local memberFound = false
                        if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
                            for _, memberDetails in pairs(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" and 
                                   memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID] == industry.industryId and
                                   memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == industry.industryKind and
                                   memberDetails[asrEnum.cargoGroupMember.CARGO_ID] == industry.cargoId then
                                    memberFound = true
                                end
                            end
                        end
                        if not memberFound then 
                            table.insert(dropDownEntries, {
                                text = industry.industryName,
                                textTip = industry.industryKind, 
                                icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(industry.cargoId)]) .. "@2x.tga",
                                iconTip = string.lower(cargoTypes[tonumber(industry.cargoId)]),
                                icon2 = industryKindIcon,
                                icon2Tip = industry.industryKind,
                                icon3 = industryTypeIcon,
                                value = {
                                    [asrEnum.cargoGroupMember.TYPE] = "industry",
                                    [asrEnum.cargoGroupMember.INDUSTRY_ID] = industry.industryId,
                                    [asrEnum.cargoGroupMember.INDUSTRY_KIND] = industry.industryKind,
                                    [asrEnum.cargoGroupMember.CARGO_ID] = industry.cargoId,
                                }
                            })
                        end
                    end
                    showDropDownList("cargoGroupDropDownList", dropDownEntries, true)
                end
            end)

            -- shipping contract
            local cargoGroupShippingContractLabel = api.gui.comp.TextView.new("Add")
            local cargoGroupShippingContractButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
            local cargoGroupShippingContractButtonIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/configure_line@2x.tga")
            cargoGroupShippingContractButtonIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
            cargoGroupShippingContractButtonIcon:setMinimumSize(api.gui.util.Size.new(18, 18))
            cargoGroupShippingContractButtonLayout:addItem(cargoGroupShippingContractButtonIcon)
            cargoGroupShippingContractButtonLayout:addItem(api.gui.comp.TextView.new(i18Strings.shipping_contract))
            local cargoGroupShippingContractButton = api.gui.comp.Button.new(cargoGroupShippingContractButtonLayout, false)
            cargoGroupShippingContractButton:setId("asr.cargoGroupShippingContractInput-"  .. selectedCargoGroupId)
            local currentSettingsRowCount = cargoGroupSettingsTable:getNumRows()
            cargoGroupSelectionTable:addRow({cargoGroupShippingContractLabel, cargoGroupShippingContractButton})
            local currentSelectionRowCount = cargoGroupSelectionTable:getNumRows()

            cargoGroupShippingContractButton:onClick(function ()
                
                local list = asrGuiObjects.cargoGroupDropDownList
                if list:isVisible() then
                    list:setVisible(false, false)
                else

                    local settingsTabletHeight = getDistance("cargoGroupSettingsTable", currentSettingsRowCount - 1)
                    local selectionTabletHeight = getDistance("cargoGroupSelectionTable", currentSelectionRowCount - 1)
                    local index = cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList)
                    log("gui: height: " .. settingsTabletHeight .. " index: " .. index  )
                    -- move the dropdown list into position
                    cargoGroupSettingsLayout:setPosition(cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList), cargoGroupSettingsTable:getColWidth(0) + cargoGroupSelectionTable:getColWidth(0), settingsTabletHeight + selectionTabletHeight)

                    local shippingContracts = {}

                    if asrState[asrEnum.SHIPPING_CONTRACTS] then
                        for shippingContractId, shippingContractDetails in pairs(asrState[asrEnum.SHIPPING_CONTRACTS]) do
                            table.insert(shippingContracts, {
                                shippingContractId = shippingContractId,
                                cargoId = shippingContractDetails[asrEnum.shippingContract.CARGO_ID],
                                shippingContractName = shippingContractDetails[asrEnum.shippingContract.NAME]
                                
                            })
                        end
                    end
                    -- normalise the list
                    log("gui: shipping contracts")
                    local dropDownEntries = {}
                    for _,shippingContract in pairs(shippingContracts) do 

                        -- check if it's not in the members list already
                        local memberFound = false
                        if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
                            for _, memberDetails in pairs(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" and 
                                   memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID] == shippingContract.shippingContractId and
                                   memberDetails[asrEnum.cargoGroupMember.CARGO_ID] == shippingContract.cargoId then
                                    memberFound = true
                                end
                            end
                        end
                        if not memberFound then 
                            table.insert(dropDownEntries, {
                                text = shippingContract.shippingContractName,
                                icon = "ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(shippingContract.cargoId)]) .. "@2x.tga",
                                iconTip = string.lower(cargoTypes[tonumber(shippingContract.cargoId)]),
                                icon2 = "ui/icons/game-menu/configure_line@2x.tga",
                                icon2Tip = "",
                                value = {
                                    [asrEnum.cargoGroupMember.TYPE] = "shippingContract",
                                    [asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID] = shippingContract.shippingContractId,
                                    [asrEnum.cargoGroupMember.CARGO_ID] = shippingContract.cargoId,
                            }
                            })
                        end
                    end
                    showDropDownList("cargoGroupDropDownList", dropDownEntries, true)
                end
            end)

            -- cargo group
            local cargoGroupCargoGroupLabel = api.gui.comp.TextView.new("Add")
            local cargoGroupCargoGroupButtonLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
            local cargoGroupCargoGroupButtonIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
            cargoGroupCargoGroupButtonIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
            cargoGroupCargoGroupButtonIcon:setMinimumSize(api.gui.util.Size.new(18, 18))
            cargoGroupCargoGroupButtonLayout:addItem(cargoGroupCargoGroupButtonIcon)
            cargoGroupCargoGroupButtonLayout:addItem(api.gui.comp.TextView.new(i18Strings.cargo_group))
            local cargoGroupCargoGroupButton = api.gui.comp.Button.new(cargoGroupCargoGroupButtonLayout, false)
            cargoGroupCargoGroupButton:setId("asr.cargoGroupCargoGroupInput-"  .. selectedCargoGroupId)
            local currentSettingsRowCount = cargoGroupSettingsTable:getNumRows()
            cargoGroupSelectionTable:addRow({cargoGroupCargoGroupLabel, cargoGroupCargoGroupButton})
            local currentSelectionRowCount = cargoGroupSelectionTable:getNumRows()

            cargoGroupCargoGroupButton:onClick(function ()
                
                local list = asrGuiObjects.cargoGroupDropDownList
                if list:isVisible() then
                    list:setVisible(false, false)
                else

                    local settingsTabletHeight = getDistance("cargoGroupSettingsTable", currentSettingsRowCount - 1)
                    local selectionTabletHeight = getDistance("cargoGroupSelectionTable", currentSelectionRowCount - 1)
                    local index = cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList)
                    log("gui: height: " .. settingsTabletHeight .. " index: " .. index  )
                    -- move the dropdown list into position
                    cargoGroupSettingsLayout:setPosition(cargoGroupSettingsLayout:getIndex(cargoGroupDropDownList), cargoGroupSettingsTable:getColWidth(0) + cargoGroupSelectionTable:getColWidth(0), settingsTabletHeight + selectionTabletHeight)

                    local cargoGroups = {}

                    if asrState[asrEnum.CARGO_GROUPS] then
                        for cargoGroupId, cargoGroupDetails in pairs(asrState[asrEnum.CARGO_GROUPS]) do
                            table.insert(cargoGroups, {
                                cargoGroupName = cargoGroupDetails[asrEnum.cargoGroup.NAME],
                                cargoGroupId = cargoGroupId
                            })
                        end
                    end
                    -- normalise the list
                    log("gui: cargo groups")
                    local dropDownEntries = {}
                    for _,cargoGroup in pairs(cargoGroups) do 
                        -- check if it's not in the members list already
                        local memberFound = false
                        if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
                            for _, memberDetails in pairs(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                                if memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" and 
                                   memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID] == cargoGroup.cargoGroupId then
                                    memberFound = true
                                end
                            end
                        end
                        if not memberFound then 
                            table.insert(dropDownEntries, {
                                text = cargoGroup.cargoGroupName,
                                icon2 = "ui/icons/game-menu/cargo@2x.tga",
                                iconTip = "",
                                icon2Tip = "",
                                value = {
                                    [asrEnum.cargoGroupMember.TYPE] = "cargoGroup",
                                    [asrEnum.cargoGroupMember.CARGO_GROUP_ID] = cargoGroup.cargoGroupId,
                                }
                            })
                        end
                    end
                    showDropDownList("cargoGroupDropDownList", dropDownEntries, true)
                end
            end)


            -- current list of members
            local cargoGroupMembersScrollLayout = api.gui.layout.BoxLayout.new("VERTICAL");
            local cargoGroupMembersScrollWrapper = api.gui.comp.Component.new("asr.cargoGroupMembersScrollWrapper")
            cargoGroupMembersScrollWrapper:setLayout(cargoGroupMembersScrollLayout)
    
            local cargoGroupMembersScrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.TextView.new('cargoGroupMembersScrollArea'), "asr.cargoGroupMembersScrollArea")
            cargoGroupMembersScrollArea:setId("asr.cargoGroupMembersScrollArea-"  .. selectedCargoGroupId)
            cargoGroupMembersScrollArea:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupMembersScrollArea.width, asrGuiDimensions.cargoGroupMembersScrollArea.height))
            cargoGroupMembersScrollArea:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.cargoGroupMembersScrollArea.width, asrGuiDimensions.cargoGroupMembersScrollArea.height))
        
            local cargoGroupMembersTable = api.gui.comp.Table.new(4, 'SINGLE')
            cargoGroupMembersTable:setColWidth(2,asrGuiDimensions.cargoGroupMembersScrollArea.width - 140)
            cargoGroupMembersTable:setId("asr.cargoGroupMembersTable-"  .. selectedCargoGroupId)

            cargoGroupMembersTable:onHover(function (id) 
                for mapId, cargoGroupMemberId in pairs(asrGuiState.cargoGroupMembersRowMap) do
                    local cargoGroupMemberDeleteButton = api.gui.util.getById("asr.cargoGroupMemberDeleteButton-" .. tostring(selectedCargoGroupId) .. "-" .. tostring(cargoGroupMemberId))
                    if cargoGroupMemberDeleteButton then
                        if id + 1 == mapId then
                            cargoGroupMemberDeleteButton:setVisible(true, false)
                        else
                            cargoGroupMemberDeleteButton:setVisible(false, false)
                        end
                    end
                end
                if id == -1 then
                    cargoGroupMembersTable:select(-1, false)
                end
            end)
    
            asrGuiState.cargoGroupMembersRowMap= {}
            local memberNamesMap = {}
            if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
                for memberId, memberDetails in pairs(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                    local memberNameString, memberNameWrapper, memberIcon1, memberIcon2
                    if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" then
                        memberNameString = asrState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.NAME]
                        local memberNameLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                        memberNameWrapper = api.gui.comp.Component.new("asr.cargoGroupMemberNameWrapper")
                        memberNameLayout:addItem(api.gui.comp.TextView.new(memberNameString))
                        memberNameWrapper:setLayout(memberNameLayout)
                        if asrState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.TYPE] == "town" then
                            local townIcon = api.gui.comp.ImageView.new("ui/ui/button/medium/towns@2x.tga")
                            townIcon:setMaximumSize(api.gui.util.Size.new(15,15))
                            memberNameLayout:addItem(townIcon)
                        end
                        if memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "supplier" then
                            memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/load_game@2x.tga")
                            memberIcon1:setMaximumSize(api.gui.util.Size.new(12, 12))
                            memberIcon1:setStyleClassList({"asrIndustryKind"})
                        elseif memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "consumer" then
                            memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/save_game@2x.tga")
                            memberIcon1:setMaximumSize(api.gui.util.Size.new(12, 12))
                            memberIcon1:setStyleClassList({"asrIndustryKind"})
                        end
                        if memberDetails[asrEnum.cargoGroupMember.CARGO_ID] then
                            memberIcon2 = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]) .. "@2x.tga")
                            memberIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
                        end
                    
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
                        if asrState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])] then 
                            memberNameString = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME]
                            memberNameWrapper = api.gui.comp.TextView.new(memberNameString)
                            memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/configure_line@2x.tga")
                            memberIcon1:setMaximumSize(api.gui.util.Size.new(18, 18))
                            memberIcon1:setStyleClassList({"asrIndustryOther"})
                            if memberDetails[asrEnum.cargoGroupMember.CARGO_ID] then
                                memberIcon2 = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]) .. "@2x.tga")
                                memberIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
                            end
                        end
                    elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                        if asrState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])] then
                            memberNameString = asrState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME]
                            memberNameWrapper = api.gui.comp.TextView.new(memberNameString)
                            memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
                            memberIcon1:setMaximumSize(api.gui.util.Size.new(18, 18))
                            memberIcon1:setStyleClassList({"asrIndustryOther"})
                        end
                    end

                    local cargoGroupMemberDeleteIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/sell_thin.tga")
                    cargoGroupMemberDeleteIcon:setId("asr.cargoGroupMemberDeleteIcon-" .. tostring(selectedCargoGroupId) .. "-" .. tostring(memberId))
                    cargoGroupMemberDeleteIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                    local cargoGroupMemberDeleteButton = api.gui.comp.Button.new(cargoGroupMemberDeleteIcon, false)
                    cargoGroupMemberDeleteButton:setId("asr.cargoGroupMemberDeleteButton-" .. tostring(selectedCargoGroupId) .. "-" .. tostring(memberId))
                    cargoGroupMemberDeleteButton:setStyleClassList({"asrMiniListButton"})
                    cargoGroupMemberDeleteButton:setVisible(false, false)
                    cargoGroupMemberDeleteButton:setEnabled(true)
                    cargoGroupMemberDeleteButton:setTooltip(i18Strings.delete_cargo_group_member)
                    cargoGroupMemberDeleteButton:onClick(function () 
                        sendEngineCommand("asrDeleteCargoGroupMember", { cargoGroupId = selectedCargoGroupId, memberId = memberId })
                    end)
    
                    if memberIcon1 == nil then memberIcon1 = api.gui.comp.TextView.new("") end
                    if memberIcon2 == nil then memberIcon2 = api.gui.comp.TextView.new("") end
                    if memberNameWrapper == nil then memberNameWrapper = api.gui.comp.TextView.new("unkown") end

                    cargoGroupMembersTable:addRow({
                        memberIcon1, memberIcon2, memberNameWrapper, cargoGroupMemberDeleteButton })
                    
                    table.insert(asrGuiState.cargoGroupMembersRowMap, memberId)
                    table.insert(memberNamesMap, {name = memberNameString})
                end
                cargoGroupMembersTable:setOrder(asrHelper.getSortOrder(memberNamesMap, "name"))
            end

            cargoGroupMembersScrollArea:setContent(cargoGroupMembersTable)
            cargoGroupMembersScrollLayout:addItem(cargoGroupMembersScrollArea)

            -- local cargoGroupMembersLabel = api.gui.comp.TextView.new("Members")
            -- cargoGroupMembersLabel:setGravity(0,0)
            -- cargoGroupSelectionTable:addRow({cargoGroupMembersLabel, cargoGroupMembersScrollWrapper})

            -- -- current amount of cargo
            local currentAmountWrapper = api.gui.comp.Component.new("asr.amountWrapper")
            currentAmountWrapper:setId("asr.currentAmountWrapper-"  .. selectedCargoGroupId)
            local currentAmountLayout = api.gui.layout.BoxLayout.new("VERTICAL");
            currentAmountWrapper:setGravity(0,0)
            currentAmountWrapper:setLayout(currentAmountLayout)

            local currentTotalAmountLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
            local currentTotalAmountWrapper = api.gui.comp.Component.new("asr.totalAmountWrapper")
            currentTotalAmountWrapper:setLayout(currentTotalAmountLayout)

            local currentTotalAmountIcon = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
            currentTotalAmountIcon:setMaximumSize(api.gui.util.Size.new(18, 18))
            currentTotalAmountLayout:addItem(currentTotalAmountIcon)

            local currentValue = 0

            if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] and asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] then
                currentValue = asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT]
            end

            local currentTotalAmountText = api.gui.comp.TextView.new(tostring(currentValue))
            currentTotalAmountText:setId("asr.currentTotalAmountText-"  .. selectedCargoGroupId)
            currentTotalAmountLayout:addItem(currentTotalAmountText)

            currentAmountLayout:addItem(currentTotalAmountWrapper)

            cargoGroupSettingsTable:addRow({currentAmountWrapper, cargoGroupSelectionTable})
            cargoGroupSettingsTable:addRow({api.gui.comp.TextView.new(""), cargoGroupMembersScrollWrapper})

            asrGuiState.rebuildCargoGroupsSettingsTable = false
            log("gui: rebuildCargoGroupsLayout: done initial build of the settings table")
        else

            -- just a refresh
            if asrState[asrEnum.CARGO_GROUPS] then 
                -- log("gui: rebuildCargoGroupsLayout: running refresh of the cargo groups table")
                for cargoGroupId, cargoGroup in pairs(asrState[asrEnum.CARGO_GROUPS]) do    
                    local cargoGroupCargoIcon = api.gui.util.getById("asr.cargoGroupCargoIcon-" .. tostring(cargoGroupId))
                    local cargoGroupNameTextInput = api.gui.util.getById("asr.cargoGroupNameTextInput-" .. tostring(cargoGroupId))
                    local cargoGroupNameLabel = api.gui.util.getById("asr.cargoGroupNameLabel-" .. tostring(cargoGroupId))
                    local cargoGroupDeleteButton = api.gui.util.getById("asr.cargoGroupDeleteButton-" .. tostring(cargoGroupId))

                    if cargoGroupNameLabel then
                        cargoGroupNameLabel:setText(cargoGroup[asrEnum.cargoGroup.NAME], false)
                    else
                        log("gui: rebuildCargoGroupsLayout: can't find name label")
                    end
                    if cargoGroupNameTextInput then
                        if not cargoGroupNameTextInput:isVisible() then
                            cargoGroupNameTextInput:setText(cargoGroup[asrEnum.cargoGroup.NAME], false)
                        end
                    else
                        log("gui: rebuildCargoGroupsLayout: can't find name text input")
                    end                    
                    if cargoGroupDeleteButton then
                        if cargoGroup[asrEnum.cargoGroup.IN_USE] and cargoGroup[asrEnum.cargoGroup.IN_USE] ~= 0 then
                            cargoGroupDeleteButton:setEnabled(false)
                            cargoGroupDeleteButton:setTooltip(i18Strings.in_use_cant_delete)
                        else 
                            cargoGroupDeleteButton:setEnabled(true)
                            cargoGroupDeleteButton:setTooltip(i18Strings.delete_cargo_group)
                        end    
                    end
                end
                cargoGroupsTable:setOrder(asrHelper.getSortOrder(asrState[asrEnum.CARGO_GROUPS], asrEnum.cargoGroup.NAME))
            end
    
            local cargoGroupSettingsNameLabel = api.gui.util.getById("asr.cargoGroupSettingsNameLabel-" .. selectedCargoGroupId)
            if  cargoGroupSettingsNameLabel and asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] ~= nil then
                cargoGroupSettingsNameLabel:setText(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.NAME], false)
            end

            local cargoGroupMembersTable = api.gui.util.getById("asr.cargoGroupMembersTable-"  .. selectedCargoGroupId)
    
            if cargoGroupMembersTable then 
                if asrGuiState.rebuildCargoGroupsMembersTable == true then 
                    cargoGroupMembersTable:deleteAll()
                    asrGuiState.cargoGroupMembersRowMap= {}
                    local memberNamesMap = {}
                    if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS] then
                        for memberId, memberDetails in pairs(asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.MEMBERS]) do
                            local memberNameString, memberNameWrapper, memberIcon1, memberIcon2
                            if memberDetails[asrEnum.cargoGroupMember.TYPE] == "industry" then
                                memberNameString = asrState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.NAME]
                                local memberNameLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
                                memberNameWrapper = api.gui.comp.Component.new("asr.cargoGroupMemberNameWrapper")
                                memberNameWrapper:setLayout(memberNameLayout)
                                memberNameLayout:addItem(api.gui.comp.TextView.new(memberNameString))
                                if asrState[asrEnum.INDUSTRIES][tostring(memberDetails[asrEnum.cargoGroupMember.INDUSTRY_ID])][asrEnum.industry.TYPE] == "town" then
                                    local townIcon = api.gui.comp.ImageView.new("ui/ui/button/medium/towns@2x.tga")
                                    townIcon:setMaximumSize(api.gui.util.Size.new(15,15))
                                    memberNameLayout:addItem(townIcon)
                                end
                                if memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "supplier" then
                                    memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/load_game@2x.tga")
                                    memberIcon1:setMaximumSize(api.gui.util.Size.new(12, 12))
                                    memberIcon1:setStyleClassList({"asrIndustryKind"})
                                elseif memberDetails[asrEnum.cargoGroupMember.INDUSTRY_KIND] == "consumer" then
                                    memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/save_game@2x.tga")
                                    memberIcon1:setMaximumSize(api.gui.util.Size.new(12, 12))
                                    memberIcon1:setStyleClassList({"asrIndustryKind"})
                                end
                                if memberDetails[asrEnum.cargoGroupMember.CARGO_ID] then
                                    memberIcon2 = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]) .. "@2x.tga")
                                    memberIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
                                end
                            
                            elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "shippingContract" then
                                memberNameString = asrState[asrEnum.SHIPPING_CONTRACTS][tostring(memberDetails[asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID])][asrEnum.shippingContract.NAME]
                                memberNameWrapper = api.gui.comp.TextView.new(memberNameString)
                                memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/configure_line@2x.tga")
                                memberIcon1:setMaximumSize(api.gui.util.Size.new(18, 18))
                                memberIcon1:setStyleClassList({"asrIndustryOther"})
                                if memberDetails[asrEnum.cargoGroupMember.CARGO_ID] then
                                    memberIcon2 = api.gui.comp.ImageView.new("ui/hud/cargo_" .. string.lower(cargoTypes[tonumber(memberDetails[asrEnum.cargoGroupMember.CARGO_ID])]) .. "@2x.tga")
                                    memberIcon2:setMaximumSize(api.gui.util.Size.new(18, 18))
                                end
        
                            elseif memberDetails[asrEnum.cargoGroupMember.TYPE] == "cargoGroup" then
                                memberNameString = asrState[asrEnum.CARGO_GROUPS][tostring(memberDetails[asrEnum.cargoGroupMember.CARGO_GROUP_ID])][asrEnum.cargoGroup.NAME]
                                memberNameWrapper = api.gui.comp.TextView.new(memberNameString)
                                memberIcon1 = api.gui.comp.ImageView.new("ui/icons/game-menu/cargo@2x.tga")
                                memberIcon1:setMaximumSize(api.gui.util.Size.new(18, 18))
                                memberIcon1:setStyleClassList({"asrIndustryOther"})
                            end
        
                            local cargoGroupMemberDeleteIcon = api.gui.comp.ImageView.new("ui/button/xxsmall/sell_thin.tga")
                            cargoGroupMemberDeleteIcon:setId("asr.cargoGroupMemberDeleteIcon-" .. tostring(selectedCargoGroupId) .. "-" .. tostring(memberId))
                            cargoGroupMemberDeleteIcon:setMaximumSize(api.gui.util.Size.new(15, 15))
                            local cargoGroupMemberDeleteButton = api.gui.comp.Button.new(cargoGroupMemberDeleteIcon, false)
                            cargoGroupMemberDeleteButton:setId("asr.cargoGroupMemberDeleteButton-" .. tostring(selectedCargoGroupId) .. "-" .. tostring(memberId))
                            cargoGroupMemberDeleteButton:setStyleClassList({"asrMiniListButton"})
                            cargoGroupMemberDeleteButton:setVisible(false, false)
                            cargoGroupMemberDeleteButton:setEnabled(true)
                            cargoGroupMemberDeleteButton:setTooltip(i18Strings.delete_cargo_group_member)
                            cargoGroupMemberDeleteButton:onClick(function () 
                                sendEngineCommand("asrDeleteCargoGroupMember", { cargoGroupId = selectedCargoGroupId, memberId = memberId })
                            end)
            
                            if memberIcon1 == nil then memberIcon1 = api.gui.comp.TextView.new("") end
                            if memberIcon2 == nil then memberIcon2 = api.gui.comp.TextView.new("") end
                            if memberNameWrapper == nil then memberNameWrapper = api.gui.comp.TextView.new("unkown") end
        
                            cargoGroupMembersTable:addRow({
                                memberIcon1, memberIcon2, memberNameWrapper, cargoGroupMemberDeleteButton })
                        
                            table.insert(asrGuiState.cargoGroupMembersRowMap, memberId)
                            table.insert(memberNamesMap, {name = memberNameString})
                        end
                    end
                    cargoGroupMembersTable:setOrder(asrHelper.getSortOrder(memberNamesMap, "name"))
                end
                asrGuiState.rebuildCargoGroupsMembersTable = false
            end
            -- current cargo
            local currentValue = 0

            if asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] and asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT] then
                currentValue = asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)][asrEnum.cargoGroup.CARGO_AMOUNT]
            end

            local currentTotalAmountText = api.gui.util.getById("asr.currentTotalAmountText-"  .. selectedCargoGroupId)
            if currentTotalAmountText then
                currentTotalAmountText:setText(tostring(currentValue), false)
            end
            
        end
    else
        -- log("gui: rebuildCargoGroupsLayout: nothing in the table to display")
        -- if selectedCargoGroupId ~= nil then
        --     log("gui: rebuildCargoGroupsLayout: selcted contract id ok")
        -- end
        -- if asrState[asrEnum.CARGO_GROUPS] and asrState[asrEnum.CARGO_GROUPS][tostring(selectedCargoGroupId)] ~= nil then
        --     log("gui: rebuildCargoGroupsLayout: selcted contract details ok")
        -- end
        if cargoGroupSettingsTable ~= nil then
            -- log("gui: rebuildCargoGroupsLayout: contract settings table ok")
            cargoGroupSettingsTable:deleteAll()
        end        
    end
end


local function buildMainWindow()


    local tabs = api.gui.comp.TabWidget.new("NORTH")
    
    local linesTabLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
    linesTabLayout:setId("asr.linesTabLayout")

    local linesTabWrapper = api.gui.comp.Component.new("asr.linesTab")
    linesTabWrapper:setLayout(linesTabLayout)

    local linesScrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.TextView.new('linesScrollArea'), "asr.linesScrollArea")
    linesScrollArea:setId("asr.linesScrollArea")

    local linesScrollAreaLayout = api.gui.layout.BoxLayout.new("VERTICAL")
    local linesScrollAreaComponent = api.gui.comp.Component.new("asr.linesScrollAreaComponent")
    linesScrollAreaComponent:setLayout(linesScrollAreaLayout)

    local linesScrollFilterTextInput = api.gui.comp.TextInputField.new(i18Strings.search_for_line)
    linesScrollFilterTextInput:setGravity(1,1)
    linesScrollFilterTextInput:setMaxLength(22)
    linesScrollFilterTextInput:setMinimumSize(api.gui.util.Size.new(180, 18))
    linesScrollFilterTextInput:setMaximumSize(api.gui.util.Size.new(180, 18))
    linesScrollFilterTextInput:onChange(function (string)
        asrGuiState.linesFilterString = string
        rebuildLinesTable()
    end)

    local linesTable = api.gui.comp.Table.new(4, 'SINGLE')
    linesTable:setColWidth(0,25)
    linesTable:setColWidth(1,25)
    linesTable:setColWidth(2,25)
    linesTable:setId("asr.linesTable")
    -- linesTable:onHover(function (id) 
    --     if id < 0 then 
    --         linesTable:select(id, false)    
    --     end
    -- end)
    linesTable:onSelect(function (id) 
    
        log("gui: line table id selected: " .. id)
        if id >= 0 then
            log("gui: line id selected: " .. asrGuiState.linesRowMap[id + 1])
            asrGuiState.selectedLine = asrGuiState.linesRowMap[id + 1]
            asrGuiState.lineSettingsTableBuilt = false
            asrGuiState.settingsTableInitalising = true
            if asrGuiObjects.lineSettingsDropDownList ~= nil then
                asrGuiObjects.lineSettingsDropDownList:setVisible(false, false)
            end
            rebuildLineSettingsLayout()

            sendEngineCommand("asrInitLine", { lineId = asrGuiState.linesRowMap[id + 1] })
        end
    end)
    linesScrollArea:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.linesScrollArea.width, asrGuiDimensions.linesScrollArea.height))
    linesScrollArea:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.linesScrollArea.width, asrGuiDimensions.linesScrollArea.height))
    linesScrollAreaLayout:addItem(linesScrollFilterTextInput)
    linesScrollAreaLayout:addItem(linesTable)
    linesScrollArea:setContent(linesScrollAreaComponent)

    linesTabLayout:addItem(linesScrollArea)

    local lineSettingsScrollArea = api.gui.comp.ScrollArea.new(api.gui.comp.TextView.new('lineSettingsScrollArea'), "asr.lineSettingsScrollArea")
    lineSettingsScrollArea:setId("asr.lineSettingsScrollArea")
    lineSettingsScrollArea:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsScrollArea.width, asrGuiDimensions.lineSettingsScrollArea.height))
    lineSettingsScrollArea:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.lineSettingsScrollArea.width, asrGuiDimensions.lineSettingsScrollArea.height))
    
    local lineSettingsScrollAreaLayout = api.gui.layout.AbsoluteLayout.new()
    lineSettingsScrollAreaLayout:setId("asr.settingsScrollAreaLayout")
    asrGuiObjects.lineSettingsScrollAreaLayout = lineSettingsScrollAreaLayout

    local lineSettingsScrollAreaWrapper = api.gui.comp.Component.new("asr.lineSettingsScrollArea")
    lineSettingsScrollAreaWrapper:setLayout(lineSettingsScrollAreaLayout)

    -- build line settings area
    rebuildLineSettingsLayout()

    lineSettingsScrollArea:setContent(lineSettingsScrollAreaWrapper)
    linesTabLayout:addItem(lineSettingsScrollArea)

    -- linesWindowLayout:addItem(linesTabWrapper,0,0)

    tabs:addTab(api.gui.comp.TextView.new(i18Strings.lines), linesTabWrapper)

    -- cargo tracking setting - shippment contracts and cargo groups tab

    local cargoTrackingTabLayout = api.gui.layout.BoxLayout.new("VERTICAL");
    cargoTrackingTabLayout:setId("asr.cargoTrackingTabLayout")
    asrGuiObjects.cargoTrackingTabLayout = cargoTrackingTabLayout
    local cargoTrackingTabWrapper = api.gui.comp.Component.new("asr.cargoTrackingTab")
    cargoTrackingTabWrapper:setLayout(cargoTrackingTabLayout)

    -- shipping contracts    
    log("gui: main rebuildShippingContractsLayout")
    rebuildShippingContractsLayout()

    -- cargo groups
    log("gui: main rebuildCargoGroupsLayout")
    rebuildCargoGroupsLayout()

    tabs:addTab(api.gui.comp.TextView.new(i18Strings.cargo_tracking), cargoTrackingTabWrapper)

    -- mod settings and debug tab

    local globalSettingsTable = api.gui.comp.Table.new(2, 'NONE')
    globalSettingsTable:setColWidth(0, asrGuiDimensions.globalSettingsTable.columns[1])
    globalSettingsTable:setColWidth(1, asrGuiDimensions.globalSettingsTable.columns[2])

    local settingsTable = api.gui.comp.Table.new(3, 'NONE')

    -- if no settings are present to start with - use the defaults

    if asrState[asrEnum.SETTINGS] == nil then 

        asrState[asrEnum.SETTINGS] = {}
        asrState[asrEnum.SETTINGS][asrEnum.settings.EXTRA_CAPACITY] = 0
        asrState[asrEnum.SETTINGS][asrEnum.settings.ENABLE_TRAIN_PURCHASE] = false
        asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] = 160
        asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] = 1
    end

    local gloalMinimalTrainSizeLabel = api.gui.comp.TextView.new(i18Strings.minimal_train_wagon_count)
    gloalMinimalTrainSizeLabel:setTooltip(i18Strings.minimal_train_wagon_count_tip)
    local MinimalTrainSizeValue = api.gui.comp.TextView.new("")
    MinimalTrainSizeValue:setMinimumSize(api.gui.util.Size.new(30, 20))
    local MinimalTrainSizeSlider = api.gui.comp.Slider.new(true)
    if asrState[asrEnum.SETTINGS] ~= nil then
        if not asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] then 
            asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT] = 1
        end
        MinimalTrainSizeSlider:setDefaultValue(asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT])
        MinimalTrainSizeSlider:setValue(asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT], false)
        MinimalTrainSizeValue:setText(tostring(asrState[asrEnum.SETTINGS][asrEnum.settings.MINIMAL_WAGON_COUNT]))
    end
    MinimalTrainSizeSlider:setMaximum(6)
    MinimalTrainSizeSlider:setMinimum(0)
    MinimalTrainSizeSlider:setMinimumSize(api.gui.util.Size.new(150, 20))
    MinimalTrainSizeSlider:onValueChanged(function (value) 
        sendEngineCommand("asrSettings", {property = asrEnum.settings.MINIMAL_WAGON_COUNT, value = value})
        MinimalTrainSizeValue:setText(tostring(value))
    end)
    
    settingsTable:addRow({gloalMinimalTrainSizeLabel,  MinimalTrainSizeValue, MinimalTrainSizeSlider})

    local trainLengthLayout = api.gui.layout.BoxLayout.new("HORIZONTAL");
    local trainLengthWrapper = api.gui.comp.Component.new("asr.trainLength")
    trainLengthWrapper:setLayout(trainLengthLayout)
    local trainLengthLabel = api.gui.comp.TextView.new(i18Strings.default_maximal_train_length)
    trainLengthLabel:setTooltip(i18Strings.default_maximal_train_length_tip)
    local MinimalTrainSizeFiller = api.gui.comp.TextView.new("")

    local trainLengthTextInput = api.gui.comp.TextInputField.new("000")
    if asrState[asrEnum.SETTINGS] and asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] then
        trainLengthTextInput:setText(tostring(asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]), false)
    end
    trainLengthTextInput:setMaxLength(3)
    trainLengthTextInput:setMinimumSize(api.gui.util.Size.new(28, 18))
    trainLengthTextInput:setMaximumSize(api.gui.util.Size.new(28, 18))
    trainLengthTextInput:onFocusChange(function (hasFocus) 
        if not hasFocus then
            local amountValue = trainLengthTextInput:getText()
            local amountValueNum = tonumber(amountValue)
            if amountValueNum == nil then
                trainLengthTextInput:setText("", false)
                return
            end
            if amountValueNum ~= math.floor(amountValueNum) then
                trainLengthTextInput:setText("", false)
                return
            end
            -- send the value to the engine
            sendEngineCommand("asrSettings", { property = asrEnum.settings.TRAIN_LENGTH, value = amountValueNum })
        end
    end)
    trainLengthTextInput:onEnter(function () 
        local amountValue = trainLengthTextInput:getText()
        local amountValueNum = tonumber(amountValue)
        if amountValueNum == nil then
            trainLengthTextInput:setText("", false)
            return
        end
        if amountValueNum ~= math.floor(amountValueNum) then
            trainLengthTextInput:setText("", false)
            return
        end
        sendEngineCommand("asrSettings", { property = asrEnum.settings.TRAIN_LENGTH, value = amountValueNum })
    end)
    trainLengthTextInput:onCancel(function ()
        if asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH] then
            trainLengthTextInput:setText(tostring(asrState[asrEnum.SETTINGS][asrEnum.settings.TRAIN_LENGTH]), false)
        end    
    end)

    trainLengthLayout:addItem(trainLengthTextInput)
    trainLengthLayout:addItem(api.gui.comp.TextView.new("m"))
    settingsTable:addRow({trainLengthLabel, trainLengthWrapper, MinimalTrainSizeFiller})

    local enableTimingsLabel = api.gui.comp.TextView.new(i18Strings.enable_timings)
    local enableTimingsCheckBox = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
    enableTimingsCheckBox:setId("asr.timingsEnabled")
    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then
        enableTimingsCheckBox:setSelected(true, false)
    else
        enableTimingsCheckBox:setSelected(false, false)
    end
    enableTimingsCheckBox:setStyleClassList({"asrCheckbox"})
    enableTimingsCheckBox:onToggle(function (checked)
        local timingsTable = api.gui.util.getById("asr.timingsTable")
        if checked then
            sendEngineCommand("asrEnableTimings", {})
            timingsTable:setVisible(true, false)
        else
            sendEngineCommand("asrDisableTimings", {})
            timingsTable:setVisible(false, false)
        end
    end)    
    settingsTable:addRow({enableTimingsLabel, enableTimingsCheckBox,api.gui.comp.TextView.new("")})

    local enableDebugLabel = api.gui.comp.TextView.new(i18Strings.enable_debug)
    local enableDebugCheckBox = api.gui.comp.CheckBox.new("", "ui/checkbox0.tga", "ui/checkbox1.tga" )
    enableDebugCheckBox:setId("asr.debugEnabled")
    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] then
        enableDebugCheckBox:setSelected(true, false)
    else
        enableDebugCheckBox:setSelected(false, false)
    end
    enableDebugCheckBox:setStyleClassList({"asrCheckbox"})
    enableDebugCheckBox:onToggle(function (checked)
        local debugTable = api.gui.util.getById("asr.debugTable")
        if checked then
            sendEngineCommand("asrEnableDebug", {})
            debugTable:setVisible(true, false)
        else
            sendEngineCommand("asrDisableDebug", {})
            debugTable:setVisible(false, false)
        end
    end)
    settingsTable:addRow({enableDebugLabel, enableDebugCheckBox,api.gui.comp.TextView.new("")})


    local timingsTable = api.gui.comp.Table.new(3, 'NONE')
    timingsTable:setId("asr.timingsTable")

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.TIMINGS_ENABLED] then
        timingsTable:setVisible(true, false)
    else
        timingsTable:setVisible(false, false)
    end

    globalSettingsTable:addRow({settingsTable, timingsTable})

    local debugTable = api.gui.comp.Table.new(1, 'NONE')
    debugTable:setId("asr.debugTable")
    local dumpLinesStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump lines state"), false)
    dumpLinesStateButton:onClick(function () 
        sendEngineCommand("asrDumpLinesState")
    end)

    local dumpIndustriesStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump industries state"), false)
    dumpIndustriesStateButton:onClick(function () 
        sendEngineCommand("asrDumpIndustriesState")
    end)

    local dumpTrackedTainsButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump tracked trains"), false)
    dumpTrackedTainsButton:onClick(function () 
        sendEngineCommand("asrDumpTrackedTrains")
    end)

    local dumpModelCacheButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump model cache"), false)
    dumpModelCacheButton:onClick(function () 
        sendEngineCommand("asrDumpModelCache")
    end)

    local dumpShippingContractsButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump shipping contracts"), false)
    dumpShippingContractsButton:onClick(function () 
        sendEngineCommand("asrDumpShippingContracts")
    end)

    local dumpCargoGroupsButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump cargo groups"), false)
    dumpCargoGroupsButton:onClick(function () 
        sendEngineCommand("asrDumpCargoGroups")
    end)

    local unpauseButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Unpause"), false)
    unpauseButton:onClick(function () 
        sendEngineCommand("asrUnpause")
    end)

    local eraseStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("!!! Erase state !!!"), false)
    eraseStateButton:onClick(function () 
        sendEngineCommand("asrEraseState")
    end)

    local dumpStateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Dump complete state"), false)
    dumpStateButton:onClick(function () 
        sendEngineCommand("asrDumpState")
    end)

    local forceLineCheckButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Force line rescan"), false)
    forceLineCheckButton:onClick(function () 
        sendEngineCommand("asrForceLineCheck")
    end)

    local deleteIndustriesButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Delete industries"), false)
    deleteIndustriesButton:onClick(function () 
        sendEngineCommand("asrDeleteIndustriesState")
    end)

    local checkTrainConfigsButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Chceck train configs"), false)
    checkTrainConfigsButton:onClick(function () 
        sendEngineCommand("asrCheckTrainConfigs")
    end)

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.DEBUG_ENABLED] then
        debugTable:setVisible(true, false)
    else
        debugTable:setVisible(false, false)
    end

    debugTable:addRow({dumpLinesStateButton})
    debugTable:addRow({dumpIndustriesStateButton})
    debugTable:addRow({dumpShippingContractsButton})
    debugTable:addRow({dumpCargoGroupsButton})
    debugTable:addRow({dumpModelCacheButton})
    debugTable:addRow({dumpStateButton})
    -- debugTable:addRow({checkTrainConfigsButton})
    debugTable:addRow({dumpTrackedTainsButton})
    debugTable:addRow({forceLineCheckButton})
    debugTable:addRow({deleteIndustriesButton})
    -- debugTable:addRow({unpauseButton})
    debugTable:addRow({eraseStateButton})

    globalSettingsTable:addRow({debugTable, api.gui.comp.Component.new("Filler")})
    tabs:addTab(api.gui.comp.TextView.new(i18Strings.settings), globalSettingsTable)


    local window = api.gui.comp.Window.new("Autosizer", tabs)
    if tabs:getCurrentTabIndex() == -1 then
        tabs:setCurrentTab(0, false)
    end

    window:setMinimumSize(api.gui.util.Size.new(asrGuiDimensions.mainWindow.width, asrGuiDimensions.mainWindow.height))
    window:setMaximumSize(api.gui.util.Size.new(asrGuiDimensions.mainWindow.width, asrGuiDimensions.mainWindow.height))


	window:addHideOnCloseHandler()

    -- tabs:onCurrentChanged(function (tab) 
    --     if tab == 0 then
    --         sendEngineCommand("asrStartRefresh", {})
    --     else
    --         sendEngineCommand("asrStopRefresh", {})
    --     end
    -- end)

	window:onClose(function()
			asrGuiState.isVisible = false
            sendEngineCommand("asrStopRefresh", {})
	 	end)
    window:onVisibilityChange(function (visible)
        if visible == true then
            sendEngineCommand("asrRefreshLinesNames", {})
            sendEngineCommand("asrStartRefresh", {})
            sendEngineCommand("asrCheckCargoTrackingReferences", {})
            asrGuiState.refreshLinesTable = true
        end
    end)
	window:setResizable(true)

    log("gui: lines window created")
	return window

end

local function guiInit()

    log("gui: in init")

    cargoTypes =  game.interface.getCargoTypes()

    local asrIcon = api.gui.comp.ImageView.new("ui/Autosizer_icon.tga")
    asrIcon:setMaximumSize(api.gui.util.Size.new(60,60))
    asrIcon:setMinimumSize(api.gui.util.Size.new(60,60))
    local mainButtonsLayout = api.gui.util.getById("mainButtonsLayout"):getItem(2)
    local asrButton = api.gui.comp.ToggleButton.new(asrIcon)
	asrButton:setTooltip("Autosizer")
    asrButton:setName("ConstructionMenuIndicator")
    mainButtonsLayout:addItem(asrButton)

    -- local buttonLabel = api.gui.comp.TextView.new("Autosizer")

    -- local button = api.gui.comp.Button.new(buttonLabel, false)
    
    -- local gameInfoLayout = api.gui.util.getById("gameInfo"):getLayout()
    -- gameInfoLayout:addItem(button)

    local linesWindow = buildMainWindow()

    linesWindow:setVisible(false,false)
    linesWindow:onClose(function ()
        asrButton:setSelected(false, false)
    end)
    asrButton:onToggle(function ()

        if asrGuiState.isVisible then
            asrGuiState.isVisible = false
            linesWindow:setVisible(false,true)
            
        else
            sendEngineCommand("asrForceLineCheck")
            asrGuiState.isVisible = true
            linesWindow:setVisible(true,true)
        end
    end)

    log("gui: done in init")
    asrGuiState.initDone = true
end

function asrGui.forceLineCheck()

    sendEngineCommand("asrForceLineCheck")

end

function asrGui.guiUpdate()
    

    if #asrEngineMessageQueue then
        local queueCopy = asrEngineMessageQueue
        asrEngineMessageQueue = {}
        for _, message in ipairs(queueCopy) do
            game.interface.sendScriptEvent(message.id, "", message.params)    
        end
    end

    if asrState[asrEnum.UPDATE_TIMESTAMP] ~= asrLastEngineTimestamp then
        asrLastEngineTimestamp = asrState[asrEnum.UPDATE_TIMESTAMP]
        asrGuiState.refreshLinesTable = true
        asrGuiState.refreshShippingContractsLayout = true
        asrGuiState.refreshCargoGroupsLayout = true
    end

    
    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.LINES_VERSION] ~= asrLastLinesVersion then
        asrLastLinesVersion = asrState[asrEnum.STATUS][asrEnum.status.LINES_VERSION]
        log("gui: lines version change")
        asrGuiState.rebuildLinesTable = true 
    end

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.SHIPPING_CONTRACTS_VERSION] ~= asrLastShippingContractsVersion then
        asrLastShippingContractsVersion = asrState[asrEnum.STATUS][asrEnum.status.SHIPPING_CONTRACTS_VERSION]
        log("gui: shipping contracts version change")
        asrGuiState.rebuildShippingContractsTable = true
    end

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_VERSION] ~= asrLastCargoGroupsVersion then
        asrLastCargoGroupsVersion = asrState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_VERSION]
        log("gui: cargo group version change")
        asrGuiState.rebuildCargoGroupsTable = true
    end

    if asrState[asrEnum.STATUS] and asrState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION] ~= asrLastCargoGroupsMembersVersion then
        asrLastCargoGroupsMembersVersion = asrState[asrEnum.STATUS][asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION]
        log("gui: cargo group members version change")
        asrGuiState.rebuildCargoGroupsMembersTable = true
    end

    if not asrGuiState.initDone then
        guiInit()
        rebuildLinesTable()
        rebuildLineSettingsLayout()
    end

    if asrGuiState.isVisible then
        if asrGuiState.initDone then 
            getTimings()
        end
        
        if asrGuiState.initDone and asrGuiState.refreshLinesTable then
            refreshLinesTable()
            rebuildLineSettingsLayout()
            asrGuiState.refreshLinesTable = false
        end

        if asrGuiState.initDone and (asrGuiState.refreshShippingContractsLayout or asrGuiState.rebuildShippingContractsTable) then
            -- log("gui: got signal to refresh shipping contracts")
            rebuildShippingContractsLayout()
            asrGuiState.refreshShippingContractsLayout = false
        end

        if asrGuiState.initDone and (asrGuiState.refreshCargoGroupsLayout or asrGuiState.rebuildCargoGroupsTable) then
            -- log("gui: got signal to refresh cargoGroups")
            rebuildCargoGroupsLayout()
            asrGuiState.refreshCargoGroupsLayout = false
        end

        if asrGuiState.initDone and asrGuiState.rebuildLinesTable then
            rebuildLinesTable()
            rebuildLineSettingsLayout()
            asrGuiState.rebuildLinesTable = false
        end    
    end
end



return asrGui