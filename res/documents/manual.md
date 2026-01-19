# Train Autosizer for Transport Fever 2

## What is it?

Autosizer is a mod that taps into the in-game cargo movement system in order to use trains more efficiently. It monitors the production and consumption of cargo and based on defined formulas - adjusts the number of wagons of cargo trains. For each line, behaviour at each stop (or station) can be customised. Once set - the mod takes care of making sure the trains run (almost) fully utilised and no cargo is lost.

## The math behind it

In TF2 each industry produces cargo. The given number of units (for example 400 iron ore units for an iron ore mine) is produced during a single in-game period (which is by default one year of in-game, or 12 minutes of real-world time). By knowing the time it takes for the train(s) on the line to travel from the supplier industry station to the consumer industry station and the capacity of the wagons it's possible to calculate the transport rate. In fact the game already does this, this rate is visible in the line overview window:

![Line overview](images/line_overview.png)

In this particular case the rate is 420, which means that this single train, using 11 wagons can carry the whole output of an ore mine. If the round-trip ("frequence" in TF2 parlance) was longer the train would have to be longer. Equally - if the round-trip was shorter (for example due to multiple trains on the same line) - the capacity required per train would need to be lower.

This mod uses the same math to calculate the optimal number of wagons per train to maintain the required rate. If the rate changes (for example due to the industry moving to the next level or due to congestion causing the train to take more time to reach the station) the number of wagons gets adjusted accordingly.

## Where do I find it?

After the mod has been activated it a new icon shows up next to the bulldozer icon:

![Autosizer Icon](images/menu.png)

pressing that icon brings up (and hides) the Autosizer configuration window.

## How do I use it?

### Basic usage

Let's now walk through a simple example that shows how to use the basic features of the mod. Let's start with a map:

![Sample map](images/map.png)

We have 2 coal mines (#1 at the top, #2 at the bottom), 1 iron ore mine and two steel mills (#1 at the top and #2 at the bottom). Note: the actual industry labels in the subsequent screenshots don't align perfectly with this numbering.

To start with, let's create lines that supply coal and iron ore to steel mill #1 and configure them to track the production levels of the coal and the iron ore mines.

First line carries the coal directly from coal mine #1 to steel mill #1 and the second one carries iron ore from iron ore mine #1 to steel mill #1. And when the lines are created - let's buy and assign them very simple trains - an engine with one gondola wagon:

![Sample map](images/train_assignment.png)

Once the trains leave the depot - the game builds supply chain relationships between the suppliers and the consumers:

![Supplier](images/coal_producer.png)

In this case - the rate is very small - only 2 units, but the coal mine is only starting. By now we have all the necessary things to actually configure Autosizer for this first line. After clicking the Autosizer button we're presented with a (rather empty looking) window:

![Autosizer Overview](images/autosizer1.png)

On the left, there's a list of lines. Only those lines that have trains with cargo wagons on them are displayed here.
Besides the name of the line there's the line's colour, state checkbox - enabled or disabled and line status indicated by the colour.
On the right hand side there's the Autosizer configuration for the line. In this case the line is not configured yet.

Lets now tick the "station state" checkbox, as shown below:

![Line configuration](images/autosizer2.jpg)

That makes a new panel appear, with a list of cargo information sources. In this case - we want to track the production of the coal mine, so let's select the "Industry" option, which makes a button with `--- Select ---` on it appear. Once we click that button we can see two options: a coal mine and a steel mill. The first icon on the line shows the kind of the industry (supplier, arrow pointing up or consumer, arrow pointing down) and the second - the type of cargo. In this case we want to track the supplier so let's click the mine.

The industry list contains the suppliers from the catchment area of the given station and consumers from the catchment areas of all the stations on the line.

![Line configuration](images/autosizer3.png)

Once the mine is selected two things happen:

- the target cargo amount gets populated to reflect the current value of production of the industry
- the line status turns blue, which means the line can now be enabled

If we tick the checkbox next to the line name - the status turns to green, indicating that now the train capacity at the station will be adjusted to match the production of the mine.

![Line configuration](images/autosizer4.png)

And when train pulls into the station we can see that it's already longer that what was initially purchased:

![Coal train](images/coal_train1.png)

### Shipping contracts

This concept already exists in the game - each supplier and producer connected by a line form a supply chain relationship. The shipping contract is simply the amount of cargo a supplier wants to ship to a consumer. This example shows how to use the shipping contracts.

On the map there's only one iron ore mine and two steel mills. If we create two lines joining the iron ore mine with both steel mills each of them will receive only a portion of the iron ore mine production. So let's build the lines and assign them a train each (again one engine, one wagon), like so:

![Iron ore assignments](images/assignments_ore1.png)

Once the trains are out of the depot the supply chains get  updated:

![Iron ore consumer](images/consumer_ore.png)

Now, we can configure Autosizer to track that information. Let's open the Autosizer window and open the second tab - "Cargo tracking":

![Shipping contract](images/shipping_contract1.png)

Once we click the "New shipping contract button" we can populate the supplier and consumer information from the drop down lists:

![Shipping contract](images/shipping_contract2.png)

Once both supplier and consumer are selected, the name gets automatically generated (changing the name manually turns off the auto-naming function) and the cargo amount gets updated as well:

![Shipping contract](images/shipping_contract3.png)

Once we have that - we can go back the the "lines" tab and select the first iron ore line. Enable the first station, select "Shipping contract" and select the right shipping contract from the list.

![Shipping contract](images/shipping_contract4.png)

Once both of the lines are set up the window looks like this and train lengths will be automatically updated:

![Shipping contract](images/shipping_contract5.png)

### Cargo groups

Cargo groups are a way of grouping multiple sources of cargo information in order to create a single amount to track. This functionality can be used to track the amount of cargo needed to supply a single industry (such as a steel mill) from a hub station. A cargo group can contain industries, shipping contracts and other cargo groups.

Using the original map, we create 5 lines:

- 3 for the suppliers to the cargo hub in the middle of the map
- 2 for the consumers, from the cargo hub

![Cargo group lines](images/map_lines.png)

The setup for the suppliers can simply use the "Industry" as the source of information. The lines to the steel mills need to carry both iron ore and coal.

After opening the Autosizer window - click on the "Cargo Tracking" tab and click the "New Cargo Group" button on the left side:

![Cargo groups](images/cargo_group1.png)

On the right side a new set of options appears. They allow us to add members to the cargo group. We can add an industry, a shipping contract or another cargo group. Clicking on "Industry" button opens a drop-down list with all the industries on the map (that are in catchment areas of a station).

![Cargo groups](images/cargo_group2.png)

Let's add both iron ore and coal (adding members also updates the name of the cargo group)

![Cargo groups](images/cargo_group3.png)

Now that we have the cargo group - we can go back to the "Lines" tab and select the hub to steel mill line. From the selectors - we chose cargo group and click the "Select" button:

![Cargo groups](images/cargo_group4.png)

But when the trains pulls into the hub station the line status turns orange, hovering over the status dot reveals a problem:

![Cargo groups](images/cargo_group5.png)

A single train is not enough to carry all the cargo. This can be fixed by simply adding another train onto the line. The mod automatically splits the number of wagons required between all the trains on the line. If you enable the departure scheduler this mod will make sure that the trains are spaced evenly on the line.

## Mod settings

The settings tab provides the ability to adjust some global settings and also can show the performance metrics of the mod. 

![Settings](images/settings.png)

### Minimal train wagon count

This number is used to determine the minimal number of wagons the train should end up with after the adjustment process. This might be for either aesthetic or performance reasons. By default it's set to 1. If you want to use engine-only trains - this slider must be moved to 0.

### Default maximal train length

This number is used in train adjustment calculations to determine how long the train can be. By default it's 160m. Changing the value here adjusts it for all lines that use the 'Global' setting.

### Enable scheduler

This option enables the departures scheduler at each station that's been configured.

### Show tracking details

This option enables an additional panel in the line settings that shows the current tracking information about the trains.

### Enable timings

Enabling this option turns on performance tracking in the mod. The performance statistics are displayed on the right side. There are two types of functions here:

Real-time functions:
- `checkTrainsCapacity`
- `checkTrainsPositions`
- `refrshLinesCargoAmounts`

Periodic functions
- `updateSupplyChains`

The 'Total' value shows the amount of time all the real-time functions are taking. The left column shows the average duration of the function execution, the right one - the maximal one (over the last 20 executions).

In addition the table displays the number of trains currently being tracked. More on this in the Performance considerations below.

### Enable debug

Enabling this option turns on extensive debugging into the console log. This might be useful during troubleshooting. This option also enables a number of buttons (in both the settings and line tabs). Generally speaking those buttons either display the state of internal variables, or reset them. Pressing the `!!! Erase state !!!` button results in a "factory-reset" of the mod.


## Additional options

### Train length

By default all calculations use the globally defined train length to determine how long the train can be. This can be changed on per-line settings.

### Picking up waiting cargo

Each station configuration panel has a checkbox labeled "Pick up waiting". If this option is enabled for a station - when the train pulls in any cargo currently waiting (for this line) is counted. If there's more cargo than the train would pick up based on the default calculations - the selected percentage of the surplus cargo is used to calculate the number of extra wagons that should be added in order to accommodate the waiting cargo:

![Pickup waiting](images/pickup_waiting.png)

If the slider is set to 100% the train will attempt to pick up all the waiting cargo. That is likely to result in the train being very long (and slow). Also the subsequent train might end up being quite empty, so some discretion in use of this option is advised. This option also has performance implications (more on that further on).

Selecting the 'Auto-clear' checkbox means that if there's no additional (beyond what's expected from the regular calculations) cargo waiting - the "Pick up waiting" option will be switched off. This configuration can be used to clear any backlog of cargo at the station - once the backlog is gone - the trains go back to their default configurations.

### Manually adjusting wagon capacity

In order to speed up the calculations the mod assumes that each wagon has the same capacity for each type of cargo. This works for the default wagons, but not for some of those that come from mods. If there are different capacities for different cargos - the smallest amount found is used as the default capacity for a given wagon model in all calculations. This might result in incorrect capacity calculations (particularly for longer trains). In order to correct this the "Adjust capacity" option can be used:

![Adjust capacity](images/adjust_capacity.png)

Moving the slider permanently adjusts the discovered capacity of the wagons for the calculations at that station.

### Departure scheduler

Enabling the departure scheduler for a station means that the mod will try to time the departures of the trains, so they're evenly spaced on the line. Since the frequency of the line means how often (on average) the trains depart from any given station - that value is used. When the scheduler is enabled - the value gets displayed:

![Departure scheduler](images/departure_scheduler1.png)

In addtion, if display of train tracking information is enabled in settings, the train tracking panel show how long before the train departs:

![Departure scheduler](images/departure_scheduler2.png)

The scheduler relies on the in-game frequency calculations by default. If the invidual round-trips vary singnificantly in duration (for example due to random congestion or large number of passing loops on a long single-track line) the scheduler will keep on adjusting the wait times but won't be able to settle. 

### Trains with no wagons

It's possible to reduce the number of wagons to zero and end up with an engine-only train, this can be achieved in two ways:

- by using the 'fixed amount' option and setting it to 0
- by using a cargo group with no members

There are some unintended consequences of doing that:

- the game stops properly tracking round trip times (frequency), so the mod's own tracking steps in, but these calculations are not as exact as the ones done by the game. They rely on measuring the loading/unloading time at each station, and that information can only be captured when the train is actually at the station, so the accuracy gets better with time (average of last 5 load/unload times are used)
  
- if there's only one train on the line, the moment its wagons are gone the supply chains get broken, so the industries stop producing and the cargo starts to disappear from the station. The only way to prevent this is to make sure there's at least one train with wagons left on the line.


## Train adjustment process

The addition and removal of wagons happens at the stations. The calculation to determine the train length are carried out before the train starts to unload, but the actual adjustment generally only happens about 200ms before the train is completely empty - it's not possible to catch the "empty" moment exactly and if the adjustment is carried out too late - the newly added wagons don't load.

In two special cases the train adjustment happens at different times:

- if the required capacity at the station is 0 (either set manually, via the 'Fixed amount' or by using an empty cargo group) the train is adjusted as it departs for the next station (this is to ensure that no cargo is lost during unloading)

- if the train arrives at the station with no wagons - it's adjusted before the loading starts.

The mod discovers the models of the wagons on the line. When it needs to add more wagons it randomly selects from the available pool.  The discovered models are displayed in the line settings panel:

![Wagons](images/wagons.png)

There can be multiple different models here, the mod identifies what types of cargo can be carried by each type of wagon. When new wagons need to be added - generic wagons (i.e. those that can carry more than one cargo) are preferred over specific ones. These models are cached once discovered. If you decide to change the model of the wagons by adding a new train with different models - they have to be manually rediscovered by using the 'Refresh' button, that forces the mod to scan all the trains on the line and identify the wagons.

## Other mods compatibility

I have tested this mod with a number of other mods that provide different types of wagons and I haven't encountered any issues. Both single and multi-compartment wagons are supported. The economy mods that add more types of cargo are also supported. This mod also works with the Timetable mod.

## Performance considerations

This mod contains three different types of functions:

- real-time, run at every tick of the game (i.e every 200ms)
- periodic, run every 2 seconds and spread over multiple ticks
- on-demand (mostly triggered by the UI)

The real-time functions are associated with tracking of the trains and carrying out train replacements. If a train's capacity needs to be adjusted at the next stop, from the moment that's identified the train status will be polled at every tick. Large number of tracked trains leads to the main function taking longer. The amount of time it takes can be seen in settings under 'Total' row (if performance tracking is enabled in the settings). If there are no other CPU intensive mods in the game generally times under 100ms should be fine.

All other functions (particularly those associated with updating of the production/consumption data) are set to only run for up 50ms per tick, which should leave enough headroom for the real-time functions.

The configuration of the lines does have an impact on the performance:

- Lines that have only one station enabled tend to have the most stable train length and only require the trains to be tracked occasionally
- Enabling pickup of waiting cargo at a station means that the trains always need to be tracked when heading to that station
- Lines that have more than one station enabled  need tracking of all trains heading to those enabled stations if the enabled stations require different capacities
- Enabling zero-length trains on the line (by setting the fixed amount of cargo to 0 at any of the stations or by using empty cargo group) forces all the trains on that line to be tracked permanently

The settings tab displays the number of tracked trains (if performance tracking is enabled).

One other consideration is the number of API calls made by the mod to the game. Each train check requires an API call, so if there are 200 tracked trains that means 1000 calls a second. That in itself shouldn't be a problem, but I've noticed (particularly on very large maps) that sometimes the API starts to return invalid information when queried very quickly. If that happens the mod stops querying the API in that tick. This shows up in the console log as messages similar to this one: `couldn't get info from the API`, if the following number is `0` that means that the API stopped responding correctly. If this starts to happen more frequently the game will most likely crash.
  
## Known issues aka features

1. Visual glitches when trains are being reconfigured casing the wagons overlap on departure
    Due to the way the game calculates the train stopping position (based on the length of the train when it enters the station) when new wagons are added they have to fit into roughly the same space as the original train. That leads to an 'accordion' effect when the train departs.

2. When trains get reconfigured at more than one station on a line the line "rate"  displayed in the game is not accurate any more.
  
3. At any given station all trains are configured to the same length by default (actual train might be longer if the station is configured for waiting cargo pickup), which can lead to overprovisioning of the line capacity. Lower numbers of longer trains on the line allows for better accuracy.

4. Multiheaded trains are supported, but all engines must be at the front of the train, otherwise they might get deleted when the train is scaled down.

5. If a train picks up multiple types of cargo at the station some capacity might be lost due to wagons not loading fully. This generally shouldn't be an issue, as some overprovisioning happens naturally.

6. All wagons in a single train do not have to be capable of carrying the same set of cargos. The capacity for each type of cargo is tracked separately.

7. Using full load all/any leads to much longer round-trip times, but the mod correctly takes this into account and creates longer trains as necessary. The  Timetable mod has the same effect.

8. It's always the last wagons that get removed from the train. The maintenance data of the original engine and wagons is copied to the new train. That might result in the game displaying the train as having multiple groups of the same wagons (instead of just one group).

9. Generation of the new train configuration happens as the train is almost unloaded. If the train is stopped by the scheduler the configuration is generated when the train is started again.

10. There's a known issue when the train gets singificantly expanded at a station, but didn't offload much cargo (for example a train that picks up logs from two forests, increasing length at the second forest). That might lead the the train leaving with partially empty wagons. The only way to ensure this doesn't happen is to adjust the train at the previous stop.