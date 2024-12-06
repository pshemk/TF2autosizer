local asrHelper = require "autosizer_pk/autosizer_helper"

local asrGuiHelper = {}

local selectedRow

function asrGuiHelper.buildMultiOptionList(params) 


    -- local componentLayout = api.gui.layout.BoxLayout.new("VERTICAL");
    -- local component = api.gui.comp.Component.new("asr.dropDown")

    -- component:setLayout(componentLayout)

    local list = api.gui.comp.List.new(true, 1 ,false)
    list:setId("asr.List")

    -- if params.id ~= nil then
    --     list:setId(params.id)
    -- end
    if params.width ~= nil and params.height ~= nil then
        list:setMinimumSize(api.gui.util.Size.new(params.width, params.height))
    end

    if params.entries ~= nil then 
        for _, entry in pairs(params.entries) do 
            local label, icon
            if entry.text ~= nil then
                label = api.gui.comp.TextView.new(entry.text)
                if entry.textTip ~= nil then label:setTooltip(entry.textTip) end
            else
                label = api.gui.comp.TextView.new(" ??? ")
            end
            if entry.icon ~= nil then 
                icon = api.gui.comp.ImageView.new(entry.icon)
                if entry.iconTip ~= nil then icon:setTooltip(entry.iconTip) end
                icon:setMaximumSize(api.gui.util.Size.new(15, 15))
            else
                icon = api.gui.comp.TextView.new("")
            end
            -- local lineTable = api.gui.comp.Table.new(2, 'NONE')
            -- -- lineTable:setColWidth(1, 10)
            -- lineTable:addRow({icon, label})
            -- lineTable:setColWeight(0, 15)
            local lineLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
            lineLayout:addItem(icon)
            lineLayout:addItem(label)
            local lineWrapper =  api.gui.comp.Component.new("asr.tableLine")
            lineWrapper:setLayout(lineLayout)
            list:addItem(lineWrapper)
        end
        -- if selectedRow ~= nil then list:select(selectedRow, false) end
        list:onSelect(function (row)
            print("gui: list row: " .. row .. " selected")
            selectedRow = row
        end)
    end

    -- componentLayout:addItem(list)
    return list
end

function asrGuiHelper.refreshMultiOptionList(list, params) 

    list:clear(false)
    if params.entries ~= nil then 
        for _, entry in pairs(params.entries) do 
            local label, icon
            if entry.text ~= nil then
                label = api.gui.comp.TextView.new(entry.text)
                if entry.textTip ~= nil then label:setTooltip(entry.textTip) end
            else
                label = api.gui.comp.TextView.new(" ??? ")
            end
            if entry.icon ~= nil then 
                icon = api.gui.comp.ImageView.new(entry.icon)
                icon:setMaximumSize(api.gui.util.Size.new(15, 15))
                if entry.iconTip ~= nil then icon:setTooltip(entry.iconTip) end
            else
                icon = api.gui.comp.TextView.new("")
            end
            -- local lineTable = api.gui.comp.Table.new(2, 'NONE')
            -- -- lineTable:setColWidth(1, 10)
            -- lineTable:addRow({icon, label})

            -- -- lineTable:setColWeight(0, 15)
            -- list:addItem(lineTable)
            local lineLayout = api.gui.layout.BoxLayout.new("HORIZONTAL")
            lineLayout:addItem(icon)
            lineLayout:addItem(label)
            local lineWrapper =  api.gui.comp.Component.new("asr.tableLine")
            lineWrapper:setLayout(lineLayout)
            list:addItem(lineWrapper)

        end
    end
    -- if selectedRow ~= nil then list:select(selectedRow, false) end
    return list
end

local function getColourString(r, g, b)
    local x = string.format("%03.0f", (r * 100))
    local y = string.format("%03.0f", (g * 100))
    local z = string.format("%03.0f", (b * 100))
    return x .. y .. z
end

function asrGuiHelper.getLineColour(line)
    if type(line) == "string" then line = tonumber(line) end
    if not(type(line) == "number") then return "default" end
    local colour = api.engine.getComponent(line, api.type.ComponentType.COLOR)
    if (colour and  colour.color) then
        return getColourString(colour.color.x, colour.color.y, colour.color.z)
    else
        return "default"
    end
end

return asrGuiHelper