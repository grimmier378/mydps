local mq = require('mq')
local ImGui = require('ImGui')
local script = 'MyDPS'
local configFile = string.format("%s/MyUI/%s/%s/%s.lua", mq.configDir, script, mq.TLO.EverQuest.Server(), mq.TLO.Me.Name())
local RUNNING = true
local damTable, settings = {}, {}
local winFlags = bit32.bor(ImGuiWindowFlags.None,
		ImGuiWindowFlags.NoTitleBar)
local update = os.time()
local clicked = false
local fontScale = 1.5
local clickThrough = false

local defaults = {
	Options = {
		sortNewest = false,
		showType = true,
		showTarget = true,
		showMyMisses = true,
		showMissMe = true,
		showHitMe = true,
		displayTime = 10,
		fontScale = 1.5,
		bgColor = {0, 0, 0, 0.5},
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

local function npcMeleeCallBack(line, dType, target, dmg)
	if not tonumber(dmg) then
		type = 'missedMe'
		dmg = 'MISSED ME'
	else
		type = 'gothit'
		local startType, stopType = string.find(line, "(%w+) YOU")
		target = string.sub(line, 1, startType - 2)
		-- local tmp = string.sub(line,"YOU" -1)
		-- if tmp ~= nil then
		-- 	for k, v in pairs(MeleeColors) do
		-- 		if string.find(line, k) then
		-- 			tmp = k
		-- 			target = string.sub(line, 1, string.find(line, tmp) - 1)
		-- 			break
		-- 		end
		-- 	end
		-- end
	end
	if target == nil then return end
	if not settings.Options.showMissMe and type == 'missedMe' then return end
	if not settings.Options.showHitMe and type == 'gothit' then return end
	table.insert(damTable, {type = type, target = target, damage = dmg, timestamp = os.time()})
	update = os.time()
	if settings.Options.sortNewest then
		table.sort(damTable, function(a, b) return a.timestamp > b.timestamp end)
	else
		table.sort(damTable, function(a, b) return a.timestamp < b.timestamp end)
	end
end

local function meleeCallBack(line, dType, target, dmg)
	if string.find(line, "have been healed") then return end
	local type = dType or "gothit"
	if dmg == nil then
		dmg = 'MISSED'
		type = 'miss'
	end

	if not settings.Options.showMyMisses and type == 'miss' then return end
	if type == 'miss' then target = 'YOU' end
	table.insert(damTable, {type = type, target = target, damage = dmg, timestamp = os.time()})
	update = os.time()
	if settings.Options.sortNewest then
		table.sort(damTable, function(a, b) return a.timestamp > b.timestamp end)
	else
		table.sort(damTable, function(a, b) return a.timestamp < b.timestamp end)
	end
end

local function cleanTable()
	local timeCheck = os.time()
	for i, v in ipairs(damTable) do
		if timeCheck - v.timestamp > settings.Options.displayTime then
			table.remove(damTable, i)
		end
	end
	update = os.time()
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
	ImGui.SetNextWindowSize(400, 200, ImGuiCond.FirstUseEver)
	local bgColor = settings.Options.bgColor
	if clicked then ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(bgColor[1], bgColor[2], bgColor[3], bgColor[4])) end
	local open, show = ImGui.Begin(script.."##"..mq.TLO.Me.Name(), true, winFlags)
	if not open then
		RUNNING = false
	end
	if show then
		ImGui.SetWindowFontScale(fontScale)
		if not clicked then
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
			end

			if ImGui.CollapsingHeader("Options") then
				settings.Options.showType = ImGui.Checkbox("Show Type", settings.Options.showType)
				settings.Options.showTarget = ImGui.Checkbox("Show Target", settings.Options.showTarget)
				settings.Options.sortNewest = ImGui.Checkbox("Sort Newest on top", settings.Options.sortNewest)
				settings.Options.showMyMisses = ImGui.Checkbox("Show My Misses", settings.Options.showMyMisses)
				settings.Options.showMissMe = ImGui.Checkbox("Show Missed Me", settings.Options.showMissMe)
				settings.Options.showHitMe = ImGui.Checkbox("Show Hit Me", settings.Options.showHitMe)
				settings.Options.displayTime = ImGui.SliderInt("Display Time", settings.Options.displayTime, 1, 60)
			end

			fontScale = ImGui.SliderFloat("Font Scale", fontScale, 0.5, 2)
			if ImGui.Button("Start") then
				mq.pickle(configFile, settings)
				clickThrough = true
				clicked = true
				damTable = {}
			end
		else
			if #damTable > 0 then
				for i, v in ipairs(damTable) do
					local color = checkColor(v.type)
					local output = ""

					if settings.Options.showType then
						output = output .. " " .. v.type
					end

					if settings.Options.showTarget then
						output = output .. " " .. v.target
					end

					output = output .. " " .. v.damage

					ImGui.TextColored(ImVec4(color[1],color[2],color[3], color[4]), "%s",output)
				end
			end
			ImGui.PopStyleColor()
		end
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
	printf("\aw[\at%s\ax] \ay/mydps mymisses\ax - Show my misses.", script)
	printf("\aw[\at%s\ax] \ay/mydps missedme\ax - Show NPC missed me.", script)
	printf("\aw[\at%s\ax] \ay/mydps hitme\ax - Show NPC hit me.", script)
	printf("\aw[\at%s\ax] \ay/mydps sort\ax - Sort newest on top.", script)
	printf("\aw[\at%s\ax] \ay/mydps move\ax - Toggle click through, allows moving of window.", script)
	printf("\aw[\at%s\ax] \ay/mydps delay #\ax - Set the display time in seconds.", script)
	printf("\aw[\at%s\ax] \ay/mydps help\ax - Show this help.", script)
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
		clicked = false
		winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
		damTable = {}
	elseif cmd == "clear" then
		damTable = {}
		update = os.time()
		printf("\aw[\at%s\ax] \ayTable Cleared\ax", script)
	elseif cmd == 'start' then
		clicked = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		damTable = {}
		printf("\aw[\at%s\ax] \ayStarted\ax", script)
	elseif cmd == 'showtype' then
		settings.Options.showType = not settings.Options.showType
		printf("\aw[\at%s\ax] \ayShow Type set to %s\ax", script, settings.Options.showType)
	elseif cmd == 'showtarget' then
		settings.Options.showTarget = not settings.Options.showTarget
		printf("\aw[\at%s\ax] \ayShow Target set to %s\ax", script, settings.Options.showTarget)
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
	]]
	-- Register Events
	loadSettings()
	mq.event("melee_do_damage", "#*#You #1# #2# for #3# points of damage#*#", meleeCallBack )
	mq.event("melee_miss", "#*#You try to #1# #2#, but miss#*#", meleeCallBack )
	mq.event("melee_got_hit", "#2# #1# YOU for #3# points of damage.", npcMeleeCallBack )
	mq.event("melee_missed_me", "#2# tries to #1# YOU, but misses!", npcMeleeCallBack )
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
		if clicked then
			winFlags = clickThrough and bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration) or bit32.bor(ImGuiWindowFlags.NoDecoration)
		else
			winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoTitleBar)
		end
		-- Clean up the table
		cleanTable()
		mq.delay(10)
	end
end
-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
Init()
Loop()