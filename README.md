# Gnomish Pachinko

A peg-shooting puzzle game for World of Warcraft (WoW Forever). No gold is ever won: 1000 generated levels of pegs, bricks, eggs, gems and bosses to clear, one chapter of ten levels for every place in Azeroth and Outland.

Open it with `/pachinko` (or `/gp`).

## How it plays

The board is a portrait column, 490 by 700, with the pegs in its upper two thirds and a long fall to the bucket.

Point the launcher with the mouse and click the field to shoot. You have ten balls a level. Every peg or brick the ball touches lights up and vanishes two seconds later. Finish the level's objective to clear it and unlock the next one.

- **Blue** pegs and bricks are points.
- **Orange** pegs are the goal of a classic level: 15 of them on level 1, 30 by level 1000.
- **Purple** is one bonus peg worth 1,000. It hops to a new spot every shot.
- **Green** pegs fire the chapter's power.
- **Steel-rimmed** pieces are tough: they crack on the first hit and light on the second. **Gold-rimmed** ones take three. They start in chapter 4, and from chapter 7 orange pegs can be tough too.
- The **bucket** sliding along the bottom gives a ball back. So do 25,000, 75,000 and 125,000 points.
- Finish the goal and **Fever** begins: the ball drops into one of the five G-N-O-M-E buckets (1,000 / 10,000 / 25,000 / 10,000 / 1,000), then every ball you had left is fired at them too. Light all five and the GNOME bonus pays 100,000 and every bucket is worth 25,000.
- **Style points**: a Long Shot (two goal pieces far apart in one shot) or a Super Slide (riding along six bricks) pays 5,000. A shot that touches nothing is a Total Miss.
- **Keys**: a gold cage of bars round some orange pegs falls away when you light its loose key.

### Objectives

Every level is one of four kinds, marked by a coloured dot on the level select:

- **Classic**: light every orange peg.
- **Eggs** (levels ending 5 from chapter 2, and 7 from chapter 4): hatch every egg, two hits each. Eggs sit in nests: clear the pegs under one and it falls. Catch it in the bucket and it hatches with a bonus; let it fall off the board and the level is lost.
- **Long Shots** (levels ending 6 from chapter 7): make two or three Long Shots, two orange pegs far apart in one shot.
- **Gems** (levels ending 3 and 8 from chapter 3): knock every gem loose and drop it off the bottom; one in the bucket is a Bucket Drop bonus.
- **Boss** (every tenth level in odd chapters): a big mechanical boss slides back and forth along the bottom, under the pegs, so the ball has to come down through the pattern or thread a gap to reach it. Hit it until its health is gone.
- **Duel** (every tenth level in even chapters): clear the board, then Cogwhistle Overspark, Tinkmaster's older brother, challenges you on a fresh shared board: a coin flip, five balls each, turn and turn about, highest score wins. A shot that lights no orange costs a quarter of your duel score.
- **No bucket** on some levels from chapter 5 (ending 4 and 9, never a gem level): the only free balls are the score marks. Five bosses take turns, each with a trick: the Tin Drake speeds up as it weakens, the Bolt Golem raises a two-hit shield every third shot, the Gyro Spider jumps when hit, the Mechano-Boar charges and turns around when hit, the Cog Yeti heals after any shot that misses it.

### Powers, power-ups and boosts

Powers unlock one per chapter and the level card lets you pick any you have: Multiball, Super Guide (the full bounce path for three shots), Space Blast (a huge explosion that hits everything near the green peg), Fireball, Spooky Ball, Pyramid (a ramp across the bottom that bounces the ball back up, for three shots), Chain Lightning (a bolt that leaps from the green peg through six more pieces) and Free Ball Frenzy (three extra balls and 5,000 points).

Two power-ups can be armed for a shot from the slots at the field's bottom-left: Ring of Fire (the first hit also hits everything in a small ring) and Rainbow Ball (a wide ring). The level card offers one boost, Extra Green Peg. They are earned, never bought: a Ring of Fire for every clear, an Extra Green Peg for three stars, two Rainbow Balls for a boss or a duel won.

With the mouse over the field, Left and Right nudge the aim by 1.2 degrees and Space pauses.

### Stars

Every cleared level earns one to three stars by score. The marks come from the level itself: what its pieces are worth, one Fever bin, and the bins of the spare balls a good player keeps, with fewer spare balls asked of harder levels. They are shown on the side panel and in the level select tooltip, and the level select keeps your stars and your total.

### Plays

Losing a level (running out of balls) spends one of the day's plays, and out of balls on an ordinary level you can Play On with three more balls for a play. You get five free plays in any rolling 24 hours; clearing a level never costs one. When they are gone the game shows how long until the next free play comes back, and five more plays for the day can be bought for 10g: mail the gold to Chairface Chippendale with "pachinko plays purchase" as the subject, or press **Buy plays** at a mailbox and the mail fills itself in. The count is kept in an encrypted record mirrored to several places outside the addon folder, so reinstalling the addon does not reset it, and an edited copy locks the day.

## Tinkmaster Overspark

Tinkmaster Overspark, the gnome engineer of Tinker Town, hosts the game: his voice is the announcer and his 3D model stands in the field's top corner, acting out the match with the game's own animations. `/pachinko mascot` hides or shows him; `mascot target` swaps in any creature you target; `mascot scale`, `face`, `z` and `play <animation>` tune him.

## Layouts and gimmicks

Chapter 1 is nine starter pictures that teach the game: level 1 is nine pegs and three oranges, bricks first appear on level 7, and level 10 is the first boss. From level 11 the real patterns begin, sparse at first and filling in until level 80.

Fifteen layout families (Brickwork, Rainbow, Diamonds, Rings, Zigzag, Brick Arcs, Brick Walls, Spiral, Waves, Hourglass, Honeycomb, Pillars, Chevrons, Castle, Star), each a drawn pattern with a few variants and no random filler, are built from the level number, so level 437 is the same level 437 for everyone. From chapter 3 the gimmicks arrive one per chapter, each debuting on the first level of its chapter: a sliding row of bricks, rising and falling peg lifts, solid gray blocks that only bounce, a turning wheel, pink bumpers that throw the ball back harder, a swinging pendulum bar, twin wheels, a bumper gate and a sliding block. Later levels draw from the whole pool, and from level 300 sometimes twice.

## Commands

- `/pachinko` opens or closes the game.
- `/pachinko levels` opens the level select.
- `/pachinko 25` plays level 25, if it is unlocked.
- `/pachinko plays` says how many plays are left today.
- `/pachinko buy` (or `buy 2`) fills out the purchase mail at a mailbox.
- `/pachinko sound` toggles the sound effects, `/pachinko voice` the announcer.
- `/pachinko minimap` shows or hides the minimap button (left-click plays, right-click opens the level select, drag to move).
- `/pachinko reset` wipes your level progress (not the day's plays); the level map has a Reset progress button that does the same after a confirming second click.

## Art and audio

`ASSETS.md` lists every texture, sound effect and announcer line the game wants, with sizes, formats and ElevenLabs prompts. Everything ships as a generated placeholder or a silent hook until the real file is dropped in under the same name.

## Development

Pure Lua, no build step. `tests/engine_test.py` (needs `pip install lupa`) builds all 1000 levels, plays scripted ones through the engine, checks the plays vault, and drives the window headless. `tools/make_textures.py` (needs Pillow) regenerates the textures, including the placeholder art for eggs, gems, bosses, cracks, rims, stars, the pyramid and the blast; `tools/make_notes.py` (needs numpy and soundfile) synthesizes the combo notes and the placeholder effects.
