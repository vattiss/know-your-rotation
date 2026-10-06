local wow = require("wow")
local H = require("helpers")

local CORE = { "Locale.lua", "API.lua", "Data.lua" }

local function api(class, setup)
	local w = wow.new()
	w:player(class)
	if setup then
		setup(w)
	end
	local ns = w:load(CORE)
	ns.ClassToken = function()
		return w.state.class
	end
	ns.db = { roleAuto = true }
	return w, ns, ns.API
end

local function talents(w, list)
	w.state.talents = {}
	for i, t in ipairs(list) do
		w.state.talents[i] = { name = t[1], points = t[2] }
	end
end

describe("API.MainTree", function()
	it("names the tree with the most points, cached for 3 s", function()
		local w, _, A = api("MAGE")
		H.eq(A.MainTree(), nil, "no data")
		talents(w, { { "Arcane", 2 }, { "Fire", 11 }, { "Frost", 5 } })
		H.eq(A.MainTree(), nil, "cached miss")
		w:advance(4)
		H.eq(A.MainTree(), "fire")
		w.state.talents = { { name = "Frost", points = 20 } }
		H.eq(A.MainTree(), "fire", "cached")
		w:advance(4)
		H.eq(A.MainTree(), "frost")
		w.state.talents = { { name = wow.SECRET_STRING, points = 5 } }
		w:advance(4)
		H.eq(A.MainTree(), nil, "hidden name")
		w.env.C_SpecializationInfo.GetSpecializationInfo = function()
			return 0
		end
		w:advance(4)
		H.eq(A.MainTree(), nil, "spec ID 0: no talents")
		w.env.C_SpecializationInfo = nil
		w:advance(4)
		H.eq(A.MainTree(), nil)
	end)
end)

describe("ns.SyncAutoRole", function()
	it("picks tank and heal trees, else damage", function()
		local w, ns, A = api("WARRIOR")
		ns.SyncAutoRole()
		H.eq(ns.db.role, nil, "no talents yet: keep the role")
		talents(w, { { "Arms", 3 }, { "Fury", 1 }, { "Protection", 9 } })
		w:advance(4)
		local refreshed = {}
		ns.InvalidateAPLCache = function()
			refreshed.cache = true
		end
		ns.UI = {
			RefreshRoles = function()
				refreshed.ui = true
			end,
		}
		ns.InvalidateTick = function()
			refreshed.tick = true
		end
		ns.SyncAutoRole()
		H.eq(ns.db.role, "tank")
		H.truthy(refreshed.cache and refreshed.ui and refreshed.tick)
		refreshed = {}
		ns.SyncAutoRole()
		H.falsy(refreshed.cache, "unchanged: no refresh")
		w.state.class = "PRIEST"
		talents(w, { { "Discipline", 1 }, { "Holy", 10 } })
		w:advance(4)
		ns.SyncAutoRole()
		H.eq(ns.db.role, "heal")
		talents(w, { { "Shadow", 10 } })
		w:advance(4)
		ns.InvalidateAPLCache, ns.UI, ns.InvalidateTick = nil, nil, nil
		ns.NormalizeRole = function(role)
			return role
		end
		ns.SyncAutoRole()
		H.eq(ns.db.role, "damage")
		local _ = A
	end)

	it("uses melee range for hunters and damage shamans", function()
		local w, ns, A = api("HUNTER")
		local melee = false
		A.TargetInMelee = function()
			return melee
		end
		ns.SyncAutoRole()
		H.eq(ns.db.role, nil, "hunter without a target")
		w:target()
		ns.SyncAutoRole()
		H.eq(ns.db.role, "range")
		melee = true
		ns.SyncAutoRole()
		H.eq(ns.db.role, "melee")
		w.state.class = "SHAMAN"
		w.state.units.target = nil
		ns.db.role = "damage"
		ns.SyncAutoRole()
		H.eq(ns.db.role, "damage", "no talents, no target: keep")
		w:target()
		ns.SyncAutoRole()
		H.eq(ns.db.role, "melee")
		melee = false
		ns.SyncAutoRole()
		H.eq(ns.db.role, "caster")
		talents(w, { { "Elemental", 5 } })
		w:advance(4)
		w.state.units.target = nil
		ns.SyncAutoRole()
		H.eq(ns.db.role, "caster", "keep without a target")
		ns.db.role = "heal"
		talents(w, {})
		w:advance(4)
		ns.SyncAutoRole()
		H.eq(ns.db.role, "heal", "no talent data: a healer stays a healer")
		talents(w, { { "Enhancement", 5 } })
		w:advance(4)
		ns.SyncAutoRole()
		H.eq(ns.db.role, "caster", "talented out of heal, no target")
	end)

	it("keeps druids hybrid and leaves other classes alone", function()
		local w, ns = api("DRUID")
		talents(w, { { "Feral Combat", 8 } })
		ns.SyncAutoRole()
		H.eq(ns.db.role, "hybrid")
		w.state.class = "ROGUE"
		ns.db.role = "damage"
		ns.SyncAutoRole()
		H.eq(ns.db.role, "damage")
		ns.db.roleAuto = false
		ns.SyncAutoRole()
		ns.db = nil
		ns.SyncAutoRole()
	end)
end)

describe("API weapon buff auras and odd aura IDs", function()
	it("finds a weapon buff aura by any rank", function()
		local w, _, A = api("SHAMAN", function(w)
			w.spell(8017, { name = "Rockbiter Weapon" })
			w.spell(8018, { name = "Rockbiter Weapon II" })
		end)
		H.same({ A.HasWeaponBuff(nil) }, { false, 0 })
		H.same({ A.HasWeaponBuff({ id = 8017, ranks = { 8018 } }) }, { false, 0 })
		w.aura("player", { name = "Rockbiter Weapon II", spellId = 8018, expirationTime = w.state.time + 60 })
		H.same({ A.HasWeaponBuff({ id = 8017, ranks = { 8018 } }) }, { true, 60 })
		H.same({ A.HasWeaponBuff({ id = 8018 }) }, { true, 60 })
	end)

	it("matches a scanned aura by the resolved ID when its name differs", function()
		local w, _, A = api("MAGE", function(w)
			w.spell(50, { name = "Old Armor", override = 51 })
			w.spell(51, { name = "New Armor" })
		end)
		w.aura("player", { name = "Shown Differently", spellId = 51 })
		w.env.C_UnitAuras.GetPlayerAuraBySpellID = nil
		H.eq((A.FindAura(50, "player", "HELPFUL")), true)
	end)
end)
