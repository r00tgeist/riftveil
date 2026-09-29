-- ══════════════════════════════════════════════════════════════════
--  CHEAT REVEALER unit test (LuaJIT only: needs the real FFI)
--  Extracts the CHEAT REVEALER block from riftveil.lua, builds real voice
--  packets with the same struct layout, and checks:
--    1. each cheat's signature run is detected as that cheat;
--    2. random packets (every field random) never label anyone;
--    3. a short run (below each detector's threshold) labels nobody.
--  Usage: luajit tools/cheat_detect_test.lua      exit 1 on any failure
-- ══════════════════════════════════════════════════════════════════
local ffi = require("ffi")
local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local src = assert(io.open(SCRIPT_DIR .. "../riftveil.lua")):read("*a")
-- From the banner line above "--  CHEAT REVEALER" to the one above
-- "--  RECORD MANAGEMENT" (plain finds: the banner is UTF-8).
local function banner_start(title)
    local i = assert(src:find("\n--  " .. title, 1, true), title .. " not found")
    return src:sub(1, i - 1):match(".*()\n") + 1
end
local a = banner_start("CHEAT REVEALER")
local b = banner_start("RECORD MANAGEMENT") - 1
local LOGS = {}
local env = setmetatable({
    ffi = ffi,
    info = function(_, fmt, ...) LOGS[#LOGS + 1] = string.format(fmt, ...) end,
    entity = {get_player_name = function(i) return "p" .. i end},
    -- the CHEAT PROFILES block that follows loads its table at startup
    database = {read = function() return nil end},
    isnum = function(v, lo) return type(v) == "number" and v == v and (not lo or v >= lo) end,
}, {__index = _G})
local chunk = assert(load(src:sub(a, b) .. "\nreturn {OnVoice = OnVoice, CHEAT_OF = CHEAT_OF, ForgetAllCheats = ForgetAllCheats, ForgetCheat = ForgetCheat}",
    "cheat_block", "t", env))
local M = chunk()

local buf = ffi.new("uint8_t[64]")
local P = ffi.cast(ffi.typeof([[
    struct {
        char pad_0000[8]; int32_t client; int32_t audible_mask;
        uint32_t xuid_low; uint32_t xuid_high; void* voice_data;
        bool proximity; bool caster; char pad_001E[2]; int32_t format;
        int32_t sequence_bytes; uint32_t section_number;
        uint32_t uncompressed_sample_offset; char pad_0030[4]; uint32_t has_bits;
    } *]]), buf)
local function word(off, v) ffi.cast("uint16_t*", buf + off)[0] = v end
local function send(ent, fill)
    ffi.fill(buf, 64, 0)
    buf[8] = ent - 1
    fill()
    M.OnVoice({data = buf})
end
local rnd = math.random
math.randomseed(20260929)
local function noise()
    for i = 12, 63 do buf[i] = rnd(0, 255) end
end

local fails = 0
local function check(name, cond, detail)
    print(string.format("  %s  %s%s", cond and "PASS" or "FAIL", name, detail and ("  (" .. detail .. ")") or ""))
    if not cond then fails = fails + 1 end
end

-- Signature generators: one packet of each cheat's traffic. Offsets in the
-- struct: xuid_low 16, xuid_high 20 (word at 22 = its high half),
-- sequence_bytes 40, section_number 44.
local SIG = {
    pd = function() noise(); word(16, 0x695B) end,
    ft = function() noise(); word(16, 0x7FFA) end,
    pl = function() noise(); word(44, 0x7275) end,
    af = function() noise(); word(16, 0xAFF1) end,
    r7 = function() noise(); word(16, 0x0234) end,
    nw = function() noise(); P.xuid_high = 0 end,
    ot = function() noise(); P.xuid_low = 777; P.section_number = 5 end,
    gs = function() noise(); P.xuid_high = rnd(1, 2^31); P.sequence_bytes = rnd(1e5, 2^31) end,
}
-- neverlose: one fixed xuid_high on every 4th packet, the rest unique
local nl_i = 0
SIG.nl = function()
    noise(); nl_i = nl_i + 1
    P.xuid_high = (nl_i % 4 == 0) and 123456789 or rnd(1, 2^31)
    P.sequence_bytes = 4242   -- constant, unlike gamesense
end
-- ev0lve: x, x+d, x-d, *, x+1 in the xuid_high stream
local ev_i, ev_x = 0, 1000
SIG.ev = function()
    noise(); ev_i = ev_i + 1
    local k = ev_i % 5
    if k == 1 then ev_x = rnd(1000, 2^20) end
    P.xuid_high = ({[1] = ev_x, [2] = ev_x + 7, [3] = ev_x - 7, [4] = rnd(1, 2^20), [0] = ev_x + 1})[k]
end
print("1. Signature runs are detected")
local ent = 2
for id, gen in pairs(SIG) do
    M.ForgetAllCheats()
    for _ = 1, 60 do send(ent, gen) end
    check(id, M.CHEAT_OF[ent] == id, "got " .. tostring(M.CHEAT_OF[ent]))
end

print("2. Real voice (no cheat) labels nobody")
-- A legit client's voice: its own steam xuid on every packet, a sequence
-- counter that grows, payload bytes random. (Packets with random xuid AND
-- random sequence bytes on every packet are gamesense's signature -- see
-- the gs case above.)
M.ForgetAllCheats()
local labelled = 0
local seq = {}
for _ = 1, 20000 do
    local e = rnd(1, 10)
    seq[e] = (seq[e] or rnd(0, 1e6)) + rnd(1, 900)
    send(e, function()
        noise()
        P.xuid_low, P.xuid_high = 40000000 + e * 7919, 17825793
        P.sequence_bytes = seq[e]
        P.section_number = rnd(0, 2^31)
    end)
end
for _ in pairs(M.CHEAT_OF) do labelled = labelled + 1 end
local got = {}; for e, c in pairs(M.CHEAT_OF) do got[#got + 1] = e .. "=" .. c end
check("20000 random packets over 10 players", labelled == 0, labelled .. " labelled: " .. table.concat(got, " "))

print("3. Short runs label nobody")
for id, gen in pairs(SIG) do
    M.ForgetAllCheats()
    for _ = 1, 10 do send(ent, gen) end
    check(id .. " x10", M.CHEAT_OF[ent] == nil, "got " .. tostring(M.CHEAT_OF[ent]))
end

print("4. Forgetting a slot")
M.ForgetAllCheats()
for _ = 1, 60 do send(3, SIG.pd) end
M.ForgetCheat(3)
check("ForgetCheat clears the label", M.CHEAT_OF[3] == nil)

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
