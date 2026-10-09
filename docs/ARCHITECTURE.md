# Know Your Rotation architecture

Classic Era rotation helper for the **camelot** client of WoW Forever (interface `16001`, `_classic_beta_` folder). The player always presses the keys. The addon suggests up to 3 spells, plus a reminder for defense, interrupt, purge, dispel and weapon enchant, then puts a glow on the matching action bar button.

See also [AGENTS.md](../AGENTS.md) for the repository, the AddOns path, the push rule and the checks (tests, lint, format, types).

Tests: `tests/run.lua` is a small describe / it runner with line coverage (pure Lua, LuaJIT `jit.util` for the executable lines, a line hook for the executed ones). `tests/wow.lua` builds a fresh WoW-like global environment per test (units, spells and spellbook, auras, totems, action slots, frames, events, timers, Settings API) and loads the addon files into it with `setfenv`, so module-local state never leaks between tests.

## Client constraints

Forever reuses the Midnight / camelot API, not the Classic 1.14 API alone.

The reference for this API is the `ref/wow-ui-source` submodule (`forever` branch): `Interface/AddOns/Blizzard_APIDocumentationGenerated` for functions, events and their secret-value rules, the rest of `Interface/AddOns` for how the Blizzard UI uses them. Read the relevant entry there, and the section of this file for the part you change, before editing code (see AGENTS.md, *Before you start any change*).

- Spell IDs can differ from public Classic (example: devotion aura). The code stores `1.60.1` lab IDs in `ns.Spell`, then `ns.API.Resolve` finds the spell **known to the player** through `C_Spell.GetOverrideSpell`, `IsPlayerSpell` / `C_SpellBook`, then the name in the spellbook.
- Some values are *secret values*. The `API*.lua` files and `APL.lua` go through `issecretvalue` / `canaccessvalue` before reading a number or a string. An unreadable value is treated as absent.
- Every Blizzard call is wrapped in a `pcall`. Never replace `C_Spell`, `C_SpellBook`, `GetSpellInfo` or the unit functions.
- A single TOC: `KnowYourRotation.toc`, with `## Interface: 16001` and `## AllowLoadGameType: camelot`.
- Global SavedVariables: `KnowYourRotationDB`.

## Lifecycle

`Core.lua` creates an invisible frame and a table `handlers`, one function per event (`handlers.PLAYER_LOGIN`, `handlers.UNIT_AURA`, ...); the frame's `OnEvent` only looks the event up. Events about the player alone (`UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_START`, `UNIT_INVENTORY_CHANGED`, `UNIT_POWER_UPDATE`) are registered with `RegisterUnitEvent(..., "player")`, and `UNIT_AURA` for `player`, `target`, `focus` and `mouseover` only, so nameplates and party members do not wake the addon.

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

Load order (single TOC): `Locale.lua` → `API.lua` → `APICooldown.lua` → `APIAura.lua` → `APIUnit.lua` → `APITotem.lua` → `APIWeapon.lua` → `APIStep.lua` → `Data.lua` → `Physics.lua` → `Lists.lua` → `APL.lua` → `Share.lua` → `UI.lua` → `Options.lua` → `Glow.lua` → `Rotations.lua` → `Debug.lua` → `Core.lua`.

| File | Role |
| --- | --- |
| `Locale.lua` | English strings only. `ns.T(key)` returns the string, or the raw key if missing. |
| `API.lua` | `ns.API`: spell info, spellbook index, `Resolve` / `Known`. Creates `ns.API.I`, the table the API files share (helpers `readable`, `safe`, `unitExists`, `normName`, and state used by more than one file). |
| `APICooldown.lua` | Cooldown tracking after a cast, holds (`HoldRemain`), `IsRotationAction`. |
| `APIAura.lua` | Aura reading and memory (`HasAura`, `FindAura`), combo points, the look-ahead (`PredictBegin` / `PredictConsume`). |
| `APIUnit.lua` | Health, range, enemy count, heal unit, roles (`SyncAutoRole`), creature types, casts, purge. |
| `APITotem.lua` | Shaman totems kept through combat. |
| `APIWeapon.lua` | Weapon enchants and weapon tooltips. |
| `Debug.lua` | Debug mode (Behavior page, off by default): once a second it classifies what the API answers (value, SECRET, nil, error) in the current context (combat / idle, enemy / friend / no target) and counts selected events (`UNIT_ATTACK`, `UNIT_COMBAT`, `UNIT_SPELLCAST_SUCCEEDED`, `PLAYER_TOTEM_UPDATE`, `UI_ERROR_MESSAGE`) plus the client's error texts. Counts live in `ns.db.debug`, capped at 700 keys and 150 texts. It also records, for up to 16 steps of the list, why each is or is not offered (`addon says`) and which buttons it would glow on (`glows on buttons`), why each defense step (aspects, auras, shields) is or is not offered (`defense says`), what the shaman's totem bar buttons hold (`MultiCastActionButtonN`: action slot, type, id), the names of the buffs on you and the totems in the shaman's slots (out of combat), `ns.API.TotemState` for each totem step (slot content, time left, near, effect on you), and `UnitAffectingCombat` / `UnitExists(target)` as the client answers them. `ns.Debug.Report()` turns them into text (Profiles page, "Debug report" button; "Clear debug data" empties them). No chat command. |
| `APIStep.lua` | `Ready`, `StepOk` and `STEP_CHECKS`, `WhyNot`. |
| `Data.lua` | IDs, roles, colors, racials, interrupts, purges, cleanses, enchants, long buffs, heals. |
| `Physics.lua` | Auto Shot clip, energy tick. Option `ns.db.showPhysics`. No combat log. |
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

Evaluated by `ns.API.StepOk` in order. A missing field is ignored. The conditions are the list `STEP_CHECKS` in `APIStep.lua`: each entry is the option it belongs to (or nil = always) and a small function that returns the reason the step is refused (shown as the WhyNot tooltip), or nil. The cooldown, readiness and range logic that follows is plain code at the end of `StepOk`. A new option is one new entry in that list.

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
| `nocreature` | `true` = Mechanical / Elemental. Table / string = canonical types (`undead`, `demon`, …). `UnitCreatureType` is secret for units that are not player-controlled or in your group (`SecretWhenUnitIdentityRestricted`); an unreadable type counts as unknown and blocks nothing. |
| `creature` | Inverse: the step is OK only if the target type matches (Exorcism Undead/Demon). An unknown type lets the step through; Exorcism's `usable` check still refuses a wrong target. |
| `totem` | Totems are not rotation steps any more: `ns.BuildTotem` (a cue of its own, own glow and color, `showTotem`) reads the spells in the shaman's totem bar slots (`ns.API.TotemBar`: `MultiCastActionButton1-4` through `GetActionInfo`, readable in combat) and offers every one that is missing (they sit in different slots, so they glow together), by the `when` of its `ns.TOTEM_INFO` row: `pull` (buff totems: in combat or with an enemy targeted, so at the start of the fight, at range), `hostile` (Searing: an enemy targeted) or `melee` (Earthbind, Stoneclaw, Magma: target in melee range, because a slow or area totem only helps there). Totems without a `when` (Tremor, Grounding) stay on the defense list. The glow stays until the totem is down and never takes a slot of the rotation queue; `ns.IsTotemCue` keeps them out of the lists (`AddAPL` refuses them, `listVersion` 5 replaced the old lists). The step option itself, used for the check: suggests the totem if absent or remain ≤ `refresh` (default 1 s). `ns.API.TotemRemain`: `GetTotemInfo` is secret in combat (`SecretWhenTotemSlotSecret`), so readable reads (and `PLAYER_TOTEM_UPDATE`) teach each totem's slot and duration, and in combat the addon's own casts stand in (`ns.API.NoteTotemCast`, one totem per slot: fire 1, earth 2, water 3, air 4; `ns.TOTEM_INFO` gives slot and duration until a real one is read; the client reports 300 s for Stoneskin Totem). The drop point is stored with `UnitPosition`; more than 30 yd away the totem counts as gone (the debug data showed the effect still on you at 20-24 yd; 30 is a guess, nothing was measured above 24 yd), so a new pull gets a new one. Cleared on death. If the totem's slot holds a different totem you dropped (Earthbind in the earth slot, Magma in the fire slot) that is still up, the wanted totem counts as up too, so it does not replace your choice while it lasts. When the totem was only seen in its slot (drop point unknown, e.g. after a /reload), is a buff totem (`pull`), has stood for 5 s and its effect is not on you out of combat, it counts as gone. When the totem is gone or more than 30 yd away but its effect aura is still on you (`Stoneskin` for Stoneskin Totem, matched by the spell name with and without " Totem"), it counts as up for the aura's remaining time: no new totem while the effect holds. (Found in the debug data: Stoneskin was suggested although the totem stood in its slot.) |
| `enemiesMin` / `enemiesYards` | Refuses if `EnemyCount(yards)` &lt; N (Whirlwind, Consecration, Swipe). |
| `skipLow` | Refuses DoT/mark if target health &lt; 20 % (trash) or &lt; 5 % (elite/raidmob). |
| `targetMana` | Refuses if the target has no mana (Viper Sting). |
| `needanybuff` | Requires at least one buff from the list on the player (Judgement after a seal). |
| `ifTargeting` | Requires the target to attack you (`ns.API.TargetAttacksYou`, Aspect of the Monkey). |
| `anybuff` | List of IDs. If the player has **any** of them, the step is refused. Used for exclusive seals, auras, aspects, armors. |
| `form` | Requires the form aura on the player (`ns.API.Form`). |
| `noform` | Refused if this form is active. |
| `combat` | Requires the player in combat. |
| `comboMin` | Minimum player/target combo points. |
| `pet` / `nopet` | Pet present or absent. |
| `ready = false` | Accepts the step without testing cooldown or usability. |
| `filler` | Spam spell with no own cooldown (Wrath, Heroic Strike, Sinister Strike…). Skipped only by a real cooldown, not by the GCD. `ns.Physics.Blocks` still applies. |
| `nocombat` | Refused if the player is in combat (Charge, Stealth, Prowl, Pyroblast as an opener). |
| `autoRepeat` | Auto-repeat attack (Auto Shot, wand Shoot): offered only while it is not running, since pressing it again would stop it. Never counts as a rotation action, so it does not take slot 1 from a filler. Priest, mage and warlock lists end with the wand: a filler the client reports as out of mana no longer passes, so the wand comes next. |
| `engaged` | Only in combat or with an enemy targeted (seals, totems, Tiger's Fury), so they are not suggested while walking around. |
| `enemyTarget` | Needs an attackable target, without a range check (Stealth, Prowl before a pull). |
| `needKnownAny` | At least one of these spells must be learned (Stealth needs Ambush, Garrote or Cheap Shot; Prowl needs Ravage or Pounce). |
| `weakTarget` | Only for a target below your level (an unknown level counts as not weak). Rogue leveling: Eviscerate from 2 combo points on a weak mob, from 3 on a mob of your level (up to level 19). |
| `maxLevel` | Offered only up to this character level (Stoneskin Totem up to 29, then Strength of Earth Totem takes its place). |
| `minLevel` | Offered only from this character level on (Strength of Earth 30, Mana Spring 40 in the damage lists, Rupture 40): early fights are too short for them. |
| `behind` | Must be behind the target (Backstab, Shred). Refused while the target attacks you or that is unknown (it faces you), or for 3 s after a "must be behind" error on that target (`UI_ERROR_MESSAGE`, `ns.API.NoteUIError`). `ns.API.TargetAttacksYou` reads `UnitThreatSituation("player", "target")` first (not secret for player vs target; 2 / 3 = you have aggro), and `UnitIsUnit("targettarget", "player")` only as a fallback: compound tokens are always secret on addon-restricted maps (`SecretWhenUnitComparisonRestricted`). No target's target (stunned, gouged) is allowed. |
| `nodebuff` + `unit = "player"` | Checks the debuff on you (Weakened Soul before Power Word: Shield). Without `unit`, a non-heal step checks the target. `refresh = 0` refuses while the debuff is up at all. |
| `notMelee` | Refused when the target is in melee range (`ns.API.TargetInMelee`): melee shaman Lightning Bolt / Lava Burst only for the pull. A spell ID as the value limits it to characters who know that spell (Stormstrike): until a melee shaman has Stormstrike, melee is weak and the shocks leave gaps, so it casts Lightning Bolt between them while the client says it has the mana (the filler is not offered when out of mana). (Found in the debug data: a level 2 shaman got nothing offered in melee, "not in melee range" 190 times against 69 offers.) |
| `inMelee` | Inverse: only when the target is in melee range (Frost Nova once the mob reaches the mage). |
| `notKnown` | Refused once this other spell is learned (Summon Imp until Summon Voidwalker). |
| `notTree` | Refused when the name of the talent tree with the most points contains this word (`ns.API.MainTree`): Frostbolt / Arcane Missiles not for a Fire mage, so Fireball comes next. |
| `swimming` | Only while swimming (Unending Breath). |
| `inGroup` / `orPet` | Only in a group, or with `orPet` also with a pet out: threat drops (Fade, Feint, Disengage) do nothing solo. |
| `petDead` / `notPetDead` | Hunter pet dead or not (`ns.API.PetDead`: a dead `pet` unit, or the "Your pet is dead" error, cleared by a live pet): Revive Pet instead of Call Pet. |
| `hpPerCombo` | Target health threshold of N% per combo point (Eviscerate: 8). |
| `needbuff` | Helpful aura ID required on the player (Garrote and Ambush require Stealth). |
| `needdebuff` | Debuff ID required on the target (Conflagrate requires Immolate). |
| `proc` | The client must report the spell as usable. Used for Overpower, Revenge, Riposte, Counterattack and Mongoose Bite. If the answer is hidden, the step is skipped. Do not read the combat log: that call is reserved for the Blizzard UI and blocks the addon. |
| `usable` | The client must report the spell as usable (Exorcism, Holy Wrath, Backstab). If the answer is hidden, the step is skipped. |
| `manaMax` | Refused if the player's mana percentage is above this threshold (Life Tap). |
| `hpMin` | Refused if health (player, or `unit`) is under this percentage. |
| `hold` | Seconds after a successful cast during which the spell is no longer suggested (DoT, HoT, snare). Forever/Classic defaults. Editable next to each spell. `0` = no aura delay. Harmful holds are tied to the target: its GUID when readable, otherwise (an NPC's GUID is secret, `SecretWhenUnitIdentityRestricted`) the current target, cleared on every target change. A `filler` is never held, even with a saved hold. For `nodebuff` / `nobuff`, the readable aura wins; hold = Forever fallback. No CLEU. |
| `anydebuff` | List of IDs. If the target has **any** of them, the step is refused. One sting, one curse. |

`ns.API.Ready`: spell resolved, no own cooldown running, no `noMana`. The GCD (about 1.5 s) does not remove the spell from the queue: it stays the next button to press. A longer cooldown (Judgement, Shock, Aimed Shot, Blast Wave…) removes it until it ends, and the next step in the list is tested. This applies to all classes, racials and defense.

The camelot client often hides `GetSpellCooldown` in combat. On a successful cast, `ns.API.NoteSpellCast` starts the spell's base cooldown (`GetSpellBaseCooldown`, otherwise `ns.COOLDOWNS`). The three shaman shocks share this time (`ns.COOLDOWN_GROUPS`). A proc that makes the spell available earlier may have to wait for this delay to end, because the game does not let the addon read the remaining time.

Overpower, Revenge, Riposte, Counterattack and Mongoose Bite (`opt.proc`) are only suggested if `IsSpellUsable` answers true. A hidden answer skips the step. The combat log is not read.

`Physics.lua` (Behavior option `showPhysics`, "Classic Auto Shot timing", default true): `UNIT_SPELLCAST_SUCCEEDED` with Auto Shot (75) starts the shot timer, its length from `UnitRangedDamage` (secret in combat, so the last readable value is kept) or the ranged weapon tooltip. `ns.Physics.Blocks` holds Aimed Shot, Multi-Shot and Volley in the last 0.4 s before an Auto Shot; `StepOk` asks it, so the option really turns this off. `UNIT_POWER_UPDATE` resyncs the 2 s energy tick on a gain of about 20 (40 with Adrenaline Rush); `ns.Physics.EnergySoon` lets a spell through when its energy arrives within 0.45 s. There is no swing timer: `UNIT_ATTACK` is not a per-swing event and the combat log is blocked. A movable combo point window follows the HUD chrome for the rogue and the cat druid. Player settings are stored in `KnowYourRotationCharDB` (SavedVariablesPerCharacter). The first login copies `KnowYourRotationDB` once.

A spell that is only helpful (`IsHelpful` and not `IsHarmful`) can pass through the power cost if `IsSpellUsable` is false or absent. A harmful spell with `usable == false` is refused.


## Queues (`Rotations.lua`)

`ns.BuildQueue`: up to 3 slots. The list is read in order; spells **already cast in the current pass** (`ns.NoteRotationCast` / `rotSpent`) are skipped — even if they had not been displayed yet. When no usable step remains in the pass, `rotSpent` is cleared and the queue **restarts from the beginning**. Also reset on target change and when leaving combat.

- ignores an unchecked step, a weapon enchant and a maintenance buff;
- the spell being cast is not shown again: it counts as used, and `PredictConsume` assumes it was cast (DoT, CD / shocks, buff, stealth, combo points), so slot 1 shows what comes next;
- a leading **filler** yields to a lower **action** (shock, DoT, CD, proc) as soon as it is ready and in range `in` or unknown (`notOut`) — the shock then moves to slot 1. Starfire / Ice Lance / Swipe / auto racials do not steal;
- the same spell appears only once in the queue: slots 2-3 show other spells. A step of an `anybuff` / `anydebuff` group is refused by `StepOk` once the look-ahead (`PredictConsume`) marked another step of that group;
- `opt.hold` removes a spell after a cast for N seconds (DoT / snare) in addition to the "pass" marking;
- slot 1 prefers `RangeState` `in`; otherwise `notOut`. `out` → slots 2–3;
- `ns.ApplyRotationEdit` (Up / Down / Apply) clears the cache and re-evaluates the glows without `/reload`;
- `IsSpellUsable` false during the GCD or a cast no longer prevents a shock from entering the queue;
- unless slot 1 already is a heal, the first `StepOk` heal is moved to the head (also from slot 2 or 3, since only slot 1 glows) and the queue is trimmed back to 3.

`ns.queueHeal[id]` (list ID and resolved ID) is used for the green highlight.

`ns.BuildDefense`: first checked defense step that passes `StepOk`, in two passes: steps with `hp` (defensive cooldowns) first, then the rest (buffs), each in list order. A step whose spell is on no action button cannot glow, so the first one that is on a bar goes first (only one of the three hunter aspects is usually on the bars); when none is, the first stays. A lapsed Battle Shout does not hide Shield Wall at 20%.

`ns.BuildInterrupt`: known and ready class ID, hostile target that is casting an interruptible spell (`notInterruptible` is return 8 of `UnitCastingInfo`, 7 of `UnitChannelInfo`), and not clearly out of range. `ns.BuildPurge` has the same range check.

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
- `ns.ResolveCombatMode()`: if `auto`, out of combat always `auto` (pull with the single list, so openers like Charge stay first); in combat `aoe` when `EnemyCount() >= autoEnemies` (floor 2), otherwise `auto`.
- `ns.SetCombatMode` remembers the last manual mode in `lastManualMode` (never `auto`).
- The Behavior page sets the mode with a dropdown (`ns.SetCombatMode`).
- `EnemyCount([maxYards])` counts hostile nameplates. Outside player combat, any hostile nameplate counts; in combat, only those fighting you: on your threat table (`UnitThreatSituation`), or targeting you or your pet. A readable "not on your threat table" still checks the pet, then excludes the mob; `UnitAffectingCombat` is only a fallback when threat and the target check are both hidden. With no nameplate, a hostile target counts as 1. Optional `maxYards` (bands 10 / 28 via `TargetRangeBand` / `CheckInteractDistance`). Nameplates must be enabled for auto AoE.
- `roleAuto` (default true): `ns.SyncAutoRole` picks the role from the name of the talent tree with the most points (`specRole`, `C_SpecializationInfo.GetSpecializationInfo`): Protection = tank; Holy, Discipline or Restoration = heal; anything else = damage. Never by tree position or the client's role field. No talent data (low level) keeps the current role. Druid bear / cat lists come from the form (`ns.ActiveSpec`); shaman and hunter switch melee / ranged by distance (`TargetInMelee`). The Behavior page role dropdown calls `ns.SetRoleChoice`: `auto` sets `roleAuto = true`, any role sets it false and pins that role (`ns.RoleChoice` reads it back).
- `CombatNotice`: Hunter/Warlock in combat → "call pet" / "pet not attacking" as a screen message.
- Deferred spellbook index (`RebuildSpellBookIndex`): warmed at login / lazy remap only. **No** `SPELLS_CHANGED` (ConROC neither) — learn / level-up = soft Invalidate + `ButtonFetch` 0.5 s. Glow without action tooltip.

`ns.CoerceChecked` only accepts `true`, `1`, `"1"`. `ns.IsStepEnabled` refuses `false`, `0`, `"0"`.

## Profiles (`Core.lua`)

The Rotation and Defense pages have a Profile dropdown that picks which profile's lists are shown and edited (`editProfile` in `Options.lua`), independent of the profile in use; opening a page starts on the profile in use. Every list call of the editor goes through `ns.WithProfile(key, fn, ...)`: it saves the profile in use, binds the lists (`apl`, `aplDrop`, `def`, `defDrop`) of `key`, runs `fn`, writes them back to `key` and binds the profile in use again. While swapped, `ns.FlushProfile` does nothing and `ns.Tick` returns at once, so the glows never read the other profile's lists. The profile in use and the automatic switching are not touched.

`ns.PROFILE_ORDER = { "pve", "pvp" }`. Old `base` / `custom` profiles are dropped at login.

`autoProfile` (default true): `ns.ApplyAutoProfile` picks PvP in battlegrounds and arenas, or when targeting an attackable player in the open world (not by the PvP flag, which a PvP realm keeps on in contested zones), PvE otherwise (never back to PvE in combat). The Behavior page profile dropdown calls `ns.SetProfileChoice` (`auto`, `pve`, `pvp`; a fixed profile sets `autoProfile = false`).

The active profile is copied into `ns.db.profiles[key]` by `FlushProfile` (profile change, options, logout) and reloaded by `BindProfile`. Profile fields: `apl`, `aplDrop`, `def`, `defDrop`, `role`, `combatMode`, `lastManualMode`, `autoEnemies`, `weaponBuff`.

`ns.ResetCurrentProfile` clears these lists for the current profile, resets `autoEnemies = 3`, `lastManualMode = single`, `combatMode = auto`, normalized role. The other profiles stay. `ns.ResetAll` calls the same function.

Migrations in `defaults()`:

- `listVersion ~= 4`: clears the global `apl`, `aplDrop`, `def`, `defDrop` **and** those of each profile.

Bump `listVersion` only when old saves must be discarded. Players then lose their reorderings.

Other defaults: `showRotation`, `showDefense`, `showInterrupt`, `showPurge`, `showCleanse`, `showWeapon`, `showTotem` true; `role` `damage` then normalized; `autoEnemies` 3; `combatMode` `auto`; initial profile `pve` if the `profiles` table does not exist.

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

`ns.GlowFetch` reads the action buttons of the default bars (`Action`, `MultiBar*`), the shaman's totem bar (`MultiCastActionButton1-12`), the stance bar and, when loaded, Dominos, Bartender4 and ElvUI. A spell that is on none of them has no button to glow.

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

`ns.API.Resolve(spellID)` caches in `resolveCache` (cleared at login). `LEARNED_SPELL_IN_TAB`, `SPELL_PUSHED_TO_ACTIONBAR`, `PLAYER_TALENT_UPDATE` and `PLAYER_LEVEL_UP` clear the whole cache after 1.2 s. `SPELLS_CHANGED` only clears misses, once per burst (the camelot client spams it). A spell is known when `IsPlayerSpell`, `IsSpellKnownOrOverridesKnown`, `IsSpellKnown` or `C_SpellBook.IsSpellInSpellBook` says so. `FindSpellBookSlotForSpell` is not used: the Forever client returns a slot for spells not learned yet too (debug data, hunter level 5: Aspect of the Hawk), and the spellbook index skips `FutureSpell` items.

1. Override `C_Spell.GetOverrideSpell` if it is a readable number.
2. If the player knows that ID, keep it.
3. Otherwise the original ID if known.
4. Otherwise the ID obtained by name (`C_Spell.GetSpellInfo`), if known. The names tried are the spell name and its English hint names (`ns.SPELL_NAME_HINT[id]`: a string, or a list of strings, for IDs Forever remaps).
5. Otherwise a spellbook walk (`GetSpellBookSkillLineInfo`, then index 1–400, banks player/pet/`spell`/`0`/`1`).
6. Cache `false` if nothing. `Known` is "Resolve ≠ nil".

`CursorSpell` reads `GetCursorInfo`. It requires a `spell` or `spellid` type when a type is present, then finds the spellbook spell by name (the cursor's own bank first, without changing the cached bank list). A cursor ID whose name the player does not know is rejected.

Auras: `C_UnitAuras.GetPlayerAuraBySpellID` for the player, then `GetAuraDataBySpellName`, otherwise `GetAuraDataByIndex` up to 40. Comparison by resolved ID, normalized name (without "Rank"), or family (`seal`, blessing, aura, aspect, armor).

A personal buff (`nobuff` without `heal`) is always read on the player. The seal is a helpful buff: looking for it on the hostile target makes it reappear in the queue.

On the camelot client, choosing a target can make auras unreadable (*secret values*). A failed read is not an absence. The seal is remembered for **30 seconds** after the cast (Classic duration), then it is suggested again even in combat. Blessings last 5 minutes in this memory, auras and aspects 30 minutes, unless the game gives a shorter real duration. A DoT cast on the target is remembered (until the target changes) if the target aura is unreadable: for the duration last seen on the target, else the spell's own duration (`ns.SPELL_HOLD` / step `hold`: Moonfire 9 s, Flame Shock 12 s, …), else **18 seconds**. A self-buff cast without a family length is remembered the same way (Slice and Dice, Renew, Rejuvenation), else 30 s. Attacks and heals cast on someone else are not remembered as your buffs.

Target debuffs on an enemy count only when **you** applied them (`HARMFUL|PLAYER`), so another warlock's Corruption does not hide yours. Debuffs one per target whoever applies them (`ns.SHARED_DEBUFF_IDS`: Sunder Armor, Expose Armor, Faerie Fire, Hunter's Mark, Curse of the Elements / Shadow, Demoralizing Shout / Roar, Thunder Clap, Fire Vulnerability, Winter's Chill, the judgements) count from anyone. Debuffs on a friendly unit (Weakened Soul) always count from anyone.

`ns.API.Cooldown`: after a cast the addon tracks the spell's base cooldown, which also covers secret readings. When the client reports a readable real cooldown (longer than the GCD), that value wins, so talent-shortened cooldowns (Reverberation, Improved Fire Blast) are not held back. Heals (`opt.heal`) keep looking at the ally to heal.

In combat the client may hide cooldowns (`SecretWhenCooldownsRestricted`), and a hidden cooldown used to count as ready, so a racial on cooldown (Blood Fury) came back now and then. Now every cooldown read while the client allows it is remembered until its end and used when the next reads are secret; casts also start a tracked cooldown, and the racials have fallback lengths in `ns.COOLDOWNS` (found by name, so the class's own spell ID does not matter).
The queue imitates ConROC: the 1st spell is the one to cast now, the 2nd and 3rd are the next ones **after** this simulated press. A spell outside the list does not cut the suggestion: on the next tick, the priority is recomputed.

Heals — unit (`ns.API.HealUnit`, also used by `HealHealth` and `HealRangeUnit`): the unit a press from the bar would heal. `opt.unit` if present, otherwise a friendly `mouseover` (only with the client's `enableMouseoverCast` on), otherwise a friendly `target`, otherwise `player` (an enemy target or no target heals yourself). Health, auras and range all come from that one unit. A dead or attackable unit is not friendly.

## Opening the options

There are no slash commands and no minimap button. The options live in the game Settings window (Options → AddOns). `ns.RegisterOptions` registers a text-only landing page as the category, then Highlights and Behavior (native) and Rotation, Defense and Profiles (canvas) as sub-categories. The landing page shows the detected role, mode and profile and the GitHub links, expandable with +. The canvas pages share one host frame moved into whichever panel is open; panels are created hidden so Settings' first `Show()` fires `OnShow`. `ns.RefreshOptions` does nothing while they are closed.

## `KnowYourRotationDB` schema

```
listVersion          = 4
profile              = "pve" | "pvp"
showRotation, showDefense, showInterrupt, showPurge,
showCleanse, showWeapon, showTotem
autoProfile, cleanseGroup, showPhysics
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

Measured with the debug mode on a level 2 shaman (client 1.60.1): `UnitHealth("player")`, `UnitHealth("target")` and `UnitPower("player", mana)` are **secret all the time**, in combat and out, with or without a target. Only `UnitHealthMax` / `UnitPowerMax` of the player are readable. `ns.API.Health` therefore falls back to `UnitHealthPercent` (also secret) and then answers 100, and `ns.API.HealthHidden()` is true. What follows from it:

- Every rule that compares health or mana in numbers cannot decide in the queue: `hp` (heals, defensives, Drain Life), `hpMin` (Bloodrage, Life Tap, Hellfire), `skipLow` (no DoT on an almost dead mob), `manaMax`. `hp` and `manaMax` steps are shown by the hidden-value glows instead (`ns.BuildHiddenHeal`, `Defense`, `Execute`, `Pet`, `Mana`); the WhyNot tooltip says "health is hidden by the game". `hpMin` and `skipLow` always pass, so Bloodrage / Hellfire are not held back at low health and DoTs are not skipped on dying mobs.
- The glow follows **your own** health (and the target's or pet's for finishers and Mend Pet), not a party member's.
- Other reads that work in combat (same data): `UnitCreatureType`, `UnitGUID`, `UnitThreatSituation`, `UnitIsUnit`, `UnitReaction`, `UnitLevel`, `UnitClassification`, `GetComboPoints`, `IsSpellUsable`. Secret in combat: `GetSpellCooldown`, `GetTotemInfo`, `UnitAttackSpeed`, `UnitRangedDamage`; `C_UnitAuras.GetAuraDataByIndex` raises an error in combat.

- `ns.API.AutoHealThreshold(spellID, unit, fallback)` returns `100 - healSize / maxHealth * 100`, clamped to 30–92. The heal size is parsed from `C_Spell.GetSpellDescription` (`ns.API.HealAmount`, cached, wiped by `InvalidateSpells`). Max health is remembered by `ns.API.MaxHealth` while readable. Steps with their own `hp` below 50 (emergency heals) keep it. `autoHeal = false` turns it off.
- When health is hidden, `ns.BuildHiddenHeal` picks the heal to cast and `ns.GlowHiddenHeal` shows its glow with an alpha taken from `UnitHealthPercent("player", true, curve)`: the curve is 1 below the threshold and 0 above, and the result goes straight into `SetAlpha` without being read.

## Options load time

The page host and the spell-list rows are built by `ns.PrebuildOptions` / `ns.WarmOptionsList` 4 and 6 seconds after login (out of combat), so the first click in Settings is not slow. `ns.RefreshOptions` rebuilds the spell list only on the Rotation and Defense pages.

## Weapon buff pick

`ns.SelectedWeaponBuff` returns the player's pick (`weaponBuff`, per profile) only if a rank of it is learned, otherwise `ns.AutoWeaponBuff`: the first learned entry of a role priority list (shaman melee: Windfury, Flametongue, Rockbiter, Frostbrand; other shaman roles: Flametongue first), or of `ns.WEAPON_BUFFS` order for other classes. With nothing learned it returns nothing and no weapon cue is shown. The Highlights dropdown lists Automatic plus the learned buffs only.

Rogues coat both weapons: with an off-hand weapon equipped (`ns.WeaponIsDual`, item class 2 in slot 17) each hand has its own pick (`weaponBuff`, `weaponBuffOff`, both per profile and in the export as `W=` / `O=`). Automatic main hand: Instant, Deadly, Wound, Crippling, Mind-numbing; off hand: Deadly, Instant, Crippling, Wound, Mind-numbing (first learned). `buildDualWeapon` reads each hand with `handState`: a missing or wrong poison, or one with 30 s or less left, is suggested; main hand first. A missing reading must hold for 1.5 s and is ignored during the 3 s grace after a cast; an unanswered reading never nags. Hands are read with `C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)` (what the Blizzard buff frame uses), falling back to the `GetWeaponEnchantInfo` shim.

## Finishers and executes with hidden target health

The client hides the target's health in combat too. Spells that are only usable on a low target anyway (Execute, Hammer of Wrath) use `proc = true`, so the client's own "usable" answer decides. Other low-target steps (`hp` with `unit = "target"`, or `hpPerCombo`, e.g. Eviscerate at 8% target health per combo point from 2 points, Shadow Word: Death, Shadowburn) get a second glow: `ns.BuildHiddenExecute` picks the first such step that is otherwise ready, and `ns.GlowHiddenExecute` lights it with an alpha from `UnitHealthPercent("target", true, curve)`, like the hidden heal glow. When the health is readable, `StepOk` compares it directly (`needHp = Combo() * hpPerCombo`).

While that finisher glow is active and the rotation glow sits on another spell, `ns.GlowFadeForFinisher` fades the rotation glow with the reverse curve (`fadeCurve`: 0 below the threshold, 1 above). Both alphas come from the same hidden target health, so only one glow shows; the overlay's normal alpha is kept in `frame.kyrAlpha` and restored afterwards.

## Self-buffs in combat

In combat the client may return no auras at all, which looks like "buff missing". `ns.API.HasAura` therefore trusts the remembered expiry of a self-buff (`heldAura`: set when the buff is seen with its remaining time, or when it is cast, by family length such as 30 min for armors) while in combat, and only releases it on a "not found" out of combat. `StepOk`'s `nobuff` check uses the same rule, so Demon Skin, armors, aspects and similar buffs are not re-suggested mid-fight.

Defense steps that wait for low health (`hp`, on the player: Power Word: Shield, Shield Wall, Divine Protection, …) get the same treatment when health is hidden: `ns.BuildHiddenDefense` picks the first ready one from `ns.GetDef()` and `ns.GlowHiddenDefense` lights it in the defense color with the player-health curve.

The five hidden-value builders (`BuildHiddenHeal`, `Execute`, `Pet`, `Mana`, `Defense`) share one loop, `hiddenPick` in `Rotations.lua`, and differ only in which steps they want, which `opt` flag switches the step's own value check off, and how the threshold is computed. `ns.BuildHiddenHeal` also takes rotation steps with `hp` on the player that are not heals (Drain Life at 40 %). Two more glows use the same `hiddenGlow` builder in `Glow.lua`: `ns.BuildHiddenPet` / `ns.GlowHiddenPet` for `hp` with `unit = "pet"` (Mend Pet, pet-health curve), and `ns.BuildHiddenMana` / `ns.GlowHiddenMana` for `manaMax` steps (Life Tap) when `ns.API.ManaHidden()`: the alpha comes from `UnitPowerPercent("player", 0, false, curve)`. `StepOk` refuses `manaMax` while mana is hidden unless the builder passes `noManaGate`.
