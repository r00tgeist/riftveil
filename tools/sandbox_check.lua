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
    "Tick", "Decide", "Write", "Traced", "LocalWeaponClass",
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
        if k == "trace_line"         then return function() return 1.0, -1 end end
        if k == "eye_position"       then return function() return 0, 0, 64 end end
        -- Traced damage per hitbox from W.players[ent].tdmg (default: head
        -- 180, body 55 -- an armored enemy behind nothing, scout-like).
        if k == "trace_bullet"       then return function(_, _, _, _, tx)
            local target, hb = math.floor(tx / 1000), math.floor(tx % 1000)
            local p = W.players[target]
            if not p then return nil, 0 end
            local d = p.tdmg and p.tdmg[hb]
            if d == nil then d = (hb == 0) and 180 or 55 end
            return target, d
        end end
        if k == "register_esp_flag"  then return function(_, _, _, _, cb) ESP_FLAGS[#ESP_FLAGS + 1] = cb end end
        if k == "set_event_callback" then return function(name, cb) CALLBACKS[name] = cb end end
        if k == "log"                then return function() end end
        if k == "update_player_list" then return function() end end
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
                if prop == "m_fFlags"           then return 1 end
                if prop == "m_angEyeAngles"     then return 0, p and p.eye or 0, 0 end
                if prop == "m_flPoseParameter"  then CUR = ent; return p and p.pose01 or 0.5 end
                if prop == "m_totalHitsOnServer" then return W.srv_hits end
                if prop == "m_vecMins"          then return -16, -16, 0 end
                if prop == "m_vecMaxs"          then return 16, 16, 72 end
                if prop == "m_vecViewOffset"    then return 0, 0, 64 end
                if prop == "m_nTickBase"        then return W.tick end
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
        return function() end
    end}),
    writefile = function(name, content)
        -- The logger rewrites the whole file each flush; scan only what was
        -- appended since the last write (or everything after a roll/clear).
        local from = LOG_SCANNED[name] or 0
        if #content < from then from = 0 end
        for line in content:sub(from + 1):gmatch("[^\n]+") do
            if line:find("%]%[ERR%]") then ERR_LINES[#ERR_LINES + 1] = line end
        end
        LOG_SCANNED[name] = #content
        LOG_CAPTURE[1] = content
    end,
    readfile  = function() return "" end,
    print = print,
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
    if F then F.STATE_PHYSICS = false end
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
        end
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
            el.a = {"Vulnerability", "Hit memory", "Adaptive engine", "Cheat profiles"}
        end
        -- the same switch in the v6.2 menu (RV_TARGET parity runs)
        if el.kind == "checkbox" and type(el.name) == "string" and el.name:find("Desync Angle", 1, true) then
            el.a = false
        end
    end
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
                              vuln_pref = 7, eng = "bad", samples = "q", gen = "z"}
        DB_T["1888056104"] = "garbage"
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
        for i, c in ipairs(cases) do
            local got = AX.Decide(c[1], c[2], c[3], c[4], c[5], c[6])
            if got ~= c[7] then
                UNIT_FAIL[#UNIT_FAIL + 1] = string.format("AIMX.Decide case %d (hp %d head %d body %d): got %s, expected %s",
                    i, c[1], c[2], c[3], tostring(got), c[7])
            end
        end
        -- calibration: the ragebot predicts 4x our head trace on 5 shots
        local fh0 = AX.CAL.fh
        for _ = 1, 5 do AX.OnFire({aim_th = 50, aim_tb = 40}, 1, 200) end
        if math.abs(AX.CAL.fh - 4) > 0.01 then
            UNIT_FAIL[#UNIT_FAIL + 1] = string.format("AIMX calibration: head factor %.2f after 5 shots at 4x, expected 4", AX.CAL.fh)
        end
        for k in pairs(AX.CAL.head) do AX.CAL.head[k] = nil end
        AX.CAL.fh = fh0
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
        STATS.nl, STATS.gs = nil, nil
        if TC({cheat = "nl", config_conf = 1, config_type = "luasense_beta"}) ~= nil
           or TC({cheat = "gs", config_conf = 1, config_type = "luasense_beta"}) ~= "luasense_beta"
           or TC({config_conf = 1, config_type = "luasense_beta"}) ~= "luasense_beta" then
            UNIT_FAIL[#UNIT_FAIL + 1] = "TrustedCfg: gamesense presets must apply to gs and unknown only"
        end
    elseif not os.getenv("RV_MUST_RUN_V7") and not os.getenv("RV_TARGET") then
        UNIT_FAIL[#UNIT_FAIL + 1] = "CheatTrusts/CHEAT_STATS/TrustedCfg not reachable"
    end
end

for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
fire("console_input", "rv_stats")
fire("console_input", "rv_db")
fire("console_input", "rv_save")
fire("console_input", "rv_engine")
fire("console_input", "rv_perf")
fire("console_input", "rv_perf")
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
