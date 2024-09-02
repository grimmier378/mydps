local mq = require('mq')
local ImGui = require('ImGui')
local script = 'MyDPS'
local configFile = string.format("%s/MyUI/%s/%s/%s.lua", mq.configDir, script, mq.TLO.EverQuest.Server(), mq.TLO.Me.Name())
local RUNNING = true
local damTable, settings = {}, {}
local winFlags = bit32.bor(ImGuiWindowFlags.None,
		ImGuiWindowFlags.NoTitleBar)
local started = false
local fontScale = 1.5
local clickThrough = false
local tableSize = 0
local sequenceCounter = 0
local dpsStartTime = os.time()
local previewBG = false
local dmgTotal, dmgCounter, dsCounter, dmgTotalDS = 0, 0, 0, 0

local defaults = {
	Options = {
		sortNewest = false,
		showType = true,
		showTarget = true,
		showMyMisses = true,
		showMissMe = true,
		showHitMe = true,
		showDS = true,
		displayTime = 10,
		fontScale = 1.5,
		bgColor = {0, 0, 0, 0.5},
		dpsReportTimer = 60,
		dpsReport = true,
	},
	MeleeColors = {
		["crush"] = { 1, 0, 0, 1},
		["kick"] = {0,  1,0,1},
		["bite"] = { 0, 0,1, 1},
		["bash"] = {1,1,0,1},
		["hit"] = {1,0,1, 1},
		["pierce"] = {0,1,1, 1},
		["backstabs"] = {1,1,1,1},
		["slash"] = { 0.8, 0.8, 0, 1 },
		["miss"] = { 1, 1, 1, 1},
		["missedMe"] = {1,0,1,1},
		["non-melee"] = {1,1,1,1},
		["gothit"] = {1,0,0,1},
		["crit"] = {1,1,0,1},
		["YOU-non-melee"] = {1,1,0,1},
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

	if newSetting then mq.pickle(configFile, settings) end
end

local function sortTable(tbl)
	if #tbl == 0 then return end
	table.sort(tbl, function(a, b)
		if settings.Options.sortNewest then
			return (a.sequence > b.sequence)
		else
			return (a.sequence < b.sequence)
		end
	end)
	return tbl
end

local function npcMeleeCallBack(line, dType, target, dmg)
	if not tonumber(dmg) then
		type = 'missedMe'
		dmg = 'MISSED'
	else
		type = 'gothit'
		local startType, stopType = string.find(line, "(%w+) YOU")
		target = string.sub(line, 1, startType - 2)
	end
	if target == nil then return end
	if not settings.Options.showMissMe and type == 'missedMe' then return end
	if not settings.Options.showHitMe and type == 'gothit' then return end
	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
end

local function nonMeleeClallBack(line, target, dmg)
	if not tonumber(dmg) then return end
	local type = "non-melee"
	if target == nil then target = 'YOU' type = "YOU-non-melee" end

	if string.find(line, "was hit") then
		target = string.sub(line, 1, string.find(line, "was") - 2)
		type = "dShield"
	end

	if type ~= 'dShield' then
		dmgTotal = dmgTotal + (tonumber(dmg) or 0)
		dmgCounter = dmgCounter + 1
	else
		dmgTotalDS = dmgTotalDS + (tonumber(dmg) or 0)
		dsCounter = dsCounter + 1
	end

	if not settings.Options.showDS and type == 'dShield' then return end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
end

local function meleeCallBack(line, dType, target, dmg)
	if string.find(line, "have been healed") then return end
	local type = dType or nil
	if type == nil then return end
	if dmg == nil then
		dmg = 'MISSED'
		type = 'miss'
	end

	dmgTotal = dmgTotal + (tonumber(dmg) or 0)
	dmgCounter = dmgCounter + 1

	if not settings.Options.showMyMisses and type == 'miss' then return end

	if type == 'miss' then target = 'YOU' end
	if damTable == nil then damTable = {} end
	
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = type, target = target, damage = dmg,
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
end

local function critalCallBack(line, dmg)
	if not tonumber(dmg) then return end

	dmgTotal = dmgTotal + (tonumber(dmg) or 0)
	dmgCounter = dmgCounter + 1

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {type = "crit", target = mq.TLO.Target.CleanName(), damage = string.format("CRIT <%d>",dmg),
		timestamp = os.time(), sequence = sequenceCounter
	})
	tableSize = tableSize + 1
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

local workingTable = {}

local function Draw_GUI()
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
				ImGui.Text("This will show the last %d seconds of YOUR melee attacks.", settings.Options.displayTime)
				ImGui.Text("The window is click through after you start.")
				ImGui.Text("/mydps help for a list of commands.")
				ImGui.Text("Click button to enable. /lua stop %s to close.", script)

			if ImGui.CollapsingHeader("Color Key") then
				if ImGui.BeginTable("Color Key", 2, ImGuiTableFlags.Borders) then
					for type, color in pairs(settings.MeleeColors) do
						ImGui.TableNextColumn()
						settings.MeleeColors[type] = ImGui.ColorEdit4(type, color, bit32.bor(ImGuiColorEditFlags.NoInputs, ImGuiColorEditFlags.AlphaBar))
					end
					ImGui.EndTable()
				end
				ImGui.SeparatorText("Window Background Color")
				settings.Options.bgColor = ImGui.ColorEdit4("Background Color", settings.Options.bgColor, bit32.bor(ImGuiColorEditFlags.NoInputs, ImGuiColorEditFlags.AlphaBar))
				ImGui.SameLine()
				if ImGui.Button("Preview") then
					previewBG = not previewBG
				end
			end

			if ImGui.CollapsingHeader("Options") then
				settings.Options.showType = ImGui.Checkbox("Show Type", settings.Options.showType)
				settings.Options.showTarget = ImGui.Checkbox("Show Target", settings.Options.showTarget)
				settings.Options.sortNewest = ImGui.Checkbox("Sort Newest on top", settings.Options.sortNewest)
				settings.Options.showMyMisses = ImGui.Checkbox("Show My Misses", settings.Options.showMyMisses)
				settings.Options.showMissMe = ImGui.Checkbox("Show Missed Me", settings.Options.showMissMe)
				settings.Options.showHitMe = ImGui.Checkbox("Show Hit Me", settings.Options.showHitMe)
				settings.Options.showDS = ImGui.Checkbox("Show Damage Shield", settings.Options.showDS)
				settings.Options.dpsReport = ImGui.Checkbox("Show DPS Report", settings.Options.dpsReport)
				local tmpTimer = settings.Options.dpsReportTimer / 60

				ImGui.SetNextItemWidth(100)
				tmpTimer = ImGui.SliderFloat("DPS Report Timer (minutes)", tmpTimer, 0.5, 60, "%.2f")
				if tmpTimer ~= settings.Options.dpsReportTimer then
					settings.Options.dpsReportTimer = tmpTimer * 60
				end
			end

			ImGui.SetNextItemWidth(100)
			settings.Options.displayTime = ImGui.SliderInt("Display Time", settings.Options.displayTime, 1, 60)

			ImGui.SetNextItemWidth(100)
			fontScale = ImGui.SliderFloat("Font Scale", fontScale, 0.5, 2, "%.2f")
			if ImGui.Button("Start") then
				settings.Options.fontScale = fontScale
				mq.pickle(configFile, settings)
				clickThrough = true
				started = true
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

local function pHelp()
	printf("\aw[\at%s\ax] \ayCommands\ax", script)
	printf("\aw[\at%s\ax] \ay/mydps start\ax - Start the DPS window.", script)
	printf("\aw[\at%s\ax] \ay/mydps exit\ax - Exit the script.", script)
	printf("\aw[\at%s\ax] \ay/mydps ui\ax - Show the UI.", script)
	printf("\aw[\at%s\ax] \ay/mydps clear\ax - Clear the table.", script)
	printf("\aw[\at%s\ax] \ay/mydps showtype\ax - Show the type of attack.", script)
	printf("\aw[\at%s\ax] \ay/mydps showtarget\ax - Show the target of the attack.", script)
	printf("\aw[\at%s\ax] \ay/mydps showds\ax - Show damage shield.", script)
	printf("\aw[\at%s\ax] \ay/mydps mymisses\ax - Show my misses.", script)
	printf("\aw[\at%s\ax] \ay/mydps missedme\ax - Show NPC missed me.", script)
	printf("\aw[\at%s\ax] \ay/mydps hitme\ax - Show NPC hit me.", script)
	printf("\aw[\at%s\ax] \ay/mydps sort\ax - Sort newest on top.", script)
	printf("\aw[\at%s\ax] \ay/mydps settings\ax - Show current settings.", script)
	printf("\aw[\at%s\ax] \ay/mydps dodps\ax - Toggle DPS Auto Reporting.", script)
	printf("\aw[\at%s\ax] \ay/mydps report\ax - Report the current DPS since Last Report.", script)
	printf("\aw[\at%s\ax] \ay/mydps move\ax - Toggle click through, allows moving of window.", script)
	printf("\aw[\at%s\ax] \ay/mydps delay #\ax - Set the display time in seconds.", script)
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

local function pDPS(dur)
	local dps = dur > 0 and (dmgTotal / dur) or 0
	local dpsDS = dur > 0 and (dmgTotalDS / dur) or 0
	local avgDmg = dmgCounter > 0 and (dmgTotal / dmgCounter) or 0
	local grandTotal = dmgTotal + dmgTotalDS
	local grandCounter = dmgCounter + dsCounter
	local grangAvg = grandCounter > 0 and (grandTotal / grandCounter) or 0
	local grandDPS = dur > 0 and (grandTotal / dur) or 0
	printf("\aw[\at%s\ax] \ayDPS \ax(\aoNO DS\ax): \at%.2f\ax, \ayTimeSpan:\ax\ao %.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage: \ax\ao%d\ax",
			script, dps, (dur/60), dmgTotal, dmgCounter,avgDmg )
	printf("\aw[\at%s\ax] \ayDPS \ax(\atDS Dmg\ax): \at%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Hits: \ax\ao%d\ax",
		script, dpsDS, (dur/60), dmgTotalDS, dsCounter)
	printf("\aw[\at%s\ax] \ayDPS \ax(\agALL\ax): \ag%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage:\ax \ao%d\ax",
		script, grandDPS, (dur/60), grandTotal, grandCounter, grangAvg)
	dmgTotal = 0
	dmgCounter = 0
	dmgTotalDS = 0
	dsCounter = 0
	dpsStartTime = os.time()
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
		winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
	elseif cmd == "clear" then
		damTable = {}
		tableSize = 0
		dmgTotal, dmgCounter, dsCounter, dmgTotalDS = 0, 0, 0, 0
		printf("\aw[\at%s\ax] \ayTable Cleared\ax", script)
	elseif cmd == 'start' then
		started = true
		clickThrough = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		printf("\aw[\at%s\ax] \ayStarted\ax", script)
	elseif cmd == 'showtype' then
		settings.Options.showType = not settings.Options.showType
		printf("\aw[\at%s\ax] \ayShow Type set to %s\ax", script, settings.Options.showType)
	elseif cmd == 'showtarget' then
		settings.Options.showTarget = not settings.Options.showTarget
		printf("\aw[\at%s\ax] \ayShow Target set to %s\ax", script, settings.Options.showTarget)
	elseif cmd == 'showds' then
		settings.Options.showDS = not settings.Options.showDS
		printf("\aw[\at%s\ax] \ayShow Damage Shield set to %s\ax", script, settings.Options.showDS)
	elseif cmd == 'mymisses' then
		settings.Options.showMyMisses = not settings.Options.showMyMisses
		printf("\aw[\at%s\ax] \ayShow My Misses set to %s\ax", script, settings.Options.showMyMisses)
	elseif cmd == 'missedme' then
		settings.Options.showMissMe = not settings.Options.showMissMe
		printf("\aw[\at%s\ax] \ayShow Missed Me set to %s\ax", script, settings.Options.showMissMe)
	elseif cmd == 'hitme' then
		settings.Options.showHitMe = not settings.Options.showHitMe
		printf("\aw[\at%s\ax] \ayShow Hit Me set to %s\ax", script, settings.Options.showHitMe)
	elseif cmd == 'sort' then
		settings.Options.sortNewest = not settings.Options.sortNewest
		printf("\aw[\at%s\ax] \aySort Newest set to %s\ax", script, settings.Options.sortNewest)
	elseif cmd == 'move' then
		clickThrough = not clickThrough
		printf("\aw[\at%s\ax] \ayClick Through set to %s\ax", script, clickThrough)
	elseif cmd == 'settings' then
		pCurrentSettings()
	elseif cmd == 'dodps' then
		settings.Options.dpsReport = not settings.Options.dpsReport
		printf("\aw[\at%s\ax] \ayDo DPS Reporting set to %s\ax", script, settings.Options.dpsReport)
	elseif cmd == 'report' then
		pDPS(os.time() - dpsStartTime)
	elseif #args == 2 and cmd == "delay" then
		if tonumber(args[2]) then
			settings.Options.displayTime = tonumber(args[2])
			printf("\aw[\at%s\ax] \ayDisplay time set to %s\ax", script, settings.Options.displayTime)
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
	]]
	-- Register Events
	loadSettings()
	local MyName = mq.TLO.Me.CleanName()
	local str = string.format("#*#%s scores a critical hit! #*#(#1#)", MyName)
	mq.event("melee_crit", "#*#You score a critical hit! #*#(#1#)", critalCallBack )
	mq.event("melee_crit2", "#*#You deliver a critical blast! #*#(#1#)", critalCallBack )
	mq.event("melee_crit3", str, critalCallBack )
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

end

local function Loop()
	-- Main Loop
	while RUNNING do

		-- Make sure we are still in game or exit the script.
		if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
		mq.doevents()

		if started then
			winFlags = clickThrough and bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration) or bit32.bor(ImGuiWindowFlags.NoDecoration)
		else
			winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
		end

		local currentTime = os.time()
		if currentTime - dpsStartTime >= settings.Options.dpsReportTimer then
			if settings.Options.dpsReport then pDPS(currentTime - dpsStartTime) end
		end

		-- Clean up the table
		cleanTable()
		workingTable = sortTable(damTable)
		mq.delay(5)
	end
end
-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
Init()
Loop()