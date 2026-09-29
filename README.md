# RIFTVEIL

A resolver for CS:GO on gamesense.pub, built for 2v2 HvH (unmatched.gg).
One file: `riftveil.lua`. Load it in gamesense under **LUA**; everything
else in this repository is tooling that runs on a PC, never in the game.

## Menu (LUA › B)

| Row | What it does |
|---|---|
| **Resolver** | Master switch. Off releases every player back to the built-in resolver. |
| **Detection** | Vulnerability windows, Hit memory, Desync angle (6lex), Adaptive engine. |
| **Tight interpolation** | Low-latency interp cvars while the resolver is on; originals restored when off. |
| **Indicators** | Info panel, ESP flags (`VLN`, `RES`), SHIFT marker for broken backtrack records. |
| **Debug log** | Verbose `riftveil_debug.txt` (the log is always written; this adds per-tick detail). |

The accent colour follows gamesense's own *Menu color*. Drag the panel by
its header while the menu is open.

Console: `rv_stats` (per-player state), `rv_engine` (engine audit and
per-player arm beliefs),
`rv_db`, `rv_save`, `rv_reset`, `rv_wipe`, `rv_clear`.

## How it decides

1. **Detectors** read each enemy every net update: animation-layer desync
   (6lex), vulnerability windows (LBY snaps, unchokes, stops, peeks, duck
   transitions), confirmed hit sides per movement state, the pose-tracked
   side, config fingerprints and backtrack/defensive signals.
2. **The chain** ranks their corrections by fixed priority
   (vulnerability > 6lex > hit memory > suppress > meta hold > built-in).
3. **The decision engine** puts every candidate next to the chain's pick
   and overrides it only when shot evidence says another candidate is
   better with > 85% probability. Evidence is shared: one head hit grades
   every detector that was present when the shot was fired. What it learns
   carries across players and sessions. A Brier-score self-audit puts it
   in safe mode (chain only) whenever its predictions fall behind a
   base-rate model. While it decides, the chain's own adaptive habits
   (flipping the tracked side after misses, wiping hit memory on a soft
   reset) stand down -- measured to fight the engine.
4. **Enemy cheat.** If the cheat revealer script is loaded next to
   RIFTVEIL, each enemy's detected cheat (gs, nl, nw, ot, ...) keys an
   extra engine level: evidence pooled over every player met on that
   cheat, saved across sessions. A new enemy then starts from what worked
   against that cheat, not from the lobby average. Without the revealer
   nothing changes. Shot lines log `cht=`; `rv_engine` lists the layer.

Full reasoning, including what was tried and cut, is in the comment blocks
of `riftveil.lua` (search for `DECISION ENGINE`). History: `CHANGELOG.md`.

## Sending a match log

After a match, send both `riftveil_debug.txt` and `riftveil_debug_prev.txt`
from the game folder. Or read them yourself:

```
lua5.3 tools/log_report.lua riftveil_debug_prev.txt riftveil_debug.txt
```

It prints head rate per method and per engine arm with 95% intervals, the
engine's override record against the chain, its calibration, and flags any
applied correction outside ±60°.

## Development

Everything below needs `lua5.3` and `luajit` (the game's runtime);
`luacheck` is optional.

```
bash tools/check_all.sh          # full suite, ~3 minutes
QUICK=1 bash tools/check_all.sh  # 2 fuzz seeds, short soak
```

| Tool | Checks |
|---|---|
| `tools/sandbox_check.lua` | Loads the script against a mock gamesense and plays a scripted match: global leaks, undeclared reads, swallowed errors, required code paths, unit checks. `RV_FUZZ=<seed>` adds a hostile randomized phase (NaN/inf inputs, churn, out-of-order events) with plist range checks and a memory soak. `RV_PLIST_OUT`, `RV_NO_ENGINE`, `RV_TARGET` enable differential tests. |
| `tools/cheat_sim.lua` | Careers of 12 matches against new opponents: measures the cheat layer against the global layer alone, in worlds where the cheat decides the AA fully, partly, or not at all. |
| `tools/engine_sim.lua` | Runs the real engine code against 10 modeled opponents vs the chain alone; checks the no-evidence guarantee. `RV_ENG="KEY=value,..."` overrides constants for ablations. |
| `tools/log_report.lua` | Real-match analysis (above). |
| `tools/preview/` | Renders the info panel from its own drawing code (needs Pillow). |
