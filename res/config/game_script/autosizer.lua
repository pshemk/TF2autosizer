

-- GUI related functions
local autosizerGui = require "autosizer_pk/autosizer_gui"

-- Engine related functions
local autosizerEngine = require "autosizer_pk/autosizer_engine"

function data()
    return {

        -- guiInit = autosizerGui.guiInit;
        guiUpdate = autosizerGui.guiUpdate;

        guiHandleEvent = function(id, name, param)
            if id == "vehicleManager" and name == "accept" then
                -- new vehicle purchased or cloned or deleted
                autosizerGui.forceLineCheck()
            elseif id == "lineChooseButton" and name == "button.click" then
                -- vehicle assigned to line
                autosizerGui.forceLineCheck()
            end
        end,
            
        handleEvent = function (src, id, name, param)
            if src == "autosizer.lua" then
                autosizerEngine.handleEvent(id, param)
            end
        end,

        update = function() 
            autosizerEngine.update()
        end,

        save = function()
            return autosizerEngine.getState()
        end,

        load = function(loadedState)
            if loadedState == nil then return end
            autosizerEngine.setState(loadedState)
            autosizerGui.setState(loadedState)
        end,

    }
end
