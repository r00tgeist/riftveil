# RIFTVEIL improvement plan (from v8.32)

Goal: one resolver model that works against luasense and the other 30-40
AA scripts with any settings, without per-script presets, and without
making the ragebot wait. Evidence for every claim: `docs/RESOLVER_AUDIT.md`.

Rules that stay: each change ships behind a `FEATURE` flag that the v6.2
parity run switches off, with a harness test that also runs the old path;
nothing is decided on a simulation; a change stays only if its log_report
number holds up on real matches (head rate = head / (head + resolver miss),
resolver-decided shots).

Where we are: v6.2 measured 74%. Across all logs the methods sit at
61-77%; `vuln_unk` was the drag (35% since v8.15) until the v8.29 delta
(70% in its first match).

## Step 1 -- verify (v8.32, this release)

- Audit of every resolver-path function: `docs/RESOLVER_AUDIT.md`.
- **Debug log works again** (dead since v8.1). Turn it on for the next
  matches: the steps below are judged on its lines.
- **Probe**: every `[corr]` line now carries `pz=` (the body-yaw pose read
  on that record) and `pf=` (what we forced). log_report:
  `POSE READ BACK vs WHAT WE FORCED`.
- **Max desync** (`DESYNC_FORMULA`): the correction cap is Valve's limit
  (58 standing, 29 running, never lower), not a line to 0 at 580 u/s.
- Gate to step 2: one or two matches with Debug log on.

## Step 2 -- read the enemy, not ourselves

Decided by the probe.

- If `forced: pose within 5 of it` is the large majority, the AA detector,
  side tracker, config recogniser and LBY / CTR triggers are reading our own
  output. Then:
  - classify the AA from the **eye-yaw history** the server sends (2-way /
    3-way / 5-way / skitter / hold are yaw modifiers; they show in
    `m_angEyeAngles`), the record cadence and the animation layers;
  - take the side from the pose **only on records built while nothing was
    forced** (gamesense's own answer), never from our own;
  - judge: per-method head rate at least as high as before, x-way and hold
    labels stable across forced / not forced.
- If the pose does not follow what we force, the current reading stays and
  step 2 is skipped.

## Step 3 -- one magnitude model instead of presets

- Value = side x `MaxDesync` for that frame. Almost every AA runs its body
  yaw limit at max (211 of 330 limit sliders default to 60; settings
  exports median 60; Neverlose presets 58-60), whatever the script; the
  luasense tables are yaw offsets.
- Per enemy, learn a scale from where head hits land (start at 1.0, move
  toward the forced fraction that hit, forget over a round) -- one number
  per enemy and side, so it works for any script and any settings.
- Retire `KNOWN_CFGS` / `CFG_COUNTER` / `RecognizeCfg` once it holds up.
- Judge: `BY FORCED VALUE PER METHOD`; side-based methods (hit memory +
  LBY) at or above today's 63% over 60+ decided shots, and the left side
  (stuck at 18-32 today) no worse than the right.

## Step 4 -- suppress where it pays, no waiting

- Suppress stays: 70% overall, 92% on 2-way, 83% skitter, 72% 3-way, 69%
  hold. Only 5-way is weak (56%, 16 shots): switch it off there if 5-way
  stays under 55% at 40+ shots.
- Delay: safe point at fire peaked at 15% (v8.27) when the delay was worst
  and fell to 4-7% after. Log `wait=` per shot (time the target was
  traceable before we fired) and keep "in doubt -> safe point" only while
  its head rate beats plain shots by more than the time it costs.
- Judge: `BY AIM POLICY` plus the new wait column.

## Step 5 -- vuln values in one unit

- STP / PKA / CTR / LND still force world yaws (as UNK did before v8.29).
  Move each to eye-relative values once it has 20+ decided shots in logs
  with the probe; DCK (77%, world yaw) is left alone unless its rate drops.

## Step 6 -- cut what never fires

`PredictSide` (never executed), meta-hold brute (never logged), `YawSide`
(compares the eye with itself), the dead vuln window boosts, and 6lex if
"Desync angle" never forces in the next logs. Removed only after the step-1
logs confirm they stay silent.

## What to send

Matches with **Debug log on** (now real). Each step above names the
log_report table it is decided on.
