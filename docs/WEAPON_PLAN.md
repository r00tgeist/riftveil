# Per-weapon aim policy — implementation plan (v2)

Status: **plan, not implemented.** v7.8 logs every input the policy needs
(`wpn=`, `hp=`, `ar=`, `aim=`, `pdmg=` on every shot line). One match of
that data plus an in-game check of the player-list fields come first.

## Principle

The head is always an option. Nothing in this design forbids it; the
policy only *leans* the ragebot per enemy, per tick, through soft
player-list overrides (prefer body, prefer safe point), never "force
body". gamesense's own per-weapon configs (RAGE › Weapon type) stay the
baseline; RIFTVEIL adds the one input the ragebot lacks: how sure the
resolver is about this enemy's head right now.

## The decision, derived — not hand-picked

`tools/aim_model.lua` computes, per weapon, enemy HP, body exposure and
resolver certainty `p`, which option maximizes the probability of killing
within one peek (~0.6 s), with each later kill discounted when the enemy
shoots back:

| Option | Hit chance per shot | When it wins |
|---|---|---|
| **head** | `geo_head × p` | resolver sure enough |
| **head, safe point** | `geo_sp` (side-proof, smaller area) | head needed but resolver unsure |
| **prefer body** | `geo_body(exposure) × 0.95` | body lethal within the peek *and* exposed |

What comes out (armor + helmet; full table: run the model):

1. **Head vs head-on-safe-points is one ratio.** Head beats safe points
   exactly when `p > geo_sp / geo_head`. With the placeholder values
   (0.60 / 0.85) that is p > 0.71 for *every* weapon — so the most
   important number in the whole policy is how much hit chance safe
   points cost versus a normal head shot. It must be measured, not
   assumed (step 2).
2. **Body only when it is lethal within the peek and visible.**
   - AWP, body fully open: body (112 dmg kills). Partial or head-only
     exposure: head, on safe points when unsure.
   - Scout: body only at ≤ ~74 HP; above that, head / head-sp.
   - R8: body at ≤ ~80 HP.
   - Auto, deagle at full HP: body wins only with no time pressure (2-3
     hits). When the enemy shoots back, one head hit now beats two body
     hits 0.25 s later → head / head-sp.
   - Pistols: head / head-sp almost always.
3. **Exposure decides as much as the weapon.** "Full open" is what makes
   body viable; a head-first peek over cover makes body worthless no
   matter the weapon.

## Inputs, per enemy, per tick (threat only, to stay cheap)

| Input | Source | Cost |
|---|---|---|
| weapon class | local weapon item index | 2 API calls |
| resolver certainty `p` | engine posterior of the applied arm; 1.0 in a trusted vuln window | none |
| HP, armor, helmet | `m_iHealth`, `m_ArmorValue`, `m_bHasHelmet` | 3 props |
| exposure | `client.trace_bullet` from our eye to head and chest: estimated damage vs open-air damage | 2 traces, threat only |
| time pressure | enemy weapon class and whether we're in their view | cheap props |

## Measured constants (from logs, not guessed)

| Constant | How |
|---|---|
| `geo_head`, `geo_body` | hit rate by `wpn` × `aim=` hitgroup on shots with a right side (head hits confirm side) |
| `geo_sp` | same, on shots taken with the safe-point override on (step 4 logs it) |
| weapon damage table | `dmg=` by `group=`, `wpn=`, `ar=` |
| peek length | time between first aim_fire and loss of the target |

## Steps

1. **Verify the player-list fields in game.** `pcall(plist.get, ent,
   "Override prefer body aim")` / `"Override safe point"`: log existence
   and accepted values. The only source for the names so far is an
   obfuscated script — not enough to build on.
2. **Collect a v7.8 match; fit the constants** above with an extension of
   `tools/log_report.lua`; rerun `aim_model.lua` with the fitted values.
3. **Implement `AimPolicy(rec, weapon, exposure)`** in the ApplyDecision
   stage, a pure function returning one of `head`, `head_sp`, `body`,
   mapped to soft overrides through `PSet` (cached writes). Head is never
   blocked.
4. **Log the decision** per shot (`pol=head|sp|body`) so the kill rate of
   each choice can be compared per weapon.
5. **Menu:** Detection › "Weapon aim policy", off by default until the
   first measured match.
6. **Tests:** unit-test the policy against `aim_model.lua`'s table;
   fuzz the new plist writes (allowed values only); differential test
   that with the policy off nothing changes.

## Risks

- Field names or values differ → step 1.
- The placeholder `geo_sp / geo_head` ratio decides the head/safe-point
  split everywhere → nothing ships before step 2 measures it.
- Exposure traces cost time → threat only, once per tick, and skipped
  when no shot is possible.
