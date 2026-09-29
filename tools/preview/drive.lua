-- Step 2 of the panel preview (see render.py for the full usage).
-- Runs the real INFO PANEL block from riftveil.lua against a recording
-- renderer and writes the last frame's draw calls for each scenario.
local DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local SRC = DIR .. "../../riftveil.lua"
local OUT = DIR .. "out/"
local M = dofile(OUT .. "metrics.lua")

local src = assert(io.open(SRC)):read("a")
local a = assert(src:find("local DrawOverlay = (function()", 1, true))
local b = assert(src:find("end)() -- panel scope", a, true))
local block = src:sub(a, b + #"end)() -- panel scope" - 1)

local CALLS = {}
local function rec(...) CALLS[#CALLS + 1] = table.concat({...}, "\t") end

local function measure(flags, text)
    local t = tostring(text or ""):gsub("\a%x%x%x%x%x%x%x%x", "")
    local tbl = (flags and flags:find("-", 1, true)) and M.small or M.norm
    local w = 0
    for ch in t:gmatch("[\1-\127\194-\244][\128-\191]*") do w = w + (tbl[ch] or 6) end
    return w, (tbl == M.small) and M.small_h or M.norm_h
end

local S = {threat = 1, menu = false, names = {}}
local env = setmetatable({
    renderer = {
        rectangle = function(x, y, w, h, r, g, bb, al) rec("R", x, y, w, h, r, g, bb, al) end,
        gradient  = function(x, y, w, h, r1, g1, b1, a1, r2, g2, b2, a2, hz)
            rec("G", x, y, w, h, r1, g1, b1, a1, r2, g2, b2, a2, tostring(hz)) end,
        text      = function(x, y, r, g, bb, al, flags, _, text) rec("T", x, y, r, g, bb, al, flags, text) end,
        line      = function(x1, y1, x2, y2, r, g, bb, al) rec("L", x1, y1, x2, y2, r, g, bb, al) end,
        measure_text = measure,
        world_to_screen = function() return nil end,
    },
    ui = {
        new_slider  = function(_, _, _, _, _, def) return {v = def} end,
        set_visible = function() end,
        get = function(el) return el.v end,
        set = function(el, v) el.v = v end,
        is_menu_open = function() return S.menu end,
        mouse_position = function() return 0, 0 end,
    },
    client = {
        screen_size = function() return 10000, 10000 end,
        current_threat = function() return S.threat end,
        key_state = function() return false end,
    },
    entity = {
        is_alive = function() return true end,
        get_player_name = function(p) return S.names[p] end,
        get_origin = function() return 0, 0, 0 end,
        get_prop = function() return 0 end,
    },
    globals = {frametime = function() return 0.016 end},
}, {__index = _G})

local prelude = [[
local function Clamp(v, a, b) return math.min(math.max(v, a), b) end
local function isnum(v) return type(v) == "number" and v == v end
local METH = {HIT_MEM="hit_mem", SIX_LEX="6lex", PERIOD="period", SUPPRESS="suppress",
    DEF_TICK="def_tick", LAGCOMP="lagcomp", PHASE="phase", RING="ring", RING_SPK="ring_spike",
    YAW_CACHE="yaw_cache", SYM_FLIP="sym_flip", META_HOLD="meta_hold", TRACK="track"}
local ENG = {Label = function(arm) return string.upper((arm:gsub("_", " "):gsub(":as", ""):gsub(":", " "))) end}
local AA_SHORT = {two="2way", three="3way", five="5way", skitter="skitter", hold="hold", static="static"}
local CFG = {CONF_ESP = 0.5, CFG_THRESH = 0.6}
local REC, EIDX_S64, LIVE_ENEMIES = P.REC, P.EIDX, P.LIVE
local STATE_VER, LAST_SPIKE = 0, false
local ACCENT = P.ACCENT
local function ReadAccent() return false end
local function TitleText() return "" end
local ui_title, ui_on = {v = ""}, {v = true}
local IND = {panel = true, esp = true, shift = true}
local function SetState(ver, spike) STATE_VER, LAST_SPIKE = ver, spike end
]]
local P = {REC = {}, EIDX = {}, LIVE = {}, ACCENT = {150, 200, 60}}
env.P = P
local chunk = assert(load(prelude .. block .. "\nreturn DrawOverlay, SetState", "panel", "t", env))
local DrawOverlay, SetState = chunk()

local function base_rec(t)
    local r = {conf = 0.7, aa_type = "two", last_meth = nil, last_val = 0, vuln_ttl = 0,
        vuln_type = nil, resolved = false, side = 0, preferred_bt = 0, config_type = nil,
        config_conf = 0, def_tickbase = false, meta_aggressive = false,
        total_hits = 0, total_misses = 0}
    for k, v in pairs(t) do r[k] = v end
    return r
end

local SCEN = {
    {file = "a_resolved.txt", menu = false, spike = false, names = {"zia anger", "goralan"},
     recs = {
        base_rec{conf = 0.72, side = -1, resolved = true, last_meth = "hit_mem", last_val = -29,
                 preferred_bt = 2, def_tickbase = true, total_hits = 24, total_misses = 11,
                 eng_by = true, eng_arm = "hitmem:as"},
        base_rec{conf = 0.41, aa_type = "three", total_hits = 7, total_misses = 5}}},
    {file = "b_vuln.txt", menu = false, spike = false,
     names = {"\208\162\208\184\208\188\209\131\209\128 \208\159\209\136\208\181\208\189\208\184\209\135\208\189\209\139\208\185 the second", "7vip"},
     recs = {
        base_rec{conf = 0.55, side = 1, vuln_ttl = 9, vuln_type = "lby", last_val = -24,
                 last_meth = "vuln_lby", aa_type = "skitter", total_hits = 31, total_misses = 12},
        base_rec{conf = 0.63, aa_type = "two", total_hits = 4, total_misses = 2}}},
    {file = "c_building.txt", menu = true, spike = true, names = {"goralan"},
     recs = {base_rec{conf = 0.18, side = 0, aa_type = "five", config_type = "luasense_beta",
                      config_conf = 0.8, total_hits = 3, total_misses = 2}}},
    {file = "d_idle.txt", menu = false, spike = false, names = {}, recs = {}},
}

for _, sc in ipairs(SCEN) do
    for k in pairs(P.REC) do P.REC[k] = nil end
    for k in pairs(P.EIDX) do P.EIDX[k] = nil end
    for k in pairs(P.LIVE) do P.LIVE[k] = nil end
    S.names = {}
    for i, r in ipairs(sc.recs) do
        P.REC["s" .. i] = r; P.EIDX[i] = "s" .. i; P.LIVE[#P.LIVE + 1] = i
        S.names[i] = sc.names[i]
    end
    S.threat = (#sc.recs > 0) and 1 or nil
    S.menu = sc.menu
    SetState(math.random(1, 1e6), sc.spike)
    for _ = 1, 90 do CALLS = {}; DrawOverlay() end
    local f = assert(io.open(OUT .. sc.file, "w"))
    f:write(table.concat(CALLS, "\n"), "\n")
    f:close()
end
print("scenarios written")
