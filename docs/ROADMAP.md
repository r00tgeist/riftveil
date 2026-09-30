# RIFTVEIL roadmap and status

Updated with every release. What is in the script, what is waiting on data,
and what comes next. Older versions are kept in `versions/` so none of the
work is lost: `riftveil_v6.2.lua` (the 74% resolver), `riftveil_v7.9.lua`
(the decision engine), `riftveil_v8.1.lua`.

## In the script (v8.8)

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
| Tools | `rv_perf` profiler, `rv_stats`, `rv_db`, `rv_save` | no |
| Weapons | Aim policy on traced damage: prefer body only when a body shot kills from here, body preference off when only the head kills, safe point when in doubt or airborne; values verified, traces self-calibrated | yes, Detection › Weapon aim |

Every release proves with `tools/check_all.sh` step 7 that, with the
post-v6.2 features off, the script forces the same side and value as v6.2.

## Waiting on a match log

1. **Is the head rate back?** The target is v6.2's 74% on resolver-decided
   shots. `lua5.3 tools/log_report.lua` on the two log files shows it per
   method, state, weapon, cheat and player.
2. **Does condition detection help?** Compare `st=running` and
   `st=slowmotion` against the v6.2-era logs. If it's worse, set
   `FEATURE.STATE_PHYSICS = false` (one word).
3. **Is the aim policy active and calibrated?** The log's `[aim]` lines
   say which player-list values work and the trace calibration factor.
   `BY AIM POLICY` and `TRACE CALIBRATION` in log_report show the rest.
4. **Does the cheat revealer fire in game?** Look for `[cheat] player=...`
   lines, and `[cheat] learned ...` after a save.

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
4. **Saved hit rate** (found in v8.5.6). FlushDB saves
   hit_count / (hit_count + resolver_misses), but resolver_misses is a
   streak (0 after every hit, 0 again after 3 misses), so the saved rate
   sits near 100% and every player with 3+ hits starts the next match at
   the 0.35 seed cap. v6.2 did the same while it measured 74%, so it stays
   until `BY PROFILE START` in log_report (seeded vs cold start) shows
   whether the seed helps or hurts.
5. **Defensive AA frames** (found in v8.6, located in v8.7). Every AA
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
