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
local NO_ENGINE = os.getenv("RV_NO_ENGINE") ~= nil
local PLIST_LOG = {}

-- Functions the scenario is designed to reach. If any of these show zero
-- executed lines, the harness itself is broken and the run fails.
local MUST_RUN = {
    "ProcessPlayer", "DetectVuln", "DetectAA", "CanSeeHead", "CfgAngle",
    "LiveCap", "DynamicMaxYaw", "Extract6Lex", "Update", "SyncFlags",
    "BuildOverlay", "DrawPanel", "FitText", "UpdateDrag", "DrawShiftMarkers",
    "on_aim_fire", "on_aim_hit", "on_aim_miss", "FlushDB", "UpdateEspState",
    "EngineStep", "ENG.Decide", "ENG.Credit", "ENG.Post", "EngSnap",
}

-- ── Mutable world state the mocks read from ──────────────────────────
local TI = 1 / 64
local W = {
    tick = 100, real = 0, srv_hits = 0, threat = 101, menu_open = false,
    players = {
        [101] = {sim = 0, vx = 0, vy = 0, pose01 = 0.5, eye = 45, duck = 0,
                 torso = 70, gfy = 60},
        [102] = {sim = 0, vx = 250, vy = 0, pose01 = 0.5, eye = -30, duck = 0,
                 torso = -10, gfy = -15},
    },
}
local CUR = 101  -- entity whose animstate the FFI proxy currently reports

-- Animstate / animlayer fields returned as real numbers. Anything else
-- indexed on the FFI proxy returns the proxy itself so pointer chains like
-- `cel[0][3]` and `ffi.cast(...)(nc, 0)` never crash the stub.
local function field(k)
    local p = W.players[CUR]
    if k == "duck_amount"      then return p.duck end
    if k == "eye_angles_y"     then return p.eye end
    if k == "torso_yaw"        then return p.torso end
    if k == "goal_feet_yaw"    then return p.gfy end
    if k == "on_ground"        then return true end
    if k == "min_yaw"          then return -58 end
    if k == "max_yaw"          then return 58 end
    if k == "feet_spd_fwd"     then return math.min(1, math.sqrt(p.vx^2 + p.vy^2) / 250) end
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
local LOG_CAPTURE = {}

-- UI elements carry their kind so ui.get returns the right shape.
local function ui_el(kind, a, b, c, d) return {kind = kind, a = a, b = b, c = c, d = d} end

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
        if k == "key_state"          then return function() return false end end
        if k == "trace_line"         then return function() return 1.0, -1 end end
        if k == "eye_position"       then return function() return 0, 0, 64 end end
        if k == "register_esp_flag"  then return function(_, _, _, _, cb) ESP_FLAGS[#ESP_FLAGS + 1] = cb end end
        if k == "set_event_callback" then return function(name, cb) CALLBACKS[name] = cb end end
        if k == "log"                then return function() end end
        if k == "update_player_list" then return function() end end
        return function() return nil end
    end}),
    entity = setmetatable({}, {__index = function(_, k)
        if k == "get_players"      then return function() return {101, 102} end end
        if k == "is_enemy"         then return function() return true end end
        if k == "is_alive"         then return function() return true end end
        if k == "get_local_player" then return function() return 1 end end
        if k == "get_steam64"      then return function(p) return 76561198000000000 + p end end
        -- 102 gets a long Cyrillic name so the panel's UTF-8 width fit runs.
        if k == "get_player_name"  then return function(p)
            if p == 102 then return "Тимур Пшеничный the second" end
            return "bot" .. tostring(p)
        end end
        if k == "get_origin"       then return function(p)
            local s = W.players[p]
            return s and (W.tick * 0.5) or 0, 0, 0
        end end
        if k == "hitbox_position"  then return function() return 100, 0, 64 end end
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
                return 0
            end
        end
        return function() return nil end
    end}),
    ui = setmetatable({}, {__index = function(_, k)
        if k == "new_checkbox"     then return function() return ui_el("checkbox", true) end end
        -- Multiselects start with every item selected, so each module runs.
        if k == "new_multiselect"  then return function(_, _, _, items)
            local sel = {}
            for _, v in ipairs(items) do
                if not (NO_ENGINE and v == "Adaptive engine") then sel[#sel + 1] = v end
            end
            return ui_el("multi", sel)
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
        if k == "mouse_position" then return function() return 0, 0 end end
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
        if k == "band" then return function(a, b) return (a % (2 * b) >= b) and b or 0 end end
        return function() return 0 end
    end}),
    plist    = setmetatable({}, {__index = function(_, k)
        if k == "set" then
            return function(ent, field, value)
                PLIST_LOG[#PLIST_LOG + 1] = string.format("%d\t%s\t%s\t%s", W.tick, tostring(ent), field, tostring(value))
            end
        end
        return function() end
    end}),
    renderer = setmetatable({}, {__index = function(_, k)
        if k == "measure_text"   then return function(_, text) return #tostring(text or "") * 6, 12 end end
        if k == "world_to_screen" then return function() return 500, 500 end end
        return function() end
    end}),
    writefile = function(_, content) LOG_CAPTURE[#LOG_CAPTURE + 1] = content end,
    readfile  = function() return "" end,
    print = print,
    string = string, table = table, math = math, pairs = pairs, ipairs = ipairs,
    tostring = tostring, tonumber = tonumber, type = type, select = select,
    pcall = pcall, setmetatable = setmetatable, error = error, next = next,
    os = os, unpack = table.unpack,
}
mock.require = function() return mock.ffi end

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
        local reason  = reasons[(step // 10) % #reasons + 1]
        fire("aim_fire", {id = id, target = 101, backtrack = 2, hit_chance = 70,
                          extrapolated = (step // 10) % 3 == 0})
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

for _, cb in ipairs(UI_CALLBACKS) do pcall(cb) end
fire("console_input", "rv_stats")
fire("console_input", "rv_db")
fire("console_input", "rv_save")
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

local log_text = table.concat(LOG_CAPTURE, "\n")
local err_lines = {}
for line in log_text:gmatch("[^\n]+") do
    if line:find("%]%[ERR%]") then err_lines[#err_lines + 1] = line end
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
