-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL LOG REPORT
--  Turns riftveil_debug.txt files into numbers: per-method and per-engine-
--  arm head rates with 95% Wilson intervals, the engine's override record
--  against the chain, its calibration (predicted vs observed head rate)
--  and a range check on every applied correction value.
--
--  Head rate = head/neck hits / (head/neck hits + resolver misses). Body
--  hits and non-resolver misses (spread, prediction error, death, and
--  extrapolated or teleported shots) carry no yaw information and are
--  counted separately, the same rule on_aim_hit / on_aim_miss use.
--
--  Usage:  lua5.3 tools/log_report.lua riftveil_debug_prev.txt riftveil_debug.txt
--          (luajit works too; pass files oldest first)
-- ══════════════════════════════════════════════════════════════════
local files = {...}
if #files == 0 then
    io.stderr:write("usage: lua tools/log_report.lua <riftveil_debug.txt> [more logs...]\n")
    os.exit(2)
end

-- 95% Wilson score interval for k successes in n trials.
local function wilson(k, n)
    if n == 0 then return 0, 0 end
    local z, p = 1.96, k / n
    local den = 1 + z * z / n
    local mid = (p + z * z / (2 * n)) / den
    local half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return math.max(0, mid - half), math.min(1, mid + half)
end

-- Cut and pad by UTF-8 characters, not bytes: most names in these logs
-- are Cyrillic, and a byte cut splits a letter in half.
local function cell(s, width)
    local out, n = {}, 0
    for ch in s:gmatch("[\1-\127\194-\244][\128-\191]*") do
        if n == width then break end
        n = n + 1; out[n] = ch
    end
    return table.concat(out) .. string.rep(" ", width - n)
end

local function bucket(t, key)
    local b = t[key]
    if not b then b = {head = 0, body = 0, rmiss = 0, other = 0, oor = 0}; t[key] = b end
    return b
end

local by_meth, by_arm, by_player, by_origin, by_state, by_wpn = {}, {}, {}, {}, {}, {}
local calib = {}          -- decile -> {n, heads, psum}
local versions, engine_lines, resets = {}, {}, 0
local brier_n, brier_se = 0, 0
local total_lines = 0

local function field(line, key)
    return line:match(" " .. key .. "=(%S+)")
end

for _, path in ipairs(files) do
    local f = io.open(path, "r")
    if not f then io.stderr:write("cannot open " .. path .. "\n"); os.exit(2) end
    for line in f:lines() do
        total_lines = total_lines + 1
        local v = line:match("RIFTVEIL v([%d%.]+) loaded")
        if v then versions[#versions + 1] = v end
        if line:find("%]%[engine%]") then engine_lines[#engine_lines + 1] = line end
        if line:find("soft reset", 1, true) then resets = resets + 1 end

        local is_hit  = line:find("%]%[hit%]") ~= nil
        local is_miss = line:find("%]%[miss%]") ~= nil and line:find("reason=") ~= nil
        if is_hit or is_miss then
            local player = line:match("player=(.-) group=") or line:match("player=(.-) reason=") or "?"
            local meth   = field(line, "meth") or "?"
            local val    = tonumber(field(line, "val") or "")
            local arm    = line:match(" eng=([%w_:]+)")
            local by     = line:match(" eng=[%w_:]+(%*)") ~= nil
            local p      = tonumber(line:match(" p=([%d%.]+)") or "")
            local kind
            if is_hit then
                local g = field(line, "group")
                kind = (g == "head" or g == "neck") and "head" or "body"
            else
                local reason = field(line, "reason")
                local extra  = line:find("[extrap]", 1, true) or line:find("[tele]", 1, true)
                kind = ((reason == "?" or reason == "") and not extra) and "rmiss" or "other"
            end
            local targets = {bucket(by_meth, meth), bucket(by_player, player)}
            local st = field(line, "st")
            if st then targets[#targets + 1] = bucket(by_state, st) end
            local wpn = field(line, "wpn")
            if wpn then targets[#targets + 1] = bucket(by_wpn, wpn) end
            if arm then
                targets[#targets + 1] = bucket(by_arm, arm)
                targets[#targets + 1] = bucket(by_origin, by and "engine override" or "chain pick")
            end
            for _, b in ipairs(targets) do
                b[kind] = b[kind] + 1
                if val and math.abs(val) > 60.5 then b.oor = b.oor + 1 end
            end
            if p and (kind == "head" or kind == "rmiss") then
                local y = (kind == "head") and 1 or 0
                local d = math.min(9, math.floor(p * 10))
                local c = calib[d] or {n = 0, heads = 0, psum = 0}
                calib[d] = c
                c.n, c.heads, c.psum = c.n + 1, c.heads + y, c.psum + p
                brier_n, brier_se = brier_n + 1, brier_se + (p - y) * (p - y)
            end
        end
    end
    f:close()
end

local function report(title, t, min_n)
    local keys = {}
    for k, b in pairs(t) do
        if b.head + b.rmiss + b.body + b.other >= (min_n or 1) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        return (t[a].head + t[a].rmiss) > (t[b].head + t[b].rmiss)
    end)
    if #keys == 0 then return end
    print(("\n%s"):format(title))
    print(("  %-22s %5s %5s %5s %5s   %-17s %s"):format("", "head", "rmiss", "body", "other", "head rate (95%)", "|val|>60"))
    for _, k in ipairs(keys) do
        local b = t[k]
        local n = b.head + b.rmiss
        local lo, hi = wilson(b.head, n)
        local rate = n > 0 and ("%3d%% [%2d-%3d%%]"):format(
            math.floor(100 * b.head / n + 0.5), math.floor(100 * lo + 0.5), math.floor(100 * hi + 0.5)) or "   --"
        print(("  %s %5d %5d %5d %5d   %-17s %s"):format(
            cell(k, 22), b.head, b.rmiss, b.body, b.other, rate, b.oor > 0 and tostring(b.oor) or "-"))
    end
end

print(("RIFTVEIL log report -- %d file(s), %d lines"):format(#files, total_lines))
if #versions > 0 then
    local seen, list = {}, {}
    for _, v in ipairs(versions) do if not seen[v] then seen[v] = true; list[#list + 1] = v end end
    print("versions loaded: " .. table.concat(list, ", ") .. ("  (%d loads)"):format(#versions))
end
print(("soft resets: %d   engine log lines: %d"):format(resets, #engine_lines))

report("BY METHOD (what was applied)", by_meth)
report("BY MOVEMENT STATE (v7.5+ logs)", by_state)
report("BY WEAPON (v7.7+ logs)", by_wpn)
report("BY ENGINE ARM", by_arm)
report("ENGINE OVERRIDES vs CHAIN PICKS", by_origin)
report("BY PLAYER (5+ shots)", by_player, 5)

if brier_n > 0 then
    print("\nENGINE CALIBRATION (predicted head chance vs what happened)")
    print(("  %-10s %6s %10s %10s"):format("predicted", "shots", "mean pred", "observed"))
    for d = 0, 9 do
        local c = calib[d]
        if c then
            print(("  %3d-%3d%%   %6d %9.0f%% %9.0f%%"):format(d * 10, d * 10 + 10, c.n,
                100 * c.psum / c.n, 100 * c.heads / c.n))
        end
    end
    print(("  Brier score %.3f over %d scored shots (0.25 = coin-flip guessing)"):format(brier_se / brier_n, brier_n))
else
    print("\n(no engine telemetry in these logs -- v7.3+ writes eng=/p= on every shot line)")
end
