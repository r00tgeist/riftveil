# RIFTVEIL changelog

Moved out of `riftveil.lua` in v7.2. Newest first.

```text
  v8.39  – Hit memory weighs what each shot can prove (HMEM_WEIGHT).
          FIXED -- v6.2 counted head hits regardless of side: a head hit
          on +, then one on -, read as "confirmed twice" and forced -. The
          memory is now one signed number per movement state and one
          overall; a + and a - hit cancel.
          Weapon (ours): awp / scout / auto / r8 / deagle 1, pistol 0.75,
          rifle / smg 0.5, machine gun 0.25, shotgun / taser / knife /
          grenade 0. Hitbox: aimed head -> head 1, neck 0.5; a head hit off
          a body-aimed shot 0 (spread put it there, not our angle). Two
          precise head hits on one side make a known side, as before.
          A resolver miss on the remembered side takes twice its weight
          (head-aimed 1, neck / chest / stomach 0.5, limbs 0), never past
          zero; "prediction error", teleported / extrapolated shots and a
          miss on the other side take nothing. A soft reset clears it.
          Logging: every learn / against / weaken / drop / skip is an [hmem]
          line with our weapon (wc=), its weight, aimed and landed hitbox,
          the hitbox weight, memory before -> after (overall and this
          state) and why a skip taught nothing. Hit / miss lines add wc=
          (weapon in full: rifle, smg, shotgun, knife ... instead of
          "other"), hw= (the weight that shot carried) and hm= (memory in
          effect at the shot, overall/this state); rv_stats shows hm.
          log_report: BY OUR WEAPON IN FULL, HIT MEMORY EVIDENCE.
  v8.38  – Wiring pass: the v8.32-8.37 pieces made to agree with each other.
          Hit memory stores the side that was on the hitbox (LEARN_GS):
          a forced shot that lands the head files the sign of the value we
          forced, gamesense's own shot files gamesense's answer. v6.2 filed
          our pose majority, even when a vuln window had forced the other
          side.
          A hit-memory resolver miss now drops the whole memory under
          KNOWN_ONLY (v6.2 cleared only that movement state and forced the
          missed side again from the global memory); gamesense resolves
          until a new head hit confirms a side.
          Vuln windows are detected only on clean records (POSE_CLEAN):
          their value comes from the animstate our client built, which on a
          record we forced is our own value.
          VULN_DELTA -- stop / peek / landing windows force the goal-feet /
          torso yaw relative to the eye, within this frame's limit, like UNK
          since v8.29; they forced world yaws (the side came from map
          facing). DCK keeps its value (77%, the best method in the logs).
          FIXED -- the shot log line could crash aim_hit / aim_miss when a
          window's type was missing ("!" .. nil).
          Quality: one release path (PListRelease) instead of two copies of
          the four player-list writes; the per-record entity.get_desync()
          probe removed (never logged a line in 34k verbose decisions); the
          vuln window "+1 tick" boosts -- and CanSeeHead's trace -- skipped
          where they can't beat the 200 ms lag-comp window (every 64 / 128
          tick server); CanSeeHead unit-called by the harness.
          Each change behind its flag where it decides anything, harness
          test with the v6.2 path, mutation-checked; parity exact.
  v8.37  – Force only on knowledge; learn from gamesense's own resolver.
          BEAT_BUILTIN off: deciding by head rates on 8-20 shots is luck
          (they swing 15-20 points either way).
          KNOWN_ONLY -- RIFTVEIL forces only where something is known: a
          confirmed head hit (hit memory) or a server event (vuln windows on
          unchoke, stop, peek, landing, duck crossing). Everything else is
          gamesense's own resolver. No longer forced, because they are
          guesses: suppress (inverts the side our client shows), meta hold /
          brute, and the LBY / CTR windows (triggered by the client pose).
          Pose confidence no longer gates event windows or hit memory.
          LEARN_GS -- on a record built with nothing forced, the body-yaw
          pose our client shows is gamesense's resolved answer. It is kept
          per enemy and logged on every shot (gs=); when gamesense's own
          shot lands the head, hit memory files that answer's side (v6.2
          filed our 16-record majority, often the other side on jitter).
          FIXED -- rv_db crashed on a saved profile with fractional counts
          (old version / hand edit): "%d" on 4.5.
          Harness: nothing-known enemy left to gamesense (v6.2: suppress),
          hit memory and a low-confidence unchoke window forced on every
          record, LBY window not forced; gamesense's answer captured from an
          unforced record and filed on a builtin head hit (v6.2: our side);
          rv_db with fractional counts. Each part mutation-checked; v6.2
          parity exact.
  v8.36  – Steer gamesense instead of replacing it.
          BEAT_BUILTIN -- the public resolvers that work with gamesense
          (hysteria / jitterresolver / AlynResolver / GS_RESOLVER -- one
          script copied five times -- Bloodedge) set Force body yaw only in
          the moment they know more and leave it off, gamesense's own
          resolver, everywhere else. Force body yaw is the only lever into
          gamesense's resolver; the question is when to pull it. Now: a
          RIFTVEIL method forces only while its learned head rate keeps
          within 5 points of gamesense's own -- on the enemy's cheat when
          both have 8+ head-aimed shots there, else across every enemy (new
          "all" bucket, credited whether a cheat is detected or not, saved
          like the rest). Below that the enemy goes back to gamesense; every
          4th shot still tries the method so it can earn its way back.
          Across the logs gamesense lands 65%: DCK 77%, suppress 70%, hit
          memory 67% keep forcing; PKA 47%, CTR 50% would hand back. Debug
          log / save: "[cheat] learned all: ...". Off in the parity run;
          harness covers release, probe, keep, cheat-vs-all bucket, credit
          without a cheat and the v6.2 path, each mutation-checked.
  v8.35  – Plan steps 2 and 3 in code: read the enemy, not ourselves; one
          magnitude for every lua.
          POSE_CLEAN -- the AA picture, confidence, side, flips and the
          pose-triggered windows (LBY / CTR) come only from records built
          while nothing was forced. The body-yaw pose is computed by our
          client; on a record we forced it reads our own value back (bots
          with no desync were labelled hold / 2-way / 3-way on 56 of 64
          shots, and a constant hit-memory value showed as "hold" on 50% of
          its lines vs 11% unforced). A record we forced also clears the
          previous pose, so our own switch can't read as an LBY "snap".
          Harness: an enemy on a static AA, fakelagging, whose pose echoes
          what we force and whose first reads jitter -- v6.2 keeps forcing
          its own alternating suppress forever, v8.35 reads it static and
          hands it back; single-record checks for confidence, previous pose
          and the LBY window.
          FULL_DESYNC -- every side-based value (hit memory, suppress, LBY,
          6lex fallback, meta) is the side times the engine's desync limit
          for that frame (MaxDesync: 58 standing, 29 at a full run) instead
          of the luasense yaw-offset tables, for any lua and any settings:
          211 of 330 limit sliders in the repo's AA scripts default to 60,
          settings exports and presets sit at 58-60; in the logs the right
          side landed 66% at 30-39 and 77% at 40-60, and under 20 was the
          weakest band for every method. Hit memory takes the speed-aware
          limit too (it used a flat 58). Harness: +-cap from CfgAngle,
          suppress at 58 on a standing enemy, hit memory at the running
          limit; v6.2 paths checked.
          Both off in the v6.2 parity run; every part mutation-checked.
  v8.34  – Full review of the resolver path, function by function.
          FIXED (WINDOW_GATE) -- an open vuln window that was NOT being
          forced (Vulnerability off, the enemy's cheat distrusting that
          type, confidence under the window minimum) still stood the side
          chain and suppress down for its 11 records; the fallback then used
          the raw, unflipped side. Now only a forced window does.
          FIXED (STALE_WINDOW) -- round start reset the player list but not
          what each record says it forces (method, value, window, suppress
          streak), so a shot before the round's first decision was learned
          as last round's method.
          FIXED (META_STREAK) -- the "gamesense failing twice in a row"
          streak was reset only by OUR hits; gamesense's own hit didn't end
          it, so builtin miss, hit, miss handed the enemy to the aggressive
          mode.
          CHANGED (NO_SAFEPOINT) -- the aim policy no longer forces safe
          point. Across the logs: safe point 47%, head kill + safe point
          50%, ragebot default 57%, head kill 86% head rate; on x-way after
          a resolver miss 48% (34/71) with it against 43% (25/58) before it
          existed -- no real gain, and it is what made the ragebot wait.
          Head kill -> head only, body kill -> body, else the ragebot's own
          setting. "In doubt" (2 misses, x-way after a miss) now decides
          nothing; the x-way log table keeps measuring it.
          NEW LOG FIELDS -- two side signals the server sends, on every shot
          line, so the next logs can test them: eo= the enemy's eye yaw
          against facing straight away from us (L/R-yaw AAs pick the offset
          by desync side), lbyu= seconds since the server moved their LBY
          target. log_report: EYE OFFSET vs FORCED SIDE, SINCE THEIR LBY
          TARGET LAST MOVED.
          Checked, no change: preferred_bt / vuln_pref are learned and saved
          but no decision reads them (panel only); scout shots under the
          ragebot default land 48% (87), mostly with no traced line to the
          head -- peeks and extrapolated positions, gamesense no better
          (8/13); "Tight interpolation" leaves the lag-comp window as the
          default (lerp 0.031) and switches entity interpolation off.
          Each fix: harness test running the v6.2 path too, mutation-checked.
  v8.33  – No choke, no desync: bots and no-AA players are static.
          The logs hold 64 shots at bots (Yogi, Neil, George, Toby, Allen,
          Ulysses, Marvin, Harvey -- no Steam ID). A bot has no desync, yet
          RIFTVEIL labelled them hold 27, 2-way 15, 3-way 9, skitter 3,
          5-way 2 and static only 8, and forced a value on 54 (hit memory
          21, vuln 17, suppress 16). The pose it reads is our client's --
          gamesense's resolver and our own override -- not the enemy's.
          FEATURE.NO_CHOKE_STATIC: desync needs choked commands (the hidden
          angle sits on a choked one), so an enemy whose last 16 records
          came one tick apart (one bundled packet allowed) is static and
          handed to gamesense whatever the pose shows. Choking one tick
          every third record, fakelag, or a gap past 64 ticks (history
          starts over) keep resolving. Debug log: [aa] line when an enemy
          goes in or out. Off in the parity run; harness covers bot,
          bundled packet, intermittent choke, fakelag, reset and the v6.2
          path, each mutation-checked.
          Static troll AA (fakelag on, desync fixed) still reads from the
          pose: that is plan step 2, decided on the Debug log probe.
  v8.32  – Step 1 of docs/PLAN.md: verify every resolver function.
          docs/RESOLVER_AUDIT.md -- each function on the path to the forced
          value: what it reads (server data, client data, or client data our
          own override writes), what it feeds, how its shots land.
          FIXED -- the Debug log checkbox did nothing since v8.1: SyncFlags
          set DET.verbose from itself, so no [corr] / [vuln] / [cfg] / [dcap]
          line was written for 30 versions (the v8.x logs only had shot
          lines; the v8.28 phantom-DCK counter could never print). Logging
          only.
          FIXED (DESYNC_FORMULA) -- the cap on our correction guesses is
          Valve's per-frame body-yaw limit (antiaim_funcs' SetUpVelocity
          formula: 58 standing, 29 at a full run, ducking toward half, never
          lower) instead of VelCap's line to 0 at 580 u/s (18 deg at 400).
          The animstate min/max yaw LiveCap reads are +-58 on 97% of 16.7k
          samples -- fixed aim limits -- so VelCap was the only speed model;
          forced values under 20 deg are the weakest band in every log (side
          methods ~45%, suppress 33%, against 62-77% from 20 up). Off in the
          parity run; harness covers standing / run / air / slow walk /
          crouch-walk / unreadable input, mutation-checked.
          PROBE (log only): every [corr] line carries pz= (the body-yaw pose
          read on that record) and pf= (what we forced). Players' pose
          parameters are computed by our client, not sent by the server, so
          the AA detector may be reading our own override back (hit memory,
          one constant value, is labelled hold on 50% of its lines vs 11%
          when nothing is forced). log_report: POSE READ BACK vs WHAT WE
          FORCED decides plan step 2.
          Measured, no change: suppress lands 70% (2-way 92%, skitter 83%,
          3-way 72%, hold 69%; 5-way 56%, 16 shots) and changes no shot
          timing; safe point at fire was 15% in v8.27 against 4-7% after,
          which lines up with the delay. 211 of 330 desync-limit sliders in
          the repo's AA scripts default to 60 -- presets differ in yaw
          offsets and side patterns, not in desync size.
  v8.31  – Local lagcomp box: the shot + teleport alone, no speed condition.
          v8.30's 64-unit rule hid it on a normal ground double tap; the
          exploit is the shot followed by the tickbase teleport, so that is
          the whole trigger now (DT on, our shot, shift > 2 ticks within
          0.25 s). Harness: a DT shot while standing still draws it.
  v8.30  – Local lagcomp box: only a double-tap shot that breaks lag comp.
          It flashed on any tickbase shift over 2 ticks, so toggling DT and
          defensive lit it too. Now it needs all of: double tap on and our
          own shot (weapon_fire), the shift within 0.25 s of it (one batch
          of commands, sv_maxusrcmdprocessticks 16), and the shifted ticks
          carrying us more than 64 units -- the lag-comp break rule the
          enemy SHIFT box uses (lagcomp-box-gs). A ground DT at 250 u/s
          moves ~55 u in 14 ticks at 64 tick and draws nothing; fast moves
          (air strafing) do. Harness: no shot, slow, stale shot, DT off,
          another player's shot -- each gate mutation-checked; weapon_fire
          added to the fuzz. Display only, no resolver change.
  v8.29  – vuln_unk forces torso - eye, not the torso world yaw.
          The v8.28 match (29 shots, 8 decided by the resolver: 3 head, 5
          resolver misses) is too small to blame on v8.28 by itself, and its
          other changes rarely touch a forced value. What every session since
          v8.15 shares is vuln_unk: 36% head vs resolver miss (10/28), every
          other method ~68% (p 0.01), 45 of 59 values beyond 60 deg. Those
          values are the torso's world yaw -- the player list clamps them to
          +-60, so the side and size came from which way the enemy faced on
          the map. v7.2-7.9 forced torso - eye (59%, 17/29); v8.0 reverted it
          with the rest of v6.2. The v8.28 roadmap made "under ~50% in the
          next logs" the trigger to retry it; it's ported line for line from
          v7.9 as FEATURE.UNK_DELTA (no window when the eye is unreadable),
          off in the parity run. Harness: torso 150 / eye 100 forces +50
          (v6.2: 150), mutation-checked.
  v8.28  – Resolver-logic bug hunt. Three v6.2 defects, each behind a FEATURE
          flag (off in the parity run) with a harness test that also runs
          the flag-off v6.2 path to prove it still reaches the defect.
          FIXED (STALE_WINDOW) -- a released enemy's shots carried the last
          forced method. ClearEnt (STATIC AA, confidence below 0.20, a stale
          record) released the player list but kept last_meth / last_val,
          and the vuln window only counts down on processed records, so it
          stayed "open" while released, dead or dormant. In the new log all
          8 shots at aa=static enemies were labelled hit_mem (5) or
          vuln_lby in-window (3) with nothing forced; across all logs 27 of
          ~630 in-window shots repeat a window's exact value more than 10 s
          later (one 65 s, across a round). Those shots fed vuln / cheat
          trust and skipped the flip as if our angle had missed, instead of
          counting toward the builtin-miss takeover. Now: a release labels
          the player builtin, a shot is in a window only if the window is
          what we force (vuln trials counted on the same test), a record
          more than 64 ticks after the last closes the window, and the aim
          policy's "in doubt" (two resolver misses -> safe point) no longer
          waits on a frozen window.
          Same defect at the start: a new record was labelled "ring", so a
          shot before our first decision (8 in the logs, all val=0 -- ring is
          never forced) counted as ours. It starts as builtin now.
          FIXED (DCK_GAP) -- a duck-crossing window could open without a
          crossing. Records not sampled (stale > 2 ticks, no animstate)
          saved duck 0, and first sight read nil as 0, so an enemy already
          crouched "crossed" 0.5 on the next sampled record and got the
          torso yaw forced for 11 records. Skipped now, and logged (verbose)
          so the next logs can count it.
          FIXED (CFG_CADENCE) -- config recognition ran when simtime % 32
          == 0, which an enemy sending records on a fixed even cadence can
          never land on (every 2 ticks on odd ticks: never); it stayed on
          the fallback L/R table. Now every 32 sim ticks since the last run.
          log_report: "LBY WINDOWS BY AA TYPE" -- on 3/5-way the centre pass
          reads as an LBY snap (LBY fires on 18-20% of corrections there vs
          6% on hold); head rate 59% vs 56% other vuln, so no change yet.
          Checked, no change (the numbers say so):
          - hit memory taught by a vuln head hit: 26% vs 60% head looked
            bad (p 0.007) but was aim mix -- on head-aimed shots 4/8, like
            suppress 5/9 and unk 21/36. Teaching hits on opposite sides:
            22/24 hit. Suppress-taught: 2/6, too few.
          - vuln windows by age: 72-79% from 0.1 s to 1.6 s+, although
            they last 11 records (2.6 s on a fakelagger), not 200 ms.
          - skitter never sticks (a phase-locked pattern match, ~750 flips
            to/from 3/5-way); after a resolver miss it hit 11/11 head, so it
            stays out of the x-way safe point.
          - velocity spikes zero the VelCap correction for a tick (1 in ~400
            cap reads); no v8 shot fired on one.
          - vuln abs-angle values (the v7.2 delta fix, reverted with v6.2):
            raw <=7.1 65% (277), delta 7.2-7.9 59% (29), raw 8.x 71% (75).
            The new log's vuln_unk is 38% (6/16, 21 of 25 beyond 60 deg) --
            the one to watch.
          - a double tap whose first bullet hits can turn the second miss
            into "server hit": 2 cases in all logs.
          - META_HOLD brute-forces per tick, not per miss: never logged.
          - every vuln window is 11 records (lc_ttl), so base_ttl and the
            +1 boosts are dead at 64/128 tick.
  v8.27  – Bug hunt, continued.
          COVERAGE GAP closed -- the hostile fuzz world never fired
          bullet_impact, player_hurt, run_command or predict_command, so the
          shot log's impact matching, the grenade lines, the local LC box
          and our own-shift tracker had never seen random or broken input.
          The fuzz now fires all four every run: impacts from us and others
          with NaN / inf / missing coordinates, hurt events with odd weapons
          and values, and our tickbase jumping both ways, NaN included.
          FIXED -- a NaN tickbase as the first read of a life made the local
          LC tracker's max NaN; every later comparison failed and the box
          stayed dead until death. The own-shift tracker (predict_command)
          took a missing tickbase as 0. Both now skip unreadable values.
          Clean under the extended fuzz: seeds 1-8 in check_all plus 24
          fresh seeds, both runtimes, identical writes; 200k-tick soak flat.
          Harness: the fuzz phase no longer leaves its tickbase offset (NaN
          at times) to the unit tests after it, which failed 2 of the first
          24 fresh seeds.
          Checked, no change: after a hit-memory miss the next hit-memory
          shot repeats the sign 4/8 head, switches 4/4 -- 15 shots, too few.
  v8.26  – Bug hunt.
          FIXED -- our own shift (brk.def, read by WeDefensive / LCTicks)
          never went back to 0 once the tickbase caught up: after one
          defensive / DT shift it kept its last value, and LCTicks kept
          adding up to 13 phantom ticks to the lag-comp lookup until we
          died or hit someone. In v6.2 too, so FEATURE.DEF_RESET, off in
          the parity run.
          FIXED -- a debug log left as zero bytes by a crash mid-write was
          read back at load and rewritten at the top of every later log
          (the uploaded 106 KB log was nothing but zeros); most viewers stop
          at the first zero, so the log looked empty. Zeros are dropped at
          load and the drop is logged.
          FIXED (boxes only) -- ExtrapolateOrigin traced with skip -1 (could
          stop on the player's own hull), at foot level (a stair froze the
          box), and lifted standing players by sv_jump_impulse * ti per
          tick. Now skips the player, traces at step height, keeps standing
          players on the ground.
          FIXED -- the enemy SHIFT box stayed up to 1 s on a record that
          arrived late or without animstate (the origin history is dropped
          there; now the box is too).
          Checked clean: all 17 event names, the 3 menu references (Menu
          color, Double tap, Force safe point), all 15 netvars, every
          variable division. Fuzz, fresh seeds, both runtimes, identical
          writes: 64 x 60k ticks on v8.25, 32 x 20k on v8.26.
          Lead, not changed: hit memory taught by a vuln head hit lands 51%
          (22/43) when its forced value's sign is opposite to the teaching
          hit's, 66% (21/32) when the same (p ~0.24); suppress logs side and
          value with opposite signs (99%), hit memory with the same (95%).
  v8.25  – Enemy SHIFT box drawn live, as lagcomp-box-gs does: while the
          enemy's last record broke lag comp, every frame at their current
          origin carried forward by that record's gap, gone as soon as a
          normal record arrives (1 s safety timeout). It was computed once
          per break and left in the world for a 0.5 s fade, so it trailed a
          moving enemy and outlived the break. Decision side
          (_shift_streak) unchanged; parity exact.
  v8.24  – Local LC box leads instead of trailing: it was fixed in the world
          at the moment the shift was seen, so we walked past it and it sat
          behind us for its half second. Now every frame it's drawn at our
          current origin carried forward by the shifted ticks, back or
          forward shift alike.
  v8.23  – FIXED -- Double tap was looked up only under RAGE > Other; current
          gamesense keeps it under RAGE > Aimbot (~660 public scripts vs
          ~280), so DtReady was always false: the local LC box (v8.21+)
          never fired, and the weapon aim policy's double-tap case never
          applied. Now Aimbot, then Other, logged at load.
          Local LC box no longer reads the DT menu at all: only double tap
          shifts the tickbase. Catches both directions -- tickbase back
          below its max (defensive / recharge, box extrapolated by the
          ticks) and a forward jump of more than one tick between commands
          (the teleport, box where we landed).
  v8.22  – Local LC box: with double tap on a toggle key the shift lands at
          the switch, when the key already reads off, and v8.21's "double
          tap on" gate dropped it. It now flashes while double tap is on or
          was on within the last second.
  v8.21  – Lag-comp boxes, simpler, and a bug hunt.
          LOCAL box: double tap only. It flashes when double tap is on (key
          held, AIMX.DtReady) and the tickbase is shifted > 2 ticks; the
          fakelag trigger (setup_command, sent records > 64u apart) is gone
          -- it was most of what the box showed. Labelled with the shifted
          ticks.
          Both boxes red (240,64,64): the local LC box and the enemy SHIFT
          box, label and tether.
          FIXED -- df= (defensive frames before a shot) counted one frame on
          every net update while the enemy choked inside its defensive
          window: rec.lt stays on the last real record, so the same lower
          simtime came round again each update. Each frame now counts once.
          Measurement only; old logs' df= read high when it was choked.
          Bug hunt otherwise clean: no remove-while-iterating, player-list
          cache resyncs every second, 48 fresh fuzz seeds x 2 runtimes.
          Harness: the shot-log test no longer inherits a NaN / inf eye from
          the fuzz phase; an infinite eye prints no angle (isnum already
          rejects it); DT off / on, re-flash, expiry, option off and red for
          both boxes; mutation-checked.
  v8.20  – Lag-comp boxes fixed.
          ENEMY SHIFT box (and the lagcomp distrust streak it sets) fired on
          bots: the origin-jump check compared a new record with the last
          one however old -- a bot moved to its spawn at round start, or
          anyone back from dormancy, read as a > 64u lag-comp break. Now
          (FEATURE.SHIFT_GAP, off in the parity run) only records 2-64
          ticks apart count, as lagcomp-box-gs does, and the move must be
          one sv_maxvelocity (3500) allows in that gap.
          LOCAL box showed nothing on double tap: it only watched sent
          fakelag records. Added the tickbase check the public defensive
          indicators use (run_command, max m_nTickBase - tickbase - 1, over
          2 = shifting): it flashes our origin extrapolated by the shifted
          ticks for 0.5 s, "LC 9t". The fakelag trigger stays (now also
          bounded by the reachable distance) and flashes the same way.
          Harness: bot teleport vs 15-tick fakelag break (enemy); tickbase
          shift, fakelag break, no break, one-command teleport, re-flash,
          expiry, option off (local); mutation-checked.
  v8.19  – Local lagcomp box only when lag compensation is actually broken
          (two sent records > 64u apart). v8.18 also drew an amber box
          whenever the record trailed us, i.e. on any choke.
  v8.18  – Local lagcomp box (Indicators > Local lagcomp, on once). The
          repo's lagcomp box scripts (lagcomp-box-gs and copies) box
          enemies only; this is ours. setup_command with chokedcommands 0
          = the previous command was sent: our origin then is the server
          record. Drawn as our hull there with a tether to where we stand;
          amber with distance and choked count while it trails, green
          LAGCOMP when two sent records are > 64u apart (4096 squared,
          the enemy marker's check). Hidden on us (< 2u) or after 1 s.
          Harness: trailing, 30u step, 100u break, expiry, option off;
          mutation-checked.
  v8.17  – Shot log printed with print(), as the original "[MISC] aimbot
          log" does, so gamesense shows it in the console AND the top-left
          corner like its own logs; v8.16 used client.color_log. Plain
          text, the original's look; the content is unchanged. Harness:
          output captured from print, one string per line, color_log
          flagged. A top-right on-screen box was built and dropped: the
          top-left is where gamesense logs go.
  v8.16  – Console shot log (Indicators > Shot log, on once by default),
          in the format of the public "[MISC] aimbot log":
            [217] [244/251] Missed x's head(98)(76%) due to resolver:0.03°
            · RIFTVEIL vuln_lby -24° [aa=5way | cf=62% | cht=nl | streak=1
            | next=sp | lc=0 | tc=1]
          plus Hit lines and "Naded / Burned / Knifed x for 34 damage".
          Extended with what RIFTVEIL did: who resolved the target, read
          from the player list at fire time (RIFTVEIL + method + forced
          yaw, GAMESENSE resolver, or NO RESOLVER when correction is off;
          red on the one that missed), AA type, confidence, cheat, aim
          policy, safe point, the run of resolver misses and next=sp when
          the aim policy goes to safe point. AIMX.InDoubt is now the single
          definition of "side in doubt" for the policy and the log.
          FIXED vs the original -- the spread angle matched the impact by
          tick (missing whenever impact and result land on different
          ticks); each shot now claims its own impacts, wall penetrations
          included, so double-tap bullets don't mix.
          Console only: the debug file and log_report are unchanged.
          Verified: with the logger on through a 20,000-tick fuzz world,
          the player-list writes are byte-identical to v8.15 (the fuzz
          counts in check_all moved only because the new menu item and
          reference shift its random stream). Harness: spread, resolver
          through a wall, double tap, hit, gamesense / no resolver, late,
          server hit, grenade, option off, every color_log call checked;
          mutation-checked.
  v8.15  – AA-script patterns, applied: 3-way / 5-way after a resolver
          miss. x-way (57% of neverlose AA scripts, 24% of gamesense) and
          anti-bruteforce (59% / 36%) ship together; joining every pre-v8
          shot to the AA type on the debug log's last [corr] line:
          - next head shot at a 3/5-way enemy within 10 s of a resolver
            miss on them: 43% (25/58), vs 59% for the same enemies
            otherwise and 77% for other AA after a miss (p 0.023 / 0.001;
            9 of 12 logs at or under 50%; 75% again after 10 s).
          - no side choice fixes it: kept 32%, flipped 48%, hit memory
            3 of 16.
          - by AA type overall: 5-way 56%, 3-way 59%, hold 69%, 2-way 75%,
            skitter 79%.
          - anti-bruteforce reset timers by family: 600 ticks (9.4 s, one
            family x10 copies), 5 s, 3 s, 2 s, 1 s, 0.5-1.1 s.
          ADDED -- FEATURE.XWAY_UNSURE: such an enemy counts as "side in
          doubt" for the aim policy (safe point on the head; safe point when
          nothing kills). Vuln windows don't exempt it (40% there). The
          forced body yaw is untouched; v6.2 parity unchanged.
          ADDED -- aa= on every shot line; log_report BY AA TYPE and 3/5-WAY
          AFTER A RESOLVER MISS ON THEM (falls back to [corr] aa= on older
          debug logs). Harness: window, 5-way, hold, flag off, hit, spread
          miss, aa= on the miss line.
  v8.14  – Repo pass: player-list field and enemy-prop inventory
          (REPO_SURVEY 6b). The LBY target is read by 191 scripts, 262
          times as sign(eye - LBY) = desync side; RIFTVEIL never read it.
          Not adopted (an LBY update sets the target to the eye yaw), but
          now logged per shot as lbyd=, and log_report BY EYE - LBY DELTA
          vs OUR FORCED SIDE says whether it carries side information.
          "Override simulation time" / "Override hitbox" exist only in one
          machine-written script -- not used. On-shot / teleport /
          extrapolated: 0 of 149 v8.x shots.
  v8.13  – REMOVED the StarSync movement features (v8.9): Fast ladder and
          Jumpscout hit chance, with their menu rows, setup_command
          callback and harness tests. Includes v8.12.1 below.
  v8.12.1 – Correction magnitude checked within method: the "small values
          hit less" dip (51% vs 64%, p 0.053) is a method-mix effect --
          vuln_lby 50% vs 56%, vuln_unk 53% vs 59%, vuln_dck 75% vs 78%
          below / above 20. No change. log_report: BY FORCED VALUE PER
          METHOD.
  v8.12  – Neverlose deep dive (docs/REPO_SURVEY.md section 5).
          117 unique NL scripts (108 AA), 18 with built-in presets, 215
          settings files (152 decode; the angelwings MessagePack exports
          are mangled in most files). Findings:
          - The desync limit is at 58-60 in nearly every preset state and
            in players' settings (median 60); yaw offsets are asymmetric,
            right > left, matching the asymmetric table.
          - New presets either sit inside the luasense bands (gated to nl /
            undetected since v8.10) or form a low-offset family (~10/20).
            Not added: forced values under 20 are the weakest band in all
            logs (51%).
          - NL defensive = hidden yaw / pitch overrides (309 / 287 calls),
            visible only on the frames v8.10 skips.
          - NL anti-bruteforce: 28 scripts, bullet impacts 25 / player_hurt
            12, radius 50-70 (gamesense 100). Corrects the v8.11 file-level
            count, which mixed in unrelated player_hurt handlers.
          - No NL script adapts its AA to the enemy's cheat.
          ADDED -- log_report splits BY PREVIOUS SHOT AT THEM by enemy
          cheat (e.g. "nl after a head hit").
  v8.11  – Survey of s0daa/CSGO-HVH-LUAS (docs/REPO_SURVEY.md).
          1,371 readable unique gamesense Luas (569 anti-aim), ~45
          distinct readable resolvers, 115 neverlose AA scripts, 617
          settings exports. Findings, all counted by script:
          - "Correction active" = gamesense's resolver: every resolver
            that hands a player back sets it true (8 more distinct sources).
          - Our jitter-side method, animstate struct and live desync cap
            match or beat what the resolvers use; the "animlayer resolver"
            in vandal / Cartel fills its slots from its own guess.
          - The library cheat revealer is byte-identical to ours.
          - AA meta: delayed jitter 81%, defensive 75%, anti-bruteforce
            36% (gamesense) / 59% (neverlose), x-way 24% / 57%.
          - Anti-bruteforce triggers on our bullet passing within ~100
            units (hit or miss), reacts mostly by changing jitter / limit,
            resets after 1-5 s. Reconstructed from the v8.8 log: shots
            within 5 s of our last at the same player 6 head / 0 miss,
            later ones 19 / 12 -- no cost seen.
          - No gamesense AA script ships an embedded preset; no new
            config fingerprint to add.
          ADDED -- ls= (seconds since our previous shot at that player)
          and prv= (its outcome) on every shot line; log_report BY TIME
          SINCE OUR LAST SHOT AT THEM and BY PREVIOUS SHOT AT THEM.
          Measurement only.
          CANDIDATES (ROADMAP Next): force pitch on a pitch breaker,
          hit memory inside the anti-bruteforce window, freestand side.
  v8.10  – First match log on v8.x, and the luasense correction.
          LOG (v8.8, 43 resolver-decided shots): head rate 70% (30/43,
          95% 55-81%) -- back at v6.2's 74% from v6.7-v7.9's 49%. Aim
          policy values all accepted; trace calibration x1.00; cheat
          revealer detects gs and nl; seeded start 86% vs cold 60%.
          FIXED -- luasense presets went to the wrong cheat. The
          luasense_beta table is the built-in preset of the NEVERLOSE
          luasense beta, all 7 states exact (s0daa/CSGO-HVH-LUAS,
          Neverlose/lua/luasense beta.lua: standing 24/41 ... slowmotion
          23/47); the gamesense luasense builds in the same repo ship no
          built-in presets and contain neither number. v8.0 gave the
          presets to gamesense users only. Now: luasense_beta/std for nl
          and undetected players, never another detected cheat;
          "symmetric" (a desync shape) for everyone. In the log, a gs
          player was being read as luasense_beta/std and nl players were
          denied their symmetric table. Harness: 8 cases, fail on 8.9.
          CHANGED -- defensive frames skipped (FEATURE.SKIP_DEF_FRAMES,
          on). A frame below the highest simulation time already received
          is not sampled: lag compensation keeps no record of it, and
          lagrecord skips it the same way. Before, it reached the pose
          history, the yaw cache and, on unrecorded ticks, the lag-comp
          table. The log: 86% (18/21) with 0-8 such frames in the second
          before the shot, 55% (12/22) with 9+ (Fisher p 0.045, 4 of 5
          players). Modest evidence on one match with three independent
          sources for the mechanism; one word reverts it, and df= keeps
          measuring. The v6.2 parity run turns it off (decisions with the
          post-v6.2 features off are still exactly v6.2's: 342/342).
          Harness: no out-of-order sample in the pose history (3 on 8.9).
  v8.9   – Movement from StarSync (a neverlose script), ported to gamesense.
          ADDED -- Fast ladder (checkbox, off by default). The logic is the
          one shipped identically in two gamesense scripts (angelwings,
          abyss): pitch 89, sideways buttons, yaw +90 / +30 / +150 by
          strafe. From StarSync: not while a grenade is thrown
          (m_fThrowTime), not while holding +use. Harness: up, down+right,
          grenade, +use, off-ladder and switched-off cases.
          ADDED -- Jumpscout hit chance (slider, 0 = Off). Airborne with the
          SSG 08, RAGE > Aimbot > "Minimum hit chance" (the reference three
          uploaded gamesense scripts use) is set to it; the user's value is
          restored on landing, weapon switch, Off, death and unload.
          StarSync's version only switches neverlose's SSG Auto Stop to
          "In Air", a menu gamesense doesn't have. Harness: air 30, landed
          back to 70, AWP in air untouched.
          Both are independent of the Resolver switch; neither touches the
          resolver, the player list or v6.2 parity.
          NOT PORTED: teleport ladder exit (neverlose double-tap uncharge
          internals), no fall damage (needs a hull trace; gamesense has
          trace_line only, and a centre-line trace mistimes the landing on
          edges), super toss (needs neverlose's grenade_override_view and
          movement simulation), StarSync's own dormant aimbot (separate
          script territory; dormant_aimbot.lua already exists for gs), and
          the visual / AA builder parts (not this script's job).
  v8.8   – Explore tickcount's projects (github.com/tickcount).
          FIXED -- "Correction active" was inverted. It is gamesense's
          own resolver for a player, on by default: vandal turns it off
          while its resolver runs and ON to hand the player back, tsv4
          turns it off for bots, angelwings keeps it on, tickcount's
          Eagle ESP reads it as "FAKE". Every RIFTVEIL version, v6.2
          included, set it OFF when "releasing to the built-in", in round
          resets, when switched off and at unload -- so a released player
          had no resolver, and turning RIFTVEIL off (to compare, say)
          left gamesense's resolver off on all 64 slots. Releases now set
          it on. Forced shots are unchanged (on, as before) and the v6.2
          parity check (forced side and value) is unchanged. Only 15 of
          the logged shots were "builtin", so match impact is small; the
          after-effects were not. Shots log cor= (1 / 0 / ?), log_report
          BY GAMESENSE CORRECTION ACTIVE. Harness test fails on 8.7.
          ADDED -- primordial detection, ported from tickcount's
          voice-listener.lua (by the cheat revealer's author; the revealer
          we ported names primordial but never detects it): a non-reliable
          packet with the 0x4D mark carrying the sender's own entindex,
          13+ within 120 s (the library trusts 5). The loose gamesense read
          also fires on those packets, so it may not replace a primordial
          label. FFI tests: detected, stable over 1500 packets, not on
          other senders' or reliable packets, 20000 random packets clean.
          VERIFIED -- our animstate struct matches antiaim_funcs.lua field
          for field; lagrecord skips backward-simtime frames and drops
          records on a 4096 sq-unit origin jump (our threshold too).
          NOTED -- 0xAFF1 is pandora in voice-listener (2022) and airflow
          in the uploaded revealer (newer); kept as airflow. Both are
          non-gamesense, so presets and decisions don't change.
          Not ported: gamesense's shared-ESP check (runs shellcode via
          VirtualAlloc), nixware/spirthack (need a bit reader over the
          voice payload), the p2c icon set (would need textures in the
          panel; the ESP flag stays text).
  v8.7   – Explore 2: the API, the meta, indicators.
          META, located in code: lag compensation writes no record while a
          player's simulation time is at or below the highest it sent
          (tickcount/lagrecord-csgo.lua, which detects defensive exactly
          this way). Defensive AA frames therefore arrive with a lower
          simtime -- and ProcessPlayer samples every simtime change,
          backwards ones included, into the pose ring (v6.2 core). Now
          counted per player (measurement only, no decision reads it) and
          logged per shot as df= (frames in the last second); log_report
          BY DEFENSIVE FRAMES. The one-line skip waits on that data
          (ROADMAP 5). Harness test: backward frames counted; the scripted
          in-order match logs df=0 on every shot.
          META: our own defensive read (brk) is the public pattern verbatim
          (same code in the unnamed AA script and lagrecord's README).
          API: client.current_threat is the "At targets" AA enemy, not the
          ragebot's target. get_esp_data().flags bit 11 is read by two
          uploaded scripts as "this enemy can hit us" -- not a resolver
          input. trace_bullet returns nil entindex when no player is hit;
          tsv4 scales damage only then, which corroborates that traces
          ending on a player are already final (WEAPON_PLAN).
          INDICATORS: client.draw_hitboxes (entindex, duration, hitbox list,
          colour, tick) with aim_fire.tick could show the record each miss
          was fired at; left out to keep the UI lean -- say if you want it.
  v8.6   – Explore: the API, the meta, indicators.
          API (docs.gamesense.gs events/aim_fire): every shot carries
          teleported ("breaking lag compensation"), extrapolated,
          interpolated, boosted and high_priority. RIFTVEIL read none of
          them. Now logged on every shot line as fl= (t x i b p, plus d =
          our defensive-tickbase read on the target), and a teleported or
          extrapolated shot no longer feeds the cheat profiles or the aim
          policy's miss run (no side information in it). The v6.2 core
          still sees every shot, as it did. Harness test fails on 8.5.6.
          META: every AA script uploaded has a defensive AA mode (pitch
          up / zero / random, yaw sideways / spin / n-way during the
          tickbase shift). The enemy's eye pitch at fire is logged as pit=
          (-999 = unread) so the next log shows whether misses cluster on
          defensive frames; the fix waits for that (ROADMAP 5).
          INDICATORS: ESP flags now show the aim policy on each enemy
          (BODY / HEAD / HEAD SP / SAFE PT; nothing at ragebot default);
          the panel shows it only for the threat. Harness-tested.
          log_report: BY SHOT FLAGS, BY ENEMY PITCH AT FIRE.
  v8.5.6 – Explore / verify pass 6: v6.2 core internals, logging.
          FOUND, NOT CHANGED (v6.2 decisions, data first): the saved hit
          rate divides head hits by head hits + a miss STREAK (reset on
          every hit), so it reads near 100% and every player with 3+ hits
          starts the next match at the 0.35 seed. The 74% was measured
          with it. New: the "new profile" line logs seed=, and log_report
          has BY PROFILE START (seeded vs cold start) to decide it.
          FOUND, NOT CHANGED: "Tight interpolation" sets cl_interp 0.031,
          ratio 1, so lerp = max(0.031, 1/64) = 31 ms -- the default lerp,
          not a lower one (Source: GetClientInterpAmount). Every uploaded
          log, the 74% ones included, ran with it on; it stays as is.
          FOUND, NOT CHANGED: our defensive-shift reading (brk) keeps its
          last shift until death, a hit or a 64-tick jump. v6.2 core,
          feeds the backtrack window only while "ahead".
          FIXED: rv_stats labelled the miss streak "rmiss", read as a
          total; it says "miss streak" now.
          VERIFIED: 32 more fuzz seeds (9-40, LuaJIT) clean; the Detection
          chain's trust gates key on the same method names the shot log
          credits.
  v8.5.5 – Explore / verify pass 5: saved data and console commands.
          FIXED: rv_wipe left the learned cheat profiles (their own saved
          key) in place; they came back on the next load. It clears them
          now. rv_db lists them (cheat | method=heads/shots), so they can
          be checked without waiting for an autosave line.
          FIXED: a saved cheat id was taken as-is. An unknown one ("zz",
          a hand edit) switched off the gamesense presets for that player
          and showed in the panel. Only the 10 known ids load now.
          Each harness-tested (fail on 8.5.4).
  v8.5.4 – Explore / verify pass 4: cheat-profile crediting.
          FIXED: cheat-profile learning counted every resolver miss
          against the method but only head hits for it, so a body-aimed
          shot could only ever count as a failure. In the v7.7+ logs
          (aim= field) body-aimed shots were 5 of 15 credited misses and 1
          of 7 credited hits while landing 11 of 16 -- a steady push toward
          "skip this method". Only head-aimed shots are credited now, hit
          or miss. Harness test fails on 8.5.3.
          FIXED: the aim policy's "side in doubt" (two resolver misses in
          a row) was only ended by a head hit: miss, body hit, miss still
          counted as two in a row. Any hit ends the run now.
          EXPLORED, NOT CHANGED: "prediction error" misses count as
          resolver misses (v6.2 core, parity). Only 6 in all logs; too few
          to say whether they carry side information (roadmap item 2).
          EXPLORED, NOT CHANGED: calibration is one factor for all weapons.
          If traces leave out armor, the factor would differ per weapon by
          armor penetration; whether it does shows in log_report's TRACE
          CALIBRATION once there are v8.4+ logs, so it waits for data.
  v8.5.3 – Explore / verify pass 3: aim fields, calibration, cheat stats.
          FIXED: trace calibration could be pulled down by lethal shots.
          If the ragebot caps its predicted damage at the target's health
          (the docs don't say), an AWP head on a 100 HP enemy reads 100 /
          448 = x0.22, and after five such shots a 240 wallbang head no
          longer counted as a kill -- the aim policy would drop "head".
          Only predictions below health calibrate now (the script and
          log_report). Harness: 0.22 on 8.5.2, unchanged now.
          FIXED: a player-list set that raised was cached as written (the
          write cache stored the value first), so that field was never
          retried; and the aim field kept the previous value for a tick
          instead of its fallback. Both harness-tested (fail on 8.5.2).
          FIXED: saved cheat stats weren't capped on load: a 0/5e8 entry
          needed ~90 shots of halving before the method could recover.
          Load and credit share one cap (CP.Fit).
          CHANGED: "[cheat] learned" is logged only when a cheat's numbers
          changed, not for every cheat on every 60 s autosave.
          ADDED: log_report BY ENEMY SPEED (mv=), a check on st= that
          doesn't go through the classifier.
          VERIFIED, NOT CHANGED: the Write fallback chain ends (On -> Force
          -> "-", Off -> "-"); the probe cadence (every 4th shot, counted
          at aim_fire); EnemyMaxSpeed costs three prop reads per record.
  v8.5.2 – Explore / verify pass 2.
          FIXED: switching Resolver off mid-round left the last forced
          body yaw and aim overrides on every enemy until the next round
          start (the README said "off releases every player" -- it didn't,
          in v6.2 either). The first update after switching off now hands
          every player back to the built-in, including any entity we ever
          wrote to. Harness test: fails on 8.5.1, passes now.
          FIXED: the info panel's INFO row had no width limit -- up to
          eight tags ran past the 200 px panel. Tags that don't fit are
          dropped whole, warnings (DEF, SPIKE, AGG) ahead of details.
          EXPLORED, NOT CHANGED: v7's claim that v6.2's hit memory learns
          the wrong side after a suppress head hit. In every v5.2-v6.2 log,
          no hit-memory shot followed a suppress head hit (they followed
          vuln windows: 12 head / 5 miss, and hit memory: 4 / 0), so the
          case never arises in the data; v6.2 behaviour stays.
          Parity note: the switch-off release covers the write cache only
          on switch-off; round resets stay on the 64 slots, as in v6.2.
  v8.5.1 – Explore / verify pass.
          VERIFIED against docs.gamesense.gs: aim_fire.damage is the
          predicted damage (the aim calibration's input), hitgroup the
          targeted group; the voice event struct matches the cheat
          revealer's byte for byte (client at 8, xuid at 16); ui.reference
          returns the double-tap checkbox and hotkey, ui.get(hotkey) =
          active; get_players excludes dormant and dead. Scoped max speeds
          (AWP 100, G3SG1 120, AUG/SG 553 150) confirmed.
          FOUND by a new hostile-input fuzz (health, armor, traces, eye
          position, weapon, scope, ground flag -- NaN/inf/nil/wrong entity):
          a NaN/inf hp, armor or trace reached "%d" in the hit/miss log
          line and threw before the shot entry was cleared. Now every
          integer log field goes through LogInt (-1 when not finite).
          FOUND by a new corrupt-profile case: fractional kills / bt_pref
          in the saved DB crashed rv_stats (proved: fails on 8.5, passes
          now). Counters load as integers.
          Coverage: the double-tap aim path, the state tracker and the
          reconnect cheat-reset now run in the harness (auto in hand in
          phase 3, player_connect_full fired). Trace cost measured: ~4
          traces per tick in a 2v2, 8 at most while moving.
  v8.5 – State / condition tracker debugged against movement physics.
          tools/state_test.lua: Source movement physics, CS:GO weapon
          speeds, 15 scenarios x fakelag 1/3/8/14, scored per tick against
          the AA builder's condition, with a ceiling (truth held between
          records). All scenarios: v6.2 76.3%, v8.4 80.9%, v8.5 91.7%,
          ceiling 93.1%.
          FIXED: scoped snipers read as slow walk (AWP scoped 69 -> 92%):
          thresholds follow the enemy's weapon and scope, run above 40% of
          max speed; heavy fakelag hid a run's start; fake duck flickered
          (55 -> 92%), now held as crouch; an unreadable ground flag meant
          "in air" (0 -> 91%); no speed change after a gap defaulted to
          slow walk; velocity that never reads falls back to origin speed
          after 2 records (a single zero is a real stop -- the first cut
          of this fired on real stops, the test caught it).
          The tracker has its own section (STATE TRACKER) and speed
          history; shot lines log mv=; the debug log gets a [state] line
          per change. v6.2 parity unchanged with the feature off.
          Harness: the mock origin now moves with velocity. Details:
          docs/STATE_AUDIT.md.
  v8.4 – Weapon aim decided on traced damage.
          v8.3 read nominal chest damage ("AWP: prefer body always"),
          which is wrong whenever the body shot can't kill from where you
          stand: a wallbang, a body behind cover, a head-over-box peek.
          Now, per enemy: client.trace_bullet from your eye (and 4 ticks
          ahead while moving) to the head and to pelvis/stomach/chest --
          the method the public gamesense scripts use.
            body shot kills (two with a charged DT on auto/deagle/pistol)
              -> prefer body On
            only the head kills -> prefer body OFF for that enemy, so a
              global prefer body can't trade a lethal head for a
              non-lethal body; + safe point when our side is in doubt (2
              resolver misses in a row) or the enemy is airborne
            nothing kills -> ragebot default (+ safe point if in doubt)
          Every player-list value is read back on first use and falls
          back if the game rejects it (body On -> Force -> -, Off -> -).
          Trace scaling self-calibrates against the ragebot's predicted
          damage (median of 15 shots, applied after 5). Shot lines log
          tr=head/body; log_report prints TRACE CALIBRATION; the panel
          shows BODY / HEAD / HEAD SP / SAFE PT.
          Research and sources: docs/WEAPON_PLAN.md. Tests: 12 decision
          cases (AWP open vs wallbang, head over cover, scout full vs 70
          HP, auto with/without DT, safe point, airborne), calibration,
          and the rejected-value fallback.
  v8.3 – Weapon aim policy, built (Detection › Weapon aim, on once).
          v8.2 only logged weapon data and probed the fields; this acts.
          PREFER BODY when one body shot kills: enemy HP <= our weapon's
          chest damage after armor, minus 8% for range falloff. AWP
          always, scout <= 68 HP, R8 <= 73, auto <= 60, deagle <= 53,
          pistols <= 22. A lethal body shot doesn't depend on the desync
          side; a head shot does.
          SAFE POINT after two resolver misses in a row on a player (reset
          by a head hit only), outside vulnerability windows: two misses
          say our side is wrong, and safe points hit whatever the side.
          Otherwise the ragebot's own per-weapon config. Head is never
          taken away: only "prefer" and "On" are written, never "Force".
          FIELDS verified at run time: the first "On" written is read
          back; a missing field or different value switches the policy
          off for the session and logs why ([aim] lines).
          Shot lines log pol=; the panel's INFO row shows BODY / SAFE PT;
          log_report adds BY AIM POLICY (overall and per weapon).
          Tests: 10 policy cases (every weapon, armor, miss streak, vuln
          window); the harness now holds an AWP, checks writes are only
          "-" or "On"; its bit.band mock handles real masks.
  v8.2 – Progress saved; condition detection, speed, weapon data back.
          SAVED: versions/ holds v6.2, v7.9 and v8.1 as files (the git
          proxy refuses tags); docs/ROADMAP.md lists every feature, what
          is waiting on a log and what comes next.
          CONDITIONS: v7.5's physics-based ClassifyState is back as
          FEATURE.STATE_PHYSICS (on): slow walk is no longer read during a
          run's acceleration or braking, crouch-move starts at 5 u/s.
          Unit-tested against Source movement physics every run.
          SPEED: player-list fields are written only when they change
          (harness: 3552 -> 1124 writes, -68%), update_player_list runs on
          a new enemy or once a second instead of every tick, and
          get_players(true) replaces the per-player enemy/alive checks.
          rv_perf is back (QueryPerformanceCounter per callback).
          WEAPONS: every shot logs wpn= hp= ar= aim= pdmg= cf=; the first
          shot of a session probes the player-list aim override fields
          and logs them ([aimfield]) -- step 1 of docs/WEAPON_PLAN.md.
          Backtrack read in ticks or seconds (v6.2 logged bt=64+).
          PROOF: check_all step 7 runs with FEATURE.STATE_PHYSICS off and
          still matches v6.2 on all 342 forced ticks, 0 opposite.
  v8.1 – The v7.9 menu and info panel are back.
          v8.0 took v6.2's file whole and brought its old menu and panel
          with it. Now: the v7.9 six-row menu (Resolver, Detection,
          Tight interpolation, Indicators, Debug log), the v7.9 info panel
          with drag and eased height, VLN/RES flags, SHIFT marker and the
          Menu color accent, on top of the v6.2 decision code. Detection's
          fourth option is now "Cheat profiles" (replaces Adaptive engine,
          added once to existing selections). Suppress and asymmetric
          angles fixed on, jitter prediction off, as v6.2 ran in the logs.
          rv_save is back. v6.2 parity still exact: 342/342 forced ticks,
          0 opposite, 0 magnitude difference.
  v8.0 – Back to the v6.2 resolver; cheat revealer built in; per-cheat
          resolving.
          WHY: across every uploaded log, resolver-decided shots hit the
          head 74% of the time on v5.2-v6.2 (100/135, 10 of 10 opponents
          at 57% or better) and 49% on v6.7-v7.9 (54/111, 9 of 12 at 60%
          or worse), v7.9 alone 32%. Every method dropped. v6.3-v6.7
          changed vuln values, the desync cap and 6lex confidence; v7.x
          added the engine, turned off the miss flip and changed hit
          memory. No single change can be proven guilty from the logs, so
          the whole decision path goes back to v6.2.
          KEPT FROM LATER (no decision changes): bounded NA (inf froze the
          game), type-checked latency read, %.0f steam ids, DB entries
          validated on load, DB autosave no longer re-adds the match, DB
          capped at 500 profiles, rec.tm pruned by age (leak), bounded
          logger (512 KB roll, flushed every round and autosave), every
          callback in an error guard, NaN/out-of-range yaw never written,
          backtrack ticks range-checked, st= and cht= on shot lines.
          PROOF: tools/check_all.sh step 7 -- on the harness match v8.0
          forces the same side with the same value as v6.2 on every tick
          v6.2 runs (352/352, 0 opposite); the extra ticks are ones where
          v6.2 itself crashes.
          CHEAT REVEALER built in: the voice-packet detectors from the
          cheat revealer script (gs, nl, nw, pd, ot, ft, pl, ev, r7, af),
          ESP flag, panel line, saved per profile.
          tools/cheat_detect_test.lua checks them on real FFI packets.
          CHEAT PROFILES: gamesense Lua AA presets apply to gamesense
          users only; per (cheat, method) head hits and resolver misses
          are learned across players and sessions, and a method at <= 30%
          after 8+ shots against a cheat is skipped for it (probed every
          4th shot). Unknown cheat: exactly v6.2.
          REMOVED: the decision engine, its cheat layer, engine_sim,
          cheat_sim (and, by mistake, the v7 menu and panel -- back in
          v8.1).
  v7.9 – Enemy-cheat engine layer; vuln windows scored on real evidence.
          LOG: the v7.6 match (51 shots) hit the head on 42% of
          informative shots vs ~63% over all earlier logs. Two opponents
          account for it (2 heads / 11 resolver-decided shots), both on
          jittering 5-way/3-way AA, mostly through vuln_unk and suppress.
          Window age (0.2 s vs > 1 s since detection) showed no effect,
          so the window length stays.
          FIX: vuln_profile scored every shot in a window as a trial and
          every hit, body included, as a success -- body hits land from
          either side, so the per-player trust gate could never fire.
          Now only an applied window's head hits and resolver misses
          count; the unk miss streak follows the same rule.
          CHEAT LAYER: with the cheat revealer script loaded, each
          enemy's cheat id (read from its gamesense/cheat_revealer
          module once a second) keys a new engine level between global
          and player, pooled over every player on that cheat and saved
          (riftveil_engine_cheat); 6 same-cheat votes let an arm act on a
          player with no shots yet. Cheat saved per profile. Shot lines
          log cht=, log_report adds BY ENEMY CHEAT, rv_engine lists the
          layer. tools/cheat_sim.lua: +0.4 points when the cheat decides
          the AA, +0.15 on average across worlds, worst -0.01.
  v7.8 – Per-weapon aim policy: model and data, no behaviour change.
          tools/aim_model.lua derives when head, head-on-safe-points or
          prefer-body kills fastest, per weapon, enemy HP, body exposure
          and resolver certainty, with kills discounted when the enemy
          shoots back. Head stays available everywhere; body wins only
          when lethal within the peek and exposed; head vs safe points is
          decided by the ratio of their hit chances, which must be
          measured. Shot lines now also log the ragebot's aimed hitgroup
          and predicted damage (aim=, pdmg=); log_report breaks weapons
          down by aimed hitgroup. Plan rewritten: docs/WEAPON_PLAN.md.
  v7.7 – Logs that contain the match; weapon data for per-weapon aim.
          The first v7.6 log sent in held no shots: the log reached disk
          only every 2048 lines or at match end, so a match with Debug
          log off stayed in memory. Now also flushed at every round start
          and with the 60 s autosave.
          Every [hit]/[miss] line now records the local weapon class
          (wpn=awp|scout|auto|r8|deagle|pistol), and the target's health
          and armor at fire time (hp=, ar=); log_report adds BY WEAPON.
          Plan for a resolver-driven per-weapon aim gate:
          docs/WEAPON_PLAN.md (not implemented yet).
  v7.6 – FPS hotfix + in-game profiler. Reported: 100-200 fps lost.
          GUARDS: every callback now runs inside a pcall wrapper that logs
          an error once (then every 1000th), so an error can no longer
          repeat into the console every frame -- paint had no guard at
          all, and Update logged every failing tick without a limit.
          PER FRAME: threat read once per tick instead of every frame;
          panel position re-read only while the menu is open (or every
          2 s); drag input (mouse, key) only read with the menu open; the
          panel text rebuild throttled from every tick to ~16 Hz. API
          calls per paint frame 38.4 -> 34.5 (mock count).
          DISK: log file cap 1.5 MB -> 512 KB, bounding each synchronous
          rewrite of the log.
          PROFILER: rv_perf (run it, play ~10 s, run it again) prints
          calls/s, average and max microseconds and errors per callback,
          timed with QueryPerformanceCounter through the FFI.
  v7.5 – Enemy state detection audited against the AA builders
          (docs/STATE_AUDIT.md). Builders pick slow walk by key; we read
          it from a 5-100 u/s speed band, which also caught every runner
          accelerating into or braking out of a peek (38% of a rifle
          peek-and-stop, by Source movement physics). ClassifyState now
          uses the speed change per tick (fakelag-normalized): gaining
          > 10 u/s/tick is a run, braking keeps its state; misread peek
          ticks 18-19 -> 1, a real slow walk unchanged. Crouch-move
          threshold 20 -> 5 u/s (builders: 2 / 3.63 / 10). Movement state
          on every [hit]/[miss] line (st=) and a per-state table in
          tools/log_report.lua. Physics-profile regression check added.
  v7.4 – Bug hunt, engine interplay, ProcessPlayer split.
          ENGINE INTERPLAY: the chain's own adaptive habits fought the
          engine. Under Adaptive engine the legacy flip no longer inverts
          the tracked side, and the soft reset no longer wipes hit memory
          or engine evidence. tools/engine_sim.lua (flip now modelled):
          average gain over the chain +0.64 (v7.3 behaviour) -> +1.97,
          worst scenario -0.60. Engine off: unchanged.
          BUGS:
          - A saved profile with a wrong-typed field made NewRec throw on
            every tick for that player -- no resolver for them all match --
            and FlushDB throw too. DB entries are now validated against a
            schema on load and on use (found by a corrupt-data test).
          - Harness blind spot: rv_clear discarded unflushed [ERR] lines,
            which had been hiding exactly that crash.
          STRUCTURE: ProcessPlayer 680 -> 387 lines; side tracking, the
          legacy chain and applying the decision are now TrackSide,
          ChainPick and ApplyDecision. Proven behaviour-identical: 12
          differential runs (both runtimes, engine on/off, scripted + 4
          fuzz worlds, ~915k plist writes).
          COVERAGE: every function but the disabled Jitter Prediction now
          runs in the harness (111 -> 113 of 114): new phase for the
          lagcomp and yaw-cache sources (late records), torso clustering,
          origin-jump SHIFT, panel drag, rv_clear, corrupt DB entries; unit
          checks for ENG.Fade and the DB cap.
          PERFORMANCE (LuaJIT, first measurement on the game's runtime):
          2v2 72 us per tick including 4 paint frames, 0.46% of the tick
          budget; 5 enemies 113 us. No change warranted; added to the suite.
          DOCS: choke semantics ("record staleness beyond latency") written
          down where it's computed. NEW: rv_engine console command.
  v7.3 – Engine v2 by measurement, full debugging pass, tooling.
          ENGINE: per-movement-state context (state -> player -> other
          players -> prior, each level a capped prior for the next), a
          Brier-score self-audit with automatic safe mode (margin 0.04 cut
          the worst simulated scenario from -1.27 to -0.83 points), and a
          predicted head chance p on every shot line (eng=arm p=0.61).
          Tried and cut after ablation in tools/engine_sim.lua: per-shot
          forgetting, a Page-Hinkley config-change detector (0.45 false
          alarms per stationary player-match) and a coupled per-source
          sign-accuracy model (+1.3 avg vs +1.9). Per-state evidence is
          session-only: saving it cost 1.68 MB per autosave at the DB cap
          (now 208 KB).
          BUGS FOUND BY THE NEW TESTS:
          - NA() never returned on inf/huge input (inf - 360 == inf): one
            corrupt FFI float would freeze the game thread. Bounded now,
            identical on 2M finite inputs.
          - GetLat compared the netchannel call's result outside its
            pcall; a non-number would crash Update every tick. Found by
            running the harness on LuaJIT for the first time.
          - Profile keys used tostring(steam64): a 64-bit id in a double
            prints as 7.6561198e+16 and every player would share one
            profile. %.0f now; identical keys for real account ids.
          - Non-finite eye yaw / pose / duck reached the history buffers
            and Clamp, whose NaN behaviour differs between Lua builds.
            Input boundary at the sample site; a missing pose now reads as
            centre (no evidence) instead of a full -60 desync.
          - Backtrack ticks and damage are sanitized before logging.
          VERIFICATION: tools/check_all.sh -- syntax on Lua 5.3 and
          LuaJIT, luacheck 0 warnings, scripted harness on both runtimes,
          identical plist writes across runtimes (scripted and 8 fuzz
          worlds, ~720k writes), 200k-tick soak with flat memory, DB-cap
          unit check, engine sim, log analyzer smoke test.
          TOOLS: tools/log_report.lua (per-method/arm head rates with
          Wilson intervals, override record, calibration, range check);
          README.md.
  v7.2 – Adaptive decision engine; review cleanups.
          ENGINE (Detection > Adaptive engine, on by default): every
          detector's correction becomes a candidate arm (vuln windows,
          6lex, hit memory, pose side as-is/inverted = meta hold/suppress,
          built-in). The legacy priority chain stays the default pick; the
          engine overrides it only when P(candidate > pick) > 0.85 on Beta
          posteriors seeded from the 9-log head rates, with evidence on
          this player. Outcomes are shared: a head hit scores every
          candidate present at fire time against the confirmed side; a
          resolver miss fails the applied arm and spills half a count to
          the rest. A global table carries evidence across players and
          sessions (halved on load); per-player evidence persists per
          steam64 and is halved on a soft reset. Replaces the v7.0
          learner and tools/learner_sim.lua.
          PROOF: with the engine off, the harness scenario produces the
          exact plist writes of v7.1 (817/817). tools/engine_sim.lua runs
          the real engine code: +3.0 points average over the chain, worst
          -0.1, +12.6 when hit memory goes stale, +6.4 when the LBY window
          is backwards; no-evidence picks equal the chain's in 5000/5000.
          CLEANUPS: changelog moved here (-940 lines in the script);
          chain thresholds moved to CFG; JITTER_AA table; dead is_jitter
          removed; debug flag cached per tick instead of 6 ui.get calls
          per player; per-tick context table reused; ResetMatchState()
          shared by rv_reset/rv_wipe/EndMatch; DB stamped with a load
          generation and capped at 500 profiles (least recently seen
          dropped).
    v7.1 – Interface redesign; the [EXP] switches are gone.
            MENU: six rows in LUA > B -- title, Resolver (master),
            Detection (Vulnerability / Hit memory / Desync angle),
            Tight interpolation, Indicators (Info panel / ESP flags /
            Shift marker), Debug log. The four DB/log buttons moved to
            the console (new: rv_save). Names carry a hidden
            "\nriftveil" suffix so saved config values can't collide
            with another script's elements. The accent follows
            gamesense's Menu color; the separate picker is gone.
            First run of this layout turns on Resolver, Vulnerability,
            Hit memory, Tight interpolation and all indicators, once
            (flagged in the database, so a saved config wins after).
            [EXP] FEATURES, fixed from the 9 match logs instead of left
            to toggles (see FEATURE SET for the reasoning in full):
            Suppress ON (78.1% head, best method, on in every log);
            Asymmetric ON (every log already ran it); Jitter prediction
            OFF (mixed clocks, shadows four side sources); Adaptive
            learning OFF (would displace hit memory and suppress). All
            four code paths are kept.
            TIGHT INTERPOLATION now follows the master switch: turning
            the resolver off restores the original interp cvars.
            INFO PANEL: rebuilt in gamesense's visual language -- square
            two-layer frame, menu tri-colour strip, pixel-font labels,
            fixed 200px width, centre-zero side meter, eased height and
            meter. Player names are fitted by pixel width on whole UTF-8
            characters (the old byte cut split Cyrillic letters). Built
            in its own function scope: the main chunk is at Lua's
            200-local limit.
    v7.0 – Performance pass + adaptive learner. Everything below was
            measured or simulated, not assumed (tools/sandbox_check.lua,
            tools/learner_sim.lua).
            PERFORMANCE (before -> after, same 20k-tick scenario):
            per tick 226 -> 145 us (-36%), paint 107 -> 55 us (-48%),
            ESP flags 6.7 -> 1.2 us (-82%), net update 100 -> 76 us (-24%),
            21-min verbose session 243 MB -> 25 MB written to disk.
            (1) Logger was quadratic: every 512 lines it re-read AND
            rewrote the whole file, synchronously on the game thread, and
            the file never shrank across sessions. Now read once, larger
            flushes, and rolled to riftveil_debug_prev.txt at 1.5 MB, so
            each write is bounded. [dcap] (logged every tick per enemy since
            v6.7) now logs only when the cap moves a whole degree.
            (2) Memory leak: rec.tm only cleared tm[st - 36]; any enemy
            whose simtime skips ticks (fakelag, choke) never had that slot
            written, so nothing was ever removed -- 2,500 entries after 20k
            ticks for an 8-tick fakelag enemy. Now age-pruned, bounded.
            (3) ~37% of CPU re-scanned the 16-slot pose buffer: RLen was
            O(n) and ran ~8x/tick, PoseVar 3x/tick, CountClusters
            allocated+sorted every tick. Now O(1) count, memoized variance,
            scratch reuse -- 0 output mismatches vs v6.8 on 200k random
            histories. DetectAA's flip loop also counted a bogus pair
            (oldest vs NEWEST, via ring wraparound) once the buffer was
            full: fixed, changes its output on 13.9% of evaluations.
            (4) Paint: panel content cached per state version (it rebuilt
            text and re-measured it every frame); ESP flags are now per-
            tick table lookups (each call allocated a closure and made 3 C
            calls, per enemy, per flag, per frame); BOX_EDGES hoisted.
            (5) plist.set only when a value changes (was 4x/enemy/tick),
            with a 1s resync; update_player_list only when a new enemy
            appears (was every tick); get_players(true) instead of manual
            enemy/alive filtering; named pcall targets instead of per-call
            closures in GetAS/GetAL/GetLat/LCTicks.
            BUGS: (6) hit memory recorded the ring-buffer side estimate,
            not the side actually forced -- every suppress head hit (the
            most-used method, negated by design) taught it the opposite of
            what hit; vuln hits likewise. Now uses the applied value's
            sign. (7) FlushDB autosave re-added the whole match every 60s
            (a real log shows one player's 3 hits stored as 3, 6 ... 36);
            now merges into a per-match baseline, idempotent. (8)
            ResetPlist never cleared "High priority". (9) Bots (steam64 0)
            are no longer resolved.
            ADAPTIVE LEARNING ([EXP] toggle, off until you enable it): real
            logs showed the tracked side barely predicts outcomes (68.4%
            vs 64.3% head rate, 483 shots), so no global convention fix
            exists. It learns per player, from head hits and '?' misses,
            whether to keep or flip the tracked side (per movement state),
            full vs half magnitude, force vs built-in, and whether each
            vuln delta family is signed right. Design picked by simulation:
            +21.5 points vs fixed when the tracked side is inverted, -1.0
            when it's right, +2.5 average over 8 opponent types, and 70.2%
            (near the 72% optimum) in a rematch using the persisted counts.
            [hit]/[miss] lines now carry lrn=/vor= tags; rv_stats shows it.
    v6.8 – API-grounded review against docs.gamesense.gs (entity, client,
            globals, aim_fire, aim_miss pages).
            (1) 'prediction error' misses no longer blame the resolver.
            The aim_miss docs list four reasons: 'spread', 'prediction
            error', 'death', and '?' ("unknown cause or resolver-related
            miss"). is_resolver included 'prediction error', so each one
            flipped the tracked side and counted toward the soft reset
            that wipes hit memory. Rare (2 of 78 misses across two real
            logs), but every one corrupted side state for a miss caused
            by movement prediction. It still drives the backtrack-depth
            penalty, which is what it's actually evidence of.
            (2) Shots the aimbot flagged extrapolated or teleported
            (aim_fire fields, "breaking lag compensation") are now
            snapshotted and excluded from resolver blame on a miss --
            the position was a guess, so the miss says nothing about yaw.
            (3) Backtrack is read unit-agnostically. The aim_fire docs
            contradict themselves: the field says "Amount of ticks", the
            example wraps it in globals.toticks() (seconds). v4.2
            followed the example; if the description is right, TT()
            turned every nonzero tick count into ticks*64, failing the
            1..16 check so backtrack learning could never learn. The two
            readings can't overlap -- seconds are capped by sv_maxunlag
            (<= 0.2, always < 1), nonzero ticks are whole numbers >= 1 --
            so (0,1) is converted as seconds and >= 1 taken as ticks.
            Logs can't settle it: all 257 hits / 78 misses logged bt=0.
            (4) CanSeeHead's source is now client.eye_position() (the
            local player's real eye position per the client docs)
            instead of origin + m_vecViewOffset.z.
            (5) tools/sandbox_check.lua rebuilt. The old harness's
            ui.get mock returned false for everything, so Update() bailed
            at `if not ui.get(ui_on)` and ProcessPlayer -- the whole
            resolver -- executed zero lines while it still printed PASS.
            It now uses element-aware UI mocks, a stateful animstate
            mock with real numeric fields, and an 80-tick scenario
            (jitter, LBY snaps, choke/unchoke, stop/peek/duck, hits and
            every miss reason). It also flags undeclared global READS and
            [ERR] lines swallowed by riftveil's own pcalls, prints
            per-function coverage, and fails if a core function never
            runs. Verified by reintroducing a real out-of-scope-local bug
            from this pass (mvz in CanSeeHead) -- the new harness flags
            it; the old one passed it.
            Flagged, not changed: TrackDT compares enemy simtime against
            globals.tickcount(); globals.servertickcount() ("most recently
            received tick from the server") may be the more correct
            baseline for def-tickbase detection, but the docs don't pin
            down how far tickcount leads it, so no change without data.
    v6.7 – Explored 3 uploaded reference resolver/AA scripts for
            genuinely useful, verifiable techniques (not invented).
            Found the same formula independently in all three: a
            per-tick "true currently-achievable max desync" computed
            from stop_to_full_run/feet_spd_fwd/feet_spd_unk/duck_amount
            scaling max_yaw, instead of treating max_yaw as a flat
            constant regardless of movement state. One of the three
            scripts shares RIFTVEIL's own exact FFI struct layout --
            same 0x9960 base offset, same pad13[0x1CA] position for
            min_yaw/max_yaw -- strong corroboration the field mapping
            is correct. Checked RIFTVEIL's own struct: feet_spd_fwd,
            feet_spd_unk, and stop_to_full_run have been declared and
            read into rv_as every single tick since the FFI section was
            written, but were never referenced anywhere else in the
            file -- dead struct fields, same class of gap as the
            DetectVuln 3rd-return-value fix earlier this session.
            Added DynamicMaxYaw(as), wired into LiveCap: when the
            dynamic read succeeds and comes in tighter than the flat
            engine max_yaw, LiveCap's cap uses it instead. This can
            only REDUCE the cap toward what's actually achievable this
            exact tick, never widen it past the engine's own reported
            bound -- a strictly more conservative correction cap, not a
            riskier guess, and it touches every CfgAngle-capped
            correction in the file (corr_cap/live_cap feed LBY, 6lex
            fallback, hit_mem, suppress, meta_hold, and the yaw-jitter
            threshold) since they all read live_cap through LiveCap.
    v6.6 – Checked the real gamesense API (docs.gamesense.gs/docs/api/
            entity) for a capability RIFTVEIL wasn't using yet, rather
            than inventing anything unverified. Found entity.hitbox_
            position(player, hitbox_id) -- confirmed real via the docs'
            own "Head Dot ESP" example, which uses hitbox id 0 for the
            head exactly the way this fix does. CanSeeHead (gates the
            LBY/UNK vuln TTL boost) was tracing to target origin +
            m_vecViewOffset.z as an approximation of head position --
            close while standing, but view offset and the actual head
            hitbox don't track each other precisely through every
            crouch/lean pose. Swapped the trace's target endpoint to the
            real queried head hitbox position, falling back to the old
            origin+view-offset approximation only if the hitbox query
            itself fails (dormant/unresolved entity this tick) -- same
            fail-open philosophy the rest of this function already uses.
    v6.5 – Traced whether the detection methods actually COLLABORATE
            (cross-validate each other) when making a decision, not just
            whether they're wired correctly (v6.4). Answer: mostly no --
            both the side-tracking chain and the override chain are
            strict if/elseif priority waterfalls (hit_mem > 6lex >
            period > lagcomp > def_tick > ring_spike > yaw_cache; vuln >
            6lex > hit_mem > meta_hold > suppress > release). The first
            method whose conditions pass wins outright; every lower-
            priority method's opinion is discarded for that tick even if
            it would have disagreed. No voting, no consensus, at the
            actual decision point.
            Two real collaboration points already existed: six_agree/
            six_disagree (6lex's per-player track record graded against
            hit_mem's confirmed hits over time, gating whether 6lex is
            even trusted) and a confidence bump when 6lex's side agrees
            with the ring buffer's dom_side. But that second one was
            asymmetric -- a real gap, not just an absence of a feature:
            it unconditionally added +0.08 confidence on ANY nonzero
            six_side, even when six_side and dom_side ACTIVELY
            CONTRADICTED each other (both nonzero, opposite signs).
            Agreement was rewarded (+0.05 on top); disagreement between
            two independent signals was silently treated as neutral
            instead of negative evidence. Fixed: a real disagreement
            between six_side and dom_side now decays confidence the same
            way a genuinely quiet/no-signal tick already does
            (CFG.CONF_DECAY), instead of still gaining ground.
    v6.4 – Wiring audit: verified every function's return values are
            actually consumed by its caller (not just that the file
            parses), and that every defined function is actually called
            from somewhere. Method: cross-referenced all 68 top-level
            `local function` definitions against every call site, and
            checked multi-return-value functions (DetectAA, LiveCap,
            GetLat, ExtrapolateOrigin, GetRec, DetectVuln, ...) for
            whether the caller captures as many values as the function
            actually returns.
            Found one real dead wire: DetectVuln returns 3 values
            (vtype, val, conf) in every branch, but its one call site
            in ProcessPlayer only captured 2 (`local vtype, vcorr =
            DetectVuln(...)`). Lua doesn't error on this -- extra return
            values are just silently discarded -- so nothing ever
            surfaced it. The dropped 3rd value was a whole per-detection
            confidence subsystem: graduated 0.72 (CTR, weakest heuristic)
            up to 0.97 (UNK with cluster + live-cap + settled-state
            cross-check all agreeing), computed fresh every tick, never
            logged, never read, with zero effect on any resolver
            decision. Fixed by capturing it (`local vtype, vcorr, vconf
            = DetectVuln(...)`), storing it on the new rec.vuln_conf
            field, and adding conf=%.2f to the verbose [vuln] debug
            line. Deliberately NOT wiring it into a new gating decision
            (e.g. requiring vconf above some threshold before opening a
            window) -- that would need real per-confidence-level
            accuracy data to pick a defensible cutoff from, which is a
            job for a future log, not a guess made now. This at least
            makes the signal visible for that analysis going forward.
            Every other multi-return call site checked out: DetectAA's
            4 values, LiveCap's 3, GetLat's 2, ExtrapolateOrigin's 3,
            GetRec's 2 are all captured and genuinely used downstream
            (traced pose_sum specifically since it looked like the most
            likely second dead output -- it's read by the DEF_TICK/
            RING_SPK side-tracking fallbacks). All 68 defined functions
            are reachable from an event callback or another function --
            none dangling. rec.vuln_pref (written on every confirmed
            vuln hit, persisted to DB, shown in rv_db) was the other
            field that looked like it might be write-only, but it reads
            as intentional cross-match telemetry ("which vuln type has
            worked on this player historically"), not a broken
            connection -- nothing in its own documentation or surrounding
            code implies it was ever meant to gate a live decision.
    v6.3 – MAJOR fix, found from a real debug log (not a review guess):
            5 of DetectVuln's 6 non-LBY branches (UNK/STP/PKA/DCK/LND/CTR)
            were returning a raw ABSOLUTE animstate yaw reading
            (as.torso_yaw / as.goal_feet_yaw / eye_y itself) as the vuln
            correction, which flows straight through rec.vuln_val ->
            override_val -> plist.set(..., "Force body yaw value", ...)
            with no transformation anywhere in between. [LBY]'s own
            CfgAngle output proves what that field actually wants: a
            small SIGNED DESYNC OFFSET (its KNOWN_CFGS/CFG_COUNTER
            tables are literally desync magnitudes, ~20-47°, bounded by
            DESYNC_CAP=58) -- not a full -180..180 compass-direction
            world yaw. Proof from a real log: type=stp val hit 354.3,
            type=unk hit 179.9 with 26% of all UNK corrections (178/679
            in one match) already exceeding DESYNC_CAP outright, type=lnd
            hit 172.8 -- while LBY's val stayed tightly inside 0..47 the
            entire time, exactly where a real desync belongs. The UNK
            branch even computes the CORRECT quantity for its own
            threshold check a few lines earlier (`d = NA(torso - eye)`,
            the signed delta) and then discarded it in favor of the raw
            torso reading for the actual return -- an internal self-
            contradiction within the same function, not just an
            outside-convention mismatch. This also explains why the
            symptom was inconsistent ("feels horrible" some fights, fine
            others): torso_yaw and eye_y are often coincidentally close
            (players roughly face where they look), so most UNK
            corrections LOOKED plausible by chance while a full quarter
            were wildly, silently wrong.
            Fixed: UNK/STP/PKA/DCK now convert their raw torso/
            goal_feet_yaw reading into Clamp(NA(reading - eye), -cap,
            cap), matching every CfgAngle-sourced correction elsewhere.
            LND/CTR had no torso reading at all -- just safe_eye standing
            in for "body already matches eye" -- so they now correctly
            return 0 (zero desync) instead of forcing body yaw to
            whatever absolute direction the enemy's eyes happened to be
            pointing. UNK's own live-cap-boost confidence check had the
            identical absolute-vs-delta bug one level down (comparing a
            raw torso reading against a desync-magnitude cap) and is
            fixed the same way, now operating on the corrected delta.
            This is very likely the single largest resolver-accuracy
            defect found across every review pass this session -- UNK
            alone fired 679 times in one log, by far the most common
            vuln type, meaning most vuln-window shots before this fix
            were aimed using a fundamentally wrong quantity roughly a
            quarter of the time.
    v6.2 – Senior resolver-review pass #3, focused on resolver-domain
            correctness this time (window/priority handling, flip and
            side-sign conventions, hit_side encoding-immutability)
            rather than generic Lua bugs or platform-API misuse (already
            covered in the previous two passes).
            Found one real issue: DetectVuln re-evaluates all 7 trigger
            conditions independently every tick with zero awareness of
            rec.vuln_ttl. If a window was already open (say an LBY snap
            with 2 ticks still left) and a DIFFERENT vtype fired on the
            very next tick with a shorter base_ttl (say a UNK unchoke,
            base_ttl=1), the old code unconditionally overwrote
            rec.vuln_ttl down to the new value -- cutting the still-
            active, still-valid window off early and handing the aimbot
            less time to find a shot than either signal alone would
            have given. Fixed with rec.vuln_ttl = math.max(rec.vuln_ttl,
            base_ttl, lc_ttl) -- provably monotonic (a fresh detection
            can now only extend/refresh the window, never shrink it),
            so unlike the KNOWN_CFGS tolerance-overlap observation
            (v5.9, still just flagged, not changed -- would need real
            per-type accuracy data to justify a specific retune), this
            one doesn't require guessing at resolver accuracy to know
            it's strictly no worse and sometimes better. vuln_type/
            vuln_val still update to the freshest read (presumably the
            more current correction) -- only the ttl is protected.
            Also specifically re-verified (no changes needed): the
            override-branch priority chain (vuln > 6lex > hit_mem >
            meta_hold > suppress > release) makes sense in reliability
            order; hit_side's flip-encoding is genuinely immutable once
            stored (a later rec.flip toggle correctly never re-applies
            to an already-encoded hit_side, confirmed by tracing every
            "apply flip" site against tracked_method); the suppress
            branch's angle math (negates the BELIEVED real side, not a
            random one); and the +/- side-sign convention (positive =
            right) is consistent across every one of the 8 side-sourcing
            methods (ring/hit_mem/6lex/period/lagcomp/def_tick/
            ring_spike/yaw_cache) plus vuln and suppress.
    v6.1 – Senior gamesense-review pass #2, focused on platform-API
            correctness (ui/event/entity/plist call semantics) rather
            than internal resolver logic. Found a real UI/cvar state
            desync bug: ui.set_callback only fires on a CHANGE event --
            it does NOT run just because a checkbox loads already-
            checked from a saved gamesense config. RefreshVis already
            accounts for this (it's manually self-invoked once right
            after ui.set_callback(ui_on, RefreshVis) so panel-item
            visibility syncs with a persisted ui_on checkbox on load),
            but ui_tight's own callback never got the same treatment.
            Concretely: if "Tight Interpolation" was left checked at
            the end of a prior session, reloading the script restores
            the checkbox to checked (gamesense persists ui state), but
            the actual cl_interp/cl_interp_ratio/cl_interpolate cvars
            stay at whatever ORIG_* captured at THIS load -- silently
            desynced from what the UI displays as active, and nothing
            forces a re-toggle to notice since the checkbox already
            reads "on". Named the callback (ApplyTightInterp) and
            self-invoke it once after registration, mirroring
            RefreshVis's own pattern exactly.
            Also checked (no issues found) every ui.*/entity.*/plist.*/
            client.* call signature against the platform's actual
            semantics: register_esp_flag's (name, r,g,b, callback)
            shape, ui.new_color_picker's 4-value ui.get() return,
            client.key_state's VK_LBUTTON=0x01 check, plist.set's four
            field names used throughout (Force body yaw[/ value],
            Correction active, High priority), the aim_fire/aim_hit/
            aim_miss event field names (id/target/backtrack/hitgroup/
            reason/damage), and console_input's suppress-return
            contract -- all consistent with prior doc-verified usage
            elsewhere in this same file.
    v6.0 – Full senior-review pass, line by line, top to bottom (not
            triggered by a specific log this time). Found a real,
            previously-undetected bug in IsHold: it reset `stable` to 0
            on a sign mismatch but kept scanning OLDER ring-buffer
            entries afterward instead of stopping there. Since a "held"
            AA pattern is supposed to mean an unbroken run of the same
            sign ending at the CURRENT tick, a mismatch at the most
            recent samples should disqualify it immediately -- but the
            old code could have a real flip 1-2 ticks ago, then a long
            coincidental run of matches further back in the same short
            window push `stable` back over CFG.HOLD_STABLE by the end of
            the loop. Concretely, with HOLD_STABLE=4 and recent-to-old
            signs [+, -, +,+,+,+,+]: the flip at offset 1 should mean
            "not holding," but the old logic finishes with stable=5 and
            reports AA.HOLD anyway. DetectAA then skips its normal flip-
            counting/cluster classification for that tick and returns a
            wrong AA type + side straight from the current sample --
            feeding wrong data into rec.aa_type, rec.conf, and the
            is_jitter/is_sym side-tracking checks downstream. Fixed to
            break out at the first mismatch instead of resetting and
            continuing, since anything before a break in the streak
            can't contribute to whether the sign is held right now.
            Reviewed and confirmed sound (no changes): RingBuffer index
            math, MeanSidePose/CountClusters/IsSkitter, TorsoCluster's
            circular-mean clustering, ChokedPkts/TrackDT/IsDefTick,
            LCTicks/WeDefensive, RecognizeCfg's hysteresis, PredictSide's
            median-gap math, CfgAngle/VelCap/LiveCap, DetectVuln's 6
            window branches, ProcessPlayer's save-phase (prev_* always
            written regardless of which early-break path was taken),
            FlushDB's weighting, on_aim_fire/hit/miss's event handling,
            the panel drag/layout code, and the SHIFT box geometry.
    v5.9 – Found the v5.8 corr_cap fix wasn't the only place it applied.
            tracked_side's unconditional side-tracking chain (used by the
            META_HOLD fallback) sets tracked_method = HIT_MEM off
            rec.hit_side whenever hit_count>=2, regardless of whether the
            "Hit Memory" checkbox is even on -- so META_HOLD could still
            clamp a confirmed hit_mem correction to literal 0 at high
            target speed through this second call site, even after [3]'s
            own call site was fixed. Now uses live_cap when
            tracked_method == HIT_MEM there too.
            Also traced KNOWN_CFGS' own numbers: luasense_beta's canonical
            average (26,41) sits inside symmetric's acceptance band
            (error 15 vs. threshold 16), luasense_std's average (30,38)
            sits inside symmetric's band too (error 8), and both sit
            inside each other's. All three known profiles mutually
            overlap in RecognizeCfg's matching space -- hysteresis
            (CFG_SWITCH_MARGIN=6) mostly holds a pick steady, but real
            per-match measurement noise can occasionally punch through
            the gap, which is consistent with (not fully explaining) the
            occasional config switches seen in logs for players near a
            boundary. Not changing the tolerance/margin numbers without
            real per-type accuracy data across multiple logs -- flagging
            it rather than guessing at a retune.
    v5.8 – Diagnosed a debug log complaint ("it feels horrible") down to
            two real bugs:
            (1) MAJOR: hit_mem overrides (the [3] branch, confirmed-side
            corrections from an actual prior hit on this player/state)
            were capped with corr_cap -- VelCap's velocity-scaled cap,
            which falls LINEARLY TO EXACTLY 0 once the target's speed
            reaches CFG.VEL_CAP_SPD (580u/s). A bhopping/fast-strafing
            enemy crosses that constantly, and CfgAngle's Clamp(raw, -cap,
            cap) with cap=0 forces the correction to literally 0 degrees --
            aim dead-center, no yaw correction at all, worse than a coin
            flip. Caught directly in a debug log:
            "meth=hit_mem val=0.0". The comment above VelCap's call site
            already said corr_cap is "used only to clamp CfgAngle's static
            guesses" -- hit_mem is confirmed data, not a guess, and was
            never supposed to be in scope. Switched both hit_mem call
            sites to live_cap (the engine's real desync bound, unscaled by
            velocity) instead of corr_cap.
            (2) "symmetric" is a real, recognized KNOWN_CFGS entry
            (avg_left=35, avg_right=35) but had no matching CFG_COUNTER
            table, so CfgAngle(..., "symmetric", ...) always fell through
            to ASYM_FALLBACK -- angles calibrated for an asymmetric desync
            pattern, applied to a player already confirmed to desync
            symmetrically. Added CFG_COUNTER.symmetric using the same
            35/35 flat value per state (no per-state symmetric calibration
            data exists yet). Seen in the same log: a player classified
            "symmetric" repeatedly, with worse-than-expected accuracy and
            config-switch churn, in the same session this angle mismatch
            was active.
    v5.7 – Bug review pass #3. Found and fixed four more:
            (1) MAJOR: on_aim_hit's is_head check used hitgroup==2 for
            "neck", but the file's OWN HG lookup table a few hundred
            lines up proves hitgroup 2 is CHEST (generic=0, head=1,
            chest=2, stomach=3, left arm=4, right arm=5, left leg=6,
            right leg=7, neck=8, gear=10) -- an internal contradiction
            within the same file, not a guess against outside docs.
            Every chest hit -- likely the single most common hitgroup in
            real fights -- has been feeding hit_side/hit_side_by_state/
            six_agree/six_disagree as if it were a confirmed head/neck
            hit, exactly the body-shot pollution the surrounding comment
            says it guards against. Fixed to hitgroup==1 or ==8.
            (2) Panel drag snapped on the first frame of every drag: the
            delta baseline (drag.mx/my) wasn't reset to the click
            position when a grab started, so the first frame applied
            whatever incidental mouse movement had happened since the
            last unrelated frame. Now reset at grab-start.
            (3) on_aim_miss's dmg_rejected path discarded a shot that
            m_totalHitsOnServer PROVES actually landed, crediting it
            nowhere at all. Now credited to total_hits (hitgroup is
            unknown for this event type, so hit_side/vuln_profile.hit/
            six_agree -- which specifically require confirmed head/neck
            hitgroup -- are correctly left uncredited).
            (4) rec.kills (and DB[s64].kills) has counted every confirmed
            hit, any hitgroup, since on_aim_hit was written -- never
            gated on the target dying. Left the field name alone (a
            rename would silently orphan everyone's already-saved DB
            entries under the old key) but fixed the misleading rv_db/
            debug-log display from "kills" to "hits", and documented
            what the seeded_conf gate's "db.kills >= 3" actually requires.
    v5.6 – Fixed the suppress streak-cap's pause window, which never
            actually functioned. The single-counter design reset
            _sup_streak to 0 in the non-suppress fallback branches the
            instant the 8-tick cap blocked suppress for even one tick --
            so the documented "pause 4 ticks, then resume" behavior
            never happened: suppress silently resumed on the very next
            tick instead, every time, since 0 < 8 immediately re-passed
            the gate. The streak_ok >= 12 branch was provably dead code.
            Rebuilt with a dedicated pause counter (_sup_pause) and a
            sup_pausing flag so the fallback branches (meta_hold/builtin
            release) know not to blow the counters away while a
            deliberate pause is genuinely in progress. Traced the full
            cycle by hand: 8 ticks suppress -> 4 ticks paused (shots go
            through normally) -> counters reset -> fresh cycle, matching
            the original design intent for the first time.
    v5.5 – Menu + bug review pass.
            (1) Renamed menu labels away from internal codenames a
            first-time user has no way to decode: "6lex extraction" ->
            "Desync Angle Detection", "Vulnerability windows" ->
            "Vulnerability Detection", "Hit-side memory" -> "Hit
            Memory", "Period prediction" -> "Jitter Prediction", "Tight
            interp" -> "Tight Interpolation", "Indicators" -> "ESP
            Indicators", "Verbose log" -> "Verbose Logging", "Panel
            accent" -> "Panel Accent Color". Only the displayed strings
            changed -- the underlying ui_* variable names (never shown
            to the user) are untouched, so no logic moved.
            (2) Found and fixed a real dead-toggle bug while reviewing:
            [EXP] Asymmetric Angles (ui_asym) was created, added to the
            SAFE/EXP visibility list, and had a comment right next to
            CfgAngle claiming it "feeds into CfgAngle via ASYM_FALLBACK
            vs CFG_COUNTER selection" -- but CfgAngle never actually
            checked it. Toggling that checkbox did nothing at all. Now
            wired as documented: ON keeps the existing per-side L/R
            fallback table, OFF averages it into one symmetric magnitude
            for both sides -- only affects players with no confidently
            recognized config (TrustedCfg fails), never touches
            CFG_COUNTER's per-config tables.
            Also reviewed (no changes needed, already correct):
            RecognizeCfg's switch hysteresis, PredictSide's jitter-period
            math, the DCK cooldown set/decrement lifecycle, and the
            STP/PKA/LND/CTR vuln branches.
    v5.4 – CRITICAL fix to the v5.2 vuln-type trust gate: vuln_profile's
            "seen" counter was incremented every time DetectVuln logged a
            detection, not once per actual shot taken. Checked against a
            real debug log: one player logged 110 "unk" detections in a
            single match against roughly a dozen actual shots at them --
            most vuln windows never get shot at (target not visible/not
            aimed-at during the brief ttl). That inflated denominator
            crushed hit/seen toward near-zero regardless of true
            accuracy, meaning the v5.2 gate would have started
            distrust-probing perfectly good vuln types almost
            immediately -- actively working against hit rate, the
            opposite of its purpose. Compounding it, on_aim_miss ALSO
            incremented seen a second time for every vuln miss (but hits
            were never double-counted), biasing the already-wrong ratio
            further downward specifically on misses.
            Fixed by crediting seen exactly once per shot, in
            on_aim_fire when a shot is fired during an open vuln
            window -- the same "one shot, one trial" definition
            on_aim_hit already uses for hit -- and removing both the
            per-detection increment and the duplicate miss-path
            increment. seen/hit are now symmetric: exactly one of each
            per shot outcome, nothing double-counted.
    v5.3 – Fixed the SHIFT box's tether line: it targeted scr[1], one
            arbitrary box corner (bottom, min-x, min-y), instead of the
            box's center. That corner sits on the far side of the box
            from the camera at plenty of viewing angles, so the tether
            looked like it stabbed into a random edge instead of
            pointing at the box -- reported as "horrible"/asymmetric.
            The box's own 12-edge geometry was already correct (checked
            the corner math against m_vecMins/m_vecMaxs -- forms a
            proper symmetric rectangular prism); only the tether target
            was wrong. Now targets the box's actual center, which stays
            a consistent anchor regardless of viewing angle.
    v5.2 – Per-player, per-vuln-TYPE trust gate (VulnTrusted). vuln_profile
            (seen/hit per VTYPE) was exposed as a read-only rv_stats/rv_db
            diagnostic in v4.7 specifically because there wasn't a real
            per-type hit ratio to calibrate a live gate against yet --
            guessing a threshold then risked suppressing a type that was
            actually fine. Now wired up, same idea as the 6lex agree/
            disagree calibration (v4.1) applied to this data: a type
            needs >=6 real detections (VULN_TRUST_MIN_N) before it can
            ever be distrusted, and below a 15% hit ratio
            (VULN_TRUST_MIN_RATIO) at that point, RIFTVEIL stops opening
            the vuln window for that specific type on that specific
            player and falls through to 6lex/hit_mem/suppress instead.
            Not a permanent lockout -- probed every 5th detection
            (VULN_PROBE_EVERY) so it can recover if their behavior
            changes mid-match (config switch, etc.), mirroring the
            existing suppress-streak-cap self-correction pattern rather
            than inventing a new one. seen/hit counters keep updating
            even while distrusted so the probe has real data to re-judge
            against. All three thresholds are new CFG constants, and the
            gate lives entirely inside the existing "[SAFE]
            Vulnerability windows" checkbox -- no new UI control added.
    v5.1 – Fixed FlushDB's cross-match hit_rate averaging: it weighted
            each match's resolver hit ratio (nhr, from hit_count/
            resolver_misses) by rec.kills, a completely different and
            much rarer sample base. Any match where you resolved someone
            correctly (hit_count>=2, the gate for even reaching this
            code) but never landed the actual kill on them -- teammate
            finished them, they died elsewhere after being hit -- had
            rec.kills==0, which zeroed that whole match's contribution
            to the running DB average despite having real data. Silently
            starved seeded_conf (NewRec reads db.hit_rate) for exactly
            that common case. Now weighted by the actual resolver sample
            size (hit_count+resolver_misses) via a new persisted
            db.samples field; kills is still tracked as its own running
            total, just no longer used as the averaging weight. rv_db
            now shows hr:%d%%(n=N) so the sample size behind that
            percentage is visible.
            Also investigated (per user request) whether ui elements
            support a :tooltip() method for in-menu guidance, the way
            two of the reference neverlose scripts reviewed today used
            it -- confirmed against docs.gamesense.gs/docs/api/ui that
            no such method exists on gamesense ui elements; that's a
            neverlose-only menu-object convention, not portable here.
            Did not add fake tooltips.
    v5.0 – Panel visual upgrade: replaced the flat hard-cornered body/
            title rectangles and straight 1px border lines with a
            rounded panel + soft drop shadow. Ported RoundedRect() from
            a real "SOLUS UI"-style script's renderer_rounded_rect
            (shared identically between two of its files), trimmed to
            just the fill -- verified renderer.circle's start_degrees/
            percentage usage against docs.gamesense.gs/docs/api/
            renderer/circle rather than trusting the source blind. One
            offset RoundedRect pass stands in for that script's several-
            step gaussian shadow (this repaints every frame, so kept to
            a single extra draw pass). The header no longer gets its own
            filled rectangle -- a flat inset rect's square corners would
            poke out past the rounded body -- replaced with a thin inset
            separator line. Purely visual, no logic touched.
    v4.9 – Added an animlayer[6].weight settled-state cross-check to the
            UNK vuln branch, found reviewing a real neverlose resolver's
            find_desync_side: it treats weight==0 or weight==1 as "the
            movement layer is fully settled, no active blend" -- a signal
            independent of the playback_rate digits 6lex reads off that
            same layer. When settled at the exact tick a torso_yaw read
            is taken, it's extra confirmation the read isn't caught
            mid-transition. Same modest-boost pattern already used for
            the live_min/live_max cross-check (+0.02 conf, capped at
            0.97) -- not a hard requirement, al6_weight is nil whenever
            the FFI read fails and the branch behaves exactly as before.
            Also reconfirmed (not changed): that resolver's own
            breaking_lc check uses the identical 4096 sq-unit origin-jump
            threshold RIFTVEIL's SHIFT detector already uses -- 4th
            independent source now confirming that number.
    v4.8 – Removed the Force Shot indicator (v4.5/v4.6) entirely, per
            request. Pulled the checkbox, color picker, CFG.FORCESHOT_CONF,
            and the DrawOverlay render block -- nothing of it remains.
    v4.7 – Surfaced vuln_profile (seen/hit per vulnerability TYPE, e.g.
            lby/unk/stp/dck) in rv_stats as a new vuln:type:hit/seen
            field. This data has been silently tracked since the vuln
            system shipped but was write-only -- nothing ever read it.
            Prompted by a real debug log showing repeated vuln_lby
            misses for multiple players at high reported hit-chance;
            didn't wire a live trust gate off that alone (not enough
            samples in one log to pick a real threshold without
            guessing, and vuln corrections are deterministic by design --
            gating them wrong risks the same corruption a bad flip
            would cause). This is the diagnostic step first: next debug
            log + an rv_stats call will show real per-type hit ratios
            per player, which is what an eventual per-player vuln-type
            trust gate (mirroring the 6lex agree/disagree calibration)
            should be calibrated against, not guesses.
    v4.6 – Force Shot indicator visual fixes: was small unboxed default-
            size text sitting dead-center on top of the crosshair/enemy
            model. Moved to 140px above center, added a dark backing box
            + thin colored accent line (same visual language as the main
            panel), and switched the text to bold+enlarged+centered
            ("+bc" flags, per docs.gamesense.gs/docs/api/renderer/text --
            "+" enlarges, "b" bolds, "c" centers).

    v4.5 – Force Shot indicator (first ragebot-adjacent addition, kept
            fully separate from the resolver pipeline). Investigated a
            real "Force Shot" from a neverlose script for this: it turned
            out to just force a fixed hit_chance=45 and override two
            Scout-specific auto-stop menu items via pui.find():override(),
            not real spread-seed prediction. Confirmed against
            docs.gamesense.gs that gamesense's Lua API has no equivalent
            (no ui.override, and client.random_float/random_int are
            generic RNG with no documented tie to the engine's own spread
            generator) -- so neither the neverlose mechanism nor genuine
            spread-seed prediction is implementable here. Instead this
            reuses RIFTVEIL's OWN already-computed resolver confidence:
            shows a screen-center "FORCE SHOT" prompt when
            client.current_threat() has an open vuln window OR a
            resolved override at/above the new FORCESHOT_CONF (0.55,
            stricter than the ESP "resolved" threshold since this asks
            the player to commit to a shot). Purely a visual indicator --
            never touches any rage/hit-chance/menu setting, since
            gamesense has no override+restore primitive to safely undo
            that if the script ever crashed mid-override.
    v4.4 – Per-CONDITION hit-side memory. hit_side/hit_count were a
            single global value per player, overwritten on every confirmed
            head/neck hit regardless of movement state. Confirmed via
            vandal.lua's own local-AA menu that this is wrong: it defines
            8 fully independent per-state desync configs (default/
            standing/moving/in air/slowwalking/crouching/crouch moving/
            crouch in air), each with its own yaw/side -- meaning a real
            enemy AA can legitimately desync a different side depending
            purely on whether they're standing vs. moving vs. crouching.
            A single global hit_side gets clobbered the instant the enemy
            changes state, causing hit_mem to misfire in whichever state
            it wasn't last learned in. Added hit_side_by_state/
            hit_count_by_state, keyed by the same STATE.* strings
            ClassifyState already produces (rec.state) -- no new state
            machine needed. on_aim_hit now records the confirmed side
            under the state active at fire time (SHOTS[].state, new);
            the [3] hit-mem override branch prefers the current state's
            own memory once it has >=2 confirmed hits, falling back to
            the old global scalar for states with no data yet. A hit_mem
            MISS now invalidates only that specific state's entry (the
            enemy demonstrably desyncs differently there) instead of
            leaving stale wrong data in place, while leaving proven-good
            memory for other states untouched. Also cleared on soft
            reset alongside the global fields. Visible via rv_stats'
            new cond[N]:state:+/-1,... field.
    v4.3 – console_input now returns true after handling any rv_* command
            (rv_stats/rv_db/rv_clear/rv_reset/rv_wipe). Per
            docs.gamesense.gs/docs/events/console_input, returning true
            suppresses the engine's own command processing; without it,
            since rv_* isn't a real registered concommand, the engine
            ALSO tried to process it after our handler ran and printed
            "Unknown command: rv_stats" right below our own output every
            single time -- confirmed via a user screenshot. Purely
            cosmetic console noise, now gone.
    v4.2 – Fixed backtrack-depth learning: e.backtrack (aim_fire event)
            is documented as a TIME value in seconds, not a tick count --
            confirmed against docs.gamesense.gs/docs/events/aim_fire,
            whose own example converts it with globals.toticks() before
            use. We were storing the raw seconds value and comparing it
            against the 1..16 TICK range everywhere else (bt_hist,
            preferred_bt, rv_stats, every hit/miss log line) -- a real
            backtrack of a few ticks is a tiny fraction of a second, so
            that comparison was false almost always. This is why every
            single hit/miss line in every debug log ever pulled from
            this script shows "bt=0", even for players clearly being
            backtracked with large vuln swings. Fixed by converting
            through the existing TT() tick-rounding helper (same one
            used for m_flSimulationTime elsewhere) instead of the
            un-verified globals.toticks(). preferred_bt-based backtrack
            depth learning should now actually learn.
    v4.1 – Per-player 6lex trust calibration, inspired by vandal.lua's
            own per-opponent learning in resolver_on_miss -- but adapted
            to validate against CONFIRMED HEAD/NECK HITS instead of
            misses, since a hit proves which side was actually real and
            a miss doesn't. Every confirmed hit now compares what 6lex
            claimed at fire time against the established real side
            (six_agree/six_disagree, tracked in on_aim_hit). Once 6lex
            has been proven wrong for a specific player by more than a
            small margin over how often it's been right, both the
            override gate and the side-tracking fallback stop trusting
            it for THAT player and fall through to hit-mem/suppress --
            doesn't touch the extraction formula itself, only how much
            its output is trusted per-opponent. Visible via rv_stats
            (6lex:agree/total). Not reset on soft-reset: it reflects a
            physical property of that player's animation data, not our
            tracked-side confidence, so an unrelated miss streak
            shouldn't erase evidence 6lex has already been wrong for them.
    v4.0 – Two resolver-adjacent additions from reviewing vandal.lua and
            re-reading lagcomp_box.lua more closely:
            (1) plist "High priority" is now set true whenever we have
            an active override and false when releasing to builtin/
            clearing -- confirmed via a real resolver's own usage
            ("prevent missing LC" per its comment), not in the official
            docs, so treated as a hint rather than core functionality
            (set last in each block so a bad field name can't stop the
            actual Force body yaw / Correction active calls before it).
            (2) The SHIFT flash from v3.9 now also draws a full 3D
            wireframe box at the extrapolated real position (velocity +
            gravity + trace_line projection, ported from lagcomp_box.lua)
            with a tether line back to the reported origin. Rebuilt the
            box's corner/edge math from scratch rather than copying that
            file's edge list directly -- it mixes 0- and 1-based Lua
            table indices, silently dropping 3 of its intended 12 edges.
            Extrapolation is purely cosmetic and pcall-wrapped throughout
            with a same-tick fallback; it cannot affect any resolver
            decision, only where the box is drawn.
    v3.9 – Menu polish pass: section headers restyled (◆/▸ instead of
            plain "--" dividers), same items, no new bloat. Added a
            customizable panel accent color picker -- only tints the
            idle/neutral chrome (header text, idle top-strip); the vuln/
            resolved/building colors in the panel stay fixed since they
            carry meaning, not taste. Added a world-space "SHIFT" flash:
            a brief fading tag over any live enemy whose origin-jump
            check just fired, inspired by a standalone "lag comp
            breaker" ESP tool (same w2s/trace_line technique, same
            frametime-based decay) but kept to a simple text tag to
            match RIFTVEIL's own minimal visual language rather than
            importing a second HUD style wholesale.
    v3.8 – DB saves were only automatic on match-end/level_init/shutdown/
            disconnect -- a crash, force-quit, or a bad server disconnect
            between those events meant that session's progress against an
            opponent was never written, requiring the manual "Save match
            to DB" button as a workaround. Added a periodic autosave:
            every 60s, if there's an active match (REC non-empty), Update()
            flushes to the permanent DB on its own. Manual save/reset/wipe
            controls are unchanged and still work the same.
    v3.7 – Added a real full-DB-wipe (button "Wipe ALL saved DB" +
            console command rv_wipe). "Reset match + DB" can only clear
            DB[s64] for players CURRENTLY loaded into REC that session --
            it has no way to touch a profile for an opponent not seen
            yet this session. That reads as "old players keep coming
            back after I reset" when it's really DB persistence working
            exactly as designed, just outside that button's scope. This
            new control empties the entire permanent database instead.
    v3.6 – Renamed "Flush DB" to "Save match to DB" and "Reset match" to
            "Reset match + DB" -- the old names caused real confusion:
            "Flush DB" reads like a clear/reset action but has always
            done the opposite (persists the current match into the
            permanent DB, merging with existing entries -- exactly what
            EndMatch already does automatically). No behavior changed,
            only the labels; "Reset match" was always the actual clear
            control.
    v3.5 – The panel's H/M header wasn't a hit/miss scoreboard, despite
            looking like one: it summed hit_count (head/neck-confirmed
            hits ONLY -- 27 of 77 real hits in the reference log) and
            resolver_misses (non-vuln misses ONLY, by design -- most
            misses happen during vuln windows and deliberately don't
            count there). Added real total_hits/total_misses fields,
            incremented on every genuine (non-discarded) aim_hit/
            aim_miss, and pointed the panel header and rv_stats at those
            instead. hit_count/resolver_misses are untouched and still
            drive hit_mem/soft-reset exactly as before -- this only fixes
            what gets displayed as "misses". Also fixed the init log
            line, which hardcoded "v2.3" as a separate literal from the
            banner above and had silently drifted for the entire session
            (still printing "v2.3 loaded" as of v3.4) -- now reads from a
            single RV_VERSION constant.
    v3.4 – Shifting guard upgraded with a direct signal: a >64-unit
            (4096 sq-unit) origin teleport on a clean (choke==0) tick now
            sets _shift_streak straight to the distrust floor instead of
            only inferring shifts indirectly from missing tm[] lookback
            slots. This exact threshold is independently confirmed in two
            real production resolvers (a public CS:GO lagrecord library,
            and a full HvH cheat script's own broke_lc check) -- not a
            guess. Origin comparison resets across any tick gap (GetAS
            miss, choke>2) the same way prev_pose already does, so it
            can't misfire by comparing across a skipped span of normal
            movement.
    v3.3 – on_aim_miss couldn't tell a real resolver miss from two other
            failure modes it was silently lumping in as "reason=?":
            (1) event timeout -- aim_miss firing >=0.5s after aim_fire
            means the event never got a clean resolution at all, not a
            real outcome; (2) damage rejected -- m_totalHitsOnServer
            moved between fire and miss despite reason=="?", meaning a
            hit landed server-side and the client-side miss event is a
            hit-registration quirk, not evidence our angle was wrong.
            Both used to feed straight into resolver_misses/flip/soft-
            reset as if they were genuine wrong-angle misses. Adapted
            from a public aim-event-logging reference; now discarded
            before touching any resolver state, logged separately
            (verbose only) instead of counted.
    v3.2 – Fixed config-recognition thrashing found in a real 12min match
            log: one player flipped luasense_beta/std/symmetric 22 times
            because those profiles sit only 4-9deg apart and noisy per-
            tick pose sampling alone tipped RecognizeCfg's "best match"
            every 32-tick recheck. Added switch hysteresis (a rival must
            beat the current pick by CFG_SWITCH_MARGIN, not just edge it
            out) plus TrustedCfg() gating every CfgAngle call on
            config_conf >= CFG_THRESH -- CFG_THRESH's own comment always
            said this was required, but nothing enforced it, so every
            flip (config_conf reset to 0.30) fed straight into the
            applied correction angle, up to 6-11deg of angle churn per
            switch with zero new evidence behind it. Log also confirmed:
            68.8% overall hit rate (77/112) across 3 real opponents,
            DB persistence working correctly (writes once hit_count>=2),
            no meta_aggressive false positives.
    v3.1 – ESP flags cut from 7 to 2 (VLN, RES). 6LX/HIT/SUP/DTB/MYW
            removed -- all five were internal diagnostics (which data
            source fired, whether a struct read succeeded) spammed onto
            every enemy's ESP box regardless of whether it meant anything
            actionable. HIT's meaning was already a subset of RES; SUP/
            DTB/config context still show in the v3.0 panel for whichever
            enemy is your current threat, where they belong -- one flag
            per real decision point (shoot now / trust this angle),
            nothing that's just plumbing confirmation.
    v3.0 – HUD rebuilt as a single draggable panel (Solus-UI style)
            instead of stacked renderer.indicator rows. Position
            persists through two hidden ui.new_slider values (survives
            config save/load and reload -- a plain Lua local wouldn't),
            drag by holding left-click on the title bar, gated to the
            menu being open so it can never grab the panel mid-fight
            while you're holding down fire. Dark panel body, thin
            border, and a 2px top accent strip that recolors with
            resolver state (blue idle / red vuln / green resolved /
            amber building) so the state reads before you read a word.
            Same content as v2.6's condensed lines, now inside one
            self-contained box instead of floating text on the HUD.
    v2.6 – Overlay condensed from 6 indicator rows to 3-4: identity
            (name/AA/conf) and status (vuln/resolved/method/angle) merged
            into one line, carried by the leading glyph+color (⚡ red /
            ● green / ○ gray) instead of separate rows; side-meter and
            supplemental tags (bt/config/def/spk/agg) merged into another.
            Header shortened to "RV". Off-angle row unchanged. Same
            information, half the vertical footprint -- was reading as
            HUD spam rather than a glance-able readout.
    v2.5 – Performance pass: GetLat() (3 pcall-wrapped FFI calls) was
            being called once per player per tick via ChokedPkts, again
            per LAGCOMP check via LCTicks, AND every single rendered
            frame in DrawOverlay's spike check -- latency isn't a
            per-player value, so all three now read the ctx.cur_lat/
            avg_lat already computed once per net_update in Update()
            (cached to LAST_SPIKE for DrawOverlay). DrawOverlay's
            off-angle row was also calling entity.get_players() +
            is_enemy/is_alive on every paint frame (allocates a fresh
            table every frame); it now reads LIVE_ENEMIES, populated for
            free inside Update()'s existing per-tick player loop. Net
            effect: paint no longer touches GetLat, client.latency, or
            entity.get_players() at all -- it was doing all three, every
            frame, regardless of framerate.
    v2.4 – Velocity-constrained desync: CfgAngle guesses now clamp to
            VelCap(spd) (58°→0° linear falloff by VEL_CAP_SPD=580u/s),
            kept separate from LiveCap so fast mouse-turns don't get
            misread as body jitter. New PKA vuln window (peek
            acceleration: stopped→fast mirrors STP, catches torso before
            body-yaw-delay AAs catch up post-peek). DB-seeded confidence:
            repeat opponents with a proven prior (3+ kills, >50% hit
            rate) skip the cold-start conf ramp -- matters in short 2v2
            engagements. Shifting guard on LAGCOMP/PHASE: a choke==0 tick
            with a missing tm[] lookback slot now counts against trust
            instead of silently falling through. Overlay redesign:
            tighter techy separators (│ ·), status dots (●/○) replacing
            check/cross glyphs, finer 10-segment side meter (■/·), and a
            new off-angle awareness line for the second live enemy.
            Blind-guess brute cycle: the true last-resort meta_aggressive
            path (zero side data at all) now cycles side+half/full
            magnitude across ticks (NIXWARE-style) instead of freezing on
            one static guess. CanSeeHead: the "standing = fully exposed"
            vuln TTL boost is now trace-verified (client.trace_line)
            instead of inferred from velocity/duck/ground alone; fails
            open so a bad trace never costs a boost the old code granted.
    v2.3 – 6-script counter batch (serenity, aesthetic×2, ambani,
            testarossa, gasolina). TorsoCluster (circular mean, W=7,
            THR=25) counters ways()/sanya/Bobro/random-limits.
            Faszsag near-zero skip (torpedo counter). meta_aggressive:
            builtin_miss_streak triggers RIFTVEIL full-control mode;
            META_HOLD tier; suppress threshold 0.45→0.28 (starves
            testarossa AB). Bug fixes: circular mean wrap-around at
            ±180°; builtin_miss_streak reset out of in_vuln gate.
            Improvement pass: STP two-tick velocity confirmation
            (gasolina fluctuate_fakelag counter); DCK 10-tick cooldown
            (fake_duck spam counter); suppress streak cap 8+4 ticks
            (hxlw1ss 375/914 stuck-suppress fix); UNK conf boost when
            torso within live cap bounds; torso_hist cleared on soft
            reset; _sup_streak and _dck_cooldown in NewRec.
    v2.2 – Log analysis (55k lines, 453 hits): fixed [corr] noise —
            only emit on method/val change (was 98% stale TTL echoes).
            DrawOverlay simplified: 1 resolver status (✔/✘/⚡) + side
            bar (◀/▶ with conf fill), blue=L orange=R gray=unknown.
            SideBar() helper. Removed MethodColor/ConfBar.
    v2.1 – Live desync bounds (as.min_yaw/max_yaw), get_desync() probe,
            7 descriptive ESP flags, 5-row overlay with conf bar
    v2.0 – Refactor: CFG table, named enums, ProcessPlayer split,
            single pcall per player, REC shape docs, consistent style
    v1.2 – Bug fixes: update_player_list order, BUG4 prev_pose reset,
            nil-concat crash, SHOTS prune, double seen increment
    v1.1 – Skeet-style indicators, ESP flags, menu redesign
    v1.0 – Initial: two-tier memory, 6lex, period prediction, vuln
```
