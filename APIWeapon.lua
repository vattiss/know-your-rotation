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

local function pickField(t, key, index)
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
				has, remain, enchId = interpretEnchant(
					pickField(t, "hasOffHandEnchant", 5),
					pickField(t, "offHandExpiration", 6),
					pickField(t, "offHandEnchantID", 8)
				)
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
