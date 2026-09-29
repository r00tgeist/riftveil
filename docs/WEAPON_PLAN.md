# Per-weapon aim policy — implementation plan

Status: **plan, not implemented.** v7.7 only adds the logging this plan
needs (`wpn=`, `hp=`, `ar=` on every shot line). It needs one match log
with that data, plus one in-game check, before any code goes in.

## The idea

Choosing hitboxes is the ragebot's job, and gamesense already has
per-weapon configs (RAGE › Weapon type): hitboxes, body-aim preference,
minimum damage per AWP / scout / auto / R8 / deagle / pistols. RIFTVEIL
must not duplicate that.

What the ragebot does **not** know is how sure the *resolver* is about a
given enemy's head right now. RIFTVEIL does: the decision engine keeps a
posterior head chance `p` for the correction it applies to each enemy.
So the per-weapon policy is a per-enemy **risk gate**:

> Take the head shot only when this weapon needs it *and* the resolver is
> sure enough; otherwise push the ragebot to the body or to safe points —
> through the player-list overrides, per enemy, per tick.

## Inputs, per enemy, per tick

| Input | Source |
|---|---|
| Weapon class | local weapon's `m_iItemDefinitionIndex` (already logged) |
| Resolver certainty `p` | `ENG.Post(rec.E, rec.eng_arm, rec.state)`; `rec.conf` when the engine is off; 1.0 inside a vulnerability window with a trusted type |
| Enemy health / armor | `m_iHealth`, `m_ArmorValue` (already logged) |
| Body lethal? | enemy health ≤ weapon body damage after armor (table below) |

## Weapon table (CS:GO weapon data; verify from logs)

Body damage = base × armor penetration when armored. Head ×4, stomach
×1.25, legs ×0.75. Range falloff ignored (HvH distances).

| Class | Base | Armor pen. | Chest vs armor | Head vs armor |
|---|---|---|---|---|
| AWP | 115 | 97.5% | ~112 → **lethal** | lethal |
| Scout | 88 | 85% | ~75 | lethal |
| Auto (G3/SCAR) | 80 | 82.5% | ~66 | lethal |
| R8 | 86 | 93.2% | ~80 | lethal |
| Deagle | 63 | 93.2% | ~59 | lethal |
| Pistols | 30–40 | 47–93% | 15–35 | often not lethal |

These numbers are from memory of the game's weapon data. The shot logs
will confirm or correct them: every hit logs `dmg=`, `group=`, `wpn=`, `ar=`.

## Policy (starting point, tuned from logs)

| Class | Head when | Otherwise |
|---|---|---|
| AWP | never needed: body is lethal | force body |
| Scout | `p ≥ 0.80` | body if lethal, else safe point |
| Auto | `p ≥ 0.85` (fires fast; a body shot costs little) | prefer body + limbs |
| R8 | `p ≥ 0.80` | body if lethal (≤ ~80 hp), else safe point |
| Deagle | `p ≥ 0.75` | body if lethal (≤ ~59 hp), else safe point |
| Pistols | `p ≥ 0.70` (body rarely kills) | safe point head |

"Sure without delay": the gate reads `p` fresh every tick, so the
ragebot fires the moment the condition holds — no timers.

## Implementation steps

1. **Verify the plist fields in game (blocker).** On load, try
   `plist.get(ent, "Override prefer body aim")` and `"Override safe point"`
   inside `pcall` and log the result and the value type. The only source
   for these names so far is an obfuscated script — not good enough to
   build on.
2. **Collect one match with v7.7.** `tools/log_report.lua` now reports
   head rate per weapon; add body-damage-per-weapon and lethal-body
   checks to confirm the table above.
3. **Implement `AimGate(rec, weapon)`** in the ApplyDecision stage: pure
   function → {body = "-"/"on"/"force", safepoint = "-"/"on"}, written
   through `PSet` (cached, so no extra plist writes when nothing changes).
4. **Menu:** one new Detection item, "Weapon aim gate", off by default
   until step 5.
5. **Measure:** log the gate's decision per shot (`gate=body|head|sp`),
   compare head/body kill rates per weapon with the gate on vs off.
6. **Tests:** unit test the policy table, fuzz the new plist writes
   (values must be one of the allowed strings), differential test that
   with the gate off plist writes are unchanged.

## Risks

- The field names or values may differ → step 1 exists for that.
- Forcing body against an enemy whose body is hard to hit (behind cover)
  can cost shots the ragebot would have taken at the head: the gate only
  applies while that enemy's head is *not* sure, and safe point (not
  force body) is the default fallback for non-lethal weapons.
