# The train autosizer mod

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

## Other mods compatibility

I have tested this mod with a number of other mods that provide different types of wagons and I haven't encountred any issues. Both single and multi-compartment wagons are supported. The economy mods that add more types of cargo are also supported. This mod also works with the Timetable mod.

## Peformance considerations

This mod contains three different types of functions:

- real-time, run at every tick of the game (i.e every 200ms)
- periodic, run every 2 seconds and spread over multiple ticks
- on-demand

The real-time functions are associated with tracking of the trains and carying out train replacements. If train's capacity needs to be adjusted at the next stop, from the moment that's identified the train status will be polled at every tick. Large number of tracked trains leads to the main function taking longer. The amount of time it takes can be seen in settings under 'Total' row (if performance tracking is enabled in the settings). If there are no other CPU intensive mods in the game generally times under 100ms should be fine.

All other functions (particularly those associated with updating of the production/consumption data) are set to only run for up 50ms per tick, which should leave enough headroom for the real-time functions.

The configuration of the lines does have an impact on the performance:

- Lines that have only one station enabled tend to have the most stable train length and only require the trains to be tracked occasionally
- Enabling pickup of waiting cargo at a station means that the trains always need to be tracked when heading to that station
- Lines that have more than one station enabled  need tracking of all trains heading to those enabled stations if the enabled stations require different capacities
- Enabling zero-length trains on the line (by setting the fixed amount of cargo to 0 at any of the stations or by using empty cargo group) forces all the trains on that line to be tracked permemently

The settings tab displays the number of tracked trains (if performance tracking is enabled).

One other consideration is the number of API calls made by the mod to the game. Each train check requires an API call, so if there are 200 tracked trains that means 1000 calls a second. That in itself shouldn't be a problem, but I've noticed (particularly on very large maps) that sometimes the API starts to return invalid information when queried very quickly. If that happens the mod stops quering the API in that tick. This shows up in the console log as messages similar to this one: `couldn't get info from the API`, if the following number is `0` that means that the API stopped responding correctly. If this starts to happen more frequently the game will most likely crash.
  
## Known issues aka features

1. Visual glitches when trains are being reconfigured casing the wagons overlap on departure
    Due to the way the game calculates the train stopping position (based on the lenght of the train when it enters the station) when new wagons are added they have to fit into roughly same space as the original train. That leads to an 'accordion' efect when the train departs.

2. Setting cargo amount to 0 at a station to get a train consiting of only the engine (using the 'Fixed amount' option or by using an empty cargo group) works, but there are the following things to consier:

- the game stops properly tracking round trip times (frequency), so the mod's own tracking steps in, but these calculations are not as exact as the ones done by the game. They rely on measuring the loading/unloading time at each station, and that information can only be captured when the train is actually at the station, so the accuracy gets better with time (average of last 5 load/unload times are used)
- if there's only one train on the line, the moment its wagons are gone the supply chains get broken, so the industries stop producing. The only way to prevent this is to make sure there's at least one train with wagons left on the line.

1. When trains get reconfigured at more than one station on a line the line "rate"  displayed in the game is not accurate any more.
  
2. At any given station all trains are configured to the same length by default (actual train might be longer if the station is configured for waiting cargo pickup), which can lead to overprovisioning of the line capacity. Lower numbers of longer trains on the line allows for better accuracy.

3. If wagons have different capacities for different types of cargos - the smallest value is used for all capacity calculations. This is not an issue with the in-game wagons, but some mods add such wagons. If this becomes a problem - use the manual capacity override in the configuration of the line.

4. Multiheaded trains are currently not supported. If they're used on the lines the mod will continiously underprovision the number of wagons by the number the of extra engines.

5. If a train picks up multiple types of cargo at the station some capacity might be lost due to wagons not loading fully. This generally shouldn't be an issue, as some overprovisioning happens naturally.

6. All wagons in a single train must be capable of carying the same set of cargos. Mixinging of different types (like a boxcar and a tanker) is not supported.

7. Using full load all/any leads to much longer round-trip times, but the mod correctly takes this into account and creates longer trains as necessary. The using the Timetable mod has the same effect.

8. It's always the last wagons that get removed from the train. The maintenance data of the original engine and wagons is copied to the new train. That might result in the game displaying the train as having multiple groups of the same wagons (instead of just one group).

9. Generation of the new train configuration happens as the train pulls into the station. If pickup of the waiting cargo is enabled - that's when the amount is calculcated. If the train takes a while to unload there might be more cargo than what the train can load.