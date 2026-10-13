local wow = require("wow")
local H = require("helpers")

local CORE = wow.API_FILES

local function api(setup)
	local w = wow.new()
	w:player("MAGE")
	if setup then
		setup(w)
	end
	local ns = w:load(CORE)
	return w, ns, ns.API
end

describe("API spell info and names", function()
	it("reads spell info defensively", function()
		local w, _, A = api(function(w)
			w.spell(133, { name = "Fireball", icon = 135812 })
		end)
		H.eq(A.SpellInfo(nil), nil)
		H.eq(A.SpellInfo(133).name, "Fireball")
		H.eq(A.SpellName(133), "Fireball")
		H.eq(A.SpellIcon(133), 135812)
		H.eq(A.SpellIcon(999), nil)
		H.eq(A.SpellLabel(999), nil)
		H.eq(A.SpellLabel(34428), "Victory Rush", "hint name for an unknown spell")
		w.env.C_Spell.GetSpellInfo = function()
			return "not a table"
		end
		H.eq(A.SpellInfo(133), nil)
		w.env.C_Spell.GetSpellInfo = function()
			error("boom")
		end
		H.eq(A.SpellInfo(133), nil)
		w.env.C_Spell = nil
		H.eq(A.SpellInfo(133), nil)
	end)

	it("hides secret names and icons", function()
		local w, _, A = api(function(w)
			w.spell(133, { name = "Fireball" })
		end)
		w.env.C_Spell.GetSpellInfo = function()
			return { name = wow.SECRET_STRING, spellID = 133, iconID = wow.SECRET }
		end
		H.eq(A.SpellName(133), nil)
		H.eq(A.SpellIcon(133), nil)
	end)

	it("treats an inaccessible value like a secret one", function()
		local w, _, A = api(function(w)
			w.spell(133, { name = "Hidden" })
		end)
		w.env.canaccessvalue = function(v)
			return v ~= "Hidden"
		end
		H.eq(A.SpellName(133), nil)
	end)

	it("returns hint names: single, lists, duplicates", function()
		local _, ns, A = api()
		H.same(A.HintNames(34428, 34428, 408341, nil, 1), { "Victory Rush", "Fire Nova", "Fire Nova Totem" })
		H.eq(A.HintName(34428), "Victory Rush")
		H.eq(A.HintName(408341), "Fire Nova")
		H.eq(A.HintName(nil), nil)
		H.eq(A.HintName(1), nil)
		ns.SPELL_NAME_HINT[2] = { "" }
		H.same(A.HintNames(2), {})
	end)
end)

describe("API spellbook index", function()
	local function book()
		return api(function(w)
			w.spell(10, { name = "Frostbolt" })
			w.spell(11, { name = "Arcane Missiles (Rank 2)" })
			w.spell(12, { name = "Lightning   Bolt" })
			w.spell(13, { name = "Fireball TEST" })
			w.spell(14, { name = "" })
		end)
	end

	it("indexes the book synchronously and finds folded names", function()
		local _, ns, A = book()
		local hooks = {}
		ns.InvalidateTick = function()
			hooks.invalidate = true
		end
		A.RebuildSpellBookIndex(true)
		H.eq(A.ResolveFromName("frostbolt"), 10)
		H.eq(A.ResolveFromName("Arcane Missiles"), 11)
		H.eq(A.ResolveFromName("Arcane Missiles rank 3"), 11)
		H.eq(A.ResolveFromName("lightning bolt"), 12, "spaces collapsed")
		H.eq(A.ResolveFromName("Nothing"), nil)
		H.eq(A.ResolveFromName("Fireball TEST"), nil, "junk")
		H.eq(A.ResolveFromName(""), nil)
		H.eq(A.ResolveFromName(nil), nil)
		H.truthy(hooks.invalidate, "finish refreshes the tick")
	end)

	it("builds in steps on timers, and a newer build wins", function()
		local w, ns, A = book()
		local ticks = 0
		ns.Tick = function()
			ticks = ticks + 1
		end
		w.env.C_SpellBook.GetNumSpellBookSkillLines = function()
			return 3
		end
		A.RebuildSpellBookIndex(false)
		A.RebuildSpellBookIndex(false) -- already building: ignored
		w:advance(0)
		H.eq(ticks, 1, "finished after the timers ran")
		A.RebuildSpellBookIndex(false) -- built a moment ago: ignored
		w:advance(10)
		A.RebuildSpellBookIndex(false)
		A.InvalidateSpellBookIndex()
		w:advance(0)
		H.eq(ticks, 1, "invalidated build never finishes")
	end)

	it("falls back to the legacy 400-slot walk", function()
		local w, ns, A = book()
		w.env.C_SpellBook.GetNumSpellBookSkillLines = function()
			return 0
		end
		w.env.C_SpellBook.GetSpellBookItemInfo = nil
		A.RebuildSpellBookIndex(true)
		H.eq(A.ResolveFromName("Frostbolt"), 10)
		A.InvalidateSpellBookIndex()
		local ticked = false
		ns.Tick = function()
			ticked = true
		end
		w.env.C_Timer = nil
		A.RebuildSpellBookIndex(false)
		H.truthy(ticked, "no timers: built at once")
	end)

	it("pumps the legacy walk on timers", function()
		local w, _, A = book()
		w.env.C_SpellBook = nil
		w.env.GetSpellBookItemName = function(index, bank)
			if bank == "spell" and index == 1 then
				return "Frostbolt"
			end
		end
		A.RebuildSpellBookIndex(false)
		w:advance(0)
		A.RebuildSpellBookIndex(false)
		A.InvalidateSpellBookIndex()
		A.RebuildSpellBookIndex(false)
		A.InvalidateSpellBookIndex()
		w:advance(0)
	end)

	it("skips book items without a name, and names an empty slot", function()
		local w, _, A = book()
		w.env.C_SpellBook.GetSpellBookItemInfo = function(index, bank)
			if bank == 0 and index == 1 then
				return { spellID = 10 }
			end
			if bank == 0 and index == 2 then
				return { name = "", spellID = 11 }
			end
		end
		A.RebuildSpellBookIndex(true)
		w.state.cursor = { "spell", 2 }
		H.eq(A.CursorSpell(), nil, "empty name does not vouch for the slot ID")
	end)

	it("pumps skill lines without timers", function()
		local w, ns, A = book()
		w.env.C_SpellBook.GetNumSpellBookSkillLines = function()
			return 3
		end
		w.env.C_Timer = nil
		local ticked = false
		ns.Tick = function()
			ticked = true
		end
		A.RebuildSpellBookIndex(false)
		H.truthy(ticked)
		w.env.C_SpellBook.GetSpellBookSkillLineInfo = function()
			return nil
		end
		A.InvalidateSpellBookIndex()
		A.RebuildSpellBookIndex(true)
	end)

	it("reads book items through every client API", function()
		local w, _, A = book()
		w.env.C_SpellBook.GetSpellBookItemInfo = function()
			error("boom")
		end
		w.env.C_SpellBook.GetSpellBookItemName = function()
			error("boom")
		end
		w.env.GetSpellBookItemName = function()
			error("boom")
		end
		w.env.Enum = nil
		w.env.BOOKTYPE_SPELL, w.env.BOOKTYPE_PET = nil, nil
		A.RebuildSpellBookIndex(true)
		H.eq(A.ResolveFromName("Frostbolt"), 10, "name API still answers")
	end)
end)

describe("API spell ranks", function()
	it("reads a rank from the subtext and finds the highest learned one", function()
		local w, _, A = api(function(w)
			w.spell(900, { name = "Frostbolt", rank = 1 })
			w.spell(901, { name = "Frostbolt", rank = 3 })
			w.spell(902, { name = "Frostbolt", rank = 2 })
			w.spell(910, { name = "Blink" })
			w.spell(920, { name = "Pyroblast", rank = 2, known = false, inBook = false })
		end)
		A.RebuildSpellBookIndex(true)
		H.eq(A.SpellRank(900), 1)
		H.eq(A.SpellRank(910), nil, "no rank text")
		H.eq(A.SpellRank(999999), nil, "unknown spell")
		H.eq(A.HighestKnownRank(900), 3, "ranks are separate book entries")
		H.eq(A.HighestKnownRank(910), nil, "a spell without ranks")
		H.eq(A.HighestKnownRank(920), nil, "not in the book")
		H.eq(A.HighestKnownRank(nil), nil)
		w.spell(903, { name = "Frostbolt", rank = 4 })
		A.NoteLearnedSpell(903)
		A.NoteLearnedSpell(903)
		H.eq(A.HighestKnownRank(900), 4, "a rank learned now counts at once")
		A.NoteLearnedSpell(wow.SECRET)
		w.spell(904, { name = "Arcane Missiles", rank = 1 })
		A.NoteLearnedSpell(904)
		H.eq(A.HighestKnownRank(904), 1, "a new name too")
		w.env.C_Spell.GetSpellSubtext = nil
		H.eq(A.SpellRank(900), nil, "no API")
		w.env.C_Spell.GetSpellSubtext = function()
			error("boom")
		end
		H.eq(A.SpellRank(900), nil, "an error is no answer")
		w.env.C_Spell.GetSpellSubtext = function()
			return wow.SECRET_STRING
		end
		H.eq(A.SpellRank(900), nil, "a hidden text is no answer")
		A.InvalidateSpellBookIndex()
		A.NoteLearnedSpell(903)
		H.eq(A.HighestKnownRank(900), nil, "the index is not built")
	end)
end)

describe("API.Resolve", function()
	it("caches known IDs, follows overrides and falls back by name", function()
		local w, _, A = api(function(w)
			w.spell(100, { name = "Frost Armor" })
			w.spell(200, { name = "Ice Armor", override = 201 })
			w.spell(201, { name = "Ice Armor" })
			w.spell(300, { name = "Old Shield", override = 301 })
			w.spell(301, { name = "Old Shield", known = false, inBook = false })
			w.spell(400, { name = "Remapped", known = false, inBook = false })
			w.spell(401, { name = "Remapped" })
			w.spell(500, { name = "Forgotten", known = false, inBook = false })
		end)
		H.eq(A.Resolve(nil), nil)
		H.eq(A.Resolve(100), 100)
		H.eq(A.Resolve(100), 100, "cached")
		H.eq(A.Resolve(200), 201, "override")
		H.eq(A.Resolve(300), 300, "override unknown, base known")
		H.eq(A.Resolve(400), 401, "same name, other ID")
		H.eq(A.Resolve(500), nil)
		H.eq(A.Known(500), nil == A.Resolve(500) and false)
		H.eq(A.Resolve(34428), nil, "hint name not in the book")
		w.spell(34429, { name = "Victory Rush" })
		A.InvalidateSpells(true)
		H.eq(A.Resolve(34428), 34429, "found through the hint name")
	end)

	it("finds a renamed spell through the built book index", function()
		local w, _, A = api(function(w)
			w.spell(600, { name = "Smite", known = false, inBook = false })
		end)
		w.state.book = { 601 }
		w.state.spells[601] = { id = 601, name = "Smite", known = false }
		A.RebuildSpellBookIndex(true)
		H.eq(A.Resolve(600), 601)
	end)

	it("does not take a spell the book lists as not learned yet for a known one", function()
		local w, _, A = api(function(w)
			w.spell(800, { name = "Aspect of the Hawk", known = false, inBook = false, future = true })
			w.state.book[#w.state.book + 1] = 800
		end)
		A.RebuildSpellBookIndex(true)
		H.eq(A.Resolve(800), nil, "a future spell is not known")
		H.eq(A.Known(800), false)
		w.state.spells[800].known = true
		w.state.spells[800].future = false
		A.InvalidateSpells(true)
		H.eq(A.Resolve(800), 800, "learned: known")
	end)

	it("asks each known-spell API in turn", function()
		local w, _, A = api(function(w)
			w.spell(700, { name = "A" })
		end)
		local env = w.env
		env.IsPlayerSpell = function()
			error("boom")
		end
		env.IsSpellKnownOrOverridesKnown = function()
			return false
		end
		env.IsSpellKnown = function()
			return false
		end
		env.C_SpellBook.IsSpellInSpellBook = function()
			return false
		end
		env.C_SpellBook.IsSpellInSpellBook = function(id)
			return id == 700
		end
		H.eq(A.Resolve(700), 700)
		A.InvalidateSpells(true)
		env.C_SpellBook.IsSpellInSpellBook = nil
		env.IsSpellKnown = function(id)
			return id == 700
		end
		H.eq(A.Resolve(700), 700)
		A.InvalidateSpells(true)
		env.IsSpellKnown = nil
		env.IsSpellKnownOrOverridesKnown = function(id)
			return id == 700
		end
		H.eq(A.Resolve(700), 700)
		A.InvalidateSpells(true)
		env.IsSpellKnownOrOverridesKnown = nil
		env.IsPlayerSpell = nil
		env.C_SpellBook = nil
		env.C_Spell.GetOverrideSpell = nil
		H.eq(A.Resolve(700), nil, "a name alone does not make a spell known")
	end)

	it("keeps resolved IDs on a light invalidation and drops misses", function()
		local w, ns, A = api(function(w)
			w.spell(800, { name = "Blink" })
		end)
		local calls = {}
		ns.InvalidateBuffCaches = function()
			calls.buff = true
		end
		ns.InvalidateAPLCache = function()
			calls.apl = true
		end
		H.eq(A.Resolve(800), 800)
		H.eq(A.Resolve(801), nil)
		w.spell(801, { name = "Blink 2" })
		A.InvalidateSpells(false)
		H.eq(A.Resolve(801), 801, "a miss is asked again")
		H.truthy(calls.buff and calls.apl)
		ns.API.healAmountCache = nil
		A.InvalidateSpells(false)
	end)
end)

describe("API names from the cursor and the API", function()
	it("reads a dragged spell from the book or by ID", function()
		local w, _, A = api(function(w)
			w.spell(10, { name = "Frostbolt" })
			w.spell(20, { name = "Junk (OLD)" })
			w.spell(30, { name = "Unlearned", known = false, inBook = false })
		end)
		H.eq(A.CursorSpell(), nil, "nothing on the cursor")
		w.state.cursor = { "item", 1 }
		H.eq(A.CursorSpell(), nil, "not a spell")
		w.state.cursor = { "spell", 1, 0 }
		H.eq(A.CursorSpell(), 10, "book slot 1, own bank first")
		w.state.cursor = { "spell", 1, "spell" }
		H.eq(A.CursorSpell(), 10)
		w.state.cursor = { "spellID", 10 }
		w.env.C_SpellBook.GetSpellBookItemInfo = function()
			return nil
		end
		w.env.C_SpellBook.GetSpellBookItemName = nil
		H.eq(A.CursorSpell(), 10, "by spell ID, known")
		w.state.cursor = { wow.SECRET_STRING, 30 }
		H.eq(A.CursorSpell(), 30, "unknown kind, unknown spell: the ID itself")
		w.state.cursor = { "spell", 20 }
		H.eq(A.CursorSpell(), nil, "junk name")
		w.state.cursor = { "spell", "Frostbolt" }
		H.eq(A.CursorSpell(), 10, "spell info by name")
		w.state.cursor = { "spell", "Nothing" }
		H.eq(A.CursorSpell(), nil)
		w.env.IsPlayerSpell = nil
		w.state.cursor = { "spell", 30 }
		H.eq(A.CursorSpell(), 30)
		w.env.GetCursorInfo = function()
			error("boom")
		end
		H.eq(A.CursorSpell(), nil)
		w.env.GetCursorInfo = nil
		H.eq(A.CursorSpell(), nil)
	end)

	it("rejects a slot ID with another name but trusts the book index", function()
		local w, _, A = api(function(w)
			w.spell(10, { name = "Frostbolt" })
			w.spell(11, { name = "Other" })
		end)
		w.env.C_SpellBook.GetSpellBookItemInfo = function(index, bank)
			if bank == 0 and index == 1 then
				return { name = "Frostbolt", spellID = 11 }
			end
		end
		w.state.cursor = { "spell", 1 }
		A.RebuildSpellBookIndex(true)
		w.state.book = {}
		H.eq(A.CursorSpell(), 11, "the book index wins over the rejected slot ID")
	end)

	it("ignores API answers with another or a junk name", function()
		local w, _, A = api(function(w)
			w.spell(10, { name = "Frostbolt" })
		end)
		w.env.C_Spell.GetSpellInfo = function(id)
			if id == "Frostbolt" then
				return { name = "Frostbolt (OLD)", spellID = 10 }
			end
			if id == "Wrong" then
				return { name = "Other", spellID = 10 }
			end
			if id == "NoId" then
				return { name = "NoId", spellID = "x" }
			end
		end
		H.eq(A.ResolveFromName("Frostbolt"), nil)
		H.eq(A.ResolveFromName("Wrong"), nil)
		H.eq(A.ResolveFromName("NoId"), nil)
		w.env.C_Spell = nil
		H.eq(A.ResolveFromName("Frostbolt"), nil)
	end)
end)

describe("API aura scan caches", function()
	it("wipes one unit or all scans", function()
		local _, _, A = api()
		A.FindAura(1, "player", "HELPFUL")
		A.FindAura(1, "target", "HARMFUL")
		A.WipeAuraScan("player")
		A.WipeAuraScans()
		A.WipeAuraScan("player")
		A.WipeAuraScan(nil)
	end)
end)
