# Know Your Rotation — agent guide

Rotation helper addon for **WoW Forever** (Classic Era combat, camelot client, interface `16001`). It shows the next spells and highlights action buttons. It never casts anything.

Repo: https://github.com/vattiss/know-your-rotation (public, branch `main`, MIT). The local folder and the AddOns folder stay named `KnowYourRotation`.

The full code map is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). This file only says where to start.

## Before you start any change

Always start by reading the docs for the part you work on, before you edit code:

1. **Project docs:** read the section of [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for that part (the table below names the file; the doc has a section per file and topic, e.g. *Step options*, *Queues*, *Self-buffs in combat*).
2. **API docs:** look up every Blizzard function, event and field you call or read in `ref/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated` (git submodule, `forever` branch). Check the name, the argument and **return order**, `Nilable`, and the `Secret*` flags (secret values cannot be compared). Example: `notInterruptible` is return 8 of `UnitCastingInfo` but return 7 of `UnitChannelInfo`.
3. **Blizzard UI code:** for filter strings, constants and CVars, check how the Blizzard UI in `ref/wow-ui-source/Interface/AddOns` uses them (e.g. aura filters in `Blizzard_FrameXMLUtil/AuraUtil.lua`, `"HARMFUL|PLAYER"`).
4. After the change, update that ARCHITECTURE section (and `README.md` if players see the change).

If the docs do not answer a question, say so instead of guessing; it can only be checked in game.

## Checks (run before you hand back a change)

- **Tests:** `luajit tests/run.lua` runs every `tests/*_spec.lua` against the WoW API stand-in in `tests/wow.lua` and prints the line coverage per file (`--uncovered` lists the missing lines, `--min=N` fails below N %). Every change to addon code comes with tests: line coverage is 100 % for every file and must stay there (`tests/MIN_COVERAGE`, enforced by CI). Code that no test can reach is dead code: remove it rather than leave it untested. Secret values are typed sentinels (`wow.SECRET`, `wow.SECRET_STRING`, `wow.SECRET_BOOL`): arithmetic or concatenation on them fails the test, like in game.
- **Lint:** `luacheck *.lua tests tools types`. `.luacheckrc` lists every WoW global the addon reads; a new Blizzard function must be added there (after checking it in `ref/`).
- **Format:** `stylua .` (config in `stylua.toml`: tabs, 120 columns). CI runs `stylua --check .`.
- **Types:** LuaLS (`.luarc.json`; `types/KnowYourRotation.lua` defines `KYR.StepOpt` / `KYR.Step`). Keep it at zero warnings.
- `tests/`, `tools/` and `types/` are never copied to the AddOns folder and never shipped (the release zip takes only the root `*.lua`).

## Scope

- Supports **WoW Forever only**. No other client or version.
- **English only.** All player text lives in `Locale.lua` (`ns.T`).

## Source of truth

Edit **this repo**. The played copy is:

`C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation`

If they diverge, the repo wins: copy the repo into AddOns. Never overwrite the repo with the game folder. After a change, bump `VERSION.txt` and the `.toc`, copy to AddOns, commit and push.

## Load order

`Locale.lua` → `API.lua` → `Data.lua` → `Physics.lua` → `Lists.lua` → `APL.lua` → `Share.lua` → `UI.lua` → `Options.lua` → `Glow.lua` → `Rotations.lua` → `Core.lua`

All shared state lives in the `ns` table (second value of `...`). `Core.lua` runs a `C_Timer.NewTicker(0.2)`. No `OnUpdate` on the whole HUD; only the physics gauge (50 ms) when `showPhysics` is on.

## Where to change what

| Need | File |
| --- | --- |
| New spell, racial, interrupt, purge, cleanse, weapon enchant | `Data.lua` (`ns.Spell`, then derived tables) |
| Default single / AoE / defense order | `Lists.lua` |
| Save, merge, add, remove a spell | `APL.lua` |
| Profile import / export | `Share.lua` |
| "Is this spell offered" conditions | `API.lua` (`StepOk`, `Ready`, `Resolve`) |
| Classic timing (swing, auto shot, energy) | `Physics.lua` |
| Rotation queue, defense, interrupt, weapon cues | `Rotations.lua` |
| Shared `ns.UI` table and refresh hooks | `UI.lua` |
| Options pages (native and canvas), spell drag | `Options.lua` |
| Glow on action bars | `Glow.lua` |
| Profiles, auto role / profile, migrations | `Core.lua` |
| Player text | `Locale.lua` |

## Pitfalls

- Resolve spells by **name + spellbook** (`ns.API.Resolve`). A Classic ID can be remapped.
- Reject names containing `TEST`, `(OLD)`, `(PT)` (`junkSpellName`).
- Buffs in `ns.MAINTENANCE_BUFF_IDS` are stripped from combat lists at load (`stripMaintFromApl`) and refused by `AddAPL`.
- A spell with its own cooldown is removed by `NoteSpellCast` until the cooldown ends. The GCD does not count. Do not bypass `ns.API.Cooldown` with `filler`. `ns.Physics.Blocks` (Auto Shot clip) applies to every step.
- `opt.hold` / `ns.SPELL_HOLD`: after a cast the spell is not offered for N seconds. `0` means no aura delay. Harmful holds are tied to the target (GUID when readable, else the current target until it changes). Fillers ignore holds. For `nodebuff` / `nobuff` spells a readable aura wins over the hold.
- `roleAuto` (default true): role from the name of the talent tree with the most points (Protection = tank; Holy / Discipline / Restoration = heal; else damage) and, for hunter / shaman, range. Druid bear / cat comes from the form. Picking a role on the Behavior page turns it off.
- Hunter stings do not apply to Mechanical / Elemental targets (`CreatureBlocked`).
- Rotation pass: a listed spell already cast is marked used for this pass; when nothing is usable the queue restarts. Reset on target change and leaving combat.
- `IsRotationAction`: a filler yields slot 1 to a ready shock / DoT / CD / proc listed lower. Do not use `require` / `requireAny` to hide a filler: list order wins.
- Do not call `CombatLogGetCurrentEventInfo`: the client blocks the addon. Proc spells use `opt.proc` (`IsSpellUsable`).
- `listVersion` is 4: saved lists are replaced once by the default order on next login.
- `auto` mode uses the single list out of combat (the pull) and until `ns.API.EnemyCount()` reaches `autoEnemies` (default 3, minimum 2) in combat, then the `aoe` list.
- The druid HUD `hybrid` button is not a list key. `ns.ActiveSpec()` picks `cat`, `bear`, `heal`, `tank` or `damage`.
- `ns.ResetCurrentProfile` only resets the active profile (`pve` or `pvp`).
