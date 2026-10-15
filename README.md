# Know Your Rotation

Rotation helper for **WoW Forever** (Classic Era combat on the camelot / Midnight-family client, interface `16001`).

It highlights the spell to press next with a glow on your action-bar button, and does the same for heals, long defense buffs, interrupts, purges, cleanses, and weapon imbues. There is no HUD window.

Current version: **1.0.0-beta.2** (beta). Download: **[CurseForge](https://www.curseforge.com/wow/addons/know-your-rotation)**.

**Beta:** the addon works, but not every class and level range has been played through yet, and the default spell lists are still being tuned for WoW Forever. Please report wrong suggestions, missing glows or Lua errors in the [issues](https://github.com/vattiss/know-your-rotation/issues).

**Status:** open source (MIT). Source, issues and pull requests: [github.com/vattiss/know-your-rotation](https://github.com/vattiss/know-your-rotation).

## Requirements

- WoW Forever Classic client (`_classic_beta_`, camelot)
- Interface version `16001`
- All nine Classic classes: Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid

Forever uses its own spell IDs for some abilities (for example Devotion Aura). The addon resolves spells by **name + spellbook**, so ranks and remapped IDs still match.

## Install

**CurseForge (recommended):** install [Know Your Rotation](https://www.curseforge.com/wow/addons/know-your-rotation) with the CurseForge app, or download the file from the project page. The app keeps it up to date.

**By hand:** download the zip from [CurseForge](https://www.curseforge.com/wow/addons/know-your-rotation/files) or from the [GitHub releases](https://github.com/vattiss/know-your-rotation/releases) (each GitHub zip has a SHA-256 checksum and a build attestation), then:

1. Copy the `KnowYourRotation` folder into:

   `World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation`

2. Restart the client (for later updates of the same folder a `/reload` is enough).
3. Enable **Know Your Rotation** in the add-on list.

The folder must contain `KnowYourRotation.toc`, the `.lua` files and the `images` folder.

## What it does

| Cue | What lights up |
| --- | --- |
| **Rotation** | The next spell from your list, only when you can press it right now |
| **Heal** | A heal once your missing health is about the size of that heal |
| **Defense** | Missing long buffs and auras, plus defensive spells when health is low |
| **Interrupt / Purge / Cleanse** | Your interrupt while the target casts, purge for an enemy magic effect, cleanse for an effect you can remove |
| **Weapon buff** | A missing or expiring weapon buff (shaman imbues, rogue poisons on each hand, warlock stones) |
| **Totems** | The totems in your totem bar: buff totems at the start of the fight, slows and area totems once enemies are in melee. A cue next to the rotation, so the other buttons keep going |
| **Messages** | Pet reminders for hunters and warlocks; "Not on your action bars (in rotation order): A, B" when the next spells are learned but on no bar (the glow then goes to the next spell that is on a bar); "Spell: Rank 1 is on your action bar, but you know Rank 3" when the bar holds an older rank than the one you learned |

Aimed Shot, Multi-Shot and Volley avoid clipping Auto Shot, and energy spells account for the next energy tick.
### Glow colors

| Color | Meaning |
| --- | --- |
| White glow | Next rotation spell |
| Green glow | Cleanse, and heals that are kept up (Renew, Power Word: Shield) |
| Blue glow | Defense buff |
| Yellow glow | Interrupt |
| Purple glow | Purge |
| Mint glow | Quick heals, pressed when the health asks for it |
| Red glow | Weapon buff |
| Cyan glow | Auto Shot, Concussive Shot (hunter) |
| Orange glow | Totem |

The rotation, heal, quick heal, defense, weapon, hunter shot and totem colors can be changed on the Highlights page.
### Combat list vs defense

- **Rotation** = short combat spells (strikes, shocks, heals, judgements…).
- **Defense** = buffs that last more than one minute, auras, and long self-buffs (Blessing of Might, Devotion Aura, Mark of the Wild, Inner Fire, aspects, Battle Shout, armors…). Those never enter the combat queue.
- Unchecked spells stay in the editor but are ignored in combat.
- Custom spells are added from the cursor (spellbook drag). Test / OLD spells are rejected.

### Heals

Heals in your lists light up when they are needed:

- **Smart heal threshold** (Behavior page, on by default): a heal is offered once the health you are missing is about what that heal restores, so it is not wasted. The heal size comes from the spell text and your maximum health is remembered out of combat.
- Emergency heals keep their own low threshold (for example Lay on Hands around 20%).
- The game hides your health and mana from add-ons (the debug mode showed it is hidden all the time, not only in combat). The heal glow therefore follows **your own** health, faded in and out by the game itself. Defensive spells that wait for low health (Power Word: Shield, Shield Wall, …) work the same way, in the defense color.
- Out of combat a heal follows the unit it would land on: a friendly target, or a friendly mouseover when the game's mouseover cast is on, otherwise you.
- **Group members:** a heal or shield also lights up for a party or raid member you select (not for other players). Their health is hidden too, so the game fades the glow by that member's health. Quick heals (mint) show once enough health is missing; heals that are kept up (Renew, Power Word: Shield; green) show whenever they are missing, and the damage glow stays visible next to them.

Full health → no heal suggestion, the damage rotation stays visible.

### The pull and racials

- Out of combat, with an enemy target out of melee range, the first spell with a cast time in your list opens the fight (for example Fireball, Smite, Lightning Bolt): the cast is free while the mob runs in, and the instants (DoTs, shocks) come right after it.
- Offensive racials (Blood Fury, Berserking, Elune's Light, Eureka) are on by default and come first: at the pull, once the target is within about 28 yards, before the opener; in combat whenever they are ready.

### Hunter shots, pets and wands

- Auto Shot and Concussive Shot are a separate cyan cue next to the rotation, so the rotation (Serpent Sting, Arcane Shot, …) keeps going. Auto Shot lights up only when it is not running (pressing it again would stop it) and the target is in shooting range; neither lights up in melee range.
- Stings are skipped on Mechanical and Elemental targets, which are immune to them.
- Call Pet is offered only once you have tamed a pet and are fighting; Revive Pet out of combat when it is dead.
- Priests, mages and warlocks get the wand (Shoot) once the main spell is out of mana; it needs a wand equipped.

### Druid forms

With the hybrid style the list follows your form (Cat Form: the cat list, Bear Form: the bear list). The tank list starts with Bear Form, so you are told to shift when you are out of it. After a shapeshift the spells of the new form are found on the bar that the game pages in.

### Finishing a low target

Execute and Hammer of Wrath light up as soon as the game lets you use them. Rogue Eviscerate does not wait for 5 combo points when the target is low: from 2 points it lights up once the target is below about 8% health per point (2 points: 16%, 3 points: 24%, …). While leveling (below level 20) Eviscerate also goes from 2 points on a mob below your level and from 3 points otherwise, instead of waiting for 5. Shadow Word: Death and Shadowburn light up below 20%. In combat the target's health is hidden from add-ons, so the game itself fades the finisher glow in and the regular rotation glow (for example Sinister Strike) out at that point: only one of them shows.

### Profiles

Two profiles, PvE and PvP, each with its own rotation and defense lists. With **Profile: Automatic** (Behavior page) dungeons and raids use PvE; battlegrounds, arenas, or targeting an enemy player use PvP; everything else uses PvE. Picking PvE or PvP by hand keeps that profile. On the Rotation and Defense pages a Profile dropdown lets you edit the PvE or PvP lists whichever one is in use. On the Profiles page you can reset the active profile and export / import it as text.

### Disabling on one character

The Highlights page has a "Disable on this character" switch: while it is on, the addon shows no glows and plays no sounds or messages on the current character. The setting is stored per character.

### Combat modes

`Automatic`, `Single` and `AoE`. Add, remove, and reorder are **per mode**. Automatic pulls with the single-target list and switches to the AoE list once enough enemies are fighting you (default 3, set on the Behavior page). The addon is tuned for leveling and learning a class, so there is no burst or raid mode.

### Your own order

The lists are a starting point for learning a class, and they cannot know your talents. On the **Rotation** page you can reorder the spells, switch a spell off, remove it, or drag one in from your spellbook; **Reset list** restores the default for the list you are looking at. What you cannot edit are the conditions of a spell (for example "only from 3 combo points"): those belong to the spell and are part of the addon. When a new addon version has to replace the saved lists, you get one message at login telling you so.

### Roles

Per class: damage, tank, heal, and the extra Classic styles (hunter range/melee, shaman caster/melee, druid hybrid / cat / bear). With **Role: Automatic** (Behavior page) the role comes from the name of your main talent tree (Protection: tank; Holy, Discipline, Restoration: heal; anything else: damage), and hunters and shamans switch melee / ranged by distance; pick a role to keep it fixed.

### Options pages

- **Highlights**: disable on this character; **Stay quiet in towns and inns** (on by default: no glow or message while you are resting and not in combat); one section per cue (rotation, defense, interrupt, purge, cleanse, weapon buff, totems) with its switch, sound and color. Only the cues your class can use are listed. The weapon buff is Automatic by default: the best one you have learned (for example Rockbiter at level 1, then Flametongue, then Windfury for a melee shaman); you can also pick one of the learned buffs. Rogues with an off-hand weapon get a separate main-hand and off-hand poison pick (Automatic: Instant on the main hand, Deadly on the off hand once learned).
- **Behavior**: role, combat mode, AoE threshold and profile (each can be Automatic); smart heal threshold (a heal is offered once the missing health is about the heal size; emergency steps below 50% keep their own value); Classic swing and auto-shot timing.
- **Rotation** and **Defense**: the spell lists. Pick the list with the two dropdowns at the top (role and, for the rotation, the mode), then reorder, switch off, remove, or drag in spells. "Show the delay column" adds the per-spell re-suggest delay.
- **Profiles**: reset, export, import.

## Opening the options

There are no chat commands and no minimap button. Open the game menu → Options → AddOns → Know Your Rotation and expand it with +. The main entry is a landing page: what the addon is for, what it detected right now (role, mode, profile), and the GitHub and issue links.

## Files

```
KnowYourRotation.toc           # load order
Locale.lua                     # English strings
API.lua                        # spell info, spellbook, resolve
APICooldown.lua, APIAura.lua,  # cooldowns and holds, auras and combo points,
APIUnit.lua, APITotem.lua,     # health / range / roles / casts, totems,
APIWeapon.lua, APIStep.lua     # weapon enchants, StepOk
Data.lua                       # IDs, racials, interrupts, cleanse
Physics.lua                    # Auto Shot clip / energy tick timing
Lists.lua                      # default APLs and defense lists
APL.lua                        # saved lists, merge, add/remove
Share.lua                      # profile import / export
UI.lua                         # shared ns.UI table (no HUD window)
Options.lua                    # configuration
Glow.lua                       # action-bar glow
Rotations.lua                  # queue and cue builders
Debug.lua                      # debug mode: what the game API really answers
Core.lua                       # profiles, events, auto role / profile
images/logo.tga                # add-on list icon (128x128, made by art/logo.ps1)
tests/                         # unit tests and the WoW API stand-in (not shipped)
tools/, types/                 # dev helpers and LuaLS type definitions (not shipped)
```

Saved variables: `KnowYourRotationDB` (account), `KnowYourRotationCharDB` (per character).

## Notes

- This is a **helper**, not a bot. You still press the keys.
- Racials appear in the editor: the offensive ones are on by default, the others off. Air Walk is never put in the combat list.
- Do not overwrite Blizzard spell APIs from other add-ons; this one reads `C_Spell` / `C_SpellBook` and never patches them.

## What to expect, and how to help

The addon was built for **leveling and learning a class**: it shows the order of your spells, reminds you of buffs, totems, pets and weapon buffs, and says when a spell is learned but not on your bars. It is not a tuned endgame rotation. Your talents, cooldowns, consumables and boss mechanics are not part of the lists, so a level 60 character gets a sensible order, not an optimal one. Most of the spells of levels 20 to 60 have not been played through in the game yet, so some of them will be wrong, and your reports are what fixes them.

You can change the lists yourself (**Rotation** page: order, on / off, remove, add from your spellbook, **Reset list**). The conditions of a spell are part of the addon and cannot be edited there.

### Collecting data for a bug report

The addon has a debug mode that records what the game really answers (a value, nothing, or a hidden value) and why a spell was or was not suggested. It is off by default and costs a little CPU.

1. Open **Behavior** and switch on **Collect debug data**.
2. Play the way you normally do, and try to bring the problem up (the wrong spell is glowing, a spell you expect is missing, a cue stays on).
3. Open **Profiles** and press **Debug report**. The text appears in the box below the buttons, already selected: press `Ctrl+C` to copy it.
4. **Clear debug data** empties the record, so a new test starts clean (a full record stops collecting new situations, and it starts over by itself at the next login).

The data is also written to your character's saved variables when you `/reload` or log out:
`World of Warcraft\_classic_beta_\WTF\Account\<account>\<realm>\<character>\SavedVariables\KnowYourRotation.lua`
(`KnowYourRotationCharDB.debug`). Attach that file if the text is too long to paste (rename it to `.txt` first: GitHub does not accept `.lua` attachments).

The report holds your class and level, the client and addon version, counts of what the game answered per situation (in combat or not, enemy, friend or no target), the reasons the addon gave per spell (`addon says | ...`, `defense says | ...`), and the names of buffs, totems and error messages the client sent. It holds no character name, realm or chat.

### Reporting an issue

Open an issue at [github.com/vattiss/know-your-rotation/issues](https://github.com/vattiss/know-your-rotation/issues) and pick **Bug or wrong suggestion** (or **Idea or missing spell**). The form asks for:

- class, level, talent tree (if you know it) and what you were doing (alone, in a group, in combat or not);
- what you expected, and what the addon showed instead (a screenshot of the action bar helps);
- the debug report from the steps above.

## For agents and contributors

Pull requests are welcome: [CONTRIBUTING.md](CONTRIBUTING.md) says how to make one and which checks to run. The player guide above is not the implementation map. Before changing code, read [AGENTS.md](AGENTS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Every push runs a check on GitHub: syntax, TOC file list, version match, luacheck with the exact list of WoW globals, StyLua formatting, and the unit tests with a minimum line coverage (`tests/MIN_COVERAGE`). Run the tests locally with LuaJIT: `luajit tests/run.lua` (`--uncovered` lists the lines no test reaches). The recommended VS Code extensions (Lua, WoW API, StyLua) are listed in `.vscode/extensions.json`. Releases are built by GitHub Actions from a version tag (`v1.0.0-beta.1`): bump `VERSION.txt` and the TOC, push, then push the tag. The release zip comes with a SHA-256 checksum and a GitHub build attestation (`gh attestation verify <zip> --repo vattiss/know-your-rotation`).

The git repository is the source of truth. The copy under `World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation` must be refreshed from this repo. Do not replace this repo with files taken from the game folder.

## Support

Source (public): [https://github.com/vattiss/know-your-rotation](https://github.com/vattiss/know-your-rotation).

Bugs and ideas: [github.com/vattiss/know-your-rotation/issues](https://github.com/vattiss/know-your-rotation/issues). The landing page of the options has the same link to copy.

## Credits

Based on Forever Rotation by Vohnka (MIT). Know Your Rotation is developed by Castorei (vattiss).

## License

[MIT](LICENSE) — free to use, modify, fork, and redistribute. See the copyright notice in the license file. Contributions are welcome: open an issue or a pull request.
