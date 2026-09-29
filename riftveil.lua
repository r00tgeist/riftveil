-- ════════════════════════════════════════════════════════════════════
--  RIFTVEIL  v7.8  ·  gamesense.pub  ·  unmatched.gg
--  Two-tier memory · config recognition · vulnerability windows
--  Adaptive decision engine · backtrack learning · debug logger
-- ════════════════════════════════════════════════════════════════════
--  Changelog: CHANGELOG.md (newest first).
--
--  SECTIONS, in file order (search for the banner text)
--    DEBUG LOGGER · PERSISTENT DATABASE · CVAR ORIGINALS · FEATURE SET
--    MENU · CONSOLE COMMANDS · CFG · ENUMS · FFI · MATH HELPERS
--    6LEX EXTRACTION · ENGINE HELPERS · DECISION ENGINE · CHOKE ESTIMATION
--    DEFENSIVE TICKBASE TRACKING · OUR TICKBASE GATE · RING BUFFER
--    AA DETECTION · CONFIG RECOGNITION · JITTER PERIOD PREDICTION
--    TORSO CLUSTER · LINE OF SIGHT · ORIGIN EXTRAPOLATION
--    VULNERABILITY DETECTOR · RECORD MANAGEMENT · DB FLUSH · ENGINE STEP
--    PROCESSPLAYER · UPDATE · SHOT FEEDBACK · ESP FLAGS · INFO PANEL
--    CLEANUP · EVENT REGISTRATION
-- ════════════════════════════════════════════════════════════════════

-- Single source of truth for the version string -- the init log line used
-- to hardcode "v2.3" as a separate literal from the header banner above,
-- silently drifting out of sync with every version bump since (it was
-- still printing "v2.3 loaded" at v3.3). Bump this AND the banner comment
-- together; nothing else should hardcode a version number.
local RV_VERSION = "7.9"

local ffi = require "ffi"

-- ══════════════════════════════════════════════════════════════════
--  DEBUG LOGGER
--  writefile / readfile are confirmed global GS API functions.
--  Output: %localappdata%\gamesense\riftveil_debug.txt (append).
--  Structured format: [HH:MM:SS.mmm][LVL][MOD] key=val ...
-- ══════════════════════════════════════════════════════════════════
local LOG_FILE      = "riftveil_debug.txt"
local LOG_PREV_FILE = "riftveil_debug_prev.txt"
-- writefile() only overwrites, so appending means rewriting the whole file.
-- The old logger also re-READ the whole file on every flush, and never
-- capped it (it grew across sessions -- one uploaded log spanned v2.3 to
-- v6.2). Benchmarked: 49.7 MB written to disk to produce a 1.9 MB log over
-- ~5 minutes of play, growing quadratically with session length, all
-- synchronous on the game thread. Now: the file is read once at load and
-- cached (log_disk), flushes are bigger, and once the file passes
-- LOG_ROLL_BYTES it's moved to riftveil_debug_prev.txt and restarted, so
-- the most recent history is always in those two files and every write is
-- bounded by the cap instead of by how long you've been playing.
local LOG_FLUSH_LINES = 2048
-- 512 KB: every flush rewrites the whole file (writefile can't append), so
-- this bounds the size of each synchronous disk write.
local LOG_ROLL_BYTES  = 512000
local log_buf   = {}
local log_total = 0
local log_disk  = readfile(LOG_FILE) or ""

local function ts()
    local h, m, s, ms = client.system_time()
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function flush_log()
    if #log_buf == 0 then return end
    log_disk = log_disk .. table.concat(log_buf, "\n") .. "\n"
    log_buf = {}
    if #log_disk > LOG_ROLL_BYTES then
        writefile(LOG_PREV_FILE, log_disk)
        log_disk = ""
    end
    writefile(LOG_FILE, log_disk)
end

local function clear_log()
    writefile(LOG_FILE, "")
    log_disk = ""; log_buf = {}; log_total = 0
end

local function log_write(level, mod, msg)
    log_buf[#log_buf + 1] = string.format("[%s][%s][%s] %s", ts(), level, mod, msg)
    log_total = log_total + 1
    if #log_buf >= LOG_FLUSH_LINES then flush_log() end
end

-- Module-scoped emit helpers. Use: dbg("6lex", "side=%d", side)
local function dbg(mod, fmt, ...) if select("#", ...) > 0 then log_write("DBG", mod, string.format(fmt, ...)) else log_write("DBG", mod, fmt) end end
local function info(mod, fmt, ...) if select("#", ...) > 0 then log_write("INF", mod, string.format(fmt, ...)) else log_write("INF", mod, fmt) end end
local function warn(mod, fmt, ...) if select("#", ...) > 0 then log_write("WRN", mod, string.format(fmt, ...)) else log_write("WRN", mod, fmt) end end
local function err(mod, fmt, ...)  if select("#", ...) > 0 then log_write("ERR", mod, string.format(fmt, ...)) else log_write("ERR", mod, fmt) end end

-- ══════════════════════════════════════════════════════════════════
--  PERSISTENT DATABASE  (read once at load, written on match end)
--  DB[steam64_str] = {config_type, vuln_pref, bt_pref, hit_rate, kills}
--
--  PER-MATCH STATE  (keyed by steam64, wiped on game_end/level_init)
-- ══════════════════════════════════════════════════════════════════
local DB_KEY   = "riftveil_v1"

-- Saved profiles are validated field by field against this schema: a wrong
-- type (an old version's leftovers, a hand edit, a partial write) used to
-- make NewRec throw on every tick for that player -- silently no resolver
-- for them all match -- and FlushDB throw on the same entry. Found by the
-- v7.4 corrupt-data test. Unknown fields are dropped; a non-table entry
-- is dropped whole.
local function DBNum(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi then return nil end
    return v
end
-- Enemy cheat ids as gamesense/cheat_revealer reports them ("wh" there
-- means no signature seen yet and is not an id).
local CHEAT_IDS = {gs = true, nl = true, nw = true, pd = true, pr = true, ot = true,
                   ft = true, pl = true, ev = true, r7 = true, af = true}
local function CleanDBEntry(e)
    if type(e) ~= "table" then return nil end
    return {
        config_type = type(e.config_type) == "string" and e.config_type or nil,
        vuln_pref   = type(e.vuln_pref)   == "string" and e.vuln_pref   or nil,
        cheat       = CHEAT_IDS[e.cheat] and e.cheat or nil,
        bt_pref     = DBNum(e.bt_pref, 0, 64),
        hit_rate    = DBNum(e.hit_rate, 0, 1),
        samples     = DBNum(e.samples, 0, 1e9),
        kills       = DBNum(e.kills, 0, 1e9),
        gen         = DBNum(e.gen, 0, 1e12),
        eng         = type(e.eng) == "table" and e.eng or nil,
    }
end
local DB = {}
do
    local raw = database.read(DB_KEY)
    if type(raw) == "table" then
        for k, e in pairs(raw) do
            if type(k) == "string" then DB[k] = CleanDBEntry(e) end
        end
    end
end
-- Load generation: bumped once per script load and stamped on every entry
-- FlushDB writes, so the DB can drop its least recently seen profiles
-- instead of growing with every opponent ever met (the whole table is
-- rewritten on each 60s autosave, so its size is a recurring cost).
local DB_GEN   = (tonumber(database.read("riftveil_gen")) or 0) + 1
database.write("riftveil_gen", DB_GEN)
local DB_MAX   = 500
local REC      = {}   -- per-player resolver records this match
local EIDX_S64 = {}   -- [entity_index] = steam64_str, refreshed each tick
local SHOTS    = {}   -- [shot_id] = context snapshot at aim_fire
local DT_HIST  = {}   -- [s64] = simtime-delta samples for DT detection

local function ResetMatchState()
    REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
end

-- Per-frame render cache, filled once per net_update_end (Update()) and read
-- by DrawOverlay (paint fires every rendered frame -- often 5-10x more often
-- than net updates, so anything DrawOverlay can read instead of recompute is
-- a real, multiplicative FPS win, not a micro-optimization).
local LIVE_ENEMIES = {}   -- array of live enemy entindexes, this net_update
-- Bumped whenever resolver state visible on the overlay can have changed
-- (every net update, every shot event); DrawOverlay rebuilds only then.
local STATE_VER = 0
local LAST_SPIKE    = false

-- Periodic DB autosave state. FlushDB previously only ran on match-end/
-- disconnect/shutdown -- a crash, force-quit, or bad server disconnect
-- between those events meant that session's DB updates were never written.
local LAST_DB_SAVE  = 0    -- globals.realtime() of the last periodic autosave

-- Player-list write-through cache. ProcessPlayer used to call plist.set four
-- times per enemy per tick even when nothing had changed; now a field is only
-- written when its value differs from what we last wrote. The cache is
-- dropped once per second (PL_RESYNC_TICKS) and on every reset, so anything
-- that resets the player list behind our back gets corrected within a second.
local PL_CACHE        = {}
local PL_KNOWN        = {}   -- entindexes already seen by update_player_list
local LAST_PL_SYNC    = 0
local PL_RESYNC_TICKS = 64
local function PSet(ent, field, value)
    local c = PL_CACHE[ent]
    if not c then c = {}; PL_CACHE[ent] = c end
    if c[field] == value then return end
    c[field] = value
    plist.set(ent, field, value)
end
local function PApply(ent, force, value, active)
    PSet(ent, "Force body yaw", force)
    PSet(ent, "Force body yaw value", value)
    PSet(ent, "Correction active", active)
    -- High priority is set last on purpose (see v4.0 note): it's the one
    -- field confirmed only through another resolver's usage, not the docs,
    -- so a failure there can't block the correction fields above.
    PSet(ent, "High priority", active)
end

info("db", "loaded with %d entries", (function() local c=0; for _ in pairs(DB) do c=c+1 end; return c end)())

-- ══════════════════════════════════════════════════════════════════
--  CVAR ORIGINALS  (saved before any modification)
-- ══════════════════════════════════════════════════════════════════
local ORIG_INTERP  = cvar.cl_interp:get_float()
local ORIG_RATIO   = cvar.cl_interp_ratio:get_int()
local ORIG_IPOLATE = cvar.cl_interpolate:get_int()

-- ══════════════════════════════════════════════════════════════════
--  FEATURE SET
--  v7.1 removed the four [EXP] switches. Each feature is now fixed on or
--  off from the match-log evidence below; every code path is kept, so a
--  decision is a one-word change here, not a rewrite.
-- ══════════════════════════════════════════════════════════════════
local FEATURE = {
    -- On in all 9 match logs, and the best head rate of any method there:
    -- 50 head hits against 14 resolver misses (78.1%).
    SUPPRESS    = true,
    -- Every logged match (v2.3 to v5.2) ran the per-side L/R table: the
    -- switch did nothing until v5.5, so all recorded results include it.
    ASYMMETRIC  = true,
    -- Off. PredictSide takes its phase from globals.tickcount() minus an
    -- enemy simtime tick, two different clocks, so our own latency shifts
    -- the prediction. And once 4 flips are recorded its elseif shadows
    -- lagcomp, def-tick, spike and yaw-cache even on ticks where it
    -- predicts nothing.
    JITTER_PRED = false,
    -- The v7.0 learner (formerly LEARNING) was replaced in v7.2 by the
    -- DECISION ENGINE, which arbitrates on top of this chain instead of
    -- sitting inside it, and is switched from the menu (Detection >
    -- Adaptive engine).
}

-- ══════════════════════════════════════════════════════════════════
--  MENU  (LUA > B)
--
--  Six rows: title, master switch, detection modules, interpolation,
--  indicators, debug log. Maintenance moved to the console (rv_stats,
--  rv_db, rv_save, rv_reset, rv_wipe, rv_clear), where a misclick
--  can't wipe a profile mid-round.
--
--  Every name carries a hidden "\nriftveil" suffix. gamesense keys saved
--  config values by element name, so a bare "Resolver" in LUA > B would
--  share its value with any other script's element of that name; text
--  after "\n" is never drawn.
--
--  The accent follows gamesense's own Menu color instead of a separate
--  picker: the title and panel always match the rest of the menu.
-- ══════════════════════════════════════════════════════════════════
local MENU_COLOR = (function()
    local ok, ref = pcall(ui.reference, "MISC", "Settings", "Menu color")
    return ok and ref or nil
end)()

local ACCENT = {150, 200, 60}   -- only used if the Menu color reference is missing
local function ReadAccent()
    if not MENU_COLOR then return false end
    local r, g, b = ui.get(MENU_COLOR)
    if type(r) ~= "number" then return false end
    if r == ACCENT[1] and g == ACCENT[2] and b == ACCENT[3] then return false end
    ACCENT[1], ACCENT[2], ACCENT[3] = r, g, b
    return true
end
ReadAccent()

local function TitleText()
    return string.format("\aCDCDCDFFrift\a%02X%02X%02XFFveil\a5C5C5CFF   %s",
        ACCENT[1], ACCENT[2], ACCENT[3], RV_VERSION)
end

local DET_KEYS  = {["Vulnerability"] = "vuln", ["Hit memory"] = "hitmem", ["Desync angle"] = "six",
                   ["Adaptive engine"] = "engine"}
local IND_KEYS  = {["Info panel"] = "panel", ["ESP flags"] = "esp", ["Shift marker"] = "shift"}

local ui_title  = ui.new_label      ("LUA", "B", TitleText())
local ui_on     = ui.new_checkbox   ("LUA", "B", "Resolver\nriftveil")
local ui_detect = ui.new_multiselect("LUA", "B", "Detection\nriftveil", {"Vulnerability", "Hit memory", "Desync angle", "Adaptive engine"})
local ui_tight  = ui.new_checkbox   ("LUA", "B", "Tight interpolation\nriftveil")
local ui_ind    = ui.new_multiselect("LUA", "B", "Indicators\nriftveil", {"Info panel", "ESP flags", "Shift marker"})
local ui_verb   = ui.new_checkbox   ("LUA", "B", "Debug log\nriftveil")

-- First run of the v7.1 layout only. The renamed elements start empty, and
-- the one-time flag keeps this from overriding a choice the user saved
-- into a config afterwards. Desync angle stays off by default: it never
-- produced a single override in the 9 logs, and when it does fire it
-- outranks hit memory and suppress, so turning it on is the user's call.
if not database.read("riftveil_ui_defaults_v71") then
    ui.set(ui_on, true)
    ui.set(ui_detect, {"Vulnerability", "Hit memory"})
    ui.set(ui_tight, true)
    ui.set(ui_ind, {"Info panel", "ESP flags", "Shift marker"})
    database.write("riftveil_ui_defaults_v71", true)
end
-- v7.2: the engine is added to whatever Detection selection already
-- exists, once. It keeps the chain's own pick until shot evidence says
-- otherwise, so it's safe on by default.
if not database.read("riftveil_ui_defaults_v72") then
    local sel, has = ui.get(ui_detect), false
    sel = type(sel) == "table" and sel or {}
    for i = 1, #sel do if sel[i] == "Adaptive engine" then has = true end end
    if not has then
        local copy = {}
        for i = 1, #sel do copy[i] = sel[i] end
        copy[#copy + 1] = "Adaptive engine"
        ui.set(ui_detect, copy)
    end
    database.write("riftveil_ui_defaults_v72", true)
end

-- Multiselect values cached as booleans: ui.get on a multiselect builds a
-- fresh table, and ProcessPlayer/paint would otherwise pay for that on
-- every read. Refreshed by the callbacks below and once per net update.
local DET = {vuln = false, hitmem = false, six = false, engine = false, verbose = false}
local IND = {panel = false, esp = false, shift = false}
local function ReadMulti(ref, keys, out)
    for _, k in pairs(keys) do out[k] = false end
    local sel = ui.get(ref)
    if type(sel) ~= "table" then return end
    for i = 1, #sel do
        local k = keys[sel[i]]
        if k then out[k] = true end
    end
end
local function SyncFlags()
    ReadMulti(ui_detect, DET_KEYS, DET)
    ReadMulti(ui_ind, IND_KEYS, IND)
    DET.verbose = ui.get(ui_verb) == true
end

-- ui.set_callback only fires on a change, never for a value already
-- restored from a saved config when the script loads, so everything with
-- a callback is also run once by hand right after registration.
local TIGHT_APPLIED = nil
local function ApplyTightInterp()
    local want = ui.get(ui_on) and ui.get(ui_tight)
    if want == TIGHT_APPLIED then return end
    local first = TIGHT_APPLIED == nil
    TIGHT_APPLIED = want
    if want then
        pcall(function()
            cvar.cl_interpolate:set_int(0)
            cvar.cl_interp_ratio:set_int(1)
            cvar.cl_interp:set_float(0.031)
        end)
        info("interp", "tight ON")
    elseif not first then
        -- Nothing to restore on the first call: ORIG_* were read from the
        -- live cvars moments ago.
        pcall(function()
            cvar.cl_interpolate:set_int(ORIG_IPOLATE)
            cvar.cl_interp_ratio:set_int(ORIG_RATIO)
            cvar.cl_interp:set_float(ORIG_INTERP)
        end)
        info("interp", "tight OFF")
    end
end

local SUB_ITEMS = {ui_detect, ui_tight, ui_ind, ui_verb}
local function SyncMenu()
    SyncFlags()
    local on = ui.get(ui_on)
    for i = 1, #SUB_ITEMS do ui.set_visible(SUB_ITEMS[i], on) end
    ApplyTightInterp()
end
ui.set_callback(ui_on,     SyncMenu)
ui.set_callback(ui_detect, SyncFlags)
ui.set_callback(ui_ind,    SyncFlags)
ui.set_callback(ui_verb,   SyncFlags)
ui.set_callback(ui_tight,  ApplyTightInterp)
SyncMenu()

-- Forward-declared: the rv_save command and EndMatch both call FlushDB,
-- rv_stats reads ENG; both are defined further down, after what they use.
local FlushDB
local ENG
local PERF   -- see PERFORMANCE PROFILER; rv_perf reads it

-- ══════════════════════════════════════════════════════════════════
--  CONSOLE COMMANDS  (console_input — confirmed cheat event)
--    rv_stats   match stats per player
--    rv_db      permanent DB contents
--    rv_engine  decision engine: audit score, per-player arm beliefs
--    rv_perf    profile: first call starts, second prints time per callback
--    rv_save    save this match's profiles to the DB now
--    rv_clear   wipe log file
--    rv_reset   hard reset match + DB entries for CURRENT enemies only
--    rv_wipe    wipe the ENTIRE permanent DB, every steam64 ever saved
-- ══════════════════════════════════════════════════════════════════
local function EngSummary(rec)
    if not rec.E then return "-" end
    local parts = {}
    for arm, c in pairs(rec.E.all) do
        if c.s + c.f >= 1 then
            local m = ENG.Post(rec.E, arm)
            parts[#parts + 1] = string.format("%s=%d%%(%.1f)", arm, math.floor(m * 100 + 0.5), c.s + c.f)
        end
    end
    table.sort(parts)
    local held = rec.eng_hold and (" hold:" .. rec.eng_hold) or ""
    return (#parts > 0 and table.concat(parts, ",") or "-") .. held
end

-- Returning true suppresses the engine's own command processing (per
-- docs.gamesense.gs/docs/events/console_input) -- without it, rv_* isn't
-- a real concommand, so after we handle it the engine ALSO complains
-- "Unknown command: rv_stats" right below our own output every time.
client.set_event_callback("console_input", function(text)
    local cmd = (text:match("^%s*(%S+)") or ""):lower()

    if cmd == "rv_stats" then
        local out = {"[RIFTVEIL] === MATCH STATS ==="}
        for s64, rec in pairs(REC) do
            local tot = (rec.total_hits or 0) + (rec.total_misses or 0)
            local hr  = tot > 0 and math.floor(rec.total_hits / tot * 100) or 0
            -- Per-condition memory: how many movement states have >=2
            -- confirmed hits of their own, and what side each learned --
            -- shows whether the enemy is actually desyncing differently
            -- per state (different signs) or just needed a few states to warm up.
            local cond_n, cond_parts = 0, {}
            for st, cnt in pairs(rec.hit_count_by_state or {}) do
                if cnt >= 2 and (rec.hit_side_by_state[st] or 0) ~= 0 then
                    cond_n = cond_n + 1
                    cond_parts[#cond_parts+1] =
                        string.format("%s:%+d", st, rec.hit_side_by_state[st])
                end
            end
            -- Per-vuln-type accuracy: vuln_profile has been tracked
            -- (seen/hit per VTYPE) since the vuln-window system shipped,
            -- but was never actually surfaced anywhere -- write-only data.
            -- Exposing it here first as a diagnostic before wiring it into
            -- any live gating decision (like the 6lex trust calibration
            -- did for that signal): need to see real per-type hit ratios
            -- across matches before picking a trust threshold, rather than
            -- guessing one and risking suppressing a type that's actually
            -- fine.
            local vp_parts = {}
            for vt, s in pairs(rec.vuln_profile or {}) do
                if (s.seen or 0) > 0 then
                    vp_parts[#vp_parts+1] = string.format("%s:%d/%d", vt, s.hit or 0, s.seen)
                end
            end
            table.sort(vp_parts)

            out[#out+1] = string.format(
                "  %s | %s | conf:%d%% | %d/%d (%d%%) | head:%d rmiss:%d | 6lex:%d/%d | bt:%d | cfg:%s | cond[%d]:%s | vuln:%s | eng:%s",
                entity.get_player_name(rec.eidx or 0) or s64,
                rec.aa_type, math.floor(rec.conf*100),
                rec.total_hits or 0, tot, hr,
                rec.hit_count, rec.resolver_misses,
                rec.six_agree or 0, (rec.six_agree or 0) + (rec.six_disagree or 0),
                rec.preferred_bt, rec.config_type or "?",
                cond_n, cond_n > 0 and table.concat(cond_parts, ",") or "-",
                #vp_parts > 0 and table.concat(vp_parts, ",") or "-",
                -- Engine: posterior head rate per arm with own evidence,
                -- plus the arm it is holding against the chain, if any.
                EngSummary(rec))
        end
        local A = ENG.AUD
        out[#out+1] = string.format("  engine: %s | shots scored %d | brier %.3f vs base-rate %.3f",
            A.safe and "SAFE MODE (chain only)" or "active", A.n,
            A.n > 0 and A.se_eng / A.n or 0, A.n > 0 and A.se_base / A.n or 0)
        out[#out+1] = string.format("  log lines: %d", log_total)
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD","stats", s)

    elseif cmd == "rv_db" then
        local out = {"[RIFTVEIL] === PERMANENT DB ==="}
        for s64, e in pairs(DB) do
            out[#out+1] = string.format(
                "  %s | cfg:%s | vuln:%s | bt:%s | hr:%d%%(n=%d) | hits:%d",
                s64, e.config_type or "?", e.vuln_pref or "?",
                tostring(e.bt_pref), math.floor((e.hit_rate or 0)*100),
                e.samples or 0, e.kills or 0)
        end
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD","db", s)

    elseif cmd == "rv_engine" then
        -- The decision engine at a glance: its audit, then per player the
        -- arms it has evidence on (posterior head chance, votes) and any
        -- override it is holding against the chain.
        local A = ENG.AUD
        local out = {string.format("[RIFTVEIL] === ENGINE === %s | %s | %d shots scored, brier %.3f vs base-rate %.3f",
            DET.engine and "on" or "off (Detection > Adaptive engine)",
            A.safe and "SAFE MODE: chain only" or "overrides allowed",
            A.n, A.n > 0 and A.se_eng / A.n or 0, A.n > 0 and A.se_base / A.n or 0)}
        for s64, rec in pairs(REC) do
            out[#out+1] = string.format("  %-20s %-3s %s", (entity.get_player_name(rec.eidx or 0) or s64):sub(1, 20),
                rec.cheat or "-", EngSummary(rec))
        end
        -- Cheat layer: votes pooled per enemy cheat, all matches.
        local ids = {}
        for id in pairs(ENG.C) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local parts = {}
            for arm, c in pairs(ENG.C[id]) do
                if c.s + c.f >= 1 then
                    parts[#parts + 1] = string.format("%s=%d%%(%.1f)", arm,
                        math.floor(100 * (c.s + 1) / (c.s + c.f + 2) + 0.5), c.s + c.f)
                end
            end
            table.sort(parts)
            out[#out+1] = string.format("  cheat %-3s %s", id, #parts > 0 and table.concat(parts, ",") or "-")
        end
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD", "engine", s)

    elseif cmd == "rv_perf" then
        -- First call starts measuring, the second prints the report.
        if not PERF.on then
            PERF.Reset()
            PERF.on = true
            client.log(PERF.qpc and "[RIFTVEIL] profiling -- play ~10 s, then run rv_perf again"
                       or "[RIFTVEIL] profiling errors only (no high-resolution timer) -- run rv_perf again")
        else
            PERF.on = false
            local s = PERF.Report()
            client.log(s); log_write("CMD", "perf", s)
        end

    elseif cmd == "rv_save" then
        -- Saves this match's profiles now instead of waiting for match end.
        if FlushDB then FlushDB() end
        client.log("[RIFTVEIL] match profiles saved")

    elseif cmd == "rv_clear" then
        clear_log()
        client.log("[RIFTVEIL] log cleared")

    elseif cmd == "rv_reset" then
        local n = 0
        for s64 in pairs(REC) do DB[s64] = nil; n = n + 1 end
        ResetMatchState()
        client.log(string.format("[RIFTVEIL] reset %d profiles", n))
        info("reset", "%d profiles cleared", n)

    elseif cmd == "rv_wipe" then
        local n = 0; for _ in pairs(DB) do n = n + 1 end
        DB = {}
        database.write(DB_KEY, DB)
        ResetMatchState()
        client.log(string.format("[RIFTVEIL] wiped entire DB (%d entries)", n))
        info("reset", "full DB wipe, %d entries cleared", n)
    else
        return
    end
    return true  -- suppress the engine's "Unknown command" for our own commands
end)

-- ══════════════════════════════════════════════════════════════════
--  CFG  — single tunables table (edit here, not buried in logic)
-- ══════════════════════════════════════════════════════════════════
local CFG = {
    -- Animstate / FFI
    AS_OFFSET    = 0x9960,  -- CCSPlayerAnimState within CBasePlayer
    AL_OFFSET    = 10640,   -- animlayer array offset
    AL_LAYER     = 6,       -- animlayer index carrying 6lex data
    AL_IDX_VTBL  = 3,       -- IClientEntityList vtable slot for GetClientEntity

    -- History
    HIST_SIZE    = 16,      -- pose ring buffer depth
    YAW_BUF      = 6,       -- eye yaw history length for yaw-jitter detection
    TM_HORIZON   = 36,      -- lagcomp lookup table: ticks to keep

    -- Pose
    POSE_SCALE   = 120,     -- m_flPoseParameter[11] → pose: raw*120-60
    DESYNC_CAP   = 58.0,    -- engine max desync angle (degrees)

    -- Confidence
    CONF_MIN     = 0.20,    -- below this: clear correction, don't apply
    CONF_GROW    = 0.20,    -- per-tick confidence gain when jitter detected
    CONF_DECAY   = 0.88,    -- per-tick decay multiplier when quiet
    CONF_ESP     = 0.38,    -- minimum conf to show "resolved" flag/indicator
    -- Override chain gates (were inline literals in ProcessPlayer)
    VULN_MIN     = 0.35,    -- conf needed to apply an open vuln window
    VULN_MIN_AGG = 0.20,    -- ...when the built-in has failed this player's meta
    SUP_MIN      = 0.45,    -- conf needed for suppress on a jitter AA
    SUP_MIN_AGG  = 0.28,    -- ...when meta_aggressive
    SUP_STREAK   = 8,       -- consecutive suppress ticks before a forced pause
    SUP_PAUSE    = 4,       -- ticks the pause lasts, letting shots through
    CONF_LOCK    = 0.65,    -- minimum to write to permanent DB
    VULN_TRUST_MIN_N     = 6,    -- min vuln_profile.seen before a type can be distrusted
    VULN_TRUST_MIN_RATIO = 0.15, -- below this hit/seen ratio (with enough samples), distrust
    VULN_PROBE_EVERY     = 5,    -- while distrusted, let 1 in N through to keep gathering evidence

    -- Detection
    CLUSTER_GAP  = 15,      -- pose delta to split into separate cluster
    POSE_THRESH  = 10,      -- minimum delta between samples to count as flip
    HOLD_STABLE  = 4,       -- ticks same sign = hold AA

    -- Velocity-constrained desync
    -- Fast players can't hold full desync -- body yaw catch-up rate is
    -- limited, so plausible max desync shrinks toward 0 as speed rises.
    -- VEL_CAP_SPD is empirical (borrowed from public resolver logic), not
    -- an engine constant -- tune against observed hit-rate if needed.
    VEL_CAP_SPD  = 580.0,   -- u/s at which velocity-implied cap reaches 0

    -- Spike / latency
    SPIKE_THR    = 0.030,   -- |cur_lat - avg_lat| above this = spike

    -- Defensive tickbase
    DT_THRESH    = 3,       -- simtime ticks ahead = def-tickbase
    DT_WINDOW    = 16,      -- simtime delta history size

    -- Vulnerability windows (thresholds)
    LBY_HIGH     = 20.0,    -- pose must have been above this to count as jitter
    LBY_LOW      = 10.0,    -- pose must drop below this to trigger LBY snap
    CTR_THRESH   = 12.0,    -- pose < this on jitter history = center pass
    STOP_SPD_HI  = 50.0,    -- was moving above this (u/s)
    STOP_SPD_LO  = 8.0,     -- now below this = stop event

    -- Vulnerability window TTLs (base ticks before LC window extension)
    VULN_TTL     = {lby=2, unk=1, stp=3, lnd=2, dck=2, ctr=1, pka=2},

    -- Period prediction
    PERIOD_MIN   = 4,       -- minimum flip samples before trusting the period
    PERIOD_MAX   = 8,       -- maximum believable jitter period (ticks)

    -- Backtrack
    LC_WINDOW_S  = 0.200,   -- sv_maxunlag estimate (seconds)

    -- Config recognition tolerances
    CFG_THRESH   = 0.50,    -- config_conf minimum before applying known angles
    CFG_GAIN     = 0.15,    -- confidence gain per matching recognition
    CFG_TICKS    = 32,      -- rerun recognition every N simtime ticks
    -- Real match log (v2.3, 12min): one player flipped luasense_beta/std/
    -- symmetric 22 times because KNOWN_CFGS profiles sit only 4-9deg apart
    -- and noisy per-tick pose sampling alone tipped the "best match" every
    -- recheck. Require a rival to beat the current pick by this much
    -- (combined L+R error) before RecognizeCfg abandons it.
    CFG_SWITCH_MARGIN = 6.0,

    -- State confidence seeds (first tick for a new player)
    STATE_SEED = {
        standing=0.40, running=0.30, crouch=0.30,
        crouch_moving=0.15, air=0.25, air_crouch=0.15, slowmotion=0.20,
    },

    -- SHOTS table stale-entry prune age (ticks)
    SHOTS_MAX_AGE = 256,
}

-- ══════════════════════════════════════════════════════════════════
--  ENUMS  — named constants replacing bare string keys everywhere
--  Typos in enum references are caught by Lua as nil, not silently
--  matching a wrong string.
-- ══════════════════════════════════════════════════════════════════

-- AA types returned by DetectAA
local AA = {
    UNKNOWN  = "unknown",
    STATIC   = "static",
    HOLD     = "hold",
    TWO_WAY  = "2way",
    THREE_WAY= "3way",
    FIVE_WAY = "5way",
    SKITTER  = "skitter",
}

-- AA types that jitter between positions (suppress only targets these).
local JITTER_AA = {
    [AA.TWO_WAY] = true, [AA.THREE_WAY] = true, [AA.FIVE_WAY] = true,
    [AA.SKITTER] = true, [AA.HOLD] = true,
}

-- Movement states returned by ClassifyState
local STATE = {
    STANDING      = "standing",
    RUNNING       = "running",
    CROUCH        = "crouch",
    CROUCH_MOVING = "crouch_moving",
    AIR           = "air",
    AIR_CROUCH    = "air_crouch",
    SLOWMOTION    = "slowmotion",
}

-- Resolver correction methods (what last_meth gets set to)
local METH = {
    RING      = "ring",
    HIT_MEM   = "hit_mem",
    SIX_LEX   = "6lex",
    PERIOD    = "period",
    LAGCOMP   = "lagcomp",
    PHASE     = "phase",
    DEF_TICK  = "def_tick",
    RING_SPK  = "ring_spike",
    YAW_CACHE = "yaw_cache",
    SYM_FLIP  = "sym_flip",
    SUPPRESS  = "suppress",
    META_HOLD = "meta_hold",  -- meta_aggressive holdover when built-in fails the meta
    TRACK     = "track",      -- engine: pose-tracked side applied as-is
}

-- Vulnerability window types returned by DetectVuln
local VTYPE = {
    LBY = "lby",  -- LBY snap: pose collapsed
    UNK = "unk",  -- unchoke tick: first real packet after burst
    STP = "stp",  -- stop event: velocity crossed zero
    LND = "lnd",  -- landing: on_ground flipped false→true
    DCK = "dck",  -- duck transition: duck_amount crossed 0.5
    CTR = "ctr",  -- jitter center pass: pose near 0 on alt pattern
    PKA = "pka",  -- peek acceleration: stopped -> fast (body yaw hasn't caught up)
}

-- Known config profiles (from luasense_beta/luasensedev analysis)
local KNOWN_CFGS = {
    luasense_beta = {avg_left=26, avg_right=41, tol=6},
    luasense_std  = {avg_left=30, avg_right=38, tol=6},
    symmetric     = {avg_left=35, avg_right=35, tol=8},
}

-- Pre-computed counter angles per state per known config
local CFG_COUNTER = {
    luasense_beta = {
        standing={L=24,R=41}, running={L=24,R=37}, crouch={L=32,R=46},
        crouch_moving={L=22,R=44}, air={L=29,R=35},
        air_crouch={L=18,R=44}, slowmotion={L=23,R=47},
    },
    luasense_std = {
        standing={L=30,R=38}, running={L=28,R=35},
        crouch={L=28,R=40}, crouch_moving={L=24,R=36},
        air={L=26,R=32}, air_crouch={L=20,R=36}, slowmotion={L=26,R=40},
    },
    -- "symmetric" is a recognized KNOWN_CFGS entry (avg_left=35, avg_right=35
    -- above) but had no CFG_COUNTER table, so CfgAngle(..., "symmetric", ...)
    -- always fell through to ASYM_FALLBACK -- angles calibrated for an
    -- asymmetric desync pattern applied to a player we'd already confirmed
    -- desyncs symmetrically. No per-state symmetric data exists, so this
    -- uses the flat 35/35 avg from KNOWN_CFGS.symmetric for every state.
    symmetric = {
        standing={L=35,R=35}, running={L=35,R=35}, crouch={L=35,R=35},
        crouch_moving={L=35,R=35}, air={L=35,R=35},
        air_crouch={L=35,R=35}, slowmotion={L=35,R=35},
    },
}

-- Fallback asymmetric table when no config is recognized
local ASYM_FALLBACK = {
    standing={24,41}, running={24,37}, crouch={32,46},
    crouch_moving={22,44}, air={29,35}, air_crouch={18,44}, slowmotion={23,47},
}

local AA_SHORT = {
    [AA.TWO_WAY]="2way", [AA.THREE_WAY]="3way", [AA.FIVE_WAY]="5way",
    [AA.SKITTER]="skitter", [AA.HOLD]="hold",
    [AA.STATIC]="static",  [AA.UNKNOWN]="?",
}

local HG = {
    "generic","head","chest","stomach",
    "left arm","right arm","left leg","right leg","neck","?","gear",
}

local SKITTER_PAT = {-1,1,0,-1,1,0,-1,0,1,-1,0,1}

-- ══════════════════════════════════════════════════════════════════
--  FFI  — animstate struct + animlayer
--  Offsets verified against luasensedev.lua and luasense_beta.lua.
--  AS_OFFSET and AL_OFFSET named above in CFG.
-- ══════════════════════════════════════════════════════════════════
pcall(ffi.cdef, [[
struct rv_as {
    char p0[24];  float anim_update_timer;
    char p1[12];  float started_moving_time; float last_move_time;
    char p2[16];  float last_lby_time;
    char p3[8];   float run_amount;
    char p4[16];
    void *entity; void *active_weapon; void *last_active_weapon;
    float last_csanim_time; int last_csanim_frame;
    float eye_timer;      float eye_angles_y; float eye_angles_x;
    float goal_feet_yaw;  float current_feet_yaw; float torso_yaw;
    float last_move_yaw;  float lean_amount;
    char p5[4];   float feet_cycle; float feet_yaw_rate;
    char p6[4];   float duck_amount; float landing_duck_amount;
    char p7[4];   float cur_origin[3]; float last_origin[3];
    float velocity_x; float velocity_y;
    char p8[4];   float u1;
    char p9[8];   float u2; float u3; float u4;
    float m_vel; float jump_fall_vel; float clamped_vel;
    float feet_spd_fwd; float feet_spd_unk;
    float last_move_start; float last_move_stop;
    bool  on_ground; bool hit_in_ground_anim;
    char p10[4];  float time_in_air; float last_z;
    float head_from_ground; float stop_to_full_run;
    char p11[4];  float magic;
    char p12[60]; float world_force;
    char p13[458]; float min_yaw; float max_yaw;
};
]])

local al_t = ffi.typeof([[
    struct {
        char pad[24]; uint32_t seq;
        float prev_cycle; float weight; float weight_delta_rate;
        float playback_rate; float cycle;
        void *entity; char pad2[4];
    }**
]])
local cpt  = ffi.typeof("void***")
local aspt = ffi.typeof("struct rv_as **")
local ncfn = ffi.typeof("float(__thiscall*)(void*, int)")

local cel = ffi.cast(cpt,
    client.create_interface("client.dll","VClientEntityList003")
    or error("[RIFTVEIL] VClientEntityList003 not found"))
local get_ent = ffi.cast("void*(__thiscall*)(void*, int)", cel[0][CFG.AL_IDX_VTBL])
local eng = ffi.cast(cpt,
    client.create_interface("engine.dll","VEngineClient014")
    or error("[RIFTVEIL] VEngineClient014 not found"))
local get_nc  = ffi.cast("void*(__thiscall*)(void*)", eng[0][78])

info("ffi", "interfaces acquired")

local function GetPtr(ent)
    local ok, p = pcall(get_ent, cel, ent)
    return (ok and p and p ~= ffi.NULL) and p or nil
end

-- These run every tick per enemy. pcall(fn, args) with named functions
-- instead of pcall(function() ... end): the old form allocated a fresh
-- closure on every call just to capture the arguments.
local function as_read(p) return ffi.cast(aspt, ffi.cast("char*", p) + CFG.AS_OFFSET)[0] end
local function al_read(ptr, idx) return ffi.cast(al_t, ffi.cast("char*", ptr) + CFG.AL_OFFSET)[0][idx] end
local function nc_read() return ffi.cast(cpt, get_nc(eng)) end
local function nc_lat(nc, slot) return ffi.cast(ncfn, nc[0][slot])(nc, 0) end

local function GetAS(ent)
    local p = GetPtr(ent); if not p then return nil end
    local ok, s = pcall(as_read, p)
    return (ok and s) or nil
end

local function GetAL(ptr, idx)
    local ok, al = pcall(al_read, ptr, idx)
    return ok and al or nil
end

local function GetLat()
    local ok, nc = pcall(nc_read)
    if not ok or not nc or nc == ffi.NULL then
        local l = client.latency(); return l, l
    end
    local ok1, cur = pcall(nc_lat, nc, 9)
    local ok2, avg = pcall(nc_lat, nc, 10)
    -- Type-checked before comparing: the vtable call sits inside pcall, the
    -- comparison doesn't. If a game update moved the slot and the call
    -- returned cdata instead of a number, "cur > 0" would throw on every
    -- tick and take the whole Update down with it. (Found by running the
    -- harness under LuaJIT, which, like the game, refuses number-vs-table
    -- comparisons that Lua 5.3 allowed through a metamethod.)
    cur = (ok1 and type(cur) == "number" and cur == cur and cur > 0 and cur < 2) and cur
          or client.latency()
    avg = (ok2 and type(avg) == "number" and avg == avg and avg > 0 and avg < 2) and avg or cur
    return cur, avg
end

-- ══════════════════════════════════════════════════════════════════
--  MATH HELPERS + INPUT VALIDATION
-- ══════════════════════════════════════════════════════════════════
local function Clamp(v, a, b) return math.min(math.max(v, a), b) end
-- A usable number: not nil, not NaN, not +-inf. math.min/max handle NaN
-- differently across Lua builds (Lua 5.3 can return the NaN, LuaJIT's
-- native min/max returns the other operand), so anything headed for Clamp
-- or the history buffers is checked with this first.
local function Finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function Sign(x)        return x > 0 and 1 or (x < 0 and -1 or 0) end
-- Normalize an angle to [-180, 180]. Bounded work for any input: the old
-- subtract-360 loops never terminated on inf (inf - 360 == inf) and
-- effectively never on huge finite values (1e300 - 360 == 1e300) -- one
-- corrupt float from an FFI animstate read would have frozen the game's
-- main thread, where no pcall can reach. Found by the v7.3 fuzzer.
-- Non-finite input maps to 0: no usable angle.
local function NA(a)
    if a ~= a or a == math.huge or a == -math.huge then return 0 end
    if a >= -180 and a <= 180 then return a end
    a = a % 360                      -- [0, 360): Lua's % is floored
    if a > 180 then a = a - 360 end
    return a
end
local function TT(t) return t and math.floor(t / globals.tickinterval() + 0.5) or 0 end

-- isnum: rejects nil, NaN, ±inf, and values beyond plausible game range
local function isnum(v, lo, hi)
    if type(v) ~= "number" or v ~= v or math.abs(v) >= 1e9 then return false end
    if lo and v < lo then return false end
    if hi and v > hi then return false end
    return true
end

-- DynamicMaxYaw: the player's TRUE currently-achievable max desync this
-- tick -- not just the flat engine bound (as.max_yaw), which is the
-- theoretical ceiling regardless of current movement state. The real
-- achievable desync shrinks as a player transitions from stopped to
-- running and while ducking; this formula (a per-tick scale factor
-- derived from stop_to_full_run/feet_spd_fwd/feet_spd_unk/duck_amount,
-- applied to max_yaw) captures that instead of treating max_yaw as a
-- flat constant all the time.
--
-- Found by exploring uploaded reference scripts and cross-checking
-- against RIFTVEIL's own code, not invented: the same formula (down to
-- the exact magic constants -0.3/-0.2) turned up independently in THREE
-- separate real resolver/AA scripts. One of them shares RIFTVEIL's own
-- exact FFI struct layout byte-for-byte -- same 0x9960 base offset, same
-- pad13[0x1CA] position for min_yaw/max_yaw -- strong corroboration this
-- mapping is correct, not a guess. feet_spd_fwd, feet_spd_unk, and
-- stop_to_full_run are three fields RIFTVEIL's own rv_as struct has
-- declared and read every tick since this file's FFI section was
-- written, but never once referenced anywhere else in the file -- dead
-- struct fields, same class of gap as the DetectVuln 3rd-return-value
-- fix earlier in this session.
local function DynamicMaxYaw(as)
    if not as then return nil end
    local duck, fwd, unk, stop, maxyaw =
        as.duck_amount, as.feet_spd_fwd, as.feet_spd_unk, as.stop_to_full_run, as.max_yaw
    if not (isnum(duck) and isnum(fwd) and isnum(unk) and isnum(stop)
            and isnum(maxyaw, 0.5, 90)) then
        return nil
    end
    fwd = Clamp(fwd, 0, 1)
    unk = math.max(unk, 1)
    local factor = (stop * -0.30000001 - 0.19999999) * fwd + 1
    if duck > 0 then
        factor = factor + duck * unk * (0.5 - factor)
    end
    local delta = maxyaw * factor
    return (delta >= 0 and delta < 60) and delta or nil
end

-- LiveCap: reads actual per-player desync bounds from animstate.
-- Confirmed accessible: skeet DLL analysis (Dec 27 2024 build) showed
-- min_yaw / max_yaw fields in rv_as after pad13[0x1CA].
-- Returns (min_yaw, max_yaw, cap) where cap = max of their magnitudes,
-- tightened to DynamicMaxYaw's per-tick estimate when that read succeeds
-- and is smaller -- this can only REDUCE the cap toward what's actually
-- achievable right now, never widen it past the engine's own reported
-- bound, so it's a strictly more conservative correction cap, not a
-- riskier guess.
-- Falls back to CFG.DESYNC_CAP = 58 if the read is invalid or not yet
-- populated (first tick on a new player).
local function LiveCap(as)
    if as then
        local mn = as.min_yaw
        local mx = as.max_yaw
        if isnum(mn, -90, -0.5) and isnum(mx, 0.5, 90) then
            local dyn = DynamicMaxYaw(as)
            local cap = (dyn and dyn < mx) and dyn or mx
            return mn, mx, cap
        end
    end
    return -CFG.DESYNC_CAP, CFG.DESYNC_CAP, CFG.DESYNC_CAP
end

-- ══════════════════════════════════════════════════════════════════
--  6LEX EXTRACTION
--  Primary:  animlayer[6].playback_rate digit[1]==9, d4d5 encodes side
--  Fallback: animlayer[6].weight (same digit pattern — Nek0o technique)
-- ══════════════════════════════════════════════════════════════════
local function Dig(v, i)
    if not isnum(v) then return 0 end
    return math.abs(
        math.floor(math.abs(v) * (10^i)) -
        math.floor(math.abs(v) * (10^(i-1))) * 10
    ) % 10
end

local function Extract6Lex(ptr, live_cap)
    live_cap = live_cap or CFG.DESYNC_CAP
    local al = GetAL(ptr, CFG.AL_LAYER)
    if not al then return 0, 0 end

    local function try(field_val)
        if not isnum(field_val) or field_val == 0 then return 0, 0 end
        if Dig(field_val, 1) ~= 9 then return 0, 0 end
        local d4, d5 = Dig(field_val, 4), Dig(field_val, 5)
        local d45    = d4 * 10 + d5
        local side   = (d45 == 30 and 1) or (d45 == 29 and -1) or 0
        if side == 0 then return 0, 0 end
        -- Clamp to live per-player cap from animstate, not hardcoded 58
        return side, Clamp((-3.4117 * (d4 + d5 * 0.1)) + 98.9393, 0, live_cap)
    end

    local s, d = try(al.playback_rate)
    if s ~= 0 then return s, d end

    -- Weight fallback: the side only; its magnitude is a fixed estimate.
    s = (try(al.weight))
    if s ~= 0 then return s, math.min(35.0, live_cap) end
    return 0, 0
end

-- ══════════════════════════════════════════════════════════════════
--  ENGINE HELPERS
-- ══════════════════════════════════════════════════════════════════
-- (MaxDesync removed — was used to compute max_d which was dead after pick chain refactor)

-- Movement state, matched to how AA builders pick their per-condition
-- config (v7.5 audit of the builders in the reference set):
--   * moving vs still at 5 u/s (builders: 2, 3.63, 10), for standing and
--     for crouching alike (was 20 for crouch-moving: slow crouch-walks
--     read as a still crouch);
--   * slow walk is a KEY in every builder, never a speed band. We can only
--     see speed, so the 5-100 band alone also caught every runner
--     accelerating into a peek or braking out of one -- 38% of a rifle
--     peek-and-stop read as slow walk. Source movement physics separates
--     them: acceleration scales with the target speed (sv_accelerate 5.5:
--     a full run gains 18-21 u/s per tick, a slow walk capped under 100
--     gains at most ~8.6), and friction braking loses 6.5-8 u/s per tick.
--     So inside the band: gaining > 10 u/s/tick is a run; losing > 2
--     u/s/tick keeps the state it is braking from; otherwise slow walk.
-- dv = speed change per tick since the previous sample (nil if unknown).
local function ClassifyState(player, as, spd, dv, prev_state)
    local flags = entity.get_prop(player, "m_fFlags") or 0
    local og    = bit.band(flags, 1) ~= 0
    local duck  = as and (as.duck_amount or 0) > 0.5
    spd = spd or 0
    if not og   then return duck and STATE.AIR_CROUCH  or STATE.AIR           end
    if duck     then return spd > 5 and STATE.CROUCH_MOVING or STATE.CROUCH   end
    if spd >= 100 then return STATE.RUNNING                                    end
    if spd <= 5   then return STATE.STANDING                                   end
    if dv then
        if dv > 10 then return STATE.RUNNING end
        if dv < -2 then
            return (prev_state == STATE.SLOWMOTION) and STATE.SLOWMOTION or STATE.RUNNING
        end
    end
    return STATE.SLOWMOTION
end

-- TrustedCfg: only hand a recognized config_type to CfgAngle once
-- config_conf has actually crossed CFG_THRESH. CFG_THRESH's own comment
-- always said it was "the minimum before applying known angles", but
-- nothing enforced that -- CfgAngle callers used rec.config_type
-- unconditionally, so every mid-recognition config flip (config_conf reset
-- to 0.30 on switch) fed straight into the applied correction angle. Real
-- match log: one player flipped configs 22 times in 12 minutes, each flip
-- changing the standing-state angle by up to 6-11 degrees.
local function TrustedCfg(rec)
    return (rec.config_conf >= CFG.CFG_THRESH) and rec.config_type or nil
end

-- Per-player, per-vuln-TYPE trust gate. vuln_profile (seen/hit per VTYPE)
-- was exposed as a read-only rv_stats/rv_db diagnostic in v4.7 specifically
-- because there wasn't yet a real per-type hit ratio to calibrate a live
-- gate against -- guessing a threshold then would've risked suppressing a
-- type that was actually fine. Same idea as the 6lex agree/disagree
-- calibration (v4.1), applied to this data now that it exists.
--
-- Requires a real minimum sample size before ever distrusting a type
-- (default-trust below that -- identical to pre-v5.2 behavior, so a
-- player with little data is never affected). A distrusted type isn't
-- locked out permanently -- it's probed every VULN_PROBE_EVERY detections
-- so it can recover if the player's actual behavior changes (a config
-- switch mid-match, for instance). This mirrors the existing suppress-
-- streak-cap pattern elsewhere in the file ("after N ticks, pause and
-- let one through") rather than inventing a new self-correction idea.
local function VulnTrusted(rec, vtype)
    local vp = rec.vuln_profile[vtype]
    if not vp or vp.seen < CFG.VULN_TRUST_MIN_N then return true end
    if (vp.hit / vp.seen) >= CFG.VULN_TRUST_MIN_RATIO then return true end
    rec.vuln_probe = rec.vuln_probe or {}
    rec.vuln_probe[vtype] = (rec.vuln_probe[vtype] or 0) + 1
    if rec.vuln_probe[vtype] >= CFG.VULN_PROBE_EVERY then
        rec.vuln_probe[vtype] = 0
        return true
    end
    return false
end

-- Return correction angle for a given side using config knowledge or fallback.
-- Optional cap clamps the static guess to the velocity/live-desync bound
-- (VelCap) so a fast-moving enemy doesn't get an overshoot correction.
local function CfgAngle(side, state, config_type, cap)
    local tbl = config_type and CFG_COUNTER[config_type] and CFG_COUNTER[config_type][state]
    local raw
    if tbl then
        raw = side > 0 and tbl.R or -tbl.L
    else
        -- FEATURE.ASYMMETRIC (fixed on since v7.1, see FEATURE SET): the
        -- per-side L/R fallback table. Off would average it into one
        -- symmetric magnitude for both sides.
        local a = ASYM_FALLBACK[state] or ASYM_FALLBACK[STATE.STANDING]
        if FEATURE.ASYMMETRIC then
            raw = side > 0 and a[2] or -a[1]
        else
            local sym = (a[1] + a[2]) / 2
            raw = side > 0 and sym or -sym
        end
    end
    return cap and Clamp(raw, -cap, cap) or raw
end

-- Velocity-constrained desync: fast players can't hold full desync, so the
-- plausible correction magnitude shrinks toward 0 as speed approaches
-- CFG.VEL_CAP_SPD. Only used to clamp OUR own correction guesses (CfgAngle
-- callers) -- kept separate from LiveCap so a fast mouse turn during a
-- peek isn't misread as body-yaw jitter.
local function VelCap(spd, cap)
    cap = cap or CFG.DESYNC_CAP
    if not isnum(spd, 0) then return cap end
    return Clamp(cap * (1 - spd / CFG.VEL_CAP_SPD), 0, cap)
end

-- (GenAngle removed — override block uses CfgAngle directly;
--  FEATURE.ASYMMETRIC picks ASYM_FALLBACK's per-side values in CfgAngle)

-- ══════════════════════════════════════════════════════════════════
--  DECISION ENGINE  (Detection > Adaptive engine)
--
--  Every detector already produces a correction: the vulnerability
--  windows, 6lex, hit memory, the pose-tracked side (applied as-is by
--  meta hold, inverted by suppress) and the built-in resolver. The legacy
--  chain ranks them by a fixed priority. The engine keeps that ranking as
--  its default and learns, per player and per movement state, when a
--  different candidate is measurably better -- and only then overrides it.
--
--  ARMS. Each source has two orientations: "as" applies its value, "inv"
--  the opposite sign. Suppress is literally pose:inv, so suppress and meta
--  hold share evidence instead of being learned separately. Built-in is a
--  single arm (it has no sign we can see).
--
--  EVIDENCE is shared between detectors. A head hit confirms the applied
--  side, so every candidate present at fire time is scored: agreeing with
--  that side is a success, disagreeing a failure -- a hit memory shot also
--  teaches 6lex, the LBY window and the pose side whether they were right.
--  A resolver miss fails the applied arm fully and spills half a count to
--  every other arm: same side as the miss -> half failure, opposite side
--  -> half success (a miss is weaker evidence than a hit: magnitude and
--  timing also cause misses).
--
--  CONTEXT. Real AA configs pick their side per movement state, so the
--  belief about an arm is a four-level hierarchy, each level a prior for
--  the one below it with a capped weight:
--      log prior  (head rate from the 9 match logs, e.g. suppress 78%)
--    + other players' evidence       (<= GLOBAL_CAP counts, persisted)
--    + this player's other states    (<= STATE_POOL counts)
--    + this player in this state     (full weight)
--  When the enemy's cheat is known (ENEMY CHEAT below), a level sits
--  between global and player: other players on the same cheat, <=
--  CHEAT_CAP votes, persisted. CHEAT_MIN_N of those votes also let an arm
--  act before this player has shots of its own. tools/cheat_sim.lua, 12
--  matches of new opponents at 10 shots each (the logs' average): +0.4
--  points when the cheat decides the AA, +0.15 averaged over worlds where
--  it decides less or nothing, worst -0.01. Small, because the player
--  layer learns within a few shots anyway; the logs' cht= field shows
--  whether real cheats differ more than that.
--  A fresh state borrows the player's general tendency; a state with its
--  own shots speaks for itself. Nothing is double counted: each level is
--  the level above minus what the level below already holds.
--
--  LEGACY ADAPTATION STANDS DOWN. The chain has two adaptive habits of
--  its own: rec.flip inverts the tracked side after certain misses, and
--  the soft reset wipes hit memory after 3 resolver misses. Under the
--  engine both are off (v7.4): with them modelled in engine_sim, the
--  engine's average gain was +0.64 with flip on, +1.76 without, and +1.97
--  once the soft reset also kept hit memory (worst case -0.60).
--
--  WHAT WAS TRIED AND CUT (tools/engine_sim.lua, 10 opponent models):
--  per-shot forgetting, a Page-Hinkley config-change detector (fired 0.45
--  times per stationary player-match), and a coupled sign-accuracy model
--  (theta per source) all scored below this design. The state layer
--  measured neutral: with ~10 shots per movement state per match there is
--  little evidence to separate states before the match ends. It stays,
--  in memory for the session only, because it never scored worse. The audit earned
--  its place: margin 0.04 cut the worst scenario from -1.27 to -0.83 and
--  raised the average from +1.85 to +1.94 points.
--
--  SELF-AUDIT. Every credited shot scores the engine's prediction (Brier
--  score) against a base-rate model that only knows the running head
--  rate. If after AUDIT_MIN shots the engine predicts worse than that
--  baseline by AUDIT_MARGIN, it is miscalibrated for this lobby: it enters
--  safe mode and returns the chain's pick until its score recovers. It
--  keeps learning in safe mode; only its overrides stop.
--
--  DECISION. Greedy on posterior means, deterministic (no RNG, so the
--  debug log explains every choice). A candidate replaces the chain's pick
--  only when P(candidate > pick) > SWITCH_IN under a normal approximation
--  of the Beta posteriors, and only once either the candidate has MIN_OWN
--  observations on this player or the pick has MIN_DEFAULT and is in
--  doubt. An engaged switch holds while P stays above HOLD. With no
--  evidence the engine returns the chain's pick -- tools/engine_sim.lua
--  checks that on 5000 random candidate sets.
-- ══════════════════════════════════════════════════════════════════
ENG = {
    SWITCH_IN    = 0.85,
    HOLD         = 0.65,
    MIN_OWN      = 2,
    MIN_DEFAULT  = 3,
    MISS_SPILL   = 0.5,
    GLOBAL_CAP   = 12,
    CHEAT_CAP    = 12,    -- votes a player borrows from others on the same cheat
    CHEAT_MIN_N  = 6,     -- same-cheat votes that let an arm act without own shots
    STATE_POOL   = 8,     -- votes a state borrows from the player's other states
    FORGET       = 1,     -- per credited shot; 1 = off (see above)
    AUDIT_MIN    = 20,
    AUDIT_MARGIN = 0.04,
    PRIOR_SCALE  = 1,
    DECAY        = 0.5,   -- saved counts on load, and on a soft reset
    DB_KEY       = "riftveil_engine",
    CHEAT_KEY    = "riftveil_engine_cheat",
    -- {prior mean, prior weight} per arm
    PRIOR = {
        ["vuln_delta:as"] = {0.62, 8}, ["vuln_delta:inv"] = {0.38, 4},
        ["vuln_lby:as"]   = {0.64, 8}, ["vuln_lby:inv"]   = {0.36, 4},
        ["vuln_other:as"] = {0.60, 6}, ["vuln_other:inv"] = {0.40, 4},
        ["six:as"]        = {0.60, 4}, ["six:inv"]        = {0.40, 4},
        ["hitmem:as"]     = {0.65, 8}, ["hitmem:inv"]     = {0.35, 4},
        ["pose:as"]       = {0.45, 4}, ["pose:inv"]       = {0.78, 8},
        ["builtin"]       = {0.50, 4},
    },
    ARM = {
        vuln_delta = {"vuln_delta:as", "vuln_delta:inv"},
        vuln_lby   = {"vuln_lby:as",   "vuln_lby:inv"},
        vuln_other = {"vuln_other:as", "vuln_other:inv"},
        six        = {"six:as",        "six:inv"},
        hitmem     = {"hitmem:as",     "hitmem:inv"},
        pose       = {"pose:as",       "pose:inv"},
    },
    -- vuln type -> source
    VULN_SRC = {unk = "vuln_delta", stp = "vuln_delta", pka = "vuln_delta",
                dck = "vuln_delta", lby = "vuln_lby"},
    G   = {},   -- global evidence: [arm] = {s, f}
    C   = {},   -- per enemy cheat: [cheat id] = {[arm] = {s, f}}
    AUD = {n = 0, se_eng = 0, se_base = 0, heads = 0, safe = false},
}

function ENG.Phi(z)
    -- Standard normal CDF, erf approximation (max abs error ~0.003).
    local t = math.sqrt(1 - math.exp(-2 * z * z / math.pi))
    return 0.5 * (1 + (z >= 0 and t or -t))
end

local function EngCell(T, arm)
    local c = T[arm]
    if not c then c = {s = 0, f = 0}; T[arm] = c end
    return c
end

-- Fresh per-player engine state. all = the player's totals per arm,
-- st[state] = the same split by movement state.
function ENG.New()
    return {all = {}, st = {}}
end

-- Posterior mean, variance and the player's own evidence count for one
-- arm, through the four-level hierarchy described above. state may be nil
-- (then the player's totals count in full).
function ENG.Post(E, arm, state)
    local pr = ENG.PRIOR[arm]
    local k  = pr[2] * ENG.PRIOR_SCALE
    local a, b = pr[1] * k, (1 - pr[1]) * k
    local own = E.all[arm]
    local os, of = own and own.s or 0, own and own.f or 0

    -- Same cheat, other players: E.cheat is set once the enemy's cheat is
    -- known (CheatOf). Their evidence is taken out of the global level so
    -- it is not counted twice.
    local cc = E.cheat and ENG.C[E.cheat]
    local c  = cc and cc[arm]
    local cs, cf = c and c.s or 0, c and c.f or 0

    local g = ENG.G[arm]
    if g then
        local gs = math.max(0, g.s - math.max(os, cs))
        local gf = math.max(0, g.f - math.max(of, cf))
        local gn = gs + gf
        if gn > 0 then
            local w = math.min(1, ENG.GLOBAL_CAP / gn)
            a, b = a + gs * w, b + gf * w
        end
    end
    local xn = 0
    if c then
        local xs, xf = math.max(0, cs - os), math.max(0, cf - of)
        xn = xs + xf
        if xn > 0 then
            local w = math.min(1, ENG.CHEAT_CAP / xn)
            a, b = a + xs * w, b + xf * w
        end
    end

    local sc = state and E.st[state] and E.st[state][arm]
    if state then
        local ss, sf = sc and sc.s or 0, sc and sc.f or 0
        local ps, pf = math.max(0, os - ss), math.max(0, of - sf)
        local pn = ps + pf
        if pn > 0 then
            local w = math.min(1, ENG.STATE_POOL / pn)
            a, b = a + ps * w, b + pf * w
        end
        a, b = a + ss, b + sf
    else
        a, b = a + os, b + of
    end
    local n = a + b
    return a / n, a * b / (n * n * (n + 1)), os + of, xn
end

-- cands[1..n] = {arm, val, meth}; d = index of the chain's pick.
-- Returns the index to apply and P(it beats the chain's pick).
function ENG.Decide(rec, cands, n, d, state)
    local E = rec.E
    if ENG.AUD.safe then rec.eng_hold = nil; return d, 0 end
    local dm, dv, dn = ENG.Post(E, cands[d].arm, state)
    local hold = rec.eng_hold
    local best, bestp = d, 0
    for i = 1, n do
        if i ~= d then
            local arm = cands[i].arm
            local m, v, on, xn = ENG.Post(E, arm, state)
            if on >= ENG.MIN_OWN or dn >= ENG.MIN_DEFAULT or xn >= ENG.CHEAT_MIN_N then
                local p = ENG.Phi((m - dm) / math.sqrt(v + dv))
                local need = (arm == hold) and ENG.HOLD or ENG.SWITCH_IN
                if p > need and p > bestp then best, bestp = i, p end
            end
        end
    end
    rec.eng_hold = (best ~= d) and cands[best].arm or nil
    return best, bestp
end

local function EngScale(T, k)
    for _, c in pairs(T) do c.s, c.f = c.s * k, c.f * k end
end

-- Multiply every count the player holds (totals and per state) by k.
function ENG.Fade(E, k)
    k = k or ENG.DECAY
    EngScale(E.all, k)
    for _, T in pairs(E.st) do EngScale(T, k) end
end

local function EngAdd(E, state, arm, ds, df)
    local c = EngCell(E.all, arm)
    c.s, c.f = c.s + ds, c.f + df
    if state then
        local T = E.st[state]
        if not T then T = {}; E.st[state] = T end
        c = EngCell(T, arm)
        c.s, c.f = c.s + ds, c.f + df
    end
    local g = EngCell(ENG.G, arm)
    g.s, g.f = g.s + ds, g.f + df
    if E.cheat then
        local T = ENG.C[E.cheat]
        if not T then T = {}; ENG.C[E.cheat] = T end
        c = EngCell(T, arm)
        c.s, c.f = c.s + ds, c.f + df
    end
end

-- Session-wide Brier audit of the prediction made at fire time.
local function EngAudit(p, head)
    local y = head and 1 or 0
    local A = ENG.AUD
    local base = (A.heads + 1) / (A.n + 2)     -- running head rate, Laplace
    A.n, A.heads = A.n + 1, A.heads + y
    A.se_eng  = A.se_eng  + (p - y) * (p - y)
    A.se_base = A.se_base + (base - y) * (base - y)
    if A.n >= ENG.AUDIT_MIN then
        local worse = (A.se_eng - A.se_base) / A.n
        -- Hysteresis: enter above the margin, leave only once at par.
        if A.safe then A.safe = worse > 0 else A.safe = worse > ENG.AUDIT_MARGIN end
    end
end

-- snap = {arm = applied arm, sign = applied sign (0 for built-in),
--         signs = {[source] = as-is sign of every candidate at fire time},
--         state = movement state at fire time, p = predicted head chance}
-- head = true for a head/neck hit, false for a resolver miss.
function ENG.Credit(rec, snap, head)
    local E, state = rec.E, snap.state
    if snap.p then EngAudit(snap.p, head) end
    if ENG.FORGET < 1 then ENG.Fade(E, ENG.FORGET) end

    if snap.arm == "builtin" or snap.sign == 0 then
        if head then EngAdd(E, state, "builtin", 1, 0) else EngAdd(E, state, "builtin", 0, 1) end
        return
    end
    local sigma, spill = snap.sign, ENG.MISS_SPILL
    if not head then EngAdd(E, state, snap.arm, 0, 1) end
    for src, sg in pairs(snap.signs) do
        local arms = ENG.ARM[src]
        if arms and sg ~= 0 then
            for o = 1, 2 do
                local arm = arms[o]
                local s   = (o == 1) and sg or -sg
                if head then
                    if s == sigma then EngAdd(E, state, arm, 1, 0) else EngAdd(E, state, arm, 0, 1) end
                elseif arm ~= snap.arm then
                    if s == sigma then EngAdd(E, state, arm, 0, spill) else EngAdd(E, state, arm, spill, 0) end
                end
            end
        end
    end
end

local function EngLoadCells(dst, t)
    if type(t) ~= "table" then return end
    for arm, c in pairs(t) do
        if ENG.PRIOR[arm] and type(c) == "table" and isnum(c.s, 0) and isnum(c.f, 0) then
            dst[arm] = {s = c.s * ENG.DECAY, f = c.f * ENG.DECAY}
        end
    end
end

-- Accepts both the v7.3 layout {all=..., st=...} and v7.2's flat
-- {[arm] = {s, f}} (loaded as totals).
function ENG.Load(t)
    local E = ENG.New()
    if type(t) ~= "table" then return E end
    if type(t.all) == "table" or type(t.st) == "table" then
        EngLoadCells(E.all, t.all)
        if type(t.st) == "table" then
            for state, T in pairs(t.st) do
                if type(state) == "string" then
                    local dst = {}
                    EngLoadCells(dst, T)
                    E.st[state] = dst
                end
            end
        end
    else
        EngLoadCells(E.all, t)
    end
    return E
end

local function EngSaveCells(T)
    local out = {}
    for arm, c in pairs(T) do
        if c.s + c.f > 0.01 then out[arm] = {s = c.s, f = c.f} end
    end
    return out
end

-- Only the player's totals are saved. Per-state votes would make each DB
-- profile ~100 small tables -- over a megabyte serialized on every 60 s
-- autosave at the 500-profile cap -- for a layer that measured neutral.
-- They live for the session; Load still reads an st table if one exists.
function ENG.Save(E)
    return {all = EngSaveCells(E.all)}
end

function ENG.SaveGlobal()
    return EngSaveCells(ENG.G)
end

function ENG.SaveCheat()
    local out = {}
    for id, T in pairs(ENG.C) do out[id] = EngSaveCells(T) end
    return out
end

function ENG.LoadCheat(t)
    ENG.C = {}
    if type(t) ~= "table" then return end
    for id, T in pairs(t) do
        if type(id) == "string" then
            local dst = {}
            EngLoadCells(dst, T)
            ENG.C[id] = dst
        end
    end
end

function ENG.Trials(E)
    local n = 0
    for _, c in pairs(E.all) do n = n + c.s + c.f end
    return n
end

do
    local G = ENG.New()
    EngLoadCells(G.all, database.read(ENG.DB_KEY))
    ENG.G = G.all
    ENG.LoadCheat(database.read(ENG.CHEAT_KEY))
end

-- Short label for an arm: "pose:inv" -> "POSE INV", for the panel and log.
function ENG.Label(arm)
    return string.upper((arm:gsub("_", " "):gsub(":as", ""):gsub(":", " ")))
end

-- ══════════════════════════════════════════════════════════════════
--  CHOKE ESTIMATION
-- ══════════════════════════════════════════════════════════════════
-- cur_lat comes from the caller's per-tick ctx (Update() reads it once via
-- GetLat()) instead of this function calling GetLat() itself -- GetLat does
-- 3 pcall-wrapped FFI calls, and calling it once per player per tick instead
-- of once per tick was pure waste (latency isn't a per-player value).
local function ChokedPkts(st_raw, cur_lat)
    if not isnum(st_raw, 0.001) then return 0 end
    local diff = globals.curtime() - st_raw
    if diff < 0 or diff > 2.0 then return 0 end
    return Clamp(TT(math.max(0.0, diff - cur_lat)), 0, 14)
end

-- ══════════════════════════════════════════════════════════════════
--  DEFENSIVE TICKBASE TRACKING
-- ══════════════════════════════════════════════════════════════════
local function TrackDT(s64, st_raw)
    if not DT_HIST[s64] then DT_HIST[s64] = {} end
    local h = DT_HIST[s64]
    h[#h + 1] = st_raw / globals.tickinterval() - globals.tickcount()
    if #h > CFG.DT_WINDOW then table.remove(h, 1) end
end

local function IsDefTick(s64)
    local h = DT_HIST[s64]
    if not h or #h < 6 then return false end
    local ahead = 0
    for _, v in ipairs(h) do if v > CFG.DT_THRESH then ahead = ahead + 1 end end
    return ahead >= math.ceil(#h * 0.65)
end

-- ══════════════════════════════════════════════════════════════════
--  OUR TICKBASE GATE
-- ══════════════════════════════════════════════════════════════════
local brk = {def=0, check=0, ahead=false}
client.set_event_callback("predict_command", function()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then brk.def = 0; brk.check = 0; return end
    local tb = entity.get_prop(me, "m_nTickBase") or 0
    brk.check = math.max(tb, brk.check)
    if math.abs(tb - brk.check) > 64 then brk.def = 0; brk.check = 0 end
    if brk.check > tb then brk.def = math.abs(tb - brk.check) end
    brk.ahead = globals.tickcount() > tb
end)

local function WeDefensive() return brk.ahead and brk.def > 2 and brk.def < 14 end

-- cur_lat/avg_lat/lerp come from the caller's per-tick ctx (Update reads
-- cl_interp once per tick) -- see ChokedPkts.
local function cvar_interp_get() return cvar.cl_interp:get_float() end
local function LCTicks(use_avg, cur_lat, avg_lat, lerp)
    local ti      = globals.tickinterval()
    local lat     = use_avg and avg_lat or cur_lat
    local shift   = WeDefensive() and (brk.def * ti) or 0
    return math.max(0, math.floor((lat + (lerp or 0.031) + shift) / ti))
end

-- ══════════════════════════════════════════════════════════════════
--  BACKTRACK INTERP MANIPULATION
-- ══════════════════════════════════════════════════════════════════
local function RestoreInterp()
    if TIGHT_APPLIED then return end
    pcall(function()
        cvar.cl_interp:set_float(ORIG_INTERP)
        cvar.cl_interp_ratio:set_int(ORIG_RATIO)
    end)
end

-- ══════════════════════════════════════════════════════════════════
--  RING BUFFER
-- ══════════════════════════════════════════════════════════════════
-- Profiled: ~37% of all CPU went to re-scanning this 16-slot buffer. RLen
-- walked every slot and ran ~8x per tick; PoseVar ran 3x per tick on
-- unchanged data. Now: c tracks the fill count (slots are only ever filled,
-- never cleared, so RLen == min(pushes, n) -- identical result, O(1)), and
-- v is a version bumped on every push so per-tick statistics can be
-- memoized. Outputs are unchanged (checked against the v6.8 functions on
-- 200k random histories).
local function RNew(n)    return {b={}, h=0, n=n, c=0, v=0} end
local function RPush(r,v)
    r.h = (r.h % r.n) + 1; r.b[r.h] = v
    if r.c < r.n then r.c = r.c + 1 end
    r.v = r.v + 1
end
local function RGet(r,o)  return r.b[((r.h - o - 1) % r.n) + 1] end
local function RLen(r)    return r.c end

-- ══════════════════════════════════════════════════════════════════
--  AA DETECTION
-- ══════════════════════════════════════════════════════════════════
local function PoseVar(hist)
    if hist._pv_v == hist.v then return hist._pv end
    local cnt, res = hist.c, 0
    if cnt >= 2 then
        local b, h, n = hist.b, hist.h, hist.n
        local sum, sq = 0, 0
        for i = 0, cnt-1 do
            local p = b[((h - i - 1) % n) + 1].p
            sum = sum + p; sq = sq + p*p
        end
        local m = sum / cnt; res = sq/cnt - m*m
    end
    hist._pv_v, hist._pv = hist.v, res
    return res
end

local function MeanSidePose(hist)
    local sl, rl, sr, rr = 0, 0, 0, 0
    for i = 0, RLen(hist)-1 do
        local e = RGet(hist, i)
        if e then
            if e.p < 0 then sl = sl + math.abs(e.p); rl = rl + 1
            elseif e.p > 0 then sr = sr + e.p; rr = rr + 1 end
        end
    end
    return rl > 0 and sl/rl or 0, rr > 0 and sr/rr or 0
end

-- Reuses per-buffer scratch arrays instead of allocating a fresh value list
-- and cluster tables on every call (it ran every tick per enemy). Returned
-- cl is only valid for indices 1..nc and until the next call.
local EMPTY_CL = {}
local function CountClusters(hist)
    local cnt = hist.c; if cnt < 3 then return 0, EMPTY_CL end
    local vals = hist._cv
    if not vals then vals = {}; hist._cv = vals end
    local b, h, n = hist.b, hist.h, hist.n
    for i = 0, cnt-1 do vals[i+1] = b[((h - i - 1) % n) + 1].p end
    for i = cnt+1, #vals do vals[i] = nil end
    table.sort(vals)
    -- Store {center, count, sum} so running average stays correct
    local cl = hist._cc
    if not cl then cl = {}; hist._cc = cl end
    local k = 1
    local c = cl[1]
    if not c then c = {}; cl[1] = c end
    c[1], c[2], c[3] = vals[1], 1, vals[1]
    for i = 2, cnt do
        local v = vals[i]
        if math.abs(v - c[1]) > CFG.CLUSTER_GAP then
            k = k + 1
            c = cl[k]
            if not c then c = {}; cl[k] = c end
            c[1], c[2], c[3] = v, 1, v
        else
            c[2] = c[2] + 1
            c[3] = c[3] + v
            c[1] = c[3] / c[2]  -- true running mean
        end
    end
    return k, cl
end

local function IsSkitter(hist)
    local cnt = RLen(hist); if cnt < 6 then return false end
    local m = 0
    for i = 0, 5 do
        local e = RGet(hist, i)
        if e then
            local exp = SKITTER_PAT[(i % #SKITTER_PAT) + 1]
            if exp == 0 and math.abs(e.p) < 10 then m = m + 1
            elseif exp ~= 0 and Sign(e.p) == exp then m = m + 1 end
        end
    end
    return m >= 4
end

-- BUG (found in senior review pass, previously undetected): the old version
-- reset `stable` to 0 on a sign mismatch but kept scanning OLDER samples
-- instead of stopping there. "Held" is supposed to mean an unbroken run of
-- the same sign ending at the most recent tick -- but if an older, unrelated
-- run of matches (past a real flip) was long enough, it could push `stable`
-- back over CFG.HOLD_STABLE by the end of the loop, e.g. hist signs (newest
-- first) [+, -, +,+,+,+,+] with HOLD_STABLE=4: the flip at offset 1 should
-- disqualify "currently holding" immediately, but the old code kept
-- counting past it and returned true anyway (final stable=5). Fixed to stop
-- at the first mismatch, since anything before a break in the streak is
-- irrelevant to whether the sign is CURRENTLY held.
local function IsHold(hist)
    local cnt = RLen(hist); if cnt < CFG.HOLD_STABLE + 2 then return false end
    local last = RGet(hist, 0); if not last then return false end
    local fs, stable = Sign(last.p), 1  -- start at 1 counting the most recent sample
    for i = 1, math.min(cnt-1, CFG.HOLD_STABLE+2) do
        local e = RGet(hist, i)
        if not e or Sign(e.p) ~= fs then break end
        stable = stable + 1
    end
    return stable >= CFG.HOLD_STABLE
end

-- Returns: aa_type, dominant_side, confidence, pose_sum
local function DetectAA(hist)
    local cnt = RLen(hist); if cnt < 4 then return AA.UNKNOWN, 0, 0, 0 end
    if PoseVar(hist) < 25 then return AA.STATIC, 0, 0.8, 0 end
    if IsHold(hist) then
        local e = RGet(hist, 0); local s = e and Sign(e.p) or 0
        return AA.HOLD, s, 0.65, s * 30
    end
    -- BUG FIX: the old loop compared RGet(i) with RGet(i+1) for i up to
    -- cnt-1. Once the buffer is full, RGet(hist, cnt) wraps around to the
    -- NEWEST sample, so it counted a bogus "flip" between the oldest and
    -- newest samples (not adjacent), inflating conf by up to 1/15 on jitter.
    -- Adjacent pairs are 0..cnt-2. Single pass, no per-index RGet calls.
    local b, h, n = hist.b, hist.h, hist.n
    local prev = b[((h - 1) % n) + 1].p
    local pose_sum, flips = prev, 0
    for i = 1, cnt-1 do
        local p = b[((h - i - 1) % n) + 1].p
        pose_sum = pose_sum + p
        if math.abs(prev - p) > CFG.POSE_THRESH and Sign(prev) ~= Sign(p) then
            flips = flips + 1
        end
        prev = p
    end
    local dom  = Sign(pose_sum)
    local conf = math.min(flips / math.max(cnt-1, 1), 1.0)
    if IsSkitter(hist) then return AA.SKITTER, dom, math.max(conf, 0.6), pose_sum end
    local nc, cl = CountClusters(hist)
    if nc >= 4 then return AA.FIVE_WAY,   dom, conf, pose_sum end
    if nc == 3 then
        if cl[2] and math.abs(cl[2][1]) < 10 then dom = 0 end
        return AA.THREE_WAY, dom, conf, pose_sum
    end
    if nc == 2 then return AA.TWO_WAY, dom, conf, pose_sum end
    return AA.UNKNOWN, dom, conf, pose_sum
end

local function YawSide(yc, eye_y)
    local n = #yc; if n < 2 then return 0 end
    local y1, y2 = NA(yc[n]), NA(yc[n-1])
    local s1, c1 = math.sin(math.rad(y1)), math.cos(math.rad(y1))
    local s2, c2 = math.sin(math.rad(y2)), math.cos(math.rad(y2))
    return Sign(NA(eye_y - NA(math.deg(math.atan2((s1+s2)/2, (c1+c2)/2)))))
end

-- ══════════════════════════════════════════════════════════════════
--  CONFIG RECOGNITION
--  Runs every CFG.CFG_TICKS to match observed asymmetric pose
--  distribution against KNOWN_CFGS profiles.
-- ══════════════════════════════════════════════════════════════════
local function RecognizeCfg(rec, current_type)
    if RLen(rec.hist) < 12 then return nil end
    local al, ar = MeanSidePose(rec.hist)
    if al < 5 or ar < 5 then return nil end  -- need data on both sides
    local best, best_err = nil, 999
    local cur_err, cur_ok = nil, false
    for name, p in pairs(KNOWN_CFGS) do
        local e = math.abs(al - p.avg_left) + math.abs(ar - p.avg_right)
        if name == current_type then
            cur_err, cur_ok = e, e < p.tol * 2
        end
        if e < p.tol * 2 and e < best_err then best_err = e; best = name end
    end
    -- Hysteresis: a still-plausible current pick isn't abandoned for a
    -- rival unless it wins by a real margin -- see CFG_SWITCH_MARGIN.
    if cur_ok and best ~= current_type
       and (cur_err - best_err) < CFG.CFG_SWITCH_MARGIN then
        return current_type
    end
    return best
end

-- ══════════════════════════════════════════════════════════════════
--  JITTER PERIOD PREDICTION
--  Computes median inter-flip gap from flip timestamps.
--  Predicts current side without reading the (possibly corrupted) pose.
-- ══════════════════════════════════════════════════════════════════
local function PredictSide(rec, cur_tc)
    local fl = rec.fl
    if #fl < CFG.PERIOD_MIN then return 0 end
    local gaps = {}
    for i = 2, #fl do
        local g = fl[i] - fl[i-1]
        if g >= 1 and g <= CFG.PERIOD_MAX then gaps[#gaps+1] = g end
    end
    if #gaps < 2 then return 0 end
    table.sort(gaps)
    local period = gaps[math.floor(#gaps / 2) + 1]
    if not period or period < 1 then return 0 end
    rec.period = period
    local since = cur_tc - fl[#fl]
    if since < 0 then return 0 end
    local predicted = (math.floor(since / period) % 2 == 0) and rec.side or -rec.side
    return predicted ~= 0 and predicted or 0
end

-- ══════════════════════════════════════════════════════════════════
--  TORSO CLUSTER  — enemy AA counter helpers
--
--  Modern AA patterns (from lua analysis):
--
--  serenity.lua (NeverLose):
--    lambotruck.numbers.ways("Way Yaw", positions) — cycles N discrete
--    torso positions per unchoke. 3-way = {-off, 0, +off}, 5-way adds
--    ±off/2. Single unchoke reads ONE position; across 5-6 reads the
--    mode cluster is the real dominant side.
--    Edge yaw: raytrace 180° arc → aligns body with cover geometry.
--    Result: torso clusters at one of N angles, edge cases near wall angle.
--
--  aesthetic_bin_oracle.lua (NeverLose v2.1):
--    body_yaw_switch slider: body yaw TURNS OFF for N ticks cyclically.
--    When off, the LBY snap reads as near-zero pose (not a real flip).
--    body_yaw_left/right_random: fakelimit ±X% each unchoke.
--    Records system: arbitrary stored animation sequences, no pattern.
--    result: LBY near-zero snaps look like real flips but aren't.
--
--  ambani_dev.lua (NeverLose):
--    torpedo jitter: alternates between faszsag pose (yawoffset≈0,
--    body yaw OFF, different fakelimits) and normal pose every N ticks.
--    Faszsag unchoke reads torso≈0 — NOT the real desync angle.
--    sanya mode: 3-way every tick, Random every 10th sent_packet.
--    tick body_yaw: ON/OFF at tickspeed with random fakelimit 47-60°
--    and random inverter overrides. Anti-bruteforce: v56.ab.jitteralgo
--    adapts to detected flip patterns.
--
--  ─────────────────────────────────────────────────────────────────
--  BATCH 2 SCRIPTS:
--
--  aesthetic_beta_6483984.lua (NeverLose β):
--    Same architecture as v2.1 but adds BODY YAW DELAY per state:
--      Standing=3t, Crouching=9t, SlowWalk=16t (!), CT/Moving=10t.
--    Body yaw lags behind fake yaw by N ticks — first unchoke reads
--    the MID-DELAY torso position, NOT the settled real angle.
--    "Meta" preset: delay=16t on slowwalk, freestanding_body_yaw=
--    "Peek Real" on CT/Moving. Records system refined with custom
--    base64 key cipher. modifier_random adds noise to offset each tick.
--    Counter: TorsoCluster naturally handles delay by preferring stable
--    cluster centers over transitional mid-delay readings. The settled
--    position forms a cluster; transitional ticks scatter and fail
--    CLUSTER_MIN. Body yaw delay effectively extends the time window
--    before our cluster converges — patience is the counter.
--
--  testarossa.lua (NeverLose, v1.8.0, testarossa.tech):
--    Anti-bruteforce: up to 10 configurable phases. Phase advances when
--    bullet_impact hits within 50 units of local player — meaning EVERY
--    missed shot triggers a phase switch. Each phase has its own
--    yaw_offset_L/R and modifier configuration. Phase resets after
--    configurable timer (default 5s) without being hit.
--    "Delayed Switch" yaw: offset switches at tick_count/2 of the delay
--    window — creates a mid-delay position that looks like neither side.
--    "Custom Way" modifier: cycles 3 offset values every 3 ticks.
--    Edge yaw: raytrace 20° steps, 30-unit range, same as serenity.
--    Counter: meta_aggressive mode fires fewer missed shots (more
--    accurate corrections), reducing AB phase triggers. Suppress when
--    below vuln confidence starves the AB system of bullet_impact events.
--    Lower suppress threshold on meta_aggressive players.
--
--  gasolina_bin_oracle.lua (NeverLose, pui):
--    Delay system: Default (fixed ticks/1.95), Random (min-max),
--    Custom (up to 6 programmable delay slots that cycle).
--    Body yaw modes: Static, Ticks (same as ambani tick_body_yaw),
--    Random (tickcount % random_N == 1).
--    "Bobro" modifier: 7-position exploit-value cycle via get_exploit_
--    values(): {-1, -0.5, -0.33, +0.33, +0.5, +1} × offset, cycling
--    positions 1-7 per unchoke. Counter: CLUSTER_W=7 catches all 7.
--    Random fakelimits: math.random(min, max) per unchoke — makes
--    limit-based resolver assumptions fail. Counter: CLUSTER_THR=25
--    absorbs ±5° random limit variance around the cluster center.
--    Speed-based switch: after N ticks, L/R limit assignments swap.
--    Counter: TorsoCluster averages through limit variance naturally.
--
--  Counter: TorsoCluster accumulates torso readings and returns the mode
--  cluster center instead of the instantaneous value.
--  W=7 covers Bobro's 7-position cycle; THR=25 absorbs random limits.
-- ══════════════════════════════════════════════════════════════════
local CLUSTER_W   = 7   -- readings to keep: covers Bobro's 7-way cycle
local CLUSTER_THR = 25  -- °, within-cluster threshold; 25 absorbs random limit variance
local CLUSTER_MIN = 3   -- minimum members to trust a cluster

local function TorsoCluster(rec, torso)
    local h = rec.torso_hist
    table.insert(h, torso)
    while #h > CLUSTER_W do table.remove(h, 1) end
    if #h < CLUSTER_MIN then return nil end

    -- Find best cluster using candidate-relative circular mean.
    -- Summing raw angle values fails near ±180° (arithmetic mean of [175°, -175°]
    -- gives 0°, not ±180°). Instead sum the NA()-wrapped *difference* from the
    -- candidate center — differences are bounded ±180°, so wrap-around is safe.
    -- Circular mean: center = NA(cand + mean_diff_from_cand)
    local best_ctr, best_cnt = torso, 0
    for _, cand in ipairs(h) do
        local cnt, diff_sum = 0, 0.0
        for _, v in ipairs(h) do
            local diff = NA(v - cand)              -- always within ±180°
            if math.abs(diff) <= CLUSTER_THR then
                cnt      = cnt + 1
                diff_sum = diff_sum + diff
            end
        end
        if cnt > best_cnt then
            best_cnt = cnt
            best_ctr = NA(cand + diff_sum / cnt)  -- circular center
        end
    end

    return best_cnt >= CLUSTER_MIN and best_ctr or nil
end

-- ══════════════════════════════════════════════════════════════════
--  LINE OF SIGHT
--  Cheap trace-based visibility check -- gates the "standing = fully
--  exposed" vuln TTL boost so it doesn't fire on a target standing still
--  behind a window frame or thin wall that just happens to read as
--  stationary via velocity/duck/ground state alone.
--  Fails OPEN (returns true) on any missing data or trace error, so a
--  bad read never costs a TTL boost the old heuristic would've granted.
-- ══════════════════════════════════════════════════════════════════
-- Target endpoint uses entity.hitbox_position(target, 0) -- the REAL head
-- hitbox world position, confirmed against docs.gamesense.gs/docs/api/
-- entity (hitbox id 0 = head; matches the documented "Head Dot ESP"
-- example, which uses this exact call for the same purpose: tracing to
-- where the head hitbox actually is). The old approximation
-- (origin + m_vecViewOffset.z) is close while standing but drifts while
-- crouching/leaning -- view offset and the actual head hitbox don't move
-- in lockstep with every pose, so a trace aimed at "origin + view offset"
-- can clip differently than one aimed at the real hitbox. Falls back to
-- the old approximation only if the hitbox query itself fails (dormant/
-- not-yet-resolved entity this tick) -- same fail-open philosophy as the
-- rest of this function.
-- Source point: client.eye_position() (docs.gamesense.gs/docs/api/client:
-- "x, y, z world coordinates of the local player's eye position") -- the
-- engine's actual eye position, instead of rebuilding it from origin +
-- m_vecViewOffset.z. Same reasoning as the target end: an approximation
-- where the API hands over the real value. Old reconstruction kept as the
-- fallback if the call fails.
local function CanSeeHead(me, target)
    if not me or not target then return true end
    local mx, my, mz
    local ok_eye, ex, ey, ez = pcall(client.eye_position)
    if ok_eye and isnum(ex) and isnum(ey) and isnum(ez) then
        mx, my, mz = ex, ey, ez
    else
        local ox, oy, oz = entity.get_origin(me)
        if not isnum(ox) then return true end
        local _, _, mvz = entity.get_prop(me, "m_vecViewOffset")
        mx, my, mz = ox, oy, oz + (isnum(mvz) and mvz or 64)
    end

    local tx, ty, tz
    local ok_hb, hx, hy, hz = pcall(entity.hitbox_position, target, 0)
    if ok_hb and isnum(hx) and isnum(hy) and isnum(hz) then
        tx, ty, tz = hx, hy, hz
    else
        local ox, oy, oz = entity.get_origin(target)
        if not isnum(ox) then return true end
        local _, _, tvz = entity.get_prop(target, "m_vecViewOffset")
        tx, ty, tz = ox, oy, oz + (isnum(tvz) and tvz or 64)
    end

    local ok, frac, hit = pcall(client.trace_line, me, mx, my, mz, tx, ty, tz)
    if not ok or not isnum(frac) then return true end
    return frac >= 0.98 or hit == target
end

-- ══════════════════════════════════════════════════════════════════
--  ORIGIN EXTRAPOLATION  (SHIFT box only -- purely cosmetic, never feeds
--  resolver decisions: a shift already gates trust via _shift_streak
--  regardless of what this draws)
--  Ported from a standalone "lag comp breaker" ESP tool: projects the
--  reported origin forward by `ticks` using current velocity plus a rough
--  gravity model, stopping at the first solid collision. Wrapped in pcall
--  throughout and falls back to the plain origin on any failure (missing
--  cvar, bad trace) so a bug here can never affect anything but the box's
--  position.
-- ══════════════════════════════════════════════════════════════════
local function ExtrapolateOrigin(player, ox, oy, oz, ticks)
    if not (isnum(ox) and isnum(oy) and isnum(oz)) or ticks <= 0 then return ox, oy, oz end
    local ok, px, py, pz = pcall(function()
        local ti = globals.tickinterval()
        local vx, vy, vz = entity.get_prop(player, "m_vecVelocity")
        vx, vy, vz = vx or 0, vy or 0, vz or 0

        local sv_g, sv_j = 800 * ti, 301 * ti  -- CS:GO defaults, used if the cvars are unavailable
        pcall(function() sv_g = cvar.sv_gravity:get_float() * ti end)
        pcall(function() sv_j = cvar.sv_jump_impulse:get_float() * ti end)
        local gravity = vz > 0 and -sv_g or sv_j

        local cx, cy, cz = ox, oy, oz
        for _ = 1, math.min(ticks, 32) do
            local nx, ny, nz = cx + vx*ti, cy + vy*ti, cz + (vz + gravity)*ti
            local frac = client.trace_line(-1, cx, cy, cz, nx, ny, nz)
            if isnum(frac) and frac <= 0.99 then return cx, cy, cz end
            cx, cy, cz = nx, ny, nz
        end
        return cx, cy, cz
    end)
    if not ok then return ox, oy, oz end
    return px, py, pz
end

-- ══════════════════════════════════════════════════════════════════
--  VULNERABILITY DETECTOR
--  Returns: vtype, correction_angle, confidence  OR  nil, 0, 0
--  rec.prev_* fields must be set from the previous tick.
-- ══════════════════════════════════════════════════════════════════
-- MAJOR BUG (found via a real debug log, not a guess -- see the vuln=stp/
-- unk/pka/dck/lnd/ctr val distributions): every branch below except [LBY]
-- was returning a RAW ABSOLUTE animstate yaw reading (as.torso_yaw,
-- as.goal_feet_yaw, or eye_y itself) as the vuln correction -- but that
-- value goes straight into rec.vuln_val -> override_val -> plist.set(...,
-- "Force body yaw value", ...) with ZERO transformation anywhere in the
-- pipeline (checked ProcessPlayer and the override chain -- nothing adds
-- eye_y back in). [LBY]'s own CfgAngle output proves what that field
-- actually expects: a small SIGNED DESYNC OFFSET (its own KNOWN_CFGS/
-- CFG_COUNTER tables are literally desync magnitudes, ~20-47 degrees,
-- bounded by DESYNC_CAP=58) -- not a full compass-direction world yaw.
-- torso_yaw/goal_feet_yaw/eye_angles_y are all ABSOLUTE angles that swing
-- across the enemy's entire facing direction over a match (-180..180), so
-- returning them directly is a straight type mismatch. Proof this isn't
-- just theoretical: a real log showed type=stp val up to 354.3, type=unk
-- up to 179.9 with 26% of all UNK corrections (178/679 in one log) already
-- exceeding DESYNC_CAP entirely, type=lnd up to 172.8 -- while [LBY]'s own
-- CfgAngle-based val stayed tightly inside 0..47 the entire time, exactly
-- where a real desync amount belongs. The UNK branch even computes the
-- CORRECT quantity for its own threshold check three lines below
-- (`d = NA(torso - eye)`, the signed delta) and then discarded it in favor
-- of the raw torso reading for the actual return value -- an internal
-- self-contradiction within this same function, not just an outside-
-- convention mismatch. Fixed: UNK/STP/PKA/DCK now convert their raw
-- torso/goal_feet_yaw reading into NA(reading - eye), clamped to corr_cap
-- like every other CfgAngle-sourced correction; LND/CTR (which had no
-- torso reading at all, just safe_eye standing in for "body already
-- matches eye") now correctly return 0 -- zero desync -- instead of
-- literally forcing body yaw to whatever absolute direction the enemy's
-- eyes happened to be pointing.
local function DetectVuln(rec, as, pose, eye_y, spd, corr_cap, al6_weight)
    -- Guard: if eye_y is zero or suspiciously small, try last ring buffer entry
    local safe_eye = (math.abs(eye_y) > 1.0) and eye_y
                     or (RLen(rec.hist) > 0 and RGet(rec.hist, 1) and RGet(rec.hist, 1).e)
                     or nil

    -- [LBY] lean body yaw snap: pose collapsed from high to near-zero
    if rec.prev_pose
       and math.abs(rec.prev_pose) >= CFG.LBY_HIGH
       and math.abs(pose) < CFG.LBY_LOW
       and PoseVar(rec.hist) > 25 then
        -- Sign of prev_pose tells us which side was faked.
        -- Positive pose = body leaned right = real position is LEFT.
        -- Use CfgAngle for the OPPOSITE side of the lean — deterministic,
        -- no dependency on eye_y which is still the fake angle at snap time.
        local real_side = -Sign(rec.prev_pose)
        if real_side == 0 then return nil, 0, 0 end
        return VTYPE.LBY, CfgAngle(real_side, rec.state, TrustedCfg(rec), corr_cap), 0.95
    end

    -- [UNK] unchoke tick: first real packet after a choke burst
    if rec.was_choked and rec.cur_choke == 0 then
        local torso = as.torso_yaw
        local gfy   = as.goal_feet_yaw
        if not torso or math.abs(torso) < 1.0 then return nil, 0, 0 end

        -- TORPEDO/FASZSAG COUNTER (ambani_dev):
        -- Torpedo jitter alternates between a "faszsag" defensive pose (yawoffset≈0,
        -- body yaw OFF) and the real desync pose every N ticks. When faszsag fires,
        -- the unchoke reveals torso≈0, which is NOT the real desync. Applying it
        -- zeroes out our correction exactly when we need it most.
        -- Skip: |torso| < 8° → this is a faszsag/defensive pose, wait for next unchoke.
        if math.abs(torso) < 8 then return nil, 0, 0 end

        local d = math.abs(NA(torso - (safe_eye or torso)))

        -- Minimum desync threshold: if torso ≈ eye, unchoke revealed nothing useful.
        -- Scale threshold up if this player has a recent unk miss streak —
        -- their torso_yaw is unreliable for this AA pattern.
        local min_d = 15 + math.min((rec.unk_miss_streak or 0) * 10, 30)
        if d < min_d then return nil, 0, 0 end

        -- Cross-validate: if goal_feet_yaw and torso disagree by > 45°,
        -- torso is mid-transition between fake and real — not reliable yet.
        if gfy and isnum(gfy) and math.abs(NA(gfy - torso)) > 45 then
            return nil, 0, 0
        end

        -- WAYS()/SANYA COUNTER (serenity, ambani_dev):
        -- lambotruck.ways() and sanya cycle through N discrete positions. A single
        -- unchoke reads whichever position the cycle landed on — could be any of 5.
        -- TorsoCluster accumulates readings and returns the dominant cluster center,
        -- which is the most-common real body position across the cycling pattern.
        -- If no stable cluster yet, fall back to the raw torso reading.
        local cluster_val    = TorsoCluster(rec, torso)
        local correction_abs = cluster_val or torso
        local conf           = cluster_val and 0.93 or 0.90  -- higher conf when clustered

        -- Convert the absolute torso/cluster reading into a signed desync
        -- DELTA relative to eye_y -- see the note above DetectVuln. Without
        -- safe_eye (rare -- both eye_y and the ring buffer fallback failed)
        -- there's nothing to compute a delta against, so bail rather than
        -- return a meaningless absolute value.
        if not safe_eye then return nil, 0, 0 end
        local correction = Clamp(NA(correction_abs - safe_eye), -corr_cap, corr_cap)

        -- LIVE CAP BOOST: when animstate min/max_yaw are populated and the
        -- correction (now a proper desync delta, not an absolute yaw) falls
        -- within the actual engine-reported desync bounds, it's a validated
        -- read. Modest boost from 0.90→0.92 / 0.93→0.96 — not a guarantee,
        -- just extra signal. Skeet DLL analysis confirmed min_yaw/max_yaw
        -- are accessible from animstate. (This check compared an ABSOLUTE
        -- torso reading against a desync-magnitude cap before the fix above
        -- -- same bug, one level down -- so it would rarely trigger unless
        -- the enemy happened to be looking near world yaw 0.)
        if rec.live_min and rec.live_max
           and isnum(rec.live_min, -90, -0.5) and isnum(rec.live_max, 0.5, 90) then
            local abs_c = math.abs(correction)
            local cap   = math.max(math.abs(rec.live_min), rec.live_max)
            if abs_c <= cap + 5 then   -- within live cap range (±5° tolerance)
                conf = cluster_val and 0.96 or 0.92
            end
        end

        -- SETTLED-STATE CROSS-CHECK (animlayer[6].weight): a real neverlose
        -- resolver's find_desync_side treats weight==0/1 as "movement layer
        -- fully settled, no active blend" -- an independent confirmation
        -- that torso_yaw isn't caught mid-transition between fake and real,
        -- distinct from the playback_rate digits 6lex reads off the same
        -- layer. Same modest-boost pattern as the live-cap check above, not
        -- a hard requirement -- al6_weight is nil whenever the FFI read fails.
        if al6_weight and (al6_weight <= 0.001 or al6_weight >= 0.999) then
            conf = math.min(conf + 0.02, 0.97)
        end

        return VTYPE.UNK, correction, conf
    end

    -- [STP] stop event: velocity crossed from high to low.
    -- FAKELAG BURST GUARD (gasolina fluctuate_fakelag, ambani):
    -- fluctuate_fakelag alternates fakelag 1↔14 every 5 ticks, sending a burst of
    -- 14 ticks at once. This creates an artificial velocity spike (high→low) at the
    -- burst boundary that looks exactly like a real stop event but isn't.
    -- Require BOTH prev_spd (1 tick ago) and prev_spd2 (2 ticks ago) to be above
    -- STOP_SPD_HI — a real stop persists; a fakelag burst collapses in 1 tick.
    if rec.prev_spd  and rec.prev_spd  >= CFG.STOP_SPD_HI
    and rec.prev_spd2 and rec.prev_spd2 >= CFG.STOP_SPD_HI then
        if (spd or 0) < CFG.STOP_SPD_LO then
            local gfy = as.goal_feet_yaw or safe_eye
            if not gfy or math.abs(gfy) < 1.0 then return nil, 0, 0 end
            if not safe_eye then return nil, 0, 0 end
            -- gfy is an absolute world yaw (see the note above DetectVuln) --
            -- convert to a signed desync delta relative to eye before
            -- returning it as the correction, same as every other branch.
            return VTYPE.STP, Clamp(NA(gfy - safe_eye), -corr_cap, corr_cap), 0.80
        end
    end

    -- [PKA] peek acceleration: velocity crossed from confirmed-stopped to fast
    -- (the mirror of STP). Modern AA delays body yaw behind the fake yaw by
    -- several ticks after a peek starts (aesthetic_beta: 3-16t depending on
    -- state) — right at peek onset, torso_yaw is still showing whatever it
    -- settled on while stopped, before the delay catches up to the new fake
    -- angle. Require 2 consecutive low-velocity ticks beforehand (same
    -- fakelag-burst guard as STP, mirrored) so a burst spike can't fake it.
    if rec.prev_spd  and rec.prev_spd  <= CFG.STOP_SPD_LO
    and rec.prev_spd2 and rec.prev_spd2 <= CFG.STOP_SPD_LO
    and (spd or 0) >= CFG.STOP_SPD_HI then
        local torso = as.torso_yaw
        -- Skip near-zero: faszsag/defensive-pose torso reads are as unreliable
        -- here as they are for UNK (see torpedo counter above).
        if torso and math.abs(torso) >= 8 and safe_eye then
            -- torso is an absolute world yaw -- convert to a signed desync
            -- delta relative to eye, same as every other branch.
            return VTYPE.PKA, Clamp(NA(torso - safe_eye), -corr_cap, corr_cap), 0.75
        end
    end

    -- [LND] landing: on_ground flipped false → true
    if rec.prev_onground == false and as.on_ground == true then
        if not safe_eye then return nil, 0, 0 end
        -- No torso reading available here -- this branch only ever had
        -- safe_eye (the eye angle itself), which was being returned
        -- directly as the correction: forcing body yaw to whatever
        -- absolute compass direction the enemy's eyes happened to point,
        -- not a desync amount. Landing is a "body yaw caught up" signal,
        -- i.e. body should match eye right now -- which in the signed-
        -- delta convention every other branch uses is 0, not eye_y itself.
        return VTYPE.LND, 0, 0.85
    end

    -- [DCK] duck transition: duck_amount crossed 0.5.
    -- DCK COOLDOWN (aesthetic_beta, gasolina fake_duck):
    -- fake_duck generates rapid duck_amount crossings every ~4 ticks. Without a
    -- cooldown, DCK floods the correction with low-confidence readings (0.78) and
    -- drowns out higher-quality UNK and LBY corrections. Cap at 1 DCK per 10 ticks.
    local dn, dp = as.duck_amount or 0, rec.prev_duck or 0
    local cross  = 0.5
    if (rec._dck_cooldown or 0) > 0 then  -- luacheck: ignore 542
        -- cooldown ticking — decrement only, no DCK this tick
    elseif (dp < cross and dn >= cross) or (dp >= cross and dn < cross) then
        local torso = as.torso_yaw or safe_eye
        if torso and math.abs(torso) >= 1.0 and safe_eye then
            rec._dck_cooldown = 10   -- set before returning so it persists
            -- torso is an absolute world yaw (falls back to safe_eye, which
            -- would correctly yield a 0 delta below) -- convert to a signed
            -- desync delta relative to eye, same as every other branch.
            return VTYPE.DCK, Clamp(NA(torso - safe_eye), -corr_cap, corr_cap), 0.78
        end
    end

    -- [CTR] jitter center pass: high variance history, pose near 0
    if PoseVar(rec.hist) > 60
       and math.abs(pose) < CFG.CTR_THRESH
       and rec.prev_pose and math.abs(rec.prev_pose) >= 18 then
        if not safe_eye then return nil, 0, 0 end
        -- Same as [LND]: no torso reading here, only safe_eye standing in
        -- for "body already matches eye" -- the correct delta for that is
        -- 0, not the absolute eye angle itself.
        return VTYPE.CTR, 0, 0.72
    end

    return nil, 0, 0
end

-- ══════════════════════════════════════════════════════════════════
--  RECORD MANAGEMENT
--
--  REC FIELD DOCUMENTATION
--  ──────────────────────────────────────────────────────────────────
--  Field             Type        Range       Writer
--  .hist             ring buf    –           Update (SamplePlayer)
--  .tm[tick]         table       –           Update (SamplePlayer)
--  .yc[]             array       –           Update (SamplePlayer)
--  .fl[]             array       simtime tk  Update (ClassifyPlayer)
--  .side             int         -1/0/1      Update (ClassifyPlayer)
--  .period           int         0..8        PredictSide
--  .conf             float       0..1        Update (ClassifyPlayer)
--  .aa_type          string(AA)  enum        DetectAA
--  .flip             bool        –           on_aim_miss
--  .lt               int         simtime tk  Update (gate)
--  .hit_side         int         -1/0/1      on_aim_hit
--  .hit_count        int         0..         on_aim_hit
--  .resolver_misses  int         0..         on_aim_miss
--  .def_tickbase     bool        –           IsDefTick
--  .six_side         int         -1/0/1      Extract6Lex
--  .six_desync       float       0..58       Extract6Lex
--  .state            string(STATE) enum      ClassifyState
--  .config_type      string/nil  –           RecognizeCfg
--  .config_conf      float       0..1        Update
--  .bt_hist          table       depth→cnt   on_aim_hit
--  .preferred_bt     int         0..16       on_aim_hit
--  .vuln_profile     table       vtype→{s,h} Update/on_aim_hit
--  .vuln_pref        string/nil  VTYPE enum  on_aim_hit
--  .vuln_ttl         int         0..         Update
--  .vuln_type        string/nil  VTYPE enum  DetectVuln
--  .vuln_val         float       degrees     DetectVuln
--  .vuln_conf        float       0..1        DetectVuln (per-detection
--                                             confidence -- DetectVuln's
--                                             3rd return value was being
--                                             silently dropped by its call
--                                             site until the wiring audit
--                                             below; now stored here and
--                                             logged, diagnostic only)
--  .prev_pose        float/nil   –           Update (save phase)
--  .prev_spd         float/nil   u/s         Update (save phase)
--  .prev_duck        float       0..1        Update (save phase)
--  .prev_onground    bool/nil    –           Update (save phase)
--  .cur_choke        int         0..14       Update
--  .was_choked       bool        –           Update
--  .kills            int         0..         on_aim_hit (misnomer: counts
--                                             every confirmed hit, any
--                                             hitgroup -- not eliminations;
--                                             see note in on_aim_hit)
--  .eidx             int         entity idx  GetRec
--  .active           bool        –           Update (apply phase)
--  .resolved         bool        –           Update (apply phase)
--  .last_val         float       degrees     Update (apply phase)
--  .last_meth        string(METH) enum       Update (apply phase)
-- ══════════════════════════════════════════════════════════════════
-- Keys of players identified as bots (get_steam64 == 0). Bots don't use
-- anti-aim desync, so forcing a body yaw on one can only hurt; EmberLash
-- (steam64 == 0) and tsv4 (GameStateAPI.IsFakePlayer) both skip them too.
local BOT_KEYS = {}

local function GetS64(player)
    local s64 = entity.get_steam64(player)
    if s64 and s64 ~= 0 then
        -- %.0f, never tostring: gamesense returns the 32-bit account id
        -- (real logs: s64=1888056751), for which both print the same
        -- digits. But a full 64-bit id held in a double prints as
        -- "7.6561198e+16" through tostring -- every player would share one
        -- profile and one DB entry. Found when the harness ran on LuaJIT.
        local k = (type(s64) == "number") and string.format("%.0f", s64) or tostring(s64)
        EIDX_S64[player] = k; return k
    end
    local n = entity.get_player_name(player)
    if n and n ~= "" and n ~= "unknown" then
        local k = "n:" .. n; EIDX_S64[player] = k
        if s64 == 0 then BOT_KEYS[k] = true end
        return k
    end
    return nil
end

local function NewRec(player, s64)
    -- Re-validated here too: DB is also written at runtime (rv_ commands,
    -- FlushDB), and this is the one place a bad entry would take a player
    -- out of the resolver.
    DB[s64] = CleanDBEntry(DB[s64])
    local db = DB[s64] or {}
    -- DB-seeded confidence: a proven prior against this steam64 (3+ confirmed
    -- HITS -- despite the field's name, .kills has counted every confirmed
    -- bullet hit since on_aim_hit was written, not actual eliminations; see
    -- the field-name note in on_aim_hit -- with a decent hit rate) skips the
    -- cold-start ramp so short 2v2 engagements don't end before CONF_MIN is
    -- even reached. Capped well below CONF_LOCK -- a prior is a hint, not
    -- this round's evidence.
    local seeded_conf = 0
    if (db.kills or 0) >= 3 and (db.hit_rate or 0) > 0.5 then
        seeded_conf = math.min(db.hit_rate * 0.5, 0.35)
    end
    return {
        hist=RNew(CFG.HIST_SIZE), tm={}, yc={}, fl={},
        side=0, period=0, conf=seeded_conf,
        aa_type=AA.UNKNOWN, flip=false, lt=-1,
        hit_side=0, hit_count=0, resolver_misses=0,
        -- Per-CONDITION hit memory: hit_side/hit_count above are a single
        -- global value, but real AA configs (confirmed in vandal.lua's own
        -- local-AA menu -- 8 independent per-state desync configs: default/
        -- standing/moving/in air/slowwalking/crouching/crouch moving/crouch
        -- in air, each with its own yaw/side) switch which side they desync
        -- on purely based on movement state. A single hit_side gets
        -- overwritten every time the enemy changes state, so memory learned
        -- while they were standing actively causes misses the moment they
        -- start moving. Keyed by the exact same STATE.* strings ClassifyState
        -- already produces (rec.state), so no new state machine is needed --
        -- see on_aim_hit (write), on_aim_miss (per-state invalidation on a
        -- hit_mem miss), and the [3] override branch below (read, falls back
        -- to the global hit_side/hit_count above when this state has no data
        -- yet).
        hit_side_by_state={}, hit_count_by_state={},
        -- Per-player 6lex trust calibration (inspired by vandal.lua's
        -- per-opponent learning, but validated against confirmed head/neck
        -- hits instead of misses -- a hit proves which side was actually
        -- real; a miss doesn't). Doesn't touch the extraction formula
        -- itself, only how much the override block trusts its output for
        -- THIS specific player -- see on_aim_hit and the 6lex override gate.
        six_agree=0, six_disagree=0,
        -- True match totals -- every real (non-discarded) hit/miss outcome,
        -- unlike hit_count (head/neck-confirmed only, drives hit_mem) and
        -- resolver_misses (non-vuln only, drives soft-reset). The panel
        -- header reads these, not those, so it shows what it claims to.
        total_hits=0, total_misses=0,
        def_tickbase=false,
        six_side=0, six_desync=0, state=STATE.STANDING,
        config_type=db.config_type or nil,
        config_conf=db.config_type and 0.5 or 0,
        bt_hist={}, preferred_bt=db.bt_pref or 0,
        vuln_profile={}, vuln_pref=db.vuln_pref or nil,
        vuln_ttl=0, vuln_type=nil, vuln_val=0, vuln_conf=0,
        cheat=db.cheat,   -- enemy cheat id (CheatPoll), saved per steam64
        -- Decision engine (see DECISION ENGINE). E = per-arm evidence,
        -- saved per steam64 and halved on load. eng_arm/eng_sig/eng_by
        -- describe the decision in effect (copied into each shot at
        -- aim_fire); eng_c is the reused candidate list.
        E = ENG.Load(db.eng), eng_hold = nil,
        eng_arm = nil, eng_by = false, eng_sig = {}, eng_c = {}, _eng_logged = false,
        -- DB entry as it was when this match started; FlushDB merges into
        -- this, never into the live DB[s64] (see the autosave fix there).
        db_base = DB[s64],
        prev_pose=nil, prev_spd=nil, prev_duck=nil, prev_onground=nil,
        cur_choke=0, was_choked=false, unk_miss_streak=0,
        kills=0, eidx=player,
        active=false, resolved=false, last_val=0, last_meth=METH.RING,
        -- Meta-aggressive override (built-in failing the current AA meta)
        builtin_miss_streak = 0,   -- consecutive misses while built-in was in control
        meta_aggressive     = false, -- true once built-in fails twice on same player
        -- Torso history cluster (for ways()/sanya/torpedo pattern counters)
        torso_hist = {},           -- rolling window of unchoke torso readings
        -- STP: require 2 consecutive low-velocity ticks to prevent fakelag burst false positives
        -- (gasolina fluctuate_fakelag alternates fakelag 1→14, creating false stop events)
        prev_spd2  = nil,          -- velocity from 2 ticks ago; both must be < STOP_SPD_LO
        -- DCK: cooldown prevents fake_duck spam flooding correction with DCK readings
        -- (aesthetic/gasolina use fake_duck as a meta exploit with rapid duck transitions)
        _dck_cooldown = 0,         -- ticks remaining before next DCK vuln allowed
        -- Suppress streak: cap consecutive suppress ticks to prevent stuck-suppress pattern
        -- (from log: hxlw1ss had 375/914 corrections as suppress — mid-conf lock-in)
        _sup_streak = 0,           -- consecutive ticks suppress has been active
        _sup_pause  = 0,           -- ticks into the post-cap pause window (0..4)
        -- Shifting guard: counts consecutive choke==0 ticks where the LC lookback
        -- (rec.tm) is missing a slot it should have. Real packet loss shows up as
        -- choke>0; a gap despite choke==0 means the backtrack record was broken
        -- (shift-style), not lost -- don't trust LAGCOMP/PHASE while this is high.
        -- Also set directly (to 3) by a same-tick origin teleport >64 units on a
        -- clean update -- see the origin-jump check in ProcessPlayer.
        _shift_streak = 0,
        prev_origin_x = nil, prev_origin_y = nil, prev_origin_z = nil,
        prev_origin_tick = nil,  -- for the origin-jump shift check + box extrapolation
        _shift_flash = 0,  -- 0..1, decayed in DrawOverlay; world-space "SHIFT" tag alpha
        _shift_box = nil,  -- {x,y,z} extrapolated origin, drawn as a wireframe while _shift_flash > 0
        -- Blind-guess brute cycle: index into the last-resort NIXWARE-style
        -- shot-cycle fallback (meta_aggressive with zero side data). _brute_half
        -- marks the half-magnitude phase of that cycle.
        _brute_idx = 0,
        _brute_half = false,
    }
end

local function GetRec(player)
    local s64 = GetS64(player); if not s64 then return nil end
    if not REC[s64] then
        REC[s64] = NewRec(player, s64)
        REC[s64].E.cheat = REC[s64].cheat
        info("rec", "new profile player=%s s64=%s",
             entity.get_player_name(player) or "?", s64)
    end
    REC[s64].eidx = player
    return REC[s64], s64
end

local function ClearEnt(player)
    PApply(player, false, 0, false)
    local s64 = EIDX_S64[player]
    if s64 and REC[s64] then
        REC[s64].active = false; REC[s64].resolved = false
    end
end

-- ══════════════════════════════════════════════════════════════════
--  ENEMY CHEAT  (feeds the engine's cheat layer)
--
--  RIFTVEIL does not read voice packets itself. When the cheat revealer
--  script runs alongside it, it registers package.preload
--  ["gamesense/cheat_revealer"] with get_cheat(ent) / has_data(ent), and
--  we read that once a second. Nothing is required unless it is already
--  registered, so without the revealer this is a table lookup every 10 s.
--
--  What the id does: the engine pools evidence per cheat across every
--  player met on it (ENG.C, persisted), so a new enemy on a cheat whose
--  AA the engine has already learned starts from that instead of from the
--  lobby-wide average. No per-cheat angles are hand-coded -- nothing in
--  the logs says what they would be; the layer learns them.
-- ══════════════════════════════════════════════════════════════════
local CHEAT_MODNAME = "gamesense/cheat_revealer"
local CHEAT_MOD, CHEAT_NEXT_LOOK = nil, 0

local function CheatModule(now)
    if CHEAT_MOD then return CHEAT_MOD end
    if now < CHEAT_NEXT_LOOK then return nil end
    CHEAT_NEXT_LOOK = now + 10
    if type(package) ~= "table" then return nil end
    local m = type(package.loaded) == "table" and package.loaded[CHEAT_MODNAME] or nil
    if not m and type(package.preload) == "table" and package.preload[CHEAT_MODNAME] then
        local ok, r = pcall(require, CHEAT_MODNAME)
        if ok then m = r end
    end
    if type(m) == "table" and type(m.get_cheat) == "function" and type(m.has_data) == "function" then
        CHEAT_MOD = m
        info("cheat", "cheat revealer found -- enemy cheats feed the engine")
    end
    return CHEAT_MOD
end

local function SetCheat(rec, id, player)
    if not CHEAT_IDS[id] or rec.cheat == id then return end
    rec.cheat, rec.E.cheat = id, id
    info("cheat", "player=%s cheat=%s", entity.get_player_name(player) or "?", id)
end

-- get_cheat indexes the revealer's per-player table without a nil check,
-- hence has_data first and both under pcall.
local function CheatPoll(enemies, n, now)
    local m = CheatModule(now)
    if not m then return end
    for i = 1, n do
        local player = enemies[i]
        local okh, has = pcall(m.has_data, player)
        if okh and has then
            local okc, c = pcall(m.get_cheat, player)
            if okc and type(c) == "table" and type(c.cheat_id) == "string" then
                local rec = GetRec(player)
                if rec then SetCheat(rec, c.cheat_id, player) end
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
--  DB FLUSH
--  Called on match end. Blends new match data with existing DB entry.
-- ══════════════════════════════════════════════════════════════════
FlushDB = function()
    for s64, rec in pairs(REC) do
        if not BOT_KEYS[s64] and (rec.hit_count >= 2 or ENG.Trials(rec.E) >= 3) then
            -- BUG FIX: merge into the entry as it was BEFORE this match
            -- (rec.db_base, snapshotted in NewRec), not the live DB[s64].
            -- Since v3.8 this runs every 60s as an autosave, and DB[s64]
            -- already held this match's earlier flushes -- so each autosave
            -- re-added the whole match: a real log shows one player's 3 hits
            -- stored as 3, 6, 9 ... 36 over twelve autosaves. Every flush
            -- is now idempotent for the current match.
            local ex   = rec.db_base or {}
            -- hit_rate is a running average across matches. It must be
            -- weighted by the sample size that actually PRODUCED nhr
            -- (hit_count+resolver_misses), not by rec.kills -- kills is a
            -- much rarer, noisier signal that's frequently 0 even with
            -- solid resolver data (resolved someone correctly several
            -- times but a teammate got the kill, or they died elsewhere
            -- after being hit). Weighting by kills meant any such match
            -- contributed ZERO to the DB average despite the hit_count>=2
            -- gate above proving real data existed -- silently starving
            -- seeded_conf (NewRec reads db.hit_rate) for exactly that
            -- common case. kills is still tracked below, just no longer
            -- used as the averaging weight.
            local this_n = rec.hit_count + rec.resolver_misses
            local prev_n = ex.samples or 0
            local tot_n  = prev_n + this_n
            local nhr    = this_n > 0 and (rec.hit_count / this_n) or 0
            DB[s64] = {
                config_type = rec.config_type or ex.config_type,
                vuln_pref   = rec.vuln_pref   or ex.vuln_pref,
                cheat       = rec.cheat       or ex.cheat,
                bt_pref     = rec.preferred_bt > 0 and rec.preferred_bt or ex.bt_pref,
                hit_rate    = tot_n > 0
                    and (nhr * this_n + (ex.hit_rate or 0) * prev_n) / tot_n
                    or nhr,
                samples     = tot_n,
                gen         = DB_GEN,
                kills       = (ex.kills or 0) + rec.kills,
                -- Engine evidence: rec.E already holds the (halved) counts
                -- loaded at match start plus this match's, so writing it
                -- is idempotent too.
                eng         = ENG.Save(rec.E),
            }
            info("db", "flush s64=%s cfg=%s vuln=%s bt=%d hr=%d%% hits=%d",
                 s64,
                 DB[s64].config_type or "?", DB[s64].vuln_pref or "?",
                 DB[s64].bt_pref or 0,
                 math.floor((DB[s64].hit_rate or 0) * 100),
                 DB[s64].kills)
        end
    end
    -- Cap: drop the least recently seen profiles past DB_MAX. Entries from
    -- before v7.2 carry no gen and count as oldest.
    local keys = {}
    for k in pairs(DB) do keys[#keys + 1] = k end
    if #keys > DB_MAX then
        table.sort(keys, function(a, b) return (DB[a].gen or 0) < (DB[b].gen or 0) end)
        for i = 1, #keys - DB_MAX do DB[keys[i]] = nil end
        info("db", "pruned %d stale profiles", #keys - DB_MAX)
    end
    database.write(DB_KEY, DB)
    database.write(ENG.DB_KEY, ENG.SaveGlobal())
    database.write(ENG.CHEAT_KEY, ENG.SaveCheat())
    info("db", "written %d entries", math.min(#keys, DB_MAX))
end

-- ══════════════════════════════════════════════════════════════════
--  ENGINE STEP  — candidates for one tick, the engine's call on them
-- ══════════════════════════════════════════════════════════════════
local function EngPush(C, n, arm, val, meth)
    n = n + 1
    local c = C[n]
    if not c then c = {}; C[n] = c end
    c.arm, c.val, c.meth = arm, val, meth
    return n
end

-- Every source that has a correction this tick goes in, both orientations,
-- plus the built-in. rec.eng_c and rec.eng_sig are reused, so a tick costs
-- no allocation beyond the vuln method string. Returns true when the engine
-- chose to release to the built-in over a chain pick.
local function EngineStep(rec, player, legacy_arm, legacy_val, legacy_meth,
                          vuln_ok, six_side, six_desync, tracked_side, tracked_method,
                          dom_side, corr_cap, live_cap)
    local C, n, sig = rec.eng_c, 0, rec.eng_sig
    local cfg = TrustedCfg(rec)

    if vuln_ok then
        local src  = ENG.VULN_SRC[rec.vuln_type] or "vuln_other"
        local arms = ENG.ARM[src]
        local v, m = rec.vuln_val, "vuln_" .. rec.vuln_type
        n = EngPush(C, n, arms[1], v, m)
        n = EngPush(C, n, arms[2], -v, m .. "_inv")
        sig[src] = Sign(v)
    end
    if DET.six and six_side ~= 0 then
        local v = six_desync > 0 and (six_side * six_desync)
                  or CfgAngle(six_side, rec.state, cfg, corr_cap)
        n = EngPush(C, n, "six:as", v, METH.SIX_LEX)
        n = EngPush(C, n, "six:inv", -v, "6lex_inv")
        sig.six = Sign(v)
    end
    if DET.hitmem then
        -- Same source order as the chain: this state's memory, then global.
        local hs = 0
        if rec.state and (rec.hit_count_by_state[rec.state] or 0) >= 2 then
            hs = rec.hit_side_by_state[rec.state] or 0
        end
        if hs == 0 and rec.hit_count >= 2 then hs = rec.hit_side end
        if hs ~= 0 then
            local v = CfgAngle(hs, rec.state, cfg, live_cap)
            n = EngPush(C, n, "hitmem:as", v, METH.HIT_MEM)
            n = EngPush(C, n, "hitmem:inv", -v, "hit_mem_inv")
            sig.hitmem = Sign(v)
        end
    end
    local bs = tracked_side ~= 0 and tracked_side or dom_side
    if bs == 0 and (legacy_arm == "pose:as" or legacy_arm == "pose:inv") then bs = 1 end
    if bs ~= 0 then
        local cap = (tracked_method == METH.HIT_MEM) and live_cap or corr_cap
        local v = CfgAngle(bs, rec.state, cfg, cap)
        n = EngPush(C, n, "pose:as", v, METH.TRACK)
        n = EngPush(C, n, "pose:inv", -v, METH.SUPPRESS)
        sig.pose = Sign(v)
    end
    n = EngPush(C, n, "builtin", 0, "builtin")

    local d
    for i = 1, n do if C[i].arm == legacy_arm then d = i; break end end
    if not d then n = EngPush(C, n, legacy_arm, legacy_val, legacy_meth); d = n end

    local pick, p = ENG.Decide(rec, C, n, d, rec.state)
    rec.eng_pick, rec.eng_by, rec.eng_arm = pick, pick ~= d, C[pick].arm
    if DET.verbose and rec._eng_logged ~= (rec.eng_by and rec.eng_arm or false) then
        rec._eng_logged = rec.eng_by and rec.eng_arm or false
        if rec.eng_by then
            dbg("engine", "player=%s pick=%s over=%s p=%.2f",
                entity.get_player_name(player) or "?", rec.eng_arm, legacy_arm, p)
        else
            dbg("engine", "player=%s back to chain pick=%s",
                entity.get_player_name(player) or "?", legacy_arm)
        end
    end
    return rec.eng_by and rec.eng_arm == "builtin"
end

-- ══════════════════════════════════════════════════════════════════
--  DECISION STAGES  -- side tracking, the legacy chain, and applying the
--  result. Split out of ProcessPlayer in v7.4; the harness checks that
--  the split changed no plist write on either runtime.
-- ══════════════════════════════════════════════════════════════════
-- Which side the enemy is on, and which source said so. Returns nil when
-- the player was released to the built-in (no side data, no meta hold).
local function TrackSide(rec, player, ctx, choke, st, six_side, pose_sum, eye_y, aa_type)
    -- ── SIDE TRACKING ──────────────────────────────────────────────
    -- Track which side we believe the enemy is on.
    -- The override block below decides whether to apply it.
    -- We do NOT compute an angle here — that happens per-case below.

    local tracked_side   = rec.side
    local tracked_method = METH.RING
    rec._brute_half       = false  -- set true below only on a true blind-guess tick

    if rec.vuln_ttl == 0 then
        -- No active vuln window — run the side detection chain
        if rec.hit_count >= 2 and rec.hit_side ~= 0 then
            -- Empirical: hit this player on this side this match
            tracked_side   = rec.hit_side   -- already flip-encoded at storage time
            tracked_method = METH.HIT_MEM

        elseif six_side ~= 0 and rec.conf > 0.30
               and (rec.six_disagree or 0) <= (rec.six_agree or 0) + 2 then
            tracked_side   = six_side
            tracked_method = METH.SIX_LEX

        elseif FEATURE.JITTER_PRED and #rec.fl >= CFG.PERIOD_MIN then
            local ps = PredictSide(rec, ctx.cur_tc)
            if ps ~= 0 then
                tracked_side   = ps
                tracked_method = METH.PERIOD
            end

        elseif not ctx.is_spike and choke == 0 and not rec.def_tickbase then
            local lco = LCTicks(false, ctx.cur_lat, ctx.avg_lat, ctx.lerp)
            local h   = rec.tm[st - lco]
            if h then
                rec._shift_streak = 0
                local s = Sign(h.p)
                if s ~= 0 then
                    tracked_side   = s
                    tracked_method = METH.LAGCOMP
                end
            else
                -- SHIFTING GUARD: choke==0 means packets ARE arriving, so a
                -- missing tm[] slot at this lookback isn't ordinary loss —
                -- it looks like a shift-style backtrack record break. Track
                -- it, and stop trusting the PHASE fallback too once it's
                -- happened repeatedly rather than locking onto a broken window.
                rec._shift_streak = (rec._shift_streak or 0) + 1
                if rec._shift_streak < 3 and #rec.fl > 0 and rec.side ~= 0 and rec.period > 0 then
                    local since = (st - lco) - rec.fl[#rec.fl]
                    tracked_side   = math.floor(since / rec.period) % 2 == 0
                                     and rec.side or -rec.side
                    tracked_method = METH.PHASE
                end
            end

        elseif rec.def_tickbase then
            tracked_side   = six_side ~= 0 and six_side
                             or (pose_sum ~= 0 and Sign(pose_sum) or rec.side)
            tracked_method = METH.DEF_TICK

        elseif ctx.is_spike then
            tracked_side   = pose_sum ~= 0 and Sign(pose_sum) or rec.side
            tracked_method = METH.RING_SPK

        elseif #rec.yc >= 2 and rec.conf < 0.60 then
            local ycs = YawSide(rec.yc, eye_y)
            if ycs ~= 0 then
                tracked_side   = ycs
                tracked_method = METH.YAW_CACHE
            end
        end

        -- Symmetric fallback: alternate when no signal
        local is_sym = rec.side == 0 and
            (aa_type == AA.THREE_WAY or aa_type == AA.FIVE_WAY or aa_type == AA.SKITTER)
        if tracked_side == 0 and is_sym then
            tracked_side   = rec.flip and 1 or -1
            tracked_method = METH.SYM_FLIP
        end

        -- Apply flip (only when side was NOT from hit_side which encodes it already)
        if rec.flip and tracked_method ~= METH.HIT_MEM then
            tracked_side = -tracked_side
        end

        if tracked_side == 0 then
            if rec.meta_aggressive then
                -- Built-in has proven it can't handle this player's meta.
                -- Never release back to it. Use our best available side.
                -- Priority: hit_side (confirmed) > ring side > flip guess.
                -- Note: flip was already applied above so work from rec.side (raw),
                -- then apply flip manually to avoid double-apply.
                local base = (rec.hit_side ~= 0 and rec.hit_side)  -- encoded, use direct
                          or (rec.side ~= 0 and rec.side)           -- raw ring side
                          or 0
                if base == 0 then
                    -- Absolute last resort: no side data at all. Cycle a short
                    -- candidate sequence (NIXWARE-style shot-cycle fallback:
                    -- side A full, side A half, side B full, side B half)
                    -- instead of freezing on one guess -- a sustained
                    -- no-signal streak shouldn't spam the same wrong angle.
                    rec._brute_idx = ((rec._brute_idx or 0) + 1) % 4
                    base = (rec._brute_idx < 2) and 1 or -1
                    if rec.flip then base = -base end
                    rec._brute_half = (rec._brute_idx % 2) == 1
                else
                    -- Apply flip to raw ring side (hit_side already encodes it)
                    if base == rec.side and rec.flip then base = -base end
                end
                tracked_side   = base ~= 0 and base or 1
                tracked_method = METH.META_HOLD
            else
                ClearEnt(player); return nil
            end
        end
    end
    return tracked_side, tracked_method
end

-- The legacy priority chain: vuln > 6lex > hit memory > suppress. Returns
-- its pick (override flag, value, method), whether suppress is inside its
-- deliberate pause, and whether a vuln window qualified.
local function ChainPick(rec, six_side, six_desync, corr_cap, live_cap,
                         tracked_side, tracked_method, dom_side, aa_type)
    -- ── ADDITIVE OVERRIDE ──────────────────────────────────────────
    -- Only take control from the built-in when signal is definitive.
    -- Priority: vuln > 6lex > hit_mem > meta_hold > suppress > release
    local should_override = false
    local override_val    = 0
    local override_meth   = tracked_method
    local sup_pausing     = false  -- true only during the suppress streak-cap's pause window

    -- [1] Vulnerability window: correction is deterministic.
    -- Lower confidence threshold when meta_aggressive — even a weaker
    -- vuln read beats the known-failing built-in.
    local vuln_min = rec.meta_aggressive and CFG.VULN_MIN_AGG or CFG.VULN_MIN
    local vuln_ok  = DET.vuln and rec.vuln_ttl > 0 and rec.conf >= vuln_min
    if vuln_ok then
        should_override = true
        override_val    = rec.vuln_val
        override_meth   = "vuln_" .. rec.vuln_type

    -- [2] 6lex: animlayer digit read — direct, no guessing. Gated by
    -- per-player calibration: once it's been proven wrong against
    -- confirmed hits more than a small margin above how often it's
    -- been right for THIS player, stop trusting it for them and fall
    -- through to hit-mem/suppress instead (see on_aim_hit).
    elseif DET.six and six_side ~= 0 and rec.conf > 0.25
           and (rec.six_disagree or 0) <= (rec.six_agree or 0) + 2 then
        should_override = true
        override_val    = six_desync > 0
                          and (six_side * six_desync)
                          or CfgAngle(six_side, rec.state, TrustedCfg(rec), corr_cap)
        override_meth   = METH.SIX_LEX

    -- [3] Hit-side memory: confirmed hit this match. Per-CONDITION
    -- memory (this exact movement state) takes priority over the
    -- global scalar -- an enemy desyncing a different side while
    -- standing vs. moving means the state-specific record is strictly
    -- more accurate whenever it exists; the global one is only a
    -- fallback for states we haven't confirmed a hit in yet this match.
    -- NOTE: hit_mem is confirmed data (an actual prior hit on this player
    -- in this state), not a static guess -- so it's capped by live_cap
    -- (the engine's real desync bound) rather than corr_cap (VelCap's
    -- velocity-scaled cap). corr_cap is meant only for CfgAngle's static
    -- guesses per the comment above VelCap's call site; it linearly falls
    -- to exactly 0 at CFG.VEL_CAP_SPD (580u/s), and a bhopping/fast-moving
    -- enemy crosses that constantly. Using corr_cap here was clamping a
    -- confirmed correction to literally val=0.0 -- aim dead-center, worse
    -- than a coin flip -- every time the target's speed spiked, which is
    -- exactly when hit_mem should matter most (fast movement is when
    -- static guesses are least trustworthy, not when confirmed data should
    -- be thrown out). Seen directly in a debug log: a hit_mem correction
    -- logged val=0.0 for a fast-moving target.
    elseif DET.hitmem and rec.state
           and (rec.hit_count_by_state[rec.state] or 0) >= 2
           and (rec.hit_side_by_state[rec.state] or 0) ~= 0 then
        should_override = true
        override_val    = CfgAngle(rec.hit_side_by_state[rec.state], rec.state, TrustedCfg(rec), live_cap)
        override_meth   = METH.HIT_MEM

    elseif DET.hitmem and rec.hit_count >= 2 and rec.hit_side ~= 0 then
        should_override = true
        override_val    = CfgAngle(rec.hit_side, rec.state, TrustedCfg(rec), live_cap)
        override_meth   = METH.HIT_MEM

    -- [4] Suppress (FEATURE.SUPPRESS): force wrong angle to gate aimbot hit-chance.
    -- When meta_aggressive, lower threshold aggressively — fewer shots =
    -- fewer bullet_impact events near the enemy = testarossa AB starved.
    -- STREAK CAP: suppress that runs for >8 consecutive ticks means we're stuck.
    -- Log analysis showed hxlw1ss at 375/914 suppress — mid-conf lock-in pattern
    -- where conf hovers above threshold permanently with no vuln ever firing.
    -- After 8 ticks suppress, pause 4 ticks and let a shot through. If we hit,
    -- great; if we miss, the correction data resets the stuck loop.
    --
    -- BUG FIXED: the old single-counter version reset _sup_streak to 0 in
    -- the non-suppress branches below the instant the streak cap blocked
    -- suppress for even one tick -- so streak_ok's "streak >= 12" arm was
    -- unreachable dead code; suppress actually resumed on the very next
    -- tick instead of pausing for 4. Fixed with a dedicated pause counter
    -- (_sup_pause) and sup_pausing, which tells the bookkeeping below not
    -- to blow the counters away while a deliberate pause is in progress.
    elseif FEATURE.SUPPRESS and rec.vuln_ttl == 0 then
        local sup_thresh = rec.meta_aggressive and CFG.SUP_MIN_AGG or CFG.SUP_MIN
        if JITTER_AA[aa_type] and rec.conf > sup_thresh then
            local streak = rec._sup_streak or 0
            if streak < CFG.SUP_STREAK then
                should_override = true
                local bs = tracked_side ~= 0 and tracked_side or dom_side
                if bs == 0 then bs = 1 end
                override_val  = -CfgAngle(bs, rec.state, TrustedCfg(rec), corr_cap)
                override_meth = METH.SUPPRESS
            else
                local pause = (rec._sup_pause or 0) + 1
                rec._sup_pause = pause
                sup_pausing = true
                if pause >= CFG.SUP_PAUSE then
                    rec._sup_streak = 0
                    rec._sup_pause  = 0
                end
            end
        end
    end
    return should_override, override_val, override_meth, sup_pausing, vuln_ok
end

-- Engine arbitration over the chain's pick, the plist write (or meta hold,
-- or release), and decision logging.
local function ApplyDecision(rec, player, should_override, override_val, override_meth,
                             sup_pausing, vuln_ok, six_side, six_desync, tracked_side,
                             tracked_method, dom_side, corr_cap, live_cap, aa_type)
    -- ── DECISION ENGINE ────────────────────────────────────────────
    -- The chain above made its pick (or will hold/release below). Put
    -- every candidate that could apply this tick next to it and let the
    -- engine decide; with no evidence it returns the chain's own pick.
    local legacy_arm
    if should_override then
        legacy_arm = (override_meth == METH.SUPPRESS and "pose:inv")
            or (override_meth == METH.SIX_LEX and "six:as")
            or (override_meth == METH.HIT_MEM and "hitmem:as")
            or ((ENG.VULN_SRC[rec.vuln_type] or "vuln_other") .. ":as")
    elseif rec.meta_aggressive and tracked_side ~= 0 then
        legacy_arm = "pose:as"
    else
        legacy_arm = "builtin"
    end
    local eng_release = false
    rec.eng_arm = legacy_arm
    if DET.engine then
        eng_release = EngineStep(rec, player, legacy_arm, override_val, override_meth,
            vuln_ok, six_side, six_desync, tracked_side, tracked_method, dom_side,
            corr_cap, live_cap)
        local pick = rec.eng_by and rec.eng_c[rec.eng_pick] or nil
        if pick then
            if pick.arm == "builtin" then
                should_override = false
            else
                should_override = true
                override_val, override_meth = pick.val, pick.meth
            end
        end
    end

    if should_override then
        -- High priority (set last inside PApply): confirmed via a real
        -- resolver's usage, not the docs -- hints the LC/backtrack system
        -- not to deprioritize this target while we're correcting them.
        PApply(player, true, override_val, true)
        rec.active = true; rec.resolved = true
        rec.last_val = override_val; rec.last_meth = override_meth
        -- Track suppress streak for the streak-cap logic above
        if override_meth == METH.SUPPRESS then
            rec._sup_streak = (rec._sup_streak or 0) + 1
        else
            rec._sup_streak = 0   -- any non-suppress override resets the streak
        end
        rec._sup_pause = 0

    elseif not eng_release and rec.meta_aggressive and tracked_side ~= 0 then
        -- META_HOLD: built-in has failed this player's meta (serenity ways(),
        -- ambani torpedo, aesthetic records — patterns the 2022-era built-in
        -- has no answer for). Hold our best tracked_side correction rather than
        -- releasing to a resolver that's already proven it can't handle this AA.
        -- Same corr_cap-zeroing bug as the [3] hit_mem branch (see v5.8):
        -- tracked_side can be sourced from METH.HIT_MEM here too (the
        -- unconditional side-tracking chain above sets tracked_method =
        -- HIT_MEM off rec.hit_side whenever hit_count>=2, regardless of
        -- whether the "Hit Memory" checkbox is even on) -- so a fast-
        -- moving target would still get its confirmed correction clamped
        -- to literal 0 right here, via this second call site, even after
        -- the [3] branch itself was fixed. Use live_cap for that case.
        local meta_cap = (tracked_method == METH.HIT_MEM) and live_cap or corr_cap
        local meta_val = CfgAngle(tracked_side, rec.state, TrustedCfg(rec), meta_cap)
        if rec._brute_half then meta_val = meta_val * 0.5 end
        PApply(player, true, meta_val, true)
        rec.active = true; rec.resolved = true
        rec.last_val = meta_val; rec.last_meth = METH.META_HOLD
        -- Don't blow away a suppress streak/pause in progress -- this
        -- branch fires DURING the deliberate 4-tick pause window (should_
        -- override is false while paused), not just when suppress is
        -- genuinely irrelevant. See sup_pausing above.
        if not sup_pausing then rec._sup_streak = 0; rec._sup_pause = 0 end

    else
        PApply(player, false, 0, false)
        rec.active = false; rec.resolved = false
        rec.last_val = 0; rec.last_meth = "builtin"
        -- Same sup_pausing guard as the meta_aggressive branch above.
        if not sup_pausing then rec._sup_streak = 0; rec._sup_pause = 0 end
    end

    -- Only log when the correction method or value actually CHANGES.
    -- Log analysis showed 35k+ [corr] lines for 453 hits — 98% were
    -- stale TTL echoes (same val repeated for 11+ ticks). This gate
    -- cuts the log to only meaningful resolver decisions.
    if DET.verbose then
        local val_changed  = math.abs((rec.last_val  or 0) - (rec._prev_log_val  or 0)) > 1.0
        local meth_changed = rec.last_meth ~= rec._prev_log_meth
        if val_changed or meth_changed then
            dbg("corr", "player=%s aa=%s side=%d meth=%s val=%.1f override=%s",
                entity.get_player_name(player) or "?",
                aa_type, tracked_side, rec.last_meth, rec.last_val,
                tostring(should_override))
            rec._prev_log_val  = rec.last_val
            rec._prev_log_meth = rec.last_meth
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
--  PROCESSPLAYER  — all per-player resolver logic
--  Called from Update() inside a pcall, so crashes are caught and
--  logged without stalling the rest of the player loop.
--  Returns early (without saving prev state) only when no data was
--  sampled. Otherwise always saves prev_pose/spd/duck/on_ground.
-- ══════════════════════════════════════════════════════════════════
local function ProcessPlayer(player, ctx)
    local st_raw = entity.get_prop(player, "m_flSimulationTime")
    if not isnum(st_raw, 0.001) then return end

    local rec, s64 = GetRec(player)
    if not rec then return end
    if BOT_KEYS[s64] then ClearEnt(player); return end

    TrackDT(s64, st_raw)

    -- "choke" is record staleness in ticks beyond our latency, measured
    -- BEFORE the fresh-record gate below: it counts up on every tick the
    -- enemy chokes (those ticks return at the gate), and drops to ~0 on the
    -- update that ends the choke -- which is how was_choked/cur_choke detect
    -- an unchoke. On the processed (fresh) ticks further down it is
    -- therefore nonzero only when a record arrived late (latency jitter,
    -- loss): that is what the lagcomp/yaw-cache split below keys on.
    local choke = ChokedPkts(st_raw, ctx.cur_lat)
    rec.was_choked   = rec.cur_choke > 0
    rec.cur_choke    = choke
    rec.def_tickbase = IsDefTick(s64)

    local st = math.floor(st_raw / ctx.ti)
    if st == rec.lt then return end
    rec.lt = st
    -- Per-decision flags: reset here (not later in the function) because
    -- several paths below exit early via `break`, and a stale value would
    -- attribute this tick's shot to a decision that wasn't made. They stay
    -- untouched on the same-simtime early return above, since the last
    -- decision's plist values are still the ones being applied.
    -- Until the override block decides, the plist is whatever the last
    -- release left it at: the built-in. Early ClearEnt breaks keep this.
    rec.eng_arm, rec.eng_by = "builtin", false
    for k in pairs(rec.eng_sig) do rec.eng_sig[k] = nil end

    -- pose/spd/duck/on_ground are nil until sampled.
    -- They are saved to rec at the end of the function regardless of path taken.
    local pose, spd, duck, on_ground = nil, nil, nil, nil

    -- repeat...until true lets us break out early (goto-safe in LuaJIT)
    -- while still running the save block below unconditionally.
    repeat

        local as = GetAS(player)
        if not as then
            rec.prev_pose = nil  -- prevent stale LBY trigger next tick
            rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_z = nil, nil, nil  -- gap ahead; don't compare across it
            rec.prev_origin_tick = nil
            break
        end

        if choke > 2 then
            ClearEnt(player)
            rec.prev_pose = nil
            rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_z = nil, nil, nil
            rec.prev_origin_tick = nil
            break
        end

        -- Velocity — read once, shared by ClassifyState, the velocity
        -- correction cap, and DetectVuln's STP/PKA checks below.
        local vx0, vy0 = entity.get_prop(player, "m_vecVelocity")
        spd = (isnum(vx0) and isnum(vy0)) and math.sqrt(vx0*vx0 + vy0*vy0) or 0

        -- State
        local dv
        if isnum(rec.prev_spd) and rec.prev_spd_st and st > rec.prev_spd_st then
            dv = (spd - rec.prev_spd) / (st - rec.prev_spd_st)   -- per tick, fakelag-safe
        end
        local state_key = ClassifyState(player, as, spd, dv, rec.state)
        rec.state = state_key
        if rec.conf == 0 then rec.conf = CFG.STATE_SEED[state_key] or 0.25 end

        -- Live per-player desync bounds from animstate.
        -- Replaces the hardcoded DESYNC_CAP = 58 with actual engine-reported
        -- clamp values. Falls back to 58 if not yet populated.
        local live_mn, live_mx, live_cap = LiveCap(as)
        rec.live_min = live_mn
        rec.live_max = live_mx

        -- Velocity-constrained correction cap — see VelCap(). Used only to
        -- clamp CfgAngle's static guesses, never the engine-read live_cap.
        local corr_cap = VelCap(spd, live_cap)

        if DET.verbose then
            -- Log only when the cap moves by a whole degree. Since v6.7's
            -- DynamicMaxYaw the cap differs from DESYNC_CAP on nearly every
            -- tick (it tracks movement/duck state), so the old
            -- `live_cap ~= DESYNC_CAP` gate logged once per enemy per tick.
            local cap_q = math.floor(live_cap + 0.5)
            if cap_q ~= rec._logged_cap then
                rec._logged_cap = cap_q
                dbg("dcap", "player=%s live=[%.1f .. %.1f] cap=%.1f",
                    entity.get_player_name(player) or "?", live_mn, live_mx, live_cap)
            end
            -- Probe skeet's entity.get_desync() if exposed — compare vs struct read.
            -- Skeet DLL (Dec 2024) confirmed get_desync() exists as Lua-callable.
            -- If it differs from live_cap, get_desync() is the post-correction value;
            -- we want the raw struct reads for our own resolver.
            local ok_gd, gd = pcall(function()
                return type(entity.get_desync) == "function" and entity.get_desync(player) or nil
            end)
            if ok_gd and gd and isnum(gd) then
                dbg("gdesync", "player=%s entity.get_desync()=%.2f live_cap=%.1f diff=%.2f",
                    entity.get_player_name(player) or "?", gd, live_cap, math.abs(gd - live_cap))
            end
        end

        -- 6lex — pass live cap so playback_rate magnitude clamps to real bounds
        local six_side, six_desync = 0, 0
        local al6_weight = nil
        do
            local ptr = GetPtr(player)
            if ptr then
                if DET.six then
                    six_side, six_desync = Extract6Lex(ptr, live_cap)
                    rec.six_side   = six_side
                    rec.six_desync = six_desync
                end
                -- animlayer[6].weight settled-state cross-check (see DetectVuln's
                -- UNK branch): a real resolver's find_desync_side uses this same
                -- field as a tri-state signal -- 0 or 1 means the movement layer
                -- is fully settled (no active blend), which independently confirms
                -- torso_yaw isn't mid-transition. Read once here regardless of
                -- the 6lex toggle since it's an unrelated signal, not a 6lex output.
                local al6 = GetAL(ptr, 6)
                al6_weight = al6 and al6.weight
            end
        end

        -- Sample. Input boundary: everything below is stored in the history
        -- buffers and fed to Clamp, so non-finite values stop here (found by
        -- the v7.3 fuzzer: a NaN eye yaw was landing in rec.tm). A missing
        -- or broken pose reads as centre, i.e. no side evidence -- it used
        -- to default to 0, which is a full -60 desync read.
        local praw = entity.get_prop(player, "m_flPoseParameter", 11)
        praw = Finite(praw) and Clamp(praw, 0, 1) or 0.5
        pose = praw * CFG.POSE_SCALE - 60
        local _, eyy = entity.get_prop(player, "m_angEyeAngles")
        local eye_y  = as.eye_angles_y
        if not Finite(eye_y) then eye_y = eyy end
        if not Finite(eye_y) then
            local last = RLen(rec.hist) > 0 and RGet(rec.hist, 1)
            eye_y = (last and Finite(last.e)) and last.e or 0
        end
        duck      = Finite(as.duck_amount) and as.duck_amount or 0
        on_ground = as.on_ground

        -- ORIGIN-JUMP SHIFT CHECK: a >64-unit origin teleport on a clean
        -- (choke==0) tick is a direct shifting/broken-backtrack-record
        -- signal -- confirmed independently in THREE real scripts now, all
        -- using this exact 4096 sq-unit (64-unit) threshold: a public CS:GO
        -- lagrecord library, a full HvH cheat's own broke_lc check, and a
        -- standalone "lag comp breaker" ESP tool that draws a 3D box on it.
        -- Stronger and more immediate than the indirect tm[]-gap proxy
        -- below, so it sets _shift_streak straight to the distrust floor
        -- instead of accumulating gradually. _shift_flash/_shift_box drive
        -- a brief world-space "SHIFT" tag + box in DrawOverlay, adapted
        -- from that same ESP tool's extrapolation technique.
        local ox, oy, oz = entity.get_origin(player)
        if choke == 0 and isnum(ox) and isnum(oy)
           and rec.prev_origin_x and rec.prev_origin_y then
            local dx, dy = ox - rec.prev_origin_x, oy - rec.prev_origin_y
            if (dx*dx + dy*dy) > 4096 then
                rec._shift_streak = math.max(rec._shift_streak or 0, 3)
                rec._shift_flash  = 1.0
                local ticks = Clamp((rec.prev_origin_tick and (st - rec.prev_origin_tick)) or 1, 1, 32)
                local ex, ey, ez = ExtrapolateOrigin(player, ox, oy, oz, ticks)
                rec._shift_box = {ex, ey, ez}
            end
        end
        rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_z = ox, oy, oz
        rec.prev_origin_tick = st

        -- One sample table shared by the ring buffer and the lag-comp map
        -- (used to allocate two identical tables per update).
        local sample = {p=pose, e=eye_y, t=st}
        RPush(rec.hist, sample)
        -- LEAK FIX: this used to clear only tm[st - TM_HORIZON]. Whenever
        -- the enemy's simtime tick skips values (fakelag, choke -- i.e.
        -- most HvH players), that exact slot was never one that had been
        -- written, so entries were never removed: measured 2,500 entries
        -- after 20k ticks for an 8-tick fakelag enemy, growing without bound
        -- for the whole match. Now pruned by age once the map holds twice
        -- the horizon -- amortized O(1), bounded at 2x TM_HORIZON.
        if not rec.tm[st] then
            rec.tm[st] = sample
            rec.tm_n = (rec.tm_n or 0) + 1
            if rec.tm_n > CFG.TM_HORIZON * 2 then
                local floor_st, n = st - CFG.TM_HORIZON, 0
                for k in pairs(rec.tm) do
                    if k < floor_st then rec.tm[k] = nil else n = n + 1 end
                end
                rec.tm_n = n
            end
        end
        rec.yc[#rec.yc+1] = eye_y
        if #rec.yc > CFG.YAW_BUF then table.remove(rec.yc, 1) end

        -- Classify
        local aa_type, dom_side, raw_c, pose_sum = DetectAA(rec.hist)
        rec.aa_type = aa_type

        -- Use live per-player cap for jitter threshold — previously hardcoded 58*0.45=26.1°
        local yaw_jit = false
        if #rec.yc >= 2 then
            local yd = math.abs(NA(rec.yc[#rec.yc] - rec.yc[#rec.yc-1]))
            yaw_jit = yd >= live_cap * 0.45
        end

        if aa_type == AA.STATIC then
            rec.conf = 0.5; ClearEnt(player); break
        end

        -- (asymmetric torso delta was tracked here but rec.asym_left/right
        --  are never read — RecognizeCfg uses MeanSidePose directly)

        -- Confidence
        -- COLLABORATION GAP (found by tracing whether detection methods
        -- actually cross-validate each other, not just whether they're
        -- wired correctly): this used to boost confidence on ANY nonzero
        -- six_side, unconditionally -- so two independent signals actively
        -- CONTRADICTING each other (six_side and dom_side both nonzero but
        -- pointing opposite ways) still added +0.08 as if 6lex alone were
        -- confirming evidence, with no penalty for the disagreement.
        -- Agreement got rewarded (the extra +0.05 below); disagreement was
        -- silently ignored instead of counting against confidence. Two
        -- detectors contradicting each other is negative evidence, not
        -- neutral -- now decayed the same way a genuinely quiet/no-signal
        -- tick already is (CFG.CONF_DECAY), instead of still gaining.
        if six_side ~= 0 then
            if dom_side ~= 0 and dom_side ~= six_side then
                rec.conf = rec.conf * CFG.CONF_DECAY
            else
                rec.conf = math.min(rec.conf + 0.08, 1.0)
                if dom_side ~= 0 and dom_side == six_side then
                    rec.conf = math.min(rec.conf + 0.05, 1.0)
                end
            end
        end
        if raw_c > 0.35 or yaw_jit then
            rec.conf = math.min(rec.conf + CFG.CONF_GROW, 1.0)
            if dom_side ~= 0 then
                if rec.side ~= 0 and dom_side ~= rec.side then
                    -- Record flip BEFORE updating rec.side so fl timestamps
                    -- stay aligned with the side value PredictSide reads
                    rec.fl[#rec.fl+1] = st
                    if #rec.fl > 24 then table.remove(rec.fl, 1) end
                end
                rec.side = dom_side
            end
        else
            rec.conf = rec.conf * CFG.CONF_DECAY
            if rec.conf < 0.08 then rec.side = 0 end
        end

        -- Config recognition (throttled)
        if rec.config_conf < 0.8 and (st % CFG.CFG_TICKS) == 0 then
            local rcfg = RecognizeCfg(rec, rec.config_type)
            if rcfg then
                if rcfg == rec.config_type then
                    rec.config_conf = math.min(rec.config_conf + CFG.CFG_GAIN, 1.0)
                else
                    if DET.verbose then
                        info("cfg", "switch %s->%s player=%s",
                             rec.config_type or "?", rcfg,
                             entity.get_player_name(player) or "?")
                    end
                    rec.config_type = rcfg; rec.config_conf = 0.30
                end
            end
        end

        if rec.conf < CFG.CONF_MIN then ClearEnt(player); break end

        -- Vulnerability window
        if rec.vuln_ttl > 0 then rec.vuln_ttl = rec.vuln_ttl - 1 end

        -- WIRING BUG (found via a "check every function's outputs are
        -- actually consumed" audit): DetectVuln returns a 3rd value --
        -- a per-detection confidence, graduated 0.72..0.97 by the
        -- SETTLED-STATE CROSS-CHECK / LIVE CAP BOOST / cluster-confidence
        -- logic inside it -- that this call site was silently dropping
        -- entirely (only vtype/vcorr were captured). Not a syntax error in
        -- Lua (extra return values are just discarded), so nothing ever
        -- surfaced it: an entire confidence subsystem computed every tick
        -- with zero effect on behavior, not even logged. Now captured and
        -- stored/logged below for visibility. Not using it to gate window-
        -- opening decisions yet -- that would need real per-confidence-
        -- level accuracy data to pick a threshold from, not a guess.
        local vtype, vcorr, vconf = DetectVuln(rec, as, pose, eye_y, spd, corr_cap, al6_weight)
        if vtype and not rec.vuln_profile[vtype] then
            rec.vuln_profile[vtype] = {seen=0, hit=0}
        end
        -- NOTE: seen is NOT incremented here. A vuln window opening is not
        -- a "trial" -- most windows never get shot at (target not visible/
        -- not aimed-at during the brief ttl). Counting every detection as
        -- seen made the denominator wildly larger than actual shot
        -- attempts (a single player logged 110 "unk" detections in one
        -- match against maybe a dozen actual shots), crushing the hit
        -- ratio to near-zero regardless of true accuracy and risking the
        -- trust gate below distrusting a perfectly good vuln type just
        -- because it rarely got fired at. seen is credited by VulnCredit,
        -- once per informative shot outcome in an open window.
        if vtype and VulnTrusted(rec, vtype) then
            local lc_ttl = math.floor(CFG.LC_WINDOW_S / ctx.ti) - 1
            local base_ttl = CFG.VULN_TTL[vtype] or 1
            local is_standing = spd < 8 and duck < 0.1 and on_ground == true

            -- One-shot boost: standing enemy = fully exposed head hitbox,
            -- confirmed via trace rather than assumed from velocity/duck/ground
            -- alone (CanSeeHead fails open, so this never costs a boost the old
            -- heuristic would've granted -- it only withholds it on a confirmed
            -- blocked line, e.g. standing behind a window frame or thin wall).
            -- +1 tick gives the aimbot more backtrack candidates to find
            -- a clean headshot position within the vulnerability window.
            if is_standing and (vtype == VTYPE.LBY or vtype == VTYPE.UNK)
               and CanSeeHead(entity.get_local_player(), player) then
                base_ttl = base_ttl + 1
            end

            -- Large unchoke desync = high confidence real position exposed.
            -- Extend so the aimbot can catch the peak exposure on backtrack.
            -- safe_eye: use eye_y if valid, else last ring buffer entry
            if vtype == VTYPE.UNK then
                local torso    = as.torso_yaw
                local safe_eye_pp = (math.abs(eye_y) > 1.0) and eye_y
                                    or (RLen(rec.hist) > 0 and RGet(rec.hist, 1) and RGet(rec.hist, 1).e)
                                    or nil
                if torso and safe_eye_pp and math.abs(NA(torso - safe_eye_pp)) > 25 then
                    base_ttl = base_ttl + 1
                end
            end

            -- Never let a fresh detection cut an already-open window short.
            -- DetectVuln re-evaluates all 7 trigger conditions independently
            -- every tick with no awareness of rec.vuln_ttl -- if a window is
            -- already open (e.g. an LBY snap with 2 ticks left) and a
            -- different vtype fires on the very next tick (e.g. a UNK
            -- unchoke with base_ttl=1), the old code overwrote vuln_ttl down
            -- to the new, SHORTER value, cutting the still-active window off
            -- early and handing the aimbot less time to find a shot than
            -- either signal would have given alone. rec.vuln_ttl here is
            -- already the post-decrement remaining time for THIS tick (see
            -- the decrement a few lines above), so max()-ing against it is
            -- monotonic -- a fresh detection can only extend or refresh the
            -- window, never shrink it. vuln_type/vuln_val still update to
            -- the newest read (a fresher signal is presumably a more
            -- current correction), only the ttl is protected from shrinking.
            rec.vuln_ttl  = math.max(rec.vuln_ttl, base_ttl, lc_ttl)
            rec.vuln_type = vtype
            rec.vuln_val  = vcorr
            rec.vuln_conf = vconf
            if DET.verbose then
                dbg("vuln", "type=%s val=%.1f conf=%.2f player=%s ttl=%d%s",
                    vtype, vcorr, vconf or 0, entity.get_player_name(player) or "?",
                    rec.vuln_ttl, is_standing and " [STAND]" or "")
            end
        end

        -- Backtrack depth is observed passively via aim_fire.backtrack.
        -- We do NOT manipulate cl_interp here — restricting it to preferred_bt
        -- caps the aimbot's maximum backtrack window and kills deeper opportunities.

        local tracked_side, tracked_method =
            TrackSide(rec, player, ctx, choke, st, six_side, pose_sum, eye_y, aa_type)
        if not tracked_side then break end

        local should_override, override_val, override_meth, sup_pausing, vuln_ok =
            ChainPick(rec, six_side, six_desync, corr_cap, live_cap,
                      tracked_side, tracked_method, dom_side, aa_type)

        ApplyDecision(rec, player, should_override, override_val, override_meth,
                      sup_pausing, vuln_ok, six_side, six_desync, tracked_side,
                      tracked_method, dom_side, corr_cap, live_cap, aa_type)

    until true  -- end of repeat block; break exits without running save

    -- Save previous frame state (always, for every path that sampled data)
    rec.prev_pose     = pose
    rec.prev_spd2     = rec.prev_spd  -- shift: spd2 = last tick's spd before this update
    rec.prev_spd      = spd
    if spd then rec.prev_spd_st = st end
    rec.prev_duck     = duck or 0
    rec.prev_onground = on_ground
    -- Decrement DCK cooldown each tick (set to 10 when DCK fires, counts down to 0)
    if (rec._dck_cooldown or 0) > 0 then
        rec._dck_cooldown = rec._dck_cooldown - 1
    end
end


-- ══════════════════════════════════════════════════════════════════
--  UPDATE  — orchestration loop
-- ══════════════════════════════════════════════════════════════════
local ESP_VLN, ESP_RES = {}, {}

local function UpdateEspState()
    for k in pairs(ESP_VLN) do ESP_VLN[k] = nil end
    for k in pairs(ESP_RES) do ESP_RES[k] = nil end
    if not IND.esp then return end
    for i = 1, #LIVE_ENEMIES do
        local ent = LIVE_ENEMIES[i]
        local s64 = EIDX_S64[ent]
        local rec = s64 and REC[s64]
        if rec then
            -- VLN: vulnerability window open (deterministic correction)
            ESP_VLN[ent] = rec.vuln_ttl > 0
            -- RES: confident correction actively overriding the built-in
            -- (hit-mem, 6lex, engine picks, meta-hold -- not suppress, not vuln)
            ESP_RES[ent] = rec.resolved and rec.conf >= CFG.CONF_ESP
                and rec.vuln_ttl == 0 and rec.last_meth ~= METH.SUPPRESS
        end
    end
end

-- Per-tick context shared by every ProcessPlayer call; filled in place.
local CTX = {}

local function Update()
    if not ui.get(ui_on) then
        if next(ESP_VLN) or next(ESP_RES) then
            for k in pairs(ESP_VLN) do ESP_VLN[k] = nil end
            for k in pairs(ESP_RES) do ESP_RES[k] = nil end
        end
        return
    end
    -- Once per tick, so a config load that skips the change callbacks
    -- still reaches the resolver within one update.
    SyncFlags()

    local cur_lat, avg_lat = GetLat()
    local ctx = CTX
    ctx.cur_lat  = cur_lat
    ctx.avg_lat  = avg_lat
    ctx.is_spike = math.abs(cur_lat - avg_lat) > CFG.SPIKE_THR
    ctx.threat   = client.current_threat()
    ctx.ti       = globals.tickinterval()
    ctx.cur_tc   = globals.tickcount()
    ctx.lerp     = 0.031
    LAST_SPIKE = ctx.is_spike
    -- Read once per tick; LCTicks used to pcall a fresh closure for this on
    -- every lag-comp lookup.
    local okl, lerp = pcall(cvar_interp_get)
    if okl and isnum(lerp, 0, 1) then ctx.lerp = lerp end

    -- entity.get_players(true): per docs.gamesense.gs/docs/api/entity it
    -- returns enemies only and already excludes dormant and dead players,
    -- so the old per-player is_enemy/is_alive calls were redundant C calls.
    -- Collect first so the player list can be refreshed BEFORE processing.
    local n_live, fresh = 0, false
    for _, player in ipairs(entity.get_players(true)) do
        n_live = n_live + 1
        LIVE_ENEMIES[n_live] = player
        if not PL_KNOWN[player] then PL_KNOWN[player] = true; fresh = true end
    end
    for i = #LIVE_ENEMIES, n_live + 1, -1 do LIVE_ENEMIES[i] = nil end

    -- update_player_list() used to run every tick. It's only needed so
    -- plist.set can reach a player that just appeared; run it then, plus a
    -- once-per-second resync that also drops the plist write cache.
    if fresh or ctx.cur_tc - LAST_PL_SYNC >= PL_RESYNC_TICKS or ctx.cur_tc < LAST_PL_SYNC then
        if not fresh then PL_CACHE = {} end
        client.update_player_list()
        LAST_PL_SYNC = ctx.cur_tc
        if DET.engine then CheatPoll(LIVE_ENEMIES, n_live, globals.realtime()) end
    end

    for i = 1, n_live do
        local player = LIVE_ENEMIES[i]
        local ok, msg = pcall(ProcessPlayer, player, ctx)
        if not ok then
            err("update", "player=%d crash=%s", player, tostring(msg))
        end
    end
    UpdateEspState()
    STATE_VER = STATE_VER + 1

    -- Periodic autosave: don't rely solely on match-end/disconnect/shutdown
    -- firing cleanly. Every 60s, if there's anyone worth saving, flush to
    -- the permanent DB so a crash or hard stop doesn't lose the session.
    local now = globals.realtime()
    if next(REC) and (now - LAST_DB_SAVE) >= 60 then
        LAST_DB_SAVE = now
        FlushDB()
        -- The log too: it only reached disk every 2048 lines or at match
        -- end, so a match with Debug log off could sit entirely in memory
        -- -- the first v7.6 log sent in had none of the match in it.
        flush_log()
    end

    -- Tight interp is handled by its ui.set_callback — nothing to do here

    local prune_tc = ctx.cur_tc - CFG.SHOTS_MAX_AGE
    for id, s in pairs(SHOTS) do
        if (s.tick or 0) < prune_tc then SHOTS[id] = nil end
    end
end

-- ══════════════════════════════════════════════════════════════════
--  SHOT FEEDBACK
-- ══════════════════════════════════════════════════════════════════
-- Engine arm behind a shot, for the [hit]/[miss] log lines, so a real match
-- log shows per-arm outcomes:  eng=pose:inv   eng=hitmem:inv* (* = override)
local function EngTag(d)
    local e = d.eng
    if not e then return "" end
    -- eng=<arm>[*]: * marks a shot where the engine overrode the chain
    return string.format(" eng=%s%s p=%.2f", e.arm, e.by and "*" or "", e.p or 0)
end

local function EngSnap(r)
    local signs = {}
    for src, sg in pairs(r.eng_sig) do signs[src] = sg end
    -- p: the engine's predicted head chance for the arm being fired, the
    -- number the audit and the drift test score against the outcome.
    local p = ENG.Post(r.E, r.eng_arm, r.state)
    return {arm = r.eng_arm, by = r.eng_by, sign = Sign(r.last_val or 0), signs = signs,
            state = r.state, p = p}
end

-- Local weapon class by item definition index (CS:GO item ids), for the
-- per-weapon analysis of shot outcomes (st= and wpn= on every shot line).
local WEAPON_CLASS = {
    [9] = "awp", [40] = "scout", [11] = "auto", [38] = "auto",
    [64] = "r8", [1] = "deagle",
    [4] = "pistol", [61] = "pistol", [32] = "pistol", [36] = "pistol",
    [3] = "pistol", [30] = "pistol", [63] = "pistol", [2] = "pistol",
}
local function LocalWeaponClass()
    local me = entity.get_local_player()
    local w = me and entity.get_player_weapon(me)
    local idx = w and entity.get_prop(w, "m_iItemDefinitionIndex")
    if type(idx) ~= "number" then return "?" end
    return WEAPON_CLASS[bit.band(idx, 0xFFFF)] or "other"
end

local function BacktrackTicks(v)
    if not Finite(v) or v <= 0 then return 0 end
    if v < 1 then return TT(v) end
    return math.min(64, math.floor(v + 0.5))   -- sv_maxunlag caps real values far below 64
end

local function on_aim_fire(e)
    local t = e.target; if not t then return end
    local s64 = GetS64(t); local r = s64 and REC[s64]
    local praw = entity.get_prop(t, "m_flPoseParameter", 11)
    local me   = entity.get_local_player()
    SHOTS[e.id] = {
        s64     = s64,
        fy      = praw and (praw * CFG.POSE_SCALE - 60) or 0,
        meth    = r and r.last_meth or METH.RING,
        val     = r and r.last_val  or 0,
        side    = r and r.side      or 0,
        flip    = r and r.flip      or false,   -- store flip state at fire time
        conf    = r and r.conf      or 0,
        aa      = r and r.aa_type   or AA.UNKNOWN,
        state   = r and r.state     or nil,  -- movement state at fire time, for per-condition hit_mem
        -- Unit-agnostic on purpose. docs.gamesense.gs/docs/events/aim_fire
        -- contradicts itself: the field is described as "Amount of ticks
        -- the player was backtracked", but the page's own example wraps it
        -- in globals.toticks(), which only makes sense for seconds. v4.2
        -- trusted the example and always ran it through TT() -- if the
        -- description is right, every nonzero value became ticks*64 and
        -- failed the 1..16 range check below, so backtrack learning could
        -- never learn anything. The two readings can't overlap: seconds are
        -- capped by sv_maxunlag (<= 0.2, always < 1), while a nonzero tick
        -- count is a whole number >= 1. So (0,1) can only be seconds and
        -- >= 1 can only be ticks -- correct under either interpretation.
        bt      = BacktrackTicks(e.backtrack),
        -- The aimbot's own record-quality flags (aim_fire docs). A miss on
        -- an extrapolated or teleporting (LC-breaking) record was aimed at
        -- a guessed position, so on_aim_miss doesn't blame the yaw for it.
        extrapolated = e.extrapolated == true,
        teleported   = e.teleported == true,
        hc      = e.hit_chance or 0,
        wpn     = LocalWeaponClass(),
        cheat   = r and r.cheat or nil,
        -- What the ragebot aimed at and expected to deal (aim_fire fields),
        -- so logs show hit rate per weapon and aimed hitgroup -- the input
        -- the per-weapon aim model needs (docs/WEAPON_PLAN.md).
        aim_hg  = tonumber(e.hitgroup) or -1,
        aim_dmg = tonumber(e.damage) or -1,
        -- target health/armor at fire time: was a body shot lethal?
        thp     = tonumber(entity.get_prop(t, "m_iHealth")) or -1,
        tarm    = tonumber(entity.get_prop(t, "m_ArmorValue")) or -1,
        in_vuln = r and r.vuln_ttl > 0 or false,
        vuln_t  = r and r.vuln_type or nil,
        cfg     = r and r.config_type or nil,
        six_side = r and r.six_side or 0,  -- for 6lex agree/disagree calibration on hit
        -- Decision engine: the arm in effect at fire time, the sign actually
        -- applied, and every candidate's sign (copied -- rec.eng_sig is
        -- reused each tick), so the outcome can score all of them.
        eng     = (r and DET.engine and r.eng_arm) and EngSnap(r) or nil,
        tick    = globals.tickcount(),
        -- fire_time/srv_hits: lets on_aim_miss tell a real resolver miss
        -- apart from a stale/timed-out event or a server-side hit that got
        -- reported as a client-side miss (see on_aim_miss).
        fire_time  = globals.realtime(),
        srv_hits = me and (entity.get_prop(me, "m_totalHitsOnServer") or 0) or 0,
    }
end

-- A vuln window shot is a trial of that vuln type only when its value was
-- the one applied (the engine may have picked another candidate inside an
-- open window), and it is scored only on an outcome that says something
-- about the side: a head/neck hit (success) or a resolver miss (failure).
-- v7.8 counted every shot fired in the window as seen and every hit, body
-- included, as a success -- a body hit lands from either side, so a type
-- that never found the head still read ~50% and the trust gate could not
-- fire. In the v7.6 match log vuln_unk went 0 heads / 5 resolver misses
-- with 4 body hits, which v7.8 scored as 4/10.
local function VulnCredit(rec, d, head)
    if not (d.in_vuln and d.vuln_t and d.meth == "vuln_" .. d.vuln_t) then return end
    local vp = rec.vuln_profile[d.vuln_t]
    if not vp then vp = {seen = 0, hit = 0}; rec.vuln_profile[d.vuln_t] = vp end
    vp.seen = vp.seen + 1
    if head then
        vp.hit = vp.hit + 1
        rec.vuln_pref = d.vuln_t
        -- A head hit proves the torso read was right -- reset the unk streak
        if d.vuln_t == "unk" then rec.unk_miss_streak = 0 end
    elseif d.vuln_t == "unk" then
        -- Scales back unreliable unchokes (DetectVuln raises min_d)
        rec.unk_miss_streak = (rec.unk_miss_streak or 0) + 1
    end
end

local function on_aim_hit(e)
    STATE_VER = STATE_VER + 1
    brk.def = 0; brk.check = 0
    local d = SHOTS[e.id]; if not d then return end
    local rec = d.s64 and REC[d.s64]

    if rec then
        rec.total_hits       = rec.total_hits + 1
        rec.resolver_misses = 0
        rec.conf            = math.min(rec.conf + 0.06, 1.0)
        -- FIELD NAME NOTE: despite being called "kills" everywhere (rec,
        -- DB[s64], rv_stats/rv_db output), this counts every confirmed
        -- bullet HIT, any hitgroup/damage -- it's never gated on the target
        -- actually dying. Left unrenamed here and in the persisted DB
        -- schema: a real rename would silently orphan the "kills" field in
        -- everyone's already-saved database (old saves have data under
        -- that key; new code reading a renamed key would see nil). rv_stats/
        -- rv_db's displayed label was fixed to say "hits" instead, and the
        -- seeded_conf gate above documents what the underlying number
        -- actually requires.
        rec.kills           = rec.kills + 1
        -- Any RIFTVEIL-sourced hit (not built-in) proves our correction works
        -- on this player — reset the builtin failure streak so meta_aggressive
        -- doesn't permanently suppress the built-in if we later hit with hit_mem,
        -- 6lex, or any non-builtin method. Checked here, not inside the vuln gate,
        -- so hit_mem and ring-buffer hits also reset it correctly.
        if d.meth ~= "builtin" then
            rec.builtin_miss_streak = 0
        end
        -- Only count head and neck hits as confirmed side for hit_mem.
        -- Body shots (stomach, chest, limbs) have large hitboxes accessible
        -- from many angles — they don't confirm the head correction angle.
        -- hitgroup 1 = head, hitgroup 8 = neck (NOT 2 -- 2 is chest; see the
        -- file's own HG lookup table a few hundred lines up: generic=0,
        -- head=1, chest=2, stomach=3, left arm=4, right arm=5, left leg=6,
        -- right leg=7, neck=8, gear=10). The old check (hitgroup==1 or ==2)
        -- was checking head-or-CHEST, meaning every chest hit -- probably
        -- the single most common hitgroup in real fights -- fed into
        -- hit_side/hit_side_by_state/six_agree/six_disagree as if it were a
        -- confirmed head/neck hit, exactly the body-shot pollution this
        -- comment says it's guarding against.
        local is_head = e.hitgroup == 1 or e.hitgroup == 8
        -- BUG FIX: the confirmed side used to be the ring-buffer ESTIMATE at
        -- fire time (d.side, flip-adjusted) -- not the side we actually
        -- forced. Those differ whenever the applied correction wasn't a
        -- straight CfgAngle of the ring side: every suppress shot (which
        -- negates it by design, and was the most-used method in the logs --
        -- 4,129 of ~13,000 decisions), every vuln-window shot (their sign
        -- comes from torso/LBY reads, not the ring), and every engine inversion.
        -- A suppress head hit taught hit memory the OPPOSITE of what hit.
        -- The sign of the applied value is what the hit confirms; the ring
        -- side is only the fallback for built-in shots (val == 0).
        local applied = Sign(d.val or 0)
        local confirmed = (applied ~= 0) and applied or (d.flip and -d.side or d.side)
        if is_head and d.eng then ENG.Credit(rec, d.eng, true) end
        if confirmed ~= 0 and is_head then
            rec.hit_side  = confirmed
            rec.hit_count = rec.hit_count + 1
            -- Per-condition memory: same confirmed side, filed under the
            -- movement state that was active when the shot was fired (see
            -- hit_side_by_state comment in NewRec). Independent of the
            -- global hit_side above -- a hit while standing shouldn't
            -- overwrite what was learned while moving, and vice versa.
            if d.state then
                rec.hit_side_by_state[d.state]  = rec.hit_side
                rec.hit_count_by_state[d.state] =
                    (rec.hit_count_by_state[d.state] or 0) + 1
            end
            -- 6lex trust calibration: this confirmed head/neck hit IS the
            -- real side (same ground truth hit_mem just used above) --
            -- compare it against whatever 6lex claimed at fire time, if it
            -- made a call. Doesn't touch the extraction formula, only how
            -- much the override gate below trusts it for this player.
            if (d.six_side or 0) ~= 0 then
                if d.six_side == rec.hit_side then
                    rec.six_agree = (rec.six_agree or 0) + 1
                else
                    rec.six_disagree = (rec.six_disagree or 0) + 1
                end
            end
        end
        -- Backtrack depth learning. bt=0 means no backtrack used — skip it
        -- to avoid conflicting with preferred_bt=0 which means "not learned".
        local bt = d.bt or 0
        if bt >= 1 and bt <= 16 then
            rec.bt_hist[bt] = (rec.bt_hist[bt] or 0) + 1
            local best_bt, best_c = 0, 0
            for depth, count in pairs(rec.bt_hist) do
                if count > best_c then best_c = count; best_bt = depth end
            end
            rec.preferred_bt = best_bt
        end
        if is_head then VulnCredit(rec, d, true) end
    end

    info("hit", "player=%s group=%s dmg=%d meth=%s val=%.0f bt=%d st=%s wpn=%s hp=%d ar=%d aim=%s pdmg=%d%s%s%s",
        entity.get_player_name(e.target) or "?",
        HG[(tonumber(e.hitgroup) or -1) + 1] or "?",
        Finite(tonumber(e.damage)) and math.floor(e.damage) or 0,
        d.meth, d.val, d.bt, d.state or "?", d.wpn or "?", d.thp or -1, d.tarm or -1,
        HG[(d.aim_hg or -1) + 1] or "?", d.aim_dmg or -1,
        d.cheat and (" cht=" .. d.cheat) or "",
        d.in_vuln and (" !" .. d.vuln_t) or "", EngTag(d))
    SHOTS[e.id] = nil
end

local function on_aim_miss(e)
    STATE_VER = STATE_VER + 1
    local d = SHOTS[e.id]
    if not d then return end

    -- EVENT TIMEOUT: the miss event fired long after the shot (dropped or
    -- delayed resolution) -- this was never a clean outcome to begin with,
    -- resolver or otherwise, so it's discarded rather than counted as any
    -- kind of miss. Threshold matches the public aim-logging pattern this
    -- was adapted from.
    local is_timeout = (globals.realtime() - (d.fire_time or 0)) >= 0.5

    -- DAMAGE REJECTED: reason=="?" but the server's own hit counter moved
    -- between fire and this event -- a hit landed server-side despite the
    -- client reporting a miss. That's a hit-registration quirk, not
    -- evidence our correction angle was wrong, so it must not count toward
    -- resolver_misses/flip/soft-reset (those are supposed to mean "our
    -- angle guess was wrong," and this specifically isn't that).
    local reason  = e.reason or "?"
    local me      = entity.get_local_player()
    local is_dmg_rejected = reason == "?" and me
        and (d.srv_hits or 0) ~= (entity.get_prop(me, "m_totalHitsOnServer") or 0)

    if is_timeout or is_dmg_rejected then
        -- dmg_rejected specifically means m_totalHitsOnServer PROVES this
        -- shot actually landed -- that's not just "not evidence we were
        -- wrong" as the comment above says, it's positive evidence we were
        -- RIGHT, and it was being thrown away entirely (didn't count
        -- toward total_hits, hit_count, nothing). Credit total_hits now
        -- since that's confirmed regardless of hitgroup. Can't safely
        -- credit hit_side/vuln_profile.hit/six_agree here though -- unlike
        -- on_aim_hit, this event carries no hitgroup, and those three
        -- specifically require confirmed head/neck hits by design; crediting
        -- them off an unknown-hitgroup event risks polluting that
        -- calibration with body-shot data mislabeled as a head confirmation.
        -- is_timeout stays fully discarded -- genuinely ambiguous/stale,
        -- no confirmed outcome either way.
        if is_dmg_rejected then
            local rec = d.s64 and REC[d.s64]
            if rec then rec.total_hits = rec.total_hits + 1 end
        end
        if DET.verbose then
            dbg("miss", "player=%s discarded (%s) meth=%s val=%.0f -- %s",
                entity.get_player_name(e.target) or "?",
                is_timeout and "timeout" or "dmg_rejected", d.meth, d.val,
                is_dmg_rejected and "credited as total_hits" or "not counted")
        end
        SHOTS[e.id] = nil
        return
    end

    do
        local rec = d.s64 and REC[d.s64]
        if rec then rec.total_misses = rec.total_misses + 1 end
    end

    -- docs.gamesense.gs/docs/events/aim_miss lists exactly four reasons:
    -- 'spread', 'prediction error', 'death', and '?' ("unknown cause or
    -- resolver-related miss"). Only '?' belongs to the resolver. 'prediction
    -- error' used to be lumped in here, so every one flipped the tracked side
    -- and counted toward a soft reset that wipes hit memory -- blaming the
    -- resolver for the aimbot's movement prediction. It still feeds the
    -- backtrack-depth penalty below, which is what it's actually evidence of.
    -- Shots the aimbot itself flagged as extrapolated or teleported (target
    -- breaking lag compensation) are excluded too: when the position itself
    -- was a guess, a miss says nothing about whether our yaw was right.
    local is_resolver = (reason == "?" or reason == "")
                        and not d.extrapolated and not d.teleported

    warn("miss", "player=%s reason=%s meth=%s val=%.0f bt=%d hc=%.0f%% st=%s wpn=%s hp=%d ar=%d aim=%s pdmg=%d%s%s%s%s",
        entity.get_player_name(e.target) or "?",
        reason, d.meth, d.val, d.bt, d.hc, d.state or "?", d.wpn or "?", d.thp or -1, d.tarm or -1,
        HG[(d.aim_hg or -1) + 1] or "?", d.aim_dmg or -1,
        d.cheat and (" cht=" .. d.cheat) or "",
        d.in_vuln and (" !" .. d.vuln_t) or "",
        (d.extrapolated and " [extrap]" or "") .. (d.teleported and " [tele]" or ""),
        EngTag(d))

    if reason == "prediction error" then
        local rec = d.s64 and REC[d.s64]
        if rec and rec.preferred_bt > 0 then
            rec.bt_hist[rec.preferred_bt] =
                math.max(0, (rec.bt_hist[rec.preferred_bt] or 0) - 1)
            local best_bt, best_c = 0, 0
            for depth, count in pairs(rec.bt_hist) do
                if count > best_c then best_c = count; best_bt = depth end
            end
            rec.preferred_bt = best_bt
        end
    end

    if is_resolver then
        local rec = d.s64 and REC[d.s64]
        if rec then
            -- Engine credit goes first: the built-in branch below returns
            -- early, and a built-in miss is evidence the engine needs.
            if d.eng then ENG.Credit(rec, d.eng, false) end

            -- BUILT-IN FAIL TRACKING (meta_aggressive counter):
            -- When d.meth == "builtin", the built-in resolver was in control.
            -- That means it missed — NOT RIFTVEIL. Don't flip, don't soft-reset our data.
            -- Instead, count it against the built-in and activate meta_aggressive mode
            -- once it fails twice on the same player. At that point RIFTVEIL takes over
            -- permanently instead of releasing back to a resolver stuck in the old meta.
            if d.meth == "builtin" then
                rec.builtin_miss_streak = (rec.builtin_miss_streak or 0) + 1
                if rec.builtin_miss_streak >= 2 and not rec.meta_aggressive then
                    rec.meta_aggressive = true
                    warn("meta", "built-in failing player=%s streak=%d -> RIFTVEIL takes over",
                        entity.get_player_name(e.target) or "?", rec.builtin_miss_streak)
                end
                -- Built-in missed: don't corrupt our flip/hit_mem/conf data
                SHOTS[e.id] = nil
                return
            end

            -- Decide whether to flip.
            -- Vuln corrections are absolute angles — flipping after a vuln miss
            -- corrupts flip state and causes the dump pattern (shots 2-3 wrong side).
            -- High-confidence misses are prediction errors, not wrong-side guesses.
            -- hit_mem misses are confirmed-side data — don't discard with a flip.
            local should_flip = true
            if d.in_vuln then
                should_flip = false   -- absolute angle, flip is meaningless
                rec.vuln_ttl = 0
            elseif d.meth == METH.HIT_MEM then
                should_flip = false   -- confirmed side, don't flip it away
                -- This specific movement state's memory just proved wrong
                -- (the enemy likely desyncs differently in this state than
                -- whatever state it was learned in) -- clear only that
                -- state's entry so it relearns, without touching the global
                -- hit_side/other states' entries, which are still unproven
                -- wrong. A no-op if this miss actually came from the global
                -- fallback (state had no per-state data yet).
                if d.state then
                    rec.hit_side_by_state[d.state]  = 0
                    rec.hit_count_by_state[d.state] = 0
                end
            elseif (d.conf or 0) > 0.65 then
                should_flip = false   -- high confidence = prediction error, not wrong side
            end

            -- The legacy flip stands down while the engine decides: both
            -- adapt the tracked side, and flipping it underneath the engine
            -- mixes two conventions into its pose evidence. In
            -- tools/engine_sim.lua (flip modelled) the engine's average gain
            -- over the chain is +0.64 points with flip and +1.76 without;
            -- stale hit memory recovers +11.5 instead of +5.1.
            if should_flip and not DET.engine then
                rec.flip = not rec.flip
            end

            -- Only count non-vuln misses toward soft reset.
            -- Most vuln misses are prediction errors, not resolver failures.
            -- Counting them wipes hit_mem data prematurely.
            VulnCredit(rec, d, false)

            if not d.in_vuln then
                rec.resolver_misses = rec.resolver_misses + 1
                if rec.resolver_misses >= 3 then
                    warn("reset", "soft reset player=%s",
                         entity.get_player_name(e.target) or "?")
                    rec.conf = 0.22; rec.resolver_misses = 0
                    rec.flip = false
                    -- Under the engine, hit memory and engine evidence are
                    -- kept: the engine already demotes stale hit memory
                    -- through its hitmem arms, and wiping both threw that
                    -- evidence away. tools/engine_sim.lua: average gain
                    -- +1.76 -> +1.97, worst scenario -1.12 -> -0.60.
                    if not DET.engine then
                        rec.hit_side = 0; rec.hit_count = 0
                        rec.hit_side_by_state = {}; rec.hit_count_by_state = {}
                    end
                    -- Clear torso history so old cluster readings don't persist.
                    -- A soft reset means our corrections were wrong — the player likely
                    -- switched configs. Stale cluster = wrong correction for new config.
                    rec.torso_hist = {}
                    rec._sup_streak = 0
                    rec._sup_pause = 0
                    rec._shift_streak = 0
                    rec._brute_idx = 0
                end
            end
        end
    end
    SHOTS[e.id] = nil
end

-- ══════════════════════════════════════════════════════════════════
--  ESP FLAGS  (v3.1 — cut from 7 to 2)
--    VLN  crimson    — vulnerability window currently open (shoot now)
--    RES  green      — resolver confident, correction applied
--
--  6LX/HIT/SUP/DTB/MYW removed: none of them told you to DO anything
--  differently, they were internal diagnostics (which data source fired,
--  whether a struct read succeeded) leaking onto every enemy's ESP box at
--  once. HIT's meaning is already a subset of RES (hit-mem is one of the
--  methods RES lights up for). SUP/DTB/config/etc. still show in the
--  panel for whichever enemy is your current threat; 6LX/MYW are verbose-
--  log only now (ui_verb) since they were pure plumbing confirmation,
--  not something a player acts on mid-round.
-- ══════════════════════════════════════════════════════════════════
-- Flag state is computed once per tick in Update() (UpdateEspState) and the
-- callbacks are plain table lookups. They used to run per enemy, per flag,
-- per rendered FRAME -- each allocating a pcall closure and making three C
-- calls (ui.get, is_enemy, is_alive) to read values that only change once
-- per tick.
client.register_esp_flag("VLN", 232, 86, 86, function(ent) return ESP_VLN[ent] == true end)
client.register_esp_flag("RES", 150, 200, 70, function(ent) return ESP_RES[ent] == true end)

-- ══════════════════════════════════════════════════════════════════
--  INFO PANEL  (v7.1 redesign)
--
--  Drawn in gamesense's own visual language rather than a rounded card:
--  square corners, a two-layer 1px frame, the menu's tri-colour strip with
--  its darker second row, small pixel-font labels and a fixed width. The
--  width never follows the content: a box that resizes with every name
--  change reads as flicker at the edge of vision.
--
--    ┌────────────────────────────────────┐
--    │▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀│  strip
--    │ riftveil                 24/37  65% │  session score
--    │─────────────────────────────────────│
--    │ TARGET  zia anger              2WAY │
--    │ STATE   RESOLVED        HIT MEM -29 │
--    │ SIDE    ━━━━━━━━━┃             62%  │  centre-zero side meter
--    │ INFO    BT 2 · DEF                  │  only when there are tags
--    │ ALT     goralan            2WAY 40% │  the other enemy (2v2)
--    └────────────────────────────────────┘
--
--  Position persists through two hidden sliders: slider values survive
--  config save/load and script reload, a Lua local would not. Drag by the
--  header while the menu is open, so holding mouse1 to shoot can never
--  move it.
--
--  Built inside its own function: the main chunk sits at Lua's 200-local
--  limit (a do-block would still count against it), and nothing outside
--  the panel needs its helpers. Only DrawOverlay comes out.
-- ══════════════════════════════════════════════════════════════════
local DrawOverlay = (function()
local PANEL_RES    = 10000
local PANEL_W      = 200
local PANEL_PAD    = 6
local PANEL_HEAD_H = 19   -- 2px strip + 17px title row
local PANEL_ROW_H  = 14
local PANEL_LBL_W  = 44   -- label column
local PANEL_BODY_PAD = 3  -- above the first row and below the last

-- The gamesense menu strip, bright row and the half-brightness row
-- beneath it.
local STRIP_A = {59, 175, 222}
local STRIP_B = {202, 70, 205}
local STRIP_C = {201, 227, 58}

-- State colours carry meaning, so they stay fixed whatever the accent is.
local C_VULN  = {232, 86, 86}
local C_OK    = {150, 200, 70}
local C_BUILD = {220, 168, 72}
local C_TEXT  = {205, 205, 205}
local C_DIM   = {112, 112, 112}
local C_ALT   = {140, 140, 140}

local ui_panel_x = ui.new_slider("LUA","B","  Panel X", 0, PANEL_RES, 6800)
local ui_panel_y = ui.new_slider("LUA","B","  Panel Y", 0, PANEL_RES, 1400)
ui.set_visible(ui_panel_x, false)
ui.set_visible(ui_panel_y, false)

local function PanelPos()
    local w, h = client.screen_size()
    return ui.get(ui_panel_x) / PANEL_RES * w, ui.get(ui_panel_y) / PANEL_RES * h
end
local function SetPanelPos(x, y)
    local w, h = client.screen_size()
    ui.set(ui_panel_x, Clamp(x, 0, w) / w * PANEL_RES)
    ui.set(ui_panel_y, Clamp(y, 0, h) / h * PANEL_RES)
end

local drag = {held = false, grabbed = false, mx = 0, my = 0}

-- Called once per paint with the header's current screen rect.
local function UpdateDrag(px, py, pw, ph, menu_open)
    if not menu_open then
        -- No mouse or key reads while the menu is closed: a drag can't
        -- start then, and this ran on every frame.
        drag.held, drag.grabbed = false, false
        return false
    end
    local mx, my    = ui.mouse_position()
    local held      = menu_open and client.key_state(0x01) == true
    if held and not drag.held then
        drag.grabbed = mx >= px and mx <= px + pw and my >= py and my <= py + ph
        -- Re-base the delta on the grab frame, or the first frame of every
        -- drag jumps by however far the mouse moved since the last one.
        if drag.grabbed then drag.mx, drag.my = mx, my end
    elseif not held then
        drag.grabbed = false
    end
    if drag.grabbed then
        local x, y = PanelPos()
        SetPanelPos(x + (mx - drag.mx), y + (my - drag.my))
    end
    drag.held, drag.mx, drag.my = held, mx, my
    return menu_open
end

-- METH_LABEL: short display strings for each resolver method
local METH_LABEL = {
    [METH.HIT_MEM]  = "hit-mem",
    [METH.SIX_LEX]  = "6lex",
    [METH.PERIOD]   = "period",
    [METH.SUPPRESS] = "suppress",
    [METH.DEF_TICK] = "def-tick",
    [METH.LAGCOMP]  = "lagcomp",
    [METH.PHASE]    = "phase",
    [METH.RING]     = "ring",
    [METH.RING_SPK] = "ring-spk",
    [METH.YAW_CACHE]= "yaw-cache",
    [METH.SYM_FLIP] = "sym-flip",
    [METH.META_HOLD]= "meta",
    [METH.TRACK]    = "track",
}
local function MethTag(meth)
    return string.upper(((METH_LABEL[meth] or meth):gsub("[-_]", " ")))
end

-- Hoisted: this was allocated (13 tables) on every rendered frame, even
-- when no SHIFT flash was active.
local BOX_EDGES = {
    {1,2},{2,4},{4,3},{3,1},   -- bottom face
    {5,6},{6,8},{8,7},{7,5},   -- top face
    {1,5},{2,6},{3,7},{4,8},   -- verticals
}

-- Names are cut to the pixel width they have, by whole UTF-8 characters.
-- The old byte-based sub(1, 15) could split a Cyrillic letter in half and
-- draw a broken glyph; the logs are full of Cyrillic names. Cached per
-- name, since measure_text is a C call and names rarely change.
-- Keyed by width first: the same player can sit in the TARGET row and the
-- ALT row (different right tags, different room) within one match.
local FIT_CACHE = {}
local function FitText(s, max_w)
    local by_w = FIT_CACHE[max_w]
    if not by_w then by_w = {}; FIT_CACHE[max_w] = by_w end
    local hit = by_w[s]
    if hit then return hit end
    local out = s
    if renderer.measure_text("", s) > max_w then
        local chars = {}
        for ch in s:gmatch("[\1-\127\194-\244][\128-\191]*") do chars[#chars+1] = ch end
        local n = #chars
        repeat
            n = n - 1
            out = table.concat(chars, "", 1, math.max(n, 0)) .. "\xe2\x80\xa6"
        until n <= 1 or renderer.measure_text("", out) <= max_w
    end
    by_w[s] = out
    return out
end

-- Reused row records: {lbl, val, vf (font), vc (colour), rt (right text),
-- rc, rw (right width), bar (true for the side meter)}.
local function PanelRow(OV, i, lbl, val, vf, vc, rt, rc)
    local r = OV.rows[i]
    if not r then r = {}; OV.rows[i] = r end
    r.lbl, r.val, r.vf, r.vc = lbl, val, vf, vc
    r.rt, r.rc = rt, rc
    r.rw = (rt and rt ~= "") and renderer.measure_text("-", rt) or 0
    r.bar = nil
    return r
end

-- Content build, cached. paint runs every rendered frame (200-300 fps),
-- but everything here only changes with the resolver state (once per net
-- update, or on a shot event), the threat, or the accent.
local OVERLAY    = {ver = -1, rows = {}, n = 0, bar = 0}
local ACCENT_VER = 0
local FONT_H     = nil

local function BuildOverlay(OV, threat)
    if not FONT_H then
        local _, hs = renderer.measure_text("-", "A")
        local _, hn = renderer.measure_text("", "A")
        FONT_H = {small = hs or 9, norm = hn or 12}
    end
    local acc_hex = string.format("%02X%02X%02XFF", ACCENT[1], ACCENT[2], ACCENT[3])

    -- Header: brand left, this match's score right. total_hits and
    -- total_misses count every real outcome; hit_count and
    -- resolver_misses are resolver inputs, not a scoreboard.
    local mh, mm = 0, 0
    for _, r in pairs(REC) do
        mh = mh + (r.total_hits or 0)
        mm = mm + (r.total_misses or 0)
    end
    local total = mh + mm
    OV.brand = "\aCDCDCDFFrift\a" .. acc_hex .. "veil"
    if total > 0 then
        local pct = math.floor(mh / total * 100 + 0.5)
        OV.score   = string.format("\a707070FF%d/%d  \aCDCDCDFF%d%%", mh, total, pct)
        OV.score_w = renderer.measure_text("-", string.format("%d/%d  %d%%", mh, total, pct))
    else
        OV.score   = "\a707070FF--"
        OV.score_w = renderer.measure_text("-", "--")
    end

    local rec = nil
    if threat and entity.is_alive(threat) then
        local s64 = EIDX_S64[threat]
        rec = s64 and REC[s64]
    end

    local n, value_w = 0, PANEL_W - PANEL_PAD * 2 - PANEL_LBL_W
    OV.bar = 0
    if rec then
        local cf  = rec.conf
        local aa  = string.upper(AA_SHORT[rec.aa_type] or "?")
        local aaw = renderer.measure_text("-", aa)
        n = n + 1
        PanelRow(OV, n, "TARGET",
            FitText(entity.get_player_name(threat) or "?", value_w - aaw - 8), "", C_TEXT,
            aa, C_DIM)

        local meth    = rec.last_meth
        local has_val = isnum(rec.last_val) and math.abs(rec.last_val) > 0.5
        local ang     = has_val and string.format("%+d", math.floor(rec.last_val + 0.5)) or ""
        n = n + 1
        if rec.vuln_ttl > 0 then
            PanelRow(OV, n, "STATE", "VULN " .. string.upper(rec.vuln_type or "?"), "-", C_VULN,
                string.format("%dT  %s", rec.vuln_ttl, ang), C_DIM)
        elseif rec.resolved and cf >= CFG.CONF_ESP then
            local src = (meth and meth ~= "builtin") and (MethTag(meth) .. "  ") or ""
            PanelRow(OV, n, "STATE", "RESOLVED", "-", C_OK, src .. ang, C_DIM)
        else
            PanelRow(OV, n, "STATE", "BUILDING", "-", C_BUILD, nil, nil)
        end

        n = n + 1
        local side = rec.side
        local pct  = side ~= 0 and string.format("%d%%", math.floor(cf * 100)) or "--"
        PanelRow(OV, n, "SIDE", nil, nil, nil, pct, C_TEXT).bar = true
        OV.bar = Clamp(side * cf, -1, 1)

        local tags = {}
        if rec.cheat then tags[#tags+1] = string.upper(rec.cheat) end
        if rec.preferred_bt > 0 then tags[#tags+1] = "BT " .. rec.preferred_bt end
        if rec.config_type and rec.config_conf >= CFG.CFG_THRESH then
            tags[#tags+1] = string.upper((rec.config_type:gsub("_", " ")))
        end
        if rec.def_tickbase    then tags[#tags+1] = "DEF" end
        if LAST_SPIKE          then tags[#tags+1] = "SPIKE" end
        if rec.meta_aggressive then tags[#tags+1] = "AGG" end
        if rec.eng_by          then tags[#tags+1] = "ENG " .. ENG.Label(rec.eng_arm) end
        if DET.engine and ENG.AUD.safe then tags[#tags+1] = "ENG SAFE" end
        if #tags > 0 then
            n = n + 1
            PanelRow(OV, n, "INFO", table.concat(tags, "  \xc2\xb7  "), "-", C_DIM, nil, nil)
        end

        -- 2v2: the one other live enemy. LIVE_ENEMIES is cached once per
        -- net update, so no entity scan here.
        for _, p in ipairs(LIVE_ENEMIES) do
            if p ~= threat then
                local os64 = EIDX_S64[p]
                local orec = os64 and REC[os64]
                if orec then
                    local ort = string.format("%s  %d%%",
                        string.upper(AA_SHORT[orec.aa_type] or "?"), math.floor(orec.conf * 100))
                    local ortw = renderer.measure_text("-", ort)
                    n = n + 1
                    PanelRow(OV, n, "ALT",
                        FitText(entity.get_player_name(p) or "?", value_w - ortw - 8), "", C_ALT,
                        ort, C_DIM)
                end
                break
            end
        end
    elseif LAST_SPIKE then
        n = n + 1
        PanelRow(OV, n, "NET", "LAG SPIKE", "-", C_BUILD, nil, nil)
    end

    OV.n  = n
    OV.ph = PANEL_HEAD_H + (n > 0 and (n * PANEL_ROW_H + PANEL_BODY_PAD * 2) or 0)
    OV.ver, OV.threat, OV.acc = STATE_VER, threat, ACCENT_VER
end

local function DrawStrip(x, y, w)
    local a, b, c = STRIP_A, STRIP_B, STRIP_C
    local hw = math.floor(w / 2)
    renderer.gradient(x,      y,     hw,     1, a[1], a[2], a[3], 255, b[1], b[2], b[3], 255, true)
    renderer.gradient(x + hw, y,     w - hw, 1, b[1], b[2], b[3], 255, c[1], c[2], c[3], 255, true)
    renderer.gradient(x,      y + 1, hw,     1, a[1], a[2], a[3], 110, b[1], b[2], b[3], 110, true)
    renderer.gradient(x + hw, y + 1, w - hw, 1, b[1], b[2], b[3], 110, c[1], c[2], c[3], 110, true)
end

local ANIM = {h = nil, bar = 0}

local PP = {x = nil, y = nil, at = -1}
local function DrawPanel(threat)
    local OV = OVERLAY
    local now = globals.realtime()
    -- Rebuild on a new target or accent at once; for resolver-state changes
    -- (every tick) at most ~16 times a second. The text measurement in a
    -- rebuild is the costliest part of the panel, and 16 Hz is faster than
    -- anyone reads it.
    if OV.threat ~= threat or OV.acc ~= ACCENT_VER
       or (OV.ver ~= STATE_VER and now - (OV.built_at or -1) >= 0.06) then
        BuildOverlay(OV, threat)
        OV.built_at = now
    end

    -- Panel position: two slider reads and the screen size, re-read only
    -- while the menu is open (it can be dragged then) or every 2 s.
    local menu_open = ui.is_menu_open()
    if menu_open or not PP.x or now - PP.at > 2 then
        local x, y = PanelPos()
        PP.x, PP.y, PP.at = math.floor(x), math.floor(y), now
    end
    local px, py = PP.x, PP.y
    UpdateDrag(px, py, PANEL_W, PANEL_HEAD_H, menu_open)

    -- Height eases toward its target, so rows slide in and out instead of
    -- the box snapping between sizes when a target appears.
    local ft = globals.frametime()
    local k  = math.min(1, ft * 14)
    local h  = ANIM.h or OV.ph
    h = h + (OV.ph - h) * k
    if math.abs(OV.ph - h) < 0.5 then h = OV.ph end
    ANIM.h = h
    ANIM.bar = ANIM.bar + (OV.bar - ANIM.bar) * math.min(1, ft * 10)
    local ph = math.floor(h + 0.5)
    local w  = PANEL_W

    -- Frame: black outline, 1px bevel, opaque body. Opaque on purpose --
    -- the stacked layers only read as edges when nothing blends through.
    renderer.rectangle(px - 2, py - 2, w + 4, ph + 4, 10, 10, 10, 255)
    renderer.rectangle(px - 1, py - 1, w + 2, ph + 2, 46, 46, 46, 255)
    renderer.rectangle(px,     py,     w,     ph,     19, 19, 19, 255)
    if menu_open then
        -- Accent outline while the menu is open: the box is draggable now.
        local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
        local oa = drag.grabbed and 220 or 110
        renderer.rectangle(px - 3,     py - 3,      w + 6, 1,      ar, ag, ab, oa)
        renderer.rectangle(px - 3,     py + ph + 2, w + 6, 1,      ar, ag, ab, oa)
        renderer.rectangle(px - 3,     py - 2,      1,     ph + 4, ar, ag, ab, oa)
        renderer.rectangle(px + w + 2, py - 2,      1,     ph + 4, ar, ag, ab, oa)
    end
    DrawStrip(px, py, w)

    local fh = FONT_H
    local ty_norm  = math.floor((PANEL_HEAD_H - 2 - fh.norm) / 2)
    local ty_small = math.floor((PANEL_HEAD_H - 2 - fh.small) / 2)
    renderer.text(px + PANEL_PAD, py + 2 + ty_norm, 205, 205, 205, 255, "", 0, OV.brand)
    renderer.text(px + w - PANEL_PAD - OV.score_w, py + 2 + ty_small, 205, 205, 205, 255, "-", 0, OV.score)

    if OV.n == 0 or ph <= PANEL_HEAD_H then return end
    renderer.rectangle(px, py + PANEL_HEAD_H, w, 1, 33, 33, 33, 255)

    local row_small = math.floor((PANEL_ROW_H - fh.small) / 2)
    local row_norm  = math.floor((PANEL_ROW_H - fh.norm) / 2)
    local vx     = px + PANEL_PAD + PANEL_LBL_W
    local bottom = py + ph - PANEL_BODY_PAD
    local ry     = py + PANEL_HEAD_H + PANEL_BODY_PAD
    for i = 1, OV.n do
        if ry + PANEL_ROW_H > bottom + 1 then break end  -- still easing open
        local r = OV.rows[i]
        renderer.text(px + PANEL_PAD, ry + row_small, C_DIM[1], C_DIM[2], C_DIM[3], 255, "-", 0, r.lbl)
        if r.bar then
            -- Centre-zero side meter: the fill grows from the centre mark
            -- toward the side we track, its length is the confidence.
            local bx0 = vx
            local bw  = w - PANEL_PAD - 34 - (vx - px)
            local cx  = bx0 + math.floor(bw / 2)
            local by  = ry + math.floor((PANEL_ROW_H - 4) / 2)
            renderer.rectangle(bx0, by, bw, 4, 34, 34, 34, 255)
            local v  = ANIM.bar
            local fw = math.floor(math.abs(v) * (bw / 2) + 0.5)
            if fw > 0 then
                local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
                if v < 0 then
                    renderer.gradient(cx - fw, by, fw, 4, ar, ag, ab, 255, ar, ag, ab, 110, true)
                else
                    renderer.gradient(cx, by, fw, 4, ar, ag, ab, 110, ar, ag, ab, 255, true)
                end
            end
            renderer.rectangle(cx, by - 2, 1, 8, 96, 96, 96, 255)
        elseif r.val then
            local c = r.vc
            renderer.text(vx, ry + (r.vf == "-" and row_small or row_norm),
                c[1], c[2], c[3], 255, r.vf, 0, r.val)
        end
        if r.rw > 0 then
            local c = r.rc
            renderer.text(px + w - PANEL_PAD - r.rw, ry + row_small, c[1], c[2], c[3], 255, "-", 0, r.rt)
        end
        ry = ry + PANEL_ROW_H
    end
end

-- World-space SHIFT marker: a brief, fading tag and wireframe box over any
-- live enemy whose backtrack record just broke (the origin-jump check in
-- ProcessPlayer), not only the current threat. The flash decays even with
-- the marker hidden, so switching it back on never replays a stale one.
local function DrawShiftMarkers(show)
    local decay = globals.frametime() * 2  -- fades out over ~0.5s
    for _, p in ipairs(LIVE_ENEMIES) do
        local s2 = EIDX_S64[p]
        local r2 = s2 and REC[s2]
        if r2 and (r2._shift_flash or 0) > 0 then
            r2._shift_flash = math.max(0, r2._shift_flash - decay)
            if show and r2._shift_flash > 0 then
                local ox2, oy2, oz2 = entity.get_origin(p)
                local a = math.floor(r2._shift_flash * 255)
                local sx, sy
                if isnum(ox2) and isnum(oy2) and isnum(oz2) then
                    sx, sy = renderer.world_to_screen(ox2, oy2, oz2 + 78)
                    if sx then
                        renderer.text(sx, sy, C_BUILD[1], C_BUILD[2], C_BUILD[3], a, "-c", 0, "SHIFT")
                    end
                end

                local box = r2._shift_box
                if box then
                    local mnx, mny, mnz = entity.get_prop(p, "m_vecMins")
                    local mxx, mxy, mxz = entity.get_prop(p, "m_vecMaxs")
                    if isnum(mnx) and isnum(mxx) then
                        local bx, by, bz = box[1], box[2], box[3]
                        local corners = {
                            {bx+mnx, by+mny, bz+mnz}, {bx+mxx, by+mny, bz+mnz},
                            {bx+mnx, by+mxy, bz+mnz}, {bx+mxx, by+mxy, bz+mnz},
                            {bx+mnx, by+mny, bz+mxz}, {bx+mxx, by+mny, bz+mxz},
                            {bx+mnx, by+mxy, bz+mxz}, {bx+mxx, by+mxy, bz+mxz},
                        }
                        local scr = {}
                        for ci = 1, 8 do
                            local cx, cy, cz = corners[ci][1], corners[ci][2], corners[ci][3]
                            local ssx, ssy = renderer.world_to_screen(cx, cy, cz)
                            if ssx then scr[ci] = {ssx, ssy} end
                        end
                        local ba = math.floor(a * 0.8)
                        for _, e in ipairs(BOX_EDGES) do
                            local p1, p2 = scr[e[1]], scr[e[2]]
                            if p1 and p2 then
                                renderer.line(p1[1], p1[2], p2[1], p2[2], C_BUILD[1], C_BUILD[2], C_BUILD[3], ba)
                            end
                        end
                        -- Tether to the box centre, not a corner: a corner
                        -- sits on the far side of the box at many angles.
                        local ccx = bx + (mnx + mxx) / 2
                        local ccy = by + (mny + mxy) / 2
                        local ccz = bz + (mnz + mxz) / 2
                        local tsx, tsy = renderer.world_to_screen(ccx, ccy, ccz)
                        if sx and tsx then
                            renderer.line(sx, sy, tsx, tsy, C_BUILD[1], C_BUILD[2], C_BUILD[3], ba)
                        end
                    end
                end
            end
        end
    end
end

return function()
    -- The accent follows gamesense's Menu color. ui.get on it returns four
    -- numbers, no allocation, so polling it per frame is cheaper than
    -- trusting a callback on an element this script doesn't own.
    if ReadAccent() then
        ACCENT_VER = ACCENT_VER + 1
        ui.set(ui_title, TitleText())
    end
    if not ui.get(ui_on) then return end
    -- Threat as read once per tick in Update, not queried every frame.
    if IND.panel then DrawPanel(CTX.threat) end
    DrawShiftMarkers(IND.shift)
end
end)() -- panel scope

-- ══════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════
-- Also clears "High priority" now: every other release path clears it, but
-- this one didn't, so after a round reset or script unload every enemy we
-- had corrected stayed flagged high-priority in gamesense's player list.
-- Written last so a failure on it can't block the three core fields.
local function reset_one(i)
    plist.set(i, "Force body yaw", false)
    plist.set(i, "Force body yaw value", 0)
    plist.set(i, "Correction active", false)
    plist.set(i, "High priority", false)
end
local function ResetPlist()
    for i = 1, 64 do pcall(reset_one, i) end
    PL_CACHE = {}; PL_KNOWN = {}
end

local function EndMatch()
    info("match", "ended -- flushing DB")
    FlushDB()
    ResetPlist()
    ResetMatchState()
    RestoreInterp()
    flush_log()
end

local function FullShutdown()
    EndMatch()
    pcall(function()
        cvar.cl_interpolate:set_int(ORIG_IPOLATE)
        cvar.cl_interp_ratio:set_int(ORIG_RATIO)
        cvar.cl_interp:set_float(ORIG_INTERP)
    end)
    flush_log()
end

-- ══════════════════════════════════════════════════════════════════
--  PERFORMANCE PROFILER  (rv_perf)
--
--  Every callback runs through Instrument: a pcall, so an error can never
--  repeat per frame into the console (it is logged once, then every 1000th
--  time), and -- while rv_perf is measuring -- a high-resolution timer
--  (QueryPerformanceCounter through LuaJIT's FFI) around the call.
-- ══════════════════════════════════════════════════════════════════
PERF = {on = false, since = 0, stat = {}, order = {}}
PERF.qpc = (function()
    pcall(ffi.cdef, [[
        int QueryPerformanceCounter(int64_t *count);
        int QueryPerformanceFrequency(int64_t *freq);
    ]])
    local ok, C = pcall(function()
        local c = ffi.C
        local _ = c.QueryPerformanceCounter and c.QueryPerformanceFrequency
        return c
    end)
    if not ok or not C then return nil end
    local ok_new, buf = pcall(ffi.new, "int64_t[1]")
    if not ok_new or not buf then return nil end
    local ok_f = pcall(C.QueryPerformanceFrequency, buf)
    local freq = ok_f and tonumber(buf[0])
    if not freq or freq <= 0 then return nil end
    return function()
        C.QueryPerformanceCounter(buf)
        return tonumber(buf[0]) * 1e6 / freq          -- microseconds
    end
end)()

function PERF.Reset()
    for _, st in pairs(PERF.stat) do st.n, st.sum, st.max, st.err = 0, 0, 0, 0 end
    PERF.since = globals.realtime()
end

function PERF.Report()
    local secs = math.max(0.001, globals.realtime() - PERF.since)
    local out = {string.format("[RIFTVEIL] === PERF === %.1f s measured%s", secs,
        PERF.qpc and "" or " (no timer: error counts only)")}
    local total = 0
    for _, name in ipairs(PERF.order) do
        local st = PERF.stat[name]
        local per_s = st.sum / secs
        total = total + per_s
        out[#out + 1] = string.format("  %-14s %7.0f calls/s  avg %7.1f us  max %8.1f us  %6.2f ms/s  errors %d",
            name, st.n / secs, st.n > 0 and st.sum / st.n or 0, st.max, per_s / 1000, st.err)
    end
    out[#out + 1] = string.format("  total %.2f ms per second of game time (%.2f%% of one core)",
        total / 1000, total / 1e4)
    return table.concat(out, "\n")
end

local function Instrument(name, fn)
    local st = {n = 0, sum = 0, max = 0, err = 0}
    PERF.stat[name] = st
    PERF.order[#PERF.order + 1] = name
    local clock = PERF.qpc
    return function(...)
        local t0 = PERF.on and clock and clock()
        local ok, r = pcall(fn, ...)
        if t0 then
            local dt = clock() - t0
            st.n, st.sum = st.n + 1, st.sum + dt
            if dt > st.max then st.max = dt end
        end
        if not ok then
            st.err = st.err + 1
            if st.err == 1 or st.err % 1000 == 0 then
                err(name, "%s (x%d)", tostring(r), st.err)
                if st.err == 1 then client.log("[RIFTVEIL] error in " .. name .. ": " .. tostring(r)) end
            end
            return nil
        end
        return r
    end
end

-- ══════════════════════════════════════════════════════════════════
--  EVENT REGISTRATION
-- ══════════════════════════════════════════════════════════════════
client.set_event_callback("net_update_end", Instrument("net_update", function()
    if entity.is_alive(entity.get_local_player()) then Update() end
end))
client.set_event_callback("paint",       Instrument("paint", DrawOverlay))
client.set_event_callback("aim_fire",    Instrument("aim_fire", on_aim_fire))
client.set_event_callback("aim_miss",    Instrument("aim_miss", on_aim_miss))
client.set_event_callback("aim_hit",     Instrument("aim_hit", on_aim_hit))
-- Round start is a natural pause: flush the log there so a copied log
-- always holds every finished round.
client.set_event_callback("round_start", function() ResetPlist(); flush_log() end)
client.set_event_callback("game_end",    EndMatch)
client.set_event_callback("level_init",  EndMatch)
client.set_event_callback("shutdown",    FullShutdown)
client.set_event_callback("disconnect",  FullShutdown)

info("init", "RIFTVEIL v" .. RV_VERSION .. " loaded -- commands: rv_stats  rv_engine  rv_perf  rv_db  rv_save  rv_clear  rv_reset  rv_wipe")
flush_log()
