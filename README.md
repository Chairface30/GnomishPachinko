# Gnomish Pachinko

A peg-shooting puzzle game for World of Warcraft (WoW Forever). No gold is ever won: 400 generated levels of pegs, bricks, eggs, gems and bosses to clear, one chapter of ten levels for each of forty places of the original Azeroth.

Open it with `/pachinko` (or `/gp`).

## How it plays

The board is a portrait column, 490 by 700, with the pegs in its upper two thirds and a long fall to the bucket.

Point the launcher with the mouse and click the field to shoot. You have ten balls a level. Every peg or brick the ball touches lights up and vanishes two seconds later. Finish the level's objective to clear it and unlock the next one.

- **Blue** pegs and bricks are points.
- **Orange** pegs are the goal of a classic level: 3 of them on level 1, 30 by level 400.
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
- **Eggs** (levels ending 5 from chapter 2, and 7 from chapter 4): hatch every egg, two hits each. Eggs are big loose bodies resting in a cradle of two bricks: knock a cradle brick out and the egg rolls and falls. Catch it in the bucket and it hatches with a bonus; let it fall off the board and the level is lost. Preserve the bricks.
- **Long Shots** (levels ending 6 from chapter 7): make two or three Long Shots, two orange pegs far apart in one shot.
- **Gems** (levels ending 3 and 8 from chapter 3): each gem is a big loose body on a two-brick ledge. Hitting it only nudges it: knock the ledge out and gravity does the rest. Off the bottom it counts; in the bucket it is a Bucket Drop bonus.
- **Boss** (every tenth level in odd chapters): a big mechanical boss slides back and forth along the bottom, under the pegs, so the ball has to come down through the pattern or thread a gap to reach it. Hit it until its health is gone.
- **Duel** (every tenth level in even chapters): clear the board, then Cogwhistle Overspark, Tinkmaster's older brother, challenges you on a fresh shared board: a coin flip, five balls each, turn and turn about. Lighting the last orange earns its shooter 25,000 and ends the duel; either way the higher score wins. No Fever and no end bonus in a duel. A shot that lights no orange costs 500 of your duel score.
- **No bucket** on some levels from chapter 5 (ending 4 and 9, never a gem level): the only free balls are the score marks. Five bosses take turns, each with a trick: the Tin Drake speeds up as it weakens and throws steel scrap after every shot, the Bolt Golem raises a two-hit shield every third shot, the Gyro Spider jumps when hit and spins webs after every shot that catch a ball (a fireball burns them), the Mechano-Boar charges and turns around when hit, the Cog Yeti heals after any shot that misses it.

### Powers, power-ups and boosts

Powers unlock one per chapter and the level card lets you pick any you have: Multiball, Super Guide (the bounce path through two bounces for three shots; the Crazy Guide, five, once Tinkmaster beats his brother in their duel on level 90), Space Blast (a burst about an inch across that hits everything near the green peg and throws loose eggs and gems), Fireball, Spooky Ball, Pyramid (a step pyramid over the bucket that throws the ball up toward the walls, crumbling to dust after three strikes), Chain Lightning (a bolt that leaps from the green peg through six more pieces) and Free Ball Frenzy (three extra balls and 5,000 points).

Two power-ups can be armed for a shot from the slots at the field's bottom-left: Ring of Fire (the first hit also hits everything in a small ring) and Rainbow Ball (a wide ring). The level card offers one boost, Extra Green Peg. They are earned, never bought: a Ring of Fire for every clear, an Extra Green Peg for three stars, two Rainbow Balls for a boss or a duel won.

With the mouse over the field, Left and Right nudge the aim by a quarter of a degree and Space pauses. The guide shows a faint ball where the shot first meets a piece. Hold the right mouse button over the board to zoom in on where the shot will land and aim very finely (a fiftieth of a degree a pixel); let go to zoom back out.

### Stars

Every cleared level earns one to three stars by score. The marks come from the level itself: what its pieces are worth, one Fever bin, and the bins of the spare balls a good player keeps, with fewer spare balls asked of harder levels. They are shown on the side panel and in the level select tooltip, and the level select keeps your stars and your total.

### Plays

Losing a level (running out of balls) spends one of the day's plays, and out of balls on an ordinary level you can Play On with three more balls for a play. You get five free plays in any rolling 24 hours; clearing a level never costs one. When they are gone the game shows how long until the next free play comes back.

### Golden Gears

Golden Gears are the pachinko's own currency: mail gold to Chairface Chippendale with "pachinko golden gears" as the subject (or press **Get Golden Gears** at a mailbox and the mail fills itself in) and every gold is one gear. You always press Send yourself: the addon will not, and cannot, send mail for you, since the Blizzard (ahem, Gnomish) Regulators forbid it. The shop in the side panel sells 3 Suction Tubes for 1 gear, an Extra Green Peg for 1, 3 Rings of Fire for 2, 3 Rainbow Balls for 3, and 5 plays for 10. Gears are the only way to buy plays. Special balls are otherwise earned only from bosses and duels. `/pachinko gears` shows your gears, `/pachinko shop <suction|ring|rainbow|plays>` buys, `/pachinko buy <n>` fills the mail for n gears.

Everything worth cheating at, the gears, the special balls, the plays and the level progress, is kept in an encrypted, checksummed record mirrored to several places outside the addon folder. At logout it leaves the plain save file entirely and comes back from the sealed copy at login, so editing the save changes nothing, an older copy put back cannot restore spent gears, and an edited copy locks the day's plays.

## The hosts

Four gnomes take the chapters in turn, each a 3D model from the game standing in the round box over the board, acting out the match, with a voice and lines of their own. Each brings two powers, and the level card lets you pick either while they host:

- **Tinkmaster Overspark** (chapters 1, 5, 9...): Multiball and Super Guide.
- **High Tinker Mekkatorque** (2, 6, 10...): Space Blast and Chain Lightning.
- **Razzle Sprysprocket** (3, 7, 11...): Pyramid and Free Ball Frenzy.
- **Bink** (4, 8, 12...): Fireball and Spooky Ball.

Each introduces themselves the first time they host, and the host explains every new mechanic the first time it turns up. The bosses and Tinkmaster's brother Cogwhistle introduce themselves too. Every line is spoken, one voice at a time. `/pachinko mascot` hides or shows the host; `mascot target` swaps in any creature you target (until `mascot reset`); `mascot scale`, `face`, `z` and `play <animation>` tune the model.

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

Every picture is a named slot in `Art.lua` with a generated placeholder in `Textures/`; a finished sprite dropped in under the slot's name is used with no code change. `ASSETS.md` lists them all with sizes and rules. `tools/cut_sheet.py` slices a transparent sprite sheet into the slots from a small JSON map (`tools/sheets/`), and `tools/gen_sprites.py` fills every other slot through AutoSprite in the sheet's style (dry run until `--go`). The audio is all generated with ElevenLabs.

## Development

Pure Lua, no build step. `tests/engine_test.py` (needs `pip install lupa`) builds all 400 levels, plays scripted ones through the engine, checks the plays vault, drives the window headless and checks `Textures/` against `Art.lua`. `tools/make_textures.py` (needs Pillow and lupa) regenerates a placeholder for every art slot (`--from-base` derives the coloured sets from a painted white peg, brick, key or boss; `--sheet out.png` writes a contact sheet); `tools/make_notes.py` (needs numpy and soundfile) synthesizes the combo notes and the placeholder effects.
