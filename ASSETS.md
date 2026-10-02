# Gnomish Pachinko — Art Asset List

Every picture the game draws is a **slot** in `Art.lua`: a name, a file in `Textures/`, a size, and whether the game tints it. The window only ever asks the registry, so **a finished sprite dropped into `Textures/` under the slot's name is used with no code change.** Today every slot holds a generated placeholder (`tools/make_textures.py`), so the game runs complete; replace them one at a time in any order. `tests/engine_test.py` checks that the folder and the registry agree.

Audio is done: every effect and announcer line is generated with ElevenLabs (`tools/gen_sfx.py`, `tools/gen_voice.py`), and Tinkmaster Overspark is a 3D model from the game, so no character portraits are needed.

## 1. Format and rules

- **TGA, 32-bit, uncompressed, with alpha**, at the size listed (powers of two). PNG is fine to hand over; the tools convert.
- **Sprite sheets are welcome.** A transparent PNG with the sprites laid out in rows goes through `tools/cut_sheet.py`: `--list` numbers the sprites and writes a `_boxes.png` to check, then a small JSON map (`tools/sheets/pegs.json` is the first) names each number's slot and the tool cuts, scales and saves them. A `_lit` or `_gone` state is scaled exactly like its base sprite, so paint them at the same scale on the sheet.
- **AutoSprite fills the gaps.** `tools/gen_sprites.py` (key in `~/.autosprite_key`) has a plan for every slot: cut from the sheet, derived locally from another slot, drawn by AutoSprite as a new *pose* of a sheet sprite (the bricks in each colour are "the same orb stretched into a bar", 3 credits each) or as a new *asset* from a prompt with the background removed (2 credits each). It is a dry run until `--go`; `--stage asset` needs no sheet, the sheet and pose stages take `--sheet path.png`. `tools/generated_sprites.json` remembers what was made so a rerun only does what is missing.
- **Tinted vs full colour.** A slot marked *tinted* must be painted in white and greys: the game multiplies in a colour (glow colours, steel and gold rims, the boss's blue shield). Everything else is **full colour** and drawn as painted.
- **Fill.** Round pieces have room around them: the body fills **70%** of a peg canvas (80% for balls, eggs, gems and keys) so the lit state's halo and the gone state's shards can spill into the rest. The game draws the texture bigger to compensate, so a base peg painted edge to edge comes out too big. Bars (bricks, rails, cage bars) fill the width and 90% of the height; they stretch to any length.
- File names exactly as listed, lower case; CurseForge's packager is case-sensitive.

## 2. Art direction (from the Peggle Blast teardown, as a target, not a copy)

- Bright, glossy casual-cartoon. Thick soft shading, a strong specular highlight on every round object, warm rim light, no hard black outlines on gameplay pieces.
- Readability first: gameplay pieces saturated and high-contrast; the frame and background softer and lower in saturation so pegs always pop.
- Materials: pegs and balls are glossy plastic or candy; the frame and HUD are warm **copper and brass** with rivets and inset plates (this is a gnomish machine); cards are dark with a gold border (the text on them is light); buttons fat, rounded, glossy.
- Palette (approximate):

| Role | Colour |
|---|---|
| Blue peg / brick | `#2E6FE0` body, `#8FC2FF` highlight |
| Orange peg / brick | `#F26A1B` body, `#FFC27A` highlight |
| Green peg / brick | `#3DBE3A` body, `#B6F59A` highlight, small gear glyph |
| Purple peg | `#A23FE0` body, `#E1A8FF` highlight, small star glyph |
| Lit (hit) piece | pastel of its colour plus a white glow |
| Gone piece | shards or a burst in its colour |
| Tough piece rims | steel `#C8CDD6` (two hits), gold `#F2C14E` (three hits) |
| Frame / HUD | copper `#B8662A` to `#E39A55`, dark trim `#5A2E12` |
| Card | dark `#211839`, border `#C4772A` |
| Primary button | green `#3FC83A`, edge `#1E7A1C` |
| Secondary button | orange `#F08A2A`, edge `#A3471A` |
| Field background | night-sky navy today; a soft backdrop per world later |

## 3. The slots

The authoritative list is `Art.lua` (run `python tools/make_textures.py --sheet out.png` for a contact sheet of the current set). Grouped here with what each one is for.

### Base pieces (tinted)

| File | Size | What it is | Drawn at |
|---|---|---|---|
| `peg.tga` | 64x64 | White domed disc. **Only the tool reads it**: `make_textures.py --from-base` derives the four coloured pegs from it. Paint this one or the four, not both | - |
| `brick.tga` | 64x32 | White rounded bar lit from the top; the coloured bricks are derived from it the same way. Also the glow and rim around a brick | - |
| `key.tga`, `boss.tga` | 64x64 | White sources for the two keys and the five boss faces | - |
| `ring.tga` | 64x64 | The soft glow halo a lit piece wears, pulsing in its colour | 36 px |
| `rim.tga` | 64x64 | Thin metal band at the edge: steel and gold tough pieces, the boss's shield, the minimap ring | 26 px |
| `crack.tga` | 64x64 | White crack lines, transparent elsewhere, over a damaged tough piece | 20 px |
| `dot.tga` | 32x32 | Soft dot: aim guide, lightning bolt, map path | 5 to 8 px |
| `star.tga` | 32x32 | Five-point star, gold when earned, grey when not | 10 to 30 px |
| `blast.tga` | 128x128 | Soft radial burst with ragged spikes: Space Blast (about an inch across), Ring of Fire | 40 to 100 px |
| `pyramid.tga` | 512x128 | The sandstone step pyramid with a gold capstone, as wide as the board (full color) | 490x122 |
| `pyramid_crumble1..4.tga` | 512x128 | The same pyramid after 1 to 4 of its 5 strikes | 490x122 |
| `pyramid_dust.tga` | 128x128 | A sandstone dust cloud: strikes and the collapse | varies |
| `web.tga` | 64x64 | The Gyro Spider's web | 26x26 body |
| `boss_platform.tga` | 128x128 | The round hover platform the boss's 3D model stands on, seen from above | 78x78 |
| `icon.tga` | 64x64 | Addon list icon (full colour) | 64 px |

### Pegs and bricks (full colour, three states each)

| Files | Size | Notes |
|---|---|---|
| `peg_blue.tga`, `peg_orange.tga`, `peg_green.tga`, `peg_purple.tga` | 64x64 | Body fills 70%. Green carries a small gear glyph, purple a star glyph |
| `peg_<colour>_lit.tga` | 64x64 | The hit state: brighter, with a halo. Shown for the two seconds before the piece vanishes |
| `peg_<colour>_gone.tga` | 64x64 | Shards or a burst, shown for a third of a second as it fades |
| `brick_<colour>.tga`, `brick_<colour>_lit.tga`, `brick_<colour>_gone.tga` | 64x32 | The same three states for bricks |
| `bumper.tga` | 64x64 | Star bumper: throws the ball back harder |
| `block.tga` | 64x64 | Round solid steel block, never lights |
| `rail.tga` | 64x32 | Solid grey steel bar with end caps, never lights |
| `cage_gold.tga`, `cage_silver.tga` | 64x32 | One bar of a key cage, stretched like a brick |
| `key_gold.tga`, `key_silver.tga` | 64x64 | The two keys |

### Eggs, gems and bosses (full colour)

Eggs and gems are loose bodies twice a peg's size, resting in brick cradles; they roll and fall.

| Files | Size | Notes |
|---|---|---|
| `egg.tga` | 64x64 | Whole egg, slightly pointed top; body fills 80% |
| `egg_cracked.tga` | 64x64 | After a hit |
| `egg_hatched.tga` | 64x64 | Hatching, shown while it fades |
| `gem.tga` | 64x64 | Faceted cut gem; spins as it rolls |
| `boss_drake.tga`, `boss_golem.tga`, `boss_spider.tga`, `boss_boar.tga`, `boss_yeti.tga` | 64x64 | Five boss faces: Tin Drake, Bolt Golem, Gyro Spider, Mechano-Boar, Cog Yeti |

### Balls (full colour)

| Files | Size | Notes |
|---|---|---|
| `ball.tga` | 64x64 | Chrome sphere, strong highlight; body fills 80% |
| `ball_fire.tga` | 64x64 | Fireball and Ring of Fire |
| `ball_electric.tga` | 64x64 | After Chain Lightning fires |
| `ball_rainbow.tga` | 64x64 | Rainbow Ball (it leaves a ribbon) |
| `ball_wing.tga` | 64x64 | The leftover balls fired in Fever |
| `ball_spooky.tga` | 64x64 | Spooky Ball |
| `ball_small.tga` | 32x32 | One ball of the balls-left strip along the top of the board |

### Launcher and bucket

| Files | Size | Notes |
|---|---|---|
| `launcher_barrel.tga` | 32x64 | Copper cannon nozzle, painted pointing down; rotates with the aim |
| `launcher_hub.tga` | 64x64 | The pivot plate at the top centre |
| `launcher_flash.tga` | 64x64 | Muzzle flash (tinted), a tenth of a second on launch |
| `bucket.tga` | 128x64 | The free-ball bucket (full colour): a nest, a pot, whatever the world wants |
| `bucket_splash1.tga` to `bucket_splash4.tga` | 128x64 | A catch: four frames over the bucket (tinted) |
| `fever_bucket.tga`, `fever_bucket_lit.tga` | 128x32 | One Fever cup, unlit and scored; the game writes the letter and value on it |

### Icons (full colour)

| Files | Size | Where |
|---|---|---|
| `power_multiball`, `power_guide`, `power_blast`, `power_fireball`, `power_spooky`, `power_pyramid`, `power_lightning`, `power_frenzy` | 64x64 | The level card's master selector and the side panel's Power line |
| `item_ring`, `item_rainbow`, `item_green` | 64x64 | Ring of Fire, Rainbow Ball, Extra Green Peg: the slots and the card |
| `goal_orange`, `goal_egg`, `goal_gem`, `goal_boss`, `goal_duel`, `goal_longshot` | 32x32 | The side panel's objective counter and the map nodes' corner |

### HUD, cards and map (full colour)

| Files | Size | Notes |
|---|---|---|
| `frame_bg.tga` | 512x512 | The window's copper plate. **9-slice**: a 32 px border all round, drawn 24 px wide; the middle stretches |
| `plate.tga` | 256x64 | Inset plate behind the Balls, goal and Score readouts; 9-slice, 16 px border drawn 8 |
| `card.tga` | 512x512 | The level card, result card and out-of-plays panel; 9-slice, 32 px border drawn 24; light text sits on it |
| `button_green`, `button_orange`, `button_grey` (+ `_down` for pressed) | 256x64 | Fat rounded glossy buttons; 9-slice, 16 px border drawn 8 |
| `gauge.tga`, `gauge_fill.tga` | 128x64 | The multiplier semicircle, unfilled, and its rainbow fill (clipped left to right by progress) |
| `banner.tga` | 512x64 | A ribbon behind the big text callouts |
| `callout_fever.tga` | 512x128 | The FEVER! callout, text baked in |
| `map_node`, `map_node_done`, `map_node_locked`, `map_node_boss` | 64x64 | Level nodes: open, cleared, locked, the boss node |
| `map_bg_1.tga` ... | up to 512x1024 | A map backdrop per world (ten chapters). Add `map_bg_2` and so on and raise `ART.MAP_BG_COUNT` in Art.lua |
| `field_bg_1.tga` ... | up to 512x1024 | A board backdrop per world behind the pegs, soft and low-contrast; `ART.FIELD_BG_COUNT` likewise |
| `minimap.tga` | 64x64 | The minimap button |

### Effects

| Files | Size | Notes |
|---|---|---|
| `spark1.tga` to `spark4.tga` | 64x64 | A sparkle burst, four frames (tinted): every peg hit, style shots, the win sweep |
| `confetti.tga` | 64x64 | A few bits of confetti (full colour), thrown on the GNOME bonus and a three-star clear |
| `firework.tga` | 128x128 | A burst for the GNOME bonus (tinted) |
| `trail.tga` | 64x16 | One segment of the ball's rainbow ribbon (full colour) in Fever and behind the Rainbow Ball |
| `glow_soft.tga` | 128x128 | A soft radial glow (tinted): the last-piece slow-mo and the boss's hit flash |

## 4. Priority

1. The pegs and bricks in their three states, the balls, the eggs and gems: the board.
2. The launcher, the bucket and its splash, the icons: the HUD stops being text.
3. Frame, plate, card, buttons, gauge, banner, map nodes: the window stops looking like a debug panel.
4. The effects and the bosses.
5. Backdrops per world.

## Audio (done)

Generated and in place: 40 effects (`tools/gen_sfx.py`, prompts inside), the 16-note combo scale from one marimba note, and 32 announcer lines in Tinkmaster Overspark's voice (`tools/gen_voice.py`, voice id `wo6udizrrtpIxWGp2qJk`). Regenerate any clip with `--only <name> --force`.
