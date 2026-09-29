-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL CHEAT LAYER SIMULATION
--  Runs the ACTUAL engine block from riftveil.lua (extracted, as in
--  engine_sim.lua) over a career of matches against new opponents, and
--  measures what pooling evidence per enemy cheat (ENG.C, CHEAT_CAP) buys
--  over the lobby-wide global layer alone (CHEAT_CAP = 0).
--
--  World: 4 cheats, each with a typical AA behaviour -- the engine_sim
--  opponent profiles (chain right, suppress backwards, LBY window
--  backwards, built-in strong). A player runs their cheat's profile with
--  probability R and a random profile otherwise (custom configs, Luas).
--  R = 0 makes the cheat meaningless: the layer must not hurt then.
--  Each match: 2 new opponents, 10 shots each (the logs average 10 per
--  player per match), cheat detected with probability 0.8
--  (revealer not running / no voice data otherwise). Global and cheat
--  evidence persist between matches, halved on load as in the script.
--
--  Usage: luajit tools/cheat_sim.lua   (RV_RUNS=n to change run count)
--  Exit 1 if the chosen CHEAT_CAP loses more than MAX_LOSS points to
--  CHEAT_CAP = 0 at any R, or gains nothing on average.
-- ══════════════════════════════════════════════════════════════════
local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local src = assert(io.open(SCRIPT_DIR .. "../riftveil.lua")):read("a")
local a = assert(src:find("\nENG = {", 1, true), "engine block not found")
local b = assert(src:find("\nend\n", src:find("function ENG.Label", 1, true), true))
local prelude = [[
local ENG
local database = {read = function() return nil end}
local function isnum(v, lo) return type(v) == "number" and v == v and (not lo or v >= lo) end
]]
local ENG = assert(load(prelude .. src:sub(a + 1, b + 4) .. "\nreturn ENG"))()
local CHOSEN = ENG.CHEAT_CAP
local SHOTS, MATCHES, MAX_LOSS = tonumber(os.getenv("RV_SHOTS") or "") or 10, 12, 0.5
local RUNS = tonumber(os.getenv("RV_RUNS") or "") or 600
math.randomseed(20260929)

local PROFILES = {
    {q_pose = 0.22, q_lby = 0.70, q_hit = 0.70, builtin = 0.45},
    {q_pose = 0.75, q_lby = 0.70, q_hit = 0.70, builtin = 0.45},
    {q_pose = 0.22, q_lby = 0.30, q_hit = 0.70, builtin = 0.45},
    {q_pose = 0.45, q_lby = 0.55, q_hit = 0.55, builtin = 0.70},
}
local CHEATS = {"nl", "gs", "ot", "ev"}
local STATES = {"standing", "running", "air", "crouch"}
local function side() return (math.random() < 0.5) and 1 or -1 end
local function sgn(acc, T) return (math.random() < acc) and T or -T end

local function play(pr, rec)
    local heads, C = 0, {}
    for _ = 1, SHOTS do
        local T, st, n, signs, legacy = side(), STATES[math.random(#STATES)], 0, {}, nil
        local function push(arm, s)
            n = n + 1; C[n] = C[n] or {}; C[n].arm, C[n].val = arm, s
        end
        if math.random() < 0.3 then
            local s = sgn(pr.q_lby, T); signs.vuln_lby = s
            push("vuln_lby:as", s); push("vuln_lby:inv", -s); legacy = "vuln_lby:as"
        end
        if rec.heads >= 2 then
            local s = sgn(pr.q_hit, T); signs.hitmem = s
            push("hitmem:as", s); push("hitmem:inv", -s); legacy = legacy or "hitmem:as"
        end
        local ps = sgn(pr.q_pose, T); signs.pose = ps
        push("pose:as", ps); push("pose:inv", -ps); legacy = legacy or "pose:inv"
        push("builtin", 0)
        local d
        for i = 1, n do if C[i].arm == legacy then d = i end end
        local c = C[ENG.Decide(rec, C, n, d, st)]
        local r, outcome = math.random(), nil
        if c.arm == "builtin" then
            outcome = (r < pr.builtin) and "head" or ((r < pr.builtin + 0.12) and "body" or "miss")
        elseif c.val == T then
            outcome = (r < 0.72) and "head" or ((r < 0.85) and "body" or "miss")
        else
            outcome = (r < 0.18) and "head" or ((r < 0.30) and "body" or "miss")
        end
        if outcome == "head" then heads = heads + 1; rec.heads = rec.heads + 1 end
        if outcome ~= "body" then
            ENG.Credit(rec, {arm = c.arm, sign = c.val, signs = signs, state = st,
                             p = (ENG.Post(rec.E, c.arm, st))}, outcome == "head")
        end
    end
    return heads
end

local function career(R, cap)
    ENG.CHEAT_CAP = cap
    local saved_g, saved_c, total = nil, nil, 0
    for _ = 1, MATCHES do
        ENG.G = saved_g and ENG.Load({all = saved_g}).all or {}
        ENG.LoadCheat(saved_c)
        ENG.AUD = {n = 0, se_eng = 0, se_base = 0, heads = 0, safe = false}
        for _ = 1, 2 do
            local k = math.random(#CHEATS)
            local pr = (math.random() < R) and PROFILES[k] or PROFILES[math.random(#PROFILES)]
            local rec = {E = ENG.New(), heads = 0}
            if math.random() < 0.8 then rec.E.cheat = CHEATS[k] end
            total = total + play(pr, rec)
        end
        saved_g, saved_c = ENG.SaveGlobal(), ENG.SaveCheat()
    end
    return total
end

local CAPS = {0, 6, 12, 24}
print(string.format("%-6s" .. string.rep(" %9s", #CAPS), "R", "cap 0", "cap 6", "cap 12", "cap 24"))
local fails, gain_sum, worst = 0, 0, math.huge
local RS = {1.0, 0.7, 0.4, 0.0}
for _, R in ipairs(RS) do
    local row, base = {}, nil
    for i, cap in ipairs(CAPS) do
        -- same random stream per cap: identical opponents, only the cap differs
        math.randomseed(1000 + math.floor(R * 100))
        local h = 0
        for _ = 1, RUNS do h = h + career(R, cap) end
        local rate = 100 * h / (RUNS * MATCHES * 2 * SHOTS)
        base = base or rate
        row[i] = string.format("%8.2f%%", rate)
        if cap == CHOSEN then
            local d = rate - base
            gain_sum = gain_sum + d
            if d < worst then worst = d end
            row[i] = row[i] .. "*"
        end
    end
    print(string.format("%-6.1f %s", R, table.concat(row, " ")))
end
print(string.format("\nCHEAT_CAP %d (*): average gain over cap 0 %+.2f points, worst %+.2f",
    CHOSEN, gain_sum / #RS, worst))
if worst < -MAX_LOSS then print("FAIL: the cheat layer loses to the global layer alone"); fails = fails + 1 end
if gain_sum <= 0 then print("FAIL: the cheat layer gains nothing on average"); fails = fails + 1 end
os.exit(fails == 0 and 0 or 1)
