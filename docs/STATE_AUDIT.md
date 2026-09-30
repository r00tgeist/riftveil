# Enemy state detection audit (v7.5, debugged again in v8.5)

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

## v8.5 debugging pass

`tools/state_test.lua` plays enemy movement through the real STATE TRACKER
code and scores it tick by tick against the condition an AA builder would
be in. The movement is Source physics (accelerate 5.5, friction 5.2,
stopspeed 80, jump 302 u/s, gravity 800, duck in 13 ticks), CS:GO weapon
max speeds, and HvH slow walk at 34% of max speed. Each scenario runs at
fakelag 1, 3, 8 and 14. The **ceiling** is a tracker that knew the truth at
every record and held it until the next one: that is what fakelag leaves
possible.

| Scenario | v6.2 | v8.4 | v8.5 | ceiling |
|---|---|---|---|---|
| knife peek, run and stop | 79.7 | 94.2 | 94.2 | 94.2 |
| rifle peek, counter-strafe | 80.6 | 87.3 | 92.9 | 92.9 |
| rifle / knife slow walk | 95.1 / 93.7 | 95.1 / 93.7 | 95.1 / 93.7 | 95.1 / 93.7 |
| AWP scoped walk | 69.4 | 80.1 | 91.9 | 91.9 |
| AWP unscoped run / slow walk | 85.5 | 91.9 | 94.2 | 94.2 |
| auto scoped walk / slow walk | 78.6 | 87.9 | 91.4 | 92.8 |
| scout run / slow walk | 79.8 | 87.3 | 89.5 | 89.5 |
| crouch, crouch-walk | 90.9 | 92.0 | 92.0 | 92.0 |
| jumps (standing, running, crouched) | 84.1 | 89.0 | 89.0 | 90.4 |
| fake duck (fakelag 14) | 54.7 | 54.7 | 92.0 | 98.2 |
| velocity unreadable while running | 24.1 | 24.1 | 84.3 | 95.4 |
| ground flag unreadable | 0.0 | 0.0 | 91.1 | 95.0 |
| **all 15 scenarios** | **76.3** | **80.9** | **91.7** | **93.1** |

Bugs found and fixed:

1. **Scoped snipers read as slow walk.** A scoped AWP tops out at 100 u/s
   and accelerates at 8.6 u/s per tick, under both fixed cuts (100 u/s,
   10 u/s per tick). Thresholds now follow the enemy's weapon and scope.
   HvH slow walk holds 34% of max speed, so a run is anything above 40% of
   max (100 u/s with a knife as before, 86 with an AK, 40 with a scoped
   AWP). The acceleration cuts scale with max speed / 250.
2. **Heavy fakelag hid the start of a run.** The speed change averaged over
   a 14-tick gap includes the standing ticks before the run, so a rifle at
   92 u/s read as slow walk. The speed-based cut (1) catches it.
3. **Fake duck flickered** crouch / standing every record. It's now held as
   crouch, as the builders map it: heavy fakelag, duck amount mid-way on
   3 of the last 4 records, on the ground, slower than 40 u/s.
4. **An unreadable ground flag meant "in air"** for every player. The
   animstate's on_ground now decides.
5. **No speed change yet** (the first record after a gap) defaulted to slow
   walk; it now keeps a running or slow-walk state.
6. **Velocity that never reads:** after 2 records in a row with 0 velocity
   while the origin moves, that player's speed comes from the origin delta
   (logged once). A single zero record is a real stop and is left alone.
   The first version of this fix fired on real stops; the test caught it.

Also: the tracker keeps its own speed history. `prev_spd` still feeds only
the v6.2 stop detector. Shot lines log the speed the state was judged on
(`mv=`). The debug log gets a `[state]` line on every change of condition,
with speed, speed change, weapon max speed, record gap, duck amount and
fake duck. With `FEATURE.STATE_PHYSICS` off, the v6.2 classifier is
untouched (check_all's parity step).

Still open: fakelag itself. At 14 ticks between records, the state can only
change when a record arrives. That is the ceiling column, and nothing on
our side can beat it.
