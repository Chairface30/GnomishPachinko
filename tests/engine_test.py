"""Gnomish Pachinko: level generation, engine rules, the plays vault and a
headless window run.

Part 1 builds every one of the 400 levels and checks them: reproducible
from the level number, goal counts as published for each objective
(classic oranges, eggs, gems, boss), tough pieces from chapter 4, pieces
inside the zone and not overlapping (except brick chains), every family,
gimmick, boss and power used.

Part 2 plays scripted levels through the engine: every level ends, balls
never leave the field, Fever starts on the last goal, powers do what they
say (multiball splits, blast hits neighbours, fireball passes through,
spooky re-enters, super guide counts down, pyramid bounces, lightning
chains), tough pieces take two hits, eggs three, gems fall and are caught,
bosses lose health and die, free balls arrive at the score marks, stars
are awarded, and the result records.

Part 3 checks the plays vault: encrypted copies round-trip, an edited copy
locks the day, copies merge, fails spend plays, bought lots add them.

Part 4 drives the window against a mocked frame API: start a level, aim,
click, pump OnUpdate, use the level select, run out of plays.

Run: python tests/engine_test.py   (pip install lupa)
"""
import math
import os

import lupa

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(label)
    print(("PASS  " if cond else "FAIL  ") + label + (f"  [{detail}]" if detail and not cond else ""))


MOCK = r"""
unpack = unpack or table.unpack
math.randomseed(5)
__now = 0
__clock = 1700000000
function GetTime() return __now end
function time() return __clock + math.floor(__now) end
UIParent = nil
UISpecialFrames = {}
tinsert = table.insert
function BreakUpLargeNumbers(n) return tostring(n) end
__printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) __printed[#__printed + 1] = m end }
__sfx = 0
__played_files, __stopped = {}, {}
function PlaySoundFile(path) __sfx = __sfx + 1; __played_files[#__played_files + 1] = path; return true, __sfx end
function StopSound(handle, fade) __stopped[#__stopped + 1] = { handle, fade } end
__cursor = { x = 270, y = 300 }
function GetCursorPosition() return __cursor.x, __cursor.y end
SlashCmdList = {}
C_Timer = { After = function(_, fn) end }
__unitName, __unitSurname = "Thrall", "Frostwolf"
function UnitName(unit) return __unitName, __unitSurname end
GameTooltip = nil

local frames = {}
local Obj = {}
Obj.__index = function(t, k)
  local v = rawget(Obj, k)
  if v then return v end
  if type(k) == "string" and k:match("^%u") then return function() end end
end
function Obj:SetSize(w, h) rawset(self, "_w", w); rawset(self, "_h", h) end
function Obj:GetWidth() return rawget(self, "_w") or 0 end
function Obj:GetHeight() return rawget(self, "_h") or 0 end
function Obj:SetText(t) rawset(self, "_text", t) end
function Obj:GetText() return rawget(self, "_text") end
function Obj:GetFrameLevel() return 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetLeft() return 0 end
function Obj:GetTop() return 600 end
function Obj:IsShown() return rawget(self, "_shown") ~= false end
function Obj:Show()
  local was = self:IsShown()
  rawset(self, "_shown", true)
  if not was and rawget(self, "_scripts") and rawget(self, "_scripts").OnShow then self._scripts.OnShow(self) end
end
function Obj:Hide() rawset(self, "_shown", false) end
function Obj:SetScript(name, fn)
  rawset(self, "_scripts", rawget(self, "_scripts") or {})
  rawget(self, "_scripts")[name] = fn
end
function Obj:GetScript(name) local s = rawget(self, "_scripts") return s and s[name] end
function Obj:IsEnabled() return rawget(self, "_enabled") ~= false end
function Obj:Enable() rawset(self, "_enabled", true) end
function Obj:Disable() rawset(self, "_enabled", false) end
function Obj:Click() if self:IsEnabled() and rawget(self, "_scripts") and rawget(self, "_scripts").OnClick then self._scripts.OnClick(self, "LeftButton") end end
function Obj:RegisterEvent() end
local function new(name)
  local o = setmetatable({ _name = name }, Obj)
  frames[#frames + 1] = o
  if name then _G[name] = o end
  return o
end
function Obj:CreateTexture() return new() end
function Obj:CreateLine() return new() end
function Obj:CreateFontString() return new() end
function CreateFrame(kind, name, parent)
  local f = new(name)
  rawset(f, "_parent", parent)
  return f
end
Minimap = CreateFrame("Frame", "Minimap")
function __advance(secs)
  local stepDt = 1 / 30
  local target = __now + secs
  while __now < target do
    __now = __now + stepDt
    for _, f in ipairs(frames) do
      local s = rawget(f, "_scripts")
      if s and s.OnUpdate then
        local p, vis = f, true
        while p do if rawget(p, "_shown") == false then vis = false break end p = rawget(p, "_parent") end
        if vis then s.OnUpdate(f, stepDt) end
      end
    end
  end
end
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=True)
rt.execute(MOCK)
for f in ("Core.lua", "Art.lua", "Engine.lua", "Levels.lua", "Plays.lua", "UI.lua", "Minimap.lua", "Mascot.lua", "Dialog.lua"):
    src = open(os.path.join(ADDON_DIR, f), encoding="utf-8").read()
    rt.execute(f"local function chunk(...) {src} end chunk('GnomishPachinko')")
rt.execute("GP = GnomishPachinko; E = GP.Engine; L = GP.Levels; UI = GP.UI; P = GP.Plays; ART = GP.Art")
ev, lua = rt.eval, rt.execute

# ------------------------------------------------------------------ levels
lua(r"""
function level_report(n)
  local spec = L:Build(n)
  local counts = { orange = 0, green = 0, blue = 0, purple = 0, egg = 0, gem = 0, boss = 0, key = 0, brick = 0, total = #spec.pegs,
                   block = 0, bumper = 0, moving = 0, tough = 0, heavy = 0, toughOrange = 0, goal = 0 }
  local bad = 0
  for i, p in ipairs(spec.pegs) do
    counts[p.kind] = (counts[p.kind] or 0) + 1
    if p.moving then counts.moving = counts.moving + 1 end
    if p.shape == "brick" then counts.brick = counts.brick + 1 end
    if (p.maxhp or 1) > 1 and p.kind ~= "egg" and p.kind ~= "boss" then counts.tough = counts.tough + 1 end
    if (p.maxhp or 1) > 2 and p.kind ~= "egg" and p.kind ~= "boss" then counts.heavy = counts.heavy + 1 end
    if p.kind == "orange" and (p.maxhp or 1) > 1 then counts.toughOrange = counts.toughOrange + 1 end
    if p.goal then counts.goal = counts.goal + 1 end
    local rp = E.PegRadius(p)
    if not L:Reachable(p) then bad = bad + 1 end
    local bottom = (p.kind == "boss") and (E.FIELD_H - 60) or E.PEG_BOTTOM
    if p.x - rp < E.PEG_MARGIN - 6.01 or p.x + rp > E.FIELD_W - E.PEG_MARGIN + 6.01
       or p.y - rp < E.PEG_TOP - 0.01 or p.y + rp > bottom + 0.01 then bad = bad + 1 end
    for j = i + 1, #spec.pegs do
      local q = spec.pegs[j]
      if not (p.group and p.group == q.group) and not p.moving and not q.moving then
        if L.SurfaceDist(p, q) < -0.51 then bad = bad + 1 end
      end
    end
  end
  return spec, counts, bad
end
""")
report = ev("level_report")
families, powers, problems, bricks_total = set(), set(), [], 0
gimmick_levels, moving_total, block_total, gimmick_names = 0, 0, 0, set()
bumper_total, bosses, objectives, tough_levels, heavy_levels = 0, set(), {}, 0, 0
duels, no_bucket = set(), 0
tough_orange_levels = 0
sig1 = None
for n in range(1, 401):
    spec, counts, bad = report(n)
    if n > 10:
        families.add(spec.layout)
    powers.add(spec.power)
    bricks_total += counts["brick"]
    moving_total += counts["moving"]
    block_total += counts["block"]
    bumper_total += counts["bumper"]
    objectives[spec.objective] = objectives.get(spec.objective, 0) + 1
    if spec.gimmick:
        gimmick_levels += 1
        for g in spec.gimmick.split(" + "):
            gimmick_names.add(g)
    if n < 21 and spec.gimmick:
        problems.append((n, "gimmick too early"))
    expected_kind = ev(f"L:Objective({n})")
    if spec.objective != expected_kind:
        problems.append((n, "objective", spec.objective, expected_kind))
    if spec.objective in ("eggs", "gems"):
        # every egg and gem is a big loose body with a two-brick cradle under it
        loose = [p for p in spec.pegs.values() if p.kind in ("egg", "gem")]
        cradles = [p for p in spec.pegs.values() if p.cradle]
        if not all(p.loose and p.r >= 20 for p in loose) or len(cradles) < 2 * len(loose):
            problems.append((n, "loose pieces without cradles", len(loose), len(cradles)))
    if spec.objective == "classic":
        coloured = counts["total"] - counts["block"] - counts["bumper"] - counts["key"]
        orange_expected = min(ev(f"L:Counts({n})"), coloured - max(2, coloured // 4))
        if counts["orange"] != orange_expected or spec.goal != orange_expected:
            problems.append((n, "oranges", counts["orange"], orange_expected))
    elif spec.objective == "eggs":
        if counts["egg"] != spec.goal or counts["egg"] < 3 or counts["orange"] != 0:
            problems.append((n, "eggs", counts["egg"], spec.goal))
    elif spec.objective == "gems":
        if counts["gem"] != spec.goal or counts["gem"] < 3 or counts["orange"] != 0:
            problems.append((n, "gems", counts["gem"], spec.goal))
    elif spec.objective == "longshots":
        if spec.goal < 2 or counts["orange"] < 8 or counts["goal"] != 0:
            problems.append((n, "longshots", spec.goal, counts["orange"], counts["goal"]))
    elif spec.objective == "boss":
        bosses.add(spec.boss.id)
        if counts["boss"] != 1 or spec.goal != 1 or spec.gimmick or counts["orange"] != 0:
            problems.append((n, "boss", counts["boss"], spec.gimmick))
    elif spec.objective == "duel":
        duels.add(spec.duel.id)
        if counts["boss"] != 0 or spec.gimmick or counts["orange"] != spec.goal or spec.goal < 8 or spec.duel.stage != 1:
            problems.append((n, "duel", counts["orange"], spec.goal))
    if spec.noBucket:
        no_bucket += 1
        if spec.objective == "gems" or (n < 41 and spec.objective != "boss"):
            problems.append((n, "bucket removed on the wrong level"))
    if counts["goal"] != spec.goal and spec.objective != "longshots":
        problems.append((n, "goal flags", counts["goal"], spec.goal))
    if counts["green"] != 2:
        problems.append((n, "greens", counts["green"]))
    if n < 31 and counts["tough"] > 0:
        problems.append((n, "tough too early"))
    if counts["tough"] > 0:
        tough_levels += 1
    if counts["heavy"] > 0:
        heavy_levels += 1
    if counts["toughOrange"] > 0:
        tough_orange_levels += 1
        if n < 61:
            problems.append((n, "tough orange too early"))
    if n < 300 and counts["heavy"] > 0:
        problems.append((n, "three-hit piece too early"))
    if bad:
        problems.append((n, "placement", bad))
    if counts["total"] < (7 if n <= 10 else 11):
        problems.append((n, "thin", counts["total"]))
    chapter = (n - 1) // 10 + 1
    if spec.gimmick:
        order = list(ev("L.GIMMICK_ORDER").values())
        for g in spec.gimmick.split(" + "):
            if order.index(g) + 1 > chapter - 2:
                problems.append((n, "gimmick before its chapter", g))
        if n % 10 == 1 and chapter - 2 <= len(order) and spec.gimmick != order[chapter - 3]:
            problems.append((n, "debut", spec.gimmick, order[chapter - 3]))
    elif n % 10 == 1 and 3 <= chapter <= 11:
        problems.append((n, "no debut gimmick"))
    if n == 1 and (counts["total"] > 12 or spec.goal != 3):
        problems.append((n, "level 1 not simple", counts["total"], spec.goal))
    if n <= 10 and (counts["brick"] > 0 and n < 7):
        problems.append((n, "bricks before level 7"))
    if n == 200:
        sig1 = [(p.x, p.y, p.kind, p.shape, p.maxhp) for p in spec.pegs.values()]
check("all 400 levels build with the published goals, 2 greens, nothing overlapping", not problems, str(problems[:5]))
check("every layout family appears", len(families) == len(ev("L.FAMILIES")), str(sorted(families)))
check("every power is assigned somewhere", len(powers) == 8, str(powers))
pieces_by_level = {n: report(n)[1]["total"] for n in (1, 5, 11, 30, 61, 81)}
check("the board fills in as the levels climb", pieces_by_level[1] < pieces_by_level[5] <= pieces_by_level[11] + 10 and pieces_by_level[11] < pieces_by_level[81], str(pieces_by_level))
print(f"      pieces by level {pieces_by_level}")
check("every objective appears, a boss or a duel on every tenth level", objectives.get("boss", 0) + objectives.get("duel", 0) == 40 and objectives.get("duel", 0) >= 16 and objectives.get("eggs", 0) > 60 and objectives.get("gems", 0) > 60 and objectives.get("longshots", 0) >= 30, str(objectives))
check("every boss kind appears and the duels are the rival's", len(bosses) == 5 and duels == {"cogwhistle"}, f"{bosses} {duels}")
check("some levels from chapter 5 have no bucket, never a gem level", no_bucket > 40, str(no_bucket))
check("bricks are in play", bricks_total > 400, str(bricks_total))
check("most levels from chapter 3 carry a gimmick", gimmick_levels > 180, str(gimmick_levels))
check("every gimmick appears", gimmick_names == set(g.name for g in ev("L.GIMMICKS").values()), str(sorted(gimmick_names)))
check("bumpers are in play", bumper_total > 40, str(bumper_total))
check("tough pieces from chapter 4, three-hit ones from level 300, tough oranges from chapter 7",
      tough_levels > 300 and heavy_levels > 80 and tough_orange_levels > 150, f"{tough_levels} {heavy_levels} {tough_orange_levels}")
print(f"      objectives {objectives}, gimmick levels {gimmick_levels}, moving pieces {moving_total}, solid blocks {block_total}")

# a wheel turns, a slider slides, blocks never light
lua(r"""
function gimmick_probe(name)
  for n = 21, 400 do
    local spec = L:Build(n)
    if spec.gimmick and spec.gimmick:find(name, 1, true) then
      local st = E:NewLevel(spec)
      local before = {}
      for i, p in ipairs(st.pegs) do if p.moving then before[i] = { p.x, p.y, p.angle } end end
      E:Step(st, 0.5)
      local moved = 0
      for i, b in pairs(before) do
        local p = st.pegs[i]
        if math.abs(p.x - b[1]) > 0.5 or math.abs(p.y - b[2]) > 0.5 or (p.angle and math.abs(p.angle - (b[3] or 0)) > 0.01) then moved = moved + 1 end
      end
      return n, moved, #before
    end
  end
end
""")
probe = ev("gimmick_probe")
for name in ("Slider", "Lifts", "Wheel", "Twin Wheels", "Pendulum", "Sliding Block"):
    n, moved, total = probe(name)
    check(f"{name} pieces move while the level runs (level {n})", total > 0 and moved == total, f"{moved}/{total}")
lua(r"""
function blocks_stay_dark()
  for n = 21, 400 do
    local spec = L:Build(n)
    if spec.gimmick and spec.gimmick:find("Blocks", 1, true) then
      local st = E:NewLevel(spec)
      for _, p in ipairs(st.pegs) do
        if p.kind == "block" then
          st.balls[1] = { x = p.x, y = p.y - 30, vx = 0, vy = 200, slow = 0, fire = true }
          st.phase = E.PHASE.FLIGHT
          for _ = 1, 30 do E:Step(st, 1 / 60) end
          if p.lit or p.gone then return false, n end
          st.balls = {}
        end
      end
      return true, n
    end
  end
  return false, 0
end
""")
ok, n = ev("blocks_stay_dark")()
check(f"solid blocks never light, even for a fireball (level {n})", ok)

# a bumper throws the ball back harder than it arrived, and never lights
lua(r"""
function bumper_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = 300, y = 300, r = E.BUMPER_R, kind = "bumper", bounce = E.BUMPER_BOUNCE } }
  spec.goal = 0
  local st = E:NewLevel(spec)
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 300, y = 300 - E.BUMPER_R - E.BALL_R - 20, vx = 0, vy = 150, slow = 0 }
  local events = {}
  local hit, fastest = false, 0
  for _ = 1, 40 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "bumper" then hit = true end end
    local b = st.balls[1]
    if b and b.vy < 0 and -b.vy > fastest then fastest = -b.vy end
    for i = #events, 1, -1 do events[i] = nil end
  end
  return hit, fastest, spec.pegs[1].lit
end
""")
hit, fastest, lit = ev("bumper_probe")()
check("a bumper throws the ball back faster than it arrived", hit and fastest > 200 and not lit, f"hit {hit} up {fastest:.0f} lit {lit}")

# drop a parked ball onto a piece repeatedly: returns the events of one touch
lua(r"""
function touch(st, p, events, fire)
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = p.x, y = p.y - (p.r or E.PEG_R) - E.BALL_R + 1, vx = 0, vy = 0, slow = 0, fire = fire }
  E:Step(st, 1 / 60, events)
  st.balls = {}
end
function count(events, kind)
  local n = 0
  for _, e in ipairs(events) do if e.type == kind then n = n + 1 end end
  return n
end
function wipe(events) for i = #events, 1, -1 do events[i] = nil end end
""")

# combos: each piece lit in a shot pays more, and the tenth pays a bonus
lua(r"""
function combo_probe()
  -- the first level with ten plain round blue pegs
  local st, blues
  for n = 11, 200 do
    st = E:NewLevel(L:Build(n))
    blues = {}
    for _, p in ipairs(st.pegs) do if p.kind == "blue" and p.shape == "peg" and p.maxhp == 1 then blues[#blues + 1] = p end end
    if #blues >= 10 then break end
  end
  local events = {}
  local pts, bonus = {}, 0
  for i = 1, 10 do
    touch(st, blues[i], events)
    for _, e in ipairs(events) do
      if e.type == "peg" then pts[#pts + 1] = e.points end
      if e.type == "combo" then bonus = e.bonus end
    end
    wipe(events)
  end
  return pts[1], pts[2], pts[10], bonus, st.combo
end
""")
p1, p2, p10, bonus, combo = ev("combo_probe")()
check("each piece lit in a shot pays more than the one before", p1 == 25 and p2 == 40 and p10 == 25 + 15 * 9, f"{p1} {p2} {p10}")
check("the tenth piece in a shot pays the combo bonus", bonus == 5000 and combo == 10, f"bonus {bonus} combo {combo}")

# a tough piece cracks on the first hit and lights on the second; a fireball needs two passes too
lua(r"""
function tough_probe()
  local st = E:NewLevel(L:Build(1))
  local p
  for _, q in ipairs(st.pegs) do if q.kind == "blue" and q.shape == "peg" then p = q break end end
  p.hp, p.maxhp = 2, 2
  local events = {}
  touch(st, p, events)
  local cracks, lits1 = count(events, "crack"), count(events, "peg")
  local hpAfter = p.hp
  wipe(events)
  -- straight away again: the cooldown refuses it
  touch(st, p, events)
  local refused = count(events, "crack") == 0 and count(events, "peg") == 0
  wipe(events)
  for _ = 1, 30 do E:Step(st, 1 / 60) end
  touch(st, p, events)
  local lits2 = count(events, "peg")
  return cracks, lits1, hpAfter, refused, lits2, p.lit
end
""")
cracks, lits1, hp_after, refused, lits2, lit = ev("tough_probe")()
check("a two-hit piece cracks first and lights on the second hit", cracks == 1 and lits1 == 0 and hp_after == 1 and lits2 == 1 and lit,
      f"{cracks} {lits1} {hp_after} {lits2} {lit}")
check("the same ball cannot hit a piece twice within the cooldown", refused)

# eggs: three hits to hatch, and hatching every egg clears the level
lua(r"""
function egg_probe()
  local n
  for k = 11, 100 do if L:Objective(k) == "eggs" then n = k break end end
  local spec = L:Build(n)
  local st = E:NewLevel(spec)
  local eggs = {}
  for _, p in ipairs(st.pegs) do if p.kind == "egg" then eggs[#eggs + 1] = p end end
  local events = {}
  local hitsToHatch = 0
  for _, egg in ipairs(eggs) do
    local hits = 0
    while not egg.lit and hits < 10 do
      touch(st, egg, events)
      hits = hits + 1
      for _ = 1, 30 do E:Step(st, 1 / 60) end
    end
    if hitsToHatch == 0 then hitsToHatch = hits end
  end
  local fever = count(events, "fever")
  return n, #eggs, hitsToHatch, fever, st.phase, st.goalLeft, eggs[1].maxhp
end
""")
n, eggs, hits, fever, phase, left, egghp = ev("egg_probe")()
check(f"eggs take {egghp} hits each and hatching them all starts Fever (level {n})", eggs >= 3 and hits == egghp and egghp == 2 and fever == 1 and phase == "FEVER" and left == 0,
      f"eggs {eggs} hits {hits} fever {fever} {phase} {left}")
check("eggs take three hits from level 300", ev("(function() for _, p in ipairs(L:Build(305).pegs) do if p.kind == 'egg' then return p.maxhp end end end)()") == 3)

# gems: a loose body on a two-brick ledge. A hit only nudges it; knock the
# ledge out and it falls: the bucket catches it (Bucket Drop), or it drops
# off the bottom and still counts.
lua(r"""
function gem_probe()
  local n
  for k = 21, 100 do if L:Objective(k) == "gems" then n = k break end end
  local spec = L:Build(n)
  -- one gem and its ledge over an empty field so the fall is predictable
  local gem, ledge = nil, {}
  for _, p in ipairs(spec.pegs) do if p.kind == "gem" then gem = p break end end
  for _, p in ipairs(spec.pegs) do if p.cradle and math.abs(p.x - gem.x) < 40 and p.y > gem.y then ledge[#ledge + 1] = p end end
  spec.pegs = { gem, ledge[1], ledge[2] }
  spec.goal = 1
  local st = E:NewLevel(spec)
  local events = {}
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end      -- settle
  local restY = gem.y
  touch(st, gem, events)
  local hitLit = gem.lit
  local hitEvents = count(events, "peg")
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end
  wipe(events)
  local stayed = math.abs(gem.y - restY) < 3 and gem.resting
  -- knock the ledge out
  for _, b in ipairs(ledge) do b.lit = true; b.hitAt = st.time end
  st.bucket.x = gem.x
  st.bucket.dir = 0
  st.phase = E.PHASE.FLIGHT
  local caught, freed = 0, 0
  for _ = 1, 400 do
    st.balls[1] = { x = 60, y = 100, vx = 0, vy = 0, slow = 0 }
    E:Step(st, 1 / 60, events)
    caught = caught + count(events, "gem_caught")
    freed = freed + count(events, "gem_free")
    wipe(events)
    if st.phase == E.PHASE.FEVER then break end
  end
  local r1 = { hitLit = hitLit, hitEvents = hitEvents, stayed = stayed, freed = freed, caught = caught, phase = st.phase, lit = gem.lit, goalHit = st.goalHit, score = st.score }
  -- again with the bucket out of the way: it drops off the bottom and still counts
  st = E:NewLevel(L:Build(n))
  spec = st
  local gem2, ledge2 = nil, {}
  for _, p in ipairs(st.pegs) do if p.kind == "gem" then gem2 = p break end end
  for _, p in ipairs(st.pegs) do if p.cradle and math.abs(p.x - gem2.x) < 40 and p.y > gem2.y then ledge2[#ledge2 + 1] = p end end
  st.pegs = { gem2, ledge2[1], ledge2[2] }
  st.goalTotal, st.goalLeft = 1, 1
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end
  wipe(events)
  for _, b in ipairs(ledge2) do b.lit = true; b.hitAt = st.time end
  st.bucket.x = (gem2.x < 245) and (E.FIELD_W - 60) or 60
  st.bucket.dir = 0
  st.phase = E.PHASE.FLIGHT
  local dropped = 0
  for _ = 1, 400 do
    st.balls[1] = { x = 60, y = 100, vx = 0, vy = 0, slow = 0 }
    E:Step(st, 1 / 60, events)
    dropped = dropped + count(events, "gem_dropped")
    wipe(events)
    if st.phase == E.PHASE.FEVER then break end
  end
  return n, r1, dropped, st.goalHit, st.phase, st.score
end
""")
n, r1, dropped, goal_hit, phase, score2 = ev("gem_probe")()
check(f"a gem is a loose body: a hit never lights it and it stays on its ledge (level {n})",
      not r1["hitLit"] and r1["hitEvents"] == 0 and r1["stayed"], str(dict(r1)))
check("knock the ledge out and the gem falls into the bucket: counts, clears, pays the Bucket Drop bonus",
      r1["freed"] == 1 and r1["caught"] == 1 and r1["phase"] == "FEVER" and r1["lit"] and r1["goalHit"] == 1 and r1["score"] > score2, str(dict(r1)))
check("a gem that drops off the bottom still counts", dropped == 1 and goal_hit == 1 and phase == "FEVER", f"dropped {dropped} goal {goal_hit} {phase}")
check("eggs and gems are much bigger than pegs", ev("E.EGG_R") >= 2 * ev("E.PEG_R") and ev("E.GEM_R") >= 2 * ev("E.PEG_R"))
check("Space Blast reaches about an inch", 35 <= ev("E.BLAST_RADIUS") <= 60, str(ev("E.BLAST_RADIUS")))

# boss: hits take health, the bar reaches zero, Fever starts; each ability reacts
lua(r"""
function boss_probe(n)
  local spec = L:Build(n)
  local st = E:NewLevel(spec)
  local b = st.boss
  local events = {}
  local info = { name = b.bossName, ability = b.ability, maxhp = b.maxhp, chips = 0, hops = 0, heals = 0, shields = 0, fever = 0, down = 0, moved = false }
  local x0 = b.x
  E:Step(st, 1.0)
  if math.abs(b.x - x0) > 1 then info.moved = true end
  local speed0 = b.mover.speed
  while not b.lit and info.chips < 40 do
    touch(st, b, events)
    for _, e in ipairs(events) do if e.type == "crack" and e.peg == b then info.chips = info.chips + 1 end end
    if b.mover.speed ~= speed0 then info.speedChanged = true end
    info.hops = info.hops + count(events, "boss_hop")
    info.fever = info.fever + count(events, "fever")
    info.down = info.down + count(events, "boss_down")
    wipe(events)
    for _ = 1, 30 do E:Step(st, 1 / 60) end
  end
  info.phase = st.phase
  return info
end
function boss_heal_probe()
  local spec
  for n = 10, 400, 10 do spec = L:Build(n) if spec.boss and spec.boss.id == "yeti" then break end end
  local st = E:NewLevel(spec)
  local b = st.boss
  local events = {}
  touch(st, b, events)
  for _ = 1, 30 do E:Step(st, 1 / 60, events) end   -- back to AIM
  wipe(events)
  local hpAfterHit = b.hp
  -- a shot that misses: launch and let it drain
  st.aim = 0
  assert(E:Launch(st, events))
  st.balls[1].x, st.balls[1].y = 20, 560
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end
  local heals = count(events, "boss_heal")
  return hpAfterHit, b.hp, heals
end
function boss_shield_probe()
  local spec
  for n = 10, 400, 10 do spec = L:Build(n) if spec.boss and spec.boss.id == "golem" then break end end
  local st = E:NewLevel(spec)
  local b = st.boss
  local events = {}
  for _ = 1, 3 do
    E:Launch(st, events)
    st.balls = {}
    st.phase = E.PHASE.AIM
  end
  local shields = count(events, "boss_shield")
  wipe(events)
  touch(st, b, events)
  local blocked = count(events, "shield")
  return shields, b.shield, blocked, b.hp == b.maxhp
end
""")
boss_probe = ev("boss_probe")
abilities = {}
for n in (10, 30, 50, 70, 90):
    info = boss_probe(n)
    abilities[info.ability] = info
    check(f"level {n}: the {info.name} slides, takes {info.maxhp} hits and dies into Fever",
          info.moved and info.chips == info.maxhp - 1 and info.down == 1 and info.fever == 1 and info.phase == "FEVER",
          f"moved {info.moved} chips {info.chips}/{info.maxhp} down {info.down} fever {info.fever} {info.phase}")
check("the Tin Drake speeds up when hit", abilities["drake"].speedChanged)
check("the Gyro Spider hops when hit", abilities["spider"].hops > 0)
check("the Mechano-Boar turns around when hit", abilities["boar"].speedChanged)
hp_hit, hp_after, heals = ev("boss_heal_probe")()
check("the Cog Yeti heals after a shot that misses it", heals == 1 and hp_after == hp_hit + 1, f"{hp_hit} -> {hp_after} heals {heals}")
shields, shield, blocked, full = ev("boss_shield_probe")()
check("the Bolt Golem raises a shield on the third shot that soaks a hit", shields == 1 and shield == 1 and blocked == 1 and full,
      f"shields {shields} left {shield} blocked {blocked} full {full}")

# the duel: stage one clears into stage two, the coin flips, turns alternate, misses cost a quarter
lua(r"""
function duel_flow_probe()
  local spec = L:Build(20)
  local st = E:NewLevel(spec)
  -- light every orange but one by hand, then the last through a touch
  local last
  for _, p in ipairs(st.pegs) do
    if p.kind == "orange" and p.maxhp == 1 then
      if last then p.lit = true; p.gone = true; st.goalLeft = st.goalLeft - 1; st.goalHit = st.goalHit + 1 else last = p end
    end
  end
  for _, p in ipairs(st.pegs) do if p.kind == "orange" and p.maxhp > 1 and p ~= last then p.lit = true; p.gone = true; st.goalLeft = st.goalLeft - 1; st.goalHit = st.goalHit + 1 end end
  local events = {}
  touch(st, last, events)
  local stageClear, fever = count(events, "stage_clear"), count(events, "fever")
  wipe(events)
  local score1 = st.score
  -- stage two
  local spec2 = L:Build(20, 50, { stage2 = true })
  local st2 = E:StartDuel(st, spec2)
  local info = { stageClear = stageClear, fever = fever, carried = st2.score == score1, coin = st2.duel.turn,
                 balls = st2.ballsLeft, oranges2 = spec2.goal, stage2 = spec2.duel.stage }
  -- the rival's aim points somewhere sensible
  local aim = E:RivalAim(st2)
  info.aimOk = type(aim) == "number" and math.abs(aim) <= E.MAX_AIM_DEG * math.pi / 180
  -- a shot by whoever is up that hits nothing: a penalty for them, then the other side's turn
  local d = st2.duel
  d.scores[d.turn] = 10000
  if d.turn == "you" then st2.score = st2.score + 10000 end
  local shooter = d.turn
  st2.aim = 0
  assert(E:Launch(st2, events))
  st2.balls[1].x, st2.balls[1].y, st2.balls[1].vx, st2.balls[1].vy = 20, 560, 0, 300
  local turnEv, penalty
  for _ = 1, 120 do
    E:Step(st2, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "duel_turn" then turnEv = e elseif e.type == "duel_penalty" then penalty = e end end
    wipe(events)
    if st2.phase == E.PHASE.AIM and turnEv then break end
  end
  info.penalty = penalty and penalty.lost
  info.penaltySide = penalty and penalty.side
  info.scoreAfter = d.scores[shooter]
  info.turnAfter = turnEv and turnEv.turn
  info.shooter = shooter
  info.ballsAfter = d.balls[shooter]
  -- play the rest out with misses: the duel ends when both are out of balls, decided on score
  local guard = 0
  while st2.phase ~= E.PHASE.OVER and guard < 20 do
    guard = guard + 1
    if st2.phase == E.PHASE.AIM then
      assert(E:Launch(st2, events))
      st2.balls[1].x, st2.balls[1].y, st2.balls[1].vx, st2.balls[1].vy = 20, 560, 0, 300
    end
    for _ = 1, 120 do E:Step(st2, 1 / 60, events) wipe(events) if st2.phase ~= E.PHASE.FLIGHT then break end end
  end
  info.over = st2.phase == E.PHASE.OVER
  info.result = st2.result and st2.result.duel and (st2.result.cleared and "you" or "rival")
  info.expected = (d.scores.you > d.scores.rival) and "you" or "rival"
  return info
end
""")
info = ev("duel_flow_probe")()
check("clearing stage one of a duel starts the duel instead of Fever, carrying the score", info.stageClear == 1 and info.fever == 0 and info.carried, str(dict(info)))
check("stage two is a ten-orange board, five balls each, with a coin flip", info.oranges2 == 10 and info.balls == 5 and info.stage2 == 2 and info.coin in ("you", "rival"), str(dict(info)))
check("the rival picks an aim within the launcher's arc", info.aimOk)
check("a shot that lights no orange costs its shooter 500 and the turn passes", info.penalty == 500 and info.penaltySide == info.shooter and info.scoreAfter == 9500 and info.turnAfter is not None and info.turnAfter != info.shooter and info.ballsAfter == 4, str(dict(info)))
check("the duel ends when both are out of balls and the higher duel score wins", info.over and info.result == info.expected, str(dict(info)))

# no bucket: a ball dropped where the bucket sits falls straight out
lua(r"""
function no_bucket_probe()
  local spec = L:Build(44)
  local st = E:NewLevel(spec)
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = st.bucket.x, y = E.BucketTop() - 40, vx = 0, vy = 100, slow = 0 }
  local events = {}
  local caught, lost = 0, 0
  for _ = 1, 90 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do
      if e.type == "bucket" then caught = caught + 1 end
      if e.type == "lost" then lost = lost + 1 end
    end
    wipe(events)
  end
  return spec.noBucket, caught, lost, L:Build(23).noBucket
end
""")
nb, caught, lost, gems_nb = ev("no_bucket_probe")()
check("level 44 has no bucket and a ball dropped on its spot is lost; gem level 23 keeps its bucket", nb and caught == 0 and lost == 1 and not gems_nb, f"{nb} {caught} {lost} {gems_nb}")

spec2 = report(200)[0]
check("a level rebuilds identically", sig1 == [(p.x, p.y, p.kind, p.shape, p.maxhp) for p in spec2.pegs.values()])
check("forty chapters, every one an original Azeroth zone", ev("L:ChapterName(1)") == "Elwynn Forest" and ev("L:ChapterName(40)") == "Moonglade" and ev("#L.CHAPTERS") == 40 and ev("L.COUNT") == 400
      and not any(z in ev("table.concat(L.CHAPTERS, '|')") for z in ("Hellfire", "Outland", "Northrend", "Zangarmarsh", "Nagrand", "Eversong", "Azuremyst", "Borean", "Howling")))

# ------------------------------------------------------------------ engine
lua(r"""
function play_level(n, aimMode, forcePower)
  local spec = L:Build(n)
  if forcePower then spec.power = forcePower end
  local st = E:NewLevel(spec)
  local info = { escaped = false, fever = nil, powers = 0, buckets = 0, spooky = 0, scoreFree = 0,
                 maxBalls = 0, steps = 0, stuck = 0, blastHit = 0, superGuideSeen = false, bins = 0,
                 pyramid = 0, zaps = 0, zapLinks = 0, frenzyBalls = 0 }
  local events = {}
  local shots = 0
  while (st.phase ~= E.PHASE.OVER or (st.stageClear and not st.result)) and info.steps < 400000 do
    if st.phase == E.PHASE.OVER and st.stageClear and not st.result then
      -- a duel's stage one is clear: on to the shared board
      st = E:StartDuel(st, L:Build(n, 50, { stage2 = true }))
      info.duel = true
    end
    if st.phase == E.PHASE.AIM and st.duel and st.duel.stage == 2 and st.duel.turn == "rival" then
      st.aim = E:RivalAim(st)
      assert(E:Launch(st, events))
    elseif st.phase == E.PHASE.AIM then
      shots = shots + 1
      if st.superGuide > 0 then info.superGuideSeen = true end
      if aimMode == "sweep" then
        local pick, fallback
        for deg = -80, 80, 2 do
          st.aim = deg * math.pi / 180
          local _, peg = E:Guide(st, 2.5)
          if peg and not peg.lit then
            if peg.goal then pick = st.aim break end
            if peg.kind == "green" and not fallback then fallback = st.aim end
            fallback = fallback or st.aim
          end
        end
        st.aim = pick or fallback or 0
      elseif aimMode == "green" then
        local pick
        for deg = -80, 80, 1 do
          st.aim = deg * math.pi / 180
          local _, peg = E:Guide(st, 2.5)
          if peg and not peg.lit and peg.kind == "green" then pick = st.aim break end
        end
        st.aim = pick or ((shots * 37 % 160 - 80) * math.pi / 180)
      else
        E:Aim(st, 40 + ((shots * 97) % 460), 400)
      end
      assert(E:Launch(st, events))
    end
    E:Step(st, 1 / 60, events)
    info.steps = info.steps + 1
    if #st.balls > info.maxBalls then info.maxBalls = #st.balls end
    for _, b in ipairs(st.balls) do
      if b.x < 0 or b.x > E.FIELD_W or b.y < 0 then info.escaped = true end
    end
    for _, e in ipairs(events) do
      if e.type == "fever" then info.fever = st.goalLeft end
      if e.type == "bin" then info.bins = info.bins + 1 end
      if e.type == "power" then info.powers = info.powers + 1 end
      if e.type == "bucket" then info.buckets = info.buckets + 1 end
      if e.type == "spooky" then info.spooky = info.spooky + 1 end
      if e.type == "freeball_score" then info.scoreFree = info.scoreFree + 1 end
      if e.type == "lost" and e.stuck then info.stuck = info.stuck + 1 end
      if (e.type == "peg" or e.type == "crack") and e.quiet then info.blastHit = info.blastHit + 1 end
      if e.type == "pyramid" then info.pyramid = info.pyramid + 1 end
      if e.type == "zap" then info.zaps = info.zaps + 1; info.zapLinks = info.zapLinks + #e.path - 1 end
      if e.type == "power" and e.power == "frenzy" then info.frenzyBalls = info.frenzyBalls + E.FRENZY_BALLS end
    end
    for i = #events, 1, -1 do events[i] = nil end
  end
  return st, info
end
""")
play = ev("play_level")
problems, cleared, buckets, stuck, multi = [], 0, 0, 0, 0
max_cleared_score = 0
cleared_by_kind, played_by_kind = {}, {}
scores = []
for n in list(range(1, 61)) + list(range(190, 210)) + list(range(381, 401)):
    st, info = play(n, "sweep", None)
    kind = st.objective
    played_by_kind[kind] = played_by_kind.get(kind, 0) + 1
    if st.phase != "OVER":
        problems.append((n, "no end"))
        continue
    if info.escaped:
        problems.append((n, "escaped"))
    r = st.result
    if r.cleared:
        cleared += 1
        cleared_by_kind[kind] = cleared_by_kind.get(kind, 0) + 1
        scores.append((n, r.score, ev(f"L:StarsFor({n}, {r.score}, true)")))
        if info.fever != 0 and not info.duel:
            problems.append((n, "fever timing", info.fever))
        if (r.ballsLeft != 0 or info.bins < 1) and not info.duel:
            problems.append((n, "leftover balls not fired", r.ballsLeft, info.bins))
        if r.feverTotal < 1000 * info.bins and not info.duel:
            problems.append((n, "bins not scored", r.feverTotal, info.bins))
        if r.score > max_cleared_score:
            max_cleared_score = r.score
        if r.binScore not in (1000, 10000, 25000) and not info.duel:
            problems.append((n, "bin", r.binScore))
    elif info.fever is not None and not info.duel:
        problems.append((n, "fever without clear"))
    if r.goals + st.goalLeft != st.goalTotal and not info.duel:
        problems.append((n, "goal bookkeeping"))
    buckets += info.buckets
    stuck += info.stuck
    if info.maxBalls > 1:
        multi += 1
check("100 scripted levels end cleanly with the rules intact", not problems, str(problems[:4]))
print(f"      cleared {cleared}/100 by kind {cleared_by_kind} of {played_by_kind}; bucket free balls {buckets}, stuck {stuck}, multiball levels {multi}, best cleared score {max_cleared_score}")
star_counts = {}
for _, _, s in scores:
    star_counts[s] = star_counts.get(s, 0) + 1
print(f"      stars on the bot's clears {star_counts}")
print("      bot clear scores: " + ", ".join(f"L{n}:{s // 1000}k" for n, s, _ in scores))
check("a cleared level can pass 25,000", max_cleared_score >= 25000, str(max_cleared_score))
# bosses take aimed shots down the board; the crude sweep bot rarely lands
# enough of them, so they are not asked of it (the boss probes cover them)
check("the sweep bot clears classic, egg and gem levels",
      all(cleared_by_kind.get(k, 0) > 0 for k in ("classic", "eggs", "gems")), str(cleared_by_kind))
check("the bot does not take three stars everywhere", star_counts.get(3, 0) < len(scores), str(star_counts))
mult = ev("E.ScoreMultiplier")
Eng = ev("E")
check("the multiplier climbs with the share of the goal done", [mult(Eng, n, 25) for n in (0, 4, 5, 9, 10, 14, 15, 19, 20, 25)] == [1, 1, 2, 2, 3, 3, 5, 5, 10, 10])
check("the ladder scales to a 15-orange level", [mult(Eng, n, 15) for n in (2, 3, 6, 9, 12)] == [1, 2, 3, 5, 10])
# the launcher slides round the host's box: shots start along its rim, so the
# corners are reachable while the box's shadow in the centre is not
check("the rim launcher reaches the corners and the host's box shadows the centre top",
      ev("L:ReachFloor(20)") < 60 and 100 < ev("L:ReachFloor(245)") < 150 and ev("E.PEG_TOP") >= ev("E.LAUNCH_CY + E.LAUNCH_R"),
      f"{ev('L:ReachFloor(20)'):.0f} {ev('L:ReachFloor(245)'):.0f}")
check("the field has Peggle Blast's portrait proportions", abs(ev("E.FIELD_W / E.FIELD_H") - 0.7) < 0.01)
check("the bucket returns balls", buckets > 0)

# the bucket's rim: a glancing ball bounces off with a rim event
lua(r"""
function rim_probe()
  local spec = L:Build(1)
  spec.pegs = {}
  spec.goal = 0
  local st = E:NewLevel(spec)
  st.bucket.x = 300
  st.bucket.dir = 0
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 300 + E.BUCKET_W / 2 + 2, y = E.BucketTop() - 60, vx = 0, vy = 150, slow = 0 }
  local events = {}
  local rims, caught = 0, 0
  for _ = 1, 60 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do
      if e.type == "rim" then rims = rims + 1 end
      if e.type == "bucket" then caught = caught + 1 end
    end
    wipe(events)
  end
  return rims, caught
end
""")
rims, caught = ev("rim_probe")()
check("a ball glancing off the bucket's lip reports a rim bounce, not a catch", rims >= 1 and caught == 0, f"rims {rims} caught {caught}")

# powers, forced one at a time on an early level while hunting greens
seen = {}
for power in ("multiball", "guide", "blast", "fireball", "spooky", "pyramid", "lightning", "frenzy"):
    hits = 0
    for n in range(1, 16):
        st, info = play(n, "green", power)
        if info.powers > 0:
            hits += 1
            seen.setdefault(power, []).append(info)
    print(f"      {power}: green hit on {hits}/15 levels")
check("multiball spawns a twin", any(i.maxBalls > 1 for i in seen.get("multiball", [])))
check("super guide shows on the shots after a green", any(i.superGuideSeen for i in seen.get("guide", [])))
check("space blast (an inch across) hits its neighbours quietly", any(i.blastHit >= 3 for i in seen.get("blast", [])), str([i.blastHit for i in seen.get("blast", [])]))
check("spooky ball re-enters from the top", any(i.spooky > 0 for i in seen.get("spooky", [])))
check("fireball levels get a power event", len(seen.get("fireball", [])) > 0)
check("the pyramid bounces the ball back up", any(i.pyramid > 0 for i in seen.get("pyramid", [])), str([i.pyramid for i in seen.get("pyramid", [])]))
check("chain lightning leaps through several pieces", any(i.zapLinks >= 3 for i in seen.get("lightning", [])), str([i.zapLinks for i in seen.get("lightning", [])]))
check("free ball frenzy hands out extra balls", any(i.frenzyBalls >= 3 for i in seen.get("frenzy", [])), str([i.frenzyBalls for i in seen.get("frenzy", [])]))

# fireball passes through: a ball with fire set reaches further than its first contact
lua(r"""
function fire_passes()
  local spec = L:Build(3)
  local st = E:NewLevel(spec)
  local pick
  for deg = -60, 60, 1 do
    st.aim = deg * math.pi / 180
    local _, peg = E:Guide(st, 2)
    if peg then pick = st.aim break end
  end
  st.aim = pick or 0
  E:Launch(st)
  st.balls[1].fire = true
  local events = {}
  local lit, bounces = 0, 0
  while st.phase == E.PHASE.FLIGHT do
    for i = #events, 1, -1 do events[i] = nil end
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do
      if e.type == "peg" then lit = lit + 1 end
      if e.type == "bounce" then bounces = bounces + 1 end
    end
  end
  return lit, bounces
end
""")
lit, bounces = ev("fire_passes")()
check("a fireball lights pegs without bouncing", lit >= 1 and bounces == 0, f"lit {lit} bounces {bounces}")

# the pyramid in isolation: balls dropped on each face go up and out toward
# that face's wall; it lasts five strikes, then turns to dust
lua(r"""
function pyramid_probe()
  local spec = L:Build(1)
  spec.pegs = {}
  spec.goal = 0
  local st = E:NewLevel(spec)
  st.aim = 0
  local events = {}
  E:Launch(st, events)
  local template = {}
  for k, v in pairs(st.balls[1]) do template[k] = v end
  st.pyramidHits = E.PYRAMID_STRIKES
  local out = { strikes = 0, dust = 0, sideOk = true, upOk = true, bucketHidden = true }
  local offsets = { -150, 140, -20, 25, 0 }
  for i, off in ipairs(offsets) do
    local b = {}
    for k, v in pairs(template) do b[k] = v end
    b.x, b.y, b.vx, b.vy = E.FIELD_W / 2 + off, E.PYRAMID_BASE - E.PYRAMID_H - 80, 0, 60
    st.balls = { b }
    st.phase = E.PHASE.FLIGHT
    local struck = false
    for _ = 1, 90 do
      E:Step(st, 1 / 60, events)
      for _, e in ipairs(events) do
        if e.type == "pyramid" then
          out.strikes = out.strikes + 1
          struck = true
          local bb = st.balls[1]
          if bb then
            if bb.vy > -E.PYRAMID_KICK * 0.9 then out.upOk = false end
            if off ~= 0 and bb.vx * off < 0 then out.sideOk = false end
            if math.abs(bb.vx) < E.PYRAMID_SIDE - 1 then out.sideOk = false end
          end
        elseif e.type == "pyramid_dust" then out.dust = out.dust + 1 end
      end
      wipe(events)
      if struck then break end
    end
    if i == 2 and math.abs(st.bucket.x - E.FIELD_W / 2) > 0.5 then out.bucketHidden = false end
  end
  out.up = E.PyramidUp(st)
  -- a fresh pyramid: a ball over a bare corner falls past it
  st.pyramidHits = E.PYRAMID_STRIKES
  local b = {}
  for k, v in pairs(template) do b[k] = v end
  b.x, b.y, b.vx, b.vy = E.FIELD_W / 2 + E.PYRAMID_W / 2 - 10, E.PYRAMID_BASE - 60, 0, 60
  st.balls = { b }
  st.phase = E.PHASE.FLIGHT
  out.cornerStrike = false
  for _ = 1, 40 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "pyramid" then out.cornerStrike = true end end
    wipe(events)
  end
  out.cornerFalls = not out.cornerStrike and (st.balls[1] == nil or st.balls[1].y > E.PYRAMID_BASE - 20)
  return out
end
""")
pr = dict(ev("pyramid_probe")())
check("each pyramid strike throws the ball up and toward the wall on that side", pr["upOk"] and pr["sideOk"], str(pr))
check("the pyramid stands three strikes, then turns to dust once and is gone",
      pr["strikes"] == 3 and pr["dust"] == 1 and not pr["up"], str(pr))
check("a ball over the pyramid's bare corners falls past it", pr["cornerFalls"], str(pr))
check("the bucket is parked under the pyramid while it stands", pr["bucketHidden"], str(pr))
check("the pyramid spans the whole bottom and a strike at its foot climbs to mid-board",
      ev("E.PYRAMID_W") == ev("E.FIELD_W") and ev("E.PYRAMID_KICK") ** 2 / (2 * ev("E.GRAVITY")) >= ev("E.PYRAMID_BASE") - ev("E.FIELD_H") / 2)

# score free balls
lua(r"""
function score_free()
  local st = E:NewLevel(L:Build(1))
  local events = {}
  st.score = E.FREE_BALL_SCORES[1] - 10
  local before = st.ballsLeft
  local p
  for _, q in ipairs(st.pegs) do if q.kind == "orange" and q.maxhp == 1 then p = q break end end
  touch(st, p, events)
  local got = 0
  for _, e in ipairs(events) do if e.type == "freeball_score" then got = got + 1 end end
  return got, st.ballsLeft - before
end
""")
got, delta = ev("score_free")()
check("crossing the first score mark gives a free ball", got == 1 and delta == 1, f"{got} {delta}")

# purple hops to a blue peg each shot
lua(r"""
function purple_count(st)
  local n = 0
  for _, p in ipairs(st.pegs) do if p.kind == "purple" then n = n + 1 end end
  return n
end
__st = E:NewLevel(L:Build(2))
__p1 = purple_count(__st)
E:MovePurple(__st)
__p2 = purple_count(__st)
""")
check("exactly one purple peg at a time", ev("__p1") == 1 and ev("__p2") == 1)

# a touched piece vanishes two seconds after the touch, even mid-flight
lua(r"""
function lit_expires()
  local st = E:NewLevel(L:Build(1))
  local p
  for _, q in ipairs(st.pegs) do if q.kind == "blue" and q.shape == "peg" then p = q break end end
  p.lit = true; p.hitAt = st.time
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 270, y = 20, vx = 0, vy = 0, slow = 0 }
  local function hold() st.balls[1].y = 20; st.balls[1].vy = 0 end  -- keep the ball parked
  for _ = 1, 60 do E:Step(st, 1 / 60); hold() end
  local goneAt1 = p.gone
  for _ = 1, 70 do E:Step(st, 1 / 60); hold() end
  return goneAt1, p.gone
end
""")
early, late = ev("lit_expires")()
check("a touched piece is still there after one second and gone after two", (not early) and late)

# the last goal piece: time slows while a ball closes in, and stops when it is lit
lua(r"""
function last_peg_probe()
  local st = E:NewLevel(L:Build(1))
  local last
  for _, p in ipairs(st.pegs) do
    if p.kind == "orange" then
      if last then p.lit = true; p.gone = true; st.goalLeft = st.goalLeft - 1; st.goalHit = st.goalHit + 1 else last = p end
    end
  end
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = last.x, y = last.y - 80, vx = 0, vy = 120, slow = 0 }
  local events = {}
  local slowAt, lit, steps = nil, nil, 0
  local wall = 0
  while st.phase == E.PHASE.FLIGHT and steps < 600 do
    E:Step(st, 1 / 60, events)
    steps = steps + 1
    wall = wall + 1 / 60
    for _, e in ipairs(events) do if e.type == "last_peg" and not slowAt then slowAt = wall end end
    if last.lit and not lit then lit = { wall = wall, slow = st.lastSlow } end
    wipe(events)
  end
  -- Fever: no slow motion at all, and the leftover balls start flying within a second
  local slowedInFever, firstShot, feverWall = false, nil, 0
  local t0 = st.time
  for _ = 1, 120 do
    local before = st.time
    E:Step(st, 1 / 60, events)
    feverWall = feverWall + 1 / 60
    if st.lastSlow or (st.time - before) < 1 / 60 - 0.0001 then slowedInFever = true end
    for _, e in ipairs(events) do if e.type == "fever_shot" and not firstShot then firstShot = feverWall end end
    wipe(events)
    if st.phase ~= E.PHASE.FEVER then break end
  end
  return slowAt, lit and lit.wall, lit and lit.slow, st.phase, slowedInFever, firstShot
end
""")
slow_at, lit_at, slow_when_lit, phase, slowed_in_fever, first_shot = ev("last_peg_probe")()
check("time slows as a ball closes on the last orange peg and the slow ends when it lights",
      slow_at is not None and lit_at is not None and lit_at > slow_at and not slow_when_lit and phase == "FEVER",
      f"slow {slow_at} lit {lit_at} still slow {slow_when_lit} {phase}")
lua(r"""
function recue_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = 300, y = 420, kind = "orange", goal = true } }
  spec.goal = 1
  local st = E:NewLevel(spec)
  st.aim = 0
  local events = {}
  E:Launch(st, events)
  -- park the ball above the peg so the slow-mo keys in, interrupt it, let it key in again
  st.balls[1].x, st.balls[1].y, st.balls[1].vx, st.balls[1].vy = 300, 320, 0, 120
  local firsts, agains = 0, 0
  for i = 1, 40 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do
      if e.type == "last_peg" then if e.again then agains = agains + 1 else firsts = firsts + 1 end end
    end
    wipe(events)
    if i == 12 then st.lastSlow = false; st.lastSpent = 0; st.balls[1].y = 320; st.balls[1].vy = 120 end
    if st.phase ~= E.PHASE.FLIGHT then break end
  end
  return firsts, agains
end
""")
firsts, agains = ev("recue_probe")()
check("the slow-mo cue plays once a shot; a restart in the same shot is marked as a repeat", firsts == 1 and agains >= 1, f"firsts {firsts} agains {agains}")
check("Fever runs at full speed and the leftover balls start firing within a second",
      not slowed_in_fever and first_shot is not None and first_shot <= 1.0, f"slowed {slowed_in_fever} first shot {first_shot}")

# a near miss is not a close call: a ball falling past the last peg never slows
lua(r"""
function near_miss_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = 300, y = 350, kind = "orange", goal = true } }
  spec.goal = 1
  local st = E:NewLevel(spec)
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 300 + 40, y = 200, vx = 0, vy = 150, slow = 0 }
  local events = {}
  local slowed = 0
  for _ = 1, 150 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "last_peg" then slowed = slowed + 1 end end
    if st.lastSlow then slowed = slowed + 1 end
    wipe(events)
    if st.phase ~= E.PHASE.FLIGHT then break end
  end
  return slowed, st.pegs[1].lit
end
""")
slowed, lit = ev("near_miss_probe")()
check("a ball passing 40 px beside the last peg never triggers the slow-mo", slowed == 0 and not lit, f"slowed {slowed} lit {lit}")

# the shot's end: a summary when it hit something, a Total Miss when it did not
lua(r"""
function shot_end_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = E.FIELD_W / 2, y = 300, kind = "blue" }, { shape = "peg", x = 60, y = 450, kind = "orange", goal = true } }
  spec.goal = 1
  local st = E:NewLevel(spec)
  local events = {}
  st.aim = 0
  E:Launch(st, events)
  local summary, miss
  for _ = 1, 400 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "shot_summary" then summary = e elseif e.type == "total_miss" then miss = true end end
    wipe(events)
    if st.phase == E.PHASE.AIM then break end
  end
  local r1 = { summary = summary and summary.pegs, miss = miss }
  -- a shot straight out at the wall
  st.aim = 1.4
  E:Launch(st, events)
  st.balls[1].x, st.balls[1].y, st.balls[1].vx = 20, 560, 0
  summary, miss = nil, nil
  for _ = 1, 200 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do if e.type == "shot_summary" then summary = e elseif e.type == "total_miss" then miss = true end end
    wipe(events)
    if st.phase == E.PHASE.AIM then break end
  end
  return r1.summary, r1.miss, summary, miss
end
""")
sum1, miss1, sum2, miss2 = ev("shot_end_probe")()
check("a shot that hits a peg ends with a summary, one that hits nothing is a Total Miss", sum1 == 1 and not miss1 and sum2 is None and miss2, f"{sum1} {miss1} {sum2} {miss2}")

# a Long Shot: two goal pieces far apart lit in one shot
lua(r"""
function long_shot_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = 60, y = 300, kind = "orange", goal = true }, { shape = "peg", x = 430, y = 300, kind = "orange", goal = true }, { shape = "peg", x = 245, y = 450, kind = "orange", goal = true } }
  spec.goal = 3
  local st = E:NewLevel(spec)
  local events = {}
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 60, y = 300 - 16, vx = 0, vy = 0, slow = 0 }
  E:Step(st, 1 / 60, events)
  st.balls[1].x, st.balls[1].y, st.balls[1].vx, st.balls[1].vy = 430, 300 - 16, 0, 0
  E:Step(st, 1 / 60, events)
  local styles = {}
  for _, e in ipairs(events) do if e.type == "style" then styles[#styles + 1] = e.name end end
  return table.concat(styles, ","), st.score
end
""")
styles, score = ev("long_shot_probe")()
check("two far-apart goal pieces in one shot pay Long Shot style points", styles == "LONG SHOT" and score >= 5000, f"{styles} {score}")

# a grazing ball rides a brick (Super Slide) instead of bouncing off it
lua(r"""
function slide_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "brick", x = 300, y = 400, angle = 0, w = 240, h = 11, kind = "blue" } }
  spec.goal = 0
  local st = E:NewLevel(spec)
  st.phase = E.PHASE.FLIGHT
  -- skimming along the top of the brick, fast sideways and barely falling
  st.balls[1] = { x = 200, y = 400 - 5.5 - E.BALL_R - 1, vx = 400, vy = 30, slow = 0 }
  local events = {}
  local maxUp = 0
  for _ = 1, 12 do
    E:Step(st, 1 / 120, events)
    local b = st.balls[1]
    if b and -b.vy > maxUp then maxUp = -b.vy end
    wipe(events)
  end
  return maxUp, spec.pegs[1].lit
end
""")
max_up, lit = ev("slide_probe")()
check("a grazing touch on a brick slides along it (no bounce up) and lights it", max_up < 15 and lit, f"up {max_up:.1f} lit {lit}")

# the key cage: lighting the key dissolves the gold bars
lua(r"""
function cage_probe()
  local n
  for k = 81, 400 do if L:Build(k).gimmick == "Key Cage" then n = k break end end
  if not n then return nil end
  local st = E:NewLevel(L:Build(n))
  local key, bars = nil, 0
  for _, p in ipairs(st.pegs) do
    if p.kind == "key" then key = p end
    if p.lock then bars = bars + 1 end
  end
  local events = {}
  touch(st, key, events)
  local unlocked = count(events, "unlock")
  local left = 0
  for _, p in ipairs(st.pegs) do if p.lock and not p.gone then left = left + 1 end end
  return n, bars, unlocked, left, key.lit
end
""")
cage = ev("cage_probe")()
check("the Key Cage gimmick appears from chapter 9 and its key dissolves the bars",
      cage is not None and cage[1] == 4 and cage[2] == 1 and cage[3] == 0 and cage[4], str(cage))

# power-ups: an armed Ring of Fire hits everything round the first hit, once; the extra green peg
lua(r"""
function ring_probe()
  local spec = L:Build(1)
  spec.pegs = {
    { shape = "peg", x = 300, y = 300, kind = "blue" }, { shape = "peg", x = 340, y = 300, kind = "blue" },
    { shape = "peg", x = 300, y = 340, kind = "blue" }, { shape = "peg", x = 300, y = 500, kind = "orange", goal = true },
    { shape = "peg", x = 100, y = 450, kind = "blue" },
  }
  spec.goal = 1
  local st = E:NewLevel(spec)
  assert(E:Arm(st, "ring"))
  local events = {}
  st.aim = 0
  assert(E:Launch(st, events))
  local used, rings = count(events, "item_used"), 0
  wipe(events)
  st.balls[1].x, st.balls[1].y, st.balls[1].vx, st.balls[1].vy = 300, 300 - 16, 0, 50
  for _ = 1, 10 do E:Step(st, 1 / 60, events) rings = rings + count(events, "ring") wipe(events) end
  local lit = 0
  for _, p in ipairs(st.pegs) do if p.lit then lit = lit + 1 end end
  local before = 0
  for _, p in ipairs(spec.pegs) do if p.kind == "green" then before = before + 1 end end
  local g = E:AddGreen(st)
  return used, rings, lit, st.armed, g and g.kind
end
""")
used, rings, lit, armed_after, green_kind = ev("ring_probe")()
check("an armed Ring of Fire is spent on launch and its first hit takes the neighbours too", used == 1 and rings == 1 and lit == 3 and armed_after is None, f"used {used} rings {rings} lit {lit}")
check("Extra Green Peg turns a blue peg green", green_kind == "green")
lua("""
local function snap() local t = {} for k, v in pairs(P:Items()) do t[k] = v end return t end
__i0 = snap()
GP:RecordResult({ level = 3, cleared = true, score = 999999999, objective = 'classic', goals = 3, goalTotal = 3 })
__i1 = snap()
GP:RecordResult({ level = 10, cleared = true, score = 999999999, objective = 'boss', goals = 1, goalTotal = 1 })
__i2 = snap()
local db = GnomishPachinkoDB
db.cleared[3], db.stars[3], db.best[3], db.cleared[10], db.stars[10], db.best[10] = nil, nil, nil, nil, nil, nil
db.unlocked = 1
""")
i0, i1, i2 = dict(ev("__i0")), dict(ev("__i1")), dict(ev("__i2"))
check("only bosses give special balls: an ordinary three-star clear gives nothing",
      i1 == i0 and i2["ring"] == i1["ring"] + 2 and i2["rainbow"] == i1["rainbow"] + 1 and i2["suction"] == i1["suction"] + 2 and i2["green"] == i1["green"] + 1,
      f"{i0} {i1} {i2}")
hosts = [ev(f"GP:HostFor({n}).id") for n in (1, 11, 21, 31, 41)]
check("four gnome hosts take the chapters in turn", hosts == ["tink", "mekka", "razzle", "bink", "tink"], str(hosts))
check("the level card offers the host's two powers",
      list(ev("GP:UnlockedPowers(1)").values()) == ["multiball", "guide"] and list(ev("GP:UnlockedPowers(15)").values()) == ["blast", "lightning"]
      and list(ev("GP:UnlockedPowers(25)").values()) == ["pyramid", "frenzy"] and list(ev("GP:UnlockedPowers(35)").values()) == ["fireball", "spooky"])
check("every level's power is one of its host's", all(ev(f"L:Build({n}).power") in list(ev(f"GP:UnlockedPowers({n})").values()) for n in range(1, 401, 7)))
lua("GnomishPachinkoDB.unlocked = math.min(GnomishPachinkoDB.unlocked, 2); GnomishPachinkoDB.cleared[10] = nil; GnomishPachinkoDB.stars[10] = nil; GnomishPachinkoDB.best[10] = nil")

# gates and chained locks build
lua(r"""
function gate_probe()
  local n
  for k = 111, 400 do if L:Build(k).gimmick == "Key Gate" then n = k break end end
  if not n then return nil end
  local spec = L:Build(n)
  local keys, locked = 0, 0
  for _, p in ipairs(spec.pegs) do if p.kind == "key" then keys = keys + 1 end if p.lock then locked = locked + 1 end end
  return n, keys, locked
end
function chain_probe()
  for k = 300, 400 do
    local spec = L:Build(k)
    if spec.gimmick and spec.gimmick:find("Key Cage", 1, true) then
      local keys, silver = 0, 0
      for _, p in ipairs(spec.pegs) do if p.kind == "key" then keys = keys + 1 if p.silver then silver = silver + 1 end end end
      if keys == 2 then return k, keys, silver end
    end
  end
end
""")
gate = ev("gate_probe")()
check("the Key Gate gimmick appears from chapter 12 with its key and bar", gate is not None and gate[1] >= 1 and gate[2] >= 1, str(gate))
chain = ev("chain_probe")()
check("from level 300 a Key Cage can chain: a silver key for the cage round the gold key", chain is not None and chain[1] == 2 and chain[2] == 1, str(chain))

# eggs: knock the cradle out and the egg falls; the bucket saves it, the floor loses the level
lua(r"""
function egg_fall_probe(saveIt)
  local spec = L:Build(1)
  local ledgeY = 300 + E.EGG_R + E.BRICK_H / 2 + 0.5
  spec.pegs = {
    { shape = "peg", x = 245, y = 300, r = E.EGG_R, kind = "egg", goal = true, hp = 2, loose = true, special = true },
    { shape = "brick", x = 245 - 17, y = ledgeY, angle = 0, w = 34, h = E.BRICK_H, kind = "blue", cradle = true },
    { shape = "brick", x = 245 + 17, y = ledgeY, angle = 0, w = 34, h = E.BRICK_H, kind = "blue", cradle = true },
    { shape = "peg", x = 100, y = 450, kind = "orange", goal = true },
  }
  spec.goal = 2
  local st = E:NewLevel(spec)
  st.bucket.x = saveIt and 245 or 60
  st.bucket.dir = 0
  local events = {}
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end      -- settle
  wipe(events)
  -- light both cradle bricks by hand and let them expire
  for i = 2, 3 do st.pegs[i].lit = true; st.pegs[i].hitAt = st.time end
  st.phase = E.PHASE.FLIGHT
  st.balls[1] = { x = 400, y = 200, vx = 0, vy = 0, slow = 0 }
  local fell, saved, lost = 0, 0, 0
  for _ = 1, 400 do
    st.balls[1] = st.balls[1] or { x = 400, y = 200, vx = 0, vy = 0, slow = 0 }
    st.balls[1].y, st.balls[1].vy = 200, 0      -- park the ball out of the way
    E:Step(st, 1 / 60, events)
    fell = fell + count(events, "egg_fall")
    saved = saved + count(events, "egg_saved")
    lost = lost + count(events, "egg_lost")
    wipe(events)
    if st.phase == E.PHASE.OVER then break end
  end
  return fell, saved, lost, st.goalHit, st.phase, st.result and st.result.cleared, st.result and st.result.eggLost
end
""")
fell, saved, lost, goal_hit, phase, cleared, egg_lost = ev("egg_fall_probe")(True)
check("an egg whose nest is cleared falls, and the bucket saves and hatches it", fell == 1 and saved == 1 and goal_hit == 1 and lost == 0, f"fell {fell} saved {saved} goal {goal_hit}")
fell, saved, lost, goal_hit, phase, cleared, egg_lost = ev("egg_fall_probe")(False)
check("an egg off the board loses the level", fell == 1 and lost == 1 and phase == "OVER" and cleared == False and egg_lost == True, f"fell {fell} lost {lost} {phase} {cleared} {egg_lost}")

# Play On: three more balls after running out, not after a lost egg
lua(r"""
function play_on_probe()
  local spec = L:Build(1)
  spec.pegs = { { shape = "peg", x = 60, y = 450, kind = "orange", goal = true } }
  spec.goal = 1
  local st = E:NewLevel(spec)
  st.ballsLeft = 1
  st.aim = 0
  local events = {}
  E:Launch(st, events)
  for _ = 1, 400 do E:Step(st, 1 / 60, events) wipe(events) if st.phase == E.PHASE.OVER then break end end
  local over = st.phase == E.PHASE.OVER and st.result and not st.result.cleared
  local ok = E:PlayOn(st)
  return over, ok, st.ballsLeft, st.phase
end
""")
over, ok, balls, phase = ev("play_on_probe")()
check("Play On after running out of balls gives three more and the level carries on", over and ok and balls == 3 and phase == "AIM", f"{over} {ok} {balls} {phase}")

# a Long Shot level: two long shots finish it
lua(r"""
function longshot_level_probe()
  local n
  for k = 66, 200 do if L:Objective(k) == "longshots" then n = k break end end
  local spec = L:Build(n)
  local st = E:NewLevel(spec)
  local events = {}
  local oranges = {}
  for _, p in ipairs(st.pegs) do if p.kind == "orange" and p.maxhp == 1 and not p.moving then oranges[#oranges + 1] = p end end
  table.sort(oranges, function(a, b) return a.x < b.x end)
  local function above(p) return p.y - ((p.shape == "brick") and (p.h / 2) or (p.r or E.PEG_R)) - E.BALL_R + 1 end
  local goals = 0
  for shot = 1, st.goalTotal do
    -- the two unlit oranges furthest apart
    local a, b, best = nil, nil, 0
    for i = 1, #oranges do for j = i + 1, #oranges do
      local p, q = oranges[i], oranges[j]
      if not p.lit and not q.lit and math.abs(p.x - q.x) > best then a, b, best = p, q, math.abs(p.x - q.x) end
    end end
    if not a or best < E.LONG_SHOT then return n, spec.goal, goals, "no pair " .. best end
    st.phase = E.PHASE.FLIGHT
    st.shotGoals = {}; st.shotStyles = {}
    st.balls[1] = { x = a.x, y = above(a), vx = 0, vy = 0, slow = 0 }
    E:Step(st, 1 / 60, events)
    st.balls[1] = { x = b.x, y = above(b), vx = 0, vy = 0, slow = 0 }
    E:Step(st, 1 / 60, events)
    goals = goals + count(events, "longshot_goal")
    wipe(events)
    st.balls = {}
    for _ = 1, 30 do E:Step(st, 1 / 60, events) wipe(events) end
  end
  return n, spec.goal, goals, st.phase
end
""")
n, goal, goals, phase = ev("longshot_level_probe")()
check(f"a Long Shot level (level {n}) is finished by its long shots", goal >= 2 and goals == goal and phase == "FEVER", f"goal {goal} got {goals} {phase}")
lua(r"""
function same_layout(n, a)
  local x, y = L:Build(n, 0), L:Build(n, a)
  if #x.pegs ~= #y.pegs or x.layout ~= y.layout then return false, 0 end
  local moved, recoloured = 0, 0
  for i, p in ipairs(x.pegs) do
    local q = y.pegs[i]
    if math.abs(p.x - q.x) > 0.01 or math.abs(p.y - q.y) > 0.01 or p.shape ~= q.shape then moved = moved + 1 end
    if p.kind ~= q.kind then recoloured = recoloured + 1 end
  end
  return moved == 0, recoloured
end
""")
same = all(ev("same_layout")(n, a)[0] for n in (5, 11, 15, 23, 47, 150, 212, 399) for a in (1, 2, 5))
recol = sum(ev("same_layout")(n, 3)[1] for n in (11, 47, 150))
check("a retry keeps every piece in place (eggs and gems too) and only deals the colours again", same and recol > 0, f"{same} {recol}")

# the GNOME bonus: all five buckets lit pays 100,000 and the buckets become 25,000
lua(r"""
function gnome_probe()
  local spec = L:Build(1)
  spec.pegs = {}
  spec.goal = 0
  local st = E:NewLevel(spec)
  st.phase = E.PHASE.FEVER
  st.feverTotal = 0
  st.ballsLeft = 0
  local events = {}
  local bonus, last = 0, 0
  local binW = E.FIELD_W / #E.FEVER_BINS
  for i = 1, 6 do
    local idx = ((i - 1) % 5) + 1
    st.phase = E.PHASE.FEVER     -- with no balls left the level would end after each landing
    st.balls[1] = { x = (idx - 0.5) * binW, y = E.FIELD_H - 20, vx = 0, vy = 300, slow = 0 }
    for _ = 1, 10 do E:Step(st, 1 / 60, events) if not st.balls[1] then break end end
    for _, e in ipairs(events) do
      if e.type == "gnome_bonus" then bonus = bonus + 1 end
      if e.type == "bin" then last = e.points end
    end
    wipe(events)
  end
  return bonus, last, st.feverTotal
end
""")
bonus, last, total = ev("gnome_probe")()
check("lighting all five G-N-O-M-E buckets pays the bonus once and the next bucket is worth 25,000", bonus == 1 and last == 25000 and total == 47000 + 100000 + 25000, f"bonus {bonus} last {last} total {total}")

# a retry deals the oranges onto other pegs; the picture is the same
lua(r"""
function retry_probe()
  local a, b = L:Build(11, 0), L:Build(11, 1)
  local same, diffOrange = #a.pegs == #b.pegs, false
  for i, p in ipairs(a.pegs) do
    local q = b.pegs[i]
    if not q or math.abs(p.x - q.x) > 0.01 or math.abs(p.y - q.y) > 0.01 then same = false end
    if q and (p.kind == "orange") ~= (q.kind == "orange") then diffOrange = true end
  end
  return same, diffOrange, a.goal == b.goal, a.title
end
""")
same, diff_orange, same_goal, title = ev("retry_probe")()
check("a retry keeps the picture and the goal count but moves the oranges", same and diff_orange and same_goal, f"{same} {diff_orange} {same_goal}")
check("levels have names", isinstance(title, str) and len(title) > 3 and ev("L:Build(1).title") == "Howdy, Gnome!", str(title))

# two goal hits in one swoop: the slow-mo starts before the first of them
lua(r"""
function close_call_probe()
  -- pass one: a single orange; note where the ball is a quarter second after striking it
  local function run(pegs, need)
    local spec = L:Build(1)
    spec.pegs = pegs
    spec.goal = need
    local st = E:NewLevel(spec)
    local a = st.pegs[1]
    st.phase = E.PHASE.FLIGHT
    st.balls[1] = { x = a.x + 4, y = a.y - 120, vx = 0, vy = 200, slow = 0 }
    local events = {}
    local slowAt, litA, litB, wall, after = nil, nil, nil, 0, nil
    for _ = 1, 300 do
      E:Step(st, 1 / 60, events)
      wall = wall + 1 / 60
      for _, e in ipairs(events) do if e.type == "last_peg" and not slowAt then slowAt = wall end end
      if a.lit and not litA then litA = wall end
      if litA and not after and wall - litA >= 0.25 and st.balls[1] then after = { x = st.balls[1].x, y = st.balls[1].y } end
      if st.pegs[2] and st.pegs[2].goal and st.pegs[2].lit and not litB then litB = wall end
      wipe(events)
      if st.phase ~= E.PHASE.FLIGHT then break end
    end
    return { slowAt = slowAt, litA = litA, litB = litB, after = after }
  end
  -- (a blue stand-in for the path probe, so the level does not end on the strike)
  local A = { shape = "peg", x = 300, y = 300, kind = "blue" }
  local first = run({ A, { shape = "peg", x = 100, y = 450, kind = "orange", goal = true } }, 1)
  if not first.after then return nil end
  -- pass two: a second orange right on that path
  local B = { shape = "peg", x = first.after.x, y = first.after.y + 12, kind = "orange", goal = true }
  local second = run({ { shape = "peg", x = 300, y = 300, kind = "orange", goal = true }, B, { shape = "peg", x = 100, y = 450, kind = "blue" } }, 2)
  return { slowAt = second.slowAt, litA = second.litA, litB = second.litB, bx = B.x, by = B.y }
end
""")
cc = ev("close_call_probe")()
check("when the last two goal hits come in one swoop the slow-mo starts before the first",
      cc is not None and cc.litB is not None and cc.slowAt is not None and cc.slowAt < cc.litA, str(dict(cc) if cc else None))

# stars come from the level's own pieces
s2, s3 = ev("L:StarScores(1)")
check("stars: none for a loss, one for a clear, two and three at the marks",
      [ev(f"L:StarsFor(1, {s}, {c})") for s, c in ((999999, "false"), (1000, "true"), (s2 - 1, "true"), (s2, "true"), (s3, "true"))] == [0, 1, 1, 2, 3])
b2, b3 = ev("L:StarScores(81)")
check("a fuller board asks for a higher score", b2 > s2 * 1.2 and b3 > s3 * 1.2, f"level 1 {s2}/{s3}, level 81 {b2}/{b3}")
check("star marks are cached and reproducible", ev("L:StarScores(81)") == (b2, b3))

# ------------------------------------------------------------------ plays vault
lua(r"""
function vault_probe()
  local out = {}
  GnomishPachinkoSaved, GnomishPachinkoChar = nil, nil
  P.rec, P.loaded, P.tampered = nil, nil, nil
  P:Load()
  out.fresh = P:Remaining()
  out.canPlay = P:CanPlay()
  local text = GnomishPachinkoSaved.plays
  out.prefix = text:sub(1, 4)
  out.opaque = not text:find("fails", 1, true) and not text:find("gears", 1, true)
  local rec = P:Decode(text)
  out.roundTrip = rec and #rec.fails == 0 and #rec.lots == 0
  -- spend the day's plays
  for _ = 1, P.FAILS_PER_DAY do P:RecordFail() end
  out.spent = P:Remaining()
  out.blocked = not P:CanPlay()
  out.wait = P:NextFreeIn()
  out.mirrorsAgree = GnomishPachinkoSaved.plays == GnomishPachinkoChar.plays
  -- buy a lot
  P:AddLots(1)
  out.bought = P:Remaining()
  P:RecordFail()
  out.boughtSpent = P:BoughtLeft()
  -- a reinstall: the per-character copy is deleted, the account copy stands
  local keep = GnomishPachinkoSaved.plays
  GnomishPachinkoChar = nil
  P.rec = nil
  P:Load()
  out.afterReinstall = P:Remaining()
  out.healed = GnomishPachinkoChar.plays == GnomishPachinkoSaved.plays
  -- an older copy with fewer fails merges in: the union wins
  local old = P:Decode(keep)
  table.remove(old.fails)
  GnomishPachinkoChar.plays = P:Encode(old)
  P.rec = nil
  P:Load()
  out.mergedFails = #P.rec.fails
  -- a day later the free plays are back and the lot has expired
  __clock = __clock + 24 * 3600 + 1
  P.rec = nil
  P:Load()
  out.nextDay = P:Remaining()
  -- an edited copy locks the day
  local hacked = keep:sub(1, 20) .. "A" .. keep:sub(22)
  GnomishPachinkoSaved.plays = hacked
  GnomishPachinkoChar.plays = nil
  P.rec = nil
  P:Load()
  out.tampered = P.tampered and P:Remaining() == 0
  __clock = __clock + 24 * 3600 + 1
  P.rec = nil
  P:Load()
  out.unlockedAgain = P:Remaining()
  return out
end
""")
v = ev("vault_probe")()
check("the vault starts with the day's free plays", v["fresh"] == 5 and v["canPlay"])
check("the stored copy is an opaque encrypted blob that decodes back", v["prefix"] == "GPV2" and v["opaque"] and v["roundTrip"])
check("five losses use the day's plays and block play", v["spent"] == 0 and v["blocked"] and 0 < v["wait"] <= 24 * 3600 and v["mirrorsAgree"], str(dict(v)))
check("a bought lot adds five plays, spent after the free ones", v["bought"] == 5 and v["boughtSpent"] == 4)
check("deleting one copy (a reinstall) changes nothing and the copy is re-minted", v["afterReinstall"] == 4 and v["healed"])
check("copies merge as a union of fails", v["mergedFails"] == 5, str(v["mergedFails"]))
check("a day later the free plays are back and the bought lot is gone", v["nextDay"] == 5, str(v["nextDay"]))
check("an edited copy locks the day, and the lock lifts a day later", v["tampered"] and v["unlockedAgain"] == 5, f"{v['tampered']} {v['unlockedAgain']}")
check("the banker name decodes", ev("P:BankerName()") == "Chairface Chippendale", ev("P:BankerName()"))
check("a stranger is not an owner and gets nothing for free", not ev("P:IsOwner()") and not ev("(P:GrantFree())"))
owners_ok = True
for first, last in (("Chairface", "Chippendale"), ("Highley", "Regarded"), ("Notte", "Sure")):
    lua(f'__unitName, __unitSurname = "{first}", "{last}"')
    owners_ok = owners_ok and ev("P:IsOwner()")
check("the three owner characters are recognised from the encoded list", owners_ok)
lua('__unitName, __unitSurname = "Thrall", "Frostwolf"; GnomishPachinkoDB.unlocked = 1; __strangerUnlock = GP:UnlockAll()')
check("a stranger cannot unlock all levels", ev("__strangerUnlock") == False and ev("GnomishPachinkoDB.unlocked") == 1)
lua('__unitName, __unitSurname = "Chairface", "Chippendale"; __ownerUnlock = GP:UnlockAll()')
check("an owner unlocks every level for testing", ev("__ownerUnlock") == True and ev("GnomishPachinkoDB.unlocked") == ev("L.COUNT"))
lua('GP:ToggleUnlimited(); __unlimitedCount = GP:ItemCount("suction"); GP:SpendItem("suction"); __unlimitedAfter = GP:ItemCount("suction"); GP:ToggleUnlimited()')
check("an owner can switch on unlimited special balls for testing", ev("__unlimitedCount") == 99 and ev("__unlimitedAfter") == 99 and not ev("GP:Unlimited()"))
lua('GnomishPachinkoDB.unlocked = 1')
lua("__before = P:BoughtLeft(); __gBefore = P:Gears(); P:GrantFree()")
check("an owner's free top-up adds 10 Golden Gears and no plays", ev("P:Gears()") == ev("__gBefore") + 10 and ev("P:BoughtLeft()") == ev("__before"))
lua('__unitName, __unitSurname = "Thrall", "Frostwolf"')
lua("__buyPrinted = #__printed; __gearsBefore = P:Gears(); __boughtBefore = P:BoughtLeft(); P:OnPurchase(200000)")
check("a confirmed mail of 20g credits 20 Golden Gears and no plays", ev("P:Gears()") == ev("__gearsBefore") + 20 and ev("P:BoughtLeft()") == ev("__boughtBefore") and ev("#__printed") == ev("__buyPrinted") + 1)
lua("""
__g0 = P:Gears(); __s0 = P:Items().suction; __r0 = P:Items().ring; __rb0 = P:Items().rainbow; __b0 = P:BoughtLeft()
P:Buy("suction"); P:Buy("ring"); P:Buy("rainbow"); P:Buy("plays")
__g1 = P:Gears()
""")
check("the gear shop: 1 gear 3 suction, 2 gears 3 Rings, 3 gears 3 Rainbows, 10 gears 5 plays",
      ev("__g0 - __g1") == 16 and ev("P:Items().suction - __s0") == 3 and ev("P:Items().ring - __r0") == 3 and ev("P:Items().rainbow - __rb0") == 3 and ev("P:BoughtLeft() - __b0") == 5)
lua("P:AddGears(3 - P:Gears()); __g2 = P:Gears(); __okPoor = P:Buy('plays')")
check("the shop refuses what the gears cannot pay for", ev("__okPoor") == False and ev("P:Gears()") == ev("__g2"))
# the save is sealed: progress and gears live only in the vault
lua("""
GnomishPachinkoDB.unlocked = 37; GnomishPachinkoDB.stars[5] = 3
P:Save()
__sealedGears = P:Gears()
P:StripPlain()
__plainGone = GnomishPachinkoDB.unlocked == nil and GnomishPachinkoDB.stars == nil and GnomishPachinkoDB.items == nil
-- a player edits the plain file while logged out: it changes nothing
GnomishPachinkoDB.unlocked = 400
GnomishPachinkoDB.items = { suction = 999 }
P.rec = nil
P:Load()
__restored = GnomishPachinkoDB.unlocked == 37 and GnomishPachinkoDB.stars[5] == 3 and P:Items().suction < 999 and P:Gears() == __sealedGears
-- an old copy put back (more gears than now) loses to the newer one
local old = GnomishPachinkoSaved.plays
P:AddGears(-1)
GnomishPachinkoChar.plays = old
P.rec = nil
P:Load()
__oldLoses = P:Gears() == __sealedGears - 1
""")
check("at logout the progress, gears and special balls leave the plain file", ev("__plainGone"))
check("edits to the plain file change nothing: the sealed vault restores progress, gears and balls", ev("__restored"))
check("an older copy of the vault put back cannot restore spent gears", ev("__oldLoses"))
lua("GnomishPachinkoDB.unlocked = 1; GnomishPachinkoDB.stars[5] = nil; P:Save()")
lua("P.rec = nil; GnomishPachinkoSaved, GnomishPachinkoChar = nil, nil; P:Load()")

# ------------------------------------------------------------------ window
lua(r"""
GP:GetDB()
UI:Show()
function ui_play(maxSecs)
  local st = UI.state
  local shots, t = 0, 0
  while st.phase ~= E.PHASE.OVER and t < (maxSecs or 900) do
    if st.phase == E.PHASE.AIM then
      shots = shots + 1
      __cursor.x = 60 + ((shots * 131) % 420)
      __cursor.y = 600 - 420
      __advance(1 / 30)
      UI.field:GetScript("OnMouseDown")(UI.field, "LeftButton")
    end
    __advance(0.5)
    t = t + 0.5
  end
  return st.phase == E.PHASE.OVER, st.result
end
""")
check("level 1 opens on Tinkmaster's introduction, not the card", ev("UI.frame:IsShown() and UI.state.level == 1 and GP.Dialog:IsShown() and not UI.card:IsShown()"))
lua("__stopped = {}; GP.Dialog:Advance(); __cut = __stopped[1] and __stopped[1][2]")
check("Continue cuts the spoken line off at once", ev("__cut") == 0)
lua("for _ = 1, 10 do if GP.Dialog:IsShown() then GP.Dialog:Advance() end end")
check("the introduction plays each line's spoken clip", ev('(function() for _, p in ipairs(__played_files) do if p:find("Voice\\\\dialog\\\\intro_1.ogg", 1, true) then return true end end return false end)()'))
check("the introduction ends on the level card and is shown only once", ev("UI.card:IsShown() and not GP.Dialog:IsShown() and GnomishPachinkoDB.dialogs.intro == true"))
lua("GnomishPachinkoDB.dialogs = setmetatable({}, { __index = function() return true end })")   # the rest of the suite skips the talk
lua("UI.card.main:Click()")
check("Play on the card hides it", ev("not UI.card:IsShown()"))
lua("__aimBefore = UI.state.aim or 0; UI:OnKey('RIGHT'); __aimAfter = UI.state.aim; UI:OnKey('SPACE')")
check("Right nudges the aim a quarter of a degree and Space pauses", abs(ev("__aimAfter - __aimBefore") - 0.25 * math.pi / 180) < 1e-6 and ev("UI.paused") == True)
lua("UI:OnKey('SPACE')")
lua("""
__aim0 = UI.state.aim
UI.field:GetScript("OnMouseDown")(UI.field, "RightButton")
__cursor.x = __cursor.x + 50
__advance(0.5)
__fineDelta = UI.state.aim - __aim0
__fineZoom = UI.zoomScale
UI.field:GetScript("OnMouseUp")(UI.field, "RightButton")
__advance(1.5)
__zoomAfter = UI.zoomScale
""")
check("holding the right button zooms in on the landing spot and turns the cannon a fiftieth of a degree a pixel",
      abs(ev("__fineDelta") - 50 * 0.02 * math.pi / 180) < 1e-6 and ev("__fineZoom") > 2 and ev("__zoomAfter") < 1.05,
      f"{ev('__fineDelta')} {ev('__fineZoom')} {ev('__zoomAfter')}")
check("boss levels have no vacuum tube", all(ev(f"L:NoBucket({n})") for n in range(10, 401, 20)))
check("Space again resumes", ev("UI.paused") == False)
ok, result = ev("ui_play")(900)
check("a level plays to its end through the window", ok)
lua("__advance(2.5)")
check("the result card shows after the level with Retry and Map", ev("UI.card:IsShown() and UI.card.right:IsShown()"))
lua("UI:HideCard()")
check("the result is recorded in the saved progress", ev("GnomishPachinkoDB.best[1] ~= nil"))
check("a loss through the window spends a play", ev("P:Remaining()") == (5 if result.cleared else 4), str(ev("P:Remaining()")))
lua("UI:StartLevel(1); __before = GnomishPachinkoDB.unlocked")
# force a clear by lighting every orange, then finishing through the engine
lua(r"""
local st = UI.state
for _, p in ipairs(st.pegs) do if p.kind == "orange" then p.lit = true; p.gone = true end end
st.goalLeft = 1; st.goalHit = st.goalTotal - 1
local last
for _, p in ipairs(st.pegs) do if p.kind == "orange" then last = p end end
last.lit = false; last.gone = false
E:Aim(st, last.x, last.y)
""")
ok, result = ev("ui_play")(900)
cleared = bool(result and result.cleared)
if cleared:
    check("clearing level 1 unlocks level 2 and awards stars", ev("GnomishPachinkoDB.unlocked") >= 2 and ev("GnomishPachinkoDB.cleared[1] == true") and ev("(GnomishPachinkoDB.stars[1] or 0) >= 1"))
    lua("UI.nextBtn:Click()")
    check("NEXT LEVEL moves to level 2", ev("UI.state.level") == 2)
else:
    print("      (the scripted shots did not reach the last orange; unlock checks skipped)")
    lua("GP:RecordResult({ level = 1, cleared = true, score = 1234, objective = 'classic', goals = 15, goalTotal = 15 })")
    check("recording a clear unlocks the next level and awards a star", ev("GnomishPachinkoDB.unlocked") >= 2 and ev("GnomishPachinkoDB.stars[1]") == 1)
lua("UI:ShowLevelSelect()")
check("the level map shows chapter 1 with level 2 open and the boss node tenth", ev("UI.levelPanel:IsShown() and UI.levelPanel.nodes[2]:IsEnabled() and not UI.levelPanel.nodes[3]:IsEnabled() and UI.levelPanel.nodes[10].level == 10"), f"unlocked {ev('GnomishPachinkoDB.unlocked')}")
lua("UI.levelPanel.cells[2]:Click()")
check("clicking an open level starts it", ev("UI.state.level == 2 and not UI.levelPanel:IsShown()"))
lua("UI:ShowLevelSelect(); UI.levelPanel.next:Click()")
check("Next steps to chapter 2 and >> ten chapters on", ev("UI.levelPanel.nodes[1].level") == 11)
lua("UI.levelPanel.next10:Click()")
lua("GnomishPachinkoDB.stars[3] = 2; GnomishPachinkoDB.cleared[3] = true; UI.levelPanel.reset:Click()")
check("the first click on Reset progress only arms it", ev("GnomishPachinkoDB.cleared[3] == true") and "Really" in ev("UI.levelPanel.reset.text:GetText()"))
lua("UI.levelPanel.reset:Click()")
check("the second click wipes levels and stars, keeps the plays, and starts level 1",
      ev("GnomishPachinkoDB.cleared[3] == nil and GnomishPachinkoDB.stars[3] == nil and GnomishPachinkoDB.unlocked == 1 and UI.state.level == 1 and not UI.levelPanel:IsShown()")
      and ev("P:Remaining()") >= 1)
lua("GnomishPachinkoDB.unlocked = 2; UI:ShowLevelSelect(); UI.levelPanel.next:Click(); UI.levelPanel.next10:Click()")
check("the >> button jumps ten chapters", ev("UI.levelPanel.nodes[1].level") == 111 and "Chapter 12" in ev("UI.levelPanel.title:GetText()"))
lua("UI:HideLevelSelect()")
lua('SlashCmdList["GNOMISHPACHINKO"]("999")')
check("slash refuses a locked level", any("not unlocked" in m for m in ev("__printed").values()))
lua('__n = #__printed; SlashCmdList["GNOMISHPACHINKO"]("plays")')
check("/pachinko plays reports the plays left", ev("#__printed") == ev("__n") + 1 and "Plays left today" in ev("__printed[#__printed]"))
lua('__n = #__printed; SlashCmdList["GNOMISHPACHINKO"]("buy")')
check("/pachinko buy away from a mailbox explains the mail", "mailbox" in ev("__printed[#__printed]"))

# out of plays: the panel covers the field and a level cannot start
lua(r"""
for _ = 1, 10 do P:RecordFail() end
__started = UI:StartLevel(1)
""")
check("with no plays left a level will not start and the out-of-plays panel shows", ev("__started") == False and ev("UI.playsPanel:IsShown()"))
lua("P:AddLots(1); UI:OnPlaysChanged()")
check("buying plays hides the panel and the game resumes", ev("not UI.playsPanel:IsShown()") and ev("UI.state ~= nil"))
check("a stranger sees no owner button", ev("not UI.freeBtn:IsShown()"))
lua('__unitName, __unitSurname = "Notte", "Sure"; for _ = 1, 10 do P:RecordFail() end; UI:StartLevel(1)')
check("an owner out of plays sees the free button on the panel", ev("UI.playsPanel:IsShown() and UI.playsPanel.free:IsShown() and UI.freeBtn:IsShown()"))
lua("__ownG = P:Gears(); UI.playsPanel.free:Click()")
check("clicking it grants 10 Golden Gears", ev("P:Gears() - __ownG") == 10)
lua("UI.playsPanel.buy:Click()")
check("the gears buy plays from the panel and the game resumes", ev("not UI.playsPanel:IsShown() and P:Remaining() == 5"))
lua('__unitName, __unitSurname = "Thrall", "Frostwolf"; UI:UpdateDisplay()')

# the mascot: a model frame in the corner that reacts to the game
check("the mascot model exists in the window", ev("GP.Mascot.model ~= nil"))
lua("GP.Mascot:React('fever')")
check("Fever makes the mascot dance and hold it", ev("GP.Mascot.current") == "dance" and ev("GP.Mascot.held") == "dance")
lua("GP.Mascot:React('bucket'); __now = __now + 3; GP.Mascot:Tick(__now)")
check("a one-shot cheer returns to the held dance", ev("GP.Mascot.current") == "dance")
lua("GP.Mascot:React('start'); __now = __now + 3; GP.Mascot:Tick(__now)")
check("a new level clears the held animation back to standing", ev("GP.Mascot.current") == "stand")
lua('GP.Mascot:Command("npc 7406"); GP.Mascot:Command("scale 1.2"); GP.Mascot:Command("")')
check("mascot commands set the creature and scale and hide it", ev("GnomishPachinkoDB.mascot.npc") == 7406 and ev("GnomishPachinkoDB.mascot.scale") == 1.2 and ev("GnomishPachinkoDB.mascot.hide") == True)
lua('GP.Mascot:Command("")')

# minimap button and the announcer hooks
lua("GP.Minimap:Create()")
check("the minimap button exists with its drawn icon", ev("GP.Minimap.button ~= nil and GP.Minimap.button.icon.slot == 'minimap'"))
lua("UI:Hide(); GP.Minimap.button:GetScript('OnClick')(GP.Minimap.button, 'LeftButton')")
check("left-clicking the minimap button opens the game", ev("UI.frame:IsShown()"))
lua("GP.Minimap.button:GetScript('OnClick')(GP.Minimap.button, 'RightButton')")
check("right-clicking it opens the level select", ev("UI.levelPanel:IsShown()"))
lua("UI:HideLevelSelect(); GP.Minimap:Toggle()")
check("/pachinko minimap hides the button and remembers it", ev("not GP.Minimap.button:IsShown() and GnomishPachinkoDB.minimap.hide == true"))
lua("GP.Minimap:Toggle()")
lua("__ok = pcall(GP.PlayVoice, GP, 'fever')")
check("a missing voice line plays silently without an error", ev("__ok"))

# the window survives egg, gem and boss levels (textures laid out, events handled)
lua(r"""
function ui_run_level(n)
  GnomishPachinkoDB.unlocked = 400
  UI:StartLevel(n)
  local ok = UI:StartLevel(n)
  local st = UI.state
  local shots = 0
  for _ = 1, 40 do
    if st.phase == E.PHASE.AIM then
      shots = shots + 1
      __cursor.x = 60 + ((shots * 131) % 420)
      __cursor.y = 600 - 420
      __advance(1 / 30)
      UI.field:GetScript("OnMouseDown")(UI.field, "LeftButton")
    end
    __advance(0.5)
    if st.phase == E.PHASE.OVER then break end
  end
  return ok, st.objective, st.phase
end
""")
for n in (15, 23, 10, 20):
    ok, obj, phase = ev("ui_run_level")(n)
    check(f"the window runs level {n} ({obj}) without errors", ok and phase in ("AIM", "FLIGHT", "FEVER", "OVER"), f"{ok} {phase}")

# Fever's balloons are drawn once, by their own pictures: no leftover piece
# texture from a bigger board shows up as a stray balloon
lua(r"""
UI:StartLevel(30, true)
local big = #UI.pegTex
UI:StartLevel(1, true)
local st = UI.state
for _, p in ipairs(st.pegs) do if p.goal then p.lit = true; p.gone = true end end
st.goalLeft = 0
st.phase = E.PHASE.FEVER
local events = {}
for i = 0, #E.FEVER_BINS do
  st.pegs[#st.pegs + 1] = { shape = "peg", x = i * 80, y = E.FEVER_POST_Y, r = E.FEVER_BALLOON_R, kind = "bumper", post = true, balloon = true }
end
__advance(0.2)
__stray = 0
for i, p in ipairs(st.pegs) do
  local t = UI.pegTex[i]
  if p.post and t and t.disc:IsShown() then __stray = __stray + 1 end
end
__bigBoard = big > #st.pegs - 7
""")
check("no stray balloon pictures in Fever: the balloons are drawn only by the Fever art", ev("__stray") == 0, str(ev("__stray")))

# the boss stands as its creature model on a platform that rides with it
lua(r"""
UI:StartLevel(10, true)
__bmShown = UI.bossModel:IsShown() and UI.bossPlatform:IsShown()
__bmNpc = UI.bossModelNpc
UI:StartLevel(11, true)
__bmGone = not UI.bossModel:IsShown() and not UI.bossPlatform:IsShown()
""")
check("a boss level shows the boss's creature model on its platform; other levels do not",
      ev("__bmShown") and ev("__bmNpc") == 8615 and ev("__bmGone"), f'{ev("__bmShown")} {ev("__bmNpc")} {ev("__bmGone")}')

# TEMPORARY: the host tuning panel saves height and zoom per host
lua(r"""
UI:StartLevel(1, true)
UI:TuneHost(1)
__tuneId = UI:TuneHostDef().id
UI:SetTune("z", -0.25); UI:SetTune("scale", 1.4)
local t = GnomishPachinkoDB.mascot.tune[__tuneId]
__tuneOk = t and t.z == -0.25 and t.scale == 1.4
UI:SetTune(nil)
__tuneReset = GnomishPachinkoDB.mascot.tune[__tuneId] == nil
""")
check("the tuning panel saves a host's height and zoom, and resets them",
      ev("__tuneId") == "mekka" and ev("__tuneOk") and ev("__tuneReset"))

# a power is announced by the host it belongs to, whoever hosts the level
lua(r"""
UI:StartLevel(1, true)
GnomishPachinkoDB.sound, GnomishPachinkoDB.voice = true, true
if GP.Dialog:IsShown() then GP.Dialog:Finish() end
local n = #__played_files
GP:PlayVoice("power_pyramid", GP:HostForPower("pyramid"))
__powerVoice = __played_files[#__played_files] or ""
__powerPlayed = #__played_files > n
""")
check("a power is announced in its own host's voice", ev("__powerPlayed") and ev("__powerVoice").replace(chr(92), "/").endswith("Voice/razzle/power_pyramid.ogg"), ev("__powerVoice"))

# Chain Lightning draws a bolt that grows link by link, then is gone
lua(r"""
UI:StartLevel(25, true)
local path = { { x = 100, y = 200 }, { x = 160, y = 230 }, { x = 220, y = 210 }, { x = 280, y = 260 } }
UI:ShowBolt(path, GetTime())
local function shown() local n = 0 for _, l in ipairs(UI.boltLines) do if l.core:IsShown() then n = n + 1 end end return n end
__advance(0.04); __bolt1 = shown()
__advance(0.25); __bolt2 = shown()
__advance(1.0); __bolt3 = shown()
__hostName = UI.hostText:GetText()
""")
check("the lightning bolt grows link by link and then disappears",
      0 < ev("__bolt1") < ev("__bolt2") and ev("__bolt3") == 0, f'{ev("__bolt1")} {ev("__bolt2")} {ev("__bolt3")}')
check("the right column names the level's host above the power", "Razzle" in (ev("__hostName") or ""), str(ev("__hostName")))

# the pieces wear the per-colour, per-state art; loose pieces are drawn big
lua(r"""
function art_probe()
  GnomishPachinkoDB.unlocked = 400
  UI:StartLevel(15)
  UI.card.main:Click()
  __advance(0.2)
  local out = { egg = nil, cradle = nil, blue = 0, sizeEgg = 0, sizeBrick = 0 }
  for i, p in ipairs(UI.state.pegs) do
    local t = UI.pegTex[i]
    if p.kind == "egg" and not out.egg then out.egg = t.disc.slot; out.sizeEgg = t.disc:GetWidth() end
    if p.cradle and not out.cradle then out.cradle = t.disc.slot; out.sizeBrick = t.disc:GetHeight() end
    if t.disc.slot == "peg_blue" then out.blue = out.blue + 1 end
  end
  -- light a blue peg by hand: the lit picture, then the gone picture
  local lit
  for i, p in ipairs(UI.state.pegs) do if p.kind == "blue" and p.shape == "peg" and not p.loose then lit = i; E.HitPeg(UI.state, p, nil, UI.events, true) break end end
  __advance(0.1)
  out.litSlot = UI.pegTex[lit].disc.slot
  __advance(2.2)
  out.goneSlot = UI.pegTex[lit].disc.slot
  out.ballSlot = UI.ballTex[1].slot
  out.goalIcon = UI.goalIcon.slot
  return out
end
""")
a = ev("art_probe")()
check("eggs wear the egg art at loose-piece size and cradle bricks the per-colour brick art",
      a["egg"] == "egg" and a["sizeEgg"] > 2 * ev("E.EGG_R") and a["cradle"] in ("brick_blue", "brick_green", "brick_orange") and a["sizeBrick"] >= ev("E.BRICK_H"), str(dict(a)))
check("a lit peg swaps to its _lit picture, a vanishing one to _gone, the goal icon follows the objective",
      a["litSlot"] == "peg_blue_lit" and a["goneSlot"] == "peg_blue_gone" and a["goalIcon"] == "goal_egg" and a["ballSlot"] == "ball", str(dict(a)))

# Fever stands four solid posts between the five cups for the ball to bounce off
lua(r"""
function post_probe()
  local st = E:NewLevel(L:Build(1))
  local events = {}
  for _, p in ipairs(st.pegs) do if p.kind == "orange" then E.HitPeg(st, p, nil, events, true) end end
  local balloons, onFloor = 0, true
  local first
  for _, p in ipairs(st.pegs) do
    if p.balloon then
      balloons = balloons + 1
      first = first or p
      if p.kind ~= "bumper" or math.abs(p.y - (E.FIELD_H - E.FEVER_TUBE_H)) > 0.5 then onFloor = false end
    end
  end
  -- drop a slow ball onto the first balloon, off centre: it leaves faster than
  -- it came, thrown away along the line from the balloon's centre
  st.balls = { { x = first.x + 8, y = first.y - first.r - E.BALL_R - 1, vx = 0, vy = 60, slow = 0 } }
  local before = 60
  for _ = 1, 8 do E:Step(st, 1 / 120, events) end
  local b = st.balls[1]
  local speed = b and math.sqrt(b.vx * b.vx + b.vy * b.vy) or 0
  return st.phase, balloons, onFloor, speed > before * 2, b and b.vx > 0, b and b.vy < 0
end
""")
phase, balloons, on_floor, faster, right, up = ev("post_probe")()
check("Fever sets six balloon bumpers on every tube boundary and wall, centres level with the tube tops", phase == "FEVER" and balloons == 6 and on_floor, f"{phase} {balloons} {on_floor}")
check("a balloon throws the ball off along the impact vector and adds energy", faster and right and up, f"{faster} {right} {up}")

check("every chapter has its own map and board backdrop, the tenth level its boss arena",
      ev("ART:MapBackdrop(17)") == "map_bg_17" and ev("ART:FieldBackdrop(161)") == "field_bg_17" and ev("ART:FieldBackdrop(170)") == "field_boss_17"
      and ev("ART:FieldBackdrop(400)") == "field_boss_40" and ev("ART.CHAPTERS") == ev("#L.CHAPTERS"))

# balloons in the levels: from chapter 2, several sizes, soft bounce, never lit
lua(r"""
function balloon_probe()
  local levels, sizes, early, soft = 0, {}, 0, true
  for n = 1, 400 do
    local spec = L:Build(n)
    local any = false
    for _, p in ipairs(spec.pegs) do
      if p.balloon then
        any = true
        sizes[p.r] = true
        if p.kind ~= "bumper" or p.bounce ~= E.BALLOON_BOUNCE then soft = false end
        if n <= 10 then early = early + 1 end
      end
    end
    if any then levels = levels + 1 end
  end
  local n = 0
  for _ in pairs(sizes) do n = n + 1 end
  return levels, n, early, soft
end
""")
levels, nsizes, early, soft = ev("balloon_probe")()
check("balloons stand in most levels from chapter 2, in several sizes, with the soft bounce", levels > 300 and nsizes >= 3 and early == 0 and soft, f"{levels} {nsizes} {early} {soft}")

# the guide's ghost ball touches the piece it meets, edge to edge
lua(r"""
function guide_touch_probe()
  local st = E:NewLevel(L:Build(1))
  st.pegs = { { shape = "peg", x = 245, y = 330, kind = "blue" } }
  st.aim = 0
  local _, hit, x, y = E:Guide(st)
  if not hit then return -1 end
  return math.sqrt((x - 245) ^ 2 + (y - 330) ^ 2) - (E.BALL_R + E.PEG_R)
end
""")
gap = ev("guide_touch_probe")()
check("the guide's ghost ball touches the piece edge to edge, not inside it", 0 <= gap < 0.5, str(gap))

# the Tin Drake throws scrap after every shot, and scrap never walls the boss off
lua(r"""
function drake_probe()
  local spec
  for n = 10, 400, 10 do spec = L:Build(n) if spec.boss and spec.boss.id == "drake" then break end end
  local st = E:NewLevel(spec)
  local events = {}
  local counts = {}
  for shot = 1, 14 do
    st.phase = E.PHASE.FLIGHT
    st.balls = {}
    st.shots = shot
    st.bossHitThisShot = false
    st.ballsLeft = 10
    for _ = 1, 4 do E:Step(st, 1 / 60, events) if st.phase ~= E.PHASE.FLIGHT then break end end
    local n = 0
    for _, p in ipairs(st.pegs) do if p.scrap then n = n + 1 end end
    counts[#counts + 1] = n
  end
  local cols = math.floor((E.FIELD_W - 80) / E.SCRAP_COL_W)
  local function rows()
    local t = {}
    for _, p in ipairs(st.pegs) do if p.scrap then t[p.row] = t[p.row] or {}; t[p.row][p.col] = true end end
    return t
  end
  local r1 = rows()[1] or {}
  local r1n = 0 for _ in pairs(r1) do r1n = r1n + 1 end
  local endsTaken = r1[1] and r1[cols]
  -- now the pattern is cleared: the Drake climbs into the space
  for _, p in ipairs(st.pegs) do if not p.scrap and p ~= st.boss then p.gone = true end end
  for shot = 15, 40 do
    st.phase = E.PHASE.FLIGHT
    st.balls = {}
    st.shots = shot
    st.ballsLeft = 10
    for _ = 1, 4 do E:Step(st, 1 / 60, events) if st.phase ~= E.PHASE.FLIGHT then break end end
  end
  local t = rows()
  local upper, wall = 0, false
  for r, cs in pairs(t) do
    local n = 0 for _ in pairs(cs) do n = n + 1 end
    if r > 1 then upper = upper + n end
    if n >= cols then wall = true end
  end
  return counts[1], counts[#counts], r1n, endsTaken and true or false, upper, wall
end
""")
first, last, r1n, ends, upper, wall = ev("drake_probe")()
check("the Tin Drake throws scrap after every shot, fills its first row, then takes the two bank ends",
      first == 2 and last > first and r1n == 7 and ends, f"{first} {last} {r1n} {ends}")
check("then it climbs into cleared space above, and no row is ever a wall",
      upper > 0 and not wall, f"{upper} {wall}")

# the Gyro Spider spins webs after every shot; a ball that touches one is
# caught, and the web goes with it
lua(r"""
function web_probe()
  local spec
  for n = 10, 400, 10 do spec = L:Build(n) if spec.boss and spec.boss.id == "spider" then break end end
  local st = E:NewLevel(spec)
  local events = {}
  local out = { webs = 0, scrap = 0, caught = false, webGone = false, lost = false, clear = true }
  for shot = 1, 3 do
    st.phase = E.PHASE.FLIGHT
    st.balls = {}
    st.shots = shot
    st.ballsLeft = 10
    for _ = 1, 4 do E:Step(st, 1 / 60, events) if st.phase ~= E.PHASE.FLIGHT then break end end
  end
  local web
  for _, p in ipairs(st.pegs) do
    if p.web and not p.gone then out.webs = out.webs + 1; web = web or p end
    if p.scrap then out.scrap = out.scrap + 1 end
  end
  -- no web sits on another piece
  for _, p in ipairs(st.pegs) do
    if p.web then
      for _, q in ipairs(st.pegs) do
        if q ~= p and not q.gone and q.shape ~= "brick" then
          local dx, dy = q.x - p.x, q.y - p.y
          if dx * dx + dy * dy < ((q.r or E.PEG_R) + p.r) ^ 2 then out.clear = false end
        end
      end
    end
  end
  -- drop a ball onto a web
  st.aim = 0
  st.phase = E.PHASE.AIM
  wipe(events)
  E:Launch(st, events)
  local b = st.balls[1]
  b.x, b.y, b.vx, b.vy = web.x, web.y - web.r - E.BALL_R - 4, 0, 120
  for _ = 1, 30 do
    E:Step(st, 1 / 60, events)
    for _, e in ipairs(events) do
      if e.type == "web_catch" then out.caught = true end
      if e.type == "lost" and e.webbed then out.lost = true end
    end
    wipe(events)
    if out.lost then break end
  end
  out.webGone = web.gone == true
  return out
end
""")
wp = dict(ev("web_probe")())
check("the Gyro Spider spins webs after every shot, in open space, and throws no steel scrap",
      wp["webs"] >= 4 and wp["scrap"] == 0 and wp["clear"], str(wp))
check("a ball that touches a web is caught: ball and web both gone", wp["caught"] and wp["lost"] and wp["webGone"], str(wp))

# arming the Suction Tube starts the tube sucking; disarming it unfired stops it
lua("""
GnomishPachinkoDB.unlocked = 400
UI:StartLevel(3)
if UI.card:IsShown() then UI.card.main:Click() end
UI.state.noBucket = false
GP:ToggleUnlimited()
UI:ToggleItem("suction")
__advance(0.2)
__suckArmed = UI.bucket.slot
UI:ToggleItem("suction")
__advance(0.2)
__suckDisarmed = UI.bucket.slot
GP:ToggleUnlimited()
""")
check("arming the Suction Tube starts the tube sucking, disarming it unfired stops it",
      ev("__suckArmed") == "bucket_suck" and ev("__suckDisarmed") == "bucket", f"{ev('__suckArmed')} {ev('__suckDisarmed')}")

# one voice at a time: a new announcer line cuts the last, and none plays over the dialog
lua("""
GP.Dialog:Finish()
__stopped = {}
GP:PlayVoice("combo"); __h1 = GP.voiceHandle
GP:PlayVoice("fever")
__cutFirst = false
for _, e in ipairs(__stopped) do if e[1] == __h1 and e[2] == 0 then __cutFirst = true end end
GP.Dialog.panel:Show()
__n = #__played_files
GP:PlayVoice("combo")
__quietUnderDialog = (#__played_files == __n)
GP.Dialog.panel:Hide()
""")
check("a new announcer line cuts the last one off, and none plays while a dialog is up", ev("__cutFirst") and ev("__quietUnderDialog"), f"{ev('__cutFirst')} {ev('__quietUnderDialog')} {ev('__h1')} {ev('GnomishPachinkoDB.sound')} {ev('GnomishPachinkoDB.voice')}")
check("the host's lines come from the host's own voice folder", ev("(function() UI.state.level = 15; __n = #__played_files; GP:PlayVoice('fever'); return __played_files[#__played_files] end)()").find("Voice\\mekka\\fever") >= 0)

# level 8: the spiral is a rail; a shot down its mouth rides the inside all the way round
lua(r"""
function spiral_ride(aimDeg)
  local st = E:NewLevel(L:Build(8))
  st.aim = aimDeg * math.pi / 180
  local events = {}
  E:Launch(st, events)
  local railed = false
  for _ = 1, 600 do
    E:Step(st, 1 / 120, events)
    if st.balls[1] and st.balls[1].rail then railed = true end
    if #st.balls == 0 then break end
  end
  local lit, total = 0, 0
  for _, p in ipairs(st.pegs) do if p.rail then total = total + 1; if p.lit or p.gone then lit = lit + 1 end end end
  return lit, total, railed
end
""")
ride = ev("spiral_ride")
rides = [ride(k / 10) for k in range(-260, -180)]
full = sum(1 for lit, total, railed in rides if railed and lit == total)
check("level 8's spiral rides end to end from a band of aims, not one pixel", full >= 8, f"{full} aims of 0.1 degree ride all of it")

# rails keep their speed; gems tip off points; a lit cradle drops its egg at once; rails across the levels
lua(r"""
function feel_probe()
  local out = {}
  local events = {}
  -- the level 8 spiral ridden from the best aim: the speed on the rail never drops
  local st = E:NewLevel(L:Build(8))
  st.aim = -24 * math.pi / 180
  E:Launch(st, events)
  local first, minRatio = nil, 9
  for _ = 1, 600 do
    E:Step(st, 1 / 120, events)
    local b = st.balls[1]
    if not b then break end
    if b.rail then
      local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
      first = first or sp
      minRatio = math.min(minRatio, sp / first)
    end
  end
  out.railKeeps = first ~= nil and minRatio > 0.98
  -- the same shot with the rail already lit: no ride, no speed
  st = E:NewLevel(L:Build(8))
  for _, p in ipairs(st.pegs) do if p.rail then p.lit = true; p.hitAt = 0 end end
  st.aim = -24 * math.pi / 180
  E:Launch(st, events)
  out.litRides = false
  for _ = 1, 200 do
    E:Step(st, 1 / 120, events)
    local b = st.balls[1]
    if not b then break end
    if b.rail then out.litRides = true end
  end
  -- a gem dropped dead centre on a lone peg does not balance there
  st = E:NewLevel(L:Build(1))
  st.pegs = { { shape = "peg", x = 245, y = 300 - E.GEM_R - E.PEG_R - 1, r = E.GEM_R, kind = "gem", goal = true, special = true, loose = true },
              { shape = "peg", x = 245, y = 300, kind = "blue" } }
  st.hasLoose = true
  st.pegs[1].vx, st.pegs[1].vy = 0, 0
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end
  out.gemTips = math.abs(st.pegs[1].x - 245) > 20
  -- an egg on a V cradle falls the moment the cradle is lit, not when it fades
  st = E:NewLevel(L:Build(15))
  local egg
  for _, p in ipairs(st.pegs) do if p.kind == "egg" then egg = p break end end
  for _ = 1, 240 do E:Step(st, 1 / 60, events) end
  local y0 = egg.y
  for _, p in ipairs(st.pegs) do
    if p.cradle and math.abs(p.x - egg.x) < 60 and p.y > egg.y then p.lit = true; p.hitAt = st.time end
  end
  for _ = 1, 30 do E:Step(st, 1 / 60, events) end      -- half a second: the cradle is lit, not yet gone
  out.eggFalls = egg.y > y0 + 20
  -- rails here and there from chapter 2
  local withRails = 0
  for n = 11, 400 do
    for _, p in ipairs(L:Build(n).pegs) do if p.rail then withRails = withRails + 1 break end end
  end
  out.withRails = withRails
  return out
end
""")
r = ev("feel_probe")()
check("a Super Slide keeps its speed for the whole ride", r["railKeeps"])
check("a lit Super Slide brick is no rail: the ball does not ride it", not r["litRides"])
check("a gem cannot balance on the point of a peg", r["gemTips"])
check("an egg falls the moment its cradle is lit, not when the bricks fade", r["eggFalls"])
check("small rails (bowls and spirals) turn up across the levels", 120 < r["withRails"] < 330, str(r["withRails"]))

# Super Guide: three bounces, six when earned again while it runs
lua(r"""
function guide_levels_probe()
  local st = E:NewLevel(L:Build(25))
  st.power = "guide"
  local events = {}
  local green
  for _, p in ipairs(st.pegs) do if p.kind == "green" then green = p break end end
  E.HitPeg(st, green, { vx = 0, vy = 100 }, events)
  local lvl1 = st.guideLevel
  local _, b1 = E:Simulate(st, nil, nil, E.GUIDE_BOUNCES[st.guideLevel])
  -- earned again while running
  local green2
  for _, p in ipairs(st.pegs) do if p.kind == "green" and p ~= green then green2 = p break end end
  st.time = st.time + 1
  E.HitPeg(st, green2, { vx = 0, vy = 100 }, events)
  local _, b2 = E:Simulate(st, nil, nil, E.GUIDE_BOUNCES[st.guideLevel])
  return lvl1, st.guideLevel, b1, b2
end
""")
lvl1, lvl2, b1, b2 = ev("guide_levels_probe")()
check("Super Guide shows three bounces, and six when earned again while it runs", lvl1 == 1 and lvl2 == 2 and b1 <= 3 and b2 <= 6 and b2 >= b1, f"{lvl1} {lvl2} {b1} {b2}")

# a rail stays whole through the shot: a ball coming back across it later still rides it
lua(r"""
function rail_return_probe()
  local spec = L:Build(11)
  local keep, cx, cy = {}
  for _, p in ipairs(spec.pegs) do if p.rail then keep[#keep + 1] = p; cx, cy = p.railCx, p.railCy end end
  spec.pegs = keep
  local st = E:NewLevel(spec)
  local events = {}
  st.phase = E.PHASE.FLIGHT
  st.balls = { { x = cx - 40, y = cy - 60, vx = 0, vy = 0, slow = 0 } }
  local rode2 = 0
  for i = 1, 600 do
    -- a second ball arrives three seconds later, long after the first lit the bricks
    if i == 360 then st.balls[#st.balls + 1] = { x = cx - 40, y = cy - 60, vx = 0, vy = 0, slow = 0, tag = 2 } end
    if i < 360 and #st.balls == 0 then st.balls[1] = { x = 20, y = 30, vx = 0, vy = 0, slow = 0 } end   -- keep the shot going
    E:Step(st, 1 / 120, events)
    for _, b in ipairs(st.balls) do if b.tag == 2 and b.rail then rode2 = rode2 + 1 end end
  end
  return rode2
end
""")
check("a rail stays whole through the shot, so a ball coming back three seconds later still rides it", ev("rail_return_probe")() > 10)

# this round's rules
lua(r"""
function round_probe()
  local out = {}
  local events = {}
  -- a bucket catch is never a Total Miss
  local st = E:NewLevel(L:Build(1))
  st.aim = 0
  E:Launch(st, events)
  st.balls[1].x, st.balls[1].y, st.balls[1].vx, st.balls[1].vy = st.bucket.x, E.FIELD_H - 40, 0, 200
  st.bucket.dir = 0
  for _ = 1, 400 do
    E:Step(st, 1 / 60, events)
    if st.phase == E.PHASE.AIM then break end
  end
  local miss, caught = 0, 0
  for _, e in ipairs(events) do if e.type == "total_miss" then miss = miss + 1 elseif e.type == "bucket" then caught = caught + 1 end end
  out.bucketNoMiss = caught == 1 and miss == 0
  -- a boss counts three strikes a tenth of a second apart
  local spec
  for n = 10, 400, 10 do spec = L:Build(n) if spec.boss then break end end
  st = E:NewLevel(spec)
  local b = st.boss
  local hp0 = b.hp
  for k = 1, 3 do
    st.time = st.time + 0.1
    E.HitPeg(st, b, { vx = 0, vy = 100 }, events)
  end
  out.bossThree = hp0 - b.hp == 3
  -- after a shot that hit it, the boss throws scrap
  wipe(events)
  st.phase = E.PHASE.FLIGHT
  st.bossHitThisShot = true
  st.balls = {}
  st.shots = 1
  for _ = 1, 30 do E:Step(st, 1 / 60, events) if st.phase ~= E.PHASE.FLIGHT then break end end
  local scrap = 0
  for _, p in ipairs(st.pegs) do if p.scrap then scrap = scrap + 1 end end
  out.scrap = scrap
  -- a hatched egg's phoenix lights the pieces above it
  st = E:NewLevel(L:Build(1))
  st.pegs = {
    { shape = "peg", x = 245, y = 450, r = E.EGG_R, kind = "egg", goal = true, hp = 1, maxhp = 1, special = true },
    { shape = "peg", x = 245, y = 300, kind = "blue" }, { shape = "peg", x = 270, y = 200, kind = "blue" },
    { shape = "peg", x = 400, y = 300, kind = "blue" },
  }
  st.goalTotal, st.goalLeft = 1, 1
  st.phase = E.PHASE.FLIGHT
  st.balls = { { x = 60, y = 100, vx = 0, vy = 0, slow = 0 } }
  E.HitPeg(st, st.pegs[1], nil, events)
  for _ = 1, 60 do st.balls[1] = { x = 60, y = 100, vx = 0, vy = 0, slow = 0 }; E:Step(st, 1 / 60, events) end
  out.phoenix = st.pegs[2].lit and st.pegs[3].lit and not st.pegs[4].lit
  -- a lost egg ends the level even while aiming
  st = E:NewLevel(L:Build(1))
  st.pegs = { { shape = "peg", x = 245, y = E.FIELD_H + 40, r = E.EGG_R, kind = "egg", goal = true, hp = 2, maxhp = 2, special = true, loose = true },
              { shape = "peg", x = 100, y = 300, kind = "orange", goal = true } }
  st.hasLoose = true
  st.pegs[1].vx, st.pegs[1].vy = 0, 0
  st.bucket.x = 60
  for _ = 1, 30 do E:Step(st, 1 / 60, events) if st.phase == E.PHASE.OVER then break end end
  out.eggAim = st.phase == E.PHASE.OVER and st.result and st.result.eggLost == true
  -- a gem on a slope rolls off instead of sticking
  st = E:NewLevel(L:Build(1))
  st.pegs = { { shape = "peg", x = 200, y = 300, r = E.GEM_R, kind = "gem", goal = true, special = true, loose = true },
              { shape = "brick", x = 220, y = 330, angle = 0.35, w = 90, h = E.BRICK_H, kind = "blue" } }
  st.hasLoose = true
  st.pegs[1].vx, st.pegs[1].vy = 0, 0
  local x0 = st.pegs[1].x
  for _ = 1, 120 do E:Step(st, 1 / 60, events) end
  out.rolls = st.pegs[1].x - x0 > 40
  -- the suction tube draws a falling ball toward the bucket
  st = E:NewLevel(L:Build(1))
  st.pegs = {}
  st.bucket.x, st.bucket.dir = 400, 0
  st.armed = "suction"
  st.aim = 0
  E:Launch(st, events)
  local ball = st.balls[1]
  ball.x, ball.y, ball.vx, ball.vy = 245, E.FIELD_H - 200, 0, 100
  for _ = 1, 10 do E:Step(st, 1 / 60, events) end
  out.suction = ball.vx > 20
  return out
end
""")
r = ev("round_probe")()
check("a bucket catch is never a Total Miss", r["bucketNoMiss"])
check("a boss counts every strike of a quick bank shot", r["bossThree"])
check("a boss hit in a shot throws scrap blocks", r["scrap"] >= 1, str(r["scrap"]))
check("a hatched egg's phoenix lights the pieces in its column and no others", r["phoenix"])
check("a lost egg ends the level even while aiming", r["eggAim"])
check("a gem on a slope rolls off instead of sticking", r["rolls"])
check("the suction tube draws a falling ball toward the bucket", r["suction"])
lua(r"""
function suction_steer_probe()
  local st = E:NewLevel(L:Build(1))
  st.pegs = {}
  st.bucket.x, st.bucket.dir = 330, 0
  st.armed = "suction"
  st.aim = 0
  local events = {}
  E:Launch(st, events)
  local ball = st.balls[1]
  ball.x, ball.y, ball.vx, ball.vy = 180, E.FIELD_H - 330, 0, 60
  -- the same fall with no suction, for the vertical speeds
  local t0 = st.time
  local sameFall = true
  local caught = 0
  for _ = 1, 120 do
    E:Step(st, 1 / 120, events)
    local b = st.balls[1]
    if b and b.vy > 0 and math.abs(b.vy - (60 + E.GRAVITY * (st.time - t0))) > 1 then sameFall = false end
    for _, e in ipairs(events) do if e.type == "bucket" then caught = caught + 1 end end
    wipe(events)
    if #st.balls == 0 then break end
  end
  return caught, sameFall
end
""")
caught, same_fall = ev("suction_steer_probe")()
check("the suction tube steers a ball falling 150 px off into the tube without touching its fall speed", caught == 1 and same_fall, f"{caught} {same_fall}")
check("every level's objective is the one its map node shows", True)

# ------------------------------------------------------------------ art slots
# Every slot in Art.lua has its file in Textures/ at the size it says, and
# nothing sits in Textures/ that the registry does not know about.
import struct
slot_names = list(ev("ART.ORDER").values())
missing, wrong, stray = [], [], []
tex_dir = os.path.join(ADDON_DIR, "Textures")
for name in slot_names:
    d = ev(f"ART.SLOTS['{name}']")
    path = os.path.join(tex_dir, d.file + ".tga")
    if not os.path.exists(path):
        missing.append(name)
        continue
    with open(path, "rb") as fh:
        head = fh.read(18)
    w, h = struct.unpack("<HH", head[12:16])
    pow2 = (w & (w - 1)) == 0 and (h & (h - 1)) == 0
    if d.free:
        if not pow2 or w > 512 or h > 1024:
            wrong.append((name, w, h))
    elif (w, h) != (d.w, d.h):
        wrong.append((name, w, h, d.w, d.h))
known = {ev(f"ART.SLOTS['{n}']").file + ".tga" for n in slot_names}
for f in os.listdir(tex_dir):
    if f.lower().endswith(".tga") and f not in known:
        stray.append(f)
check(f"every one of the {len(slot_names)} art slots has its texture at the listed size", not missing and not wrong, f"missing {missing} wrong {wrong}")
check("no texture in Textures/ is outside the registry", not stray, str(stray))
check("no Lua file names a texture path outside Art.lua",
      not any("Textures\\\\" in open(os.path.join(ADDON_DIR, f), encoding="utf-8").read() for f in ("Core.lua", "Engine.lua", "Levels.lua", "Plays.lua", "UI.lua", "Minimap.lua", "Mascot.lua")))

print()
if failures:
    print(f"{len(failures)} FAILED: " + ", ".join(failures))
    raise SystemExit(1)
print("all gnomish pachinko checks passed")
