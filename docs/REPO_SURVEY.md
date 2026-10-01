# Survey: s0daa/CSGO-HVH-LUAS (v8.11, Neverlose section v8.12)

What 5,220 files of public HvH scripts say about resolving, about the anti-aim
RIFTVEIL faces, and what is worth adding. Every number below was counted by
script over the repo (github.com/s0daa/CSGO-HVH-LUAS, Oct 2026), not read off
menus. Copies were removed by hashing each file with whitespace and comments
stripped.

## What is in the repo

| Folder | Files | Used here |
|---|---|---|
| Gamesense/lua | 2,304 | 1,371 readable unique (117 obfuscated, 9 stubs); 569 of them anti-aim scripts |
| Gamesense/resolver | 94 | 67 readable (about 45 distinct), 27 obfuscated |
| Gamesense/lua setts, cfg | 855 | 617 unique settings exports, 79 decodable |
| Gamesense/lib | 33 | the shared libraries (cheat_revealer, antiaim_funcs, trace, csgo_weapons ...) |
| Neverlose/lua | 127 | 115 anti-aim scripts |
| Primordial/lua, resolver | 1,280 | resolvers only (7) |
| CS2, Other | ~200 | not CS:GO resolving |

## 1. Resolvers: what they do, against what RIFTVEIL does

Signals used by the ~45 distinct readable gamesense resolvers:

| Technique | Resolvers | In RIFTVEIL |
|---|---|---|
| Animlayer reads (layer 6 weight / rate, cycle) | most | yes (6lex, layer 6 state) |
| Animstate (goal feet / eye yaw, duck, speed fraction) | most | yes, same struct (field-for-field match with antiaim_funcs) |
| Max desync = Valve GetMaxDesyncDelta formula (Synaple, vandal, metaset) | many | better: the live min/max yaw from the animstate (LiveCap) |
| Jitter side from the circular mean of the last two eye yaws (Synaple CDetectDesyncSide) | several | yes, identical (YawSide) |
| "Animlayer resolver" with left / centre / right playback rates (vandal, Cartel) | 3 | no, and not real: the slots are filled from its own guess, nothing is re-animated (Lua can't without hooks) |
| Freestanding from wall traces (GILVzQi, PhantomSight, kitty) | 5 | no; but GILVzQi's traces start at OUR eye, i.e. our own AA's freestanding misapplied to the enemy |
| Pitch breaker: pitch jump > 37 deg between frames -> "Force pitch" to the down value + safe point (GILVzQi) | 1 (+64 files use Force pitch) | no -- see candidates |
| "Defensive AA resolver": grounded enemy with pitch < -1 -> Force pitch 0, body yaw 0 (Miracle / Starlight) | 3 | no -- see candidates |
| Roll zeroing: m_angEyeAngles[2] = 0 every frame (GILVzQi) | 1 | no; roll isn't in what RIFTVEIL reads |
| Neural networks / "AI" (Neural_resolver, resolverx, mah0ver, chatgpt ...) | ~10 | no; none trains on anything but its own miss events, most are templates |
| Bruteforce on miss | ~15 | yes (v6.2 flip after resolver misses) |

**"Correction active" confirmed again.** Every resolver that hands a player
back sets it **true** (Bloodedge, GILVzQi, Synaple, mah0ver, hysteria,
angelwings, bounty, random_reso2: 8 distinct files). Only "skeet resolver sucks" and
metaset set it false, to switch gamesense's own resolver off while theirs
runs. That is the v8.8 fix.

**The cheat revealer in Gamesense/lib is byte-identical** to the one ported
into RIFTVEIL (same leak header, 5 differing lines: header and final
newline). No newer signatures exist in this repo.

## 2. The anti-aim RIFTVEIL faces

Mentions in 569 gamesense and 115 neverlose anti-aim scripts. A mention is
not proof of use -- most scripts reference gamesense's own controls
(Freestanding body yaw, Edge yaw, Roll, Fake lag) only to hide or override
them -- so read the gamesense column for scripted features:

| Feature | gamesense | neverlose | RIFTVEIL's answer |
|---|---|---|---|
| Conditional builder (per movement state) | 92% | -- | per-state tables, condition tracker (91.7% vs 93.1% ceiling) |
| Delayed / tick jitter | 81% | 75% | HOLD detection, torso clusters |
| Defensive AA | 75% | 73% | v8.10 skips defensive frames (backward simtime) |
| force_defensive in the command | 69% | 70% | same |
| Defensive pitch (up / zero / random) | 43% | 55% | logged (pit=); v8.8 log: no cost at fire |
| Center / offset / random jitter | 62-69% | -- | 2-way / skitter classes |
| Skitter | 42% | -- | SKITTER class |
| 3-way / 5-way (x-way) | 24% / 14% | 57% | THREE_WAY / FIVE_WAY classes |
| Body yaw jitter / opposite / static | 37% / 62% / 76% | inverter 83% | the core's side tracking |
| Anti-bruteforce | 36% | 59% | see section 3 |
| Fake flick | 21% | 22% | none specific |
| Animation / leg breakers | 71% / 76% | -- | own-model visuals, no effect on hitboxes |

## 3. Anti-bruteforce, in detail

207 gamesense AA scripts carry it (68 neverlose). How it works in the code:

- **Trigger:** our bullet. 173 use `bullet_impact`: the closest point of our
  bullet's ray to their eye within **100 units** (most common; 35-45 in
  others). 86 also use `player_hurt`. A hit that doesn't kill passes inside
  that radius too.
- **Reaction:** change the jitter (83%), change the fake limit / body yaw
  value (49%), cycle phases (39%), change the yaw offset (33%), invert the
  side (30%), randomise (30%). The Oceanrage family: toggle side if "Side"
  is ticked, random yaw offset of +-7.
- **Reset:** after a timer (61%: 1 s and 5 s most common) and at round start.

What it means for RIFTVEIL: the shot after one that passed near them, inside
the reset window, faces a changed AA. Reconstructed from the v8.8 log's
timestamps (resolver-decided shots, head / miss):

| Since our last shot at them | Head | Miss |
|---|---|---|
| first shot | 5 | 1 |
| < 5 s | 6 | 0 |
| 5 s + | 19 | 12 |

No sign anti-bruteforce cost us in that match; the misses are on fresh
re-engagements. v8.11 logs `ls=` (seconds since our last shot at them) and
`prv=` (its outcome) on every shot so log_report can keep checking.

**v8.15: where it does cost us -- 3-way / 5-way after a resolver miss.**
The pre-v8 debug logs carry the AA type on every `[corr]` line. Joining each
shot to the last one before it (resolver-decided shots, head / resolver
miss; log_report `3/5-WAY AFTER A RESOLVER MISS ON THEM`):

| Enemy AA, shot before at them | Head | Miss | Rate |
|---|---|---|---|
| 3 / 5-way, resolver miss < 10 s ago | 25 | 33 | **43%** |
| 3 / 5-way, anything else | 249 | 170 | 59% |
| other AA, resolver miss < 10 s ago | 33 | 10 | 77% |
| other AA, anything else | 194 | 79 | 71% |

Fisher p = 0.023 against the same x-way enemies at other times, 0.001
against other AA after a miss; 9 of the 12 logs with such shots sit at or
under 50%. Ten seconds or more after the miss, x-way is back at 75% (18 / 24).
Within the window neither side choice works: we kept the missed side 7 of
22 (32%), flipped 13 of 27 (48%), and hit memory reusing its side went 3 of
16. x-way is in 57% of neverlose AA scripts and anti-bruteforce in 59%; they
are the same scripts' menus, and a phase switch on top of a 3- or 5-way
cycle leaves no side to bet on.

The reset timers, by family rather than by copy: 600 ticks (9.4 s) in one
gamesense family copied 10 times (Interitus / Dash / Winterwells / alive /
aai: 70-unit radius, 3-tick debounce), 5 s (Fumosight, outlaw aimtools on
neverlose), 3 s (acidtech, idealyaw), 2 s, 1 s, 0.5-1.1 s (semirage). The
10 s window covers the longest of them.

RIFTVEIL's answer (FEATURE.XWAY_UNSURE) is in the aim policy, not the side:
such an enemy counts as "side in doubt", so the head is taken on safe points
(and safe point is on when nothing kills). The forced body yaw is unchanged.

## 4. Presets and settings exports

- **Neverlose luasense beta** ships 5 built-in presets; its first is
  RIFTVEIL's luasense_beta table on all 7 states (v8.10).
- **No gamesense AA script in the repo ships an embedded preset** with per-
  state left/right yaw (0 of 569); their values come from each player's
  imported settings. So there is no new fingerprint to add from gamesense,
  and the live recogniser (pose spread per player) stays the right tool.
- **Settings exports:** 79 of 617 decode (the rest use per-script ciphers),
  giving 906 left/right yaw pairs. Medians by state, |left| / |right|:
  standing 22 / 10, running 34 / 30, slowmotion 25 / 23, crouch 31 / 32,
  crouch-moving 24 / 15, air 10 / 10, air-crouch 32 / 19 -- with
  interquartile ranges ~20 degrees wide. No single setup is the meta.
  These are yaw-add offsets, not the correction angle RIFTVEIL writes, so the
  default table is not retuned from them (v6.2 measured 74% with it).

## 5. Neverlose in depth (v8.12)

Half the opponents in the v8.8 log ran Neverlose. 117 unique Neverlose
scripts, 108 of them anti-aim; 215 unique settings / cfg files.

**Built-in presets.** 18 scripts ship presets (JSON or base64). Per state,
the body yaw LIMITS (the desync itself) and the yaw offsets:

| Preset | Limits (L/R) | Yaw offsets, avg L / R | In an existing fingerprint band |
|---|---|---|---|
| luasense beta #0 | 60 / 60 every state | 24.6 / 42.0 | luasense_beta (exact, all 7 states) |
| luasense beta #2-#4 | 56-60 | 26.6-29.3 / 38.1-42.0 | luasense_beta / luasense_std |
| Cb4N6YD | 59-60 | 26.1 / 35.9 | luasense_beta / std |
| exscord #1, idealyaw #1 | 60 (29 air) | 23.6-27.4 / 33.2-33.4 | luasense_std (loosely) |
| chimera, idealyaw #0 | 30 stand / 36 run / 45 slow / 58-60 | 9.4-9.8 / 19.8-20.2 | none |
| exscord #0, luasense beta #1 | 60 | 9.8-12.2 / 16.8-23.8 | none |
| aesthetic, jago, ye4, huyanza | 58-60 | 0 / 0 (jitter-only) | none |

- **The desync limit is at maximum almost everywhere** (58-60 in every
  state of 15 of 18 presets). Real players agree: in the decodable
  settings exports the median limit is 60 in every state, with 58-90% of
  them at 55+ on both sides.
- **Yaw offsets are asymmetric, right larger than left**, in presets and in
  players' settings alike (running 25/40, slow walk 31/47, air-crouch
  28/48 medians) -- the shape the asymmetric L/R table already assumes.
- **No new fingerprint added.** The presets either fall inside the
  luasense bands (and since v8.10 those apply to neverlose and undetected
  players, which is right for them) or form a low-offset family (~10/20)
  that would force small correction values. Across every log, forced values
  under 20 are the weakest band: 51% (33/65), against 77% for 40-50 and 63%
  for 50-60. That isn't monotonic (30-40: 49%), so the magnitude question
  stays open rather than being "go to 60".

**Settings exports.** 152 of 215 decode. 45 are angelwings-style
(`name_` + base64 of MessagePack: angelwings 31, testarossa 6, xoyaw 2 ...);
their bytes are mangled partway in most files, so only fragments survive
(limits seen 47-60, delays 1-5, defensive on in some states with a static
pitch and spin yaw).

**How Neverlose AA is built** (108 scripts):

- Defensive = Neverlose's hidden angles: `rage.antiaim:override_hidden_
  yaw_offset` (309 calls) and `override_hidden_pitch` (287). They show only
  on defensive ticks, i.e. the backward-simtime frames v8.10 skips. Hidden
  yaw options: random, spin, sideways, 3/5-way, opposite. Hidden pitch:
  down, custom, random, up, zero, fake up / down, progressive.
- Side flips are scripted through `rage.antiaim:inverter` (272 calls);
  yaw modifiers offset / center / random / spin / 3-way / 5-way; way-count
  sliders 1-5.
- Delay sliders mostly max at 5-20 ticks; defaults 0-2.
- `rage.exploit:force_teleport` in 75 calls -- the teleported shots that
  aim_fire flags (fl=t), kept out of learning since v8.6.
- Anti-bruteforce (28 scripts with a handler that drives it): bullet
  impacts 25, player_hurt 12; radius 50-70 units (gamesense: 100).
- **No neverlose script switches AA by the enemy's cheat.** Arc uses the
  voice listener for scoreboard icons; luasense loads it and discards it.

## 6. Deeper pass: obfuscated, Primordial, configs, defences, defaults

**Obfuscated resolvers (27).** Most use VM obfuscators (Luraph, MoonSec,
IronBrew; e.g. TECNO V1, demon, sauron, the three byte-identical 157 KB
"resolver15eur / sanchez95 / resolver_upd") and can't be read without
devirtualising them. Only Hyper ReSolver (Hercules-obfuscated) is legible:
side from the pose sign, flip on miss, desync = max x a per-mode factor
(0.8-0.95) -- generic. Its "Respect Gamesense Resolver" option skips any
player whose "Correction active" is on: one more source that reads that
field as gamesense's own resolver.

**Primordial resolvers (7).** soulresolve (2,984 lines) adds random numbers
to angles and writes a random goal-feet yaw; the rest are 2-90-line stubs
or animlayer readers. The only usable fact: animstate at player + 0x9960,
the offset RIFTVEIL uses (third source after antiaim_funcs and the logs).

**Native gamesense configs (379).** Binary: header 60 0D C0 DE, then
entries keyed by 4-byte hashes of the setting names. Not decoded --
reading them means reversing gamesense's name hashing, not guessed here.

**Defences against RIFTVEIL's vulnerability windows** (596 gamesense / 108
neverlose AA scripts):

| Window | Scripts that address it | RIFTVEIL's data |
|---|---|---|
| Duck transition (vuln_dck) | 3% / 1% | 71% head (v5.2 era), 5/5 (v8.8) -- strongest |
| LBY update (vuln_lby) | 26% / 23% | 70% (v5.2 era) |
| Landing (vuln_lnd) | 46% / 56% mention landing anims | 83% (v5.2 era, n=6) |
| Lean / leg breakers | 56% / 83%, 45% / 71% | own-model visuals in most scripts |

The duck-transition window is almost undefended, which fits it being the
best method in the data.

**Defaults are the preset for untuned players.** gamesense AA scripts ship
no presets, so their slider defaults are what a player who never tunes
runs: fake limit 60 (most common), yaw left / right 0 (279 / 308 and
273 / 303), delay 0, 5 or 1. Untuned means full desync, no yaw offset.

**Not pursued on purpose: simulating each AA mode against RIFTVEIL.** The
result would measure RIFTVEIL against a model of the enemy's animation,
not against the game -- the route that led v7.x from 74% to 49%.
Decisions stay on match logs.

## 6b. Inventory: player-list fields and enemy props (v8.14)

Every `plist.set/get` field name across 1,371 gamesense scripts and the
resolvers (uses / files): Force body yaw 690/181, Force body yaw value
466/179, Override prefer body aim 238/52, Correction active 168/107,
Override safe point 148/73, Force pitch 144/32, High priority 62/27,
Force pitch value 51/31, Add to whitelist 37/21, Allow shared ESP updates
and Disable visuals 6/2. Some scripts spell them in other capitalisation
("Correction Active", "force pitch"). "Override simulation time" /
"Simulation time override" / "Override hitbox" appear only in Insanity.lua,
which looks machine-written; nothing confirms they exist -- not used.

Enemy props read most: velocity 873, origin 736, eye angles 581, flags
470, pose parameters 368, simulation time 294, health 198, **LBY target
191** (not read by RIFTVEIL), view offset 184, duck amount 141. The LBY
target is used 262 times as `sign(eye yaw - LBY)` = desync side. That
reading is debatable after the 2018 desync update (an LBY update sets the
target to the eye yaw), so v8.14 logs it per shot (`lbyd=`) and
log_report compares head rate when its sign agrees / disagrees with our
forced side, instead of adopting it.

On-shot records: 32 scripts read the enemy weapon's m_fLastShotTime;
gamesense marks on-shot backtrack itself (aim_fire.high_priority, fl=p).
In all 149 v8.x shots logged so far: 0 on-shot, 0 teleported, 0
extrapolated; 147 used accuracy boost.

## 7. Candidates, ranked, and what decides each

1. **Force pitch on a pitch breaker** (GILVzQi: pitch jump > 37 deg -> force
   the down value for that tick + safe point). Defensive pitch is in 43-55% of
   AA scripts. The v8.8 log saw off-down pitch at fire on 7 resolver-decided
   shots: 6 head, 1 miss -- no cost yet. Decided by `BY ENEMY PITCH AT FIRE`.
2. **Hit memory and anti-bruteforce.** A non-lethal hit triggers the
   enemy's switch. If `BY PREVIOUS SHOT AT THEM` shows "after a head hit"
   falling well below the rest, hit memory should not reuse a side within the
   reset window. v8.8: 64% after a head hit vs 73% after a body hit -- no
   gap yet. After a resolver miss on a 3/5-way enemy it is a gap (section 3:
   43%, hit memory 3 of 16); v8.15 answers that with safe point, and leaves
   the side alone because neither keeping nor flipping it worked there.
3. **Freestand side** (trace from either side of the enemy's head to our eye;
   freestanding body yaw hides the real side from the threat). Needs a log
   field first, and in 2v2 the enemy's threat may be our teammate.
4. **Roll.** RIFTVEIL doesn't read the roll angle. GILVzQi zeroes it
   client-side; whether roll AA works on unmatched.gg and moves the server
   hitboxes isn't established here. No action without a log showing it.
5. Not worth porting: neural / "AI" resolvers, the fake animlayer resolver,
   our-eye freestanding, hook-based animation rebuilds (metaset; unsafe).

Sources: the repo above; earlier passes in this repo cover tickcount's
lagrecord (defensive frames) and voice-listener (primordial).
