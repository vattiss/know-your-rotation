@AGENTS.md

# Working notes for Claude Code

- LuaJIT (Lua 5.1 compatible, like WoW) is installed but not on PATH: `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`. After editing Lua, syntax-check each file with `luajit -bl <file>.lua` (exit code non-zero = error). This only checks syntax; the WoW API is not available, so nothing is actually run. Say so plainly.
- Lua patterns have no alternation: `(A|B)` does not work. Match a generic prefix, then compare in code.
- Match the surrounding style: tab indentation, `local addonName, ns = ...` header, `ns.T("KEY")` for every player-facing string (add the key to `Locale.lua`).
- `ref/wow-ui-source` is a git submodule (Gethe/wow-ui-source, `forever` branch): the Blizzard UI code and API docs for the Forever client (`Interface/AddOns/Blizzard_APIDocumentationGenerated`). Check API names there before using a function. Never copy `ref/` into the AddOns folder. Fresh clone: `git submodule update --init --depth 1`.
- Do not commit or bump the version unless asked. When asked: bump `VERSION.txt` and `KnowYourRotation.toc` together, then copy the repo into the AddOns folder named in AGENTS.md.
