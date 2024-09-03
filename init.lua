local mq = require('mq')
local ImGui = require('ImGui')
local script = 'MyDPS'
local configFile = string.format("%s/MyUI/%s/%s/%s.lua", mq.configDir, script, mq.TLO.EverQuest.Server(), mq.TLO.Me.Name())
local RUNNING = true
local damTable, settings = {}, {}
local MyName = mq.TLO.Me.CleanName()
local winFlags = bit32.bor(ImGuiWindowFlags.None,
		ImGuiWindowFlags.NoTitleBar)
local started = false
local fontScale = 1.0
local clickThrough = false
local tableSize = 0
local sequenceCounter, battleCounter = 0, 0
local dpsStartTime = os.time()
local previewBG, showBattleHistory = false, false
local dmgTotal, dmgCounter, dsCounter, dmgTotalDS, dmgTotalBattle, dmgBattCounter = 0, 0, 0, 0, 0, 0
local workingTable, battlesHistory = {}, {}
local enteredCombat = false
local showCombatWindow = true
local battleStartTime, leftCombatTime = 0, 0

local defaults = {
	Options = {
		sortNewest = false,
		showType = true,
		showTarget = true,
		showMyMisses = true,
		showMissMe = true,
		showHitMe = true,
		showDS = true,
		showHistory = false,
		displayTime = 10,
		fontScale = 1.0,
		bgColor = {0, 0, 0, 0.5},
		dpsTimeSpanReportTimer = 60,
		dpsTimeSpanReport = true,
		dpsBattleReport = true,
		announceDNET = false,
		battleDuration = 10,
		sortHistory = false,
	},
	MeleeColors = {
		["crush"] = { 1, 1, 1, 1},
		["kick"] = { 1, 1, 1, 1},
		["bite"] = { 1, 1, 1, 1},
		["bash"] = { 1, 1, 1, 1},
		["hit"] = { 1, 1, 1, 1},
		["pierce"] = { 1, 1, 1, 1},
		["backstab"] = {1,0,0,1},
		["slash"] = { 1, 1, 1, 1},
		["miss"] = { 0.5, 0.5, 0.5, 1},
		["missed-me"] = { 0.5, 0.5, 0.5, 1},
		["non-melee"] = {0,1,1,1},
		["hit-by"] = {1,0,0,1},
		["crit"] = {1,1,0,1},
		["hit-by-non-melee"] = {1,1,0,1},
		["gothit-non-melee"] = {1,1,0,1},
		["dShield"] = {0,1,0,1},
	}
}

local function File_Exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function loadSettings()
	if not File_Exists(configFile) then
		settings = defaults
		mq.pickle(configFile, settings)
	else
		settings = dofile(configFile)
		if not settings then
			settings = {}
			settings = defaults
		end
	end
	local newSetting = false
	for k, v in pairs(defaults.MeleeColors) do
		if settings.MeleeColors[k] == nil then
			settings.MeleeColors[k] = v
			newSetting = true
		end
	end
	for k, v in pairs(defaults.Options) do
		if settings.Options[k] == nil then
			settings.Options[k] = v
			newSetting = true
		end
	end

	fontScale = settings.Options.fontScale or fontScale
	showBattleHistory = settings.Options.showHistory or showBattleHistory
	if newSetting then mq.pickle(configFile, settings) end
end

---comment
---@param tbl table @ table to sort
---@param sortType string @ type of sort (combat, history)
---@return table @ sorted table
local function sortTable(tbl, sortType)
	if sortType == nil then return tbl end
	if #tbl == 0 then return tbl end
	table.sort(tbl, function(a, b)
		if sortType == 'combat' then
			if settings.Options.sortNewest then
				return (a.sequence > b.sequence)
			else
				return (a.sequence < b.sequence)
			end
		else
			if settings.Options.sortHistory then
				return (a.sequence > b.sequence)
			else
				return (a.sequence < b.sequence)
			end
		end
	end)
	return tbl
end

local function parseCurrentBattle(dur)
	if not enteredCombat then return end
	if dur > 0 then
		local dps = dur > 0 and (dmgTotalBattle / dur) or 0
		local avgDmg = dmgBattCounter > 0 and (dmgTotalBattle / dmgBattCounter) or 0
		local exists = false
		for k, v in pairs (battlesHistory) do
			if v.sequence == -1 or v.sequence == 9999 then
				v.sequence = settings.Options.sortHistory and 9999 or -1
				v.dps = dps
				v.dur = dur
				v.dmg = dmgTotalBattle
				v.avg = avgDmg
				exists = true
				break
			end
		end
		if not exists then
			table.insert(battlesHistory , {sequence = (settings.Options.sortHistory and 9999 or -1), dps = dps, dur = dur, dmg = dmgTotalBattle, avg = avgDmg})
		end
		battlesHistory = sortTable(battlesHistory, 'history')
	end
end

local function npcMeleeCallBack(line, dType, target, dmg)
	if not tonumber(dmg) then
		type = 'missed-me'
		dmg = 'MISSED'
	else
		type = 'hit-by'
		local startType, stopType = string.find(line, "(%w+) YOU")
		target = string.sub(line, 1, startType - 2)
	end
	if target == nil then return end
	if not enteredCombat then
		enteredCombat = true
		dmgBattCounter = 0
		dmgTotalBattle = 0
		battleStartTime = os.time()
		leftCombatTime = 0
	end
	parseCurrentBattle(os.time() - battleStartTime)
	if not settings.Options.showMissMe and type == 'missed-me' then return end
	if not settings.Options.showHitMe and type == 'hit-by' then return end
	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
end

local function nonMeleeClallBack(line, target, dmg)
	if not tonumber(dmg) then return end
	if not enteredCombat then
		enteredCombat = true
		dmgBattCounter = 0
		dmgTotalBattle = 0
		battleStartTime = os.time()
		leftCombatTime = 0
	end
	local type = "non-melee"
	if target == nil then target = 'YOU' type = "hit-by-non-melee" end

	if string.find(line, "was hit") then
		target = string.sub(line, 1, string.find(line, "was") - 2)
		type = "dShield"
	end

	if type ~= 'dShield' then
		dmgTotal = dmgTotal + (tonumber(dmg) or 0)
		dmgCounter = dmgCounter + 1
		if enteredCombat then
			dmgTotalBattle = dmgTotalBattle + (tonumber(dmg) or 0)
			dmgBattCounter = dmgBattCounter + 1
		end
	else
		dmgTotalDS = dmgTotalDS + (tonumber(dmg) or 0)
		dsCounter = dsCounter + 1
		if enteredCombat then
			dmgTotalBattle = dmgTotalBattle + (tonumber(dmg) or 0)
			dmgBattCounter = dmgBattCounter + 1
		end
	end

	if not settings.Options.showDS and type == 'dShield' then parseCurrentBattle(os.time() - battleStartTime) return end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function meleeCallBack(line, dType, target, dmg)
	if string.find(line, "have been healed") then return end
	local type = dType or nil
	if type == nil then return end
	if not enteredCombat then
		enteredCombat = true
		dmgBattCounter = 0
		dmgTotalBattle = 0
		battleStartTime = os.time()
		leftCombatTime = 0
	end
	if dmg == nil then
		dmg = 'MISSED'
		type = 'miss'
	end

	dmgTotal = dmgTotal + (tonumber(dmg) or 0)
	dmgCounter = dmgCounter + 1
	if enteredCombat then
		dmgTotalBattle = dmgTotalBattle + (tonumber(dmg) or 0)
		dmgBattCounter = dmgBattCounter + 1
	end

	if not settings.Options.showMyMisses and type == 'miss' then parseCurrentBattle(os.time() - battleStartTime) return end

	if type == 'miss' then target = 'YOU' end
	if damTable == nil then damTable = {} end
	
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function critalCallBack(line, dmg)
	if not tonumber(dmg) then return end
	if not enteredCombat then
		enteredCombat = true
		battleStartTime = os.time()
		leftCombatTime = 0
	end
	dmgTotal = dmgTotal + (tonumber(dmg) or 0)
	dmgCounter = dmgCounter + 1
	if enteredCombat then
		dmgTotalBattle = dmgTotalBattle + (tonumber(dmg) or 0)
		dmgBattCounter = dmgBattCounter + 1
	end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = "crit", target = mq.TLO.Target.CleanName(), damage = string.format("CRIT <%d>",dmg),
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function cleanTable()
	if tableSize > 0 then
		local currentTime = os.time()
		local i = 1
		while i <= tableSize do
			if currentTime - damTable[i].timestamp > settings.Options.displayTime then
				table.remove(damTable, i)
				tableSize = tableSize - 1
			else
				i = i + 1
			end
		end
	end
end

---comment
---@param t any
---@return table
local function checkColor(t)
	if settings.MeleeColors[t] then
		return settings.MeleeColors[t]
	else
		return {1, 1, 1, 1}
	end
end

local function Draw_GUI()
	if not RUNNING then return end
	if showCombatWindow then
		ImGui.SetNextWindowSize(400, 200, ImGuiCond.FirstUseEver)
		local bgColor = settings.Options.bgColor
		if previewBG or started then
			ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(bgColor[1], bgColor[2], bgColor[3], bgColor[4]))
		else
			ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.1, 0.1, 0.1, 0.9))
		end
		local open, show = ImGui.Begin(script.."##"..mq.TLO.Me.Name(), true, winFlags)
		if not open then
			RUNNING = false
		end
		if show then
			ImGui.SetWindowFontScale(fontScale)
			if not started then
					ImGui.PushTextWrapPos((ImGui.GetWindowContentRegionWidth() - 20) or 20)
					ImGui.Text("This will show the last %d seconds of YOUR melee attacks. \nThe window is click through after you start.\n run /mydps help for a list of commands. \nClick button to enable. /lua stop %s to close.", settings.Options.displayTime, script)
					ImGui.PopTextWrapPos()
					-- ImGui.Text("The window is click through after you start.")
					-- ImGui.Text("/mydps help for a list of commands.")
					-- ImGui.Text("Click button to enable. /lua stop %s to close.", script)

				if ImGui.CollapsingHeader("Color Key") then
					if ImGui.BeginTable("Color Key", 2, ImGuiTableFlags.Borders) then
						for type, color in pairs(settings.MeleeColors) do
							ImGui.TableNextColumn()
							settings.MeleeColors[type] = ImGui.ColorEdit4(type, color, bit32.bor(ImGuiColorEditFlags.NoInputs, ImGuiColorEditFlags.AlphaBar))
							ImGui.SameLine()
							ImGui.HelpMarker(string.format("Set the color for %s messages.", type))
						end
						ImGui.EndTable()
					end
					ImGui.SeparatorText("Window Background Color")
					settings.Options.bgColor = ImGui.ColorEdit4("Background Color", settings.Options.bgColor, bit32.bor(ImGuiColorEditFlags.NoInputs, ImGuiColorEditFlags.AlphaBar))
					ImGui.SameLine()
					ImGui.HelpMarker("Set the background color of the window.")
					ImGui.SameLine()
					if ImGui.Button("BG Preview") then
						previewBG = not previewBG
					end
				end

				if ImGui.CollapsingHeader("Options") then
					settings.Options.showType = ImGui.Checkbox("Show Type", settings.Options.showType)
					ImGui.SameLine()
					ImGui.HelpMarker("Show the type of attack.")
					settings.Options.showTarget = ImGui.Checkbox("Show Target", settings.Options.showTarget)
					ImGui.SameLine()
					ImGui.HelpMarker("Show the target of the attack. or YOU MISS")
					settings.Options.sortNewest = ImGui.Checkbox("Sort Newest Combat Spam on top", settings.Options.sortNewest)
					ImGui.SameLine()
					ImGui.HelpMarker("Sort Combat Spam the newest on top.")
					settings.Options.sortHistory = ImGui.Checkbox("Sort Newest History on top", settings.Options.sortHistory)
					ImGui.SameLine()
					ImGui.HelpMarker("Sort Battle History Table the newest on top.")
					settings.Options.showMyMisses = ImGui.Checkbox("Show My Misses", settings.Options.showMyMisses)
					ImGui.SameLine()
					ImGui.HelpMarker("Show your misses.")
					settings.Options.showMissMe = ImGui.Checkbox("Show Missed Me", settings.Options.showMissMe)
					ImGui.SameLine()
					ImGui.HelpMarker("Show NPC missed you.")
					settings.Options.showHitMe = ImGui.Checkbox("Show Hit Me", settings.Options.showHitMe)
					ImGui.SameLine()
					ImGui.HelpMarker("Show NPC hit you.")
					settings.Options.showDS = ImGui.Checkbox("Show Damage Shield", settings.Options.showDS)
					ImGui.SameLine()
					ImGui.HelpMarker("Show Damage Shield Spam Damage.")
					settings.Options.dpsTimeSpanReport = ImGui.Checkbox("Do DPS over Time Reporting", settings.Options.dpsTimeSpanReport)
					ImGui.SameLine()
					ImGui.HelpMarker("Report DPS over a set time span.")
					settings.Options.dpsBattleReport = ImGui.Checkbox("Do DPS Battle Reporting", settings.Options.dpsBattleReport)
					ImGui.SameLine()
					ImGui.HelpMarker("Report DPS For last Battle.")
					showBattleHistory = ImGui.Checkbox("Show Battle History", showBattleHistory)
					if showBattleHistory ~= settings.Options.showHistory then
						settings.Options.showHistory = showBattleHistory
						mq.pickle(configFile, settings)
					end
					ImGui.SameLine()
					ImGui.HelpMarker("Show the Battle History Window.")
					settings.Options.announceDNET = ImGui.Checkbox("Announce to DanNet Group", settings.Options.announceDNET)
					ImGui.SameLine()
					ImGui.HelpMarker("Announce DPS Reports to DanNet Group.")
					local tmpTimer = settings.Options.dpsTimeSpanReportTimer / 60
					ImGui.SetNextItemWidth(120)
					tmpTimer = ImGui.SliderFloat("DPS Report Timer (minutes)", tmpTimer, 0.5, 60, "%.2f")
					ImGui.SameLine()
					ImGui.HelpMarker("Set the time span for DPS Over Time Span Reporting.")
					if tmpTimer ~= settings.Options.dpsTimeSpanReportTimer then
						settings.Options.dpsTimeSpanReportTimer = tmpTimer * 60
					end
					ImGui.SetNextItemWidth(120)
					settings.Options.battleDuration = ImGui.InputInt("Battle Duration End Delay", settings.Options.battleDuration)
					ImGui.SameLine()
					ImGui.HelpMarker("Set the time in seconds to make sure we dont enter combat again.\n This will allow Battle Reports to handle toons that have long delay's between engaging the next mob.")
				end

				ImGui.SetNextItemWidth(120)
				settings.Options.displayTime = ImGui.SliderInt("Display Time", settings.Options.displayTime, 1, 60)
				ImGui.SameLine()
				ImGui.HelpMarker("Set the time in seconds to display the damage.")

				ImGui.SetNextItemWidth(120)
				fontScale = ImGui.SliderFloat("Font Scale", fontScale, 0.5, 2, "%.2f")
				ImGui.SameLine()
				ImGui.HelpMarker("Set the font scale for the window.")

				if ImGui.Button("Start") then
					settings.Options.fontScale = fontScale
					mq.pickle(configFile, settings)
					clickThrough = true
					started = true
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Start the DPS Window.")
				end
				ImGui.SameLine()
				if ImGui.Button("Hide") then
					mq.pickle(configFile, settings)
					showCombatWindow = false
				end
				if ImGui.IsItemHovered() then
					ImGui.SetTooltip("Hide the DPS Window.")
				end
			else
				if tableSize > 0 and workingTable ~= nil then
					for i, v in ipairs(workingTable) do
						local color = checkColor(v.type)
						local output = ""

						if settings.Options.showType and v.type ~= nil then
							output = output .. " " .. v.type
						end

						if settings.Options.showTarget and v.target ~= nil then
							output = output .. " " .. v.target
						end

						if v.damage ~= nil then
							output = output .. " " .. v.damage

							-- Display the output text with color
							ImGui.TextColored(ImVec4(color[1], color[2], color[3], color[4]), "%s", output)
						end
					end
				end
			end
			ImGui.PopStyleColor()
			ImGui.SetWindowFontScale(1)
		end
		ImGui.End()
	end

	if showBattleHistory then
		ImGui.SetNextWindowSize(400, 200, ImGuiCond.FirstUseEver)
		local openReport, showReport = ImGui.Begin("Battles##"..mq.TLO.Me.Name(), true, ImGuiWindowFlags.None)
		if not openReport then
			showBattleHistory = false
			settings.Options.showHistory = false
			mq.pickle(configFile, settings)
			printf("\aw[\at%s\ax] \ayShow Battle History set to %s\ax", script, showBattleHistory)
		end
		if showReport then
			if settings.Options.showHistory ~= showBattleHistory then
				settings.Options.showHistory = showBattleHistory
				mq.pickle(configFile, settings)
			end
			ImGui.SetWindowFontScale(fontScale)
			if #battlesHistory > 0 then
				if ImGui.BeginTable("Battles", 5, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable)) then
					ImGui.TableSetupColumn("Battle", ImGuiTableColumnFlags.None)
					ImGui.TableSetupColumn("DPS", ImGuiTableColumnFlags.None)
					ImGui.TableSetupColumn("Duration", ImGuiTableColumnFlags.None)
					ImGui.TableSetupColumn("Avg. Damage", ImGuiTableColumnFlags.None)
					ImGui.TableSetupColumn("Total Damage", ImGuiTableColumnFlags.None)
					ImGui.TableSetupScrollFreeze(0, 1)
					ImGui.TableHeadersRow()
					for i, v in ipairs(battlesHistory) do
						ImGui.TableNextRow()
						ImGui.TableNextColumn()
						ImGui.Text("%s", ((v.sequence == -1 or v.sequence == 9999) and "Current" or v.sequence))
						ImGui.TableNextColumn()
						ImGui.Text("%.2f", v.dps)
						ImGui.TableNextColumn()
						ImGui.Text("%.0f", v.dur)
						ImGui.TableNextColumn()
						ImGui.Text("%d", v.avg)
						ImGui.TableNextColumn()
						ImGui.Text("%d", v.dmg)
					end
					ImGui.EndTable()
				end
			end
		end
		ImGui.End()
	end
end

local function pHelp()
	printf("\aw[\at%s\ax] \ayCommands\ax", script)
	printf("\aw[\at%s\ax] \ay/lua run mydps\ax - Run the script.", script)
	printf("\aw[\at%s\ax] \ay/lua run mydps start\ax - Run and Start, bypassing the Options Display.", script)
	printf("\aw[\at%s\ax] \ay/lua run mydps start hide\ax - Run and Start, bypassing the Options Display and Hides the Spam Window.", script)
	printf("\aw[\at%s\ax] \ay/mydps start\ax - Start the DPS window.", script)
	printf("\aw[\at%s\ax] \ay/mydps exit\ax - Exit the script.", script)
	printf("\aw[\at%s\ax] \ay/mydps ui\ax - Toggle the Options UI.", script)
	printf("\aw[\at%s\ax] \ay/mydps hide\ax - Toggles show|hide of the Damage Spam Window.", script)
	printf("\aw[\at%s\ax] \ay/mydps clear\ax - Clear the data.", script)
	printf("\aw[\at%s\ax] \ay/mydps showtype\ax - Toggle Showing the type of attack.", script)
	printf("\aw[\at%s\ax] \ay/mydps showtarget\ax - Toggle Showing the Target of the attack.", script)
	printf("\aw[\at%s\ax] \ay/mydps showds\ax - Toggle Showing damage shield.", script)
	printf("\aw[\at%s\ax] \ay/mydps history\ax - Toggle the battle history window.", script)
	printf("\aw[\at%s\ax] \ay/mydps mymisses\ax - Toggle Showing my misses.", script)
	printf("\aw[\at%s\ax] \ay/mydps missed-me\ax - Toggle Showing NPC missed me.", script)
	printf("\aw[\at%s\ax] \ay/mydps hitme\ax - Toggle Showing NPC hit me.", script)
	printf("\aw[\at%s\ax] \ay/mydps sort [new|old]\ax - Sort Toggle newest on top. [new|old] arguments optional so set direction", script)
	printf("\aw[\at%s\ax] \ay/mydps sorthistory [new|old]\ax - Sort history Toggle newest on top. [new|old] arguments optional so set direction", script)
	printf("\aw[\at%s\ax] \ay/mydps settings\ax - Print current settings to console.", script)
	printf("\aw[\at%s\ax] \ay/mydps doreporting [all|battle|time]\ax - Toggle DPS Auto DPS reporting on for 'Battles, Time based, or BOTH'.", script)
	printf("\aw[\at%s\ax] \ay/mydps report\ax - Report the Time Based DPS since Last Report.", script)
	printf("\aw[\at%s\ax] \ay/mydps battlereport\ax - Report the battle history to console.", script)
	printf("\aw[\at%s\ax] \ay/mydps announce\ax - Toggle Announce to DanNet Group.", script)
	printf("\aw[\at%s\ax] \ay/mydps move\ax - Toggle click through, allows moving of window.", script)
	printf("\aw[\at%s\ax] \ay/mydps delay #\ax - Set the combat spam display time in seconds.", script)
	printf("\aw[\at%s\ax] \ay/mydps battledelay #\ax - Set the Battle ending Delay time in seconds.", script)
	printf("\aw[\at%s\ax] \ay/mydps help\ax - Show this help.", script)
end

local function pCurrentSettings()
	for k, v in pairs(settings.Options) do
		if k == "bgColor" then
			printf("\aw[\at%s\ax] \ay%s\ax = {\ar%s\ax, \ag%s\ax, \at%s\ax,\ao %s\ax}", script, k, v[1], v[2], v[3], v[4])
		else
			printf("\aw[\at%s\ax] \ay%s\ax = \at%s", script, k, v)
		end
	end
end

local function announceDanNet(msg)
	if settings.Options.announceDNET then
		mq.cmdf("/squelch /dgt %s", msg)
	end
end

---comment
---@param dur integer @ duration in seconds
---@param rType string @ type of report (ALL, COMBAT)
local function pDPS(dur, rType)
	if dur == nil then printf(printf("\aw[\at%s\ax] \ayNothing to Report! Try again later.",script)) return end
	if rType:lower() == "all" then
		local dps = dur > 0 and (dmgTotal / dur) or 0
		local dpsDS = dur > 0 and (dmgTotalDS / dur) or 0
		local avgDmg = dmgCounter > 0 and (dmgTotal / dmgCounter) or 0
		local grandTotal = dmgTotal + dmgTotalDS
		local grandCounter = dmgCounter + dsCounter
		local grangAvg = grandCounter > 0 and (grandTotal / grandCounter) or 0
		local grandDPS = dur > 0 and (grandTotal / dur) or 0
		local msgNoDS = string.format("\aw[\at%s\ax] \ayDPS \ax(\aoNO DS\ax): \at%.2f\ax, \ayTimeSpan:\ax\ao %.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage: \ax\ao%d\ax",
				script, dps, (dur/60), dmgTotal, dmgCounter,avgDmg )
		local msgDS = string.format("\aw[\at%s\ax] \ayDPS \ax(\atDS Dmg\ax): \at%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Hits: \ax\ao%d\ax",
			script, dpsDS, (dur/60), dmgTotalDS, dsCounter)
		local msgALL = string.format("\aw[\at%s\ax] \ayDPS \ax(\agALL\ax): \ag%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage:\ax \ao%d\ax",
			script, grandDPS, (dur/60), grandTotal, grandCounter, grangAvg)
		printf(msgNoDS)
		printf(msgDS)
		printf(msgALL)
		if settings.Options.announceDNET then
			announceDanNet(msgNoDS)
			announceDanNet(msgDS)
			announceDanNet(msgALL)
		end
		dmgTotal = 0
		dmgCounter = 0
		dmgTotalDS = 0
		dsCounter = 0
		dpsStartTime = os.time()
	elseif rType:lower() == 'combat' then
		local dps = dur > 0 and (dmgTotalBattle / dur) or 0
		local avgDmg = dmgBattCounter > 0 and (dmgTotalBattle / dmgBattCounter) or 0
		battleCounter = battleCounter + 1
		table.insert(battlesHistory , {sequence = battleCounter, dps = dps, dur = dur, dmg = dmgTotalBattle, avg = avgDmg})
		if settings.Options.dpsBattleReport then 
			local msg = string.format("\aw[\at%s\ax] \ayChar:\ax\ao %s\ax, \ayDPS \ax(\aoBATTLE\ax): \at%.2f\ax, \ayTimeSpan:\ax\ao %.0f sec\ax, \ayTotal Damage: \ax\ao%d\ax, \ayAvg. Damage: \ax\ao%d\ax",
				script, MyName, dps, dur, dmgTotalBattle, avgDmg)
			print(msg)
			if settings.Options.announceDNET then
				announceDanNet(msg)
			end
		end
		dmgTotalBattle = 0
		battlesHistory = sortTable(battlesHistory, 'history')
	end
end

local function pBattleHistory()
	if battleCounter  == 0 then
		printf("\aw[\at%s\ax] \ayNo Battle History\ax", script)
		return
	end
	for i, v in ipairs(battlesHistory) do
		local msg = string.format("\aw[\at%s\ax] \ayChar:\ax\ao %s\ax, \ayBattle: \ax\ao%d\ax, \ayDPS: \ax\at%.2f\ax, \ayDuration: \ax\ao%.0f sec\ax, \ayTotal Damage: \ax\ao%d\ax, \ayAvg. Damage: \ax\ao%d\ax",
			script, MyName, v.sequence, v.dps, v.dur, v.dmg, v.avg)
		print(msg)
		if settings.Options.announceDNET then
			announceDanNet(msg)
		end
	end
end

local function processCommand(...)
	local args = {...}
	if #args == 0 then
		printf("\aw[\at%s\ax] \arInvalid command, \ayType /mydps help for a list of commands.", script)
		return
	end
	local cmd = args[1]
	cmd = cmd:lower()
	if cmd == "exit" then
		RUNNING = false
	elseif cmd == "ui" then
		started = false
		showCombatWindow = true
		winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
	elseif cmd == "hide" then
		if #args == 2 then
			if args[2] == 'on' then
				showCombatWindow = false
			elseif args[2] == 'off' then
				showCombatWindow = true
			end
		end
		printf("\aw[\at%s\ax] \ayToggle Combat Spam set to %s\ax", script, showCombatWindow)
	elseif cmd == "clear" then
		damTable, battlesHistory = {}, {}
		battleStartTime, dpsStartTime = 0, 0
		dmgTotal, dmgCounter, dsCounter, dmgTotalDS, battleCounter, tableSize = 0, 0, 0, 0, 0, 0
		printf("\aw[\at%s\ax] \ayTable Cleared\ax", script)
	elseif cmd == 'start' then
		started = true
		clickThrough = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		printf("\aw[\at%s\ax] \ayStarted\ax", script)
	elseif cmd == 'showtype' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showType = true
			elseif args[2] == 'off' then
				settings.Options.showType = false
			end
		else
			settings.Options.showType = not settings.Options.showType
		end
		printf("\aw[\at%s\ax] \ayShow Type set to %s\ax", script, settings.Options.showType)
	elseif cmd == 'showtarget' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showTarget = true
			elseif args[2] == 'off' then
				settings.Options.showTarget = false
			end
		else
			settings.Options.showTarget = not settings.Options.showTarget
		end
		printf("\aw[\at%s\ax] \ayShow Target set to %s\ax", script, settings.Options.showTarget)
	elseif cmd == 'showds' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showDS = true
			elseif args[2] == 'off' then
				settings.Options.showDS = false
			end
		else
			settings.Options.showDS = not settings.Options.showDS
		end
		printf("\aw[\at%s\ax] \ayShow Damage Shield set to %s\ax", script, settings.Options.showDS)
	elseif cmd == 'history' then
		if #args == 2 then
			if args[2] == 'on' then
				showBattleHistory = true
			elseif args[2] == 'off' then
				showBattleHistory = false
			end
		else
			showBattleHistory = not showBattleHistory
		end
		settings.Options.showHistory = showBattleHistory
		printf("\aw[\at%s\ax] \ayShow Battle History set to %s\ax", script, showBattleHistory)
	elseif cmd == 'mymisses' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showMyMisses = true
			elseif args[2] == 'off' then
				settings.Options.showMyMisses = false
			end
		else
			settings.Options.showMyMisses = not settings.Options.showMyMisses
		end
		printf("\aw[\at%s\ax] \ayShow My Misses set to %s\ax", script, settings.Options.showMyMisses)
	elseif cmd == 'missed-me' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showMissMe = true
			elseif args[2] == 'off' then
				settings.Options.showMissMe = false
			end
		else
			settings.Options.showMissMe = not settings.Options.showMissMe
		end
		printf("\aw[\at%s\ax] \ayShow Missed Me set to %s\ax", script, settings.Options.showMissMe)
	elseif cmd == 'hitme' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.showHitMe = true
			elseif args[2] == 'off' then
				settings.Options.showHitMe = false
			end
		else
			settings.Options.showHitMe = not settings.Options.showHitMe
		end
		printf("\aw[\at%s\ax] \ayShow Hit Me set to %s\ax", script, settings.Options.showHitMe)
	elseif cmd == 'sort' then
		if #args == 2 then
			if args[2] == 'new' then
				settings.Options.sortNewest = true
			elseif args[2] == 'old' then
				settings.Options.sortNewest = false
			end
		else
			settings.Options.sortNewest = not settings.Options.sortNewest
		end
		local dir = settings.Options.sortNewest and "Newest" or "Oldest"
		printf("\aw[\at%s\ax] \aySort Combat Spam\ax \at%s \axOn Top!", script, dir)
	elseif cmd == 'sorthistory' then
		if #args == 2 then
			if args[2] == 'new' then
				settings.Options.sortHistory = true
			elseif args[2] == 'old' then
				settings.Options.sortHistory = false
			end
		else
			settings.Options.sortHistory = not settings.Options.sortHistory
		end
		battlesHistory = sortTable(battlesHistory, 'history')
		local dir = settings.Options.sortHistory and "Newest" or "Oldest"
		printf("\aw[\at%s\ax] \aySorted Battle History\ax \at%s \axOn Top!", script, dir)
	elseif cmd == 'move' then
		clickThrough = not clickThrough
		printf("\aw[\at%s\ax] \ayClick Through set to %s\ax", script, clickThrough)
	elseif cmd == 'settings' then
		pCurrentSettings()
	elseif cmd == 'report' then
		local dur = os.time() - dpsStartTime
		pDPS(dur, 'ALL')
	elseif cmd == 'battlereport' then
		pBattleHistory()
	elseif cmd == 'announce' then
		if #args == 2 then
			if args[2] == 'on' then
				settings.Options.announceDNET = true
			elseif args[2] == 'off' then
				settings.Options.announceDNET = false
			end
		else
			settings.Options.announceDNET = not settings.Options.announceDNET
		end
		printf("\aw[\at%s\ax] \ayAnnounce to DanNet Group set to %s\ax", script, settings.Options.announceDNET)
	elseif #args == 2 and cmd == 'doreporting' then
		if args[2] == 'battle' then
			settings.Options.dpsBattleReport = not settings.Options.dpsBattleReport
			printf("\aw[\at%s\ax] \ayDo DPS Battle Reporting set to %s\ax", script, settings.Options.dpsBattleReport)
		elseif args[2] == 'time' then
			settings.Options.dpsTimeSpanReport = not settings.Options.dpsTimeSpanReport
			printf("\aw[\at%s\ax] \ayDo DPS Reporting set to %s\ax", script, settings.Options.dpsTimeSpanReport)
		elseif args[2] == 'all' then
			settings.Options.dpsBattleReport = not settings.Options.dpsBattleReport
			settings.Options.dpsTimeSpanReport = settings.Options.dpsBattleReport
			printf("\aw[\at%s\ax] \ayDo DPS Reporting set to %s\ax", script, settings.Options.dpsTimeSpanReport)
		else
			printf("\aw[\at%s\ax] \arInvalid argument, \ayType \at/mydps doreporting\ax takes arguments \aw[\agall\aw|\agbattle\aw|\agtime\aw] \ayplease try again.", script)
		end	
	elseif #args == 2 and cmd == "delay" then
		if tonumber(args[2]) then
			settings.Options.displayTime = tonumber(args[2])
			printf("\aw[\at%s\ax] \ayDisplay time set to %s\ax", script, settings.Options.displayTime)
		else
			printf("\aw[\at%s\ax] \arInvalid argument, \ayType /mydps help for a list of commands.", script)
		end
	elseif #args == 2 and cmd == "battledelay" then
		if tonumber(args[2]) then
			settings.Options.battleDuration = tonumber(args[2])
			printf("\aw[\at%s\ax] \ayBattle Duration time set to %s\ax", script, settings.Options.battleDuration)
		else
			printf("\aw[\at%s\ax] \arInvalid argument, \ayType /mydps help for a list of commands.", script)
		end
	elseif cmd == "help" then
		pHelp()
	else
		printf("\aw[\at%s\ax] \arUnknown command, \ayType /mydps help for a list of commands.", script)
	end
	mq.pickle(configFile, settings)
end

local args = {...}
local function Init()

	--[[
		Combat : #*# Heals #*# for #*#
		Combat : #*#crush#*#point#*# of damage#*#
		Combat : #*# healed #*# for #*#
		Combat : #*# kick#*#point#*# of damage#*#
		Combat : #*# bite#*#point#*# of damage#*#
		Combat : #*#non-melee#*#
		Combat : #*# bash#*#point#*# of damage#*#
		Combat : #*# hits#*#point#*# of damage#*#
		Combat : #*#You hit #*# for #*#
		Combat : #*#pierce#*#point#*# of damage#*#
		Combat : #*#backstabs #*#
		Combat : #*# but miss#*#
		Combat : #*#slash#*#point#*# of damage#*#
		Combat : #*#trike through#*#
		You try to #1# #2*, but miss!

		Crits : #*#ASSASSINATE#*#
		Crits : #*#Finishing Blow#*#
		Crits : #*#crippling blow#*#
		Crits : #*#xceptional#*#
		Crits : #*#critical hit#*#
		Crits : #*#critical blast#*#
		You deliver a critical blast!
		Mollypolly scores a critical hit! (312)
		You score a critical hit! (312)
		#1# hit #2# for #3# points of non-melee damage.
		You were hit by non-melee for %1 damage.
		#2# was hit by non-melee for #3# points of damage
		#1# scores a Deadly Strike!(#2#)
	]]
	-- Register Events
	loadSettings()
	local MyName = mq.TLO.Me.CleanName()
	local str = string.format("#*#%s scores a critical hit! #*#(#1#)", MyName)
	mq.event("melee_crit", "#*#You score a critical hit! #*#(#1#)", critalCallBack )
	mq.event("melee_crit2", "#*#You deliver a critical blast! #*#(#1#)", critalCallBack )
	mq.event("melee_crit3", str, critalCallBack )
	str = string.format("#*#%s scores a Deadly Strike! #*#(#1#)", MyName)
	mq.event("melee_deadly_strike", str, critalCallBack )
	str = string.format("#*#%s hit #1# for #2# points of non-melee damage#*#", MyName)
	mq.event("melee_non_melee", str , nonMeleeClallBack)
	mq.event("melee_damage_shield", "#*# was hit by non-melee for #2# points of damage#*#", nonMeleeClallBack)
	mq.event("melee_you_hit_non-melee", "#*#You were hit by non-melee for #2# damage#*#", nonMeleeClallBack)
	mq.event("melee_do_damage", "#*#You #1# #2# for #3# points of damage#*#", meleeCallBack )
	mq.event("melee_miss", "#*#You try to #1# #2#, but miss#*#", meleeCallBack )
	mq.event("melee_got_hit", "#2# #1# YOU for #3# points of damage#*#", npcMeleeCallBack )
	mq.event("melee_missed_me", "#2# tries to #1# YOU, but misses#*#", npcMeleeCallBack )
	mq.bind("/mydps", processCommand)
	-- Initialize ImGui
	mq.imgui.init(script, Draw_GUI)
	pHelp()
	if args[1] ~= nil and args[1] == "start" then
		if #args == 2 and args [2] == 'hide' then
			showCombatWindow = false
		end
		started = true
		clickThrough = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		printf("\aw[\at%s\ax] \ayStarted\ax", script)
	end
end

local function Loop()
	-- Main Loop
	while RUNNING do

		-- Make sure we are still in game or exit the script.
		if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end

		if started then
			winFlags = clickThrough and bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration) or bit32.bor(ImGuiWindowFlags.NoDecoration)
		else
			winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
		end

		local currentTime = os.time()
		if currentTime - dpsStartTime >= settings.Options.dpsTimeSpanReportTimer then
			local dur = currentTime - dpsStartTime
			if settings.Options.dpsTimeSpanReport then
				pDPS(dur, 'ALL')
			end
		end

		if mq.TLO.Me.CombatState() ~= 'COMBAT' and enteredCombat then

			if leftCombatTime == 0 then
				leftCombatTime = os.time()
			end

			local endOfCombat = os.time() - leftCombatTime
			if endOfCombat > settings.Options.battleDuration then
				enteredCombat = false
				local battleDuration = os.time() - battleStartTime - endOfCombat
				for k, v in pairs (battlesHistory) do
					if v.sequence == -1 or v.sequence == 9999 then
						table.remove(battlesHistory, k)
					end
				end
				pDPS(battleDuration, "COMBAT")
				battleStartTime = 0
				leftCombatTime = 0
			end
		end
		-- Clean up the table
		parseCurrentBattle(currentTime - battleStartTime)
		cleanTable()
		workingTable = sortTable(damTable, 'combat')
		mq.doevents()
		mq.delay(5)
	end
end
-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
Init()
Loop()