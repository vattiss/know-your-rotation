local wow = require("wow")
local H = require("helpers")

describe("Data.Color", function()
	it("uses the saved colour, then the default, then the 'next' colour", function()
		local w = wow.new()
		w:player("ROGUE")
		local ns = w:load()
		ns.db = nil
		H.same({ ns.Color("heal") }, { 0.15, 1, 0.28 })
		ns.db = { colors = { heal = { 0.5 }, def = "bad", weapon = { "x" } } }
		H.same({ ns.Color("heal") }, { 0.5, 0, 0 }, "missing parts are 0")
		H.same({ ns.Color("def") }, { 0.2, 0.55, 1 }, "not a table")
		H.same({ ns.Color("weapon") }, { 1, 0.12, 0.08 }, "no red value")
		H.same({ ns.Color("nope") }, { 1, 1, 1 }, "unknown key")
		ns.db.colors.next = { 0.1, 0.2, 0.3 }
		H.same({ ns.Color("next") }, { 0.1, 0.2, 0.3 })
	end)
end)

describe("Data.RACIALS", function()
	it("keeps the offensive racials for the fight", function()
		local w = wow.new()
		w:player("WARRIOR")
		local ns = w:load()
		local count = 0
		for _, racial in ipairs(ns.RACIALS) do
			if racial.opt and racial.opt.hostile then
				count = count + 1
				H.eq(racial.opt.combat, true, racial.key .. " is not offered before the pull")
			end
		end
		H.truthy(count >= 5, "the offensive racials were checked")
	end)
end)
