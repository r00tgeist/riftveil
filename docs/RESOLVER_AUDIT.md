# Resolver audit (v8.32, full review v8.34)

Every function on the path from a network update to the value written into
the player list, checked for what it reads, what it feeds, whether it fires
in the 24 uploaded debug logs (v2.3 to v8.29), and how its shots land. Head rate = head hits /
(head hits + resolver misses), the measure `tools/log_report.lua` uses.

## The question behind every row: who wrote the number we read?

CS:GO sends some of an enemy's state from the server. The client computes
the rest itself, and those computed values are where gamesense's resolver,
and our own Force body yaw, put their answer.

| Source | Values | Can carry our own output? |
|---|---|---|
| **Server** | simulation time, origin, eye angles (`m_angEyeAngles`), LBY target, duck amount, flags, animation layers | no |
| **Client, from server data** | velocity, animstate speed / on-ground / duck copies | no |
| **Client, resolved** | body-yaw pose parameter (`m_flPoseParameter` 11), animstate goal-feet / current-feet / torso yaw | **yes** |

Players' pose parameters are not networked (the animation-breaker scripts in
the repo write them on the local player every frame, which only works because
they are client-side). Suspected effect: when we force ±35, the next record's
pose reads ±35. Signs in the logs: hit memory (one constant value) carries
the `hold` label on 50% of its lines against 11% when nothing is forced.
v8.32 logs `pz=` (pose read) and `pf=` (what we forced) on every `[corr]`
line, and log_report's `POSE READ BACK vs WHAT WE FORCED` settles it.

## Inputs

| Function | Reads | Feeds | Verdict |
|---|---|---|---|
| `ChokedPkts` | server simtime, our latency | UNK trigger, stale-record skip | **keep**. It measures how stale the newest record is (climbs on updates with no new record), not the choke count; correct for what uses it |
| `TrackDT` / `IsDefTick` | server simtime vs our tickcount | DEF_TICK branch, `fl=d` | keep; rare |
| `LiveCap` | animstate min / max yaw | hit memory cap, 6lex clamp | **misnamed**: ±58 on 97% of 16.7k samples -- the fixed aim limits, not speed-scaled. Use `MaxDesync` for any speed-aware cap |
| `VelCap` | velocity | correction cap (v6.2) | **replaced** (`DESYNC_FORMULA`): a line to 0 at 580 u/s; the engine never goes under half the cap |
| `MaxDesync` (v8.32) | velocity, weapon max speed, animstate walk-to-run, duck | correction cap | new; Valve's SetUpVelocity formula as antiaim_funcs computes it; harness-checked |
| `EnemyMaxSpeed` | weapon, scoped | state tracker, `MaxDesync` | keep |
| `TrackState` / `ClassifyState` | velocity, flags, duck, weapon | per-state tables, hit memory by state | keep (state tracker audit: 91.7% vs 93.1% ceiling) |
| `Extract6Lex` | animation layer 6 (server) | 6lex side (Desync angle option) | never forced in any log; digit decoding of a server float is folklore (Nek0o). **Drop candidate** |
| pose (`m_flPoseParameter` 11) | client, resolved | ring history, AA type, side, flips, config recogniser, LBY / CTR triggers, lag-comp side | **suspect** -- see above; decided by the probe |

## AA picture

**Bots prove the pose isn't theirs.** 64 shots at bots (no AA, no desync):
labelled hold 27, 2-way 15, 3-way 9, static 8, skitter 3, 5-way 2; we forced
a value on 54. v8.33 `NO_CHOKE_STATIC` makes any enemy whose records come one
tick apart static (desync needs choked commands) -- server timing, not pose.


| Function | Reads | Verdict |
|---|---|---|
| `DetectAA`, `PoseVar`, `IsHold`, `CountClusters`, `IsSkitter` | pose history | Logic sound (v8.28 checks). Input suspect. Skitter is a phase-locked match that never sticks; after a resolver miss it still landed 11/11, so it stays out of the x-way safe point |
| `MeanSidePose` -> `RecognizeCfg` -> `TrustedCfg` | pose history | **circular if the pose is ours**: forcing the fallback 24/41 makes the pose read 24/41, which "recognises" luasense; forcing ±35 confirms "symmetric". v8.28 fixed its cadence; whether it measures the enemy at all waits on the probe |
| `YawSide` | server eye-yaw history | sound in idea (Synaple's method), but compares the eye with an average that already contains it; never reached (needs conf < 0.6 after every branch above). **Fix or drop** |
| `PredictSide` | flip times | `JITTER_PRED` off; never executed. **Drop** |
| `TorsoCluster` | animstate torso (client) | feeds UNK; fine as a smoother |

## Side

| Branch | Fires in logs | Verdict |
|---|---|---|
| hit memory (global + per state) | 341 shots, 67% | keep. Value now capped by the engine limit; taught by vuln hits 4/8 on head-aimed shots, like the rest |
| 6lex | 0 | drop candidate (above) |
| lag-comp / phase / DEF_TICK / RING_SPK / yaw cache | never as the forced method; they only steer suppress's side | keep until the side is rebased (plan step 2) |
| symmetric flip, meta hold brute | meta hold never logged | brute index advances per tick, not per miss; **drop** with step 2 |
| `rec.flip` on resolver misses | every non-vuln miss | keep (v6.2) |

## Value written

| Method | Shots | Head rate | Value source | Verdict |
|---|---|---|---|---|
| vuln UNK | 1,059 | 54% raw era; **70%** with v8.29 delta | torso - eye, capped | fixed in v8.29 |
| vuln LBY | 629 | 61% | table angle for the side opposite the pose collapse | trigger is a pose collapse: on 3/5-way that is the centre pass, and if the pose is ours, our own switch. Watch (table in log_report) |
| hit memory | 498 | 67% | table angle, live cap | keep; magnitude in plan step 3 |
| suppress | 385 | 70% | minus the table angle for the tracked side | **keep**: 2-way 92%, skitter 83%, 3-way 72%, hold 69%; 5-way 56% (16) is the only weak spot |
| vuln DCK | 281 | 77% | torso world yaw (unit mismatch) | best method despite the units; don't touch without data |
| vuln LND | 59 | 61% | the eye's world yaw (unit mismatch) | move to delta / side value when it has 20+ decided shots |
| vuln STP / PKA / CTR | 28 / 23 / 22 | 67% / 47% / 50% | goal-feet / torso world yaw, pose | same as LND |
| builtin | 176 | 65% | gamesense | the reference everything must beat |

Forced magnitude, side-based methods (hit memory, LBY): right side 30-39
deg 66%, 40-60 deg 77%; left side never gets past 32 because the tables are
luasense yaw offsets (left smaller). Under 20 deg is the weakest band for
every method (side ~45%, suppress 33%) -- most of those came from VelCap on
fast enemies, which `DESYNC_FORMULA` ends.

## Presets

`KNOWN_CFGS` / `CFG_COUNTER` / `ASYM_FALLBACK` hold luasense **yaw
offsets** (24/41, 30/38, 35/35) and write them as the **body yaw**. What a
player actually desyncs by is the body-yaw limit:

- 211 of 330 limit sliders in the repo's gamesense AA scripts default to 60
  (248 cap at 60);
- the median limit in decodable settings exports is 60 in every state; 15
  of 18 Neverlose presets run 58-60;
- what differs between luasense and the other 30-40 scripts -- and between
  settings inside luasense -- is the yaw jitter shape and the side pattern.

So no number of presets covers them; a model that doesn't need them does:
side x the engine's limit for that frame, with the magnitude learned per
enemy from where heads land (plan step 3).

## Plumbing found broken

- **Debug log checkbox dead since v8.1**: `SyncFlags` set `DET.verbose`
  from itself, so no `[corr]` / `[vuln]` / `[cfg]` / `[dcap]` line was
  written for 30 versions -- the v8.x logs only ever had shot lines. Fixed
  in v8.32; the probe and the phantom-DCK counter depend on it.

## Aim policy and delay

Safe point at fire: 3% (v8.8), 9% (v8.24), **15% (v8.27)**, 4% (v8.28),
7% (v8.29) -- the "delay" period and its end line up with it; suppress
changes no timing. Plan step 4 adds a wait measurement.

## Full review (v8.34)

Every function on the path read in full, records to plist writes to shot
events.

| Finding | Fix |
|---|---|
| A counting vuln window that isn't forced (Vulnerability off, cheat distrust, low confidence) blocked the side chain and suppress for 11 records | `WINDOW_GATE` |
| Round start cleared the player list but not each record's method / value / window | `STALE_WINDOW` (round start) |
| gamesense's own hit didn't end its miss streak (meta takeover on miss, hit, miss) | `META_STREAK` |
| Forced safe point: 47-50% head rate vs 57% default, 86% head kill; it is the waiting | `NO_SAFEPOINT` |
| `preferred_bt`, `vuln_pref`: learned, saved, shown -- never used | none (display) |
| No side signal from server data | logged: `eo=`, `lbyu=` |
| Vuln windows need pose-derived confidence >= 0.20 to even be detected | plan step 2 (rebased with the pose) |
| Saved profiles bring the recognised preset back at 0.5 trust -- enough to apply | plan step 3 (presets retired) |

## v8.35

The two root problems above are handled in code: `POSE_CLEAN` (detection
reads only records with nothing forced) and `FULL_DESYNC` (side x engine
limit, no preset tables).
