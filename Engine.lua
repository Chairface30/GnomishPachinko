--[[
    Gnomish Pachinko - Engine.lua
    The peg-shooter's physics and rules. Pure Lua, no frame API: UI.lua
    draws whatever this produces and tests/engine_test.py drives it headless.

    Field pixels, origin top-left, y grows DOWNWARD (the UI anchors every
    texture TOPLEFT at (x, -y)).

    Pieces: round pegs and BRICKS (rotated rectangles, like the brick arcs
    in the Pogo Peggle). Both share the peg record: { shape, x, y, kind,
    lit, gone } with w/h/angle on bricks. Kinds: blue (points), orange
    (clear them all), green (the level's power), purple (one bonus peg,
    moves every shot).

    A level: AIM (Aim/Guide, Launch on click) -> FLIGHT (Step) -> AIM when
    the ball drains, FEVER the moment the last orange lights -> OVER with
    state.result (cleared or out of balls).
]]

local GP = GnomishPachinko
GP.Engine = GP.Engine or {}
local E = GP.Engine

E.FIELD_W, E.FIELD_H = 540, 600
E.BALL_R      = 7
E.PEG_R       = 9
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

E.BUCKET_W     = 84
E.BUCKET_H     = 16
E.BUCKET_SPEED = 130
E.FEVER_SLOWMO = 0.35
E.FEVER_BINS   = { 10000, 50000, 100000, 50000, 10000 }
E.FEVER_BALL_BONUS = 10000
E.FREE_BALL_SCORES = { 25000, 75000, 125000 }

E.BALLS       = 10
E.PEG_POINTS  = { blue = 10, orange = 100, green = 10, purple = 500 }
E.BLAST_RADIUS = 85
E.GUIDE_SHOTS = 3

E.PHASE = { AIM = "AIM", FLIGHT = "FLIGHT", FEVER = "FEVER", OVER = "OVER" }

-- The green-peg powers, unlocked one per chapter then cycled.
E.POWERS = {
    { id = "multiball", name = "Multiball",   blurb = "The ball splits in two." },
    { id = "guide",     name = "Super Guide", blurb = "See the whole bounce path for three shots." },
    { id = "blast",     name = "Space Blast", blurb = "Lights every peg near the green one." },
    { id = "fireball",  name = "Fireball",    blurb = "The ball burns straight through pegs." },
    { id = "spooky",    name = "Spooky Ball", blurb = "A lost ball comes back in from the top." },
}

local W, H = E.FIELD_W, E.FIELD_H
local sin, cos, sqrt, floor, abs = math.sin, math.cos, math.sqrt, math.floor, math.abs
local atan2 = math.atan2 or math.atan
local pi = math.pi

function E:ScoreMultiplier(orangesHit)
    if orangesHit >= 25 then return 10 end
    if orangesHit >= 20 then return 5 end
    if orangesHit >= 15 then return 3 end
    if orangesHit >= 10 then return 2 end
    return 1
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
        local rr = R + E.PEG_R
        local d2 = dx * dx + dy * dy
        if d2 >= rr * rr then return nil end
        local d = sqrt(d2)
        if d < 0.0001 then return rr, 0, -1 end
        return rr - d, dx / d, dy / d
    end
end
E.PegContact = pegContact

-- Bounding radius used for spacing checks.
local function pegRadius(p)
    if p.shape == "brick" then return sqrt(p.w * p.w + p.h * p.h) / 2 end
    return E.PEG_R
end
E.PegRadius = pegRadius

-- ---------------------------------------------------------------------
-- State

-- pegs: list from Levels; power: id; balls: count
function E:NewLevel(spec)
    local state = {
        level = spec.level,
        chapter = spec.chapter,
        name = spec.name,
        seed = spec.seed,
        layout = spec.layout,
        pegs = spec.pegs,
        orangeTotal = spec.orange,
        power = spec.power,
        balls = {},
        ballsLeft = spec.balls or E.BALLS,
        ballsFired = 0,
        orangeLeft = spec.orange,
        orangeHit = 0,
        score = 0,
        freeBallIdx = 1,
        superGuide = 0,
        phase = E.PHASE.AIM,
        aim = 0,
        time = 0,
        acc = 0,
        bucket = { x = W / 2, dir = 1 },
        feverBin = nil,
        result = nil,
        rng = E.NewRng((spec.seed or 1) + 977),
    }
    self:MovePurple(state)
    return state
end

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

function E:Launch(state)
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
    if state.superGuide > 0 then state.superGuide = state.superGuide - 1 end
    state.phase = E.PHASE.FLIGHT
    return true
end

-- ---------------------------------------------------------------------
-- Simulation

local function push(events, ev)
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

local lightPeg

local function applyPower(state, p, ball, events)
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
            if not q.lit and not q.gone then
                local dx, dy = q.x - p.x, q.y - p.y
                if dx * dx + dy * dy <= r2 then lightPeg(state, q, nil, events, true) end
            end
        end
    elseif power == "fireball" and ball then
        ball.fire = true
    elseif power == "spooky" and ball then
        ball.spooky = (ball.spooky or 0) + 1
    end
    push(events, { type = "power", power = power, x = p.x, y = p.y })
end

lightPeg = function(state, p, ball, events, quiet)
    p.lit = true
    p.hitAt = state.time
    local pts
    if p.kind == "orange" then
        state.orangeHit = state.orangeHit + 1
        state.orangeLeft = state.orangeLeft - 1
        pts = E.PEG_POINTS.orange * E:ScoreMultiplier(state.orangeHit)
    else
        pts = (E.PEG_POINTS[p.kind] or 10) * E:ScoreMultiplier(state.orangeHit)
    end
    addScore(state, pts, events)
    push(events, { type = "peg", peg = p, points = pts, x = p.x, y = p.y, quiet = quiet })

    if p.kind == "green" then applyPower(state, p, ball, events) end

    if p.kind == "orange" and state.orangeLeft == 0 and state.phase ~= E.PHASE.FEVER then
        state.phase = E.PHASE.FEVER
        push(events, { type = "fever" })
    end
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

-- Resolve the ball against every peg. light=false runs the guide's dry
-- simulation (bounces only).
collideBall = function(state, ball, events, light)
    local R = E.BALL_R
    for _, p in ipairs(state.pegs) do
        if not p.gone then
            local depth, nx, ny = pegContact(p, ball.x, ball.y, R)
            if depth then
                if ball.fire and light then
                    -- a fireball burns through: light it, keep flying
                    if not p.lit then lightPeg(state, p, ball, events) end
                else
                    ball.x, ball.y = ball.x + nx * depth, ball.y + ny * depth
                    local vn = ball.vx * nx + ball.vy * ny
                    if vn < 0 then
                        local k = (1 + E.RESTITUTION) * vn
                        ball.vx = ball.vx - k * nx
                        ball.vy = ball.vy - k * ny
                        if light then push(events, { type = "bounce", peg = p, speed = -vn }) end
                    end
                    if light and not p.lit then lightPeg(state, p, ball, events) end
                end
            end
        end
    end
end

local function finishLevel(state, events)
    local cleared = state.orangeLeft == 0
    if cleared then
        local bonus = state.ballsLeft * E.FEVER_BALL_BONUS + (state.feverBin or 0)
        state.score = state.score + bonus
    end
    state.result = {
        cleared = cleared,
        score = state.score,
        oranges = state.orangeHit,
        binScore = state.feverBin,
        ballsLeft = state.ballsLeft,
        level = state.level,
    }
    state.phase = E.PHASE.OVER
    push(events, { type = "level_over", result = state.result })
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

    if state.phase == E.PHASE.FEVER then
        if ball.y + R >= H - 2 then
            local idx = floor(ball.x / (W / #E.FEVER_BINS)) + 1
            if idx < 1 then idx = 1 elseif idx > #E.FEVER_BINS then idx = #E.FEVER_BINS end
            local pts = E.FEVER_BINS[idx]
            if not state.feverBin then state.feverBin = pts end
            push(events, { type = "bin", index = idx, points = pts, x = ball.x })
            return false
        end
    else
        local b = state.bucket
        local top = bucketTop()
        if ball.vy > 0 and ball.y + R >= top and ball.y - R <= top + E.BUCKET_H then
            local half = E.BUCKET_W / 2
            local off = ball.x - b.x
            if abs(off) <= half - R then
                state.ballsLeft = state.ballsLeft + 1
                push(events, { type = "bucket", x = ball.x })
                return false
            elseif abs(off) <= half + R then
                ball.y = top - R
                ball.vy = -ball.vy * 0.45
                ball.vx = ball.vx + (off > 0 and 60 or -60)
            end
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

local function substep(state, dt, events)
    state.time = state.time + dt
    if state.phase ~= E.PHASE.FEVER then moveBucket(state, dt) end
    if state.phase == E.PHASE.AIM or state.phase == E.PHASE.OVER then return end

    for i = #state.balls, 1, -1 do
        local ball = state.balls[i]
        if not integrateBall(state, ball, dt, events) then
            table.remove(state.balls, i)
        end
    end

    if #state.balls == 0 then
        if state.phase == E.PHASE.FEVER then
            finishLevel(state, events)
        else
            clearLitPegs(state, events)
            if state.ballsLeft > 0 then
                state.phase = E.PHASE.AIM
                E:MovePurple(state)
                push(events, { type = "ready" })
            else
                finishLevel(state, events)
            end
        end
    end
end

function E:Step(state, dt, events)
    if dt > 0.1 then dt = 0.1 end
    if state.phase == E.PHASE.FEVER then dt = dt * E.FEVER_SLOWMO end
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
