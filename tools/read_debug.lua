-- Prints the debug data of one character from its SavedVariables file.
--   luajit tools/read_debug.lua "<path>/SavedVariables/KnowYourRotation.lua"
-- Characters: C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\<account>\<realm>\<character>\SavedVariables\
-- The file with debug data is the big one (the others are a few hundred bytes).
local path = assert(arg[1], "usage: luajit tools/read_debug.lua <KnowYourRotation.lua>")
local env = {}
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk()
local d = env.KnowYourRotationCharDB and env.KnowYourRotationCharDB.debug
if not d then
	print("no debug data in this file")
	return
end
print(("samples %d, keys %d, dropped %d"):format(d.samples or 0, d.keys or 0, d.dropped or 0))
for key, value in pairs(d.info or {}) do
	print(key, value)
end
local probes, byProbe = {}, {}
for key, n in pairs(d.counts or {}) do
	local name, ctx, result = key:match("^(.-)\t(.-)\t(.*)$")
	if not byProbe[name] then
		byProbe[name] = {}
		probes[#probes + 1] = name
	end
	byProbe[name][#byProbe[name] + 1] = ("  %s -> %s x%d"):format(ctx, result, n)
end
table.sort(probes)
for _, name in ipairs(probes) do
	print(name)
	table.sort(byProbe[name])
	for _, line in ipairs(byProbe[name]) do
		print(line)
	end
end
for key, n in pairs(d.texts or {}) do
	print("TEXT", key, n)
end
