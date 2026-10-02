-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL SANDBOX CHECK
--  Loads riftveil.lua inside a stubbed gamesense environment and drives
--  it through a multi-tick scenario, then reports three things a plain
--  `loadfile()` syntax check can't:
--
--    1. Accidental global WRITES -- a missing `local` (every _ENV write is
--       trapped via __newindex).
--    2. Undeclared global READS -- almost always a local referenced after
--       it went out of scope, which Lua silently evaluates to nil.
--    3. Runtime crashes that riftveil's own pcall wrappers would otherwise
--       swallow into the debug log ([ERR] lines are captured and fail the
--       run).
--
--  Plus a coverage report: which top-level functions never executed.
--  A check only proves anything about code it actually runs -- the first
--  version of this harness returned false from every ui.get(), so Update()
--  bailed at `if not ui.get(ui_on)` and ProcessPlayer (the entire
--  resolver) executed zero lines while the tool still printed PASS. The
--  coverage report exists so that can't happen silently again.
--
--  Usage:  lua5.3 tools/sandbox_check.lua
--  Exit 0 = clean. Exit 1 = load error, leak, bad read, captured [ERR],
--  or a function listed in MUST_RUN that never executed.
-- ══════════════════════════════════════════════════════════════════

local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local TARGET     = os.getenv("RV_TARGET") or (SCRIPT_DIR .. "../riftveil.lua")
-- Differential testing (see tools/engine_sim.lua's header): RV_PLIST_OUT
-- records every plist.set call to a file, RV_NO_ENGINE starts Detection
-- without "Adaptive engine".
local PLIST_OUT = os.getenv("RV_PLIST_OUT")
-- Fuzz + soak: RV_FUZZ=<seed> appends a randomized phase of RV_TICKS ticks
-- (default 20000): players joining and leaving (bots included), NaN/inf/
-- nil in props and animstate, simtime jumping backwards, shots resolved
-- late, twice, or never, garbage hitgroups/reasons/backtrack values,
-- random menu changes, console commands and round/match events. Every
-- plist write is checked (value finite and within +-60, flags boolean)
-- and memory must stay flat across the run.
local FUZZ_SEED = tonumber(os.getenv("RV_FUZZ") or "")
local PLIST_BAD, PLIST_BAD_N = {}, 0
local NO_ENGINE = os.getenv("RV_NO_ENGINE") ~= nil
local PLIST_LOG = {}
local PLIST_STATE = {}
-- [field .. "\t" .. value] = true: plist.set raises for that value (unit checks)
local PLIST_THROW = {}
-- unit failures found during the scenario, before UNIT_FAIL exists
local EARLY_FAIL = {}
-- Values the aim policy may write to gamesense's player-list combo fields
local AIM_FIELD_VALUES = {
    ["Override prefer body aim"] = {["-"] = true, ["On"] = true, ["Off"] = true, ["Force"] = true},
    ["Override safe point"]      = {["-"] = true, ["On"] = true},
}

-- Functions the scenario is designed to reach. If any of these show zero
-- executed lines, the harness itself is broken and the run fails.
-- v8.0 is the v6.2 decision core (see CHANGELOG); RV_MUST_RUN_V7=1 checks
-- the v7.x function set when running an old version through RV_TARGET.
local MUST_RUN = os.getenv("RV_MUST_RUN_V7") and {
    "ProcessPlayer", "DetectVuln", "DetectAA", "CanSeeHead", "CfgAngle",
    "LiveCap", "DynamicMaxYaw", "Extract6Lex", "Update", "SyncFlags",
    "BuildOverlay", "DrawPanel", "FitText", "UpdateDrag", "DrawShiftMarkers",
    "on_aim_fire", "on_aim_hit", "on_aim_miss", "FlushDB", "UpdateEspState",
    "EngineStep", "ENG.Decide", "ENG.Credit", "ENG.Post", "EngSnap",
    "TorsoCluster", "YawSide", "ExtrapolateOrigin", "LCTicks", "clear_log", "SetPanelPos",
    "TrackSide", "ChainPick", "ApplyDecision",
} or {
    "ProcessPlayer", "DetectVuln", "DetectAA", "CanSeeHead", "CfgAngle",
    "LiveCap", "Extract6Lex", "Update", "SyncFlags", "UpdateEspState",
    "BuildOverlay", "DrawPanel", "FitText", "UpdateDrag", "DrawShiftMarkers", "SetPanelPos",
    "on_aim_fire", "on_aim_hit", "on_aim_miss", "FlushDB",
    "TorsoCluster", "ExtrapolateOrigin", "clear_log",
    "Tick", "Decide", "Write", "Traced", "LocalWeaponClass", "DtReady", "TrackState", "EnemyMaxSpeed",
}

-- ── Mutable world state the mocks read from ──────────────────────────
local TI = 1 / 64
local W = {
    tick = 100, real = 0, srv_hits = 0, threat = 101, menu_open = false,
    weapon = 9,   -- AWP in hand: the weapon aim policy has work to do
    players = {
        [101] = {sim = 0, vx = 0, vy = 0, pose01 = 0.5, eye = 45, duck = 0,
                 torso = 70, gfy = 60},
        [102] = {sim = 0, vx = 250, vy = 0, pose01 = 0.5, eye = -30, duck = 0,
                 torso = -10, gfy = -15,
                 -- fully open: the AWP's body shot kills (aim policy "body")
                 tdmg = {[0] = 448, [2] = 112, [3] = 112, [5] = 112}},
    },
}
local CUR = 101  -- entity whose animstate the FFI proxy currently reports

-- Animstate / animlayer fields returned as real numbers. Anything else
-- indexed on the FFI proxy returns the proxy itself so pointer chains like
-- `cel[0][3]` and `ffi.cast(...)(nc, 0)` never crash the stub.
-- Real FFI float fields are always numbers (possibly NaN/inf, never nil),
-- so a missing value reads as 0 here, and a departed player as all zeros.
local ZERO = {duck = 0, eye = 0, torso = 0, gfy = 0, vx = 0, vy = 0}
local function field(k)
    local p = W.players[CUR] or ZERO
    if k == "duck_amount"      then return p.duck or 0 end
    if k == "eye_angles_y"     then return p.eye or 0 end
    if k == "torso_yaw"        then return p.torso or 0 end
    if k == "goal_feet_yaw"    then return p.gfy or 0 end
    if k == "on_ground"        then return true end
    if k == "min_yaw"          then return -58 end
    if k == "max_yaw"          then return 58 end
    if k == "feet_spd_fwd"     then
        -- NaN passes through untouched: math.min(1, NaN) differs between
        -- Lua builds, and a real FFI field would just hold the NaN.
        local v = math.sqrt((p.vx or 0)^2 + (p.vy or 0)^2) / 250
        if v ~= v then return v end
        return v > 1 and 1 or v
    end
    if k == "feet_spd_unk"     then return 1 end
    if k == "stop_to_full_run" then return 0.5 end
    if k == "playback_rate"    then return 0.9123 end
    if k == "weight"           then return (W.tick % 2 == 0) and 1 or 0 end
    return nil
end

local proxy
proxy = setmetatable({}, {
    __index = function(_, k)
        if type(k) == "string" then
            local v = field(k)
            if v ~= nil then return v end
        end
        return proxy
    end,
    __call = function() return proxy end,
    __add  = function() return proxy end,
    __sub  = function() return proxy end,
    __unm  = function() return proxy end,
    __lt   = function() return false end,
    __le   = function() return false end,
    __tostring = function() return "0" end,
})

local CALLBACKS, ESP_FLAGS, UI_CALLBACKS = {}, {}, {}
local LOG_CAPTURE, LOG_SCANNED, ERR_LINES = {}, {}, {}
-- print / client.color_log: every call is checked; the text is kept only
-- while a test sets CONSOLE_ON, so the soak stays flat
local CONSOLE, CONSOLE_ON, CONSOLE_BAD = {}, false, {}
local TRACE_SKIP = {}   -- client.trace_line skip entities while CONSOLE_ON
local SCREEN, SCREEN_RGB = {}, {}   -- renderer.text strings / "r,g,b" while CONSOLE_ON

-- UI elements carry their kind so ui.get returns the right shape.
local UI_ELEMS = {}
local function ui_el(kind, a, b, c, d)
    local el = {kind = kind, a = a, b = b, c = c, d = d}
    UI_ELEMS[#UI_ELEMS + 1] = el
    return el
end

local mock = {
    ffi = setmetatable({}, {__index = function(_, k)
        if k == "cdef" then return function() end end
        if k == "typeof" or k == "cast" then return function() return proxy end end
        if k == "NULL" then return nil end
        return function() return nil end
    end}),
    client = setmetatable({}, {__index = function(_, k)
        if k == "create_interface"   then return function() return {} end end
        if k == "system_time"        then return function() return 12, 0, 0, 0 end end
        if k == "latency"            then return function() return 0.03 end end
        if k == "screen_size"        then return function() return 1920, 1080 end end
        if k == "current_threat"     then return function() return W.threat end end
        if k == "key_state"          then return function(key) return key == 0x01 and W.m1 == true end end
        if k == "trace_line"         then return function(skip)
            if CONSOLE_ON then TRACE_SKIP[#TRACE_SKIP + 1] = skip end
            return 1.0, -1
        end end
        if k == "eye_position"       then return function()
            if W.eye_bad then return W.eye_bad, 0, 64 end
            return 0, 0, 64
        end end
        -- Traced damage per hitbox from W.players[ent].tdmg (default: head
        -- 180, body 55 -- an armored enemy behind nothing, scout-like).
        if k == "trace_bullet"       then return function(_, _, _, _, tx)
            local target, hb = math.floor(tx / 1000), math.floor(tx % 1000)
            local p = W.players[target]
            if not p then return nil, 0 end
            if p.trace_other then return p.trace_other, 90 end   -- the line hits someone else
            local d = p.tdmg and p.tdmg[hb]
            if d == nil then d = (hb == 0) and 180 or 55 end
            return target, d
        end end
        if k == "register_esp_flag"  then return function(_, _, _, _, cb) ESP_FLAGS[#ESP_FLAGS + 1] = cb end end
        if k == "set_event_callback" then return function(name, cb) CALLBACKS[name] = cb end end
        if k == "log"                then return function() end end
        -- the shot log prints with print(), as the original aimbot log
        -- does (console + top-left); color_log output stays in the console
        if k == "color_log"          then return function()
            if #CONSOLE_BAD < 4 then CONSOLE_BAD[#CONSOLE_BAD + 1] = "client.color_log (the shot log must use print)" end
        end end
        if k == "update_player_list" then return function() end end
        if k == "userid_to_entindex" then return function(u) return u end end
        return function() return nil end
    end}),
    entity = setmetatable({}, {__index = function(_, k)
        if k == "get_players"      then return function()
            if W.live then
                local out = {}
                for i, p in ipairs(W.live) do out[i] = p end
                return out
            end
            return {101, 102}
        end end
        if k == "is_enemy"         then return function() return true end end
        if k == "is_alive"         then return function(p) return not (W.dead and W.dead[p]) end end
        if k == "get_local_player" then return function() return 1 end end
        if k == "get_steam64"      then return function(p)
            if W.s64 then return W.s64[p] end
            -- gamesense returns the 32-bit account id, not a 64-bit
            -- SteamID (real logs: s64=1888056751)
            return 1888056000 + p
        end end
        -- 102 gets a long Cyrillic name so the panel's UTF-8 width fit runs.
        if k == "get_player_name"  then return function(p)
            if W.names then return W.names[p] end
            if p == 102 then return "Тимур Пшеничный the second" end
            return "bot" .. tostring(p)
        end end
        if k == "get_origin"       then return function(p)
            local s = W.players[p]
            -- moves with the player's velocity (x only), plus any teleport
            return s and (W.tick * (s.vx or 0) / 64 + (s.jump or 0)) or 0, 0, 0
        end end
        -- x encodes (entity, hitbox) so the trace_bullet mock knows what it hit
        if k == "hitbox_position"  then return function(ent, hb) return (ent or 0) * 1000 + (tonumber(hb) or 0), 0, 64 end end
        if k == "get_player_weapon" then return function() return W.weapon and 900 or nil end end
        if k == "get_prop" then
            return function(ent, prop, idx)
                local p = W.players[ent]
                if prop == "m_flSimulationTime" then return p and p.sim or 0 end
                if prop == "m_vecVelocity"      then return p and p.vx or 0, p and p.vy or 0, 0 end
                if prop == "m_fFlags"           then
                    if p and p.flags_nil then return nil end
                    return p and p.flags or 1
                end
                if prop == "m_bIsScoped"        then return p and p.scoped or 0 end
                if prop == "m_angEyeAngles"     then return p and p.pitch or 89, p and p.eye or 0, 0 end
                if prop == "m_flPoseParameter"  then CUR = ent; return p and p.pose01 or 0.5 end
                if prop == "m_totalHitsOnServer" then return W.srv_hits end
                if prop == "m_vecMins"          then return -16, -16, 0 end
                if prop == "m_vecMaxs"          then return 16, 16, 72 end
                if prop == "m_vecViewOffset"    then return 0, 0, 64 end
                if prop == "m_nTickBase"        then return W.tick + (W.tb_off or 0) end
                if prop == "m_iHealth"          then return p and p.hp or 100 end
                if prop == "m_ArmorValue"       then return p and p.armor or 100 end
                if prop == "m_iItemDefinitionIndex" then return ent == 900 and W.weapon or 0 end
                return 0
            end
        end
        return function() return nil end
    end}),
    ui = setmetatable({}, {__index = function(_, k)
        -- Old versions (RV_TARGET) had [EXP] switches; the real logs show
        -- jitter prediction and adaptive learning never fired in game, so
        -- they start off, as the user ran them.
        if k == "new_checkbox"     then return function(_, _, name)
            local off = type(name) == "string" and (name:find("Jitter Prediction", 1, true)
                or name:find("Adaptive Learning", 1, true))
            local el = ui_el("checkbox", not off)
            el.name = name
            return el
        end end
        -- Multiselects start with every item selected, so each module runs.
        if k == "new_multiselect"  then return function(_, _, _, items)
            local sel = {}
            local el
            for _, v in ipairs(items) do
                if not (NO_ENGINE and v == "Adaptive engine") then sel[#sel + 1] = v end
            end
            el = ui_el("multi", sel)
            el.items = items
            return el
        end end
        if k == "reference"        then return function() return ui_el("color", 150, 200, 60, 255) end end
        if k == "new_slider"       then return function(_, _, _, _, _, def) return ui_el("slider", def or 0) end end
        if k == "new_color_picker" then return function(_, _, _, r, g, b, a) return ui_el("color", r, g, b, a) end end
        if k == "new_label" or k == "new_button" then return function() return ui_el("static") end end
        if k == "get" then
            return function(el)
                if type(el) ~= "table" then return nil end
                if el.kind == "color" then return el.a, el.b, el.c, el.d end
                return el.a
            end
        end
        if k == "set" then return function(el, v) if type(el) == "table" then el.a = v end end end
        if k == "set_callback" then return function(el, cb) UI_CALLBACKS[#UI_CALLBACKS + 1] = cb end end
        if k == "is_menu_open"   then return function() return W.menu_open end end
        if k == "mouse_position" then return function() return W.mx or 0, W.my or 0 end end
        return function() end
    end}),
    cvar = setmetatable({}, {__index = function()
        return setmetatable({}, {__index = function(_, k)
            if k == "get_float" then return function() return 0.031 end end
            if k == "get_int"   then return function() return 1 end end
            return function() end
        end})
    end}),
    database = setmetatable({}, {__index = function(_, k)
        if k == "read" then return function() return {} end end
        return function() end
    end}),
    globals = setmetatable({}, {__index = function(_, k)
        if k == "tickinterval" then return function() return TI end end
        if k == "curtime"      then return function() return W.tick * TI end end
        if k == "realtime"     then return function() return W.real end end
        if k == "tickcount"    then return function() return W.tick end end
        if k == "frametime"    then return function() return 0.016 end end
        return function() return 0 end
    end}),
    bit = setmetatable({}, {__index = function(_, k)
        if k == "band" then return function(a, b)
            -- general bitwise AND on non-negative integers (flags, masks)
            local r, bitv = 0, 1
            a, b = math.floor(a), math.floor(b)
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
                a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
            end
            return r
        end end
        return function() return 0 end
    end}),
    plist    = setmetatable({}, {__index = function(_, k)
        if k == "set" then
            return function(ent, field, value)
                if PLIST_THROW[field .. "\t" .. tostring(value)] then error("bad value " .. tostring(value)) end
                if PLIST_OUT then
                    PLIST_LOG[#PLIST_LOG + 1] = string.format("%d\t%s\t%s\t%s", W.tick, tostring(ent), field, tostring(value))
                end
                local bad
                -- RV_AIM_REJECT=On: the game "ignores" that aim value, to test the
                -- read-back fallback (it stores "-" instead)
                local stored = value
                if AIM_FIELD_VALUES[field] and value == os.getenv("RV_AIM_REJECT") then stored = "-" end
                PLIST_STATE[tostring(ent) .. "\t" .. field] = stored
                if field == "Force body yaw value" then
                    if type(value) ~= "number" or value ~= value or math.abs(value) > 60 then bad = true end
                elseif AIM_FIELD_VALUES[field] then
                    if not AIM_FIELD_VALUES[field][value] then bad = true end
                elseif type(value) ~= "boolean" then
                    bad = true
                end
                if bad then
                    PLIST_BAD_N = PLIST_BAD_N + 1
                    if #PLIST_BAD < 8 then
                        PLIST_BAD[#PLIST_BAD + 1] = string.format("tick %d ent %s %s = %s", W.tick, tostring(ent), field, tostring(value))
                    end
                end
            end
        end
        -- get returns what set stored, "-" for an aim field never written
        if k == "get" then
            return function(ent, field)
                local v = PLIST_STATE[tostring(ent) .. "\t" .. field]
                if v == nil and AIM_FIELD_VALUES[field] then return "-" end
                return v
            end
        end
        return function() end
    end}),
    renderer = setmetatable({}, {__index = function(_, k)
        if k == "measure_text"   then return function(_, text) return #tostring(text or "") * 6, 12 end end
        if k == "world_to_screen" then return function() return 500, 500 end end
        if k == "text" then return function(...)
            if CONSOLE_ON then
                local _, _, r, g, b = ...
                SCREEN[#SCREEN + 1] = tostring(select(9, ...))
                SCREEN_RGB[#SCREEN] = string.format("%s,%s,%s", tostring(r), tostring(g), tostring(b))
            end
        end end
        return function() end
    end}),
    writefile = function(name, content)
        -- The logger rewrites the whole file each flush; scan only what was
        -- appended since the last write (or everything after a roll/clear).
        local from = LOG_SCANNED[name] or 0
        if #content < from then from = 0 end
        for line in content:sub(from + 1):gmatch("[^\n]+") do
            if line:find("%]%[ERR%]") then ERR_LINES[#ERR_LINES + 1] = line end
            if (line:find("][miss]", 1, true) or line:find("][hit]", 1, true)) and not line:find(" discarded ", 1, true) then
                SHOT_SEEN = (SHOT_SEEN or 0) + 1
                if line:find(" eo=%-?[%d]* lbyu=[%d%.%-]+ aa=") then SHOT_EO = (SHOT_EO or 0) + 1 end
            end
            if line:find("][corr]", 1, true) then
                CORR_SEEN = (CORR_SEEN or 0) + 1
                if line:find(" pz=%-?%d* pf=%-?%d*$") then CORR_PROBED = (CORR_PROBED or 0) + 1 end
            end
        end
        LOG_SCANNED[name] = #content
        LOG_CAPTURE[1] = content
    end,
    -- the debug log as a crash mid-write leaves it: zero bytes, then text
    readfile  = function(name)
        if name == "riftveil_debug.txt" then return string.rep("\0", 64) .. "[00:00:00.000][INF][init] old\n" end
        return ""
    end,
    -- the shot log's output: one string per line, kept while CONSOLE_ON
    print = function(...)
        local n, msg = select("#", ...), (...)
        if n ~= 1 or type(msg) ~= "string" then
            if #CONSOLE_BAD < 4 then CONSOLE_BAD[#CONSOLE_BAD + 1] = "print() with " .. n .. " args, first " .. type(msg) end
        elseif CONSOLE_ON then
            CONSOLE[#CONSOLE + 1] = msg
        end
    end,
    string = string, table = table, math = math, pairs = pairs, ipairs = ipairs,
    tostring = tostring, tonumber = tonumber, type = type, select = select,
    pcall = pcall, setmetatable = setmetatable, error = error, next = next,
    os = os, unpack = table.unpack or unpack,
}
-- A stand-in for the cheat revealer script's module (RV_NO_REVEALER=1
-- leaves it out). Entity 1 has no data, entity 2's get_cheat throws like
-- the real one does on a missing table, the rest report a cheat, "wh"
-- (no signature) included.
local REVEALER = {
    has_data  = function(ent) return ent ~= 1 end,
    get_cheat = function(ent)
        if ent == 2 then error("attempt to index a nil value") end
        local ids = {"nl", "gs", "wh", "ot"}
        return {cheat_id = ids[ent % 4 + 1], cheat_long = "?"}
    end,
}
mock.package = {loaded = {}, preload = {}}
if not os.getenv("RV_NO_REVEALER") then
    mock.package.preload["gamesense/cheat_revealer"] = function() return REVEALER end
end
mock.require = function(name)
    local f = mock.package.preload[name]
    if f then
        local m = f(); mock.package.loaded[name] = m; return m
    end
    return mock.ffi
end

-- RV_COUNT_API: count every game API call during the benchmark (per tick
-- and per paint frame), to compare versions by how much they ask the game.
local API_COUNT = os.getenv("RV_COUNT_API") and {} or nil
local API_PHASE = "load"
if API_COUNT then
    for _, ns in ipairs({"client", "entity", "ui", "renderer", "globals", "plist"}) do
        local mt = getmetatable(mock[ns])
        local idx = mt.__index
        mt.__index = function(tbl, k)
            local key = API_PHASE .. "\t" .. ns .. "." .. tostring(k)
            API_COUNT[key] = (API_COUNT[key] or 0) + 1
            return idx(tbl, k)
        end
    end
end

local declared = {}
for k in pairs(mock) do declared[k] = true end

local leaks, bad_reads, bad_read_seen = {}, {}, {}
local ENV = setmetatable({}, {
    __index = function(_, k)
        local v = rawget(mock, k)
        if v == nil and not declared[k] and not bad_read_seen[k] then
            bad_read_seen[k] = true
            bad_reads[#bad_reads + 1] = k
        end
        return v
    end,
    __newindex = function(t, k, v)
        if not declared[k] then leaks[#leaks + 1] = k end
        rawset(t, k, v)
    end,
})

-- ── Coverage: record every riftveil.lua line that executes ───────────
local hits = {}
local target_src = "@" .. TARGET
local function hook(_, line)
    if debug.getinfo(2, "S").source == target_src then hits[line] = true end
end

local chunk, load_err = loadfile(TARGET, "t", ENV)
if not chunk then
    print("LOAD ERROR: " .. tostring(load_err))
    os.exit(1)
end

debug.sethook(hook, "l")

local ok, run_err = pcall(chunk)
if not ok then print("RUNTIME ERROR during top-level load: " .. tostring(run_err)) end



-- RV_PARITY=1: switch off the post-v6.2 decision features (FEATURE flags
-- that change a correction) before the first tick, for the v6.2 parity run.
if os.getenv("RV_PARITY") then
    local seen = {}
    local function find(f, depth)
        if seen[f] or depth > 4 then return nil end
        seen[f] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(f, i)
            if not n then break end
            if n == "FEATURE" and type(v) == "table" then return v end
            if type(v) == "function" then
                local r = find(v, depth + 1)
                if r then return r end
            end
        end
    end
    local F
    for _, cb in pairs(CALLBACKS) do F = F or find(cb, 0) end
    if F then F.STATE_PHYSICS = false; F.SKIP_DEF_FRAMES = false; F.SHIFT_GAP = false; F.DEF_RESET = false; F.DCK_GAP = false; F.CFG_CADENCE = false; F.STALE_WINDOW = false; F.UNK_DELTA = false; F.DESYNC_FORMULA = false; F.NO_CHOKE_STATIC = false; F.WINDOW_GATE = false; F.META_STREAK = false end
end

local cb_errors = {}
local function fire(name, ...)
    local cb = CALLBACKS[name]
    if not cb then return end
    local cb_ok, cb_err = pcall(cb, ...)
    if not cb_ok then cb_errors[#cb_errors + 1] = name .. ": " .. tostring(cb_err) end
end

-- ── Scenario ─────────────────────────────────────────────────────────
-- 101: standing, jittering pose (+/-36 deg) with a periodic LBY collapse
--      to 0, and a 2-tick choke every 6 ticks followed by a clean
--      unchoke -> exercises LBY/UNK vuln windows and CanSeeHead.
-- 102: running, then stopping (STP), then peeking again (PKA), with a
--      duck crossing mid-way (DCK).
local POSE_SEQ = {0.8, 0.2, 0.8, 0.2, 0.8, 0.5, 0.2, 0.8, 0.2, 0.8}
for step = 1, 80 do
    W.tick = W.tick + 1
    W.real = W.real + TI

    local a = W.players[101]
    local lag = (step % 6 == 3) and 2 or 0
    a.sim   = (W.tick - lag) * TI
    a.pose01 = POSE_SEQ[(step % #POSE_SEQ) + 1]
    a.torso = (step % 2 == 0) and 70 or 20

    local b = W.players[102]
    b.sim = W.tick * TI
    if step <= 20 then b.vx = 250
    elseif step <= 40 then b.vx = 0
    else b.vx = 250 end
    b.duck = (step >= 30 and step <= 35) and 1 or 0
    b.pose01 = POSE_SEQ[((step + 3) % #POSE_SEQ) + 1]

    fire("predict_command")
    fire("net_update_end")
    fire("paint")
    for _, cb in ipairs(ESP_FLAGS) do pcall(cb, 101); pcall(cb, 102) end

    -- Shots at varying points so the fire snapshot sees different
    -- vuln/method states.
    if step % 10 == 5 then
        local id = step
        fire("aim_fire", {id = id, target = 101, backtrack = 0, hit_chance = 80})
        fire("aim_hit",  {id = id, target = 101, hitgroup = 1, damage = 100})
    elseif step % 10 == 7 then
        local id = step
        local reasons = {"?", "prediction error", "spread", "death"}
        local reason  = reasons[math.floor(step / 10) % #reasons + 1]
        fire("aim_fire", {id = id, target = 101, backtrack = 2, hit_chance = 70,
                          extrapolated = math.floor(step / 10) % 3 == 0})
        fire("aim_miss", {id = id, target = 101, reason = reason})
    end
end
-- Phase 2: quiet play -- no chokes, no LBY collapse, no stop/peek/duck
-- events -- so no vuln window is open and the hit_mem/suppress chain is
-- what's in control when shots land. Mixed head hits, body hits and
-- resolver misses so every feedback path runs. Midway the menu opens (drag
-- outline) and the threat drops for a stretch (panel eases shut).
local QUIET = {0.72, 0.30, 0.72, 0.30}
for step = 81, 240 do
    W.tick = W.tick + 1
    W.real = W.real + TI
    local a = W.players[101]
    a.sim = W.tick * TI
    a.pose01 = QUIET[(step % #QUIET) + 1]
    a.torso = 30
    local b = W.players[102]
    b.sim = W.tick * TI
    b.vx, b.duck = 250, 0
    W.menu_open = step >= 150 and step < 170
    W.threat = (step >= 190 and step < 205) and nil or ((step >= 120 and step < 140) and 102 or 101)
    fire("net_update_end")
    fire("paint")
    for _, cb in ipairs(ESP_FLAGS) do pcall(cb, 101); pcall(cb, 102) end
    if step % 3 == 0 then
        local id = 1000 + step
        fire("aim_fire", {id = id, target = 101, backtrack = 0, hit_chance = 75})
        local r = step % 9
        if r == 0 then fire("aim_hit",  {id = id, target = 101, hitgroup = 1, damage = 90})
        elseif r == 3 then fire("aim_hit", {id = id, target = 101, hitgroup = 3, damage = 30})
        else fire("aim_miss", {id = id, target = 101, reason = "?"}) end
    end
end

-- Reads a script-local by name through the upvalues of registered
-- callbacks (and the functions they close over), for soak measurements.
local function probe(name)
    local seen = {}
    local function walk(f, depth)
        if seen[f] or depth > 4 then return nil end
        seen[f] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(f, i)
            if not n then break end
            if n == name then return v, true end
            if type(v) == "function" then
                local r, ok = walk(v, depth + 1)
                if ok then return r, true end
            end
        end
    end
    for _, cb in pairs(CALLBACKS) do
        local v, ok = walk(cb, 0)
        if ok then return v end
    end
end
local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end; return n end

-- A debug log left as zero bytes by a crash: the zeros are dropped at load
-- and the drop is logged; the old text after them is kept (right after
-- load: the scenarios below run rv_clear)
do
    local FL = probe("flush_log")
    if FL then
        FL()
        local c = LOG_CAPTURE[1] or ""
        if c:find("%z") then EARLY_FAIL[#EARLY_FAIL + 1] = "debug log: zero bytes from a damaged file written back" end
        if not c:find("[INF][init] old", 1, true) then EARLY_FAIL[#EARLY_FAIL + 1] = "debug log: the old text after the zeros was lost" end
        if not c:find("64 zero bytes dropped", 1, true) then EARLY_FAIL[#EARLY_FAIL + 1] = "debug log: the dropped zeros weren't logged" end
    end
end

-- ── Fuzz + soak phase (RV_FUZZ) ──────────────────────────────────────
local FUZZ_REPORT
if FUZZ_SEED then
    debug.sethook()   -- line coverage would make a long soak crawl
    -- MINSTD (Park-Miller): exact in both Lua 5.3 integers and LuaJIT
    -- doubles (state * 48271 < 2^53), so a seed builds the same world on
    -- both runtimes and their plist writes can be compared one to one.
    local rng_state = (FUZZ_SEED % 2147483646) + 1
    local function rnd()
        rng_state = (rng_state * 48271) % 2147483647
        return (rng_state - 1) / 2147483646
    end
    local function rint(a, b)
        if not b then a, b = 1, a end
        return a + math.floor(rnd() * (b - a + 1))
    end
    local TICKS = tonumber(os.getenv("RV_TICKS") or "") or 20000
    local NAN, INF = 0 / 0, 1 / 0
    local function nasty(x)
        local r = rnd()
        if r < 0.004 then return NAN elseif r < 0.006 then return INF
        elseif r < 0.008 then return -INF elseif r < 0.012 then return nil end
        return x
    end
    local NAMES = {"zia anger", "goralan", "миша", "Тимур Пшеничный", "7vip", "", "unknown", "x"}
    W.live, W.s64, W.names, W.dead = {}, {}, {}, {}
    local free = {}
    for i = 2, 24 do free[#free + 1] = i end
    local function join()
        if #free == 0 then return end
        local p = table.remove(free, rint(#free))
        W.live[#W.live + 1] = p
        -- 600 steam ids so profiles outnumber DB_MAX and pruning runs; 8% bots
        W.s64[p] = (rnd() < 0.08) and 0 or (1888056000 + rint(600))
        W.names[p] = NAMES[rint(#NAMES)] .. tostring(rint(99))
        W.players[p] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
    end
    local function leave()
        if #W.live == 0 then return end
        local i = rint(#W.live)
        local p = table.remove(W.live, i)
        free[#free + 1] = p
        W.players[p] = nil
    end
    for _ = 1, 3 do join() end

    local next_id, pending = 50000, {}
    local REASONS = {"?", "?", "?", "spread", "prediction error", "death", "", false, "weird"}
    local BT = {0, 0, 0, 1, 2, 5, 0.03, -1, 100}
    local CMDS = {"rv_stats", "rv_db", "rv_save", "rv_reset", "rv_wipe", "rv_clear", "rv_nope", "  RV_STATS  ", ""}
    local mem = {}
    local t0 = os.clock()
    for step = 1, TICKS do
        W.tick = W.tick + ((rnd() < 0.002) and -3 or 1)
        W.real = W.real + TI
        if rnd() < 0.01 then join() end
        if rnd() < 0.008 then leave() end
        for _, p in ipairs(W.live) do
            local s = W.players[p]
            local r = rnd()
            if r < 0.7 then s.sim = W.tick * TI                           -- clean update
            elseif r < 0.95 then                                         -- choke: no update
            else s.sim = (W.tick - rint(0, 20)) * TI end          -- stale/back
            s.sim     = nasty(s.sim)
            s.pose01  = nasty((rnd() < 0.5) and rnd() or (s.pose01 or 0.5))
            s.eye     = nasty((s.eye or 0) + rint(-40, 40))
            s.vx      = nasty(rint(0, 300))
            s.duck    = nasty((rnd() < 0.1) and 1 or 0)
            s.torso   = nasty(rint(-180, 180))
            s.gfy     = nasty(rint(-180, 180))
            W.dead[p] = rnd() < 0.02
            -- aim policy and state tracker inputs
            s.hp      = nasty(rint(-5, 130))
            s.armor   = nasty(rint(0, 100))
            s.scoped  = nasty((rnd() < 0.3) and 1 or 0)
            s.flags   = nasty((rnd() < 0.1) and 0 or 1)
            s.flags_nil = rnd() < 0.01
            s.tdmg    = {[0] = nasty(rint(0, 500)), [2] = nasty(rint(0, 150)),
                         [3] = nasty(rint(0, 150)), [5] = nasty(rint(0, 150))}
            s.trace_other = (rnd() < 0.05) and rint(1, 64) or nil
        end
        local WEAPONS = {9, 40, 11, 38, 64, 1, 4, 61, 42, 500, 0, 70000, nil}
        if rnd() < 0.02 then W.weapon = WEAPONS[rint(#WEAPONS)] end
        W.eye_bad = (rnd() < 0.01) and ((rnd() < 0.5) and NAN or INF) or nil
        local rt = rnd()
        W.threat = (rt < 0.8 and #W.live > 0) and W.live[rint(#W.live)] or (rt < 0.9 and nil or 999)
        if rnd() < 0.01 then W.menu_open = not W.menu_open end

        fire("net_update_end")
        if os.getenv("RV_DUMP_TICK") and W.tick == tonumber(os.getenv("RV_DUMP_TICK")) then
            -- Debug aid: every scalar field of every profile, sorted, so two
            -- runs can be diffed line by line.
            local out = {}
            local function dump(prefix, t, depth)
                local keys = {}
                for k in pairs(t) do keys[#keys + 1] = k end
                table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
                for _, k in ipairs(keys) do
                    local v = t[k]
                    if type(v) == "number" then
                        out[#out + 1] = string.format("%s.%s = %.6g", prefix, tostring(k), v)
                    elseif type(v) == "string" or type(v) == "boolean" then
                        out[#out + 1] = string.format("%s.%s = %s", prefix, tostring(k), tostring(v))
                    elseif type(v) == "table" and depth < 3 then
                        dump(prefix .. "." .. tostring(k), v, depth + 1)
                    end
                end
            end
            dump("REC", probe("REC") or {}, 0)
            local f = assert(io.open(os.getenv("RV_DUMP_OUT"), "w"))
            f:write(table.concat(out, "\n"), "\n"); f:close()
        end
        fire("paint")
        for _, cb in ipairs(ESP_FLAGS) do pcall(cb, W.live[1] or 5); pcall(cb, 999) end

        if rnd() < 0.15 then
            next_id = (rnd() < 0.02) and (next_id - 1) or (next_id + 1)   -- id reuse
            local tgt = (#W.live > 0 and rnd() < 0.95) and W.live[rint(#W.live)] or rint(1, 64)
            fire("aim_fire", {id = next_id, target = tgt, backtrack = nasty(BT[rint(#BT)]),
                              hit_chance = nasty(rint(0, 100)), extrapolated = rnd() < 0.1,
                              teleported = rnd() < 0.05})
            pending[#pending + 1] = {id = next_id, target = tgt, at = step + rint(0, 40)}
        end
        for i = #pending, 1, -1 do
            local sh = pending[i]
            if sh.at <= step then
                table.remove(pending, i)
                local r = rnd()
                local id = (rnd() < 0.03) and 999999 or sh.id                -- unknown id
                if r < 0.35 then
                    fire("aim_hit", {id = id, target = sh.target, hitgroup = nasty(rint(-1, 12)),
                                     damage = nasty(rint(0, 120))})
                elseif r < 0.95 then
                    fire("aim_miss", {id = id, target = sh.target, reason = REASONS[rint(#REASONS)]})
                end                                                                 -- else: never resolved
                if rnd() < 0.03 then                                         -- duplicate event
                    fire("aim_miss", {id = id, target = sh.target, reason = "?"})
                end
            end
        end

        -- events the v8.16+ features listen to: impacts for the shot log
        -- (ours and others', broken coordinates), grenade / fire / knife
        -- damage, and our tickbase jumping both ways (local LC box, our
        -- own shift) -- including NaN
        if rnd() < 0.05 then
            fire("bullet_impact", {userid = (rnd() < 0.7) and 1 or rint(1, 70), x = nasty(rint(-2000, 2000)),
                                   y = nasty(rint(-2000, 2000)), z = nasty(rint(-100, 300))})
        end
        if rnd() < 0.01 then
            local WPN = {"hegrenade", "inferno", "knife", "awp", "", "x"}
            fire("player_hurt", {attacker = (rnd() < 0.6) and 1 or rint(0, 70),
                                 userid = (#W.live > 0 and rnd() < 0.9) and W.live[rint(#W.live)] or rint(0, 70),
                                 weapon = WPN[rint(#WPN)], hitgroup = nasty(rint(-1, 10)),
                                 dmg_health = nasty(rint(0, 150)), health = nasty(rint(-5, 100))})
        end
        -- our shots and others' (the local LC box: a DT shot arms it)
        if rnd() < 0.03 then fire("weapon_fire", {userid = (rnd() < 0.7) and 1 or rint(0, 70), weapon = "weapon_ssg08"}) end
        if rnd() < 0.02 then W.tb_off = (rnd() < 0.95) and rint(-20, 20) or NAN end
        fire("run_command", {}); fire("predict_command", {})

        if rnd() < 0.002 then fire("round_start") end
        if rnd() < 0.0004 then fire(rnd() < 0.5 and "game_end" or "level_init") end
        if rnd() < 0.003 then fire("console_input", CMDS[rint(#CMDS)]) end
        if rnd() < 0.002 then
            local el = UI_ELEMS[rint(#UI_ELEMS)]
            if el.kind == "checkbox" then el.a = not el.a
            elseif el.kind == "multi" then
                local sel = {}
                for _, it in ipairs(el.items) do if rnd() < 0.6 then sel[#sel + 1] = it end end
                el.a = sel
            end
            for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
        end

        if step % math.floor(TICKS / 20) == 0 then
            collectgarbage("collect")
            -- Heap net of the logger's in-memory file text, which grows to
            -- LOG_ROLL_BYTES by design and then rolls over.
            local logb = #(probe("log_disk") or "")
            mem[#mem + 1] = {heap = collectgarbage("count"), net = collectgarbage("count") - logb / 1024,
                             rec = count(probe("REC")), shots = count(probe("SHOTS")),
                             db = count(probe("DB")), log = logb}
        end
    end
    -- Put the menu back the way the rest of the run expects it.
    for _, el in ipairs(UI_ELEMS) do
        if el.kind == "checkbox" then el.a = true
        elseif el.kind == "multi" then el.a = {}; for i, it in ipairs(el.items) do el.a[i] = it end end
    end
    W.tb_off = nil   -- the unit tests below need a readable tickbase
    FUZZ_REPORT = {ticks = TICKS, secs = os.clock() - t0, mem = mem}
    W.live, W.s64, W.names, W.dead = nil, nil, nil, nil
    debug.sethook(hook, "l")
end

-- ── Benchmark (RV_BENCH=<enemies>) ───────────────────────────────────
-- Clean, realistic play (no hostile inputs), debug log off, coverage hook
-- off. Times net_update_end and paint separately; with LuaJIT, also runs
-- jit.profile and prints the hottest functions.
local BENCH
if os.getenv("RV_BENCH") then
    debug.sethook()
    local N = tonumber(os.getenv("RV_BENCH")) or 2
    local TICKS = tonumber(os.getenv("RV_TICKS") or "") or 20000
    for _, el in ipairs(UI_ELEMS) do
        if el.kind == "checkbox" then el.a = true end          -- resolver, tight interp ...
    end
    -- debug log off: it's the last checkbox created in the menu block
    local cbs = {}
    for _, el in ipairs(UI_ELEMS) do if el.kind == "checkbox" then cbs[#cbs + 1] = el end end
    cbs[#cbs].a = false
    if os.getenv("RV_NO_ENGINE") then
        for _, el in ipairs(UI_ELEMS) do
            if el.kind == "multi" and el.items[1] == "Vulnerability" then
                el.a = {"Vulnerability", "Hit memory", "Desync angle"}
            end
        end
    end
    for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
    W.live = {}
    for i = 1, N do
        local p = 200 + i
        W.live[i] = p
        W.players[p] = {sim = W.tick * TI, vx = (i % 2) * 250, vy = 0, pose01 = 0.5,
                        eye = i * 30, duck = 0, torso = 40, gfy = 36}
    end
    local prof_counts = {}
    local ok_prof, profile = pcall(require, "jit.profile")
    if ok_prof and os.getenv("RV_PROFILE") then
        profile.start("f", function(th, samples)
            local where = profile.dumpstack(th, "F", 1)
            prof_counts[where] = (prof_counts[where] or 0) + samples
        end)
    end
    local t_net, t_paint, id = 0, 0, 90000
    for step = 1, TICKS do
        W.tick = W.tick + 1
        W.real = W.real + TI
        for i, p in ipairs(W.live) do
            local c = W.players[p]
            if (step + i) % 4 ~= 0 then c.sim = W.tick * TI end    -- light fakelag
            c.pose01 = ((step + i) % 2 == 0) and 0.78 or 0.24      -- 2-way jitter
            c.eye = (c.eye + 3) % 360 - 180
        end
        W.threat = W.live[1 + step % N]
        local t0 = os.clock()
        API_PHASE = "tick"
        fire("net_update_end")
        local t1 = os.clock()
        API_PHASE = "frame"
        for _ = 1, 4 do fire("paint") end                        -- ~256 fps at 64 tick
        API_PHASE = "other"
        local t2 = os.clock()
        t_net, t_paint = t_net + (t1 - t0), t_paint + (t2 - t1)
        if step % 8 == 0 then
            id = id + 1
            fire("aim_fire", {id = id, target = W.live[1], backtrack = 1, hit_chance = 80})
            if step % 16 == 0 then fire("aim_hit", {id = id, target = W.live[1], hitgroup = 1, damage = 90})
            else fire("aim_miss", {id = id, target = W.live[1], reason = "?"}) end
        end
    end
    if ok_prof and os.getenv("RV_PROFILE") then profile.stop() end
    BENCH = {n = N, ticks = TICKS, net = t_net / TICKS * 1e6, paint = t_paint / (TICKS * 4) * 1e6,
             prof = prof_counts}
    W.live = nil
    for i = 1, N do W.players[200 + i] = nil end
    debug.sethook(hook, "l")
end

-- Phase 3: paths phases 1-2 never reach. 6lex off and a fresh opponent
-- (103, no hit history) so the lagcomp and yaw-cache side sources decide;
-- an unchoke that exposes a large torso offset (UNK window + torso
-- cluster); a 200-unit origin teleport (SHIFT check + extrapolation); a
-- panel drag with the menu open; and rv_clear.
do
    for _, el in ipairs(UI_ELEMS) do
        if el.kind == "multi" and el.items and el.items[1] == "Vulnerability" then
            el.a = {"Vulnerability", "Hit memory", "Adaptive engine", "Cheat profiles", "Weapon aim"}
        end
        -- the same switch in the v6.2 menu (RV_TARGET parity runs)
        -- (and an auto in hand from here: the double-tap path of the aim policy)
        if el.kind == "checkbox" and type(el.name) == "string" and el.name:find("Desync Angle", 1, true) then
            el.a = false
        end
    end
    W.weapon = 11
    for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
    -- A clean match first, so this phase doesn't depend on what the fuzz
    -- phase left behind (a leftover profile sharing 104's id and holding
    -- hit history would route it to hit memory instead of the yaw cache).
    -- Then rv_clear: it drops log lines not yet flushed to disk, which
    -- would hide any [ERR] raised in this phase from the check below.
    fire("game_end")
    fire("console_input", "rv_clear")
    -- Corrupt saved data for 103 and 104: wrong types everywhere, and one
    -- entry that isn't a table at all. The resolver must still run them.
    local DB_T = probe("DB")
    if DB_T then
        DB_T["1888056103"] = {kills = "x", hit_rate = {}, config_type = 5, bt_pref = "a",
                              vuln_pref = 7, eng = "bad", samples = "q", gen = "z", cheat = "zz"}
        DB_T["1888056104"] = "garbage"
        -- right types, wrong shape: fractional counters (a hand edit, an
        -- old version's float) reached "%d" in the db flush line
        DB_T["1888056101"] = {kills = 3.7, bt_pref = 2.5, hit_rate = 0.9, samples = 4.5}
    end
    W.live = {101, 102, 103}
    W.players[103] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 10, duck = 0,
                      torso = 70, gfy = 66}
    for step = 1, 90 do
        W.tick = W.tick + 1
        W.real = W.real + TI
        local c = W.players[103]
        -- choke 3 of every 5 ticks, then a clean unchoke
        local choked = (step % 5) < 3
        c.sim = choked and c.sim or (W.tick * TI)
        c.pose01 = (step % 2 == 0) and 0.78 or 0.24
        c.eye = 10 + (step % 7) * 9            -- turning: fills the yaw cache
        c.torso = (step % 10 < 5) and 70 or 62  -- two nearby positions: a cluster
        c.gfy = c.torso - 4
        c.jump = (step >= 60) and 200 or 0     -- teleport at step 60
        for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
        W.threat = 103
        W.menu_open = step >= 40 and step <= 44
        W.m1 = step >= 41 and step <= 43
        W.mx, W.my = 1310 + (step - 41) * 10, 155
        fire("net_update_end")
        fire("paint")
        if step % 9 == 0 then
            local id = 3000 + step
            fire("aim_fire", {id = id, target = 103, backtrack = 1, hit_chance = 70})
            if step % 18 == 0 then fire("aim_hit", {id = id, target = 103, hitgroup = 1, damage = 100})
            else fire("aim_miss", {id = id, target = 103, reason = "?"}) end
        end
    end
    do  -- a saved cheat id must be a known one
        local REC_T, EI = probe("REC"), probe("EIDX_S64")
        local r = REC_T and EI and EI[103] and REC_T[EI[103]]
        if r and r.cheat == "zz" then EARLY_FAIL[#EARLY_FAIL + 1] = "DB load: unknown saved cheat id \"zz\" taken as the player's cheat" end
    end
    -- 104: brand-new jittering opponent, small torso offset (no UNK
    -- window), whose records arrive late (simtime 4 ticks old on arrival,
    -- 2 beyond our latency). On late records the lagcomp source is skipped
    -- and the yaw cache decides while confidence is still below 0.60.
    W.live = {101, 102, 104}
    W.players[104] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0,
                      torso = 3, gfy = 3}
    for step = 1, 12 do
        W.tick = W.tick + 3
        W.real = W.real + 3 * TI
        local c = W.players[104]
        c.sim = (W.tick - 4) * TI
        c.pose01 = (step % 2 == 0) and 0.8 or 0.2
        c.eye = (step % 2 == 0) and 60 or -60
        for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
        W.threat = 104
        fire("net_update_end")
        fire("paint")
    end
    W.live, W.players[103], W.players[104], W.m1, W.menu_open = nil, nil, nil, false, false
end

-- ── Targeted unit checks on the live script state ────────────────────
-- DB cap: 600 profiles through the real FlushDB must leave exactly 500,
-- keeping the most recently stamped ones.
local UNIT_FAIL, UNIT_OK = {}, nil
for _, f in ipairs(EARLY_FAIL) do UNIT_FAIL[#UNIT_FAIL + 1] = f end
-- ClassifyState against Source movement physics (sv_accelerate 5.5,
-- friction 5.2, stopspeed 80, 64 tick): a peek-and-stop must read as
-- running, not slow walk; a capped slow walk must read as slow walk; a
-- slow crouch-walk must read as crouch-moving.
do
    local CS = probe("ClassifyState")
    local FEAT = probe("FEATURE")
    if not (FEAT and FEAT.STATE_PHYSICS) and not os.getenv("RV_MUST_RUN_V7") then
        -- v6.2's speed-band classifier (RV_PARITY or an old RV_TARGET):
        -- the physics check below tests the v7.5 one.
    elseif not CS then
        UNIT_FAIL[#UNIT_FAIL + 1] = "ClassifyState: not reachable through upvalues"
    else
        local TI_, ACC, FRIC, STOP = 1 / 64, 5.5, 5.2, 80
        local function run(profile, duck)
            local counts, prev, state = {}, nil, "standing"
            for _, v in ipairs(profile) do
                local dv = prev and (v - prev) or nil
                state = CS(101, {duck_amount = duck and 1 or 0}, v, dv, state)
                counts[state] = (counts[state] or 0) + 1
                prev = v
            end
            return counts
        end
        local function peek(wish)
            local p, v = {}, 0
            for _ = 1, 20 do v = math.min(wish, v + ACC * wish * TI_); p[#p + 1] = v end
            for _ = 1, 30 do v = math.max(0, v - math.max(v, STOP) * FRIC * TI_); p[#p + 1] = v end
            return p
        end
        local function capped(cap, n)
            local p, v = {}, 0
            for _ = 1, n do v = math.min(cap, v + ACC * cap * TI_); p[#p + 1] = v end
            return p
        end
        local knife, rifle = run(peek(250)), run(peek(215))
        local slow, crouch = run(capped(82, 40)), run(capped(40, 30), true)
        if (knife.slowmotion or 0) > 1 or (rifle.slowmotion or 0) > 1 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("ClassifyState: peeks read as slow walk on %d/%d ticks",
                knife.slowmotion or 0, rifle.slowmotion or 0)
        end
        if (slow.slowmotion or 0) < 38 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("ClassifyState: slow walk read as slow walk on only %d/40 ticks", slow.slowmotion or 0)
        end
        if (crouch.crouch_moving or 0) < 29 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("ClassifyState: crouch-walk read as crouch-moving on only %d/30 ticks", crouch.crouch_moving or 0)
        end
    end
end

-- ENG.Fade (soft reset): halves totals and per-state votes, nothing else.
do
    local E_ = probe("ENG")
    if E_ then
        local E = E_.New()
        E.all["pose:inv"] = {s = 4, f = 2}
        E.st.standing = {["pose:inv"] = {s = 2, f = 1}}
        E_.Fade(E)
        local a, b = E.all["pose:inv"], E.st.standing["pose:inv"]
        if not (a.s == 2 and a.f == 1 and b.s == 1 and b.f == 0.5) then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("ENG.Fade: got all %g/%g state %g/%g, expected 2/1 and 1/0.5", a.s, a.f, b.s, b.f)
        end
    end
end
do
    local REC_T, FLUSH, DB_T = probe("REC"), probe("FlushDB"), probe("DB")
    local ENG_T = probe("ENG")
    if not probe("DB_MAX") then
        -- no DB cap in this version
    elseif not (REC_T and FLUSH and DB_T) then
        UNIT_FAIL[#UNIT_FAIL + 1] = "DB cap: could not reach REC/FlushDB/DB/ENG through upvalues"
    else
        for k in pairs(DB_T) do DB_T[k] = nil end
        for i = 1, 600 do
            DB_T["old" .. i] = {gen = 0, samples = 1, kills = 0}
        end
        for i = 1, 10 do
            REC_T["new" .. i] = {hit_count = 2, resolver_misses = 1, kills = 1, preferred_bt = 0,
                                 E = ENG_T and ENG_T.New() or nil, db_base = nil}
        end
        local ok, e = pcall(FLUSH)
        if not ok then UNIT_FAIL[#UNIT_FAIL + 1] = "DB cap: FlushDB raised " .. tostring(e) end
        local n, fresh = count(DB_T), 0
        for i = 1, 10 do if DB_T["new" .. i] then fresh = fresh + 1 end end
        if n ~= 500 then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("DB cap: %d profiles after flush, expected 500", n) end
        if fresh ~= 10 then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("DB cap: pruned %d of this match's 10 profiles", 10 - fresh) end
        for i = 1, 10 do REC_T["new" .. i] = nil end
        if n == 500 and fresh == 10 then UNIT_OK = "DB cap: 610 profiles -> 500, this match's 10 kept" end
    end
end

-- WEAPON AIM POLICY: the decision on traced damage, and calibration.
do
    local AX = probe("AIMX")
    if AX then
        local cases = {
            -- hp, traced head, traced body, dt2, unsure, air, expected
            {100, 448, 112, false, false, false, "body"},    -- AWP, full open: body kills
            {100, 240,  60, false, false, false, "head"},    -- AWP wallbang: only the head kills
            {100, 300,   0, false, false, false, "head"},    -- head over cover, body hidden
            {100, 299,  74, false, false, false, "head"},    -- scout, full HP: head is the kill
            {70,  299,  74, false, false, false, "body"},    -- scout, 70 HP: body kills
            {100, 264,  65, true,  false, false, "body"},    -- auto + charged DT: two body shots
            {100, 264,  65, false, false, false, "head"},    -- auto, no DT
            {100, 240,  60, false, true,  false, "headsp"},  -- only head kills, side in doubt
            {100, 240,  60, false, false, true,  "headsp"},  -- only head kills, enemy in air
            {100,  80,  40, false, true,  false, "sp"},      -- nothing kills, side in doubt
            {100,  80,  40, false, false, false, "-"},       -- nothing kills: ragebot default
            {0,   448, 112, false, false, false, "-"},       -- dead / no HP read
        }
        -- the safe-point policy (FEATURE.NO_SAFEPOINT off), then without it:
        -- head kill -> head, nothing kills -> the ragebot's own setting
        local FE = probe("FEATURE")
        local nosp = {headsp = "head", sp = "-"}
        for _, flag in ipairs({false, true}) do
            if FE then FE.NO_SAFEPOINT = flag end
            for i, c in ipairs(cases) do
                local want = (flag and nosp[c[7]]) or c[7]
                local got = AX.Decide(c[1], c[2], c[3], c[4], c[5], c[6])
                if got ~= want then
                    UNIT_FAIL[#UNIT_FAIL + 1] = string.format("AIMX.Decide case %d (hp %d head %d body %d, no safe point %s): got %s, expected %s",
                        i, c[1], c[2], c[3], tostring(flag), tostring(got), want)
                end
            end
        end
        if FE then FE.NO_SAFEPOINT = true end
        -- calibration: the ragebot predicts 4x our head trace on 5 shots
        local fh0 = AX.CAL.fh
        -- lethal predictions first: if the ragebot caps them at health they
        -- would read as x0.22 (100 / 448); they must not move the factor
        for _ = 1, 5 do AX.OnFire({aim_th = 448, aim_tb = 112}, 1, 100, 100) end
        if AX.CAL.fh ~= fh0 or #AX.CAL.head ~= 0 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("AIMX calibration: lethal predictions moved the head factor to %.2f", AX.CAL.fh)
        end
        for _ = 1, 5 do AX.OnFire({aim_th = 20, aim_tb = 40}, 1, 80, 100) end
        if math.abs(AX.CAL.fh - 4) > 0.01 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("AIMX calibration: head factor %.2f after 5 shots at 4x, expected 4", AX.CAL.fh)
        end
        for k in pairs(AX.CAL.head) do AX.CAL.head[k] = nil end
        AX.CAL.fh = fh0
        -- field write fallbacks, on a slot nobody uses (60): a value the game
        -- ignores (read back differs) and a value whose set raises must both
        -- leave the fallback in the field within the same write
        local FB, OK = "Override prefer body aim", AX.VAL_OK["Override prefer body aim"]
        local saved = {On = OK.On, Force = OK.Force, Off = OK.Off}
        local function field() return PLIST_STATE["60\t" .. FB] end
        OK.On, OK.Force, OK.Off = nil, nil, nil
        PLIST_THROW[FB .. "\tOn"] = true
        AX.Write(60, FB, "On")
        if field() ~= "Force" or OK.On ~= false then
            UNIT_FAIL[#UNIT_FAIL + 1] = "AIMX.Write: set of On raised, field is " .. tostring(field()) .. ", expected Force"
        end
        -- a set that raised must not be cached as written: once the game
        -- takes "-" again, the next write of it must go through
        PLIST_THROW[FB .. "\tOn"], PLIST_THROW[FB .. "\t-"] = nil, true
        PLIST_STATE["60\t" .. FB] = "Force"   -- in the field, whatever the step above did
        AX.Write(60, FB, "-")
        PLIST_THROW[FB .. "\t-"] = nil
        AX.Write(60, FB, "-")
        if field() ~= "-" then
            UNIT_FAIL[#UNIT_FAIL + 1] = "AIMX.Write: a raised set was cached; field stuck at " .. tostring(field())
        end
        OK.On, OK.Force, OK.Off = saved.On, saved.Force, saved.Off
    elseif not os.getenv("RV_TARGET") then
    elseif not os.getenv("RV_TARGET") then
        UNIT_FAIL[#UNIT_FAIL + 1] = "AIMX not reachable"
    end
end

-- CHEAT PROFILES: a method at <= 30% on >= 8 shots against a cheat is
-- skipped for that cheat except on every 4th shot; nothing changes for
-- an unknown cheat or too little data; gamesense presets only for gs.
do
    local CT, STATS, TC, DET_T = probe("CheatTrusts"), probe("CHEAT_STATS"), probe("TrustedCfg"), probe("DET")
    if CT and STATS and TC and DET_T then
        DET_T.cheat = true   -- Detection > Cheat profiles
        STATS.nl = {suppress = {h = 1, m = 9}, hit_mem = {h = 7, m = 3}}
        STATS.gs = {suppress = {h = 0, m = 3}}
        local cases = {
            {{cheat = "nl", shots_fired = 1}, "suppress", false},
            {{cheat = "nl", shots_fired = 4}, "suppress", true},
            {{cheat = "nl", shots_fired = 1}, "hit_mem", true},
            {{cheat = "gs", shots_fired = 1}, "suppress", true},
            {{shots_fired = 1}, "suppress", true},
        }
        for i, c in ipairs(cases) do
            if CT(c[1], c[2]) ~= c[3] then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("CheatTrusts case %d: expected %s", i, tostring(c[3]))
            end
        end
        -- "[cheat] learned" only when a cheat's numbers changed: the
        -- autosave runs every 60 s and would repeat every cheat ever seen
        local FL, FDB = probe("flush_log"), probe("FlushDB")
        if FL and FDB then
            local function learned()
                FL()
                local _, n = (LOG_CAPTURE[1] or ""):gsub("%[cheat%] learned nl:", "")
                return n
            end
            FDB(); local c1 = learned()
            FDB(); local c2 = learned()
            if c1 == 0 or c2 > c1 then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("[cheat] learned: %d line(s) after one save, %d after an unchanged second", c1, c2)
            end
        end
        STATS.nl, STATS.gs = nil, nil
        -- counts are capped on load as on credit: a saved 0/5e8 must not
        -- need ~90 shots of halving before the method can recover
        local CPT = probe("CP")
        if CPT and CPT.Fit then
            local c = {h = 0, m = 5e8}
            CPT.Fit(c)
            if c.h + c.m > CPT.CAP then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("CP.Fit: %.0f shots left, cap %d", c.h + c.m, CPT.CAP)
            end
        else
            UNIT_FAIL[#UNIT_FAIL + 1] = "CP.Fit not reachable"
        end
        -- luasense presets are the Neverlose luasense's: nl and unknown
        -- players get them, other detected cheats don't; the symmetric
        -- shape applies whatever the cheat
        local tc_cases = {
            {"nl", "luasense_beta", "luasense_beta"}, {"nl", "luasense_std", "luasense_std"},
            {nil,  "luasense_beta", "luasense_beta"}, {"gs", "luasense_beta", nil},
            {"gs", "luasense_std", nil},              {"pd", "luasense_beta", nil},
            {"gs", "symmetric", "symmetric"},         {"nl", "symmetric", "symmetric"},
        }
        for _, c in ipairs(tc_cases) do
            local got = TC({cheat = c[1], config_conf = 1, config_type = c[2]})
            if got ~= c[3] then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("TrustedCfg(%s, %s) = %s, expected %s",
                    tostring(c[1]), c[2], tostring(got), tostring(c[3]))
            end
        end
    elseif not os.getenv("RV_MUST_RUN_V7") and not os.getenv("RV_TARGET") then
        UNIT_FAIL[#UNIT_FAIL + 1] = "CheatTrusts/CHEAT_STATS/TrustedCfg not reachable"
    end
end

-- Cheat-profile crediting is symmetric: only head-aimed shots count, as a
-- head hit or a resolver miss; a body-aimed miss must not count against
-- the method (it could never have counted for it). Any hit ends a run of
-- resolver misses for the aim policy's "side in doubt".
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local STATS, REC_T, EI = probe("CHEAT_STATS"), probe("REC"), probe("EIDX_S64")
    local rec = REC_T and EI and EI[101] and REC_T[EI[101]]
    if STATS and rec then
        local c0, st0 = rec.cheat, rec.aim_miss_streak
        rec.cheat, rec.aim_miss_streak, STATS.pl = "pl", 0, nil
        local function shot(id, hg, outcome, tele)
            fire("aim_fire", {id = id, target = 101, backtrack = 0, hit_chance = 80, hitgroup = hg, damage = 30,
                              teleported = tele})
            if outcome == "miss" then fire("aim_miss", {id = id, target = 101, reason = "?"})
            else fire("aim_hit", {id = id, target = 101, hitgroup = outcome, damage = 30}) end
        end
        local function credited()
            local n = 0
            for _, c in pairs(STATS.pl or {}) do n = n + c.h + c.m end
            return n
        end
        shot(90001, 3, "miss")
        if credited() ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "cheat credit: a body-aimed resolver miss was counted against the method" end
        if rec.aim_miss_streak ~= 1 then UNIT_FAIL[#UNIT_FAIL + 1] = "aim_miss_streak: " .. tostring(rec.aim_miss_streak) .. " after one miss" end
        shot(90002, 3, 3)
        if rec.aim_miss_streak ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "aim_miss_streak: a body hit didn't end the run of misses" end
        shot(90003, 1, "miss")
        shot(90004, 1, 1)
        -- a teleporting target (aim_fire.teleported): no side information
        shot(90005, 1, "miss", true)
        if rec.aim_miss_streak ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "aim_miss_streak: a miss on a teleporting target counted" end
        if credited() ~= 2 then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("cheat credit: %d head-aimed shots counted, expected 2", credited()) end
        rec.cheat, rec.aim_miss_streak, STATS.pl = c0, st0, nil
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "cheat credit test: CHEAT_STATS / REC / EIDX_S64[101] not reachable"
    end
end

-- FEATURE.XWAY_UNSURE: a 3-way / 5-way enemy we missed on the resolver
-- less than 10 s ago puts the aim policy in "side in doubt"; a hit, another
-- kind of miss, other AA, the window running out or the flag off don't.
-- The shot line carries the AA type (aa=).
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local AX, FEAT, REC_T, EI = probe("AIMX"), probe("FEATURE"), probe("REC"), probe("EIDX_S64")
    local rec = REC_T and EI and EI[101] and REC_T[EI[101]]
    if AX and AX.XwayAfterMiss and FEAT and rec then
        local aa0, out0, ft0, st0 = rec.aa_type, rec.last_outcome, rec.last_fire_t, rec.aim_miss_streak
        local function shot(id, outcome)
            rec.aa_type = "3way"
            fire("aim_fire", {id = id, target = 101, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
            if outcome == "hit" then fire("aim_hit", {id = id, target = 101, hitgroup = 1, damage = 30})
            else fire("aim_miss", {id = id, target = 101, reason = outcome}) end
        end
        local function xw(dt) return AX.XwayAfterMiss(rec, W.real + (dt or 0)) end
        shot(90101, "?")
        if not xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: a resolver miss on a 3-way enemy didn't put the side in doubt" end
        if not xw(9.5) then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: doubt ended before 10 s" end
        if xw(10.5) then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: doubt outlived the 10 s window" end
        rec.aa_type = "5way"
        if not xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: 5-way not covered" end
        rec.aa_type = "hold"
        if xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: a hold-AA enemy after one miss counted as in doubt" end
        rec.aa_type = "3way"
        FEAT.XWAY_UNSURE = false
        if xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: FEATURE.XWAY_UNSURE = false still put the side in doubt" end
        FEAT.XWAY_UNSURE = true
        local FL = probe("flush_log")
        if FL then
            FL()
            if not (LOG_CAPTURE[1] or ""):find("%]%[miss%] [^\n]* aa=3way") then
                UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: the miss line carries no aa=3way"
            end
        end
        shot(90102, "hit")
        if xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: still in doubt after a head hit" end
        shot(90103, "spread")
        if xw() then UNIT_FAIL[#UNIT_FAIL + 1] = "x-way: a spread miss put the side in doubt" end
        rec.aa_type, rec.last_outcome, rec.last_fire_t, rec.aim_miss_streak = aa0, out0, ft0, st0
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "x-way test: AIMX.XwayAfterMiss / FEATURE / REC[101] not reachable"
    end
end

-- SHOT LOG (Indicators > Shot log): one print() line per shot in the
-- "[id] [fire/now] Missed x's head(98)(76%) due to spread:2.00°" format,
-- who resolved the target (from the player list), each shot's own impacts
-- for the angle (double tap included), grenade damage, and nothing at all
-- with the option off.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local IND_T, REC_T, EI = probe("IND"), probe("REC"), probe("EIDX_S64")
    local rec = REC_T and EI and EI[101] and REC_T[EI[101]]
    if IND_T and rec then
        local log0, eyebad0 = IND_T.log, W.eye_bad
        W.eye_bad = nil   -- the fuzz phase can leave the eye NaN / inf
        local keep = {}
        for _, f in ipairs({"aa_type", "last_outcome", "last_fire_t", "aim_miss_streak", "last_meth", "last_val", "vuln_ttl"}) do keep[f] = rec[f] end
        local PF = {"Force body yaw", "Force body yaw value", "Correction active"}
        local pl0 = {}
        for _, f in ipairs(PF) do pl0[f] = PLIST_STATE["101\t" .. f] end
        -- the record's label matches what the list says is forced, as the
        -- script keeps it (a released player's shots are builtin)
        local function plset(forced, val, cor)
            PLIST_STATE["101\tForce body yaw"], PLIST_STATE["101\tForce body yaw value"] = forced, val
            PLIST_STATE["101\tCorrection active"] = cor
            rec.last_meth, rec.last_val, rec.vuln_ttl = forced and "suppress" or "builtin", forced and val or 0, 0
        end
        local function lines(f)
            for i = #CONSOLE, 1, -1 do CONSOLE[i] = nil end
            CONSOLE_ON = true; f(); CONSOLE_ON = false
            local out, cur = {}, {}
            for _, m in ipairs(CONSOLE) do
                if m:sub(-1) == "\0" then cur[#cur + 1] = m:sub(1, -2)
                else cur[#cur + 1] = m; out[#out + 1] = table.concat(cur); cur = {} end
            end
            if #cur > 0 then out[#out + 1] = table.concat(cur) .. " <UNTERMINATED>" end
            return out
        end
        local function want(tag, got, ...)
            local line = got[1] or ""
            if #got ~= 1 then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("shot log %s: %d lines, expected 1", tag, #got) end
            for _, s in ipairs({...}) do
                if not line:find(s, 1, true) then
                    UNIT_FAIL[#UNIT_FAIL + 1] = string.format("shot log %s: no %q in: %s", tag, s, line)
                end
            end
        end
        -- eye (0, 0, 64) in the mock; the ragebot aims at (1000, 0, 64)
        local function shoot(id) fire("aim_fire", {id = id, target = 101, backtrack = 0, hit_chance = 76, hitgroup = 1,
                                                    damage = 98, tick = 1244, x = 1000, y = 0, z = 64}) end
        local function impact(x, y) W.real = W.real + 0.005; fire("bullet_impact", {userid = 1, x = x, y = y, z = 64}) end
        local function miss(id, reason) fire("aim_miss", {id = id, target = 101, hitgroup = 1, reason = reason}) end
        local t2 = 1000 * math.tan(math.rad(2))
        IND_T.log = true
        rec.aa_type = "5way"

        plset(true, -24, false)
        want("spread", lines(function() shoot(92001); impact(1000, t2); miss(92001, "spread") end),
            "[92001] [244/", "Missed bot101's head(98)(76%) due to spread:2.00°", " · RIFTVEIL ", " -24°", "aa=5way", "lc=")

        -- a resolver miss through a wall: two impacts on the aimed ray
        rec.aa_type = "3way"
        local rl = lines(function() shoot(92002); impact(500, 0); impact(1000, 0); miss(92002, "?") end)
        want("resolver", rl, "due to resolver:0.00°", " · RIFTVEIL ", "streak=")
        -- no forced safe point (FEATURE.NO_SAFEPOINT): the line doesn't promise one
        if (rl[1] or ""):find("next=sp", 1, true) then UNIT_FAIL[#UNIT_FAIL + 1] = "shot log: next=sp printed with safe point off" end

        -- double tap: the first bullet 3° off, the second on the ray --
        -- each result takes its own impact
        local dt = lines(function()
            shoot(92003); shoot(92004)
            impact(1000, 1000 * math.tan(math.rad(3))); impact(800, 0)
            miss(92003, "spread"); miss(92004, "?")
        end)
        if not ((dt[1] or ""):find("spread:3.00°", 1, true) and (dt[2] or ""):find("resolver:0.00°", 1, true)) then
            UNIT_FAIL[#UNIT_FAIL + 1] = "shot log double tap: " .. tostring(dt[1]) .. " / " .. tostring(dt[2])
        end

        plset(false, 0, true)
        want("hit", lines(function() shoot(92005); impact(1000, 0)
                fire("aim_hit", {id = 92005, target = 101, hitgroup = 1, damage = 98}) end),
            "[92005] [244/", "Hit bot101's head for 98(98) (100 remaining) aimed=head(76%)", " · GAMESENSE resolver")
        plset(false, 0, false)
        CRAFTED_COR0 = (CRAFTED_COR0 or 0) + 1   -- a state the script never makes: see the cor=0 check
        want("no resolver", lines(function() shoot(92006); miss(92006, "?") end), "due to resolver", " · NO RESOLVER")

        plset(true, 31, false)
        want("late", lines(function() shoot(92007); W.real = W.real + 0.6; miss(92007, "spread") end), "(late, not counted)")
        local srv0 = W.srv_hits
        W.srv_hits = 0
        want("server hit", lines(function() shoot(92008); W.srv_hits = 1; miss(92008, "?") end), "Hit bot101 on the server", " +31°")
        W.srv_hits = srv0
        want("grenade", lines(function()
            fire("player_hurt", {attacker = 1, userid = 101, weapon = "hegrenade", hitgroup = 0, dmg_health = 34, health = 66})
        end), "Naded bot101 for 34 damage (66 remaining)")

        -- an unreadable (infinite) eye: no angle rather than ":nan°"
        W.eye_bad = math.huge
        local inf = lines(function() shoot(92010); impact(1000, t2); miss(92010, "spread") end)
        W.eye_bad = nil
        if (inf[1] or ""):find("nan", 1, true) or not (inf[1] or ""):find("due to spread · ", 1, true) then
            UNIT_FAIL[#UNIT_FAIL + 1] = "shot log: infinite eye position printed: " .. tostring(inf[1])
        end

        IND_T.log = false
        local off = lines(function() shoot(92009); impact(1000, 0); miss(92009, "spread") end)
        if #off > 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "shot log: printed with the option off: " .. off[1] end

        IND_T.log, W.eye_bad = log0, eyebad0
        for f, v in pairs(keep) do rec[f] = v end
        for _, f in ipairs(PF) do PLIST_STATE["101\t" .. f] = pl0[f] end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "shot log test: IND / REC[101] not reachable"
    end
    if #CONSOLE_BAD > 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "shot log: bad output call " .. CONSOLE_BAD[1] end
end

-- LOCAL LAGCOMP BOX: a red flash on a double-tap tickbase shift, whatever
-- the DT menu reads, drawn ahead of us (our origin each frame extrapolated
-- by the shifted ticks) for back and forward shifts; normal one-tick steps
-- and fakelag draw nothing; no re-flash in the same shift; 0.5 s; option off.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local IND_T, LC, AX = probe("IND"), probe("LOCALLC"), probe("AIMX")
    if IND_T and LC and AX and AX.DtReady then
        local lc0, p0, tick0, dt0 = IND_T.lc, W.players[1], W.tick, AX.DtReady
        IND_T.lc = true
        local dt_on = true
        AX.DtReady = function() return dt_on end
        local function label()
            for i = #SCREEN, 1, -1 do SCREEN[i] = nil; SCREEN_RGB[i] = nil end
            CONSOLE_ON = true; fire("paint"); CONSOLE_ON = false
            for i, t in ipairs(SCREEN) do if t:find("^LC  ") then return t, SCREEN_RGB[i] end end
            return nil
        end
        local function fail(m) UNIT_FAIL[#UNIT_FAIL + 1] = "local lagcomp: " .. m end
        local function run(t) W.tick = t; fire("run_command", {}) end
        local function shoot() fire("weapon_fire", {userid = 1, weapon = "weapon_scar20"}) end
        local function settle(a, b) W.real = W.real + 0.6; for t = a, b do run(t) end end
        -- 640 u/s: the box sits 9 ticks (90 u) ahead
        W.players[1] = {vx = 640, jump = 0}
        LC.S.t, LC.S.shot = -1, -1
        for t = 5000, 5010 do run(t) end            -- one tick per command
        fire("setup_command", {chokedcommands = 0})
        if label() ~= nil or LC.S.t ~= -1 then fail("drawn without a shift") end
        -- a shift with no shot (defensive, DT toggled): nothing
        run(5000)
        if label() ~= nil then fail("drawn on a shift without a double-tap shot") end
        -- DT shot, back shift of 9 ticks, 90 u: the box, 9 ticks ahead
        settle(5000, 5010)
        shoot(); run(5000)
        local txt, rgb = label()
        local ox = W.tick * 640 / 64
        if txt ~= "LC  9t" then fail("DT-shot shift label " .. tostring(txt) .. ", expected LC  9t") end
        if rgb ~= "240,64,64" then fail("label colour " .. tostring(rgb) .. ", expected red 240,64,64") end
        if not (LC.S.bx and math.abs(LC.S.bx - (ox + 90)) < 0.01) then
            fail(string.format("box at x=%s, expected %.1f", tostring(LC.S.bx), ox + 90))
        end
        local t1 = LC.S.t
        W.real = W.real + 0.01; run(5001)
        if LC.S.t ~= t1 then fail("re-flashed while the same shift ran") end
        W.real = W.real + 0.6
        if label() ~= nil then fail("still drawn after the 0.5 s flash") end
        -- still ahead after we move on (it follows us, never trails)
        W.real = W.real - 0.55
        run(5001); W.tick = 5040
        label()
        if not (LC.S.bx and LC.S.bx > W.tick * 10) then fail("box fell behind us: " .. tostring(LC.S.bx)) end
        -- speed doesn't matter: a DT shot standing still still teleports
        W.players[1].vx = 0
        settle(5003, 5012)
        shoot(); run(5002)
        if label() ~= "LC  9t" then fail("no box for a DT shot + teleport while standing: " .. tostring(label())) end
        W.players[1].vx = 640
        -- the shot too long before the shift (> 0.25 s): nothing
        settle(5003, 5012)
        shoot(); W.real = W.real + 0.3; run(5002)
        if label() ~= nil then fail("drawn for a shot 0.3 s before the shift") end
        -- a shot with double tap off: nothing
        settle(5003, 5012)
        dt_on = false; shoot(); dt_on = true; run(5002)
        if label() ~= nil then fail("drawn for a shot with double tap off") end
        -- someone else's shot: nothing
        settle(5003, 5012)
        fire("weapon_fire", {userid = 2, weapon = "weapon_ssg08"}); run(5002)
        if label() ~= nil then fail("drawn for another player's shot") end
        -- an unreadable (NaN) tickbase as the first read of a life doesn't
        -- break detection for the rest of it
        W.real = W.real + 0.6
        LC.S.tb_max, LC.S.tb_prev = nil, nil
        W.tb_off = 0 / 0; run(5003); W.tb_off = nil
        for t = 5003, 5012 do run(t) end
        shoot(); run(5002)
        if label() ~= "LC  9t" then fail("no flash after a NaN tickbase: " .. tostring(label())) end
        -- forward: caught up, then a 13-tick jump between two commands
        settle(5003, 5014)
        shoot(); run(5028)
        if label() ~= "LC  13t" then fail("teleport label " .. tostring(label()) .. ", expected LC  13t") end
        if not (LC.S.bx and math.abs(LC.S.bx - (5028 + 13) * 10) < 0.01) then fail("teleport box not 13 ticks ahead: " .. tostring(LC.S.bx)) end
        W.real = W.real + 0.6
        IND_T.lc = false
        LC.S.t = -1
        shoot(); run(9000); run(8980)
        if LC.S.t ~= -1 or label() ~= nil then fail("ran with the option off") end
        IND_T.lc, W.players[1], W.tick, AX.DtReady = lc0, p0, tick0, dt0
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "local lagcomp test: IND / LOCALLC / AIMX.DtReady not reachable"
    end
end

-- Our own shift (WeDefensive / LCTicks): back to 0 once the tickbase has
-- caught up (FEATURE.DEF_RESET); v6.2 kept the last value.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local B = probe("brk")
    if B then
        local tick0 = W.tick
        local function pc(t) W.tick = t; fire("predict_command", {}) end
        pc(20000); pc(19990)
        if not (B.def and B.def >= 9) then UNIT_FAIL[#UNIT_FAIL + 1] = "our shift: 10 ticks back read as " .. tostring(B.def) end
        for t = 19991, 20005 do pc(t) end
        if B.def ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "our shift: still " .. tostring(B.def) .. " after the tickbase caught up" end
        W.tick = tick0
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "our shift test: brk not reachable"
    end
end

-- ExtrapolateOrigin (the boxes): the trace skips the player it moves, and
-- a standing player stays on the ground
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local IND_T, LC, AX = probe("IND"), probe("LOCALLC"), probe("AIMX")
    if IND_T and LC and AX then
        local lc0, p0, tick0, dt0 = IND_T.lc, W.players[1], W.tick, AX.DtReady
        IND_T.lc = true
        AX.DtReady = function() return true end
        -- a DT shot, then a 9-tick shift
        W.players[1] = {vx = 640, jump = 0}
        W.tick = 30000; fire("run_command", {})
        fire("weapon_fire", {userid = 1, weapon = "weapon_scar20"})
        W.tick = 29990; fire("run_command", {})
        for i = #TRACE_SKIP, 1, -1 do TRACE_SKIP[i] = nil end
        CONSOLE_ON = true; fire("paint"); CONSOLE_ON = false
        local bad
        for _, sk in ipairs(TRACE_SKIP) do if sk == -1 then bad = true end end
        if #TRACE_SKIP == 0 or bad then UNIT_FAIL[#UNIT_FAIL + 1] = "extrapolation: trace skip -1 (or no trace) for the local box" end
        if LC.S.bz ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "extrapolation: a standing player's box moved to z=" .. tostring(LC.S.bz) end
        W.real = W.real + 1
        IND_T.lc, W.players[1], W.tick, AX.DtReady = lc0, p0, tick0, dt0
    end
end

-- SHIFT box (enemies): a bot that moves 1500u in one record (spawn at round
-- start) doesn't light it; a fakelag break -- 14 ticks choked, the next
-- record 100u on -- does
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI = probe("REC"), probe("EIDX_S64")
    local live0 = W.live
    W.live = {101, 102, 105}
    W.players[105] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
    local function step(sent)
        W.tick = W.tick + 1; W.real = W.real + TI
        if sent then W.players[105].sim = W.tick * TI end
        for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
        fire("net_update_end")
    end
    for _ = 1, 10 do step(true) end
    local r = REC_T and EI and EI[105] and REC_T[EI[105]]
    if r then
        W.players[105].jump = 1500; step(true)
        if r._lc_on then UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box: a bot moved 1500u in one record lit it" end
        for _ = 1, 10 do step(true) end
        for _ = 1, 14 do step(false) end
        W.players[105].jump = 1600; step(true)
        if not r._lc_on then UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box: a 100u fakelag break (15-tick gap) didn't light it" end
        -- drawn red, like the local box
        for i = #SCREEN, 1, -1 do SCREEN[i] = nil; SCREEN_RGB[i] = nil end
        CONSOLE_ON = true; fire("paint"); CONSOLE_ON = false
        local red
        for i, t in ipairs(SCREEN) do if t == "SHIFT" then red = SCREEN_RGB[i] end end
        if red ~= "240,64,64" then UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box: label colour " .. tostring(red) .. ", expected red 240,64,64" end
        -- drawn ahead of where they stand now (15-tick gap, vx 0 here: on
        -- them), and gone once a normal record arrives
        if not (r._lc_box and math.abs(r._lc_box[1] - 1600) < 0.01) then
            UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box: not at their current origin carried forward: " .. tostring(r._lc_box and r._lc_box[1])
        end
        W.players[105].vx = 640; r._lc_box = nil
        fire("paint")
        local exp = W.tick * 640 / 64 + 1600 + 15 * 10
        if not (r._lc_box and math.abs(r._lc_box[1] - exp) < 0.01) then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("SHIFT box: didn't follow a moving enemy: %s, expected %.1f", tostring(r._lc_box and r._lc_box[1]), exp)
        end
        W.players[105].vx = 0
        step(true)
        r._lc_box = nil
        fire("paint")
        if r._lc_on or r._lc_box then UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box: still drawn after a normal record" end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "SHIFT box test: player 105 has no record"
    end
    W.live, W.players[105] = live0, nil
end

-- DCK after a gap (FEATURE.DCK_GAP): an enemy crouched the whole time
-- whose record arrives 8 ticks stale (choke 6 here: not sampled), the next
-- one 4 ticks stale (choke 2: sampled, not an unchoke), didn't cross 0.5 -- no
-- DCK window. With the flag off (v6.2) the same sequence
-- opens one, which proves the sequence reaches the DCK check.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F = probe("REC"), probe("EIDX_S64"), probe("FEATURE")
    local live0 = W.live
    local function run(flag, id)
        F.DCK_GAP = flag
        W.live = {101, 102, id}
        W.players[id] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 1, torso = 30, gfy = 30}
        local function step(stale)    -- stale: ticks behind now, nil = no new record
            W.tick = W.tick + 1; W.real = W.real + TI
            if stale then W.players[id].sim = (W.tick - stale) * TI end
            W.players[id].pose01 = (W.tick % 2 == 0) and 0.15 or 0.85   -- 2-way jitter, not STATIC
            for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
            fire("net_update_end")
        end
        for _ = 1, 15 do step(0) end
        local r = REC_T and EI and EI[id] and REC_T[EI[id]]
        if not r then return nil end
        r.vuln_type, r.vuln_ttl = nil, 0
        for _ = 1, 10 do step(nil) end
        step(8)                       -- choke 6 (2 ticks of latency): not sampled
        step(4)                       -- choke 2: sampled, still crouched
        local t = r.vuln_type
        W.players[id] = nil
        return t or "none"
    end
    if REC_T and EI and F then
        local on, off = run(true, 106), run(false, 107)
        F.DCK_GAP = true
        if on == nil or off == nil then
            UNIT_FAIL[#UNIT_FAIL + 1] = "DCK gap test: players 106/107 have no record"
        else
            if on == "dck" then UNIT_FAIL[#UNIT_FAIL + 1] = "DCK gap: a crouched enemy got a DCK window on the record after a stale (unsampled) one" end
            if off ~= "dck" then UNIT_FAIL[#UNIT_FAIL + 1] = "DCK gap test: with the flag off the sequence gave " .. tostring(off) .. ", not the v6.2 phantom DCK -- the test no longer reaches the check" end
        end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "DCK gap test: REC / EIDX_S64 / FEATURE not reachable"
    end
    W.live = live0
end

-- Config recognition cadence (FEATURE.CFG_CADENCE): an enemy sending a
-- record every 2 ticks, always on an odd tick, gets recognised. v6.2 ran
-- recognition on simtime % 32 == 0, which that cadence never lands on --
-- the flag-off half proves the sequence still shows that.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F = probe("REC"), probe("EIDX_S64"), probe("FEATURE")
    local live0 = W.live
    local function run(flag, id)
        F.CFG_CADENCE = flag
        W.live = {101, 102, id}
        W.players[id] = {sim = 0, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
        local sent, last_cc, last_t, min_gap = 0, nil, nil, math.huge
        for _ = 1, 400 do
            W.tick = W.tick + 1; W.real = W.real + TI
            if W.tick % 2 == 1 then
                sent = sent + 1
                W.players[id].sim = W.tick * TI
                W.players[id].pose01 = (sent % 2 == 0) and 0.15 or 0.85
            end
            for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
            fire("net_update_end")
            -- each recognition moves config_conf: those moves are >= 32 ticks apart
            local r = REC_T and EI and EI[id] and REC_T[EI[id]]
            if r and r.config_conf ~= last_cc then
                if last_cc and last_t then min_gap = math.min(min_gap, W.tick - last_t) end
                last_cc, last_t = r.config_conf, W.tick
            end
        end
        local r = REC_T and EI and EI[id] and REC_T[EI[id]]
        W.players[id] = nil
        if not r then return nil end
        return r.config_type or "none", r.lt, min_gap
    end
    if REC_T and EI and F then
        local on, _, gap = run(true, 108)
        local off, lt = run(false, 109)
        F.CFG_CADENCE = true
        if on == nil or off == nil then
            UNIT_FAIL[#UNIT_FAIL + 1] = "config cadence test: players 108/109 have no record"
        else
            if on == "none" then UNIT_FAIL[#UNIT_FAIL + 1] = "config cadence: a 2-way jitter enemy on a 2-tick odd cadence was never recognised" end
            if gap < 32 then UNIT_FAIL[#UNIT_FAIL + 1] = "config cadence: recognition ran " .. gap .. " ticks after the last run, expected >= 32" end
            if off ~= "none" then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("config cadence test: with the flag off it recognised %s (last simtime tick %s) -- the cadence no longer avoids st %% 32 == 0", tostring(off), tostring(lt)) end
        end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "config cadence test: REC / EIDX_S64 / FEATURE not reachable"
    end
    W.live = live0
end

-- Stale vuln windows (FEATURE.STALE_WINDOW): (a) an enemy released on
-- STATIC AA with a window still counting is shot as builtin, not in the
-- window; (b) a record 100 ticks after the last (death / dormancy) closes
-- the window. The flag-off half shows v6.2's behaviour on both.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F, SH = probe("REC"), probe("EIDX_S64"), probe("FEATURE"), probe("SHOTS")
    local live0 = W.live
    local function run(flag, id)
        F.STALE_WINDOW = flag
        W.live = {101, 102, id}
        W.players[id] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
        local function step(gap, jitter)
            W.tick = W.tick + (gap or 1); W.real = W.real + (gap or 1) * TI
            W.players[id].sim = W.tick * TI
            W.players[id].pose01 = jitter and ((W.tick % 2 == 0) and 0.15 or 0.85) or 0.5
            for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
            fire("net_update_end")
        end
        -- before any decision: a new record's label, and a shot at an enemy
        -- with no record yet
        local NR = probe("NewRec")
        local okn, r0 = pcall(NR or error, id, "stale_test_" .. id)
        local first = okn and type(r0) == "table" and r0.last_meth or nil
        fire("aim_fire", {id = 94000 + id, target = 199, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
        local d0 = SH[94000 + id]
        if not (d0 and d0.meth == first) then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("stale window (flag %s): a shot at an enemy with no record is %s, a new record %s", tostring(flag), tostring(d0 and d0.meth), tostring(first))
        end
        SH[94000 + id] = nil
        for _ = 1, 12 do step(1, false) end            -- constant pose: STATIC, released
        local r = REC_T and EI and EI[id] and REC_T[EI[id]]
        if not (r and SH) then W.players[id] = nil; return nil end
        r.vuln_ttl, r.vuln_type, r.vuln_val, r.last_meth, r.last_val = 6, "dck", -93, "vuln_dck", -93
        r.vuln_profile.dck = {seen = 0, hit = 0}
        step(1, false)                                  -- still STATIC: ClearEnt
        local sid = 93000 + id
        fire("aim_fire", {id = sid, target = id, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
        local d = SH[sid]
        local meth, inv = d and d.meth, d and d.in_vuln
        -- two resolver misses on a released enemy: in doubt (safe point),
        -- the frozen window doesn't count
        local AX = probe("AIMX")
        r.aim_miss_streak = 2
        local doubt = AX and AX.InDoubt(r, W.real)
        r.aim_miss_streak = 0
        if flag and not doubt then UNIT_FAIL[#UNIT_FAIL + 1] = "stale window: two misses on a released enemy with a frozen window not in doubt" end
        if not flag and doubt then UNIT_FAIL[#UNIT_FAIL + 1] = "stale window test: flag off, the frozen window still read as no window" end
        -- a trial is counted exactly when the shot is in the window
        if (r.vuln_profile.dck.seen > 0) ~= (inv == true) then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("stale window (flag %s): vuln trials %d for a shot in window %s", tostring(flag), r.vuln_profile.dck.seen, tostring(inv))
        end
        SH[sid] = nil
        -- (b) window open, then nothing for 100 ticks
        for _ = 1, 12 do step(1, true) end
        r.vuln_ttl, r.vuln_type, r.vuln_val = 6, "dck", -93
        step(100, true)
        local ttl = r.vuln_ttl
        W.players[id] = nil
        return meth, inv, ttl, first
    end
    if REC_T and EI and F and SH then
        local m1, v1, t1, f1 = run(true, 110)
        local m0, v0, t0, f0 = run(false, 111)
        if f1 ~= "builtin" then UNIT_FAIL[#UNIT_FAIL + 1] = "stale window: a new enemy starts labelled " .. tostring(f1) .. ", not builtin" end
        if f0 ~= "ring" then UNIT_FAIL[#UNIT_FAIL + 1] = "stale window test: flag off, a new enemy starts as " .. tostring(f0) .. ", not v6.2's ring" end
        F.STALE_WINDOW = true
        if m1 == nil or m0 == nil then
            UNIT_FAIL[#UNIT_FAIL + 1] = "stale window test: players 110/111 have no record / shot"
        else
            if m1 ~= "builtin" or v1 then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("stale window: a STATIC-released enemy was shot as %s, in window %s", tostring(m1), tostring(v1)) end
            if t1 ~= 0 then UNIT_FAIL[#UNIT_FAIL + 1] = "stale window: a record 100 ticks on left the window at " .. tostring(t1) end
            if m0 ~= "vuln_dck" or not v0 or not (t0 and t0 > 0) then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("stale window test: flag off gave %s / %s / ttl %s, not v6.2's stale window -- the test no longer reaches it", tostring(m0), tostring(v0), tostring(t0))
            end
        end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "stale window test: REC / EIDX_S64 / FEATURE / SHOTS not reachable"
    end
    W.live = live0
end

-- UNK value (FEATURE.UNK_DELTA): an enemy looking at world yaw 100 whose
-- torso unchokes at 150 gets +50 (torso - eye, within the cap), not the
-- world yaw 150 that v6.2 forced (the flag-off half).
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F = probe("REC"), probe("EIDX_S64"), probe("FEATURE")
    local live0 = W.live
    local function run(flag, id)
        F.UNK_DELTA = flag
        W.live = {101, 102, id}
        W.players[id] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 100, duck = 0, torso = 150, gfy = 146}
        local best
        for step = 1, 60 do
            W.tick = W.tick + 1; W.real = W.real + TI
            local c = W.players[id]
            if (step % 5) >= 3 then c.sim = W.tick * TI end   -- choke 3 of 5, then unchoke
            c.pose01 = (step % 2 == 0) and 0.78 or 0.24
            for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
            fire("net_update_end")
            local r = REC_T and EI and EI[id] and REC_T[EI[id]]
            if r and r.vuln_type == "unk" and r.vuln_ttl > 0 then best = r.vuln_val end
        end
        W.players[id] = nil
        return best
    end
    if REC_T and EI and F then
        local on, off = run(true, 113), run(false, 114)
        F.UNK_DELTA = true
        if not (on and math.abs(on - 50) < 0.5) then UNIT_FAIL[#UNIT_FAIL + 1] = "UNK delta: torso 150 / eye 100 forced " .. tostring(on) .. ", expected +50" end
        if not (off and math.abs(off - 150) < 0.5) then UNIT_FAIL[#UNIT_FAIL + 1] = "UNK delta test: flag off gave " .. tostring(off) .. ", not v6.2's world yaw 150 -- no UNK window reached" end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "UNK delta test: REC / EIDX_S64 / FEATURE not reachable"
    end
    W.live = live0
end

-- Max desync (FEATURE.DESYNC_FORMULA): Valve's limit -- 58 standing, 29
-- at a full run (never lower), ~51 slow-walking, ducking toward half; an
-- unreadable input keeps the cap. A 500 u/s enemy's correction cap is 29+
-- (VelCap: 8, the flag-off half).
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local MD, REC_T, EI, F = probe("MaxDesync"), probe("REC"), probe("EIDX_S64"), probe("FEATURE")
    if MD and REC_T and EI and F then
        local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.05 end
        local cases = {
            {"standing", {stop_to_full_run = 0, duck_amount = 0}, 0, 58},
            {"full run", {stop_to_full_run = 1, duck_amount = 0}, 250, 29},
            {"air 400 u/s", {stop_to_full_run = 1, duck_amount = 0}, 400, 29},
            {"slow walk 80 u/s", {stop_to_full_run = 0, duck_amount = 0}, 80, 58 * (1 - 0.2 * 80 / 130)},
            {"crouch-walk 85 u/s", {stop_to_full_run = 0, duck_amount = 1}, 85, 58 * (function()
                local m = 1 - 0.2 * 85 / 130; return m + 1 * 1 * (0.5 - m) end)()},
            {"unread transition", {duck_amount = 0}, 250, 29},
            {"NaN speed", {stop_to_full_run = 1, duck_amount = 0}, 0 / 0, 58},
        }
        for _, c in ipairs(cases) do
            local got = MD(c[2], c[3], 250, 58)
            if not near(got, c[4]) then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("max desync %s: %s, expected %.1f", c[1], tostring(got), c[4]) end
        end
        if not near(MD(nil, 100, 250, 58), 58) then UNIT_FAIL[#UNIT_FAIL + 1] = "max desync: no animstate didn't keep the cap" end
        -- in the resolver: a 500 u/s enemy
        local live0 = W.live
        local function run(flag, id)
            F.DESYNC_FORMULA = flag
            W.live = {101, 102, id}
            W.players[id] = {sim = W.tick * TI, vx = 500, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
            for _ = 1, 6 do
                W.tick = W.tick + 1; W.real = W.real + TI
                W.players[id].sim = W.tick * TI
                W.players[id].pose01 = (W.tick % 2 == 0) and 0.15 or 0.85
                for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
                fire("net_update_end")
            end
            local r = EI[id] and REC_T[EI[id]]
            W.players[id] = nil
            return r and r.corr_cap
        end
        local on, off = run(true, 115), run(false, 116)
        F.DESYNC_FORMULA = true
        if not (on and on >= 29 - 0.05) then UNIT_FAIL[#UNIT_FAIL + 1] = "max desync: a 500 u/s enemy's cap is " .. tostring(on) .. ", expected >= 29" end
        if not (off and near(off, 58 * (1 - 500 / 580))) then UNIT_FAIL[#UNIT_FAIL + 1] = "max desync test: flag off gave " .. tostring(off) .. ", not VelCap's 8" end
        W.live = live0
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "max desync test: MaxDesync / REC / EIDX_S64 / FEATURE not reachable"
    end
end

-- No choke, no desync (FEATURE.NO_CHOKE_STATIC): a bot sending every tick
-- whose pose (our client's) jitters is static and handed to gamesense; one
-- bundled packet in 16 doesn't change that; an enemy fakelagging (3-tick
-- gaps) is resolved; after a 100-tick gap the history starts over. The
-- flag-off half shows v6.2 resolving the bot.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F, NC = probe("REC"), probe("EIDX_S64"), probe("FEATURE"), probe("NoChoke")
    local live0 = W.live
    local function run(flag, id, gaps)
        F.NO_CHOKE_STATIC = flag
        W.live = {101, 102, id}
        W.players[id] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
        local n = 0
        for _, gap in ipairs(gaps) do
            for _ = 1, gap - 1 do
                W.tick = W.tick + 1; W.real = W.real + TI
                for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
                fire("net_update_end")
            end
            W.tick = W.tick + 1; W.real = W.real + TI
            n = n + 1
            W.players[id].sim = W.tick * TI
            W.players[id].pose01 = (n % 2 == 0) and 0.15 or 0.85   -- what our client shows: jitter
            for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
            fire("net_update_end")
        end
        local r = EI[id] and REC_T[EI[id]]
        W.players[id] = nil
        return r
    end
    local function rep(v, k) local t = {} for i = 1, k do t[i] = v end return t end
    if REC_T and EI and F and NC then
        local bot = run(true, 117, rep(1, 24))
        if not (bot and bot.aa_type == "static" and bot.last_meth == "builtin") then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("no choke: a bot sending every tick read as %s / %s, expected static / builtin",
                tostring(bot and bot.aa_type), tostring(bot and bot.last_meth))
        end
        local g = rep(1, 24); g[10] = 2
        local bundled = run(true, 118, g)
        if not (bundled and bundled.aa_type == "static") then UNIT_FAIL[#UNIT_FAIL + 1] = "no choke: one bundled packet in 16 broke it: " .. tostring(bundled and bundled.aa_type) end
        local some = {} for i = 1, 24 do some[i] = (i % 3 == 0) and 2 or 1 end
        local s1 = run(true, 122, some)
        if not (s1 and s1.aa_type ~= "static") then UNIT_FAIL[#UNIT_FAIL + 1] = "no choke: an enemy choking one tick every third record read as static" end
        local fl = run(true, 119, rep(3, 24))
        if not (fl and fl.aa_type ~= "static") then UNIT_FAIL[#UNIT_FAIL + 1] = "no choke: a fakelagging enemy (3-tick gaps) read as static" end
        local g2 = rep(1, 24); g2[20] = 100
        local back = run(true, 120, g2)
        if not (back and not NC(back)) then UNIT_FAIL[#UNIT_FAIL + 1] = "no choke: the history didn't start over after a 100-tick gap" end
        local off = run(false, 121, rep(1, 24))
        F.NO_CHOKE_STATIC = true
        if not (off and off.aa_type ~= "static") then UNIT_FAIL[#UNIT_FAIL + 1] = "no choke test: flag off read the bot as static -- the test no longer shows v6.2's jitter label" end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "no choke test: REC / EIDX_S64 / FEATURE / NoChoke not reachable"
    end
    W.live = live0
end

-- Window gate (FEATURE.WINDOW_GATE): with "Vulnerability" (and 6lex) off, a counting
-- window isn't forced, so it mustn't switch suppress off -- a jittering,
-- fakelagging enemy gets suppress. v6.2 (flag off) released it.
-- Round start (STALE_WINDOW): a record that was forcing comes back as
-- builtin with no window; v6.2 kept last round's.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F = probe("REC"), probe("EIDX_S64"), probe("FEATURE")
    local det_el
    for _, el in ipairs(UI_ELEMS) do
        if el.kind == "multi" and el.items and el.items[1] == "Vulnerability" then det_el = el end
    end
    if REC_T and EI and F and det_el then
        local det0 = det_el.a
        local function set_det(list) det_el.a = list; for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end end
        local nov = {}
        for _, it in ipairs(det_el.items) do if it ~= "Vulnerability" and it ~= "Desync angle" then nov[#nov + 1] = it end end
        set_det(nov)
        local live0 = W.live
        local function run(flag, id)
            F.WINDOW_GATE = flag
            W.live = {101, 102, id}
            W.players[id] = {sim = W.tick * TI, vx = 0, vy = 0, pose01 = 0.5, eye = 0, duck = 0, torso = 0, gfy = 0}
            local r
            for n = 1, 30 do
                for _ = 1, 3 do   -- one record every 3 ticks: chokes, so not static
                    W.tick = W.tick + 1; W.real = W.real + TI
                    for _, p in ipairs({101, 102}) do W.players[p].sim = W.tick * TI end
                    if _ == 3 then
                        W.players[id].sim = W.tick * TI
                        W.players[id].pose01 = (n % 2 == 0) and 0.15 or 0.85
                    end
                    r = EI[id] and REC_T[EI[id]]
                    if r and n >= 20 then r.vuln_ttl, r.vuln_type, r.vuln_val = 11, "dck", 40 end
                    fire("net_update_end")
                end
            end
            W.players[id] = nil
            return r and r.last_meth
        end
        local on, off = run(true, 123), run(false, 124)
        F.WINDOW_GATE = true
        set_det(det0)
        if on ~= "suppress" then UNIT_FAIL[#UNIT_FAIL + 1] = "window gate: an unforced window (Vulnerability off) left " .. tostring(on) .. ", expected suppress" end
        if off == "suppress" then UNIT_FAIL[#UNIT_FAIL + 1] = "window gate test: flag off still suppressed -- the test no longer reaches v6.2's block" end
        W.live = live0
        -- round start
        local function rs(flag)
            F.STALE_WINDOW = flag
            local r = next(REC_T) and REC_T[next(REC_T)]
            if not r then return nil end
            r.active, r.last_meth, r.last_val, r.vuln_ttl = true, "suppress", -35, 6
            fire("round_start")
            return r.last_meth, r.vuln_ttl, r.active
        end
        local m1, t1, a1 = rs(true)
        local m0, t0 = rs(false)
        F.STALE_WINDOW = true
        if not (m1 == "builtin" and t1 == 0 and a1 == false) then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("round start: record left as %s / window %s / active %s", tostring(m1), tostring(t1), tostring(a1))
        end
        if not (m0 == "suppress" and t0 == 6) then UNIT_FAIL[#UNIT_FAIL + 1] = "round start test: flag off cleared the record -- not v6.2's behaviour" end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "window gate test: REC / EIDX_S64 / FEATURE / detection menu not reachable"
    end
end

-- Meta streak (FEATURE.META_STREAK): gamesense miss, hit, miss is not two
-- misses in a row -- no takeover. v6.2 (flag off) took over.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local REC_T, EI, F, SH = probe("REC"), probe("EIDX_S64"), probe("FEATURE"), probe("SHOTS")
    local r = EI and REC_T and EI[102] and REC_T[EI[102]]
    if r and F and SH then
        local function run(flag)
            F.META_STREAK = flag
            r.meta_aggressive, r.builtin_miss_streak = false, 0
            local id = 95000
            local function shot(outcome)
                id = id + 1
                r.last_meth, r.last_val, r.vuln_ttl, r.active = "builtin", 0, 0, false
                fire("aim_fire", {id = id, target = 102, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
                if outcome == "miss" then fire("aim_miss", {id = id, target = 102, hitgroup = 1, reason = "?"})
                else fire("aim_hit", {id = id, target = 102, hitgroup = 2, damage = 30}) end
            end
            shot("miss"); shot("hit"); shot("miss")
            return r.meta_aggressive
        end
        local on, off = run(true), run(false)
        F.META_STREAK = true
        r.meta_aggressive, r.builtin_miss_streak = false, 0
        if on then UNIT_FAIL[#UNIT_FAIL + 1] = "meta streak: builtin miss, hit, miss handed the enemy to the aggressive mode" end
        if not off then UNIT_FAIL[#UNIT_FAIL + 1] = "meta streak test: flag off didn't take over -- the test no longer shows v6.2's reset" end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "meta streak test: REC[102] / FEATURE / SHOTS not reachable"
    end
end

-- Defensive frames: a frame whose simulation time is below the highest
-- already received (lag compensation writes no record for it) is counted,
-- and the next shot at that player carries the count (df=)
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local SH = probe("SHOTS")
    local p = W.players[102]
    if SH and p then
        W.live = {101, 102}
        local top = W.tick
        for k = 1, 6 do
            W.tick = W.tick + 1
            W.real = W.real + TI
            -- even steps: a new top record; odd: 3 ticks back (defensive)
            p.sim = ((k % 2 == 0) and (top + k) or (top + k - 3)) * TI
            W.players[101].sim = W.tick * TI
            fire("net_update_end")
        end
        fire("aim_fire", {id = 91001, target = 102, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
        local d = SH[91001]
        if not (d and (d.df or 0) >= 2) then
            UNIT_FAIL[#UNIT_FAIL + 1] = "defensive frames: " .. tostring(d and d.df) .. " counted, expected >= 2"
        end
        SH[91001] = nil
        -- one defensive frame seen on five net updates (the enemy chokes
        -- inside its window) counts once
        W.tick = W.tick + 1; W.real = W.real + TI
        p.sim = (top + 2) * TI
        W.players[101].sim = W.tick * TI
        fire("net_update_end")
        fire("aim_fire", {id = 91002, target = 102, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
        local before = SH[91002] and SH[91002].df or 0
        SH[91002] = nil
        for _ = 1, 5 do
            W.tick = W.tick + 1; W.real = W.real + TI
            W.players[101].sim = W.tick * TI
            fire("net_update_end")
        end
        fire("aim_fire", {id = 91003, target = 102, backtrack = 0, hit_chance = 80, hitgroup = 1, damage = 30})
        local after = SH[91003] and SH[91003].df or 0
        SH[91003] = nil
        if after ~= before then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("defensive frames: one frame seen on 5 updates counted %d times", after - before + 1)
        end
        -- FEATURE.SKIP_DEF_FRAMES: none of them reached the pose history,
        -- and the last record stayed the highest one
        local REC_T, EI = probe("REC"), probe("EIDX_S64")
        local r = REC_T and EI and EI[102] and REC_T[EI[102]]
        if r and r.hist then
            -- ring buffer {b, h, n}: walk it oldest to newest
            local maxt, back, hb = -1, 0, r.hist
            for o = hb.n - 1, 0, -1 do
                local sm = hb.b[((hb.h - o - 1) % hb.n) + 1]
                if type(sm) == "table" and sm.t then
                    if sm.t < maxt then back = back + 1 end
                    if sm.t > maxt then maxt = sm.t end
                end
            end
            if back > 0 or (r.st_max and r.lt ~= r.st_max) then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("defensive frames sampled: %d out of order in the pose history, last record %s vs highest %s",
                    back, tostring(r.lt), tostring(r.st_max))
            end
        else
            UNIT_FAIL[#UNIT_FAIL + 1] = "defensive frame test: player 102's record / history not reachable"
        end
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "defensive frame test: SHOTS / player 102 not reachable"
    end
end

-- ESP: the aim policy in force shows on that enemy (Indicators > ESP flags)
if not os.getenv("RV_TARGET") then
    local REC_T, EI, UES, IND_T = probe("REC"), probe("EIDX_S64"), probe("UpdateEspState"), probe("IND")
    local rec = REC_T and EI and EI[101] and REC_T[EI[101]]
    if rec and UES and IND_T then
        local pol0, esp0 = rec.aim_pol, IND_T.esp
        rec.aim_pol, IND_T.esp = "headsp", true
        UES()
        local seen
        for _, cb in ipairs(ESP_FLAGS) do
            local ok, on, text = pcall(cb, 101)
            if ok and on and text == "HEAD SP" then seen = true end
        end
        if not seen then UNIT_FAIL[#UNIT_FAIL + 1] = "ESP: no HEAD SP flag on an enemy under that aim policy" end
        rec.aim_pol, IND_T.esp = pol0, esp0
        UES()
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "ESP aim flag test: REC / UpdateEspState / IND not reachable"
    end
end

-- Resolver switched off mid-match: one update later every player must be
-- back on the built-in (no forced yaw, no aim override) -- not only at the
-- next round start. (Not in parity runs: v6.2 never released, and parity is
-- about decisions while the resolver is on.)
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local master
    for _, el in ipairs(UI_ELEMS) do
        if el.kind == "checkbox" and type(el.name) == "string" and el.name:find("^Resolver") then master = el end
    end
    if master then
        for ent = 101, 102 do
            PLIST_STATE[ent .. "\tForce body yaw"] = true
            PLIST_STATE[ent .. "\tOverride prefer body aim"] = "On"
        end
        master.a = false
        fire("net_update_end")
        for ent = 101, 102 do
            if PLIST_STATE[ent .. "\tForce body yaw"] ~= false
               or PLIST_STATE[ent .. "\tOverride prefer body aim"] ~= "-" then
                UNIT_FAIL[#UNIT_FAIL + 1] = "resolver off: player " .. ent .. " still forced after an update"
            end
            -- handed back to gamesense's own resolver, not left with none
            if PLIST_STATE[ent .. "\tCorrection active"] ~= true then
                UNIT_FAIL[#UNIT_FAIL + 1] = "resolver off: player " .. ent .. " left with Correction active "
                    .. tostring(PLIST_STATE[ent .. "\tCorrection active"]) .. " (gamesense's resolver off)"
            end
        end
        master.a = true
    else
        UNIT_FAIL[#UNIT_FAIL + 1] = "resolver master switch not found"
    end
end

for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
-- a player (re)connects into a slot: that slot's cheat data is dropped;
-- our own connect drops everyone's
fire("player_connect_full", {userid = 102})
fire("player_connect_full", {userid = 1})
fire("console_input", "rv_stats")
fire("console_input", "rv_db")
fire("console_input", "rv_save")
fire("console_input", "rv_engine")
fire("console_input", "rv_perf")
fire("console_input", "rv_perf")
-- rv_wipe clears everything saved, the learned cheat profiles included
-- (up to 8.5.4 they survived it). Last: it drops every profile.
if not os.getenv("RV_TARGET") and not os.getenv("RV_PARITY") then
    local STATS = probe("CHEAT_STATS")
    if STATS then
        STATS.nl = {suppress = {h = 3, m = 9}}
        fire("console_input", "rv_db")
        if not (LOG_CAPTURE[1] or ""):find("cheat nl | suppress=3/12", 1, true) then
            local FL = probe("flush_log"); if FL then FL() end
        end
        if not (LOG_CAPTURE[1] or ""):find("cheat nl | suppress=3/12", 1, true) then
            UNIT_FAIL[#UNIT_FAIL + 1] = "rv_db: learned cheat profiles not listed"
        end
        fire("console_input", "rv_wipe")
        if next(STATS) then UNIT_FAIL[#UNIT_FAIL + 1] = "rv_wipe: learned cheat profiles survived" end
    end
end
fire("round_start")
fire("game_end")
fire("shutdown")

debug.sethook()

if os.getenv("RV_LOG_OUT") then
    local f = assert(io.open(os.getenv("RV_LOG_OUT"), "w"))
    f:write(LOG_CAPTURE[#LOG_CAPTURE] or "")
    f:close()
end
if PLIST_OUT then
    local f = assert(io.open(PLIST_OUT, "w"))
    f:write(table.concat(PLIST_LOG, "\n"), "\n")
    f:close()
end

-- ── Report ───────────────────────────────────────────────────────────
local failed = false
print("")

if #leaks > 0 then
    failed = true
    print("FAIL -- accidental global writes (missing 'local'?):")
    for _, k in ipairs(leaks) do print("  " .. tostring(k)) end
end
if #bad_reads > 0 then
    failed = true
    print("FAIL -- reads of undeclared globals (out-of-scope local? typo?):")
    for _, k in ipairs(bad_reads) do print("  " .. tostring(k)) end
end
if #cb_errors > 0 then
    failed = true
    print("FAIL -- uncaught callback errors:")
    for _, e in ipairs(cb_errors) do print("  " .. e) end
end

local err_lines = ERR_LINES
if BENCH and API_COUNT then
    local per = {tick = BENCH.ticks, frame = BENCH.ticks * 4}
    local sums, rows = {tick = 0, frame = 0}, {}
    for key, n in pairs(API_COUNT) do
        local phase, name = key:match("^(%w+)\t(.+)$")
        if per[phase] then
            sums[phase] = sums[phase] + n
            rows[#rows + 1] = {phase, name, n / per[phase]}
        end
    end
    table.sort(rows, function(a, b) return a[3] > b[3] end)
    print(string.format("API calls: %.1f per tick, %.1f per paint frame", sums.tick / per.tick, sums.frame / per.frame))
    for i = 1, math.min(14, #rows) do print(string.format("  %-5s %-28s %6.2f", rows[i][1], rows[i][2], rows[i][3])) end
end
if BENCH then
    print(string.format("Bench: %d enemies, %d ticks: net_update %.1f us/tick, paint %.1f us/frame, total at 4 frames/tick %.1f us/tick",
        BENCH.n, BENCH.ticks, BENCH.net, BENCH.paint, BENCH.net + 4 * BENCH.paint))
    local rows, total = {}, 0
    for k, v in pairs(BENCH.prof) do rows[#rows + 1] = {k, v}; total = total + v end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(12, #rows) do
        print(string.format("  %5.1f%%  %s", 100 * rows[i][2] / total, rows[i][1]))
    end
end
if UNIT_OK then print("Unit: " .. UNIT_OK) end
do
    local bad = 0
    for line in (LOG_CAPTURE[1] or ""):gmatch("[^\n]+") do
        if line:find("meth=builtin", 1, true) and line:find(" cor=0", 1, true) then bad = bad + 1 end
    end
    -- the v8.32 probe rides on every [corr] line: pose read and what we forced
    local corr, probed = CORR_SEEN or 0, CORR_PROBED or 0
    if (SHOT_SEEN or 0) == 0 or SHOT_EO ~= SHOT_SEEN then
        UNIT_FAIL[#UNIT_FAIL + 1] = string.format("shot lines: %d of %d carry eo= / lbyu=", SHOT_EO or 0, SHOT_SEEN or 0)
    end
    if corr == 0 or probed ~= corr then UNIT_FAIL[#UNIT_FAIL + 1] = string.format("probe: %d of %d [corr] lines carry pz= / pf=", probed, corr) end
    bad = bad - (CRAFTED_COR0 or 0)   -- the shot log test's own "no resolver" shot
    if bad > 0 then UNIT_FAIL[#UNIT_FAIL + 1] = bad .. " builtin shot(s) fired with gamesense's resolver off (cor=0)" end
end
if #UNIT_FAIL > 0 then
    failed = true
    print("FAIL -- unit checks:")
    for _, l in ipairs(UNIT_FAIL) do print("  " .. l) end
end
if PLIST_BAD_N > 0 then
    failed = true
    print(string.format("FAIL -- %d invalid plist writes (value outside +-60, NaN, or non-boolean flag):", PLIST_BAD_N))
    for _, l in ipairs(PLIST_BAD) do print("  " .. l) end
end
if FUZZ_REPORT then
    local m = FUZZ_REPORT.mem
    print(string.format("Fuzz: %d ticks in %.1fs (%.0f ticks/s)", FUZZ_REPORT.ticks, FUZZ_REPORT.secs,
        FUZZ_REPORT.ticks / math.max(FUZZ_REPORT.secs, 1e-9)))
    -- Leak test: the net heap's peak over the second half of the soak may
    -- not exceed the first half's peak by more than 25% + 256 KB.
    local peak1, peak2, maxshots, maxrec, maxdb = 0, 0, 0, 0, 0
    for i, c in ipairs(m) do
        if i <= #m / 2 then peak1 = math.max(peak1, c.net) else peak2 = math.max(peak2, c.net) end
        maxshots, maxrec, maxdb = math.max(maxshots, c.shots), math.max(maxrec, c.rec), math.max(maxdb, c.db)
    end
    print(string.format("  net heap peak: first half %.0f KB, second half %.0f KB | max REC %d, SHOTS %d, DB %d",
        peak1, peak2, maxrec, maxshots, maxdb))
    if os.getenv("RV_SOAK_TRACE") then
        for i, c in ipairs(m) do
            print(string.format("    %2d  heap %6.0f KB  net %6.0f KB  log %7d B  REC %3d  SHOTS %3d  DB %3d",
                i, c.heap, c.net, c.log, c.rec, c.shots, c.db))
        end
    end
    -- (skipped when RV_PLIST_OUT is set: the recorder itself keeps every
    -- write in memory and would read as a leak)
    if not PLIST_OUT and peak2 > peak1 * 1.25 + 256 then
        failed = true
        print(string.format("FAIL -- net heap grew %.0f KB from the first half to the second (leak)", peak2 - peak1))
    end
    if maxdb > 500 then
        failed = true
        print(string.format("FAIL -- DB held %d profiles, cap is 500", maxdb))
    end
end
if #err_lines > 0 then
    failed = true
    print("FAIL -- runtime errors swallowed by riftveil's pcall wrappers:")
    local shown = {}
    for _, l in ipairs(err_lines) do
        local key = l:gsub("^%[[^%]]*%]", "")
        if not shown[key] then shown[key] = true; print("  " .. l) end
    end
end

-- Per-function coverage for top-level `local function NAME(` definitions,
-- `NAME = function(` forward-declared ones (FlushDB) and module functions
-- (`function ENG.Decide(`).
local src_lines = {}
for line in io.lines(TARGET) do src_lines[#src_lines + 1] = line end
local fn_ranges = {}
for i, line in ipairs(src_lines) do
    local name = line:match("^local function ([%w_]+)%(") or line:match("^([%w_]+) = function%(")
                 or line:match("^function ([%w_%.]+)%(")
    if name then
        local j = i + 1
        while j <= #src_lines and not src_lines[j]:match("^end") do j = j + 1 end
        fn_ranges[#fn_ranges + 1] = {name = name, s = i, e = j}
    end
end
local total_fn, never = 0, {}
local cov_by_name = {}
for _, r in ipairs(fn_ranges) do
    local body, hit = 0, 0
    for l = r.s + 1, r.e - 1 do
        local t = src_lines[l]
        if t:match("%S") and not t:match("^%s*%-%-") then
            body = body + 1
            if hits[l] then hit = hit + 1 end
        end
    end
    total_fn = total_fn + 1
    cov_by_name[r.name] = {hit = hit, body = body}
    if hit == 0 and body > 0 then never[#never + 1] = r.name end
end

print(string.format("Coverage: %d/%d top-level functions executed at least one line.",
    total_fn - #never, total_fn))
if #never > 0 then
    print("  Never executed: " .. table.concat(never, ", "))
end
for _, name in ipairs(MUST_RUN) do
    local c = cov_by_name[name]
    if not c then
        failed = true
        print("FAIL -- MUST_RUN function not found in source: " .. name)
    elseif c.hit == 0 then
        failed = true
        print(string.format("FAIL -- MUST_RUN function never executed: %s (harness isn't reaching it)", name))
    else
        print(string.format("  %-14s %3d/%-3d lines", name, c.hit, c.body))
    end
end

print("")
if failed then os.exit(1) end
print("PASS -- no leaks, no undeclared reads, no swallowed runtime errors, and every MUST_RUN function executed.")
os.exit(0)
