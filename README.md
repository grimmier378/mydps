# MyDPS

## Scrolling Combat window for MacroQuest.

## UI Settings

* Configure custom colors for different damage types.
* Configure the window background color and alpha to use when started.
* Preview button so you can adjust colors against the background set.
* Sliders for:
* * Font Scale
* * Display Time
* * Auto Reporting Interval
* Toggles for: 
* * Your Misses
* * NPC Misses YOU
* * NPC Hits YOU
* * Damage Shields (unassigned non-melee)
* * Show Target Name
* * Show Damage Type
* * Auto Report DPS
* * Sorting Toggle by Timestamp

## Commands

* /mydps start - Start the DPS window.
* /mydps exit - Exit the script.
* /mydps ui - Show the UI.
* /mydps clear - Clear the table.
* /mydps showtype - Show the type of attack.
* /mydps showtarget - Show the target of the attack.
* /mydps showds - Show damage shield.
* /mydps mymisses - Show my misses.
* /mydps missedme - Show NPC missed me.
* /mydps hitme - Show NPC hit me.
* /mydps sort - Sort newest on top.
* /mydps settings - Show current settings.
* /mydps dodps - Toggle DPS Auto Reporting.
* /mydps report - Report the current DPS since Last Report.
* /mydps move - Toggle click through, allows moving of window.
* /mydps delay # - Set the display time in seconds.
* /mydps help - Show this help.

## Reporting

* ```/mydps report``` or if you have auto reporting out will output like below.
* Timespan is based on your settings for auto reporting if Auto Reporting is enabled
* * Otherwise Timespan is since the last time reported.

```
[MyDPS] DPS (NO DS): 31.63, TimeSpan: 2.57 min, Total Damage: 4871, Total Attempts: 29, Average: 167
[MyDPS] DPS (DS Dmg): 5.82, TimeSpan: 2.57 min, Total Damage: 896, Total Hits: 13
[MyDPS] DPS (ALL): 37.45, TimeSpan: 2.57 min, Total Damage: 5767, Total Attempts: 42, Average: 137
```
