local addonName, ns = ...
ns.API = ns.API or {}

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
	return upper:find("TEST", 1, true)
		or upper:find("(OLD)", 1, true)
		or upper:find("(PT)", 1, true)
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

-- Forever lab clients often drop accents (Eclair vs Éclair). Fold so Resolve
-- matches the spellbook for every class spell and racial by name.
local ACCENT_FOLD = {
	["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
	["À"] = "a", ["Á"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Å"] = "a",
	["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
	["È"] = "e", ["É"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
	["Ì"] = "i", ["Í"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
	["Ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
	["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u",
	["Ù"] = "u", ["Ú"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["ý"] = "y", ["ÿ"] = "y", ["Ý"] = "y",
	["ç"] = "c", ["Ç"] = "c",
	["ñ"] = "n", ["Ñ"] = "n",
	["œ"] = "oe", ["Œ"] = "oe",
	["æ"] = "ae", ["Æ"] = "ae",
}

local function foldAccents(name)
	if type(name) ~= "string" or name == "" then
		return name
	end
	return (name:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
		return ACCENT_FOLD[ch] or ch
	end))
end

local function normSpellName(name)
	name = safe(name, nil)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	name = foldAccents(name):lower()
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

	local function finish()
		if gen ~= spellBookGen then
			return
		end
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
	if not want then
		return nil
	end
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
	local banks = bookBanks()
	if arg2 ~= nil then
		table.insert(banks, 1, arg2)
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

local enemyCountAt, enemyCountVal, enemyCountValKey = 0, 0, nil

function ns.API.EnemyCount(maxYards)
	local now = GetTime()
	maxYards = tonumber(maxYards)
	local cacheKey = maxYards or 0
	if enemyCountAt > 0 and (now - enemyCountAt) < 0.3 and enemyCountValKey == cacheKey then
		return enemyCountVal
	end
	local count = 0
	local function hostile(unit)
		local okEx, exists = pcall(UnitExists, unit)
		if not okEx or not exists then
			return false
		end
		local okDead, dead = pcall(UnitIsDead, unit)
		if okDead and dead then
			return false
		end
		local okAtk, atk = pcall(UnitCanAttack, "player", unit)
		if okAtk and atk then
			return true
		end
		local okR, react = pcall(UnitReaction, "player", unit)
		return okR and type(react) == "number" and react <= 4
	end
	local function plain(value)
		return not (issecretvalue and issecretvalue(value))
	end
	-- In combat, count only enemies fighting you: on your threat table, or
	-- targeting you or your pet. A mob fighting someone else nearby does not
	-- count. Out of combat every hostile nameplate counts.
	local function inFight(unit)
		local okP, pcombat = pcall(UnitAffectingCombat, "player")
		if not (okP and pcombat) then
			return true
		end
		if UnitThreatSituation then
			local ok, status = pcall(UnitThreatSituation, "player", unit)
			if ok and plain(status) then
				return status ~= nil
			end
		end
		local targetUnit = unit .. "target"
		for _, who in ipairs({ "player", "pet" }) do
			local ok, same = pcall(UnitIsUnit, targetUnit, who)
			if ok and plain(same) and same == true then
				return true
			end
		end
		local okC, combat = pcall(UnitAffectingCombat, unit)
		return okC and plain(combat) and combat == true or false
	end
	local function inYards(unit)
		if not maxYards or maxYards <= 0 then
			return true
		end
		local minY, maxY = ns.API.TargetRangeBand(unit)
		if minY and minY > maxYards then
			return false
		end
		if maxY and maxY <= maxYards then
			return true
		end
		-- ~10 yd band via duel interact when yards <= 10.
		if maxYards <= 10 then
			local close
			if CheckInteractDistance then
				local ok, result = pcall(CheckInteractDistance, unit, 3)
				if ok then
					close = safe(result, nil)
				end
				if close == nil then
					ok, result = pcall(CheckInteractDistance, unit, 2)
					if ok then
						close = safe(result, nil)
					end
				end
			end
			return close == true or close == 1
		end
		if maxYards <= 28 then
			if CheckInteractDistance then
				local ok, result = pcall(CheckInteractDistance, unit, 1)
				if ok then
					result = safe(result, nil)
					return result == true or result == 1
				end
			end
			return true
		end
		return true
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if hostile(unit) and inFight(unit) and inYards(unit) then
			count = count + 1
		end
	end
	if count < 1 and hostile("target") and inYards("target") then
		count = 1
	end
	enemyCountAt = now
	enemyCountVal = count
	enemyCountValKey = cacheKey
	return count
end

function ns.API.SpellName(spellID)
	local info = ns.API.SpellInfo(spellID)
	return info and safe(info.name, nil)
end

local HINT_LOCALES = { "enUS" }

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

local function hintLocale()
	return "enUS"
end

function ns.API.HintNames(...)
	local out, seen = {}, {}
	for n = 1, select("#", ...) do
		local spellID = select(n, ...)
		local pack = spellID and ns.SPELL_NAME_HINT and ns.SPELL_NAME_HINT[spellID]
		if type(pack) == "string" then
			pushHintName(out, seen, pack)
		elseif type(pack) == "table" then
			local loc = hintLocale()
			pushHintName(out, seen, pack[loc])
			for i = 1, #HINT_LOCALES do
				local code = HINT_LOCALES[i]
				if code ~= loc then
					pushHintName(out, seen, pack[code])
				end
			end
			for i = 1, #pack do
				pushHintName(out, seen, pack[i])
			end
		end
	end
	return out
end

function ns.API.HintName(spellID)
	local pack = spellID and ns.SPELL_NAME_HINT and ns.SPELL_NAME_HINT[spellID]
	if type(pack) == "string" then
		return pack
	end
	if type(pack) ~= "table" then
		return nil
	end
	local loc = hintLocale()
	local hit = pack[loc] or pack.enUS or pack[1]
	if type(hit) == "table" then
		return hit[1]
	end
	return hit
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
local healNames
local auraScans = {}
local predict
local heldHarmful = {}
local heldHarmfulGuid

function ns.API.WipeAuraScans()
	wipe(auraScans)
end

function ns.API.WipeAuraScan(unit)
	if not unit then
		wipe(auraScans)
		return
	end
	local prefix = unit .. "\0"
	for key in pairs(auraScans) do
		if strsub(key, 1, #prefix) == prefix then
			auraScans[key] = nil
		end
	end
end

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
	wipe(auraScans)
	healNames = nil
	if ns.InvalidateBuffCaches then
		ns.InvalidateBuffCaches()
	end
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
end

local function playerKnows(id)
	if not id then
		return false
	end
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

function ns.API.Known(spellID)
	return ns.API.Resolve(spellID) ~= nil
end

local cdUntil = {}
local cdKnown = {}
local holdUntil = {}

local function cdKey(spellID)
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		local n = strlower(name)
		n = n:gsub("%s*%([^%)]*%)", "")
		if strtrim then
			n = strtrim(n)
		end
		if n ~= "" then
			return n
		end
	end
	return "id:" .. tostring(spellID)
end

local function parseBaseCooldown(cd, gcd)
	cd = tonumber(safe(cd, nil))
	gcd = tonumber(safe(gcd, nil))
	if not cd or cd <= 0 then
		return 0
	end
	if cd < 500 then
		local gcdSec = gcd and gcd < 500 and gcd or 1.5
		if cd <= gcdSec + 0.05 or cd <= 1.5 then
			return 0
		end
		return cd
	end
	local gcdMs = gcd or 1500
	if cd <= gcdMs + 50 then
		return 0
	end
	return cd / 1000
end

local function baseCooldownSec(spellID)
	if GetSpellBaseCooldown then
		local ok, cd, gcd = pcall(GetSpellBaseCooldown, spellID)
		if ok then
			local sec = parseBaseCooldown(cd, gcd)
			if sec > 0 then
				return sec
			end
		end
	end
	if C_Spell and C_Spell.GetSpellBaseCooldown then
		local ok, cd, gcd = pcall(C_Spell.GetSpellBaseCooldown, spellID)
		if ok then
			if type(cd) == "table" then
				local sec = parseBaseCooldown(cd.duration or cd.cooldown, cd.gcd)
				if sec > 0 then
					return sec
				end
			else
				local sec = parseBaseCooldown(cd, gcd)
				if sec > 0 then
					return sec
				end
			end
		end
	end
	return 0
end

local function groupOf(spellID)
	local groups = ns.COOLDOWN_GROUPS
	if not groups then
		return nil
	end
	local castName = ns.API.SpellName(spellID)
	for _, group in ipairs(groups) do
		for _, id in ipairs(group.ids) do
			if id == spellID or (castName and ns.API.SpellName(id) == castName) then
				return group
			end
		end
	end
end

local function fallbackSeconds(spellID)
	local map = ns.COOLDOWNS
	if map and map[spellID] then
		return map[spellID]
	end
	local group = groupOf(spellID)
	if group and group.seconds then
		return group.seconds
	end
	local name = ns.API.SpellName(spellID)
	if map and name then
		for id, seconds in pairs(map) do
			if ns.API.SpellName(id) == name then
				return seconds
			end
		end
	end
	return 0
end

function ns.API.SpellCooldownSec(spellID)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID then
		return 0
	end
	local sec = baseCooldownSec(spellID)
	if sec and sec > 0.2 then
		return sec
	end
	return fallbackSeconds(spellID) or 0
end

function ns.API.IsFallback(opt)
	opt = opt or {}
	return opt.filler == true or opt.swing == true
end

-- A filler listed first must yield to these when they are pressable.
-- Nukes without a cooldown (Starfire, Ice Lance, Swipe) stay list-order.
-- Auto-appended racials never steal a filler higher in the list.
function ns.API.IsRotationAction(spellID, opt, isRacial)
	if isRacial then
		return false
	end
	opt = opt or {}
	if ns.API.IsFallback(opt) or opt.autoRepeat then
		return false
	end
	if opt.heal or opt.nodebuff or opt.nobuff or opt.needbuff or opt.needdebuff then
		return true
	end
	if opt.proc or opt.usable or opt.comboMin then
		return true
	end
	if opt.nopet or opt.pet or opt.nocombat then
		return true
	end
	if opt.hp or opt.manaMax or opt.hpMin then
		return true
	end
	if opt.anybuff or opt.anydebuff then
		return true
	end
	local sec = ns.API.SpellCooldownSec(spellID)
	return sec and sec > 0.2
end

local function markCooldown(spellID, seconds)
	if not seconds or seconds <= 0.2 then
		return
	end
	local exp = GetTime() + seconds
	cdUntil[cdKey(spellID)] = exp
	cdUntil["id:" .. tostring(spellID)] = exp
	local group = groupOf(spellID)
	if not group then
		return
	end
	local groupExp = GetTime() + math.max(seconds, group.seconds or 0)
	for _, id in ipairs(group.ids) do
		cdUntil[cdKey(id)] = groupExp
		cdUntil["id:" .. tostring(id)] = groupExp
	end
end

function ns.API.NoteSpellCast(spellID)
	ns.API.lastCastAt = GetTime()
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	ns.API.NoteComboCast(spellID)
	local key = cdKey(spellID)
	local seconds = baseCooldownSec(spellID)
	if seconds <= 0 and cdKnown[key] and cdKnown[key] > 1.5 then
		seconds = cdKnown[key]
	end
	if seconds <= 0 then
		seconds = fallbackSeconds(spellID)
	end
	markCooldown(spellID, seconds)
	local hold = ns.API.HoldSeconds(spellID)
	if hold and hold > 0 then
		ns.API.NoteSpellHold(spellID, hold)
	end
end

-- Re-suggest delay after cast (DoT / HoT / snare). Independent from real CD.
function ns.API.HoldSeconds(spellID)
	local resolved = ns.API.Resolve(spellID) or spellID
	if not resolved then
		return 0
	end
	local function fromStep(step)
		if not step or not step.id then
			return nil
		end
		local sid = ns.API.Resolve(step.id) or step.id
		if sid ~= resolved and step.id ~= spellID and step.id ~= resolved then
			return nil
		end
		if step.opt and step.opt.hold ~= nil then
			return tonumber(step.opt.hold) or 0
		end
		return nil
	end
	if ns.GetAPL then
		local apl = ns.GetAPL()
		for i = 1, #(apl or {}) do
			local hit = fromStep(apl[i])
			if hit ~= nil then
				return math.max(0, hit)
			end
		end
	end
	if ns.GetDef then
		local def = ns.GetDef()
		for i = 1, #(def or {}) do
			local hit = fromStep(def[i])
			if hit ~= nil then
				return math.max(0, hit)
			end
		end
	end
	if ns.SPELL_HOLD then
		local h = ns.SPELL_HOLD[resolved] or ns.SPELL_HOLD[spellID]
		if type(h) == "number" then
			return math.max(0, h)
		end
	end
	return 0
end

-- Target DoT / snare / mark holds bind to the mob GUID so a new target
-- (or a dead one) can be marked again. Self HoTs / Slice and Dice stay global.
local function holdTargetGuid()
	local ok, guid = pcall(UnitGUID, "target")
	if ok and readable(guid) and type(guid) == "string" then
		return guid
	end
	return nil
end

local function holdBindsToTarget(spellID)
	if ns.API.IsHelpful(spellID) and not ns.API.IsHarmful(spellID) then
		return false
	end
	return ns.API.IsHarmful(spellID) == true
end

local function unitIsDead(unit)
	if UnitIsDeadOrGhost then
		local ok, dead = pcall(UnitIsDeadOrGhost, unit)
		if ok and dead == true then
			return true
		end
		if ok and dead == false then
			return false
		end
	end
	if UnitIsDead then
		local ok, dead = pcall(UnitIsDead, unit)
		if ok and dead == true then
			return true
		end
	end
	return false
end

local function writeHold(spellID, exp, guid)
	local entry = { exp = exp, guid = guid }
	holdUntil[cdKey(spellID)] = entry
	holdUntil["id:" .. tostring(spellID)] = entry
	local resolved = ns.API.Resolve(spellID)
	if resolved and resolved ~= spellID then
		holdUntil[cdKey(resolved)] = entry
		holdUntil["id:" .. tostring(resolved)] = entry
	end
end

local function clearHoldKeys(spellID)
	holdUntil[cdKey(spellID)] = nil
	holdUntil["id:" .. tostring(spellID)] = nil
	local resolved = ns.API.Resolve(spellID)
	if resolved and resolved ~= spellID then
		holdUntil[cdKey(resolved)] = nil
		holdUntil["id:" .. tostring(resolved)] = nil
	end
end

local function clearTargetBoundHolds()
	for key, entry in pairs(holdUntil) do
		if type(entry) == "number" then
			holdUntil[key] = nil
		elseif type(entry) == "table" and entry.guid ~= "self" then
			holdUntil[key] = nil
		end
	end
end

function ns.API.NoteSpellHold(spellID, seconds)
	seconds = tonumber(seconds)
	if not spellID or not seconds or seconds <= 0 then
		return
	end
	local exp = GetTime() + seconds
	local guid = "self"
	if holdBindsToTarget(spellID) then
		guid = holdTargetGuid() or false
	end
	writeHold(spellID, exp, guid)
end

function ns.API.HoldRemain(spellID)
	if not spellID then
		return 0
	end
	local entry = holdUntil[cdKey(spellID)] or holdUntil["id:" .. tostring(spellID)]
	if not entry then
		local resolved = ns.API.Resolve(spellID)
		if resolved then
			entry = holdUntil[cdKey(resolved)] or holdUntil["id:" .. tostring(resolved)]
		end
	end
	if not entry then
		return 0
	end
	-- Legacy plain number = old global hold; keep time-only behaviour.
	local exp, guid
	if type(entry) == "number" then
		exp = entry
		guid = "self"
	elseif type(entry) == "table" then
		exp = entry.exp
		guid = entry.guid
	else
		clearHoldKeys(spellID)
		return 0
	end
	if not exp then
		clearHoldKeys(spellID)
		return 0
	end
	if guid ~= "self" then
		-- Bound to a mob: new target, no target, or dead sticky target -> re-suggest.
		if guid == false or guid == nil then
			clearHoldKeys(spellID)
			return 0
		end
		local cur = holdTargetGuid()
		if not cur or cur ~= guid or unitIsDead("target") then
			clearHoldKeys(spellID)
			return 0
		end
	end
	local remain = exp - GetTime()
	if remain <= 0 then
		clearHoldKeys(spellID)
		return 0
	end
	return remain
end

local function trackedRemain(spellID)
	local exp = cdUntil[cdKey(spellID)] or cdUntil["id:" .. tostring(spellID)]
	if not exp then
		return 0
	end
	local remain = exp - GetTime()
	if remain <= 0 then
		cdUntil[cdKey(spellID)] = nil
		cdUntil["id:" .. tostring(spellID)] = nil
		return 0
	end
	return remain
end

local function readSpellCooldown(spellID)
	if not spellID or not C_Spell or not C_Spell.GetSpellCooldown then
		return 0, 0, true
	end
	local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" then
		return 0, 0, true
	end
	local start = info.startTime or info.start
	local duration = info.duration
	if (start ~= nil and not readable(start)) or (duration ~= nil and not readable(duration)) then
		return 0, 0, true
	end
	start = tonumber(start) or 0
	duration = tonumber(duration) or 0
	local remain = duration - (GetTime() - start)
	if remain < 0 then
		remain = 0
	end
	if duration > 0 and duration <= 1.51 then
		return 0, duration, false
	end
	return remain, duration, false
end

function ns.API.Cooldown(spellID)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID then
		return 0, 0
	end
	local apiRemain, apiDuration, secret = readSpellCooldown(spellID)
	local key = cdKey(spellID)
	if not secret and apiDuration and apiDuration > 1.51 then
		cdKnown[key] = apiDuration
	end
	local tracked = trackedRemain(spellID)
	if predict then
		local pred = predict.cd[cdKey(spellID)] or predict.cd["id:" .. tostring(spellID)]
		if pred then
			local predRemain = pred - GetTime()
			if predRemain > tracked then
				tracked = predRemain
			end
		end
	end
	if tracked > 0.2 then
		-- A readable real cooldown wins over the estimate from the base
		-- cooldown: talents can shorten it (Reverberation, Improved Fire Blast).
		if not secret and apiDuration and apiDuration > 1.51 then
			return apiRemain, apiDuration
		end
		return tracked, apiDuration > 0 and apiDuration or tracked
	end
	if secret then
		return 0, 0
	end
	return apiRemain, apiDuration
end

local function unitExists(unit)
	if not unit then
		return false
	end
	local ok, exists = pcall(UnitExists, unit)
	return ok and exists and true or false
end

local function unitFriendly(unit)
	if not unitExists(unit) then
		return false
	end
	local okDead, dead = pcall(UnitIsDead, unit)
	if okDead and dead then
		return false
	end
	local okAtk, atk = pcall(UnitCanAttack, "player", unit)
	if okAtk and readable(atk) and atk then
		return false
	end
	if okAtk and not readable(atk) then
		return false
	end
	local okR, react = pcall(UnitReaction, "player", unit)
	if okR and readable(react) and type(react) == "number" then
		return react > 4
	end
	if okAtk and readable(atk) and not atk then
		return true
	end
	return false
end

local function healNameSet()
	if healNames and next(healNames) then
		return healNames
	end
	healNames = {}
	for id in pairs(ns.HEAL_SPELL_IDS or {}) do
		local name = ns.API.SpellName(id)
		if name then
			healNames[name] = true
		end
	end
	return healNames
end

function ns.API.IsHelpful(spellID, opt)
	if opt and opt.heal then
		return true
	end
	local id = ns.API.Resolve(spellID) or spellID
	if ns.HEAL_SPELL_IDS and ((id and ns.HEAL_SPELL_IDS[id]) or (spellID and ns.HEAL_SPELL_IDS[spellID])) then
		return true
	end
	local name = ns.API.SpellName(id) or ns.API.SpellName(spellID)
	if name and healNameSet()[name] then
		return true
	end
	if C_Spell and C_Spell.IsSpellHelpful then
		local ok, helpful = pcall(C_Spell.IsSpellHelpful, id)
		if ok and helpful == true then
			return true
		end
	end
	return false
end

function ns.API.IsHealSpell(spellID, opt)
	if opt and opt.heal then
		return true
	end
	if not spellID then
		return false
	end
	if ns.IsMaintenanceBuff and ns.IsMaintenanceBuff(spellID) then
		return false
	end
	if ns.IsWeaponBuff and ns.IsWeaponBuff(spellID) then
		return false
	end
	local id = ns.API.Resolve(spellID) or spellID
	if ns.HEAL_SPELL_IDS and ((id and ns.HEAL_SPELL_IDS[id]) or ns.HEAL_SPELL_IDS[spellID]) then
		return true
	end
	local name = ns.API.SpellName(id) or ns.API.SpellName(spellID)
	if name and healNameSet()[name] then
		return true
	end
	return false
end

function ns.API.IsHarmful(spellID)
	local id = ns.API.Resolve(spellID) or spellID
	if C_Spell and C_Spell.IsSpellHarmful then
		local ok, harmful = pcall(C_Spell.IsSpellHarmful, id)
		if ok and harmful == true then
			return true
		end
	end
	return false
end

local function numberOrNil(value)
	value = safe(value, nil)
	if type(value) == "number" and value == value then
		return value
	end
	return nil
end

function ns.API.SpellMaxRange(spellID)
	local id = ns.API.Resolve(spellID) or spellID
	if not id then
		return nil
	end
	local info = ns.API.SpellInfo(id)
	if info then
		local maxR = numberOrNil(info.maxRange)
		if maxR ~= nil then
			return maxR
		end
	end
	return nil
end

local function interactInRange(unit, index)
	if not CheckInteractDistance then
		return nil
	end
	local ok, result = pcall(CheckInteractDistance, unit, index)
	if not ok then
		return nil
	end
	result = safe(result, nil)
	if result == true or result == 1 then
		return true
	end
	if result == false or result == 0 then
		return false
	end
	return nil
end

function ns.API.TargetRangeBand(unit)
	unit = unit or "target"
	if not unitExists(unit) then
		return nil, nil
	end
	if UnitDistanceSquared then
		-- Only valid when the client says it measured (group members); for an
		-- enemy it returns 0 with checked = false, which read as "in melee".
		local ok, distSq, checked = pcall(UnitDistanceSquared, unit)
		if ok and not (issecretvalue and (issecretvalue(checked) or issecretvalue(distSq))) and checked == true then
			distSq = numberOrNil(distSq)
			if distSq and distSq >= 0 then
				local yards = math.sqrt(distSq)
				return yards, yards
			end
		end
	end
	-- Classic: 3 ~10 yd (duel), 2 ~11 yd (trade), 1 ~28 yd (inspect).
	local close = interactInRange(unit, 3)
	if close == nil then
		close = interactInRange(unit, 2)
	end
	local inspect = interactInRange(unit, 1)
	if close == true then
		return 0, 11
	end
	if inspect == true then
		return 11, 28
	end
	if inspect == false then
		return 28, 100
	end
	return nil, nil
end

local function rangeUnitFor(spellID, opt)
	opt = opt or {}
	if opt.heal or (ns.API.IsHelpful(spellID, opt) and not ns.API.IsHarmful(spellID)) then
		if ns.API.HealRangeUnit then
			return ns.API.HealRangeUnit(opt)
		end
		return "player"
	end
	return "target"
end

function ns.API.NeedsRange(spellID, opt)
	opt = opt or {}
	if opt.nopet or opt.nocombat then
		return false
	end
	local id = ns.API.Resolve(spellID) or spellID
	if opt.heal then
		local unit = rangeUnitFor(id, opt)
		return unit ~= "player"
	end
	if opt.hostile then
		return true
	end
	if ns.API.IsHarmful(id) then
		return true
	end
	return false
end

-- "none" = no check, "in" / "out" / "unknown".
-- Unknown is never treated as in-range for the first HUD slot.
-- Yard band can override a wrong/secret IsSpellInRange so melee spells
-- stay out at distance and long-range spells can still win slot 1 (all classes).
function ns.API.RangeState(spellID, opt)
	opt = opt or {}
	local id = ns.API.Resolve(spellID) or spellID
	if not id or not ns.API.NeedsRange(id, opt) then
		return "none"
	end
	local unit = rangeUnitFor(id, opt)
	-- A self-cast (heal on yourself) has no distance. The action slot would
	-- report "out of range" while an enemy is targeted, so skip the check.
	if unit == "player" then
		return "in"
	end
	if not unitExists(unit) then
		return "out"
	end
	local maxR = ns.API.SpellMaxRange(id)
	if maxR == 0 and ns.API.IsHarmful(id) then
		maxR = 5
	end
	local minY, maxY = ns.API.TargetRangeBand(unit)
	-- Melee-range spell vs clearly far target: always out (every class).
	if minY and maxR and maxR <= 5 and minY > 8 then
		return "out"
	end
	if minY and maxR and minY >= maxR then
		return "out"
	end
	local slot = ns.SpellBarSlot and ns.SpellBarSlot(id)
	local flag
	if ns.SpellInRange then
		flag = ns.SpellInRange(id, slot)
	end
	if flag == true then
		return "in"
	end
	if flag == false then
		-- Band says the target is inside max range: prefer in when Forever
		-- reports false/secret for long-range shots (Hunter/mage/etc.).
		if maxY and maxR and maxR > 5 and maxY <= maxR then
			return "in"
		end
		return "out"
	end
	if maxY and maxR and maxY <= maxR then
		return "in"
	end
	return "unknown"
end

-- mode: "in" (slot 1), "notOut" (unknown allowed), "any" (lookahead / OOR).
function ns.API.InSpellRange(spellID, opt, mode)
	mode = mode or "in"
	local state = ns.API.RangeState(spellID, opt)
	if state == "none" or state == "in" then
		return true
	end
	if state == "out" then
		return mode == "any"
	end
	return mode ~= "in"
end

-- The unit a heal lands on when pressed from the action bar: the mouseover
-- (only with the client's mouseover cast on), a friendly target, else you
-- (an enemy target or no target heals yourself).
local function mouseoverCastOn()
	if not GetCVarBool then
		return false
	end
	local ok, on = pcall(GetCVarBool, "enableMouseoverCast")
	return ok and on == true
end

function ns.API.HealUnit(opt)
	opt = opt or {}
	if opt.unit and unitExists(opt.unit) then
		return opt.unit
	end
	if mouseoverCastOn() and unitFriendly("mouseover") then
		return "mouseover"
	end
	if unitFriendly("target") then
		return "target"
	end
	return "player"
end

function ns.API.HealHealth(opt)
	return ns.API.Health(ns.API.HealUnit(opt))
end

function ns.API.HealRangeUnit(opt)
	return ns.API.HealUnit(opt)
end


local function hasResources(id)
	if C_Spell and C_Spell.GetSpellPowerCost then
		local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
		if ok and type(costs) == "table" then
			for _, cost in ipairs(costs) do
				if type(cost) == "table" then
					local needed = tonumber(safe(cost.cost, nil))
					local ptype = tonumber(safe(cost.type, nil)) or 0
					-- Negative power types are health costs (Bloodrage, Life Tap): not a resource to wait for.
					if needed and needed > 0 and ptype >= 0 then
						local cur = safe(UnitPower("player", ptype), nil)
						if type(cur) == "number" and cur < needed then
							return false
						end
					end
				end
			end
		end
	end
	return true
end

local function readUsable(fn, id)
	if not fn then
		return nil, nil
	end
	local ok, usable, noMana = pcall(fn, id)
	if not ok then
		return nil, nil
	end
	return safe(usable, nil), safe(noMana, nil)
end

function ns.API.Ready(spellID, opt, ignoreCooldown)
	local id = ns.API.Resolve(spellID)
	if not id then
		return false
	end
	if not ignoreCooldown then
		local remain = ns.API.Cooldown(id)
		if remain > 0.2 then
			return false
		end
	end
	local helpfulOnly = ns.API.IsHelpful(id, opt) and not ns.API.IsHarmful(id)
	local usable, noMana = readUsable(C_Spell and C_Spell.IsSpellUsable, id)
	if noMana == true then
		return false
	end
	if usable == true then
		return true
	end
	if helpfulOnly then
		return hasResources(id)
	end
	-- Camelot marks other spells unusable during a cast or GCD. Fillers
	-- already bypass this; shocks and DoTs must still enter the lookahead.
	if usable == false then
		if ns.API.CastRemain() > 0 then
			return hasResources(id)
		end
		local last = ns.API.lastCastAt
		if last and (GetTime() - last) < 1.55 then
			return hasResources(id)
		end
		return false
	end
	return hasResources(id)
end

-- Why a step is not offered right now (shown on the Rotation / Defense rows).
local rejectReason
local function reject(reason)
	rejectReason = reason
	return false
end

function ns.API.WhyNot(spellID, opt)
	rejectReason = nil
	if ns.API.StepOk(spellID, opt, 0.2) then
		return nil
	end
	return rejectReason or "unknown"
end

function ns.API.StepOk(spellID, opt, timeShift)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID or not ns.API.Known(spellID) then
		return reject("not learned yet")
	end
	opt = opt or {}
	local gate = tonumber(timeShift) or 0.2
	if gate < 0.2 then
		gate = 0.2
	end
	if opt.hostile and not ns.API.Hostile() then
		return reject("needs an enemy target")
	end
	-- Level gate: some spells only pay off later while leveling (longer fights,
	-- bigger mana pool). minLevel = from this character level on.
	if opt.minLevel then
		local ok, level = pcall(UnitLevel, "player")
		level = ok and tonumber(safe(level, nil)) or nil
		if level and level < opt.minLevel then
			return reject(("from level %d"):format(opt.minLevel))
		end
	end
	-- Auto-repeat attacks (Auto Shot): suggest turning it on, never while it
	-- is already running (pressing it again would stop it).
	if opt.autoRepeat then
		local repeating = false
		local check = (C_Spell and C_Spell.IsAutoRepeatSpell) or IsAutoRepeatSpell
		if check then
			local ok, on = pcall(check, spellID)
			repeating = ok and on == true
		end
		if not repeating and IsAutoRepeatSpell and check ~= IsAutoRepeatSpell then
			local ok, on = pcall(IsAutoRepeatSpell, ns.API.SpellName(spellID) or spellID)
			repeating = ok and on == true
		end
		if repeating then
			return reject("already on")
		end
	end
	-- Fight-only buffs (seals, totems, Tiger's Fury): in combat, or right
	-- before a pull with an enemy targeted. Never while just walking around.
	if opt.engaged and not ns.API.InCombat() and not ns.API.Hostile() then
		return reject("only in combat or with an enemy targeted")
	end
	-- An attackable target is needed, without making the spell range-checked
	-- (Stealth / Prowl are cast on yourself).
	if opt.enemyTarget and not ns.API.Hostile() then
		return reject("only with an enemy targeted")
	end
	-- At least one of these must be learned (e.g. an opener to use from Stealth).
	if opt.needKnownAny then
		local anyKnown = false
		for _, other in pairs(opt.needKnownAny) do
			if other and ns.API.Known(other) then
				anyKnown = true
				break
			end
		end
		if not anyKnown then
			return reject("nothing to use it for yet")
		end
	end
	if opt.nocreature and ns.API.CreatureBlocked and ns.API.CreatureBlocked(opt.nocreature) then
		return reject("no effect on this creature type")
	end
	if opt.creature and ns.API.CreatureMatch and not ns.API.CreatureMatch(opt.creature) then
		return reject("only for another creature type")
	end
	if opt.totem then
		local refreshAt = tonumber(opt.refresh)
		if refreshAt == nil then
			refreshAt = 1
		end
		local remain = ns.API.TotemRemain and ns.API.TotemRemain(spellID) or 0
		if remain > refreshAt then
			return reject("totem already up")
		end
	end
	if opt.enemiesMin then
		local n = ns.API.EnemyCount(opt.enemiesYards)
		if (n or 0) < opt.enemiesMin then
			return reject("not enough enemies near you")
		end
	end
	if opt.skipLow and ns.API.Hostile() then
		local floorHp = (ns.API.IsRaidmob and ns.API.IsRaidmob()) and 5 or 20
		if ns.API.Health("target") < floorHp then
			return reject("target is almost dead")
		end
	end
	if opt.targetMana then
		local okCur, current = pcall(UnitPower, "target", 0)
		local okMax, maxp = pcall(UnitPowerMax, "target", 0)
		if not okCur or not readable(current) or current <= 0 then
			return reject("target has no mana")
		end
		if okMax and readable(maxp) and maxp <= 0 then
			return reject("target has no mana")
		end
	end
	if opt.ifTargeting and ns.API.TargetAttacksYou() ~= true then
		return reject("only when the target attacks you")
	end
	-- Backstab / Shred: only from behind. A mob faces whoever it attacks, so
	-- not while it attacks you; after a "must be behind" error, wait a moment.
	if opt.behind then
		if ns.API.NotBehindRecently() then
			return reject("you were not behind the target")
		end
		if ns.API.TargetAttacksYou() ~= false then
			return reject("the target is facing you")
		end
	end
	-- Cast-time spells a melee build only uses to pull.
	if opt.notMelee and ns.API.TargetInMelee() then
		return reject("not in melee range")
	end
	-- Point-blank spells (Frost Nova): only once the target has reached you.
	if opt.inMelee and not ns.API.TargetInMelee() then
		return reject("only when the target is in melee range")
	end
	-- Replaced by a better spell once that one is learned (Imp -> Voidwalker).
	if opt.notKnown and ns.API.Known(opt.notKnown) then
		return reject("a better spell is learned")
	end
	-- Not for this talent tree (word in the name of the tree with the most points).
	if opt.notTree then
		local tree = ns.API.MainTree()
		if tree and tree:find(opt.notTree, 1, true) then
			return reject("not for your talent tree")
		end
	end
	if opt.swimming then
		local ok, swimming = pcall(IsSwimming)
		if not ok or safe(swimming, false) ~= true then
			return reject("only while swimming")
		end
	end
	-- Threat drops (Fade, Feint, Disengage) do nothing with nobody else around.
	if opt.inGroup then
		local ok, grouped = pcall(IsInGroup)
		grouped = ok and safe(grouped, false) == true
		if not grouped and not (opt.orPet and unitExists("pet")) then
			return reject("only in a group")
		end
	end
	if opt.petDead and not ns.API.PetDead() then
		return reject("your pet is not dead")
	end
	if opt.notPetDead and ns.API.PetDead() then
		return reject("your pet is dead")
	end
	local helpful = ns.API.IsHelpful(spellID, opt)
	local auraUnit = helpful and ns.API.HealUnit(opt) or "player"
	-- Aura-first (ConROC-style): readable missing aura -> allow; up with remain
	-- above refresh -> block. stacks=N keeps applying until count reaches N.
	-- Hold is only a Forever fallback when auras lie.
	if opt.nobuff then
		local buffUnit = "player"
		if opt.heal then
			buffUnit = opt.unit or auraUnit
		end
		local found, remain, unreadable, _, stacks = ns.API.FindAura(spellID, buffUnit, "HELPFUL")
		if found then
			local needStacks = tonumber(opt.stacks)
			local refreshAt = tonumber(opt.refresh) or 0
			if needStacks and (stacks or 0) < needStacks then
				if ns.API.HoldRemain(spellID) > 0 then
					clearHoldKeys(spellID)
				end
			elseif remain >= 9000 or refreshAt <= 0 or remain > refreshAt then
				return reject("already active")
			end
		elseif not found and not unreadable then
			if ns.API.HoldRemain(spellID) > 0 then
				clearHoldKeys(spellID)
			end
		end
		if not found and (unreadable or ns.API.InCombat()) and ns.API.HasAura(spellID, buffUnit, "HELPFUL") then
			return reject("already active")
		end
	end
	if opt.nodebuff then
		local debuff = opt.nodebuff == true and spellID or opt.nodebuff
		-- Seals / buffs are "helpful" but judgement/DoT checks always use the enemy.
		local debuffUnit = opt.unit or ((helpful and opt.heal) and auraUnit or "target")
		local found, remain, unreadable, _, stacks = ns.API.FindAura(debuff, debuffUnit, "HARMFUL")
		if found then
			local needStacks = tonumber(opt.stacks)
			local refreshAt = tonumber(opt.refresh)
			if refreshAt == nil then
				refreshAt = 6
			end
			if needStacks and (stacks or 0) < needStacks then
				clearHoldKeys(spellID)
			elseif remain >= 9000 or refreshAt <= 0 or remain > refreshAt then
				return reject("already active")
			else
				clearHoldKeys(spellID)
			end
		elseif not found and not unreadable then
			clearHoldKeys(spellID)
		elseif not found and unreadable and ns.API.HasAura(debuff, debuffUnit, "HARMFUL") then
			return reject("already active")
		end
	end
	local holdLeft = ns.API.HoldRemain(spellID)
	if holdLeft > gate then
		return reject("waiting after the last cast (delay)")
	end
	local needHp = opt.hp
	if opt.hpPerCombo then
		needHp = ns.API.Combo() * opt.hpPerCombo
	end
	if opt.noHpGate then
		-- Health is hidden: the caller checks the threshold another way.
		needHp = nil
	elseif opt.heal or ns.API.IsHealSpell(spellID, opt) then
		needHp = ns.API.AutoHealThreshold(spellID, opt.unit or ns.API.HealUnit(opt), needHp or 99)
	end
	if needHp then
		local hp
		if opt.unit then
			hp = ns.API.Health(opt.unit)
		elseif helpful or opt.heal then
			hp = ns.API.HealHealth(opt)
		else
			hp = ns.API.Health("player")
		end
		if hp > needHp then
			return reject("health is above the heal threshold")
		end
	end
	if opt.form and not ns.API.Form(opt.form) then
		return reject("wrong form or stance")
	end
	if opt.noform and ns.API.Form(opt.noform) then
		return reject("not in this form or stance")
	end
	if opt.combat and not ns.API.InCombat() then
		return reject("only in combat")
	end
	if opt.comboMin and ns.API.Combo() < opt.comboMin then
		local have, source = ns.API.ComboDebug()
		return reject(("not enough combo points (%d of %d, read from %s)"):format(have, opt.comboMin, source))
	end
	if opt.pet and not unitExists("pet") then
		return reject("needs your pet")
	end
	if opt.nopet and unitExists("pet") then
		return reject("pet is already out")
	end
	if opt.nocombat and ns.API.InCombat() then
		return reject("only out of combat")
	end
	if opt.needbuff and not ns.API.HasAura(opt.needbuff, "player", "HELPFUL") then
		return reject("needs a buff you do not have")
	end
	if opt.needanybuff then
		local okBuff = false
		for _, other in ipairs(opt.needanybuff) do
			if ns.API.HasAura(other, "player", "HELPFUL") then
				okBuff = true
				break
			end
		end
		if not okBuff then
			return reject("needs a buff you do not have")
		end
	end
	-- require / requireAny are NOT used to hide list spells. List order is
	-- authoritative: if the player put Frostbolt above Fireball, Frostbolt wins
	-- when it is known and ready. School gating lived here before and skipped
	-- fillers the player had explicitly ordered.
	if opt.needdebuff and not ns.API.HasAura(opt.needdebuff, opt.unit or "target", "HARMFUL") then
		return reject("needs a debuff on the target first")
	end
	if opt.proc or opt.usable then
		local usable = readUsable(C_Spell and C_Spell.IsSpellUsable, spellID)
		if usable ~= true then
			if opt.proc then
				return reject("waiting for its proc")
			end
			if ns.API.CastRemain() <= 0 then
				local last = ns.API.lastCastAt
				if not last or (GetTime() - last) >= 1.55 then
					return reject("not usable right now")
				end
			end
		end
	end
	if opt.manaMax and not opt.noManaGate then
		local okCur, current = pcall(UnitPower, "player", 0)
		local okMax, maxp = pcall(UnitPowerMax, "player", 0)
		if not okCur or not okMax or not readable(current) or not readable(maxp) then
			-- Hidden in combat: ns.GlowHiddenMana shows it instead.
			return reject("mana is hidden right now")
		end
		if maxp <= 0 or (current / maxp) * 100 > opt.manaMax then
			return reject("mana is still high")
		end
	end
	if opt.hpMin then
		local hp = ns.API.Health(opt.unit or "player")
		if hp < opt.hpMin then
			return reject("health too low for it")
		end
	end
	if opt.anybuff then
		for _, other in ipairs(opt.anybuff) do
			if ns.API.HasAura(other, "player", "HELPFUL") then
				return reject("a buff from the same group is already up")
			end
		end
	end
	if opt.anydebuff then
		for _, other in ipairs(opt.anydebuff) do
			if ns.API.HasAura(other, opt.unit or "target", "HARMFUL") then
				return reject("a debuff from the same group is already on the target")
			end
		end
	end
	local remain = ns.API.Cooldown(spellID)
	if ns.API.CastingSpell(spellID) then
		remain = 0
	else
		local castLeft = ns.API.CastRemain()
		if castLeft > 0 and remain > 0 and remain <= castLeft + 0.45 then
			remain = 0
		end
	end
	if not opt.swing and remain > gate then
		return reject("on cooldown")
	end
	if opt.ready == false then
		return true
	end
	if ns.Physics and ns.Physics.IsClip and ns.Physics.IsClip(spellID) and ns.Physics.WouldClip and ns.Physics.WouldClip() then
		return reject("would clip Auto Shot")
	end
	if ns.API.Ready(spellID, opt, true) then
		return true
	end
	-- Fillers skip the strict "usable" test (the client says no during a cast
	-- or GCD), but not when it says you are out of mana: then the next step
	-- (the wand) takes over.
	if opt.filler == true or opt.swing == true then
		local _, noMana = readUsable(C_Spell and C_Spell.IsSpellUsable, spellID)
		if noMana ~= true then
			return true
		end
	end
	-- Out of range is still a queue candidate for slots 2-3. Slot 1
	-- requires RangeState "in" separately. IsSpellUsable is false when OOR.
	if hasResources(spellID) and ns.API.RangeState then
		local reach = ns.API.RangeState(spellID, opt)
		if reach == "out" or reach == "unknown" then
			return true
		end
	end
	if ns.Physics and ns.Physics.EnergySoon and ns.Physics.EnergySoon(spellID) then
		return true
	end
	return reject("not usable right now (stance, rage / mana, or the client says no)")
end

local function auraRemain(aura)
	if not aura then
		return 0
	end
	local exp = safe(aura.expirationTime, nil)
	if exp and exp > 0 then
		local remain = exp - GetTime()
		if remain < 0 then
			remain = 0
		end
		return remain
	end
	return 9999
end

local function auraStacks(aura)
	if type(aura) ~= "table" then
		return 0
	end
	local n = safe(aura.applications, nil)
	if n == nil then
		n = safe(aura.stacks, nil)
	end
	if n == nil then
		n = safe(aura.count, nil)
	end
	if type(n) == "number" and n > 0 then
		return n
	end
	return 1
end

-- Exclusive buff families. An active seal (whatever its rank ID) counts for
-- all seals: the Forever client often hides the aura ID as soon as a target
-- is selected.
local AURA_FAMILIES = {
	{ key = "seal", tokens = { "seal" } },
	{ key = "blessing", tokens = { "blessing" } },
	{ key = "palaura", tokens = { "aura" } },
	{ key = "aspect", tokens = { "aspect" } },
	{ key = "magearmor", tokens = { "ice armor", "frost armor", "mage armor" } },
	{ key = "lockarmor", tokens = { "demon skin", "demon armor" } },
}

local heldNames = {}
local heldFamilies = {}
local buffCastAt = {}

local FAMILY_SECONDS = {
	seal = 30,
	blessing = 300,
	palaura = 1800,
	aspect = 1800,
	magearmor = 1800,
	lockarmor = 1800,
}

local function normName(name)
	local n = strlower(name)
	n = n:gsub("%s*%([^%)]*%)", "")
	n = strtrim(n)
	return n
end

-- Combo points. The client may hide them in combat (secret values), so a
-- count of builders and finishers since the last target change backs them up.
local comboEstimate = 0
local comboBuilders, comboFinishers

local function comboNameSets()
	if comboBuilders then
		return
	end
	comboBuilders, comboFinishers = {}, {}
	local R, D = ns.Spell.Rogue or {}, ns.Spell.Druid or {}
	local function add(set, id)
		local name = id and ns.API.SpellName(id)
		if name then
			set[name] = true
		end
	end
	-- By key, so a spell missing from ns.Spell does not cut the list short.
	for _, key in ipairs({ "SinisterStrike", "Backstab", "Hemorrhage", "GhostlyStrike", "Ambush", "Garrote", "Gouge", "Mutilate" }) do
		add(comboBuilders, R[key])
	end
	for _, key in ipairs({ "Claw", "Shred", "Rake", "Ravage", "Pounce", "MangleCat" }) do
		add(comboBuilders, D[key])
	end
	for _, key in ipairs({ "Eviscerate", "SliceandDice", "Rupture", "KidneyShot", "ExposeArmor", "Venom" }) do
		add(comboFinishers, R[key])
	end
	for _, key in ipairs({ "FerociousBite", "Rip" }) do
		add(comboFinishers, D[key])
	end
	-- Names not loaded yet: try again next time.
	if not next(comboBuilders) then
		comboBuilders, comboFinishers = nil, nil
	end
end

function ns.API.NoteComboCast(spellID)
	local name = spellID and ns.API.SpellName(spellID)
	if not name then
		return
	end
	comboNameSets()
	if not comboBuilders then
		return
	end
	if comboFinishers[name] then
		comboEstimate = 0
	elseif comboBuilders[name] then
		comboEstimate = math.min(5, comboEstimate + 1)
	end
end

function ns.API.ResetComboEstimate()
	comboEstimate = 0
end

-- The highest of: player power 4 (modern), GetComboPoints on the target
-- (Classic), and the cast count. One source may read 0 on this client while
-- another has the real value, so none of them is trusted alone.
local lastComboSource = "count"

local function rawCombo()
	local best, source = comboEstimate, "count"
	local okP, power = pcall(UnitPower, "player", 4)
	if okP and readable(power) and type(power) == "number" and power > best then
		best, source = power, "power"
	end
	if GetComboPoints then
		local ok, points = pcall(GetComboPoints, "player", "target")
		if ok and readable(points) and type(points) == "number" and points > best then
			best, source = points, "target"
		end
	end
	lastComboSource = source
	return best
end

function ns.API.ComboDebug()
	local value = rawCombo()
	return value, lastComboSource
end

function ns.API.PredictBegin()
	predict = { debuffs = {}, buffs = {}, cd = {}, usedBuffs = {}, combo = rawCombo(), taken = 0 }
end

function ns.API.PredictEnd()
	predict = nil
end

local function predictMarkDebuff(spellID)
	if not predict or not spellID then
		return
	end
	predict.debuffs[spellID] = true
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		predict.debuffs[normName(name)] = true
	end
end

local function predictMarkBuff(spellID)
	if not predict or not spellID then
		return
	end
	predict.buffs[spellID] = true
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		predict.buffs[normName(name)] = true
	end
end

local function isComboBuilder(spellID)
	local builders = ns.COMBO_BUILDERS
	if not builders or not spellID then
		return false
	end
	if builders[spellID] then
		return true
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	for id in pairs(builders) do
		if ns.API.SpellName(id) == name then
			return true
		end
	end
	return false
end

function ns.API.PredictConsume(spellID, opt)
	if not predict then
		return
	end
	spellID = ns.API.Resolve(spellID) or spellID
	opt = opt or {}
	predict.taken = (predict.taken or 0) + 1
	if opt.nodebuff then
		local debuff = opt.nodebuff == true and spellID or opt.nodebuff
		predictMarkDebuff(debuff)
		predictMarkDebuff(spellID)
	end
	if type(opt.anydebuff) == "table" then
		for _, id in ipairs(opt.anydebuff) do
			predictMarkDebuff(id)
		end
	end
	if opt.needdebuff then
		predictMarkDebuff(opt.needdebuff)
	end
	if opt.nobuff then
		predictMarkBuff(spellID)
	end
	if type(opt.anybuff) == "table" then
		for _, id in ipairs(opt.anybuff) do
			predictMarkBuff(id)
		end
	end
	if opt.needbuff then
		predict.usedBuffs[opt.needbuff] = true
		local name = ns.API.SpellName(opt.needbuff)
		if type(name) == "string" and name ~= "" then
			predict.usedBuffs[normName(name)] = true
		end
	end
	if opt.comboMin then
		predict.combo = 0
	elseif isComboBuilder(spellID) then
		predict.combo = math.min(5, (predict.combo or 0) + 1)
	end
	if opt.filler == true or opt.swing == true then
		return
	end
	local seconds = ns.API.SpellCooldownSec(spellID)
	if not seconds or seconds <= 0.2 then
		return
	end
	local exp = GetTime() + seconds
	predict.cd[cdKey(spellID)] = exp
	predict.cd["id:" .. tostring(spellID)] = exp
	local group = groupOf(spellID)
	if not group then
		return
	end
	for _, id in ipairs(group.ids) do
		predict.cd[cdKey(id)] = exp
		predict.cd["id:" .. tostring(id)] = exp
	end
end

local function targetGuid()
	local ok, guid = pcall(UnitGUID, "target")
	if ok and readable(guid) and type(guid) == "string" then
		return guid
	end
	return nil
end

function ns.API.ClearTargetDebuffs()
	wipe(heldHarmful)
	heldHarmfulGuid = nil
	clearTargetBoundHolds()
end

-- remain: the duration seen on the target, if any. Otherwise the spell's
-- own duration (ns.SPELL_HOLD / step hold), else 18 s.
function ns.API.NoteTargetDebuff(spellID, remain)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local okExists, exists = pcall(UnitExists, "target")
	if not okExists or not exists then
		return
	end
	local guid = targetGuid()
	if heldHarmfulGuid and guid and heldHarmfulGuid ~= guid then
		wipe(heldHarmful)
	end
	heldHarmfulGuid = guid
	local name = ns.API.SpellName(spellID)
	local seconds = tonumber(remain)
	if not seconds or seconds <= 0 or seconds >= 9000 then
		seconds = ns.API.HoldSeconds(spellID)
		if not seconds or seconds <= 0 then
			seconds = 18
		end
	end
	local exp = GetTime() + seconds
	if type(name) == "string" and name ~= "" then
		heldHarmful[normName(name)] = exp
	end
	if type(spellID) == "number" then
		heldHarmful["id:" .. tostring(spellID)] = exp
		local resolved = ns.API.Resolve(spellID)
		if resolved and resolved ~= spellID then
			heldHarmful["id:" .. tostring(resolved)] = exp
		end
	end
end

local function heldHarmfulAura(spellID)
	local now = GetTime()
	if type(spellID) == "number" then
		local exp = heldHarmful["id:" .. tostring(spellID)]
		if exp and now < exp then
			return true
		end
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local exp = heldHarmful[normName(name)]
	return exp and now < exp or false
end

local function familyOf(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local n = normName(name)
	for _, family in ipairs(AURA_FAMILIES) do
		for _, token in ipairs(family.tokens) do
			if n:find(token, 1, true) then
				return family.key
			end
		end
	end
end

local function auraIdentity(aura)
	if type(aura) ~= "table" then
		return nil, nil, false
	end
	local auraID = safe(aura.spellId, nil)
	local auraName = safe(aura.name, nil)
	local hidden = (aura.spellId ~= nil and auraID == nil) or (aura.name ~= nil and auraName == nil)
	if not hidden and auraID == nil and auraName == nil then
		hidden = true
	end
	return auraID, auraName, hidden
end

local function rememberAura(spellID, auraName, remain, fromCast)
	local name = auraName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local family = familyOf(name)
	local seconds = family and FAMILY_SECONDS[family]
	if not seconds then
		local hold = ns.API.HoldSeconds(spellID)
		seconds = (hold and hold > 0) and hold or 30
	end
	local exp
	if remain and remain > 0 and remain < 9000 then
		exp = GetTime() + remain
	elseif fromCast or not heldNames[key] or heldNames[key] <= GetTime() then
		exp = GetTime() + seconds
	end
	if exp then
		heldNames[key] = exp
		if family then
			heldFamilies[family] = exp
		end
	end
	if fromCast then
		buffCastAt[key] = GetTime()
		if family then
			buffCastAt[family] = GetTime()
		end
	end
end

function ns.API.NoteSelfBuff(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	-- Attacks are no buff; a heal cast on someone else is not on you.
	if ns.API.IsHarmful(spellID) and not ns.API.IsHelpful(spellID) then
		return
	end
	if ns.API.IsHealSpell(spellID) and ns.API.HealUnit() ~= "player" then
		return
	end
	rememberAura(spellID, nil, nil, true)
end

local function heldAura(spellID, wantName)
	local name = wantName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local now = GetTime()
	local exp = heldNames[normName(name)]
	if exp and now < exp then
		return true
	end
	local family = familyOf(name)
	exp = family and heldFamilies[family]
	return exp and now < exp or false
end

local function releaseAura(spellID, wantName, familiesSeen)
	local name = wantName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local stamped = buffCastAt[key]
	if stamped and (GetTime() - stamped) < 1 then
		return
	end
	heldNames[key] = nil
	local family = familyOf(name)
	if family and not (familiesSeen and familiesSeen[family]) then
		local famStamp = buffCastAt[family]
		if not famStamp or (GetTime() - famStamp) >= 1 then
			heldFamilies[family] = nil
		end
	end
end

local function scanUnitAuras(unit, filter)
	local now = GetTime()
	local key = (unit or "") .. "\0" .. (filter or "")
	local hit = auraScans[key]
	if hit and (now - hit.t) < 0.2 then
		return hit
	end
	local scan = {
		t = now,
		unit = unit,
		filter = filter,
		names = {},
		ids = {},
		families = {},
		unreadable = false,
	}
	auraScans[key] = scan
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		scan.unreadable = true
		return scan
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok then
			scan.unreadable = true
			break
		end
		if not aura then
			if i == 1 and (next(heldNames) or next(heldFamilies)) then
				local busy = ns.API.InCombat and ns.API.InCombat()
				if not busy then
					local okE, exists = pcall(UnitExists, "target")
					busy = okE and exists and true or false
				end
				if busy then
					scan.unreadable = true
				end
			end
			break
		end
		local auraID, auraName, hidden = auraIdentity(aura)
		if hidden then
			scan.unreadable = true
		else
			if auraID then
				scan.ids[auraID] = aura
			end
			if auraName then
				scan.names[normName(auraName)] = aura
				local family = familyOf(auraName)
				if family then
					scan.families[family] = aura
				end
			end
		end
	end
	return scan
end

local function auraBySpellName(unit, name, filter)
	if type(name) ~= "string" or name == "" or not C_UnitAuras then
		return nil
	end
	if C_UnitAuras.GetAuraDataBySpellName then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
		if ok and type(aura) == "table" then
			return aura
		end
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		local ok, auraName, _, _, _, _, _, _, _, auraID = pcall(AuraUtil.FindAuraByName, name, unit, filter)
		if ok and (auraName or auraID) then
			return { name = auraName, spellId = auraID }
		end
	end
end

function ns.API.HasAura(spellID, unit, filter)
	unit = unit or "player"
	filter = filter or "HELPFUL"
	if predict then
		local resolved = ns.API.Resolve(spellID) or spellID
		local name = ns.API.SpellName(resolved or spellID)
		local key = type(name) == "string" and name ~= "" and normName(name) or nil
		if filter == "HELPFUL" and unit == "player" then
			if (resolved and predict.usedBuffs[resolved]) or (spellID and predict.usedBuffs[spellID]) or (key and predict.usedBuffs[key]) then
				return false, 0
			end
		end
		if filter == "HARMFUL" and (unit == "target" or unit == "") then
			if (resolved and predict.debuffs[resolved]) or (spellID and predict.debuffs[spellID]) or (key and predict.debuffs[key]) then
				return true, 9999
			end
		end
		if filter == "HELPFUL" and unit == "player" then
			if (resolved and predict.buffs[resolved]) or (spellID and predict.buffs[spellID]) or (key and predict.buffs[key]) then
				return true, 9999
			end
		end
	end
	local found, remain, unreadable, familiesSeen = ns.API.FindAura(spellID, unit, filter)
	local selfBuff = unit == "player" and filter == "HELPFUL"
	local targetHarm = unit == "target" and filter == "HARMFUL"
	if targetHarm then
		local guid = targetGuid()
		if heldHarmfulGuid and guid and heldHarmfulGuid ~= guid then
			wipe(heldHarmful)
			heldHarmfulGuid = guid
		end
	end
	if found then
		if selfBuff then
			rememberAura(spellID, nil, remain, false)
		end
		if targetHarm then
			ns.API.NoteTargetDebuff(spellID, remain)
		end
		return true, remain
	end
	if selfBuff and unreadable and heldAura(spellID) then
		return true, 9999
	end
	if targetHarm and unreadable and heldHarmfulAura(spellID) then
		return true, 9999
	end
	if selfBuff and not unreadable then
		-- In combat the client may simply return no auras. A long self-buff we
		-- saw or cast is trusted until it runs out; the "not found" only
		-- counts out of combat.
		if heldAura(spellID) and ns.API.InCombat() then
			return true, 9999
		end
		releaseAura(spellID, nil, familiesSeen)
	end
	return false, 0
end

local sharedNames

local function sharedDebuff(spellID, wantKey)
	local ids = ns.SHARED_DEBUFF_IDS
	if not ids then
		return false
	end
	if ids[spellID] then
		return true
	end
	if not sharedNames or not next(sharedNames) then
		sharedNames = {}
		for id in pairs(ids) do
			local name = ns.API.SpellName(id)
			if type(name) == "string" and name ~= "" then
				sharedNames[normName(name)] = true
			end
		end
	end
	return wantKey and sharedNames[wantKey] or false
end

function ns.API.FindAura(spellID, unit, filter)
	if not spellID then
		return false, 0, false, nil, 0
	end
	unit = unit or "player"
	filter = filter or "HELPFUL"
	local resolved = ns.API.Resolve(spellID)
	local wantName = ns.API.SpellName(resolved or spellID) or ns.API.SpellName(spellID)
	local wantKey = type(wantName) == "string" and normName(wantName) or nil
	local wantFamily = familyOf(wantName)
	if filter == "HARMFUL" and unit == "target" and not sharedDebuff(spellID, wantKey) and ns.API.Hostile() then
		filter = "HARMFUL|PLAYER"
	end

	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and unit == "player" then
		for _, id in ipairs({ resolved, spellID }) do
			if id then
				local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
				if ok and type(aura) == "table" then
					return true, auraRemain(aura), false, nil, auraStacks(aura)
				end
			end
		end
	end

	if wantName then
		local named = auraBySpellName(unit, wantName, filter)
		if named then
			local _, _, hidden = auraIdentity(named)
			if not hidden then
				return true, auraRemain(named), false, nil, auraStacks(named)
			end
		end
	end

	local scan = scanUnitAuras(unit, filter)
	if wantKey and scan.names[wantKey] then
		local aura = scan.names[wantKey]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if resolved and scan.ids[resolved] then
		local aura = scan.ids[resolved]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if spellID and scan.ids[spellID] then
		local aura = scan.ids[spellID]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if wantFamily and scan.families[wantFamily] then
		local aura = scan.families[wantFamily]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	return false, 0, scan.unreadable, scan.families, 0
end

function ns.API.HasWeaponBuff(entry)
	if not entry then
		return false, 0
	end
	local ids = { entry.id }
	if entry.ranks then
		for _, id in ipairs(entry.ranks) do
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		local found, remain = ns.API.FindAura(id, "player", "HELPFUL")
		if found then
			return true, remain
		end
	end
	return false, 0
end

function ns.API.Hostile()
	if not UnitExists("target") then
		return false
	end
	local dead = UnitIsDead("target")
	if readable(dead) and dead then
		return false
	end
	local reaction = UnitReaction("player", "target")
	if not readable(reaction) then
		return true
	end
	return reaction <= 4
end

function ns.API.Health(unit)
	unit = unit or "player"
	local health = safe(UnitHealth(unit), nil)
	local max = safe(UnitHealthMax(unit), nil)
	if health and max and max > 0 then
		if unit == "player" then
			ns.API.healthHidden = false
		end
		return (health / max) * 100
	end
	-- Plain values are hidden: ask for the percentage instead.
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
		pct = ok and safe(pct, nil) or nil
		if type(pct) == "number" then
			if unit == "player" then
				ns.API.healthHidden = false
			end
			return pct
		end
	end
	-- Hidden in combat: callers that need a number get 100; the heal cue
	-- switches to a glow whose alpha the client drives (ns.GlowHiddenHeal).
	if unit == "player" then
		ns.API.healthHidden = true
	end
	return 100
end

-- Smart heal threshold: cast a heal once the missing health roughly equals
-- what the spell restores, so it is not wasted. Needs the heal size (parsed
-- from the spell text) and the maximum health (remembered while readable,
-- because the client hides it in combat).
ns.API.healAmountCache = {}
local playerMaxHealth

function ns.API.MaxHealth(unit)
	unit = unit or "player"
	local max = safe(UnitHealthMax(unit), nil)
	if type(max) == "number" and max > 0 then
		if unit == "player" then
			playerMaxHealth = max
		end
		return max
	end
	if unit == "player" then
		return playerMaxHealth
	end
	return nil
end

function ns.API.HealAmount(spellID)
	local id = ns.API.Resolve(spellID) or spellID
	if not id then
		return nil
	end
	local cache = ns.API.healAmountCache
	if cache[id] ~= nil then
		return cache[id] or nil
	end
	if not C_Spell or not C_Spell.GetSpellDescription then
		return nil
	end
	local ok, desc = pcall(C_Spell.GetSpellDescription, id)
	desc = ok and safe(desc, nil) or nil
	if type(desc) ~= "string" or desc == "" then
		return nil -- text not loaded yet: ask again next time
	end
	desc = desc:lower():gsub(",", "")
	local lo, hi = desc:match("heal[^%d]*(%d+)%s+to%s+(%d+)")
	local amount
	if lo then
		amount = (tonumber(lo) + tonumber(hi)) / 2
	else
		local single = desc:match("heal[^%d]*(%d+)")
		amount = single and tonumber(single) or nil
	end
	cache[id] = amount or false
	return amount
end

-- Returns the health percent at or below which the heal should be offered.
-- Emergency steps (own threshold under 50) keep their value.
function ns.API.AutoHealThreshold(spellID, unit, fallback)
	if ns.db and ns.db.autoHeal == false then
		return fallback
	end
	if fallback and fallback < 50 then
		return fallback
	end
	local amount = ns.API.HealAmount(spellID)
	local maxHp = ns.API.MaxHealth(unit or "player")
	if not amount or not maxHp or maxHp <= 0 then
		return fallback
	end
	local pct = 100 - (amount / maxHp) * 100
	if pct < 30 then
		pct = 30
	elseif pct > 92 then
		pct = 92
	end
	return pct
end

-- True when the client hides this unit's health (combat), so no number can be compared.
function ns.API.HealthHiddenFor(unit)
	local health = safe(UnitHealth(unit), nil)
	local max = safe(UnitHealthMax(unit), nil)
	if health and max and max > 0 then
		return false
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
		if ok and type(safe(pct, nil)) == "number" then
			return false
		end
	end
	return true
end

-- True when the client hides your mana (combat), so manaMax cannot be compared.
function ns.API.ManaHidden()
	local okCur, current = pcall(UnitPower, "player", 0)
	local okMax, maxp = pcall(UnitPowerMax, "player", 0)
	return not (okCur and okMax and readable(current) and readable(maxp))
end

-- "You must be behind your target": remembered for a few seconds on that target.
local notBehindAt, notBehindGUID
local NOT_BEHIND_SECONDS = 3

local function targetGUID()
	local ok, guid = pcall(UnitGUID, "target")
	return ok and safe(guid, nil) or nil
end

-- Dead hunter pet: seen as a dead "pet" unit, or from the "Your pet is
-- dead" error after the unit is gone. Cleared once a live pet is out.
local petDeadFlag = false

function ns.API.PetDead()
	if unitExists("pet") then
		local ok, dead = pcall(UnitIsDead, "pet")
		petDeadFlag = ok and safe(dead, false) == true
	end
	return petDeadFlag
end

function ns.API.NoteUIError(message)
	if type(message) ~= "string" or not readable(message) then
		return false
	end
	local lower = strlower(message)
	if message == SPELL_FAILED_NOT_BEHIND or lower:find("behind", 1, true) then
		notBehindAt = GetTime()
		notBehindGUID = targetGUID()
		return true
	end
	if lower:find("pet is dead", 1, true) then
		petDeadFlag = true
		return true
	end
	if lower:find("have a pet", 1, true) then
		petDeadFlag = false
		return true
	end
	return false
end

function ns.API.NotBehindRecently()
	if not notBehindAt or (GetTime() - notBehindAt) > NOT_BEHIND_SECONDS then
		return false
	end
	local guid = targetGUID()
	return guid == nil or notBehindGUID == nil or guid == notBehindGUID
end

function ns.API.HealthHidden()
	ns.API.Health("player")
	return ns.API.healthHidden == true
end

-- Creature types -> canonical EN keys.
local CREATURE_CANON = {
	mechanical = "mechanical",
	machine = "mechanical",
	elemental = "elemental",
	undead = "undead",
	demon = "demon",
}

local function creatureCanon(ctype)
	if type(ctype) ~= "string" or ctype == "" then
		return nil
	end
	local key = strlower(ctype)
	return CREATURE_CANON[key] or key
end

local function targetCreatureCanon()
	if not unitExists("target") then
		return nil
	end
	-- Secret when the unit is not player-controlled or in your group
	-- (SecretWhenUnitIdentityRestricted): then the type is unknown.
	local ok, ctype = pcall(UnitCreatureType, "target")
	if not ok or not readable(ctype) or type(ctype) ~= "string" or ctype == "" then
		return nil
	end
	return creatureCanon(ctype)
end

local function creatureListHas(list, canon)
	if not canon then
		return false
	end
	if list == true then
		return canon == "mechanical" or canon == "elemental"
	end
	if type(list) == "string" then
		return canon == creatureCanon(list)
	end
	if type(list) == "table" then
		for _, name in ipairs(list) do
			if type(name) == "string" and canon == creatureCanon(name) then
				return true
			end
		end
	end
	return false
end

function ns.API.CreatureBlocked(list)
	if list == nil or list == false then
		return false
	end
	return creatureListHas(list, targetCreatureCanon())
end

function ns.API.CreatureMatch(list)
	if list == nil or list == false then
		return true
	end
	local canon = targetCreatureCanon()
	if not canon then
		-- Unknown type: let the step through; Exorcism's own "usable" check
		-- still refuses a wrong target.
		return true
	end
	return creatureListHas(list, canon)
end

function ns.API.IsRaidmob()
	if not unitExists("target") then
		return false
	end
	local okC, classification = pcall(UnitClassification, "target")
	if okC and type(classification) == "string" then
		if classification == "worldboss" or classification == "rareelite" or classification == "elite" then
			return true
		end
	end
	local okT, tlvl = pcall(UnitLevel, "target")
	local okP, plvl = pcall(UnitLevel, "player")
	if okT and okP and type(tlvl) == "number" and type(plvl) == "number" then
		if tlvl < 0 or tlvl > plvl + 2 then
			return true
		end
	end
	return false
end

-- Totems. GetTotemInfo is secret in combat (SecretWhenTotemSlotSecret), so
-- readable reads teach each totem's slot and duration and our own casts
-- stand in during combat (one totem per slot: a new one replaces the old).
-- A totem you walked away from (UnitPosition, more than TOTEM_RANGE yards)
-- counts as gone, so a new pull gets a new one.
local TOTEM_RANGE = 20
local totemSlotOf, totemSecondsOf = {}, {}
local totemOut = {}
local totemInfoByName

local function totemFamily(key)
	return (key:gsub("%s+totem$", ""):gsub("^totem%s+", ""))
end

local function totemMatches(key, wantKey, wantFamily)
	if key == wantKey then
		return true
	end
	local family = totemFamily(key)
	return family == wantFamily or key:find(wantFamily, 1, true) ~= nil
end

local function totemInfo(spellID, key)
	local map = ns.TOTEM_INFO
	if not map then
		return nil
	end
	local resolved = ns.API.Resolve(spellID) or spellID
	if map[resolved] or map[spellID] then
		return map[resolved] or map[spellID]
	end
	if not totemInfoByName or not next(totemInfoByName) then
		totemInfoByName = {}
		for id, row in pairs(map) do
			local name = ns.API.SpellName(id)
			if type(name) == "string" and name ~= "" then
				totemInfoByName[normName(name)] = row
			end
		end
	end
	return key and totemInfoByName[key] or nil
end

local function playerSpot()
	local ok, x, y, _, map = pcall(UnitPosition, "player")
	if not ok then
		return nil
	end
	x, y, map = safe(x, nil), safe(y, nil), safe(map, nil)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return x, y, map
end

local function walkedAway(entry)
	if not entry or not entry.x then
		return false
	end
	local x, y, map = playerSpot()
	if not x then
		return false
	end
	if map ~= entry.map then
		return true
	end
	local dx, dy = x - entry.x, y - entry.y
	return dx * dx + dy * dy > TOTEM_RANGE * TOTEM_RANGE
end

local function readTotemSlot(slot)
	local ok, haveTotem, totemName, startTime, duration = pcall(GetTotemInfo, slot)
	if not ok or not readable(haveTotem) then
		return nil
	end
	if not haveTotem then
		return false
	end
	if not readable(totemName) or not readable(startTime) or not readable(duration) or type(totemName) ~= "string" or totemName == "" then
		return nil
	end
	return normName(totemName), tonumber(startTime) or 0, tonumber(duration) or 0
end

-- A readable slot: learn the totem's slot and duration, keep our cast
-- record (with its position) when it is the same totem.
local function syncTotemSlot(slot, key, startTime, duration)
	totemSlotOf[key] = slot
	if duration > 0 then
		totemSecondsOf[key] = duration
	end
	local entry = totemOut[slot]
	if not (entry and entry.key == key and math.abs(entry.at - startTime) < 2) then
		totemOut[slot] = { key = key, at = startTime, seconds = duration }
	else
		entry.at, entry.seconds = startTime, duration
	end
end

function ns.API.NoteTotemCast(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local row = totemInfo(spellID, key)
	local slot = totemSlotOf[key] or (row and row.slot)
	if not slot then
		return
	end
	local x, y, map = playerSpot()
	totemOut[slot] = {
		key = key,
		at = GetTime(),
		seconds = totemSecondsOf[key] or (row and row.seconds) or 60,
		x = x,
		y = y,
		map = map,
	}
end

function ns.API.NoteTotemSlot(slot)
	slot = tonumber(slot)
	if not slot then
		return
	end
	local key, startTime, duration = readTotemSlot(slot)
	if key == false then
		totemOut[slot] = nil
	elseif key then
		syncTotemSlot(slot, key, startTime, duration)
	end
end

function ns.API.ClearTotems()
	wipe(totemOut)
end

function ns.API.TotemRemain(spellID)
	if not spellID or not GetTotemInfo then
		return 0
	end
	local wantName = ns.API.SpellName(ns.API.Resolve(spellID) or spellID) or ns.API.SpellName(spellID)
	if type(wantName) ~= "string" or wantName == "" then
		return 0
	end
	local wantKey = normName(wantName)
	local wantFamily = totemFamily(wantKey)
	local now = GetTime()
	for slot = 1, 4 do
		local key, startTime, duration = readTotemSlot(slot)
		if key == false then
			totemOut[slot] = nil
		elseif key then
			syncTotemSlot(slot, key, startTime, duration)
		end
		local entry = totemOut[slot]
		if entry and totemMatches(entry.key, wantKey, wantFamily) then
			local remain = entry.at + entry.seconds - now
			if remain <= 0 or walkedAway(entry) then
				return 0
			end
			return remain
		end
	end
	return 0
end

-- True when the target attacks you, false when it attacks someone else or
-- no one, nil when unknown. UnitThreatSituation("player", "target") is not
-- secret (SecretWhenUnitThreatStateRestricted: player vs target is allowed);
-- 2 / 3 mean you have aggro. UnitIsUnit("targettarget", ...) is a compound
-- token, always secret on addon-restricted maps, so it is only a fallback.
function ns.API.TargetAttacksYou()
	if not unitExists("target") then
		return false
	end
	if UnitThreatSituation then
		local ok, status = pcall(UnitThreatSituation, "player", "target")
		if ok and readable(status) and type(status) == "number" then
			return status >= 2
		end
	end
	if not unitExists("targettarget") then
		return false
	end
	local ok, onMe = pcall(UnitIsUnit, "targettarget", "player")
	if ok and readable(onMe) then
		return onMe == true
	end
	return nil
end

function ns.API.TargetInMelee()
	if not unitExists("target") or not ns.API.Hostile() then
		return false
	end
	-- Distance band first: never treat a far target as melee (role auto + queue).
	local minY, maxY = ns.API.TargetRangeBand("target")
	if minY and minY > 8 then
		return false
	end
	if maxY and maxY <= 5 then
		return true
	end
	local token = ns.ClassToken and ns.ClassToken()
	local probe
	local S = ns.Spell
	if token == "HUNTER" and S and S.Hunter then
		probe = S.Hunter.RaptorStrike or S.Hunter.WingClip or S.Hunter.MongooseBite
	elseif token == "SHAMAN" and S and S.Shaman then
		probe = S.Shaman.Stormstrike or S.Shaman.LavaLash or S.Shaman.EarthShock
	elseif token == "WARRIOR" and S and S.Warrior then
		probe = S.Warrior.HeroicStrike or S.Warrior.Rend
	elseif token == "ROGUE" and S and S.Rogue then
		probe = S.Rogue.SinisterStrike
	elseif token == "DRUID" and S and S.Druid then
		probe = S.Druid.Claw or S.Druid.Mangle or S.Druid.Maul
	elseif token == "PALADIN" and S and S.Paladin then
		probe = S.Paladin.CrusaderStrike or S.Paladin.Judgement
	end
	if probe then
		local state = ns.API.RangeState(probe, { hostile = true })
		if state == "in" then
			return true
		end
		if state == "out" then
			return false
		end
	end
	if minY and minY <= 5 then
		return true
	end
	local close = interactInRange("target", 3)
	return close == true
end

function ns.API.CombatNotice()
	local token = ns.ClassToken and ns.ClassToken()
	if token ~= "HUNTER" and token ~= "WARLOCK" then
		return nil
	end
	if not ns.API.InCombat() then
		return nil
	end
	-- Only once a pet can be summoned: hunters get Call Pet around level 10,
	-- and a warlock may not have a demon spell yet.
	local summons
	if token == "HUNTER" then
		summons = { "CallPet" }
	else
		summons = { "SummonImp", "SummonVoidwalker", "SummonSuccubus", "SummonFelhunter", "SummonIncubus", "SummonFelguard" }
	end
	local book = token == "HUNTER" and ns.Spell.Hunter or ns.Spell.Warlock
	local canSummon = false
	for _, key in ipairs(summons) do
		local id = book and book[key]
		if id and ns.API.Known(id) then
			canSummon = true
			break
		end
	end
	if not canSummon then
		return nil
	end
	if not unitExists("pet") then
		return token == "WARLOCK" and "NOTICE_SUMMON_DEMON" or "NOTICE_CALL_PET"
	end
	if not ns.API.Hostile() then
		return nil
	end
	local okT, hasPetTarget = pcall(UnitExists, "pettarget")
	if okT and not hasPetTarget then
		return "NOTICE_PET_ASSIST"
	end
	local okC, petCombat = pcall(UnitAffectingCombat, "pet")
	if okC and petCombat == false then
		return "NOTICE_PET_ASSIST"
	end
	return nil
end

-- Role from the talent tree with the most points, judged by the tree's name
-- (not its position or the role the client reports, which can differ on
-- Forever): Protection = tank, Holy / Discipline / Restoration = heal,
-- anything else = damage. Cached for a few seconds; nil = no talent data yet.
local TANK_TREE_WORDS = { "protection" }
local HEAL_TREE_WORDS = { "restoration", "holy", "discipline" }
local specRoleCache, specRoleAt = nil, -10
local treeCache, treeAt = nil, -10

-- Lower-case name of the talent tree with the most points; nil = no points
-- or no talent data yet. Cached for a few seconds.
function ns.API.MainTree()
	local now = GetTime()
	if treeAt > 0 and now - treeAt < 3 then
		return treeCache
	end
	treeAt = now
	treeCache = nil
	local info = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
	if not info then
		return nil
	end
	local bestPoints = 0
	for index = 1, 4 do
		local ok, specId, name, _, _, _, _, points = pcall(info, index)
		if not ok or not specId or specId == 0 then
			break
		end
		points = tonumber(safe(points, 0)) or 0
		if points > bestPoints and type(name) == "string" and readable(name) then
			bestPoints = points
			treeCache = name:lower()
		end
	end
	return treeCache
end

local function specRole()
	local now = GetTime()
	if specRoleAt > 0 and now - specRoleAt < 3 then
		return specRoleCache
	end
	specRoleAt = now
	specRoleCache = nil
	local bestName = ns.API.MainTree()
	if not bestName then
		return nil
	end
	specRoleCache = "damage"
	for _, word in ipairs(TANK_TREE_WORDS) do
		if bestName:find(word, 1, true) then
			specRoleCache = "tank"
		end
	end
	for _, word in ipairs(HEAL_TREE_WORDS) do
		if bestName:find(word, 1, true) then
			specRoleCache = "heal"
		end
	end
	return specRoleCache
end

-- Picks the playstyle from the character, no clicking needed: talent tree,
-- defensive stance / Righteous Fury, and melee range for hunter / shaman.
function ns.SyncAutoRole()
	if not ns.db or ns.db.roleAuto == false then
		return
	end
	local token = ns.ClassToken and ns.ClassToken()
	local want
	if token == "HUNTER" then
		if not ns.API.Hostile() or not unitExists("target") then
			return
		end
		want = ns.API.TargetInMelee() and "melee" or "range"
	elseif token == "WARRIOR" or token == "PALADIN" or token == "PRIEST" or token == "SHAMAN" or token == "DRUID" then
		local spec = specRole()
		if spec == nil and (token ~= "SHAMAN" or ns.db.role == "heal") then
			-- No talent data yet (low level): keep whatever is set.
			return
		end
		if spec == "tank" or spec == "heal" then
			want = spec
		elseif token == "SHAMAN" then
			-- Damage shaman: caster at range, melee when in reach of the target.
			if not ns.API.Hostile() or not unitExists("target") then
				if ns.db.role == "heal" then
					want = "caster"
				else
					return
				end
			else
				want = ns.API.TargetInMelee() and "melee" or "caster"
			end
		elseif token == "DRUID" then
			want = "hybrid"
		else
			want = "damage"
		end
	else
		return
	end
	want = ns.NormalizeRole and ns.NormalizeRole(want) or want
	if ns.db.role == want then
		return
	end
	-- In-memory only while fighting: FlushProfile mid-combat feels like lag.
	ns.db.role = want
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.UI and ns.UI.RefreshRoles then
		ns.UI.RefreshRoles()
	end
	if ns.InvalidateTick then
		ns.InvalidateTick()
	end
end

function ns.API.InCombat()
	local ok, combat = pcall(UnitAffectingCombat, "player")
	if ok and readable(combat) then
		return combat and true or false
	end
	return ok and combat and true or false
end

local EAT_AURA = {
	food = true,
	drink = true,
	nourriture = true,
	boisson = true,
	essen = true,
	trinken = true,
	comida = true,
	bebida = true,
}

function ns.API.IsEating()
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then
			break
		end
		local name = safe(aura.name, nil)
		if name then
			if EAT_AURA[strlower(name)] then
				return true
			end
		end
	end
	return false
end

function ns.API.ShouldHideIdle()
	if not ns.db then
		return false
	end
	local function yes(fn, ...)
		if type(fn) ~= "function" then
			return false
		end
		local ok, value = pcall(fn, ...)
		return ok and value == true
	end
	if yes(UnitIsDeadOrGhost, "player") or yes(UnitOnTaxi, "player") or yes(IsMounted) then
		return true
	end
	if ns.API.IsEating() == true then
		return true
	end
	if not ns.API.InCombat() and yes(IsResting) then
		return true
	end
	return false
end

function ns.API.UnitFriendly(unit)
	return unitFriendly(unit)
end

function ns.API.CastRemain()
	local function remain(fn)
		if not fn then
			return 0
		end
		local ok, name, _, _, _, endTime = pcall(fn, "player")
		if not ok or name == nil then
			return 0
		end
		if issecretvalue and issecretvalue(name) then
			return 0
		end
		endTime = tonumber(safe(endTime, nil))
		if not endTime then
			return 0
		end
		if endTime > 100000 then
			endTime = endTime / 1000
		end
		local left = endTime - GetTime()
		if left < 0 then
			return 0
		end
		return left
	end
	local cast = remain(UnitCastingInfo)
	if cast > 0 then
		return cast
	end
	return remain(UnitChannelInfo)
end

function ns.API.CastingSpell(spellID)
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local function same(fn)
		if not fn then
			return false
		end
		local ok, castName = pcall(fn, "player")
		if not ok or type(castName) ~= "string" or castName == "" then
			return false
		end
		if issecretvalue and issecretvalue(castName) then
			return false
		end
		return castName == name
	end
	return same(UnitCastingInfo) or same(UnitChannelInfo)
end

function ns.API.TargetCasting()
	if not UnitExists("target") then
		return false
	end
	-- notInterruptible is return 8 of UnitCastingInfo (after castID) and
	-- return 7 of UnitChannelInfo.
	local function peek(fn, kickIndex)
		if not fn then
			return false, nil
		end
		local ok, name = pcall(fn, "target")
		if not ok or name == nil then
			return false, nil
		end
		local okKick, notKick = pcall(function()
			return (select(kickIndex, fn("target")))
		end)
		if okKick and readable(notKick) and notKick then
			return false, true
		end
		return true, false
	end
	local casting = peek(UnitCastingInfo, 8)
	if casting then
		return true
	end
	casting = peek(UnitChannelInfo, 7)
	if casting then
		return true
	end
	return ns.API.castTarget == true
end

function ns.API.TargetCastProgress()
	if not UnitExists or not UnitExists("target") then
		return nil
	end
	local function millis(value)
		if not readable(value) then
			return nil
		end
		local ok, n = pcall(function()
			local v = tonumber(value)
			if type(v) ~= "number" then
				return nil
			end
			return v + 0
		end)
		if ok and type(n) == "number" then
			return n
		end
		return nil
	end
	local function slice(fn, channel)
		if type(fn) ~= "function" then
			return nil
		end
		local pack = { pcall(fn, "target") }
		if not pack[1] or not readable(pack[2]) then
			return nil
		end
		local notKick = channel and pack[8] or pack[9]
		if readable(notKick) and notKick then
			return nil
		end
		local startMS = millis(pack[5])
		local endMS = millis(pack[6])
		if not startMS or not endMS or endMS <= startMS then
			return nil
		end
		local span = endMS - startMS
		local progress = ((GetTime() * 1000) - startMS) / span
		if progress < 0 then
			progress = 0
		end
		if progress > 1 then
			progress = 1
		end
		return progress
	end
	local cast = slice(UnitCastingInfo, false)
	if cast then
		return cast
	end
	return slice(UnitChannelInfo, true)
end

function ns.API.Purgable(stealableOnly)
	if not UnitExists("target") or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HELPFUL")
		if not ok or not aura then
			break
		end
		if stealableOnly then
			if readable(aura.isStealable) and aura.isStealable then
				return true
			end
		else
			if readable(aura.isStealable) and aura.isStealable then
				return true
			end
			local dispel = safe(aura.dispelName, nil)
			if dispel == "Magic" then
				return true
			end
		end
	end
	return false
end

function ns.API.HasDebuffType(types, unit)
	if not types or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	if unit and unit ~= "player" and not unitFriendly(unit) then
		return false
	end
	unit = unit or "player"
	local want = {}
	for _, name in ipairs(types) do
		want[name] = true
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
		if not ok or not aura then
			break
		end
		local dispel = safe(aura.dispelName, nil)
		if dispel and want[dispel] then
			return true
		end
	end
	return false
end

local function asNumber(value)
	if readable(value) and type(value) == "number" then
		return value
	end
	local ok, n = pcall(tonumber, value)
	if ok and type(n) == "number" then
		return n
	end
	return nil
end

local function pickField(t, key, index)
	if type(t) ~= "table" then
		return nil
	end
	if t[key] ~= nil then
		return t[key]
	end
	return t[index]
end

local function interpretEnchant(has, remainRaw, enchRaw)
	if type(has) == "table" then
		local t = has
		has = pickField(t, "hasMainHandEnchant", 1)
		remainRaw = pickField(t, "mainHandExpiration", 2)
		enchRaw = pickField(t, "mainHandEnchantID", 4)
	end
	local remain = asNumber(remainRaw)
	local enchId = asNumber(enchRaw)
	if remain then
		if remain > 10000 then
			remain = remain / 1000
		end
	else
		remain = 0
	end
	if enchId and enchId > 0 then
		return true, remain > 0 and remain or 9999, enchId
	end
	if type(has) == "table" then
		return nil, 0, nil
	end
	if readable(has) then
		if has then
			return true, remain > 0 and remain or 9999, nil
		end
		return false, 0, 0
	end
	return nil, 0, nil
end

-- Per-slot read (C_PaperDollInfo, what the Blizzard buff frame uses). Returns
-- has, remainSeconds, enchantID; has is nil when the API cannot answer.
local function readTempEnchant(offhand)
	if not C_PaperDollInfo or not C_PaperDollInfo.GetTemporaryEnchantmentInfo then
		return nil
	end
	local slot = offhand and (INVSLOT_OFFHAND or 17) or (INVSLOT_MAINHAND or 16)
	local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, slot)
	if not ok then
		return nil
	end
	if info == nil then
		return false, 0, 0
	end
	if type(info) ~= "table" then
		return nil
	end
	local remainMs = info.remainingTimeMs
	local enchId = info.enchantID
	if not readable(remainMs) or type(remainMs) ~= "number" then
		remainMs = nil
	end
	if not readable(enchId) or type(enchId) ~= "number" then
		enchId = nil
	end
	local remain = remainMs and remainMs / 1000 or 0
	return true, remain > 0 and remain or 9999, enchId
end

local function readWeaponEnchant(offhand)
	local tHas, tRemain, tId = readTempEnchant(offhand)
	if tHas ~= nil then
		return tHas, tRemain, tId
	end
	local packs = {}
	local function push(ok, a, b, c, d, e, f, g, h)
		if ok then
			packs[#packs + 1] = { a, b, c, d, e, f, g, h }
		end
	end
	if GetWeaponEnchantInfo then
		push(pcall(GetWeaponEnchantInfo))
	end
	if C_Item and C_Item.GetWeaponEnchantInfo then
		push(pcall(C_Item.GetWeaponEnchantInfo))
	end
	local bestHas, bestRemain, bestId
	local sawFalse = false
	local sawUnknown = false
	for _, src in ipairs(packs) do
		local has, remain, enchId
		if type(src[1]) == "table" then
			local t = src[1]
			if offhand then
				has, remain, enchId = interpretEnchant(pickField(t, "hasOffHandEnchant", 5), pickField(t, "offHandExpiration", 6), pickField(t, "offHandEnchantID", 8))
			else
				has, remain, enchId = interpretEnchant(t)
			end
		elseif offhand then
			has, remain, enchId = interpretEnchant(src[5], src[6], src[8])
		else
			has, remain, enchId = interpretEnchant(src[1], src[2], src[4])
		end
		if has == true then
			return true, remain, enchId
		end
		if has == false then
			sawFalse = true
		else
			sawUnknown = true
			if bestHas == nil then
				bestHas, bestRemain, bestId = has, remain, enchId
			end
		end
	end
	if sawUnknown then
		return bestHas, bestRemain or 0, bestId
	end
	if sawFalse then
		return false, 0, 0
	end
	return bestHas, bestRemain or 0, bestId
end

function ns.API.WeaponEnchant(offhand)
	return readWeaponEnchant(offhand and true or false)
end

local tooltipCacheAt = 0
local tooltipCacheTexts

local function collectWeaponTooltipTexts()
	local now = GetTime()
	if tooltipCacheTexts and (now - tooltipCacheAt) < 1 then
		return tooltipCacheTexts
	end
	local texts = {}
	local function readSlot(slot)
		if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then
			return
		end
		local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
		if ok and type(data) == "table" and data.lines then
			for _, line in ipairs(data.lines) do
				local text = safe(line.leftText, nil)
				if text then
					texts[#texts + 1] = strlower(text)
				end
			end
		end
	end
	readSlot(16)
	readSlot(17)
	tooltipCacheAt = now
	tooltipCacheTexts = texts
	return texts
end

function ns.API.ClearWeaponTooltipCache()
	tooltipCacheAt = 0
	tooltipCacheTexts = nil
end

function ns.API.WeaponTooltipHas(tokens)
	if not tokens or #tokens == 0 then
		return false
	end
	local texts = collectWeaponTooltipTexts()
	if #texts == 0 then
		return false
	end
	for _, text in ipairs(texts) do
		for _, token in ipairs(tokens) do
			if type(token) == "string" and token ~= "" and text:find(token, 1, true) then
				return true
			end
		end
	end
	return false
end

function ns.API.Form(spellID)
	return ns.API.HasAura(spellID, "player", "HELPFUL")
end

function ns.API.Combo()
	if predict and predict.combo ~= nil then
		return predict.combo
	end
	return rawCombo()
end

function ns.API.Power(kind)
	local map = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
	local token = map[kind] or 0
	local current = safe(UnitPower("player", token), 0) or 0
	local max = safe(UnitPowerMax("player", token), 1) or 1
	return current, max
end

function ns.API.Add(queue, spellID, opt)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID or #queue >= 3 then
		return
	end
	for i = 1, #queue do
		if queue[i] == spellID then
			return
		end
	end
	if ns.API.StepOk(spellID, opt) then
		queue[#queue + 1] = spellID
	end
end
