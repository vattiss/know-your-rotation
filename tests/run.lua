-- Test runner with line coverage, pure Lua (LuaJIT, no C modules), so it runs
-- the same way locally on Windows and in CI.
--
--   luajit tests/run.lua                 run every tests/*_spec.lua
--   luajit tests/run.lua share           run tests/share_spec.lua only
--   luajit tests/run.lua --min=100       fail when total coverage is lower
--   luajit tests/run.lua --uncovered     list the lines no test reached
--
-- Coverage: the executable lines of each addon file come from its LuaJIT
-- bytecode (jit.util), the executed ones from a line hook (JIT off).

if jit then
	jit.off()
	jit.flush()
end

local ROOT = (arg[0]:gsub("[\\/]?tests[\\/]run%.lua$", ""))
if ROOT == "" then
	ROOT = "."
end
package.path = ROOT .. "/tests/?.lua;" .. package.path

local ADDON_FILES = {
	"Locale.lua",
	"API.lua",
	"APICooldown.lua",
	"APIAura.lua",
	"APIUnit.lua",
	"APITotem.lua",
	"APIWeapon.lua",
	"APIStep.lua",
	"Data.lua",
	"Physics.lua",
	"Lists.lua",
	"APL.lua",
	"Share.lua",
	"UI.lua",
	"Options.lua",
	"Glow.lua",
	"Rotations.lua",
	"Debug.lua",
	"Core.lua",
}

local options = { min = nil, uncovered = false, only = {} }
for _, a in ipairs(arg) do
	local min = a:match("^%-%-min=(%d+%.?%d*)$")
	if min then
		options.min = tonumber(min)
	elseif a == "--uncovered" then
		options.uncovered = true
	else
		options.only[#options.only + 1] = a
	end
end

---------------------------------------------------------------------------
-- Coverage
---------------------------------------------------------------------------

local hits = {} -- [path] = { [line] = true }

local function normPath(source)
	local path = source:gsub("^@", ""):gsub("\\", "/")
	return path:match("([^/]+%.lua)$")
end

local tracked = {}
for _, f in ipairs(ADDON_FILES) do
	tracked[f] = true
	hits[f] = {}
end

local getinfo = debug.getinfo
debug.sethook(function(_, line)
	local info = getinfo(2, "S")
	local file = info and normPath(info.source)
	if file and tracked[file] then
		hits[file][line] = true
	end
end, "l")

local function executableLines(path)
	local jutil = require("jit.util")
	local fn = assert(loadfile(path))
	local lines = {}
	-- Opcode names, to skip the jump LuaJIT emits right after a return at
	-- the end of an if / elseif chain: it can never run.
	local okDef, vmdef = pcall(require, "jit.vmdef")
	local function opName(f, pc)
		if not okDef then
			return nil
		end
		local ins = jutil.funcbc(f, pc)
		if not ins then
			return nil
		end
		local op = bit.band(ins, 0xff)
		return (vmdef.bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+", ""))
	end
	local function walk(f)
		local info = jutil.funcinfo(f)
		local prev
		for pc = 1, (info.bytecodes or 1) - 1 do
			local i = jutil.funcinfo(f, pc)
			local name = opName(f, pc)
			local deadJump = name == "JMP"
				and prev
				and (prev:sub(1, 3) == "RET" or prev:sub(1, 5) == "CALLT" or prev == "CALLMT")
			if i.currentline and not deadJump then
				lines[i.currentline] = true
			end
			prev = name
		end
		local k = -1
		while true do
			local c = jutil.funck(f, k)
			if c == nil then
				break
			end
			if type(c) == "proto" then
				walk(c)
			end
			k = k - 1
		end
	end
	walk(fn)
	return lines
end

---------------------------------------------------------------------------
-- describe / it
---------------------------------------------------------------------------

local results = { passed = 0, failed = 0, failures = {} }
local stack = {}

local function currentHooks(kind)
	local list = {}
	for _, block in ipairs(stack) do
		for _, fn in ipairs(block[kind]) do
			list[#list + 1] = fn
		end
	end
	return list
end

function describe(name, body)
	stack[#stack + 1] = { name = name, before = {}, after = {} }
	body()
	stack[#stack] = nil
end

function before_each(fn)
	table.insert(stack[#stack].before, fn)
end

function after_each(fn)
	table.insert(stack[#stack].after, fn)
end

function it(name, body)
	local names = {}
	for _, block in ipairs(stack) do
		names[#names + 1] = block.name
	end
	names[#names + 1] = name
	local full = table.concat(names, " > ")
	local ok, err = true, nil
	for _, fn in ipairs(currentHooks("before")) do
		ok, err = xpcall(fn, debug.traceback)
		if not ok then
			break
		end
	end
	if ok then
		ok, err = xpcall(body, debug.traceback)
	end
	local after = currentHooks("after")
	for i = #after, 1, -1 do
		local okA, errA = xpcall(after[i], debug.traceback)
		if ok and not okA then
			ok, err = okA, errA
		end
	end
	if ok then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.failures[#results.failures + 1] = { name = full, err = err }
	end
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

local function listSpecs()
	local specs = {}
	local windows = package.config:sub(1, 1) == "\\"
	local cmd = windows and ('dir /b "' .. ROOT:gsub("/", "\\") .. '\\tests\\*_spec.lua" 2>nul')
		or ('ls "' .. ROOT .. '/tests/" 2>/dev/null')
	local p = assert(io.popen(cmd))
	for line in p:lines() do
		local name = line:match("([%w_]+)_spec%.lua$")
		if name then
			specs[#specs + 1] = name
		end
	end
	p:close()
	table.sort(specs)
	return specs
end

local specs = listSpecs()
if #options.only > 0 then
	specs = options.only
end

for _, name in ipairs(specs) do
	local path = ROOT .. "/tests/" .. name .. "_spec.lua"
	local chunk, err = loadfile(path)
	if not chunk then
		results.failed = results.failed + 1
		results.failures[#results.failures + 1] = { name = name, err = err }
	else
		local ok, runErr = xpcall(chunk, debug.traceback)
		if not ok then
			results.failed = results.failed + 1
			results.failures[#results.failures + 1] = { name = name .. " (load)", err = runErr }
		end
	end
end

debug.sethook()

for _, f in ipairs(results.failures) do
	io.write("\nFAIL ", f.name, "\n", tostring(f.err), "\n")
end
io.write(("\n%d passed, %d failed\n\n"):format(results.passed, results.failed))

local totalLines, totalHit = 0, 0
io.write(("%-14s %7s %7s %8s\n"):format("file", "lines", "hit", "cover"))
for _, f in ipairs(ADDON_FILES) do
	local lines = executableLines(ROOT .. "/" .. f)
	local n, h, missing = 0, 0, {}
	for line in pairs(lines) do
		n = n + 1
		if hits[f][line] then
			h = h + 1
		else
			missing[#missing + 1] = line
		end
	end
	table.sort(missing)
	totalLines, totalHit = totalLines + n, totalHit + h
	io.write(("%-14s %7d %7d %7.1f%%\n"):format(f, n, h, n > 0 and h * 100 / n or 100))
	if options.uncovered and #missing > 0 then
		io.write("  uncovered: ", table.concat(missing, " "), "\n")
	end
end
local total = totalLines > 0 and totalHit * 100 / totalLines or 100
io.write(("%-14s %7d %7d %7.1f%%\n"):format("total", totalLines, totalHit, total))

local failed = results.failed > 0
if options.min and total + 1e-9 < options.min then
	io.write(("\ncoverage %.1f%% is below the required %.1f%%\n"):format(total, options.min))
	failed = true
end
os.exit(failed and 1 or 0)
