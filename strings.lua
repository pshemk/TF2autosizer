function data()
    return {
       en = {
            add = "Add",
            adjust_capacity = "Adjust capacity",
            adjust_capacity_tip = "Adjustment of the calculated capacity.",
            all_is_well = "All is well",
            capacity_warning = "More cargo than expected was waiting at:",
            cargo_group = "Cargo group",
            cargo_tracking = "Cargo Tracking",
            consumer = "Consumer",
            default = "Default",
            default_maximal_train_length = "Default maximal train length",
            default_maximal_train_length_tip = "The maximal train length.\nCan be overridden by line settings.",
            delete_cargo_group = "Delete cargo group",
            delete_cargo_group_member = "Delete cargo group member",
            delete_shipping_contract = "Delete shipping contract",
            disabled = "Disabled",
            disabled_for_line = "Autosizer disabled for this line",
            enable_debug = "Enable debug",
            enable_scheduler = "Enable scheduler",
            enable_timings = "Enable timings",
            enabled = "Enabled",
            expecting_cargo = "Expecting:",
            fixed_amount = "Fixed amount",
            in_use_cant_delete = "In use, can't delete",
            industry = "Industry",
            length_warning = "Required trains would have been longer than allowed at:",
            line_name = "Line name",
            lines = "Lines",
            loading = "Loading",
            manual = "Manual",
            minimal_train_wagon_count = "Minimal train wagon count",
            minimal_train_wagon_count_tip = "Minimal number of wagons each train should always have",
            mod_desc = [[
Train Autosizer

This mod allows you to change train length automatically at a station in order to accomodate for the cargos. It aims to simplify line management and maintain sufficient capacity when requirements change. 
It can track the production or consumption of an industry (or a town) and calculate the required amount of wagons neccessary to carry all the cargo. If the production changes - the train length gets adjusted automatically. I can track multiple types of cargo on a single line and select the correct wagons to carry it. 
In additon to simply tracking industries it can also use groupings, such as "shipping contracts" or "cargo groups" to enable more complex scenarios, such as cargo hubs. The trains can also be configured to pick up cargo currently waiting at the station.
It can also schedule the trains on the line to maintain even distribution, allowing completly turn off 'full load all/any' and still have fully loaded trains.

The manual is available on [url=https://github.com/pshemk/TF2autosizer/blob/main/res/documents/manual.md]GitHub[/url]

If you find a bug or would like to see some other changes - please raise an issue on GitHub.

If you like my mod [url=https://buymeacoffee.com/peteraklnz]buy me a coffee :-) [/url]
            
            ]],
            name = "Name",
            name_desc = "Train Autosizer",
            new_cargo_group = "New cargo group",
            new_shipping_contract = "New shipping contract",
            not_tracked = "Train not being currently tracked",
            pickup_waiting = "Pick up waiting",
            pickup_watitng_tip = "Additional amount of waiting cargo to pick up,\nover the calculated rate.",
            pickup_waiting_backlog_label = "Auto-clear",
            pickup_waiting_backlog_label_tip = "Disables the waiting cargo pick up option\nif there is no more extra cargo to pick up",
            rename_cargo_group = "Rename cargo group",
            rename_shipping_contract = "Rename shipping contract",
            schedule_departures = "Schedule departures",
            schedule_departures_tip_off = "Only one train on the line, can't enable",
            schedule_departures_tip_on = "Ensures that trains depart the station at regular intervals",
            search_for_line = "Search for line",
            search_for_shipping_contract = "Search for shipping contract",
            search_for_cargo_group = "Search for cargo group",
            settings = "Settings",
            shipping_contract = "Shipping contract",
            show_status_window = "Show status window",
            show_tracking_details = "Show tracking details",
            stations = "Stations",
            status_configured = "Configured",
            status_miconfigured_stations = "No stations enabled or incomplete station config",
            status_miconfigured_wagons = "Wagons with different capacities",
            supplier = "Supplier",
            train_length = "Train length",
            trains = "Trains",
            tracked = "Train is being tracked",
            tracking_delay = "Tracking delay",
            tracking_delayed = "Train will be tracked later in the trip",
            tracking_delay_tip = "Percentage of the trip after which train starts to be tracked.\nIf there's a lot of variation in duration of the same trip\nthis number should be lowered to 50%",
            unknown_cargo_warning = "Unexpected cargo found at:",
            unloading = "Unloading",
            wagons = "Wagons",
            wagons_refresh_tip = "Rebuild the list of available wagons",
            waiting = "Waiting",
            waiting_cargo = "Waiting:"
    }
}
end
 