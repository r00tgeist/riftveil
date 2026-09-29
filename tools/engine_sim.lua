-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL DECISION ENGINE SIMULATION
--  Runs the ACTUAL engine code from riftveil.lua (the DECISION ENGINE
--  block, extracted from the source, not reimplemented) against simulated
--  opponents, and compares head-hit rate with the legacy priority chain on
--  its own -- the exact behaviour the engine falls back to.
--
--  Opponent model, per shot: a true side T (random). Each source's as-is
--  sign matches T with its own accuracy q (LBY window, hit memory, pose
--  side). The pose side is applied inverted by suppress, so q_pose = 0.22
--  is the chain being right 78% of the time, as in the logs. A shot on the
--  true side: 72% head, 13% body, 15% resolver miss. On the wrong side:
--  18% head, 12% body, 70% resolver miss. Built-in: its own head rate.
--  Body hits carry no information, as in on_aim_hit.
--
--  Legacy chain: LBY window when one is open (30% of shots) > hit memory
--  (after 2 head hits) > suppress. 2 players per match share the engine's
--  global table; a second match starts from the saved, halved counts.
--
--  Also checks the engine's safety property on random candidate sets:
--  with no evidence it must return the chain's pick, every time.
--
--  Usage:  lua5.3 tools/engine_sim.lua
--  Exit 1 if the average gain is <= 0, any scenario loses more than
--  MAX_LOSS points, or the no-evidence check fails once.
--
--  Differential check against the previous version of the script (the
--  engine switched off must write exactly the same player-list values):
--    RV_TARGET=old.lua RV_PLIST_OUT=a.txt lua5.3 tools/sandbox_check.lua
--    RV_NO_ENGINE=1    RV_PLIST_OUT=b.txt lua5.3 tools/sandbox_check.lua
--    cmp a.txt b.txt
-- ══════════════════════════════════════════════════════════════════
local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local TARGET = SCRIPT_DIR .. "../riftveil.lua"
local SHOTS, RUNS, MAX_LOSS = 40, 2000, 2.0

local src = assert(io.open(TARGET)):read("a")
local a = assert(src:find("\nENG = {", 1, true), "engine block not found")
local b = assert(src:find("\nend\n", src:find("function ENG.Label", 1, true), true), "ENG.Label not found")
local block = src:sub(a + 1, b + 4)
local prelude = [[
local ENG
local database = {read = function() return nil end}
local function isnum(v, lo) return type(v) == "number" and v == v and (not lo or v >= lo) end
]]
local ENG = assert(load(prelude .. block .. "\nreturn ENG"))()
-- Tuning: RV_ENG="FORGET=1,PH_LAMBDA=99" overrides engine constants.
for k, v in (os.getenv("RV_ENG") or ""):gmatch("([%w_]+)=([%w%.%-%+]+)") do ENG[k] = tonumber(v) end
RUNS = tonumber(os.getenv("RV_RUNS") or "") or RUNS

math.randomseed(20260929)
local STATS = {safe = 0}
local function side() return (math.random() < 0.5) and 1 or -1 end

-- q_* may be a number or a function(state, shot) for context and drift.
local STATES = {"standing", "running", "air", "crouch"}
local SCEN = {
    {name = "chain right (logs)",   q_pose = 0.22, q_lby = 0.70, q_hit = 0.70, builtin = 0.45},
    {name = "suppress backwards",   q_pose = 0.75, q_lby = 0.70, q_hit = 0.70, builtin = 0.45},
    {name = "LBY window backwards", q_pose = 0.22, q_lby = 0.30, q_hit = 0.70, builtin = 0.45},
    {name = "hit memory stale",     q_pose = 0.22, q_lby = 0.70, q_hit = 0.35, builtin = 0.45},
    {name = "everything a coin",    q_pose = 0.50, q_lby = 0.50, q_hit = 0.50, builtin = 0.45},
    {name = "built-in strong",      q_pose = 0.45, q_lby = 0.55, q_hit = 0.55, builtin = 0.70},
    {name = "mixed",                q_pose = 0.60, q_lby = 0.40, q_hit = 0.55, builtin = 0.45},
    {name = "per-state split",      q_lby = 0.70, q_hit = 0.60, builtin = 0.45,
     q_pose = function(st) return (st == "standing" or st == "crouch") and 0.22 or 0.80 end},
    {name = "config switch @20",    q_lby = 0.70, q_hit = 0.70, builtin = 0.45,
     q_pose = function(_, shot) return shot <= 20 and 0.22 or 0.80 end},
    {name = "no signal at all",     q_pose = 0.50, q_lby = 0.50, q_hit = 0.50, builtin = 0.45, flat = true},
}

local function q(v, st, shot) return type(v) == "function" and v(st, shot) or v end
local function sgn_for(acc, T) return (math.random() < acc) and T or -T end

-- One player's match. Returns head hits.
local function play(sc, use_engine, rec)
    local heads = 0
    local C = {}
    for shot = 1, SHOTS do
        local T = side()
        local st = STATES[math.random(#STATES)]
        local n = 0
        local signs = {}
        local function push(arm, s, meth)
            n = n + 1
            C[n] = C[n] or {}
            C[n].arm, C[n].val, C[n].meth = arm, s, meth
        end
        local legacy
        if math.random() < 0.3 then
            local s = sgn_for(q(sc.q_lby, st, shot), T); signs.vuln_lby = s
            push("vuln_lby:as", s); push("vuln_lby:inv", -s)
            legacy = legacy or "vuln_lby:as"
        end
        if rec.heads >= 2 then
            local s = sgn_for(q(sc.q_hit, st, shot), T); signs.hitmem = s
            push("hitmem:as", s); push("hitmem:inv", -s)
            legacy = legacy or "hitmem:as"
        end
        local ps = sgn_for(q(sc.q_pose, st, shot), T); signs.pose = ps
        push("pose:as", ps); push("pose:inv", -ps)
        legacy = legacy or "pose:inv"
        push("builtin", 0)
        local d
        for i = 1, n do if C[i].arm == legacy then d = i end end
        local pick = use_engine and ENG.Decide(rec, C, n, d, st) or d
        local c = C[pick]
        local r, outcome = math.random(), nil
        if sc.flat then
            -- outcome independent of the side: nothing to learn
            outcome = (r < 0.45) and "head" or ((r < 0.57) and "body" or "miss")
        elseif c.arm == "builtin" then
            outcome = (r < sc.builtin) and "head" or ((r < sc.builtin + 0.12) and "body" or "miss")
        elseif c.val == T then
            outcome = (r < 0.72) and "head" or ((r < 0.85) and "body" or "miss")
        else
            outcome = (r < 0.18) and "head" or ((r < 0.30) and "body" or "miss")
        end
        if outcome == "head" then heads = heads + 1; rec.heads = rec.heads + 1 end
        if outcome ~= "body" then
            local p = ENG.Post(rec.E, c.arm, st)
            ENG.Credit(rec, {arm = c.arm, sign = c.val, signs = signs, state = st, p = p},
                       outcome == "head")
        end
    end
    return heads
end

local function match(sc, use_engine, saved)
    ENG.G = saved and ENG.Load({all = saved.G}).all or {}
    ENG.AUD = {n = 0, se_eng = 0, se_base = 0, heads = 0, safe = false}
    local total, recs = 0, {}
    for p = 1, 2 do
        local rec = {E = ENG.Load(saved and saved.E[p]), heads = 0}
        recs[p] = rec
        total = total + play(sc, use_engine, rec)
    end
    if ENG.AUD.safe then STATS.safe = STATS.safe + 1 end
    return total, {G = ENG.SaveGlobal(), E = {ENG.Save(recs[1].E), ENG.Save(recs[2].E)}}
end

print(string.format("%-22s %8s %8s %7s %11s %6s", "scenario", "chain", "engine", "delta", "2nd match", "safe"))
local sum, worst, fails = 0, math.huge, 0
for _, sc in ipairs(SCEN) do
    local ch, en, en2 = 0, 0, 0
    STATS.safe = 0
    for _ = 1, RUNS do
        ch = ch + match(sc, false)
        local h, saved = match(sc, true)
        en = en + h
        en2 = en2 + match(sc, true, saved)
    end
    local T = SHOTS * 2 * RUNS
    local d = 100 * (en - ch) / T
    sum = sum + d
    if d < worst then worst = d end
    -- safe: share of matches that ended in audit safe mode
    print(string.format("%-22s %7.1f%% %7.1f%% %+6.1f %10.1f%% %5.0f%%", sc.name,
        100 * ch / T, 100 * en / T, d, 100 * en2 / T, 100 * STATS.safe / (RUNS * 2)))
end
local avg = sum / #SCEN
print(string.format("\naverage gain %+.2f points, worst scenario %+.2f", avg, worst))

-- Safety: with no evidence at all, the engine returns the chain's pick.
local ARMS = {}
for arm in pairs(ENG.PRIOR) do ARMS[#ARMS + 1] = arm end   -- priors are keyed by arm
table.sort(ARMS)
local bad = 0
for _ = 1, 5000 do
    ENG.G = {}
    ENG.AUD.safe = false
    local n, C = math.random(2, #ARMS), {}
    for i = 1, n do C[i] = {arm = ARMS[math.random(#ARMS)], val = side()} end
    local d = math.random(n)
    if ENG.Decide({E = ENG.New()}, C, n, d, STATES[math.random(#STATES)]) ~= d then bad = bad + 1 end
end
print(string.format("no-evidence check: engine kept the chain's pick in %d/5000 random cases", 5000 - bad))

if avg <= 0 then print("FAIL: engine no longer beats the chain on average"); fails = fails + 1 end
if worst < -MAX_LOSS then print(string.format("FAIL: a scenario loses more than %.1f points", MAX_LOSS)); fails = fails + 1 end
if bad > 0 then print("FAIL: engine overrode the chain with no evidence"); fails = fails + 1 end
os.exit(fails == 0 and 0 or 1)
