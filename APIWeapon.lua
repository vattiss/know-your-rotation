local addonName, ns = ...
local I = ns.API.I

-- Weapon enchants and tooltips.
local readable, safe = I.readable, I.safe

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

local function interpretEnchant(has, remainRaw, enchRaw)
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
	return true, remain > 0 and remain or 9999, nil
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

-- C_Item.GetWeaponEnchantInfo(weaponSlot): a list of WeaponEnchantInfo
-- (hasEnchant, enchantType, timeLeft, charges, enchantID). Only a temporary
-- enchant or an imbue (Enum.ItemEnchantType 2 / 3) counts. nil = no answer.
local function readItemEnchant(offhand)
	if not (C_Item and C_Item.GetWeaponEnchantInfo) then
		return nil
	end
	local slots = Enum and Enum.WeaponSlot
	local slot = offhand and (slots and slots.OffHand or 1) or (slots and slots.MainHand or 0)
	local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slot)
	if not ok or type(list) ~= "table" then
		return nil
	end
	local types = Enum and Enum.ItemEnchantType
	local temporary, imbue = types and types.Temporary or 2, types and types.Imbue or 3
	for _, entry in ipairs(list) do
		local kind = type(entry) == "table" and safe(entry.enchantType, nil)
		if (kind == temporary or kind == imbue) and safe(entry.hasEnchant, nil) == true then
			return interpretEnchant(true, safe(entry.timeLeft, nil), safe(entry.enchantID, nil))
		end
	end
	return false, 0, 0
end

local function readWeaponEnchant(offhand)
	local tHas, tRemain, tId = readTempEnchant(offhand)
	if tHas ~= nil then
		return tHas, tRemain, tId
	end
	local iHas, iRemain, iId = readItemEnchant(offhand)
	if iHas ~= nil then
		return iHas, iRemain, iId
	end
	-- No answer from either API: unknown (the tooltip read decides).
	return nil, 0, nil
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
