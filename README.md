# MyDPS

by Grimmier

## Scrolling Combat window and DPS reporting for MacroQuest.

Creates a window to output your damage to. When first opened you are presented with the options display. While the options is displayed, you can adjust the size and position of the window. Atfer you have configured your settings and positioned the window, click the Start button.

Once you Press the Start button, the Window will change backgrounds and become click-through. You will not be able to interact with it. To allow moving of the window you can use ```/mydps move``` to toggle mouse interaction (for moveing) on|off or you can use ```/mydps ui``` to re-enter the options view, where you can edit settings and resize / move the window. 

The script will keep track of Damage over a Time span (customizable) and Per Battle. You can set auto reporting to console for both; Timespan reporting will happen evern x amount of time, you set this delay; Battle reporting will happen when the fights over. There are also options for reporting this over DanNet Group channel. 

There is a Battle History window you can toggle to show your past battle reports. You can also report this table to console with a command line prompt as well. 

## UI Settings

* Configure custom colors for different damage types.
* Configure the window background color and alpha to use when started.
* Preview button so you can adjust colors against the background set.


* Sliders for:
  * Font Scale
  * Display Time
  * Auto Reporting Interval


* Toggles for: 
  * Your Misses
  * NPC Misses YOU
  * NPC Hits YOU
  * Damage Shields (unassigned non-melee)
  * Show Target Name
  * Show Damage Type
  * Auto Report DPS (Time Based)
  * Auto Report DPS (Per Battle)
  * Sorting Toggle by Timestamp

## Commands

* ```/lua run mydps``` - Run the script.
* ```/lua run mydps start``` - Run and Start, bypassing the Options Display.
* ```/mydps start``` - Start the DPS window.
* ```/mydps exit``` - Exit the script.
* ```/mydps ui``` - Show the UI.
* ```/mydps clear``` - Clear the table.
* ```/mydps showtype``` - Show the type of attack.
* ```/mydps showtarget``` - Show the target of the attack.
* ```/mydps showds``` - Show damage shield.
* ```/mydps history``` - Show the battle history window.
* ```/mydps mymisses``` - Show my misses.
* ```/mydps missed-me``` - Show NPC missed me.
* ```/mydps hitme``` - Show NPC hit me.
* ```/mydps sort``` - Sort newest on top.
* ```/mydps settings``` - Show current settings.
* ```/mydps doreporting [all|battle|time] ``` - Toggle DPS Auto DPS reporting on for 'Battles, Time based, or BOTH'.
* ```/mydps report``` - Report the Time Based DPS since Last Report.
* ```/mydps battlereport``` - Report the battle history to console.
* ```/mydps announce``` - Toggle Announce to DanNet Group.
* ```/mydps move``` - Toggle click through, allows moving of window.
* ```/mydps delay #``` - Set the display time in seconds.
* ```/mydps help``` - Show this help.

## Reporting

* ```/mydps report``` or if you have auto reporting out will output like below.
* Timespan is based on your settings for auto reporting if Auto Reporting is enabled
  * Otherwise Timespan is since the last time reported.

```
[MyDPS] Char: CHARNAME, DPS (NO DS): 31.63, TimeSpan: 2.57 min, Total Damage: 4871, Total Attempts: 29, Average: 167
[MyDPS] Char: CHARNAME, DPS (DS Dmg): 5.82, TimeSpan: 2.57 min, Total Damage: 896, Total Hits: 13
[MyDPS] Char: CHARNAME, DPS (ALL): 37.45, TimeSpan: 2.57 min, Total Damage: 5767, Total Attempts: 42, Average: 137
```

* Battle Based Reportting if enabled will start recording when you enter COMBAT and report when the fighting is over.
* ```/mydps battlereport``` will output the table of battles to console.

### Normal Combat Report (after a battle)
```[MyDPS] Char: CHARNAME, DPS (BATTLE): 182.31, TimeSpan: 29 sec, Total Damage: 5287```

### Battle History Report (console)
```
[MyDPS] Char: CHARNAME, Battle: 1, DPS: 118.08, Duration: 12 sec, Total Damage: 1417
[MyDPS] Char: CHARNAME, Battle: 2, DPS: 199.40, Duration: 20 sec, Total Damage: 3988
[MyDPS] Char: CHARNAME, Battle: 3, DPS: 137.08, Duration: 36 sec, Total Damage: 4935
```