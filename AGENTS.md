# Know Your Rotation — agent guide

Rotation helper addon for **WoW Forever** (Classic Era combat, camelot client, interface `16001`). It shows the next spells and highlights action buttons. It never casts anything.

Repo: https://github.com/attilavarga96/know-your-rotation (public, branch `main`, MIT). The local folder and the AddOns folder stay named `KnowYourRotation`.

The full code map is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). This file only says where to start.

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
| Default single / AoE / burst / defense order | `Lists.lua` |
| Save, merge, add, remove a spell | `APL.lua` |
| Profile import / export | `Share.lua` |
| "Is this spell offered" conditions | `API.lua` (`StepOk`, `Ready`, `Resolve`) |
| Classic timing (swing, auto shot, energy) | `Physics.lua` |
| HUD queue, defense, interrupt, weapon | `Rotations.lua` |
| Windows, toolbar | `UI.lua` |
| Options, spell drag | `Options.lua` |
| Glow on action bars | `Glow.lua` |
| Profiles, auto role / profile, migrations | `Core.lua` |
| Player text | `Locale.lua` |

## Pitfalls

- Resolve spells by **name + spellbook** (`ns.API.Resolve`). A Classic ID can be remapped.
- Reject names containing `TEST`, `(OLD)`, `(PT)` (`junkSpellName`).
- Buffs in `ns.MAINTENANCE_BUFF_IDS` are stripped from combat lists at load (`stripMaintFromApl`) and refused by `AddAPL`.
- A spell with its own cooldown is removed by `NoteSpellCast` until the cooldown ends. The GCD does not count. Do not bypass `ns.API.Cooldown` with `filler`. `filler` is still blocked by `ns.Physics.Blocks`.
- `opt.hold` / `ns.SPELL_HOLD`: after a cast the spell is not offered for N seconds. `0` means no aura delay. Harmful holds are tied to the target GUID. For `nodebuff` / `nobuff` spells a readable aura wins over the hold.
- `roleAuto` (default true): Hunter/Shaman switch melee/ranged by range. A manual HUD role click turns it off.
- Hunter stings do not apply to Mechanical / Elemental targets (`CreatureBlocked`).
- Rotation pass: a listed spell already cast is marked used for this pass; when nothing is usable the queue restarts. Reset on target change and leaving combat.
- `IsRotationAction`: a filler yields slot 1 to a ready shock / DoT / CD / proc listed lower. Do not use `require` / `requireAny` to hide a filler: list order wins.
- Do not call `CombatLogGetCurrentEventInfo`: the client blocks the addon. Proc spells use `opt.proc` (`IsSpellUsable`).
- `listVersion` is 4: saved lists are replaced once by the default order on next login.
- `auto` mode uses the single list until `ns.API.EnemyCount()` reaches `autoEnemies` (default 3, minimum 2), then the `aoe` list.
- The druid HUD `hybrid` button is not a list key. `ns.ActiveSpec()` picks `cat`, `bear`, `heal`, `tank` or `damage`.
- `ns.ResetCurrentProfile` only resets the active profile (`base`, `pve`, `pvp`, `custom`).
