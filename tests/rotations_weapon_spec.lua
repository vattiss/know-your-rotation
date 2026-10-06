local wow = require("wow")
local H = require("helpers")

local function boot(class, setup)
	local w = wow.new()
	w:player(class)
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

local function shaman(spells)
	return boot("SHAMAN", function(w)
		for id, name in pairs(spells or { [8017] = "Rockbiter Weapon" }) do
			w.spell(id, { name = name })
		end
	end)
end

describe("Weapon buff choice", function()
	it("lists the class choices and the learned rank", function()
		local w, ns = shaman({ [8017] = "Rockbiter Weapon", [8018] = "Rockbiter Weapon" })
		H.eq(#ns.WeaponChoices(), 4)
		local entry, id = ns.AutoWeaponBuff()
		H.eq(entry.key, "Rockbiter")
		H.eq(id, 8018, "highest learned rank")
		H.eq(ns.WeaponBuffLearned(entry), true)
		H.eq(ns.WeaponBuffLearned(nil), false)
		w.state.class = "MAGE"
		H.same(ns.WeaponChoices(), {})
		H.eq(ns.SelectedWeaponBuff(), nil, "no choices")
		ns.ClassToken = nil
		H.same(ns.WeaponChoices(), {})
	end)

	it("orders by role and honours the player's pick", function()
		local _, ns = shaman({
			[8017] = "Rockbiter Weapon",
			[8024] = "Flametongue Weapon",
			[8232] = "Windfury Weapon",
		})
		ns.db.role = "melee"
		H.eq(ns.AutoWeaponBuff().key, "Windfury")
		ns.db.role = "caster"
		H.eq(ns.AutoWeaponBuff().key, "Flametongue")
		ns.db.weaponBuff = "Rockbiter"
		H.eq(ns.SelectedWeaponBuff().key, "Rockbiter")
		ns.db.weaponBuff = "Frostbrand"
		H.eq(ns.SelectedWeaponBuff().key, "Flametongue", "pick not learned: automatic")
		ns.db.weaponBuff = "auto"
		H.eq(ns.SelectedWeaponBuff().key, "Flametongue")
	end)

	it("falls back to any learned buff without a priority list", function()
		local _, ns = boot("WARLOCK", function(w)
			w.spell(2362, { name = "Create Spellstone" })
		end)
		H.eq(ns.AutoWeaponBuff().key, "Spellstone")
		H.eq(ns.AutoWeaponBuff(true), ns.AutoWeaponBuff(), "no off-hand list")
		H.eq(ns.WeaponHasOffhandChoice(), false)
	end)

	it("returns nothing while nothing is learned", function()
		local _, ns = shaman({})
		H.eq(ns.AutoWeaponBuff(), nil)
		H.eq(ns.BuildWeapon(), nil)
		H.eq(ns.weaponNeedLast, nil)
	end)
end)

describe("Weapon dual wield (rogue)", function()
	it("needs a weapon in the off hand", function()
		local w, ns = boot("ROGUE")
		H.eq(ns.WeaponHasOffhandChoice(), true)
		H.eq(ns.WeaponIsDual(), false, "nothing equipped")
		w.state.items = { [17] = 123 }
		w.state.itemInfo = { [123] = { classID = 2 } }
		H.eq(ns.WeaponIsDual(), true)
		w.state.itemInfo[123].classID = 4
		H.eq(ns.WeaponIsDual(), false, "a shield")
		w.env.C_Item.GetItemInfoInstant = nil
		H.eq(ns.WeaponIsDual(), true, "unknown item class")
		w.env.GetInventoryItemID = nil
		H.eq(ns.WeaponIsDual(), false)
		w.state.class = "SHAMAN"
		H.eq(ns.WeaponIsDual(), false)
	end)

	it("suggests the first hand that is missing or about to run out", function()
		local w, ns = boot("ROGUE", function(w)
			w.spell(8679, { name = "Instant Poison" })
			w.spell(2823, { name = "Deadly Poison" })
			w.state.items = { [17] = 123 }
			w.state.itemInfo = { [123] = { classID = 2 } }
		end)
		w.state.enchants[16] = { enchantID = 323, remainingTimeMs = 600000 }
		w.state.enchants[17] = { enchantID = 7, remainingTimeMs = 600000 }
		local id, remain, need = ns.BuildWeapon()
		H.same({ id, remain, need }, { 8679, 0, false }, "both up")
		w.state.enchants[16].remainingTimeMs = 20000
		H.same({ ns.BuildWeapon() }, { 8679, 20, true }, "main hand runs out")
		w.state.enchants[16].remainingTimeMs = 600000
		w.state.enchants[17] = nil
		H.same({ ns.BuildWeapon() }, { 8679, 0, false }, "off hand missing: wait 1.5 s")
		w:clock(2)
		H.same({ ns.BuildWeapon() }, { 2823, 0, true })
		w.state.enchants[17] = { enchantID = 323, remainingTimeMs = 600000 }
		H.same({ ns.BuildWeapon() }, { 2823, 0, true }, "still not the right poison")
		w.state.enchants[16].remainingTimeMs = 0
		w.state.enchants[17] = { enchantID = 7, remainingTimeMs = 0 }
		H.same({ ns.BuildWeapon() }, { 8679, 0, false }, "no expiry known")
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			return "odd"
		end
		w.env.GetWeaponEnchantInfo = nil
		H.same({ ns.BuildWeapon() }, { 8679, 0, false }, "client cannot say: quiet")
		ns.weaponGrace = w.state.time + 5
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			return nil
		end
		H.same({ ns.BuildWeapon() }, { 8679, 0, false }, "grace after a cast")
		w.state.class = "ROGUE"
		ns.db.weaponBuff = nil
		w.state.spells[8679].known = false
		w.state.spells[2823].known = false
		ns.API.InvalidateSpells(true)
		H.same({ ns.BuildWeapon() }, { nil, 0, false }, "nothing learned")
	end)
end)

describe("Weapon single hand", function()
	local function rockbiter()
		local w, ns = shaman()
		return w, ns
	end

	it("reports the buff up, about to expire, or missing after a moment", function()
		local w, ns = rockbiter()
		w.state.enchants[16] = { enchantID = 1, remainingTimeMs = 1800000 }
		H.same({ ns.BuildWeapon() }, { 8017, 1800, false })
		w.state.enchants[16].remainingTimeMs = 25000
		H.same({ ns.BuildWeapon() }, { 8017, 25, true })
		w.state.enchants[16].remainingTimeMs = 1800000
		ns.BuildWeapon()
		w.state.enchants[16] = nil
		local id, left, need = ns.BuildWeapon()
		H.eq(id, 8017)
		H.eq(need, false, "seen recently: trust the memory for a moment")
		H.truthy(left > 0)
		w:clock(2)
		H.same({ ns.BuildWeapon() }, { 8017, 0, true }, "held 1.5 s: missing")
		ns.weaponMissingSince = nil
		H.same({ ns.BuildWeapon() }, { 8017, 0, true }, "nothing seen: at once")
	end)

	it("reads an aura, the tooltip, or another class's enchant", function()
		local w, ns = rockbiter()
		w.aura("player", { name = "Rockbiter Weapon", spellId = 8017, expirationTime = w.state.time + 100 })
		H.same({ ns.BuildWeapon() }, { 8017, 100, false }, "aura")
		w.state.auras.player = {}
		ns.API.WipeAuraScans()
		w.state.enchants[16] = { enchantID = 5, remainingTimeMs = 500000 }
		w:clock(3601)
		H.eq(select(3, ns.BuildWeapon()), true, "Flametongue on the weapon: other")
		w.state.enchants[16] = nil
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			error("boom")
		end
		w.env.GetWeaponEnchantInfo = nil
		w.state.tooltips = { [16] = { { leftText = "Rockbiter 3" } } }
		ns.API.ClearWeaponTooltipCache()
		H.same({ ns.BuildWeapon() }, { 8017, 9999, false }, "tooltip")
		w.state.tooltips = nil
		ns.API.ClearWeaponTooltipCache()
		local _, _, need = ns.BuildWeapon()
		H.eq(need, false, "unknown: inside the remembered hour")
	end)

	it("handles off-hand states with an unknown main hand", function()
		local w, ns = rockbiter()
		local answers = {}
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function(slot)
			local a = answers[slot]
			if a == "error" then
				error("boom")
			end
			return a
		end
		w.env.GetWeaponEnchantInfo = nil
		answers[16] = "error"
		answers[17] = { enchantID = 5, remainingTimeMs = 1000 }
		ns.ClearWeaponMemory()
		H.eq(select(3, ns.BuildWeapon()), true, "unknown main, other off: nothing proves the buff")
		answers[16] = { enchantID = 5, remainingTimeMs = 1000 }
		answers[17] = nil
		w:clock(2)
		H.eq(select(3, ns.BuildWeapon()), true, "other main, empty off")
		answers[17] = "error"
		w:clock(2)
		H.eq(select(3, ns.BuildWeapon()), true, "other main, unknown off: no memory left")
	end)

	it("remembers casts and enchant changes", function()
		local w, ns = shaman({ [8017] = "Rockbiter Weapon", [16314] = "Rockbiter Weapon" })
		ns.weaponNeedLast = nil
		ns.ClearWeaponMemory()
		ns.NoteWeaponCast(nil, nil)
		ns.NoteWeaponCast(wow.SECRET, "nothing")
		H.eq(ns.weaponGrace, 0)
		ns.NoteWeaponCast(8017)
		H.eq(ns.weaponGrace, w.state.time + 3)
		w:clock(5)
		ns.NoteWeaponCast(99999, "Rockbiter Weapon")
		H.eq(ns.weaponCastAt, w.state.time, "matched by spell name")
		ns.NoteWeaponCast(99999, "Something Rockbiter")
		ns.weaponNeedLast = true
		ns.NoteWeaponCast(99999, "Unrelated")
		H.eq(ns.weaponCastAt, w.state.time, "while needed: any cast counts")
		ns.weaponNeedLast = nil
		ns.IsWeaponBuff = function()
			return true
		end
		ns.NoteWeaponCast(424242)
		ns.WEAPON_BUFF_IDS = nil
		ns.NoteWeaponCast(424242)
		ns.ClearWeaponMemory()
		H.eq(ns.weaponGrace, 0)
		ns.weaponNeedLast = true
		ns.NoteWeaponEnchantChanged()
		H.eq(ns.weaponSeenUntil, w.state.time + 3600)
		ns.weaponNeedLast = nil
		ns.NoteWeaponEnchantChanged()
		H.eq(ns.weaponRecheckDrop, nil, "inside the cast grace")
		w:clock(10)
		ns.NoteWeaponEnchantChanged()
		H.eq(ns.weaponRecheckDrop, true)
		w.state.enchants[16] = nil
		H.same({ ns.BuildWeapon() }, { 16314, 0, true }, "a drop we did not cause (highest rank)")
		w.state.class = "MAGE"
		ns.NoteWeaponEnchantChanged()
		ns.NoteWeaponCast(nil, "Rockbiter Weapon")
	end)

	it("treats both hands with another imbue as missing, and waits inside a grace", function()
		local w, ns = shaman()
		w.state.enchants[16] = { enchantID = 5, remainingTimeMs = 500000 }
		w.state.enchants[17] = { enchantID = 5, remainingTimeMs = 500000 }
		ns.ClearWeaponMemory()
		H.eq(select(3, ns.BuildWeapon()), true, "Flametongue on both: Rockbiter missing")
		ns.weaponMissingSince = nil
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			return "odd"
		end
		w.env.GetWeaponEnchantInfo = nil
		ns.weaponGrace = w.state.time + 2
		H.same({ ns.BuildWeapon() }, { 8017, 0, false }, "unknown state inside the grace")
	end)

	it("matches tooltips through English hint names", function()
		local w, ns = shaman()
		ns.SPELL_NAME_HINT[8017] = "Stone Edge"
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			return "odd"
		end
		w.env.GetWeaponEnchantInfo = nil
		w.state.tooltips = { [16] = { { leftText = "Stone Edge" } } }
		ns.WEAPON_BUFFS.SHAMAN[3].match = nil
		ns.InvalidateBuffCaches()
		ns.API.ClearWeaponTooltipCache()
		H.same({ ns.BuildWeapon() }, { 8017, 9999, false })
	end)

	it("matches spell names of every rank, and empty names never", function()
		local w, ns = shaman({ [8017] = "Rockbiter Weapon", [8018] = "Rockbiter II" })
		ns.WEAPON_BUFFS.SHAMAN[3].match = nil
		ns.NoteWeaponCast(nil, "rockbiter ii")
		H.eq(ns.weaponCastAt, w.state.time)
		ns.ClearWeaponMemory()
		ns.weaponNeedLast = nil
		ns.NoteWeaponCast(nil, "")
		H.eq(ns.weaponCastAt, 0)
	end)
end)
