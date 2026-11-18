## 0.5.0

- Warrior: Heroic Strike with any spare rage until you learn Mortal Strike / Bloodthirst / Shield Slam (was 60 rage, so the square stayed empty most of the fight).
- Warrior: tank priority in Defensive Stance (or with a shield in a group): Taunt / Mocking Blow, Revenge, Shield Slam, Shield Block, Thunder Clap / Demoralizing Shout, Sunder Armor, Heroic Strike / Cleave.
- Warrior: short of rage, the square shows the next strike to wait for, tinted blue (any class: the square turns blue while you lack the resource).
- Warrior: next to the mob before the fight, the opener is suggested instead of nothing.
- The range zone (MELEE / TOO FAR) is no longer shown for pure melee classes (Warrior, Rogue, Paladin).
- Settings window: "More Forever addons" with a link to each Forever addon you don't have yet (nothing shown when you have them all).

## 0.4.1

- The settings window and the minimap button tooltip show the loaded version.

## 0.4.0

Next-spell suggestions for all classes, built from the Forever leveling and spec guides
(Maxroll, Mobalytics, Wowhead, Icy Veins). Only the Hunter has been played with the addon so far:
please report anything odd on CurseForge or GitHub (`/frot trace` keeps a log for bug reports).
- Warrior: Battle Shout, Charge / Intercept, Victory Rush, Execute / Overpower / Revenge when they light up, Mortal Strike / Bloodthirst / Shield Slam, Rend, Whirlwind, Thunder Clap, Sunder and Demoralizing Shout on elites, Heroic Strike / Cleave with spare rage, Pummel / Shield Bash on casts.
- Rogue (Combat): stealth openers, Slice and Dice, Shank, Sinister Strike to 5 combo points, Eviscerate, Adrenaline Rush / Blade Flurry / Cold Blood, Riposte, Kick, Evasion.
- Mage: Frost / Fire / Arcane by your talents; armor and Arcane Intellect, Frost Nova when a mob reaches you, Ice Lance on frozen targets, Pyroblast and Missiles procs, Counterspell, Evocation, wand when dry.
- Warlock: Banes and DoTs on mobs that live, Immolate / Conflagrate / Shadowburn, Wrack, Shadow Bolt on Shadow Trance, Life Tap, Drain Life when low, Drain Soul for shards, Demon Skin / Armor.
- Priest: Inner Fire / Fortitude, Shield before the mob reaches you, Shadow Word: Pain, Mind Blast, Devouring Plague, Vampiric Embrace, Shadow Word: Death, Mind Flay / Holy Fire / Smite, self-heals.
- Paladin (Retribution): aura and Blessing of Might, Crusader -> Judgement on elites, damage seal, Judgement on cooldown, Holy / Crusader Strike, Hammer of Wrath, Exorcism on Undead and Demons, Consecration, Hammer of Justice on casts, emergency heals.
- Shaman: weapon imbue and Lightning Shield, Lightning Bolt pull, Stormstrike / Rage of the Farseer, Maelstrom Lightning Bolt, totems, Flame / Earth Shock, Lava Burst, Chain Lightning, interrupts, self-heals.
- Druid: cat (Faerie Fire, Rake, Claw, Rip, Ferocious Bite, Shifting Power), bear (Maul, Swipe, Roar, Enrage) and caster / Moonkin (Moonfire, Insect Swarm, Starfire, Wrath), Mark of the Wild / Thorns, self-heals.
- Shared: proc glows on your bars push the spell up, interrupts when the target casts, self-buffs remembered while the game hides your auras in combat, combo points counted when hidden.
- Settings: "Self-heal spell below" slider.

## 0.3.0

Hunter priority rebuilt from the Forever leveling and spec guides:
- Aimed Shot before Arcane Shot (hardest hit, baseline at 20); Multi-Shot instead of it on 2+ enemies; Volley on 3+.
- Summon Hawk until 2 hawks are out on mobs that live, Arcane Shot otherwise (they share a cooldown).
- Bestial Wrath, Intimidation and Rapid Fire on elites and players.
- Survival melee weaving: Aspect of the Beast, Mongoose Bite, Raptor Strike, Strider Kick, Lacerate, traps (they work in combat in Forever).
- Ranged specs in melee: Disengage to the pet, trap, Raptor Strike, Wing Clip.

## 0.2.7

- Hunter in melee: Mongoose Bite, Disengage when the mob is on you and your pet is up, Immolation/Explosive Trap, Raptor Strike, then Wing Clip to step back.
- Hunter at range: Concussive Shot when the mob runs at you.

## 0.2.6

- Fixed: Aspect of the Hawk was suggested while active (player auras are hidden in combat; the last known aspect is now remembered, also across /reload).
- The range zone text under the square is off by default; the icon by the nameplate shows it.

## 0.2.5

- Hunter: range zone icon next to the target nameplate (melee / too close / shoot / too far).
- Fixed: Raptor Strike was suggested on far targets (its range check always says yes in Forever); melee is now detected with Wing Clip / Mongoose Bite.
- Mana potion is suggested when you no longer have mana for a shot (the game hides mana numbers in combat).

## 0.2.4

- Hunter: range zone under the square - MELEE, DEAD ZONE (too close to shoot), SHOOT or TOO FAR.

## 0.2.3

- Fixed: the Aspect of the Hawk reminder stayed on while the aspect was active.

## 0.2.2

- Fixed: a melee spell was suggested when the target was far away.
- Shots are only suggested when the target is in range.
- Short decision log in saved variables for bug reports (`/frot trace` to turn it off).

## 0.2.1

- Hunter: reminds to switch to Aspect of the Hawk when shooting in Cheetah/Pack/Beast or with no aspect.

## 0.2.0

- Settings window (`/frot`, minimap button, addons menu).
- Next-spell square between the player and target frames (or free position), with key bind and damage.
- Numbers moved to the bottom-left corner of buttons (key binds stay readable).
- Addon icon.

## 0.1.0

- First version: Hunter next-spell suggestion, damage-per-second numbers on buttons and tooltips.
