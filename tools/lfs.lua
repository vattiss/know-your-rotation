-- Minimal pure-Lua stand-in for LuaFileSystem, only for running luacheck
-- locally on Windows without a C compiler. Not part of the addon.
local lfs = { _VERSION = "LuaFileSystem 0.0 (tools/lfs.lua shim)" }

local windows = package.config:sub(1, 1) == "\\"

local function isFile(path)
	local f = io.open(path, "rb")
	if f then
		local ok = f:read(0) ~= nil or f:seek("end") ~= nil
		f:close()
		return ok
	end
	return false
end

function lfs.attributes(path, what)
	local mode
	if isFile(path) then
		mode = "file"
	elseif os.rename(path, path) then
		mode = "directory"
	end
	if not mode then
		return nil, "cannot obtain information from file '" .. tostring(path) .. "'"
	end
	local attrs = { mode = mode, modification = 0 }
	if what then
		return attrs[what]
	end
	return attrs
end

function lfs.currentdir()
	local p = io.popen(windows and "cd" or "pwd")
	local dir = p and p:read("*l")
	if p then
		p:close()
	end
	return dir
end

function lfs.dir(path)
	local cmd = windows and ('dir /b "' .. path .. '" 2>nul') or ('ls -a "' .. path .. '" 2>/dev/null')
	local p = assert(io.popen(cmd))
	local names = { ".", ".." }
	for line in p:lines() do
		if line ~= "." and line ~= ".." then
			names[#names + 1] = line
		end
	end
	p:close()
	local i = 0
	return function()
		i = i + 1
		return names[i]
	end
end

function lfs.mkdir(path)
	local ok = os.execute((windows and 'mkdir "' or 'mkdir -p "') .. path .. '"')
	return ok == 0 or ok == true
end

return lfs
