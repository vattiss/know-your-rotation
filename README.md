# Know Your Rotation

Rotation helper for **WoW Forever** (Classic Era combat on the camelot / Midnight-family client, interface `16001`).

It highlights the spell to press next with a glow on your action-bar button, and does the same for heals, long defense buffs, interrupts, purges, cleanses, and weapon imbues. There is no HUD window. It does **not** cast spells for you.

Current version: **1.0.0**

**Status:** open source (MIT). Source, issues and pull requests: [github.com/attilavarga96/know-your-rotation](https://github.com/attilavarga96/know-your-rotation).

## Requirements

- WoW Forever Classic client (`_classic_beta_`, camelot)
- Interface version `16001`
- All nine Classic classes: Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid

Forever uses its own spell IDs for some abilities (for example Devotion Aura). The addon resolves spells by **name + spellbook**, so ranks and remapped IDs still match.

## Install

1. Copy the `KnowYourRotation` folder into:

   `World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation`

2. Restart the client or type `/reload`.
3. Enable **Know Your Rotation** in the add-on list.

The folder must contain `KnowYourRotation.toc` and the `.lua` files.

## What it does

| Surface | Role |
| --- | --- |
| **Rotation** | The next combat ability from your checked list lights up on its action-bar button |
| **Defense** | Missing long buffs / auras, plus emergency buttons when health is low |
| **Weapon** | Missing weapon imbue (shaman / rogue poisons, etc.) |
| **Interrupt / Purge / Cleanse** | Target interrupt, enemy magic purge, dispellable debuffs |
| **Classic timing** | White-hit swing (main + off-hand), hunter auto-shot clip, energy tick |

### Glow colors

| Color | Meaning |
| --- | --- |
| White glow | Next damage / utility spell |
| Green glow | Heal (only when someone actually needs healing) |
| Blue glow | Defense buff |
| Red glow | Weapon imbue |

### Combat list vs defense

- **Rotation** = short combat spells (strikes, shocks, heals, judgements…).
- **Defense** = buffs that last more than one minute, auras, and long self-buffs (Blessing of Might, Devotion Aura, Mark of the Wild, Inner Fire, aspects, Battle Shout, armors…). Those never enter the combat queue.
- Unchecked spells stay in the editor but are ignored in combat.
- Custom spells are added from the cursor (spellbook drag). Test / OLD spells are rejected.

### Heals

Heals are suggested from the **friendly unit that needs them** (mouseover, friendly target, then you / party if you are attacking a mob).

Examples (paladin):

- Holy Shock / Holy Light around **80%**
- Flash of Light around **70%**
- Lay on Hands around **20%**

Full health → no heal suggestion, damage rotation stays visible. Same idea for Priest, Shaman, and Druid (fast heal vs big heal vs HoT).

### Profiles

Four profiles, all saved independently:

| Profile | Typical use |
| --- | --- |
| Base | Default / shared |
| PvE | PvE |
| PvP | PvP |
| Customs | Experiments |

PvE or PvP is picked automatically (dungeons and raids = PvE; battlegrounds and arenas = PvP; in the open world your PvP flag or an attackable player as target = PvP); you can also switch in the options window. **Reset** only wipes the **selected** profile. You can export / import a profile as text. Optional auto-switch uses PvE or PvP from the instance type.

### Combat modes

`Auto` / `Single` / `AoE` / `Burst`. Add, remove, and reorder are **per mode**. Auto uses the single-target list until enough enemies are nearby (default: 3).

### Roles

Per class: damage, tank, heal, and the extra Classic styles (hunter range/melee, shaman caster/melee, druid hybrid / cat / bear). The role is picked automatically from your talents, stance and range; pick it by hand in the options to turn that off.

### Advanced options

(Automatic role and PvE / PvP profile detection is on the Profiles page.)

- Only suggest spells that are on your action bars
- Group dispel limited to types your class can remove
- Classic combat timing (white hits, dual wield, auto-shot, energy)
- Overlay colors and alert volume

## Opening the options

There are no chat commands and no minimap button. Open the game menu → Options → AddOns → Know Your Rotation; expand it with + for General, Rotation, Defense, Advanced and Info. Role, combat mode and PvE / PvP profile are detected automatically.

## Files

```
KnowYourRotation.toc              # load order
Locale.lua                     # English strings
API.lua                        # spell resolve, auras, ready, heals
Data.lua                       # IDs, racials, interrupts, cleanse
Physics.lua                    # swing / auto-shot / energy timing
Lists.lua                      # default APLs and defense lists
APL.lua                        # saved lists, merge, add/remove
Share.lua                      # profile import / export
UI.lua                         # shared ns.UI table (no HUD window)
Options.lua                    # configuration
Glow.lua                       # action-bar glow
Rotations.lua                  # queue and cue builders
Core.lua                       # profiles, events, auto role / profile
```

Saved variables: `KnowYourRotationDB` (account), `KnowYourRotationCharDB` (per character).

## Notes

- This is a **helper**, not a bot. You still press the keys.
- Racials appear in the editor (off by default). Air Walk is never put in the combat list.
- Do not overwrite Blizzard spell APIs from other add-ons; this one reads `C_Spell` / `C_SpellBook` and never patches them.

## For agents and contributors

The player guide above is not the implementation map. Before changing code, read [AGENTS.md](AGENTS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

The git repository is the source of truth. The copy under `World of Warcraft\_classic_beta_\Interface\AddOns\KnowYourRotation` must be refreshed from this repo. Do not replace this repo with files taken from the game folder.

## Support

Source (public): [https://github.com/attilavarga96/know-your-rotation](https://github.com/attilavarga96/know-your-rotation).

## License

[MIT](LICENSE) — free to use, modify, fork, and redistribute. See the copyright notice in the license file. Contributions are welcome: open an issue or a pull request.
