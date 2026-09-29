# Enemy state detection audit (v7.5)

Scope: how RIFTVEIL classifies an enemy's movement state, what depends on
that state, and how it compares with the AA builders in the reference set.
Left/right body yaw only; defensive and exploit features are out of scope.

## Our wiring

`ClassifyState` → `rec.state` (7 states: standing, running, slowmotion,
crouch, crouch_moving, air, air_crouch). The state selects:

- correction magnitude everywhere (`CfgAngle`: per-state L/R tables,
  `ASYM_FALLBACK` = luasense_beta's table for unrecognized configs);
- per-state hit memory (`hit_side_by_state`), written at fire-time state;
- the decision engine's context layer (session only);
- the confidence seed for a new profile (`CFG.STATE_SEED`);
- the LBY window's magnitude.

## Builders surveyed

| Builder | Conditions | Moving threshold | Slow walk | Crouch |
|---|---|---|---|---|
| vandal | default, standing, moving, air, slow walk, crouch, crouch-move, crouch-air | 2 u/s | slow-walk **key** | FL_DUCKING flag |
| EmberLash | standing, moving, walking, crouching, sneaking, air, air-crouch | 10 u/s | slow-motion **key** | in_duck or fake duck |
| message_28 (NL) | standing, movement, slow walk, crouch, move-crouch, air, air-crouch | 3.63 u/s | key | — |
| monstry | global, stand, walk, run, air, air+c, crouch, crouch+move | — | — | m_flDuckAmount |
| tsv4 | global, standing, moving, slow motion, air | — | — | — |

Presets: monstry's built-in "*Default" decodes to all conditions disabled
and zeroed; angelwings downloads its presets at runtime (not in the file);
vandal's sliders default to 0. EmberLash is the only one shipping per-state
values (yaw offsets, not desync): right > left in 10 of 12 entries, e.g.
crouching -21/+34, moving (vs gamesense) -29/+37. Same direction as our
tables; the magnitudes are head-yaw offsets and are not transferable.

## Findings and changes

1. **Slow walk misread (fixed).** Builders select slow walk by key; we
   inferred it from a 5-100 u/s band, which also caught every acceleration
   into and braking out of a run. Source physics (sv_accelerate 5.5,
   friction 5.2): 38% of a rifle peek-and-stop and 30% of a knife one read
   as slow walk. Now: inside the band, gaining > 10 u/s per tick is a run
   (full-speed acceleration is 18-21), losing > 2 keeps the state being
   braked from; otherwise slow walk. Peeks: 18-19 misread ticks -> 1; a
   real capped slow walk still reads as slow walk on every tick.
2. **Crouch-move threshold (fixed).** 20 u/s -> 5, matching our standing
   threshold and the builders (2 / 3.63 / 10).
3. **State now logged** on every [hit]/[miss] line (`st=`), and
   `tools/log_report.lua` reports head rate per state -- the old logs
   couldn't be analysed per condition.
4. **Open: fake duck.** EmberLash maps fake duck to its crouch config; our
   duck_amount > 0.5 may flicker between crouch and standing during a fake
   duck. No data on the duck-amount pattern, so unchanged until a log shows it.

Regression check: `tools/sandbox_check.lua` runs these physics profiles
through the real `ClassifyState` on every run.
