local wow = require("wow")
local H = require("helpers")

local function boot(class)
	local w = wow.new()
	w:player(class or "ROGUE")
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

describe("Share.ExportProfile", function()
	it("writes the header, settings, lists and drops", function()
		local _, ns = boot("ROGUE")
		ns.FlushProfile = nil
		ns.db.role = "damage"
		ns.db.combatMode = "aoe"
		ns.db.lastManualMode = "aoe"
		ns.db.autoEnemies = 4
		ns.db.weaponBuff = "Instant:Poison"
		ns.db.weaponBuffOff = nil
		ns.db.apl = {
			ROGUE = {
				damage = {
					single = {
						{ key = "Eviscerate", on = 1, hold = 2 },
						{ key = "Custom1", on = 0, custom = true, id = 1752 },
						"junk",
					},
					aoe = { { key = "BladeFlurry", on = 1 } },
					weird = { { key = "Skip", on = 1 } },
					[1] = "bad",
				},
				flat = { { key = "Gouge", on = 1 } },
				[2] = {},
			},
			[3] = {},
		}
		ns.db.def = {
			ROGUE = { damage = { { key = "Evasion", on = 0 } }, empty = {}, [1] = {} },
			[2] = {},
		}
		ns.db.aplDrop = { ROGUE = { damage = { single = { Rupture = true, Off = false }, aoe = {} }, [1] = {} } }
		ns.db.defDrop = { ROGUE = { damage = { Sprint = true }, none = {} } }
		local text = ns.ExportProfile()
		H.truthy(text:find("^WFR1\n"), "header")
		H.truthy(text:find("\nC=ROGUE\n", 1, true), "class")
		H.truthy(text:find("\nW=Instant_Poison\n", 1, true), "escaped weapon buff")
		H.truthy(text:find("\nO=\n", 1, true), "empty off-hand buff")
		H.truthy(text:find("APL:ROGUE.damage.single=Eviscerate:1::2,Custom1:0:1752", 1, true), "single list")
		H.truthy(text:find("APL:ROGUE.damage.aoe=BladeFlurry:1", 1, true), "aoe list")
		H.truthy(text:find("APL:ROGUE.flat.single=Gouge:1", 1, true), "flat list as single")
		H.falsy(text:find("weird", 1, true), "unknown mode skipped")
		H.truthy(text:find("DEF:ROGUE.damage=Evasion:0", 1, true), "defense")
		H.truthy(text:find("DRP:ROGUE.damage.single=Rupture", 1, true), "drops")
		H.falsy(text:find("Off", 1, true), "false drop skipped")
		H.truthy(text:find("DDR:ROGUE.damage=Sprint", 1, true), "defense drops")
	end)

	it("handles missing tables and default values", function()
		local _, ns = boot("ROGUE")
		ns.db.apl, ns.db.def, ns.db.aplDrop, ns.db.defDrop = nil, nil, nil, nil
		ns.db.role, ns.db.combatMode, ns.db.lastManualMode, ns.db.autoEnemies = nil, nil, nil, "x"
		local ClassToken, ProfileKey = ns.ClassToken, ns.ProfileKey
		ns.ClassToken, ns.ProfileKey, ns.FlushProfile = nil, nil, nil
		local text = ns.ExportProfile()
		ns.ClassToken, ns.ProfileKey = ClassToken, ProfileKey
		H.truthy(text:find("\nC=\nP=pve\nR=damage\nM=auto\nL=single\nA=3\n", 1, true), text)
	end)

	it("skips odd rows and drop tables", function()
		local _, ns = boot("ROGUE")
		ns.db.apl = { ROGUE = { damage = { single = "nope", aoe = { { key = "A", on = 1 } } } } }
		ns.db.aplDrop = { ROGUE = { damage = { single = "nope" } } }
		ns.db.defDrop = { ROGUE = { damage = "nope" } }
		local text = ns.ExportProfile()
		H.truthy(text:find("APL:ROGUE.damage.aoe=A:1", 1, true))
	end)
end)

describe("Share.ImportProfile", function()
	it("rejects non-text and a wrong header", function()
		local _, ns = boot()
		H.same({ ns.ImportProfile(nil) }, { false, "OPT_IMPORT_BAD" })
		H.same({ ns.ImportProfile("hello") }, { false, "OPT_IMPORT_BAD" })
	end)

	it("rejects another class", function()
		local _, ns = boot("ROGUE")
		H.same({ ns.ImportProfile("WFR1\nC=MAGE") }, { false, "OPT_IMPORT_CLASS", "MAGE" })
	end)

	it("round-trips an export", function()
		local _, ns = boot("ROGUE")
		ns.db.apl = { ROGUE = { damage = { single = { { key = "Eviscerate", on = 0, hold = 3 } } } } }
		ns.db.def = { ROGUE = { damage = { { key = "Evasion", on = 1 } } } }
		ns.db.aplDrop = { ROGUE = { damage = { aoe = { Rupture = true } } } }
		ns.db.defDrop = { ROGUE = { damage = { Sprint = true } } }
		ns.db.weaponBuff = "Instant"
		ns.db.weaponBuffOff = "Deadly"
		local text = ns.ExportProfile()
		ns.db.apl, ns.db.def = nil, nil
		local ok, key = ns.ImportProfile(text)
		H.eq(ok, true)
		H.eq(key, "OPT_IMPORT_OK")
		H.eq(ns.db.weaponBuff, "Instant")
		H.eq(ns.db.weaponBuffOff, "Deadly")
		H.eq(ns.db.aplDrop.ROGUE.damage.aoe.Rupture, true)
		H.eq(ns.db.defDrop.ROGUE.damage.Sprint, true)
	end)

	it("parses every line kind and clamps settings", function()
		local _, ns = boot("ROGUE")
		local refreshed = {}
		ns.UI = ns.UI or {}
		ns.UI.RefreshRoles = function()
			refreshed.roles = true
		end
		ns.UI.RefreshModes = function()
			refreshed.modes = true
		end
		ns.ApplyRotationEdit = function() end
		local text = table.concat({
			"WFR1",
			"C=",
			"R=heal",
			"M=aoe",
			"L=aoe",
			"A=1",
			"W=",
			"O=",
			"APL:ROGUE.damage.single=Eviscerate:1:1752:2.5,bad chunk,SinisterStrike:0",
			"APL:ROGUE.damage.aoe=",
			"APL:ROGUE.damage=Ignored:1",
			"DEF:ROGUE.damage=Evasion:1",
			"DEF:ROGUE.damage.single=Sprint:0",
			"DEF:ROGUE.damage.other=Feint:0",
			"DRP:ROGUE.damage.single=Rupture,bad key!,Gouge",
			"DRP:ROGUE.damage=Ignored",
			"DRP:ROGUE.damage.aoe=",
			"DDR:ROGUE.damage=Sprint",
			"XYZ:ROGUE.damage=Nothing",
			"APL:nodots=Nothing",
		}, "\r\n")
		local ok = ns.ImportProfile(text)
		H.eq(ok, true)
		local single = ns.db.apl.ROGUE.damage.single
		H.eq(#single, 2)
		H.same(single[1], { key = "Eviscerate", on = 1, hold = 2.5, id = 1752, custom = true })
		H.same(single[2], { key = "SinisterStrike", on = 0 })
		H.eq(#ns.db.apl.ROGUE.damage.aoe, 0)
		-- A DEF line with an unknown mode replaces the whole list (export never writes one).
		H.eq(ns.db.def.ROGUE.damage[1].key, "Feint")
		H.eq(ns.db.aplDrop.ROGUE.damage.single.Rupture, true)
		H.eq(ns.db.aplDrop.ROGUE.damage.single.Gouge, true)
		H.eq(ns.db.combatMode, "aoe")
		H.eq(ns.db.lastManualMode, "aoe")
		H.eq(ns.db.autoEnemies, 2)
		H.eq(ns.db.weaponBuff, nil)
		H.truthy(refreshed.roles and refreshed.modes, "UI refreshed")
	end)

	it("clamps a high enemy count and keeps unknown modes", function()
		local _, ns = boot("ROGUE")
		ns.ApplyRotationEdit = function() end
		ns.db.combatMode = "single"
		ns.db.lastManualMode = "single"
		ns.ImportProfile("WFR1\nR=\nM=bad\nL=bad\nA=99")
		H.eq(ns.db.autoEnemies, 8)
		H.eq(ns.db.combatMode, "single")
		H.eq(ns.db.lastManualMode, "single")
		ns.ImportProfile("WFR1\nA=x")
		H.eq(ns.db.autoEnemies, 3)
	end)

	it("falls back to FlushProfile without ApplyRotationEdit", function()
		local _, ns = boot("ROGUE")
		local calls = {}
		ns.ApplyRotationEdit = nil
		ns.FlushProfile = function()
			calls[#calls + 1] = "flush"
		end
		ns.InvalidateAPLCache = function()
			calls[#calls + 1] = "cache"
		end
		ns.Tick = function()
			calls[#calls + 1] = "tick"
		end
		ns.NormalizeRole = nil
		ns.ImportProfile("WFR1\nR=tank")
		H.same(calls, { "flush", "cache", "tick" })
		H.eq(ns.db.role, "tank")
		ns.InvalidateAPLCache, ns.Tick = nil, nil
		ns.ImportProfile("WFR1")
		ns.FlushProfile = nil
		ns.ClassToken = nil
		ns.UI = nil
		H.eq(ns.ImportProfile("WFR1"), true)
	end)
end)
