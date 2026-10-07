# Gnomish Pachinko — Changelog

## Unreleased

- **The window fits the screen:** the game and the level editor shrink to fit when they are taller or wider than the screen (1080p, or a large UI scale), and refit when the resolution or UI scale changes. `/pachinko scale <40-150>` picks a size in percent (useful to enlarge it on a 4K screen); it still shrinks to fit. `/pachinko scale auto` goes back to fitting.

## Gnomish Pachinko v0.7.2 (2026-10-06)

- The cannon stays on the host's ring when the board zooms in (on the last piece, or while fine-aiming with the right button). It used to slide off with the zoom and only come back when the view zoomed out.

## Gnomish Pachinko v0.7.1 (2026-10-03)

- **Daily plays are claimed:** each day at noon, server time, a **Claim 5 daily plays** button appears beside your plays (and a banner says so when you open the game). Nothing is added until you press it, and a missed day is not made up. Free plays build up to 50; at 50 no claim comes until you drop below, then the next comes at the following noon. Free plays are spent first.
- A claim time saved before the noon reset (a day after the last claim) moves back to the noon it falls after, so the switch to noon takes effect at once; the reset lands exactly on noon in the realm's time zone.
- **Bought plays never expire** (they lasted 24 hours) and have no limit.
- The minimap tooltip is short: your level and how many are cleared, plays left, when the next daily plays are ready, and the clicks. No stars, gears or mail text.

## Gnomish Pachinko v0.7.0 (2026-10-03)

The first tagged release. Version 1.0 waits until the bosses have their final mechanics.

- **The map is laid out by hand:** every chapter's ten levels sit where they were placed one by one (MapLayout.lua), instead of on a path made from the chapter number.
- Level editor: **the tools on the right are regrouped into sections** that close to their header bar with a click (the ones below move up): Level; Selection and position; Toughness, size and angle; Colors; Mirror, copy and delete; Rails and locks; Moving parts; Files and sharing. Every section starts closed; whichever you open or close stays that way.
- Level editor: **eggs and gems are their own pieces**, with no bricks attached; build what they rest on yourself. The checks warn about an egg or gem with nothing under it (it would fall at the start). A level's layout brought into the editor keeps its cradle bricks as ordinary bricks.
- Level editor: the **Mirror while placing** button sits beside Copy L-R, Copy T-B and Copy quad.
- Level editor: the snap grid sits at the snap's own spacing, 5, 10 or 20 pixels (5 and 10 both drew a 10-pixel grid), every fourth line a little stronger.
- Level editor: **Copy L-R, Copy T-B and Copy quad** make mirrored copies of the selection across one middle line, the other, or into all four quarters (Mirror copy only went left-right). Flip both turns the selection half a turn.
- **Colorblind mode** (a Colorblind box beside Sound and Music, or /pachinko colorblind; off by default): every unlit orange piece wears a white triangle, green a plus and the purple a star (blue has none), so no color has to be told apart by hue. The level editor shows the same marks on pieces set to a color.
- Level editor: **Redo** (button and Ctrl+Y) beside Undo.
- Level editor: **mirror while placing**, left-right, top-bottom or quad: every piece placed (pegs, bars, rows, Super Slides, arcs, circles) gets copies across the board's middle lines. A mirrored slide is a rail of its own and a mirrored key opens only its own cage.
- Level editor: **Preview motion** shows the moving parts moving right on the editor board; any change stops it.
- Level editor: pieces sitting on top of each other are tinted yellow and listed in the checks (a rail's own joints don't count).
- Level editor: a faint **snap grid** shows while Snap is on.
- Level editor (owner): an **Approved levels** list of everything waiting to ship, to load or remove.
- The level card's objective is centred on the card (it sat a little to the right); its icon sits just before the text.
- **The level card is laid out afresh:** the three stars spread out with the score each one takes written beneath it ("Clear" under the first unless the level sets a score), so the "2 stars at..." line is gone; the best score and credits sit under the stars, the power row a little higher, and the objective big and centred right above the Play button.
- Fixed: the aim guide treated moving pieces as standing still, so its ball met a sliding block (or any moving piece) where the block was when the guide was drawn, often in thin air. The guide (and the Super Guide) now moves the pieces on as the predicted ball flies, and is redrawn continuously while anything moves: it meets the piece where the real ball will.
- **Test plays end with a card:** the cleared card (the score counting up and the stars filling by the level's own marks, the sweep and fanfare) or the failed card (out of balls, egg lost), titled TEST, with **Back to editor** and **Retry** and no plays line. Nothing is recorded.
- Level editor: **Export code** shows the code as a block in a scrolling box, with a **Select all** button that selects the whole code for Ctrl+C (the game's clipboard is off limits to addons: an earlier Copy button that tried it caused an error). Import takes a code pasted as a block or as one line.
- A code made on one of the owner's own characters is not a submission when imported: it carries no builder credit.
- Level editor: **star scores.** Type the score for 1, 2 and 3 stars (blank keeps them automatic: the first star for clearing, the others worked out from the board); the left column shows the marks the level ends up with. A level that sets a 1-star score gives no star for a clear below it (it still counts as cleared). The level card, the info panel and the result card's stars use the level's own marks.
- **Super Slides follow physics.** A ball takes a rail only coming in grazing along the inside of a bend (a little more steeply at either end), rides it to the end of that bend, and leaves at exactly the speed it came in (slow balls are no longer sped up). The outside of a bend, a square hit, or a straight rail is an ordinary brick, so a ball no longer floats along the outside of a curve. On an S-shaped rail the ride ends where the bend turns the other way.
- The opening talk and the CurseForge page's opening mention the level editor and sending levels in (Tinkmaster's line is voiced).
- Level editor: **positions count from the middle of the board.** X is 0 on the middle line, minus to the left and plus to the right; Y is 0 on a new dotted line across the middle, plus upward and minus downward.
- Level editor: the **oranges total** counts the always orange pieces and shows the split ("Oranges: 5 (3 always orange, 2 random)"); it can't be set below the always orange count.
- Level editor: **bigger pieces.** Pegs grow to 40 pixels round, bumpers 60, keys 30, eggs 50, gems 46, steel studs 70 and balloons 70 (past the game's own sizes, 3 pixels a click); bars run up to the board's whole width; bricks come in half, full, one and a half and double.
- Level editor: a ring or arc set **turning** spins round its own centre (its gap no longer pulls the turn off to one side, which made it wobble).
- Level editor: slides on a **tight bend** (tighter than about 67 pixels round) are laid in half bricks, and bricks on a bend overlap a little at their joints, so the wall stays closed.
- Level editor: **color buttons go round.** Orange and Green each click through dealt, never, always and back to dealt (making one always makes the other never); Purple, which hops every shot, can land or never. Colors: all dealt puts the selection back to plain dealing.
- Level editor: **Bigger / Smaller work on every piece**: bricks step between full and half, bars get longer or shorter, and pegs, studs, balloons, bumpers, keys, eggs and gems grow or shrink (an egg's or gem's cradle is rebuilt to fit).
- Level editor: **exact positions.** X and Y boxes show where the selection is (one piece's spot, or a group's middle) and take typed numbers: Move puts it there (Enter in a box too), Line up X / Line up Y puts every selected piece in a column or row, Spread X / Spread Y spaces them evenly.
- Test play: a **Back to editor** button in the footer under the board leaves a test at any time.
- Level editor: **Slide arc** and **Slide circle** tools for smooth curves. An arc: click where it starts, click where it ends, move the mouse to bend it and click to lay it (right-click or Escape cancels). A circle: press at the middle and drag out the size; the ring opens at the top as its mouth. Both are laid in full bricks, the last cut to fit.
- Only submitted levels (imported from a player's code) credit their builder in the game. The author's own levels name no one, and neither does a level being test-played from the editor.
- **Players' levels credit their builders:** a level from the editor that goes into the game shows "Level by <name>" on its level card and in the info panel. The CurseForge page and README now invite players to post their level codes in the CurseForge comments.
- Level editor: **any mix of goals.** Oranges and Long Shots (1 to 5) switch on and off, and every egg and gem placed is a goal, so a level can ask for oranges, eggs, gems and Long Shots together. The info panel lists each goal with its count.
- Level editor: **piece colors.** A peg or brick can be dealt at random on every attempt (as before) or set to orange, blue or green for good, and Never orange / Never green / Never purple keep a dealt piece from ever being that color.
- Level editor: exact turns. Type a number of degrees in the box and press - or + to turn the selection by exactly that much, or Set angle to put every selected bar at that angle (0 level, 90 upright). The selection line shows the bars' angle.
- Level editor: a **Super Slide** tool. Drag a path and a rail of bricks is laid along it, ready to ride. Bricks come in standard sizes (full and half): a dragged row or slide is full bricks end to end with the last one cut to fit, and Smaller / Bigger steps a brick between the sizes.
- The map's buttons: **Level editor** and **Return to current level** (was Back to the game) sit side by side in the window's footer under the board, above the author and version line, while the map is open. Reset progress stays at the bottom of the map. The map's path sits a little higher to leave room.
- **Level editor** (the Level editor button on the map, or /pachinko editor), for every player: place pegs, bricks, steel bars and studs, balloons, bumpers, keys and cage bars, eggs and gems (their cradles are built for them). Select with a click, Shift+click or a dragged box, and move, turn (right-drag, the wheel, Q / E), mirror, duplicate, copy and paste or delete the selection as a group. Set tough pieces, always-orange pins, rails, key-and-cage links and moving groups (slide, lift, wheel, swing), the goal, the oranges and the bucket. Start from any level's layout, test-play on the board (no play spent, nothing recorded), save by name, and export a level code to send in. Red pieces are out of the ball's reach.
- The game's owner can import a level code, test it and approve it for a level number; approved levels are then shipped in the addon and replace that generated level for everyone.
- The window shows the version and author along the bottom. The version is 0.7.0.
- **Fixed: the duel's coin flip was rigged by the level number.** It came from the level's fixed random stream, so each duel level always flipped the same way (level 90 always gave Cogwhistle the first shot). It is now a fresh 50/50 draw every time.
- **Spirals can be ridden:** most generated spirals now open like level 8's, with the mouth on the upper flank and the outer arm running down from it, so a falling ball can be laid into it for a Super Slide. Before, nearly every spiral's arm climbed away from its mouth. One in five still opens the hard way.
- Fixed: the goal's count in the info panel ("20 / 20") ran into the end of its heading ("ORANGE PEGS LEFT"). The heading now shrinks to leave room for the count.
- **Free Ball Frenzy gives 1 extra ball** (was 3), still with its 5,000 points. Razzle's line is re-voiced to match.
- **Fewer tutorials:** the Wheel, Twin Wheels, Bumpers, Bumper Gate, Key Gate (level 111) and Sliding Block (level 121) no longer stop for a talk.
- **The last gem's (or egg's) fall is slowed only at the tube:** it drops at full speed and the slow motion and the crowd's "ahhh" kick in only as it is about to drop into the tube (coming down, close above the mouth and lined up with it). If it lands in another cradle or on a ledge instead, the moment ends as soon as it stops dropping, rather than hanging in slow motion while the "ahhh" ran out.
- **Retrying a duel skips the board you already cleared:** once a duel level's first board is cleared, Retry goes straight to the duel with Cogwhistle, carrying over that board's score as before. Starting the level fresh from the map plays the whole thing.
- **Cogwhistle no longer runs away with a duel he opens:** when the coin gives him the first shot, he takes a warm-up shot down a middling lane instead of his best one. On a fresh duel board his best opening (often half the oranges and a big combo) left nothing to catch up on, worst of all on level 90. His later turns are unchanged.
- **Tough pieces show the hits they have left:** a hit strips a layer. A gold-rimmed piece turns steel-rimmed and shows a crack; a steel-rimmed piece loses its rim and becomes a plain piece. The tough pieces' tutorial demo and Bink's line (re-voiced) match.
- **Level 66, the Long Shots tutorial, is redesigned:** just two angled walls of orange pegs in a V, nothing else on the board (no gimmick, rail, balloon, green or rimmed piece). A ball off one wall flies across to the other, so Long Shots come easily.
- **A wedged ball leaves the board:** a ball that stays in the same spot for three seconds (stuck between pieces, jittering in place) is taken off as if it had fallen off the bottom. That is a second longer than lit pieces take to vanish, so a ball just resting on pieces it lit waits for them to go and falls on.
- **The Bolt Golem starts behind its shield,** shown as a glowing half dome over the top of it (dimmer with one hit left). The shield now blocks lightning as well: an orange's bolt knocks off a layer instead of hurting him. He still raises it again every third shot. Razzle's golem line is re-voiced to match.
- Fixed: a ball running off the end of a Super Slide could be taken straight back onto the same rail, over and over, and sit at its end. It now flies on along the rail's last stretch.
- Rail (Super Slide) bricks bounce a ball like any other brick: a touch that doesn't take the rail no longer kills the ball's bounce, and a contact that can't start a ride is an ordinary bounce instead of leaving the ball stopped. On the rail the ball keeps its speed.
- **The Cog Yeti heals 3 health** (was 1) after a shot that lights no orange and never touches it, more than a direct hit's 2, so a wasted shot costs more than a good one earns. The popup shows the amount.
- **The Gyro Spider soaks up the lightning:** a lit orange no longer hurts it, it only charges it (the count shows over its body). Strike the spider with the ball in the same shot and the whole charge hits it on top of the strike's own 2; if the shot ends without a strike, the charge fizzles. Lighting oranges and then finding the spider (which jumps when hit, past webs that catch the ball) is the fight now.
- **Play On is gone,** and **a retry uses a play**: starting a level over (the Retry button beside the board, or on the result card after a clear) spends one of the day's plays. A lost level still costs one play, and retrying it after the loss does not cost a second.
- The Gyro Spider's webs can also pop up right where a peg has been cleared, as well as in the open spaces.
- The phoenix egg tutorials show an egg being hit: it cracks, hatches on the last hit (two, or three for the tougher eggs), and the phoenix climbs out of it and away, over and over while the host talks, with no arrow.
- The moving-piece tutorials (Slider, Lifts, Wheel, Pendulum, Twin Wheels) show a plain moving piece instead of whatever moved first (the Lifts talk showed the purple peg), and show it moving: lifts bob, sliders glide, wheels circle, pendulums swing.
- The steel and gold rim tutorials now show the pieces themselves: a steel-rimmed and a gold-rimmed peg (just the gold one for the gold tutorial) above the talk box, a ball bouncing on each, cracking it hit by hit until it lights, then starting over, with no arrow.
- **The Gyro Spider spins two webs every time an orange is lit** (instead of two after every shot), up to 10 on the board, never right on top of a ball in flight.
- The last gem's (or egg's) fall stays in slow motion but zooms back out to the whole board, so you can see whether the bucket catches it.
- Fixed: the Levels button beside the board opened the map behind the level cleared card, which stayed on screen. Any card is now closed first.
- Gems are heavier: a hit shoves a gem 3.5 times less than before. The temporary Gem mass slider is gone from the Testing fly-out.
- **Super Slides are earned, not handed out.** A ride lights only the bricks the ball actually glides past; hitting the lead brick no longer lights the whole chain. And the ball takes a rail only in at a mouth (either end brick) or coming in grazing along the face (within about 35 degrees); a squarer hit on a brick mid-chain is an ordinary brick hit that bounces and lights just that brick.
- **The last orange no longer decides a duel.** Its 25,000 bonus is gone: lighting it pays only the peg's own points and ends the duel (there is nothing left to shoot for), and the higher score wins. Cogwhistle's challenge line is re-voiced to match.
- The level card for a duel level (20, 40, 60 and on) no longer prints the rival's long description under the goal; the duel's rules are still in the map tooltip.
- **The Tin Drake's iron draws the lightning:** while any of its scrap barricades are up, an orange's zap strikes the nearest piece instead of the drake, destroying it. Hit the drake directly, or clear the iron first.
- The Tin Drake throws a piece of iron the moment every ball is fired (at most 4 up at once), so it can't be aimed around. He keeps a boss's full health.
- The boss tutorials have no arrow or sample piece.
- **The tutorials show what they talk about:** while the host speaks, a big sample of the piece in question is put up in the middle above the talk box (only for the talk: gone before the level card shows) with a soft glow and the goofy arrow jabbing and wobbling at it (the purple peg, bricks, balloons, rails, every moving setup, keys, eggs, gems, the bosses and the rest).
- **Gems (and eggs) move like real bodies when hit:** the shove goes along the line from the ball through the face it struck, as strong as the ball closed on that face. A square hit drives a gem straight on; a glancing one barely nudges it.
- **FULL CLEAR!** Lighting every piece on the board that can light (pegs, bricks, eggs, the purple) pays a 100,000 bonus, once, with a banner, fireworks and the fanfare.
- A tutorial is always voiced by the host of the first level it belongs to, whenever the player meets it (the special balls by Tinkmaster, the Slider by Razzle, and so on).
- **Every obstacle and objective gets a tutorial:** a voiced talk from the chapter's host on the first level it appears, and after Play a cartoon arrow that slides in on the thing itself (following it if it moves) until the first shot. New talks: the purple peg, small rails, each moving setup on its own (Slider, Lifts, Blocks, Wheel, Bumpers, Pendulum, Key Cage, Twin Wheels, Bumper Gate, Key Gate, Sliding Block), cages inside cages, three-hit pegs and three-hit eggs. The existing ones (bricks, balloons, tough pegs, eggs, gems, mixed, Long Shots, the bosses) now point too.

- A chapter's rewards are no longer written on the result card: the special-ball buttons on the left glow and a "+1" floats up off each as its count goes up.
- Fixed: the result card's high score line was hidden.

- Star marks set by hand where the formula misjudged: level 8 (the Super Slide) asks 300,000 for two stars and 500,000 for three; level 10 (the first boss) asks 150,000 for two and 260,000 for three, down from 420,000 and 637,000.
- No green pieces on the Super Slide tutorial's spiral (level 8, which is the spiral alone): its greens are blue, so the ride is never interrupted by a power.
- **The Super Slide tutorial points the way:** on level 8, after its talk, a cartoon arrow slides in and out along the way the ball should come in, pointing along the spiral's mouth into the inside of its lead brick, at the angle that catches the rail. It disappears with the first shot.
- **The Tin Drake gets faster, faster:** it speeds up from its own starting speed as it weakens (before, its first hit could slow it down), reaching 2.2 times that speed near death in chapter 1 and more in each later chapter, up to a cap.
- Clearing a chapter (its boss or duel) gives one each of Ring of Fire, Rainbow Ball and Suction Tube, the first time only; replaying it gives nothing more. (It used to give two Rings, a Rainbow, two Suction Tubes and a green peg every time.)
- The Tin Drake faces the camera in the conversation box.
- **The result card's lines, tidied:** under the title, what happened (Done! or Missed:), then the level's high score (NEW! when you just beat it), then the best combo. The Fever points and the star marks are gone, and each line has its own size and colour so it reads easily.
- The LEVEL CLEARED banner shows on its own; the score and the Fever bins are left to the result card.
- A bank shot now counts by how far across the board it goes: the orange must be at least 220 pixels sideways from where the ball met the wall (about half the board), not just a long flight.
- Fixed: a blue title banner showed for a moment behind the opening talk. A level no longer opens with a banner; the level card shows its title and objective.
- The Suction Tube's tutorial arrow comes in lower still, nearly level from the right.
- **The board waits for Play:** while the level card (and any talk before it) is up, the board shows only its painted backdrop; the pieces, bucket, cannon, boss and ribbon appear when Play is pressed.
- **The map reads better:** taller chapter buttons with bigger words (<<, Prev, Next, >>) along the top, and the chapter's name (22) and its levels line (15) larger, beneath them.
- **Boss health rebalanced** for oranges that zap and double-damage direct hits: it starts at 12 and climbs a little under half a point a chapter (29 by the last boss). In simulated play a careful player needs most of an early boss level's balls and beats late bosses about two times in three. The hand-set 8 for the first Gyro Spider is gone; it has 13 like its chapter.

- The special balls (and the Extra Green Peg) are handed over on the line where the host says so, "Here's one of each", with a chime; until then their buttons show none. Skipping the talk still hands them over.
- Closing the result card stops everything it set playing: the tally, the rockets, the fanfare and the host's line.
- A bank shot now needs the ball to go off the wall and straight onto an orange peg; touching anything else first (a blue peg, a brick, a balloon, a bumper, the pyramid) spoils it.

- The tutorial arrows can no longer be mixed up: the Rainbow Ball's comes in from the left side, nearly level, and the Suction Tube's comes in lower from the right.
- **More style points:** lighting 3 oranges with one ball is a HAT TRICK (+5,000), 5 an ORANGE CRUSH (+12,500), 8 an ORANGE AVALANCHE (+25,000). Coming off a side wall and flying at least 200 pixels without touching anything before lighting a piece is a BANK SHOT (+7,500).

- **The tutorials point, loudly:** with the glow, a comically fat cartoon arrow jabs at each button being talked about, each from its own silly angle, wobbling as it goes.
- **The testing buttons have their own fly-out:** a Testing tab on the window's right side (owner characters only) opens a panel with Unlock all, Unlimited items, +10 Golden Gears and Reset progress. They are gone from the map, the shop and the out-of-plays panel.
- **Each star pops all the way:** as it fills it flies up, spins a full turn and drops back into place. Only a three-star clear brings the fanfare, and with it a shower of little stars shooting out of the big ones like bottle rockets.
- **The tutorials point:** while the host talks about the special balls, their buttons glow; as each one is named (Ring of Fire, Rainbow Ball, Suction Tube) only that one lights up. The Extra Green Peg's button glows the same way in its talk.
- **The stars take their time:** the count-up runs over four and a half seconds at an even pace, and each star pops to life as it fills, swelling and springing back with a burst of light behind it.
- **Cheat-proofing pass.** Everything that makes or spends Golden Gears, special balls, plays or progress now lives in the addon's private namespace, out of reach of a `/run` line or another addon. Only results the game itself produced are recorded (once each); tutorial gifts are the ones written in the addon and are remembered in the vault; the item counts handed out are copies; levels, stars, best scores and the Crazy Guide are sealed from the addon's own record, so an edit to the live settings is undone at the next save; and the owner check reads the player's name through the client function as it was at login.
- The cheer at the end of a three-star clear fades out naturally instead of stopping dead.

- The opening talk runs in a new order (Tinkmaster's welcome and how to play first, then the work-in-progress note and the call for ideas), and ends with him ushering the player up to the machine and sending them off.
- **New players start with no special balls and no green pegs,** and those buttons stay hidden until Tinkmaster explains them: the special balls on level 2 (with one of each to try), the Extra Green Peg in a new voiced talk on level 3 (with one to try). Players past those levels hear the talk on their next level.

- **Button ends are true half gears:** every plate button is drawn as a half-cog end on each side, at its real shape whatever the button's height, with the logo's copper plate between them. Before, the plate's ends were sliced and stretched, and the cogs came out misshapen on taller buttons.
- Fixed: the conversation box's buttons could not be clicked. The raised cards (and the sheet behind them that eats clicks) sat over it; the box now sits over everything.
- The plays counter reads simply PLAYS LEFT, in word-art; bought plays are not shown apart.
- Over ten balls, one extra ball sits at the top of the left column with the total written in it (11, 15, ...); at ten or fewer it disappears.

- **Plays left are a brass play token and a framed number,** with a short note beside them (bought plays, or the wait for the next free one).
- Reset progress now also puts the special balls and green pegs back to what a new player starts with; gears and the day's plays are kept.

- Fixed: the result card's Map and Retry buttons overlapped.
- **Buttons click:** held down, a button's plate darkens and its words sink a little; let go over it, it gives a soft click.
- The balls left are two and a half times bigger, in two columns of five; the left column is a little wider to hold them.
- The Extra Green Peg can only be used before a level starts, from the level card; once the level is under way its button is greyed out.
- A soft click going into the shop and back out.
- **The result card, redesigned:** three big bevelled stars span the whole card, the middle one larger and higher, sitting over the card's own border. They fill with gold left to right as the score, big and without a label, spins up beneath them. All the text comes below.
- **Every button wears the logo plate** (gold words on the blank logo plate), across the game, apart from the map's nodes and the pictures that have their own art.
- The level and result cards sit over everything on the board; Tinkmaster's ring no longer covers them.

- **A bigger level card:** larger text throughout, the best score on a line of its own, the power with its icon and what it does, and every button in the logo's style (a blank logo plate that keeps its cog ends at any width, gold words on it).
- **The left column's special balls are big and sit under the balls:** Ring of Fire, Rainbow Ball, Suction Tube and now the Extra Green Peg, each a logo-plate button with a large icon. The green peg is the level boost while the card is up, and adds a green peg on the spot during play.

- Every explanation of buying Golden Gears now says plainly that the addon will not, and cannot, press Send: the Blizzard (ahem, Gnomish) Regulators forbid it. Tinkmaster says so too, in a new voiced line.
- **The star count-up sounds the part:** a rising tally under the count, a bottle rocket as each of the first two stars fills, and a fanfare with fireworks when the third does.
- **The right column, tidied:** the info spreads over the column's height with one text size throughout (13, numbers 14, headings all the same height), so nothing is tiny. The shop's way in is the golden gear with a SHOP header beside it. The line under Get Golden Gears is gone, and the owner's button sits in the shop. Sound and Music are a footer along the bottom.
- **Next Level, Restart and Level Select look like the logo:** small copper plates with the logo's cog end-caps and gold lettering, cut from the logo itself, instead of bright enamel.

- **The result card counts up:** three big stars start grey and fill with gold from left to right as the score climbs past each star's mark, with a rising chime for each full star.
- **Restart, Level Select and Next Level are gnomish plates:** colored enamel (copper-red, blue, green) in a riveted brass rim, an icon in a porthole, and the word in cream with the cog-and-piston letters.
- **The info headings are brass word-art** (Objective, Power, Balls, Score and the rest), every O a cogwheel and every I a piston. The goal heading changes with the objective. `tools/word_art.py` draws them.
- **The shop button is a shiny golden gear** that turns and glows under the mouse. **Get Golden Gears** now sits in the shop, under the offers, and the level buttons close up at the bottom of the column.

- **The Golden Gear shop has its own page.** A big Golden Gear Shop button at the bottom of the info swaps the info for the shop in the same space; Leave shop swaps it back.
- The gear shop sells the **Extra Green Peg** for 1 Golden Gear. The shop is three rows now, and the level buttons sit a little lower to make room.
- **Sound and Music boxes** above the right column: one switches the sound effects and voices, the other the music, each on its own.
- **A welcome for new players:** Tinkmaster greets them, warns that the bosses are a work in progress and may change completely, and asks for ideas (new gnome hosts and powers, obstacles, bosses) on the CurseForge page.

- **Bosses fall to good play, not lucky bounces.** Boss levels now deal orange pegs (the boss's health and four more; they are not goals). Every orange you light zaps the boss with a bolt for 1 damage, and a direct hit does 2. The Bolt Golem's shield stops only the ball, not a zap. In simulated play a careful player now beats nearly every boss. Before, only a direct hit counted, and from a fresh board only about one aim in seven touched the boss at all.
- Fixed: the sad "awww" could play as the last-piece zoom began, on a shot that then hit. It now plays only when the ball has truly missed: the shot ends with the piece standing, or the slow motion stays off for most of a second.
- The first Gyro Spider (level 30) has 8 health instead of 9.
- Fixed: a duel could be lost with the higher score, when Cogwhistle lit the last orange. The last orange now pays a 25,000 bonus and ends the duel, and the scores always decide it.
- **The last-piece zoom has a crowd:** instead of a whispered "last one", a held "ahhhh" builds through the slow motion until the piece lights and the Fever music cuts in. If the ball misses, it falls away into a sad "awwww".
- **Every boss has a voice of its own:** the Bolt Golem booms through iron with a metal-room echo, the Gyro Spider hisses and crackles with electricity, the Mechano-Boar snorts and growls, and the Cog Yeti rumbles slow through an ice-cave echo.
- **The Tin Drake sounds like a small dragon:** a new snarling, hissing voice, pitched up with a growl and a light tin ring, and a new line. In the conversation box it is turned half round to face the player.
- **The special-ball tutorial comes with a gift:** one Ring of Fire, one Rainbow Ball and one Suction Tube to try, given once with the level 2 talk.
- Fixed: the speaker's name in the conversation box was half covered by the border.
- **The conversation box keeps the framing set by eye** for Tinkmaster, Mekkatorque, Razzle, Bink and Cogwhistle. The temporary dialog tuning panel is gone.
- **Cogwhistle looks the evil brother:** Tinkmaster's own model, lit pure, strong green. Any speaker can be given a tint; tinted speakers use a model frame of their own so the light never spills onto the others.
- **Super Guide tracks two bounces.** It no longer grows when earned again; it just runs for more shots.
- **Tinkmaster duels his brother.** Level 90, the end of his chapter 9, is a duel with Cogwhistle instead of a boss, with its own voiced conversation. Win it and his Super Guide becomes the **Crazy Guide**: five bounces of the path. The unlock is sealed with the rest of the progress.
- The host named in the right column follows the chapter shown on the map, and goes back to the level's host when the map closes.

- The speaker in the conversation box sits behind the box's border, in a window that runs to the box's edges. The dialog tuner adds a camera distance slider.
- **Balloons fit the picture.** A level's balloons come in mirrored pairs, the same size at the same height either side, with an odd one only on the center line. Each level keeps to one arrangement: by the walls, on the flanks, or a center balloon with pairs beside it. No more single balloon stuck somewhere at random.
- **Temporary dialog tuning panel** left of the window: pick any speaker in the conversation box (the four hosts, Cogwhistle, the five bosses) and set height, sideways, zoom, turn and tilt. The box now shows whole models in a clipped window instead of the head-cropping portrait camera.
- Pressing **Get Golden Gears** away from a mailbox has Tinkmaster explain, in his own voice, how gears are bought by mail. He says it once; after that, heard or skipped, it is a chat line.
- **Duels end on the last orange.** Lighting it earns its shooter a 25,000 bonus and ends the duel at once; the higher score wins. A duel has no Fever and no end bonus.
- **A Super Slide is a sure thing.** Once a ball takes a rail it rides it to the end along the bricks in order, lighting every one, and leaves off the far end. It used to slip off at joints and leave bricks unlit.
- **Scored Fever tubes stand out:** unscored tubes are dimmed and their points grayed; a scored tube lights up with a pulsing glow behind it and over its letter.
- The boss's health bar sits just under it, always on the board and over its model; its name is no longer printed on the board.
- **Each host and boss keeps the framing set by eye** (height and zoom per host; view angle, distance, turn, tilt, offset, size and platform per boss). The temporary tuning panel is gone.
- The boss's health bar and name sit below it, and a hurt boss no longer shows cracks.
- Hosts and bosses show their whole model, head to feet. They used the client's portrait camera, which crops to the head. The boss tuning has a Size slider for the model's frame.
- Fixed: the boss Model turn slider did nothing. The camera now circles the boss to turn it.
- **The host stays inside the ring however far it is zoomed.** The model is clipped to a square that lies wholly under the ring's band, so it shows only through the round opening. A try with nine model copies in strips was dropped: the copies drifted out of step.
- **The tuning panel sets each boss separately:** arrows pick the boss and show its model on any boss level. Sliders set view angle (swinging the camera up for a bird's-eye view), camera distance, turn, tilt and x/y offset. A button hides the platform for that boss.

- Fixed: the host Zoom slider snapped back. The client refits a model to its frame, so zoom now resizes the model's frame instead.
- A power is announced in the voice of the host it belongs to, whichever host runs the level.
- The Pyramid lasts three strikes, and a ball over its bare corners past the bottom step falls through.
- **Temporary host tuning panel** left of the window: Height and Zoom sliders for each of the four hosts (arrows pick the host), and a Boss tilt slider. Values save on the spot; they will be written into the game and the panel removed.
- **Lit bricks always leave after two seconds,** Super Slide rails included. A lit rail brick no longer catches the ball or gives it the speed boost.
- **Eggs sit in different cradles:** a V, a shallow V, a flat ledge or a three-brick cup.
- **Bosses are seen from above:** the model is tilted toward the camera and stands on a round platform drawn as a circle.
- **Boss models:** the Tin Drake is a mithril dragonling (Arcanite, then Mechanical as fallbacks), the Gyro Spider takes the Electrocutioner 6000, the Mechano-Boar is Agathelos's armored boar, and the Cog Yeti an Ice Thistle yeti.

- **Bosses are 3D.** Each boss is its creature model standing on a round hover platform that slides with it. It flinches when hit and plays its death when beaten. The flat face shows until the model loads, and stays if the client lacks the model.
- Fixed: stray balloons appeared around the board in Fever and did nothing. They were old piece pictures from a bigger board, re-shown at their old spots when Fever added its balloons.
- **Chain Lightning is a real bolt.** A jagged, flickering line with a blue glow leaps from the green peg to each piece in turn, flashing on each one, then fades.
- The right column names the level's host above the Power line.
- The Golden Gear shop is a two-by-two grid, so it no longer runs into the level buttons.

- **The Pyramid is a step pyramid as wide as the board.** Only its bare corners, past the bottom step, let a ball fall. A strike even at its foot throws the ball up to the middle of the board. It covers the bucket, which is parked and hidden under it. Both sides throw the ball up and back toward the wall on that side. It lasts three strikes over any number of shots, crumbles a little at each one, and turns to dust on the last.
- **Each boss fights its own way.** Steel scrap is now only the Tin Drake's. The Gyro Spider spins two webs after every shot, anywhere in the open. A ball that touches a web is caught, and the web and the ball are both gone. A fireball burns webs away.
- The Gyro Spider uses the Mechano-Tank spider mech model.
- The Get Golden Gears button reads "Get Golden Gears" over "1g each".
- New sounds: web shot, web catch, pyramid crumble, pyramid collapse.

- **The Tin Drake builds upward.** It throws two blocks after every shot: first five in the row just above it, then that row's two ends by the walls (easy bank shots), then rows higher up, only where the pattern has been cleared. Every row keeps a column open.
- **The pyramid kicks harder**, so a ball that lands on it goes back up the board.
- **The owner's button gives 10 Golden Gears** instead of free plays.
- The Get Golden Gears button is twice as tall and its text wraps.

### Earlier in development

- **Every picture is a named art slot.** `Art.lua` lists all 114 of them (pegs and bricks in four colours and three states, balls, eggs, gems, bosses, launcher, bucket and splash, icons, skins, map, effects) with a generated placeholder each, and the window draws only through them, so a finished sprite dropped into `Textures/` under the slot's name is used with no code change. `tools/cut_sheet.py` slices a transparent sprite sheet into the slots from a JSON map; `tools/make_textures.py` regenerates the placeholders. New on screen because of it: lit and vanishing pictures per piece, a muzzle flash, a bucket splash, sparkles on every hit, confetti and fireworks on the GNOME bonus and three-star clears, a rainbow ribbon in Fever and behind the Rainbow Ball, a glow on the last piece, lit Fever cups, icons for powers, power-ups and the objective, a balls-left strip, a multiplier gauge, skinned buttons, cards, plates, map nodes and backdrops, and a drawn minimap button.
- **Eggs and gems are loose bodies, twice a peg's size.** They are not pinned: gravity pulls them, and each rests in a cradle of two ordinary bricks the level builds under it (a flat ledge for a gem, a V for an egg). A hit only nudges them (and damages an egg). Knock a gem's ledge out and it rolls and falls: off the bottom it counts, in the bucket it is a Bucket Drop. Lose an egg's cradle and it drops: the bucket saves it, the floor loses the level. The last gem's fall gets the slow-mo. Space Blast throws them.
- **Space Blast is about an inch across** (radius 45, down from 140).
- **400 levels over forty chapters**, every chapter a place from the original Azeroth; no Outland or Northrend.
- Fixed: after a lost egg (or any result card without a main button) the next level card had no PLAY button.

- **A proper ramp.** Chapter 1 is nine hand-drawn starter pictures (level 1 is nine pegs and three oranges; bricks first appear on level 7; level 10 is the first, five-health boss). From level 11 the fifteen pattern families start sparse and fill in until level 80. Oranges go 3 on level 1, 8 by level 10, 15 by level 40, 30 by level 1000. Gimmicks arrive one per chapter from chapter 3 in a fixed order (Slider, Lifts, Blocks, Wheel, Bumpers, Pendulum, Twin Wheels, Bumper Gate, Sliding Block), each making its debut on the first level of its chapter, and the pool is drawn from more often as the levels climb.
- **Star marks come from the level itself**: what its pieces are worth, one Fever bin, and the bins of the spare balls a good player keeps (fewer spare balls asked of harder levels: more goal pieces, tough pieces, eggs, gems, a boss). A fuller board asks for a higher score.
- **The last-peg moment.** When a ball closes in on the last goal piece (the last orange, the last egg's last hit, the boss's last point), time slows to less than a quarter and the field zooms in on it (it keys in off a look-ahead of the ball's path, so it starts well before contact, and when the last two goal hits come in one swoop it starts before the first of them). The boss is drawn behind the pegs., easing back out once it lights. That is the only slow motion: Fever runs at full speed, the leftover balls start firing less than a second after the last piece lights, and a **clearing fanfare** loops from that moment until the last of them has landed.
- **A level map in Peggle Blast's shape** replaces the grid: one chapter a page, its ten levels climbing a winding path to the boss node at the top, stars under every node, the path lit green as far as you have cleared, Prev/Next for a chapter and << / >> for ten.
- **Minimap button** ("GP"): left-click plays, right-click opens the level select, drag it round the ring; `/pachinko minimap` hides it.
- **The announcer.** Voice lines play from `Sounds/Voice/` when the files exist (level start, boss start, free ball, Fever, cleared, three stars, out of balls, out of plays, combos, hatched, gem, boss shield and boss down, every power); `/pachinko voice` turns them off. `ASSETS.md` lists every texture, effect and voice line still wanted, with ElevenLabs prompts.
- **A full set of sound effects, generated.** `tools/gen_sfx.py` makes every effect with ElevenLabs from written prompts (dry run by default, `--go` spends credits), including the combo scale resampled from one generated marimba note. The game now has a sound for everything: the bucket, combos, each power's activation, the fever bins, a lost ball, the spooky re-entry, a gem knocked loose, the boss's shield, heal and hop, the ramp bounce, level start and out of balls. Until the tool has run, synthesized stand-ins fill those names. `tools/gen_voice.py` records the announcer with an Eleven v4 voice of the pachinko's own (never Trixie's).
- **Tinkmaster Overspark is the host.** The gnome engineer of Tinker Town, as his own 3D model from the game, stands in the field's top corner and acts with the game's own animations: waves at a new level, points when you fire, cheers a free ball, flexes a power, laughs at a combo, kneels for the last peg, dances through Fever, roars at the GNOME bonus, cries when the balls run out. His voice is the announcer. `/pachinko mascot target` makes any creature you target the mascot instead; `mascot npc <id>`, `id <display id>`, `scale`, `face`, `z`, `play <animation>` and `reset` tune him, and `/pachinko mascot` alone hides or shows him.
- **Built from the Peggle Blast notes.** Fever's five buckets are G-N-O-M-E at 1,000 / 10,000 / 25,000 / 10,000 / 1,000; light all five and the GNOME bonus pays 100,000 and every bucket is 25,000 from then on. A shot ends with its summary ("350 x 8 pegs = 2,800"), a shot that touches nothing is a Total Miss, two goal pieces far apart in one shot are a Long Shot and a ride along six bricks a Super Slide, each worth 5,000 style points, and "2 balls left" / "last ball" warnings show. Super Slides are real: a grazing touch on a brick rides along it instead of bouncing. Gems count the moment they drop off the bottom and a Bucket Drop pays 10,000 on top. Eggs hatch in two hits (three from level 300). Super Guide stacks. Every level has a name, a card before it (number, name, objective, star marks, Play or Map) and a card after it (stars, score, Retry / Next / Map), and a retry deals the oranges, eggs and gems onto different pegs. A new gimmick from chapter 9, the **Key Cage**: a gold cage of solid bars round three orange pegs that falls away when its loose key is lit.
- **Eggs sit in nests and fall.** Each egg gets two nest pegs under it; clear them and the egg drops and rolls like a gem. Catch it in the bucket and it hatches ("Phoenix Hatch", +5,000); let it fall off the board and the level is lost. An egg that comes to rest settles where it is. An egg nothing could be put under is wedged and never falls.
- **Long Shot levels** (ending 6 from chapter 7): the goal is two or three Long Shots, two orange pegs far apart in one shot.
- **Play On.** Out of balls on an ordinary level, the result card offers three more balls for one of the day's plays; the loss is only recorded when you end the level, retry, or move on. Not in a duel or after a lost egg.
- **Tinkmaster's tips**: the first time a mechanic appears (bricks, tough pieces, a boss, eggs, gems, a duel, keys, Long Shots, no bucket, moving parts, the power-up slots) the level card carries a line from him, once.
- **Presentation**: pieces fade in one after another when a level starts, whatever is left sparkles away when it is won, the Super Guide path is a rainbow, and the side panel has fill bars for the next free ball and the multiplier.
- **A portrait board.** The field is 490 by 700, Peggle Blast's proportions: the patterns sit in the upper two thirds and the ball has a long fall to the bucket. Every picture keeps its shape (the generator's drawings are scaled into the new field); the Fever buckets, the boss's band, the Pyramid and the level map follow the new size.
- **Powers, power-ups and boosts.** An eighth power, Free Ball Frenzy (three extra balls and 5,000 on the spot). The level card has a master selector: pick any power unlocked so far (one per chapter reached), and the pick sticks. Two in-level power-ups, armed from slots at the field's bottom-left for the next shot: Ring of Fire (the first hit also hits everything within a small ring) and Rainbow Ball (a wide ring). One pre-level boost on the card, Extra Green Peg. All of them are earned, never bought: a Ring of Fire for every clear, an Extra Green Peg for three stars, two Rainbow Balls for a boss or a duel won; the result card lists the rewards. You start with two Rings and one Extra Green Peg.
- **Key Gate** gimmick from chapter 12: a long slanted bar over a cluster of oranges, dropped by its key across the field. From level 300 the Key Cage chains: the gold key sits in a silver cage whose silver key is elsewhere.
- **Keyboard**: with the mouse over the field, Left and Right nudge the aim by 1.2 degrees (the cursor takes over again once it moves) and Space pauses.
- The mascot judges whether the client could show a creature only after giving the model a moment to load, so Tinkmaster no longer gives way to your own character on a slow load; `/pachinko mascot status` says what was tried.
- **The duel is a real match.** Even chapters' tenth levels: clear the board (stage one), then Cogwhistle Overspark, Tinkmaster's older brother, refuses to accept it and a duel starts on a fresh shared board: a coin flip, five balls each, turn and turn about, two score boxes on the field, his aim line shown in red while he thinks. A shot that lights no orange costs its shooter a quarter of their duel score. Highest duel score wins; losing costs a play and restarts from stage one. The rival aims with a look-ahead over a fan of angles and picks one of the best three, so he goes for the oranges but can be beaten. The launcher now swings toward the cursor instead of snapping, and Super Slide style points come in tiers: 5,000 "Nice!" at six bricks, 12,500 "Awesome!" at twelve, 25,000 "Unbelievable!" at twenty.
- **No bucket on some levels.** From chapter 5, levels ending 4 and 9 (never a gem level) have no bucket: no free balls from below. The level map and the level's objective say so.
- The slow-mo zoom no longer jerks in, backs out and comes back: the engine lets go only after the ball has been off track for several checks, and the window holds the zoom through a brief gap and glides after the ball instead of snapping. It is centred on the ball and follows it, not the piece, and it only happens for a real close call: a ball whose predicted path strikes the last piece. A ball merely passing near it no longer triggers it, and the slow-mo lets go as soon as the ball is off track and moving away.
- The slow-mo whoosh and "Last one!" play once a shot; when the slow-mo stops and starts again in the same shot (the ball swings away and back) it zooms again quietly instead of playing them twice.
- The bucket **ka-chings** like a cash register when it catches a ball, and the ball **clinks** off its ceramic rim when it bounces off the lip (a new `rim` event).
- **Reset progress button** on the level map, beside Back to the game: click it twice within six seconds to wipe levels, stars and best scores (the day's plays are kept). Same as `/pachinko reset`.
- **Owner top-up.** On the owner's own characters (an encoded allow-list, the same scheme as the casino's) a separate green button on the side panel and on the out-of-plays panel grants five plays for free, no mail.
- The side panel's plays readout no longer runs into the buy button when the "next free play" line shows.
- The mailbox's **Buy Pachinko Plays** button sits under the casino's Buy Casino Credits button when that is showing, and takes its place when it is not.
- **Tough pieces.** Steel-rimmed pegs and bricks crack on the first hit and light on the second; gold-rimmed ones take three. They start in chapter 4 and grow to a third of the board; three-hit pieces from level 300; orange pegs can be tough from chapter 7. A ball cannot hit the same piece twice in a fifth of a second.
- **Four kinds of level.** Classic (light the oranges), **Eggs** (hatch every egg, three hits each; levels ending 5 from chapter 2 and 7 from chapter 4), **Gems** (knock every gem loose and catch it in the bucket, a miss puts it back; levels ending 3 and 8 from chapter 3) and **Boss** (every tenth level). The objective is spelled out when a level starts and on the side panel; the level select marks each kind with a coloured dot.
- **Five bosses** with 5 to 21 health, sliding back and forth along the bottom of the field under the pegs (so the ball has to come down through the pattern or thread a gap, and the boss is never the first thing the cannon hits), bouncing the ball back up: the Tin Drake speeds up as it weakens, the Bolt Golem raises a two-hit shield every third shot, the Gyro Spider jumps when hit, the Mechano-Boar charges and turns around when hit, the Cog Yeti heals after any shot that misses it. A health bar follows the boss.
- **Stars.** One to three stars a level by score (200k + 150 x level for two, 350k + 300 x level for three), shown on the side panel, under the result banner and on the level select with a running total.
- **Two new powers**: Pyramid (a ramp across the bottom bounces the ball back up, four bounces a shot, for three shots) and Chain Lightning (a bolt leaps from the green peg through six more pieces). Seven powers now cycle by chapter.
- **Space Blast is a much bigger explosion** (radius 140, up from 85) with a burst and a shockwave ring.
- **The day's plays.** Losing a level spends one of five free plays in a rolling 24 hours; clearing never does. Out of plays, the field is covered by a panel with the time to the next free play and a buy button. Five more plays for the day cost 10g by mail to the casino banker with "pachinko plays purchase" as the subject; the same mail flow as the casino (the form fills itself at a mailbox, the sender's own SendMail is hooked, MAIL_SEND_SUCCESS confirms), a **Buy Pachinko Plays** button on the mailbox, and `/pachinko plays` and `/pachinko buy`.
- **The plays vault.** The record is encrypted with a keyed stream cipher plus a keyed checksum and mirrored to the account SavedVariables, the per-character SavedVariables, the LibScrying satellite's file when present, and a client CVar when the client allows one. Copies are merged at login (union of fails), so deleting one changes nothing; an edited copy locks the day.
- **Placeholder art and sounds** for the new pieces (egg, gem, boss, crack, rim, star, pyramid, blast) and effects (clink, crack, hatch, gem, boss hit, boss down, zap, blast), generated by the tools, to be replaced by real assets under the same names.
- The multiplier now follows the share of the level's goal done (a boss by health lost), the result banner names the goal, and the score free balls and combos apply to every kind of level.

### Gnomish Pachinko v1.0.0

- **Gnomish Pachinko v1.0.0.** A peg-shooting puzzle game with 1000 generated levels in 100 chapters named for the places of Azeroth and Outland. Pegs and bricks, ten balls a level, light every orange peg to clear it and unlock the next. A purple bonus peg, a free-ball bucket, free balls at 25k, 75k and 125k points, and Fever with five scoring bins when the last orange peg lights.
- **Five powers** on the green pegs, one per chapter in turn: Multiball, Super Guide (the full bounce path for three shots), Space Blast, Fireball, Spooky Ball.
- **Gimmicks** from chapter 3, like the real thing: Slider, Lifts, Wheel, Twin Wheels, Pendulum, Blocks (solid, never light) and Sliding Block, one a level and sometimes two late on.
- **Touched pieces vanish two seconds after the touch**, while the ball is still flying, instead of waiting for it to drain.
- **Every level is a drawn pattern**, nothing random sprinkled on top: fifteen families (Brickwork, Rainbow, Diamonds, Rings, Zigzag, Brick Arcs, Brick Walls, Spiral, Waves, Hourglass, Honeycomb, Pillars, Chevrons, Castle, Star), each with a few variants. A gimmick that would gut a pattern is left off that level.
- **The field is 600 wide** so every pattern fits whole, and pieces may sit as close as the pattern draws them, even touching.
- **Clearing a level fires off every ball you had left**, in random directions, each scoring the bin it lands in.
- **Scores are higher**: pegs 25, oranges 250, the purple 1,000, and the multiplier climbs with the share of the level's oranges you have lit (x2 at a fifth, up to x10 at four fifths), so the free balls at 25k, 75k and 125k are within reach.
- **No pieces in the high corners** the launcher cannot reach.
- **Barriers and bumpers.** Gray bars are solid and never light; pink bumpers throw the ball back harder than they came. Two new gimmicks use them: Bumpers and Bumper Gate.
- **Combos.** Every piece lit in one shot rings a note higher (a C major scale over two octaves) and pays 15 more than the one before; chains of 10, 15, 20, 25 and 30 pay 5k, 10k, 20k, 50k and 100k.
- **Level select** with 100 levels a page, cleared levels in green and best scores under each number. `/pachinko`, `/pachinko levels`, `/pachinko <n>`, `/pachinko sound`, `/pachinko reset`.
