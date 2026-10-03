# RIFTVEIL roadmap and status

Updated with every release. What is in the script, what is waiting on data,
and what comes next. Older versions are kept in `versions/` so none of the
work is lost: `riftveil_v6.2.lua` (the 74% resolver), `riftveil_v7.9.lua`
(the decision engine), `riftveil_v8.1.lua`.

## In the script (v8.47)

| Area | Feature | Changes shots? |
|---|---|---|
| Core | v6.2 decision chain: vulnerability windows, 6lex, hit memory, suppress, meta hold | yes, the core |
| Core | Condition tracker by movement physics: slow walk vs peek, weapon/scope-aware thresholds, fake duck, unreadable flags/velocity (91.7% vs a 93.1% ceiling in tools/state_test.lua) | yes, `FEATURE.STATE_PHYSICS` |
| Cheats | Built-in cheat revealer (voice packets, 11 cheats), ESP flag, panel | no |
| Cheats | Gamesense Lua presets only for gamesense users | yes, with Cheat profiles on |
| Cheats | Per-(cheat, method) learned trust, saved across sessions | yes, once a method fails 8+ shots on a cheat |
| UI | v7.9 menu, info panel, VLN/RES/cheat flags, SHIFT marker | no |
| Speed | Player-list writes only on change (-68% writes), player list refreshed once a second | no |
| Logging | Every shot: `st= wpn= hp= ar= aim= pdmg= cf= cht=`; bounded log, flushed each round | no |
| UI | Local lagcomp box: red 0.5 s flash where a double-tap shot's shift puts us, only on our shot with DT on followed by the teleport (shift > 2 ticks within 0.25 s), extrapolated by the shifted ticks; the shot is seen client-side (predicted last-shot time, aim_fire), so manual shots count too (v8.40) | no (Indicators › Local lagcomp) |
| Logging | Shot log (console + top-left, via print like the original), `[id] [fire/now] Missed x's head(98)(76%) due to spread:1.84°` plus who resolved the shot (RIFTVEIL method + forced yaw, or GAMESENSE), AA, policy, flags, chokes | no (Indicators › Shot log) |
| Tools | `rv_perf` profiler, `rv_stats`, `rv_db`, `rv_save` | no |
| Weapons | Aim policy on traced damage: prefer body only when a body shot kills from here, body preference off when only the head kills, safe point when in doubt or airborne; values verified, traces self-calibrated | yes, Detection › Weapon aim |
| Weapons | "In doubt" includes a 3-way / 5-way enemy missed on the resolver in the last 10 s (43% head there in the pre-v8 logs vs 59-77% elsewhere) | measured only since v8.34 (it fed safe point) |
| Core | Force only on knowledge: hit memory (confirmed head hit) and event windows (unchoke / stop / peek / landing / duck); everything else is gamesense's own resolver -- suppress, meta hold, LBY / CTR windows no longer force | yes, `FEATURE.KNOWN_ONLY` |
| Core | Hit memory stores the side that was on the hitbox (forced value's sign / gamesense's answer); its own miss drops it; vuln windows only from clean records; stop / peek / landing values eye-relative | yes, `LEARN_GS`, `KNOWN_ONLY`, `POSE_CLEAN`, `VULN_DELTA` |
| Core | Hit memory is signed evidence weighted by our weapon (awp/scout/auto/deagle 1 ... shotgun 0) and the hitbox (aimed head -> head 1, neck 0.5; stray head hit 0): a +, - pair cancels; a resolver miss on the remembered side takes twice its weight; `[hmem]` line for every learn / weaken / skip | yes, `FEATURE.HMEM_WEIGHT` |
| Core | Defensive phase (any defensive frame in the last second) has its own hit memory ("def"): the landed side repeats 41/78 there vs 63/87 outside, so the overall memory isn't used in it; event windows still force | yes, `FEATURE.DEF_PHASE` (replaced v8.43's release) |
| Core | Opening shot at a defensive enemy (no shot for 5 s) is gamesense's probe; follow-ups resolved (opening: gamesense 69% vs forced 54%; follow-ups forced 76%) | yes, `FEATURE.DEF_OPEN` |
| Core | After a resolver miss, that side is off limits for 3 s (next shot after a miss: 73% on the other side, 55% on the same -- which was shot 2 times in 3) | yes, `FEATURE.MISS_FLIP` |
| Core | Defensive phase held until 3 s without a defensive frame (gaps under 2 s 79% of the time); a confirmed hit memory beats a window of the other sign | yes, `FEATURE.DEF_HOLD`, `FEATURE.MEM_FIRST` |
| Core | Duck windows force torso - eye within the frame's limit (were the torso's world yaw, clamped: side by map direction) | yes, `FEATURE.DCK_DELTA` |
| Weapons | Damage calibration only from current-eye traces made at most 2 ticks before the shot (stale best-of-two-eyes traces calibrated x1.52) | yes, `FEATURE.CAL_FRESH` |
| Core | Learn from gamesense: its resolved answer (pose on unforced records) is kept, logged as `gs=`, and filed by hit memory when its own shot lands the head | yes, `FEATURE.LEARN_GS` |
| Core | (v8.36 stats rule, off: a method forced while its head rate kept up with gamesense's) | `FEATURE.BEAT_BUILTIN` = false |
| Core | AA picture, side, flips and LBY / CTR windows only from records built with nothing forced (the pose is our client's; forced records read our own value back) | yes, `FEATURE.POSE_CLEAN` |
| Core | Forced value = side x the engine's desync limit for that frame, for every lua and setting -- no luasense tables | yes, `FEATURE.FULL_DESYNC` |
| Core | Only a forced vuln window stands the side chain and suppress down; round start clears what each record forces; gamesense's own hit ends its miss streak | yes, `WINDOW_GATE`, `STALE_WINDOW`, `META_STREAK` |
| Weapons | No forced safe point (it landed 47-50% against 57% default and 86% head-kill, and made the ragebot wait) | yes, `FEATURE.NO_SAFEPOINT` |
| Logging | Shot lines: `eo=` (eye yaw vs facing away from us) and `lbyu=` (time since their LBY target moved) -- side signals the server sends, tested by log_report | no |
| Core | Enemy sending every tick (no choke: bots, no-AA players) = static, handed to gamesense -- desync needs choked commands | yes, `FEATURE.NO_CHOKE_STATIC` |
| Core | Correction cap = Valve's per-frame body-yaw limit (58 standing, 29 running), not a line to 0 at 580 u/s | yes, `FEATURE.DESYNC_FORMULA` |
| Logging | Debug log checkbox works again (dead v8.1-8.31); `[corr]` lines carry the pose read back (`pz=`) and what we forced (`pf=`) -- plan step 2 is decided on them | no |
| Core | UNK windows force torso - eye within the cap, not the torso world yaw (v7.2 fix, retried on the v8.28 trigger: raw 36% since v8.15) | yes, `FEATURE.UNK_DELTA` |
| Core | v6.2 defect fixes: a released enemy's shots count as builtin and stale vuln windows close (`STALE_WINDOW`); no DCK window without a real duck crossing (`DCK_GAP`); config recognition every 32 sim ticks whatever the record cadence (`CFG_CADENCE`) | yes, each its own flag, off in the parity run |

Every release proves with `tools/check_all.sh` step 7 that, with the
post-v6.2 features off, the script forces the same side and value as v6.2.

## First match log on v8.x (v8.8, 43 resolver-decided shots)

1. **Head rate is back: 70% (30/43, 95% interval 55-81%)** on
   resolver-decided shots, against v6.2's 74% and v6.7-v7.9's 49%.
2. **Condition detection:** slowmotion 83% (10/12), running 71% (5/7);
   standing 1/4 and air 2/5 are too few to judge. Stays on.
3. **Aim policy:** every value read back fine (prefer body On / Off,
   safe point On). "head" (only the head kills) 7 head hits, 0 misses;
   "body" 14 body + 2 head hits, 0 misses. Trace calibration x1.00 over
   17 body shots: gamesense's traces are already final.
4. **Cheat revealer fires:** gamesense and neverlose detected; nl 77%,
   gs 67% head rate.
5. **Defensive frames:** 86% (18/21) with 0-8 in the second before the
   shot, 55% (12/22) with 9+ (Fisher p 0.045, 4 of 5 players). Acted on
   in v8.10 (FEATURE.SKIP_DEF_FRAMES); the next log's BY DEFENSIVE FRAMES
   shows whether the 9+ row recovers.
6. **Pitch at fire:** off-down (defensive) pitch didn't cost heads
   (6 head, 1 miss); the frame count matters, not the pitch on the shot.
7. **Seeded start 86% (12/14) vs cold start 60% (18/30):** the inflated
   seed (Next 4) doesn't hurt; it stays.

## From the repo survey (docs/REPO_SURVEY.md), each waiting on its log table

- **Force pitch on a pitch breaker** -- `BY ENEMY PITCH AT FIRE`.
- **Hit memory inside the anti-bruteforce window** -- `BY PREVIOUS SHOT AT
  THEM` / `BY TIME SINCE OUR LAST SHOT AT THEM`.
- **Freestand side** -- needs its own log field first.
- **Correction magnitude -- checked, no change.** Overall, forced values
  under 20 hit 51% (33/65) vs 64% (p 0.053), but within each method the gap
  disappears (vuln_lby 50% vs 56%, vuln_unk 53% vs 59%, vuln_dck 75% vs
  78%): the dip was vuln_lby producing most small values. hit_mem /
  suppress under 20 went 2/8, too few. log_report now has BY FORCED VALUE
  PER METHOD to keep checking.
- **Low-offset neverlose family** (chimera / idealyaw / exscord, ~10/20) as
  a fingerprint -- no evidence either way; not added.

## v8.15: 3-way / 5-way after a resolver miss

From the "take the AA scripts' patterns" pass. x-way (57% of neverlose AA
scripts, 24% of gamesense) and anti-bruteforce (59% / 36%) come together;
the pre-v8 debug logs show what that does to us. Head rate on the next shot
at a 3/5-way enemy within 10 s of a resolver miss on them: **43% (25/58)**,
against 59% for the same enemies otherwise and 77% for other AA after a miss
(p 0.023 / 0.001; 9 of 12 logs at or under 50%). By AA type overall: 5-way
56%, 3-way 59%, hold 69%, 2-way 75%, skitter 79%.

No side choice fixed it (kept 32%, flipped 48%, hit memory 3/16), so v8.15
changes the aim policy instead: that enemy counts as "side in doubt" and the
head is taken on safe points. Shot lines now carry `aa=`; log_report has
`BY AA TYPE` and `3/5-WAY AFTER A RESOLVER MISS ON THEM`. The next log
decides it: the first row's `pol=` shows `headsp` / `sp`, and its head rate
and body share against the old 43% say whether safe point paid.

## Lead from the v8.26 bug hunt (not changed)

Hit memory replays the side learned from a head hit (`d.side`, flipped if
the shot was flipped). Across methods the logged side and the forced value
don't share a sign convention: suppress logs them opposite (99%), hit memory
the same (95%), vuln 50/50. Hit-memory shots taught by a vuln head hit land
51% (22/43) when their value's sign is opposite to the teaching hit's and
66% (21/32) when it matches (p ~0.24). If a bigger log keeps that gap,
teach hit memory the forced value's sign instead of the tracked side.

## The plan from here

`docs/PLAN.md` (steps 1-6, each with the log_report table that decides it)
and `docs/RESOLVER_AUDIT.md` (every resolver function, verdict and evidence).

## Watch list from the v8.28 bug hunt (not changed)

- **vuln_unk values** -- triggered and done in v8.29 (`UNK_DELTA`: raw
  36% since v8.15, p 0.01). Judge it on `BY METHOD` vuln_unk head rate in
  the next logs: the delta era measured 59%. If it comes back under the
  raw era's 55% overall, switch the flag off. First v8.29 match: 78%
  (7 head / 2 resolver misses, every value inside +-58; raw since v8.15
  11/31, p 0.05). The one world-yaw window shot (vuln_lnd 145) missed.
  Same session, 60 shots: vuln_unk 7 head / 3 resolver misses (70%), our
  methods together 14 / 6 (70%). Builtin dipped to 2 / 5 there, but is 65%
  (58 / 89) across all logs, so the suppress pause that hands records to it
  stays as v6.2 had it. STP / PKA / LND / DCK / CTR
  still force world yaws (few shots: DCK 67%, the rest n < 10).
- **LBY on 3/5-way** is mostly the jitter's centre pass. `LBY WINDOWS BY AA
  TYPE` in log_report: 59% vs 56% other vuln so far.
- **Phantom DCK windows** (now skipped): the verbose log line
  `type=dck skipped` counts how often v6.2 opened one.

## Next, in order

1. **Aim policy, measured** (`docs/WEAPON_PLAN.md` › Next): kill rate per
   choice and weapon from the `pol= tr=` logs; crouch / fake-duck safe
   point if the data shows it.
2. **Prediction errors not counted as resolver misses** (v6.8). v6.2 flips
   the tracked side on them; it's a candidate once the core is confirmed
   back at v6.2's rate.
3. **Vulnerability window credit fix** (v7.9): score windows on head hits
   and resolver misses only. It never triggered in the logs, so it's low
   value.
4. **Saved hit rate** -- RESOLVED, stays (v8.8 log: seeded 86% vs cold
   60%). FlushDB saves
   hit_count / (hit_count + resolver_misses), but resolver_misses is a
   streak (0 after every hit, 0 again after 3 misses), so the saved rate
   sits near 100% and every player with 3+ hits starts the next match at
   the 0.35 seed cap. v6.2 did the same while it measured 74%, so it stays
   until `BY PROFILE START` in log_report (seeded vs cold start) shows
   whether the seed helps or hurts.
5. **Defensive AA frames** -- DONE in v8.10 (FEATURE.SKIP_DEF_FRAMES),
   on the v8.8 log's numbers above. Found in v8.6, located in v8.7. Every AA
   script uploaded (angelwings, abyss, EmberLash, vandal, viera, the
   unnamed one) has a defensive mode: pitch up / zero / random and yaw
   sideways / opposite / spin / n-way while it shifts tickbase; abyss
   forces it every 7th command while flicking. Lag compensation writes no
   record while a player's simulation time is at or below the highest it
   has sent (tickcount/lagrecord-csgo.lua), so those frames arrive with
   a LOWER simulation time. ProcessPlayer takes any simtime change as a
   new record (`st == rec.lt`), so they go into the pose ring and yaw
   cache, and rec.lt steps backwards. The fix is one line (skip a frame
   below the highest simtime seen) but it changes the v6.2 core, so it
   waits for the log: `df=` counts those frames per shot, and
   `BY DEFENSIVE FRAMES` / `BY ENEMY PITCH AT FIRE` show whether the
   head rate drops with them. Two more sources since v8.7: lagrecord's
   own record loop skips exactly these frames for every player
   (`simulation_time <= records[1].simulation_time`), and tickcount's
   antiaim_funcs opens a "no history" window whenever simtime goes back.
   Also open: antiaim_funcs counts an enemy as shifting when simtime is
   6+ ticks BEHIND server time; our IsDefTick (v6.2) flags 3+ ticks
   AHEAD of our tickcount. `fl=d` against `df=` in the log will show
   which one tracks the real defensive frames.
6. **Decision engine** (v7.2-v7.9, `versions/riftveil_v7.9.lua`): only if
   the logs show a gap it could close. It ran during the drop to 49%.
