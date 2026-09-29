-- ══════════════════════════════════════════════════════════════════
--  PLIST PARITY  -- compares two RV_PLIST_OUT write logs by EFFECT
--  Usage: lua5.3 tools/plist_parity.lua a.txt b.txt [show]
--
--  Versions cache player-list writes differently (v6.2 rewrites every field
--  every tick, later versions only on change), so the raw logs differ even
--  when behaviour doesn't. This carries each player's fields forward and,
--  on every tick either log wrote, compares the forced body yaw value
--  (0 when "Force body yaw" is off):
--    same      both force, same sign (mean |dmag| = magnitude difference)
--    OPPOSITE  both force, opposite sides
--    onlyA/B   only one of them forces
-- ══════════════════════════════════════════════════════════════════
local function load(path)
    local byt, maxt = {}, 0
    for line in io.lines(path) do
        local t, pl, f, v = line:match("^(%d+)\t(%d+)\t([^\t]+)\t(.*)$")
        if t then
            t = tonumber(t)
            byt[t] = byt[t] or {}
            table.insert(byt[t], {pl, f, v})
            if t > maxt then maxt = t end
        end
    end
    return byt, maxt
end

local ta, ma = load(arg[1])
local tb, mb = load(arg[2])
local ca, cb, players = {}, {}, {}
local n, same, opp, only_a, only_b, none, dmag = 0, 0, 0, 0, 0, 0, 0
local shown = {}

local function forced(c)
    return c["Force body yaw"] == "true" and tonumber(c["Force body yaw value"]) or 0
end

for t = 0, math.max(ma, mb) do
    for _, w in ipairs(ta[t] or {}) do ca[w[1]] = ca[w[1]] or {}; ca[w[1]][w[2]] = w[3]; players[w[1]] = true end
    for _, w in ipairs(tb[t] or {}) do cb[w[1]] = cb[w[1]] or {}; cb[w[1]][w[2]] = w[3]; players[w[1]] = true end
    if ta[t] or tb[t] then
        for pl in pairs(players) do
            local va, vb = forced(ca[pl] or {}), forced(cb[pl] or {})
            n = n + 1
            if va ~= 0 and vb ~= 0 then
                if (va > 0) == (vb > 0) then
                    same = same + 1
                    dmag = dmag + math.abs(math.abs(va) - math.abs(vb))
                else
                    opp = opp + 1
                    if #shown < 8 then shown[#shown + 1] = string.format("t=%d p=%s A=%.1f B=%.1f", t, pl, va, vb) end
                end
            elseif va ~= 0 then only_a = only_a + 1
            elseif vb ~= 0 then only_b = only_b + 1
            else none = none + 1 end
        end
    end
end

print(string.format("n=%d same=%d (mean |dmag| %.1f) OPPOSITE=%d onlyA=%d onlyB=%d none=%d",
    n, same, same > 0 and dmag / same or 0, opp, only_a, only_b, none))
if arg[3] then for _, l in ipairs(shown) do print("  " .. l) end end
