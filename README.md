# Gnomish Pachinko

A peg-shooting puzzle game for World of Warcraft (WoW Forever). No gambling, no gold, no credits: 1000 generated levels of pegs and bricks to clear, one chapter of ten levels for every place in Azeroth and Outland.

Open it with `/pachinko` (or `/gp`).

## How it plays

Point the launcher with the mouse and click the field to shoot. You have ten balls a level. Every peg or brick the ball touches lights up and vanishes when the ball is gone. Light all the orange pegs to clear the level and unlock the next one.

- **Blue** pegs and bricks are points.
- **Orange** pegs are the goal: 15 of them on level 1, 30 by level 1000.
- **Purple** is one bonus peg worth 500. It hops to a new spot every shot.
- **Green** pegs fire the chapter's power: Multiball, Super Guide, Space Blast, Fireball, or Spooky Ball.
- The **bucket** sliding along the bottom gives a ball back. So do 25,000, 75,000 and 125,000 points.
- Hit the last orange peg and **Fever** begins: time slows and the ball drops into one of five bins worth 10,000 to 100,000 points, plus 10,000 for every spare ball.

Twelve layout families (Brickwork, Rainbow, Diamonds, Rings, Zigzag, Brick Arcs, Brick Walls, Spiral, Waves, Hourglass, Honeycomb, Pillars) are built from the level number, so level 437 is the same level 437 for everyone.

## Commands

- `/pachinko` opens or closes the game.
- `/pachinko levels` opens the level select.
- `/pachinko 25` plays level 25, if it is unlocked.
- `/pachinko sound` toggles the sound effects.
- `/pachinko reset` wipes your progress.

## Development

Pure Lua, no build step. `tests/engine_test.py` (needs `pip install lupa`) builds all 1000 levels, plays scripted ones through the engine, and drives the window headless. `tools/make_textures.py` (needs Pillow) regenerates the textures.
