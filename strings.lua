function data()
    return {
       en = {
            add = "Add",
            adjust_capacity = "Adjust capacity",
            adjust_capacity_tip = "Adjustment of the calculated capacity.",
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
            fixed_amount = "Fixed amount",
            in_use_cant_delete = "In use, can't delete",
            industry = "Industry",
            line_name = "Line name",
            lines = "Lines",
            manual = "Manual",
            minimal_train_wagon_count = "Minimal train wagon count",
            minimal_train_wagon_count_tip = "Minimal number of wagons each train should always have",
            mod_desc = [[
[h1]Train Autosizer[/h1]

This mod allows you to change train length automatically at a station, according to set rules. It aims to simplify line management and maintain sufficient capacity when requirements change. 
It can track the production or consumption of an industry (or a town) and calculate the required amount of wagons neccessary to carry all the cargo. If the production changes - the train length gets adjusted automatically. 
In additon to simply tracking industries it can also use groupings, such as "shipping contracts" or "cargo groups" to enable more complex scenarios, such as cargo hubs. The trains can also be configured to pick up cargo currently waiting at the station.

The manual is available on [url=https://github.com/pshemk/TF2autosizer/blob/main/docs/manual.md]GitHub[/url]

If you find a bug or would like to see some other changes - please raise an issue on GitHub.

If you like my mod [url=https://buymeacoffee.com/peteraklnz]buy me a coffee :-) [/url]
            
            ]],
            name = "Name",
            name_desc = "Train Autosizer",
            new_cargo_group = "New cargo group",
            new_shipping_contract = "New shipping contract",
            pickup_waiting = "Pick up waiting",
            pickup_wating_tip = "Additional amount of waiting cargo to pick up,\nover the calculated value.",
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
            stations = "Stations",
            status_configured = "Configured",
            status_miconfigured_stations = "No stations enabled or incomplete station config",
            status_miconfigured_wagons = "Wagons with different capacities",
            supplier = "Supplier",
            train_length = "Train length",
            wagons = "Wagons",
            wagons_refresh_tip = "Rebuild the list of available wagons",
    }
}
end
 