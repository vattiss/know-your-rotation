# Next steps

State: 261 unit tests, 100 % line coverage on all 12 addon files (CI enforces it through `tests/MIN_COVERAGE`), luacheck / StyLua / LuaLS clean. Nothing here was tried in game yet.

## 1. Try it in game (most important)

Every change since the 1.0.0-beta.1 push was checked only by syntax checks and the unit tests with the WoW API stand-in (`tests/wow.lua`). The stand-in follows the API docs, but the real client can differ. Things to watch:

- **Shaman in combat:** does the rotation still glow while totems are down (secret `GetTotemInfo`)? Walk 25+ yards from a Searing Totem: a new one must be suggested.
- **Interrupt:** does the Kick / Pummel / Counterspell / Earth Shock glow light on a normal cast (`notInterruptible` is return 8 of `UnitCastingInfo`, 7 of `UnitChannelInfo`)?
- **Backstab / Shred:** not offered while the mob attacks you, offered when a tank holds it; after "You must be behind your target" it waits 3 s.
- **Hidden health / mana glows:** Drain Life, Life Tap, Mend Pet, heals, executes fade in by themselves.
- **Own debuffs only** (`HARMFUL|PLAYER`): with another warlock's Corruption on the mob, yours is still suggested.
- **Hold on mobs** (secret GUID): Flamestrike is not re-suggested at once.
- **Creature type:** if `UnitCreatureType` is secret for mobs, Serpent Sting on elementals, Exorcism restrictions and bleed immunity cannot work (nothing more to fix in code).
- Suggested test characters: hunter 10, shaman 10, rogue 10 (then warlock, priest, mage, druid).

## 2. Open decisions

1. **"Only suggest spells on your action bars"** (`barOnly`): `ns.SpellOnBar` always returns true (an unreliable bar scan used to clear the rotation), so the Behavior switch and the "not on a bar" warning do nothing. Either remove the switch and code, or make `SpellOnBar` real and test the flicker.
2. **Aura families:** every buff with "aura" in its name counts as a paladin aura, "blessing" as a blessing. Another paladin's Devotion Aura can hide a hunter's Trueshot Aura; another paladin's Kings can hide your Might.
3. **Unusable spell with unknown range:** `StepOk` lets it through (comment: the client says "unusable" out of range). The API docs say `IsSpellUsable` ignores range, so a spell in the wrong stance may be offered. Check in game, then tighten.
4. **Dying mobs in combat:** the "skip DoTs on an almost dead target" rule cannot work while target health is hidden. Idea: fade the DoT glow below 20 % target health with the same curve trick as finishers, and light the next list spell instead. Decided against for now.

## 3. Tooling still to do

- Event handling: `Core.lua` has one long `if / elseif` chain. A table of handlers is cleaner, and `RegisterUnitEvent("UNIT_AURA", "player", "target")` cuts useless calls.
- Split `API.lua` (about 2400 lines) by topic: spellbook, cooldowns / holds, auras, units, totems.
- Turn `StepOk` (about 370 lines) into a table of small condition functions, one per option, each with its own reject text; the ARCHITECTURE option table could come from it.
- The five `BuildHidden*` functions repeat one loop: share a helper.
- Add the new CI pieces to the release workflow check if wanted (release already runs the syntax check only).

## 4. Release

Version stays 1.0.0-beta.1 until the official release (bump `VERSION.txt` and the TOC together, then push the tag `v<version>`). Nothing is tagged yet.
