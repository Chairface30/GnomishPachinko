# Gnomish Pachinko — Art Asset List

Everything the game draws today is a generated placeholder (from `tools/make_textures.py`) or a plain colored square. This is the full list of art that would replace them, in the order it pays off. Audio is done: every effect and announcer line is generated with ElevenLabs (`tools/gen_sfx.py`, `tools/gen_voice.py`), and Tinkmaster Overspark himself is a 3D model from the game, so no character portraits are needed.

Two tiers:

- **Drop-in**: same file name as today, the game uses it with no code change.
- **Needs a small code change**: new file names (per-color pegs, animation frames, HUD skins). Deliver them and I wire them up; the code side is an hour, not a project.

## 1. Format and rules

- **TGA, 32-bit, uncompressed, with alpha**, power-of-two sizes (32, 64, 128, 256, 512). Origin bottom-left (the default export in Photoshop, GIMP, Krita, Aseprite). PNG is fine to hand over; I convert.
- **Tinted vs full color.** Anything marked *tinted* must be painted in white and grays: the game multiplies the texture by a color (blue, orange, gold, per boss...). Paint it in color and the color is lost. *Full color* pieces are drawn as painted.
- Keep a little transparent padding inside the canvas so filtering does not clip edges. Round pieces: the shape should fill about 90% of the canvas.
- File names exactly as listed, lower case; CurseForge's packager is case-sensitive.

## 2. Art direction (from the Peggle Blast teardown, as a target, not a copy)

- Bright, glossy casual-cartoon. Thick soft shading, a strong specular highlight on every round object, warm rim light, no hard black outlines on gameplay pieces.
- Readability first: gameplay pieces saturated and high-contrast; the frame and background softer and lower in saturation so pegs always pop.
- Materials: pegs and balls are glossy plastic or candy; the frame and HUD are warm **copper and brass** with rivets and inset plates (this is a gnomish machine); cards are **parchment-gold** with a thick rounded border; buttons fat, rounded, glossy.
- Palette (approximate):

| Role | Color |
|---|---|
| Blue peg / brick | `#2E6FE0` body, `#8FC2FF` highlight |
| Orange peg / brick | `#F26A1B` body, `#FFC27A` highlight |
| Green peg / brick | `#3DBE3A` body, `#B6F59A` highlight, small gear glyph |
| Purple peg | `#A23FE0` body, `#E1A8FF` highlight, small star glyph |
| Lit (hit) piece | pastel of its color plus a white glow |
| Tough piece rims | steel `#C8CDD6` (two hits), gold `#F2C14E` (three hits) |
| Frame / HUD | copper `#B8662A` to `#E39A55`, dark trim `#5A2E12` |
| Card | gold-parchment `#F7C65A` to `#F2A93A`, border `#C4772A`, navy `#1F3A8A` titles |
| Primary button | green `#3FC83A`, edge `#1E7A1C` |
| Secondary button | orange `#F08A2A`, edge `#A3471A` |
| Field background | night-sky navy today; a soft gnomish-workshop or Azeroth-sky backdrop per world later |

Note on tinting: the game tints the *white* peg texture with the colors above, so one well-shaded white peg gives all four colors. Per-color hand-painted pegs (tier 2) are only worth it if you want glyphs and distinct materials per color.

## 3. Gameplay pieces

### 3.1 Drop-in replacements (same names, tinted unless noted)

| File | Size | What it is | Drawn at |
|---|---|---|---|
| `peg.tga` | 64x64 | Domed glossy disc with a thin darker rim | 18 px (pegs), 30 px (bumpers), 26 px (minimap button) |
| `brick.tga` | 64x32 | Rounded rectangular bar, lit from the top, bevelled ends; must stretch to any length | 30x11 and longer |
| `ball.tga` | 64x64 | Chrome sphere, strong highlight | 16 px |
| `ring.tga` | 64x64 | Soft glow ring, the halo a lit piece wears | 36 px |
| `rim.tga` | 64x64 | Thin metal band at the edge (outer 20% of the radius), light top, dark bottom | 26 px (tough pegs, boss shield), 33 px (minimap) |
| `crack.tga` | 64x64 | White crack lines on transparent, no fill, central | over pegs 20 px and bricks 30x11 |
| `egg.tga` | 64x64 | Egg, slightly pointed top; tinted cream. Two hits hatch it | 28 px |
| `gem.tga` | 64x64 | Faceted cut gem; tinted cyan; spins while falling | 22 px |
| `key.tga` | 64x64 | Old-fashioned key, bow at the top; tinted gold or silver | 22 px |
| `boss.tga` | 64x64 | Round mechanical boss face, gear teeth round the rim, eyes, mouth; tinted per boss (steel, brass, green, red, ice) | 54 px, slides along the bottom |
| `bucket.tga` | 128x32 | Wide copper or clay pot (full color) | 92x23 |
| `pyramid.tga` | 256x32 | Wide golden trapezoid ramp with brick seams (full color) | 420x40 |
| `blast.tga` | 128x128 | Soft radial burst with ragged spikes, white centre fading out | grows 40 to 300 px |
| `dot.tga` | 32x32 | Soft dot; aim guide, lightning bolt, map path | 6 to 8 px |
| `star.tga` | 32x32 | Five-point star with a lighter inner facet | 9, 12, 28 px |
| `icon.tga` | 64x64 | Addon list icon (full color): a peg, a brick, a ball | 64 px |

### 3.2 Per-color and per-state set (needs a small code change)

Only if you want more than tinting can give. Each piece has three states.

| Files | Size | Notes |
|---|---|---|
| `peg_blue.tga`, `peg_orange.tga`, `peg_green.tga`, `peg_purple.tga` | 64x64 each | Full color. Green carries a small gear glyph, purple a star glyph |
| `peg_<color>_lit.tga` | 64x64 | Pastel plus glow, the hit state |
| `peg_<color>_gone.tga` | 64x64 | Shards or a burst, shown for a third of a second as the piece vanishes |
| `brick_<color>.tga`, `brick_<color>_lit.tga`, `brick_<color>_gone.tga` | 64x32 | Same three states for bricks |
| `brick_arc_<color>.tga` | 64x32 | Optional: a slightly wedge-shaped brick so curved runs look continuous |
| `ball_fire.tga`, `ball_electric.tga`, `ball_rainbow.tga`, `ball_wing.tga` | 64x64 | Fireball, Chain Lightning, Rainbow Ball, Free Ball Frenzy balls |
| `key_gold.tga`, `key_silver.tga` | 64x64 | The two lock colors, if not tinted |
| `cage_gold.tga`, `cage_silver.tga` | 64x32 | Cage and gate bars, full color, stretched like bricks |
| `rail.tga` | 64x32 | Indestructible grey steel bar with end caps (today a tinted brick) |
| `bumper.tga` | 64x64 | Star bumper: blue ring, white star centre; today a tinted peg |
| `egg_cracked.tga` | 64x64 | The egg after its first hit (today the crack overlay is drawn on top) |
| `boss_drake.tga`, `boss_golem.tga`, `boss_spider.tga`, `boss_boar.tga`, `boss_yeti.tga` | 64x64 each | Five distinct boss faces instead of one tinted face: Tin Drake, Bolt Golem, Gyro Spider, Mechano-Boar, Cog Yeti |
| `nest.tga` | 64x64 | A nest peg under an egg (today a plain blue peg) |

### 3.3 Launcher, bucket and buckets

| Files | Size | Notes |
|---|---|---|
| `launcher_barrel.tga` | 32x64 | Copper cannon nozzle, drawn pointing down; rotates with the aim (today a grey rectangle) |
| `launcher_hub.tga` | 64x64 | The pivot plate at the top centre (today a tinted peg) |
| `launcher_flash.tga` | 64x64 | Muzzle flash, shown for a moment on launch |
| `bucket_splash1.tga` to `bucket_splash4.tga` | 128x64 | A catch: white splash with spray, four frames |
| `fever_bucket.tga` | 128x64 | One Fever cup; the game writes the letter and value on it. Unlit and lit (`fever_bucket_lit.tga`) |

## 4. Power, item and objective icons (full color)

| Files | Size | Where |
|---|---|---|
| `power_multiball.tga`, `power_guide.tga`, `power_blast.tga`, `power_fireball.tga`, `power_spooky.tga`, `power_pyramid.tga`, `power_lightning.tga`, `power_frenzy.tga` | 64x64 | The master selector on the level card and the side panel's Power line |
| `item_ring.tga`, `item_rainbow.tga`, `item_green.tga` | 64x64 | Ring of Fire, Rainbow Ball, Extra Green Peg: the slots and the card |
| `goal_orange.tga`, `goal_egg.tga`, `goal_gem.tga`, `goal_boss.tga`, `goal_duel.tga`, `goal_longshot.tga` | 32x32 | The objective counter's icon and the map nodes' dots |
| `ball_small.tga` | 32x32 | The balls-left strip (a row of little balls) |

## 5. HUD, cards and map (full color)

| Files | Size | Notes |
|---|---|---|
| `frame_bg.tga` | 512x512 | The window's copper frame plate, 9-slice friendly (even border) |
| `plate.tga` | 256x64 | A copper inset plate for readouts (score, balls, objective) |
| `card.tga` | 512x512 | The parchment-gold card (level start, result, out of plays), even border for 9-slice |
| `button_green.tga`, `button_orange.tga`, `button_grey.tga` | 256x64 | Fat rounded glossy buttons, three colors; plus `_down` variants if you like |
| `gauge.tga` | 128x64 | The multiplier semicircle, unfilled; `gauge_fill.tga` the rainbow fill (the game clips it by progress) |
| `banner.tga` | 512x64 | A ribbon behind the big callouts (FEVER!, FREE BALL!, YOUR TURN) |
| `map_node.tga`, `map_node_boss.tga`, `map_node_locked.tga` | 64x64 | Round stone or wood level nodes; the boss node larger and ringed |
| `map_bg_1.tga` ... | 512x1024 | Optional: a map backdrop per world (ten chapters each): meadow, forest, cavern, workshop, snow... |
| `field_bg_1.tga` ... | 512x1024 | Optional: a board backdrop per world behind the pegs, soft and low-contrast |
| `minimap.tga` | 64x64 | A drawn minimap icon if the "GP" text button is to be replaced |

## 6. Effects (tinted unless noted)

| Files | Size | Notes |
|---|---|---|
| `spark1.tga` to `spark4.tga` | 64x64 | A small sparkle burst, four frames: peg hits, gem drops, the win sweep |
| `confetti.tga` | 64x64 | A few bits of confetti (full color): the GNOME bonus and three-star clears |
| `firework.tga` | 128x128 | A burst for the GNOME bonus |
| `trail.tga` | 64x16 | One segment of the ball's rainbow ribbon in Fever and the Long Shot sparkle line (full color) |
| `glow_soft.tga` | 128x128 | A soft radial glow for the last-peg zoom and the boss's hit flash |

## 7. Priority

1. **Section 3.1** (drop-in): the single biggest visual lift for the least work, no code needed.
2. **Section 3.3** launcher and bucket, and the **section 4** icons: the HUD stops being text.
3. **Section 5** frame, plate, card, buttons: the window stops looking like a debug panel.
4. **Section 3.2** per-color pegs with lit and gone states, and the **section 6** effects.
5. Backdrops per world.

## Audio (done)

Generated and in place: 40 effects (`tools/gen_sfx.py`, prompts inside), the 16-note combo scale from one marimba note, and 32 announcer lines in Tinkmaster Overspark's voice (`tools/gen_voice.py`, voice id `wo6udizrrtpIxWGp2qJk`). Regenerate any clip with `--only <name> --force`.
