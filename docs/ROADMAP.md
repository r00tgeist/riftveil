# RIFTVEIL roadmap and status

Updated with every release. What is in the script, what is waiting on data,
and what comes next. Older versions are kept in `versions/` so none of the
work is lost: `riftveil_v6.2.lua` (the 74% resolver), `riftveil_v7.9.lua`
(the decision engine), `riftveil_v8.1.lua`.

## In the script (v8.4)

| Area | Feature | Changes shots? |
|---|---|---|
| Core | v6.2 decision chain: vulnerability windows, 6lex, hit memory, suppress, meta hold | yes, the core |
| Core | Condition detection by movement physics (slow walk vs peek, crouch-move at 5 u/s) | yes, `FEATURE.STATE_PHYSICS` |
| Cheats | Built-in cheat revealer (voice packets, 10 cheats), ESP flag, panel | no |
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
4. **Decision engine** (v7.2-v7.9, `versions/riftveil_v7.9.lua`): only if
   the logs show a gap it could close. It ran during the drop to 49%.
