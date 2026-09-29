-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL LEARNER SIMULATION
--  Runs the ACTUAL adaptive-learner functions from riftveil.lua (extracted
--  from the source, not reimplemented) against simulated opponents and
--  compares head-hit rate with the fixed "always keep the tracked side,
--  full magnitude, always force" policy RIFTVEIL used before the learner.
--
--  Opponent model: per movement state, a head-hit probability for each
--  choice (keep / flip side, half-magnitude bonus, built-in resolver).
--  Every resolved shot is a head hit (success) or a resolver miss
--  (failure), matching how on_aim_hit / on_aim_miss feed the learner.
--
--  Usage:  lua5.3 tools/learner_sim.lua
--  Exit 1 if the learner's average gain over fixed drops to <= 0, or if it
--  loses more than MAX_LOSS points in any scenario.
-- ══════════════════════════════════════════════════════════════════
local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local TARGET = SCRIPT_DIR .. "../riftveil.lua"
local SHOTS, RUNS, MAX_LOSS = 40, 3000, 3.0

local src = assert(io.open(TARGET)):read("a")
local a = assert(src:find("local LEARN_SIDE_PRIOR", 1, true), "learner block not found")
local b = assert(src:find("\nend\n", src:find("local function VorDecide", 1, true), true), "VorDecide not found")
local block = src:sub(a, b + 4)
local prelude = [[
local VTYPE = {UNK="unk",STP="stp",PKA="pka",DCK="dck",LBY="lby",LND="lnd",CTR="ctr"}
local METH = {RING="ring",PERIOD="period",LAGCOMP="lagcomp",PHASE="phase",DEF_TICK="def_tick",RING_SPK="ring_spike"}
local function isnum(v, lo, hi) return type(v)=="number" and v==v and (not lo or v>=lo) and (not hi or v<=hi) end
]]
local M = assert(load(prelude .. block ..
    "\nreturn {LearnFromDB=LearnFromDB, LearnToDB=LearnToDB, LearnDecide=LearnDecide, LearnFeedback=LearnFeedback, VorDecide=VorDecide}"))()

math.randomseed(20260929)
local STATES = {"standing", "running", "air", "crouch"}
local function flat(k, f) return function() return k, f end end
local SCEN = {
    {name = "side right",        side = flat(0.70, 0.40), half = -0.05, builtin = 0.55},
    {name = "side inverted",     side = flat(0.40, 0.72), half = -0.05, builtin = 0.55},
    {name = "side ~equal",       side = flat(0.62, 0.62), half = -0.05, builtin = 0.55},
    {name = "log-like mix",      side = flat(0.68, 0.64), half = -0.02, builtin = 0.60},
    {name = "per-state differs", half = -0.05, builtin = 0.55,
     side = function(st) if st == "standing" or st == "crouch" then return 0.70, 0.40 end return 0.40, 0.70 end},
    {name = "one state inverted", half = -0.05, builtin = 0.55,
     side = function(st) if st == "air" then return 0.35, 0.70 end return 0.70, 0.40 end},
    {name = "builtin beats us",  side = flat(0.45, 0.42), half = -0.03, builtin = 0.70},
    {name = "half magnitude",    side = flat(0.55, 0.40), half = 0.12, builtin = 0.50},
}

local function p_hit(sc, st, side, mag, mode)
    if mode == 2 then return sc.builtin end
    local pk, pf = sc.side(st)
    local p = (side == 1) and pk or pf
    if mag == 2 then p = p + sc.half end
    return math.max(0.02, math.min(0.98, p))
end

local function run(sc, learner, db)
    local hits = 0
    local rec = {L = M.LearnFromDB(db)}
    for _ = 1, SHOTS do
        local st = STATES[math.random(#STATES)]
        rec.state = st
        local side, mag, mode = 1, 1, 1
        if learner then side, mag, mode = M.LearnDecide(rec) end
        local ok = math.random() < p_hit(sc, st, side, mag, mode)
        if ok then hits = hits + 1 end
        if learner then M.LearnFeedback(rec, {state = st, side = side, mag = mag, mode = mode}, ok) end
    end
    return hits, rec
end

print(string.format("%-20s %10s %10s %8s %14s", "scenario", "fixed", "learner", "delta", "2nd match*"))
local sum, worst, fails = 0, math.huge, 0
for _, sc in ipairs(SCEN) do
    local f, l, l2 = 0, 0, 0
    for _ = 1, RUNS do
        f = f + run(sc, false)
        local h, rec = run(sc, true)
        l = l + h
        l2 = l2 + run(sc, true, {learn = M.LearnToDB(rec.L)})
    end
    local T = SHOTS * RUNS
    local d = 100 * (l - f) / T
    sum = sum + d
    if d < worst then worst = d end
    print(string.format("%-20s %9.1f%% %9.1f%% %+7.1f %13.1f%%", sc.name, 100 * f / T, 100 * l / T, d, 100 * l2 / T))
end
local avg = sum / #SCEN
print(string.format("\naverage gain %+.2f points, worst scenario %+.2f", avg, worst))
print("* 2nd match vs the same opponent, starting from the persisted (halved) DB counts")

-- Vuln orientation: coupled votes should converge to the inverted arm when
-- the derived delta sign is backwards.
local rec = {L = M.LearnFromDB(nil)}
local flipped = 0
for _ = 1, 40 do
    local arm, fam = M.VorDecide(rec, "unk")
    local ok = math.random() < ((arm == 2) and 0.7 or 0.35)
    local v = rec.L.vor[fam]
    if (ok and arm == 1) or ((not ok) and arm == 2) then v.k = v.k + 1 else v.f = v.f + 1 end
    if arm == 2 then flipped = flipped + 1 end
end
print(string.format("vuln orientation, inverted truth: chose 'inverted' on %d/40 windows", flipped))

if avg <= 0 then print("FAIL: learner no longer beats fixed on average"); fails = fails + 1 end
if worst < -MAX_LOSS then print(string.format("FAIL: worst-case loss exceeds %.1f points", MAX_LOSS)); fails = fails + 1 end
if flipped < 20 then print("FAIL: vuln orientation did not converge to 'inverted'"); fails = fails + 1 end
os.exit(fails == 0 and 0 or 1)
