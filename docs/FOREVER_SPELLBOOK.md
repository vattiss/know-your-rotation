# Forever catalog — spells 1–60 and talents

Snapshot of the **WoW Forever** (beta) spellbooks and trees. Used to align `Data.lua` / `Lists.lua` without inventing IDs.

- Client : **1.60.1.69876** (spellbook 20 Sept 2026)
- Talents : calculators [wowforevertalent.com](https://wowforevertalent.com/) (updated 24 Sept 2026)
- New paladin IDs: [wowforeverbuilds.com/abilities/paladin](https://wowforeverbuilds.com/abilities/paladin) (build 1.60.1.69876)
- Diff Era : [foreverdiff.com](https://foreverdiff.com/) · [foreverchanges.pro/changes](https://foreverchanges.pro/changes)
- Wowhead Forever : [wowhead.com/forever](https://www.wowhead.com/forever) (JS pages, less usable than the spellbook above)

Ranks may still change before launch. A spell **already in `ns.Spell`** resolves by **name + spellbook**: a Classic ID is often enough. A **new** spell needs a real Forever (lab) ID plus a `step` in the lists.

Addon legend: **IN** = key in `ns.Spell` · **GAP** = missing, add if combat · **UTIL** = outside the queue (portals, tracking, passives) · **TAL** = talent / talent spell

Weapon passives, languages, *Attack*, *Throw*, *Shoot*: omitted everywhere (useless for the HUD).

---

## Current addon coverage

`ns.Spell` is a **ConROC Classic Era** core, not the Forever spellbook. Known Era spells generally stay **IN**. The **new rotation spells** are the gap.

To add first (combat / heal / defense / proc):

| Class | Spells missing from `Data.lua` (combat) |
| --- | --- |
| Warrior | Victory Rush, Spearing Strike |
| Paladin | Holy Strike, Light's Vigil, Voice of Truth, Swift Judgement, Templar's Bulwark |
| Hunter | Sniper Shot, Enchanted Flare, Strider Kick, Lacerate (chasseur), Scatter Shot |
| Rogue | Mutilate, Venom |
| Priest | Shadow Word: Death, Penance, Binding Heal, Prayer of Mending, Chastise, Confounding Flash, Contingency Plan, Divine Grace |
| Shaman | Lava Burst, Riptide, Water Shield, Fire Nova (spell, no longer a totem), Totemic Projection, Call of the Elements / Ancestors / Spirits |
| Mage | Frostfire Bolt, Ice Lance, Arcane Blast |
| Warlock | Incinerate, Wrack, Bane of Havoc, Summon Incubus ; *Bane of Agony* = former Curse of Agony (renamed) |
| Druid | Lacerate (ours), Mangle / Primal Bite, Berserk, Wild Growth, Revive |
| Racials (active) | Will to Survive, Elune's Light, Eureka!, Shatter Curse, Rapid Regeneration, Cannibalize ; Walk on Air deliberately excluded |

`Seal of Fury` et `Crusader Strike` are already in `ns.Spell.Paladin`.

---

## Warrior

ForeverDiff: 44 spells · 54 talents. Spellbook: 42 spells + general.

### Arms

| Spell | Ranks / lvl | Addon |
| --- | --- | --- |
| Battle Stance | 1 | UTIL |
| Charge | 3 ranks | IN |
| Hamstring | 3 | IN |
| Heroic Strike | 9 | IN |
| Mocking Blow | 5 | IN |
| Mortal Strike | 4 | IN TAL |
| Overpower | 4 | IN |
| Rend | 7 | IN |
| Retaliation | 20 (changed) | IN |
| Spearing Strike | **New** · 1 | **GAP** |
| Sweeping Strikes | 30 | IN TAL |
| Tactical Mastery | 14 · now trainable | UTIL |
| Thunder Clap | 6 (changed, Battle+Def) | IN |
| Victory Rush | **New** · 20 · 30 s · heal 10% | **GAP** |

### Fury

Battle Shout, Berserker Rage, Berserker Stance, Bloodthirst, Challenging Shout, Cleave, Death Wish, Demoralizing Shout, Execute, Intercept (30/42/52), Intimidating Shout, Piercing Howl, Pummel, Recklessness, Slam (**15 s CD**, ranks 20–54), Whirlwind.

All **IN** except Challenging Shout / Intimidating Shout (**UTIL** / rare).

### Protection

Bloodrage, Concussion Blow, Defensive Stance, Disarm, Last Stand, Revenge, Shield Bash, Shield Block (2 charges / 7 s), Shield Slam, Shield Wall (15 min, 60 %), Sunder Armor, Taunt.

All **IN**.

### Talents (51 pts, 3 trees)

**Arms** (max) : Improved Heroic Strike 3, Deflection 5, Improved Rend 3, Improved Charge 2, Improved Tactical Mastery 5, Improved Overpower 2, Anger Management 1, Deep Wounds 3, **Spearing Strike 1 (new)**, Two-Handed Weapon Specialization 3, Impale 2, **Bloodthrill 5 (new)**, Sweeping Strikes 1, **Weaponmaster 5 (new)**, Improved Slam 2, Improved Hamstring 3, Mortal Strike 1.

**Fury** : Booming Voice 5, Cruelty 5, Iron Will 5, Unbridled Wrath 5, Improved Cleave 3, Piercing Howl 1, Blood Craze 3, **Boundless Rage 3 (new)**, Dual Wield Specialization 5, **Raging Blows 1 (new)**, Enrage 5, Improved Execute 2, **Precision 3 (new)**, Death Wish 1, Improved Intercept 2, Improved Berserker Rage 2, Flurry 5, Bloodthirst 1.

**Protection** : Shield Specialization 5, Anticipation 5, Improved Bloodrage 2, Toughness 5, Improved Thunder Clap 3, Last Stand 1, **Master of Defense 2 (new)**, Improved Revenge 3, Defiance 3, Improved Sunder Armor 3, Improved Disarm 3, **Vanguard 1 (new)** (Charge in Defensive), Improved Shield Wall 2, Concussion Blow 1, Improved Shield Bash 2, **Bastion 5**, **Focused Rage 3 (new)**, Shield Slam 1.

---

## Paladin

ForeverDiff: 81 spells · 60 talents. Spellbook: 53 spells.

### Holy

Blessing of Light, Blessing of Wisdom, Cleanse, Consecration (trainable at 20), Divine Favor, Exorcism, Flash of Light, Greater Blessing of Light / Wisdom, Hammer of Wrath, Holy Light, Holy Shock, Holy Wrath, Lay on Hands, **Light's Vigil New** (ID **1310911**), Purify, Redemption, Seal of Light / Righteousness / Wisdom, Sense Undead, Turn Undead, **Voice of Truth New** (ID **1310897**).

IN: heals, seals, judgements, Cleanse, Consecration, Exorcism, Hammer of Wrath, Holy Shock/Wrath, Lay on Hands. **GAP**: Light's Vigil, Voice of Truth. UTIL: Redemption, Sense Undead, Turn Undead, Greater Blessings (group).

### Protection

Blessing of Freedom / Kings / Protection / Sacrifice / Salvation, Concentration Aura, Devotion Aura, Divine Intervention / Protection / Shield, resistance auras, Greater Blessing of Kings / Salvation, Hammer of Justice, Holy Shield, Righteous Fury, **Seal of Fury New** (IN `SealFury`), Seal of Justice, **Swift Judgement New**, **Templar's Bulwark New** (ID **1311015**).

**GAP**: Swift Judgement, Templar's Bulwark.

### Retribution

Blessing of Might, Greater Blessing of Might, **Holy Strike New** (8 ranks from 6), Judgement (no longer consumes the seal, 10 s), Repentance, Retribution Aura, Seal of Command, Seal of the Crusader.

**GAP**: Holy Strike. Crusader Strike already **IN**.

### Talents (52 · 20 new · 25 changed)

**Holy** : Improved Holy Strike 2, Divine Strength 5, Divine Intellect 5, Healing Light 3, Spiritual Focus 2, Improved Seals 3, Unyielding Faith 2, Voice of Truth 1, Reverence 3, Purifying Power 2, Infusion of Light 2, Illumination 5, Divine Favor 1, Divine Precision 3, Holy Shock 1, Consecrated Ground 2, Holy Power 5, Light's Vigil 1.

**Protection** : Toughness 5, Redoubt 5, Precision 3, Guardian's Favor 2, Anticipation 5, Improved Seal of Fury 1, Improved Righteous Fury 3, Shield Specialization 3, Sacred Duty 2, Swift Judgement 1, One-Handed Weapon Specialization 3, Improved Hammer of Justice 3, Templar's Bulwark 1, Reckoning 5, Iron Creed 5, Holy Shield 1.

**Retribution** : Deflection 5, Benediction 5, Improved Judgement 2, Holy Conduit 2, Conviction 5, Vindication 3, Sanctified Judgement 3, Seal of Command 1, Pursuit of Justice 2, Eye for an Eye 2, Sacred Arbiter 1, Crusade 2, Two-Handed Weapon Specialization 3, Vengeance 3, Repentance 1, Champion of the Light 3, Instrument of Law 2, Twist of Light 1.

---

## Hunter

ForeverDiff: 94 spells · 54 talents. Spellbook: 88 (including 30 pet).

### Beast Mastery

Aspects Beast / Cheetah / Hawk / Monkey / Pack / Wild, Beast Lore, Bestial Wrath, Call Pet, Dismiss Pet, Eagle Eye, Eyes of the Beast, Feed Pet, Intimidation, Mend Pet, Revive Pet, Scare Beast, **Summon Hawk New**, Tame Beast, Tranquilizing Shot.

IN: aspects (Beast partial), Bestial Wrath, Call Pet, Intimidation, Mend Pet. **GAP**: Summon Hawk, Tranquilizing Shot. UTIL: lore / feed / tame / eagle / dismiss.

### Marksmanship

Aimed Shot (trainable, 2 s, CD shared with Multi-Shot), Arcane Shot, Auto Shot, Concussive Shot, Distracting Shot, **Enchanted Flare New**, Flare, Hunter's Mark, Multi-Shot, Rapid Fire, Scatter Shot, Scorpid / Serpent / Viper Sting, **Sniper Shot New**, Trueshot Aura, Volley.

IN: Aimed, Arcane, Auto, Concussive, Mark, Multi, Rapid, stings, Trueshot, Volley. **GAP**: Sniper Shot, Enchanted Flare, Scatter Shot, Distracting Shot, Flare.

### Survival

Counterattack, Deterrence, Disengage, Explosive / Freezing / Frost / Immolation Trap, Feign Death, **Lacerate New**, Mongoose Bite, Raptor Strike, **Strider Kick New**, Track *, Wing Clip.

IN: Counterattack, Deterrence, Disengage, Feign, Mongoose, Raptor, Wing Clip. **GAP**: Lacerate (hunter), Strider Kick, traps (optional). UTIL: Track *.

### Pets (30)

Bite, Claw, Charge, Cower, Dash, Dive, Growl, etc. + **New** : Dismember, Dust Cloud, Mine!, Pinch, Savage Rend, Swipe, Tendon Rip, Trickster's Dance, Web. Thunderstomp rank 4 new. Outside the player queue.

### Talents (50 · 14 new · 24 changed)

**Beast Mastery** : Deadly Aspects 5, Endurance Training 5, Focused Fire 2, Improved Aspect of the Monkey 3, Pathfinding 2, Improved Revive Pet 2, Bestial Swiftness 1, Unleashed Fury 5, Improved Mend Pet 2, Ferocity 5, Summon Hawk 1, Spirit Bond 2, Intimidation 1, Bestial Discipline 2, Frenzy 5, Bestial Wrath 1.

**Marksmanship** : Hawk Eye 3, Improved Concussive Shot 5, Lethal Attacks 5, Improved Stings 3, Efficiency 5, Careful Aim 5, Rapid Killing 2, Improved Arcane Shot 5, Lone Wolf 1, Trueshot Aura 1, Mortal Shots 5, Rapid Recuperation 2, Barrage 3, Scatter Shot 1, Ranged Weapon Specialization 5, Sniper Shot 1.

**Survival** : Improved Tracking 5, Deflection 5, Entrapment 5, Savage Strikes 2, Survivalist 5, Improved Wing Clip 3, Clever Traps 2, Surefooted 3, Deterrence 1, Survival Tactics 2, Predator's Edge 5, Counterattack 1, Resourcefulness 2, Expose Prey 2, Survivalist's Discipline 2, Strider Kick 1, Lightning Reflexes 5, Lacerating Strikes 1.

---

## Rogue

ForeverDiff: 58 spells · 50 talents. Spellbook: 40 + poisons.

### Assassination

Ambush, Cheap Shot, Cold Blood, Eviscerate, Expose Armor, Garrote, Kidney Shot, **Mutilate New**, Rupture, Slice and Dice, **Venom New** (40).

IN: all except **GAP Mutilate, Venom**.

### Combat

Adrenaline Rush, Backstab, Blade Flurry, Evasion, Feint, Gouge, Kick, Riposte, Sinister Strike, Sprint. All **IN**.

### Subtlety

Blind, Detect/Disarm Traps, Distract, Ghostly Strike, Hemorrhage, Pick Pocket, Premeditation, Preparation, Safe Fall, Sap, Stealth, Vanish.

IN: Ghostly, Hemorrhage, Premeditation, Stealth, Vanish. UTIL: Blind, traps, Pick Pocket, Sap, Safe Fall. **GAP**: Preparation (burst).

### Poisons

Crippling, Instant, Mind-numbing, Deadly, Wound, Blinding Powder. IN via `WEAPON_BUFFS` (except powder).

1H Axes: no longer a spell, a weapon skill.

### Talents (53 · 9 new · 30 changed)

**Assassination** : Improved Gouge 3, Remorseless Attacks 2, Malice 5, Ruthlessness 3, Murder 2, Improved Slice and Dice 3, Relentless Strikes 1, Improved Expose Armor 2, Lethality 5, Vile Poisons 5, Cold Blood 1, Improved Poisons 5, Vigor 2, **Mutilate 1**, Improved Kidney Shot 2, Seal Fate 5, **Venom 1**.

**Combat** : Improved Eviscerate 3, Improved Sinister Strike 2, Lightning Reflexes 5, Puncturing Wounds 3, Deflection 3, Precision 3, Endurance 2, Riposte 1, Improved Sprint 2, Improved Kick 2, **Flawless Execution 1**, Dual Wield Specialization 5, Blade Flurry 1, **Hack and Slash 5**, Weapon Expertise 2, Aggression 3, Adrenaline Rush 1.

**Subtlety** : Camouflage 5, Master of Deception 3, Opportunity 2, Setup 3, Elusiveness 2, Dirty Tricks 2, Improved Ambush 3, Initiative 3, Ghostly Strike 1, Improved Distract 2, Heightened Senses 2, Premeditation 1, Serrated Blades 3, Dirty Deeds 2, Preparation 1, Hemorrhage 1, Quietus 5, Cutthroat 5, Thousand Cuts 1.

---

## Priest

ForeverDiff: 82 spells · 54 talents. Spellbook: 56.

### Discipline

**Confounding Flash New**, **Contingency Plan New**, Dispel Magic, Divine Spirit, Elune's Grace, Feedback, Inner Fire, Inner Focus, Levitate, Mana Burn, **Penance New**, Power Infusion, PW: Fortitude / Shield, Prayer of Fortitude / Spirit, Shackle Undead, Starshards.

IN: Dispel (purge), Divine Spirit, Inner Fire/Focus, Mana Burn, PI, Fortitude, Shield. **GAP**: Penance, Confounding Flash, Contingency Plan. UTIL: Levitate, Shackle, Starshards (racial/book), Elune's Grace, Feedback.

### Holy

Abolish/Cure Disease, **Binding Heal New**, **Chastise New**, Desperate Prayer, **Divine Grace New**, Fear Ward (baseline for all), Flash / Greater / Heal / Lesser Heal, Holy Fire, Holy Nova, Lightwell, Prayer of Healing, **Prayer of Mending New**, Renew, Resurrection, Smite.

IN: heals, Holy Fire, Holy Nova, PoH, Renew, Smite. **GAP**: Binding Heal, Prayer of Mending, Chastise, Divine Grace. UTIL: Resurrection, Lightwell, Desperate Prayer.

### Shadow

**Dark Sacrifice New**, Devouring Plague (all), Fade, Hex of Weakness, Mind Blast / Control / Flay / Soothe / Vision, Prayer of Shadow Protection, Psychic Scream, Shadow Protection, **Shadow Word: Death New** (32, 15 s), SW: Pain, Shadowform, Shadowguard, Silence, Touch of Weakness, Vampiric Embrace.

IN: Fade, Mind Blast/Flay, Psychic Scream, SW: Pain, Shadowform, VE, Silence, Devouring Plague. **GAP**: SW: Death, Dark Sacrifice. UTIL: Mind Control/Vision/Soothe, Hex, Shadowguard, Touch of Weakness.

### Talents (53 · 13 new · 29 changed)

**Discipline** : Power in Light 5, Wand Specialization 2, Twin Disciplines 5, Silent Resolve 3, Holy Precision 3, Improved PW: Shield 3, Martyrdom 2, Mental Agility 3, Inner Focus 1, Meditation 3, Improved Inner Fire 3, Mental Strength 5, Soul Warding 1, Improved Mana Burn 2, Penance 1, Renewed Hope 5, Divine Aegis 3, Power Infusion 1.

**Holy** : Twilight Focus 3, Improved Renew 3, Holy Specialization 5, Spell Warding 5, Divine Fury 5, Holy Nova 1, Blessed Recovery 3, Inspiration 3, Holy Reach 2, Improved Healing 3, Searing Light 2, Binding Heal 1, Litany of Light 2, Spirit of Redemption 1, Spiritual Guidance 5, Spiritual Healing 3, Prayer of Mending 1.

**Shadow** : Shadow Focus 5, Blackout 5, Spirit Tap 5, Shadow Affinity 3, Improved SW: Pain 2, Shadow Reach 2, Improved Mind Blast 5, Improved Psychic Scream 2, Mind Flay 1, Improved Mind Flay 2, Improved Fade 2, Vampiric Embrace 1, Shadow Weaving 3, Silence 1, Devouring Contagion 2, Early Demise 2, Darkness 5, Shadowform 1.

---

## Shaman

ForeverDiff: 69 spells · 53 talents. Spellbook: 56.

### Elemental

Call of the Ancestors (30), Call of the Elements (20), **Call of the Spirits New** (40), Chain Lightning, Earth Shock, Earthbind Totem, **Fire Nova** (30 yd spell, no longer a totem), Flame / Frost Shock, **Lava Burst New**, Lightning Bolt, Magma / Searing / Stoneclaw Totem, Purge, Totemic Recall.

IN: CL, shocks, LB, Magma, Searing, Stoneclaw, Purge, Fire Nova (totem ID 1535 — **to recheck**: Forever made it a spell). **GAP**: Lava Burst, Calls, Totemic Recall.

### Enhancement

Astral Recall, Far Sight, resistance totems / Flametongue / Frost / Grace / Grounding / Nature / Sentry / Stoneskin / Strength / Windfury / Windwall, weapons Flametongue / Frostbrand / Rockbiter / Windfury, Ghost Wolf, Lightning Shield, **Rage of the Farseer New**, Stormstrike, **Totemic Projection New**, Water Breathing / Walking.

IN: weapons, Lightning Shield, Stormstrike, Grounding, Grace, Strength, Stoneskin, Windfury Totem. **GAP**: Totemic Projection, Rage of the Farseer (TAL + book). UTIL: Far Sight, Water *, Astral Recall.

### Restoration

Ancestral Spirit, Chain Heal, Cure Disease/Poison, Disease/Poison Cleansing Totem, Healing Stream, Healing Wave, LHW, Mana Spring / Tide, Nature's Swiftness, Reincarnation, **Riptide New**, Tremor, **Water Shield New** (20).

IN: heals, HS, Mana Spring, NS, Tremor. **GAP**: Riptide, Water Shield. UTIL: Ancestral Spirit, Reincarnation.

### Talents (50 · 12 new · 29 changed)

**Elemental** : Convection 5, Concussion 5, Elemental Warding 3, Reverberation 5, Call of Flame 3, Elemental Devastation 3, Elemental Focus 1, Elemental Fury 5, Improved Fire Nova 2, Eye of the Storm 3, Call of Thunder 1, Elemental Reach 2, Lightning Overload 3, Earthbound 1, Elemental Alacrity 3, Lava Burst 1.

**Enhancement** : Earth's Grasp 2, Thundering Strikes 5, Ancestral Knowledge 5, Guardian Totems 2, Mental Dexterity 3, Improved Ghost Wolf 2, Improved Lightning Shield 3, Elemental Weapons 3, Shamanistic Focus 1, Anticipation 3, Toughness 5, Flurry 5, Stormstrike 1, Spirit Weapons 1, Mental Quickness 2, Improved Stormstrike 2, Maelstrom Weapon 5, Rage of the Farseer 1.

**Restoration** : Improved Healing Wave 5, Totemic Focus 5, Mindfulness 3, Natural Grace 3, Tidal Focus 5, Improved Reincarnation 2, Ancestral Healing 3, Healing Focus 3, Water Shield 1, Tidal Mastery 5, Restorative Totems 5, Mana Tide Totem 1, Healing Way 3, Nature's Swiftness 1, Purification 5, Riptide 1.

---

## Mage

ForeverDiff: 73 spells · 41 talents. Spellbook: 58.

### Arcane

Amplify/Dampen Magic, **Arcane Blast** (new ranks), Arcane Brilliance / Explosion / Intellect / Missiles / Power, Blink, Conjure Food/Water/gems, Counterspell, Evocation, Mage Armor, Mana Shield, Polymorph (+ Turtle / Pig), Portals and Teleports (including **Teleport: Dalaran New**), Presence of Mind, Remove Lesser Curse, Slow Fall.

IN: intellect, missiles, explosion, counterspell, blink, evocation, armors, PoM, AP, cleanse curse, partial wards. **GAP**: Arcane Blast. UTIL: conjure, portals, polymorph, Slow Fall.

### Fire

Blast Wave, Combustion, Fire Blast, Fire Ward, Fireball, Flamestrike, **Frostfire Bolt New** (40, 3 s), Pyroblast, Scorch. All IN except **GAP Frostfire Bolt**.

### Frost

Blizzard, Cold Snap, Cone of Cold, Frost Armor / Nova / Ward / bolt, Ice Armor / Barrier / Block, **Ice Lance New**. **GAP**: Ice Lance. Cold Snap **TAL**.

### Talents (54 · 6 new · 31 changed)

**Arcane** : Wand Specialization 2, Arcane Focus 5, Improved Channeling 5, Arcane Subtlety 2, Magic Absorption 2, Arcane Concentration 5, Arcane Resilience 2, Arcane Geometry 2, Arcane Impact 3, Arcane Blast 1, Arcane Shielding 2, Improved Counterspell 2, Arcane Meditation 3, Missile Barrage 1, Presence of Mind 1, Arcane Mind 5, Arcane Instability 3, Arcane Power 1.

**Fire** : Wake of Fire 2, Incineration 3, Improved Fireball 5, Ignite 5, Flame Throwing 2, Impact 3, Burning Soul 3, Improved Flamestrike 3, Pyroblast 1, Improved Scorch 3, Improved Fire Ward 2, Hot Streak 1, Master of Elements 3, Critical Mass 3, Blast Wave 1, Fire Power 5, Combustion 1.

**Frost** : Frost Warding 2, Improved Frostbolt 5, Elemental Precision 5, Ice Shards 5, Permafrost 3, Improved Frost Nova 2, Frostbite 3, Piercing Ice 3, Frost Channeling 3, Ice Lance 1, Improved Blizzard 3, Arctic Reach 2, Ice Block 1, Shatter 3, Improved Cone of Cold 3, Cold Snap 1, Fingers of Frost 2, Winter's Chill 5, Ice Barrier 1.

---

## Warlock

ForeverDiff: 64 spells · 67 talents. Spellbook: 69 (including demons).

### Affliction

Amplify Curse, **Bane of Agony** (formerly Curse of Agony — IN under `CurseofAgony`, **rename / alias**), Bane of Doom, Corruption, Curse of Exhaustion / Recklessness / Elements / Tongues / Weakness, Death Coil, Drain Life / Mana / Soul, Fear, Howl of Terror, Life Tap, Siphon Life, **Wrack New**.

**GAP**: Wrack. Curse of Shadow is still in `ns.Spell` — check whether it still exists next to the Banes.

### Demonology

Banish, Create Fire/Health/Soul/Spellstone, Demon Armor/Skin, Demonic Sacrifice, Detect Invisibility, Eye of Kilrogg, Fel Domination, Health Funnel, Inferno, Ritual of Doom / Summoning, Sense Demons, Shadow Ward, Soul Link, **Subjugate Demon** (formerly Enslave), Summon Felhunter / Imp / **Incubus New** / Succubus / Voidwalker, Unending Breath.

IN: armors, classic summons, stones, partial Fear tools. **GAP**: Incubus. UTIL: rituals, Eye, Sense, Inferno, Subjugate.

### Destruction

**Bane of Havoc New**, Conflagrate, Hellfire, Immolate, **Incinerate New**, Rain of Fire, Searing Pain, Shadow Bolt, Shadowburn, Soul Fire.

**GAP**: Incinerate, Bane of Havoc.

### Demons (16)

Blood Pact, Consume Shadows, Devour Magic, Fire Shield/bolt, Lash of Pain, etc., Spell Lock. Outside the player queue (except pet logic later).

### Talents (52 · 19 new · 28 changed)

**Affliction** : Improved Life Tap 2, Suppression 5, Improved Corruption 5, Malediction 5, Soul Harvesting 2, Improved Drains 3, Improved Bane of Agony 2, Fel Concentration 3, Amplify Curse 1, Pandemic 3, Malevolence 5, Nightfall 2, Curse of Exhaustion 1, Siphon Life 1, Soul Siphon 3, Shadow Mastery 5, Wrack 1.

**Demonology** : Improved Health Funnel 2, Improved Imp 3, Demonic Embrace 5, Unholy Power 5, Demonic Aegis 2, Improved Voidwalker 3, Fel Vitality 3, Demonic Energies 2, Improved Sayaad 3, Demonic Sacrifice 1, Master Summoner 2, Decimation 2, Fel Domination 1, Demonic Brand 3, Improved Felhunter 3, Soul Link 1, Demonic Knowledge 3, Master Demonologist 5, Demonic Pact 1.

**Destruction** : Destructive Reach 2, Improved Shadow Bolt 5, Bane 5, Molten Skin 5, Cataclysm 3, Aftermath 5, Ruin 5, Shadowburn 1, Intensity 3, Agonizing Flames 3, Conflagrate 1, Pyroclasm 2, Bane of Havoc 1, Fire and Brimstone 3, Shadow and Flame 5, Incinerate 1.

---

## Druid

ForeverDiff: 72 spells · 59 talents. Spellbook: 60.

### Balance

Barkskin, Entangling Roots, Faerie Fire, Hibernate, Hurricane, Insect Swarm, Moonfire, Moonkin, Nature's Grasp (trainable), Omen of Clarity (trainable), Soothe Animal, Starfire, Teleport: Moonglade, Thorns, Wrath.

IN: Barkskin, FF, Hurricane, IS, Moonfire, Moonkin, Starfire, Thorns, Wrath. UTIL: Roots, Hibernate, Soothe, Moonglade. Omen / Grasp: **IN Grasp**, Omen **GAP** (proc, not a queue button).

### Feral

Aquatic / Bear / Cat / Dire Bear / Travel, Bash, **Berserk New** (40), Challenging Roar, Claw, Cower, Dash, Demo Roar, Enrage, Feline Grace, Feral Charge, Ferocious Bite, Frenzied Regen, Growl, **Lacerate New** (42/50/58), **Mangle New** (Forever also renamed a talent *Primal Bite* according to the build notes), Maul, Pounce, Prowl, Rake, Ravage, Rip, Shred, Swipe, Tiger's Fury, Track Humanoids.

IN: forms, Bash, Claw, Demo, Enrage, Charge, Bite, Frenzied, Growl, Maul, Prowl, Rake, Ravage, Rip, Shred, Swipe, Tiger. **GAP**: Lacerate, Mangle/Primal Bite, Berserk. UTIL: Aquatic, Travel, Dash, Cower, Pounce, Track.

### Restoration

Abolish/Cure Poison, Gift / Mark of the Wild, Healing Touch, Innervate, Nature's Swiftness, Rebirth, Regrowth, Rejuvenation, Remove Curse, **Revive New**, Swiftmend, Tranquility, **Wild Growth New**.

IN: heals, MotW, Innervate, NS, Swiftmend, Tranquility, Remove Curse. **GAP**: Wild Growth, Revive (out of combat). UTIL: Rebirth vs Revive.

### Talents (51 · 14 new · 32 changed)

**Balance** : Improved Wrath 5, Genesis 5, Moonglow 3, Improved Moonfire 2, Nature's Majesty 2, Nature's Reach 2, Improved Entangling Roots 3, Nature's Splendor 1, Insect Swarm 1, Vengeance 5, Improved Starfire 5, Overgrowth 2, Nature's Grace 1, Eclipse 3, Moonfury 5, Moonkin Form 1.

**Feral** : Ferocity 5, Heart of the Wild 5, Feral Swiftness 2, Feral Instinct 3, Brutal Impact 3, Thick Hide 3, Savage Fury 2, Feral Charge 1, Sharpened Claws 2, Shredding Attacks 3, Mangle 1, Predatory Strikes 3, Primal Fury 2, Predatory Instincts 2, Leader of the Pack 1, King of the Jungle 3, Natural Reaction 5, Rend and Tear 5, Berserk 1.

**Restoration** : Nature's Focus 5, Furor 5, Naturalist 5, Subtlety 3, Natural Shapeshifter 3, Reflection 3, Gift of Nature 5, Gift of the Earthmother 1, Tranquil Spirit 5, Improved Rejuvenation 3, Swiftmend 1, Nature's Swiftness 1, Living Spirit 3, Improved Tranquility 2, Improved Regrowth 5, Wild Growth 1.

---

## Racials (10 races × 4 = 40)

Source : [wowforevertalent.com/racials](https://wowforevertalent.com/racials/) (export 17 Sept 2026). 26/40 have a Classic counterpart. They **cost no** talent points.

`ns.RACIALS` only keeps the **useful actives** (added to the lists, `on = false` except Blood Fury / Berserking). Passives are not HUD buttons.

Addon race IDs: Human 1, Orc 2, Dwarf 3, Night Elf 4, Undead 5, Tauren 6, Gnome 7, Troll 8, Aeolid Order (Alliance) 95, Aeolid Windshaper (Horde) 96.

### Alliance

| Race | Preview classes | Active / passive | Forever | Addon |
| --- | --- | --- | --- | --- |
| Human | War Hunt Mage Rog Pal Priest Lock | **Will to Survive** · instant · 3 min · breaks stuns | **New** | **GAP** |
| | | **Perception** · instant · 3 min · stealth detection 20 s | Changed (still there) | **IN** `20600` |
| | | Sword Specialization · +2% crit (sword) | Passive (Era = skill +5) | UTIL |
| | | The Human Spirit · +5% Spirit | Passive | UTIL |
| Dwarf | War Hunt Rog Pal Priest **Shaman** | **Stoneform** · 3 min · bleed/poison/disease + −10% phys 8 s | Changed (no more +armor) | **IN** `20594` |
| | | Find Treasure · minimap | | UTIL |
| | | Mace Specialization · +1% crit (mace) | Passive | UTIL |
| | | Big Game Hunter · +5% vs Beasts | Passive (Era = gun crit) | UTIL |
| Night Elf | War Hunt Rog Priest Dru | **Elune's Light** · 3 min · +10% crit 15 s | **New** | **GAP** |
| | | **Shadowmeld** · 10 s ; in combat 2 min CD | Changed (Era out of combat) | **IN** `20580` |
| | | Quickness · +1% dodge, +2% speed, stealth +1 | Passive | UTIL |
| | | Wisp Spirit · +75% speed when dead | Passive (Era 50%) | UTIL |
| Gnome | War Mage Rog Priest Lock | **Escape Artist** · 2 min · + immunity 3 s | Changed | **IN** `20589` |
| | | **Eureka!** · 2 min · 3 spells: −cost / +10% dmg (heal −15% mana +10%) | **New** | **GAP** |
| | | Expansive Mind · +5% mana/rage/energy | Passive (Era +5% int) | UTIL |
| | | Engineering Specialization · −20% engineering fail | Passive | UTIL |
| Aeolid Order (95) | War Hunt Mage Rog Dru | **Walk on Air** · 2 min · glide 10 s | New | **excluded** (`1259416`) |
| | | **Read Ley Line** · 2 s / 2 min · health+mana regen | | **IN** `LeyLine` `1259705` |
| | | Elemental Insight · +5% vs elementals | Passive | UTIL |
| | | Wind Blessed · +1% haste | Passive | UTIL |

### Horde

| Race | Preview classes | Active / passive | Forever | Addon |
| --- | --- | --- | --- | --- |
| Orc | War Hunt Mage Rog Lock Sham | **Blood Fury** · 2 min · +10% AP and SP 15 s | Changed (Era +25% AP, −heal) | **IN** `20572` `on=true` |
| | | **Shatter Curse** · 3 min · curse+bane + −15% magic 8 s | **New** | **GAP** |
| | | Axe Specialization · +1% crit (axe) | Passive | UTIL |
| | | Hardiness · −20% stun duration | Passive | UTIL |
| Undead | War Mage Rog Priest Lock **Pal** | **Will of the Forsaken** · 2 min · charm/fear/sleep | Changed (no more immunity) | **IN** `7744` |
| | | **Cannibalize** · 2 min · 7% health **and mana** / 2 s × 10 s | Changed (Era health only) | **GAP** |
| | | Underwater Breathing | Passive | UTIL |
| | | Touch of the Grave · life drain proc | **New** passive | UTIL |
| Tauren | War Hunt Dru Sham | **War Stomp** · 0,5 s / 2 min · 8 yd stun | | **IN** `20549` |
| | | Cultivation · 1 h · doubled herbs | Changed (Era +15 herbalism) | UTIL |
| | | Plainsrunning · speed up to +30% | **New** passive | UTIL |
| | | Endurance · +5% health, +1% hit | Passive | UTIL |
| Troll | War Hunt Mage Rog Priest Lock Sham | **Berserking** · 3 min · +10% haste 10 s | Changed (Era 10–30% depending on health) | **IN** `20554` `on=true` |
| | | **Rapid Regeneration** · 3 min · 50% health / 6 s (channel) | **New** | **GAP** |
| | | Beast Slaying · +5% vs Beasts | Passive | UTIL |
| | | Regeneration · +10% regen, 10% in combat | Passive | UTIL |
| Aeolid Windshaper (96) | War Hunt Rog Dru Sham | **Walk on Air** | New | **excluded** |
| | | **Skysight** · 0,5 s / 2 min · +10% speed 30 s (15 min near a convergence) | | **IN** `SkyView` `1259686` |
| | | Elemental Insight / Wind Blessed | Passives | UTIL |

### Priest racials (on top of the 40)

Always **tied to race**, not talents. Fear Ward and Devouring Plague are **baseline for all priests** (no longer racials).

| Race | Spells | Addon |
| --- | --- | --- |
| Human | Divine Grace (new, heal <50%, 10 min), Feedback | **GAP** / Feedback is in the priest spellbook |
| Dwarf | Chastise (new), Desperate Prayer | **GAP** / Desperate Prayer |
| Night Elf | Elune's Grace (changed), Starshards (30 s CD) | **GAP** (listed as priest spells) |
| Gnome | Confounding Flash, Contingency Plan | **GAP** |
| Undead | Dark Sacrifice (new), Touch of Weakness | **GAP** |
| Troll | Hex of Weakness, Shadowguard | **GAP** |

Preview classes that **changed** vs Era: dwarf shaman, undead paladin, aeolid druid, orc mage, gnome priest.

### To put in `ns.RACIALS` (combat / defense)

| Priority | Spell | Race | Why |
| --- | --- | --- | --- |
| 1 | Will to Survive | Human | Breaks stun — defense |
| 1 | Elune's Light | Night Elf | 15 s crit burst |
| 1 | Eureka! | Gnome | Burst dmg/heal |
| 1 | Shatter Curse | Orc | Cleanse curse/bane |
| 2 | Rapid Regeneration | Troll | Channel heal |
| 2 | Cannibalize | Undead | Regen out of melee |
| — | Walk on Air | Aeolids | Stay excluded (no combat queue) |
| — | Find Treasure, Cultivation | Dwarf / Tauren | Outside the rotation |

---

## What not to put in the queue

- Portals, teleports, conjurations, out-of-combat resurrection, tracking, lore, feed pet, pick lock/pocket.
- Tree passives (Improved X): they change `opt` / CD, not a button.
- Set / relic spells (paladin 13xxxxx IDs): not APL steps.
- Combat log for procs: always forbidden.

## Next implementation (when coding)

1. Lab IDs of the **GAPs** (Wowhead Forever spell, `/dump` in game, or wowforeverbuilds).
2. `ns.Spell` + `HEAL_SPELL_IDS` / `MAINTENANCE_BUFF_IDS` / `COOLDOWNS` as needed.
3. `step` in `Lists.lua` (single / AoE / burst / def).
4. Bump `listVersion` only if saved lists must be replaced.
5. Test `Resolve` by name: Holy Strike, Victory Rush, Lava Burst, etc.

Sources to re-read if the client moves to **1.60.1.70009+**: Slam / Thunder Clap / Holy Strike already changed between snapshots.
