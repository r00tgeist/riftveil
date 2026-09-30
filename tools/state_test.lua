-- ══════════════════════════════════════════════════════════════════
--  STATE TRACKER TEST
--  Plays enemy movement generated with Source movement physics through the
--  real STATE TRACKER code (extracted from riftveil.lua, not reimplemented)
--  and scores it against the condition an AA builder would be in.
--
--  Physics, 64 tick: sv_accelerate 5.5, sv_friction 5.2, sv_stopspeed 80,
--  jump 301.99 u/s up with sv_gravity 800 (0.75 s in the air), duck 0 -> 1
--  in 13 ticks. Weapon max speeds from CS:GO weapon data; HvH slow walk at
--  34% of max speed (the accuracy threshold slow motion keys aim for).
--
--  Every scenario runs with the enemy's records arriving every 1, 3, 8 and
--  14 ticks (fakelag); a record's state holds until the next one, and every
--  tick is scored. Ticks where the builders themselves disagree (easing out
--  of a slow walk, a duck halfway down) are not scored.
--
--  Usage:
--    luajit tools/state_test.lua                 new tracker (riftveil.lua)
--    luajit tools/state_test.lua old.lua         any version, for comparison
--  Prints accuracy per scenario for v6.2 mode (FEATURE.STATE_PHYSICS off),
--  physics mode, and the ceiling: the truth at every record, held until the
--  next one (what fakelag leaves possible). Exit 1 if physics mode is more
--  than 3 points under the ceiling overall, or 10 in any scenario.
-- ══════════════════════════════════════════════════════════════════
-- physics mode vs the ceiling (a tracker that knew the truth at every
-- record, held until the next): within 3 points overall, 10 per scenario
local MAX_GAP_TOTAL, MAX_GAP_SCENARIO = 0.03, 0.10
local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local TARGET = arg and arg[1] or (SCRIPT_DIR .. "../riftveil.lua")
local src = assert(io.open(TARGET)):read("*a")

local function find_plain(s, needle, from) return s:find(needle, from or 1, true) end
local function line_start(s, i) return (s:sub(1, i - 1):match(".*()\n") or 0) + 1 end
local a, b
local ts = find_plain(src, "\n--  STATE TRACKER")
if ts then
    a = line_start(src, ts)                 -- the banner line above the title
else
    a = assert(find_plain(src, "\nlocal function ClassifyState"), "no ClassifyState in " .. TARGET) + 1
end
b = assert(find_plain(src, "\n-- TrustedCfg: only hand", a), "end marker not found") - 1
local block = src:sub(a, b)

local band = (bit and bit.band) or (function()
    local ok, m = pcall(require, "bit")
    if ok and m then return m.band end
    return load("return function(x, y) return math.floor(x) & math.floor(y) end")()
end)()

local STATE = {STANDING = "standing", RUNNING = "running", SLOWMOTION = "slowmotion",
               CROUCH = "crouch", CROUCH_MOVING = "crouch_moving", AIR = "air", AIR_CROUCH = "air_crouch"}
local FEATURE = {STATE_PHYSICS = true}
local W = {}   -- the enemy as the game would report it this tick
local entity = {
    get_prop = function(ent, prop)
        if ent == 900 then return (prop == "m_iItemDefinitionIndex") and W.weapon or nil end
        if prop == "m_fFlags" then
            if W.flags_nil then return nil end
            return W.ground and 1 or 0
        end
        if prop == "m_bIsScoped" then return W.scoped and 1 or 0 end
        return nil
    end,
    get_player_weapon = function() return 900 end,
    get_player_name = function(i) return "p" .. tostring(i) end,
}
local function isnum(v, lo, hi)
    if type(v) ~= "number" or v ~= v or math.abs(v) >= 1e9 then return false end
    if lo and v < lo then return false end
    if hi and v > hi then return false end
    return true
end
local env = setmetatable({entity = entity, bit = {band = band}, STATE = STATE, FEATURE = FEATURE,
                          info = function() end, dbg = function() end, DET = {verbose = false},
                          isnum = isnum}, {__index = _G})
local chunk = assert(load(block .. "\nreturn ClassifyState, TrackState", "state_tracker", "t", env))
local ClassifyState, TrackState = chunk()

-- A tracker without TrackState (v8.4 and older): its inline ProcessPlayer
-- path -- speed change from prev_spd / prev_spd_st.
if not TrackState then
    TrackState = function(rec, player, as, spd, st)
        local dv
        if FEATURE.STATE_PHYSICS and rec.prev_spd and rec.prev_spd_st and st > rec.prev_spd_st then
            dv = (spd - rec.prev_spd) / (st - rec.prev_spd_st)
        end
        local s = ClassifyState(player, as, spd, dv, rec.state)
        rec.prev_spd, rec.prev_spd_st = spd, st
        return s, spd
    end
end

-- ── Physics ──────────────────────────────────────────────────────────
local TI = 1 / 64
local ACCEL, FRIC, STOP = 5.5, 5.2, 80
local function accel(v, wish) return math.min(wish, v + ACCEL * wish * TI) end
local function friction(v) return math.max(0, v - math.max(v, STOP) * FRIC * TI) end
local WPN = {knife = {42, 250}, ak = {7, 215}, awp = {9, 200, 100}, auto = {11, 215, 120},
             scout = {40, 230, 230}, deagle = {1, 230}}
local function maxspd(w, scoped) local d = WPN[w]; return (scoped and d[3]) or d[2] end

-- A scenario is a list of ticks: {spd, ground, duck, weapon, scoped, truth,
-- vel_nil, flags_nil}. Builders are small helpers appending phases.
local function Scenario()
    local S = {v = 0, duck = 0, ground = true, w = "knife", scoped = false, ticks = {}}
    function S:tick(truth, extra)
        local t = {spd = self.v, ground = self.ground, duck = self.duck, weapon = WPN[self.w][1],
                   scoped = self.scoped, truth = truth}
        if extra then for k, x in pairs(extra) do t[k] = x end end
        self.ticks[#self.ticks + 1] = t
    end
    function S:stand(n, truth) for _ = 1, n do self.v = friction(self.v); self:tick(truth or STATE.STANDING) end end
    function S:run(n, wish, truth)
        for _ = 1, n do self.v = accel(self.v, wish); self:tick(truth or STATE.RUNNING) end
    end
    -- no input: friction until stopped; the builders read "moving" while
    -- the speed is still above their threshold (2-10 u/s)
    function S:coast(truth_moving, truth_stopped)
        while self.v > 0 do
            self.v = friction(self.v)
            self:tick(self.v > 10 and truth_moving or (self.v <= 5 and (truth_stopped or STATE.STANDING) or nil))
        end
    end
    function S:counter(wish)
        while self.v > 0 do
            self.v = math.max(0, friction(self.v) - ACCEL * wish * TI)
            self:tick(self.v > 10 and STATE.RUNNING or (self.v <= 5 and STATE.STANDING or nil))
        end
    end
    function S:duck_to(target, truth)   -- 13 ticks from 0 to 1; transition not scored
        local step = 1 / 13
        while math.abs(self.duck - target) > 1e-6 do
            self.duck = (target > self.duck) and math.min(target, self.duck + step) or math.max(target, self.duck - step)
            self.v = friction(self.v)
            self:tick(nil)
        end
        if truth then self:tick(truth) end
    end
    function S:jump(n_extra_air, wish, duck, truth)
        -- 48 ticks in the air; horizontal speed kept (no air friction)
        self.ground = false
        if duck then self.duck = 1 end
        for _ = 1, 48 + (n_extra_air or 0) do
            if wish then self.v = math.min(wish, self.v) end
            self:tick(truth or (duck and STATE.AIR_CROUCH or STATE.AIR))
        end
        self.ground = true
        if duck then self.duck = 0 end
    end
    return S
end

local SCEN = {}
-- gap: allowed distance from the ceiling when a scenario needs evidence
-- the ceiling gets for free (default MAX_GAP_SCENARIO)
local function add(name, build, lags, gap) SCEN[#SCEN + 1] = {name = name, build = build, lags = lags, gap = gap} end

add("knife peek, run and stop", function(S) S.w = "knife"; S:stand(10); S:run(30, 250); S:coast(STATE.RUNNING); S:stand(20) end)
add("rifle peek, counter-strafe", function(S) S.w = "ak"; S:stand(10); S:run(25, 215); S:counter(215); S:stand(20) end)
add("rifle slow walk", function(S)
    S.w = "ak"; S:stand(10); S:run(60, maxspd("ak") * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(15)
end)
add("knife slow walk", function(S)
    S.w = "knife"; S:stand(10); S:run(60, 250 * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(15)
end)
add("AWP scoped walk", function(S)
    S.w, S.scoped = "awp", true; S:stand(10); S:run(50, 100); S:coast(STATE.RUNNING); S:stand(15)
end)
add("AWP scoped slow walk", function(S)
    S.w, S.scoped = "awp", true; S:stand(10); S:run(60, 100 * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(15)
end)
add("AWP unscoped run / slow walk", function(S)
    S.w = "awp"; S:stand(10); S:run(40, 200); S:coast(STATE.RUNNING); S:stand(10)
    S:run(60, 200 * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(10)
end)
add("auto scoped walk / slow walk", function(S)
    S.w, S.scoped = "auto", true; S:stand(10); S:run(50, 120); S:coast(STATE.RUNNING); S:stand(10)
    S:run(60, 120 * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(10)
end)
add("scout run / slow walk", function(S)
    S.w, S.scoped = "scout", true; S:stand(10); S:run(40, 230); S:coast(STATE.RUNNING); S:stand(10)
    S:run(60, 230 * 0.34, STATE.SLOWMOTION); S:coast(nil); S:stand(10)
end)
add("crouch, crouch-walk", function(S)
    S.w = "ak"; S:stand(10); S:duck_to(1); S:stand(20, STATE.CROUCH)
    S:run(50, 215 * 0.34, STATE.CROUCH_MOVING); S:coast(STATE.CROUCH_MOVING, STATE.CROUCH); S:stand(15, STATE.CROUCH)
    S:duck_to(0); S:stand(10)
end)
add("jumps (standing, running, crouched)", function(S)
    S.w = "knife"; S:stand(10); S:jump(); S:stand(10)
    S:run(30, 250); S:jump(0, 250); S:coast(STATE.RUNNING); S:stand(10)
    S:jump(0, nil, true); S:stand(10)
end)
add("micro-movement AA", function(S)
    S.w = "ak"
    for i = 1, 80 do S.v = (i % 2 == 0) and 1.1 or 0; S:tick(STATE.STANDING) end
end)
add("fake duck (records every 14 ticks)", function(S)
    S.w = "ak"; S:stand(10)
    for i = 1, 200 do
        -- the duck amount a record shows during a fake duck: somewhere mid-way
        S.duck = 0.25 + 0.5 * ((i * 37) % 11) / 10
        S.v = 0
        S:tick(STATE.CROUCH)
    end
    S.duck = 0; S:stand(15)
end, {14})
add("velocity unreadable while running", function(S)
    S.w = "ak"; S:stand(10, STATE.STANDING)
    for _ = 1, 60 do S.v = accel(S.v, 215); S:tick(STATE.RUNNING, {vel_nil = true}) end
    while S.v > 0 do
        S.v = friction(S.v)
        S:tick(S.v > 10 and STATE.RUNNING or (S.v <= 5 and STATE.STANDING or nil), {vel_nil = true})
    end
    for _ = 1, 15 do S:tick(STATE.STANDING, {vel_nil = true}) end
end, nil, 0.15)   -- two moving records before the origin is trusted: up to 28 ticks at fakelag 14
add("ground flag unreadable", function(S)
    S.w = "ak"
    for _ = 1, 30 do S:tick(STATE.STANDING, {flags_nil = true}) end
    for _ = 1, 40 do S.v = accel(S.v, 215); S:tick(STATE.RUNNING, {flags_nil = true}) end
end)

-- ── Run ──────────────────────────────────────────────────────────────
local function play(sc, lag, physics, oracle)
    FEATURE.STATE_PHYSICS = physics
    local S = Scenario()
    sc.build(S)
    local rec = {state = STATE.STANDING}
    local cur = STATE.STANDING
    local x = 0                  -- origin along one axis, integrated from speed
    local ok, n = 0, 0
    for i, t in ipairs(S.ticks) do
        x = x + t.spd * TI
        if (i - 1) % lag == 0 then
            W.ground, W.scoped, W.weapon, W.flags_nil = t.ground, t.scoped, t.weapon, t.flags_nil
            local as = {duck_amount = t.duck, on_ground = t.ground}
            local spd = t.vel_nil and 0 or t.spd
            local st = 1000 + i
            cur = TrackState(rec, 101, as, spd, st, x, 0, TI)
            if oracle then cur = t.truth or cur end
            rec.state = cur
            rec.prev_spd = spd
            rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_tick = x, 0, st
        end
        if t.truth then
            n = n + 1
            if cur == t.truth then ok = ok + 1
            elseif (physics or os.getenv("RV_STATE_TRACE_ALL")) and os.getenv("RV_STATE_TRACE") and sc.name:find(os.getenv("RV_STATE_TRACE"), 1, true) then
                print(string.format("    %s lag %2d tick %3d spd %6.1f truth %-13s got %s", physics and "P" or "L", lag, i, t.spd, t.truth, cur))
            end
        end
    end
    return ok, n
end

print(string.format("%-40s %14s %14s %9s", "scenario (fakelag 1/3/8/14)", "v6.2 mode", "physics mode", "ceiling"))
local tot = {[false] = {0, 0}, [true] = {0, 0}, ceil = {0, 0}}
local fails = 0
local function score(sc, physics, oracle)
    local ok, n = 0, 0
    for _, lag in ipairs(sc.lags or {1, 3, 8, 14}) do
        local o, m = play(sc, lag, physics, oracle)
        ok, n = ok + o, n + m
    end
    return ok, n
end
for _, sc in ipairs(SCEN) do
    local lo, ln = score(sc, false)
    local po, pn = score(sc, true)
    local co, cn = score(sc, true, true)
    tot[false][1], tot[false][2] = tot[false][1] + lo, tot[false][2] + ln
    tot[true][1], tot[true][2]   = tot[true][1] + po, tot[true][2] + pn
    tot.ceil[1], tot.ceil[2]     = tot.ceil[1] + co, tot.ceil[2] + cn
    local flag = ""
    if co / cn - po / pn > (sc.gap or MAX_GAP_SCENARIO) then fails = fails + 1; flag = "  <- FAIL" end
    print(string.format("%-40s %5.1f%% (%4d) %5.1f%% (%4d) %8.1f%%%s", sc.name,
        100 * lo / ln, ln, 100 * po / pn, pn, 100 * co / cn, flag))
end
local tp, tc = tot[true][1] / tot[true][2], tot.ceil[1] / tot.ceil[2]
print(string.format("%-40s %13.1f%% %13.1f%% %8.1f%%", "TOTAL", 100 * tot[false][1] / tot[false][2], 100 * tp, 100 * tc))
if tc - tp > MAX_GAP_TOTAL then
    print(string.format("FAIL: physics mode %.1f points under the ceiling overall", 100 * (tc - tp))); fails = fails + 1
end
if fails > 0 then print("FAIL: " .. fails .. " check(s)") end
os.exit(fails == 0 and 0 or 1)
