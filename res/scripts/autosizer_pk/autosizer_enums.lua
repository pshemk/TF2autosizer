
local asrEnum = {}

-- KEYS
-- top level state
asrEnum.UPDATE_TIMESTAMP                        = 1
asrEnum.STATUS                                  = 2
asrEnum.LINES                                   = 3
asrEnum.INDUSTRIES                              = 4
asrEnum.SETTINGS                                = 5
asrEnum.TIMINGS                                 = 6
asrEnum.TRACKED_TRAINS                          = 7
asrEnum.CHECKED_TRAINS                          = 8
asrEnum.SHIPPING_CONTRACTS                      = 9
asrEnum.CARGO_GROUPS                            = 10
asrEnum.MODEL_CACHE                             = 11

-- STATUS
asrEnum.status                                  = {}
asrEnum.status.LINES_COUNTER                    = 1
asrEnum.status.STOCK_ITERATION                  = 2
asrEnum.status.LINES_VERSION                    = 3
asrEnum.status.DEBUG_ENABLED                    = 4
asrEnum.status.TIMINGS_ENABLED                  = 5
asrEnum.status.LAST_ID                          = 6
asrEnum.status.SHIPPING_CONTRACTS_VERSION       = 7
asrEnum.status.CARGO_GROUPS_VERSION             = 8
asrEnum.status.CARGO_GROUPS_MEMBERS_VERSION     = 9
asrEnum.status.GUI_DEBUG                        = 10

-- LINES
asrEnum.line                                    = {}
asrEnum.line.ENABLED                            = 1
asrEnum.line.NAME                               = 2
asrEnum.line.INDUSTRIES                         = 3
asrEnum.line.STATIONS                           = 4
-- asrEnum.line.TOWNS                           = 5
asrEnum.line.UPDATE_TIMESTAMP                   = 6
asrEnum.line.TRAVEL_TIME                        = 7
asrEnum.line.VEHICLES                           = 8
asrEnum.line.STATUS                             = 9
asrEnum.line.STATUS_MESSAGE                     = 10
asrEnum.line.SETTINGS                           = 11
asrEnum.line.LINE_ID                            = 12
asrEnum.line.ALWAYS_TRACK                       = 13

-- LINE STATION
asrEnum.station                                 = {}
asrEnum.station.ENABLED                         = 1
asrEnum.station.STATION_ID                      = 2
asrEnum.station.STATION_GROUP_ID                = 3
asrEnum.station.CARGO_AMOUNT                    = 4
asrEnum.station.SELECTOR                        = 5
asrEnum.station.INDUSTRY_ID                     = 6
asrEnum.station.INDUSTRY_KIND                   = 7
asrEnum.station.INDUSTRY_CARGO_ID               = 8
asrEnum.station.FIXED_AMOUNT_VALUE              = 9
asrEnum.station.LINE_ID                         = 10
asrEnum.station.WAITING_CARGO_ENABLED           = 11
asrEnum.station.WAITING_CARGO_VALUE             = 12
asrEnum.station.CAPACITY_ADJUSTMENT_ENABLED     = 13
asrEnum.station.CAPACITY_ADJUSTMENT_VALUE       = 14
asrEnum.station.SHIPPING_CONTRACT_ID            = 15
asrEnum.station.SHIPPING_CONTRACT_CARGO_ID      = 16
asrEnum.station.CARGO_GROUP_ID                  = 17
asrEnum.station.LENGTH_WARNING                  = 18
asrEnum.station.STOP_DURATION                   = 19

-- LINE VEHICLES
asrEnum.vehicle                                 = {}
asrEnum.vehicle.WAGONS                          = 1
asrEnum.vehicle.ENGINES                         = 2

-- LINE SETTINGS
asrEnum.lineSettngs                             = {}
asrEnum.lineSettngs.TRAIN_LENGTH_SELECTOR       = 1
asrEnum.lineSettngs.TRAIN_LENGTH                = 2

-- LINE INDUSTRY
asrEnum.lineIndustry                            = {}
asrEnum.lineIndustry.NAME                       = 1
asrEnum.lineIndustry.STATION_ID                 = 2
asrEnum.lineIndustry.TYPE                       = 3

-- MODEL CACHE
asrEnum.modelCache                              = {}
asrEnum.modelCache.CAPACITY                     = 1
asrEnum.modelCache.CAPACITIES                   = 2
asrEnum.modelCache.COMPARTMENTS                 = 3
asrEnum.modelCache.LENGTH                       = 4
asrEnum.modelCache.TYPE                         = 5

-- INDUSTRY
asrEnum.industry                                = {}
asrEnum.industry.SUPPLIER                       = 1
asrEnum.industry.CONSUMER                       = 2
asrEnum.industry.SUPPLIER_ITERATION             = 3
asrEnum.industry.CONSUMER_ITERATION             = 4
asrEnum.industry.NAME                           = 5
asrEnum.industry.TYPE                           = 6
asrEnum.industry.CONSUMERS                      = 7
asrEnum.industry.SUPPLIERS                      = 8

-- SHIPPING_CONTRACT
asrEnum.shippingContract                        = {}
asrEnum.shippingContract.ID                     = 1
asrEnum.shippingContract.NAME                   = 2
asrEnum.shippingContract.SUPPLIER_ID            = 3
asrEnum.shippingContract.CONSUMER_ID            = 4
asrEnum.shippingContract.CARGO_ID               = 5
asrEnum.shippingContract.IN_USE                 = 6
asrEnum.shippingContract.CARGO_AMOUNT           = 7
asrEnum.shippingContract.MANUAL_NAME            = 8

-- CARGO GROUP
asrEnum.cargoGroup                              = {}
asrEnum.cargoGroup.ID                           = 1
asrEnum.cargoGroup.NAME                         = 2
asrEnum.cargoGroup.MEMBERS                      = 3
asrEnum.cargoGroup.IN_USE                       = 4
asrEnum.cargoGroup.VALID                        = 5
asrEnum.cargoGroup.VALIDITY_CHECKED             = 6
asrEnum.cargoGroup.CARGO_AMOUNT                 = 7
asrEnum.cargoGroup.MANUAL_NAME                  = 8

-- CARGO GROUP MEMBER
asrEnum.cargoGroupMember                        = {}
asrEnum.cargoGroupMember.TYPE                   = 1
asrEnum.cargoGroupMember.INDUSTRY_ID            = 2
asrEnum.cargoGroupMember.INDUSTRY_KIND          = 3
asrEnum.cargoGroupMember.CARGO_ID               = 4
asrEnum.cargoGroupMember.SHIPPING_CONTRACT_ID   = 5
asrEnum.cargoGroupMember.CARGO_GROUP_ID         = 6


-- SETTINGS
asrEnum.settings                                = {}
asrEnum.settings.TRAIN_LENGTH                   = 1
asrEnum.settings.EXTRA_CAPACITY                 = 2
asrEnum.settings.ENABLE_TRAIN_PURCHASE          = 3
asrEnum.settings.MINIMAL_WAGON_COUNT            = 4

-- TRACKED TRAINS
asrEnum.trackedTrain                            = {}
asrEnum.trackedTrain.IN_STATION                 = 1
asrEnum.trackedTrain.ARRIVAL_TIMESTAMP          = 2
asrEnum.trackedTrain.TIME_UNTIL_LOAD            = 3
asrEnum.trackedTrain.REPLACED                   = 4
asrEnum.trackedTrain.DELETE_ON_EXIT             = 5
asrEnum.trackedTrain.STATE                      = 6
asrEnum.trackedTrain.STOP_INDEX                 = 7
asrEnum.trackedTrain.DEPARTURE_TIMESTAMP        = 8
asrEnum.trackedTrain.GENERATED_CONFIG           = 9
asrEnum.trackedTrain.REPLACE_ON                 = 10
asrEnum.trackedTrain.SECTION_TIMES              = 11


-- CONSUMER TYPES
asrEnum.consumer                                = {}
asrEnum.consumer.TYPE                           = 1
asrEnum.consumer.TOWN                           = 2

-- VALUES
asrEnum.value                                   = {}
asrEnum.value.INDUSTRY_SHIPPING                 = 1
asrEnum.value.SUPPLY_CONTRACT                   = 2
asrEnum.value.CARGO_GROUP                       = 3
asrEnum.value.FIXED_AMOUNT                      = 4
asrEnum.value.DELETE                            = -1

return asrEnum