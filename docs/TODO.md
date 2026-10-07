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

## 2. Open decisions (done)

1. `barOnly` removed: `ns.SpellOnBar` always answered true, so the switch, the "not on a bar" tooltip and the off-bar warning did nothing.
2. The paladin aura family now holds only the real paladin auras (Trueshot Aura no longer counts). One blessing still stands for all blessings (another paladin's Kings hides your Might).
3. An unusable spell is a queue candidate only when its range is certainly "out"; an unknown range no longer lets a wrong-stance spell through.
4. Still open: dying mobs in combat (DoT skip rule cannot work while target health is hidden).

## 3. Structure (mostly done)

Done: `Core.lua` events are a table of handlers with unit-filtered registrations; `StepOk` is a list of small checks (`STEP_CHECKS`); the five `BuildHidden*` functions share `hiddenPick`.

Still to do:

- Split `API.lua` (about 2500 lines) by topic: spellbook, cooldowns / holds, auras, units, totems. The file shares many `local` helpers (`readable`, `safe`, `unitExists`, the hold and aura tables), so the split needs a small internal table (`ns.API.internal`) first.
- The release workflow runs only the syntax check; the unit tests, luacheck and StyLua could run there too.

## 4. Release

Version stays 1.0.0-beta.1 until the official release (bump `VERSION.txt` and the TOC together, then push the tag `v<version>`). Nothing is tagged yet.
