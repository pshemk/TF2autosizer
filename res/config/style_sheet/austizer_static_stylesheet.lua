-- require "tableutil"
local ssu = require "stylesheetutil"

function data()
  local result = { }

  local a = ssu.makeAdder(result)          -- helper function

  a("!asrCheckbox", {
    padding = {7,6,3,3},
    fontSize = 15,
  })

  a("!asrStationCheckbox", {
    padding = {0,0,0,60},
    fontSize = 15,
  })

  a("!asrGenericCheckbox", {
    padding = {0,3,0,7},
    fontSize = 15,
  })

  a("!asrLineStatusDefault", {
    color = {0, 0, 0, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineStatusOK", {
    color = {0.45098039, 0.84313725, 0.29411765, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineFilterOK", {
    color = {0.45098039, 0.84313725, 0.29411765, 1},
    fontSize = 27,
    padding = {-5, 0, 0 , 0},
    margin = {0, 0, 0, 0},
  })

  a("!asrLineStatusError", {
    color = {0.89411765, 0.03137255, 0.03921569, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineStatusWarning", {
    color = {1, 0.5, 0, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineFilterWarning", {
    color = {1, 0.5, 0, 1},
    fontSize = 27,
    padding = {-5, 0, 0 , 0},
    margin = {0, 0, 0, 0},
  })

  a("!asrLineStatusOverCapacity", {
    color = {1, 1, 0, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineFilterOverCapacity", {
    color = {1, 1, 0, 1},
    fontSize = 27,
    padding = {-5, 0, 0, 0},
    margin = {0, 0, 0, 0},
  })


  a("!asrLineStatusIncompatible", {
    color = {0, 0 , 0, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineStatusMisconfigured", {
    color = {1, 1, 1, 1},
    
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineFilterMisconfigured", {
    color = {1, 1, 1, 1},
    fontSize = 27,
    padding = {-5, 0, 0, 0},
    margin = {0, 0, 0, 0},
  })


  a("!asrLineStatusConfigured", {
    color = {0.14117647, 0.40784314, 0.82352941, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })

  a("!asrLineStatusUpdating", {
    color = {0.99607843, 0.6, 0, 1},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })
  
  a("!asrLineStatusDisabled", {
    color = {1, 1, 1, 0},
    fontSize = 27,
    padding = {0, 3, 0 ,3},
  })
  a("!asrLineName", {
    padding = {3, 0, 0 ,3},
  })

  a("!asrLineEditButton", {
    padding = {3, 3, 0 ,0},
  })
  
  a("!asrShippingContractIcon", {
    padding = {3, 3, 0 , 5},
  })

  a("!asrMiniListButton", {
    padding = {5, 10, 5 , 10},
  })

  a("!asrNewButton", {
    backgroundColor = { 0.32156863, 0.54117647, 0.69019608, 1},
  })

  a("!asrCargoButton", {
    margin = {3, 0, 3 , 20}
  })

  a("!asrLinesStatusFilter", {
    margin = {3, 3, 3 , 20}
  })

  a("!asrScrollFilterTextInput", {
    margin = {0, 0 ,0 , 155}
  })

  a("!asrDropList", {
    backgroundColor = {0.17647059, 0.25098039, 0.24313725, 1},
    -- backgroundColor = {0, 0, 0, 1},
    padding = {0, 3, 0 ,3},
  })

  a("!asrIndustryKind", {
    padding = {0, 0, 0 ,7},
  })

  a("!asrIndustryOther", {
    padding = {0, 0, 0 ,3},
  })
  return result
end