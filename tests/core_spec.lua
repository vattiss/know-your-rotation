local wow = require("wow")
local H = require("helpers")

local function boot(class, setup)
	local w = wow.new()
	w:player(class or "WARRIOR")
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

describe("Core saved variables", function()
	it("copies the account settings once into the character settings", function()
		local w = wow.new()
		w:player("WARRIOR")
		local shared = { x = 1 }
		local account = { showPurge = false, nested = { a = shared, b = shared } }
		account.self = account
		w.env.KnowYourRotationDB = account
		local ns = w:load()
		H.eq(ns.db.showPurge, false)
		H.eq(ns.db.nested.a, ns.db.nested.b, "shared tables stay shared")
		H.eq(ns.db.self, ns.db.self.self, "cycles copied")
		H.eq(ns.db.charReady, 1)
		ns.db.showPurge = true
		w:fire("PLAYER_LOGIN")
		H.eq(ns.db.showPurge, true, "not copied again")
	end)

	it("keeps character values and fills the defaults", function()
		local w = wow.new()
		w:player("SHAMAN")
		w.env.KnowYourRotationDB = { showPurge = false }
		w.env.KnowYourRotationCharDB = {
			charReady = 1,
			listVersion = 3,
			apl = { x = 1 },
			profiles = { pve = { apl = { y = 1 } }, base = {}, custom = {} },
			profile = "custom",
			role = "damage",
			lastManualMode = "nope",
			combatMode = "nope",
		}
		local ns = w:load()
		w:fire("PLAYER_LOGIN")
		H.eq(ns.db.showPurge, true, "own setting, default filled")
		H.eq(ns.db.listVersion, 4)
		H.eq(ns.db.apl, nil, "old lists replaced")
		H.eq(ns.db.profiles.pve.apl, nil)
		H.eq(ns.db.profiles.base, nil)
		H.eq(ns.db.profile, "pve")
		H.eq(ns.db.role, "caster", "shaman damage is caster")
		H.eq(ns.db.combatMode, "auto")
		H.eq(ns.db.lastManualMode, "single")
		H.truthy(ns.db.profiles.pvp, "pvp profile created")
	end)
end)

describe("Core profiles", function()
	it("flushes, binds and switches profiles", function()
		local _, ns = boot()
		ns.db.role = "tank"
		ns.db.weaponBuffOff = "x"
		ns.FlushProfile()
		H.eq(ns.db.profiles.pve.role, "tank")
		local calls = {}
		ns.UI = {
			RefreshRoles = function()
				calls.roles = true
			end,
			RefreshModes = function()
				calls.modes = true
			end,
		}
		ns.RefreshOptions = function()
			calls.options = true
		end
		ns.SetProfile("nope")
		H.eq(ns.ProfileKey(), "pve")
		ns.SetProfile("pvp")
		H.eq(ns.ProfileKey(), "pvp")
		H.eq(ns.db.role, "damage", "pvp profile starts empty")
		H.truthy(calls.roles and calls.modes and calls.options)
		ns.db.profiles.pvp.combatMode = "bogus"
		ns.SetProfile("pvp")
		H.eq(ns.db.combatMode, "auto", "rebinding cleans the mode")
		ns.SetProfile("pve")
		H.eq(ns.db.role, "tank")
		ns.InvalidateAPLCache, ns.UI, ns.RefreshOptions, ns.Tick = nil, {}, nil, nil
		ns.SetProfile("pvp")
		local db = ns.db
		ns.db = nil
		H.eq(ns.ProfileKey(), "pve")
		ns.FlushProfile()
		ns.db = db
		ns.db.profiles = nil
		ns.FlushProfile()
		H.truthy(ns.db.profiles.pvp)
	end)

	it("picks automatic or fixed profiles", function()
		local _, ns = boot()
		H.eq(ns.ProfileChoice(), "auto")
		ns.SetProfileChoice("pvp")
		H.eq(ns.ProfileChoice(), "pvp")
		H.eq(ns.db.autoProfile, false)
		ns.SetProfileChoice("auto")
		H.eq(ns.ProfileChoice(), "auto")
		H.eq(ns.ProfileKey(), "pve", "open world, no enemy player")
		ns.RefreshOptions = function() end
		ns.SetProfileChoice("bogus")
	end)

	it("resets the active profile, with or without a confirmation popup", function()
		local w, ns = boot()
		ns.db.apl = { x = 1 }
		ns.db.autoEnemies = 6
		ns.UI = {
			RefreshRoles = function() end,
			RefreshModes = function() end,
		}
		ns.RefreshOptions = function() end
		ns.ConfirmResetAll()
		H.eq(w.popup.name, "KNOWYOURROTATION_RESET_ALL")
		w.env.StaticPopupDialogs.KNOWYOURROTATION_RESET_ALL.OnAccept()
		H.eq(ns.db.apl, nil)
		H.eq(ns.db.autoEnemies, 3)
		H.contains(w.printed, "|cff66ccffKnow Your Rotation|r: " .. ns.T("OPT_RESET_ALL_DONE"))
		w.env.StaticPopup_Show = nil
		ns.db.autoEnemies = 5
		ns.InvalidateAPLCache, ns.UI, ns.RefreshOptions, ns.Tick = nil, {}, nil, nil
		ns.ConfirmResetAll()
		H.eq(ns.db.autoEnemies, 3, "no popup: reset at once")
		w.env.YES, w.env.OKAY, w.env.NO, w.env.CANCEL = nil, nil, nil, nil
		w.env.StaticPopup_Show = function() end
		ns.ConfirmResetAll()
		H.eq(w.env.StaticPopupDialogs.KNOWYOURROTATION_RESET_ALL.button1, "OK")
	end)
end)

describe("Core roles and modes", function()
	it("normalizes roles per class", function()
		local w, ns = boot("HUNTER")
		H.eq(ns.NormalizeRole("damage"), "range")
		H.eq(ns.NormalizeRole("melee"), "melee")
		H.eq(ns.NormalizeRole(nil), "range")
		w.state.class = "DRUID"
		H.eq(ns.NormalizeRole("damage"), "hybrid")
		w.state.class = "SHAMAN"
		H.eq(ns.NormalizeRole("damage"), "caster")
		w.state.class = "MAGE"
		H.eq(ns.NormalizeRole("tank"), "damage")
	end)

	it("reads the class token defensively", function()
		local w, ns = boot("ROGUE")
		H.eq((ns.ClassToken()), "ROGUE")
		w.env.UnitClass = function()
			error("boom")
		end
		H.eq((ns.ClassToken()), "ROGUE", "from UnitClassBase")
		w.env.UnitClassBase = nil
		H.eq((ns.ClassToken()), nil)
		H.eq(ns.RoleAllowed("damage"), true, "unknown class: damage")
		H.eq(ns.NormalizeRole("tank"), "damage")
	end)

	it("sets roles and modes and refreshes", function()
		local _, ns = boot("WARRIOR")
		local refreshed = {}
		ns.UI = {
			RefreshRoles = function()
				refreshed.roles = true
			end,
			RefreshModes = function()
				refreshed.modes = true
			end,
			options = true,
		}
		ns.RefreshOptions = function()
			refreshed.options = true
		end
		ns.SetRole("tank")
		H.eq(ns.db.role, "tank")
		ns.RoleAllowed = function()
			return false
		end
		ns.SetRole("damage")
		H.eq(ns.db.role, "tank", "refused")
		ns.SetRoleChoice("tank")
		H.eq(ns.RoleChoice(), "tank")
		ns.SetRoleChoice("auto")
		H.eq(ns.RoleChoice(), "auto")
		ns.SetCombatMode("aoe")
		local flush, refresh = ns.FlushProfile, ns.RefreshOptions
		ns.SyncAutoRole, ns.FlushProfile, ns.RefreshOptions = nil, nil, nil
		ns.SetRoleChoice("auto")
		ns.FlushProfile, ns.RefreshOptions = flush, refresh
		ns.db.roleAuto = false
		ns.db.role = nil
		H.eq(ns.RoleChoice(), "damage")
		ns.SetCombatMode("aoe")
		H.eq(ns.db.combatMode, "aoe")
		H.eq(ns.db.lastManualMode, "aoe")
		ns.SetCombatMode("bogus")
		H.eq(ns.db.combatMode, "single")
		ns.SetCombatMode("auto")
		H.eq(ns.db.lastManualMode, "single")
		ns.InvalidateAPLCache = nil
		ns.UI = {}
		ns.SetCombatMode("auto")
		ns.SetRole("tank")
		H.truthy(refreshed.roles and refreshed.modes and refreshed.options)
	end)
end)

describe("Core feature switches and sounds", function()
	it("clears the glows of switched-off features", function()
		local _, ns = boot()
		local cleared = {}
		for _, name in ipairs({
			"GlowClear",
			"GlowClearDef",
			"GlowClearKick",
			"GlowClearPurge",
			"GlowClearCleanse",
			"GlowClearWeapon",
		}) do
			ns[name] = function()
				cleared[name] = true
			end
		end
		for _, key in ipairs({
			"showRotation",
			"showDefense",
			"showInterrupt",
			"showPurge",
			"showCleanse",
			"showWeapon",
		}) do
			ns.db[key] = false
		end
		ns.ApplyFeatureFlags()
		H.eq(cleared.GlowClear and cleared.GlowClearDef and cleared.GlowClearKick and cleared.GlowClearWeapon, true)
		ns.GlowClear, ns.GlowClearDef, ns.Tick = nil, nil, nil
		ns.ApplyFeatureFlags()
	end)

	it("cycles and plays alert sounds", function()
		local w, ns = boot()
		H.eq(ns.SoundLabelKey("ping"), "SND_PING")
		H.eq(ns.SoundLabelKey("bogus"), "SND_NONE")
		H.eq(ns.NextSound("none"), "ping")
		H.eq(ns.NextSound("click"), "none")
		H.eq(ns.NextSound("bogus"), "none")
		ns.PlayAlertSound("none")
		H.eq(#w.sounds, 0)
		ns.PlayAlertSound("ping")
		H.eq(w.sounds[1], "MAP_PING")
		w.env.SOUNDKIT = nil
		ns.PlayAlertSound("ping")
		H.eq(w.sounds[2], 3175)
	end)
end)

describe("Core automatic profile", function()
	it("uses PvP in battlegrounds, arenas and against enemy players", function()
		local w, ns = boot()
		w.state.instance = { "Warsong Gulch", "pvp" }
		ns.ApplyAutoProfile()
		H.eq(ns.ProfileKey(), "pvp")
		w.state.instance = { "Deadmines", "party" }
		w.state.units.player.combat = true
		ns.ApplyAutoProfile()
		H.eq(ns.ProfileKey(), "pvp", "not back to PvE in combat")
		w.state.units.player.combat = false
		ns.ApplyAutoProfile()
		H.eq(ns.ProfileKey(), "pve")
		w.state.instance = { "Elwynn", "none" }
		w:target({ isPlayer = true })
		ns.ApplyAutoProfile()
		H.eq(ns.ProfileKey(), "pvp", "enemy player")
		w.env.GetInstanceInfo = function()
			error("boom")
		end
		ns.ApplyAutoProfile()
		w.env.GetInstanceInfo = nil
		ns.ApplyAutoProfile()
		ns.db.autoProfile = false
		ns.ApplyAutoProfile()
	end)
end)

describe("Core tick", function()
	it("does nothing before boot and hides while idle or muted", function()
		local w = wow.new()
		w:player("WARRIOR")
		local ns = w:load()
		ns.Tick()
		w:fire("PLAYER_LOGIN")
		ns.db.muted = true
		local glowed
		ns.GlowSpell = function(id)
			glowed = id
		end
		ns.InvalidateTick()
		ns.Tick()
		H.eq(glowed, nil)
	end)

	it("glows the queue and fades it under a hidden finisher", function()
		local w, ns = boot()
		local calls = {}
		ns.BuildQueue = function()
			ns.queueGlowOk = true
			return { 11, 12, 13 }
		end
		ns.BuildHiddenExecute = function()
			return 20, 20
		end
		ns.GlowSpell = function(id)
			calls.spell = id
		end
		ns.GlowFadeForFinisher = function(id, threshold)
			calls.fade = { id, threshold }
		end
		ns.InvalidateTick()
		ns.Tick()
		H.eq(calls.spell, 11)
		H.same(calls.fade, { 11, 20 })
		calls.spell = nil
		ns.Tick()
		H.eq(calls.spell, nil, "same signature: no repaint")
		local _ = w
	end)

	it("alerts once for interrupts, cleanses, weapons and pet reminders", function()
		local w, ns = boot("HUNTER")
		ns.BuildInterrupt = function()
			return 6552
		end
		ns.BuildCleanse = function()
			return 4987
		end
		ns.BuildWeapon = function()
			return 8017, 0, true
		end
		ns.API.CombatNotice = function()
			return "NOTICE_CALL_PET"
		end
		w.spell(6552, { name = "Pummel" })
		ns.Tick()
		ns.Tick()
		H.eq(#w.sounds, 3, "kick, cleanse and weapon sound once each")
		H.contains(w.messages, ns.T("NOTICE_CALL_PET"))
		ns.BuildWeapon = function()
			return 8017, 0, false
		end
		ns.Tick()
		ns.db = nil
		local ok = pcall(ns.Tick)
		H.eq(ok, false, "no settings: the tick needs them")
	end)

	it("skips optional glow hooks that are missing", function()
		local _, ns = boot()
		for _, name in ipairs({
			"GlowHiddenHeal",
			"GlowHiddenDefense",
			"GlowHiddenExecute",
			"GlowHiddenPet",
			"GlowHiddenMana",
			"GlowSpell",
			"GlowDef",
			"GlowInterrupt",
			"GlowPurge",
			"GlowCleanse",
			"GlowWeapon",
			"GlowFadeForFinisher",
			"SyncAutoRole",
		}) do
			ns[name] = nil
		end
		ns.InvalidateTick()
		ns.Tick()
	end)
end)

describe("Core events", function()
	it("greets on login only, and listens to the right units", function()
		local w = wow.new()
		w:player("WARRIOR")
		local ns = w:load()
		w:fire("PLAYER_LOGIN")
		local greetings = #w.printed
		H.eq(greetings, 2)
		w:fire("PLAYER_ENTERING_WORLD", false, false)
		H.eq(#w.printed, greetings, "no second greeting")
		local ticks = 0
		ns.API.WipeAuraScan = function()
			ticks = ticks + 1
		end
		w:fire("UNIT_AURA", "player")
		w:fire("UNIT_AURA", "party1")
		w:fire("UNIT_AURA", "nameplate3")
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 1)
		H.eq(ticks, 1, "only the registered units")
		w:fire("NOT_AN_EVENT")
	end)

	it("reacts to learning, bars, logout and the login sequence", function()
		local w, ns = boot()
		local flushed, fetched = 0, 0
		ns.API.InvalidateSpells = function()
			flushed = flushed + 1
		end
		ns.GlowFetch = function()
			fetched = fetched + 1
		end
		w:fire("PLAYER_LEVEL_UP")
		w:fire("LEARNED_SPELL_IN_SKILL_LINE")
		w:advance(1)
		H.truthy(flushed >= 1, "learn spam flushed after 0.5 s")
		w:fire("SPELL_PUSHED_TO_ACTIONBAR")
		w:fire("ACTIONBAR_SLOT_CHANGED")
		w:advance(1)
		H.truthy(fetched >= 1)
		w:fire("PLAYER_ENTERING_WORLD", false, true)
		w:fire("PLAYER_LOGOUT")
		w:fire("PLAYER_LOGOUT")
	end)

	it("handles login without timers or a failing options page", function()
		local w = wow.new()
		w:player("WARRIOR")
		w.env.C_Timer.After = nil
		local ns = w:load()
		ns.RegisterOptions = function()
			error("options broke")
		end
		w:fire("PLAYER_LOGIN")
		H.truthy(ns.booted)
		H.truthy(#w.printed >= 1)
		w:fire("PLAYER_LEVEL_UP")
		w:fire("SPELL_PUSHED_TO_ACTIONBAR")
		w:fire("UNIT_INVENTORY_CHANGED", "player")
	end)

	it("resets per-target state and reacts to zone, death and combat end", function()
		local w, ns = boot()
		ns.API.ResetComboEstimate = function()
			ns.resetCombo = true
		end
		w:fire("PLAYER_TARGET_CHANGED")
		H.truthy(ns.resetCombo)
		H.eq(ns.API.castTarget, false)
		w:fire("PLAYER_REGEN_ENABLED")
		w:fire("ZONE_CHANGED_NEW_AREA")
		local cleared
		ns.API.ClearTotems = function()
			cleared = true
		end
		w:fire("PLAYER_DEAD")
		H.truthy(cleared)
		w:fire("PLAYER_ALIVE")
		w:advance(0)
	end)

	it("tracks auras, casts, totems, errors, power and gear", function()
		local w, ns = boot("ROGUE")
		w.spell(1752, { name = "Sinister Strike", harmful = true })
		w:fire("UNIT_AURA", "player")
		w:fire("UNIT_AURA", "party1")
		w:fire("UNIT_INVENTORY_CHANGED", "party1")
		w:fire("UNIT_INVENTORY_CHANGED", "player")
		w.state.units.player.casting = { name = "Sinister Strike" }
		w:fire("UNIT_SPELLCAST_START", "player")
		w:fire("UNIT_SPELLCAST_START", "target")
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", wow.SECRET)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1752)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 1752)
		w:fire("PLAYER_TOTEM_UPDATE", 1)
		w:fire("UI_ERROR_MESSAGE", 51, "You must be behind your target.")
		w:fire("UI_ERROR_MESSAGE", 51, "Out of range.")
		w:fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
		w:fire("UNIT_POWER_UPDATE", "player", "ENERGY")
		w:fire("UNIT_POWER_UPDATE", "target", "COMBO_POINTS")
		local cleared = 0
		ns.ClearWeaponMemory = function()
			cleared = cleared + 1
		end
		w.state.items = { [16] = 100, [17] = 200 }
		w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
		w:fire("PLAYER_EQUIPMENT_CHANGED", 17)
		w:fire("PLAYER_EQUIPMENT_CHANGED", 17)
		w:fire("PLAYER_EQUIPMENT_CHANGED", 5)
		H.eq(cleared, 2, "a new weapon in each hand")
		w.env.GetInventoryItemID = nil
		w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
		w:fire("WEAPON_ENCHANT_CHANGED")
		w:fire("UPDATE_SHAPESHIFT_FORM")
		w:advance(1)
	end)
end)

describe("Core.WithProfile", function()
	it("runs a function on another profile's lists and puts everything back", function()
		local _, ns = boot("ROGUE")
		ns.SaveAPL({ { key = "Eviscerate", on = 1 } }, nil, "damage", "single")
		ns.FlushProfile()
		local pveLists = ns.db.apl
		local builds = 0
		ns.BuildQueue = function()
			builds = builds + 1
			return {}
		end
		local first, second = ns.WithProfile("pvp", function(a, b)
			H.eq(ns.ProfileKey(), "pve", "the profile in use does not change")
			H.eq(ns.db.apl, nil, "the PvP lists start empty")
			ns.SaveAPL({ { key = "Garrote", on = 1 } }, nil, "damage", "single")
			H.eq(ns.GetAPL(nil, "damage", "single")[1].key, "Garrote")
			return a + 1, b
		end, 1, "x")
		H.same({ first, second }, { 2, "x" })
		H.eq(builds, 0, "the glows do not tick while the other lists are bound")
		H.eq(ns.db.apl, pveLists, "the PvE lists are bound again")
		H.eq(ns.GetAPL(nil, "damage", "single")[1].key, "Eviscerate")
		H.eq(ns.db.profiles.pvp.apl.ROGUE.damage.single[1].key, "Garrote", "saved into the PvP profile")
	end)

	it("runs on the profile in use or an unknown key directly", function()
		local _, ns = boot("ROGUE")
		H.eq(
			ns.WithProfile("pve", function(x)
				return x
			end, 5),
			5
		)
		H.eq(
			ns.WithProfile("nope", function(x)
				return x
			end, 6),
			6
		)
	end)

	it("restores the lists when the function fails", function()
		local _, ns = boot("ROGUE")
		ns.SaveAPL({ { key = "Eviscerate", on = 1 } }, nil, "damage", "single")
		ns.FlushProfile()
		local pveLists = ns.db.apl
		local ok, err = pcall(ns.WithProfile, "pvp", function()
			error("broken editor")
		end)
		H.eq(ok, false)
		H.truthy(err:find("broken editor", 1, true))
		H.eq(ns.db.apl, pveLists)
		ns.Tick()
	end)
end)
