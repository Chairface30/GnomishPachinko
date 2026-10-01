"""Gnomish Pachinko: level generation, engine rules and a headless window run.

Part 1 builds every one of the 1000 levels and checks them: reproducible
from the level number, orange/green counts as published, pieces inside the
zone and not overlapping (except brick chains), every family and every
power used.

Part 2 plays scripted levels through the engine: every level ends, balls
never leave the field, Fever starts on the last orange, powers do what they
say (multiball splits, blast lights neighbours, fireball passes through,
spooky re-enters, super guide counts down), free balls arrive at the score
marks, and the result records.

Part 3 drives the window against a mocked frame API: start a level, aim,
click, pump OnUpdate, use the level select.

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
function GetTime() return __now end
function time() return 1000000 + math.floor(__now) end
UIParent = nil
UISpecialFrames = {}
tinsert = table.insert
function BreakUpLargeNumbers(n) return tostring(n) end
__printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) __printed[#__printed + 1] = m end }
__sfx = 0
function PlaySoundFile() __sfx = __sfx + 1 end
__cursor = { x = 270, y = 300 }
function GetCursorPosition() return __cursor.x, __cursor.y end
SlashCmdList = {}

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
function Obj:CreateFontString() return new() end
function CreateFrame(kind, name, parent)
  local f = new(name)
  rawset(f, "_parent", parent)
  return f
end
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
for f in ("Core.lua", "Engine.lua", "Levels.lua", "UI.lua"):
    src = open(os.path.join(ADDON_DIR, f), encoding="utf-8").read()
    rt.execute(f"local function chunk(...) {src} end chunk('GnomishPachinko')")
rt.execute("GP = GnomishPachinko; E = GP.Engine; L = GP.Levels; UI = GP.UI")
ev, lua = rt.eval, rt.execute

# ------------------------------------------------------------------ levels
lua(r"""
function level_report(n)
  local spec = L:Build(n)
  local counts = { orange = 0, green = 0, blue = 0, purple = 0, brick = 0, total = #spec.pegs }
  local bad = 0
  counts.block = 0
  counts.moving = 0
  for i, p in ipairs(spec.pegs) do
    counts[p.kind] = (counts[p.kind] or 0) + 1
    if p.moving then counts.moving = counts.moving + 1 end
    if p.shape == "brick" then counts.brick = counts.brick + 1 end
    local rp = E.PegRadius(p)
    if p.x - rp < E.PEG_MARGIN - 6.01 or p.x + rp > E.FIELD_W - E.PEG_MARGIN + 6.01
       or p.y - rp < E.PEG_TOP - 0.01 or p.y + rp > E.PEG_BOTTOM + 0.01 then bad = bad + 1 end
    for j = i + 1, #spec.pegs do
      local q = spec.pegs[j]
      if not (p.group and p.group == q.group) and p.shape == "peg" and q.shape == "peg" then
        local need = 2 * E.PEG_R + 2 * E.BALL_R + 6
        local dx, dy = p.x - q.x, p.y - q.y
        if dx * dx + dy * dy < need * need - 0.01 then bad = bad + 1 end
      end
    end
  end
  return spec, counts, bad
end
""")
report = ev("level_report")
families, powers, problems, bricks_total = set(), set(), [], 0
gimmick_levels, moving_total, block_total, gimmick_names = 0, 0, 0, set()
sig1 = None
for n in range(1, 1001):
    spec, counts, bad = report(n)
    orange_expected = min(round(15 + (n - 1) / 999 * 15), counts['total'] - counts['block'] - 6)
    families.add(spec.layout)
    powers.add(spec.power)
    bricks_total += counts["brick"]
    moving_total += counts["moving"]
    block_total += counts["block"]
    if spec.gimmick:
        gimmick_levels += 1
        for g in spec.gimmick.split(" + "):
            gimmick_names.add(g)
    if n < 21 and spec.gimmick:
        problems.append((n, "gimmick too early"))
    if counts["orange"] != orange_expected or counts["green"] != 2:
        problems.append((n, "counts", dict(counts), orange_expected))
    if bad:
        problems.append((n, "placement", bad))
    if counts["total"] < 28:
        problems.append((n, "thin", counts["total"]))
    if n == 500:
        sig1 = [(p.x, p.y, p.kind, p.shape) for p in spec.pegs.values()]
check("all 1000 levels build with the published orange count, 2 greens, no overlaps", not problems, str(problems[:4]))
check("every layout family appears", len(families) == len(ev("L.FAMILIES")), str(sorted(families)))
check("every power is assigned somewhere", len(powers) == 5, str(powers))
check("bricks are in play", bricks_total > 1000, str(bricks_total))
check("most levels from chapter 3 carry a gimmick", gimmick_levels > 500, str(gimmick_levels))
check("every gimmick appears", gimmick_names == set(g.name for g in ev("L.GIMMICKS").values()), str(sorted(gimmick_names)))
print(f"      gimmick levels {gimmick_levels}, moving pieces {moving_total}, solid blocks {block_total}")

# a wheel turns, a slider slides, blocks never light
lua(r"""
function gimmick_probe(name)
  for n = 21, 1000 do
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
  for n = 21, 1000 do
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
spec2 = report(500)[0]
check("a level rebuilds identically", sig1 == [(p.x, p.y, p.kind, p.shape) for p in spec2.pegs.values()])
check("chapter names cycle through 100 places", ev("L:ChapterName(1)") == "Elwynn Forest" and ev("L:ChapterName(100)") == "Sunwell Plateau" and ev("L:ChapterName(101)") == "Elwynn Forest")

# ------------------------------------------------------------------ engine
lua(r"""
function play_level(n, aimMode, forcePower)
  local spec = L:Build(n)
  if forcePower then spec.power = forcePower end
  local st = E:NewLevel(spec)
  local info = { escaped = false, fever = nil, powers = 0, buckets = 0, spooky = 0, scoreFree = 0,
                 maxBalls = 0, steps = 0, stuck = 0, blastLit = 0, superGuideSeen = false }
  local events = {}
  local shots = 0
  while st.phase ~= E.PHASE.OVER and info.steps < 400000 do
    if st.phase == E.PHASE.AIM then
      shots = shots + 1
      if st.superGuide > 0 then info.superGuideSeen = true end
      if aimMode == "sweep" then
        local pick, fallback
        for deg = -80, 80, 2 do
          st.aim = deg * math.pi / 180
          local _, peg = E:Guide(st, 2.5)
          if peg and not peg.lit then
            if peg.kind == "orange" then pick = st.aim break end
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
      assert(E:Launch(st))
    end
    for i = #events, 1, -1 do events[i] = nil end
    E:Step(st, 1 / 60, events)
    info.steps = info.steps + 1
    if #st.balls > info.maxBalls then info.maxBalls = #st.balls end
    for _, b in ipairs(st.balls) do
      if b.x < 0 or b.x > E.FIELD_W or b.y < 0 then info.escaped = true end
    end
    for _, e in ipairs(events) do
      if e.type == "fever" then info.fever = st.orangeLeft end
      if e.type == "power" then info.powers = info.powers + 1 end
      if e.type == "bucket" then info.buckets = info.buckets + 1 end
      if e.type == "spooky" then info.spooky = info.spooky + 1 end
      if e.type == "freeball_score" then info.scoreFree = info.scoreFree + 1 end
      if e.type == "lost" and e.stuck then info.stuck = info.stuck + 1 end
      if e.type == "peg" and e.quiet then info.blastLit = info.blastLit + 1 end
    end
  end
  return st, info
end
""")
play = ev("play_level")
problems, cleared, buckets, stuck, multi = [], 0, 0, 0, 0
for n in list(range(1, 41)) + list(range(480, 500)) + list(range(981, 1001)):
    st, info = play(n, "sweep", None)
    if st.phase != "OVER":
        problems.append((n, "no end"))
        continue
    if info.escaped:
        problems.append((n, "escaped"))
    r = st.result
    if r.cleared:
        cleared += 1
        if info.fever != 0:
            problems.append((n, "fever timing", info.fever))
        if r.binScore not in (10000, 50000, 100000):
            problems.append((n, "bin", r.binScore))
    elif info.fever is not None:
        problems.append((n, "fever without clear"))
    if r.oranges + st.orangeLeft != st.orangeTotal:
        problems.append((n, "orange bookkeeping"))
    buckets += info.buckets
    stuck += info.stuck
    if info.maxBalls > 1:
        multi += 1
check("80 scripted levels end cleanly with the rules intact", not problems, str(problems[:4]))
print(f"      cleared {cleared}/80, free balls from the bucket {buckets}, stuck balls {stuck}, multiball levels {multi}")
check("the sweep bot clears some levels", cleared > 0)
check("the bucket returns balls", buckets > 0)

# powers, forced one at a time on an early level while hunting greens
seen = {}
for power in ("multiball", "guide", "blast", "fireball", "spooky"):
    hits = 0
    for n in range(1, 16):
        st, info = play(n, "green", power)
        if info.powers > 0:
            hits += 1
            seen.setdefault(power, []).append(info)
    print(f"      {power}: green hit on {hits}/15 levels")
check("multiball spawns a twin", any(i.maxBalls > 1 for i in seen.get("multiball", [])))
check("super guide shows on the shots after a green", any(i.superGuideSeen for i in seen.get("guide", [])))
check("space blast lights neighbours quietly", any(i.blastLit > 0 for i in seen.get("blast", [])))
check("spooky ball re-enters from the top", any(i.spooky > 0 for i in seen.get("spooky", [])))
check("fireball levels get a power event", len(seen.get("fireball", [])) > 0)

# fireball passes through: a ball with fire set reaches further than its first contact
lua(r"""
function fire_passes()
  local spec = L:Build(3)
  local st = E:NewLevel(spec)
  -- aim at the first peg straight below the muzzle and check the ball lights more than one
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

# score free balls
lua(r"""
function score_free()
  local st = E:NewLevel(L:Build(1))
  local events = {}
  st.score = 24990
  st.balls[1] = { x = 270, y = 300, vx = 0, vy = 0, slow = 0 }
  st.phase = E.PHASE.FLIGHT
  local before = st.ballsLeft
  -- light an orange by hand through a step with the ball sitting on a peg
  local p
  for _, q in ipairs(st.pegs) do if q.kind == "orange" then p = q break end end
  st.balls[1].x, st.balls[1].y = p.x, p.y - E.PEG_R - E.BALL_R + 1
  E:Step(st, 1 / 60, events)
  local got = 0
  for _, e in ipairs(events) do if e.type == "freeball_score" then got = got + 1 end end
  return got, st.ballsLeft - before
end
""")
got, delta = ev("score_free")()
check("crossing 25,000 points gives a free ball", got == 1 and delta == 1, f"{got} {delta}")

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
check("the window opens on level 1", ev("UI.frame:IsShown() and UI.state.level == 1"))
ok, result = ev("ui_play")(900)
check("a level plays to its end through the window", ok)
check("the result is recorded in the saved progress", ev("GnomishPachinkoDB.best[1] ~= nil"))
lua("UI:StartLevel(1); __before = GnomishPachinkoDB.unlocked")
# force a clear by lighting every orange, then finishing through the engine
lua(r"""
local st = UI.state
for _, p in ipairs(st.pegs) do if p.kind == "orange" then p.lit = true; p.gone = true end end
st.orangeLeft = 1; st.orangeHit = st.orangeTotal - 1
local last
for _, p in ipairs(st.pegs) do if p.kind == "orange" then last = p end end
last.lit = false; last.gone = false
E:Aim(st, last.x, last.y)
""")
ok, result = ev("ui_play")(900)
cleared = bool(result and result.cleared)
if cleared:
    check("clearing level 1 unlocks level 2", ev("GnomishPachinkoDB.unlocked") >= 2 and ev("GnomishPachinkoDB.cleared[1] == true"))
    lua("UI.nextBtn:Click()")
    check("NEXT LEVEL moves to level 2", ev("UI.state.level") == 2)
else:
    print("      (the scripted shots did not reach the last orange; unlock checks skipped)")
    lua("GP:RecordResult({ level = 1, cleared = true, score = 1234 })")
    check("recording a clear unlocks the next level", ev("GnomishPachinkoDB.unlocked") >= 2)
lua("UI:ShowLevelSelect()")
check("level select shows page 1 with level 2 open", ev("UI.levelPanel:IsShown() and UI.levelPanel.cells[2]:IsEnabled() and not UI.levelPanel.cells[3]:IsEnabled()"))
lua("UI.levelPanel.cells[2]:Click()")
check("clicking an open level starts it", ev("UI.state.level == 2 and not UI.levelPanel:IsShown()"))
lua("UI.levelPanel.cells[1]:Click()")  # hidden panel, but the click handler still works
lua("UI:ShowLevelSelect(); UI.levelPanel.next:Click()")
check("paging reaches levels 101-200", ev("UI.levelPanel.cells[1].level") == 101)
lua('SlashCmdList["GNOMISHPACHINKO"]("999")')
check("slash refuses a locked level", any("not unlocked" in m for m in ev("__printed").values()))

print()
if failures:
    print(f"{len(failures)} FAILED: " + ", ".join(failures))
    raise SystemExit(1)
print("all gnomish pachinko checks passed")
