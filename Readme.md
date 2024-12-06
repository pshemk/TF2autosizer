# The train autosizer mod for Transport Fever 2

## TL; DR

This mod automatically adjusts the number of train wagons at each station, according to dynamically tracked cargo data. Each station can track the following amounts:

- nearby industry production
- nearby industry consumption
- nearby town consumption
- amount of cargo shipped between a given supplier and a given consumer (aka a "shipping contract")
- an abstract number which is a sum derived from any combination of the above numers (aka a "cargo group")
- a manually entered fixed amount
- train can be also configured to pick up an amount of waiting cargo

This means, that when the demand changes (for example when the industry moves to the next production level) the capacity of the trains gets automatically adjusted. That removes the need to micromange the lines and also improves profability by removing the maintance cost of running empty wagons.

This mod can be safely added to and removed from any savegame.

## Architecture

This mod is split into two parts:

- the UI 
- the backend 

The "UI" part (in `autosizer_gui.lua`) is responsible for all the user interactions, whilst the backend "engine" part (in `autosizer_engine.lua`) is the one carrying out the work: tracking trains, replacing them, tracking cargo amounts and updating the configuration. Both parts frequently communicate with each other. The UI sends messages to the backend and the backend saves the "state" and updates the timestamps to notfiy the UI about changes. All "state" changes are only ever written by the backend. 