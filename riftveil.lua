-- ════════════════════════════════════════════════════════════════════
--  RIFTVEIL  v6.0  ·  gamesense.pub  ·  unmatched.gg
--  Two-tier memory · period prediction · config recognition
--  Vulnerability windows · backtrack learning · debug logger
-- ════════════════════════════════════════════════════════════════════
--  Changelog
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
local RV_VERSION = "6.0"

local ffi = require "ffi"

-- ══════════════════════════════════════════════════════════════════
--  DEBUG LOGGER
--  writefile / readfile are confirmed global GS API functions.
--  Output: %localappdata%\gamesense\riftveil_debug.txt (append).
--  Structured format: [HH:MM:SS.mmm][LVL][MOD] key=val ...
-- ══════════════════════════════════════════════════════════════════
local LOG_FILE  = "riftveil_debug.txt"
local log_buf   = {}
local log_total = 0

local function ts()
    local h, m, s, ms = client.system_time()
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function log_write(level, mod, msg)
    local line = string.format("[%s][%s][%s] %s", ts(), level, mod, msg)
    log_buf[#log_buf + 1] = line
    log_total = log_total + 1
    if #log_buf >= 512 then
        local existing = readfile(LOG_FILE) or ""
        writefile(LOG_FILE, existing .. table.concat(log_buf, "\n") .. "\n")
        log_buf = {}
    end
end

local function flush_log()
    if #log_buf == 0 then return end
    local existing = readfile(LOG_FILE) or ""
    writefile(LOG_FILE, existing .. table.concat(log_buf, "\n") .. "\n")
    log_buf = {}
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
local DB       = database.read(DB_KEY) or {}
local REC      = {}   -- per-player resolver records this match
local EIDX_S64 = {}   -- [entity_index] = steam64_str, refreshed each tick
local SHOTS    = {}   -- [shot_id] = context snapshot at aim_fire
local DT_HIST  = {}   -- [s64] = simtime-delta samples for DT detection

-- Per-frame render cache, filled once per net_update_end (Update()) and read
-- by DrawOverlay (paint fires every rendered frame -- often 5-10x more often
-- than net updates, so anything DrawOverlay can read instead of recompute is
-- a real, multiplicative FPS win, not a micro-optimization).
local LIVE_ENEMIES = {}   -- array of live enemy entindexes, this net_update
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
--  UI  —  skeet / deutsch style, LUA "B" container
--
--  Philosophy: built-in resolver runs by default.
--  We only take control when our signal is stronger than its guess.
--  [SAFE] = tested, additive, won't break the built-in
--  [EXP]  = experimental, disable if resolver feels worse
-- ══════════════════════════════════════════════════════════════════
local _h0      = ui.new_label("LUA","B","\xe2\x97\x86 RIFTVEIL")
local ui_on    = ui.new_checkbox("LUA","B","  Enable")

-- SAFE — these only override when signal is definitive
-- Display names were internal codenames until now (e.g. "6lex extraction"
-- means nothing to someone opening this menu cold -- it's the animation-
-- layer digit-read technique's internal nickname). Renamed to describe
-- what each one actually does; the underlying ui_* variable names are
-- unchanged (purely internal, never shown), so no logic moved.
local _h1      = ui.new_label("LUA","B","\xe2\x96\xb8 SAFE")
local ui_6lex  = ui.new_checkbox("LUA","B","  [SAFE] Desync Angle Detection")
local ui_vuln  = ui.new_checkbox("LUA","B","  [SAFE] Vulnerability Detection")
local ui_hitmem= ui.new_checkbox("LUA","B","  [SAFE] Hit Memory")

-- EXPERIMENTAL — disable if things feel worse
local _h2      = ui.new_label("LUA","B","\xe2\x96\xb8 EXPERIMENTAL")
local ui_per   = ui.new_checkbox("LUA","B","  [EXP] Jitter Prediction")
local ui_asym  = ui.new_checkbox("LUA","B","  [EXP] Asymmetric Angles")
local ui_sup   = ui.new_checkbox("LUA","B","  [EXP] Suppress Shots")

-- INTERFACE
local _h3      = ui.new_label("LUA","B","\xe2\x96\xb8 INTERFACE")
local ui_tight = ui.new_checkbox("LUA","B","  Tight Interpolation")
local ui_esp   = ui.new_checkbox("LUA","B","  ESP Indicators")
local ui_verb  = ui.new_checkbox("LUA","B","  Verbose Logging")
-- Accent picker: only tints the panel's idle/neutral chrome (header text,
-- idle top-strip). Never touches the vuln/resolved/building colors in
-- DrawOverlay -- those carry meaning (red/green/amber = state), not taste,
-- so they stay fixed regardless of this setting.
local ui_accent = ui.new_color_picker("LUA","B","  Panel Accent Color", 90, 150, 255, 255)

local _h4      = ui.new_label("LUA","B","\xe2\x96\xb8 CONTROLS")

-- Forward-declare FlushDB so button callbacks can reference it
local FlushDB

-- Renamed from "Flush DB" -- that name reads as a clear/reset action but
-- does the opposite: it PERSISTS the current match's stats into the
-- permanent DB (merging with existing entries), which is exactly what
-- EndMatch already does automatically. This button is only useful for
-- saving early mid-match; it has never cleared anything. "Reset match"
-- below is the actual clear control.
local _btn_flush = ui.new_button("LUA","B","  Save match to DB", function()
    if FlushDB then FlushDB() end
    client.log("[RIFTVEIL] match stats saved to DB")
end)
local _btn_reset = ui.new_button("LUA","B","  Reset match + DB", function()
    local n = 0
    for s64 in pairs(REC) do DB[s64] = nil; n = n + 1 end
    REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
    client.log(string.format("[RIFTVEIL] reset %d profiles", n))
    info("reset", "manual reset, %d profiles cleared", n)
end)
-- "Reset match + DB" above can only clear DB[s64] for players CURRENTLY in
-- REC -- it has no way to touch a profile from an opponent not loaded into
-- this session yet. That looks like "old players keep coming back after I
-- reset" when it's really just DB persistence working outside that
-- button's scope. This is the actual full wipe.
local _btn_wipe = ui.new_button("LUA","B","  Wipe ALL saved DB", function()
    local n = 0; for _ in pairs(DB) do n = n + 1 end
    DB = {}
    database.write(DB_KEY, DB)
    REC = {}; DT_HIST = {}; SHOTS = {}; EIDX_S64 = {}
    client.log(string.format("[RIFTVEIL] wiped entire DB (%d entries)", n))
    info("reset", "full DB wipe, %d entries cleared", n)
end)
local _btn_clr = ui.new_button("LUA","B","  Clear log", function()
    writefile(LOG_FILE, "")
    log_buf = {}; log_total = 0
    client.log("[RIFTVEIL] log cleared")
end)

local SUB_ITEMS = {
    _h1, ui_6lex, ui_vuln, ui_hitmem,
    _h2, ui_per, ui_asym, ui_sup,
    _h3, ui_tight, ui_esp, ui_verb, ui_accent,
    _h4, _btn_flush, _btn_reset, _btn_wipe, _btn_clr,
}
local function RefreshVis()
    local on = ui.get(ui_on)
    for _, item in ipairs(SUB_ITEMS) do ui.set_visible(item, on) end
end
ui.set_callback(ui_on, RefreshVis)
RefreshVis()

ui.set_callback(ui_tight, function()
    if not ui.get(ui_on) then return end
    if ui.get(ui_tight) then
        pcall(function()
            cvar.cl_interpolate:set_int(0)
            cvar.cl_interp_ratio:set_int(1)
            cvar.cl_interp:set_float(0.031)
        end)
        info("interp", "tight ON")
    else
        pcall(function()
            cvar.cl_interpolate:set_int(ORIG_IPOLATE)
            cvar.cl_interp_ratio:set_int(ORIG_RATIO)
            cvar.cl_interp:set_float(ORIG_INTERP)
        end)
        info("interp", "tight OFF")
    end
end)

-- ══════════════════════════════════════════════════════════════════
--  CONSOLE COMMANDS  (console_input — confirmed cheat event)
--    rv_stats   match stats per player
--    rv_db      permanent DB contents
--    rv_clear   wipe log file
--    rv_reset   hard reset match + DB entries for CURRENT enemies only
--    rv_wipe    wipe the ENTIRE permanent DB, every steam64 ever saved
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
                "  %s | %s | conf:%d%% | %d/%d (%d%%) | head:%d rmiss:%d | 6lex:%d/%d | bt:%d | cfg:%s | cond[%d]:%s | vuln:%s",
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
                tostring(e.bt_pref), math.floor((e.hit_rate or 0)*100),
                e.samples or 0, e.kills or 0)
        end
        local s = table.concat(out, "\n")
        client.log(s); log_write("CMD","db", s)

    elseif cmd == "rv_clear" then
        writefile(LOG_FILE, ""); log_buf = {}; log_total = 0
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

local CFG_LABEL = {
    luasense_beta = "luasense β",
    luasense_std  = "luasense",
    symmetric     = "symmetric",
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
    cur = (ok1 and cur and cur > 0) and cur or client.latency()
    avg = (ok2 and avg and avg > 0) and avg or cur
    return cur, avg
end

-- ══════════════════════════════════════════════════════════════════
--  MATH HELPERS + INPUT VALIDATION
-- ══════════════════════════════════════════════════════════════════
local function Clamp(v, a, b) return math.min(math.max(v, a), b) end
local function Sign(x)        return x > 0 and 1 or (x < 0 and -1 or 0) end
local function NA(a)
    while a >  180 do a = a - 360 end
    while a < -180 do a = a + 360 end
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

    s, d = try(al.weight)
    if s ~= 0 then return s, math.min(35.0, live_cap) end  -- weight fallback: fixed estimate
    return 0, 0
end

-- ══════════════════════════════════════════════════════════════════
--  ENGINE HELPERS
-- ══════════════════════════════════════════════════════════════════
-- (MaxDesync removed — was used to compute max_d which was dead after pick chain refactor)

local function ClassifyState(player, as, spd)
    local flags = entity.get_prop(player, "m_fFlags") or 0
    local og    = bit.band(flags, 1) ~= 0
    local duck  = as and (as.duck_amount or 0) > 0.5
    spd = spd or 0
    if not og   then return duck and STATE.AIR_CROUCH  or STATE.AIR           end
    if duck     then return spd > 20 and STATE.CROUCH_MOVING or STATE.CROUCH  end
    if spd > 5 and spd < 100 then return STATE.SLOWMOTION                     end
    if spd >= 100             then return STATE.RUNNING                        end
    return STATE.STANDING
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
        -- ui_asym gate: was documented in a comment here ("ui_asym toggle
        -- feeds into CfgAngle via ASYM_FALLBACK vs CFG_COUNTER selection")
        -- but never actually checked -- the [EXP] Asymmetric Angles
        -- checkbox did nothing at all. Wired up now: ON uses the per-side
        -- L/R fallback table as before; OFF averages it into one symmetric
        -- magnitude for both sides, matching what the toggle's own name
        -- and menu grouping ("disable if things feel worse") imply it was
        -- always meant to do.
        local a = ASYM_FALLBACK[state] or ASYM_FALLBACK[STATE.STANDING]
        if ui.get(ui_asym) then
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
    if (rec._dck_cooldown or 0) > 0 then
        -- cooldown ticking — decrement only, no DCK this tick
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
        local k = tostring(s64); EIDX_S64[player] = k; return k
    end
    local n = entity.get_player_name(player)
    if n and n ~= "" and n ~= "unknown" then
        local k = "n:" .. n; EIDX_S64[player] = k; return k
    end
    return nil
end

local function NewRec(player, s64)
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
        vuln_ttl=0, vuln_type=nil, vuln_val=0,
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
        info("rec", "new profile player=%s s64=%s",
             entity.get_player_name(player) or "?", s64)
    end
    REC[s64].eidx = player
    return REC[s64], s64
end

local function ClearEnt(player)
    plist.set(player, "Force body yaw", false)
    plist.set(player, "Force body yaw value", 0)
    plist.set(player, "Correction active", false)
    plist.set(player, "High priority", false)
    local s64 = EIDX_S64[player]
    if s64 and REC[s64] then
        REC[s64].active = false; REC[s64].resolved = false
    end
end

-- ══════════════════════════════════════════════════════════════════
--  DB FLUSH
--  Called on match end. Blends new match data with existing DB entry.
-- ══════════════════════════════════════════════════════════════════
FlushDB = function()
    for s64, rec in pairs(REC) do
        if rec.hit_count >= 2 then
            local ex   = DB[s64] or {}
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
            }
            info("db", "flush s64=%s cfg=%s vuln=%s bt=%d hr=%d%% hits=%d",
                 s64,
                 DB[s64].config_type or "?", DB[s64].vuln_pref or "?",
                 DB[s64].bt_pref or 0,
                 math.floor((DB[s64].hit_rate or 0) * 100),
                 DB[s64].kills)
        end
    end
    database.write(DB_KEY, DB)
    local n = 0; for _ in pairs(DB) do n = n + 1 end
    info("db", "written %d entries", n)
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
    rec.lt = st

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
        local state_key = ClassifyState(player, as, spd)
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

        if ui.get(ui_verb) then
            if live_cap ~= CFG.DESYNC_CAP then
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
                if ui.get(ui_6lex) then
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

        RPush(rec.hist, {p=pose, e=eye_y, t=st})
        rec.tm[st]      = rec.tm[st] or {p=pose, e=eye_y, t=st}
        rec.tm[st - CFG.TM_HORIZON] = nil
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

        -- Config recognition (throttled)
        if rec.config_conf < 0.8 and (st % CFG.CFG_TICKS) == 0 then
            local rcfg = RecognizeCfg(rec, rec.config_type)
            if rcfg then
                if rcfg == rec.config_type then
                    rec.config_conf = math.min(rec.config_conf + CFG.CFG_GAIN, 1.0)
                else
                    if ui.get(ui_verb) then
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

            rec.vuln_ttl  = math.max(base_ttl, lc_ttl)
            rec.vuln_type = vtype
            rec.vuln_val  = vcorr
            if ui.get(ui_verb) then
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

            elseif ui.get(ui_per) and #rec.fl >= CFG.PERIOD_MIN then
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
            local is_jitter = aa_type == AA.TWO_WAY  or aa_type == AA.THREE_WAY
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
        -- Lower confidence threshold when meta_aggressive — even a weaker
        -- vuln read beats the known-failing built-in.
        local vuln_min = rec.meta_aggressive and 0.20 or 0.35
        if ui.get(ui_vuln) and rec.vuln_ttl > 0 and rec.conf >= vuln_min then
            should_override = true
            override_val    = rec.vuln_val
            override_meth   = "vuln_" .. rec.vuln_type

        -- [2] 6lex: animlayer digit read — direct, no guessing. Gated by
        -- per-player calibration: once it's been proven wrong against
        -- confirmed hits more than a small margin above how often it's
        -- been right for THIS player, stop trusting it for them and fall
        -- through to hit-mem/suppress instead (see on_aim_hit).
        elseif ui.get(ui_6lex) and six_side ~= 0 and rec.conf > 0.25
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
        elseif ui.get(ui_hitmem) and rec.state
               and (rec.hit_count_by_state[rec.state] or 0) >= 2
               and (rec.hit_side_by_state[rec.state] or 0) ~= 0 then
            should_override = true
            override_val    = CfgAngle(rec.hit_side_by_state[rec.state], rec.state, TrustedCfg(rec), live_cap)
            override_meth   = METH.HIT_MEM

        elseif ui.get(ui_hitmem) and rec.hit_count >= 2 and rec.hit_side ~= 0 then
            should_override = true
            override_val    = CfgAngle(rec.hit_side, rec.state, TrustedCfg(rec), live_cap)
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
        elseif ui.get(ui_sup) and rec.vuln_ttl == 0 then
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
            plist.set(player, "Force body yaw", true)
            plist.set(player, "Force body yaw value", override_val)
            plist.set(player, "Correction active", true)
            -- High priority: confirmed via a real resolver's usage (not in
            -- the official docs) -- hints the LC/backtrack system not to
            -- deprioritize this target's validation window while we're
            -- actively correcting them ("prevent missing LC" per that
            -- script's own comment). Set last so a bad/renamed field
            -- can't stop the actual correction above from applying.
            plist.set(player, "High priority", true)
            rec.active = true; rec.resolved = true
            rec.last_val = override_val; rec.last_meth = override_meth
            -- Track suppress streak for the streak-cap logic above
            if override_meth == METH.SUPPRESS then
                rec._sup_streak = (rec._sup_streak or 0) + 1
            else
                rec._sup_streak = 0   -- any non-suppress override resets the streak
            end
            rec._sup_pause = 0

        elseif rec.meta_aggressive and tracked_side ~= 0 then
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
            plist.set(player, "Force body yaw", true)
            plist.set(player, "Force body yaw value", meta_val)
            plist.set(player, "Correction active", true)
            plist.set(player, "High priority", true)
            rec.active = true; rec.resolved = true
            rec.last_val = meta_val; rec.last_meth = METH.META_HOLD
            -- Don't blow away a suppress streak/pause in progress -- this
            -- branch fires DURING the deliberate 4-tick pause window (should_
            -- override is false while paused), not just when suppress is
            -- genuinely irrelevant. See sup_pausing above.
            if not sup_pausing then rec._sup_streak = 0; rec._sup_pause = 0 end

        else
            plist.set(player, "Force body yaw", false)
            plist.set(player, "Force body yaw value", 0)
            plist.set(player, "Correction active", false)
            plist.set(player, "High priority", false)
            rec.active = false; rec.resolved = false
            rec.last_val = 0; rec.last_meth = "builtin"
            -- Same sup_pausing guard as the meta_aggressive branch above.
            if not sup_pausing then rec._sup_streak = 0; rec._sup_pause = 0 end
        end

        -- Only log when the correction method or value actually CHANGES.
        -- Log analysis showed 35k+ [corr] lines for 453 hits — 98% were
        -- stale TTL echoes (same val repeated for 11+ ticks). This gate
        -- cuts the log to only meaningful resolver decisions.
        if ui.get(ui_verb) then
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

    until true  -- end of repeat block; break exits without running save

    -- Save previous frame state (always, for every path that sampled data)
    rec.prev_pose     = pose
    rec.prev_spd2     = rec.prev_spd  -- shift: spd2 = last tick's spd before this update
    rec.prev_spd      = spd
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
local function Update()
    if not ui.get(ui_on) then return end

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

    client.update_player_list()
    local n_live = 0
    for _, player in ipairs(entity.get_players()) do
        if entity.is_enemy(player) and entity.is_alive(player) then
            -- Cache the live-enemy list here (already paid for is_enemy/
            -- is_alive this tick) so DrawOverlay's off-angle row doesn't
            -- re-scan every player again on every single rendered frame.
            n_live = n_live + 1
            LIVE_ENEMIES[n_live] = player
            local ok, msg = pcall(ProcessPlayer, player, ctx)
            if not ok then
                err("update", "player=%d crash=%s", player, tostring(msg))
            end
        end
    end
    for i = #LIVE_ENEMIES, n_live + 1, -1 do LIVE_ENEMIES[i] = nil end

    -- Periodic autosave: don't rely solely on match-end/disconnect/shutdown
    -- firing cleanly. Every 60s, if there's anyone worth saving, flush to
    -- the permanent DB so a crash or hard stop doesn't lose the session.
    local now = globals.realtime()
    if next(REC) and (now - LAST_DB_SAVE) >= 60 then
        LAST_DB_SAVE = now
        FlushDB()
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
        -- e.backtrack is a TIME value (seconds), not a tick count -- must
        -- go through TT() before comparing against the 1..16 tick range
        -- used everywhere else (bt_hist/preferred_bt/log output).
        bt      = TT(e.backtrack),
        hc      = e.hit_chance or 0,
        in_vuln = r and r.vuln_ttl > 0 or false,
        vuln_t  = r and r.vuln_type or nil,
        cfg     = r and r.config_type or nil,
        six_side = r and r.six_side or 0,  -- for 6lex agree/disagree calibration on hit
        tick    = globals.tickcount(),
        -- fire_time/srv_hits: lets on_aim_miss tell a real resolver miss
        -- apart from a stale/timed-out event or a server-side hit that got
        -- reported as a client-side miss (see on_aim_miss).
        fire_time  = globals.realtime(),
        srv_hits = me and (entity.get_prop(me, "m_totalHitsOnServer") or 0) or 0,
    }
    -- Credit a vuln_profile "seen" (trial) here, once per actual shot fired
    -- during an open vuln window -- not once per detection (see the
    -- comment at the DetectVuln call site in ProcessPlayer for why).
    if r and r.vuln_ttl > 0 and r.vuln_type and r.vuln_profile[r.vuln_type] then
        r.vuln_profile[r.vuln_type].seen = r.vuln_profile[r.vuln_type].seen + 1
    end
end

local function on_aim_hit(e)
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
        if d.side ~= 0 and is_head then
            rec.hit_side  = d.flip and -d.side or d.side
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

    info("hit", "player=%s group=%s dmg=%d meth=%s val=%.0f bt=%d%s",
        entity.get_player_name(e.target) or "?",
        HG[e.hitgroup + 1] or "?", e.damage or 0,
        d.meth, d.val, d.bt,
        d.in_vuln and (" !" .. d.vuln_t) or "")
    SHOTS[e.id] = nil
end

local function on_aim_miss(e)
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
        if ui.get(ui_verb) then
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

    local is_resolver = reason == "?" or reason == "" or reason == "prediction error"

    warn("miss", "player=%s reason=%s meth=%s val=%.0f bt=%d hc=%.0f%%%s",
        entity.get_player_name(e.target) or "?",
        reason, d.meth, d.val, d.bt, d.hc,
        d.in_vuln and (" !" .. d.vuln_t) or "")

    if is_resolver then
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
local function ent_rec(ent)
    if not ui.get(ui_on) then return nil end
    if not entity.is_enemy(ent) or not entity.is_alive(ent) then return nil end
    local s64 = EIDX_S64[ent]; return s64 and REC[s64] or nil
end

-- VLN — vulnerability window open (deterministic correction being applied)
client.register_esp_flag("VLN", 230, 28, 28, function(ent)
    local ok, r = pcall(function()
        local rec = ent_rec(ent); return rec ~= nil and rec.vuln_ttl > 0
    end); return ok and r or false
end)

-- RES — resolver has a confident read and is overriding the built-in
-- (covers hit-mem, 6lex, and meta-hold alike -- any method confident
-- enough to be actively applied, not suppress and not a vuln window)
client.register_esp_flag("RES", 55, 205, 70, function(ent)
    local ok, r = pcall(function()
        local rec = ent_rec(ent)
        return rec ~= nil and rec.resolved and rec.conf >= CFG.CONF_ESP
            and rec.vuln_ttl == 0 and rec.last_meth ~= METH.SUPPRESS
    end); return ok and r or false
end)

-- ══════════════════════════════════════════════════════════════════
--  DRAGGABLE PANEL  (v3.0 — Solus-UI style single panel, replaces the
--  stacked renderer.indicator rows entirely)
--
--  Position is persisted through two HIDDEN sliders instead of a plain
--  Lua local -- ui.new_slider values survive config save/load and script
--  reload (a raw local table wouldn't), which is the same trick real
--  Solus-style HUDs use to make a "movable box" remember where you put it.
--  Drag by clicking and holding inside the title bar -- gated to the menu
--  being open so holding left-click to shoot during a round can never
--  accidentally drag the panel around mid-fight.
-- ══════════════════════════════════════════════════════════════════
local PANEL_RES     = 10000
local PANEL_PAD     = 7
local PANEL_ROW_H   = 13
local PANEL_TITLE_H = 16
local PANEL_MIN_W   = 150
local PANEL_R       = 6  -- corner radius

-- Rounded rectangle: 3 straight-fill rects + 4 corner quarter-circles.
-- Ported from a real "SOLUS UI"-style script's renderer_rounded_rect,
-- trimmed to just the fill (no outline/multi-step shadow -- this repaints
-- every frame, so a single extra call for a flat drop-shadow is used
-- instead of a several-step gaussian falloff). renderer.circle's
-- start_degrees/percentage usage here is verified against
-- docs.gamesense.gs/docs/api/renderer/circle: 180@0.25 sweeps the
-- top-left quarter, 270@0.25 top-right, 0@0.25 bottom-right, 90@0.25
-- bottom-left.
local function RoundedRect(x, y, w, h, r, cr, cg, cb, ca)
    r = math.min(r, h / 2, w / 2)
    if r <= 0 then
        renderer.rectangle(x, y, w, h, cr, cg, cb, ca)
        return
    end
    renderer.rectangle(x + r, y, w - 2 * r, h, cr, cg, cb, ca)
    renderer.rectangle(x, y + r, r, h - 2 * r, cr, cg, cb, ca)
    renderer.rectangle(x + w - r, y + r, r, h - 2 * r, cr, cg, cb, ca)
    renderer.circle(x + r,     y + r,     cr, cg, cb, ca, r, 180, .25)
    renderer.circle(x + w - r, y + r,     cr, cg, cb, ca, r, 270, .25)
    renderer.circle(x + w - r, y + h - r, cr, cg, cb, ca, r, 0,   .25)
    renderer.circle(x + r,     y + h - r, cr, cg, cb, ca, r, 90,  .25)
end

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

-- Called once per paint with the title bar's current screen rect.
local function UpdateDrag(px, py, pw, ph)
    local menu_open = ui.is_menu_open()
    local mx, my    = ui.mouse_position()
    local held      = menu_open and client.key_state(0x01) == true
    if held and not drag.held then
        drag.grabbed = mx >= px and mx <= px + pw and my >= py and my <= py + ph
        -- Reset the delta baseline to THIS frame's mouse position the
        -- instant a grab starts. Without this, drag.mx/my still held
        -- whatever position was recorded on the last unrelated frame
        -- (mouse released, hovering elsewhere) -- so the very first frame
        -- of every drag applied a "jump" equal to incidental mouse
        -- movement since then, snapping the panel before smooth dragging
        -- took over on subsequent frames.
        if drag.grabbed then drag.mx, drag.my = mx, my end
    elseif not held then
        drag.grabbed = false
    end
    if drag.grabbed then
        local x, y = PanelPos()
        SetPanelPos(x + (mx - drag.mx), y + (my - drag.my))
    end
    drag.held, drag.mx, drag.my = held, mx, my
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

-- SideBar: directional confidence fill, rendered as a plain text line
-- inside the panel body.
--   side=-1  →  ◀ ■■■■■■····  62%        (fill anchored left, grows with conf)
--   side=+1  →    62%  ····■■■■■■ ▶      (fill anchored right)
--   side= 0  →      ··· unk ···           (unknown)
local function SideBar(side, conf)
    local cf     = Clamp(conf, 0, 1)
    local BARS   = 10
    local filled = math.floor(cf * BARS + 0.5)
    local full   = string.rep("\xe2\x96\xa0", filled)         -- ■ U+25A0
    local empty  = string.rep("\xc2\xb7", BARS - filled)      -- · U+00B7
    local pct    = math.floor(cf * 100)
    if side < 0 then
        return "\xe2\x97\x80 " .. full .. empty .. " " .. pct .. "%"
    elseif side > 0 then
        return pct .. "% " .. empty .. full .. " \xe2\x96\xb6"
    else
        return "\xc2\xb7\xc2\xb7\xc2\xb7 unk \xc2\xb7\xc2\xb7\xc2\xb7"
    end
end

local function DrawOverlay()
    if not ui.get(ui_on) or not ui.get(ui_esp) then return end

    -- ── Gather content ────────────────────────────────────────────────
    -- total_hits/total_misses (every real outcome) -- NOT hit_count
    -- (head/neck-confirmed only) or resolver_misses (non-vuln only). Those
    -- two drive internal resolver logic and were never meant to be a
    -- hit/miss scoreboard; using them here undercounted misses badly,
    -- since most misses happen during vuln windows and resolver_misses
    -- deliberately excludes those.
    local mh, mm = 0, 0
    for _, r in pairs(REC) do
        mh = mh + (r.total_hits or 0)
        mm = mm + (r.total_misses or 0)
    end
    local total  = mh + mm
    local hr_str = total > 0
        and string.format("%d%%", math.floor(mh / total * 100)) or "--"
    local header = string.format("%dH/%dM \xc2\xb7 %s", mh, mm, hr_str)

    -- is_spike is computed once per net_update in Update() (LAST_SPIKE) --
    -- paint fires every rendered frame, so recomputing it here via GetLat()
    -- would be pure per-frame overhead for a value that rarely changes.
    local is_spike = LAST_SPIKE
    local threat   = client.current_threat()
    local rec      = nil
    if threat and entity.is_alive(threat) then
        local s64 = EIDX_S64[threat]
        rec = s64 and REC[s64]
    end

    -- lines: {text, r, g, b}. accent_* drives the title bar's top strip,
    -- so the panel's overall color reads the resolver state even before
    -- you read a single word of text.
    local lines = {}
    -- Idle default reads from ui_accent (user-customizable) -- the vuln/
    -- resolved/building branches below still override it with their own
    -- fixed, meaningful colors regardless of this setting.
    local accent_r, accent_g, accent_b = ui.get(ui_accent)

    if rec then
        local cf   = rec.conf
        local name = entity.get_player_name(threat) or "?"
        if #name > 16 then name = name:sub(1, 15) .. "\xe2\x80\xa6" end
        local tc = AA_SHORT[rec.aa_type] or "?"

        lines[#lines+1] = {string.format("%s  \xc2\xb7  %s  %d%%", name, tc, math.floor(cf * 100)), 225, 225, 232}

        local meth    = rec.last_meth
        local mlbl    = (meth and meth ~= "builtin") and (METH_LABEL[meth] or meth) or nil
        local has_val = isnum(rec.last_val) and math.abs(rec.last_val) > 0.5
        local angle_s = has_val and string.format(" %+.0f\xc2\xb0", rec.last_val) or ""

        if rec.vuln_ttl > 0 then
            local vt = (rec.vuln_type or "?"):upper()
            accent_r, accent_g, accent_b = 235, 60, 60
            lines[#lines+1] = {string.format("\xe2\x9a\xa1 %s  %dt%s", vt, rec.vuln_ttl, angle_s), 245, 115, 115}
        elseif rec.resolved and cf >= CFG.CONF_ESP then
            accent_r, accent_g, accent_b = 70, 210, 130
            local src = mlbl and ("  " .. mlbl) or ""
            lines[#lines+1] = {string.format("\xe2\x97\x8f resolved%s%s", src, angle_s), 130, 225, 165}
        else
            accent_r, accent_g, accent_b = 215, 150, 60
            lines[#lines+1] = {"\xe2\x97\x8b building", 215, 178, 120}
        end

        local side = rec.side
        local sr, sg, sb_line
        if     side < 0 then sr, sg, sb_line = 100, 170, 255
        elseif side > 0 then sr, sg, sb_line = 255, 165, 90
        else                 sr, sg, sb_line = 150, 150, 158 end
        lines[#lines+1] = {SideBar(side, cf), sr, sg, sb_line}

        local sup = {}
        if rec.preferred_bt > 0 then sup[#sup+1] = "bt:" .. rec.preferred_bt end
        if rec.config_type and rec.config_conf >= CFG.CFG_THRESH then
            sup[#sup+1] = CFG_LABEL[rec.config_type] or rec.config_type
        end
        if rec.def_tickbase    then sup[#sup+1] = "def" end
        if is_spike            then sup[#sup+1] = "spk" end
        if rec.meta_aggressive then sup[#sup+1] = "agg" end
        if #sup > 0 then
            lines[#lines+1] = {table.concat(sup, "  \xc2\xb7  "), 150, 150, 162}
        end

        -- Off-angle awareness: 2v2/duel modes only ever have one other
        -- enemy. Reads LIVE_ENEMIES (cached once per net_update in
        -- Update()) instead of scanning entity.get_players() again here
        -- every rendered frame.
        for _, p in ipairs(LIVE_ENEMIES) do
            if p ~= threat then
                local os64 = EIDX_S64[p]
                local orec = os64 and REC[os64]
                if orec then
                    local oname = entity.get_player_name(p) or "?"
                    if #oname > 16 then oname = oname:sub(1, 15) .. "\xe2\x80\xa6" end
                    local otc = AA_SHORT[orec.aa_type] or "?"
                    lines[#lines+1] = {string.format("\xe2\x86\xb3 %s  %s %d%%", oname, otc, math.floor(orec.conf * 100)), 125, 125, 135}
                end
                break
            end
        end
    elseif is_spike then
        lines[#lines+1] = {"\xe2\x96\xb2 spike", 235, 150, 60}
    end

    -- ── Layout ──────────────────────────────────────────────────────
    local px, py  = PanelPos()
    local title_w = renderer.measure_text(nil, header) + PANEL_PAD * 2 + 18
    local content_w = PANEL_MIN_W
    for _, ln in ipairs(lines) do
        local w = renderer.measure_text(nil, ln[1])
        if w > content_w then content_w = w end
    end
    local pw = math.max(title_w, content_w + PANEL_PAD * 2)
    local ph = PANEL_TITLE_H + #lines * PANEL_ROW_H + (#lines > 0 and PANEL_PAD or 2)

    UpdateDrag(px, py, pw, PANEL_TITLE_H)

    -- ── Draw ────────────────────────────────────────────────────────
    -- Rounded body + a single offset shadow pass instead of the old flat
    -- hard-cornered rectangles and straight 1px border lines (which would
    -- visibly clash with rounded corners). The header no longer gets its
    -- own filled rectangle -- square corners on an inset rect would poke
    -- out past the rounded body above/below it -- a thin inset separator
    -- line marks the header/body boundary instead.
    RoundedRect(px + 3, py + 4, pw, ph, PANEL_R, 0, 0, 0, 90)      -- shadow
    RoundedRect(px, py, pw, ph, PANEL_R, 14, 14, 18, 232)          -- body
    renderer.gradient(px + PANEL_R, py, pw - PANEL_R * 2, 2,
                                      accent_r, accent_g, accent_b, 235,
                                      accent_r, accent_g, accent_b, 40, false) -- accent strip
    renderer.rectangle(px + PANEL_R, py + PANEL_TITLE_H, pw - PANEL_R * 2, 1,
                        45, 45, 52, 200) -- header separator

    -- "RV" tinted 55% toward the accent color, blended with light gray so
    -- it stays legible even if the user picks a dark accent.
    local title_r = math.floor(accent_r * 0.55 + 205 * 0.45)
    local title_g = math.floor(accent_g * 0.55 + 208 * 0.45)
    local title_b = math.floor(accent_b * 0.55 + 218 * 0.45)
    renderer.text(px + PANEL_PAD, py + 3, title_r, title_g, title_b, 255, "", 0, "RV")
    local hdr_w = renderer.measure_text(nil, header)
    renderer.text(px + pw - hdr_w - PANEL_PAD, py + 3, 150, 150, 162, 220, "", 0, header)

    local ly = py + PANEL_TITLE_H + 3
    for _, ln in ipairs(lines) do
        renderer.text(px + PANEL_PAD, ly, ln[2], ln[3], ln[4], 240, "", 0, ln[1])
        ly = ly + PANEL_ROW_H
    end

    -- ── World-space "SHIFT" flash + box ─────────────────────────────────
    -- Fires from the origin-jump check in ProcessPlayer -- a brief, fading
    -- tag + wireframe box over ANY live enemy whose backtrack record just
    -- broke, not just the current threat, since a shift is a rare,
    -- meaningful moment worth surfacing regardless of who's aimed at.
    -- Inspired by a standalone "lag comp breaker" ESP tool's 3D box +
    -- tether-line style; the box corners/edges here are rebuilt from
    -- scratch with correct 1-indexed Lua array math (that reference file's
    -- own edge list mixes 0- and 1-based indices, silently dropping 3 of
    -- its 12 intended edges -- not something to carry over).
    local BOX_EDGES = {
        {1,2},{2,4},{4,3},{3,1},   -- bottom face
        {5,6},{6,8},{8,7},{7,5},   -- top face
        {1,5},{2,6},{3,7},{4,8},   -- verticals
    }
    local decay = globals.frametime() * 2  -- fades out over ~0.5s
    for _, p in ipairs(LIVE_ENEMIES) do
        local s2 = EIDX_S64[p]
        local r2 = s2 and REC[s2]
        if r2 and (r2._shift_flash or 0) > 0 then
            r2._shift_flash = math.max(0, r2._shift_flash - decay)
            if r2._shift_flash > 0 then
                local ox2, oy2, oz2 = entity.get_origin(p)
                local a = math.floor(r2._shift_flash * 255)
                local sx, sy
                if isnum(ox2) and isnum(oy2) and isnum(oz2) then
                    sx, sy = renderer.world_to_screen(ox2, oy2, oz2 + 78)
                    if sx then
                        renderer.text(sx, sy, 255, 140, 60, a, "c", 0, "SHIFT")
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
                                renderer.line(p1[1], p1[2], p2[1], p2[2], 255, 140, 60, ba)
                            end
                        end
                        -- Tether from the actually-reported origin to the box's
                        -- CENTER, not an arbitrary corner -- scr[1] (bottom,
                        -- min-x, min-y) is on the far side of the box from the
                        -- camera at plenty of viewing angles, so the tether
                        -- looked like it stabbed into a random edge instead of
                        -- pointing at the box. The center is always a
                        -- consistent, symmetric anchor regardless of angle.
                        local ccx = bx + (mnx + mxx) / 2
                        local ccy = by + (mny + mxy) / 2
                        local ccz = bz + (mnz + mxz) / 2
                        local tsx, tsy = renderer.world_to_screen(ccx, ccy, ccz)
                        if sx and tsx then
                            renderer.line(sx, sy, tsx, tsy, 255, 140, 60, ba)
                        end
                    end
                end
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════
local function ResetPlist()
    for i = 1, 64 do
        pcall(function()
            plist.set(i, "Force body yaw", false)
            plist.set(i, "Force body yaw value", 0)
            plist.set(i, "Correction active", false)
        end)
    end
end

local function EndMatch()
    info("match", "ended -- flushing DB")
    FlushDB()
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
--  EVENT REGISTRATION
-- ══════════════════════════════════════════════════════════════════
client.set_event_callback("net_update_end", function()
    if entity.is_alive(entity.get_local_player()) then
        local ok, msg = pcall(Update)
        if not ok then err("update", "top-level crash: %s", tostring(msg)) end
    end
end)
client.set_event_callback("paint",       DrawOverlay)
client.set_event_callback("aim_fire",    on_aim_fire)
client.set_event_callback("aim_miss",    on_aim_miss)
client.set_event_callback("aim_hit",     on_aim_hit)
client.set_event_callback("round_start", ResetPlist)
client.set_event_callback("game_end",    EndMatch)
client.set_event_callback("level_init",  EndMatch)
client.set_event_callback("shutdown",    FullShutdown)
client.set_event_callback("disconnect",  FullShutdown)

info("init", "RIFTVEIL v" .. RV_VERSION .. " loaded -- commands: rv_stats  rv_db  rv_clear  rv_reset  rv_wipe")
flush_log()
