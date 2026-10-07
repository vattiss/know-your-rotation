local addonName, ns = ...
ns.API = ns.API or {}
-- Shared between the API files: functions and state that more than one file uses.
local I = {}
ns.API.I = I

-- Spell info, the spellbook index and spell resolution.

local function readable(value)
	if value == nil then
		return false
	end
	if issecretvalue and issecretvalue(value) then
		return false
	end
	if canaccessvalue and not canaccessvalue(value) then
		return false
	end
	return true
end

local function safe(value, fallback)
	if readable(value) then
		return value
	end
	return fallback
end

function ns.API.SpellInfo(spellID)
	if not spellID or not C_Spell or not C_Spell.GetSpellInfo then
		return nil
	end
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	if ok and type(info) == "table" then
		return info
	end
	return nil
end

local function junkSpellName(name)
	if type(name) ~= "string" then
		return true
	end
	local upper = name:upper()
	return upper:find("TEST", 1, true) or upper:find("(OLD)", 1, true) or upper:find("(PT)", 1, true)
end

local function spellIdFromName(name)
	name = safe(name, nil)
	if type(name) ~= "string" or name == "" or junkSpellName(name) then
		return nil
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		if ok and type(info) == "table" then
			local id = safe(info.spellID, nil)
			local got = safe(info.name, nil)
			if type(id) == "number" and (not got or got == name) and not junkSpellName(got or name) then
				return id
			end
		end
	end
	return nil
end

local cachedBanks

local function bookBanks()
	if cachedBanks then
		return cachedBanks
	end
	local banks = {}
	if Enum and Enum.SpellBookSpellBank then
		banks[#banks + 1] = Enum.SpellBookSpellBank.Player
		banks[#banks + 1] = Enum.SpellBookSpellBank.Pet
	end
	if BOOKTYPE_SPELL then
		banks[#banks + 1] = BOOKTYPE_SPELL
	end
	if BOOKTYPE_PET then
		banks[#banks + 1] = BOOKTYPE_PET
	end
	banks[#banks + 1] = 0
	banks[#banks + 1] = 1
	banks[#banks + 1] = "spell"
	banks[#banks + 1] = "pet"
	cachedBanks = banks
	return banks
end

local function readBookItem(index, bank)
	if index == nil or bank == nil then
		return nil, nil
	end
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
		local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
		if ok and type(info) == "table" then
			return safe(info.name, nil), safe(info.spellID, nil)
		end
	end
	if C_SpellBook and C_SpellBook.GetSpellBookItemName then
		local ok, name = pcall(C_SpellBook.GetSpellBookItemName, index, bank)
		if ok then
			return safe(name, nil), nil
		end
	end
	if GetSpellBookItemName then
		local ok, name = pcall(GetSpellBookItemName, index, bank)
		if ok then
			return safe(name, nil), nil
		end
	end
	return nil, nil
end

-- name: a readable, non-empty string (the callers check).
local function normSpellName(name)
	name = name:lower()
	name = name:gsub("%s*%([^%)]*%)", "")
	name = name:gsub("%s*rank%s*%d+", "")
	name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return name
end

local spellBookIndex
local spellBookGen = 0
local spellBookBuilding
local lastBookBuildAt = 0

local function indexBookName(index, bookName, bookId)
	if type(bookId) ~= "number" or junkSpellName(bookName) then
		return
	end
	if type(bookName) == "string" and bookName ~= "" then
		local key = normSpellName(bookName)
		if key and not index[key] then
			index[key] = bookId
		end
	end
end

function ns.API.InvalidateSpellBookIndex()
	spellBookGen = spellBookGen + 1
	spellBookIndex = nil
	spellBookBuilding = false
end

function ns.API.RebuildSpellBookIndex(sync)
	if spellBookBuilding and not sync then
		return
	end
	-- Never rebuild more than once every few seconds outside login sync -
	-- Forever quest rewards must not queue index jobs.
	if not sync and spellBookIndex and lastBookBuildAt and (GetTime() - lastBookBuildAt) < 5 then
		return
	end
	spellBookGen = spellBookGen + 1
	local gen = spellBookGen
	spellBookIndex = nil
	spellBookBuilding = true
	local index = {}
	local banks = bookBanks()
	lastBookBuildAt = GetTime()

	-- Only reached right after a pump that checked the generation.
	local function finish()
		spellBookIndex = index
		spellBookBuilding = false
		if ns.API.InvalidateSpells then
			ns.API.InvalidateSpells(false)
		end
		if ns.InvalidateTick then
			ns.InvalidateTick()
		end
		-- Defer HUD refresh one frame so Forever never stacks index finish + Tick
		-- cost on the same quest-reward freeze window.
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				if ns.Tick then
					ns.Tick()
				end
			end)
		elseif ns.Tick then
			ns.Tick()
		end
	end

	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		local okNum, num = pcall(C_SpellBook.GetNumSpellBookSkillLines)
		if okNum and type(num) == "number" and num > 0 then
			local line = 1
			local function pumpLine()
				if gen ~= spellBookGen then
					return
				end
				local budget = sync and 99 or 2
				while line <= num and budget > 0 do
					local okLine, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
					if okLine and type(lineInfo) == "table" then
						local off = tonumber(lineInfo.itemIndexOffset) or 0
						local count = tonumber(lineInfo.numSpellBookItems) or 0
						for i = off + 1, off + count do
							for _, bank in ipairs(banks) do
								local bookName, bookId = readBookItem(i, bank)
								indexBookName(index, bookName, bookId)
							end
						end
					end
					line = line + 1
					budget = budget - 1
				end
				if line <= num then
					if C_Timer and C_Timer.After then
						C_Timer.After(0, pumpLine)
					else
						pumpLine()
					end
				else
					finish()
				end
			end
			if sync then
				pumpLine()
			elseif C_Timer and C_Timer.After then
				C_Timer.After(0, pumpLine)
			else
				pumpLine()
			end
			return
		end
	end

	local i = 1
	local function pumpLegacy()
		if gen ~= spellBookGen then
			return
		end
		local budget = sync and 400 or 40
		while i <= 400 and budget > 0 do
			for _, bank in ipairs(banks) do
				local bookName, bookId = readBookItem(i, bank)
				indexBookName(index, bookName, bookId)
			end
			i = i + 1
			budget = budget - 1
		end
		if i <= 400 then
			if C_Timer and C_Timer.After then
				C_Timer.After(0, pumpLegacy)
			else
				pumpLegacy()
			end
		else
			finish()
		end
	end
	if sync then
		pumpLegacy()
	elseif C_Timer and C_Timer.After then
		C_Timer.After(0, pumpLegacy)
	else
		pumpLegacy()
	end
end

local function findPlayerSpellByName(name)
	name = safe(name, nil)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local want = normSpellName(name)
	if spellBookIndex then
		return spellBookIndex[want]
	end
	-- ConROC never walks the whole book: it uses IsSpellKnown on rank IDs.
	-- Forever remaps: try cheap name->ID APIs first; warm the index lazily
	-- only when still missing (login / rare remap), never on SPELLS_CHANGED.
	local fromApi = spellIdFromName(name)
	if type(fromApi) == "number" then
		return fromApi
	end
	if not spellBookBuilding then
		ns.API.RebuildSpellBookIndex(false)
	end
	return nil
end

local function acceptSpellId(id, expectedName)
	if type(id) ~= "number" or not readable(id) or junkSpellName(ns.API.SpellName(id) or "") then
		return nil
	end
	if expectedName then
		local got = ns.API.SpellName(id)
		if got and got ~= expectedName then
			return nil
		end
	end
	return id
end

function ns.API.ResolveFromName(name)
	if type(name) ~= "string" or name == "" or junkSpellName(name) then
		return nil
	end
	return findPlayerSpellByName(name) or spellIdFromName(name)
end

function ns.API.CursorSpell()
	if not GetCursorInfo then
		return nil
	end
	local ok, kind, arg1, arg2 = pcall(GetCursorInfo)
	if not ok then
		return nil
	end
	local kindText = safe(kind, nil)
	if type(kindText) == "string" then
		kindText = kindText:lower()
	end
	if kindText and kindText ~= "spell" and kindText ~= "spellid" then
		return nil
	end

	local name, slotId
	-- The cursor names its own bank first; never change the cached list.
	local banks = { arg2 }
	for _, bank in ipairs(bookBanks()) do
		banks[#banks + 1] = bank
	end
	for _, bank in ipairs(banks) do
		local bookName, bookId = readBookItem(arg1, bank)
		if bookName or bookId then
			name = bookName or name
			slotId = acceptSpellId(bookId, bookName) or slotId
			if name then
				break
			end
		end
	end

	if name then
		return findPlayerSpellByName(name) or slotId or spellIdFromName(name)
	end

	if type(arg1) == "number" and readable(arg1) then
		local guessed = ns.API.SpellName(arg1)
		if guessed and not junkSpellName(guessed) then
			if IsPlayerSpell then
				local okKnown, known = pcall(IsPlayerSpell, arg1)
				if okKnown and known then
					return arg1
				end
			end
			return findPlayerSpellByName(guessed) or arg1
		end
	end

	local info = ns.API.SpellInfo(arg1)
	if info then
		local infoName = safe(info.name, nil)
		if infoName then
			return findPlayerSpellByName(infoName) or acceptSpellId(safe(info.spellID, nil), infoName)
		end
	end
	return nil
end

function ns.API.SpellName(spellID)
	local info = ns.API.SpellInfo(spellID)
	return info and safe(info.name, nil)
end

-- ns.SPELL_NAME_HINT: the English spellbook name(s) of a spell, a string or
-- a list of strings, used when the ID is remapped on Forever.
local function pushHintName(out, seen, name)
	if type(name) == "table" then
		for i = 1, #name do
			pushHintName(out, seen, name[i])
		end
		return
	end
	if type(name) == "string" and name ~= "" and not seen[name] then
		seen[name] = true
		out[#out + 1] = name
	end
end

function ns.API.HintNames(...)
	local out, seen = {}, {}
	for n = 1, select("#", ...) do
		local spellID = select(n, ...)
		pushHintName(out, seen, spellID and ns.SPELL_NAME_HINT[spellID])
	end
	return out
end

function ns.API.HintName(spellID)
	local pack = spellID and ns.SPELL_NAME_HINT[spellID]
	if type(pack) == "table" then
		return pack[1]
	end
	return pack
end

function ns.API.SpellLabel(spellID)
	return ns.API.SpellName(spellID) or ns.API.HintName(spellID)
end

function ns.API.SpellIcon(spellID)
	local info = ns.API.SpellInfo(spellID)
	if not info then
		return nil
	end
	local icon = info.originalIconID or info.iconID or info.icon
	if readable(icon) then
		return icon
	end
	return nil
end

local resolveCache = {}
function ns.API.InvalidateSpells(full)
	if ns.API.healAmountCache then
		wipe(ns.API.healAmountCache)
	end
	if full then
		wipe(resolveCache)
		if ns.API.InvalidateSpellBookIndex then
			ns.API.InvalidateSpellBookIndex()
		end
	else
		for id, resolved in pairs(resolveCache) do
			if not resolved then
				resolveCache[id] = nil
			end
		end
	end
	wipe(I.auraScans)
	I.healNames = nil
	if ns.InvalidateBuffCaches then
		ns.InvalidateBuffCaches()
	end
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
end

local function playerKnows(id)
	if IsPlayerSpell then
		local ok, known = pcall(IsPlayerSpell, id)
		if ok and known then
			return true
		end
	end
	if IsSpellKnownOrOverridesKnown then
		local ok, known = pcall(IsSpellKnownOrOverridesKnown, id)
		if ok and known then
			return true
		end
	end
	if IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, id)
		if ok and known then
			return true
		end
	end
	if C_SpellBook then
		if C_SpellBook.IsSpellInSpellBook then
			local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id)
			if ok and known then
				return true
			end
		end
		if C_SpellBook.FindSpellBookSlotForSpell then
			local ok, slot = pcall(C_SpellBook.FindSpellBookSlotForSpell, id)
			if ok and slot then
				return true
			end
		end
	end
	return false
end

---The spell ID the player knows for this spell (by name + spellbook).
---@param spellID integer
---@return integer?
function ns.API.Resolve(spellID)
	if not spellID then
		return nil
	end
	local cached = resolveCache[spellID]
	if cached ~= nil then
		return cached or nil
	end
	local id = spellID
	if C_Spell and C_Spell.GetOverrideSpell then
		local ok, over = pcall(C_Spell.GetOverrideSpell, spellID)
		if ok and type(over) == "number" and readable(over) then
			id = over
		end
	end
	if playerKnows(id) then
		resolveCache[spellID] = id
		return id
	end
	if id ~= spellID and playerKnows(spellID) then
		resolveCache[spellID] = spellID
		return spellID
	end
	local names = { ns.API.SpellName(id) or ns.API.SpellName(spellID) }
	local hints = ns.API.HintNames(spellID, id)
	for i = 1, #hints do
		names[#names + 1] = hints[i]
	end
	for i = 1, #names do
		local name = names[i]
		if type(name) == "string" and name ~= "" then
			local fromName = spellIdFromName(name)
			if fromName and playerKnows(fromName) then
				resolveCache[spellID] = fromName
				return fromName
			end
			local bookId = findPlayerSpellByName(name)
			if bookId then
				resolveCache[spellID] = bookId
				return bookId
			end
		end
	end
	resolveCache[spellID] = false
	return nil
end

---@param spellID integer
---@return boolean
function ns.API.Known(spellID)
	return ns.API.Resolve(spellID) ~= nil
end

local function unitExists(unit)
	local ok, exists = pcall(UnitExists, unit)
	return ok and exists and true or false
end

local function normName(name)
	local n = strlower(name)
	n = n:gsub("%s*%([^%)]*%)", "")
	n = strtrim(n)
	return n
end

I.normName = normName
I.readable = readable
I.safe = safe
I.unitExists = unitExists
