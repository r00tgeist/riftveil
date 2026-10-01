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

| Row | What it does |
|---|---|
| **Resolver** | Master switch. Off releases every player back to the built-in resolver. |
| **Detection** | Vulnerability windows, Hit memory, Desync angle (6lex), Cheat profiles, Weapon aim. |
| **Tight interpolation** | Low-latency interp cvars while the resolver is on; originals restored when off. |
| **Indicators** | Info panel, ESP flags (`VLN`, `RES`, aim policy `BODY` / `HEAD` / `HEAD SP` / `SAFE PT`, enemy cheat), SHIFT marker. |
| **Debug log** | Verbose `riftveil_debug.txt` (the log is always written; this adds per-tick detail). |

The accent follows gamesense's own *Menu color*; drag the panel by its
header while the menu is open. The info panel's INFO row shows the current
threat's cheat. Suppress and asymmetric angles are fixed on and jitter
prediction off, as v6.2 ran in the logs.

Console: `rv_stats`, `rv_db` (saved profiles and learned cheat profiles),
`rv_perf`, `rv_save`, `rv_clear`, `rv_reset`, `rv_wipe` (everything saved,
cheat profiles included).

Status of every feature, what's waiting on a match log, and what comes
next: `docs/ROADMAP.md`. What 5,220 public HvH scripts say about resolving
and the anti-aim RIFTVEIL faces: `docs/REPO_SURVEY.md`. Earlier versions are kept in `versions/`.

## Weapon aim

Decided on the **real damage from where you stand**. The script traces from
your eye (and a few ticks ahead while you peek) to the enemy's head and
body, through whatever is in between.

- **A body shot kills** (or two with a charged double tap on an auto,
  deagle or pistol) → prefer body.
- **Only the head kills** (wallbang, body behind cover, scout on a full-HP
  enemy) → body preference off for that enemy, so the head is taken. On
  safe points if the resolver just missed twice or they're in the air.
- **Nothing kills** → your ragebot config as it is.

The script checks the player-list fields in game and calibrates its traces
against the ragebot's own damage prediction. How and why, with sources:
`docs/WEAPON_PLAN.md`.

## Cheat-based resolving

1. **Detection.** Every HvH cheat leaves a fingerprint in the voice-data
   packets it sends, even when nobody talks. RIFTVEIL reads them (the
   detectors from the cheat revealer script, ported) and labels each
   enemy: gamesense, neverlose, nixware, pandora, onetap, fatality,
   plaguecheat, ev0lve, rifk7, airflow, primordial (from tickcount's
   voice-listener). The label is saved with the
   player's profile.
2. **A Lua's presets only for the cheat that runs it.** The `luasense_beta`
   fingerprint is the built-in preset of the **Neverlose** luasense beta,
   all 7 states exact (`luasense_std` is the same family). A player
   detected on any other cheat can't be running it, so they get the
   default L/R table instead of a false match. `symmetric` is a desync
   shape, not a Lua, and applies to everyone. (v8.0–v8.9 had this
   backwards: only gamesense users got the luasense presets.)
3. **What works per cheat is learned.** Every head-aimed shot (head hit or
   resolver miss) is filed under (enemy cheat, method) across all players
   on that cheat and saved between sessions. A method at 30% or worse against a cheat after
   8+ shots is skipped for that cheat (every 4th shot still tries it, so it
   can recover). Each save logs what was learned: `[cheat] learned nl: ...`.

With no cheat detected, too few shots, or Detection › Cheat profiles off,
the resolver is exactly v6.2.

## Sending a match log

After a match, send both `riftveil_debug.txt` and `riftveil_debug_prev.txt`
from the game folder. Or read them yourself:

```
lua5.3 tools/log_report.lua riftveil_debug_prev.txt riftveil_debug.txt
```

Head rate per method, movement state (`st=`), enemy speed (`mv=`), weapon
(`wpn=`, and weapon by aimed hitgroup), aim policy, shot flags (`fl=`:
teleported, extrapolated, ...), enemy pitch at fire (`pit=`, defensive AA),
defensive frames in the second before the shot (`df=`), gamesense's own
resolver on/off for the target (`cor=`), seconds since our previous shot
at them and its outcome (`ls=`, `prv=`; anti-bruteforce windows),
DB-seeded vs cold start, enemy cheat (`cht=`) and player, with 95% intervals.

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
| `tools/state_test.lua` | Plays Source movement physics (peeks, counter-strafes, slow walks, scoped snipers, crouch, jumps, fake duck) at fakelag 1-14 through the real state tracker; scores it per tick against the AA builder's condition and against what fakelag leaves possible. |
| `tools/log_report.lua` | Real-match analysis (above). |
| `tools/aim_model.lua` | Per-weapon kill-probability model (docs/WEAPON_PLAN.md). |
