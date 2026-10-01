# Gnomish Pachinko

A peg-shooting puzzle game for World of Warcraft (WoW Forever). No gold is ever won: 1000 generated levels of pegs, bricks, eggs, gems and bosses to clear, one chapter of ten levels for every place in Azeroth and Outland.

Open it with `/pachinko` (or `/gp`).

## How it plays

Point the launcher with the mouse and click the field to shoot. You have ten balls a level. Every peg or brick the ball touches lights up and vanishes two seconds later. Finish the level's objective to clear it and unlock the next one.

- **Blue** pegs and bricks are points.
- **Orange** pegs are the goal of a classic level: 15 of them on level 1, 30 by level 1000.
- **Purple** is one bonus peg worth 1,000. It hops to a new spot every shot.
- **Green** pegs fire the chapter's power.
- **Steel-rimmed** pieces are tough: they crack on the first hit and light on the second. **Gold-rimmed** ones take three. They start in chapter 4, and from chapter 7 orange pegs can be tough too.
- The **bucket** sliding along the bottom gives a ball back. So do 25,000, 75,000 and 125,000 points.
- Finish the goal and **Fever** begins: time slows and the ball drops into one of five bins worth 10,000 to 100,000 points, then every ball you had left is fired at the bins too.

### Objectives

Every level is one of four kinds, marked by a coloured dot on the level select:

- **Classic**: light every orange peg.
- **Eggs** (levels ending 5 from chapter 2, and 7 from chapter 4): hatch every egg. Eggs take three hits and crack a little more each time.
- **Gems** (levels ending 3 and 8 from chapter 3): knock every gem loose and catch it in the bucket. A gem that misses goes back to its nest for the next shot.
- **Boss** (every tenth level): a big mechanical boss slides along the top. Hit it until its health is gone. Five bosses take turns, each with a trick: the Tin Drake speeds up as it weakens, the Bolt Golem raises a two-hit shield every third shot, the Gyro Spider jumps when hit, the Mechano-Boar charges and turns around when hit, the Cog Yeti heals after any shot that misses it.

### Powers

One per chapter, in turn: Multiball, Super Guide (the full bounce path for three shots), Space Blast (a huge explosion that hits everything near the green peg), Fireball, Spooky Ball, Pyramid (a ramp across the bottom that bounces the ball back up, for three shots) and Chain Lightning (a bolt that leaps from the green peg through six more pieces).

### Stars

Every cleared level earns one to three stars by score; the marks for two and three stars are shown on the side panel and in the level select tooltip. The level select keeps your stars and your total.

### Plays

Losing a level (running out of balls) spends one of the day's plays. You get five free plays in any rolling 24 hours; clearing a level never costs one. When they are gone the game shows how long until the next free play comes back, and five more plays for the day can be bought for 10g: mail the gold to Chairface Chippendale with "pachinko plays purchase" as the subject, or press **Buy plays** at a mailbox and the mail fills itself in. The count is kept in an encrypted record mirrored to several places outside the addon folder, so reinstalling the addon does not reset it, and an edited copy locks the day.

## Layouts and gimmicks

Fifteen layout families (Brickwork, Rainbow, Diamonds, Rings, Zigzag, Brick Arcs, Brick Walls, Spiral, Waves, Hourglass, Honeycomb, Pillars, Chevrons, Castle, Star), each a drawn pattern with a few variants and no random filler, are built from the level number, so level 437 is the same level 437 for everyone. From chapter 3 most levels add a gimmick, and the late game sometimes two: a sliding row of bricks, rising and falling peg lifts, a turning wheel, twin wheels, a swinging pendulum bar, solid gray blocks that only bounce, a sliding block, pink bumpers that throw the ball back harder, and a bumper gate.

## Commands

- `/pachinko` opens or closes the game.
- `/pachinko levels` opens the level select.
- `/pachinko 25` plays level 25, if it is unlocked.
- `/pachinko plays` says how many plays are left today.
- `/pachinko buy` (or `buy 2`) fills out the purchase mail at a mailbox.
- `/pachinko sound` toggles the sound effects.
- `/pachinko reset` wipes your level progress (not the day's plays).

## Development

Pure Lua, no build step. `tests/engine_test.py` (needs `pip install lupa`) builds all 1000 levels, plays scripted ones through the engine, checks the plays vault, and drives the window headless. `tools/make_textures.py` (needs Pillow) regenerates the textures, including the placeholder art for eggs, gems, bosses, cracks, rims, stars, the pyramid and the blast; `tools/make_notes.py` (needs numpy and soundfile) synthesizes the combo notes and the placeholder effects.
