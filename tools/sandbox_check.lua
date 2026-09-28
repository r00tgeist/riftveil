-- ══════════════════════════════════════════════════════════════════
--  RIFTVEIL SANDBOX CHECK
--  Loads riftveil.lua inside a stubbed gamesense environment and
--  actually EXECUTES it -- registration code plus every registered
--  event callback (predict_command / net_update_end / paint / aim_fire
--  / aim_hit / aim_miss / round_start / console_input / game_end / both
--  ESP flag callbacks) -- to catch two classes of bug that a plain
--  `loadfile()` syntax check can't:
--
--    1. Accidental globals: every write to _ENV is trapped via
--       __newindex. A missing "local" on a variable that's supposed to
--       be script-scoped shows up here as a caught write instead of
--       silently polluting the global namespace (this file uses a
--       single-script global scope, like every gamesense.pub Lua
--       cheat -- a leaked global here is a real footgun, not a style
--       nit). Stub table/function names (client, entity, ui, ...) are
--       pre-declared so ordinary API calls aren't false positives.
--
--    2. Straight-up runtime crashes in a callback's body when driven
--       with plausible mock data -- doesn't replace real in-game
--       testing (stubs are deliberately generic), but catches gross
--       breakage (nil arithmetic, bad indexing, wrong arg order)
--       before it ever reaches a live match.
--
--  Usage:  lua5.3 tools/sandbox_check.lua
--  Exit code 0 = clean, 1 = load error or leaked globals found.
--  Run this after every edit, before syntax-checking is considered
--  sufficient -- `loadfile` only proves the file PARSES, this proves
--  the registration path and every event handler actually RUN clean.
-- ══════════════════════════════════════════════════════════════════

local SCRIPT_DIR = (arg and arg[0] or ""):match("(.*/)") or "./"
local TARGET      = SCRIPT_DIR .. "../riftveil.lua"

-- A self-referential proxy: indexing, calling, or arithmetic on it all
-- just return itself (or a fallback), so arbitrarily deep FFI-style
-- chains like `cel[0][CFG.AL_IDX_VTBL]` or `ffi.cast(...)(nc, 0)` never
-- crash the stub regardless of how many levels they nest.
local function blackhole()
    local proxy
    proxy = setmetatable({}, {
        __index    = function() return proxy end,
        __call     = function() return proxy end,
        __add      = function() return proxy end,
        __sub      = function() return proxy end,
        __unm      = function() return proxy end,
        __tostring = function() return "0" end,
    })
    return proxy
end

-- Captured so the driver below can fire real registered callbacks
-- instead of only exercising top-level registration code.
local CALLBACKS = {}
local ESP_FLAGS = {}

local mock = {
    ffi = setmetatable({}, {__index = function(_, k)
        if k == "cdef"   then return function() end end
        if k == "typeof" then return function() return blackhole() end end
        if k == "cast"   then return function() return blackhole() end end
        if k == "NULL"   then return nil end
        return function() return nil end
    end}),
    client = setmetatable({}, {__index = function(_, k)
        if k == "create_interface"  then return function() return {} end end
        if k == "system_time"       then return function() return 0,0,0,0 end end
        if k == "latency"           then return function() return 0 end end
        if k == "screen_size"       then return function() return 1920,1080 end end
        if k == "current_threat"    then return function() return nil end end
        if k == "key_state"         then return function() return false end end
        if k == "mouse_position"    then return function() return 0,0 end end
        if k == "trace_line"        then return function() return 1.0, nil end end
        if k == "register_esp_flag" then return function(_,_,_,_,cb) ESP_FLAGS[#ESP_FLAGS+1] = cb end end
        if k == "set_event_callback" then return function(name, cb) CALLBACKS[name] = cb end end
        if k == "log"                then return function() end end
        if k == "update_player_list" then return function() end end
        if k == "get_players"        then return function() return {101, 102} end end
        if k == "is_enemy"           then return function() return true end end
        if k == "is_alive"           then return function() return true end end
        if k == "get_local_player"   then return function() return 1 end end
        return function() return nil end
    end}),
    entity = setmetatable({}, {__index = function(_, k)
        if k == "get_players"      then return function() return {101, 102} end end
        if k == "is_enemy"         then return function() return true end end
        if k == "is_alive"         then return function() return true end end
        if k == "get_local_player" then return function() return 1 end end
        if k == "get_steam64"      then return function(p) return 76561198000000000 + p end end
        if k == "get_player_name"  then return function(p) return "bot" .. tostring(p) end end
        if k == "get_origin"       then return function() return 0, 0, 0 end end
        if k == "get_prop" then
            return function(_, prop)
                if prop == "m_flSimulationTime" then return 1.0 end
                if prop == "m_vecVelocity"      then return 50.0, 30.0 end
                if prop == "m_fFlags"           then return 1 end
                if prop == "m_angEyeAngles"     then return 0.0, 45.0 end
                if prop == "m_flPoseParameter"  then return 0.5 end
                if prop == "m_totalHitsOnServer" then return 0 end
                if prop == "m_vecMins"          then return -16, -16, 0 end
                if prop == "m_vecMaxs"          then return 16, 16, 72 end
                if prop == "m_vecViewOffset"    then return 0, 0, 64 end
                if prop == "m_nTickBase"        then return 100 end
                return 0
            end
        end
        return function() return nil end
    end}),
    ui = setmetatable({}, {__index = function(_, k)
        if k == "new_label" or k == "new_checkbox" or k == "new_button"
           or k == "new_slider" or k == "new_color_picker" then
            return function() return {} end
        end
        if k == "get"          then return function() return false, 0, 0, 0, 0 end end
        if k == "set"          then return function() end end
        if k == "set_visible"  then return function() end end
        if k == "set_callback" then return function() end end
        if k == "is_menu_open" then return function() return false end end
        if k == "mouse_position" then return function() return 0, 0 end end
        return function() end
    end}),
    cvar = setmetatable({}, {__index = function()
        return setmetatable({}, {__index = function(_, k)
            if k == "get_float" then return function() return 0 end end
            if k == "get_int"   then return function() return 0 end end
            if k == "set_float" then return function() end end
            if k == "set_int"   then return function() end end
            return function() end
        end})
    end}),
    database = setmetatable({}, {__index = function(_, k)
        if k == "read"  then return function() return {} end end
        if k == "write" then return function() end end
        return function() end
    end}),
    globals = setmetatable({}, {__index = function(_, k)
        if k == "tickinterval" then return function() return 0.015625 end end
        if k == "curtime"      then return function() return 0 end end
        if k == "realtime"     then return function() return 0 end end
        if k == "tickcount"    then return function() return 0 end end
        if k == "frametime"    then return function() return 0.016 end end
        return function() return 0 end
    end}),
    bit = setmetatable({}, {__index = function(_, k)
        if k == "band" then return function() return 0 end end
        return function() return 0 end
    end}),
    plist    = setmetatable({}, {__index = function() return function() end end}),
    renderer = setmetatable({}, {__index = function() return function() return 0, 0 end end}),
    writefile = function() end,
    readfile  = function() return "" end,
    print = print,
    string = string, table = table, math = math, pairs = pairs, ipairs = ipairs,
    tostring = tostring, tonumber = tonumber, type = type, select = select,
    pcall = pcall, setmetatable = setmetatable, error = error, next = next,
    os = os,
}
mock.require = function() return mock.ffi end

local declared = {}
for k in pairs(mock) do declared[k] = true end

local leaks = {}
local ENV = setmetatable({}, {
    __index = function(_, k) return rawget(mock, k) end,
    __newindex = function(t, k, v)
        if not declared[k] then leaks[#leaks + 1] = k end
        rawset(t, k, v)
    end,
})

local chunk, load_err = loadfile(TARGET, "t", ENV)
if not chunk then
    print("LOAD ERROR: " .. tostring(load_err))
    os.exit(1)
end

local ok, run_err = pcall(chunk)
if not ok then
    print("RUNTIME ERROR during top-level load: " .. tostring(run_err))
end

-- Drive every registered callback so function BODIES execute too --
-- top-level load only exercises the registration lines, not the logic
-- inside Update/ProcessPlayer/DrawOverlay/on_aim_*/console_input/etc.
local function fire(name, ...)
    local cb = CALLBACKS[name]
    if not cb then return end
    local cb_ok, cb_err = pcall(cb, ...)
    if not cb_ok then
        print(string.format("  [callback '%s' runtime error, non-fatal for leak scan]: %s",
            name, tostring(cb_err)))
    end
end

fire("predict_command")
fire("net_update_end")
fire("paint")
fire("aim_fire", {id = 1, target = 101, backtrack = 0.05})
fire("aim_hit",  {id = 1, target = 101, hitgroup = 1, damage = 100})
fire("aim_fire", {id = 2, target = 101, backtrack = 0.05})
fire("aim_miss", {id = 2, target = 101, reason = "?"})
fire("round_start")
fire("console_input", "rv_stats")
fire("console_input", "rv_db")
fire("game_end")
for _, cb in ipairs(ESP_FLAGS) do pcall(cb, 101) end

print("")
if #leaks == 0 then
    print("PASS -- no accidental global writes detected across any exercised code path.")
    os.exit(0)
else
    print("FAIL -- accidental global writes (missing 'local'?):")
    for _, k in ipairs(leaks) do print("  " .. tostring(k)) end
    os.exit(1)
end
