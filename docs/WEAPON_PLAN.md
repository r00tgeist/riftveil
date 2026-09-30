# Per-weapon aim policy

Status: **v8.4 built.** It decides on traced damage, not on weapon tables.
v8.3 used nominal chest damage ("AWP: body always"). That was wrong
whenever the body shot can't kill from where you stand: a wallbang, a body
behind cover, a head-over-box peek. v8.4 traces the real damage.

## What the research says

Sources are listed at the end. None of this was invented for RIFTVEIL.

1. **Public gamesense scripts decide lethality by tracing.** "Force body
   aim on peek" and "Lethality indicator" both call
   `client.trace_bullet(local, eye → enemy hitbox)` and compare the returned
   damage with the enemy's `m_iHealth`. The peek script traces the pelvis,
   stomach, chest and legs from three points around your eye, plus a
   position 5 ticks ahead. With a charged double tap on a fast weapon, it
   counts two shots as lethal.
2. **The player-list values seen in real scripts** are
   `"Override prefer body aim"` = `"-"` / `"Force"` and
   `"Override safe point"` = `"-"` / `"On"`. No public script uses `"On"`
   or `"Off"` for body aim, so RIFTVEIL verifies every value in game (below).
3. **HvH config guides (onetap, aimware).**
   - Body aim is set to **"lethal"** (body only when it kills) for most
     weapons.
   - AWP and autos use hitbox *priority*.
   - AWP minimum damage is **101**: the AWP only fires when the shot kills,
     head or body.
   - Safe point: *force* on AWP, prefer or force on autos, optional on
     scout.
4. **"Force safe point on specific conditions"**, a public script, forces
   safe point when the enemy is **in the air**, **ducking**, or **below X
   HP**.

## The decision (per enemy, the threat every 2 ticks, others every 6)

Traced damage to the head (hitbox 0) and the body (pelvis 2, stomach 3,
chest 5, taking the highest). It's traced from your eye, and while you
move, also from 4 ticks ahead.

| Situation | Written | Why |
|---|---|---|
| A body shot kills (or two with a charged DT on auto / deagle / pistol) | prefer body **On** | a body kill doesn't depend on the desync side |
| Only the head kills (wallbang, body behind cover, scout at full HP) | prefer body **Off** | a global "prefer body" must not trade a lethal head for a non-lethal body |
| ...and our side is in doubt (2 resolver misses in a row) or they're airborne | + safe point **On** | the head kill, on points that hit whatever the side |
| Nothing kills, side in doubt | safe point **On** | |
| Nothing kills | both **"-"** | your ragebot config decides |

The head is never taken away when it's the only way to kill.

## Built-in checks

- **Value verification.** The first time each value is written, it's read
  back. If it doesn't stick, it falls back: body On → Force → "-",
  body Off → "-", safe point On → "-". The log says which values work
  (`[aim] ... supported` / `not supported, using ...`).
- **Trace calibration.** The docs don't say whether `trace_bullet`'s
  damage includes the head ×4 and armor. Every shot, the ragebot's own
  predicted damage (`aim_fire.damage`) is compared with our trace for the
  same hitgroup. Only shots predicted below the target's health count:
  if the ragebot caps a lethal prediction at health, it would read low
  (AWP head 100 / 448 = x0.22). Once 5 shots agree, the median ratio is applied
  automatically (`[aim] calibration head: ragebot damage = traced x...`).
  `tools/log_report.lua` prints the same ratio offline (TRACE CALIBRATION).
- **Cost.** At most 8 traces per enemy per update, throttled as above.
  Check it with `rv_perf` in game.

## Next

1. From the logs (`pol= tr= wpn= hp= aim= pdmg=`), measure the kill rate of
   each choice per weapon, and whether the airborne safe point pays.
2. Add a crouching / fake-duck safe point if the logs show crouch shots
   missing.
3. Replace the fixed 4-tick peek offset with your actual acceleration.

## Sources

- gamesense Lua API, `client` (trace_bullet, scale_damage, eye_position):
  https://docs.gamesense.gs/docs/api/client
- Public gamesense workshop scripts (Force body aim on peek, Actual force
  body aim on lethal, Lethality indicator, Force safe point on specific
  conditions): https://github.com/fakeangle/gamesense_workshop_dump
- HvH config guides, onetap and aimware:
  https://github.com/csgohacks/master-guide/blob/master/cheat-configuration/onetap/hvh.md
  https://github.com/csgohacks/master-guide/blob/master/cheat-configuration/aimware/hvh.md
