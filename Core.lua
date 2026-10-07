local addonName, ns = ...

KnowYourRotationDB = KnowYourRotationDB or {}

local function copyValue(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do
		out[copyValue(k, seen)] = copyValue(v, seen)
	end
	return out
end

local function useCharacterDB()
	KnowYourRotationDB = KnowYourRotationDB or {}
	KnowYourRotationCharDB = KnowYourRotationCharDB or {}
	if KnowYourRotationCharDB.charReady ~= 1 then
		local snap = copyValue(KnowYourRotationDB)
		for k, v in pairs(snap) do
			if KnowYourRotationCharDB[k] == nil then
				KnowYourRotationCharDB[k] = v
			end
		end
		KnowYourRotationCharDB.charReady = 1
	end
	ns.db = KnowYourRotationCharDB
end

useCharacterDB()

local function defaults()
	useCharacterDB()
	if ns.ApplyLocale then
		ns.ApplyLocale()
	end
	if ns.db.listVersion ~= 4 then
		ns.db.listVersion = 4
		ns.db.apl = nil
		ns.db.aplDrop = nil
		ns.db.def = nil
		ns.db.defDrop = nil
		if ns.db.profiles then
			for _, p in pairs(ns.db.profiles) do
				p.apl = nil
				p.aplDrop = nil
				p.def = nil
				p.defDrop = nil
			end
		end
	end
	if ns.db.showRotation == nil then
		ns.db.showRotation = true
	end
	if ns.db.showDefense == nil then
		ns.db.showDefense = true
	end
	if ns.db.showInterrupt == nil then
		ns.db.showInterrupt = true
	end
	if ns.db.showPurge == nil then
		ns.db.showPurge = true
	end
	if ns.db.showCleanse == nil then
		ns.db.showCleanse = true
	end
	if ns.db.showWeapon == nil then
		ns.db.showWeapon = true
	end
	if ns.db.autoHeal == nil then
		ns.db.autoHeal = true
	end
	if ns.db.autoProfile == nil then
		ns.db.autoProfile = true
	end
	if ns.db.cleanseGroup == nil then
		ns.db.cleanseGroup = true
	end
	if ns.db.showPhysics == nil then
		ns.db.showPhysics = true
	end
	if ns.db.roleAuto == nil then
		ns.db.roleAuto = true
	end
	if ns.db.soundKick == nil then
		ns.db.soundKick = "raidwarning"
	end
	if ns.db.soundCleanse == nil then
		ns.db.soundCleanse = "ping"
	end
	if ns.db.soundWeapon == nil then
		ns.db.soundWeapon = "alarm"
	end
	ns.db.colors = ns.db.colors or {}
	if not ns.db.role then
		ns.db.role = "damage"
	end
	ns.db.role = ns.NormalizeRole(ns.db.role)
	if ns.db.autoEnemies == nil then
		ns.db.autoEnemies = 3
	end
	if ns.db.lastManualMode ~= "aoe" then
		ns.db.lastManualMode = "single"
	end
	if ns.db.combatMode ~= "auto" and ns.db.combatMode ~= "single" and ns.db.combatMode ~= "aoe" then
		ns.db.combatMode = "auto"
	end
	if not ns.db.profiles then
		ns.db.profiles = {
			pve = {
				apl = ns.db.apl,
				aplDrop = ns.db.aplDrop,
				def = ns.db.def,
				defDrop = ns.db.defDrop,
				role = ns.db.role,
				combatMode = ns.db.combatMode,
				lastManualMode = ns.db.lastManualMode,
				autoEnemies = ns.db.autoEnemies,
				weaponBuff = ns.db.weaponBuff,
			},
			pvp = {},
		}
		ns.db.profile = "pve"
	end
	for _, key in ipairs(ns.PROFILE_ORDER) do
		ns.db.profiles[key] = ns.db.profiles[key] or {}
	end
	-- Only PvE and PvP profiles exist now.
	ns.db.profiles.base = nil
	ns.db.profiles.custom = nil
	ns.db.autoProfileFrom = nil
	if not ns.ValidProfile(ns.db.profile) then
		ns.db.profile = "pve"
	end
	ns.BindProfile()
end

ns.PROFILE_ORDER = { "pve", "pvp" }

function ns.ValidProfile(key)
	return key == "pve" or key == "pvp"
end

function ns.ProfileKey()
	local key = ns.db and ns.db.profile
	if ns.ValidProfile(key) then
		return key
	end
	return "pve"
end

function ns.FlushProfile()
	if not ns.db then
		return
	end
	ns.db.profiles = ns.db.profiles or {}
	local key = ns.ProfileKey()
	local p = ns.db.profiles[key] or {}
	ns.db.profiles[key] = p
	p.apl = ns.db.apl
	p.aplDrop = ns.db.aplDrop
	p.def = ns.db.def
	p.defDrop = ns.db.defDrop
	p.role = ns.db.role
	p.combatMode = ns.db.combatMode
	p.lastManualMode = ns.db.lastManualMode
	p.autoEnemies = ns.db.autoEnemies
	p.weaponBuff = ns.db.weaponBuff
	p.weaponBuffOff = ns.db.weaponBuffOff
end

function ns.BindProfile()
	ns.db.profiles = ns.db.profiles or {}
	local key = ns.ProfileKey()
	ns.db.profile = key
	ns.db.profiles[key] = ns.db.profiles[key] or {}
	local p = ns.db.profiles[key]
	ns.db.apl = p.apl
	ns.db.aplDrop = p.aplDrop
	ns.db.def = p.def
	ns.db.defDrop = p.defDrop
	ns.db.role = ns.NormalizeRole(p.role)
	local mode = p.combatMode or "auto"
	if mode ~= "auto" and mode ~= "single" and mode ~= "aoe" then
		mode = "auto"
	end
	ns.db.combatMode = mode
	ns.db.lastManualMode = p.lastManualMode or "single"
	ns.db.autoEnemies = tonumber(p.autoEnemies) or 3
	ns.db.weaponBuff = p.weaponBuff
	ns.db.weaponBuffOff = p.weaponBuffOff
end

function ns.SetProfile(key)
	if not ns.ValidProfile(key) then
		return
	end
	if ns.ProfileKey() == key and ns.db.profiles and ns.db.profiles[key] then
		ns.BindProfile()
		return
	end
	ns.FlushProfile()
	ns.db.profile = key
	ns.BindProfile()
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.UI and ns.UI.RefreshRoles then
		ns.UI.RefreshRoles()
	end
	if ns.UI and ns.UI.RefreshModes then
		ns.UI.RefreshModes()
	end
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
	if ns.Tick then
		ns.Tick()
	end
end

-- Profile picked in the options: "auto" follows instance type / enemy player target,
-- "pve" or "pvp" pins that profile and turns the automatic switch off.
function ns.SetProfileChoice(choice)
	if choice == "auto" then
		ns.db.autoProfile = true
		ns.ApplyAutoProfile()
	elseif ns.ValidProfile(choice) then
		ns.db.autoProfile = false
		ns.SetProfile(choice)
	end
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
end

function ns.ProfileChoice()
	if ns.db.autoProfile ~= false then
		return "auto"
	end
	return ns.ProfileKey()
end

function ns.ResetCurrentProfile()
	ns.db.apl = nil
	ns.db.aplDrop = nil
	ns.db.def = nil
	ns.db.defDrop = nil
	ns.db.weaponBuff = nil
	ns.db.weaponBuffOff = nil
	ns.db.autoEnemies = 3
	ns.db.lastManualMode = "single"
	ns.db.combatMode = "auto"
	ns.db.role = ns.NormalizeRole(nil)
	ns.FlushProfile()
	ns.BindProfile()
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.UI and ns.UI.RefreshRoles then
		ns.UI.RefreshRoles()
	end
	if ns.UI and ns.UI.RefreshModes then
		ns.UI.RefreshModes()
	end
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
	if ns.Tick then
		ns.Tick()
	end
	ns.Print(ns.T("OPT_RESET_ALL_DONE"))
end

function ns.ResetAll()
	ns.ResetCurrentProfile()
end

function ns.ConfirmResetAll()
	if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
		ns.ResetAll()
		return
	end
	StaticPopupDialogs.KNOWYOURROTATION_RESET_ALL = {
		text = ns.T("OPT_RESET_ALL_CONFIRM"),
		button1 = YES or OKAY or "OK",
		button2 = NO or CANCEL or "No",
		OnAccept = function()
			ns.ResetAll()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("KNOWYOURROTATION_RESET_ALL")
end

function ns.NormalizeRole(role)
	local token = ns.ClassToken()
	if ns.RoleAllowed(role) then
		return role
	end
	if token == "SHAMAN" and role == "damage" then
		return "caster"
	end
	if token == "HUNTER" and role == "damage" then
		return "range"
	end
	if token == "DRUID" and role == "damage" then
		return "hybrid"
	end
	local roles = token and ns.CLASS_ROLES[token] or { "damage" }
	return roles[1]
end

function ns.ClassToken()
	local ok, localized, classFile, classId = pcall(UnitClass, "player")
	if ok and type(classFile) == "string" then
		local upOk, upper = pcall(string.upper, classFile)
		if upOk then
			return upper, classId, localized
		end
	end
	if UnitClassBase then
		local okBase, base = pcall(UnitClassBase, "player")
		if okBase and type(base) == "string" then
			return base:upper(), classId, localized
		end
	end
	return nil, classId, localized
end

function ns.RoleAllowed(role)
	local token = ns.ClassToken()
	local roles = token and ns.CLASS_ROLES[token] or { "damage" }
	for _, allowed in ipairs(roles) do
		if allowed == role then
			return true
		end
	end
	return false
end

function ns.SetRole(role)
	role = ns.NormalizeRole(role)
	if not ns.RoleAllowed(role) then
		return
	end
	ns.db.role = role
	if ns.FlushProfile then
		ns.FlushProfile()
	end
	if ns.UI and ns.UI.RefreshRoles then
		ns.UI.RefreshRoles()
	end
	ns.Tick()
end

function ns.SetCombatMode(mode)
	if mode ~= "auto" and mode ~= "aoe" then
		mode = "single"
	end
	if mode ~= "auto" then
		ns.db.lastManualMode = mode
	end
	ns.db.combatMode = mode
	if ns.FlushProfile then
		ns.FlushProfile()
	end
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.UI and ns.UI.RefreshModes then
		ns.UI.RefreshModes()
	end
	if ns.UI.options and ns.RefreshOptions then
		ns.RefreshOptions()
	end
	ns.Tick()
end

-- Role picked in the options: "auto" detects it (talents, stance, range),
-- any other value pins that role.
function ns.SetRoleChoice(choice)
	if choice == "auto" then
		ns.db.roleAuto = true
		if ns.SyncAutoRole then
			ns.SyncAutoRole()
		end
		if ns.FlushProfile then
			ns.FlushProfile()
		end
		if ns.RefreshOptions then
			ns.RefreshOptions()
		end
		ns.Tick()
		return
	end
	ns.db.roleAuto = false
	ns.SetRole(choice)
end

function ns.RoleChoice()
	if ns.db.roleAuto ~= false then
		return "auto"
	end
	return ns.db.role or "damage"
end

local lastTickSig

local function flagBit(value)
	return value ~= false and "1" or "0"
end

function ns.InvalidateTick()
	lastTickSig = nil
end

function ns.ApplyFeatureFlags()
	if ns.db.showRotation == false then
		if ns.GlowClear then
			ns.GlowClear()
		end
	end
	if ns.db.showDefense == false then
		if ns.GlowClearDef then
			ns.GlowClearDef()
		end
	end
	if ns.db.showInterrupt == false and ns.GlowClearKick then
		ns.GlowClearKick()
	end
	if ns.db.showPurge == false and ns.GlowClearPurge then
		ns.GlowClearPurge()
	end
	if ns.db.showCleanse == false and ns.GlowClearCleanse then
		ns.GlowClearCleanse()
	end
	if ns.db.showWeapon == false and ns.GlowClearWeapon then
		ns.GlowClearWeapon()
	end
	lastTickSig = nil
	if ns.Tick then
		ns.Tick()
	end
end

local lastAlertKick, lastAlertCleanse, lastAlertWeapon, lastNotice

-- Alert sounds the player can pick per alert (Advanced page). The first entry
-- is "no sound". Numbers are the fallback sound IDs.
ns.SOUNDS = {
	{ key = "none", label = "SND_NONE" },
	{ key = "ping", label = "SND_PING", kit = "MAP_PING", id = 3175 },
	{ key = "ready", label = "SND_READY", kit = "READY_CHECK", id = 8960 },
	{ key = "raidwarning", label = "SND_RAID", kit = "RAID_WARNING", id = 8959 },
	{ key = "alarm", label = "SND_ALARM", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
	{ key = "whisper", label = "SND_WHISPER", kit = "TELL_MESSAGE", id = 3081 },
	{ key = "quest", label = "SND_QUEST", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
	{ key = "toast", label = "SND_TOAST", kit = "UI_BNET_TOAST", id = 18019 },
	{ key = "click", label = "SND_CLICK", kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856 },
}

local function soundEntry(key)
	for _, entry in ipairs(ns.SOUNDS) do
		if entry.key == key then
			return entry
		end
	end
	return ns.SOUNDS[1]
end

function ns.SoundLabelKey(key)
	return soundEntry(key).label
end

function ns.NextSound(key)
	for index, entry in ipairs(ns.SOUNDS) do
		if entry.key == key then
			return (ns.SOUNDS[index + 1] or ns.SOUNDS[1]).key
		end
	end
	return ns.SOUNDS[1].key
end

function ns.PlayAlertSound(key)
	local entry = soundEntry(key)
	if not entry.id then
		return
	end
	local kit = (SOUNDKIT and SOUNDKIT[entry.kit]) or entry.id
	pcall(PlaySound, kit, "Master", true)
end

local ALERT_SOUND_KEY = { kick = "soundKick", cleanse = "soundCleanse", weapon = "soundWeapon" }

local function playAlert(kind, spellID)
	local key = ALERT_SOUND_KEY[kind]
	if key and ns.db then
		ns.PlayAlertSound(ns.db[key])
	end
end

function ns.ApplyAutoProfile()
	if not ns.db or ns.db.autoProfile == false or not ns.SetProfile then
		return
	end
	local itype
	if GetInstanceInfo then
		local ok, _, instanceType = pcall(GetInstanceInfo)
		if ok then
			itype = instanceType
		end
	end
	-- Open world: an attackable player as target counts as PvP (the PvP flag
	-- does not: on a PvP realm it is on all the time in contested zones).
	-- Instances decide by their own type below.
	local pvpTarget = false
	local okP, isPlayer = pcall(UnitIsPlayer, "target")
	local okA, canAttack = pcall(UnitCanAttack, "player", "target")
	if okP and okA and isPlayer == true and canAttack == true then
		pvpTarget = true
	end
	local want
	if itype == "pvp" or itype == "arena" then
		want = "pvp"
	elseif itype == "party" or itype == "raid" then
		want = "pve"
	elseif pvpTarget then
		want = "pvp"
	else
		want = "pve"
	end
	if ns.ProfileKey() == want then
		return
	end
	-- Do not swap lists back to PvE in the middle of a fight.
	if want == "pve" and ns.API.InCombat() then
		return
	end
	ns.SetProfile(want)
end

function ns.Tick()
	if not ns.booted then
		return
	end
	-- Remember max health while the client still lets us read it.
	ns.API.MaxHealth("player")
	if ns.SyncAutoRole then
		ns.SyncAutoRole()
	end

	-- No glow while dead, mounted, eating, or resting in town.
	local idle = ns.API.ShouldHideIdle() or ns.db.muted == true
	local queue = ns.db.showRotation ~= false and not idle and ns.BuildQueue() or {}
	local defense = ns.db.showDefense ~= false and not idle and ns.BuildDefense() or nil
	local interrupt = ns.db.showInterrupt ~= false and not idle and ns.BuildInterrupt() or nil
	local purge = ns.db.showPurge ~= false and not idle and ns.BuildPurge() or nil
	local cleanse = ns.db.showCleanse ~= false and not idle and ns.BuildCleanse() or nil
	local weapon, weaponNeed, _
	if ns.db.showWeapon ~= false and not idle then
		weapon, _, weaponNeed = ns.BuildWeapon()
	end
	-- Pet reminders (hunter / warlock) show once as a screen message.
	local noticeKey = not idle and ns.API.CombatNotice and ns.API.CombatNotice() or nil
	if noticeKey and noticeKey ~= lastNotice and UIErrorsFrame then
		UIErrorsFrame:AddMessage(ns.T(noticeKey), 1, 0.82, 0)
	end
	lastNotice = noticeKey
	if interrupt and interrupt ~= lastAlertKick then
		playAlert("kick", interrupt)
	end
	lastAlertKick = interrupt
	if cleanse and cleanse ~= lastAlertCleanse then
		playAlert("cleanse", cleanse)
	end
	lastAlertCleanse = cleanse
	if weaponNeed and weapon and weapon ~= lastAlertWeapon then
		playAlert("weapon", weapon)
	end
	if not weaponNeed then
		lastAlertWeapon = nil
	else
		lastAlertWeapon = weapon
	end
	local sig = (queue[1] or 0)
		.. (ns.queueGlowOk and "g" or "n")
		.. ":"
		.. (queue[2] or 0)
		.. ":"
		.. (queue[3] or 0)
		.. ":"
		.. (defense or 0)
		.. ":"
		.. (interrupt or 0)
		.. ":"
		.. (purge or 0)
		.. ":"
		.. (cleanse or 0)
		.. ":"
		.. (weapon or 0)
		.. ":"
		.. (weaponNeed and 1 or 0)
		.. ":"
		.. flagBit(ns.db.showRotation)
		.. flagBit(ns.db.showDefense)
		.. flagBit(ns.db.showInterrupt)
		.. flagBit(ns.db.showPurge)
		.. flagBit(ns.db.showCleanse)
		.. flagBit(ns.db.showWeapon)
		.. flagBit(not idle)
	-- Heal cue when health is hidden: refreshed every tick, the client drives alpha.
	local hiddenHeal, hiddenThreshold
	if ns.db.showRotation ~= false and not idle and ns.BuildHiddenHeal then
		hiddenHeal, hiddenThreshold = ns.BuildHiddenHeal()
	end
	if ns.GlowHiddenHeal then
		ns.GlowHiddenHeal(hiddenHeal, hiddenThreshold)
	end
	local hiddenDef, hiddenDefThreshold
	if ns.db.showDefense ~= false and not idle and ns.BuildHiddenDefense then
		hiddenDef, hiddenDefThreshold = ns.BuildHiddenDefense()
	end
	if ns.GlowHiddenDefense then
		ns.GlowHiddenDefense(hiddenDef, hiddenDefThreshold)
	end
	local hiddenExec, hiddenExecThreshold
	if ns.db.showRotation ~= false and not idle and ns.BuildHiddenExecute then
		hiddenExec, hiddenExecThreshold = ns.BuildHiddenExecute()
	end
	if ns.GlowHiddenExecute then
		ns.GlowHiddenExecute(hiddenExec, hiddenExecThreshold)
	end
	local hiddenPet, hiddenPetThreshold
	if ns.db.showRotation ~= false and not idle and ns.BuildHiddenPet then
		hiddenPet, hiddenPetThreshold = ns.BuildHiddenPet()
	end
	if ns.GlowHiddenPet then
		ns.GlowHiddenPet(hiddenPet, hiddenPetThreshold)
	end
	local hiddenMana, hiddenManaThreshold
	if ns.db.showRotation ~= false and not idle and ns.BuildHiddenMana then
		hiddenMana, hiddenManaThreshold = ns.BuildHiddenMana()
	end
	if ns.GlowHiddenMana then
		ns.GlowHiddenMana(hiddenMana, hiddenManaThreshold)
	end
	if sig ~= lastTickSig then
		lastTickSig = sig
		if ns.GlowSpell then
			ns.GlowSpell(ns.db.showRotation ~= false and ns.queueGlowOk and queue[1] or nil)
		end
		if ns.GlowDef then
			ns.GlowDef(defense)
		end
		if ns.GlowInterrupt then
			ns.GlowInterrupt(interrupt)
		end
		if ns.GlowPurge then
			ns.GlowPurge(purge)
		end
		if ns.GlowCleanse then
			ns.GlowCleanse(cleanse)
		end
		if ns.GlowWeapon then
			ns.GlowWeapon(weaponNeed and weapon or nil)
		end
	end
	-- After the glows are set: fade the rotation glow where the finisher takes over.
	if ns.GlowFadeForFinisher then
		local fade = hiddenExec and ns.queueGlowOk and queue[1] ~= hiddenExec and queue[1] or nil
		ns.GlowFadeForFinisher(fade, hiddenExecThreshold)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
pcall(frame.RegisterEvent, frame, "WEAPON_ENCHANT_CHANGED")
pcall(frame.RegisterEvent, frame, "UNIT_AURA")
pcall(frame.RegisterEvent, frame, "UNIT_INVENTORY_CHANGED")
pcall(frame.RegisterEvent, frame, "UNIT_SPELLCAST_START")
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_SKILL_LINE")
-- Do NOT register SPELLS_CHANGED: Forever fires it in storms on quest
-- turn-in / level-up and it is what froze the client. ConROC core also
-- ignores SPELLS_CHANGED and only reacts to learn / level-up.
pcall(frame.RegisterEvent, frame, "SPELL_PUSHED_TO_ACTIONBAR")
pcall(frame.RegisterEvent, frame, "PLAYER_TALENT_UPDATE")
pcall(frame.RegisterEvent, frame, "PLAYER_LEVEL_UP")
pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")
pcall(frame.RegisterEvent, frame, "PLAYER_DEAD")
pcall(frame.RegisterEvent, frame, "PLAYER_ALIVE")
pcall(frame.RegisterEvent, frame, "PLAYER_UNGHOST")
pcall(frame.RegisterEvent, frame, "PLAYER_UPDATE_RESTING")
pcall(frame.RegisterEvent, frame, "PLAYER_MOUNT_DISPLAY_CHANGED")
pcall(frame.RegisterEvent, frame, "ZONE_CHANGED_NEW_AREA")
pcall(frame.RegisterEvent, frame, "UNIT_POWER_UPDATE")
pcall(frame.RegisterEvent, frame, "UI_ERROR_MESSAGE")
pcall(frame.RegisterEvent, frame, "PLAYER_TOTEM_UPDATE")

local ticker
local booted

-- Started once, on the first login event.
local function startTicker()
	ticker = C_Timer.NewTicker(0.2, function()
		ns.Tick()
	end)
end

local function stopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local tickQueued
local spellsFlushGen = 0
local barFlushGen = 0
local lastPlayerCastName

local function requestTick()
	lastTickSig = nil
	if tickQueued then
		return
	end
	tickQueued = true
	local function run()
		tickQueued = nil
		ns.Tick()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0, run)
	else
		run()
	end
end

local function forceTick()
	if ns.API and ns.API.WipeAuraScans then
		ns.API.WipeAuraScans()
	end
	requestTick()
end

local function flushBars()
	if ns.GlowFetch then
		ns.GlowFetch(true)
	end
	if ns.GlowInvalidate then
		ns.GlowInvalidate()
	end
	requestTick()
end

local function scheduleBarFlush()
	-- ConROC: CancelTimer + ScheduleTimer('Fetch', 0.5)
	barFlushGen = barFlushGen + 1
	local gen = barFlushGen
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, function()
			if gen ~= barFlushGen then
				return
			end
			flushBars()
		end)
	else
		flushBars()
	end
end

local function flushSpells()
	-- ConROC-style (Forever-safe): on learn / level-up, only clear *failed*
	-- Resolve entries so newly learned ranks can resolve. Do NOT wipe known
	-- hits and do NOT rebuild the spellbook index (that is what froze Forever
	-- on quest turn-in). Pulse/Tick picks up new ranks via IsPlayerSpell.
	if ns.API and ns.API.InvalidateSpells then
		ns.API.InvalidateSpells(false)
	end
	lastTickSig = nil
	requestTick()
	scheduleBarFlush()
end

local function scheduleSpellFlush()
	spellsFlushGen = spellsFlushGen + 1
	local gen = spellsFlushGen
	if C_Timer and C_Timer.After then
		-- Same idea as ConROC ButtonFetch(0.5): coalesce learn spam.
		C_Timer.After(0.5, function()
			if gen ~= spellsFlushGen then
				return
			end
			flushSpells()
		end)
	else
		flushSpells()
	end
end

local function weaponItemId(slot)
	if not GetInventoryItemID then
		return nil
	end
	local ok, id = pcall(GetInventoryItemID, "player", slot)
	if ok and type(id) == "number" then
		return id
	end
	return nil
end

local function liveAuraUnit(unit)
	-- Player + current targets only. Party auras were wiping caches constantly
	-- in groups and forcing extra work that felt like input lag.
	return unit == "player" or unit == "target" or unit == "focus" or unit == "mouseover"
end

frame:SetScript("OnEvent", function(_, event, unit, powerToken, spellID)
	if event == "PLAYER_LOGOUT" then
		stopTicker()
		if ns.FlushProfile then
			ns.FlushProfile()
		end
		return
	end
	if event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_LEVEL_UP" then
		scheduleSpellFlush()
		return
	end
	if event == "SPELL_PUSHED_TO_ACTIONBAR" then
		-- ConROC: bar map only — no spellbook walk.
		scheduleBarFlush()
		return
	end
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		defaults()
		if not booted then
			booted = true
			ns.booted = true
			if ns.API and ns.API.InvalidateSpells then
				ns.API.InvalidateSpells(true)
			end
			if ns.API and ns.API.RebuildSpellBookIndex then
				ns.API.RebuildSpellBookIndex(false)
			end
			if ns.RegisterOptions then
				local okMini, errMini = pcall(ns.RegisterOptions)
				if not okMini then
					ns.Print(errMini)
				end
			end
			if ns.GlowFetch then
				ns.GlowFetch(true)
			end
			startTicker()
		end
		ns.weaponItemMain = weaponItemId(16)
		ns.weaponItemOff = weaponItemId(17)
		if ns.ApplyAutoProfile then
			ns.ApplyAutoProfile()
		end
		if event == "PLAYER_LOGIN" then
			local token, _, localized = ns.ClassToken()
			ns.Print(ns.T("INIT"))
			ns.Print(format(ns.T("MODULE"), localized or token or "?"))
		end
		ns.Tick()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		if ns.ApplyAutoProfile then
			ns.ApplyAutoProfile()
		end
		forceTick()
	elseif
		event == "PLAYER_DEAD"
		or event == "PLAYER_ALIVE"
		or event == "PLAYER_UNGHOST"
		or event == "PLAYER_UPDATE_RESTING"
		or event == "PLAYER_MOUNT_DISPLAY_CHANGED"
	then
		-- Totems vanish when you die.
		if event == "PLAYER_DEAD" and ns.API and ns.API.ClearTotems then
			ns.API.ClearTotems()
		end
		forceTick()
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- Classic combo points stay on the old target.
		if ns.API and ns.API.ResetComboEstimate then
			ns.API.ResetComboEstimate()
		end
		if ns.ApplyAutoProfile then
			ns.ApplyAutoProfile()
		end
		ns.API.castTarget = false
		if ns.API and ns.API.ClearTargetDebuffs then
			ns.API.ClearTargetDebuffs()
		end
		if ns.ClearRotationSpent then
			ns.ClearRotationSpent()
		end
		forceTick()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.API and ns.API.ResetComboEstimate then
			ns.API.ResetComboEstimate()
		end
		if ns.ApplyAutoProfile then
			ns.ApplyAutoProfile()
		end
		if ns.ClearRotationSpent then
			ns.ClearRotationSpent()
		end
		forceTick()
	elseif event == "UNIT_AURA" then
		if liveAuraUnit(unit) then
			if ns.API and ns.API.WipeAuraScan then
				ns.API.WipeAuraScan(unit)
			end
			-- Do not force Tick here: aura storms + full queue rebuild feel like
			-- input lag. The 0.2s ticker rebuilds with a fresh aura scan.
		end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if unit == "player" then
			if ns.API and ns.API.ClearWeaponTooltipCache then
				ns.API.ClearWeaponTooltipCache()
			end
			requestTick()
		end
	elseif event == "UNIT_SPELLCAST_START" then
		if unit == "player" and UnitCastingInfo then
			local ok, name = pcall(UnitCastingInfo, "player")
			if ok and type(name) == "string" then
				lastPlayerCastName = name
			end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" then
			local castName = lastPlayerCastName
			lastPlayerCastName = nil
			local id = spellID
			if
				(id == nil or (issecretvalue and issecretvalue(id)))
				and castName
				and ns.API
				and ns.API.ResolveFromName
			then
				id = ns.API.ResolveFromName(castName)
			end
			if ns.API and ns.API.NoteSelfBuff then
				ns.API.NoteSelfBuff(id)
			end
			if ns.API and ns.API.NoteSpellCast then
				ns.API.NoteSpellCast(id or spellID)
			end
			if ns.API and ns.API.NoteTotemCast then
				ns.API.NoteTotemCast(id)
			end
			if ns.NoteRotationCast then
				ns.NoteRotationCast(id or spellID)
			end
			if ns.API and ns.API.NoteTargetDebuff and ns.API.IsHarmful and id and ns.API.IsHarmful(id) then
				ns.API.NoteTargetDebuff(id)
			end
			if ns.NoteWeaponCast then
				ns.NoteWeaponCast(id or spellID, castName)
			end
			if ns.API and ns.API.WipeAuraScan then
				ns.API.WipeAuraScan("player")
				ns.API.WipeAuraScan("target")
			end
			requestTick()
		end
	elseif event == "PLAYER_TOTEM_UPDATE" then
		-- Payload: the totem slot. Out of combat the slot is readable.
		if ns.API and ns.API.NoteTotemSlot then
			ns.API.NoteTotemSlot(unit)
		end
		requestTick()
	elseif event == "UI_ERROR_MESSAGE" then
		-- "You must be behind your target" (Backstab / Shred wait a moment),
		-- "Your pet is dead" (Revive Pet instead of Call Pet).
		if ns.API and ns.API.NoteUIError and ns.API.NoteUIError(powerToken) then
			lastTickSig = nil
			requestTick()
		end
	elseif event == "UNIT_POWER_UPDATE" then
		if unit ~= "player" or powerToken ~= "COMBO_POINTS" then
			return
		end
		lastTickSig = nil
		requestTick()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		local slot = unit
		if slot == 16 or slot == 17 then
			local id = weaponItemId(slot)
			local prev = slot == 16 and ns.weaponItemMain or ns.weaponItemOff
			if id ~= prev then
				if slot == 16 then
					ns.weaponItemMain = id
				else
					ns.weaponItemOff = id
				end
				if ns.ClearWeaponMemory then
					ns.ClearWeaponMemory()
				end
			end
			if ns.API and ns.API.ClearWeaponTooltipCache then
				ns.API.ClearWeaponTooltipCache()
			end
		end
		requestTick()
	elseif event == "WEAPON_ENCHANT_CHANGED" then
		if ns.API and ns.API.ClearWeaponTooltipCache then
			ns.API.ClearWeaponTooltipCache()
		end
		if ns.NoteWeaponEnchantChanged then
			ns.NoteWeaponEnchantChanged()
		end
		requestTick()
	elseif
		event == "ACTIONBAR_SLOT_CHANGED"
		or event == "ACTIONBAR_PAGE_CHANGED"
		or event == "UPDATE_SHAPESHIFT_FORM"
	then
		scheduleBarFlush()
	end
end)
