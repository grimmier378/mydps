# MyDPS
by Grimmier

## Scrolling Combat window for MacroQuest.

Creates a window to output your damage to. When first opened you are presented with the options display. While the options is displayed, you can adjust the size and position of the window. Atfer you have configured your settings and positioned the window, click the Start button.

Once you Press the Start button, the Window will change backgrounds and become click-through. You will not be able to interact with it. To allow moving of the window you can use ```/mydps move``` to toggle mouse interaction (for moveing) on|off or you can use ```/mydps ui``` to re-enter the options view, where you can edit settings and resize / move the window. 

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
* ```/mydps mymisses``` - Show my misses.
* ```/mydps missed-me``` - Show NPC missed me.
* ```/mydps hitme``` - Show NPC hit me.
* ```/mydps sort``` - Sort newest on top.
* ```/mydps settings``` - Show current settings.
* ```/mydps doreporting [all|battle|time]``` - Toggle DPS Auto DPS reporting on for 'Battles, Time based, or BOTH'.
* ```/mydps report``` - Report the Time Based DPS since Last Report.
* ```/mydps move``` - Toggle click through, allows moving of window.
* ```/mydps delay #``` - Set the display time in seconds.
* ```/mydps help``` - Show this help.

## Reporting

* ```/mydps report``` or if you have auto reporting out will output like below.
* Timespan is based on your settings for auto reporting if Auto Reporting is enabled
  * Otherwise Timespan is since the last time reported.

```
[MyDPS] DPS (NO DS): 31.63, TimeSpan: 2.57 min, Total Damage: 4871, Total Attempts: 29, Average: 167
[MyDPS] DPS (DS Dmg): 5.82, TimeSpan: 2.57 min, Total Damage: 896, Total Hits: 13
[MyDPS] DPS (ALL): 37.45, TimeSpan: 2.57 min, Total Damage: 5767, Total Attempts: 42, Average: 137
```

* Battle Based Reportting if enabled will start recording when you enter COMBAT and report when the fighting is over.

```[MyDPS] DPS (BATTLE): 182.31, TimeSpan: 29 sec, Total Damage: 5287```