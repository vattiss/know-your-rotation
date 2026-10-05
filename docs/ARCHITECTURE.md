# Know Your Rotation architecture

Classic Era rotation helper for the **camelot** client of WoW Forever (interface `16001`, `_classic_beta_` folder). The player always presses the keys. The addon suggests up to 3 spells, plus a reminder for defense, interrupt, purge, dispel and weapon enchant, then puts a glow on the matching action bar button.

See also [AGENTS.md](../AGENTS.md) for the repository, the AddOns path and the push rule.

## Client constraints

Forever reuses the Midnight / camelot API, not the Classic 1.14 API alone.

- Spell IDs can differ from public Classic (example: devotion aura). The code stores `1.60.1` lab IDs in `ns.Spell`, then `ns.API.Resolve` finds the spell **known to the player** through `C_Spell.GetOverrideSpell`, `IsPlayerSpell` / `C_SpellBook`, then the name in the spellbook.
- Some values are *secret values*. `API.lua` and `APL.lua` go through `issecretvalue` / `canaccessvalue` before reading a number or a string. An unreadable value is treated as absent.
- Every Blizzard call is wrapped in a `pcall`. Never replace `C_Spell`, `C_SpellBook`, `GetSpellInfo` or the unit functions.
- A single TOC: `KnowYourRotation.toc`, with `## Interface: 16001` and `## AllowLoadGameType: camelot`.
- Global SavedVariables: `KnowYourRotationDB`.

## Lifecycle

`Core.lua` creates an invisible frame.

On `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`:

1. `defaults()` completes `KnowYourRotationDB` and calls `ns.BindProfile()`.
2. `ns.API.InvalidateSpells()` clears the resolution cache.
3. `ns.RegisterOptions()` and `ns.GlowFetch()`.
4. `ns.Tick()` (sets `ns.booted` first; `Tick` does nothing before login).

`ns.Tick` (`C_Timer` every 0.2 s like ConROC, plus target changes):

```
BuildQueue → BuildDefense → BuildInterrupt → BuildPurge → BuildCleanse → BuildWeapon
→ glows only if the result changed (rotation glow only when the first spell is pressable now)
```

Each builder honors its `ns.db.show*` switch. A missing `show*` means shown (`~= false`).

`ns.API.castTarget` becomes true when the target starts a cast or a channel, and false on stop, failure, interrupt or target change. `TargetCasting` uses it if `UnitCastingInfo` returns nothing.

## Files

Load order (single TOC): `Locale.lua` → `API.lua` → `Data.lua` → `Physics.lua` → `Lists.lua` → `APL.lua` → `Share.lua` → `UI.lua` → `Options.lua` → `Glow.lua` → `Rotations.lua` → `Core.lua`.

| File | Role |
| --- | --- |
| `Locale.lua` | English strings only. `ns.T(key)` returns the string, or the raw key if missing. |
| `API.lua` | `ns.API`: resolution, spellbook, ready, auras, heals, enemies, weapon. |
| `Data.lua` | IDs, roles, colors, racials, interrupts, purges, cleanses, enchants, long buffs, heals. |
| `Physics.lua` | Swing, auto shot clip, energy tick. Option `ns.db.showPhysics`. No combat log. |
| `Lists.lua` | `ns.APLDefaults`, `ns.APLModes`, `ns.DefDefaults`. |
| `APL.lua` | Read / write of saved lists, merge with defaults. |
| `Share.lua` | Export / import of the active profile (`WFR1` text). |
| `UI.lua` | Shared `ns.UI` table and refresh hooks (no HUD window). |
| `Options.lua` | Options panel (Settings → AddOns) and the list editors. |
| `Glow.lua` | Bar overlays. |
| `Rotations.lua` | Queue builders. |
| `Core.lua` | Profiles, roles, modes, events, auto role and profile. |

Namespace: `local addonName, ns = ...`. Do not create a second global state outside the declared SavedVariables.

## Class data (`Data.lua`)

`ns.CLASSES` and `ns.CLASS_BY_ID`: the 9 Classic classes. No DK.

`ns.CLASS_ROLES` — role styles:

| Class | Roles |
| --- | --- |
| Warrior | `damage`, `tank` |
| Paladin | `damage`, `tank`, `heal` |
| Hunter | `range`, `melee` |
| Rogue, mage, warlock | `damage` |
| Priest | `damage`, `heal` |
| Shaman | `caster`, `melee`, `heal` |
| Druid | `hybrid`, `heal`, `tank` |

`ns.NormalizeRole` converts an old shaman `damage` to `caster`, hunter to `range`, druid to `hybrid`, otherwise the first allowed role.

`ns.ActiveSpec` (in `APL.lua`) picks the **list key**, which is not always the selected role:

- Druid `heal` → `heal`. Druid `tank` → `bear` if in bear form, otherwise `tank`.
- Otherwise cat form → `cat`, bear form → `bear`, otherwise `damage`.
- Other classes: the selected role as is.

`ns.APLDefaults.DRUID.hybrid` aliases `damage`. The hunter `range`/`melee` and shaman `caster`/`melee` defenses alias `damage`. The editor uses `ns.SpecList` (for the druid: `damage`, `cat`, `bear`, `heal`, `tank`).

`ns.CLASS_COLORS` is hardcoded. Do not depend on `RAID_CLASS_COLORS`.

`ns.RACIALS`: Perception, Blood Fury, Stoneform, Shadowmeld, Will of the Forsaken, War Stomp, Escape Artist, Berserking, Read Ley Line (race 95, Alliance, also defensive), Skysight (race 96, Horde). Walk on Air `1259416` and the Aeolid passives are not listed. Racials are added to the lists with `on = false`.

`ns.INTERRUPTS`: warrior 6552, rogue 1766, shaman 8042 (Earth Shock), mage 2139, priest 15487.

`ns.PURGES`: shaman 370, priest 527, mage 30449 (Spellsteal, may be absent).

`ns.CLEANSE`: dispel **on the player** only, by types `Magic`, `Disease`, `Poison`, `Curse`. The mage purge only sees `isStealable`. The others also accept `dispelName == "Magic"`.

`ns.WEAPON_BUFFS`: shaman (Windfury, Flametongue, Rockbiter, Frostbrand), rogue (poisons), warlock (firestone / spellstone). Each entry has `key`, `id`, `duration`, sometimes `ranks`, `enchants` (4th value of `GetWeaponEnchantInfo`) and `match` (tooltip text, lowercase). The `ns.WEAPON_BUFF_IDS` and `ns.WEAPON_ENCHANT_IDS` indexes are built at load.

`ns.MAINTENANCE_BUFF_IDS`: buffs > 1 min, auras, aspects, blessings, armors, battle shout, etc. Defense only.

`ns.HEAL_SPELL_IDS`: heals and HoTs, including rank IDs. A heal is not blocked by a hostile target.

## Default lists (`Lists.lua`)

A step is `{ key, id, opt, on = true }`, created by `step(key, id, opt)`.

- `ns.APLDefaults[class][spec]`: single-target list, also used by `auto` mode.
- `ns.APLModes[class][spec].aoe`: AoE variant. If there is no variant, `defaultsFor` falls back to `APLDefaults`.
- `ns.DefDefaults[class][spec]`: long buffs and emergency buttons (low `hp`).

At the end of the file, `stripMaintFromApl` removes from `APLDefaults` and `APLModes` any step whose ID is in `MAINTENANCE_BUFF_IDS`. Add a long buff only in `DefDefaults` and in `MAINTENANCE_BUFF_IDS`.

The lists come from a ConROC Classic style Era core, levels 1–60. No SoD and no Midnight spells.

## Step options (`opt`)

Evaluated by `ns.API.StepOk` in order. A missing field is ignored.

| Field | Effect |
| --- | --- |
| `role` | The step is ignored if `ns.db.role` differs. Tested in `Rotations.stepReady`, not in `StepOk`. |
| `hostile` | Requires `ns.API.Hostile()` (living target, reaction ≤ 4). Unreadable reaction = hostile. |
| `heal` | Forces heal handling (`IsHelpful` / `IsHealSpell`). |
| `hp` | Health percentage, strictly `>` to refuse. Target: `opt.unit`, otherwise the ally to heal if the spell is helpful, otherwise the player. |
| *(heal without `hp`)* | Implicit threshold **99**. |
| `unit` | Forced unit for `hp` (`"target"`, `"pet"`, …). |
| `nobuff` | Aura-first: if the helpful aura is **readable** and absent → OK (self hold cleared). If present and remain > `refresh` (default: no forced refresh unless `opt.refresh`) → refused. If secret, `HasAura` / hold. |
| `nodebuff` | `true` = the spell must not already be a debuff on the target. An ID = that other debuff. Aura-first: readable absence → OK + clear hold; remain ≤ `refresh` (default **6** s) → refresh allowed; secret aura → GUID hold. |
| `refresh` | Remaining seconds under which a `nobuff` / `nodebuff` can be suggested again. Default for `nodebuff` = 6. |
| `stacks` | With `nodebuff` / `nobuff`: keeps suggesting while readable stacks are &lt; N; then normal refresh. Sunder / Lacerate / Fire Vulnerability. |
| `nocreature` | `true` = Mechanical / Elemental. Table / string = canonical types (`undead`, `demon`, …). |
| `creature` | Inverse: the step is OK only if the target type matches (Exorcism Undead/Demon). |
| `totem` | Suggests the totem if absent or remain ≤ `refresh` (default 1 s) via `GetTotemInfo`. |
| `enemiesMin` / `enemiesYards` | Refuses if `EnemyCount(yards)` &lt; N (Whirlwind, Consecration, Swipe). |
| `skipLow` | Refuses DoT/mark if target health &lt; 20 % (trash) or &lt; 5 % (elite/raidmob). |
| `targetMana` | Refuses if the target has no mana (Viper Sting). |
| `needanybuff` | Requires at least one buff from the list on the player (Judgement after a seal). |
| `ifTargeting` | Requires `targettarget == player` (Aspect of the Monkey). |
| `anybuff` | List of IDs. If the player has **any** of them, the step is refused. Used for exclusive seals, auras, aspects, armors. |
| `form` | Requires the form aura on the player (`ns.API.Form`). |
| `noform` | Refused if this form is active. |
| `combat` | Requires the player in combat. |
| `comboMin` | Minimum player/target combo points. |
| `pet` / `nopet` | Pet present or absent. |
| `ready = false` | Accepts the step without testing cooldown or usability. |
| `filler` | Spam spell with no own cooldown (Wrath, Heroic Strike, Sinister Strike…). Skipped only by a real cooldown, not by the GCD. `ns.Physics.Blocks` still applies. |
| `nocombat` | Refused if the player is in combat (Charge, Stealth, Prowl). |
| `needbuff` | Helpful aura ID required on the player (Garrote and Ambush require Stealth). |
| `needdebuff` | Debuff ID required on the target (Conflagrate requires Immolate). |
| `proc` | The client must report the spell as usable. Used for Overpower, Revenge, Riposte, Counterattack and Mongoose Bite. If the answer is hidden, the step is skipped. Do not read the combat log: that call is reserved for the Blizzard UI and blocks the addon. |
| `usable` | The client must report the spell as usable (Exorcism, Holy Wrath, Backstab from behind). If the answer is hidden, the step is skipped. |
| `manaMax` | Refused if the player's mana percentage is above this threshold (Life Tap). |
| `hpMin` | Refused if health (player, or `unit`) is under this percentage. |
| `hold` | Seconds after a successful cast during which the spell is no longer suggested (DoT, HoT, snare). Forever/Classic defaults. Editable next to each spell. `0` = no aura delay. Harmful holds are tied to the GUID. For `nodebuff` / `nobuff`, the readable aura wins; hold = Forever fallback. No CLEU. |
| `anydebuff` | List of IDs. If the target has **any** of them, the step is refused. One sting, one curse. |

`ns.API.Ready`: spell resolved, no own cooldown running, no `noMana`. The GCD (about 1.5 s) does not remove the spell from the queue: it stays the next button to press. A longer cooldown (Judgement, Shock, Aimed Shot, Blast Wave…) removes it until it ends, and the next step in the list is tested. This applies to all classes, racials and defense.

The camelot client often hides `GetSpellCooldown` in combat. On a successful cast, `ns.API.NoteSpellCast` starts the spell's base cooldown (`GetSpellBaseCooldown`, otherwise `ns.COOLDOWNS`). The three shaman shocks share this time (`ns.COOLDOWN_GROUPS`). A proc that makes the spell available earlier may have to wait for this delay to end, because the game does not let the addon read the remaining time.

Overpower, Revenge, Riposte, Counterattack and Mongoose Bite (`opt.proc`) are only suggested if `IsSpellUsable` answers true. A hidden answer skips the step. The combat log is not read.

`Physics.lua` (Behavior option `showPhysics`, default true): white hits for **all** classes via `PLAYER_ENTER_COMBAT` / `UNIT_ATTACK` + `UnitAttackSpeed` (main hand + off hand if dual wielding). The next-swing window (Heroic Strike, Cleave, Raptor Strike, Maul) reads the main hand only. `UNIT_SPELLCAST_SUCCEEDED` + Auto Shot 75 for the hunter clip; `UNIT_POWER_UPDATE` for the 2 s energy tick. Without an observed swing, the next-swing is not hidden. No `CombatLogGetCurrentEventInfo`. `UNIT_ATTACK` only restarts the hand whose timer has expired; a speed change realigns the progress. `UNIT_COMBAT` with `PARRY` on the player shortens the main hand swing by 40 %, without going under 20 % of the speed. The energy bar shows the remaining time and only resyncs on a tick of about 20. A movable combo point window follows the HUD chrome for the rogue and the cat druid. Player settings are stored in `KnowYourRotationCharDB` (SavedVariablesPerCharacter). The first login copies `KnowYourRotationDB` once.

A spell that is only helpful (`IsHelpful` and not `IsHarmful`) can pass through the power cost if `IsSpellUsable` is false or absent. A harmful spell with `usable == false` is refused.

`ns.API.Add` stacks at most 3 **already resolved** IDs, without duplicates, and only if `StepOk`.

## Queues (`Rotations.lua`)

`ns.BuildQueue`: up to 3 slots. The list is read in order; spells **already cast in the current pass** (`ns.NoteRotationCast` / `rotSpent`) are skipped — even if they had not been displayed yet. When no usable step remains in the pass, `rotSpent` is cleared and the queue **restarts from the beginning**. Also reset on target change and when leaving combat.

- ignores an unchecked step, a weapon enchant, a maintenance buff, and (if `barOnly`) a spell missing from the bars already indexed by GlowFetch;
- the spell being cast is pinned in slot 1, then `PredictConsume` assumes it was cast (DoT, CD / shocks, buff, stealth, combo points);
- a leading **filler** yields to a lower **action** (shock, DoT, CD, proc) as soon as it is ready and in range `in` or unknown (`notOut`) — the shock then moves to slot 1. Starfire / Ice Lance / Swipe / auto racials do not steal;
- the same spell appears only once in the queue (except `swing`): slots 2–3 show other spells;
- `opt.hold` removes a spell after a cast for N seconds (DoT / snare) in addition to the "pass" marking;
- slot 1 prefers `RangeState` `in`; otherwise `notOut`. `out` → slots 2–3;
- `ns.ApplyRotationEdit` (Up / Down / Apply) clears the cache and re-evaluates the glows without `/reload`;
- `IsSpellUsable` false during the GCD or a cast no longer prevents a shock from entering the queue;
- if no heal made it into the 3 slots, the first `StepOk` heal is inserted at the head and the queue is trimmed back to 3.

`ns.queueHeal[id]` (list ID and resolved ID) is used for the green highlight.

`ns.BuildDefense`: first checked defense step that passes `StepOk`.

`ns.BuildInterrupt`: known and ready class ID, hostile target that is casting.

`ns.BuildPurge`: ready class ID, hostile target, purgeable aura.

`ns.BuildCleanse`: first entry that is **known and ready** whose `entry.types` matches a debuff on the player, or on the group if `cleanseGroup ~= false`. A warrior / hunter without a `CLEANSE` table shows nothing. A mage only sees curses, a priest disease / magic only if they have the spell, etc. Non-friendly units are ignored.

`ns.BuildWeapon` returns `spellID, remain, need`.

1. Chosen enchant: `ns.db.weaponBuff`, otherwise the first known one, otherwise the first in the list.
2. Present if the buff aura is on the player, if a hand has a temporary enchant (even if the Forever ID is not in the list), or if the weapon tooltip contains the name. A known ID of another buff does not count.
3. Absent only if both hands answer "no enchant", with no aura and no tooltip: red reminder right away. `has == false` alone is not enough, Forever often exposes the buff through the aura or the tooltip.
4. Unreadable answer: 5 s grace after the cast, otherwise the last expiration seen, otherwise red reminder. Changing weapon clears the memory. No 30 or 60 minute memory after the cast.

## List merging (`APL.lua`)

Save keys: `ns.db.apl[CLASS][spec][mode]` and `ns.db.def[CLASS][spec]`.

A mode bucket is a table with `auto` / `single` / `aoe` and **no** `[1]` index. An old flat list (`[1]` index) is migrated to `{ single = legacy }` on first write (`ensureModeBucket`). On read, a flat list only counts for the `single` mode.

`ns.GetAPL(class, spec, mode)`:

- explicit mode, otherwise `ns.ResolveCombatMode()`;
- `auto` and `single` read `APLDefaults`;
- `aoe` reads `APLModes`, otherwise the single default;
- racials are appended at the end, unchecked;
- with no save and no removal, the defaults are returned as is;
- otherwise `mergeSteps(..., skipMaint = true)`: the saved order wins, new default steps are added if they are not in `aplDrop` and not already present (same ID or same name).

Removing a non-`custom_*` step writes its key to `aplDrop` / `defDrop`, so a default does not come back. `custom_` comes from the spell name (`custom_` + name without spaces).

`packRows` saves `{ key, on = 1|0, hold if set, id if custom, custom }`. The other `opt` fields of default spells stay in `Lists.lua` / `ns.SPELL_HOLD`. A helpful custom spell gets `opt.heal = true` on add and on merge. A defense custom spell gets `opt.combat = true`.

`ns.AddAPL` refuses a maintenance buff. `ns.DropSpellOnList` sends those spells to `ns.AddDef`. The names `TEST`, `(OLD)`, `(PT)` do not come out of `ns.API.CursorSpell`.

Combat modes (`ns.COMBAT_MODES`): `auto`, `single`, `aoe`. There is no burst mode: the addon targets leveling and learning.

- `ns.CombatMode()` is the player's choice.
- `ns.ResolveCombatMode()`: if `auto` and `EnemyCount() >= autoEnemies` (floor 2), returns `aoe`, otherwise `auto`.
- `ns.SetCombatMode` remembers the last manual mode in `lastManualMode` (never `auto`).
- The Behavior page sets the mode with a dropdown (`ns.SetCombatMode`).
- `EnemyCount([maxYards])` counts hostile nameplates. Outside player combat, any hostile nameplate counts; in combat, only those in combat. With no nameplate, a hostile target counts as 1. Optional `maxYards` (bands 10 / 28 via `TargetRangeBand` / `CheckInteractDistance`). Nameplates must be enabled for auto AoE.
- `roleAuto` (default true): `ns.SyncAutoRole` picks the role from talents, stance and range. The Behavior page role dropdown calls `ns.SetRoleChoice`: `auto` sets `roleAuto = true`, any role sets it false and pins that role (`ns.RoleChoice` reads it back).
- `CombatNotice`: Hunter/Warlock in combat → "call pet" / "pet not attacking" as a screen message.
- Deferred spellbook index (`RebuildSpellBookIndex`): warmed at login / lazy remap only. **No** `SPELLS_CHANGED` (ConROC neither) — learn / level-up = soft Invalidate + `ButtonFetch` 0.5 s. Glow without action tooltip.

`ns.CoerceChecked` only accepts `true`, `1`, `"1"`. `ns.IsStepEnabled` refuses `false`, `0`, `"0"`.

## Profiles (`Core.lua`)

`ns.PROFILE_ORDER = { "pve", "pvp" }`. Old `base` / `custom` profiles are dropped at login.

`autoProfile` (default true): `ns.ApplyAutoProfile` picks PvP in battlegrounds and arenas, when PvP flagged in the open world or targeting an attackable player, PvE otherwise (never back to PvE in combat). The Behavior page profile dropdown calls `ns.SetProfileChoice` (`auto`, `pve`, `pvp`; a fixed profile sets `autoProfile = false`).

The active profile is copied into `ns.db.profiles[key]` by `FlushProfile` (profile change, options, logout) and reloaded by `BindProfile`. Profile fields: `apl`, `aplDrop`, `def`, `defDrop`, `role`, `combatMode`, `lastManualMode`, `autoEnemies`, `weaponBuff`.

`ns.ResetCurrentProfile` clears these lists for the current profile, resets `autoEnemies = 3`, `lastManualMode = single`, `combatMode = auto`, normalized role. The other profiles stay. `ns.ResetAll` calls the same function.

Migrations in `defaults()`:

- `listVersion ~= 4`: clears the global `apl`, `aplDrop`, `def`, `defDrop` **and** those of each profile.

Bump `listVersion` only when old saves must be discarded. Players then lose their reorderings.

Other defaults: `showRotation`, `showDefense`, `showInterrupt`, `showPurge`, `showCleanse`, `showWeapon` true; `role` `damage` then normalized; `autoEnemies` 3; `combatMode` `auto`; initial profile `pve` if the `profiles` table does not exist.

## Interface

There is no HUD window. Every cue is a glow on an action-bar button (`Glow.lua`):

- rotation: the first queue spell, only if `ns.queueGlowOk` (ready, resources, not out of range);
- defense, interrupt, purge, cleanse and weapon buff each have their own glow, switched by `show*`;
- a Blizzard `ActionButtonSpellAlertTemplate` frame per button and cue, tinted by `ns.Color`; plain texture fallback;
- no glow while the player is dead, on a taxi, mounted, eating, or resting in town (`ns.API.ShouldHideIdle`);
- hunter / warlock pet reminders (`CombatNotice`) appear once as a screen message;
- optional alert sounds (`ns.SOUNDS`, picked per alert on the Highlights page; the first choice is no sound) for interrupt, cleanse and weapon.

`UI.lua` only holds the shared `ns.UI` table and the `RefreshRoles` / `RefreshModes` hooks.

Options (`KnowYourRotationOptions`, inside the Settings panel):

- landing page (canvas), then sub-categories in this order:
- **Highlights** and **Behavior**: native vertical Settings layouts (`registerHighlights`, `registerBehavior`). Every control is a `Settings.RegisterProxySetting` that reads / writes `ns.db` (checkboxes, dropdowns, the AoE slider, color swatches). Highlights lists only the cues the class has;
- **Rotation**, **Defense**, **Profiles**: canvas pages sharing one host frame, built from Blizzard templates (`UIPanelButtonTemplate`, `InsetFrameTemplate`, `WowStyle1DropdownTemplate`, `UICheckButtonTemplate`);
- editor: one list at a time, picked with a spec dropdown (`SpecList`) and, for the rotation, a mode dropdown (`auto`/`single`/`aoe`); rows with checkbox, Up, Down, Remove and an optional delay box (`showHoldColumn`); a drop zone at the end;
- Profiles page: reset this profile, export / import.



## Highlight (`Glow.lua`)

`ns.GlowFetch` (at most every 2 s, or forced) scans:

- `ActionButton1-12`, `MultiBarBottomLeft/BottomRight/Right/Left`, `MultiBar5-7`;
- `StanceButton`;
- Dominos `DominosActionButton1-132` if loaded;
- Bartender4 `BT4Button1-180`;
- ElvUI `ElvUI_Bar1-10Button1-12`.

Matching by readable ID, then by name only if that name is not shared by another spell. No `FindSpellActionButtons`: that search lit up the whole bar. Macros go through `GetMacroSpell`.

Overlays `button.WFROverlays` (Blizzard spell-alert glow, tinted):

| Key | Color | Trigger |
| --- | --- | --- |
| `next` | white | first spell of the queue, not a heal |
| `heal` | green | heal (`queueHeal` or `IsHealSpell`) |
| `def` | blue, or green if heal | defense |
| `kick` | bolt icon | interrupt |
| `purge` | circle icon | purge |
| `cleanse` | green | dispel |
| `weapon` | red | enchant to redo |

`showRotation` and `showDefense` switch the rotation and defense glows off (`GlowClear`, `GlowClearDef`). Interrupt, purge, cleanse and weapon have their own `Glow*` functions, switched by their own `show*` flag in `Tick`.


## Spell resolution

`ns.API.Resolve(spellID)` caches in `resolveCache` (cleared at login). `LEARNED_SPELL_IN_TAB`, `SPELL_PUSHED_TO_ACTIONBAR`, `PLAYER_TALENT_UPDATE` and `PLAYER_LEVEL_UP` clear the whole cache after 1.2 s. `SPELLS_CHANGED` only clears misses, once per burst (the camelot client spams it).

1. Override `C_Spell.GetOverrideSpell` if it is a readable number.
2. If the player knows that ID, keep it.
3. Otherwise the original ID if known.
4. Otherwise the ID obtained by name (`C_Spell.GetSpellInfo` or `GetSpellInfo`), if known.
5. Otherwise a spellbook walk (`GetSpellBookSkillLineInfo`, then index 1–400, banks player/pet/`spell`/`0`/`1`).
6. Cache `false` if nothing. `Known` is "Resolve ≠ nil".

`CursorSpell` reads `GetCursorInfo`. It requires a `spell` or `spellid` type when a type is present, then finds the spellbook spell by name. A cursor ID whose name the player does not know is rejected.

Auras: `C_UnitAuras.GetPlayerAuraBySpellID` for the player, then `GetAuraDataBySpellName`, otherwise `GetAuraDataByIndex` up to 40. Comparison by resolved ID, normalized name (without "Rank"), or family (`seal`, blessing, aura, aspect, armor).

A personal buff (`nobuff` without `heal`) is always read on the player. The seal is a helpful buff: looking for it on the hostile target makes it reappear in the queue.

On the camelot client, choosing a target can make auras unreadable (*secret values*). A failed read is not an absence. The seal is remembered for **30 seconds** after the cast (Classic duration), then it is suggested again even in combat. Blessings last 5 minutes in this memory, auras and aspects 30 minutes, unless the game gives a shorter real duration. A DoT cast on the target is remembered for **18 seconds** (or until the target changes) if the target aura is unreadable. Heals (`opt.heal`) keep looking at the ally to heal.

The queue imitates ConROC: the 1st spell is the one to cast now, the 2nd and 3rd are the next ones **after** this simulated press. A spell outside the list does not cut the suggestion: on the next tick, the priority is recomputed.

Heals — unit: `opt.unit` if present, otherwise `mouseover`, `target`, `focus`, `targettarget`, otherwise `player`. `HealHealth` uses `LowestFriendly` (player, mouseover, target, focus, targettarget, pet, party1–4) when none of mouseover/target/focus is friendly. A dead or attackable unit is not friendly.

## Opening the options

There are no slash commands and no minimap button. The options live in the game Settings window (Options → AddOns). `ns.RegisterOptions` registers a text-only landing page as the category, then Highlights and Behavior (native) and Rotation, Defense and Profiles (canvas) as sub-categories. The landing page shows the detected role, mode and profile and the GitHub links, expandable with +. The canvas pages share one host frame moved into whichever panel is open; panels are created hidden so Settings' first `Show()` fires `OnShow`. `ns.RefreshOptions` does nothing while they are closed.

## `KnowYourRotationDB` schema

```
listVersion          = 4
profile              = "pve" | "pvp"
showRotation, showDefense, showInterrupt, showPurge,
showCleanse, showWeapon
barOnly, autoProfile, cleanseGroup, showPhysics
soundKick, soundCleanse, soundWeapon = sound key from `ns.SOUNDS` ("none" = off)
colors.next / heal / def / weapon
role, combatMode, lastManualMode, autoEnemies, weaponBuff
apl, aplDrop, def, defDrop     -- mirror of the active profile
profiles[key]        -- same list fields + role/mode/weapon
```

## Adding a spell

1. ID in `ns.Spell.<Class>` (`Data.lua`).
2. If heal or HoT: `ns.HEAL_SPELL_IDS`, including useful ranks.
3. If long buff or aura: `ns.MAINTENANCE_BUFF_IDS` and a `step` in `DefDefaults` only.
4. Otherwise a `step` in `APLDefaults`, and in `APLModes` if AoE differs.
5. Weapon enchant: `WEAPON_BUFFS` entry (ranks, enchant IDs, tokens). No combat step.
6. Interrupt / purge / cleanse: the dedicated tables, not the queue.
7. New text: add the English string to `Locale.lua`.
8. Version in `VERSION.txt` and `KnowYourRotation.toc`.
9. Bump `listVersion` only if current saves must be invalidated.

Check in game: `/reload`, checked spell, unchecked spell, removed spell (it must not come back), neighboring profile intact, target at full health (no heal), low health (heal first), nameplates for auto AoE.

## What not to do

- Copy the AddOns folder over the repository.
- Patch a Blizzard API to "help" detection.
- Compare only raw IDs without `Resolve` or without the name.
- Put a `MAINTENANCE_BUFF_IDS` buff in the rotation.
- Change `packRows` without reading old saves (numeric `on`, flat list from before the modes).
- Forget to bump the version in `VERSION.txt` and `KnowYourRotation.toc`.
- Dispel the raid: `BuildCleanse` only looks at `player`.
- Assume `hybrid`, `range` or `caster` are the stored keys for all lists. See `ActiveSpec` and the aliases at the bottom of `Lists.lua`.

## Heal threshold and hidden health

`UnitHealth` is hidden by the client in combat. `ns.API.Health` falls back to `UnitHealthPercent`, then to 100.

- `ns.API.AutoHealThreshold(spellID, unit, fallback)` returns `100 - healSize / maxHealth * 100`, clamped to 30–92. The heal size is parsed from `C_Spell.GetSpellDescription` (`ns.API.HealAmount`, cached, wiped by `InvalidateSpells`). Max health is remembered by `ns.API.MaxHealth` while readable. Steps with their own `hp` below 50 (emergency heals) keep it. `autoHeal = false` turns it off.
- When health is hidden, `ns.BuildHiddenHeal` picks the heal to cast and `ns.GlowHiddenHeal` shows its glow with an alpha taken from `UnitHealthPercent("player", true, curve)`: the curve is 1 below the threshold and 0 above, and the result goes straight into `SetAlpha` without being read.

## Options load time

The page host and the spell-list rows are built by `ns.PrebuildOptions` / `ns.WarmOptionsList` 4 and 6 seconds after login (out of combat), so the first click in Settings is not slow. `ns.RefreshOptions` rebuilds the spell list only on the Rotation and Defense pages.

## Weapon buff pick

`ns.SelectedWeaponBuff` returns the player's pick (`weaponBuff`, per profile) only if a rank of it is learned, otherwise `ns.AutoWeaponBuff`: the first learned entry of a role priority list (shaman melee: Windfury, Flametongue, Rockbiter, Frostbrand; other shaman roles: Flametongue first), or of `ns.WEAPON_BUFFS` order for other classes. With nothing learned it returns nothing and no weapon cue is shown. The Highlights dropdown lists Automatic plus the learned buffs only.

Rogues coat both weapons: with an off-hand weapon equipped (`ns.WeaponIsDual`, item class 2 in slot 17) each hand has its own pick (`weaponBuff`, `weaponBuffOff`, both per profile and in the export as `W=` / `O=`). Automatic main hand: Instant, Deadly, Wound, Crippling, Mind-numbing; off hand: Deadly, Instant, Crippling, Wound, Mind-numbing (first learned). `buildDualWeapon` reads each hand with `handState`: a missing or wrong poison, or one with 30 s or less left, is suggested; main hand first. A missing reading must hold for 1.5 s and is ignored during the 3 s grace after a cast; an unanswered reading never nags. Hands are read with `C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)` (what the Blizzard buff frame uses), falling back to the `GetWeaponEnchantInfo` shim.
