-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL AIM MODEL
--  Derives the per-weapon aim policy instead of hand-picking thresholds:
--  for each weapon, enemy HP and resolver certainty, which choice gives
--  the highest probability of killing within one peek?
--
--    head       aim head normally        hit = geo_head * p_side
--    head_sp    head with safe point     hit = geo_sp (side doesn't matter)
--    body       prefer body              hit = geo_body * body_side
--
--  p_side is the resolver's certainty (engine posterior); desync moves the
--  head far more than the body, so the side matters for the head only
--  (body_side ~ 0.95). A peek lasts PEEK seconds; a weapon fires
--  1 + floor(PEEK / interval) shots in it, and damage adds up across hits.
--  Assumptions are named constants -- change them and rerun:
--      lua5.3 tools/aim_model.lua          (or luajit)
--  Weapon numbers are CS:GO weapon data from memory (base damage, armor
--  penetration, fire interval); the v7.7 shot logs (dmg=, group=, wpn=,
--  ar=) are there to confirm them.
-- ══════════════════════════════════════════════════════════════════
local PEEK      = 0.60   -- seconds an enemy stays shootable in one peek
local GEO_HEAD  = 0.85   -- head hit chance if the side is right
local GEO_SP    = 0.60   -- head hit chance on safe points (smaller area, side-proof)
local GEO_BODY  = 0.97   -- body hit chance
local BODY_SIDE = 0.95   -- body barely moves with desync
local ARMORED, HELMET = true, true

-- name, base damage, armor penetration, fire interval (s)
local WEAPONS = {
    {"awp",    115, 0.975, 1.46},
    {"scout",   88, 0.85,  1.25},
    {"auto",    80, 0.825, 0.25},
    {"r8",      86, 0.932, 0.50},
    {"deagle",  63, 0.932, 0.225},
    {"pistol",  35, 0.70,  0.17},   -- p250/five-seven class
}

local function damage(base, pen, part)
    local mult = (part == "head") and 4 or 1.0   -- chest; stomach would be 1.25
    local armored = ARMORED and (part ~= "head" or HELMET)
    return math.floor(base * mult * (armored and pen or 1))
end

-- P(kill within n shots) when each shot hits with probability q for d damage.
local function p_kill(q, d, hp, n)
    local need = math.ceil(hp / math.max(d, 1))
    if need > n then return 0 end
    -- at least `need` hits in n shots (binomial tail)
    local total = 0
    for k = need, n do
        local c = 1
        for i = 1, k do c = c * (n - k + i) / i end
        total = total + c * q ^ k * (1 - q) ^ (n - k)
    end
    return total
end

-- Probability that the FIRST kill lands on shot k (k = 1..n), for a
-- per-shot hit chance q and damage d: exactly need-1 hits in the first
-- k-1 shots, then a hit.
local function first_kill_at(q, d, hp, k)
    local need = math.ceil(hp / math.max(d, 1))
    if need > k then return 0 end
    local c = 1
    for i = 1, need - 1 do c = c * (k - 1 - (need - 1) + i) / i end
    return c * q ^ (need - 1) * (1 - q) ^ (k - need) * q
end

-- Value of an option: P(kill within the peek), each kill discounted by
-- exp(-threat * time) -- the enemy shoots back, so a later kill is worth
-- less. threat = 0 ignores time; 3/s means ~5% of a 0.25 s delay lost.
local function value(q, d, hp, n, interval, threat)
    local v = 0
    for k = 1, n do v = v + first_kill_at(q, d, hp, k) * math.exp(-threat * (k - 1) * interval) end
    return v
end

-- Smallest resolver certainty p at which aiming head beats both head safe
-- points and body; "never" if it doesn't within p <= 1.
local function head_threshold(dh, db, hp, n, interval, body_geo, threat)
    for p = 0.30, 1.0001, 0.01 do
        local vh  = value(GEO_HEAD * p, dh, hp, n, interval, threat)
        local vsp = value(GEO_SP, dh, hp, n, interval, threat)
        local vb  = value(body_geo * BODY_SIDE, db, hp, n, interval, threat)
        if vh >= vsp and vh >= vb then return p end
    end
    return nil
end
-- What wins below that threshold: safe-point head or body.
local function fallback(dh, db, hp, n, interval, body_geo, threat)
    local vsp = value(GEO_SP, dh, hp, n, interval, threat)
    local vb  = value(body_geo * BODY_SIDE, db, hp, n, interval, threat)
    return (vb > vsp) and "body" or "head-sp"
end

local EXPOSURE = {{"full", 0.97}, {"partial", 0.55}, {"head only", 0}}
local HPS = {100, 80, 60, 40}
for _, threat in ipairs({0, 3}) do
    print(string.format("\n=== enemy threat %s ===", threat == 0 and "ignored (no time pressure)" or "3/s (they shoot back)"))
    print("  head when resolver certainty >= p*, else the fallback")
    for _, w in ipairs(WEAPONS) do
        local name, base, pen, interval = w[1], w[2], w[3], w[4]
        local n = 1 + math.floor(PEEK / interval)
        local dh, db = damage(base, pen, "head"), damage(base, pen, "body")
        local line = string.format("  %-7s", name)
        for _, ex in ipairs(EXPOSURE) do
            local cells = {}
            for _, hp in ipairs(HPS) do
                local t = head_threshold(dh, db, hp, n, interval, ex[2], threat)
                local fb = fallback(dh, db, hp, n, interval, ex[2], threat)
                cells[#cells + 1] = (t and (t <= 0.305 and "any" or string.format("%.2f", t)) or "never")
                    .. "/" .. (fb == "body" and "B" or "S")
            end
            line = line .. string.format(" | %-9s %s", ex[1], table.concat(cells, " "))
        end
        print(line)
    end
end
print("\n  cells per exposure: hp 100 80 60 40 -> p*/fallback  (B = prefer body, S = head on safe points)")
