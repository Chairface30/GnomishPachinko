--[[
    Gnomish Pachinko - Engine.lua
    The peg-shooter's physics and rules. Pure Lua, no frame API: UI.lua
    draws whatever this produces and tests/engine_test.py drives it headless.

    Field pixels, origin top-left, y grows DOWNWARD (the UI anchors every
    texture TOPLEFT at (x, -y)).

    Pieces: round pegs and BRICKS (rotated rectangles). Both share the peg
    record: { shape, x, y, kind, hp, maxhp, lit, gone } with w/h/angle on
    bricks and an optional r on round ones.
    Kinds: blue (points), orange (goal), green (the level's power), purple
    (one bonus peg, moves every shot), egg (goal, three hits to hatch), gem
    (goal, knocked loose and caught in the bucket), boss (goal, a big
    moving piece with health), block (solid, never lights) and bumper
    (solid, round, over-bouncy).

    Every hit takes one point of hp. A piece with hp 2 or 3 (a "tough"
    piece) cracks first and only lights on its last hit. A piece whose
    `goal` flag is set counts toward clearing the level; when the last goal
    is done, FEVER starts.

    A level: AIM (Aim/Guide, Launch on click) -> FLIGHT (Step) -> AIM when
    the ball drains, FEVER the moment the last goal is done -> OVER with
    state.result (cleared or out of balls).
]]

local GP = GnomishPachinko
GP.Engine = GP.Engine or {}
local E = GP.Engine

E.FIELD_W, E.FIELD_H = 600, 600
E.BALL_R      = 7
E.PEG_R       = 9
E.EGG_R       = 13
E.GEM_R       = 10
E.BOSS_R      = 26
E.BRICK_W     = 30
E.BRICK_H     = 11
E.LAUNCHER_Y  = 26
E.PEG_TOP     = 120
E.PEG_BOTTOM  = 500
E.PEG_MARGIN  = 34
E.PEG_GAP     = 40          -- centre distance round peg to round peg

E.GRAVITY      = 1000
E.LAUNCH_SPEED = 480
E.RESTITUTION  = 0.70
E.STEP         = 1 / 120
E.MAX_AIM_DEG  = 82
E.STUCK_SPEED  = 35
E.STUCK_SECS   = 1.5
E.LIT_SECS     = 2.0        -- a lit piece vanishes this long after the hit
E.HIT_COOLDOWN = 0.2        -- one ball cannot hit the same piece twice within this

E.BUCKET_W     = 84
E.BUCKET_H     = 16
E.BUCKET_SPEED = 130
E.FEVER_SLOWMO = 0.35
-- The last goal piece: when a ball closes in on it, time slows and the
-- window zooms in on it (Peggle Blast's last-peg moment).
E.LAST_SLOWMO     = 0.3
E.LAST_NEAR       = 90       -- a ball this close and heading in starts it
E.LAST_LEAVE      = 150      -- it ends when no ball is within this
E.LAST_MAX_SECS   = 2.0      -- of slowed time, then it waits for the ball to leave and return
E.LAST_ZOOM       = 1.8
E.FEVER_BINS   = { 10000, 50000, 100000, 50000, 10000 }
E.FEVER_SHOT_GAP = 0.3     -- seconds between the leftover balls fired at the clear
E.FREE_BALL_SCORES = { 25000, 75000, 125000 }

E.BALLS       = 10
-- points for the hit that lights a piece (times the multiplier)
E.PEG_POINTS  = { blue = 25, orange = 250, green = 25, purple = 1000, egg = 500, gem = 1000, boss = 5000 }
-- points for a hit that only cracks a tough piece, an egg or the boss
E.CHIP_POINTS = { blue = 10, orange = 50, green = 10, purple = 10, egg = 100, boss = 500 }
E.BLAST_RADIUS = 140
E.GUIDE_SHOTS = 3
E.CHAIN_LINKS = 6           -- Chain Lightning: pieces after the green one
E.CHAIN_REACH = 120
E.PYRAMID_SHOTS   = 3       -- the shot that earns it and two more
E.PYRAMID_BOUNCES = 4       -- per shot
E.PYRAMID_KICK    = 380     -- the ball leaves it at least this fast, upward
E.PYRAMID_W       = 510
E.PYRAMID_H       = 14
E.PYRAMID_Y       = E.FIELD_H - E.BUCKET_H - 6 - 40

-- Combos: every piece lit in one shot adds COMBO_STEP x (hits so far)
-- to its points, and long chains pay a bonus at these lengths.
E.COMBO_STEP  = 15
E.COMBO_BONUS = { [10] = 5000, [15] = 10000, [20] = 20000, [25] = 50000, [30] = 100000 }

-- Bumpers: round, never light, and throw the ball back harder than it
-- came (bounce above 1), with a floor on the outgoing speed.
E.BUMPER_R      = 15
E.BUMPER_BOUNCE = 1.3
E.BUMPER_KICK   = 260

-- The boss: a big round piece that slides along a band near the top. It
-- bounces like a bumper so the ball comes back down through the pegs.
E.BOSS_BOUNCE = 1.0
E.BOSS_KICK   = 220
E.BOSS_BAND   = { y0 = 146, y1 = 236, y = 186 }
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
    { id = "pyramid",   name = "Pyramid",         blurb = "A ramp across the bottom bounces the ball back up, for three shots." },
    { id = "lightning", name = "Chain Lightning", blurb = "A bolt leaps from the green peg through six more pieces." },
}

-- What a level asks of you.
E.OBJECTIVES = {
    classic = { name = "Classic", goalWord = "orange pegs", text = "Light every orange peg" },
    eggs    = { name = "Eggs",    goalWord = "eggs",        text = "Hatch every egg: three hits each" },
    gems    = { name = "Gems",    goalWord = "gems",        text = "Knock every gem loose and catch it in the bucket" },
    boss    = { name = "Boss",    goalWord = "boss health", text = "Beat the boss: hit it until its health is gone" },
}

-- The bosses, one kind per chapter in turn. `ability` is what Engine does
-- with it; the names and blurbs are for the panel.
E.BOSSES = {
    { id = "drake",  name = "Tin Drake",    blurb = "Speeds up as it weakens.",                         speed = 0.6 },
    { id = "golem",  name = "Bolt Golem",   blurb = "Raises a two-hit shield every third shot.",        speed = 0.7 },
    { id = "spider", name = "Gyro Spider",  blurb = "Jumps to a new spot whenever it is hit.",          speed = 1.0 },
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
local function isSolid(p) return p.kind == "block" or p.kind == "bumper" end
E.IsSolid = isSolid

-- Bounding radius used for spacing checks.
local function pegRadius(p)
    if p.shape == "brick" then return sqrt(p.w * p.w + p.h * p.h) / 2 end
    return p.r or E.PEG_R
end
E.PegRadius = pegRadius

-- The Pyramid: one wide solid bar just above the bucket.
E.PYRAMID_PARTS = {
    { shape = "brick", x = W / 2, y = E.PYRAMID_Y, angle = 0, w = E.PYRAMID_W, h = E.PYRAMID_H, kind = "block" },
}

-- ---------------------------------------------------------------------
-- State

-- spec: from Levels. pegs carry kind/hp/goal; movers drive the gimmicks.
function E:NewLevel(spec)
    local state = {
        level = spec.level,
        chapter = spec.chapter,
        name = spec.name,
        seed = spec.seed,
        layout = spec.layout,
        objective = spec.objective or "classic",
        pegs = spec.pegs,
        movers = spec.movers or {},
        gimmick = spec.gimmick,
        goalTotal = spec.goal or spec.orange or 0,
        goalLeft = spec.goal or spec.orange or 0,
        goalHit = 0,
        power = spec.power,
        balls = {},
        gems = {},
        ballsLeft = spec.balls or E.BALLS,
        ballsFired = 0,
        shots = 0,
        score = 0,
        combo = 0,
        bestCombo = 0,
        freeBallIdx = 1,
        superGuide = 0,
        pyramidShots = 0,
        pyramidBounces = 0,
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

function E:Aim(state, tx, ty)
    local dx, dy = tx - W / 2, ty - E.LAUNCHER_Y
    if dx == 0 and dy <= 0 then return state.aim end
    state.aim = clampAim(atan2(dx, dy))
    return state.aim
end

function E:MuzzlePos(state)
    local a = state.aim or 0
    return W / 2 + sin(a) * 14, E.LAUNCHER_Y + cos(a) * 14
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
        if first then break end
        t = t + dt
        if t >= nextSample then
            pts[#pts + 1] = { x = x, y = y }
            nextSample = nextSample + every
        end
    end
    return pts, first
end

local collideBall  -- forward

-- Super Guide: the real bounce path (pegs unchanged) for up to maxT seconds.
function E:Simulate(state, maxT, every)
    maxT, every = maxT or 2.5, every or 0.04
    local pts = {}
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    local ball = { x = x, y = y, vx = sin(a) * E.LAUNCH_SPEED, vy = cos(a) * E.LAUNCH_SPEED, slow = 0 }
    local t, nextSample = 0, every
    local dt = E.STEP
    while t < maxT do
        ball.vy = ball.vy + E.GRAVITY * dt
        ball.x = ball.x + ball.vx * dt
        ball.y = ball.y + ball.vy * dt
        if ball.x < E.BALL_R then ball.x = E.BALL_R; if ball.vx < 0 then ball.vx = -ball.vx * E.RESTITUTION end end
        if ball.x > W - E.BALL_R then ball.x = W - E.BALL_R; if ball.vx > 0 then ball.vx = -ball.vx * E.RESTITUTION end end
        if ball.y < E.BALL_R then ball.y = E.BALL_R; if ball.vy < 0 then ball.vy = -ball.vy * E.RESTITUTION end end
        collideBall(state, ball, nil, false)
        if ball.y - E.BALL_R > H then break end
        t = t + dt
        if t >= nextSample then
            pts[#pts + 1] = { x = ball.x, y = ball.y }
            nextSample = nextSample + every
        end
    end
    return pts
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
    }
    state.ballsLeft = state.ballsLeft - 1
    state.ballsFired = state.ballsFired + 1
    state.shots = state.shots + 1
    state.combo = 0
    state.bossHitThisShot = false
    if state.superGuide > 0 then state.superGuide = state.superGuide - 1 end
    if state.pyramidShots > 0 then
        state.pyramidShots = state.pyramidShots - 1
        state.pyramidBounces = E.PYRAMID_BOUNCES
    else
        state.pyramidBounces = 0
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

local function addScore(state, pts, events)
    state.score = state.score + pts
    local threshold = E.FREE_BALL_SCORES[state.freeBallIdx]
    while threshold and state.score >= threshold do
        state.ballsLeft = state.ballsLeft + 1
        push(events, { type = "freeball_score", score = threshold })
        state.freeBallIdx = state.freeBallIdx + 1
        threshold = E.FREE_BALL_SCORES[state.freeBallIdx]
    end
end

local hitPeg, lightPeg, applyPower, freeGem, bossReact

applyPower = function(state, p, ball, events)
    local power = state.power
    if power == "multiball" and ball then
        state.balls[#state.balls + 1] = {
            x = ball.x, y = ball.y, vx = -ball.vx, vy = ball.vy, slow = 0,
            fire = ball.fire, spooky = ball.spooky,
        }
    elseif power == "guide" then
        state.superGuide = E.GUIDE_SHOTS
    elseif power == "blast" then
        local r2 = E.BLAST_RADIUS * E.BLAST_RADIUS
        for _, q in ipairs(state.pegs) do
            if not q.lit and not q.gone and q ~= p then
                local dx, dy = q.x - p.x, q.y - p.y
                if dx * dx + dy * dy <= r2 then hitPeg(state, q, nil, events, true) end
            end
        end
    elseif power == "fireball" and ball then
        ball.fire = true
    elseif power == "spooky" and ball then
        ball.spooky = (ball.spooky or 0) + 1
    elseif power == "pyramid" then
        state.pyramidShots = E.PYRAMID_SHOTS - 1
        state.pyramidBounces = E.PYRAMID_BOUNCES
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

-- A gem knocked loose falls as a body of its own until the bucket catches
-- it or it drains (and comes back to its nest for the next shot).
freeGem = function(state, p, ball, events)
    p.freed = true
    p.gone = true
    p.goneAt = nil
    state.gems[#state.gems + 1] = {
        x = p.x, y = p.y, vx = ball and ball.vx * 0.25 or 0, vy = 0, slow = 0, home = p,
    }
    push(events, { type = "gem_free", x = p.x, y = p.y })
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

-- One hit on a piece: a shield soaks it, a tough piece cracks, the last
-- point of hp lights it. Returns true when the hit counted.
hitPeg = function(state, p, ball, events, quiet)
    if p.lit or p.gone or isSolid(p) then return false end
    if p.cooldown and state.time < p.cooldown then return false end
    p.cooldown = state.time + E.HIT_COOLDOWN
    if p.kind == "gem" then
        freeGem(state, p, ball, events)
        return true
    end
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
    end
    local pts = (E.PEG_POINTS[p.kind] or 10) * E:ScoreMultiplier(E:Progress(state))
    pts = pts + E.COMBO_STEP * (state.combo - 1)
    addScore(state, pts, events)
    push(events, { type = "peg", peg = p, points = pts, x = at and at.x or p.x, y = at and at.y or p.y,
        quiet = quiet, combo = state.combo })
    local bonus = E.COMBO_BONUS[state.combo]
    if bonus then
        addScore(state, bonus, events)
        push(events, { type = "combo", combo = state.combo, bonus = bonus, x = p.x, y = p.y })
    end

    if p.kind == "green" then applyPower(state, p, ball, events) end
    if p.kind == "boss" then push(events, { type = "boss_down", x = p.x, y = p.y }) end

    if p.goal and state.goalLeft <= 0 and state.phase ~= E.PHASE.FEVER then
        state.phase = E.PHASE.FEVER
        state.feverSlow = true          -- slow motion until the first ball lands in a bin
        state.feverTotal = 0
        push(events, { type = "fever" })
    end
end

-- Touched pieces leave on their own after LIT_SECS, ball or no ball.
local function expireLitPegs(state, events)
    local n = 0
    for _, p in ipairs(state.pegs) do
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
    local b = state.bucket
    local lo, hi = E.BUCKET_W / 2 + 4, W - E.BUCKET_W / 2 - 4
    b.x = b.x + b.dir * E.BUCKET_SPEED * dt
    if b.x > hi then b.x = hi; b.dir = -1 end
    if b.x < lo then b.x = lo; b.dir = 1 end
end

-- Resolve a body against every peg. light=false runs a dry pass (the
-- guide's simulation and falling gems): bounces only, no hits.
collideBall = function(state, ball, events, light)
    local R = E.BALL_R
    for _, p in ipairs(state.pegs) do
        if not p.gone then
            local depth, nx, ny = pegContact(p, ball.x, ball.y, R)
            if depth then
                if ball.fire and light and not isSolid(p) and p.kind ~= "boss" then
                    -- a fireball burns through: hit it, keep flying
                    hitPeg(state, p, ball, events)
                else
                    ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
                    local vn = ball.vx * nx + ball.vy * ny
                    if vn < 0 then
                        local e = p.bounce or E.RESTITUTION
                        local k = (1 + e) * vn
                        ball.vx = ball.vx - k * nx
                        ball.vy = ball.vy - k * ny
                        if p.kind == "bumper" or p.kind == "boss" then
                            -- never sends the ball away slower than its kick
                            local kick = (p.kind == "boss") and E.BOSS_KICK or E.BUMPER_KICK
                            local out = ball.vx * nx + ball.vy * ny
                            if out < kick then
                                ball.vx = ball.vx + (kick - out) * nx
                                ball.vy = ball.vy + (kick - out) * ny
                            end
                            if light and p.kind == "bumper" then push(events, { type = "bumper", peg = p, x = p.x, y = p.y }) end
                        elseif light then
                            push(events, { type = "bounce", peg = p, speed = -vn })
                        end
                    end
                    if light and not isSolid(p) then hitPeg(state, p, ball, events) end
                end
            end
        end
    end
end

-- The Pyramid bar, while it has bounces left this shot.
local function collidePyramid(state, ball, events)
    if state.pyramidBounces <= 0 or state.phase == E.PHASE.FEVER then return end
    local R = E.BALL_R
    for _, part in ipairs(E.PYRAMID_PARTS) do
        local depth, nx, ny = pegContact(part, ball.x, ball.y, R)
        if depth then
            ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
            local vn = ball.vx * nx + ball.vy * ny
            if vn < 0 then
                local k = (1 + 0.8) * vn
                ball.vx = ball.vx - k * nx
                ball.vy = ball.vy - k * ny
                if ball.vy > -E.PYRAMID_KICK then ball.vy = -E.PYRAMID_KICK end
                state.pyramidBounces = state.pyramidBounces - 1
                push(events, { type = "pyramid", x = ball.x, left = state.pyramidBounces })
            end
        end
    end
end

local function finishLevel(state, events)
    local cleared = state.goalLeft <= 0
    state.result = {
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
local function bucketCheck(state, body)
    local R = E.BALL_R
    local b = state.bucket
    local top = bucketTop()
    if body.vy > 0 and body.y + R >= top and body.y - R <= top + E.BUCKET_H then
        local half = E.BUCKET_W / 2
        local off = body.x - b.x
        if abs(off) <= half - R then
            return 1
        elseif abs(off) <= half + R then
            body.y = top - R
            body.vy = -body.vy * 0.45
            body.vx = body.vx + (off > 0 and 60 or -60)
            return 2
        end
    end
    return nil
end

local function integrateBall(state, ball, dt, events)
    ball.vy = ball.vy + E.GRAVITY * dt
    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt

    local R = E.BALL_R
    if ball.x < R then ball.x = R; if ball.vx < 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.x > W - R then ball.x = W - R; if ball.vx > 0 then ball.vx = -ball.vx * E.RESTITUTION end end
    if ball.y < R then ball.y = R; if ball.vy < 0 then ball.vy = -ball.vy * E.RESTITUTION end end

    collideBall(state, ball, events, true)
    collidePyramid(state, ball, events)

    if state.phase == E.PHASE.FEVER then
        if ball.y + R >= H - 2 then
            local idx = floor(ball.x / (W / #E.FEVER_BINS)) + 1
            if idx < 1 then idx = 1 elseif idx > #E.FEVER_BINS then idx = #E.FEVER_BINS end
            local pts = E.FEVER_BINS[idx]
            if not state.feverBin then state.feverBin = pts end
            state.feverSlow = false
            state.feverTotal = (state.feverTotal or 0) + pts
            addScore(state, pts, events)
            push(events, { type = "bin", index = idx, points = pts, x = ball.x })
            return false
        end
    else
        if bucketCheck(state, ball) == 1 then
            state.ballsLeft = state.ballsLeft + 1
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

-- A gem back in its nest, ready for the next shot.
local function gemHome(state, p, events)
    p.freed = false
    p.gone = false
    p.cooldown = nil
    push(events, { type = "gem_home", x = p.x, y = p.y })
end

local function integrateGem(state, g, dt, events)
    g.vy = g.vy + E.GRAVITY * dt
    g.x = g.x + g.vx * dt
    g.y = g.y + g.vy * dt
    local R = E.BALL_R
    if g.x < R then g.x = R; if g.vx < 0 then g.vx = -g.vx * E.RESTITUTION end end
    if g.x > W - R then g.x = W - R; if g.vx > 0 then g.vx = -g.vx * E.RESTITUTION end end
    collideBall(state, g, nil, false)
    if bucketCheck(state, g) == 1 then
        local p = g.home
        p.collected = true
        lightPeg(state, p, nil, events, true, { x = g.x, y = bucketTop() - 10 })
        push(events, { type = "gem_caught", x = g.x, y = bucketTop() - 10 })
        return false
    end
    if g.y - R > H then
        push(events, { type = "gem_lost", x = g.x })
        return false
    end
    local speed = sqrt(g.vx * g.vx + g.vy * g.vy)
    if speed < E.STUCK_SPEED then g.slow = g.slow + dt else g.slow = 0 end
    if g.slow > E.STUCK_SECS then
        gemHome(state, g.home, events)
        return false
    end
    return true
end

-- The one goal piece left, one hit from done, or nil.
local function lastGoalPiece(state)
    local b = state.boss
    if b then
        if not b.lit and not b.gone and b.hp == 1 and (b.shield or 0) == 0 then return b end
        return nil
    end
    if state.goalLeft ~= 1 then return nil end
    for _, p in ipairs(state.pegs) do
        if p.goal and not p.lit and not p.gone and (p.hp or 1) == 1 then return p end
    end
    return nil
end

local function updateLastPeg(state, dt, events)
    if state.phase ~= E.PHASE.FLIGHT then
        state.lastSlow = false
        return
    end
    local target = lastGoalPiece(state)
    if not target then
        state.lastSlow = false
        return
    end
    local nearest, approaching = math.huge, false
    for _, ball in ipairs(state.balls) do
        local dx, dy = target.x - ball.x, target.y - ball.y
        local d = sqrt(dx * dx + dy * dy)
        if d < nearest then nearest = d end
        if d < E.LAST_NEAR and (ball.vx * dx + ball.vy * dy) > 0 then approaching = true end
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
            push(events, { type = "last_peg", x = target.x, y = target.y })
        end
    end
end

local function substep(state, dt, events)
    state.time = state.time + dt
    if #state.movers > 0 then E:UpdateMovers(state) end
    expireLitPegs(state, events)
    if state.phase ~= E.PHASE.FEVER then moveBucket(state, dt) end
    if state.phase == E.PHASE.AIM or state.phase == E.PHASE.OVER then return end

    for i = #state.balls, 1, -1 do
        local ball = state.balls[i]
        if not integrateBall(state, ball, dt, events) then
            table.remove(state.balls, i)
        end
    end
    for i = #state.gems, 1, -1 do
        if not integrateGem(state, state.gems[i], dt, events) then
            table.remove(state.gems, i)
        end
    end
    updateLastPeg(state, dt, events)

    if state.phase == E.PHASE.FEVER then
        -- once the first ball has landed, the leftover balls are fired off
        -- in random directions, one every FEVER_SHOT_GAP, each worth its bin
        if not state.feverSlow and state.ballsLeft > 0 and state.time >= (state.feverNext or 0) then
            local a = (state.rng() - 0.5) * 2 * (E.MAX_AIM_DEG * pi / 180)
            local x, y = W / 2 + sin(a) * 14, E.LAUNCHER_Y + cos(a) * 14
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

    if #state.balls == 0 and #state.gems == 0 then
        clearLitPegs(state, events)
        -- gems that were knocked loose and missed go back to their nests
        for _, p in ipairs(state.pegs) do
            if p.kind == "gem" and p.freed and not p.collected then gemHome(state, p, events) end
        end
        -- the Cog Yeti heals after a shot that never touched it
        local b = state.boss
        if b and not b.lit and b.ability == "yeti" and not state.bossHitThisShot and b.hp < b.maxhp then
            b.hp = b.hp + 1
            push(events, { type = "boss_heal", x = b.x, y = b.y, hp = b.hp })
        end
        if state.ballsLeft > 0 then
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
    if state.phase == E.PHASE.FEVER and state.feverSlow then dt = dt * E.FEVER_SLOWMO
    elseif state.lastSlow then dt = dt * E.LAST_SLOWMO end
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
