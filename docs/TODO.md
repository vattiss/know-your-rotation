# Next steps

State: 332 unit tests, 100 % line coverage on all 19 addon files (CI enforces it through `tests/MIN_COVERAGE`), luacheck / StyLua / LuaLS clean. Played in game to about level 10 on shaman, rogue, hunter, priest and druid; the bugs found there are fixed. Next: feedback from players of the beta.

## 1. Try it in game (most important)

Turn on **Behavior > Debug > Collect debug data** first. It samples the API once a second and counts events. After testing, open **Profiles > Debug report**, copy the text and send it: it answers the open questions below with data (is `GetTotemInfo`, `UnitCreatureType`, `UnitGUID`, `UnitThreatSituation` secret in combat; what `IsSpellUsable` says out of range; which error texts the client sends).

Still open, only the game (or player reports) can answer:

- Is `GetShapeshiftFormInfo` / `GetNumShapeshiftForms` readable in combat (druid form)?
- Rogue poisons: spell, item or aura in the Forever client? Not played to level 20.
- Levels above 20 were not played on any class.

Older checklist (mostly confirmed in game):

- **Shaman totem cue:** does the totem glow (orange) appear at the start of a fight and stay until the totem is down, while the other buttons keep going? Does Earthbind wait for melee range? Walk 25+ yards from a Searing Totem: a new one must be glowing.
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

Done: `API.lua` is split by topic into seven files that share `ns.API.I`; `Core.lua` events are a table of handlers with unit-filtered registrations; `StepOk` is a list of small checks (`STEP_CHECKS`); the five `BuildHidden*` functions share `hiddenPick`.

Still to do:

- `APIUnit.lua` is still about 1100 lines (units, range, roles, casts); it could be split further.
- The release workflow runs the syntax check and the unit tests; luacheck and StyLua run in the Check workflow on every push.

## 4. Release

1.0.0-beta.1 is released with the tag `v1.0.0-beta.1` (GitHub Actions builds the zip). Next version: bump `VERSION.txt` (with new release notes) and the TOC together, then push the tag `v<version>`.
