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
| **Indicators** | Info panel, ESP flags (`VLN`, `RES`, aim policy `BODY` / `HEAD` / `HEAD SP` / `SAFE PT`, enemy cheat), SHIFT marker, Shot log (below), Local lagcomp (below). |
| **Debug log** | Verbose `riftveil_debug.txt` (the log is always written; this adds every resolver decision: `[corr]` with the pose read back and what was forced, `[vuln]`, `[cfg]`, `[dcap]`). Turn it on for matches you send in. |

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

## Shot log

One line per ragebot shot, in the format of the public `[MISC] aimbot log`
script, plus what the resolver did. It's printed the way that script prints
it, so gamesense shows it in the console and in the top-left corner like its
own logs:

```text
[217] [244/251] Missed moral's head(98)(76%) due to resolver:0.03° · RIFTVEIL vuln_lby -24° [aa=5way | cf=62% | cht=nl | streak=1 | lc=0 | tc=1]
[218] [260/266] Hit moral's head for 98(98) (0 remaining) aimed=head(81%) · RIFTVEIL hit_mem +31° [aa=hold | cf=70% | pol=head | lc=1 | tc=2]
[219] [301/307] Missed moral's chest(34)(70%) due to spread:1.84° · GAMESENSE resolver [aa=2way | cf=40% | fl=I | lc=0 | tc=0]
Naded moral for 34 damage (66 remaining)
```

| Part | Meaning |
|---|---|
| `[217]` | the ragebot's shot id |
| `[244/251]` | tick of the record it fired at / tick the result came back (mod 1000; the gap is backtrack + ping) |
| `head(98)(76%)` | aimed hitgroup, predicted damage, hit chance |
| `:0.03°` | angle between where it aimed and where the bullet went: near 0 on a resolver miss, wide on spread |
| `RIFTVEIL vuln_lby -24°` | who resolved that player for that shot, read from the player list as the shot left: RIFTVEIL with its method and forced body yaw, or `GAMESENSE resolver` (released to the built-in); on a `due to resolver` miss, that's the resolver that missed |
| `aa= cf= cht=` | AA type, confidence, enemy cheat |
| `pol= sp=` | aim policy, safe point (`on` / `off` from the player list, `key` = Force safe point held) |
| `fl=` | T teleported, I interpolated, E extrapolated, B accuracy boost, H high priority, D defensive |
| `streak=` | resolver misses in a row on them |
| `lc= tc=` | our / their choked commands |

Each shot takes its own bullet impacts for the angle, so a double tap's two
bullets don't mix. A result that comes back after 0.5 s says `(late, not
counted)`; a miss the server's hit counter disproves says `Hit x on the
server`. The debug file keeps its own lines for `tools/log_report.lua`.
Turn off other aimbot-log scripts to avoid duplicate lines.

## Local lagcomp box

Only for the double-tap exploit itself: **you shoot with double tap on,
and within 0.25 s your tickbase teleports** (shifts more than 2 ticks).
Then a red box flashes for half a second **ahead of you**, where the
teleport takes you, following as you move, labelled `LC` with the shifted
ticks (as `lagcomp-box-gs` boxes an enemy). Third person. Your speed
doesn't matter. Toggling double tap, defensive and fakelag draw nothing.
The enemy SHIFT box is red too.

## Weapon aim

Decided on the **real damage from where you stand**. The script traces from
your eye (and a few ticks ahead while you peek) to the enemy's head and
body, through whatever is in between.

- **A body shot kills** (or two with a charged double tap on an auto,
  deagle or pistol) → prefer body.
- **Only the head kills** (wallbang, body behind cover, scout on a full-HP
  enemy) → body preference off for that enemy, so the head is taken.
  Safe point is never forced (since v8.34): in the logs it landed 47-50%
  against 57% for plain shots, and it is what made the ragebot wait.
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
2. **No per-Lua presets (v8.35).** The forced value is the side times
   the engine's desync limit for that frame (58 standing, down to 29 at a
   full run). AA scripts differ in yaw offsets and side patterns, but
   their body-yaw limit sits at 60 almost everywhere, so one model covers
   luasense and every other script and setting. The old luasense tables
   (yaw offsets) are only used with `FEATURE.FULL_DESYNC` off.
3. **Gamesense first (v8.36).** Force body yaw is the only lever into
   gamesense's resolver, so RIFTVEIL pulls it only where it does better:
   each method forces while its learned head rate keeps within 5 points of
   gamesense's own (per enemy cheat, else across every enemy), and hands
   the enemy back otherwise -- every 4th shot still tries it.
4. **What works per cheat is learned.** Every head-aimed shot (head hit or
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
at them and its outcome (`ls=`, `prv=`; anti-bruteforce windows), eye yaw
minus the networked LBY target (`lbyd=`), the enemy's AA type (`aa=`,
or the debug log's `[corr]` lines in older logs) and 3/5-way after a
resolver miss, DB-seeded vs cold start, enemy cheat (`cht=`) and player, with 95% intervals.

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
