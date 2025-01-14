-- local autosizerModelLoader = require "autosizer_pk/autosizer_model_loader"

--[[
	Automatic train resizer, changes the number of wagons to maintain a constant line throughput
--]]

 function data()
    return {
       info = {
      name = _("name_desc"),
      description = _("mod_desc"),
      authors = {
         {
            name = "PeterAklNZ",
            role = 'CREATOR',
         },
      },
      minorVersion = 20,   -- memory optmisation
      majorVersion = 0, 
      severityAdd = "NONE",
      severityRemove = "NONE",
      url = "https://github.com/pshemk/TF2autosizer",
      tags = { "Script Mod",  "Wagon", "Train Station", "Locomotive", "Industry" },
       },
       runFn = function (settings, modParams) 
        -- addModifier("loadModel", autosizerModelLoader.createModelCallback(params))
       end,
    }
 end
