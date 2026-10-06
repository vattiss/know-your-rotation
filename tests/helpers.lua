-- Small assertion helpers for the specs.
local H = {}

local function show(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function H.eq(actual, expected, msg)
	if actual ~= expected then
		error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
	end
end

local function deepEq(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEq(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end
H.deepEq = deepEq

function H.same(actual, expected, msg)
	if not deepEq(actual, expected) then
		error((msg and (msg .. ": ") or "") .. "tables differ", 2)
	end
end

function H.truthy(v, msg)
	if not v then
		error(msg or "expected a truthy value", 2)
	end
end

function H.falsy(v, msg)
	if v then
		error((msg or "expected a falsy value") .. ", got " .. show(v), 2)
	end
end

function H.contains(list, value, msg)
	for _, v in ipairs(list) do
		if v == value then
			return
		end
	end
	error((msg or "list does not contain") .. " " .. show(value), 2)
end

function H.errors(fn, msg)
	local ok = pcall(fn)
	if ok then
		error(msg or "expected an error", 2)
	end
end

return H
