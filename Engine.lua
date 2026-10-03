--[[
    Gnomish Pachinko - Engine.lua
    The peg-shooter's physics and rules. Pure Lua, no frame API: UI.lua
    draws whatever this produces and tests/engine_test.py drives it headless.

    Field pixels, origin top-left, y grows DOWNWARD (the UI anchors every
    texture TOPLEFT at (x, -y)). The field is a portrait column, 490 by
    700, the proportions of Peggle Blast's board: the pegs sit in its
    upper two thirds and the ball has a long fall to the bucket.

    Pieces: round pegs and BRICKS (rotated rectangles). Both share the peg
    record: { shape, x, y, kind, hp, maxhp, lit, gone } with w/h/angle on
    bricks and an optional r on round ones.
    Kinds: blue (points), orange (goal), green (the level's power), purple
    (one bonus peg, moves every shot), egg (goal, three hits to hatch), gem
    (goal, knocked loose and caught in the bucket), boss (goal, a big
    piece with health sliding along the bottom under the pegs), block
    (solid, never lights) and bumper (solid, round, over-bouncy).

    Every hit takes one point of hp. A piece with hp 2 or 3 (a "tough"
    piece) cracks first and only lights on its last hit. A piece whose
    `goal` flag is set counts toward clearing the level; when the last goal
    is done, FEVER starts.

    A level: AIM (Aim/Guide, Launch on click) -> FLIGHT (Step) -> AIM when
    the ball drains, FEVER the moment the last goal is done -> OVER with
    state.result (cleared or out of balls). The only slow motion is the
    approach to the last goal piece; Fever runs at full speed while the
    leftover balls are fired at the bins.
]]

local GP = GnomishPachinko
GP.Engine = GP.Engine or {}
local E = GP.Engine

E.FIELD_W, E.FIELD_H = 490, 700
E.BALL_R      = 7
E.PEG_R       = 9
E.EGG_R       = 22          -- eggs and gems are loose bodies, much bigger than pegs
E.GEM_R       = 20
E.BOSS_R      = 26
E.BRICK_W     = 30
E.BRICK_H     = 11
-- The launcher slides round the rim of the host's round box, which hangs
-- over the top of the field: the muzzle is LAUNCH_R from the box's centre
-- (W / 2, LAUNCH_CY) in the aim's direction. The window sizes the box to
-- match (LAUNCH_R less the barrel).
E.LAUNCH_CY   = -10
E.LAUNCH_R    = 136
E.LAUNCHER_Y  = E.LAUNCH_CY
E.PEG_TOP     = 150         -- the pattern zone, in field pixels (Levels maps its 600-wide design space into it)
E.PEG_BOTTOM  = 480
E.PEG_MARGIN  = 27
E.PEG_GAP     = 40          -- centre distance round peg to round peg

E.GRAVITY      = 1000
E.LAUNCH_SPEED = 600
E.RESTITUTION  = 0.70
E.STEP         = 1 / 120
E.MAX_AIM_DEG  = 82
E.STUCK_SPEED  = 35
E.STUCK_SECS   = 1.5
E.MAX_FLIGHT   = 25         -- seconds a ball may stay in play
E.LIT_SECS     = 2.0        -- a lit piece vanishes this long after the hit
E.HIT_COOLDOWN = 0.2        -- one ball cannot hit the same piece twice within this
E.BOSS_COOLDOWN = 0.05      -- a boss counts every real strike, even three in a quick bank shot

E.BUCKET_W     = 64
E.BUCKET_H     = 16
E.BUCKET_SPEED = 175
E.FEVER_FIRST_GAP = 0.8    -- after the last piece lights, the leftover balls start firing this soon
-- The last goal piece: when a ball closes in on it, time slows and the
-- window zooms in on it (Peggle Blast's last-peg moment).
E.LAST_SLOWMO     = 0.22
E.LAST_LOOKAHEAD  = 0.35     -- seconds of flight predicted; a path that finishes the goal starts it
E.LAST_LOOKAHEAD2 = 0.6      -- when two goal hits remain (a close call: both in one swoop)
E.LAST_MAX_HITS   = 2        -- the slow-mo is on the table once this few goal hits remain
E.LAST_LEAVE      = 170      -- it ends when no ball is within this
E.LAST_MAX_SECS   = 2.0      -- of slowed time, then it waits for the ball to leave and return
E.LAST_ZOOM       = 1.8
-- Fever: the five G-N-O-M-E buckets; light all five and the GNOME bonus
-- pays out and every bucket is worth GNOME_BUCKET from then on.
E.FEVER_BINS    = { 1000, 10000, 25000, 10000, 1000 }
E.FEVER_LETTERS = { "G", "N", "O", "M", "E" }
E.GNOME_BONUS   = 100000
E.GNOME_BUCKET  = 25000
E.BUCKET_DROP   = 10000     -- a gem that lands in the bucket, on top of counting
E.STYLE_POINTS  = 5000      -- a trick shot: a Long Shot, a Super Slide
E.LONG_SHOT     = 220       -- two orange pegs at least this far apart in one shot
E.SLIDE_RATIO   = 0.42      -- a brick contact this grazing slides instead of bouncing
E.SLIDE_RUN     = 6         -- bricks lit in one slide for the Super Slide award
E.SLIDE_GAP     = 0.3       -- seconds between two slid bricks that still count as one slide
E.FEVER_SHOT_GAP = 0.3     -- seconds between the leftover balls fired at the clear
E.FREE_BALL_SCORES = { 75000, 200000 }

E.BALLS       = 10
-- points for the hit that lights a piece (times the multiplier)
E.PEG_POINTS  = { blue = 25, orange = 250, green = 25, purple = 1000, egg = 500, gem = 1000, boss = 5000 }
-- points for a hit that only cracks a tough piece, an egg or the boss
E.CHIP_POINTS = { blue = 10, orange = 50, green = 10, purple = 10, egg = 100, boss = 500 }
E.BLAST_RADIUS = 45         -- about an inch on screen
E.GUIDE_SHOTS = 3
E.CHAIN_LINKS = 6           -- Chain Lightning: pieces after the green one
E.CHAIN_REACH = 120
E.PYRAMID_STRIKES = 3       -- a step pyramid over the bucket stands for this many strikes
E.PYRAMID_SOLID   = 0.84    -- share of its half-width that is stone: the bare corners past the bottom step let a ball fall
E.PYRAMID_SIDE    = 260     -- the ball leaves it at least this fast toward the wall on its side
E.PYRAMID_W       = E.FIELD_W  -- base width: the whole bottom, nothing drops past it
E.PYRAMID_H       = 122     -- base to the tip of its peak
E.PYRAMID_BASE    = E.FIELD_H - 2
-- ... and at least this fast upward: enough to climb from its foot to the
-- middle of the board
E.PYRAMID_KICK    = math.ceil(math.sqrt(2 * E.GRAVITY * (E.PYRAMID_BASE - E.FIELD_H / 2)) * 1.04)

-- Combos: every piece lit in one shot adds COMBO_STEP x (hits so far)
-- to its points, and long chains pay a bonus at these lengths.
E.COMBO_STEP  = 15
E.COMBO_BONUS = { [10] = 5000, [15] = 10000, [20] = 20000, [25] = 50000, [30] = 100000 }

-- Bumpers: round, never light, and throw the ball back harder than it
-- came (bounce above 1), with a floor on the outgoing speed.
E.BUMPER_R      = 15
E.BUMPER_BOUNCE = 1.3
E.BUMPER_KICK   = 260

-- The boss: a big round piece that slides along a band at the BOTTOM of
-- the field, under the pattern, so the ball has to find its way down
-- through the pegs (or thread a gap) to reach it. It bounces like a
-- bumper so the ball comes back up for more.
E.BOSS_BOUNCE = 1.0
E.BOSS_KICK   = 220
E.BOSS_BAND   = { y0 = 590, y1 = 700, y = 640 }     -- in Levels' design space: below the pattern zone, above the bucket
E.SCRAP_R        = 11        -- a boss's scrap block
E.SCRAP_PER_SHOT = 2         -- thrown after a shot that hit it
E.SCRAP_MAX      = 6         -- on the board at once
E.SCRAP_PER_SHOT_DRAKE = 2   -- the Tin Drake throws after every shot ...
E.SCRAP_MAX_DRAKE      = 40  -- ... up to this many
E.SCRAP_ROW1           = 5   -- the Drake's first row: blocks in its middle before it takes the ends and climbs
E.SCRAP_ROW_GAP        = 34  -- between the Drake's rows of scrap
E.WEB_R          = 13        -- a Gyro Spider web
E.WEB_PER_SHOT   = 2         -- spun after every shot ...
E.WEB_MAX        = 10        -- ... up to this many on the board
E.WEB_CLEAR      = 14        -- the gap kept between a web and any piece
E.SCRAP_COL_W    = 44        -- scrap sits on columns this wide (a ball passes between neighbours)
E.SCRAP_FREE_COLS = 3        -- columns always left empty: scrap is never a wall
E.GOLEM_SHIELD = 2
E.GOLEM_EVERY  = 3

E.PHASE = { AIM = "AIM", FLIGHT = "FLIGHT", FEVER = "FEVER", OVER = "OVER" }

-- The green-peg powers, unlocked one per chapter then cycled.
E.POWERS = {
    { id = "multiball", name = "Multiball",       blurb = "The ball splits in two." },
    { id = "guide",     name = "Super Guide",     blurb = "See the whole bounce path for three shots." },
    { id = "blast",     name = "Space Blast",     blurb = "A huge explosion hits every piece near the green one." },
    { id = "fireball",  name = "Fireball",        blurb = "The ball burns straight through pegs." },
    { id = "spooky",    name = "Spooky Ball",     blurb = "A lost ball comes back in from the top." },
    { id = "pyramid",   name = "Pyramid",         blurb = "A step pyramid over the bucket throws the ball back up toward the walls, for three strikes." },
    { id = "lightning", name = "Chain Lightning", blurb = "A bolt leaps from the green peg through six more pieces." },
    { id = "frenzy",    name = "Free Ball Frenzy", blurb = "Three extra balls and 5,000 points on the spot." },
}
E.FRENZY_BALLS  = 3
E.FRENZY_POINTS = 5000

-- Power-ups carried into a shot (armed from the side panel, earned by
-- clearing levels): the first piece the ball hits also hits everything
-- within the radius. Extra Green Peg is a pre-level boost: one more
-- green peg on the board.
E.ITEMS = {
    ring    = { name = "Ring of Fire",    radius = 70,  blurb = "The next shot's first hit also hits every piece in a small ring." },
    rainbow = { name = "Rainbow Ball",    radius = 150, blurb = "The next shot's first hit also hits every piece in a wide ring." },
    green   = { name = "Extra Green Peg", blurb = "Start the level with one more green peg." },
    suction = { name = "Suction Tube",    blurb = "For the next shot the bucket's tube draws a falling ball toward it." },
}
E.SUCTION_REACH = 340       -- the tube draws on a falling ball this close above the floor ...
E.SUCTION_SIDE  = 230       -- ... and this close to either side of it
E.SUCTION_PULL  = 3000      -- how hard it can bend the ball's sideways speed, pixels a second squared

-- What a level asks of you.
E.OBJECTIVES = {
    classic = { name = "Classic", goalWord = "orange pegs", text = "Light every orange peg" },
    eggs    = { name = "Eggs",    goalWord = "eggs",        text = "Hatch every egg: three hits each" },
    gems    = { name = "Gems",    goalWord = "gems",        text = "Knock every gem loose and catch it in the bucket" },
    mixed_eggs = { name = "Oranges and Eggs", goalWord = "goals", text = "Light the orange pegs and hatch the eggs" },
    mixed_gems = { name = "Oranges and Gems", goalWord = "goals", text = "Light the orange pegs and drop the gems" },
    boss    = { name = "Boss",    goalWord = "boss health", text = "Beat the boss: hit it until its health is gone" },
    duel    = { name = "Duel",    goalWord = "orange pegs", text = "Light every orange peg while the boss takes its turns" },
    longshots = { name = "Long Shots", goalWord = "long shots", text = "Make Long Shots: light two orange pegs far apart in one shot" },
}
E.PLAY_ON_BALLS = 3         -- a continue after running out of balls
E.PHOENIX_POINTS = 5000     -- an egg saved in the bucket
-- Loose pieces (eggs and gems) are bodies: gravity pulls them, the bricks
-- of their cradle hold them up, and they roll when a ball or a blast
-- nudges them. A gem counts when it leaves the bottom of the board, an
-- egg is lost there (the bucket saves either).
E.LOOSE_GRAVITY     = 900
E.LOOSE_RESTITUTION = 0.15
E.LOOSE_DRAG        = 0.9       -- rolling drag: share of the tangent speed lost per second of contact
E.LOOSE_SLEEP       = 10        -- slower than this ...
E.LOOSE_SLEEP_SECS  = 0.25      -- ... for this long while touching something: at rest
E.LOOSE_NUDGE       = { egg = 0.08, gem = 0.26 }  -- share of the ball's speed a hit passes on (a gem lighter than an egg)
E.LOOSE_TIP         = 260       -- balanced on a single point, a piece tips off it this hard (pixels a second squared)
-- A hatched egg's phoenix flies straight up off the board, lighting every
-- piece in a column twice the egg's width.
E.PHOENIX_SPEED     = 520
E.PHOENIX_HALF      = 2 * 22    -- half the column's width (the egg is 44 across)
E.LOOSE_BLAST_KICK  = 260       -- a Space Blast throws loose pieces away from it

-- The duel: no piece to hit. Stage one is a board to clear; then the
-- rival steps up and the two of you shoot turn and turn about on one
-- shared board, DUEL_BALLS each. Whoever lights the last orange wins the
-- duel there and then, keeping every point of that shot; if the balls run
-- out first, the higher duel score wins. No Fever and no end bonus in a
-- duel. A shot that lights no orange costs its shooter DUEL_PENALTY.
E.RIVAL = { id = "cogwhistle", name = "Cogwhistle Overspark",
    blurb = "Tinkmaster's older brother. Clear the board, then duel him: five balls each, turn and turn about. Whoever lights the last orange wins; otherwise the higher score. A shot that lights no orange costs 500." }
E.DUEL_BALLS   = 5
E.DUEL_PENALTY = 500         -- a shot that lights no orange costs this, the ball's own points stand
E.DUEL_STAGE2_ORANGES = 10
E.RIVAL_THINK  = 1.4        -- seconds the rival shows his aim before firing
E.STYLE_TIERS  = { { run = 20, points = 25000, caption = "UNBELIEVABLE!" }, { run = 12, points = 12500, caption = "AWESOME!" }, { run = 6, points = 5000, caption = "NICE!" } }
E.AIM_SWING    = 5.0        -- radians a second the launcher swings toward the cursor

-- The bosses, one kind per chapter in turn. `ability` is what Engine does
-- with it; the names and blurbs are for the panel.
E.BOSSES = {
    { id = "drake",  name = "Tin Drake",    blurb = "Speeds up as it weakens.",                         speed = 0.6 },
    { id = "golem",  name = "Bolt Golem",   blurb = "Raises a two-hit shield every third shot.",        speed = 0.7 },
    { id = "spider", name = "Gyro Spider",  blurb = "Jumps when hit, and spins webs after every shot: a ball that touches one is caught with it.", speed = 1.0 },
    { id = "boar",   name = "Mechano-Boar", blurb = "Charges fast and turns around when hit.",          speed = 1.8 },
    { id = "yeti",   name = "Cog Yeti",     blurb = "Heals one point after any shot that misses it.",   speed = 0.8 },
}

local W, H = E.FIELD_W, E.FIELD_H
local sin, cos, sqrt, floor, abs = math.sin, math.cos, math.sqrt, math.floor, math.abs
local atan2 = math.atan2 or math.atan
local pi = math.pi

-- The multiplier climbs with the share of the level's goal already done:
-- x2 from a fifth, x3 from two fifths, x5 from three, x10 from four.
-- Takes a fraction, or (done, total).
function E:ScoreMultiplier(done, total)
    local f = done
    if total then f = done / math.max(1, total) end
    if f >= 0.8 then return 10 end
    if f >= 0.6 then return 5 end
    if f >= 0.4 then return 3 end
    if f >= 0.2 then return 2 end
    return 1
end

-- How far along the level's goal is, 0..1. A boss counts by health lost.
function E:Progress(state)
    local b = state.boss
    if b then return (b.maxhp - math.max(0, b.hp)) / math.max(1, b.maxhp) end
    return state.goalHit / math.max(1, state.goalTotal)
end

-- Park-Miller, warmed up so small seeds differ from the first draw.
function E.NewRng(seed)
    local s = floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local function rng(lo, hi)
        s = (s * 48271) % 2147483647
        local r = (s - 1) / 2147483646
        if lo then return lo + floor(r * (hi - lo + 1)) end
        return r
    end
    for _ = 1, 8 do rng() end
    return rng
end

-- ---------------------------------------------------------------------
-- Geometry helpers shared by the simulation and the guide

-- Closest point on a peg's surface to (x, y): returns penetration depth
-- (positive when the ball overlaps) and the outward normal.
local function pegContact(p, x, y, R)
    if p.shape == "brick" then
        local c, s = cos(p.angle), sin(p.angle)
        local dx, dy = x - p.x, y - p.y
        -- into the brick's frame
        local lx = dx * c + dy * s
        local ly = -dx * s + dy * c
        local hw, hh = p.w / 2, p.h / 2
        local cx = lx < -hw and -hw or (lx > hw and hw or lx)
        local cy = ly < -hh and -hh or (ly > hh and hh or ly)
        local ex, ey = lx - cx, ly - cy
        local d2 = ex * ex + ey * ey
        if d2 > R * R then return nil end
        local nx, ny, depth
        if d2 > 0.000001 then
            local d = sqrt(d2)
            nx, ny = ex / d, ey / d
            depth = R - d
        else
            -- centre inside the brick: push out through the nearest face
            local px, py = hw - abs(lx), hh - abs(ly)
            if px < py then nx, ny = (lx < 0) and -1 or 1, 0; depth = R + px
            else nx, ny = 0, (ly < 0) and -1 or 1; depth = R + py end
        end
        -- back to field frame
        return depth, nx * c - ny * s, nx * s + ny * c
    else
        local dx, dy = x - p.x, y - p.y
        local rr = R + (p.r or E.PEG_R)
        local d2 = dx * dx + dy * dy
        if d2 >= rr * rr then return nil end
        local d = sqrt(d2)
        if d < 0.0001 then return rr, 0, -1 end
        return rr - d, dx / d, dy / d
    end
end
E.PegContact = pegContact

-- Solid pieces never light: barriers and bumpers.
local function isSolid(p) return p.kind == "block" or p.kind == "bumper" or p.kind == "web" end
E.IsSolid = isSolid

-- Bounding radius used for spacing checks.
local function pegRadius(p)
    if p.shape == "brick" then return sqrt(p.w * p.w + p.h * p.h) / 2 end
    return p.r or E.PEG_R
end
E.PegRadius = pegRadius


-- ---------------------------------------------------------------------
-- State

-- spec: from Levels. pegs carry kind/hp/goal; movers drive the gimmicks.
function E:NewLevel(spec)
    local state = {
        level = spec.level,
        chapter = spec.chapter,
        name = spec.name,
        title = spec.title,
        seed = spec.seed,
        layout = spec.layout,
        objective = spec.objective or "classic",
        pegs = spec.pegs,
        movers = spec.movers or {},
        gimmick = spec.gimmick,
        goalTotal = spec.goal or spec.orange or 0,
        goalLeft = spec.goal or spec.orange or 0,
        goalHit = 0,
        goalHitThisShot = 0,
        shotHits = 0,
        shotPegs = 0,
        shotPoints = 0,
        shotGoals = {},
        shotStyles = {},
        binsLit = {},
        gnomeBonus = false,
        noBucket = spec.noBucket or false,
        duel = spec.duel and { name = spec.duel.name, blurb = spec.duel.blurb, stage = spec.duel.stage or 1,
            turn = "you", balls = { you = 0, rival = 0 }, scores = { you = 0, rival = 0 } } or nil,
        power = spec.power,
        balls = {},
        ballsLeft = spec.balls or E.BALLS,
        ballsFired = 0,
        shots = 0,
        score = 0,
        combo = 0,
        bestCombo = 0,
        freeBallIdx = 1,
        superGuide = 0,
        pyramidHits = 0,
        lastSlow = false,
        lastPeg = nil,
        lastSpent = 0,
        bossHitThisShot = false,
        phase = E.PHASE.AIM,
        aim = 0,
        time = 0,
        acc = 0,
        bucket = { x = W / 2, dir = 1 },
        feverBin = nil,
        result = nil,
        rng = E.NewRng((spec.seed or 1) + 977),
    }
    for _, p in ipairs(state.pegs) do
        p.maxhp = p.maxhp or p.hp or 1
        p.hp = p.maxhp
        p.lit, p.gone, p.freed, p.collected = false, false, false, false
        p.cooldown, p.shield = nil, 0
        if p.kind == "boss" then state.boss = p end
        if p.loose then
            state.hasLoose = true
            p.vx, p.vy, p.resting, p.settling = 0, 0, false, true
        end
    end
    for _, mv in ipairs(state.movers) do
        for _, p in ipairs(mv.pegs) do p.mover = mv end
    end
    self:MovePurple(state)
    self:UpdateMovers(state)
    return state
end

-- Moving pieces (the gimmicks): each mover drives a group of pegs from
-- their base positions (bx, by, bangle). slide moves along x, lift along
-- y, wheel turns steadily about (cx, cy), swing rocks about it.
function E:UpdateMovers(state)
    local t = state.time
    for _, mv in ipairs(state.movers) do
        -- where each piece was, so a loose piece resting on it is carried
        for _, p in ipairs(mv.pegs) do p.px, p.py = p.x, p.y end
        if mv.kind == "slide" or mv.kind == "lift" then
            local off = mv.amp * sin(mv.speed * t + (mv.phase or 0))
            for _, p in ipairs(mv.pegs) do
                if mv.kind == "slide" then p.x = p.bx + off else p.y = p.by + off end
            end
        else
            local th
            if mv.kind == "wheel" then th = mv.speed * t + (mv.phase or 0)
            else th = mv.amp * sin(mv.speed * t + (mv.phase or 0)) end
            local c, s = cos(th), sin(th)
            for _, p in ipairs(mv.pegs) do
                local dx, dy = p.bx - mv.cx, p.by - mv.cy
                p.x = mv.cx + dx * c - dy * s
                p.y = mv.cy + dx * s + dy * c
                if p.shape == "brick" then p.angle = (p.bangle or 0) + th end
            end
        end
    end
end

-- Change a mover's speed without the piece jumping: keep the phase angle
-- continuous at this instant.
local function setMoverSpeed(mv, t, speed)
    local arg = mv.speed * t + (mv.phase or 0)
    mv.phase = arg - speed * t
    mv.speed = speed
end
E.SetMoverSpeed = setMoverSpeed

-- The purple bonus peg hops to a fresh unlit blue peg before every shot.
function E:MovePurple(state)
    local pool = {}
    for _, p in ipairs(state.pegs) do
        if p.kind == "purple" and not p.lit and not p.gone then p.kind = "blue" end
    end
    for _, p in ipairs(state.pegs) do
        if p.kind == "blue" and not p.lit and not p.gone then pool[#pool + 1] = p end
    end
    if #pool > 0 then pool[state.rng(1, #pool)].kind = "purple" end
end

local function clampAim(a)
    local lim = E.MAX_AIM_DEG * pi / 180
    if a > lim then return lim end
    if a < -lim then return -lim end
    return a
end

-- The angle that points the launcher at (tx, ty), without setting it.
function E:AimAngle(tx, ty)
    local dx, dy = tx - W / 2, ty - E.LAUNCHER_Y
    if dx == 0 and dy <= 0 then return nil end
    return clampAim(atan2(dx, dy))
end

function E:Aim(state, tx, ty)
    local dx, dy = tx - W / 2, ty - E.LAUNCHER_Y
    if dx == 0 and dy <= 0 then return state.aim end
    state.aim = clampAim(atan2(dx, dy))
    return state.aim
end

local function muzzle(a)
    return W / 2 + sin(a) * E.LAUNCH_R, E.LAUNCH_CY + cos(a) * E.LAUNCH_R
end
function E:MuzzlePos(state)
    return muzzle(state.aim or 0)
end

local function firstContact(state, x, y)
    for _, p in ipairs(state.pegs) do
        if not p.gone and pegContact(p, x, y, E.BALL_R) then return p end
    end
    return nil
end

-- Short guide: free flight to the first peg. Returns points and that peg.
function E:Guide(state, maxT, every)
    maxT, every = maxT or 0.9, every or 0.045
    local pts = {}
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    local vx, vy = sin(a) * E.LAUNCH_SPEED, cos(a) * E.LAUNCH_SPEED
    local t, nextSample = 0, every
    local dt = E.STEP
    local first
    while t < maxT do
        vy = vy + E.GRAVITY * dt
        x, y = x + vx * dt, y + vy * dt
        if x < E.BALL_R then x = E.BALL_R; vx = -vx * E.RESTITUTION end
        if x > W - E.BALL_R then x = W - E.BALL_R; vx = -vx * E.RESTITUTION end
        if y > H then break end
        first = firstContact(state, x, y)
        if first then
            -- back off to the moment the ball's edge touches the piece:
            -- halve the last step until the ball sits just outside it
            local px, py = x - vx * dt, y - vy * dt
            local lo, hi = 0, 1
            for _ = 1, 10 do
                local mid = (lo + hi) / 2
                if firstContact(state, px + (x - px) * mid, py + (y - py) * mid) then hi = mid else lo = mid end
            end
            x, y = px + (x - px) * lo, py + (y - py) * lo
            break
        end
        t = t + dt
        if t >= nextSample then
            pts[#pts + 1] = { x = x, y = y }
            nextSample = nextSample + every
        end
    end
    return pts, first, x, y      -- the piece the ball first meets, and where the ball is then
end

local collideBall  -- forward
local looseMoving, loosePhysics  -- forward

-- Super Guide: the real bounce path (pegs unchanged) for up to maxT seconds.
-- Super Guide's two levels: the path through three bounces, and through
-- six when it is earned again while still running.
E.GUIDE_BOUNCES = { 3, 6 }

function E:Simulate(state, maxT, every, maxBounces)
    maxT, every = maxT or 4, every or 0.04
    local pts = {}
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    local ball = { x = x, y = y, vx = sin(a) * E.LAUNCH_SPEED, vy = cos(a) * E.LAUNCH_SPEED, slow = 0 }
    local t, nextSample = 0, every
    local dt = E.STEP
    local bounces, lastBounce
    while t < maxT do
        ball.vy = ball.vy + E.GRAVITY * dt
        ball.x = ball.x + ball.vx * dt
        ball.y = ball.y + ball.vy * dt
        if ball.x < E.BALL_R then ball.x = E.BALL_R; if ball.vx < 0 then ball.vx = -ball.vx * E.RESTITUTION end end
        if ball.x > W - E.BALL_R then ball.x = W - E.BALL_R; if ball.vx > 0 then ball.vx = -ball.vx * E.RESTITUTION end end
        if ball.y < E.BALL_R then ball.y = E.BALL_R; if ball.vy < 0 then ball.vy = -ball.vy * E.RESTITUTION end end
        local ux, uy = ball.vx, ball.vy
        collideBall(state, ball, nil, false)
        if ball.y - E.BALL_R > H then break end
        t = t + dt
        -- a bounce off a piece (not a wall): the velocity turned sharply
        if maxBounces and (ux ~= ball.vx or uy ~= ball.vy) then
            local before = sqrt(ux * ux + uy * uy)
            local after = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
            local cosT = (before > 0 and after > 0) and (ux * ball.vx + uy * ball.vy) / (before * after) or 1
            if cosT < 0.97 and t - (lastBounce or -1) > 0.06 then
                bounces = (bounces or 0) + 1
                lastBounce = t
                if bounces >= maxBounces then
                    pts[#pts + 1] = { x = ball.x, y = ball.y }
                    break
                end
            end
        end
        if t >= nextSample then
            pts[#pts + 1] = { x = ball.x, y = ball.y }
            nextSample = nextSample + every
        end
    end
    return pts, bounces or 0
end

function E:CanLaunch(state)
    return state.phase == E.PHASE.AIM and state.ballsLeft > 0
end

local push  -- forward

function E:Launch(state, events)
    if not self:CanLaunch(state) then return false end
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    state.balls[#state.balls + 1] = {
        x = x, y = y,
        vx = sin(a) * E.LAUNCH_SPEED, vy = cos(a) * E.LAUNCH_SPEED,
        slow = 0,
        ring = state.armed and E.ITEMS[state.armed] and E.ITEMS[state.armed].radius or nil,
        suction = state.armed == "suction" or nil,
        item = state.armed,
    }
    state.suctionShot = state.armed == "suction"     -- every ball of this shot, twins included
    if state.armed then push(events, { type = "item_used", item = state.armed }) end
    state.armed = nil
    state.ballsLeft = state.ballsLeft - 1
    state.ballsFired = state.ballsFired + 1
    state.shots = state.shots + 1
    state.combo = 0
    state.goalHitThisShot = 0
    state.shotHits = 0
    state.shotBucket = false
    state.shotPegs = 0
    state.shotPoints = 0
    state.shotGoals = {}
    state.shotStyles = {}
    state.bossHitThisShot = false
    if state.superGuide > 0 then
        state.superGuide = state.superGuide - 1
        if state.superGuide == 0 then state.guideLevel = nil end
    end
    -- the Bolt Golem shields itself every third shot
    local b = state.boss
    if b and not b.lit and b.ability == "golem" and state.shots % E.GOLEM_EVERY == 0 then
        b.shield = E.GOLEM_SHIELD
        push(events, { type = "boss_shield", x = b.x, y = b.y })
    end
    state.phase = E.PHASE.FLIGHT
    return true
end

-- ---------------------------------------------------------------------
-- Simulation

push = function(events, ev)
    if events then events[#events + 1] = ev end
end

local function addScore(state, pts, events, notDuel)
    local d = state.duel
    if d and d.stage == 2 and not notDuel then
        d.scores[d.turn] = d.scores[d.turn] + pts
        if d.turn ~= "you" then return end       -- the rival's points are his alone
    end
    state.score = state.score + pts
    local threshold = E.FREE_BALL_SCORES[state.freeBallIdx]
    while threshold and state.score >= threshold do
        state.ballsLeft = state.ballsLeft + 1
        push(events, { type = "freeball_score", score = threshold })
        state.freeBallIdx = state.freeBallIdx + 1
        threshold = E.FREE_BALL_SCORES[state.freeBallIdx]
    end
end

local hitPeg, lightPeg, applyPower, nudgeLoose, bossReact

applyPower = function(state, p, ball, events)
    local power = state.power
    if power == "multiball" and ball then
        state.balls[#state.balls + 1] = {
            x = ball.x, y = ball.y, vx = -ball.vx, vy = ball.vy, slow = 0,
            fire = ball.fire, spooky = ball.spooky,
        }
    elseif power == "guide" then
        -- earned again while it runs: the longer guide, and more shots of it
        state.guideLevel = (state.superGuide > 0) and 2 or math.max(1, state.guideLevel or 1)
        state.superGuide = state.superGuide + E.GUIDE_SHOTS
    elseif power == "blast" then
        local r2 = E.BLAST_RADIUS * E.BLAST_RADIUS
        for _, q in ipairs(state.pegs) do
            if not q.lit and not q.gone and q ~= p then
                local dx, dy = q.x - p.x, q.y - p.y
                local d2 = dx * dx + dy * dy
                if q.loose then
                    -- loose pieces are thrown away from the blast
                    local reach = E.BLAST_RADIUS + (q.r or E.PEG_R)
                    if d2 <= reach * reach then
                        local d = sqrt(d2)
                        if d < 1 then dx, dy, d = 0, -1, 1 end
                        nudgeLoose(q, dx / d * E.LOOSE_BLAST_KICK, dy / d * E.LOOSE_BLAST_KICK)
                    end
                elseif d2 <= r2 then
                    hitPeg(state, q, nil, events, true)
                end
            end
        end
    elseif power == "fireball" and ball then
        ball.fire = true
    elseif power == "spooky" and ball then
        ball.spooky = (ball.spooky or 0) + 1
    elseif power == "frenzy" then
        state.ballsLeft = state.ballsLeft + E.FRENZY_BALLS
        addScore(state, E.FRENZY_POINTS, events)
    elseif power == "pyramid" then
        state.pyramidHits = E.PYRAMID_STRIKES
    elseif power == "lightning" then
        local path = { { x = p.x, y = p.y } }
        local used = { [p] = true }
        local cur = p
        local reach2 = E.CHAIN_REACH * E.CHAIN_REACH
        for _ = 1, E.CHAIN_LINKS do
            local best, bd = nil, reach2
            for _, q in ipairs(state.pegs) do
                if not used[q] and not q.lit and not q.gone and not isSolid(q) then
                    local dx, dy = q.x - cur.x, q.y - cur.y
                    local d2 = dx * dx + dy * dy
                    if d2 <= bd then best, bd = q, d2 end
                end
            end
            if not best then break end
            used[best] = true
            hitPeg(state, best, nil, events, true)
            path[#path + 1] = { x = best.x, y = best.y }
            cur = best
        end
        push(events, { type = "zap", path = path })
    end
    push(events, { type = "power", power = power, x = p.x, y = p.y })
end

-- Fever: the goal is done, the bottom becomes the five cups, and an
-- inflated balloon rests on the floor at each cup boundary. It is a
-- bumper: the bounce follows the vector the ball strikes the sphere on,
-- and the kick puts energy back into the ball, so a ball either drops
-- into a cup or is thrown back up.
E.FEVER_BALLOON_R = 16
E.BALLOON_BOUNCE  = 1.05     -- a balloon gives back a little more than it takes ...
E.BALLOON_KICK    = 150      -- ... and never sends the ball off slower than this (a bumper: 1.3 and 260)
E.FEVER_POST_R = E.FEVER_BALLOON_R
E.FEVER_TUBE_H  = 72         -- the Fever tubes stand this tall off the floor ...
E.FEVER_POST_Y  = H - E.FEVER_TUBE_H   -- ... and the balloons' centres are level with their tops
local function startFever(state, events)
    state.phase = E.PHASE.FEVER
    state.lastSlow = false
    state.feverTotal = 0
    state.feverNext = state.time + E.FEVER_FIRST_GAP
    local binW = W / #E.FEVER_BINS
    for i = 0, #E.FEVER_BINS do
        state.pegs[#state.pegs + 1] = { shape = "peg", x = i * binW, y = E.FEVER_POST_Y, r = E.FEVER_BALLOON_R,
            kind = "bumper", post = true, balloon = true, bounce = E.BALLOON_BOUNCE, kick = E.BALLOON_KICK }
    end
    push(events, { type = "fever" })
end

local function spawnPhoenix(state, x, y, events)
    state.phoenixes = state.phoenixes or {}
    state.phoenixes[#state.phoenixes + 1] = { x = x, y = y }
    push(events, { type = "phoenix", x = x, y = y })
end

-- The phoenixes climb; every piece in a phoenix's column lights (a tough
-- piece gives way at once). Solid pieces and loose ones are left alone.
local function phoenixFlight(state, dt, events)
    local list = state.phoenixes
    if not list or #list == 0 then return end
    for i = #list, 1, -1 do
        local f = list[i]
        f.y = f.y - E.PHOENIX_SPEED * dt
        for _, q in ipairs(state.pegs) do
            if not q.gone and not q.lit and not isSolid(q) and not q.loose
                and abs(q.x - f.x) <= E.PHOENIX_HALF and q.y <= f.y + 10 and q.y >= f.y - 30 then
                q.hp = 1
                q.cooldown = nil
                hitPeg(state, q, nil, events, true)
            end
        end
        if f.y < -60 then table.remove(list, i) end
    end
end
E.PhoenixFlight = phoenixFlight

-- A push on a loose piece: it wakes and rolls.
nudgeLoose = function(p, dvx, dvy)
    p.vx = (p.vx or 0) + dvx
    p.vy = (p.vy or 0) + dvy
    p.resting = false
end

-- What a boss does when it takes a point of damage.
bossReact = function(state, p, events)
    local mv = p.mover
    if p.ability == "drake" and mv then
        local dir = mv.speed < 0 and -1 or 1
        setMoverSpeed(mv, state.time, dir * (0.6 + 1.0 * (1 - p.hp / p.maxhp)))
    elseif p.ability == "spider" then
        p.bx = 100 + state.rng() * (W - 200)
        push(events, { type = "boss_hop", x = p.x, y = p.y })
    elseif p.ability == "boar" and mv then
        setMoverSpeed(mv, state.time, -mv.speed)
    end
end

-- A trick shot pays style points, once per kind (and tier) per shot.
local function style(state, name, events, x, y, points, caption)
    points = points or E.STYLE_POINTS
    local key = name .. points
    if state.shotStyles[key] then return end
    state.shotStyles[key] = true
    addScore(state, points, events)
    push(events, { type = "style", name = name, points = points, caption = caption or "NICE!", x = x, y = y })
end

-- A key lit: every piece locked to it dissolves.
local function unlock(state, key, events)
    local n = 0
    for _, q in ipairs(state.pegs) do
        if q.lock and q.lock == key.unlocks and not q.gone then
            q.gone = true
            q.goneAt = state.time
            q.lit = true
            n = n + 1
        end
    end
    push(events, { type = "unlock", lock = key.unlocks, count = n, x = key.x, y = key.y })
end

-- One hit on a piece: a shield soaks it, a tough piece cracks, the last
-- point of hp lights it. Returns true when the hit counted.
hitPeg = function(state, p, ball, events, quiet)
    if p.lit or p.gone or isSolid(p) then return false end
    if p.cooldown and state.time < p.cooldown then return false end
    if p.loose then
        -- the ball shoves a loose piece; a gem is never lit by a hit, only
        -- by leaving the board. An egg takes the hit as well.
        if ball then
            local k = E.LOOSE_NUDGE[p.kind] or 0.2
            nudgeLoose(p, ball.vx * k, ball.vy * k)
        end
        if p.kind == "gem" then return false end
    end
    p.cooldown = state.time + ((p.kind == "boss") and E.BOSS_COOLDOWN or E.HIT_COOLDOWN)
    state.shotHits = state.shotHits + 1
    if p.kind == "boss" then state.bossHitThisShot = true end
    if (p.shield or 0) > 0 then
        p.shield = p.shield - 1
        p.crackAt = state.time
        push(events, { type = "shield", peg = p, x = p.x, y = p.y, left = p.shield })
        return true
    end
    p.hp = (p.hp or 1) - 1
    if p.hp > 0 then
        p.crackAt = state.time
        local pts = (E.CHIP_POINTS[p.kind] or 10) * E:ScoreMultiplier(E:Progress(state))
        addScore(state, pts, events)
        push(events, { type = "crack", peg = p, points = pts, x = p.x, y = p.y, hp = p.hp, quiet = quiet })
        if p.kind == "boss" then bossReact(state, p, events) end
        return true
    end
    lightPeg(state, p, ball, events, quiet)
    return true
end
E.HitPeg = function(state, p, ball, events, quiet) return hitPeg(state, p, ball, events, quiet) end

-- `at` overrides where the event reports the hit (a gem lights at the bucket).
lightPeg = function(state, p, ball, events, quiet, at)
    p.lit = true
    p.hitAt = state.time
    state.combo = state.combo + 1
    if state.combo > state.bestCombo then state.bestCombo = state.combo end
    if p.goal then
        state.goalHit = state.goalHit + 1
        state.goalLeft = state.goalLeft - 1
        state.goalHitThisShot = state.goalHitThisShot + 1
    end
    -- a Long Shot: this orange and an earlier one of the shot, far apart
    if p.kind == "orange" then
        for _, g in ipairs(state.shotGoals) do
            local dx, dy = g.x - p.x, g.y - p.y
            if dx * dx + dy * dy >= E.LONG_SHOT * E.LONG_SHOT then
                local before = state.shotStyles["LONG SHOT" .. E.STYLE_POINTS]
                style(state, "LONG SHOT", events, p.x, p.y)
                if not before and state.objective == "longshots" and state.goalLeft > 0 then
                    state.goalHit = state.goalHit + 1
                    state.goalLeft = state.goalLeft - 1
                    state.goalHitThisShot = state.goalHitThisShot + 1
                    push(events, { type = "longshot_goal", left = state.goalLeft })
                    if state.goalLeft <= 0 and state.phase ~= E.PHASE.FEVER then startFever(state, events) end
                end
                break
            end
        end
        state.shotGoals[#state.shotGoals + 1] = { x = p.x, y = p.y }
    end
    local pts = (E.PEG_POINTS[p.kind] or 10) * E:ScoreMultiplier(E:Progress(state))
    pts = pts + E.COMBO_STEP * (state.combo - 1)
    addScore(state, pts, events)
    state.shotPegs = state.shotPegs + 1
    state.shotPoints = state.shotPoints + pts
    if p.kind == "key" and p.unlocks then unlock(state, p, events) end
    -- a Super Slide: bricks lit one after another along a ride
    if p.shape == "brick" and ball then
        if ball.slideAt and state.time - ball.slideAt <= E.SLIDE_GAP then ball.slideRun = (ball.slideRun or 0) + 1
        else ball.slideRun = 1 end
        ball.slideAt = state.time
        for _, tier in ipairs(E.STYLE_TIERS) do
            if ball.slideRun >= tier.run then style(state, "SUPER SLIDE", events, p.x, p.y, tier.points, tier.caption) break end
        end
    end
    push(events, { type = "peg", peg = p, points = pts, x = at and at.x or p.x, y = at and at.y or p.y,
        quiet = quiet, combo = state.combo })
    local bonus = E.COMBO_BONUS[state.combo]
    if bonus then
        addScore(state, bonus, events)
        push(events, { type = "combo", combo = state.combo, bonus = bonus, x = p.x, y = p.y })
    end

    if p.kind == "green" then applyPower(state, p, ball, events) end
    if p.kind == "egg" then spawnPhoenix(state, at and at.x or p.x, at and at.y or p.y, events) end
    if p.kind == "boss" then push(events, { type = "boss_down", x = p.x, y = p.y }) end

    if p.goal and state.goalLeft <= 0 and state.phase ~= E.PHASE.FEVER and state.duel and state.duel.stage == 1 then
        -- the board is clear: the rival steps up (the window builds stage two)
        state.lastSlow = false
        state.phase = E.PHASE.OVER
        state.stageClear = true
        push(events, { type = "stage_clear" })
        return
    end
    if p.goal and state.goalLeft <= 0 and state.phase ~= E.PHASE.FEVER then
        local d = state.duel
        if d and d.stage == 2 then
            -- the last orange decides the duel (no Fever) once the shot is done
            if not d.lastOrange then
                d.lastOrange = d.turn
                push(events, { type = "duel_last_orange", side = d.turn })
            end
        else
            startFever(state, events)
        end
    end
end

-- Touched pieces leave on their own after LIT_SECS, ball or no ball.
local function expireLitPegs(state, events)
    local n = 0
    for _, p in ipairs(state.pegs) do
        -- every lit piece, Super Slide rail bricks included
        if p.lit and not p.gone and state.time - (p.hitAt or state.time) >= E.LIT_SECS then
            p.gone = true
            p.goneAt = state.time
            n = n + 1
        end
    end
    if n > 0 then push(events, { type = "clear", count = n }) end
end

local function clearLitPegs(state, events)
    local n = 0
    for _, p in ipairs(state.pegs) do
        if p.lit and not p.gone then
            p.gone = true
            p.goneAt = state.time
            n = n + 1
        end
    end
    if n > 0 then push(events, { type = "clear", count = n }) end
    return n
end

local function bucketTop() return H - E.BUCKET_H - 6 end
E.BucketTop = bucketTop

local function moveBucket(state, dt)
    if state.noBucket then return end
    local b = state.bucket
    -- parked in the middle, under the Pyramid, while it stands
    if E.PyramidUp(state) then b.x = W / 2 return end
    local lo, hi = E.BUCKET_W / 2 + 4, W - E.BUCKET_W / 2 - 4
    b.x = b.x + b.dir * E.BUCKET_SPEED * dt
    if b.x > hi then b.x = hi; b.dir = -1 end
    if b.x < lo then b.x = lo; b.dir = 1 end
end

-- Resolve a body against every peg. light=false runs a dry pass (the
-- guide's simulation and falling gems): bounces only, no hits.
-- Rails: a curve of bricks (p.rail names it, p.railCx/Cy its centre). A
-- ball that meets a rail brick from the centre side locks onto the rail
-- and runs along its face like a road, lighting each brick, until the rail
-- ends or the ball is too slow to hold on.
E.RAIL_MIN_SPEED = 60
local function brickFrame(q)
    local c, s = cos(q.angle or 0), sin(q.angle or 0)
    local nx, ny = -s, c
    -- the face that looks at the rail's centre
    local side = ((q.railCx - q.x) * nx + (q.railCy - q.y) * ny) >= 0 and 1 or -1
    return c, s, nx * side, ny * side
end

-- A Super Slide: once a ball takes a rail it rides the whole of it. The
-- rail's bricks, in their order along the curve, make a path along their
-- inner faces; the ball runs along it at the speed it came on with, lights
-- every brick it passes, and leaves off the far end along the last brick.
-- (Searching for the nearest brick each step let a fast ball slip off at a
-- joint and leave bricks unlit.)
local function railPath(state, rail)
    local list = {}
    for i, q in ipairs(state.pegs) do
        if q.rail == rail and not q.gone then list[#list + 1] = { q = q, order = q.railIdx or i } end
    end
    table.sort(list, function(x, y) return x.order < y.order end)
    local R = E.BALL_R
    local pts = {}
    for k, e in ipairs(list) do
        local q = e.q
        local c, s, nx, ny = brickFrame(q)
        local off = q.h / 2 + R + 0.2
        pts[k] = { x = q.x + nx * off, y = q.y + ny * off, q = q, c = c, s = s }
    end
    if #pts == 0 then return nil end
    -- run on past the first and last bricks' outer ends
    local function along(p, other)
        local dx, dy = p.x - other.x, p.y - other.y
        local d = sqrt(dx * dx + dy * dy)
        if d < 0.001 then return 0, 0 end
        return dx / d, dy / d
    end
    if #pts >= 2 then
        local ux, uy = along(pts[1], pts[2])
        local w = pts[1].q.w / 2
        table.insert(pts, 1, { x = pts[1].x + ux * w, y = pts[1].y + uy * w })
        local vx, vy = along(pts[#pts], pts[#pts - 1])
        w = pts[#pts].q.w / 2
        pts[#pts + 1] = { x = pts[#pts].x + vx * w, y = pts[#pts].y + vy * w }
    end
    -- arc length at each point
    pts[1].s = 0
    for k = 2, #pts do
        local dx, dy = pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y
        pts[k].s = pts[k - 1].s + sqrt(dx * dx + dy * dy)
    end
    return pts
end

-- the point and direction at arc length s
local function railAt(pts, s)
    for k = 2, #pts do
        if s <= pts[k].s or k == #pts then
            local a, b = pts[k - 1], pts[k]
            local seg = b.s - a.s
            local f = seg > 0 and (s - a.s) / seg or 0
            if f < 0 then f = 0 elseif f > 1 then f = 1 end
            local tx, ty = 0, 0
            if seg > 0 then tx, ty = (b.x - a.x) / seg, (b.y - a.y) / seg end
            return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, tx, ty
        end
    end
    return pts[1].x, pts[1].y, 0, 0
end

-- The ball takes the rail at brick p: where along it, and which way.
local function startRide(state, ball, p, events)
    local pts = railPath(state, ball.rail)
    if not pts or #pts < 2 then ball.rail = nil return end
    -- the nearest point of the path
    local bestS, bestD = 0, nil
    for k = 2, #pts do
        local a, b = pts[k - 1], pts[k]
        local dx, dy = b.x - a.x, b.y - a.y
        local L2 = dx * dx + dy * dy
        local f = L2 > 0 and ((ball.x - a.x) * dx + (ball.y - a.y) * dy) / L2 or 0
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        local px, py = a.x + dx * f, a.y + dy * f
        local d = (ball.x - px) ^ 2 + (ball.y - py) ^ 2
        if not bestD or d < bestD then bestD, bestS = d, a.s + (b.s - a.s) * f end
    end
    local _, _, tx, ty = railAt(pts, bestS)
    local dir = (ball.vx * tx + ball.vy * ty) >= 0 and 1 or -1
    ball.ride = { pts = pts, s = bestS, dir = dir }
end

local function railStep(state, ball, events, dt)
    local ride = ball.ride
    if not ride then ball.rail = nil return end
    local pts = ride.pts
    local speed = ball.railSpeed or 300
    local s0 = ride.s
    ride.s = ride.s + ride.dir * speed * (dt or 0)
    local endS = pts[#pts].s
    -- light every brick the ball has passed this step
    local lo, hi = math.min(s0, ride.s), math.max(s0, ride.s)
    for k = 1, #pts do
        local p = pts[k]
        if p.q and p.s >= lo - 0.5 and p.s <= hi + 0.5 and not p.q.gone and not p.done then
            p.done = true
            if not p.q.lit then p.q.rideId = ball.rideId end
            hitPeg(state, p.q, ball, events)
        end
    end
    local x, y, tx, ty = railAt(pts, math.max(0, math.min(endS, ride.s)))
    ball.x, ball.y = x, y
    ball.vx, ball.vy = tx * speed * ride.dir, ty * speed * ride.dir
    if ride.s <= 0 or ride.s >= endS then
        -- off the end: away along the rail's last stretch
        for k = 1, #pts do
            local p = pts[k]
            if p.q and not p.done and not p.q.gone then p.done = true; hitPeg(state, p.q, ball, events) end
        end
        ball.ride = nil
        ball.railLost, ball.railLostAt = ball.rail, state.time
        ball.rail = nil
    end
end
E.RailStep = railStep

collideBall = function(state, ball, events, light)
    local R = E.BALL_R
    for _, p in ipairs(state.pegs) do
        if not p.gone and not (ball.rail and p.rail == ball.rail) then
            local depth, nx, ny = pegContact(p, ball.x, ball.y, R)
            if depth and p.web then
                -- a web: only a real ball in play meets it
                if light and state.phase ~= E.PHASE.FEVER then
                    p.gone = true
                    if ball.fire then
                        push(events, { type = "web_burn", x = p.x, y = p.y })
                    else
                        ball.webbed = true
                        push(events, { type = "web_catch", x = p.x, y = p.y })
                        return
                    end
                end
                depth = nil
            end
            if depth then
                local onto = false
                if p.rail and light and not ball.fire and p.railCx and not p.lit then
                    -- from the centre side, the ball takes the rail instead of bouncing
                    local _, _, fnx, fny = brickFrame(p)
                    if (ball.x - p.x) * fnx + (ball.y - p.y) * fny > 0 then onto = true end
                end
                if onto then
                    ball.rail = p.rail
                    state.rideSeq = (state.rideSeq or 0) + 1
                    ball.rideId = state.rideSeq
                    local now = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
                    if ball.railLost == p.rail and ball.railSpeed and state.time - (ball.railLostAt or 0) < 0.4 then
                        now = math.max(now, ball.railSpeed)     -- back on the same rail: the same speed
                    end
                    ball.railSpeed = math.max(E.RAIL_MIN_SPEED * 3, now)
                    ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
                    startRide(state, ball, p, events)
                    if ball.rail then railStep(state, ball, events, 0) end
                    return
                elseif ball.fire and light and not isSolid(p) and p.kind ~= "boss" and not p.loose then
                    -- a fireball burns through: hit it, keep flying
                    hitPeg(state, p, ball, events)
                else
                    ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
                    local vn = ball.vx * nx + ball.vy * ny
                    if vn < 0 then
                        local e = p.bounce or E.RESTITUTION
                        if p.shape == "brick" and not isSolid(p) and light then
                            -- a grazing touch on a brick rides along it (Super Slide)
                            local tx, ty = -ny, nx
                            local vt = ball.vx * tx + ball.vy * ty
                            if -vn < E.SLIDE_RATIO * abs(vt) then e = 0 end
                        end
                        local k = (1 + e) * vn
                        ball.vx = ball.vx - k * nx
                        ball.vy = ball.vy - k * ny
                        if p.kind == "bumper" or p.kind == "boss" then
                            -- never sends the ball away slower than its kick
                            local kick = p.kick or ((p.kind == "boss") and E.BOSS_KICK or E.BUMPER_KICK)
                            local out = ball.vx * nx + ball.vy * ny
                            if out < kick then
                                ball.vx = ball.vx + (kick - out) * nx
                                ball.vy = ball.vy + (kick - out) * ny
                            end
                            -- a little sideways throw, so a ball dropped dead
                            -- straight onto a bumper cannot bounce in place
                            -- between it and the roof for ever
                            if p.kind == "bumper" and abs(ball.vx) < 30 and state.rng then
                                ball.vx = ball.vx + (state.rng() < 0.5 and -1 or 1) * (30 + state.rng() * 50)
                            end
                            if light and p.kind == "bumper" then push(events, { type = "bumper", peg = p, x = p.x, y = p.y }) end
                        elseif light then
                            push(events, { type = "bounce", peg = p, speed = -vn })
                        end
                    end
                    if light and not isSolid(p) then
                        if hitPeg(state, p, ball, events) and ball.ring then
                            -- the armed ring: everything around the first hit
                            local r2 = ball.ring * ball.ring
                            local cx, cy, radius = p.x, p.y, ball.ring
                            ball.ring = nil
                            for _, q in ipairs(state.pegs) do
                                if q ~= p and not q.lit and not q.gone then
                                    local dx, dy = q.x - cx, q.y - cy
                                    if dx * dx + dy * dy <= r2 then hitPeg(state, q, nil, events, true) end
                                end
                            end
                            push(events, { type = "ring", item = ball.item, x = cx, y = cy, radius = radius })
                        end
                    end
                end
            end
        end
    end
end

-- Play On: after running out of balls, three more and the level carries on.
-- Not in a duel's second stage, and not after a lost egg.
function E:PlayOn(state)
    if state.phase ~= E.PHASE.OVER or not state.result or state.result.cleared then return false end
    if state.eggLost or (state.duel and state.duel.stage == 2) then return false end
    state.result = nil
    state.ballsLeft = state.ballsLeft + E.PLAY_ON_BALLS
    state.phase = E.PHASE.AIM
    self:MovePurple(state)
    return true
end

-- A pre-level Extra Green Peg: one unlit plain blue peg turns green.
function E:AddGreen(state)
    local pool = {}
    for _, p in ipairs(state.pegs) do
        if p.kind == "blue" and not p.lit and not p.gone and not p.special and not p.moving then pool[#pool + 1] = p end
    end
    if #pool == 0 then return nil end
    local p = pool[state.rng(1, #pool)]
    p.kind = "green"
    return p
end

-- Arm an item for the next shot (nil to disarm).
function E:Arm(state, item)
    if item and not E.ITEMS[item] then return false end
    state.armed = item
    return true
end

-- The Pyramid: a step pyramid standing over the bucket (which is parked
-- and hidden under it). It is drawn in steps, but each side bounces as one
-- smooth slope, so every strike sends the ball up and out toward the wall
-- on that side. It crumbles a little at each strike and turns to dust on
-- the last one.
function E.PyramidUp(state)
    return (state.pyramidHits or 0) > 0 and state.phase ~= E.PHASE.FEVER
end

local function collidePyramid(state, ball, events)
    if not E.PyramidUp(state) then return end
    local R = E.BALL_R
    local cx, base, hw, ph = W / 2, E.PYRAMID_BASE, E.PYRAMID_W / 2, E.PYRAMID_H
    local top = base - ph
    if ball.y + R < top or ball.y > base or abs(ball.x - cx) > hw * E.PYRAMID_SOLID then return end
    local side = (ball.x < cx) and -1 or 1
    if ball.x == cx then side = (ball.vx < 0) and -1 or 1 end
    -- the face from the peak (cx, top) down to the base corner on this side
    local L = sqrt(hw * hw + ph * ph)
    local fnx, fny = side * ph / L, -hw / L          -- its outward normal
    local ex, ey = side * hw, ph                     -- along it
    local t = ((ball.x - cx) * ex + (ball.y - top) * ey) / (L * L)
    t = t < 0 and 0 or (t > 1 and 1 or t)
    local px, py = cx + t * ex, top + t * ey
    local dx, dy = ball.x - px, ball.y - py
    local d = sqrt(dx * dx + dy * dy)
    local inside = ball.y > top and abs(ball.x - cx) < hw * (ball.y - top) / ph
    local nx, ny, depth
    if inside then
        nx, ny = fnx, fny
        depth = R - ((ball.x - cx) * fnx + (ball.y - top) * fny)
    elseif d < R then
        if d > 0.0001 then nx, ny = dx / d, dy / d else nx, ny = fnx, fny end
        depth = R - d
    else
        return
    end
    ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
    local vn = ball.vx * nx + ball.vy * ny
    if vn >= 0 then return end
    local k = (1 + 0.8) * vn
    local vx, vy = ball.vx - k * nx, ball.vy - k * ny
    -- up, and back toward the wall on this side
    if vy > -E.PYRAMID_KICK then vy = -E.PYRAMID_KICK end
    if vx * side < E.PYRAMID_SIDE then vx = side * E.PYRAMID_SIDE end
    if abs(vx) > 520 then vx = side * 520 end
    ball.vx, ball.vy = vx, vy
    state.pyramidHits = state.pyramidHits - 1
    push(events, { type = "pyramid", x = ball.x, y = ball.y, left = state.pyramidHits })
    if state.pyramidHits <= 0 then
        push(events, { type = "pyramid_dust", x = cx, y = base - ph / 2 })
    end
end

local function finishLevel(state, events)
    local cleared = state.goalLeft <= 0
    local d = state.duel
    if d and d.stage == 2 then
        if d.lastOrange then cleared = d.lastOrange == "you"
        else cleared = d.scores.you > d.scores.rival end
    end
    if d and d.stage == 1 then cleared = false end
    if state.eggLost then cleared = false end
    state.result = {
        eggLost = state.eggLost or nil,
        duel = d and d.stage == 2 and { you = d.scores.you, rival = d.scores.rival, name = d.name, lastOrange = d.lastOrange } or nil,
        cleared = cleared,
        score = state.score,
        goals = state.goalHit,
        goalTotal = state.goalTotal,
        objective = state.objective,
        binScore = state.feverBin,
        feverTotal = state.feverTotal or 0,
        bestCombo = state.bestCombo,
        ballsLeft = state.ballsLeft,
        level = state.level,
    }
    state.phase = E.PHASE.OVER
    push(events, { type = "level_over", result = state.result })
end

-- Bucket test shared by balls and gems: 1 = caught, 2 = rim bounce, nil = clear.
local function bucketCheck(state, body, events, radius)
    if state.noBucket or E.PyramidUp(state) then return nil end
    local R = radius or E.BALL_R
    local b = state.bucket
    local top = bucketTop()
    if body.vy > 0 and body.y + R >= top and body.y - R <= top + E.BUCKET_H then
        local half = E.BUCKET_W / 2
        local off = body.x - b.x
        if abs(off) <= half - R then
            return 1
        elseif abs(off) <= half + R then
            local speed = body.vy
            body.y = top - R
            body.vy = -body.vy * 0.45
            body.vx = body.vx + (off > 0 and 60 or -60)
            if speed > 40 then push(events, { type = "rim", x = body.x, speed = speed }) end
            return 2
        end
    end
    return nil
end

local function integrateBall(state, ball, dt, events)
    if ball.rail then
        -- on a Super Slide the rail carries the ball
        railStep(state, ball, events, dt)
    else
        ball.vy = ball.vy + E.GRAVITY * dt
        ball.x = ball.x + ball.vx * dt
        ball.y = ball.y + ball.vy * dt
    end

    local R = E.BALL_R
    if ball.x < R then ball.x = R; if ball.vx < 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.x > W - R then ball.x = W - R; if ball.vx > 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.y < R then ball.y = R; if ball.vy < 0 then ball.vy = -ball.vy * E.RESTITUTION end end

    collideBall(state, ball, events, true)
    collidePyramid(state, ball, events)
    if ball.webbed then
        push(events, { type = "lost", x = ball.x, webbed = true })
        return false
    end
    -- a piece against the wall can push the ball through it: keep it inside
    if ball.x < R then ball.x = R; if ball.vx < 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.x > W - R then ball.x = W - R; if ball.vx > 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.y < R then ball.y = R; if ball.vy < 0 then ball.vy = -ball.vy * E.RESTITUTION end end

    -- the suction tube steers every falling ball of a suction shot toward it:
    -- it bends the sideways speed toward the speed that lands the ball in the
    -- tube, and never touches the fall itself (not a magnet: no stopping, no lift)
    if (ball.suction or state.suctionShot) and not state.noBucket and not E.PyramidUp(state) and state.phase ~= E.PHASE.FEVER and ball.vy > 0 then
        local above = bucketTop() - ball.y
        local dx = state.bucket.x - ball.x
        if above > 0 and above < E.SUCTION_REACH and abs(dx) < E.SUCTION_SIDE then
            -- time left to fall to the tube's mouth
            local g = E.GRAVITY
            local tFall = (-ball.vy + sqrt(ball.vy * ball.vy + 2 * g * above)) / g
            local want = dx / math.max(tFall, 0.05) + state.bucket.dir * E.BUCKET_SPEED
            -- stronger the closer it gets
            local k = (0.6 + 0.4 * (1 - above / E.SUCTION_REACH)) * (1 - abs(dx) / E.SUCTION_SIDE * 0.4)
            local step = E.SUCTION_PULL * k * dt
            local diff = want - ball.vx
            if diff > step then diff = step elseif diff < -step then diff = -step end
            ball.vx = ball.vx + diff
        end
    end

    if state.phase == E.PHASE.FEVER then
        if ball.y + R >= H - 2 then
            local idx = floor(ball.x / (W / #E.FEVER_BINS)) + 1
            if idx < 1 then idx = 1 elseif idx > #E.FEVER_BINS then idx = #E.FEVER_BINS end
            local pts = state.gnomeBonus and E.GNOME_BUCKET or E.FEVER_BINS[idx]
            if not state.feverBin then state.feverBin = pts end
            state.feverTotal = (state.feverTotal or 0) + pts
            addScore(state, pts, events, true)
            state.binsLit[idx] = true
            push(events, { type = "bin", index = idx, points = pts, x = ball.x })
            if not state.gnomeBonus then
                local all = true
                for i = 1, #E.FEVER_BINS do if not state.binsLit[i] then all = false end end
                if all then
                    state.gnomeBonus = true
                    state.feverTotal = state.feverTotal + E.GNOME_BONUS
                    addScore(state, E.GNOME_BONUS, events, true)
                    push(events, { type = "gnome_bonus", points = E.GNOME_BONUS })
                end
            end
            return false
        end
    else
        if bucketCheck(state, ball, events) == 1 then
            state.ballsLeft = state.ballsLeft + 1
            state.shotBucket = true
            push(events, { type = "bucket", x = ball.x })
            return false
        end
    end
    if ball.y - R > H then
        if (ball.spooky or 0) > 0 and state.phase ~= E.PHASE.FEVER then
            ball.spooky = ball.spooky - 1
            ball.y = R + 1
            ball.vy = 0
            ball.slow = 0
            push(events, { type = "spooky", x = ball.x })
            return true
        end
        push(events, { type = "lost", x = ball.x })
        return false
    end

    local speed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if speed < E.STUCK_SPEED then ball.slow = ball.slow + dt else ball.slow = 0 end
    -- a ball caught bouncing for ever (between balloons, say) retires
    ball.age = (ball.age or 0) + dt
    if ball.age > E.MAX_FLIGHT then
        push(events, { type = "lost", x = ball.x, stuck = true })
        return false
    end
    if ball.slow > E.STUCK_SECS then
        if clearLitPegs(state, events) > 0 then
            ball.slow = 0
            ball.vy = ball.vy + 20
        else
            push(events, { type = "lost", x = ball.x, stuck = true })
            return false
        end
    end
    return true
end

-- Stage two of a duel: build it from the stage-two spec, carrying the
-- player's score and stats over. A coin flip says who shoots first.
function E:StartDuel(state, spec2)
    local st = self:NewLevel(spec2)
    st.score = state.score
    st.stage1Score = state.score
    st.freeBallIdx = state.freeBallIdx
    st.bestCombo = state.bestCombo
    st.duel = { name = (state.duel and state.duel.name) or E.RIVAL.name, blurb = (state.duel and state.duel.blurb) or E.RIVAL.blurb,
        stage = 2, balls = { you = E.DUEL_BALLS, rival = E.DUEL_BALLS }, scores = { you = 0, rival = 0 } }
    st.duel.turn = (st.rng() < 0.5) and "you" or "rival"
    st.ballsLeft = st.duel.balls[st.duel.turn]
    st.duelCoin = st.duel.turn
    return st
end

-- The rival's aim: tries a fan of angles with a dry flight and takes one
-- of the best, so he goes for the oranges but can be beaten.
function E:RivalAim(state)
    local best = {}
    local R = E.BALL_R
    for deg = -78, 78, 4 do
        local a = deg * pi / 180
        local x, y = muzzle(a)
        local b = { x = x, y = y, vx = sin(a) * E.LAUNCH_SPEED, vy = cos(a) * E.LAUNCH_SPEED, slow = 0 }
        local touched, value = {}, 0
        for _ = 1, floor(1.6 / E.STEP) do
            b.vy = b.vy + E.GRAVITY * E.STEP
            b.x = b.x + b.vx * E.STEP
            b.y = b.y + b.vy * E.STEP
            if b.x < R then b.x = R; if b.vx < 0 then b.vx = -b.vx * E.RESTITUTION end end
            if b.x > W - R then b.x = W - R; if b.vx > 0 then b.vx = -b.vx * E.RESTITUTION end end
            for _, q in ipairs(state.pegs) do
                if not q.gone and not q.lit and not touched[q] and pegContact(q, b.x, b.y, R) then
                    touched[q] = true
                    value = value + (q.goal and 100 or (isSolid(q) and 0 or 10))
                end
            end
            collideBall(state, b, nil, false)
            if b.y - R > H then break end
        end
        best[#best + 1] = { aim = a, value = value }
    end
    table.sort(best, function(u, v) return u.value > v.value end)
    local pick = best[state.rng(1, math.min(3, #best))] or best[1]
    return pick and pick.aim or 0
end

-- After a shot in stage two: the miss penalty, then the other side's turn.
local function duelTurnOver(state, events)
    local d = state.duel
    if not d or d.stage ~= 2 then return false end
    if d.lastOrange then return true end    -- the last orange is lit: decided
    if state.goalHitThisShot == 0 and state.shots > 0 then
        local lost = math.min(E.DUEL_PENALTY, d.scores[d.turn])
        if lost > 0 then
            d.scores[d.turn] = d.scores[d.turn] - lost
            if d.turn == "you" then state.score = state.score - lost end
            push(events, { type = "duel_penalty", side = d.turn, lost = lost })
        end
    end
    d.balls[d.turn] = state.ballsLeft
    local other = (d.turn == "you") and "rival" or "you"
    if d.balls[other] > 0 then
        d.turn = other
    elseif d.balls[d.turn] <= 0 then
        return true          -- nobody has a ball left: the duel is decided
    end
    state.ballsLeft = d.balls[d.turn]
    push(events, { type = "duel_turn", turn = d.turn, you = d.scores.you, rival = d.scores.rival })
    return false
end

-- Is any loose piece still on the move?
looseMoving = function(state)
    for _, p in ipairs(state.pegs) do
        if p.loose and not p.gone and not p.lit and not p.resting then return true end
    end
    return false
end
E.LooseMoving = looseMoving

-- One loose piece leaves the board: a gem counts, an egg is lost; the
-- bucket saves either.
local function looseOut(state, p, events, caught)
    local y = caught and (bucketTop() - 10) or (H - 24)
    if p.kind == "egg" then
        if caught then
            p.hp = 1
            lightPeg(state, p, nil, events, true, { x = p.x, y = y })
            addScore(state, E.PHOENIX_POINTS, events)
            push(events, { type = "egg_saved", x = p.x, y = y, bonus = E.PHOENIX_POINTS })
        else
            p.lost = true
            state.eggLost = true
            push(events, { type = "egg_lost", x = p.x })
        end
    else
        p.collected = true
        lightPeg(state, p, nil, events, true, { x = p.x, y = y })
        if caught then
            addScore(state, E.BUCKET_DROP, events)
            push(events, { type = "gem_caught", x = p.x, y = y, bonus = E.BUCKET_DROP })
        else
            push(events, { type = "gem_dropped", x = p.x, y = y })
        end
    end
    p.gone = true
    p.goneAt = state.time
    p.resting = true
end

-- The loose pieces: gravity, contact with everything else on the board
-- (a soft, draggy landing), walls, the bucket and the bottom edge. A piece
-- at rest on something stays put until whatever holds it is gone.
loosePhysics = function(state, dt, events)
    for _, p in ipairs(state.pegs) do
        if p.loose and not p.gone and not p.lit then
            local r = p.r or E.PEG_R
            local wasResting = p.resting
            p.vy = (p.vy or 0) + E.LOOSE_GRAVITY * dt
            p.x = p.x + (p.vx or 0) * dt
            p.y = p.y + p.vy * dt
            if p.x < r then p.x = r; if p.vx < 0 then p.vx = -p.vx * E.LOOSE_RESTITUTION end end
            if p.x > W - r then p.x = W - r; if p.vx > 0 then p.vx = -p.vx * E.LOOSE_RESTITUTION end end
            local touching = false
            local contacts, cNx, cNy, cQ = 0, 0, 0, nil
            for _, q in ipairs(state.pegs) do
                if q ~= p and not q.gone and not q.lit then
                    local depth, nx, ny = pegContact(q, p.x, p.y, r)
                    if depth then
                        touching = true
                        contacts = contacts + 1
                        cNx, cNy, cQ = nx, ny, q
                        p.x, p.y = p.x + nx * depth, p.y + ny * depth
                        local vn = p.vx * nx + p.vy * ny
                        if vn < 0 then
                            -- a soft landing along the normal, a little rolling drag along the surface
                            local tx, ty = -ny, nx
                            local vt = (p.vx * tx + p.vy * ty) * math.max(0, 1 - E.LOOSE_DRAG * dt)
                            local vn2 = -vn * E.LOOSE_RESTITUTION
                            p.vx = vn2 * nx + vt * tx
                            p.vy = vn2 * ny + vt * ty
                        end
                        -- a moving piece carries what rests on it
                        if q.moving and q.px then
                            p.x = p.x + (q.x - q.px)
                            p.y = p.y + (q.y - q.py)
                        end
                    end
                end
            end
            -- balanced on a single point (the top of a peg, the corner of a
            -- brick) a piece tips over: only a cradle, a ledge or a flat face holds it
            local balanced = false
            if contacts == 1 and cNy < -0.8 then
                local flat = false
                if cQ.shape == "brick" then
                    local fnx, fny = -sin(cQ.angle or 0), cos(cQ.angle or 0)
                    flat = abs(cNx * fnx + cNy * fny) > 0.985
                end
                if not flat then
                    balanced = true
                    if not p.tipDir then
                        p.tipDir = (cNx > 0.01 and 1) or (cNx < -0.01 and -1) or ((state.rng() < 0.5) and -1 or 1)
                    end
                    p.vx = p.vx + p.tipDir * E.LOOSE_TIP * dt
                end
            end
            -- at rest only after staying slow for a moment: on a slope gravity
            -- keeps it rolling, in a cradle it settles
            if not balanced then p.tipDir = nil end
            local speed = sqrt(p.vx * p.vx + p.vy * p.vy)
            if touching and not balanced and speed < E.LOOSE_SLEEP then p.slowT = (p.slowT or 0) + dt else p.slowT = 0 end
            if p.slowT >= E.LOOSE_SLEEP_SECS then
                p.vx, p.vy = 0, 0
                p.resting = true
                p.settling = nil
            else
                p.resting = false
            end
            if p.resting then
                p.fellAt = nil
            else
                if wasResting then p.fellAt, p.fallX, p.fallY = state.time, p.x, p.y end
                if p.fellAt and not p.settling then
                    -- a few pixels on from where it rested: it is really falling
                    local dx, dy = p.x - p.fallX, p.y - p.fallY
                    if dx * dx + dy * dy > 16 then
                        p.fellAt = nil
                        push(events, { type = (p.kind == "egg") and "egg_fall" or "gem_free", x = p.x, y = p.y })
                        if state.goalLeft == 1 and state.phase == E.PHASE.FLIGHT then
                            state.looseSlow = p
                            local again = state.lastCueShot == state.shots
                            state.lastCueShot = state.shots
                            push(events, { type = "last_peg", x = p.x, y = p.y, again = again })
                        end
                    end
                end
            end
            if not p.resting then
                local caught = bucketCheck(state, p, events, r)
                if caught == 1 then
                    looseOut(state, p, events, true)
                elseif p.y - r > H then
                    looseOut(state, p, events, false)
                end
            end
        end
    end
end

-- The goal pieces still to hit and how many hits they need between them.
-- A boss counts its health and shield; eggs their remaining hits.
local function goalHitsLeft(state, out)
    local hits = 0
    local b = state.boss
    if b then
        if not b.lit and not b.gone then
            hits = b.hp + (b.shield or 0)
            out[#out + 1] = b
        end
        return hits
    end
    for _, p in ipairs(state.pegs) do
        -- gems are not hit, they fall: the look-ahead has nothing to see
        if p.goal and not p.lit and not p.gone and p.kind ~= "gem" then
            hits = hits + (p.hp or 1)
            out[#out + 1] = p
        end
    end
    return hits
end

-- Simulates this ball's next `secs` of flight (bounces and all, nothing
-- lit) and counts its strikes on the goal pieces, each piece at most as
-- many times as it has hits left and never twice within the hit
-- cooldown. Returns the strike count and the piece struck last.
local function predictGoalHits(state, ball, goals, secs)
    local b = { x = ball.x, y = ball.y, vx = ball.vx, vy = ball.vy, slow = 0, fire = ball.fire }
    local R = E.BALL_R
    local steps = floor(secs / E.STEP)
    local hits, lastPiece = 0, nil
    local lastAt, count = {}, {}
    local t = 0
    for _ = 1, steps do
        t = t + E.STEP
        b.vy = b.vy + E.GRAVITY * E.STEP
        b.x = b.x + b.vx * E.STEP
        b.y = b.y + b.vy * E.STEP
        if b.x < R then b.x = R; if b.vx < 0 then b.vx = -b.vx * E.RESTITUTION end end
        if b.x > W - R then b.x = W - R; if b.vx > 0 then b.vx = -b.vx * E.RESTITUTION end end
        for _, g in ipairs(goals) do
            if pegContact(g, b.x, b.y, R) and (not lastAt[g] or t - lastAt[g] >= E.HIT_COOLDOWN)
                and (count[g] or 0) < ((g.hp or 1) + (g.shield or 0)) then
                lastAt[g] = t
                count[g] = (count[g] or 0) + 1
                hits = hits + 1
                lastPiece = g
            end
        end
        collideBall(state, b, nil, false)
        if b.y - R > H then break end
    end
    return hits, lastPiece
end

local function updateLastPeg(state, dt, events)
    if state.phase ~= E.PHASE.FLIGHT then
        state.lastSlow = false
        state.looseSlow = nil
        return
    end
    -- the last gem (or egg) on its way down: the moment is its fall
    local ls = state.looseSlow
    if ls then
        if ls.gone or ls.lit or ls.resting then
            state.looseSlow = nil
            state.lastSlow = false
        else
            state.lastSlow = true
            state.lastPeg = ls
            return
        end
    end
    local goals = {}
    local need = goalHitsLeft(state, goals)
    if need == 0 or need > E.LAST_MAX_HITS then
        state.lastSlow = false
        return
    end
    -- the piece the moment is about: the one left, or the last one the
    -- look-ahead saw struck
    local target = (need == 1 and #goals == 1) and goals[1] or state.lastPeg
    if target and (target.lit or target.gone) then target = nil end
    local nearest, towards = math.huge, false
    if target then
        for _, ball in ipairs(state.balls) do
            local dx, dy = target.x - ball.x, target.y - ball.y
            local d = sqrt(dx * dx + dy * dy)
            if d < nearest then nearest = d end
            if (ball.vx * dx + ball.vy * dy) > 0 then towards = true end
        end
    end
    -- The look-ahead, a few times a second rather than every substep. Only
    -- a ball whose path really strikes the piece counts as a close call:
    -- the slow-mo starts when a ball's path finishes the goal within the
    -- horizon (two strikes in one swoop included, so there is time before
    -- the first), and while it runs it ends as soon as the ball is off
    -- track and moving away.
    local approaching = false
    state.lastLook = (state.lastLook or 0) + 1
    if state.lastLook % 6 == 0 and state.lastSpent < E.LAST_MAX_SECS then
        local horizon = (need >= 2) and E.LAST_LOOKAHEAD2 or E.LAST_LOOKAHEAD
        local onTrack, trackPiece = false, nil
        for _, ball in ipairs(state.balls) do
            local hits, lastPiece = predictGoalHits(state, ball, goals, horizon)
            if hits >= need and lastPiece then onTrack, trackPiece = true, lastPiece break end
        end
        if onTrack then
            approaching = true
            target = trackPiece
            nearest = 0
            state.lastOffTrack = 0
        elseif state.lastSlow and not towards then
            -- off track and moving away: let go only once that has held
            -- for a few checks, so a bounce that flickers the prediction
            -- does not flap the slow-mo on and off
            state.lastOffTrack = (state.lastOffTrack or 0) + 1
            if state.lastOffTrack >= 3 then
                state.lastSlow = false
                return
            end
        end
    end
    if not target then
        state.lastSlow = false
        return
    end
    if state.lastSlow then
        state.lastSpent = state.lastSpent + dt
        if nearest > E.LAST_LEAVE or state.lastSpent >= E.LAST_MAX_SECS then
            state.lastSlow = false
        end
    else
        if nearest > E.LAST_LEAVE then state.lastSpent = 0 end
        if approaching and state.lastSpent < E.LAST_MAX_SECS then
            state.lastSlow = true
            state.lastPeg = target
            state.lastOffTrack = 0
            -- the cue (whoosh, voice) once a shot; a restart in the same
            -- shot zooms again but stays quiet
            local again = state.lastCueShot == state.shots
            state.lastCueShot = state.shots
            push(events, { type = "last_peg", x = target.x, y = target.y, again = again })
        end
    end
end

-- The Tin Drake's scrap: two blocks after every shot. First the row just
-- above it, SCRAP_ROW1 blocks in its middle; then that row's two open ends
-- by the walls (easy bank shots); then rows higher up, only where the
-- pattern has been cleared. Every row keeps a column clear (the first row
-- keeps two), so the scrap is never a wall.
local function drakeScrap(state, boss, events)
    local cols = floor((W - 80) / E.SCRAP_COL_W)
    local x0 = (W - cols * E.SCRAP_COL_W) / 2
    local yBand = math.max(E.PEG_BOTTOM + 18, boss.y - E.BOSS_R - 40)
    local used, count = {}, 0
    for _, p in ipairs(state.pegs) do
        if p.scrap and not p.gone and p.row then
            count = count + 1
            used[p.row] = used[p.row] or {}
            used[p.row][p.col] = true
        end
    end
    local function rowCount(r) local n = 0 for _ in pairs(used[r] or {}) do n = n + 1 end return n end
    local function rowY(r) return yBand - (r - 1) * E.SCRAP_ROW_GAP end
    local function put(r, c)
        if used[r] and used[r][c] then return false end
        local x, y = x0 + (c - 0.5) * E.SCRAP_COL_W, rowY(r)
        for _, q in ipairs(state.pegs) do
            if not q.gone and q ~= boss then
                if q.shape == "brick" then
                    if pegContact(q, x, y, E.SCRAP_R + 6) then return false end
                else
                    local dx, dy = q.x - x, q.y - y
                    local rr = (q.r or E.PEG_R) + E.SCRAP_R + 6
                    if dx * dx + dy * dy < rr * rr then return false end
                end
            end
        end
        state.pegs[#state.pegs + 1] = { shape = "peg", x = x, y = y, r = E.SCRAP_R, kind = "block", scrap = true, row = r, col = c }
        used[r] = used[r] or {}
        used[r][c] = true
        return true
    end
    -- try the given columns of a row in a random order
    local function tryRow(r, list)
        local n = #list
        if n == 0 then return false end
        local start = state.rng(1, n)
        for k = 0, n - 1 do
            if put(r, list[((start + k - 1) % n) + 1]) then return true end
        end
        return false
    end
    local middle = {}
    for c = 2, cols - 1 do middle[#middle + 1] = c end
    local made = 0
    while made < E.SCRAP_PER_SHOT_DRAKE and count + made < E.SCRAP_MAX_DRAKE do
        local placed = false
        local r1 = used[1] or {}
        local inMiddle = rowCount(1) - (r1[1] and 1 or 0) - (r1[cols] and 1 or 0)
        if inMiddle < E.SCRAP_ROW1 then placed = tryRow(1, middle) end
        if not placed then placed = tryRow(1, { 1, cols }) end
        if not placed then
            for r = 2, 14 do
                if rowY(r) < E.PEG_TOP then break end
                if rowCount(r) < cols - 1 then
                    local all = {}
                    for c = 1, cols do all[#all + 1] = c end
                    placed = tryRow(r, all)
                end
                if placed then break end
            end
        end
        if not placed then break end
        made = made + 1
    end
    if made > 0 then push(events, { type = "boss_scrap", count = made, x = boss.x, y = boss.y }) end
end

-- The Gyro Spider's webs: two after every shot, anywhere in the open
-- between the pattern's pieces. A ball that touches one is caught: the web
-- and the ball are both gone. A fireball burns a web away and flies on.
local function spiderWebs(state, boss, events)
    local count = 0
    for _, p in ipairs(state.pegs) do if p.web and not p.gone then count = count + 1 end end
    local yTop, yBot = E.PEG_TOP + 30, boss.y - E.BOSS_R - 30
    if yBot <= yTop then return end
    local made = 0
    for _ = 1, 120 do
        if made >= E.WEB_PER_SHOT or count + made >= E.WEB_MAX then break end
        local x = 34 + state.rng() * (W - 68)
        local y = yTop + state.rng() * (yBot - yTop)
        local clear = true
        for _, q in ipairs(state.pegs) do
            if not q.gone then
                if q.shape == "brick" then
                    if pegContact(q, x, y, E.WEB_R + E.WEB_CLEAR) then clear = false break end
                else
                    local dx, dy = q.x - x, q.y - y
                    local rr = (q.r or E.PEG_R) + E.WEB_R + E.WEB_CLEAR
                    if dx * dx + dy * dy < rr * rr then clear = false break end
                end
            end
        end
        if clear then
            state.pegs[#state.pegs + 1] = { shape = "peg", x = x, y = y, r = E.WEB_R, kind = "web", web = true }
            made = made + 1
        end
    end
    if made > 0 then push(events, { type = "boss_webs", count = made, x = boss.x, y = boss.y }) end
end

local function substep(state, dt, events)
    state.time = state.time + dt
    if #state.movers > 0 then E:UpdateMovers(state) end
    expireLitPegs(state, events)
    if state.phase ~= E.PHASE.FEVER then moveBucket(state, dt) end
    if state.phase == E.PHASE.OVER then return end
    if state.phase == E.PHASE.AIM then
        -- loose pieces settle into their cradles while the player aims
        if state.hasLoose then loosePhysics(state, dt, events) end
        if state.eggLost then finishLevel(state, events) end
        return
    end

    for i = #state.balls, 1, -1 do
        local ball = state.balls[i]
        if not integrateBall(state, ball, dt, events) then
            table.remove(state.balls, i)
        end
    end
    if state.hasLoose then loosePhysics(state, dt, events) end
    phoenixFlight(state, dt, events)
    if state.eggLost and state.phase ~= E.PHASE.FEVER then
        state.balls = {}
        state.lastSlow = false
        finishLevel(state, events)
        return
    end
    updateLastPeg(state, dt, events)

    if state.phase == E.PHASE.FEVER then
        -- the leftover balls are fired off in random directions, one every
        -- FEVER_SHOT_GAP, each worth its bin
        if state.ballsLeft > 0 and state.time >= (state.feverNext or 0) then
            local a = (state.rng() - 0.5) * 2 * (E.MAX_AIM_DEG * pi / 180)
            local x, y = muzzle(a)
            state.aim = a
            state.balls[#state.balls + 1] = { x = x, y = y, vx = sin(a) * E.LAUNCH_SPEED, vy = cos(a) * E.LAUNCH_SPEED, slow = 0 }
            state.ballsLeft = state.ballsLeft - 1
            state.ballsFired = state.ballsFired + 1
            state.feverNext = state.time + E.FEVER_SHOT_GAP
            push(events, { type = "fever_shot", aim = a })
        end
        if #state.balls == 0 and state.ballsLeft == 0 then finishLevel(state, events) end
        return
    end

    if state.eggLost then
        state.balls = {}
        state.lastSlow = false
        finishLevel(state, events)
        return
    end
    -- the shot is over once the balls are gone and nothing is still rolling
    -- (a piece that keeps jittering gets three seconds, then the shot ends anyway)
    if #state.balls == 0 then state.looseWait = (state.looseWait or 0) + dt else state.looseWait = 0 end
    local rolling = looseMoving(state) and state.looseWait < 3
    if #state.balls == 0 and not rolling and not (state.phoenixes and #state.phoenixes > 0) then
        state.looseWait = 0
        clearLitPegs(state, events)
        -- each boss fights back its own way: the Tin Drake throws steel
        -- scrap, the Gyro Spider spins webs (the Bolt Golem's shield and the
        -- Cog Yeti's healing are below, the boar's charge in its movement)
        local boss = state.boss
        if boss and not boss.lit and not boss.gone and boss.ability == "drake" then
            drakeScrap(state, boss, events)
        elseif boss and not boss.lit and not boss.gone and boss.ability == "spider" then
            spiderWebs(state, boss, events)
        end
        -- the Cog Yeti heals after a shot that never touched it
        local b = state.boss
        if b and not b.lit and b.ability == "yeti" and not state.bossHitThisShot and b.hp < b.maxhp then
            b.hp = b.hp + 1
            push(events, { type = "boss_heal", x = b.x, y = b.y, hp = b.hp })
        end
        if state.shotHits > 0 or state.shotPegs > 0 then
            local n = math.max(1, state.shotPegs)
            push(events, { type = "shot_summary", pegs = state.shotPegs, points = state.shotPoints, avg = floor(state.shotPoints / n) })
        elseif state.shots > 0 and not state.shotBucket then
            push(events, { type = "total_miss" })
        end
        local decided = duelTurnOver(state, events)
        if decided then
            finishLevel(state, events)
        elseif state.ballsLeft > 0 then
            state.phase = E.PHASE.AIM
            E:MovePurple(state)
            push(events, { type = "ready" })
        else
            finishLevel(state, events)
        end
    end
end

function E:Step(state, dt, events)
    if dt > 0.1 then dt = 0.1 end
    if state.lastSlow then dt = dt * E.LAST_SLOWMO end
    state.acc = state.acc + dt
    local step = E.STEP
    local guard = 0
    while state.acc >= step and guard < 60 do
        substep(state, step, events)
        state.acc = state.acc - step
        guard = guard + 1
    end
    return events
end
