local mq = require('mq')
local ImGui = require('ImGui')
local actors = require('actors')
local ActorDPS
local script = 'MyDPS'
local configFile = string.format("%s/MyUI/%s/%s/%s.lua", mq.configDir, script, mq.TLO.EverQuest.Server(), mq.TLO.Me.Name())
local RUNNING = true
local damTable, settings = {}, {}
local MyName = mq.TLO.Me.CleanName()
local winFlags = bit32.bor(ImGuiWindowFlags.None,
	ImGuiWindowFlags.NoTitleBar)
local started, doActors = false, false
local fontScale = 1.0
local clickThrough = false
local tableSize = 0
local sequenceCounter, battleCounter = 0, 0
local dpsStartTime = os.time()
local previewBG, showBattleHistory = false, true
local dmgTotal, dmgCounter, dsCounter, dmgTotalDS, dmgTotalBattle, dmgBattCounter, critHealsTotal, critTotalBattle = 0, 0, 0, 0, 0, 0, 0, 0
local workingTable, battlesHistory, actorsTable, actorsWorking = {}, {}, {}, {}
local enteredCombat = false
local showCombatWindow, sortParty = false, false
local battleStartTime, leftCombatTime = 0, 0
local firstRun = true
local defaults = {
	Options = {
		sortNewest             = false,
		showType               = true,
		showTarget             = true,
		showMyMisses           = true,
		showMissMe             = true,
		showHitMe              = true,
		showCritHeals          = true,
		showDS                 = true,
		showHistory            = true,
		displayTime            = 10,
		fontScale              = 1.0,
		bgColor                = { 0, 0, 0, 0.5, },
		dpsTimeSpanReportTimer = 60,
		dpsTimeSpanReport      = true,
		dpsBattleReport        = true,
		announceDNET           = false,
		battleDuration         = 10,
		sortHistory            = false,
		announceActors         = false,
		sortParty              = false,
		showCombatWindow       = true,
	},
	MeleeColors = {
		["crush"] = { 1, 1, 1, 1, },
		["kick"] = { 1, 1, 1, 1, },
		["bite"] = { 1, 1, 1, 1, },
		["bash"] = { 1, 1, 1, 1, },
		["hit"] = { 1, 1, 1, 1, },
		["pierce"] = { 1, 1, 1, 1, },
		["backstab"] = { 1, 0, 0, 1, },
		["slash"] = { 1, 1, 1, 1, },
		["miss"] = { 0.5, 0.5, 0.5, 1, },
		["missed-me"] = { 0.5, 0.5, 0.5, 1, },
		["non-melee"] = { 0, 1, 1, 1, },
		["hit-by"] = { 1, 0, 0, 1, },
		["crit"] = { 1, 1, 0, 1, },
		["hit-by-non-melee"] = { 1, 1, 0, 1, },
		["gothit-non-melee"] = { 1, 1, 0, 1, },
		["dShield"] = { 0, 1, 0, 1, },
		['critHeals'] = { 0, 1, 1, 1, },
	},
}


local function printOutput(msg)
	local useMyChat = mq.TLO.MyChatTlo ~= nil and true or false
	if not useMyChat then
		printf(msg)
	else
		mq.TLO.MyChatTlo(script, msg)
	end
end

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
	doActors          = settings.Options.announceActors ~= nil and settings.Options.announceActors or false
	sortParty         = settings.Options.sortParty ~= nil and settings.Options.sortParty or false
	fontScale         = settings.Options.fontScale ~= nil and settings.Options.fontScale or 1.0
	showBattleHistory = settings.Options.showHistory ~= nil and settings.Options.showHistory or false
	showCombatWindow  = settings.Options.showCombatWindow ~= nil and settings.Options.showCombatWindow or false
	if newSetting then mq.pickle(configFile, settings) end
end

---comment
---@param tbl table @ table to sort
---@param sortType string @ type of sort (combat, history, dps)
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
		elseif sortType == 'party' then
			if a.sequence == b.sequence then
				if a.dps == b.dps then
					return a.name < b.name
				else
					return a.dps > b.dps
				end
			else
				return a.sequence > b.sequence
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
		for k, v in pairs(battlesHistory) do
			if v.sequence == -1 or v.sequence == 999999 then
				v.sequence  = settings.Options.sortHistory and 999999 or -1
				v.dps       = dps
				v.dur       = dur
				v.dmg       = dmgTotalBattle
				v.crit      = critTotalBattle
				v.critHeals = critHealsTotal
				v.avg       = avgDmg
				exists      = true
				break
			end
		end
		if not exists then
			table.insert(battlesHistory,
				{
					sequence = (settings.Options.sortHistory and 999999 or -1),
					dps = dps,
					dur = dur,
					dmg = dmgTotalBattle,
					avg = avgDmg,
					crit = critTotalBattle,
					critHeals = critHealsTotal,
				})
		end
		battlesHistory = sortTable(battlesHistory, 'history')
		if settings.Options.announceActors then
			ActorDPS:send({ mailbox = 'my_dps', }, ({ Name = MyName, Subject = 'CURRENT', BattleNum = -2, DPS = dps,
				TimeSpan = dur, TotalDmg = dmgTotalBattle, AvgDmg = avgDmg, Remove = false, Crit = critTotalBattle, CritHeals = critHealsTotal, }))
			local found = false
			for k, v in pairs(actorsTable) do
				if v.name == MyName then
					v.name      = MyName
					v.sequence  = -2
					v.dps       = dps
					v.dur       = dur
					v.dmg       = dmgTotalBattle
					v.crit      = critTotalBattle
					v.critHeals = critHealsTotal
					v.avg       = avgDmg
					found       = true
					break
				end
			end
			if not found then
				table.insert(actorsTable, {
					name      = MyName,
					sequence  = -2,
					dps       = dps,
					dur       = dur,
					dmg       = dmgTotalBattle,
					crit      = critTotalBattle,
					critHeals = critHealsTotal,
					avg       = avgDmg,
				})
			end
		end
	end
end

local function npcMeleeCallBack(line, dType, target, dmg)
	if not tonumber(dmg) then
		type = 'missed-me'
		dmg  = 'MISSED'
	else
		type = 'hit-by'
		local startType, stopType = string.find(line, "(%w+) YOU")
		target = string.sub(line, 1, startType - 2)
	end
	if target == nil then return end
	if not enteredCombat then
		enteredCombat   = true
		dmgBattCounter  = 0
		dmgTotalBattle  = 0
		critTotalBattle = 0
		critHealsTotal  = 0
		battleStartTime = os.time()
		leftCombatTime  = 0
	end
	parseCurrentBattle(os.time() - battleStartTime)
	if not settings.Options.showMissMe and type == 'missed-me' then return end
	if not settings.Options.showHitMe and type == 'hit-by' then return end
	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {
		type      = type,
		target    = target,
		damage    = dmg,
		timestamp = os.time(),
		sequence  = sequenceCounter,
	})
	tableSize = tableSize + 1
end

local function nonMeleeClallBack(line, target, dmg)
	if not tonumber(dmg) then return end
	if not enteredCombat then
		enteredCombat   = true
		dmgBattCounter  = 0
		critHealsTotal  = 0
		critTotalBattle = 0
		dmgTotalBattle  = 0
		battleStartTime = os.time()
		leftCombatTime  = 0
	end
	local type = "non-melee"
	if target == nil then
		target = 'YOU'
		type   = "hit-by-non-melee"
	end

	if string.find(line, "was hit") then
		target = string.sub(line, 1, string.find(line, "was") - 2)
		type   = "dShield"
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

	if not settings.Options.showDS and type == 'dShield' then
		parseCurrentBattle(os.time() - battleStartTime)
		return
	end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {
		type      = type,
		target    = target,
		damage    = dmg,
		timestamp = os.time(),
		sequence  = sequenceCounter,
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function meleeCallBack(line, dType, target, dmg)
	if string.find(line, "have been healed") then return end
	local type = dType or nil
	if type == nil then return end
	if not enteredCombat then
		enteredCombat   = true
		dmgBattCounter  = 0
		dmgTotalBattle  = 0
		critTotalBattle = 0
		critHealsTotal  = 0
		battleStartTime = os.time()
		leftCombatTime  = 0
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

	if not settings.Options.showMyMisses and type == 'miss' then
		parseCurrentBattle(os.time() - battleStartTime)
		return
	end

	if type == 'miss' then target = 'YOU' end
	if damTable == nil then damTable = {} end

	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {
		type      = type,
		target    = target,
		damage    = dmg,
		timestamp = os.time(),
		sequence  = sequenceCounter,
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function critCallBack(line, dmg)
	if not tonumber(dmg) then return end
	if not enteredCombat then
		enteredCombat   = true
		dmgBattCounter  = 0
		dmgTotalBattle  = 0
		critTotalBattle = 0
		critHealsTotal  = 0
		battleStartTime = os.time()
		leftCombatTime  = 0
	end

	if enteredCombat then
		critTotalBattle = critTotalBattle + (tonumber(dmg) or 0)
	end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {
		type      = "crit",
		target    = mq.TLO.Target.CleanName(),
		damage    = string.format("CRIT <%d>", dmg),
		timestamp = os.time(),
		sequence  = sequenceCounter,
	})
	tableSize = tableSize + 1
	parseCurrentBattle(os.time() - battleStartTime)
end

local function critHealCallBack(line, dmg)
	if not tonumber(dmg) then return end
	if not enteredCombat then
		enteredCombat   = true
		battleStartTime = os.time()
		leftCombatTime  = 0
	end

	if enteredCombat then
		critHealsTotal = critHealsTotal + (tonumber(dmg) or 0)
	end

	if damTable == nil then damTable = {} end
	sequenceCounter = sequenceCounter + 1
	table.insert(damTable, {
		type      = "critHeals",
		target    = "You",
		damage    = string.format("CRIT_HEAL <%d>", dmg),
		timestamp = os.time(),
		sequence  = sequenceCounter,
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
---@param num number @ Number to clean
---@param percision number|nil @ default 0 - Number of decimal places
---@param percAlways boolean|nil @ default false - Always show decimal places
---@return string
local function cleanNumber(num, percision, percAlways)
	if num == nil then return "0" end
	if percision == nil then percision = 0 end
	if percAlways == nil then percAlways = false end
	local label = ""
	local floatNum = 0
	if num >= 1000000000 then
		floatNum = num / 1000000
		if percision == 2 then
			label = string.format("%.2f b", floatNum)
		elseif percision == 1 then
			label = string.format("%.1f b", floatNum)
		elseif percision == 0 then
			label = string.format("%.0f b", floatNum)
		end
	elseif num >= 1000000 then
		floatNum = num / 1000000
		if percision == 2 then
			label = string.format("%.2f m", floatNum)
		elseif percision == 1 then
			label = string.format("%.1f m", floatNum)
		elseif percision == 0 then
			label = string.format("%.0f m", floatNum)
		end
	elseif num >= 1000 then
		floatNum = num / 1000
		if percision == 2 then
			label = string.format("%.2f k", floatNum)
		elseif percision == 1 then
			label = string.format("%.1f k", floatNum)
		else
			label = string.format("%.0f k", floatNum)
		end
	else
		if not percAlways then
			label = string.format("%.0f", num)
		else
			if percision == 2 then
				label = string.format("%.2f", num)
			elseif percision == 1 then
				label = string.format("%.1f", num)
			else
				label = string.format("%.0f", num)
			end
		end
	end
	return label
end

---comment
---@param t any
---@return table
local function checkColor(t)
	if settings.MeleeColors[t] then
		return settings.MeleeColors[t]
	else
		return { 1, 1, 1, 1, }
	end
end

local color = {
	red    = ImVec4(1, 0, 0, 1),
	green  = ImVec4(0, 1, 0, 1),
	blue   = ImVec4(0, 0, 1, 1),
	yellow = ImVec4(1, 1, 0, 1),
	orange = ImVec4(1.0, 0.5, 0, 1),
	teal   = ImVec4(0, 1, 1, 1),
	white  = ImVec4(1, 1, 1, 1),
}

local function DrawHistory(tbl)
	if settings.Options.showHistory ~= showBattleHistory then
		settings.Options.showHistory = showBattleHistory
		mq.pickle(configFile, settings)
	end
	ImGui.SetWindowFontScale(fontScale)
	if #tbl > 0 then
		if ImGui.BeginTable("Battles", 8, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable,
				ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable, ImGuiTableFlags.ScrollY)) then
			ImGui.TableSetupScrollFreeze(0, 1)
			ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Battle", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("DPS", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Dur", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Avg.", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Crit Dmg", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Crit Heals", ImGuiTableColumnFlags.None)
			ImGui.TableSetupColumn("Total", ImGuiTableColumnFlags.None)
			ImGui.TableSetupScrollFreeze(0, 1)
			ImGui.TableHeadersRow()

			for index, data in ipairs(tbl) do
				local seq = ((data.sequence == -1 or data.sequence == 999999 or data.sequence == -2) and
					"Current" or (data.sequence == -3 and "Last") or data.sequence)

				local textColor = color.white
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				textColor = data.name == MyName and color.teal or color.white
				ImGui.TextColored(textColor, "%s", data.name ~= nil and data.name or MyName)
				ImGui.TableNextColumn()
				textColor = seq == "Current" and color.yellow or color.orange
				ImGui.TextColored(textColor, "%s", seq)
				ImGui.TableNextColumn()
				ImGui.Text(cleanNumber(data.dps, 1, true))
				ImGui.TableNextColumn()
				ImGui.Text("%.0f", data.dur)
				ImGui.TableNextColumn()
				ImGui.Text(cleanNumber(data.avg, 1, true))
				ImGui.TableNextColumn()
				ImGui.Text(cleanNumber(data.crit, 2))
				ImGui.TableNextColumn()
				ImGui.Text(cleanNumber(data.critHeals, 1))
				ImGui.TableNextColumn()
				ImGui.Text(cleanNumber(data.dmg, 2))
			end
			ImGui.EndTable()
		end
	end
end

local function DrawButtons()
	local btnLabel = started and "Stop" or "Start"
	if ImGui.Button(btnLabel) then
		if started then
			started = false
			clickThrough = false
		else
			clickThrough = true
			started = true
		end
		settings.Options.fontScale = fontScale
		mq.pickle(configFile, settings)
	end
	if ImGui.IsItemHovered() then
		ImGui.SetTooltip("%s the DPS Window.", btnLabel)
	end
	ImGui.SameLine()
	local btnLabel2 = showCombatWindow and "Hide" or "Show"
	if ImGui.Button(btnLabel2) then
		mq.pickle(configFile, settings)
		showCombatWindow = not showCombatWindow
	end
	if ImGui.IsItemHovered() then
		ImGui.SetTooltip("%s the DPS Window.", btnLabel2)
	end
end

local function DrawColorOptions()
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
end

local function DrawOptions()
	DrawColorOptions()

	if ImGui.CollapsingHeader("Options") then
		local col = ((ImGui.GetWindowContentRegionWidth() - 20) / 300) > 1 and ((ImGui.GetWindowContentRegionWidth() - 20) / 300) or 1
		if ImGui.BeginTable("Options", col, ImGuiTableFlags.Borders) then
			ImGui.TableNextColumn()

			showBattleHistory = ImGui.Checkbox("Show Battle History", showBattleHistory)
			if showBattleHistory ~= settings.Options.showHistory then
				settings.Options.showHistory = showBattleHistory
				mq.pickle(configFile, settings)
			end
			ImGui.SameLine()
			ImGui.HelpMarker("Show the Battle History Window.")
			ImGui.TableNextColumn()
			showCombatWindow = ImGui.Checkbox("Show Combat Spam History", showCombatWindow)
			if showCombatWindow ~= settings.Options.showCombatWindow then
				settings.Options.showCombatWindow = showCombatWindow
				mq.pickle(configFile, settings)
			end
			ImGui.SameLine()
			ImGui.HelpMarker("Show the Combat Spam Window.")
			ImGui.TableNextColumn()
			settings.Options.showType = ImGui.Checkbox("Show Type", settings.Options.showType)
			ImGui.SameLine()
			ImGui.HelpMarker("Show the type of attack.")
			ImGui.TableNextColumn()
			settings.Options.showTarget = ImGui.Checkbox("Show Target", settings.Options.showTarget)
			ImGui.SameLine()
			ImGui.HelpMarker("Show the target of the attack. or YOU MISS")
			ImGui.TableNextColumn()
			settings.Options.sortNewest = ImGui.Checkbox("Sort Newest Combat Spam on top", settings.Options.sortNewest)
			ImGui.SameLine()
			ImGui.HelpMarker("Sort Combat Spam the newest on top.")
			ImGui.TableNextColumn()
			settings.Options.sortHistory = ImGui.Checkbox("Sort Newest History on top", settings.Options.sortHistory)
			ImGui.SameLine()
			ImGui.HelpMarker("Sort Battle History Table the newest on top.")
			ImGui.TableNextColumn()
			sortParty = ImGui.Checkbox("Sort Party DPS on top", sortParty)
			ImGui.SameLine()
			ImGui.HelpMarker("Sort Party DPS the highest on top. Refrehses at about 30fps so you can read it otherwise its jumps around to fast")
			ImGui.TableNextColumn()
			if sortParty ~= settings.Options.sortParty then
				settings.Options.sortParty = sortParty
				mq.pickle(configFile, settings)
			end
			settings.Options.showMyMisses = ImGui.Checkbox("Show My Misses", settings.Options.showMyMisses)
			ImGui.SameLine()
			ImGui.HelpMarker("Show your misses.")
			ImGui.TableNextColumn()
			settings.Options.showMissMe = ImGui.Checkbox("Show Missed Me", settings.Options.showMissMe)
			ImGui.SameLine()
			ImGui.HelpMarker("Show NPC missed you.")
			ImGui.TableNextColumn()
			settings.Options.showHitMe = ImGui.Checkbox("Show Hit Me", settings.Options.showHitMe)
			ImGui.SameLine()
			ImGui.HelpMarker("Show NPC hit you.")
			ImGui.TableNextColumn()
			settings.Options.showCritHeals = ImGui.Checkbox("Show Crit Heals", settings.Options.showCritHeals)
			ImGui.SameLine()
			ImGui.HelpMarker("Show Critical Heals.")
			ImGui.TableNextColumn()
			settings.Options.showDS = ImGui.Checkbox("Show Damage Shield", settings.Options.showDS)
			ImGui.SameLine()
			ImGui.HelpMarker("Show Damage Shield Spam Damage.")
			ImGui.TableNextColumn()
			settings.Options.dpsTimeSpanReport = ImGui.Checkbox("Do DPS over Time Reporting", settings.Options.dpsTimeSpanReport)
			ImGui.SameLine()
			ImGui.HelpMarker("Report DPS over a set time span.")
			ImGui.TableNextColumn()
			settings.Options.dpsBattleReport = ImGui.Checkbox("Do DPS Battle Reporting", settings.Options.dpsBattleReport)
			ImGui.SameLine()
			ImGui.HelpMarker("Report DPS For last Battle.")
			ImGui.TableNextColumn()
			settings.Options.announceDNET = ImGui.Checkbox("Announce to DanNet Group", settings.Options.announceDNET)
			ImGui.SameLine()
			ImGui.HelpMarker("Announce DPS Reports to DanNet Group.")
			ImGui.TableNextColumn()
			settings.Options.announceActors = ImGui.Checkbox("Announce to Actors", settings.Options.announceActors)
			ImGui.SameLine()
			ImGui.HelpMarker("Announce DPS Battle Reports to Actors.")
			ImGui.EndTable()
		end
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
		ImGui.HelpMarker(
			"Set the time in seconds to make sure we dont enter combat again.\n This will allow Battle Reports to handle toons that have long delay's between engaging the next mob.")
	end

	ImGui.SetNextItemWidth(120)
	settings.Options.displayTime = ImGui.SliderInt("Display Time", settings.Options.displayTime, 1, 60)
	ImGui.SameLine()
	ImGui.HelpMarker("Set the time in seconds to display the damage.")

	ImGui.SetNextItemWidth(120)
	fontScale = ImGui.SliderFloat("Font Scale", fontScale, 0.5, 2, "%.2f")
	ImGui.SameLine()
	ImGui.HelpMarker("Set the font scale for the window.")

	DrawButtons()
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
		local isWindowOpen, showWin = ImGui.Begin(script .. "##" .. mq.TLO.Me.Name(), true, winFlags)
		if not isWindowOpen then
			RUNNING = false
		end
		if showWin then
			ImGui.SetWindowFontScale(fontScale)
			if not started then
				ImGui.PushTextWrapPos((ImGui.GetWindowContentRegionWidth() - 20) or 20)
				ImGui.Text("This will show the last %d seconds of YOUR melee attacks.", settings.Options.displayTime)
				ImGui.TextColored(color.orange, "WARNING The window is click through after you start.")
				ImGui.Text("You can Toggle Moving the window with /mydps move.")
				ImGui.Text("You can Toggle the This Screen with /mydps ui. Which will allow you to resize the window again")
				ImGui.Text("run /mydps help for a list of commands.")
				ImGui.Text("Click Start to enable.")
				ImGui.PopTextWrapPos()
				ImGui.Separator()
				DrawColorOptions()
				DrawButtons()
			else
				ImGui.PushTextWrapPos((ImGui.GetWindowContentRegionWidth() - 2) or 20)
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
							ImGui.TextColored(ImVec4(color[1], color[2], color[3], color[4]), "%s", output)
						end
					end
				end
				ImGui.PopTextWrapPos()
			end
			ImGui.PopStyleColor()
			ImGui.SetWindowFontScale(1)
		end
		ImGui.End()
	end

	if showBattleHistory then
		ImGui.SetNextWindowSize(400, 200, ImGuiCond.FirstUseEver)
		local openReport, showReport = ImGui.Begin("DPS Report##" .. mq.TLO.Me.Name(), true, ImGuiWindowFlags.None)
		if not openReport then
			showBattleHistory = false
			settings.Options.showHistory = false
			mq.pickle(configFile, settings)
			printOutput(string.format("\aw[\at%s\ax] \ayShow Battle History set to %s\ax", script, showBattleHistory))
		end
		if showReport then
			if ImGui.BeginTabBar("MyDPS##") then
				if ImGui.BeginTabItem("My History") then
					DrawHistory(battlesHistory)
					ImGui.EndTabItem()
				end
				if settings.Options.announceActors and ImGui.BeginTabItem("Party") then
					DrawHistory(actorsWorking)
					ImGui.EndTabItem()
				end
				if ImGui.BeginTabItem("Config") then
					DrawOptions()
				end
				ImGui.EndTabBar()
			end
		end
		ImGui.End()
	end
end

local function pHelp()
	local help = {
		[1] = string.format("\aw[\at%s\ax] \ayCommands\ax", script)
		,
		[2] = string.format("\aw[\at%s\ax] \ay/lua run mydps\ax - Run the script.", script)
		,
		[3] = string.format("\aw[\at%s\ax] \ay/lua run mydps start\ax - Run and Start, bypassing the Options Display.", script)
		,
		[4] = string.format("\aw[\at%s\ax] \ay/lua run mydps start hide\ax - Run and Start, bypassing the Options Display and Hides the Spam Window.", script)
		,
		[5] = string.format("\aw[\at%s\ax] \ay/mydps start\ax - Start the DPS window.", script)
		,
		[6] = string.format("\aw[\at%s\ax] \ay/mydps exit\ax - Exit the script.", script)
		,
		[7] = string.format("\aw[\at%s\ax] \ay/mydps ui\ax - Toggle the Options UI.", script)
		,
		[8] = string.format("\aw[\at%s\ax] \ay/mydps hide\ax - Toggles show|hide of the Damage Spam Window.", script)
		,
		[9] = string.format("\aw[\at%s\ax] \ay/mydps clear\ax - Clear the data.", script)
		,
		[10] = string.format("\aw[\at%s\ax] \ay/mydps showtype\ax - Toggle Showing the type of attack.", script)
		,
		[11] = string.format("\aw[\at%s\ax] \ay/mydps showtarget\ax - Toggle Showing the Target of the attack.", script)
		,
		[12] = string.format("\aw[\at%s\ax] \ay/mydps showds\ax - Toggle Showing damage shield.", script)
		,
		[13] = string.format("\aw[\at%s\ax] \ay/mydps history\ax - Toggle the battle history window.", script)
		,
		[14] = string.format("\aw[\at%s\ax] \ay/mydps mymisses\ax - Toggle Showing my misses.", script)
		,
		[15] = string.format("\aw[\at%s\ax] \ay/mydps missed-me\ax - Toggle Showing NPC missed me.", script)
		,
		[16] = string.format("\aw[\at%s\ax] \ay/mydps hitme\ax - Toggle Showing NPC hit me.", script)
		,
		[17] = string.format("\aw[\at%s\ax] \ay/mydps sort [new|old]\ax - Sort Toggle newest on top. [new|old] arguments optional so set direction", script)
		,
		[18] = string.format("\aw[\at%s\ax] \ay/mydps sorthistory [new|old]\ax - Sort history Toggle newest on top. [new|old] arguments optional so set direction", script)
		,
		[19] = string.format("\aw[\at%s\ax] \ay/mydps settings\ax - Print current settings to console.", script)
		,
		[20] = string.format("\aw[\at%s\ax] \ay/mydps doreporting [all|battle|time]\ax - Toggle DPS Auto DPS reporting on for 'Battles, Time based, or BOTH'.", script)
		,
		[21] = string.format("\aw[\at%s\ax] \ay/mydps report\ax - Report the Time Based DPS since Last Report.", script)
		,
		[22] = string.format("\aw[\at%s\ax] \ay/mydps battlereport\ax - Report the battle history to console.", script)
		,
		[23] = string.format("\aw[\at%s\ax] \ay/mydps announce\ax - Toggle Announce to DanNet Group.", script)
		,
		[24] = string.format("\aw[\at%s\ax] \ay/mydps move\ax - Toggle click through, allows moving of window.", script)
		,
		[25] = string.format("\aw[\at%s\ax] \ay/mydps delay #\ax - Set the combat spam display time in seconds.", script)
		,
		[26] = string.format("\aw[\at%s\ax] \ay/mydps battledelay #\ax - Set the Battle ending Delay time in seconds.", script)
		,
		[27] = string.format("\aw[\at%s\ax] \ay/mydps help\ax - Show this help.", script)
		,
	}
	for i = 1, 27 do
		printOutput(help[i])
	end
end

local function pCurrentSettings()
	local msg = ''
	for k, v in pairs(settings.Options) do
		if k == "bgColor" then
			msg = string.format("\aw[\at%s\ax] \ay%s\ax = {\ar%s\ax, \ag%s\ax, \at%s\ax,\ao %s\ax}", script, k, v[1], v[2], v[3], v[4])
			printOutput(msg)
		else
			msg = string.format("\aw[\at%s\ax] \ay%s\ax = \at%s", script, k, v)
			printOutput(msg)
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
	if dur == nil then
		printOutput(string.format("\aw[\at%s\ax] \ayNothing to Report! Try again later.", script))
		return
	end
	if rType:lower() == "all" then
		local dps          = dur > 0 and (dmgTotal / dur) or 0
		local dpsDS        = dur > 0 and (dmgTotalDS / dur) or 0
		local avgDmg       = dmgCounter > 0 and (dmgTotal / dmgCounter) or 0
		local grandTotal   = dmgTotal + dmgTotalDS
		local grandCounter = dmgCounter + dsCounter
		local grangAvg     = grandCounter > 0 and (grandTotal / grandCounter) or 0
		local grandDPS     = dur > 0 and (grandTotal / dur) or 0
		local msgNoDS      = string.format(
			"\aw[\at%s\ax] \ayDPS \ax(\aoNO DS\ax): \at%.2f\ax, \ayTimeSpan:\ax\ao %.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage: \ax\ao%d\ax",
			script, dps, (dur / 60), dmgTotal, dmgCounter, avgDmg)
		local msgDS        = string.format(
			"\aw[\at%s\ax] \ayDPS \ax(\atDS Dmg\ax): \at%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Hits: \ax\ao%d\ax",
			script, dpsDS, (dur / 60), dmgTotalDS, dsCounter)
		local msgALL       = string.format(
			"\aw[\at%s\ax] \ayDPS \ax(\agALL\ax): \ag%.2f\ax, \ayTimeSpan: \ax\ao%.2f min\ax, \ayTotal Damage: \ax\ao%d\ax, \ayTotal Attempts: \ax\ao%d\ax, \ayAverage:\ax \ao%d\ax",
			script, grandDPS, (dur / 60), grandTotal, grandCounter, grangAvg)

		printOutput(msgNoDS)
		printOutput(msgDS)
		printOutput(msgALL)

		if settings.Options.announceDNET then
			announceDanNet(msgNoDS)
			announceDanNet(msgDS)
			announceDanNet(msgALL)
		end
		dmgTotal     = 0
		dmgCounter   = 0
		dmgTotalDS   = 0
		dsCounter    = 0
		dpsStartTime = os.time()
	elseif rType:lower() == 'combat' then
		local dps     = dur > 0 and (dmgTotalBattle / dur) or 0
		local avgDmg  = dmgBattCounter > 0 and (dmgTotalBattle / dmgBattCounter) or 0
		battleCounter = battleCounter + 1
		table.insert(battlesHistory, { sequence = battleCounter, dps = dps, dur = dur, dmg = dmgTotalBattle, avg = avgDmg, crit = critTotalBattle, critHeals = critHealsTotal, })
		if settings.Options.dpsBattleReport then
			local msg = string.format(
				"\aw[\at%s\ax] \ayChar:\ax\ao %s\ax, \ayDPS \ax(\aoBATTLE\ax): \at%s\ax, \ayTimeSpan:\ax\ao %.0f sec\ax, \ayTotal Damage: \ax\ao%s\ax, \ayAvg. Damage: \ax\ao%s\ax",
				script, MyName, cleanNumber(dps, 1, true), dur, cleanNumber(dmgTotalBattle, 2), cleanNumber(avgDmg, 1, true))
			printOutput(msg)
			if settings.Options.announceDNET then
				announceDanNet(msg)
			end
			if settings.Options.announceActors then
				ActorDPS:send({ mailbox = 'my_dps', }, ({ Name = MyName, Subject = 'Update', BattleNum = -3,
					DPS = dps, TimeSpan = dur, TotalDmg = dmgTotalBattle, AvgDmg = avgDmg, Remove = false, Crit = critTotalBattle, CritHeals = critHealsTotal, }))
				for k, v in ipairs(actorsTable) do
					if v.name == MyName then
						v.name      = MyName
						v.sequence  = -3
						v.dps       = dps
						v.dur       = dur
						v.dmg       = dmgTotalBattle
						v.crit      = critTotalBattle
						v.critHeals = critHealsTotal
						v.avg       = avgDmg
						break
					end
				end
			end
		end
		dmgTotalBattle = 0
		battlesHistory = sortTable(battlesHistory, 'history')
	end
end

local function pBattleHistory()
	if battleCounter == 0 then
		printOutput(string.format("\aw[\at%s\ax] \ayNo Battle History\ax", script))
		return
	end
	for i, v in ipairs(battlesHistory) do
		local msg = string.format(
			"\aw[\at%s\ax] \ayChar:\ax\ao %s\ax, \ayBattle: \ax\ao%d\ax, \ayDPS: \ax\at%s\ax, \ayDuration: \ax\ao%.0f sec\ax, \ayTotal Damage: \ax\ao%s\ax, \ayAvg. Damage: \ax\ao%\ax",
			script, MyName, v.sequence, cleanNumber(v.dps, 1, true), v.dur, cleanNumber(v.dmg, 2), cleanNumber(v.avg, 1, true))
		printOutput(msg)
		if settings.Options.announceDNET then
			announceDanNet(msg)
		end
	end
end

local function processCommand(...)
	local args = { ..., }
	if #args == 0 then
		printOutput(string.format("\aw[\at%s\ax] \arInvalid command, \ayType /mydps help for a list of commands.", script))
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
		printOutput(string.format("\aw[\at%s\ax] \ayToggle Combat Spam set to %s\ax", script, showCombatWindow))
	elseif cmd == "clear" then
		damTable, battlesHistory             = {}, {}
		battleStartTime, dpsStartTime        = 0, 0
		dmgTotal, dmgCounter, dsCounter      = 0, 0, 0
		dmgTotalDS, battleCounter, tableSize = 0, 0, 0
		printOutput(string.format("\aw[\at%s\ax] \ayTable Cleared\ax", script))
	elseif cmd == 'start' then
		started = true
		clickThrough = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		printOutput(string.format("\aw[\at%s\ax] \ayStarted\ax", script))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Type set to %s\ax", script, settings.Options.showType))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Target set to %s\ax", script, settings.Options.showTarget))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Damage Shield set to %s\ax", script, settings.Options.showDS))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Battle History set to %s\ax", script, showBattleHistory))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow My Misses set to %s\ax", script, settings.Options.showMyMisses))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Missed Me set to %s\ax", script, settings.Options.showMissMe))
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
		printOutput(string.format("\aw[\at%s\ax] \ayShow Hit Me set to %s\ax", script, settings.Options.showHitMe))
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
		printOutput(string.format("\aw[\at%s\ax] \aySort Combat Spam\ax \at%s \axOn Top!", script, dir))
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
		printOutput(string.format("\aw[\at%s\ax] \aySorted Battle History\ax \at%s \axOn Top!", script, dir))
	elseif cmd == 'move' then
		clickThrough = not clickThrough
		printOutput(string.format("\aw[\at%s\ax] \ayClick Through set to %s\ax", script, clickThrough))
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
		printOutput(string.format("\aw[\at%s\ax] \ayAnnounce to DanNet Group set to %s\ax", script, settings.Options.announceDNET))
	elseif #args == 2 and cmd == 'doreporting' then
		if args[2] == 'battle' then
			settings.Options.dpsBattleReport = not settings.Options.dpsBattleReport
			printOutput(string.format("\aw[\at%s\ax] \ayDo DPS Battle Reporting set to %s\ax", script, settings.Options.dpsBattleReport))
		elseif args[2] == 'time' then
			settings.Options.dpsTimeSpanReport = not settings.Options.dpsTimeSpanReport
			printOutput(string.format("\aw[\at%s\ax] \ayDo DPS Reporting set to %s\ax", script, settings.Options.dpsTimeSpanReport))
		elseif args[2] == 'all' then
			settings.Options.dpsBattleReport = not settings.Options.dpsBattleReport
			settings.Options.dpsTimeSpanReport = settings.Options.dpsBattleReport
			printOutput(string.format("\aw[\at%s\ax] \ayDo DPS Reporting set to %s\ax", script, settings.Options.dpsTimeSpanReport))
		else
			printOutput(string.format(
				"\aw[\at%s\ax] \arInvalid argument, \ayType \at/mydps doreporting\ax takes arguments \aw[\agall\aw|\agbattle\aw|\agtime\aw] \ayplease try again.", script))
		end
	elseif #args == 2 and cmd == "delay" then
		if tonumber(args[2]) then
			settings.Options.displayTime = tonumber(args[2])
			printOutput(string.format("\aw[\at%s\ax] \ayDisplay time set to %s\ax", script, settings.Options.displayTime))
		else
			printOutput(string.format("\aw[\at%s\ax] \arInvalid argument, \ayType /mydps help for a list of commands.", script))
		end
	elseif #args == 2 and cmd == "battledelay" then
		if tonumber(args[2]) then
			settings.Options.battleDuration = tonumber(args[2])
			printOutput(string.format("\aw[\at%s\ax] \ayBattle Duration time set to %s\ax", script, settings.Options.battleDuration))
		else
			printOutput(string.format("\aw[\at%s\ax] \arInvalid argument, \ayType /mydps help for a list of commands.", script))
		end
	elseif cmd == "help" then
		pHelp()
	else
		printOutput(string.format("\aw[\at%s\ax] \arUnknown command, \ayType /mydps help for a list of commands.", script))
	end
	mq.pickle(configFile, settings)
end

--create mailbox for actors to send messages to
local function RegisterActor()
	ActorDPS = actors.register('my_dps', function(message)
		local MemberEntry  = message()
		local who          = MemberEntry.Name
		local timeSpan     = MemberEntry.TimeSpan or 0
		local avgDmg       = MemberEntry.AvgDmg or 0
		local dps          = MemberEntry.DPS or 0
		local totalDmg     = MemberEntry.TotalDmg or 0
		local battleNum    = MemberEntry.BattleNum or 0
		local critDmg      = MemberEntry.Crit or 0
		local critHealsAmt = MemberEntry.CritHeals or 0

		if who == MyName then return end
		if #actorsTable == 0 then
			table.insert(actorsTable, { name = who, dps = dps, avg = avgDmg, dmg = totalDmg, dur = timeSpan, sequence = battleNum, crit = critDmg, critHeals = critHealsAmt, })
		else
			local found = false
			for i = 1, #actorsTable do
				if actorsTable[i].name == who then
					if MemberEntry.Remove then
						table.remove(actorsTable, i)
					else
						actorsTable[i].name      = who
						actorsTable[i].dps       = dps
						actorsTable[i].avg       = avgDmg
						actorsTable[i].dmg       = totalDmg
						actorsTable[i].dur       = timeSpan
						actorsTable[i].crit      = critDmg
						actorsTable[i].critHeals = critHealsAmt
						actorsTable[i].sequence  = battleNum
					end
					found = true
					break
				end
			end
			if not found then
				table.insert(actorsTable, { name = who, dps = dps, avg = avgDmg, dmg = totalDmg, dur = timeSpan, sequence = battleNum, crit = critDmg, critHeals = critHealsAmt, })
			end
		end
	end)
end

local args = { ..., }
local function Init()
	loadSettings()

	MyName = mq.TLO.Me.CleanName()

	-- Register Events
	local str = string.format("#*#%s scores a critical hit! #*#(#1#)", MyName)

	mq.event("melee_crit", "#*#You score a critical hit! #*#(#1#)", critCallBack)
	mq.event("melee_crit2", "#*#You deliver a critical blast! #*#(#1#)", critCallBack)
	mq.event("melee_crit3", str, critCallBack)
	str = string.format("#*#%s scores a Deadly Strike! #*#(#1#)", MyName)
	mq.event("melee_deadly_strike", str, critCallBack)
	str = string.format("#*#%s hit #1# for #2# points of non-melee damage#*#", MyName)
	mq.event("melee_non_melee", str, nonMeleeClallBack)
	mq.event("melee_damage_shield", "#*# was hit by non-melee for #2# points of damage#*#", nonMeleeClallBack)
	mq.event("melee_you_hit_non-melee", "#*#You were hit by non-melee for #2# damage#*#", nonMeleeClallBack)
	mq.event("melee_do_damage", "#*#You #1# #2# for #3# points of damage#*#", meleeCallBack)
	mq.event("melee_miss", "#*#You try to #1# #2#, but miss#*#", meleeCallBack)
	mq.event("melee_got_hit", "#2# #1# YOU for #3# points of damage#*#", npcMeleeCallBack)
	mq.event("melee_missed_me", "#2# tries to #1# YOU, but misses#*#", npcMeleeCallBack)
	mq.event("melee_crit_heal", "#*#You perform an exceptional heal! #*#(#1#)", critHealCallBack)
	mq.bind("/mydps", processCommand)


	-- Initialize ImGui
	mq.imgui.init(script, Draw_GUI)

	-- Register Actor Mailbox
	if settings.Options.announceActors then RegisterActor() end

	-- Print Help
	pHelp()

	-- Check for arguments
	if args[1] ~= nil and args[1] == "start" then
		if #args == 2 and args[2] == 'hide' then
			showCombatWindow = false
		end
		started = true
		clickThrough = true
		winFlags = bit32.bor(ImGuiWindowFlags.NoMouseInputs, ImGuiWindowFlags.NoDecoration)
		printOutput(string.format("\aw[\at%s\ax] \ayStarted\ax", script))
	end
end

local function Loop()
	local uiTime = 1
	-- Main Loop
	while RUNNING do
		-- Make sure we are still in game or exit the script.
		if mq.TLO.EverQuest.GameState() ~= "INGAME" then
			printOutput(string.format("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script))
			mq.exit()
		end

		if doActors ~= settings.Options.announceActors then
			if settings.Options.announceActors then
				RegisterActor()
			end
			doActors = settings.Options.announceActors
		end

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
				for k, v in pairs(battlesHistory) do
					if v.sequence == -1 or v.sequence == 999999 then
						table.remove(battlesHistory, k)
					end
				end
				pDPS(battleDuration, "COMBAT")
				battleStartTime = 0
				leftCombatTime = 0
			end
		end
		-- Clean up the table
		if battleStartTime > 0 then
			parseCurrentBattle(currentTime - battleStartTime)
		end
		cleanTable()
		workingTable = sortTable(damTable, 'combat')
		if doActors and uiTime == 1 then actorsWorking = sortTable(actorsTable, 'party') end
		if sortParty then
			actorsWorking = actorsTable
		end

		mq.doevents()
		mq.delay(5)
		if sortParty then
			uiTime = uiTime + 5
			if uiTime >= 34 then
				if doActors then actorsWorking = sortTable(actorsTable, 'party') end
				uiTime = 0
			end
		end
	end
end
-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then
	printOutput(string.format("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script))
	mq.exit()
end
Init()
Loop()
