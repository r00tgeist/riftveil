-- ════════════════════════════════════════════════════════════════════
--  RIFTVEIL  v8.5.2  ·  gamesense.pub  ·  unmatched.gg
--  Two-tier memory · period prediction · config recognition
--  Vulnerability windows · cheat revealer · per-cheat method trust
-- ════════════════════════════════════════════════════════════════════
--  v8.0 – The v6.2 decision code (74% head on resolver-decided shots
--          in the logs, against 49% for v6.7-v7.9), plus fixes that
--          change no decision, a built-in cheat revealer and learned
--          per-cheat method trust. Full notes: CHANGELOG.md. The v6.2
--          notes below describe the decision code as it is.
--  v8.1 – The v7.9 menu and info panel back on top of that core.
--  v8.2 – Condition detection by physics, cached player-list writes,
--          rv_perf, weapon/target logging, aim-field probe. Status and
--          next steps: docs/ROADMAP.md.
--  v8.3 – Weapon aim policy: prefer body when one body shot kills, safe
--          point after two resolver misses in a row, fields verified.
--  v8.4 – Weapon aim on traced damage: body only when a body shot kills
--          from here; when only the head kills (wallbang, cover) body
--          preference is switched off. Self-calibrating. docs/WEAPON_PLAN.md
--  v8.5 – State tracker debugged against movement physics: weapon/scope
--          aware thresholds, fake duck, unreadable flags / velocity.
--          tools/state_test.lua; docs/STATE_AUDIT.md
-- ════════════════════════════════════════════════════════════════════
--  Changelog
--    v6.2 – Senior resolver-review pass #3, focused on resolver-domain
--            correctness this time (window/priority handling, flip and
--            side-sign conventions, hit_side encoding-immutability)
--            rather than generic Lua bugs or platform-API misuse (already
--            covered in the previous two passes).
--            Found one real issue: DetectVuln re-evaluates all 7 trigger
--            conditions independently every tick with zero awareness of
--            rec.vuln_ttl. If a window was already open (say an LBY snap
--            with 2 ticks still left) and a DIFFERENT vtype fired on the
--            very next tick with a shorter base_ttl (say a UNK unchoke,
--            base_ttl=1), the old code unconditionally overwrote
--            rec.vuln_ttl down to the new value -- cutting the still-
--            active, still-valid window off early and handing the aimbot
--            less time to find a shot than either signal alone would
--            have given. Fixed with rec.vuln_ttl = math.max(rec.vuln_ttl,
--            base_ttl, lc_ttl) -- provably monotonic (a fresh detection
--            can now only extend/refresh the window, never shrink it),
--            so unlike the KNOWN_CFGS tolerance-overlap observation
--            (v5.9, still just flagged, not changed -- would need real
--            per-type accuracy data to justify a specific retune), this
--            one doesn't require guessing at resolver accuracy to know
--            it's strictly no worse and sometimes better. vuln_type/
--            vuln_val still update to the freshest read (presumably the
--            more current correction) -- only the ttl is protected.
--            Also specifically re-verified (no changes needed): the
--            override-branch priority chain (vuln > 6lex > hit_mem >
--            meta_hold > suppress > release) makes sense in reliability
--            order; hit_side's flip-encoding is genuinely immutable once
--            stored (a later rec.flip toggle correctly never re-applies
--            to an already-encoded hit_side, confirmed by tracing every
--            "apply flip" site against tracked_method); the suppress
--            branch's angle math (negates the BELIEVED real side, not a
--            random one); and the +/- side-sign convention (positive =
--            right) is consistent across every one of the 8 side-sourcing
--            methods (ring/hit_mem/6lex/period/lagcomp/def_tick/
--            ring_spike/yaw_cache) plus vuln and suppress.
--    v6.1 – Senior gamesense-review pass #2, focused on platform-API
--            correctness (ui/event/entity/plist call semantics) rather
--            than internal resolver logic. Found a real UI/cvar state
--            desync bug: ui.set_callback only fires on a CHANGE event --
--            it does NOT run just because a checkbox loads already-
--            checked from a saved gamesense config. RefreshVis already
--            accounts for this (it's manually self-invoked once right
--            after ui.set_callback(ui_on, RefreshVis) so panel-item
--            visibility syncs with a persisted ui_on checkbox on load),
--            but ui_tight's own callback never got the same treatment.
--            Concretely: if "Tight Interpolation" was left checked at
--            the end of a prior session, reloading the script restores
--            the checkbox to checked (gamesense persists ui state), but
--            the actual cl_interp/cl_interp_ratio/cl_interpolate cvars
--            stay at whatever ORIG_* captured at THIS load -- silently
--            desynced from what the UI displays as active, and nothing
--            forces a re-toggle to notice since the checkbox already
--            reads "on". Named the callback (ApplyTightInterp) and
--            self-invoke it once after registration, mirroring
--            RefreshVis's own pattern exactly.
--            Also checked (no issues found) every ui.*/entity.*/plist.*/
--            client.* call signature against the platform's actual
--            semantics: register_esp_flag's (name, r,g,b, callback)
--            shape, ui.new_color_picker's 4-value ui.get() return,
--            client.key_state's VK_LBUTTON=0x01 check, plist.set's four
--            field names used throughout (Force body yaw[/ value],
--            Correction active, High priority), the aim_fire/aim_hit/
--            aim_miss event field names (id/target/backtrack/hitgroup/
--            reason/damage), and console_input's suppress-return
--            contract -- all consistent with prior doc-verified usage
--            elsewhere in this same file.
--    v6.0 – Full senior-review pass, line by line, top to bottom (not
--            triggered by a specific log this time). Found a real,
--            previously-undetected bug in IsHold: it reset `stable` to 0
--            on a sign mismatch but kept scanning OLDER ring-buffer
--            entries afterward instead of stopping there. Since a "held"
--            AA pattern is supposed to mean an unbroken run of the same
--            sign ending at the CURRENT tick, a mismatch at the most
--            recent samples should disqualify it immediately -- but the
--            old code could have a real flip 1-2 ticks ago, then a long
--            coincidental run of matches further back in the same short
--            window push `stable` back over CFG.HOLD_STABLE by the end of
--            the loop. Concretely, with HOLD_STABLE=4 and recent-to-old
--            signs [+, -, +,+,+,+,+]: the flip at offset 1 should mean
--            "not holding," but the old logic finishes with stable=5 and
--            reports AA.HOLD anyway. DetectAA then skips its normal flip-
--            counting/cluster classification for that tick and returns a
--            wrong AA type + side straight from the current sample --
--            feeding wrong data into rec.aa_type, rec.conf, and the
--            is_jitter/is_sym side-tracking checks downstream. Fixed to
--            break out at the first mismatch instead of resetting and
--            continuing, since anything before a break in the streak
--            can't contribute to whether the sign is held right now.
--            Reviewed and confirmed sound (no changes): RingBuffer index
--            math, MeanSidePose/CountClusters/IsSkitter, TorsoCluster's
--            circular-mean clustering, ChokedPkts/TrackDT/IsDefTick,
--            LCTicks/WeDefensive, RecognizeCfg's hysteresis, PredictSide's
--            median-gap math, CfgAngle/VelCap/LiveCap, DetectVuln's 6
--            window branches, ProcessPlayer's save-phase (prev_* always
--            written regardless of which early-break path was taken),
--            FlushDB's weighting, on_aim_fire/hit/miss's event handling,
--            the panel drag/layout code, and the SHIFT box geometry.
--    v5.9 – Found the v5.8 corr_cap fix wasn't the only place it applied.
--            tracked_side's unconditional side-tracking chain (used by the
--            META_HOLD fallback) sets tracked_method = HIT_MEM off
--            rec.hit_side whenever hit_count>=2, regardless of whether the
--            "Hit Memory" checkbox is even on -- so META_HOLD could still
--            clamp a confirmed hit_mem correction to literal 0 at high
--            target speed through this second call site, even after [3]'s
--            own call site was fixed. Now uses live_cap when
--            tracked_method == HIT_MEM there too.
--            Also traced KNOWN_CFGS' own numbers: luasense_beta's canonical
--            average (26,41) sits inside symmetric's acceptance band
--            (error 15 vs. threshold 16), luasense_std's average (30,38)
--            sits inside symmetric's band too (error 8), and both sit
--            inside each other's. All three known profiles mutually
--            overlap in RecognizeCfg's matching space -- hysteresis
--            (CFG_SWITCH_MARGIN=6) mostly holds a pick steady, but real
--            per-match measurement noise can occasionally punch through
--            the gap, which is consistent with (not fully explaining) the
--            occasional config switches seen in logs for players near a
--            boundary. Not changing the tolerance/margin numbers without
--            real per-type accuracy data across multiple logs -- flagging
--            it rather than guessing at a retune.
--    v5.8 – Diagnosed a debug log complaint ("it feels horrible") down to
--            two real bugs:
--            (1) MAJOR: hit_mem overrides (the [3] branch, confirmed-side
--            corrections from an actual prior hit on this player/state)
--            were capped with corr_cap -- VelCap's velocity-scaled cap,
--            which falls LINEARLY TO EXACTLY 0 once the target's speed
--            reaches CFG.VEL_CAP_SPD (580u/s). A bhopping/fast-strafing
--            enemy crosses that constantly, and CfgAngle's Clamp(raw, -cap,
--            cap) with cap=0 forces the correction to literally 0 degrees --
--            aim dead-center, no yaw correction at all, worse than a coin
--            flip. Caught directly in a debug log:
--            "meth=hit_mem val=0.0". The comment above VelCap's call site
--            already said corr_cap is "used only to clamp CfgAngle's static
--            guesses" -- hit_mem is confirmed data, not a guess, and was
--            never supposed to be in scope. Switched both hit_mem call
--            sites to live_cap (the engine's real desync bound, unscaled by
--            velocity) instead of corr_cap.
--            (2) "symmetric" is a real, recognized KNOWN_CFGS entry
--            (avg_left=35, avg_right=35) but had no matching CFG_COUNTER
--            table, so CfgAngle(..., "symmetric", ...) always fell through
--            to ASYM_FALLBACK -- angles calibrated for an asymmetric desync
--            pattern, applied to a player already confirmed to desync
--            symmetrically. Added CFG_COUNTER.symmetric using the same
--            35/35 flat value per state (no per-state symmetric calibration
--            data exists yet). Seen in the same log: a player classified
--            "symmetric" repeatedly, with worse-than-expected accuracy and
--            config-switch churn, in the same session this angle mismatch
--            was active.
--    v5.7 – Bug review pass #3. Found and fixed four more:
--            (1) MAJOR: on_aim_hit's is_head check used hitgroup==2 for
--            "neck", but the file's OWN HG lookup table a few hundred
--            lines up proves hitgroup 2 is CHEST (generic=0, head=1,
--            chest=2, stomach=3, left arm=4, right arm=5, left leg=6,
--            right leg=7, neck=8, gear=10) -- an internal contradiction
--            within the same file, not a guess against outside docs.
--            Every chest hit -- likely the single most common hitgroup in
--            real fights -- has been feeding hit_side/hit_side_by_state/
--            six_agree/six_disagree as if it were a confirmed head/neck
--            hit, exactly the body-shot pollution the surrounding comment
--            says it guards against. Fixed to hitgroup==1 or ==8.
--            (2) Panel drag snapped on the first frame of every drag: the
--            delta baseline (drag.mx/my) wasn't reset to the click
--            position when a grab started, so the first frame applied
--            whatever incidental mouse movement had happened since the
--            last unrelated frame. Now reset at grab-start.
--            (3) on_aim_miss's dmg_rejected path discarded a shot that
--            m_totalHitsOnServer PROVES actually landed, crediting it
--            nowhere at all. Now credited to total_hits (hitgroup is
--            unknown for this event type, so hit_side/vuln_profile.hit/
--            six_agree -- which specifically require confirmed head/neck
--            hitgroup -- are correctly left uncredited).
--            (4) rec.kills (and DB[s64].kills) has counted every confirmed
--            hit, any hitgroup, since on_aim_hit was written -- never
--            gated on the target dying. Left the field name alone (a
--            rename would silently orphan everyone's already-saved DB
--            entries under the old key) but fixed the misleading rv_db/
--            debug-log display from "kills" to "hits", and documented
--            what the seeded_conf gate's "db.kills >= 3" actually requires.
--    v5.6 – Fixed the suppress streak-cap's pause window, which never
--            actually functioned. The single-counter design reset
--            _sup_streak to 0 in the non-suppress fallback branches the
--            instant the 8-tick cap blocked suppress for even one tick --
--            so the documented "pause 4 ticks, then resume" behavior
--            never happened: suppress silently resumed on the very next
--            tick instead, every time, since 0 < 8 immediately re-passed
--            the gate. The streak_ok >= 12 branch was provably dead code.
--            Rebuilt with a dedicated pause counter (_sup_pause) and a
--            sup_pausing flag so the fallback branches (meta_hold/builtin
--            release) know not to blow the counters away while a
--            deliberate pause is genuinely in progress. Traced the full
--            cycle by hand: 8 ticks suppress -> 4 ticks paused (shots go
--            through normally) -> counters reset -> fresh cycle, matching
--            the original design intent for the first time.
--    v5.5 – Menu + bug review pass.
--            (1) Renamed menu labels away from internal codenames a
--            first-time user has no way to decode: "6lex extraction" ->
--            "Desync Angle Detection", "Vulnerability windows" ->
--            "Vulnerability Detection", "Hit-side memory" -> "Hit
--            Memory", "Period prediction" -> "Jitter Prediction", "Tight
--            interp" -> "Tight Interpolation", "Indicators" -> "ESP
--            Indicators", "Verbose log" -> "Verbose Logging", "Panel
--            accent" -> "Panel Accent Color". Only the displayed strings
--            changed -- the underlying ui_* variable names (never shown
--            to the user) are untouched, so no logic moved.
--            (2) Found and fixed a real dead-toggle bug while reviewing:
--            [EXP] Asymmetric Angles (ui_asym) was created, added to the
--            SAFE/EXP visibility list, and had a comment right next to
--            CfgAngle claiming it "feeds into CfgAngle via ASYM_FALLBACK
--            vs CFG_COUNTER selection" -- but CfgAngle never actually
--            checked it. Toggling that checkbox did nothing at all. Now
--            wired as documented: ON keeps the existing per-side L/R
--            fallback table, OFF averages it into one symmetric magnitude
--            for both sides -- only affects players with no confidently
--            recognized config (TrustedCfg fails), never touches
--            CFG_COUNTER's per-config tables.
--            Also reviewed (no changes needed, already correct):
--            RecognizeCfg's switch hysteresis, PredictSide's jitter-period
--            math, the DCK cooldown set/decrement lifecycle, and the
--            STP/PKA/LND/CTR vuln branches.
--    v5.4 – CRITICAL fix to the v5.2 vuln-type trust gate: vuln_profile's
--            "seen" counter was incremented every time DetectVuln logged a
--            detection, not once per actual shot taken. Checked against a
--            real debug log: one player logged 110 "unk" detections in a
--            single match against roughly a dozen actual shots at them --
--            most vuln windows never get shot at (target not visible/not
--            aimed-at during the brief ttl). That inflated denominator
--            crushed hit/seen toward near-zero regardless of true
--            accuracy, meaning the v5.2 gate would have started
--            distrust-probing perfectly good vuln types almost
--            immediately -- actively working against hit rate, the
--            opposite of its purpose. Compounding it, on_aim_miss ALSO
--            incremented seen a second time for every vuln miss (but hits
--            were never double-counted), biasing the already-wrong ratio
--            further downward specifically on misses.
--            Fixed by crediting seen exactly once per shot, in
--            on_aim_fire when a shot is fired during an open vuln
--            window -- the same "one shot, one trial" definition
--            on_aim_hit already uses for hit -- and removing both the
--            per-detection increment and the duplicate miss-path
--            increment. seen/hit are now symmetric: exactly one of each
--            per shot outcome, nothing double-counted.
--    v5.3 – Fixed the SHIFT box's tether line: it targeted scr[1], one
--            arbitrary box corner (bottom, min-x, min-y), instead of the
--            box's center. That corner sits on the far side of the box
--            from the camera at plenty of viewing angles, so the tether
--            looked like it stabbed into a random edge instead of
--            pointing at the box -- reported as "horrible"/asymmetric.
--            The box's own 12-edge geometry was already correct (checked
--            the corner math against m_vecMins/m_vecMaxs -- forms a
--            proper symmetric rectangular prism); only the tether target
--            was wrong. Now targets the box's actual center, which stays
--            a consistent anchor regardless of viewing angle.
--    v5.2 – Per-player, per-vuln-TYPE trust gate (VulnTrusted). vuln_profile
--            (seen/hit per VTYPE) was exposed as a read-only rv_stats/rv_db
--            diagnostic in v4.7 specifically because there wasn't a real
--            per-type hit ratio to calibrate a live gate against yet --
--            guessing a threshold then risked suppressing a type that was
--            actually fine. Now wired up, same idea as the 6lex agree/
--            disagree calibration (v4.1) applied to this data: a type
--            needs >=6 real detections (VULN_TRUST_MIN_N) before it can
--            ever be distrusted, and below a 15% hit ratio
--            (VULN_TRUST_MIN_RATIO) at that point, RIFTVEIL stops opening
--            the vuln window for that specific type on that specific
--            player and falls through to 6lex/hit_mem/suppress instead.
--            Not a permanent lockout -- probed every 5th detection
--            (VULN_PROBE_EVERY) so it can recover if their behavior
--            changes mid-match (config switch, etc.), mirroring the
--            existing suppress-streak-cap self-correction pattern rather
--            than inventing a new one. seen/hit counters keep updating
--            even while distrusted so the probe has real data to re-judge
--            against. All three thresholds are new CFG constants, and the
--            gate lives entirely inside the existing "[SAFE]
--            Vulnerability windows" checkbox -- no new UI control added.
--    v5.1 – Fixed FlushDB's cross-match hit_rate averaging: it weighted
--            each match's resolver hit ratio (nhr, from hit_count/
--            resolver_misses) by rec.kills, a completely different and
--            much rarer sample base. Any match where you resolved someone
--            correctly (hit_count>=2, the gate for even reaching this
--            code) but never landed the actual kill on them -- teammate
--            finished them, they died elsewhere after being hit -- had
--            rec.kills==0, which zeroed that whole match's contribution
--            to the running DB average despite having real data. Silently
--            starved seeded_conf (NewRec reads db.hit_rate) for exactly
--            that common case. Now weighted by the actual resolver sample
--            size (hit_count+resolver_misses) via a new persisted
--            db.samples field; kills is still tracked as its own running
--            total, just no longer used as the averaging weight. rv_db
--            now shows hr:%d%%(n=N) so the sample size behind that
--            percentage is visible.
--            Also investigated (per user request) whether ui elements
--            support a :tooltip() method for in-menu guidance, the way
--            two of the reference neverlose scripts reviewed today used
--            it -- confirmed against docs.gamesense.gs/docs/api/ui that
--            no such method exists on gamesense ui elements; that's a
--            neverlose-only menu-object convention, not portable here.
--            Did not add fake tooltips.
--    v5.0 – Panel visual upgrade: replaced the flat hard-cornered body/
--            title rectangles and straight 1px border lines with a
--            rounded panel + soft drop shadow. Ported RoundedRect() from
--            a real "SOLUS UI"-style script's renderer_rounded_rect
--            (shared identically between two of its files), trimmed to
--            just the fill -- verified renderer.circle's start_degrees/
--            percentage usage against docs.gamesense.gs/docs/api/
--            renderer/circle rather than trusting the source blind. One
--            offset RoundedRect pass stands in for that script's several-
--            step gaussian shadow (this repaints every frame, so kept to
--            a single extra draw pass). The header no longer gets its own
--            filled rectangle -- a flat inset rect's square corners would
--            poke out past the rounded body -- replaced with a thin inset
--            separator line. Purely visual, no logic touched.
--    v4.9 – Added an animlayer[6].weight settled-state cross-check to the
--            UNK vuln branch, found reviewing a real neverlose resolver's
--            find_desync_side: it treats weight==0 or weight==1 as "the
--            movement layer is fully settled, no active blend" -- a signal
--            independent of the playback_rate digits 6lex reads off that
--            same layer. When settled at the exact tick a torso_yaw read
--            is taken, it's extra confirmation the read isn't caught
--            mid-transition. Same modest-boost pattern already used for
--            the live_min/live_max cross-check (+0.02 conf, capped at
--            0.97) -- not a hard requirement, al6_weight is nil whenever
--            the FFI read fails and the branch behaves exactly as before.
--            Also reconfirmed (not changed): that resolver's own
--            breaking_lc check uses the identical 4096 sq-unit origin-jump
--            threshold RIFTVEIL's SHIFT detector already uses -- 4th
--            independent source now confirming that number.
--    v4.8 – Removed the Force Shot indicator (v4.5/v4.6) entirely, per
--            request. Pulled the checkbox, color picker, CFG.FORCESHOT_CONF,
--            and the DrawOverlay render block -- nothing of it remains.
--    v4.7 – Surfaced vuln_profile (seen/hit per vulnerability TYPE, e.g.
--            lby/unk/stp/dck) in rv_stats as a new vuln:type:hit/seen
--            field. This data has been silently tracked since the vuln
--            system shipped but was write-only -- nothing ever read it.
--            Prompted by a real debug log showing repeated vuln_lby
--            misses for multiple players at high reported hit-chance;
--            didn't wire a live trust gate off that alone (not enough
--            samples in one log to pick a real threshold without
--            guessing, and vuln corrections are deterministic by design --
--            gating them wrong risks the same corruption a bad flip
--            would cause). This is the diagnostic step first: next debug
--            log + an rv_stats call will show real per-type hit ratios
--            per player, which is what an eventual per-player vuln-type
--            trust gate (mirroring the 6lex agree/disagree calibration)
--            should be calibrated against, not guesses.
--    v4.6 – Force Shot indicator visual fixes: was small unboxed default-
--            size text sitting dead-center on top of the crosshair/enemy
--            model. Moved to 140px above center, added a dark backing box
--            + thin colored accent line (same visual language as the main
--            panel), and switched the text to bold+enlarged+centered
--            ("+bc" flags, per docs.gamesense.gs/docs/api/renderer/text --
--            "+" enlarges, "b" bolds, "c" centers).
--
--    v4.5 – Force Shot indicator (first ragebot-adjacent addition, kept
--            fully separate from the resolver pipeline). Investigated a
--            real "Force Shot" from a neverlose script for this: it turned
--            out to just force a fixed hit_chance=45 and override two
--            Scout-specific auto-stop menu items via pui.find():override(),
--            not real spread-seed prediction. Confirmed against
--            docs.gamesense.gs that gamesense's Lua API has no equivalent
--            (no ui.override, and client.random_float/random_int are
--            generic RNG with no documented tie to the engine's own spread
--            generator) -- so neither the neverlose mechanism nor genuine
--            spread-seed prediction is implementable here. Instead this
--            reuses RIFTVEIL's OWN already-computed resolver confidence:
--            shows a screen-center "FORCE SHOT" prompt when
--            client.current_threat() has an open vuln window OR a
--            resolved override at/above the new FORCESHOT_CONF (0.55,
--            stricter than the ESP "resolved" threshold since this asks
--            the player to commit to a shot). Purely a visual indicator --
--            never touches any rage/hit-chance/menu setting, since
--            gamesense has no override+restore primitive to safely undo
--            that if the script ever crashed mid-override.
--    v4.4 – Per-CONDITION hit-side memory. hit_side/hit_count were a
--            single global value per player, overwritten on every confirmed
--            head/neck hit regardless of movement state. Confirmed via
--            vandal.lua's own local-AA menu that this is wrong: it defines
--            8 fully independent per-state desync configs (default/
--            standing/moving/in air/slowwalking/crouching/crouch moving/
--            crouch in air), each with its own yaw/side -- meaning a real
--            enemy AA can legitimately desync a different side depending
--            purely on whether they're standing vs. moving vs. crouching.
--            A single global hit_side gets clobbered the instant the enemy
--            changes state, causing hit_mem to misfire in whichever state
--            it wasn't last learned in. Added hit_side_by_state/
--            hit_count_by_state, keyed by the same STATE.* strings
--            ClassifyState already produces (rec.state) -- no new state
--            machine needed. on_aim_hit now records the confirmed side
--            under the state active at fire time (SHOTS[].state, new);
--            the [3] hit-mem override branch prefers the current state's
--            own memory once it has >=2 confirmed hits, falling back to
--            the old global scalar for states with no data yet. A hit_mem
--            MISS now invalidates only that specific state's entry (the
--            enemy demonstrably desyncs differently there) instead of
--            leaving stale wrong data in place, while leaving proven-good
--            memory for other states untouched. Also cleared on soft
--            reset alongside the global fields. Visible via rv_stats'
--            new cond[N]:state:+/-1,... field.
--    v4.3 – console_input now returns true after handling any rv_* command
--            (rv_stats/rv_db/rv_clear/rv_reset/rv_wipe). Per
--            docs.gamesense.gs/docs/events/console_input, returning true
--            suppresses the engine's own command processing; without it,
--            since rv_* isn't a real registered concommand, the engine
--            ALSO tried to process it after our handler ran and printed
--            "Unknown command: rv_stats" right below our own output every
--            single time -- confirmed via a user screenshot. Purely
--            cosmetic console noise, now gone.
--    v4.2 – Fixed backtrack-depth learning: e.backtrack (aim_fire event)
--            is documented as a TIME value in seconds, not a tick count --
--            confirmed against docs.gamesense.gs/docs/events/aim_fire,
--            whose own example converts it with globals.toticks() before
--            use. We were storing the raw seconds value and comparing it
--            against the 1..16 TICK range everywhere else (bt_hist,
--            preferred_bt, rv_stats, every hit/miss log line) -- a real
--            backtrack of a few ticks is a tiny fraction of a second, so
--            that comparison was false almost always. This is why every
--            single hit/miss line in every debug log ever pulled from
--            this script shows "bt=0", even for players clearly being
--            backtracked with large vuln swings. Fixed by converting
--            through the existing TT() tick-rounding helper (same one
--            used for m_flSimulationTime elsewhere) instead of the
--            un-verified globals.toticks(). preferred_bt-based backtrack
--            depth learning should now actually learn.
--    v4.1 – Per-player 6lex trust calibration, inspired by vandal.lua's
--            own per-opponent learning in resolver_on_miss -- but adapted
--            to validate against CONFIRMED HEAD/NECK HITS instead of
--            misses, since a hit proves which side was actually real and
--            a miss doesn't. Every confirmed hit now compares what 6lex
--            claimed at fire time against the established real side
--            (six_agree/six_disagree, tracked in on_aim_hit). Once 6lex
--            has been proven wrong for a specific player by more than a
--            small margin over how often it's been right, both the
--            override gate and the side-tracking fallback stop trusting
--            it for THAT player and fall through to hit-mem/suppress --
--            doesn't touch the extraction formula itself, only how much
--            its output is trusted per-opponent. Visible via rv_stats
--            (6lex:agree/total). Not reset on soft-reset: it reflects a
--            physical property of that player's animation data, not our
--            tracked-side confidence, so an unrelated miss streak
--            shouldn't erase evidence 6lex has already been wrong for them.
--    v4.0 – Two resolver-adjacent additions from reviewing vandal.lua and
--            re-reading lagcomp_box.lua more closely:
--            (1) plist "High priority" is now set true whenever we have
--            an active override and false when releasing to builtin/
--            clearing -- confirmed via a real resolver's own usage
--            ("prevent missing LC" per its comment), not in the official
--            docs, so treated as a hint rather than core functionality
--            (set last in each block so a bad field name can't stop the
--            actual Force body yaw / Correction active calls before it).
--            (2) The SHIFT flash from v3.9 now also draws a full 3D
--            wireframe box at the extrapolated real position (velocity +
--            gravity + trace_line projection, ported from lagcomp_box.lua)
--            with a tether line back to the reported origin. Rebuilt the
--            box's corner/edge math from scratch rather than copying that
--            file's edge list directly -- it mixes 0- and 1-based Lua
--            table indices, silently dropping 3 of its intended 12 edges.
--            Extrapolation is purely cosmetic and pcall-wrapped throughout
--            with a same-tick fallback; it cannot affect any resolver
--            decision, only where the box is drawn.
--    v3.9 – Menu polish pass: section headers restyled (◆/▸ instead of
--            plain "--" dividers), same items, no new bloat. Added a
--            customizable panel accent color picker -- only tints the
--            idle/neutral chrome (header text, idle top-strip); the vuln/
--            resolved/building colors in the panel stay fixed since they
--            carry meaning, not taste. Added a world-space "SHIFT" flash:
--            a brief fading tag over any live enemy whose origin-jump
--            check just fired, inspired by a standalone "lag comp
--            breaker" ESP tool (same w2s/trace_line technique, same
--            frametime-based decay) but kept to a simple text tag to
--            match RIFTVEIL's own minimal visual language rather than
--            importing a second HUD style wholesale.
--    v3.8 – DB saves were only automatic on match-end/level_init/shutdown/
--            disconnect -- a crash, force-quit, or a bad server disconnect
--            between those events meant that session's progress against an
--            opponent was never written, requiring the manual "Save match
--            to DB" button as a workaround. Added a periodic autosave:
--            every 60s, if there's an active match (REC non-empty), Update()
--            flushes to the permanent DB on its own. Manual save/reset/wipe
--            controls are unchanged and still work the same.
--    v3.7 – Added a real full-DB-wipe (button "Wipe ALL saved DB" +
--            console command rv_wipe). "Reset match + DB" can only clear
--            DB[s64] for players CURRENTLY loaded into REC that session --
--            it has no way to touch a profile for an opponent not seen
--            yet this session. That reads as "old players keep coming
--            back after I reset" when it's really DB persistence working
--            exactly as designed, just outside that button's scope. This
--            new control empties the entire permanent database instead.
--    v3.6 – Renamed "Flush DB" to "Save match to DB" and "Reset match" to
--            "Reset match + DB" -- the old names caused real confusion:
--            "Flush DB" reads like a clear/reset action but has always
--            done the opposite (persists the current match into the
--            permanent DB, merging with existing entries -- exactly what
--            EndMatch already does automatically). No behavior changed,
--            only the labels; "Reset match" was always the actual clear
--            control.
--    v3.5 – The panel's H/M header wasn't a hit/miss scoreboard, despite
--            looking like one: it summed hit_count (head/neck-confirmed
--            hits ONLY -- 27 of 77 real hits in the reference log) and
--            resolver_misses (non-vuln misses ONLY, by design -- most
--            misses happen during vuln windows and deliberately don't
--            count there). Added real total_hits/total_misses fields,
--            incremented on every genuine (non-discarded) aim_hit/
--            aim_miss, and pointed the panel header and rv_stats at those
--            instead. hit_count/resolver_misses are untouched and still
--            drive hit_mem/soft-reset exactly as before -- this only fixes
--            what gets displayed as "misses". Also fixed the init log
--            line, which hardcoded "v2.3" as a separate literal from the
--            banner above and had silently drifted for the entire session
--            (still printing "v2.3 loaded" as of v3.4) -- now reads from a
--            single RV_VERSION constant.
--    v3.4 – Shifting guard upgraded with a direct signal: a >64-unit
--            (4096 sq-unit) origin teleport on a clean (choke==0) tick now
--            sets _shift_streak straight to the distrust floor instead of
--            only inferring shifts indirectly from missing tm[] lookback
--            slots. This exact threshold is independently confirmed in two
--            real production resolvers (a public CS:GO lagrecord library,
--            and a full HvH cheat script's own broke_lc check) -- not a
--            guess. Origin comparison resets across any tick gap (GetAS
--            miss, choke>2) the same way prev_pose already does, so it
--            can't misfire by comparing across a skipped span of normal
--            movement.
--    v3.3 – on_aim_miss couldn't tell a real resolver miss from two other
--            failure modes it was silently lumping in as "reason=?":
--            (1) event timeout -- aim_miss firing >=0.5s after aim_fire
--            means the event never got a clean resolution at all, not a
--            real outcome; (2) damage rejected -- m_totalHitsOnServer
--            moved between fire and miss despite reason=="?", meaning a
--            hit landed server-side and the client-side miss event is a
--            hit-registration quirk, not evidence our angle was wrong.
--            Both used to feed straight into resolver_misses/flip/soft-
--            reset as if they were genuine wrong-angle misses. Adapted
--            from a public aim-event-logging reference; now discarded
--            before touching any resolver state, logged separately
--            (verbose only) instead of counted.
--    v3.2 – Fixed config-recognition thrashing found in a real 12min match
--            log: one player flipped luasense_beta/std/symmetric 22 times
--            because those profiles sit only 4-9deg apart and noisy per-
--            tick pose sampling alone tipped RecognizeCfg's "best match"
--            every 32-tick recheck. Added switch hysteresis (a rival must
--            beat the current pick by CFG_SWITCH_MARGIN, not just edge it
--            out) plus TrustedCfg() gating every CfgAngle call on
--            config_conf >= CFG_THRESH -- CFG_THRESH's own comment always
--            said this was required, but nothing enforced it, so every
--            flip (config_conf reset to 0.30) fed straight into the
--            applied correction angle, up to 6-11deg of angle churn per
--            switch with zero new evidence behind it. Log also confirmed:
--            68.8% overall hit rate (77/112) across 3 real opponents,
--            DB persistence working correctly (writes once hit_count>=2),
--            no meta_aggressive false positives.
--    v3.1 – ESP flags cut from 7 to 2 (VLN, RES). 6LX/HIT/SUP/DTB/MYW
--            removed -- all five were internal diagnostics (which data
--            source fired, whether a struct read succeeded) spammed onto
--            every enemy's ESP box regardless of whether it meant anything
--            actionable. HIT's meaning was already a subset of RES; SUP/
--            DTB/config context still show in the v3.0 panel for whichever
--            enemy is your current threat, where they belong -- one flag
--            per real decision point (shoot now / trust this angle),
--            nothing that's just plumbing confirmation.
--    v3.0 – HUD rebuilt as a single draggable panel (Solus-UI style)
--            instead of stacked renderer.indicator rows. Position
--            persists through two hidden ui.new_slider values (survives
--            config save/load and reload -- a plain Lua local wouldn't),
--            drag by holding left-click on the title bar, gated to the
--            menu being open so it can never grab the panel mid-fight
--            while you're holding down fire. Dark panel body, thin
--            border, and a 2px top accent strip that recolors with
--            resolver state (blue idle / red vuln / green resolved /
--            amber building) so the state reads before you read a word.
--            Same content as v2.6's condensed lines, now inside one
--            self-contained box instead of floating text on the HUD.
--    v2.6 – Overlay condensed from 6 indicator rows to 3-4: identity
--            (name/AA/conf) and status (vuln/resolved/method/angle) merged
--            into one line, carried by the leading glyph+color (⚡ red /
--            ● green / ○ gray) instead of separate rows; side-meter and
--            supplemental tags (bt/config/def/spk/agg) merged into another.
--            Header shortened to "RV". Off-angle row unchanged. Same
--            information, half the vertical footprint -- was reading as
--            HUD spam rather than a glance-able readout.
--    v2.5 – Performance pass: GetLat() (3 pcall-wrapped FFI calls) was
--            being called once per player per tick via ChokedPkts, again
--            per LAGCOMP check via LCTicks, AND every single rendered
--            frame in DrawOverlay's spike check -- latency isn't a
--            per-player value, so all three now read the ctx.cur_lat/
--            avg_lat already computed once per net_update in Update()
--            (cached to LAST_SPIKE for DrawOverlay). DrawOverlay's
--            off-angle row was also calling entity.get_players() +
--            is_enemy/is_alive on every paint frame (allocates a fresh
--            table every frame); it now reads LIVE_ENEMIES, populated for
--            free inside Update()'s existing per-tick player loop. Net
--            effect: paint no longer touches GetLat, client.latency, or
--            entity.get_players() at all -- it was doing all three, every
--            frame, regardless of framerate.
--    v2.4 – Velocity-constrained desync: CfgAngle guesses now clamp to
--            VelCap(spd) (58°→0° linear falloff by VEL_CAP_SPD=580u/s),
--            kept separate from LiveCap so fast mouse-turns don't get
--            misread as body jitter. New PKA vuln window (peek
--            acceleration: stopped→fast mirrors STP, catches torso before
--            body-yaw-delay AAs catch up post-peek). DB-seeded confidence:
--            repeat opponents with a proven prior (3+ kills, >50% hit
--            rate) skip the cold-start conf ramp -- matters in short 2v2
--            engagements. Shifting guard on LAGCOMP/PHASE: a choke==0 tick
--            with a missing tm[] lookback slot now counts against trust
--            instead of silently falling through. Overlay redesign:
--            tighter techy separators (│ ·), status dots (●/○) replacing
--            check/cross glyphs, finer 10-segment side meter (■/·), and a
--            new off-angle awareness line for the second live enemy.
--            Blind-guess brute cycle: the true last-resort meta_aggressive
--            path (zero side data at all) now cycles side+half/full
--            magnitude across ticks (NIXWARE-style) instead of freezing on
--            one static guess. CanSeeHead: the "standing = fully exposed"
--            vuln TTL boost is now trace-verified (client.trace_line)
--            instead of inferred from velocity/duck/ground alone; fails
--            open so a bad trace never costs a boost the old code granted.
--    v2.3 – 6-script counter batch (serenity, aesthetic×2, ambani,
--            testarossa, gasolina). TorsoCluster (circular mean, W=7,
--            THR=25) counters ways()/sanya/Bobro/random-limits.
--            Faszsag near-zero skip (torpedo counter). meta_aggressive:
--            builtin_miss_streak triggers RIFTVEIL full-control mode;
--            META_HOLD tier; suppress threshold 0.45→0.28 (starves
--            testarossa AB). Bug fixes: circular mean wrap-around at
--            ±180°; builtin_miss_streak reset out of in_vuln gate.
--            Improvement pass: STP two-tick velocity confirmation
--            (gasolina fluctuate_fakelag counter); DCK 10-tick cooldown
--            (fake_duck spam counter); suppress streak cap 8+4 ticks
--            (hxlw1ss 375/914 stuck-suppress fix); UNK conf boost when
--            torso within live cap bounds; torso_hist cleared on soft
--            reset; _sup_streak and _dck_cooldown in NewRec.
--    v2.2 – Log analysis (55k lines, 453 hits): fixed [corr] noise —
--            only emit on method/val change (was 98% stale TTL echoes).
--            DrawOverlay simplified: 1 resolver status (✔/✘/⚡) + side
--            bar (◀/▶ with conf fill), blue=L orange=R gray=unknown.
--            SideBar() helper. Removed MethodColor/ConfBar.
--    v2.1 – Live desync bounds (as.min_yaw/max_yaw), get_desync() probe,
--            7 descriptive ESP flags, 5-row overlay with conf bar
--    v2.0 – Refactor: CFG table, named enums, ProcessPlayer split,
--            single pcall per player, REC shape docs, consistent style
--    v1.2 – Bug fixes: update_player_list order, BUG4 prev_pose reset,
--            nil-concat crash, SHOTS prune, double seen increment
--    v1.1 – Skeet-style indicators, ESP flags, menu redesign
--    v1.0 – Initial: two-tier memory, 6lex, period prediction, vuln
-- ════════════════════════════════════════════════════════════════════
--
--  TABLE OF CONTENTS          (approximate line numbers)
--    L045   Debug logger
--    L115   Persistent database + per-match state
--    L130   Cvar originals
--    L135   UI / menu
--    L200   Console commands (rv_stats, rv_db, rv_clear, rv_reset)
--    L250   CFG  — all tunable constants in one table
--    L320   Enums — AA, STATE, METH, VTYPE (no bare string keys)
--    L370   FFI  — animstate struct, animlayer, interfaces
--    L445   Math helpers + isnum() input validation
--    L465   6lex extraction (playback_rate primary, weight fallback)
--    L510   Engine helpers (MaxDesync, ClassifyState, angle tables)
--    L575   Choke estimation
--    L595   Defensive tickbase tracking
--    L620   Our tickbase gate
--    L645   Backtrack interp manipulation
--    L670   Ring buffer
--    L680   AA detection (PoseVar, CountClusters, IsSkitter, DetectAA)
--    L770   Config recognition (luasense_beta / luasense_std profiles)
--    L795   Jitter period prediction
--    L830   Vulnerability detector (6 window types)
--    L875   Record management + REC field documentation
--    L950   DB flush (permanent database write)
--    L990   ProcessPlayer — per-player resolver logic
--    L1140  Update — orchestration loop
--    L1170  Shot feedback (on_aim_fire, on_aim_hit, on_aim_miss)
--    L1265  ESP flags
--    L1305  DrawOverlay — draggable Solus-style info panel
--    L1365  Cleanup (ResetPlist, EndMatch, FullShutdown)
--    L1395  Event registration
-- ════════════════════════════════════════════════════════════════════

-- Single source of truth for the version string -- the init log line used
-- to hardcode "v2.3" as a separate literal from the header banner above,
-- silently drifting out of sync with every version bump since (it was
-- still printing "v2.3 loaded" at v3.3). Bump this AND the banner comment
-- together; nothing else should hardcode a version number.
local RV_VERSION = "8.37"

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
-- A crash while writefile rewrote the file can leave it as zero bytes
-- (one uploaded log was 106 KB of nothing else). Read back and rewritten on
-- every flush, those zeros stayed at the top of every later log, and most
-- viewers stop at the first one -- the log looked empty. Dropped here
-- ("%z": LuaJIT patterns don't take a literal "\0").
local log_nul = 0
if log_disk:find("%z") then log_disk, log_nul = log_disk:gsub("%z", "") end

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
-- Saved profiles are validated field by field: a wrong type (an old
-- version's leftovers, a partial write) made NewRec throw on every tick
-- for that player -- no resolver for them all match. Unknown fields drop.
local function DBNum(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi then return nil end
    return v
end
-- Counters and tick counts are integers ("%d" in the db log line)
local function DBInt(v, lo, hi)
    v = DBNum(v, lo, hi)
    return v and math.floor(v) or nil
end
local function CleanDBEntry(e)
    if type(e) ~= "table" then return nil end
    return {
        config_type = type(e.config_type) == "string" and e.config_type or nil,
        vuln_pref   = type(e.vuln_pref)   == "string" and e.vuln_pref   or nil,
        cheat       = type(e.cheat)       == "string" and e.cheat       or nil,
        gen         = DBNum(e.gen, 0, 1e12),
        bt_pref     = DBInt(e.bt_pref, 0, 64),
        hit_rate    = DBNum(e.hit_rate, 0, 1),
        samples     = DBNum(e.samples, 0, 1e9),
        kills       = DBInt(e.kills, 0, 1e9),
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
local REC      = {}   -- per-player resolver records this match
local EIDX_S64 = {}   -- [entity_index] = steam64_str, refreshed each tick
local SHOTS    = {}   -- [shot_id] = context snapshot at aim_fire
local DT_HIST  = {}   -- [s64] = simtime-delta samples for DT detection

-- Per-frame render cache, filled once per net_update_end (Update()) and read
-- by DrawOverlay (paint fires every rendered frame -- often 5-10x more often
-- than net updates, so anything DrawOverlay can read instead of recompute is
-- a real, multiplicative FPS win, not a micro-optimization).
local LIVE_ENEMIES = {}   -- array of live enemy entindexes, this net_update

-- Player-list writes go through a per-entity cache: a field is only sent
-- when its value changes (v6.2 sent all four fields for every enemy every
-- tick). The cache is dropped once a second and on every reset, so a value
-- the game changed behind our back is re-sent within a second.
local PL_CACHE, PL_KNOWN = {}, {}
local LAST_PL_SYNC, PL_RESYNC_TICKS = 0, 64
local function PSet(ent, field, value)
    local c = PL_CACHE[ent]
    if not c then c = {}; PL_CACHE[ent] = c end
    if c[field] == value then return end
    -- cache only what the game took: a set that raises must be retried on
    -- the next change, not remembered as written
    plist.set(ent, field, value)
    c[field] = value
end
local LAST_SPIKE    = false

-- Periodic DB autosave state. FlushDB previously only ran on match-end/
-- disconnect/shutdown -- a crash, force-quit, or bad server disconnect
-- between those events meant that session's DB updates were never written.
local LAST_DB_SAVE  = 0    -- globals.realtime() of the last periodic autosave

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
    -- v7.5 condition detection (see ClassifyState): on. It only changes
    -- which state table a moving enemy reads; shot lines log st= so the
    -- next match shows whether it helps.
    STATE_PHYSICS = true,
    -- v8.10: a frame whose simulation time is below the highest already
    -- received is skipped. Lag compensation writes no record for it (the
    -- frame defensive AA fills with a pitch / yaw flick), tickcount's
    -- lagrecord library skips it the same way, and the first match log
    -- with df= showed head rate 86% (18/21) with 0-8 such frames in the
    -- second before the shot against 55% (12/22) with 9+ (Fisher p 0.045,
    -- 4 of 5 players). v6.2 sampled them. One word to revert.
    SKIP_DEF_FRAMES = true,
    -- v8.15: a 3-way / 5-way enemy we missed on the resolver less than
    -- 10 s ago counts as "side in doubt" for the aim policy (safe point
    -- on the head; see AIMX). Every pre-v8 debug log, joined on the last
    -- [corr] aa= before each shot (log_report 3/5-WAY AFTER A RESOLVER
    -- MISS): next head shot at such an enemy 25 of 58 (43%), 9 of 12 logs
    -- at or under 50%; the same enemies otherwise 59% (249/419), other AA
    -- after a resolver miss 77% (33/43), x-way 10 s+ after the miss 75%
    -- (18/24). x-way (57% of neverlose AA
    -- scripts) and anti-bruteforce (59%) travel together; the longest
    -- anti-bruteforce reset in the public scripts is 600 ticks (9.4 s).
    -- Aim policy only: the forced body yaw is untouched.
    XWAY_UNSURE = true,
    -- v8.20: the >64u origin-jump SHIFT check compares only two records at
    -- most 64 ticks apart, at least 2 apart, with a move the player could
    -- make in that time (sv_maxvelocity 3500) -- as lagcomp-box-gs does.
    -- Before, the gap was unbounded: a surviving bot moved to its spawn at
    -- round start (or anyone back from dormancy) read as a lag-comp break,
    -- lit the SHIFT box and set the lagcomp distrust streak. Off in the
    -- v6.2 parity run.
    SHIFT_GAP = true,
    -- v8.26: our own shift (brk.def, read by WeDefensive / LCTicks) goes
    -- back to 0 once the tickbase catches up. In v6.2 it was only written
    -- while behind, so after one defensive / DT shift it kept its last
    -- value and LCTicks kept adding up to 13 phantom ticks to the lag-comp
    -- lookup until we died or hit someone. Off in the v6.2 parity run.
    DEF_RESET = true,
    -- v8.28: a DCK (duck crossing) window needs a real duck sample on the
    -- record before. v6.2 saved duck 0 for records it didn't sample (one
    -- that arrived > 2 ticks stale -- ChokedPkts is curtime - simtime -
    -- latency -- or had no animstate), and prev_duck starts nil on first
    -- sight and read as 0, so an enemy already crouched "crossed" 0.5 on
    -- the next sampled record and got a phantom DCK window (body yaw forced
    -- to the torso yaw for 11 ticks). Skips are logged (verbose) so a match
    -- log can count them. Off in the v6.2 parity run.
    DCK_GAP = true,
    -- v8.28: config recognition (RecognizeCfg -> CfgAngle's per-config L/R)
    -- runs every 32 sim ticks counted from its last run. v6.2 ran it when
    -- simtime % 32 == 0, so an enemy whose records land on a fixed even
    -- cadence out of phase with 32 was never recognised and stayed on the
    -- fallback table. Off in the v6.2 parity run.
    CFG_CADENCE = true,
    -- v8.28: a vuln window counts only while it is what we force. v6.2
    -- counted it down on processed records only, so it stayed open while
    -- the enemy was released (STATIC AA, low confidence, a stale record),
    -- dead or dormant, and the shot carried the last forced method: 27 of
    -- ~630 in-window shots in the logs repeat a window's exact value more
    -- than 10 s later (one 65 s, across a round). Those shots fed the
    -- vuln / cheat stats and skipped the flip. Off in the v6.2 parity run.
    STALE_WINDOW = true,
    -- v8.29: UNK (unchoke) windows force torso - eye, clamped to the cap,
    -- not the raw torso world yaw (v7.2's fix, reverted with v6.2). Raw
    -- vuln_unk since v8.15: 36% head vs resolver miss (10/28), every other
    -- method ~68% (p 0.01), 45 of 59 values beyond 60; the delta era
    -- (v7.2-7.9) measured 59% (17/29). The v8.28 roadmap set "under ~50%
    -- in the next logs" as the trigger. Off in the v6.2 parity run.
    UNK_DELTA = true,
    -- v8.32: the cap on our correction guesses is Valve's per-frame body-yaw
    -- limit (MaxDesync: 58 standing, 29 at a full run, never lower) instead
    -- of VelCap's straight line to 0 at 580 u/s. animstate min/max yaw read
    -- +-58 on 97% of 16.7k samples -- they are the fixed aim limits, not the
    -- speed-scaled ones -- so VelCap was the only speed model, and it put
    -- fast enemies under 20 deg: forced < 20 is the weakest band in every
    -- log (side methods ~45%, suppress 33%, vs 62-77% from 20 up). Off in
    -- the v6.2 parity run.
    DESYNC_FORMULA = true,
    -- v8.33: an enemy whose records come one tick apart (nothing choked)
    -- is static: desync needs choked commands. Bots in the logs (no AA,
    -- no desync) were labelled hold / 2-way / 3-way on 56 of 64 shots and
    -- we forced a value on 54 -- the pose we read is our client's
    -- (gamesense's resolver and our own override), not theirs. Off in the
    -- v6.2 parity run.
    NO_CHOKE_STATIC = true,
    -- v8.34: the side chain and suppress stand down only for a vuln window
    -- that is forced. v6.2 checked the window count alone, so a window it
    -- didn't apply (Vulnerability off, the enemy's cheat distrusting that
    -- type, confidence under the window minimum) switched suppress off for
    -- 11 records. Off in the v6.2 parity run.
    WINDOW_GATE = true,
    -- v8.34: gamesense's own hit ends its miss streak (meta takeover after
    -- two in a row); v6.2 only reset it on our hits. Off in the parity run.
    META_STREAK = true,
    -- v8.34: the aim policy never forces safe point (see AIMX Decide for
    -- the numbers). Head kill -> head only, body kill -> body, else the
    -- ragebot's own setting. Aim policy only.
    NO_SAFEPOINT = true,
    -- v8.35: the AA picture, side, flips and the pose-triggered windows
    -- (LBY / CTR) come only from records built while nothing was forced --
    -- on the others the body-yaw pose (computed by our client) is our own
    -- value read back. Bots (no desync) were labelled hold / 2-way / 3-way
    -- on 56 of 64 shots before. Off in the v6.2 parity run.
    POSE_CLEAN = true,
    -- v8.35: every side-based value is the side times the engine's desync
    -- limit for that frame (MaxDesync: 58 standing, 29 running) instead of
    -- the luasense yaw-offset tables, for any lua and any settings. Hit
    -- memory takes the same speed-aware limit. Off in the v6.2 parity run.
    FULL_DESYNC = true,
    -- v8.36 (off since v8.37, see below): a RIFTVEIL method forced only
    -- while its learned head rate (per enemy cheat, else across everyone)
    -- keeps within 5 points of gamesense's own -- probed every 4th shot.
    -- Across the logs gamesense lands 65%; forcing pays where we beat that
    -- (DCK 77%, suppress 70%, hit memory 67%) and cost where we don't (PKA
    -- 47%, CTR 50%, suppress on 5-way 56%). Off in the v6.2 parity run.
    -- Off since v8.37: on 8-20 shots a head rate swings 15-20 points by
    -- luck, so "the stats say we're better" isn't knowing better.
    BEAT_BUILTIN = false,
    -- v8.37: force only on knowledge -- a confirmed head hit (hit memory)
    -- or a server event (vuln windows on unchoke / stop / peek / landing /
    -- duck) -- and leave everything else to gamesense, as the public
    -- resolvers that steer it do. Guesses no longer force: suppress
    -- (inverts the side our client shows), meta hold / brute, and the
    -- pose-triggered LBY / CTR windows. Pose confidence no longer gates the
    -- event windows or hit memory. Off in the v6.2 parity run.
    KNOWN_ONLY = true,
    -- v8.37: learn from gamesense's own resolver. On a record built with
    -- nothing forced, the body-yaw pose our client shows IS gamesense's
    -- resolved answer; when its own shot lands the head, hit memory files
    -- the side of that answer (v6.2 filed our 16-record majority, which on
    -- jitter is often the other side). Logged on every shot as gs=. Off in
    -- the v6.2 parity run.
    LEARN_GS = true,
    -- These three are the v6.2 [EXP] switches as the logs show them
    -- running when the resolver hit 74% (suppress fired in every v6.2
    -- match; jitter prediction never did).
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
                   ["Cheat profiles"] = "cheat", ["Weapon aim"] = "aim"}
local IND_KEYS  = {["Info panel"] = "panel", ["ESP flags"] = "esp", ["Shift marker"] = "shift", ["Shot log"] = "log", ["Local lagcomp"] = "lc"}

local ui_title  = ui.new_label      ("LUA", "B", TitleText())
local ui_on     = ui.new_checkbox   ("LUA", "B", "Resolver\nriftveil")
local ui_detect = ui.new_multiselect("LUA", "B", "Detection\nriftveil", {"Vulnerability", "Hit memory", "Desync angle", "Cheat profiles", "Weapon aim"})
local ui_tight  = ui.new_checkbox   ("LUA", "B", "Tight interpolation\nriftveil")
local ui_ind    = ui.new_multiselect("LUA", "B", "Indicators\nriftveil", {"Info panel", "ESP flags", "Shift marker", "Shot log", "Local lagcomp"})
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
-- v8.1: "Cheat profiles" (CHEAT PROFILES) is added to whatever Detection
-- selection already exists, once. With no cheat data it changes nothing.
if not database.read("riftveil_ui_defaults_v81") then
    local sel, has = ui.get(ui_detect), false
    sel = type(sel) == "table" and sel or {}
    local copy = {}
    for i = 1, #sel do
        if sel[i] == "Cheat profiles" then has = true end
        if sel[i] ~= "Adaptive engine" then copy[#copy + 1] = sel[i] end
    end
    if not has then copy[#copy + 1] = "Cheat profiles" end
    ui.set(ui_detect, copy)
    database.write("riftveil_ui_defaults_v81", true)
end

-- v8.3: "Weapon aim" (WEAPON AIM POLICY) added once to the selection.
if not database.read("riftveil_ui_defaults_v83") then
    local sel = ui.get(ui_detect)
    sel = type(sel) == "table" and sel or {}
    local copy, has = {}, false
    for i = 1, #sel do copy[i] = sel[i]; if sel[i] == "Weapon aim" then has = true end end
    if not has then copy[#copy + 1] = "Weapon aim" end
    ui.set(ui_detect, copy)
    database.write("riftveil_ui_defaults_v83", true)
end

-- v8.16: "Shot log" (SHOT LOG, the console line per shot) added once.
if not database.read("riftveil_ui_defaults_v816") then
    local sel = ui.get(ui_ind)
    sel = type(sel) == "table" and sel or {}
    local copy, has = {}, false
    for i = 1, #sel do copy[i] = sel[i]; if sel[i] == "Shot log" then has = true end end
    if not has then copy[#copy + 1] = "Shot log" end
    ui.set(ui_ind, copy)
    database.write("riftveil_ui_defaults_v816", true)
end

-- v8.18: "Local lagcomp" (LOCAL LAGCOMP BOX) added once.
if not database.read("riftveil_ui_defaults_v818") then
    local sel = ui.get(ui_ind)
    sel = type(sel) == "table" and sel or {}
    local copy, has = {}, false
    for i = 1, #sel do copy[i] = sel[i]; if sel[i] == "Local lagcomp" then has = true end end
    if not has then copy[#copy + 1] = "Local lagcomp" end
    ui.set(ui_ind, copy)
    database.write("riftveil_ui_defaults_v818", true)
end

-- Multiselect values cached as booleans: ui.get on a multiselect builds a
-- fresh table, and ProcessPlayer/paint would otherwise pay for that on
-- every read. Refreshed by the callbacks below and once per net update.
local DET = {vuln = false, hitmem = false, six = false, cheat = false, aim = false, verbose = false}
local IND = {panel = false, esp = false, shift = false, log = false, lc = false}
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
    -- the Debug log checkbox. v8.1-8.31 set this from DET itself (never
    -- true), so no [corr] / [vuln] / [cfg] / [dcap] line was ever written
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

-- Forward-declared: the rv_save command and EndMatch both call FlushDB;
-- rv_perf reads PERF (see PERFORMANCE PROFILER).
local FlushDB
local PERF
local ResetPlist   -- CLEANUP; Update calls it when the resolver is switched off
local CheatDB      -- CHEAT PROFILES: Lines() for rv_db, Wipe() for rv_wipe


-- ══════════════════════════════════════════════════════════════════
--  CONSOLE COMMANDS  (console_input — confirmed cheat event)
--    rv_stats   match stats per player
--    rv_db      permanent DB contents
--    rv_clear   wipe log file
--    rv_reset   hard reset match + DB entries for CURRENT enemies only
--    rv_wipe    wipe the ENTIRE permanent DB, every steam64 ever saved,
--               and the learned cheat profiles
-- ══════════════════════════════════════════════════════════════════
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
                "  %s | %s | conf:%d%% | %d/%d (%d%%) | head:%d miss streak:%d | 6lex:%d/%d | bt:%d | cfg:%s | cond[%d]:%s | vuln:%s",
                entity.get_player_name(rec.eidx or 0) or s64,
                rec.aa_type, math.floor(rec.conf*100),
                rec.total_hits or 0, tot, hr,
                rec.hit_count, rec.resolver_misses,
                rec.six_agree or 0, (rec.six_agree or 0) + (rec.six_disagree or 0),
                rec.preferred_bt, rec.config_type or "?",
                cond_n, cond_n > 0 and table.concat(cond_parts, ",") or "-",
                #vp_parts > 0 and table.concat(vp_parts, ",") or "-")
        end
        out[#out+1] = string.format("  log lines: %d", log_total)
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD","stats", s)

    elseif cmd == "rv_db" then
        local out = {"[RIFTVEIL] === PERMANENT DB ==="}
        for s64, e in pairs(DB) do
            out[#out+1] = string.format(
                "  %s | cfg:%s | vuln:%s | bt:%s | hr:%d%%(n=%d) | hits:%d",
                s64, e.config_type or "?", e.vuln_pref or "?",
                tostring(e.bt_pref), math.floor((tonumber(e.hit_rate) or 0)*100),
                math.floor(tonumber(e.samples) or 0), math.floor(tonumber(e.kills) or 0))
        end
        -- learned per-cheat method stats (saved separately, same wipe)
        if CheatDB then for _, l in ipairs(CheatDB.Lines()) do out[#out+1] = "  cheat " .. l end end
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD","db", s)

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
        REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
        client.log(string.format("[RIFTVEIL] reset %d profiles", n))
        info("reset", "%d profiles cleared", n)

    elseif cmd == "rv_wipe" then
        local n = 0; for _ in pairs(DB) do n = n + 1 end
        DB = {}
        database.write(DB_KEY, DB)
        REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
        -- the learned cheat profiles are permanent data too; up to 8.5.4
        -- they survived rv_wipe and came back on the next load
        if CheatDB then CheatDB.Wipe() end
        client.log(string.format("[RIFTVEIL] wiped entire DB (%d entries) and learned cheat profiles", n))
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

local function GetAS(ent)
    local p = GetPtr(ent); if not p then return nil end
    local ok, s = pcall(function()
        return ffi.cast(aspt, ffi.cast("char*", p) + CFG.AS_OFFSET)[0]
    end)
    return (ok and s) or nil
end

local function GetAL(ptr, idx)
    local ok, al = pcall(function()
        return ffi.cast(al_t, ffi.cast("char*", ptr) + CFG.AL_OFFSET)[0][idx]
    end)
    return ok and al or nil
end

local function GetLat()
    local ok, nc = pcall(function() return ffi.cast(cpt, get_nc(eng)) end)
    if not ok or not nc or nc == ffi.NULL then
        local l = client.latency(); return l, l
    end
    local ok1, cur = pcall(function() return ffi.cast(ncfn, nc[0][9])(nc, 0) end)
    local ok2, avg = pcall(function() return ffi.cast(ncfn, nc[0][10])(nc, 0) end)
    -- Type-checked: the comparison sits outside the pcall, and LuaJIT (the
    -- game's runtime) throws on number-vs-cdata comparisons.
    cur = (ok1 and type(cur) == "number" and cur == cur and cur > 0 and cur < 2) and cur
          or client.latency()
    avg = (ok2 and type(avg) == "number" and avg == avg and avg > 0 and avg < 2) and avg or cur
    return cur, avg
end

-- ══════════════════════════════════════════════════════════════════
--  MATH HELPERS + INPUT VALIDATION
-- ══════════════════════════════════════════════════════════════════
local function Clamp(v, a, b) return math.min(math.max(v, a), b) end
-- The value written to "Force body yaw value": inside the plist's +-60 and
-- never NaN (a NaN animstate read used to reach the write; math.min/max
-- handle NaN differently in LuaJIT and Lua 5.3). Real reads are unchanged.
local function SafeYaw(v)
    if type(v) ~= "number" or v ~= v then return 0 end
    return Clamp(v, -60, 60)
end
local function Sign(x)        return x > 0 and 1 or (x < 0 and -1 or 0) end
-- Bounded: the old two while-loops never ended on inf and took ~1e9
-- iterations on a huge value -- a frozen game on one bad animstate read.
-- Same result on every finite input.
local function NA(a)
    if a ~= a or a == math.huge or a == -math.huge then return 0 end
    if a >= -180 and a <= 180 then return a end
    a = a % 360
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

-- LiveCap: reads actual per-player desync bounds from animstate.
-- Confirmed accessible: skeet DLL analysis (Dec 27 2024 build) showed
-- min_yaw / max_yaw fields in rv_as after pad13[0x1CA].
-- Returns (min_yaw, max_yaw, cap) where cap = max of their magnitudes.
-- Falls back to CFG.DESYNC_CAP = 58 if the read is invalid or not yet
-- populated (first tick on a new player).
local function LiveCap(as)
    if as then
        local mn = as.min_yaw
        local mx = as.max_yaw
        if isnum(mn, -90, -0.5) and isnum(mx, 0.5, 90) then
            return mn, mx, math.max(math.abs(mn), mx)
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

    s = try(al.weight)
    if s ~= 0 then return s, math.min(35.0, live_cap) end  -- weight fallback: fixed estimate
    return 0, 0
end

-- ══════════════════════════════════════════════════════════════════
--  ENGINE HELPERS
-- ══════════════════════════════════════════════════════════════════
-- (MaxDesync removed — was used to compute max_d which was dead after pick chain refactor)

-- ══════════════════════════════════════════════════════════════════
--  STATE TRACKER  — which movement condition an enemy is in
--
--  The AA builders pick their side and magnitude per condition (standing,
--  moving, slow walk, crouch, crouch-move, air, air-crouch), so this picks
--  which CfgAngle table, which per-state hit memory and which seed applies.
--  Everything here is measured by tools/state_test.lua: Source movement
--  physics (sv_accelerate 5.5, friction 5.2, stopspeed 80, jump 302 u/s,
--  gravity 800) played through fakelag 1-14, per scenario, against the
--  condition an AA builder would be in.
--
--  With FEATURE.STATE_PHYSICS off it is v6.2's speed-band classifier,
--  unchanged. On:
--   * Slow walk vs a run's acceleration or braking: inside the band,
--     gaining speed faster than a slow walk can is a run; losing speed
--     keeps the state being braked from (v7.5).
--   * Thresholds follow the enemy's weapon and scope: a scoped AWP tops
--     out at 100 u/s and accelerates at 8.6 u/s per tick, so the fixed
--     100 u/s / 10 u/s-per-tick cuts read every scoped AWP walk as slow
--     walk. A slow walk holds 34% of max speed, so anything above 40% of
--     the weapon's max is a run (100 u/s with a knife, as before); the
--     acceleration cuts scale with max speed / 250. This also catches a
--     heavy-fakelag enemy who started running mid-gap: the speed change
--     averaged over 14 ticks under-reads, the speed itself doesn't.
--   * Fake duck (heavy fakelag, duck amount mid-way on 3 of the last 4
--     records, on the ground, barely moving) holds CROUCH, as the builders
--     map it, instead of flickering crouch / standing every record.
--   * Crouch-move from 5 u/s (builders: 2 / 3.63 / 10), not 20.
--   * No speed change yet (first record after a gap): keep a running or
--     slow-walk state instead of defaulting to slow walk.
--   * Ground flag unreadable: the animstate's on_ground decides, instead
--     of every player reading as airborne.
--   * Velocity that never reads (0 on 2 records in a row while the origin
--     moves, never non-zero): speed from the origin delta between records.
-- ══════════════════════════════════════════════════════════════════
-- Max player speed per item definition index: {normal, scoped} (CS:GO
-- weapon data; knives, grenades and anything unlisted run at 250).
local WEAPON_MAXSPEED = {
    [1] = {230}, [2] = {240}, [3] = {240}, [4] = {240}, [7] = {215}, [8] = {220, 150},
    [9] = {200, 100}, [10] = {220}, [11] = {215, 120}, [13] = {215}, [14] = {195},
    [16] = {225}, [17] = {240}, [19] = {230}, [23] = {235}, [24] = {230}, [25] = {215},
    [26] = {240}, [27] = {225}, [28] = {150}, [29] = {210}, [30] = {240}, [31] = {220},
    [32] = {240}, [33] = {220}, [34] = {240}, [35] = {220}, [36] = {240}, [38] = {215, 120},
    [39] = {210, 150}, [40] = {230, 230}, [60] = {225}, [61] = {240}, [63] = {240}, [64] = {220},
}

local function EnemyMaxSpeed(player)
    local w = entity.get_player_weapon(player)
    local idx = w and entity.get_prop(w, "m_iItemDefinitionIndex")
    if type(idx) ~= "number" then return 250 end
    local m = WEAPON_MAXSPEED[bit.band(idx, 0xFFFF)]
    if not m then return 250 end
    local scoped = entity.get_prop(player, "m_bIsScoped")
    if m[2] and (scoped == 1 or scoped == true) then return m[2] end
    return m[1]
end

-- dv = speed change per simtime tick (nil when there is no previous
-- record to compare with); maxspd = the enemy's weapon max speed (250 when
-- unknown); fakeduck = TrackState's fake-duck read.
local function ClassifyState(player, as, spd, dv, prev_state, maxspd, fakeduck)
    local flags = entity.get_prop(player, "m_fFlags")
    spd = spd or 0
    if FEATURE.STATE_PHYSICS then
        local og
        if type(flags) == "number" then og = bit.band(flags, 1) ~= 0
        else og = as ~= nil and as.on_ground == true end
        local duck = as and (as.duck_amount or 0) > 0.5
        if not og then return duck and STATE.AIR_CROUCH or STATE.AIR end
        if fakeduck then return STATE.CROUCH end
        if duck then return spd > 5 and STATE.CROUCH_MOVING or STATE.CROUCH end
        maxspd = maxspd or 250
        local scale   = maxspd / 250
        -- A slow walk holds 34% of the weapon's max speed (the accuracy
        -- speed slow motion aims for), so above 40% it can't be one --
        -- 100 u/s with a knife, 86 with an AK, 40 with a scoped AWP.
        local run_thr = 0.4 * maxspd
        if prev_state == STATE.RUNNING then run_thr = run_thr * 0.9 end   -- hysteresis
        if spd >= run_thr then return STATE.RUNNING  end
        if spd <= 5       then return STATE.STANDING end
        if dv then
            if dv > 10 * scale then return STATE.RUNNING end
            if dv < -2 * scale then
                return (prev_state == STATE.SLOWMOTION) and STATE.SLOWMOTION or STATE.RUNNING
            end
        elseif prev_state == STATE.RUNNING or prev_state == STATE.SLOWMOTION then
            return prev_state
        end
        return STATE.SLOWMOTION
    end
    local og   = bit.band(flags or 0, 1) ~= 0
    local duck = as and (as.duck_amount or 0) > 0.5
    if not og   then return duck and STATE.AIR_CROUCH  or STATE.AIR           end
    if duck     then return spd > 20 and STATE.CROUCH_MOVING or STATE.CROUCH  end
    if spd > 5 and spd < 100 then return STATE.SLOWMOTION                     end
    if spd >= 100             then return STATE.RUNNING                        end
    return STATE.STANDING
end

-- One fresh record of one enemy: speed change, fake duck, velocity
-- fallback, then ClassifyState. ox/oy = this record's origin. Returns the
-- state and the speed it was judged on (logged on shot lines).
local function TrackState(rec, player, as, spd, st, ox, oy, ti)
    if not FEATURE.STATE_PHYSICS then
        return ClassifyState(player, as, spd, nil, rec.state), spd
    end
    -- Velocity that never reads: once a player's velocity has read 0 on 2
    -- records in a row while their origin kept moving, and never anything
    -- else, their speed comes from the origin delta from then on. A real
    -- stop gives one such record (the origin moved during the fakelag gap
    -- before it), then a still one.
    if spd >= 1 then rec.vel_ok, rec.vel_broken = true, false end
    if not rec.vel_ok and isnum(ox) and isnum(oy) and rec.prev_origin_x and rec.prev_origin_tick
       and st > rec.prev_origin_tick then
        local dx, dy = ox - rec.prev_origin_x, oy - rec.prev_origin_y
        local o = math.sqrt(dx * dx + dy * dy) / ((st - rec.prev_origin_tick) * ti)
        local moving = o > 5 and o < 400
        if moving and not rec.vel_broken then
            rec.vel_zero_n = (rec.vel_zero_n or 0) + 1
            if rec.vel_zero_n >= 2 then
                rec.vel_broken = true
                info("state", "velocity reads 0 for a moving player (%s) -- using origin speed",
                     entity.get_player_name(player) or "?")
            end
        elseif not moving then
            rec.vel_zero_n = 0
        end
        if rec.vel_broken and moving then spd = o end
    end
    -- speed change per tick since the previous classified record, from the
    -- tracker's own history (prev_spd belongs to the v6.2 stop detector)
    local dv, gap
    if rec.ts_spd and rec.ts_st and st > rec.ts_st then
        gap = st - rec.ts_st
        dv  = (spd - rec.ts_spd) / gap   -- per tick, fakelag-safe
    end
    rec.ts_spd, rec.ts_st = spd, st
    -- fake duck: heavy fakelag and a mid-way duck amount on 3 of 4 records
    local d = as and as.duck_amount or 0
    local mid = isnum(d) and d > 0.05 and d < 0.95
    local fd = rec.fd_ring
    if not fd then fd = {false, false, false, false}; rec.fd_ring = fd; rec.fd_i = 0 end
    rec.fd_i = rec.fd_i % 4 + 1
    fd[rec.fd_i] = mid and (gap or 0) >= 7
    local n = (fd[1] and 1 or 0) + (fd[2] and 1 or 0) + (fd[3] and 1 or 0) + (fd[4] and 1 or 0)
    local fakeduck = n >= 3 and spd < 40
    rec.fakeduck = fakeduck
    local maxspd = EnemyMaxSpeed(player)
    local state = ClassifyState(player, as, spd, dv, rec.state, maxspd, fakeduck)
    -- Debug log: every change of condition, with what it was judged on
    if DET.verbose and state ~= rec.state then
        dbg("state", "player=%s %s -> %s spd=%.0f dv=%s max=%d gap=%s duck=%.2f%s",
            entity.get_player_name(player) or "?", tostring(rec.state), state, spd,
            dv and string.format("%.1f", dv) or "-", maxspd, tostring(gap or "-"),
            isnum(d) and d or 0, fakeduck and " fakeduck" or "")
    end
    return state, spd
end

-- TrustedCfg: only hand a recognized config_type to CfgAngle once
-- config_conf has actually crossed CFG_THRESH. CFG_THRESH's own comment
-- always said it was "the minimum before applying known angles", but
-- nothing enforced that -- CfgAngle callers used rec.config_type
-- unconditionally, so every mid-recognition config flip (config_conf reset
-- to 0.30 on switch) fed straight into the applied correction angle. Real
-- match log: one player flipped configs 22 times in 12 minutes, each flip
-- changing the standing-state angle by up to 6-11 degrees.
-- Which cheat can run the Lua a preset came from (see CHEAT PROFILES).
-- luasense_beta is the Neverlose "luasense beta" built-in preset, all 7
-- states exact (s0daa/CSGO-HVH-LUAS, Neverlose/lua/luasense beta.lua);
-- the gamesense luasense builds ship no built-in presets at all.
-- luasense_std is the same family ("luasensedev"). symmetric is not a
-- Lua but a desync shape (35/35), so any cheat.
local CFG_CHEAT = {luasense_beta = "nl", luasense_std = "nl"}
local function TrustedCfg(rec)
    local t = (rec.config_conf >= CFG.CFG_THRESH) and rec.config_type or nil
    -- a detected player on another cheat can't be running that preset
    if t and DET.cheat and rec.cheat and CFG_CHEAT[t] and CFG_CHEAT[t] ~= rec.cheat then return nil end
    return t
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
    -- FEATURE.FULL_DESYNC: the side times the engine's limit for this frame
    -- (MaxDesync, passed as cap). The tables below are luasense YAW offsets;
    -- what an AA desyncs by is its body-yaw limit, at 60 in 211 of 330
    -- limit sliders in the repo's AA scripts, settings exports and presets
    -- alike -- whatever the lua. Bigger values landed better in the logs
    -- (right side 30-39: 66%, 40-60: 77%; under 20 the weakest everywhere).
    if FEATURE.FULL_DESYNC and isnum(cap) then return side > 0 and cap or -cap end
    local tbl = config_type and CFG_COUNTER[config_type] and CFG_COUNTER[config_type][state]
    local raw
    if tbl then
        raw = side > 0 and tbl.R or -tbl.L
    else
        -- ui_asym gate: was documented in a comment here ("ui_asym toggle
        -- feeds into CfgAngle via ASYM_FALLBACK vs CFG_COUNTER selection")
        -- but never actually checked -- the [EXP] Asymmetric Angles
        -- checkbox did nothing at all. Wired up now: ON uses the per-side
        -- L/R fallback table as before; OFF averages it into one symmetric
        -- magnitude for both sides, matching what the toggle's own name
        -- and menu grouping ("disable if things feel worse") imply it was
        -- always meant to do.
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

-- Valve's body-yaw limit for this frame (CCSGOPlayerAnimState::SetUpVelocity),
-- as antiaim_funcs and the public resolvers compute it: the full cap standing,
-- down to half of it at a full run (walk-to-run transition 1, speed >= 52%
-- of the weapon's max), ducking pulls it toward half as well. Never under
-- half: VelCap's line went to 0 at 580 u/s (18 deg at 400), the weakest band
-- in every log (FEATURE.DESYNC_FORMULA).
local function MaxDesync(as, spd, maxspd, cap)
    cap = cap or CFG.DESYNC_CAP
    if not (as and isnum(spd, 0) and isnum(maxspd, 1)) then return cap end
    local w2r = as.stop_to_full_run
    if not isnum(w2r, 0, 1) then w2r = 1 end   -- unread: the running (smaller) limit
    local m = ((w2r * -0.3) - 0.2) * Clamp(spd / (maxspd * 0.52), 0, 1) + 1
    local duck = as.duck_amount
    if isnum(duck, 0, 1) and duck > 0 then
        m = m + duck * Clamp(spd / (maxspd * 0.34), 0, 1) * (0.5 - m)
    end
    return Clamp(cap * m, cap * 0.5, cap)
end

-- (GenAngle removed — override block uses CfgAngle directly;
--  ui_asym toggle feeds into CfgAngle via ASYM_FALLBACK vs CFG_COUNTER selection)

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

-- No choke, no desync: the server animates every command it gets, and the
-- angle a desync hides has to sit on a choked one. A player whose records
-- arrive one tick apart (bots, no-AA players) has no hidden angle to
-- resolve. NOCHOKE_N records, at most one gap of 2+ (a bundled packet).
local NOCHOKE_N = 16
local function NoChoke(rec)
    local g = rec.gaps
    if not g or #g < NOCHOKE_N then return false end
    local big = 0
    for i = 1, #g do if g[i] >= 2 then big = big + 1 end end
    return big <= 1
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
    local tb = entity.get_prop(me, "m_nTickBase")
    -- unreadable / NaN: skip (a NaN max would stick until death, and the
    -- runtimes disagree on math.max with NaN)
    if not isnum(tb) then return end
    brk.check = math.max(tb, brk.check)
    if math.abs(tb - brk.check) > 64 then brk.def = 0; brk.check = 0 end
    if brk.check > tb then brk.def = math.abs(tb - brk.check)
    elseif FEATURE.DEF_RESET then brk.def = 0 end
    brk.ahead = globals.tickcount() > tb
end)

local function WeDefensive() return brk.ahead and brk.def > 2 and brk.def < 14 end

-- cur_lat/avg_lat come from the caller's per-tick ctx -- see ChokedPkts.
local function LCTicks(use_avg, cur_lat, avg_lat)
    local ti      = globals.tickinterval()
    local lat     = use_avg and avg_lat or cur_lat
    local shift   = WeDefensive() and (brk.def * ti) or 0
    local lerp    = 0.031; pcall(function() lerp = cvar.cl_interp:get_float() end)
    return math.max(0, math.floor((lat + lerp + shift) / ti))
end

-- ══════════════════════════════════════════════════════════════════
--  BACKTRACK INTERP MANIPULATION
-- ══════════════════════════════════════════════════════════════════
local function RestoreInterp()
    if ui.get(ui_tight) then return end
    pcall(function()
        cvar.cl_interp:set_float(ORIG_INTERP)
        cvar.cl_interp_ratio:set_int(ORIG_RATIO)
    end)
end

-- ══════════════════════════════════════════════════════════════════
--  RING BUFFER
-- ══════════════════════════════════════════════════════════════════
local function RNew(n)    return {b={}, h=0, n=n} end
local function RPush(r,v) r.h = (r.h % r.n) + 1; r.b[r.h] = v end
local function RGet(r,o)  return r.b[((r.h - o - 1) % r.n) + 1] end
local function RLen(r)    local c=0; for i=1,r.n do if r.b[i] then c=c+1 end end; return c end

-- ══════════════════════════════════════════════════════════════════
--  AA DETECTION
-- ══════════════════════════════════════════════════════════════════
local function PoseVar(hist)
    local cnt = RLen(hist); if cnt < 2 then return 0 end
    local sum, sq = 0, 0
    for i = 0, cnt-1 do
        local e = RGet(hist, i)
        if e then sum = sum + e.p; sq = sq + e.p*e.p end
    end
    local m = sum / cnt; return sq/cnt - m*m
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

local function CountClusters(hist)
    local cnt = RLen(hist); if cnt < 3 then return 0, {} end
    local vals = {}
    for i = 0, cnt-1 do local e = RGet(hist,i); if e then vals[#vals+1] = e.p end end
    table.sort(vals)
    -- Store {center, count, sum} so running average stays correct
    local cl = {{vals[1], 1, vals[1]}}
    for i = 2, #vals do
        if math.abs(vals[i] - cl[#cl][1]) > CFG.CLUSTER_GAP then
            cl[#cl+1] = {vals[i], 1, vals[i]}
        else
            local c = cl[#cl]
            c[2] = c[2] + 1
            c[3] = c[3] + vals[i]
            c[1] = c[3] / c[2]  -- true running mean
        end
    end
    return #cl, cl
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
    local pose_sum, flips = 0, 0
    for i = 0, cnt-1 do
        local e = RGet(hist, i); if e then pose_sum = pose_sum + e.p end
        local a, b = RGet(hist, i), RGet(hist, i+1)
        if a and b and math.abs(a.p - b.p) > CFG.POSE_THRESH and Sign(a.p) ~= Sign(b.p) then
            flips = flips + 1
        end
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
local function CanSeeHead(me, target)
    if not me or not target then return true end
    local mx, my, mz = entity.get_origin(me)
    local tx, ty, tz = entity.get_origin(target)
    if not (isnum(mx) and isnum(tx)) then return true end
    local _, _, mvz = entity.get_prop(me, "m_vecViewOffset")
    local _, _, tvz = entity.get_prop(target, "m_vecViewOffset")
    local ok, frac, hit = pcall(client.trace_line, me,
        mx, my, mz + (isnum(mvz) and mvz or 64),
        tx, ty, tz + (isnum(tvz) and tvz or 64))
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

        local g = 800
        pcall(function() g = cvar.sv_gravity:get_float() end)

        -- v8.26 (drawing only -- the boxes): the trace skips the player
        -- itself (was -1, which could stop on their own hull) and runs at
        -- step height (18u) so a stair or slope doesn't freeze the box at
        -- the first bump; standing players stay on the ground (the ported
        -- formula lifted them by sv_jump_impulse * ti each tick).
        local airborne = math.abs(vz) > 1
        local cx, cy, cz = ox, oy, oz
        for _ = 1, math.min(ticks, 32) do
            local nx, ny, nz = cx + vx*ti, cy + vy*ti, cz
            if airborne then nz = cz + vz*ti; vz = vz - g*ti end
            local frac = client.trace_line(player, cx, cy, cz + 18, nx, ny, nz + 18)
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
        local cluster_val = TorsoCluster(rec, torso)
        local correction  = cluster_val or torso
        local conf        = cluster_val and 0.93 or 0.90  -- higher conf when clustered
        -- FEATURE.UNK_DELTA: torso_yaw is a world yaw; the body yaw value is
        -- relative to the eye. v7.2-7.9 forced the difference (as here, the
        -- v7.9 line); v6.2 forced the world yaw itself, which the player
        -- list clamps to +-60 -- a value set by where on the map they face.
        if FEATURE.UNK_DELTA then
            if not safe_eye then return nil, 0, 0 end
            correction = Clamp(NA(correction - safe_eye), -corr_cap, corr_cap)
        end

        -- LIVE CAP BOOST: when animstate min/max_yaw are populated and the correction
        -- falls within the actual engine-reported desync bounds, it's a validated read.
        -- Modest boost from 0.90→0.92 / 0.93→0.96 — not a guarantee, just extra signal.
        -- Skeet DLL analysis confirmed min_yaw/max_yaw are accessible from animstate.
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
            return VTYPE.STP, gfy, 0.80
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
        if torso and math.abs(torso) >= 8 then
            return VTYPE.PKA, torso, 0.75
        end
    end

    -- [LND] landing: on_ground flipped false → true
    if rec.prev_onground == false and as.on_ground == true then
        if not safe_eye then return nil, 0, 0 end
        return VTYPE.LND, safe_eye, 0.85
    end

    -- [DCK] duck transition: duck_amount crossed 0.5.
    -- DCK COOLDOWN (aesthetic_beta, gasolina fake_duck):
    -- fake_duck generates rapid duck_amount crossings every ~4 ticks. Without a
    -- cooldown, DCK floods the correction with low-confidence readings (0.78) and
    -- drowns out higher-quality UNK and LBY corrections. Cap at 1 DCK per 10 ticks.
    local dn, dp = as.duck_amount or 0, rec.prev_duck or 0
    local cross  = 0.5
    if (rec._dck_cooldown or 0) > 0 then -- luacheck: ignore 542
        -- cooldown ticking — decrement only, no DCK this tick
    elseif FEATURE.DCK_GAP and rec.prev_duck == nil then
        -- nothing to cross from: first sight, or the record before wasn't
        -- sampled (arrived stale / no animstate). v6.2 read that as duck 0,
        -- so an enemy already crouched "crossed" 0.5 here.
        if DET.verbose and dn >= cross then
            dbg("vuln", "type=dck skipped: no duck sample before this record (stale record / first sight)")
        end
    elseif (dp < cross and dn >= cross) or (dp >= cross and dn < cross) then
        local torso = as.torso_yaw or safe_eye
        if torso and math.abs(torso) >= 1.0 then
            rec._dck_cooldown = 10   -- set before returning so it persists
            return VTYPE.DCK, torso, 0.78
        end
    end

    -- [CTR] jitter center pass: high variance history, pose near 0
    if PoseVar(rec.hist) > 60
       and math.abs(pose) < CFG.CTR_THRESH
       and rec.prev_pose and math.abs(rec.prev_pose) >= 18 then
        if not safe_eye then return nil, 0, 0 end
        return VTYPE.CTR, safe_eye, 0.72
    end

    return nil, 0, 0
end

-- ══════════════════════════════════════════════════════════════════
--  CHEAT REVEALER  — which cheat each enemy runs, from voice packets
--
--  Every HvH cheat sends voice-data packets with its own fingerprint in
--  the xuid / sequence fields (shared-ESP and user-identification
--  traffic, sent without anyone talking). The detectors below are the
--  ones from the cheat revealer script, ported unchanged in logic: each
--  needs a run of 17-45 matching packets before it answers, so a single
--  odd packet never labels anyone. CHEAT_OF[entindex] = "gs" | "nl" |
--  "nw" | "pd" | "ot" | "ft" | "pl" | "ev" | "r7" | "af".
--
--  What the resolver does with it: see CHEAT PROFILES.
-- ══════════════════════════════════════════════════════════════════
local CHEAT_OF    = {}   -- [entindex] = cheat id
local CHEAT_NAMES = {gs = "gamesense", nl = "neverlose", nw = "nixware", pd = "pandora",
                     ot = "onetap", ft = "fatality", pl = "plaguecheat", ev = "ev0lve",
                     r7 = "rifk7", af = "airflow", pm = "primordial"}

local voice_data_t = ffi.typeof([[
    struct {
        char     pad_0000[8];
        int32_t  client;
        int32_t  audible_mask;
        uint32_t xuid_low;
        uint32_t xuid_high;
        void*    voice_data;
        bool     proximity;
        bool     caster;
        char     pad_001E[2];
        int32_t  format;
        int32_t  sequence_bytes;
        uint32_t section_number;
        uint32_t uncompressed_sample_offset;
        char     pad_0030[4];
        uint32_t has_bits;
    } *
]])

-- 16-bit word at a byte offset of the packet, as the revealer formats it
local function VWord(packet, off)
    return ("%.02X"):format(ffi.cast("uint16_t*", ffi.cast("uintptr_t", packet) + off)[0])
end

local function DupEvery(array, divisor)
    local visited = {}
    for i = 1, #array do
        local v = array[i]
        if not visited[v] then
            visited[v] = true
            for j = i + 4, #array do
                if i % divisor == 0 then
                    if array[j] == v then return true end
                elseif array[j] == v then
                    return false
                end
            end
        end
    end
    return false
end

local CS = {nl = {sig_count = {}, found = {}, n_found = 0}, nw = {}, pd = {}, ot = {},
            ft = {}, pl = {}, ev = {}, r7 = {}, af = {}, gs = {}, pm = {}}

-- Counts a run of packets where test() holds; true once it exceeds need.
local function Run(store, target, hit, need)
    local n = store[target] or 0
    if n > need then return true end
    store[target] = hit and n + 1 or 0
    return false
end

local DETECT = {
    nl = function(p, t)
        if p.xuid_high == 0 then return false end
        local sig = VWord(p, 22)
        if sig == CS.nl.current then
            local c = (CS.nl.sig_count[t] or 0) + 1
            CS.nl.sig_count[t] = c
            if c > 24 then
                if not CS.nl.found[t] then CS.nl.found[t] = true; CS.nl.n_found = CS.nl.n_found + 1 end
                return true
            end
            CS.nl.sig_count[t] = nil
        end
        if CS.nl.n_found > 3 then return false end
        local h = CS.nl[t]
        if not h then h = {}; CS.nl[t] = h end
        h[#h + 1] = p.xuid_high
        if #h > 24 then
            if DupEvery(h, 4) then
                CS.nl.current = sig
                CS.nl[t] = {}
                return true
            end
            table.remove(h, 1)
        end
        return false
    end,
    nw = function(p, t)
        local n = CS.nw[t] or 0
        if n > 34 then CS.nw[t] = nil; return true end
        CS.nw[t] = (p.xuid_high == 0) and n + 1 or 0
        return false
    end,
    pd = function(p, t) local s = VWord(p, 16); return Run(CS.pd, t, s == "695B" or s == "1B39", 24) end,
    ot = function(p, t)
        local h = CS.ot[t]
        if not h then h = {}; CS.ot[t] = h end
        -- The revealer compares xuid_low and section_number only (its
        -- third field was stored under a misspelt key and always matched).
        h[#h + 1] = {xl = p.xuid_low, sn = p.section_number}
        if #h > 16 then
            local o = h[1]
            for i = 2, #h do
                if h[i].xl ~= o.xl or h[i].sn ~= o.sn then table.remove(h, 1); return false end
            end
            table.remove(h, 1)
            return true
        end
        return false
    end,
    ft = function(p, t)
        local n = CS.ft[t] or 0
        if n > 36 then return true end
        local s = VWord(p, 16)
        if s == "7FFA" or s == "7FFB" then CS.ft[t] = n + 1 end
        return false
    end,
    pl = function(p, t) return Run(CS.pl, t, VWord(p, 44) == "7275", 24) end,
    ev = function(p, t)
        local h = CS.ev[t]
        if not h then h = {}; CS.ev[t] = h end
        h[#h + 1] = p.xuid_high
        if #h > 44 then
            for i = 1, #h - 4 do
                if h[i + 1] + h[i + 2] == h[i] * 2 and h[i + 4] == h[i] + 1 then
                    CS.ev[t] = {}
                    return true
                end
            end
            table.remove(h, 1)
        end
        return false
    end,
    r7 = function(p, t) local s = VWord(p, 16); return Run(CS.r7, t, s == "234" or s == "134", 24) end,
    af = function(p, t) return Run(CS.af, t, VWord(p, 16) == "AFF1", 24) end,
    gs = function(p, t)
        local sig = VWord(p, 22)
        local bytes = string.sub(tostring(p.sequence_bytes), 1, 4)
        local g = CS.gs[t]
        if not g then g = {repeated = 0, packet = sig, bytes = bytes}; CS.gs[t] = g end
        if bytes ~= g.bytes and sig ~= g.packet then
            g.packet, g.bytes, g.repeated = sig, bytes, g.repeated + 1
        else
            g.repeated = 0
        end
        if g.repeated >= 36 then
            CS.gs[t] = {repeated = 0, packet = sig, bytes = bytes}
            return true
        end
        return false
    end,
}
DETECT.pm = function(p, t)
    -- Primordial, from tickcount/voice-listener.lua (the cheat revealer
    -- author's library; the revealer ported above names primordial but has
    -- no detector for it). Its shared-ESP packets are NOT the "reliable"
    -- kind, carry 0x4D in (sequence_bytes low byte XOR offset byte) minus
    -- sequence_bytes' high half, and encode the sender's own entindex.
    -- Reliability is decided here without dereferencing voice_data (the
    -- library reads its size through that pointer): a packet whose
    -- has_bits / format already rule "reliable" out qualifies, else not.
    local hb = p.has_bits
    if bit.band(bit.rshift(hb, 6), 1) ~= 0 and p.format == 0 and bit.band(hb, 0x185) == 0x185 then
        return false
    end
    local sb, uo = p.sequence_bytes, p.uncompressed_sample_offset
    if sb == 0 and p.section_number == 0 and uo == 0 then return false end
    local mark = bit.bxor(bit.band(sb, 0xFF), bit.band(bit.rshift(uo, 16), 0xFF)) - bit.rshift(sb, 16)
    if bit.band(mark, 0xFF) ~= 0x4D then return false end
    if bit.band(bit.bxor(bit.rshift(sb, 16), bit.rshift(sb, 8)), 0xFF) ~= t then return false end
    -- Counted within 120 s, not as a run. The library trusts more than 4;
    -- 12 here, in line with the 17-45 packet runs of the detectors above.
    local now = globals.realtime()
    local h = CS.pm[t]
    if not h then h = {}; CS.pm[t] = h end
    h[#h + 1] = now
    while h[1] and now - h[1] > 120 do table.remove(h, 1) end
    if #h > 12 then CS.pm[t] = {}; return true end
    return false
end
local DETECT_ORDER = {"nl", "nw", "pd", "ot", "ft", "pl", "ev", "r7", "af", "pm", "gs"}

-- Which detections may replace an existing one: the revealer's precedence
-- (a neverlose read can't overwrite ev/gs/pl/pd/r7/af/ft, and so on).
local CHEAT_KEEP = {
    nl = {ev = true, gs = true, pl = true, pd = true, r7 = true, af = true, ft = true},
    nw = {nl = true},
    ev = {pd = true, nl = true, ft = true},
    gs = {ev = true, ot = true, pl = true, pd = true, r7 = true, ft = true,
          -- the gamesense read only needs sequence bytes and xuid to keep
          -- changing, which primordial's packets also do; the primordial
          -- read (mark + own entindex, ~1 in 65536 by chance) is stricter
          pm = true},
    ot = {nw = true, ft = true, pd = true, pl = true},
    ft = {nw = true, pd = true},
}

local function OnVoice(e)
    if not e or not e.data then return end
    local packet = ffi.cast(voice_data_t, e.data)
    local target = (ffi.cast("char*", packet) + 8)[0] + 1
    for _, id in ipairs(DETECT_ORDER) do
        local cur = CHEAT_OF[target]
        if cur ~= id and not (cur and CHEAT_KEEP[id] and CHEAT_KEEP[id][cur])
           and DETECT[id](packet, target) then
            CHEAT_OF[target] = id
            if cur ~= id then
                info("cheat", "player=%s cheat=%s", entity.get_player_name(target) or "?", CHEAT_NAMES[id])
            end
        end
    end
end

-- A slot's data belongs to whoever held it: cleared when the slot changes
-- hands and on map change.
local function ForgetCheat(ent)
    CHEAT_OF[ent] = nil
    for _, st in pairs(CS) do if type(st) == "table" then st[ent] = nil end end
    CS.nl.sig_count[ent] = nil
    if CS.nl.found[ent] then CS.nl.found[ent] = nil; CS.nl.n_found = CS.nl.n_found - 1 end
end
local function ForgetAllCheats()
    for ent in pairs(CHEAT_OF) do CHEAT_OF[ent] = nil end
    CS = {nl = {sig_count = {}, found = {}, n_found = 0}, nw = {}, pd = {}, ot = {},
          ft = {}, pl = {}, ev = {}, r7 = {}, af = {}, gs = {}, pm = {}}
end

-- ══════════════════════════════════════════════════════════════════
--  CHEAT PROFILES  — how the resolver changes once the cheat is known
--
--  1. Lua presets only for the cheat that runs that Lua. luasense_beta /
--     luasense_std are presets of the NEVERLOSE luasense (v8.0-v8.9 had
--     this backwards and gave them to gamesense users only); a player
--     detected on any other cheat can't be running them, so a fingerprint
--     match is noise and they get the default L/R table. "symmetric" is a
--     desync shape, not a Lua, and applies whatever the cheat. Unknown
--     cheat: every preset, as v6.2.
--
--  2. Per-cheat method trust, learned. Every head hit and resolver miss is
--     credited to (enemy cheat, method) across all players on that cheat
--     and saved between sessions. A method whose head rate on that cheat
--     is <= 30% after >= 8 of those shots (Beta mean (h+1)/(n+2) < 0.35)
--     is skipped for that cheat and the chain falls through to the next
--     method -- except on every 4th shot at the player, so the method can
--     prove itself again. For a method that really hits 70% of the time
--     the chance of being skipped at 8 shots is ~1%; one that hits 30% is
--     caught about half the time by 8 shots and more after.
--     Unknown cheat, or too few shots: exactly the v6.2 chain.
-- ══════════════════════════════════════════════════════════════════
local CHEAT_DB_KEY = "riftveil_cheat_v1"
local CP = {MIN_N = 8, MAX_MEAN = 0.35, PROBE_EVERY = 4, CAP = 60}
local CHEAT_STATS = {}   -- [cheat id][meth] = {h = head hits, m = resolver misses}
-- At most CAP shots per (cheat, method), rate kept: past CAP each credit
-- halves, so a cheat's AA update shows up within a few matches. Applied on
-- load too -- a saved 0/5e8 (hand edit, old bug) would otherwise take ~90
-- shots of halving before the method could be trusted again.
function CP.Fit(c)
    while c.h + c.m > CP.CAP do c.h, c.m = c.h / 2, c.m / 2 end
end
CP.logged = {}          -- [cheat id] = last "[cheat] learned" text
do
    local raw = database.read(CHEAT_DB_KEY)
    if type(raw) == "table" then
        for id, T in pairs(raw) do
            if (CHEAT_NAMES[id] or id == "all") and type(T) == "table" then
                local dst = {}
                for meth, c in pairs(T) do
                    if type(meth) == "string" and type(c) == "table" and isnum(c.h, 0) and isnum(c.m, 0) then
                        dst[meth] = {h = c.h, m = c.m}
                        CP.Fit(dst[meth])
                    end
                end
                CHEAT_STATS[id] = dst
            end
        end
    end
end

-- FEATURE.BEAT_BUILTIN: gamesense resolves by default; one of our methods
-- forces only while it keeps up with gamesense's own head rate -- on the
-- enemy's cheat when both have CP.MIN_N head-aimed shots there, else across
-- everyone ("all"). More than CP.MARGIN below it: the enemy goes back to
-- gamesense, and every CP.PROBE_EVERY-th shot still tries the method. The
-- public resolvers that steer gamesense work the same way: Force body yaw
-- on only where they know more, off (gamesense's own) everywhere else.
CP.MARGIN = 0.05
local function Rate(st) return (st.h + 1) / (st.h + st.m + 2) end
local function Enough(st) return st and st.h + st.m >= CP.MIN_N end
local function BeatsBuiltin(rec, meth)
    local T = rec.cheat and CHEAT_STATS[rec.cheat]
    if not (T and Enough(T[meth]) and Enough(T.builtin)) then T = CHEAT_STATS.all end
    local sm, sb = T and T[meth], T and T.builtin
    if not (Enough(sm) and Enough(sb)) then return true end
    return Rate(sm) >= Rate(sb) - CP.MARGIN
end

local function CheatTrusts(rec, meth)
    if FEATURE.BEAT_BUILTIN and meth ~= "builtin" and not BeatsBuiltin(rec, meth) then
        return ((rec.shots_fired or 0) % CP.PROBE_EVERY) == 0
    end
    if not DET.cheat then return true end
    local c = rec.cheat
    local st = c and CHEAT_STATS[c] and CHEAT_STATS[c][meth]
    if not st or st.h + st.m < CP.MIN_N then return true end
    if (st.h + 1) / (st.h + st.m + 2) >= CP.MAX_MEAN then return true end
    return ((rec.shots_fired or 0) % CP.PROBE_EVERY) == 0
end

-- [cheat id] = "meth=heads/shots ..." (sorted), for the log and rv_db
local function CheatTexts()
    local out = {}
    for id, T in pairs(CHEAT_STATS) do
        local parts = {}
        for meth, c in pairs(T) do
            parts[#parts + 1] = string.format("%s=%.0f/%.0f", meth, c.h, c.h + c.m)
        end
        table.sort(parts)
        if #parts > 0 then out[id] = table.concat(parts, " ") end
    end
    return out
end
CheatDB = {
    Texts = CheatTexts,
    Lines = function()
        local lines = {}
        for id, text in pairs(CheatTexts()) do lines[#lines + 1] = id .. " | " .. text end
        table.sort(lines)
        return lines
    end,
    Wipe = function()
        for id in pairs(CHEAT_STATS) do CHEAT_STATS[id] = nil end
        for id in pairs(CP.logged) do CP.logged[id] = nil end
        database.write(CHEAT_DB_KEY, CHEAT_STATS)
        info("cheat", "learned cheat profiles wiped")
    end,
}

local function Credit1(id, meth, head)
    local T = CHEAT_STATS[id]
    if not T then T = {}; CHEAT_STATS[id] = T end
    local st = T[meth]
    if not st then st = {h = 0, m = 0}; T[meth] = st end
    if head then st.h = st.h + 1 else st.m = st.m + 1 end
    CP.Fit(st)
end
local function CheatCredit(cheat, meth, head)
    if type(meth) ~= "string" then return end
    if cheat and CHEAT_NAMES[cheat] then Credit1(cheat, meth, head) end
    -- every enemy, cheat known or not: what BEAT_BUILTIN falls back on
    if FEATURE.BEAT_BUILTIN then Credit1("all", meth, head) end
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
local function GetS64(player)
    local s64 = entity.get_steam64(player)
    if s64 and s64 ~= 0 then
        -- %.0f: tostring prints a 64-bit id held in a double as 7.6e+16
        local k = (type(s64) == "number") and string.format("%.0f", s64) or tostring(s64)
        EIDX_S64[player] = k; return k
    end
    local n = entity.get_player_name(player)
    if n and n ~= "" and n ~= "unknown" then
        local k = "n:" .. n; EIDX_S64[player] = k; return k
    end
    return nil
end

local function NewRec(player, s64)
    local db = CleanDBEntry(DB[s64]) or {}
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
        -- DB entry as this match started: FlushDB merges into it (see there)
        db_base=CleanDBEntry(DB[s64]),
        -- a known cheat id only: a saved "zz" (hand edit, other script)
        -- would switch off the gamesense presets and show in the panel
        cheat=CHEAT_NAMES[db.cheat] and db.cheat or nil,
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
        vuln_ttl=0, vuln_type=nil, vuln_val=0,
        prev_pose=nil, prev_spd=nil, prev_duck=nil, prev_onground=nil,
        cur_choke=0, was_choked=false, unk_miss_streak=0,
        kills=0, eidx=player,
        -- nothing forced yet: builtin (STALE_WINDOW; v6.2 said ring, val 0)
        active=false, resolved=false, last_val=0, last_meth=FEATURE.STALE_WINDOW and "builtin" or METH.RING,
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
        _lc_on = false,    -- last record broke lag comp: SHIFT box drawn (DrawShiftMarkers)
        _lc_ticks = 0, _lc_t = 0,  -- its record gap in ticks, when it came
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
        -- seed= : the DB-seeded starting confidence (0 = cold start), so a
        -- log can show whether seeding pays (see ROADMAP, DB hit rate)
        info("rec", "new profile player=%s s64=%s seed=%.2f",
             entity.get_player_name(player) or "?", s64, REC[s64].conf or 0)
    end
    local rec = REC[s64]
    rec.eidx = player
    -- A live detection wins over the one saved with the profile
    local c = CHEAT_OF[player]
    if c and rec.cheat ~= c then rec.cheat = c end
    return rec, s64
end

-- "Correction active" is gamesense's own resolver for that player, on by
-- default: vandal turns it off while its resolver runs and back on to hand
-- the player back, tsv4 turns it off for bots (no desync), angelwings keeps
-- it on, tickcount's Eagle ESP reads it as "FAKE". Up to 8.7 every release
-- here set it OFF -- "release to the built-in" left the player with no
-- resolver at all, and after a round reset, switching RIFTVEIL off or
-- unloading it, all 64 slots stayed that way. Releases now hand it back on.
local function ClearEnt(player)
    PSet(player, "Force body yaw", false)
    PSet(player, "Force body yaw value", 0)
    PSet(player, "Correction active", true)
    PSet(player, "High priority", false)
    local s64 = EIDX_S64[player]
    if s64 and REC[s64] then
        REC[s64].active = false; REC[s64].resolved = false
        -- FEATURE.STALE_WINDOW: nothing is forced now, so a shot fired before
        -- the next decision is gamesense's -- label it so, as the release
        -- path in ProcessPlayer does (v6.2 kept the last forced method)
        if FEATURE.STALE_WINDOW then REC[s64].last_meth = "builtin"; REC[s64].last_val = 0 end
    end
end

-- A vuln window is open AND is what we force (FEATURE.STALE_WINDOW). The
-- count alone freezes while the enemy is released, dead or dormant.
local function WindowForced(rec)
    if rec.vuln_ttl <= 0 then return false end
    return not FEATURE.STALE_WINDOW or tostring(rec.last_meth):sub(1, 5) == "vuln_"
end

-- ══════════════════════════════════════════════════════════════════
--  DB FLUSH
--  Called on match end. Blends new match data with existing DB entry.
-- ══════════════════════════════════════════════════════════════════
-- DB_GEN stamps each saved profile with the session that last saw it, so
-- the cap below drops the stalest first. The whole DB is written on every
-- 60 s autosave; uncapped it grows with every opponent ever met.
local DB_MAX = 500
local DB_GEN = 1
for _, e in pairs(DB) do
    if e.gen and e.gen >= DB_GEN then DB_GEN = e.gen + 1 end
end

FlushDB = function()
    for s64, rec in pairs(REC) do
        if rec.hit_count >= 2 then
            -- Merge into the entry as it was BEFORE this match (db_base,
            -- snapshotted in NewRec). Merging into the live DB[s64] made
            -- every 60 s autosave add the whole match again: one player's
            -- 3 hits were stored as 3, 6, 9 ... 36 over twelve autosaves.
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
                bt_pref     = rec.preferred_bt > 0 and rec.preferred_bt or ex.bt_pref,
                hit_rate    = tot_n > 0
                    and (nhr * this_n + (ex.hit_rate or 0) * prev_n) / tot_n
                    or nhr,
                samples     = tot_n,
                kills       = (ex.kills or 0) + rec.kills,
                cheat       = rec.cheat or ex.cheat,
                gen         = DB_GEN,
            }
            info("db", "flush s64=%s cfg=%s vuln=%s bt=%d hr=%d%% hits=%d",
                 s64,
                 DB[s64].config_type or "?", DB[s64].vuln_pref or "?",
                 DB[s64].bt_pref or 0,
                 math.floor((DB[s64].hit_rate or 0) * 100),
                 DB[s64].kills)
        end
    end
    local keys = {}
    for k in pairs(DB) do keys[#keys + 1] = k end
    if #keys > DB_MAX then
        table.sort(keys, function(a, b) return ((DB[a] or {}).gen or 0) < ((DB[b] or {}).gen or 0) end)
        for i = 1, #keys - DB_MAX do DB[keys[i]] = nil end
        info("db", "pruned %d stale profiles", #keys - DB_MAX)
    end
    database.write(DB_KEY, DB)
    database.write(CHEAT_DB_KEY, CHEAT_STATS)
    -- only what changed since the last save: the autosave runs every 60 s
    -- and every cheat ever seen is in the table
    for id, text in pairs(CheatDB.Texts()) do
        if CP.logged[id] ~= text then
            CP.logged[id] = text
            info("cheat", "learned %s: %s", id, text)
        end
    end
    info("db", "written %d entries", math.min(#keys, DB_MAX))
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

    TrackDT(s64, st_raw)

    local choke = ChokedPkts(st_raw, ctx.cur_lat)
    rec.was_choked   = rec.cur_choke > 0
    rec.cur_choke    = choke
    rec.def_tickbase = IsDefTick(s64)

    local st = math.floor(st_raw / ctx.ti)
    if st == rec.lt then return end
    -- DEFENSIVE FRAME COUNT (measurement only, no decision reads it): lag
    -- compensation writes no record while a player's simulation time is at
    -- or below the highest it has sent (tickcount/lagrecord-csgo.lua), so a
    -- frame arriving with a lower simtime is a defensive frame -- the one
    -- defensive AA fills with pitch up / zero and a yaw flick. v6.2 samples
    -- it like any other; the shot log's df= says how many there were.
    local def_frame = rec.st_max and st < rec.st_max and rec.st_max - st <= 64
    if def_frame then
        -- counted once per frame: rec.lt stays on the last real record, so
        -- an enemy choking inside its defensive window shows the same lower
        -- simtime on every net update (v8.7-8.20 counted each of them)
        if st ~= rec.def_st then
            rec.def_st = st
            local r = rec.dfr
            if not r then r = {}; rec.dfr = r end
            r[#r + 1] = ctx.cur_tc
            if #r > 32 then table.remove(r, 1) end
        end
        -- Not sampled (FEATURE.SKIP_DEF_FRAMES): it would go into the pose
        -- ring, the yaw cache and, on a tick never recorded (fakelag skips
        -- many), the lag-comp table that the LAGCOMP method reads. rec.lt
        -- stays on the last real record, as lagrecord's records[1] does.
        if FEATURE.SKIP_DEF_FRAMES then return end
    end
    if not rec.st_max or st > rec.st_max or rec.st_max - st > 64 then rec.st_max = st end
    -- FEATURE.STALE_WINDOW: a record more than 64 ticks after the last one
    -- (death, dormancy, a new round) closes the vuln window. It only counts
    -- down on records, so v6.2 carried it -- and its torso yaw -- over.
    if FEATURE.STALE_WINDOW and rec.lt and st - rec.lt > 64 then rec.vuln_ttl = 0 end
    -- record gaps (ticks between this record and the last) for NoChoke; a
    -- gap past 64 (death, dormancy, new round) starts the history over
    if rec.lt then
        local g = rec.gaps
        if not g or st - rec.lt > 64 then g = {}; rec.gaps = g end
        if st - rec.lt <= 64 then
            g[#g + 1] = st - rec.lt
            if #g > NOCHOKE_N then table.remove(g, 1) end
        end
    end
    rec.lt = st
    -- PROBE (log only): the value we forced for the animation this record
    -- was built with, to set against the pose read back below (pz= / pf=
    -- on [corr]). The body-yaw pose is computed by our client, not sent by
    -- the server, so it may be our own forced value coming back.
    local pf = rec.active and rec.last_val or nil
    -- FEATURE.POSE_CLEAN: the body-yaw pose is our client's; on a record
    -- built while we forced a value it reads that value back (bots with no
    -- desync came out hold / 2-way / 3-way on 56 of 64 shots). Only records
    -- built with nothing forced feed the AA picture, side, flips and the
    -- pose-triggered windows (LBY / CTR).
    local sample = not FEATURE.POSE_CLEAN or pf == nil

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
            rec._lc_on = false
            break
        end

        if choke > 2 then
            ClearEnt(player)
            rec.prev_pose = nil
            rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_z = nil, nil, nil
            rec.prev_origin_tick = nil
            rec._lc_on = false
            break
        end

        -- Velocity — read once, shared by the state tracker, the velocity
        -- correction cap, and DetectVuln's STP/PKA checks below.
        local vx0, vy0 = entity.get_prop(player, "m_vecVelocity")
        spd = (isnum(vx0) and isnum(vy0)) and math.sqrt(vx0*vx0 + vy0*vy0) or 0
        local ox, oy, oz = entity.get_origin(player)

        -- State (STATE TRACKER)
        local state_key, state_spd = TrackState(rec, player, as, spd, st, ox, oy, ctx.ti)
        rec.state, rec.state_spd = state_key, state_spd
        if rec.conf == 0 then rec.conf = CFG.STATE_SEED[state_key] or 0.25 end

        -- Live per-player desync bounds from animstate.
        -- Replaces the hardcoded DESYNC_CAP = 58 with actual engine-reported
        -- clamp values. Falls back to 58 if not yet populated.
        local live_mn, live_mx, live_cap = LiveCap(as)
        rec.live_min = live_mn
        rec.live_max = live_mx

        -- Velocity-constrained correction cap — see VelCap(). Used only to
        -- clamp CfgAngle's static guesses, never the engine-read live_cap.
        local corr_cap
        if FEATURE.DESYNC_FORMULA then corr_cap = MaxDesync(as, spd, EnemyMaxSpeed(player), live_cap)
        else corr_cap = VelCap(spd, live_cap) end
        rec.corr_cap = corr_cap

        if DET.verbose then
            if live_cap ~= CFG.DESYNC_CAP then
                dbg("dcap", "player=%s live=[%.1f .. %.1f] cap=%.1f corr=%.1f spd=%.0f",
                    entity.get_player_name(player) or "?", live_mn, live_mx, live_cap, corr_cap, spd)
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

        -- Sample
        -- the server's LBY target: when it last moved (shot log lbyu=)
        local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
        if isnum(lby) then
            if isnum(rec.lby_last) and math.abs(NA(lby - rec.lby_last)) > 1 then rec.lby_t = globals.realtime() end
            rec.lby_last = lby
        end
        local praw = entity.get_prop(player, "m_flPoseParameter", 11) or 0
        pose = praw * CFG.POSE_SCALE - 60
        local _, eyy = entity.get_prop(player, "m_angEyeAngles")
        local eye_y  = as.eye_angles_y or eyy or 0
        duck      = as.duck_amount or 0
        on_ground = as.on_ground

        -- ORIGIN-JUMP SHIFT CHECK: a >64-unit origin teleport on a clean
        -- (choke==0) tick is a direct shifting/broken-backtrack-record
        -- signal -- confirmed independently in THREE real scripts now, all
        -- using this exact 4096 sq-unit (64-unit) threshold: a public CS:GO
        -- lagrecord library, a full HvH cheat's own broke_lc check, and a
        -- standalone "lag comp breaker" ESP tool that draws a 3D box on it.
        -- Stronger and more immediate than the indirect tm[]-gap proxy
        -- below, so it sets _shift_streak straight to the distrust floor
        -- instead of accumulating gradually. _lc_on / _lc_ticks drive the
        -- world-space "SHIFT" tag + box in DrawOverlay, adapted from that
        -- same ESP tool's extrapolation technique.
        if isnum(ox) and isnum(oy) and rec.prev_origin_x and rec.prev_origin_y then
            local dx, dy = ox - rec.prev_origin_x, oy - rec.prev_origin_y
            local d2 = dx*dx + dy*dy
            local gap = rec.prev_origin_tick and (st - rec.prev_origin_tick) or 0
            local shifted
            if FEATURE.SHIFT_GAP then
                local reach = gap * 3500 * ctx.ti   -- sv_maxvelocity per tick
                shifted = d2 > 4096 and gap >= 2 and gap <= 64 and d2 <= reach * reach
            else
                shifted = choke == 0 and d2 > 4096
            end
            if shifted then
                rec._shift_streak = math.max(rec._shift_streak or 0, 3)
            end
            -- the SHIFT box (DrawShiftMarkers) shows while this holds, as
            -- lagcomp-box-gs shows its box while net_data.lagcomp holds:
            -- until a record arrives that doesn't break lag comp
            rec._lc_on = shifted and true or false
            if shifted then rec._lc_ticks, rec._lc_t = Clamp(gap, 1, 32), globals.realtime() end
        end
        rec.prev_origin_x, rec.prev_origin_y, rec.prev_origin_z = ox, oy, oz
        rec.prev_origin_tick = st

        if sample then RPush(rec.hist, {p=pose, e=eye_y, t=st}) end
        -- gamesense's own answer: the pose on a record built with nothing
        -- forced is its resolved body yaw (LEARN_GS, shot log gs=)
        if pf == nil and isnum(pose) then rec.gs_pose, rec.gs_t = pose, globals.realtime() end
        -- Pruned by age: clearing only tm[st - TM_HORIZON] leaked every
        -- entry a fakelagging enemy's skipped simtime ticks never revisit
        -- (2,500 after 20k ticks). Lookups stay within the horizon.
        if sample and not rec.tm[st] then
            rec.tm[st] = {p=pose, e=eye_y, t=st}
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
        -- FEATURE.NO_CHOKE_STATIC: an enemy that chokes nothing can't desync,
        -- whatever the pose (which our client computes) shows
        if FEATURE.NO_CHOKE_STATIC then
            local nc = NoChoke(rec)
            if nc then aa_type = AA.STATIC end
            if DET.verbose and nc ~= (rec._nochoke == true) then
                dbg("aa", "player=%s %s", entity.get_player_name(player) or "?",
                    nc and "sends every tick (no choke): no desync possible -> gamesense"
                       or "chokes again: resolving")
            end
            rec._nochoke = nc
        end
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

        -- Confidence and side: from a clean record only (POSE_CLEAN); on one
        -- we forced, the pose is our own value read back
        if sample then
            if six_side ~= 0 then
                rec.conf = math.min(rec.conf + 0.08, 1.0)
                if dom_side ~= 0 and dom_side == six_side then
                    rec.conf = math.min(rec.conf + 0.05, 1.0)
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
        end

        -- Config recognition (throttled)
        -- FEATURE.CFG_CADENCE: due once CFG_TICKS sim ticks have passed since
        -- the last run (or simtime went backwards: new map). v6.2 ran it on
        -- st % 32 == 0, which an enemy sending records on a fixed even
        -- cadence can skip forever (every 2 ticks on odd ticks: never).
        local cfg_due
        if FEATURE.CFG_CADENCE then
            cfg_due = not rec._cfg_st or st - rec._cfg_st >= CFG.CFG_TICKS or st < rec._cfg_st
        else
            cfg_due = (st % CFG.CFG_TICKS) == 0
        end
        if rec.config_conf < 0.8 and cfg_due then
            if FEATURE.CFG_CADENCE then rec._cfg_st = st end
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

        -- KNOWN_ONLY: pose confidence doesn't gate the event windows or hit
        -- memory (it is a pose number); low confidence only means no guess
        if rec.conf < CFG.CONF_MIN and not FEATURE.KNOWN_ONLY then ClearEnt(player); break end

        -- Vulnerability window
        if rec.vuln_ttl > 0 then rec.vuln_ttl = rec.vuln_ttl - 1 end

        -- POSE_CLEAN: no LBY / CTR "snap" across a record we forced
        if not sample then rec.prev_pose = nil end
        local vtype, vcorr = DetectVuln(rec, as, pose, eye_y, spd, corr_cap, al6_weight)
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
        -- because it rarely got fired at. seen is now credited in
        -- on_aim_fire, once per actual shot taken during an open vuln
        -- window -- the same definition of "trial" that on_aim_hit
        -- already uses for hit.
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
            if DET.verbose then
                dbg("vuln", "type=%s val=%.1f player=%s ttl=%d%s",
                    vtype, vcorr, entity.get_player_name(player) or "?",
                    rec.vuln_ttl, is_standing and " [STAND]" or "")
            end
        end

        -- Backtrack depth is observed passively via aim_fire.backtrack.
        -- We do NOT manipulate cl_interp here — restricting it to preferred_bt
        -- caps the aimbot's maximum backtrack window and kills deeper opportunities.

        -- ── SIDE TRACKING ──────────────────────────────────────────────
        -- Track which side we believe the enemy is on.
        -- The override block below decides whether to apply it.
        -- We do NOT compute an angle here — that happens per-case below.

        local tracked_side   = rec.side
        local tracked_method = METH.RING
        rec._brute_half       = false  -- set true below only on a true blind-guess tick

        -- Lower confidence threshold when meta_aggressive — even a weaker
        -- vuln read beats the known-failing built-in.
        local vuln_min = rec.meta_aggressive and 0.20 or 0.35
        -- The vuln window is forced this record (the [1] branch below).
        local vuln_on = DET.vuln and rec.vuln_ttl > 0
                        and (rec.conf >= vuln_min or FEATURE.KNOWN_ONLY)
                        and not (FEATURE.KNOWN_ONLY and (rec.vuln_type == VTYPE.LBY or rec.vuln_type == VTYPE.CTR))
                        and CheatTrusts(rec, "vuln_" .. tostring(rec.vuln_type))
        -- FEATURE.WINDOW_GATE: only a window we force stands the side chain
        -- and suppress down. v6.2 used vuln_ttl alone, so a window it didn't
        -- apply (Vulnerability off, the cheat distrusting that type, low
        -- confidence) switched suppress off for its 11 records and left the
        -- fallback on the raw, unflipped side.
        local window_blocks
        if FEATURE.WINDOW_GATE then window_blocks = vuln_on else window_blocks = rec.vuln_ttl > 0 end

        if not window_blocks then
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
                local lco = LCTicks(false, ctx.cur_lat, ctx.avg_lat)
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
            local is_jitter = aa_type == AA.TWO_WAY -- luacheck: ignore 211
                            or aa_type == AA.THREE_WAY
                            or aa_type == AA.FIVE_WAY or aa_type == AA.SKITTER
                            or aa_type == AA.HOLD
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
                    ClearEnt(player); break
                end
            end
        end

        -- ── ADDITIVE OVERRIDE ──────────────────────────────────────────
        -- Only take control from the built-in when signal is definitive.
        -- Priority: vuln > 6lex > hit_mem > meta_hold > suppress > release
        local should_override = false
        local override_val    = 0
        local override_meth   = tracked_method
        local sup_pausing     = false  -- true only during the suppress streak-cap's pause window

        -- [1] Vulnerability window: correction is deterministic.
        if vuln_on then
            should_override = true
            override_val    = rec.vuln_val
            override_meth   = "vuln_" .. rec.vuln_type

        -- [2] 6lex: animlayer digit read — direct, no guessing. Gated by
        -- per-player calibration: once it's been proven wrong against
        -- confirmed hits more than a small margin above how often it's
        -- been right for THIS player, stop trusting it for them and fall
        -- through to hit-mem/suppress instead (see on_aim_hit).
        elseif DET.six and six_side ~= 0 and rec.conf > 0.25
               and (rec.six_disagree or 0) <= (rec.six_agree or 0) + 2
               and CheatTrusts(rec, METH.SIX_LEX) then
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
               and (rec.hit_side_by_state[rec.state] or 0) ~= 0
               and CheatTrusts(rec, METH.HIT_MEM) then
            should_override = true
            override_val    = CfgAngle(rec.hit_side_by_state[rec.state], rec.state, TrustedCfg(rec), FEATURE.FULL_DESYNC and corr_cap or live_cap)
            override_meth   = METH.HIT_MEM

        elseif DET.hitmem and rec.hit_count >= 2 and rec.hit_side ~= 0
               and CheatTrusts(rec, METH.HIT_MEM) then
            should_override = true
            override_val    = CfgAngle(rec.hit_side, rec.state, TrustedCfg(rec), FEATURE.FULL_DESYNC and corr_cap or live_cap)
            override_meth   = METH.HIT_MEM

        -- [4] Suppress [EXP]: force wrong angle to gate aimbot hit-chance.
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
        elseif FEATURE.SUPPRESS and not FEATURE.KNOWN_ONLY and not window_blocks and CheatTrusts(rec, METH.SUPPRESS) then
            local is_jitter = aa_type == AA.TWO_WAY  or aa_type == AA.THREE_WAY
                            or aa_type == AA.FIVE_WAY or aa_type == AA.SKITTER
                            or aa_type == AA.HOLD
            local sup_thresh = rec.meta_aggressive and 0.28 or 0.45
            if is_jitter and rec.conf > sup_thresh then
                local streak = rec._sup_streak or 0
                if streak < 8 then
                    should_override = true
                    local bs = tracked_side ~= 0 and tracked_side or dom_side
                    if bs == 0 then bs = 1 end
                    override_val  = -CfgAngle(bs, rec.state, TrustedCfg(rec), corr_cap)
                    override_meth = METH.SUPPRESS
                else
                    local pause = (rec._sup_pause or 0) + 1
                    rec._sup_pause = pause
                    sup_pausing = true
                    if pause >= 4 then
                        rec._sup_streak = 0
                        rec._sup_pause  = 0
                    end
                end
            end
        end

        if should_override then
            PSet(player, "Force body yaw", true)
            PSet(player, "Force body yaw value", SafeYaw(override_val))
            PSet(player, "Correction active", true)
            -- High priority: confirmed via a real resolver's usage (not in
            -- the official docs) -- hints the LC/backtrack system not to
            -- deprioritize this target's validation window while we're
            -- actively correcting them ("prevent missing LC" per that
            -- script's own comment). Set last so a bad/renamed field
            -- can't stop the actual correction above from applying.
            PSet(player, "High priority", true)
            rec.active = true; rec.resolved = true
            rec.last_val = override_val; rec.last_meth = override_meth
            -- Track suppress streak for the streak-cap logic above
            if override_meth == METH.SUPPRESS then
                rec._sup_streak = (rec._sup_streak or 0) + 1
            else
                rec._sup_streak = 0   -- any non-suppress override resets the streak
            end
            rec._sup_pause = 0

        elseif rec.meta_aggressive and tracked_side ~= 0 and not FEATURE.KNOWN_ONLY then
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
            local meta_cap = (tracked_method == METH.HIT_MEM and not FEATURE.FULL_DESYNC) and live_cap or corr_cap
            local meta_val = CfgAngle(tracked_side, rec.state, TrustedCfg(rec), meta_cap)
            if rec._brute_half then meta_val = meta_val * 0.5 end
            PSet(player, "Force body yaw", true)
            PSet(player, "Force body yaw value", SafeYaw(meta_val))
            PSet(player, "Correction active", true)
            PSet(player, "High priority", true)
            rec.active = true; rec.resolved = true
            rec.last_val = meta_val; rec.last_meth = METH.META_HOLD
            -- Don't blow away a suppress streak/pause in progress -- this
            -- branch fires DURING the deliberate 4-tick pause window (should_
            -- override is false while paused), not just when suppress is
            -- genuinely irrelevant. See sup_pausing above.
            if not sup_pausing then rec._sup_streak = 0; rec._sup_pause = 0 end

        else
            -- release: gamesense's own resolver takes the player (see ClearEnt)
            PSet(player, "Force body yaw", false)
            PSet(player, "Force body yaw value", 0)
            PSet(player, "Correction active", true)
            PSet(player, "High priority", false)
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
                dbg("corr", "player=%s aa=%s side=%d meth=%s val=%.1f override=%s pz=%s pf=%s",
                    entity.get_player_name(player) or "?",
                    aa_type, tracked_side, rec.last_meth, rec.last_val,
                    tostring(should_override),
                    isnum(pose) and string.format("%.0f", pose) or "-",
                    isnum(pf) and string.format("%.0f", SafeYaw(pf)) or "-")
                rec._prev_log_val  = rec.last_val
                rec._prev_log_meth = rec.last_meth
            end
        end

    until true  -- end of repeat block; break exits without running save

    -- Save previous frame state (always, for every path that sampled data)
    rec.prev_pose     = sample and pose or nil
    rec.prev_spd2     = rec.prev_spd  -- shift: spd2 = last tick's spd before this update
    rec.prev_spd      = spd
    -- FEATURE.DCK_GAP: nil when this record wasn't sampled (stale, no
    -- animstate), so DetectVuln doesn't compare the next duck_amount to 0
    if FEATURE.DCK_GAP then rec.prev_duck = duck else rec.prev_duck = duck or 0 end
    rec.prev_onground = on_ground
    -- Decrement DCK cooldown each tick (set to 10 when DCK fires, counts down to 0)
    if (rec._dck_cooldown or 0) > 0 then
        rec._dck_cooldown = rec._dck_cooldown - 1
    end
end


-- ══════════════════════════════════════════════════════════════════
--  UPDATE  — orchestration loop
-- ══════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════
--  WEAPON AIM POLICY  (Detection > Weapon aim)
--
--  The ragebot's per-weapon config stays the base. Per enemy, this only
--  answers one question with the REAL damage available right now: does a
--  body shot kill, does only a head shot kill, or neither?
--
--  REAL DAMAGE. client.trace_bullet from our eye to the enemy's head
--  (hitbox 0) and body (pelvis 2, stomach 3, chest 5) returns the damage a
--  bullet would do along that line -- walls, cover, distance, armor all
--  included -- the same way the public gamesense scripts ("force body aim
--  on peek", "lethality indicator") decide lethality. While we move, a
--  second eye point 4 ticks ahead is traced too, so a peek is judged from
--  where we will shoot, not where we stand.
--
--  DECISION (hp = enemy health):
--    body shot kills          -> prefer body. A body kill doesn't depend on
--      (or two with a charged   the desync side; a head shot does. With
--       double tap, for autos,  double tap an auto or pistol lands two
--       deagle, pistols)        shots before they can react.
--    only the head kills      -> body preference OFF for this enemy, so a
--      (wallbang, body behind   global "prefer body aim" can't trade a
--       cover, scout at full    lethal head for a non-lethal body. On safe
--       HP)                     points when our side is in doubt (two
--                               resolver misses in a row) or they're in
--                               the air.
--    neither kills            -> ragebot default; safe point when our side
--                               is in doubt.
--  "In doubt" since v8.15 also covers a 3-way / 5-way enemy we missed on
--  the resolver less than 10 s ago (FEATURE.XWAY_UNSURE): the next head
--  shot at one landed 43% in the old logs, against 59-77% elsewhere.
--  Nothing is ever forced to body while a head kill is the only kill: the
--  head is always available when it's what kills.
--
--  SELF-CALIBRATION. The docs don't say whether trace_bullet's damage
--  includes the hitgroup multiplier (head x4) and armor. Every shot the
--  ragebot fires carries its own predicted damage; the ratio of that to our
--  traced damage for the same hitgroup is kept (median of the last 15) and
--  applied once 5 shots agree. Until then the traced damage is taken as-is,
--  as the public scripts do.
--
--  PLAYER-LIST VALUES. "Override prefer body aim" = "-" / "Force" and
--  "Override safe point" = "-" / "On" appear in public workshop scripts;
--  "On" and "Off" for body aim are the natural remaining options. Every
--  value is written once, read back, and if it doesn't stick it falls back
--  (body On -> Force -> "-", body Off -> "-", safe point On -> "-") and the
--  log says so ([aim] lines).
-- ══════════════════════════════════════════════════════════════════
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

-- Everything else lives in its own function scope (the main chunk is near
-- Lua's 200-local limit); AIMX is the interface.
local AIMX = (function()
local F_BODY, F_SP = "Override prefer body aim", "Override safe point"
-- per field and value: nil untested, true read back fine, false rejected
local VAL_OK   = {[F_BODY] = {["-"] = true}, [F_SP] = {["-"] = true}}
local FALLBACK = {[F_BODY] = {On = "Force", Force = "-", Off = "-"}, [F_SP] = {On = "-"}}

local HB_HEAD, HB_BODY = 0, {2, 3, 5}          -- head; pelvis, stomach, chest
local DT_WEAPON = {auto = true, deagle = true, pistol = true}
local PEEK_TICKS = 4                            -- eye extrapolation while moving
local EYES = {{0, 0, 0}, {0, 0, 0}}
local CAL = {head = {}, body = {}, fh = 1, fb = 1}

-- Current gamesense has Double tap under RAGE > Aimbot (~660 public
-- scripts reference it there); older builds under RAGE > Other (~280).
-- Up to v8.22 only Other was tried, so on current builds DtReady was
-- always false.
local DT_REF, DT_KEY
for _, tab in ipairs({"Aimbot", "Other"}) do
    local ok, a, b = pcall(ui.reference, "RAGE", tab, "Double tap")
    if ok and a then DT_REF, DT_KEY = a, b; info("aim", "double tap found in RAGE > %s", tab); break end
end
if not DT_REF then warn("aim", "double tap not found in RAGE > Aimbot or Other") end
local function DtReady()
    if not DT_REF then return false end
    local ok1, on = pcall(ui.get, DT_REF)
    if not (ok1 and on) then return false end
    if not DT_KEY then return true end
    local ok2, key = pcall(ui.get, DT_KEY)
    return ok2 and key == true
end

local function Write(ent, field, v)
    local ok = VAL_OK[field]
    local n = 0
    while ok[v] == false and n < 3 do v = FALLBACK[field][v] or "-"; n = n + 1 end
    if not pcall(PSet, ent, field, v) then
        -- the set raised: this value is out, write its fallback now so the
        -- field doesn't keep the previous enemy decision for a tick
        if v ~= "-" then ok[v] = false; Write(ent, field, FALLBACK[field][v] or "-") end
        return
    end
    if ok[v] == nil then
        local okg, back = pcall(plist.get, ent, field)
        ok[v] = okg and back == v
        local fb = FALLBACK[field][v] or "-"
        info("aim", "%s = %s: read back %s -- %s", field, v, tostring(back),
             ok[v] and "supported" or ("not supported, using " .. fb))
        if not ok[v] then
            local c = PL_CACHE[ent]
            if c then c[field] = nil end
            Write(ent, field, fb)
        end
    end
end

-- Highest traced damage to one hitbox from any of our eye points; 0 when
-- the line reaches a different player or nobody.
local function Traced(me, ne, target, hb)
    local okp, x, y, z = pcall(entity.hitbox_position, target, hb)
    if not (okp and isnum(x) and isnum(y) and isnum(z)) then return 0 end
    local best = 0
    for i = 1, ne do
        local e = EYES[i]
        local okt, hit, dmg = pcall(client.trace_bullet, me, e[1], e[2], e[3], x, y, z, false)
        if okt and hit == target and isnum(dmg) and dmg > best then best = dmg end
    end
    return best
end

-- FEATURE.XWAY_UNSURE: last shot at a 3-way / 5-way enemy was a resolver
-- miss less than XWAY_WINDOW seconds ago (last_outcome "m" is set by
-- on_aim_miss, last_fire_t at aim_fire; a hit or another shot clears it).
local XWAY_WINDOW = 10
local function XwayAfterMiss(rec, now)
    if not FEATURE.XWAY_UNSURE then return false end
    if rec.aa_type ~= AA.THREE_WAY and rec.aa_type ~= AA.FIVE_WAY then return false end
    if rec.last_outcome ~= "m" or not isnum(rec.last_fire_t) then return false end
    local dt = now - rec.last_fire_t
    return dt >= 0 and dt < XWAY_WINDOW
end

-- Our side is in doubt for this enemy: two resolver misses in a row
-- outside a vulnerability window, or the x-way case above. Shared with
-- the shot log's "next=sp" so the two can't disagree.
local function InDoubt(rec, now)
    -- STALE_WINDOW: a window we aren't forcing (released enemy) is no window
    local no_win = not WindowForced(rec)
    return ((rec.aim_miss_streak or 0) >= 2 and no_win) or XwayAfterMiss(rec, now)
end

-- The decision itself, on numbers only (unit-tested in the harness).
--   hp: enemy health; head, body: traced damage after calibration;
--   dt2: a charged double tap fires two shots; unsure: our side is in
--   doubt; air: enemy airborne.
local function Decide(hp, head, body, dt2, unsure, air)
    if not (isnum(hp) and hp > 0) then return "-" end
    -- FEATURE.NO_SAFEPOINT: never force safe point. Across the logs it
    -- landed worse than plain shots (sp 47%, head kill + safe point 50%,
    -- ragebot default 57%, head kill 86%); against x-way after a resolver
    -- miss it gave 48% (34/71) where no safe point gave 43% (25/58) -- no
    -- real gain, and safe point is what makes the ragebot wait.
    if FEATURE.NO_SAFEPOINT then unsure, air = false, false end
    if body >= hp or (dt2 and body * 2 >= hp) then return "body" end
    if head >= hp then return (unsure or air) and "headsp" or "head" end
    if unsure then return "sp" end
    return "-"
end

local function Median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    local m = math.floor((#c + 1) / 2)
    return (#c % 2 == 1) and c[m] or (c[m] + c[m + 1]) / 2
end

-- aim_fire: the ragebot's predicted damage for the hitgroup it aimed at,
-- against what we traced for that part.
-- A prediction at or above the target's health says nothing about the
-- multiplier if the ragebot caps it at health (the docs don't say), and
-- would pull the factor down (AWP head: 100 predicted / 448 traced = x0.22,
-- so a 240 wallbang head would stop counting as a kill). Only predictions
-- below health are used.
local function OnFire(rec, hitgroup, pred, hp)
    if not (rec and isnum(pred) and pred > 0) then return end
    if not (isnum(hp) and hp > 0 and pred < hp) then return end
    local group = (hitgroup == 1) and "head" or ((hitgroup == 2 or hitgroup == 3) and "body" or nil)
    if not group then return end
    local traced = (group == "head") and rec.aim_th or rec.aim_tb
    if not (isnum(traced) and traced > 0) then return end
    local t = CAL[group]
    t[#t + 1] = pred / traced
    if #t > 15 then table.remove(t, 1) end
    if #t >= 5 then
        local m = Clamp(Median(t), 0.2, 5)
        local key = (group == "head") and "fh" or "fb"
        if math.abs(m - CAL[key]) > 0.1 then
            CAL[key] = m
            info("aim", "calibration %s: ragebot damage = traced x%.2f (%d shots)", group, m, #t)
        end
    end
end

local function Tick(tc, threat, ti)
    local wpn = DET.aim and LocalWeaponClass() or nil
    local armed = wpn and wpn ~= "?" and wpn ~= "other"
    local me, ne = entity.get_local_player(), 0
    if armed and me then
        local ex, ey, ez = client.eye_position()
        if isnum(ex) and isnum(ey) and isnum(ez) then
            EYES[1][1], EYES[1][2], EYES[1][3] = ex, ey, ez
            ne = 1
            local vx, vy = entity.get_prop(me, "m_vecVelocity")
            if isnum(vx) and isnum(vy) and vx * vx + vy * vy > 900 then   -- moving > 30 u/s
                local k = PEEK_TICKS * ti
                EYES[2][1], EYES[2][2], EYES[2][3] = ex + vx * k, ey + vy * k, ez
                ne = 2
            end
        end
    end
    local dt2 = armed and DT_WEAPON[wpn] and DtReady() or false
    local now = globals.realtime()
    for i = 1, #LIVE_ENEMIES do
        local ent = LIVE_ENEMIES[i]
        local s64 = EIDX_S64[ent]
        local rec = s64 and REC[s64]
        local pol = "-"
        if rec and ne > 0 then
            -- the threat every 2 ticks, anyone else every 6
            local every = (ent == threat) and 2 or 6
            if not rec.aim_t_tc or tc - rec.aim_t_tc >= every or tc < rec.aim_t_tc then
                rec.aim_t_tc = tc
                rec.aim_th = Traced(me, ne, ent, HB_HEAD)
                local b = 0
                for j = 1, #HB_BODY do
                    local d = Traced(me, ne, ent, HB_BODY[j])
                    if d > b then b = d end
                end
                rec.aim_tb = b
            end
            local hp = tonumber(entity.get_prop(ent, "m_iHealth"))
            -- vuln windows don't exempt the x-way case: vuln shots there
            -- went 10 of 25 (40%)
            local unsure = InDoubt(rec, now)
            local air = rec.state == STATE.AIR or rec.state == STATE.AIR_CROUCH
            pol = Decide(hp, (rec.aim_th or 0) * CAL.fh, (rec.aim_tb or 0) * CAL.fb, dt2, unsure, air)
        end
        if rec then rec.aim_pol = pol end
        Write(ent, F_BODY, (pol == "body") and "On" or ((pol == "head" or pol == "headsp") and "Off" or "-"))
        Write(ent, F_SP, (pol == "sp" or pol == "headsp") and "On" or "-")
    end
end

-- Round/match reset: both fields back to the ragebot default.
local function Reset(ent)
    pcall(plist.set, ent, F_BODY, "-")
    pcall(plist.set, ent, F_SP, "-")
end

return {Tick = Tick, Decide = Decide, OnFire = OnFire, Reset = Reset, Write = Write, CAL = CAL, VAL_OK = VAL_OK,
        XwayAfterMiss = XwayAfterMiss, InDoubt = InDoubt, DtReady = DtReady}
end)() -- aim policy scope


-- ══════════════════════════════════════════════════════════════════
--  SHOT LOG  (Indicators > Shot log)
--
--  One line per ragebot shot, in the format of the public "[MISC] aimbot
--  log" (s0daa/CSGO-HVH-LUAS), with what RIFTVEIL did:
--
--   [217] [244/251] Missed moral's head(98)(76%) due to resolver:0.03° · RIFTVEIL vuln_lby -24° [aa=5way | cf=62% | cht=nl | streak=1 | lc=0 | tc=1]
--   [218] [260/266] Hit moral's head for 98(98) (0 remaining) aimed=head(81%) · RIFTVEIL hit_mem +31° [aa=hold | cf=70% | pol=head | lc=1 | tc=2]
--   [219] [301/307] Missed moral's chest(34)(70%) due to spread:1.84° · GAMESENSE resolver [aa=2way | cf=40% | lc=0 | tc=0]
--
--  [217] the ragebot's shot id. [244/251] the tick of the record it fired
--  at / the tick the result arrived, both mod 1000: the gap is backtrack
--  plus ping. head(98)(76%) aimed hitgroup, predicted damage, hit chance.
--  :0.03° the angle between where it aimed and where the bullet went --
--  near 0 on a resolver miss (the bullet went where it was sent), wide on
--  spread. Then who resolved the target for that shot, read from the
--  player list as the shot left: RIFTVEIL with its method and the body yaw
--  it forced, or GAMESENSE's own resolver. In brackets: AA type, confidence, enemy cheat, aim policy, safe
--  point (on / off from the player list, key = Force safe point held),
--  aim_fire flags (T teleported, I interpolated, E extrapolated, B accuracy
--  boost, H high priority; D our defensive read on them), on a resolver
--  miss the run of them and next=sp when the aim policy goes to safe point
--  for the next shot, and our / their choked commands (lc / tc).
--
--  Printed with print(), as the original does: gamesense puts it in the
--  console and the top-left corner, where its own logs go (v8.16 used
--  client.color_log instead).
--
--  The original matched the impact by tick, which misses whenever the
--  impact and the result land on different ticks; here each shot claims
--  its own impacts (ClaimAngle). The debug file's [hit] / [miss] lines,
--  which log_report reads, are unchanged.
-- ══════════════════════════════════════════════════════════════════
local SHOTLOG = (function()
local FLAG_OUT = {t = "T", i = "I", x = "E", b = "B", p = "H", d = "D"}
local VERB = {hegrenade = "Naded", inferno = "Burned", knife = "Knifed"}
local FORCE_SP
do
    local ok, ref = pcall(ui.reference, "RAGE", "Aimbot", "Force safe point")
    if ok then FORCE_SP = ref end
end

local IMP = {}   -- our bullet impacts, oldest first: {t, x, y, z, claimed}

local function Int(x) return isnum(x) and math.floor(x + 0.5) or 0 end
local function Name(ent) return entity.get_player_name(ent) or "?" end
local function HGName(hg) return HG[(tonumber(hg) or -1) + 1] or "?" end
local function PGet(ent, field)
    local ok, v = pcall(plist.get, ent, field)
    if ok then return v end
end

-- segs: the line's pieces, joined and printed once
local function Add(segs, ...)
    local n = #segs
    for i = 1, select("#", ...) do segs[n + i] = (select(i, ...)) end
end
local function Print(segs) print(table.concat(segs)) end

local function Dir(ox, oy, oz, x, y, z)
    if not (isnum(ox) and isnum(oy) and isnum(oz) and isnum(x) and isnum(y) and isnum(z)) then return nil end
    local dx, dy, dz = x - ox, y - oy, z - oz
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    if l < 1e-3 then return nil end
    return dx / l, dy / l, dz / l
end
local function Angle(ax, ay, az, bx, by, bz)
    return math.deg(math.acos(Clamp(ax * bx + ay * by + az * bz, -1, 1)))
end

-- This shot's deviation: the first impact we received after it left that
-- no earlier shot has claimed, plus every other unclaimed impact on that
-- same ray (the same bullet through a wall), so a double tap's second
-- bullet can't take the first one's. Results arrive in shot order.
local function ClaimAngle(lg)
    local ax, ay, az = Dir(lg.ex, lg.ey, lg.ez, lg.ax, lg.ay, lg.az)
    if not ax then return nil end
    local fx, fy, fz
    for i = 1, #IMP do
        local m = IMP[i]
        if not m.claimed and m.t >= lg.t then
            local bx, by, bz = Dir(lg.ex, lg.ey, lg.ez, m.x, m.y, m.z)
            if bx then
                if not fx then
                    fx, fy, fz = bx, by, bz; m.claimed = true
                elseif Angle(fx, fy, fz, bx, by, bz) < 1 then
                    m.claimed = true
                end
            end
        end
    end
    return fx and Angle(ax, ay, az, fx, fy, fz) or nil
end

-- aim_fire, after SHOTS[e.id] is built: what the line needs that the
-- debug log doesn't keep
local function Fire(e, d, r)
    if not IND.log then return end
    local ex, ey, ez = client.eye_position()
    local sp = PGet(e.target, "Override safe point")
    sp = (sp == "On" and "on") or (sp == "Off" and "off") or nil
    if not sp and FORCE_SP then
        local ok, on = pcall(ui.get, FORCE_SP)
        if ok and on == true then sp = "key" end
    end
    d.lg = {
        t = globals.realtime(), rt = tonumber(e.tick) or globals.tickcount(),
        ex = ex, ey = ey, ez = ez, ax = e.x, ay = e.y, az = e.z,
        lc = tonumber(globals.chokedcommands()) or 0, tc = r and r.cur_choke or -1,
        sp = sp,
        -- who resolved this player for this shot: the player list itself,
        -- not rec.last_meth (stale while the master switch is off)
        forced = PGet(e.target, "Force body yaw") == true,
        fval = PGet(e.target, "Force body yaw value"),
    }
end

-- bullet_impact: ours only, unclaimed ones kept 2 s
local function Impact(e)
    if not IND.log then return end
    local me = entity.get_local_player()
    if not me or client.userid_to_entindex(e.userid) ~= me then return end
    if not (isnum(e.x) and isnum(e.y) and isnum(e.z)) then return end
    local now, n = globals.realtime(), 0
    for i = 1, #IMP do
        local m = IMP[i]
        if not m.claimed and now - m.t < 2 then n = n + 1; IMP[n] = m end
    end
    for i = #IMP, n + 1, -1 do IMP[i] = nil end
    if n < 64 then IMP[n + 1] = {t = now, x = e.x, y = e.y, z = e.z} end
end

local function Head(segs, id, lg)
    Add(segs, string.format("[%s] [%d/%d] ", tostring(id), lg.rt % 1000, globals.tickcount() % 1000))
end

local function Tail(segs, d, rec, blame)
    local lg = d.lg
    local who, what
    if lg.forced then
        who = "RIFTVEIL"
        what = string.format(" %s %+d°", d.meth or "?", Int(isnum(lg.fval) and lg.fval or d.val))
    elseif d.cor == "0" then
        who, what = "NO RESOLVER", " (correction off)"
    else
        who, what = "GAMESENSE", " resolver"
    end
    Add(segs, " · ", who, what)
    local p = {"aa=" .. (AA_SHORT[d.aa] or "?"), string.format("cf=%d%%", Int((d.conf or 0) * 100))}
    if d.cheat then p[#p + 1] = "cht=" .. d.cheat end
    if d.pol and d.pol ~= "-" then p[#p + 1] = "pol=" .. d.pol end
    if lg.sp then p[#p + 1] = "sp=" .. lg.sp end
    local fl = (d.fl or ""):gsub("%a", FLAG_OUT)
    if fl ~= "" then p[#p + 1] = "fl=" .. fl end
    if blame and rec then
        p[#p + 1] = "streak=" .. (rec.aim_miss_streak or 0)
        if DET.aim and not FEATURE.NO_SAFEPOINT and AIMX.InDoubt(rec, globals.realtime()) then p[#p + 1] = "next=sp" end
    end
    p[#p + 1] = "lc=" .. lg.lc
    p[#p + 1] = "tc=" .. lg.tc
    Add(segs, " [", table.concat(p, " | "), "]")
end

-- aim_hit, after on_aim_hit's own bookkeeping
local function Hit(e, d)
    if not (IND.log and d.lg) then return end
    ClaimAngle(d.lg)   -- its impacts are this shot's: keep them from the next one
    local segs = {}
    Head(segs, e.id, d.lg)
    Add(segs, "Hit ", Name(e.target), "'s ", HGName(e.hitgroup),
        string.format(" for %d(%d) (%d remaining) aimed=", Int(e.damage), d.aim_dmg or 0,
            math.max(0, Int(entity.get_prop(e.target, "m_iHealth")))),
        HGName(d.aim_hg), string.format("(%d%%)", Int(d.hc)))
    Tail(segs, d, d.s64 and REC[d.s64], false)
    Print(segs)
end

-- aim_miss, at each of on_aim_miss's exits. d.lg_out: "late" (result
-- after 0.5 s, not counted) or "server" (the server's hit counter moved:
-- it landed); d.lg_res: on_aim_miss counted it as a resolver miss.
local function Miss(e, d)
    if not (IND.log and d.lg) then return end
    local ang = ClaimAngle(d.lg)
    local segs = {}
    Head(segs, e.id, d.lg)
    if d.lg_out == "server" then
        Add(segs, "Hit ", Name(e.target), " on the server (the client reported a miss)")
        Tail(segs, d, d.s64 and REC[d.s64], false)
        return Print(segs)
    end
    local reason = e.reason or "?"
    local blame = d.lg_res == true
    Add(segs, "Missed ", Name(e.target), "'s ", HGName(e.hitgroup or d.aim_hg),
        string.format("(%d)(%d%%) due to ", d.aim_dmg or 0, Int(d.hc)),
        (reason == "?" or reason == "") and "resolver" or reason)
    if ang then Add(segs, string.format(":%.2f°", ang)) end
    if d.lg_out == "late" then Add(segs, " (late, not counted)") end
    Tail(segs, d, d.s64 and REC[d.s64], blame)
    Print(segs)
end

-- player_hurt: grenade, fire and knife damage, which the ragebot's events
-- don't cover (the original's "Naded x for 34 damage (66 remaining)")
local function Hurt(e)
    if not IND.log then return end
    local verb = VERB[e.weapon]
    if not verb or (tonumber(e.hitgroup) or 0) ~= 0 then return end
    local me = entity.get_local_player()
    if not me or client.userid_to_entindex(e.attacker) ~= me then return end
    local victim = client.userid_to_entindex(e.userid)
    if not victim or victim == me then return end
    local segs = {}
    Add(segs, verb, " ", Name(victim), string.format(" for %d damage (%d remaining)", Int(e.dmg_health), Int(e.health)))
    Print(segs)
end

return {Fire = Fire, Impact = Impact, Hit = Hit, Miss = Miss, Hurt = Hurt, ClaimAngle = ClaimAngle, IMP = IMP}
end)() -- shot log scope


-- ══════════════════════════════════════════════════════════════════
--  LOCAL LAGCOMP BOX  (Indicators > Local lagcomp)
--
--  When double tap breaks lag compensation, flashes our hull for half a
--  second where the shift puts us, red, labelled with the shifted ticks --
--  the way lagcomp-box-gs boxes an enemy at its extrapolated origin.
--
--  Our m_nTickBase is read in run_command and its highest value kept;
--  max - tickbase - 1 (0..14) is the ticks being shifted, the check
--  enthusiasm, universe and excellentsanty use for their own defensive / LC
--  indicator; a jump of more than one tick between commands is the
--  forward shift (the teleport). Over 2 either way, the box is drawn ahead
--  of us for 0.5 s: each frame, our current origin extrapolated by the
--  shifted ticks, so it leads where the shift takes us.
--  Only double tap shifts the tickbase, so no menu read is needed (v8.21-
--  8.22 also required the DT menu reference, which current builds keep
--  under RAGE > Aimbot, not Other -- it never fired). Extrapolation is
--  ExtrapolateOrigin: velocity, gravity, stops at walls. Fakelag alone
--  draws nothing (v8.18-8.20 also flashed on fakelag breaks, which made up
--  most of what it showed).
-- ══════════════════════════════════════════════════════════════════
local LOCALLC = (function()
local C_LAG = {240, 64, 64}
local FLASH = 0.5
local EDGES = {{1, 2}, {2, 3}, {3, 4}, {4, 1}, {5, 6}, {6, 7}, {7, 8}, {8, 5}, {1, 5}, {2, 6}, {3, 7}, {4, 8}}
-- tb_max / shift: the LC check; bx,by,bz,t,ticks: the box being flashed
local S = {shift = 0, t = -1, ticks = 0, shot = -1}
-- a double-tap shift lands within one batch of commands after the shot:
-- at most sv_maxusrcmdprocessticks (16) ticks, 0.25 s at 64 tick
local SHOT_WIN = 0.25

-- weapon_fire: our own shot, fired with double tap on
local function OnShot(e)
    if not IND.lc then return end
    local me = entity.get_local_player()
    if not me or client.userid_to_entindex(e.userid) ~= me then return end
    if AIMX.DtReady() then S.shot = globals.realtime() end
end

local function OnRun()
    if not IND.lc then return end
    local me = entity.get_local_player()
    if not (me and entity.is_alive(me)) then S.tb_max, S.tb_prev, S.shift = nil, nil, 0; return end
    local tb = tonumber(entity.get_prop(me, "m_nTickBase"))
    if not isnum(tb) then return end   -- a NaN max would never recover
    -- a new life / reconnect starts the tickbase over
    if not S.tb_max or tb > S.tb_max or S.tb_max - tb > 64 then S.tb_max = tb end
    -- back: tickbase below its highest (defensive / recharge);
    -- forward: more than one tick since the last command (the teleport)
    local back = math.min(14, math.max(0, S.tb_max - tb - 1))
    local fwd = (S.tb_prev and tb - S.tb_prev - 1 <= 64) and math.min(14, math.max(0, tb - S.tb_prev - 1)) or 0
    S.tb_prev = tb
    local shift = math.max(back, fwd)
    -- only the double-tap exploit itself: our shot with DT on, then the
    -- tickbase teleport (shift > 2) within SHOT_WIN. No speed condition
    -- (v8.30 had a 64 u one; the shot + teleport is the break).
    if shift > 2 and S.shift <= 2 then
        local now = globals.realtime()
        if S.shot >= 0 and now - S.shot >= 0 and now - S.shot <= SHOT_WIN and AIMX.DtReady() then
            S.t, S.ticks = now, shift
        end
    end
    S.shift = shift
end

local function Draw()
    if not (IND.lc and S.t >= 0) then return end
    local age = globals.realtime() - S.t
    if age < 0 or age > FLASH then return end
    local me = entity.get_local_player()
    if not (me and entity.is_alive(me)) then return end
    local mnx, mny, mnz = entity.get_prop(me, "m_vecMins")
    local mxx, mxy, mxz = entity.get_prop(me, "m_vecMaxs")
    if not (isnum(mnx) and isnum(mxx) and isnum(mnz) and isnum(mxz)) then return end
    -- ahead of us, every frame: where we stand now carried forward by the
    -- shifted ticks (v8.20-8.23 fixed it at the moment of the shift, so we
    -- walked past it and it trailed behind)
    local cx, cy, cz = entity.get_origin(me)
    if not (isnum(cx) and isnum(cy) and isnum(cz)) then return end
    S.bx, S.by, S.bz = ExtrapolateOrigin(me, cx, cy, cz, S.ticks)
    local al = 1 - age / FLASH
    local c, x, y, z = C_LAG, S.bx, S.by, S.bz
    local P = {
        {x + mnx, y + mny, z + mnz}, {x + mxx, y + mny, z + mnz},
        {x + mxx, y + mxy, z + mnz}, {x + mnx, y + mxy, z + mnz},
        {x + mnx, y + mny, z + mxz}, {x + mxx, y + mny, z + mxz},
        {x + mxx, y + mxy, z + mxz}, {x + mnx, y + mxy, z + mxz},
    }
    local scr = {}
    for i = 1, 8 do
        local sx, sy = renderer.world_to_screen(P[i][1], P[i][2], P[i][3])
        if sx then scr[i] = {sx, sy} end
    end
    for i = 1, #EDGES do
        local p1, p2 = scr[EDGES[i][1]], scr[EDGES[i][2]]
        if p1 and p2 then renderer.line(p1[1], p1[2], p2[1], p2[2], c[1], c[2], c[3], math.floor(230 * al)) end
    end
    -- tether from where we stand to the box
    local mz = (mnz + mxz) / 2
    local bx, by = renderer.world_to_screen(x, y, z + mz)
    local ox, oy = renderer.world_to_screen(cx, cy, cz + mz)
    if bx and ox then renderer.line(bx, by, ox, oy, c[1], c[2], c[3], math.floor(140 * al)) end
    local tx, ty = renderer.world_to_screen(x, y, z + mxz + 6)
    if tx then renderer.text(tx, ty, c[1], c[2], c[3], math.floor(255 * al), "-c", 0, string.format("LC  %dt", S.ticks)) end
end

return {OnRun = OnRun, OnShot = OnShot, Draw = Draw, S = S}
end)() -- local lagcomp scope


-- Read by the info panel and ESP flags (paint runs every frame; these only
-- change once per net update or on a shot event).
local ESP_VLN, ESP_RES, ESP_AIM = {}, {}, {}   -- ESP_AIM: aim policy tag
local CTX = {threat = nil}
local STATE_VER = 0

local AIM_ESP = {body = "BODY", head = "HEAD", headsp = "HEAD SP", sp = "SAFE PT"}
local function UpdateEspState()
    for k in pairs(ESP_VLN) do ESP_VLN[k] = nil end
    for k in pairs(ESP_RES) do ESP_RES[k] = nil end
    for k in pairs(ESP_AIM) do ESP_AIM[k] = nil end
    if not IND.esp then return end
    for i = 1, #LIVE_ENEMIES do
        local ent = LIVE_ENEMIES[i]
        local s64 = EIDX_S64[ent]
        local rec = s64 and REC[s64]
        if rec then
            -- VLN: vulnerability window open (deterministic correction)
            ESP_VLN[ent] = WindowForced(rec)
            -- RES: confident correction overriding the built-in (not suppress, not vuln)
            ESP_RES[ent] = rec.resolved and rec.conf >= CFG.CONF_ESP
                and rec.vuln_ttl == 0 and rec.last_meth ~= METH.SUPPRESS
            -- aim policy per enemy (the panel shows only the threat's);
            -- nothing while it's the ragebot default
            ESP_AIM[ent] = DET.aim and AIM_ESP[rec.aim_pol] or nil
        end
    end
end

local RELEASED = true   -- the player list holds nothing of ours
local function Update()
    if not ui.get(ui_on) then
        -- Switched off: hand every player back to the built-in resolver
        -- now, not at the next round start (forced yaw and aim overrides
        -- used to stay on until then).
        if not RELEASED then
            ResetPlist(true)
            RELEASED = true
            info("release", "resolver off -- every player back to the built-in")
        end
        if next(ESP_VLN) or next(ESP_RES) then
            for k in pairs(ESP_VLN) do ESP_VLN[k] = nil end
            for k in pairs(ESP_RES) do ESP_RES[k] = nil end
        end
        return
    end
    -- Once per tick, so a config load that skips the change callbacks
    -- still reaches the resolver within one update.
    SyncFlags()
    RELEASED = false

    local cur_lat, avg_lat = GetLat()
    local ctx = {
        cur_lat  = cur_lat,
        avg_lat  = avg_lat,
        is_spike = math.abs(cur_lat - avg_lat) > CFG.SPIKE_THR,
        threat   = client.current_threat(),
        ti       = globals.tickinterval(),
        cur_tc   = globals.tickcount(),
    }
    LAST_SPIKE = ctx.is_spike

    -- entity.get_players(true): enemies only, dormant and dead already
    -- excluded (docs), so no per-player is_enemy/is_alive calls. Collected
    -- first so the player list can be refreshed before any plist write.
    local n_live, fresh = 0, false
    for _, player in ipairs(entity.get_players(true)) do
        n_live = n_live + 1
        LIVE_ENEMIES[n_live] = player
        if not PL_KNOWN[player] then PL_KNOWN[player] = true; fresh = true end
    end
    for i = #LIVE_ENEMIES, n_live + 1, -1 do LIVE_ENEMIES[i] = nil end
    -- update_player_list is only needed so plist.set reaches a player who
    -- just appeared: run it then, plus a once-a-second resync that also
    -- drops the write cache. (v6.2 ran it every tick.)
    if fresh or ctx.cur_tc - LAST_PL_SYNC >= PL_RESYNC_TICKS or ctx.cur_tc < LAST_PL_SYNC then
        if not fresh then PL_CACHE = {} end
        client.update_player_list()
        LAST_PL_SYNC = ctx.cur_tc
    end
    for i = 1, n_live do
        local player = LIVE_ENEMIES[i]
        local ok, msg = pcall(ProcessPlayer, player, ctx)
        if not ok then
            err("update", "player=%d crash=%s", player, tostring(msg))
        end
    end
    CTX.threat = ctx.threat
    AIMX.Tick(ctx.cur_tc, ctx.threat, ctx.ti)
    UpdateEspState()
    STATE_VER = STATE_VER + 1

    -- Periodic autosave: don't rely solely on match-end/disconnect/shutdown
    -- firing cleanly. Every 60s, if there's anyone worth saving, flush to
    -- the permanent DB so a crash or hard stop doesn't lose the session.
    local now = globals.realtime()
    if next(REC) and (now - LAST_DB_SAVE) >= 60 then
        LAST_DB_SAVE = now
        FlushDB()
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
-- aim_fire's backtrack, in ticks. The docs call it ticks but their example
-- converts it as seconds; the two ranges can't overlap (seconds < 1 under
-- sv_maxunlag, a nonzero tick count >= 1), so both read correctly. v6.2 ran
-- tick counts through TT() and logged bt=64+; only the log, the panel's BT
-- tag and the saved bt_pref use it -- no correction does.
local function BtTicks(v)
    if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then return 0 end
    if v < 1 then return TT(v) end
    return math.min(64, math.floor(v + 0.5))
end

-- A game value for a "%d" log field: an integer, or -1 when it isn't a
-- finite number (NaN / inf reached the shot log through hp and traces).
local function LbyDelta(ent)
    local lby = entity.get_prop(ent, "m_flLowerBodyYawTarget")
    local _, eye = entity.get_prop(ent, "m_angEyeAngles")
    if not (isnum(lby) and isnum(eye)) then return 999 end
    return math.floor(NA(eye - lby) + 0.5)
end

-- The enemy's eye yaw against facing straight away from us (yaw base "at
-- targets" + 180): an AA that picks its left / right yaw offset by desync
-- side shows that side here, in data the server sends (shot log eo=).
local function EyeOffset(ent, me)
    if not me then return "-" end
    local _, eye = entity.get_prop(ent, "m_angEyeAngles")
    local ex, ey = entity.get_origin(ent)
    local mx, my = entity.get_origin(me)
    if not (isnum(eye) and isnum(ex) and isnum(ey) and isnum(mx) and isnum(my)) then return "-" end
    if (mx - ex) ^ 2 + (my - ey) ^ 2 < 1 then return "-" end
    local to_me = math.deg(math.atan2(my - ey, mx - ex))
    return string.format("%d", math.floor(NA(eye - (to_me + 180)) + 0.5))
end

local function CorrectionActive(ent)
    local ok, v = pcall(plist.get, ent, "Correction active")
    if not ok or v == nil then return "?" end
    return v and "1" or "0"
end

-- Defensive frames (see ProcessPlayer) received from this player in the
-- last 64 ticks (one second)
local function DefFrames(rec, now)
    local n, r = 0, rec.dfr
    if r then for i = 1, #r do if now - r[i] <= 64 and now >= r[i] then n = n + 1 end end end
    return n
end

local function LogInt(v)
    v = tonumber(v)
    if not isnum(v) then return -1 end
    return math.floor(v)
end

local function on_aim_fire(e)
    local t = e.target; if not t then return end
    local s64 = GetS64(t); local r = s64 and REC[s64]
    local praw = entity.get_prop(t, "m_flPoseParameter", 11)
    local me   = entity.get_local_player()
    local pitch = entity.get_prop(t, "m_angEyeAngles")
    SHOTS[e.id] = {
        s64     = s64,
        fy      = praw and (praw * CFG.POSE_SCALE - 60) or 0,
        meth    = r and r.last_meth or (FEATURE.STALE_WINDOW and "builtin" or METH.RING),
        val     = r and r.last_val  or 0,
        side    = r and r.side      or 0,
        flip    = r and r.flip      or false,   -- store flip state at fire time
        conf    = r and r.conf      or 0,
        aa      = r and r.aa_type   or AA.UNKNOWN,
        state   = r and r.state     or nil,  -- movement state at fire time, for per-condition hit_mem
        sspd    = r and LogInt(r.state_spd) or -1,
        cheat   = r and r.cheat     or nil,  -- enemy cheat (CHEAT REVEALER), logged
        -- per-weapon aim policy: inputs and the choice in effect
        wpn     = LocalWeaponClass(),
        pol     = r and r.aim_pol or "-",
        aim_th  = r and LogInt(r.aim_th or 0) or 0,   -- traced head / body damage
        aim_tb  = r and LogInt(r.aim_tb or 0) or 0,
        aim_hg  = tonumber(e.hitgroup) or -1,
        aim_dmg = LogInt(e.damage),
        thp     = LogInt(entity.get_prop(t, "m_iHealth")),
        tarm    = LogInt(entity.get_prop(t, "m_ArmorValue")),
        -- e.backtrack is a TIME value (seconds), not a tick count -- must
        -- go through TT() before comparing against the 1..16 tick range
        -- used everywhere else (bt_hist/preferred_bt/log output).
        bt      = BtTicks(e.backtrack),
        hc      = e.hit_chance or 0,
        -- in a vuln window only if the window is what we forced (STALE_WINDOW):
        -- a released or untrusted window is a builtin shot
        in_vuln = r and WindowForced(r) or false,
        vuln_t  = r and r.vuln_type or nil,
        cfg     = r and r.config_type or nil,
        six_side = r and r.six_side or 0,  -- for 6lex agree/disagree calibration on hit
        tick    = globals.tickcount(),
        -- fire_time/srv_hits: lets on_aim_miss tell a real resolver miss
        -- apart from a stale/timed-out event or a server-side hit that got
        -- reported as a client-side miss (see on_aim_miss).
        fire_time  = globals.realtime(),
        srv_hits = me and (entity.get_prop(me, "m_totalHitsOnServer") or 0) or 0,
        -- aim_fire's own flags (docs.gamesense.gs events/aim_fire):
        -- t teleported (breaking lag compensation), x extrapolated,
        -- i interpolated, b accuracy boost, p high-priority record; plus
        -- d = our defensive-tickbase read on the target at fire time
        fl      = (e.teleported and "t" or "") .. (e.extrapolated and "x" or "")
                  .. (e.interpolated and "i" or "") .. (e.boosted and "b" or "")
                  .. (e.high_priority and "p" or "") .. (r and r.def_tickbase and "d" or ""),
        -- the target's networked eye pitch: ~89 is ordinary AA pitch down;
        -- defensive AA (every AA script uploaded has it) sets up / zero /
        -- random during the defensive window
        pit     = isnum(pitch) and math.floor(pitch + 0.5) or -999,   -- -999: unread
        -- a shot at a teleporting or extrapolated record says nothing about
        -- the desync side: kept out of the cheat profiles and the aim
        -- policy's miss run (the v6.2 core still sees it, as it did)
        nolearn = (e.teleported or e.extrapolated) and true or false,
        df      = r and DefFrames(r, globals.tickcount()) or 0,
        -- gamesense's per-player "Correction active" (its own resolver for
        -- this player; tsv4 turns it off for bots, angelwings forces it on
        -- with every body-yaw write): a "builtin" shot with it off had no
        -- resolver at all
        cor     = CorrectionActive(t),
        -- anti-bruteforce check (measurement only): 207 of 569 gamesense AA
        -- scripts and 68 of 115 neverlose ones switch side / jitter / limit
        -- when our bullet passes within ~100 units of their eye -- hit or
        -- miss -- and most reset after 1-5 s. ls= seconds since our previous
        -- shot at this player (-1 = first), prv= its outcome (h head hit,
        -- b other hit, m resolver miss, o other miss, - none).
        ls      = (r and r.last_fire_t) and (globals.realtime() - r.last_fire_t) or -1,
        -- eye yaw minus the networked LBY target, -180..180 (999 unread).
        -- 262 uses in the public scripts take its sign as the desync side;
        -- logged to test that against our forced side (measurement only)
        lbyd    = LbyDelta(t),
        eo      = EyeOffset(t, me),
        -- gamesense's resolved body yaw at the shot, if read in the last 0.25 s
        gs      = (r and isnum(r.gs_pose) and isnum(r.gs_t) and globals.realtime() - r.gs_t < 0.25) and r.gs_pose or nil,
        -- seconds since the server last moved their LBY target (- = not seen)
        lbyu    = (r and isnum(r.lby_t)) and string.format("%.2f", globals.realtime() - r.lby_t) or "-",
        prv     = r and r.last_outcome or "-",
    }
    if r then r.last_fire_t = globals.realtime(); r.last_outcome = "-" end
    SHOTLOG.Fire(e, SHOTS[e.id], r)
    -- Credit a vuln_profile "seen" (trial) here, once per actual shot fired
    -- during an open vuln window -- not once per detection (see the
    -- comment at the DetectVuln call site in ProcessPlayer for why).
    -- (STALE_WINDOW: the same test as the shot's in_vuln, so trials and
    -- hits are counted on the same shots)
    local in_win = (FEATURE.STALE_WINDOW and SHOTS[e.id].in_vuln) or (not FEATURE.STALE_WINDOW and r and r.vuln_ttl > 0)
    if r and in_win and r.vuln_type and r.vuln_profile[r.vuln_type] then
        r.vuln_profile[r.vuln_type].seen = r.vuln_profile[r.vuln_type].seen + 1
    end
    -- Weapon aim calibration: the ragebot's predicted damage vs our trace
    AIMX.OnFire(r, tonumber(e.hitgroup), tonumber(e.damage), SHOTS[e.id].thp)
    -- Shot counter for CheatTrusts' probe (every 4th shot at a player)
    if r then r.shots_fired = (r.shots_fired or 0) + 1 end
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
        -- FEATURE.META_STREAK: the streak counts gamesense's misses in a
        -- row, so its own hit ends it too. v6.2 reset it only on our hits,
        -- so builtin miss, hit, miss read as "failing twice" and handed the
        -- enemy to the aggressive mode.
        if d.meth ~= "builtin" or FEATURE.META_STREAK then
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
        -- A head hit on a head-aimed shot confirms the method, for this
        -- cheat. Only head-aimed shots are credited, hit or miss: a
        -- body-aimed shot can't earn a head hit, so counting its misses
        -- (as up to 8.5.3 did) only ever pushed methods toward "skip".
        -- In the v7.7+ logs body-aimed shots were 5 of 15 credited misses
        -- and 1 of 7 credited hits, while landing 11 of 16.
        if is_head and d.aim_hg == 1 and not d.nolearn then CheatCredit(d.cheat, d.meth, true) end
        -- Any hit ends a run of resolver misses ("two in a row")
        rec.aim_miss_streak = 0
        rec.last_outcome = is_head and "h" or "b"
        -- FEATURE.LEARN_GS: when gamesense's own resolver landed the head,
        -- the side is the one it was animating at the shot (its answer, read
        -- off a record we didn't force) -- not our majority over 16 records
        local learned
        if FEATURE.LEARN_GS and d.meth == "builtin" and isnum(d.gs) and math.abs(d.gs) >= 5 then
            learned = Sign(d.gs)
        elseif d.side ~= 0 then
            learned = d.flip and -d.side or d.side
        end
        if learned and is_head then
            rec.hit_side  = learned
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
        if d.in_vuln and d.vuln_t then
            local vp = rec.vuln_profile
            if vp[d.vuln_t] then vp[d.vuln_t].hit = (vp[d.vuln_t].hit or 0) + 1 end
            rec.vuln_pref = d.vuln_t
            -- Successful unk hit means torso_yaw was reliable — reset unk streak
            if d.vuln_t == "unk" then rec.unk_miss_streak = 0 end
        end
    end

    info("hit", "player=%s group=%s dmg=%d meth=%s val=%.0f bt=%d st=%s mv=%d wpn=%s pol=%s tr=%d/%d hp=%d ar=%d aim=%s pdmg=%d cf=%.2f fl=%s pit=%d df=%d cor=%s ls=%.1f prv=%s lbyd=%d eo=%s lbyu=%s gs=%s aa=%s%s%s",
        entity.get_player_name(e.target) or "?",
        HG[(tonumber(e.hitgroup) or -1) + 1] or "?",
        isnum(e.damage) and math.floor(e.damage) or 0,
        d.meth, d.val, d.bt, d.state or "?", d.sspd or -1, d.wpn or "?", d.pol or "-", d.aim_th or 0, d.aim_tb or 0,
        d.thp or -1, d.tarm or -1,
        HG[(d.aim_hg or -1) + 1] or "?", d.aim_dmg or -1, d.conf or 0,
        (d.fl or "") ~= "" and d.fl or "-", d.pit or -999, d.df or 0, d.cor or "?", d.ls or -1, d.prv or "-", d.lbyd or 999,
        d.eo or "-", d.lbyu or "-", isnum(d.gs) and string.format("%.0f", d.gs) or "-",
        AA_SHORT[d.aa] or "?",
        d.cheat and (" cht=" .. d.cheat) or "",
        d.in_vuln and (" !" .. d.vuln_t) or "")
    SHOTLOG.Hit(e, d)
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
        d.lg_out = is_timeout and "late" or "server"
        SHOTLOG.Miss(e, d)
        SHOTS[e.id] = nil
        return
    end

    do
        local rec = d.s64 and REC[d.s64]
        if rec then rec.total_misses = rec.total_misses + 1 end
    end

    local is_resolver = reason == "?" or reason == "" or reason == "prediction error"
    d.lg_res = is_resolver
    do
        local ro = d.s64 and REC[d.s64]
        if ro then ro.last_outcome = is_resolver and "m" or "o" end
    end

    warn("miss", "player=%s reason=%s meth=%s val=%.0f bt=%d hc=%.0f%% st=%s mv=%d wpn=%s pol=%s tr=%d/%d hp=%d ar=%d aim=%s pdmg=%d cf=%.2f fl=%s pit=%d df=%d cor=%s ls=%.1f prv=%s lbyd=%d eo=%s lbyu=%s gs=%s aa=%s%s%s",
        entity.get_player_name(e.target) or "?",
        reason, d.meth, d.val, d.bt, d.hc, d.state or "?", d.sspd or -1, d.wpn or "?", d.pol or "-", d.aim_th or 0, d.aim_tb or 0,
        d.thp or -1, d.tarm or -1,
        HG[(d.aim_hg or -1) + 1] or "?", d.aim_dmg or -1, d.conf or 0,
        (d.fl or "") ~= "" and d.fl or "-", d.pit or -999, d.df or 0, d.cor or "?", d.ls or -1, d.prv or "-", d.lbyd or 999,
        d.eo or "-", d.lbyu or "-", isnum(d.gs) and string.format("%.0f", d.gs) or "-",
        AA_SHORT[d.aa] or "?",
        d.cheat and (" cht=" .. d.cheat) or "",
        d.in_vuln and (" !" .. d.vuln_t) or "")

    if is_resolver then
        if d.aim_hg == 1 and not d.nolearn then CheatCredit(d.cheat, d.meth, false) end
        if not d.nolearn then
            local rr = d.s64 and REC[d.s64]
            if rr then rr.aim_miss_streak = (rr.aim_miss_streak or 0) + 1 end
        end
        local rec = d.s64 and REC[d.s64]
        if rec then
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
                SHOTLOG.Miss(e, d)
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
                -- seen was already credited once for this shot in
                -- on_aim_fire -- crediting it again here would double-count
                -- every miss (but not hits, which only increment hit in
                -- on_aim_hit), artificially crushing the ratio below what
                -- it actually is.
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

            if should_flip then
                rec.flip = not rec.flip
            end

            -- Only count non-vuln misses toward soft reset.
            -- Most vuln misses are prediction errors, not resolver failures.
            -- Counting them wipes hit_mem data prematurely.
            -- Track per-player unk miss streak to scale back unreliable unchokes
            if d.vuln_t == "unk" then
                rec.unk_miss_streak = (rec.unk_miss_streak or 0) + 1
            end

            if not d.in_vuln then
                rec.resolver_misses = rec.resolver_misses + 1
                if reason == "prediction error" and rec.preferred_bt > 0 then
                    rec.bt_hist[rec.preferred_bt] =
                        math.max(0, (rec.bt_hist[rec.preferred_bt] or 0) - 1)
                    local best_bt, best_c = 0, 0
                    for depth, count in pairs(rec.bt_hist) do
                        if count > best_c then best_c = count; best_bt = depth end
                    end
                    rec.preferred_bt = best_bt
                end
                if rec.resolver_misses >= 3 then
                    warn("reset", "soft reset player=%s",
                         entity.get_player_name(e.target) or "?")
                    rec.conf = 0.22; rec.resolver_misses = 0
                    rec.flip = false; rec.hit_side = 0; rec.hit_count = 0
                    rec.hit_side_by_state = {}; rec.hit_count_by_state = {}
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
    SHOTLOG.Miss(e, d)
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
-- Weapon aim policy in force on this enemy: BODY / HEAD / HEAD SP / SAFE PT
client.register_esp_flag("", 235, 190, 90, function(ent)
    local t = ESP_AIM[ent]
    if not t then return false end
    return true, t
end)
-- Enemy cheat (CHEAT REVEALER): GS / NL / NW ... once detected
client.register_esp_flag("", 220, 220, 220, function(ent)
    local c = IND.esp and ui.get(ui_on) and CHEAT_OF[ent]
    if not c or not entity.is_enemy(ent) then return false end
    return true, string.upper(c)
end)

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
local C_LAG   = {240, 64, 64}    -- lag-comp boxes (enemy SHIFT, local LC)

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
}
-- Weapon aim policy in effect on the threat (WEAPON AIM POLICY)
local AIM_TAG = {body = "BODY", head = "HEAD", headsp = "HEAD SP", sp = "SAFE PT"}

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
        if WindowForced(rec) then
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
        -- weapon aim policy in effect on this enemy
        local pt = AIM_TAG[rec.aim_pol or "-"]
        if pt then tags[#tags+1] = pt end
        -- warnings before details: a row that runs out of room drops the tail
        if rec.def_tickbase    then tags[#tags+1] = "DEF" end
        if LAST_SPIKE          then tags[#tags+1] = "SPIKE" end
        if rec.meta_aggressive then tags[#tags+1] = "AGG" end
        if rec.preferred_bt > 0 then tags[#tags+1] = "BT " .. rec.preferred_bt end
        if rec.config_type and rec.config_conf >= CFG.CFG_THRESH then
            tags[#tags+1] = string.upper((rec.config_type:gsub("_", " ")))
        end
        if #tags > 0 then
            n = n + 1
            -- Tags are in priority order; the ones that don't fit the row are
            -- dropped whole (eight tags ran past the 200 px panel).
            local sep, out = "  \xc2\xb7  ", tags[1]
            for i = 2, #tags do
                local nxt = out .. sep .. tags[i]
                if renderer.measure_text("-", nxt) > value_w then break end
                out = nxt
            end
            PanelRow(OV, n, "INFO", out, "-", C_DIM, nil, nil)
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
-- SHIFT box: while an enemy's last record broke lag comp, every frame,
-- their hull at their current origin carried forward by that record's gap
-- -- where the next record will land, as lagcomp-box-gs draws it. Up to
-- v8.24 it was computed once per break and left in the world for 0.5 s,
-- so it trailed behind a moving enemy and outlived the break.
local function DrawShiftMarkers(show)
    if not show then return end
    local now = globals.realtime()
    for _, p in ipairs(LIVE_ENEMIES) do
        local s2 = EIDX_S64[p]
        local r2 = s2 and REC[s2]
        if r2 and r2._lc_on and now - (r2._lc_t or 0) < 1 then
            local ox2, oy2, oz2 = entity.get_origin(p)
            local mnx, mny, mnz = entity.get_prop(p, "m_vecMins")
            local mxx, mxy, mxz = entity.get_prop(p, "m_vecMaxs")
            if isnum(ox2) and isnum(oy2) and isnum(oz2) and isnum(mnx) and isnum(mxx) and isnum(mnz) and isnum(mxz) then
                local sx, sy = renderer.world_to_screen(ox2, oy2, oz2 + 78)
                if sx then renderer.text(sx, sy, C_LAG[1], C_LAG[2], C_LAG[3], 255, "-c", 0, "SHIFT") end
                local bx, by, bz = ExtrapolateOrigin(p, ox2, oy2, oz2, r2._lc_ticks or 1)
                local corners = {
                    {bx+mnx, by+mny, bz+mnz}, {bx+mxx, by+mny, bz+mnz},
                    {bx+mnx, by+mxy, bz+mnz}, {bx+mxx, by+mxy, bz+mnz},
                    {bx+mnx, by+mny, bz+mxz}, {bx+mxx, by+mny, bz+mxz},
                    {bx+mnx, by+mxy, bz+mxz}, {bx+mxx, by+mxy, bz+mxz},
                }
                local scr = {}
                for ci = 1, 8 do
                    local ssx, ssy = renderer.world_to_screen(corners[ci][1], corners[ci][2], corners[ci][3])
                    if ssx then scr[ci] = {ssx, ssy} end
                end
                for _, e in ipairs(BOX_EDGES) do
                    local p1, p2 = scr[e[1]], scr[e[2]]
                    if p1 and p2 then renderer.line(p1[1], p1[2], p2[1], p2[2], C_LAG[1], C_LAG[2], C_LAG[3], 220) end
                end
                -- tether from the label to the box centre
                local tsx, tsy = renderer.world_to_screen(bx + (mnx + mxx) / 2, by + (mny + mxy) / 2, bz + (mnz + mxz) / 2)
                if sx and tsx then renderer.line(sx, sy, tsx, tsy, C_LAG[1], C_LAG[2], C_LAG[3], 160) end
                r2._lc_box = {bx, by, bz}   -- last drawn, for the harness
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
    -- before the master switch: it's about us, not the resolver
    LOCALLC.Draw()
    if not ui.get(ui_on) then return end
    -- Threat as read once per tick in Update, not queried every frame.
    if IND.panel then DrawPanel(CTX.threat) end
    DrawShiftMarkers(IND.shift)
end
end)() -- panel scope

-- ══════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════
-- all_written: also every entity in the write cache (the switch-off release
-- hands back everything we ever touched; round resets cover the 64 slots)
ResetPlist = function(all_written)
    local ents = {}
    for i = 1, 64 do ents[i] = true end
    if all_written then
        for ent in pairs(PL_CACHE) do ents[ent] = true end
    end
    for i in pairs(ents) do
        pcall(function()
            plist.set(i, "Force body yaw", false)
            plist.set(i, "Force body yaw value", 0)
            plist.set(i, "Correction active", true)    -- back to gamesense's resolver
            plist.set(i, "High priority", false)
        end)
        AIMX.Reset(i)
    end
    PL_CACHE = {}; PL_KNOWN = {}
end

local function EndMatch()
    info("match", "ended -- flushing DB")
    FlushDB()
    ForgetAllCheats()
    ResetPlist()
    REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
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
client.set_event_callback("net_update_end", Instrument("update", function()
    if entity.is_alive(entity.get_local_player()) then Update() end
end))
client.set_event_callback("paint",       Instrument("paint", DrawOverlay))
client.set_event_callback("aim_fire",    Instrument("aim_fire", on_aim_fire))
client.set_event_callback("aim_miss",    Instrument("aim_miss", on_aim_miss))
client.set_event_callback("aim_hit",     Instrument("aim_hit", on_aim_hit))
-- Shot log (console): our bullet impacts for the spread angle, and
-- grenade / fire / knife damage
client.set_event_callback("bullet_impact", Instrument("bullet_impact", SHOTLOG.Impact))
client.set_event_callback("player_hurt",   Instrument("player_hurt", SHOTLOG.Hurt))
client.set_event_callback("run_command",   Instrument("run_command", LOCALLC.OnRun))
client.set_event_callback("weapon_fire",   Instrument("weapon_fire", LOCALLC.OnShot))
-- The log also reaches disk every round, so a match with the debug log
-- off still leaves its shots on disk.
client.set_event_callback("round_start", Instrument("round_start", function()
    ResetPlist()
    -- STALE_WINDOW: the list is clear, so is what each record says it
    -- forces (v6.2 kept last round's method and window until the next
    -- decision, and a shot before it was learned as that method)
    if FEATURE.STALE_WINDOW then
        for _, rec in pairs(REC) do
            rec.active, rec.resolved = false, false
            rec.last_meth, rec.last_val = "builtin", 0
            rec.vuln_ttl = 0
            rec._sup_streak, rec._sup_pause = 0, 0
        end
    end
    flush_log()
end))
client.set_event_callback("voice",       Instrument("voice", OnVoice))
client.set_event_callback("player_connect_full", Instrument("connect", function(e)
    local ent = client.userid_to_entindex(e.userid)
    if ent == entity.get_local_player() then ForgetAllCheats() elseif ent then ForgetCheat(ent) end
end))
client.set_event_callback("game_end",    EndMatch)
client.set_event_callback("level_init",  EndMatch)
client.set_event_callback("shutdown",    FullShutdown)
client.set_event_callback("disconnect",  FullShutdown)

info("init", "RIFTVEIL v" .. RV_VERSION .. " loaded -- commands: rv_stats  rv_db  rv_perf  rv_save  rv_clear  rv_reset  rv_wipe")
if log_nul > 0 then warn("init", "the previous log was damaged: %d zero bytes dropped (a crash during a write)", log_nul) end
flush_log()
