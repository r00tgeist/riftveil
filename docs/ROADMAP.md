# RIFTVEIL roadmap and status

Updated with every release. What is in the script, what is waiting on data,
and what comes next. Older versions are kept in `versions/` so none of the
work is lost: `riftveil_v6.2.lua` (the 74% resolver), `riftveil_v7.9.lua`
(the decision engine), `riftveil_v8.1.lua`.

## In the script (v8.25)

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
| UI | Local lagcomp box: red 0.5 s flash where a double-tap shift puts us (tickbase shifted > 2 ticks back or forward), extrapolated by the shifted ticks | no (Indicators › Local lagcomp) |
| Logging | Shot log (console + top-left, via print like the original), `[id] [fire/now] Missed x's head(98)(76%) due to spread:1.84°` plus who resolved the shot (RIFTVEIL method + forced yaw, or GAMESENSE), AA, policy, flags, chokes | no (Indicators › Shot log) |
| Tools | `rv_perf` profiler, `rv_stats`, `rv_db`, `rv_save` | no |
| Weapons | Aim policy on traced damage: prefer body only when a body shot kills from here, body preference off when only the head kills, safe point when in doubt or airborne; values verified, traces self-calibrated | yes, Detection › Weapon aim |
| Weapons | "In doubt" includes a 3-way / 5-way enemy missed on the resolver in the last 10 s (43% head there in the pre-v8 logs vs 59-77% elsewhere) | yes, `FEATURE.XWAY_UNSURE` |

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
