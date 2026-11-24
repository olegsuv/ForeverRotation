## 0.9.5

- The "blocked from an action" popup is caught at the popup too (the event did not reach the addon); `/frot blocked` keeps the call stack.

## 0.9.3

- Creature types are remembered for the whole account, also from mouseover and from what the aggro log has already seen, so Serpent Sting stays off mechanicals you have met before.

## 0.9.2

- When the game refuses the addon an action ("blocked from an action only available to the Blizzard UI"), the chat says which call it was and `/frot blocked` shows where it came from, so it can be fixed.

## 0.9.1

- Fixed: "ForeverRotation has been blocked from an action only available to the Blizzard UI" after a boss in a dungeon. Forever doesn't let addons post to the chat, so the top-damage line is no longer sent by the addon: a small panel offers it and one click on its button posts it.

## 0.9.0

- Second square, right of the first, with an orange frame: a long cooldown that is due (Rapid Fire, Bestial Wrath, Death Wish, Arcane Power... anything with a base cooldown of 90 s or more). The first square keeps the next spell, so a cooldown never hides what to cast. Its button glows too.
- Immunities are learned: when a spell of yours is "immune" on a mob kind, it is not suggested on that kind again (per character). `/frot immune` lists them, `/frot immune clear` forgets them.
- The creature type is remembered per mob kind, so Serpent Sting is no longer suggested on mechanicals in combat (the game hides the type there).
- The mana potion comes after the spells: it is suggested when there is nothing left to cast. The healing potion still comes first.

## 0.8.0

- A line in the party chat when you are the group's top damage in a dungeon (like Questie's quest announcements): once per run, right after a boss dies, with at least three people dealing damage. Pets count for their owner. Settings: "Tell the party when you top the damage".

## 0.7.4

- Hunter: Auto Shot no longer flashes on the square between two shots. The game reports it as running only part of the time, so a sighting now counts for one full shot (a new target starts over).
- The range line under the square ("Shoot", "Too far"...) is shown only while the square shows something; no caption on its own.

## 0.7.3

- Fixed: a potion that isn't on an action bar showed the game's logo on the square. It now shows the potion's own icon.

## 0.7.2

- Long cooldowns (Rapid Fire, Bestial Wrath, Death Wish, Combustion, Arcane Power, Icy Veins, Adrenaline Rush, Cold Blood, Inner Focus) are suggested only for a boss, or an elite / player that will take a while. Dungeon trash is elite too, so "elite" alone no longer counts; Rapid Fire is no longer suggested on packs of normal mobs.

## 0.7.1

- Hunter: Auto Shot is suggested only while it isn't running; once it shoots, the square stays empty until there is something to cast.

## 0.7.0

- Time to die: DoTs, curses, marks, stings and long cooldowns are suggested only when the mob will live long enough for them. The game hides enemy health in combat, so the addon learns how long your kills take (one average each for normal / elite mobs solo, in a group and in dungeons, plus bosses, adjusted by the level gap) and counts down from the pull; when health can be read, it follows the health trend instead. Finishers (Shadow Word: Death, Shadowburn, Drain Soul, Ferocious Bite, Eviscerate) come in when the mob is about to die.
- Packs: mobs tagged by another group, or fighting the next party while you're not on their threat list, no longer count, so Multi-Shot / Volley / Blizzard and co. aren't suggested for someone else's pull. Hunter: Multi-Shot as a filler only on your own pack.
- Forever spells added: Mutilate (Rogue), Penance and Inner Focus (Priest), Holy Shock and Holy Shield (Paladin), Primal Bite, Lacerate and Innervate (Druid), Fire Nova and Strength of Earth Totem (Shaman), Blast Wave (Mage).
- Druid cat: a Clearcasting Shred goes before Ferocious Bite. Warrior: Hamstring dumps rage about to cap while the big strikes are on cooldown.
- Moving: a big arrow takes the spell's place on the square whenever you have to step closer (green, up: too far, or out of ammo and not in melee) or back (red, down: the hunter's dead zone); Charge, Intercept, Feral Charge, Shadowstep and Disengage still show as the spell. It doesn't bounce and waits a moment before changing, so it no longer twitches at the edge of a range. The small arrow over the square is gone.
- The square shows the icon of the action button holding the spell: a potion's own icon, Auto Shot's weapon icon. Hunter with nothing to cast in range: Auto Shot (it doesn't glow while it's already shooting).
- A potion on the square says "Use" under it instead of the range zone.
- Mana potions only when the fight goes on for another 10 s or so, not for a mob about to die.
- No live hostile target: nothing on the square and no glowing buttons (the free square shows the addon icon only while unlocked).
- Fixed: interrupts (Pummel, Kick, Counterspell, Earth Shock...) were suggested on casts that can't be interrupted; the flag never reached the addon.
- What this character cast, which aspect is up and the learned kill times are now saved per character (an alt no longer starts with your main's data). Needs a game restart once, not just /reload.
- Hunter: potions through the shared check like every class; when the game hides your mana, a basic shot's "not enough mana" stands in.
- Less work per frame: the range zone is computed once per frame for all its readers, the enemy count once per tick, the action bars are no longer re-read on every buff change.
- `/frot spells` saves your spellbook (names and ids) for bug reports and translations.
- The trace log (`/frot trace`) shows the time-to-die estimate and the target's health (or ? when hidden).

## 0.6.0

- Warlock: curses. On elites, rares and players: Curse of the Elements (else Curse of Weakness while it hits you) once per target, and Bane of Doom instead of Bane of Agony on a tough mob near full health. Only one Bane and one Curse of yours at a time.
- Hunter out of ammo (or without a ranged weapon): Aspect of the Monkey instead of the Hawk, melee priority (Mongoose Bite, Raptor Strike, traps, Counterattack), no Hunter's Mark; the range zone shows Too far until you're in melee.
- Arrow over the square (on by default): down = step back (too close to shoot), up = step closer (out of reach). Settings: "Arrow over it".
- Nameplate range icon: now to the right of the target's nameplate (past the level, clear of the elite icon and raid marks), styled like the level box, with the distance in yards beside it ("20-28 yd") and the zone word above in the plate's own font.
- Zone words in sentence case ("Melee", "Too close", "In range", "Too far"), also under the square.

## 0.5.1

- Warrior (and every class with a timed self-buff): a buff you just cast counts as on even when the game reports no such aura (the square no longer sticks on Battle Shout). The aura is also looked up by spell id.
- Aggro data log (on by default, can be switched off in settings): when a hostile mob aggroes on you by itself, it saves your level, the mob's level, elite or not and the distance just before. Mobs you or your pet pulled are left out. `/frot aggro` shows a summary. This data will drive an aggro-range indicator.
- Long option labels wrap inside the settings window.

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
