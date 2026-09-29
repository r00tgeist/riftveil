# RIFTVEIL

A resolver for CS:GO on gamesense.pub, built for 2v2 HvH (unmatched.gg).
One file: `riftveil.lua`. Load it in gamesense under **LUA**; everything
else in this repository is tooling that runs on a PC, never in the game.
You don't need to load any other script: the cheat revealer is built in.

## Why v8.0 is the v6.2 resolver

Every shot the resolver decided (head hit vs resolver miss), across all
uploaded logs:

| Versions | Head rate | Opponents |
|---|---|---|
| v5.2 – v6.2 | **74%** (100/135) | 10 of 10 at 57% or better |
| v6.7 – v7.9 | 49% (54/111) | 9 of 12 at 60% or worse |

The drop was in every method, not one. So v8.0 takes v6.2's decision code
as it was and carries forward only fixes that don't change a decision
(crash and NaN guards, bounded logging, callback guards, DB fixes). The
test suite proves it: on every tick of the harness match, v8.0 forces the
same side with the same value as v6.2 (`tools/check_all.sh`, step 7).

## Menu (LUA › B)

The v6.2 menu, unchanged, so your saved settings from then apply again:
Enable, the three [SAFE] detectors, the three [EXP] switches (Jitter
Prediction, Asymmetric Angles, Suppress Shots), Tight Interpolation, ESP
Indicators, Verbose Logging, the panel accent, and the DB/log buttons.

ESP flags: `VLN` (vulnerability window open), `RES` (resolved), and the
enemy's cheat (`GS`, `NL`, `NW`, `OT`, ...). The panel shows the current
threat's cheat too.

Console: `rv_stats`, `rv_db`, `rv_clear`, `rv_reset`, `rv_wipe`.

## Cheat-based resolving

1. **Detection.** Every HvH cheat leaves a fingerprint in the voice-data
   packets it sends, even when nobody talks. RIFTVEIL reads them (the
   detectors from the cheat revealer script, ported) and labels each
   enemy: gamesense, neverlose, nixware, pandora, onetap, fatality,
   plaguecheat, ev0lve, rifk7, airflow. The label is saved with the
   player's profile.
2. **Gamesense Lua presets only for gamesense users.** The AA config
   fingerprints (luasense beta/std, symmetric builders) are gamesense
   Luas; a neverlose or nixware player can't run them, so they get the
   default L/R table instead of a false fingerprint match.
3. **What works per cheat is learned.** Every head hit and resolver miss is
   filed under (enemy cheat, method) across all players on that cheat and
   saved between sessions. A method at 30% or worse against a cheat after
   8+ shots is skipped for that cheat (every 4th shot still tries it, so it
   can recover). Each save logs what was learned: `[cheat] learned nl: ...`.

With no cheat detected, or too few shots, v8.0 is exactly v6.2.

## Sending a match log

After a match, send both `riftveil_debug.txt` and `riftveil_debug_prev.txt`
from the game folder. Or read them yourself:

```
lua5.3 tools/log_report.lua riftveil_debug_prev.txt riftveil_debug.txt
```

Head rate per method, movement state (`st=`), enemy cheat (`cht=`) and
player, with 95% intervals.

## Development

Everything below needs `lua5.3` and `luajit` (the game's runtime);
`luacheck` is optional.

```
bash tools/check_all.sh          # full suite, a few minutes
QUICK=1 bash tools/check_all.sh  # 2 fuzz seeds, short soak
```

| Tool | Checks |
|---|---|
| `tools/sandbox_check.lua` | Loads the script against a mock gamesense and plays a scripted match: global leaks, undeclared reads, swallowed errors, required code paths, unit checks (cheat trust, preset gating, DB cap). `RV_FUZZ=<seed>` adds a hostile randomized phase with plist range checks and a memory soak. `RV_PLIST_OUT` and `RV_TARGET` enable differential tests. |
| `tools/plist_parity.lua` | Compares two player-list write logs by effect: same side, opposite side, magnitude difference. |
| `tools/cheat_detect_test.lua` | Feeds real FFI voice packets to the detectors: every cheat's signature is detected, ordinary voice is never labelled, short runs label nobody. |
| `tools/log_report.lua` | Real-match analysis (above). |
| `tools/aim_model.lua` | Per-weapon kill-probability model (docs/WEAPON_PLAN.md). |
