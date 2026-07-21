# Maelstrom Game Mode — Implementation Plan

## Context

Exploids currently ships three game modes — **Ancient Asteroids** (fixed wrapping field), **Mad Meteoroids** (rotating field), and **Classic Asteroids** (a faithful Atari-arcade recreation). The Classic mode proved a repeatable pattern for bolting a *different classic game* onto the shared GameCore engine without disturbing the others.

This plan adds a fourth mode, **Maelstrom**, that replicates the gameplay and sound effects of the classic Mac shareware game *Maelstrom* (open-source C++/SDL port at `~/Projects/Maelstrom`) — its ship/shield physics, three-size rock economy with inverted scoring, full enemy/hazard roster, prize/powerup system, wave + bonus-screen structure, and its 35 sound effects — while keeping Exploids' C64-style neon **vector** aesthetic (Maelstrom's originals are bitmap sprites; here every object is drawn as glowing vector line art).

**Outcome:** a selectable "Maelstrom" mode that *plays like* Maelstrom, sounds like Maelstrom, and looks like Exploids, added additively so the existing three modes remain byte-for-byte deterministic for replays.

### Decisions locked in (from user)

1. **Faithful recreation, not a verbatim port.** Reproduce Maelstrom's documented mechanics, values, timings, spawn formulas and *feel* inside Exploids' existing 120 Hz float engine and vector entities. Do **not** port Maelstrom's C fixed-point integer physics or its `FastRandom` PRNG bit-for-bit.
2. **Bundle the sounds now, attributed CC-BY-3.0.** Transcode and bundle the 35 SFX; document provenance and attribution in `LICENSE`/`README` (Exploids' README already treats Maelstrom's assets as CC-licensed).
3. **Fixed retro 4:3 arena.** Reuse Classic's fixed-arena plumbing at **1024×768** (a uniform ×1.6 of Maelstrom's 640×480), aspect-fit, wrapping.

---

## Architecture: mirror the Classic precedent

The entire feature follows the shape Classic already established (`Sources/GameCore/ClassicMode.swift`, 736 lines):

- **One** new `GameMode` enum case.
- **One** early-return dispatch branch in `stepSimulation`.
- A self-contained `extension GameScene` carrying a **`…Geometry` / `…Tuning` / `…Session`** trio and a single entry point `updateMaelstromMode(deltaTime:)`.
- Existing entity classes **reused** via new `applyMaelstrom…` methods; genuinely new objects get lightweight `SKShapeNode` vector entities.
- A vector HUD, a separate high-score board, a bumped replay version, and minimal parallel branches in the cold UI/CLI/iOS paths.

**Two hard project rules (`CLAUDE.md`) govern everything and are non-negotiable:**

- **Never change the global fixed timestep** (`simStepsPerSecond = 120`, `GameScene.swift:619`). Maelstrom's 30 Hz is reached by **decimation** (see below), not by retiming the loop.
- **RNG order/count is part of the replay format.** All gameplay randomness draws from `var rng: GameRandom` (`GameScene.swift:342`) via `Int.random(in:using:&rng)` / `Bool.random(using:&rng)`; all time comes from the session's own `elapsedTime`, never wall clock. The new Maelstrom branch must be **purely additive** so Ancient/Mad/Classic RNG behavior stays byte-identical. Do **not** refactor the shared `stepSimulation`/collision/spawn hot paths.

---

## File & module layout

### New files (all under `Sources/GameCore/Maelstrom/`)

Because Maelstrom is a larger feature than Classic (manual shield, prizes, multiple enemy/hazard classes, bonus screen), split it into a small directory rather than one monolith. No `Package.swift` change is needed — the `GameCore` target globs `Sources/GameCore`.

| File | Contents |
|---|---|
| `MaelstromMode.swift` | `extension GameScene`. `enum MaelstromGeometry`, `enum MaelstromTuning`, `struct MaelstromSession`; entry point `updateMaelstromMode(deltaTime:)` + the 30 Hz driver `stepMaelstromTick()`. Analogous to `ClassicMode.swift:1-219`. |
| `MaelstromShip.swift` | Ship phase machine (spawn → `INITIAL_SHIELD`/`SAFE_TIME` → `DEAD_DELAY` → respawn), thrust, brake, manual **shield-energy** drain, firing (`fireMaelstromShot`, `MAX_SHOTS` cap, `AUTOFIRE_DELAY` cadence). Peer of `ClassicMode.swift:221-363`. |
| `MaelstromWaves.swift` | Wave spawn (per-wave count formula, 1-in-10 SteelRoid, blue-moon cluster), rock split with **inverted scoring**, wave-clear (only the 3 rock classes block clear), accelerating heartbeat, and the end-of-wave **bonus screen** economy. |
| `MaelstromEnemies.swift` | Shenobi fighters, SteelRoid, homing mine, gravity vortex, Nova — spawn cadence, per-entity AI, collision resolution. |
| `MaelstromPrizes.swift` | Prize / Multiplier / Bonus-pod / Damaged-ship spawn + pickup/shoot handling + the 8 timed prize effects + Lucky. |
| `MaelstromEntities.swift` | New `SKShapeNode` vector entities (Shenobi, SteelRoid, HomingMine, Nova, MaelstromPrize) with `getWorldVertices()`, `update(deltaTime:)`, `wrapAround(screenSize:)`. Each defines a `[CGPoint]` outline → `CGMutablePath` → neon `strokeColor`, `fillColor = .clear`, `lineWidth ≈ 1.5–2` → `VectorGlowRenderer.markStroke(self)` (the exact pattern used by `Ship`/`ClassicVectorTextNode`). |
| `MaelstromHUD.swift` | `final class MaelstromHUDNode: SKNode`, mirroring `ClassicHUDNode`. **Reuses `ClassicVectorTextNode`** (assetless vector font, `ClassicHUD.swift:6-131`) for score/hi-score/wave; adds a **shield-energy bar** and an **active-prize indicator**. |
| `MaelstromSound.swift` | `extension SoundManager` mapping Maelstrom events → sample names; forces the Maelstrom sample pack while in mode. |

**Swift constraint — stored state.** Extensions can't add stored properties. Classic puts `classicSession`/`classicHUD` in the class body and keeps logic in the extension. Do the same, and to keep the `GameScene` class diff to ~2 lines, **nest all Maelstrom-only entity arrays inside `MaelstromSession`** (a struct can hold arrays of reference-typed `SKShapeNode`s). `Ship`, `activeAsteroids`, `activeLasers` reuse the existing `GameScene` arrays (`:167-173`), exactly like Classic. `MaelstromSession.reset()` = `self = MaelstromSession()` after the caller removes nodes from the scene graph.

### Existing files touched (minimal, additive)

| File | Change | Anchor |
|---|---|---|
| `GameScene.swift` | `case maelstrom = 3` on `GameMode` (frozen raw value); extend exhaustive `next`/`previous` 3-way switches to 4-way. | `:45-69` |
| `GameScene.swift` | Two class-body stored props: `var maelstromSession = MaelstromSession()`, `let maelstromHUD = MaelstromHUDNode()`; `static let maelstromLogicalArenaSize`. | `~:305`, `~:114` |
| `GameScene.swift` | Dispatch branch right after Classic's: `if gameState == .playing && gameMode == .maelstrom { updateMaelstromMode(deltaTime: deltaTime); return }`. | `:1167` |
| `GameScene.swift` | `fireLaser()` → `if gameMode == .maelstrom { fireMaelstromShot(); return }`. | `:984` |
| `GameScene.swift` | `transitionTo(.playing)` fresh-game setup: parallel branch → `initializeMaelstromSession()`, show `maelstromHUD`, hide standard labels. | `:3023-3067` |
| `GameScene.swift` | Extract `GameMode.usesFixedArena` (`.classicAsteroids || .maelstrom`) and `GameMode.usesVectorHUD`; use in `updateSceneSizing` + `activate/restore…SceneSizing` keyed off `maelstromLogicalArenaSize`. | `:3187-3222` |
| `GameScene.swift` | `activateHighScoreBoard(for:)`, `saveHighScores`, `loadHighScores`, `highScores(for:)`, `clearHighScores`: 2-way → 3-way `switch`. | `:3533-3568` |
| `GameScene.swift` | `handleKeyDown`/`handleKeyUp`: map Maelstrom-only SHIELD-hold + BRAKE-hold into `activeKeys`; clear autofire deadline on fire-release (as Classic does). | `:964-979` |
| `GameScene+HUD.swift` | `updateModeSelectionLabel()` `.maelstrom` arm + instruction string; `updateLivesLabel` + `refreshMaelstromHUD()` (RNG-/time-free). | `~:475`, `~:528` |
| `HighScoreStore.swift` | `maelstromHighScoresKey = "exploids_maelstrom_high_scores"` + `loadMaelstrom`/`saveMaelstrom`. | `:12`, `:48-60` |
| `Replay.swift` | Bump `currentLogicVersion` 9→10; add `.maelstrom` arm to `isCompatible`. | `:57`, `:152-161` |
| `Main.swift` | `--mode … maelstrom`; reject `--width/--height` and force `maelstromLogicalArenaSize` in `--replay-verify`; update `--help`. | `:405-457` |
| `ReplayRenderer.swift` | The single `.classicAsteroids` fixed-arena check → `usesFixedArena`. | (one site) |
| `ios/…/GameViewController.swift`, `TouchControlsView.swift` | Add a Maelstrom control set to `makeButtons(for:)`: THRUST, ◀, ▶, FIRE, **SHIELD (hold)**, **BRAKE (hold)**, ESC — **no HYPERSPACE**. | control builder |
| `GameScene+TestHooks.swift` | Extend `clearAllEntitiesForTesting` (drain Maelstrom arrays) + add `spawnMaelstrom*ForTesting`. | `:161-178` |
| `GameScene+Glossary.swift` | Glossary/attract entries (prizes, shield, enemies). | glossary builder |

---

## Determinism & 30 Hz decimation

### The clean 4:1 tick

`simStep = 1/120`; Maelstrom is 30 Hz; `120 / 30 = 4` exactly. Unlike Classic's non-integer 62.5 Hz rational accumulator, Maelstrom needs only a **plain integer phase counter** in the session:

```swift
mutating func advanceTick() -> Bool {   // MaelstromSession
    tickPhase += 1
    if tickPhase >= 4 { tickPhase = 0; return true }   // fire one 30 Hz tick
    return false
}
```

`updateMaelstromMode(deltaTime:)` accumulates `session.elapsedTime += deltaTime` (so pause/quit-confirm never burn deadlines — the reason Classic keeps its own clock, `ClassicMode.swift:95,167`), then calls `advanceTick()`; on `true` it runs **exactly one** `stepMaelstromTick()` with a fixed `dt = 1/30`. **All** Maelstrom simulation — ship physics, entity motion, spawn timers, collision, splits, shield drain, prize timers — happens inside that single 30 Hz path. One code path, one `dt`, no wall clock ⇒ trivially deterministic.

**Input across the 4-step gap.** Input events are recorded at 120 Hz and applied to `activeKeys` via the existing replay-driven path, so sampling `activeKeys` per tick is deterministic. To avoid dropping a fire tap that starts and ends inside a gap, use a **latch**: `handleKeyDown(fire)` sets `session.fireLatched = true`; the next tick consumes it in `fireMaelstromShot` and clears it. Held autofire pulses every `AUTOFIRE_DELAY = 6` ticks via a session deadline — the single-impulse-per-deadline design Classic already uses and tests (`ClassicMode.swift:184-194`; the "does not catch up while hidden" regression test).

### Units mapping (640×480 / 30 Hz → Exploids points)

- **Arena:** `MaelstromGeometry.logicalArenaSize = 1024×768` = uniform **×1.6** of 640×480. One scale constant `pointsPerMaelstromPixel = 1.6` maps everything, and the proven `ClassicHUDNode` layout constants reuse verbatim. Field is **toroidal** — reuse each entity's existing `wrapAround(screenSize:)`.
- **Speed:** Maelstrom `VEL_MAX = 8 px/tick` → `8 × 1.6 × 30 = 384 pts/s` cap on the ship.
- **Rotation:** store a discrete **facing index 0…47** (`SHIP_FRAMES = 48`, 7.5°/step) in the session and derive `zRotation` — bit-stable across replays (peer of Classic's discrete `angleStep`).
- **Durations = 30 Hz tick counts**, encoded verbatim in `MaelstromTuning` so a reviewer can diff them against the C headers: `INITIAL_SHIELD=90`, `SAFE_TIME=60`, `MAX_SHIELD=150`, `DEAD_DELAY=90`, `SHOT_DURATION=30`, `AUTOFIRE_DELAY=6`, `PRIZE_DURATION=300`, `MULT_DURATION=180`, `BONUS_DURATION=300`, `FREEZE_DURATION=300`, `SHAKE_DURATION=150`, `BONUS_DELAY=15`, `BOOM_MIN=10`, `NEW_LIFE=50000`, `INITIAL_BONUS=2000`, `MAX_SHOTS=18`, `PLAYER_HITS=3`, `ENEMY_HITS=3`, `HOMING_HITS=9`, `NUM_PRIZES=8`.
- **Randomness (faithful recreation):** reproduce Maelstrom's *distributions* — not its `FastRandom` PRNG — through `rng: GameRandom`: rock split `Int.random(in:1...3)`, 1-in-10 SteelRoid, 1-in-50 blue-moon cluster (4–10 copies), 1-of-8 prize, per-wave spawn count `FastRandom(max(1,wave/4)) + wave/5 + 3`, SteelRoid morph roll. Fix the RNG-draw order once and freeze it as v10.

Render-only interpolation between ticks is **out of scope for simulation** (never feeds back into state). Ship authentic 30 Hz motion first; the vector/glow look reads fine at 30 Hz.

---

## Entity strategy

Reuse `Ship`, `Asteroid`, `Laser` (all have neon vector paths, `getWorldVertices()`, and Classic-style `apply…` hooks). Everything else is a **new lightweight `SKShapeNode`** in `MaelstromEntities.swift` (Exploids' `UFO` carries Classic-specific horizontal-saucer state that's awkward to overload).

| Maelstrom object | Strategy | Vector sketch / notes |
|---|---|---|
| **Player ship** | Reuse `Ship` + `applyMaelstromProfile()` (peer of `applyClassicProfile`, `Ship.swift:187`): frictionless motion, `maxVelocity = 384`, thrust accel, discrete 48-step rotation. Shield-energy/brake live in the session. | Existing triangle outline; reuse `shieldRings` for the manual shield. |
| **Large/Medium/Small rock** | Reuse `Asteroid` + `applyMaelstromAppearance(family:)`. **Inverted scoring 50 / 100 / 300**; split into `1...3` children; child speed scales with wave. | Flat un-filled contours; sizes via `MaelstromGeometry.asteroidDiameter`. |
| **Player/enemy shots** | Reuse `Laser` (`.normal` player / non-normal enemy) + `applyMaelstromBallistics(velocity:lifetime:)`. `SHOT_DURATION=30`, `MAX_SHOTS=18`. | White vector segment. |
| **Shenobi fighter (big/little)** | New `MaelstromEnemy`, `hitPoints = 3`, aim-at-nearest + fire; little fires 2× as often. **1000 pts**. | Angular chevron/fighter with tail; little = scaled-down. |
| **SteelRoid** | New `SteelRoid`, `specialHits = 10`, **100 pts per non-lethal hit**; on depletion `rng` morph → rock / explode / homing / reset. 1-in-10 of wave spawns. | Hard hexagon/octagon, brighter stroke. |
| **Homing mine** | New `HomingMine`, `hitPoints = 9`, accelerates toward nearest player. **700 pts**. | Spiked diamond; stroke pulses as it locks. |
| **Gravity vortex** | Reuse `GravityWell` (already at `GameScene.swift:3257`); apply per-tick pull to the ship. **500 pts**. | Existing swirl vector; stored in `session.vortices`. |
| **Nova** | New `Nova` timed bomb; on detonation damages every on-screen sprite + `shakeCamera(...)` (reuse `:3264`) for `SHAKE_DURATION`. **1000 pts**. | Expanding starburst ring. |
| **The Prize** (run-over) | New `MaelstromPrize(.prize)`, 10 s life, grants 1-of-8. Shot/wasted → "idiot" sound. Blue-moon cluster 4–10. | Rotating gift/spinner glyph. |
| **Multiplier** (shoot) | `MaelstromPrize(.multiplier)`, sets end-of-wave `bonusMultiplier` 2–5. | "×N" via `ClassicVectorTextNode`. |
| **Bonus pod** (shoot) | `MaelstromPrize(.bonus)`, adds to `bonusPool`. | Rounded pod outline. |
| **Damaged ship** (fly over → +1 life) | `MaelstromPrize(.damagedShip)`. | `Ship.outlineVertices` drawn "broken". |
| **Shrapnel/debris** | Reuse the vector-debris helper pattern (`createClassicVectorDebris`, `ClassicMode.swift:705`); factor a shared `spawnVectorDebris(at:pieces:)`. Pure visual (SKActions), never tracked. | White expanding line segments. |

**Array↔scene-graph invariant** (tests + `CLAUDE.md`): add with `addChild(x); session.arr.append(x)`, remove with `x.removeFromParent(); session.arr.removeAll { $0 === x }`. Never snapshot-overwrite an array mid-iteration — always rebuild from live survivors (`ClassicMode.swift:202-212, 549-595`). Extend `clearAllEntitiesForTesting` + the invariant test to every Maelstrom array.

---

## Ship, shields & firing

Scalar state on `MaelstromSession`, mutated only in `stepMaelstromTick()`:

- `shieldEnergy: Int` (0…`MAX_SHIELD`=150, starts `INITIAL_SHIELD`=90 on spawn); `safeTicksRemaining: Int` (`SAFE_TIME`=60 auto-shield after spawn).
- Per tick: auto-shield on while `safeTicksRemaining > 0`; manual shield on while SHIELD held **and** `shieldEnergy > 0` → drain 1/tick, show `Ship.shieldRings`. Empty + pressed → `no_shield` sound; activate → `shield_on`. No invulnerability once drained (matches Classic's respawn-without-invuln model).
- **Firing:** `MAX_SHOTS=18` live cap; each shot lives `SHOT_DURATION=30` ticks (×2 with Long-range prize); held autofire every `AUTOFIRE_DELAY=6` ticks; Triple-fire reuses the existing spread geometry in `fireLaser` (`:1006`).

---

## Rocks, waves, scoring & bonus screen

- **Per-wave spawn:** `count = FastRandom(max(1,wave/4)) + wave/5 + 3`, spawned at the top edge; each has a 1-in-10 chance to be a SteelRoid instead of a LargeRock.
- **Split:** Large→1–3 Medium→1–3 Small (terminal). **Inverted scoring: 50 / 100 / 300** (small worth most). Child velocity scales with `wave`.
- **Wave clear** when `activeAsteroids.isEmpty` — only the three rock classes count; enemies/steel/mines/hazards do **not** block clear (peer of `updateClassicWave`, `:412`, minus the saucer gate).
- **Bonus-screen economy** (session scalars):
  - `waveBonus` starts `INITIAL_BONUS=2000`, decays 10 every `BONUS_DELAY=15` ticks (floored at 0) → finishing faster keeps more.
  - `bonusPool` accrues from shot Bonus pods; `bonusMultiplier` (2–5) from a shot Multiplier.
  - On clear: `awarded = (waveBonus + bonusPool) * bonusMultiplier`, tallied into `score` **500 at a time** on the bonus screen (`riff` / `pretty_good` / `no_bonus` cues), then reset to `2000 / 0 / 1`.
- **Extra life** at repeating `NEW_LIFE=50000` via a `while score >= threshold` loop (peer of `addClassicScore`, `:481`) → `new_life` sound.
- **Heartbeat:** `boom1`/`boom2` alternate on an accelerating cadence as rocks die (copy `updateClassicHeartbeat`, `:695`, with a `BOOM_MIN=10`-tick floor).

---

## Prizes & powerups

`enum MaelstromPrizeEffect: CaseIterable`, picked with `Int.random(in:0..<8,using:&rng)`:

1. **Machine guns** — continuous autofire for `PRIZE_DURATION`.
2. **Air brakes** — stronger BRAKE deceleration for the duration.
3. **Lucky-Irish** — persistent flag; on a lethal hit, `Int.random(in:0..<3)==0` shrugs it off **and** keeps the active powerup on death (`lucky` sound).
4. **Triple fire** — 3-way spread.
5. **Long range** — shot lifetime ×2.
6. **More shields** — `shieldEnergy = min(MAX_SHIELD, shieldEnergy + refill)`.
7. **Freeze** — `freezeUntilTick = tick + FREEZE_DURATION`; rocks don't integrate position while set.
8. **Nova blast** — immediate screen-clear damage (same routine as an in-world Nova detonation).

Active timed effects: `var prizeEffectDeadlines: [MaelstromPrizeEffect: Int]` (tick deadlines) — the HUD active-prize indicator reads it. `lucky` persists until consumed/death. The Prize is **collected by fly-over**; shooting or timing it out triggers the "idiot/wasted" sound.

---

## Sound pipeline

Per the user's decision, the 35 Maelstrom SFX are transcoded and bundled now, attributed CC-BY-3.0.

### Transcode (developer/asset step — not runtime code)

`SoundManager.loadBuffer` **silently skips** any file whose `processingFormat != 44100 Hz / 2-channel / Float32` (`SoundManager.swift:517, 601`). The 35 source WAVs are 8-bit unsigned PCM **mono 11025 Hz** — all would be skipped. Transcode each to **44100 Hz stereo AAC `.m4a`** and verify with `afinfo`:

```
afconvert "snd#100.wav" player_shot_0.m4a -f m4af -d aac -c 2 -r 44100
afinfo player_shot_0.m4a   # must report 44100 Hz, 2 ch
```

### Placement, loading & triggering

- Put the pack in **`Sources/GameCore/SFX/Maelstrom/`**. `Package.swift` already does `.copy("SFX")` (recursive) → **no packaging change**. Load via `Bundle.module.url(forResource:"player_shot_0", withExtension:"m4a", subdirectory:"SFX/Maelstrom")`.
- Follow the **`bosshead` "sample-only" pattern** (`SoundManager.swift:548`): a `loadMaelstromSamplesIfNeeded()` that loads the pack into `[name:[AVAudioPCMBuffer]]`, reusing the existing 8-node round-robin pool (`samplePlayers`, `:532`), plus a `playMaelstrom(_ name:)` peer of `playSampled` (`:579`). No `SoundType` enum cases, no procedural fallback. While Maelstrom is active, **force** these sample calls regardless of the user's `useSampledSFX` toggle (peer of Classic forcing its synth).
- **Name → event map** (`MaelstromSound.swift`, transcribed from `Maelstrom_Globals.h:192-227`; ergonomic `playMaelstromShot()` etc. wrappers):

  `100 player_shot · 101 multiplier_appears · 102 explosion · 103 ship_hit · 104 boom1 · 105 boom2 · 106 multiplier_gone · 107 mult_shot · 108 steel_hit · 109 bonk · 110 riff · 111 prize_appears · 112 got_prize · 113 game_over · 114 new_life · 115 bonus_appears · 116 bonus_shot · 117 no_bonus · 118 grav_appears · 119 homing_appears · 120 shield_on · 121 no_shield · 122 nova_appears · 123 nova_boom · 124 lucky · 125 damaged_appears · 126 saved_ship · 127 funk · 128 enemy_appears · 131 pretty_good · 132 thruster · 133 enemy_fire · 134 freeze · 135 idiot · 136 pause`

- **Looping thruster (132):** dedicated looping node `maelstromThrusterPlayer: AVAudioPlayerNode` (peer of `bossHeadPlayer`, `:540`); `scheduleBuffer(buf, options:.loops)` + `play()` on thrust start, `stop()` on end, driven from the ship phase (mirror `setThrustActive` discipline, `:213`).
- **Audio-thread safety (`CLAUDE.md`):** preload all buffers and do all `attach/connect` in `loadMaelstromSamplesIfNeeded()` on the main thread; the render thread only reads buffers. Never allocate/lock on the render thread.

### License / attribution (documentation task)

Maelstrom's `COPYING` releases code under **zlib** and "artwork and animations" under **CC-BY-3.0**; the sound files are attributed to Ambrosia Software and treated here as CC-BY-3.0 per the user's decision (consistent with Exploids' README, which already frames Maelstrom's assets as CC-licensed). Concretely:
- Add a new numbered item to the **`LICENSE`** "Bundled third-party assets" section (source URL `https://github.com/libsdl-org/Maelstrom`, CC-BY-3.0, attribution to Andrew Welch / Ambrosia Software, ported by Sam Lantinga).
- Add the parallel bullet to **`README.md`** and **`README.de.md`**.
- Record the pack in a provenance manifest alongside **`assets/sfx/sfx-manifest.json`** (per-effect file → source ID mapping).

---

## Replay, high scores, HUD, CLI, iOS

- **Replay (`Replay.swift`):** `maelstrom = 3` persists via existing `Codable`. Bump `currentLogicVersion` 9→10 with a doc line ("v10 adds Maelstrom; Ancient/Mad/Classic logic + RNG order unchanged, prior replays bit-identical"). In `isCompatible`, widen the legacy guard to `(3...9)`; arms: `ancient/mad → true`, `classic → (8...9).contains(version)`, **`maelstrom → false`** (only v10 exists). Because the dispatch branch is gated on `gameMode == .maelstrom` and touches no existing body/RNG, Ancient/Mad/Classic goldens must reproduce byte-for-byte — the core acceptance gate.
- **High scores:** new `exploids_maelstrom_high_scores` key + load/save peers; the 5 board selectors go 2-way → 3-way `switch`. Reuses the per-entry compact `HighScore.replayData` unchanged.
- **HUD:** `MaelstromHUDNode` reuses `ClassicVectorTextNode` at the proven 1024×768 coordinates; adds a shield-energy bar + active-prize label. Visibility follows `gameState` like Classic's HUD (including the headless render-suppression path). `refreshMaelstromHUD()` stays RNG-/time-free (replay-neutral).
- **CLI (`Main.swift`):** accept `--mode maelstrom`; treat like Classic in `--replay-verify` (reject `--width/--height`, force `maelstromLogicalArenaSize`); update `--help`.
- **iOS:** `GameViewController` already rebuilds controls per `lastKnownMode` and renders a fixed 4:3 arena via the Classic path. Add the Maelstrom button set (THRUST, ◀, ▶, FIRE, SHIELD-hold, BRAKE-hold, ESC; no hyperspace). **Proposed desktop bindings** (tunable): SHIELD = Down arrow / `S`, BRAKE = `X`. Reflect them in the mode instruction string + glossary.

---

## Phased rollout

Each phase is independently buildable, testable, and shippable.

**Phase 0 — Enum, scaffolding, determinism spine (no visible gameplay).**
`GameMode.maelstrom`, the two class-body props, `MaelstromGeometry/Tuning/Session`, all dispatch/fire/transition/scene-sizing branches, fixed-arena plumbing, empty `MaelstromHUDNode`, high-score board, `Replay` v10. `stepMaelstromTick()` advances only the tick counter + ship.
*Gates:* `swift build`; `MaelstromModeTests` for 4:1 decimation, fixed 1024×768 + aspect-fit + menu restore, 4-way mode cycling; **Ancient/Mad/Classic golden replays reproduce byte-identically** via `exploids --replay-verify` (the v10 gate); muted audio smoke test.

**Phase 1 — Core loop:** frictionless 48-step ship, thrust/fire (`MAX_SHOTS`/`SHOT_DURATION`/autofire), inverted-scoring rock splits, per-wave spawn + 1-in-10 SteelRoid stub, wave clear + heartbeat, live vector HUD.
*Gates:* split-count/scoring tests, `MAX_SHOTS` cap + autofire + no-catch-up-while-hidden, wave-count table, **golden-replay determinism** (record → replay → assert score/positions to `1e-6`), array↔scene-graph invariant.

**Phase 2 — Enemies + hazards:** Shenobi big/little, SteelRoid morphs, homing mine, gravity vortex (reused `GravityWell`), Nova + screen shake.
*Gates:* per-entity HP/scoring, **weapons×enemy regression matrix** (`CLAUDE.md`), vortex-pull determinism, invariant extended to all new arrays, golden replay with enemies.

**Phase 3 — Prizes / powerups / multiplier / bonus screen:** all 8 effects, Lucky, freeze, shield-refill, Nova-blast; Multiplier/Bonus-pod economy; blue-moon cluster; end-of-wave tally; `NEW_LIFE` extra lives; damaged-ship pickup.
*Gates:* deterministic prize selection (fixed seed → fixed sequence), freeze pauses rock integration, Lucky 1-in-3, bonus decay/multiply/tally math, extra-life loop; golden replay covering a full wave-clear + bonus screen.

**Phase 4 — Sound pack + polish + parity pass:** transcode+verify the 35 WAVs, wire `MaelstromSound` + looping thruster + heartbeat, glossary/attract entries, iOS control set + on-device audio check, tuning pass against a real Maelstrom playthrough, license/attribution sign-off.
*Gates:* muted smoke test green; macOS real-engine start; iOS Simulator + device **without LLDB** (per `CLAUDE.md` debugger-artifact warning); asset license/bundle-scan sign-off; final full-run golden replay locked as the mode's regression fixture. Bump `VERSION`.

---

## Verification (end-to-end)

- **Build/test:** `swift build`, `swift test`, `bash build-app.sh`.
- **Determinism (the load-bearing gate):** after *every* cut, run `exploids --replay-verify <golden>` on stored Ancient/Mad/Classic goldens to confirm they're byte-identical (the additive-branch guarantee). Record Maelstrom goldens per phase and re-verify them.
- **Play it:** `swift run exploids --mode maelstrom` (macOS) — confirm ship/shield/thrust feel, inverted rock scoring, wave/bonus flow, enemy/prize behavior, sounds.
- **Audio:** muted smoke test (no real engine) in `AudioSmokeTests` peer; then a real macOS start to hear the sample pack; iOS Simulator + device without debugger for the render path.
- **Entity integrity:** array↔scene-graph invariant test over all Maelstrom arrays; weapons×enemy matrix.
- **iOS input:** touch hold/release + simultaneous SHIELD+THRUST+ROTATE through the same core input path.

---

## Risks & open questions

1. **Replay churn (highest risk).** v10 is mechanical, but any incidental edit to the shared `stepSimulation`/collision/spawn order can silently break existing goldens. *Mitigation:* keep Maelstrom hot-path branches purely additive; confine shared-helper extraction (`usesFixedArena`/`usesVectorHUD`) to cold UI/CLI paths; `--replay-verify` after every cut.
2. **Scope.** Materially larger than Classic. *Mitigation:* Phases 0–1 are a shippable "core Maelstrom"; 2–4 additive.
3. **Vector-vs-sprite fidelity.** Bespoke silhouettes (Shenobi, SteelRoid, Nova, prizes) are interpretive. *Mitigation:* treat outlines as tunables; validate with centerline-bounds tests like Classic's.
4. **Float determinism.** Timing/counters are integer ticks (safe); the float-sensitive parts are position/velocity integration and aim `atan2`. *Mitigation:* single 30 Hz path, discrete rotation, `Int.random` only, `1e-6` replay assertions (the tolerances Classic already uses).
5. **Decimated input semantics.** Pin the latch-and-consume fire model with tests so a future "snappier firing" tweak can't reintroduce catch-up bursts or lost taps.

**Resolved by defaults (tunable during implementation):** arena = 1024×768 (user choice); gravity vortex = reuse `GravityWell` with a Maelstrom-tuned pull; SteelRoid morph = reproduce the documented 1-in-10 roll distribution via `rng`; SHIELD/BRAKE bindings = Down/`S` and `X`. **Mode name** proposed as "Maelstrom" (rename freely in `updateModeSelectionLabel`).

---

## Key reference files

- `Sources/GameCore/ClassicMode.swift` — the structural template (Geometry/Tuning/Session, decimation, dispatch, entity reuse, collision rebuild-from-survivors, vector debris, heartbeat).
- `Sources/GameCore/GameScene.swift` — enum `:45`, stored state `~:305`, dispatch `:1167`, `fireLaser` `:984`, `transitionTo` `:3023`, scene sizing `:3187`, high-score board `:3533`.
- `Sources/GameCore/SoundManager.swift` — sample loader `:509`, `bosshead` sample-only pattern `:548`, forced-profile pattern `:190/:198`, looping-node discipline `:540`.
- `Sources/GameCore/Replay.swift` — `currentLogicVersion` `:57`, `isCompatible` `:152`.
- `Sources/GameCore/ClassicHUD.swift` — reusable `ClassicVectorTextNode` + `ClassicHUDNode` layout to clone.
- Source of truth: `~/Projects/Maelstrom/game/Maelstrom_Globals.h:192-227` (sound IDs), `Maelstrom.h` / `object.h` / `objects.cpp` / `player.cpp` / `shenobi.h` / `game.cpp::StartNextWave` (constants & mechanics), `~/Projects/Maelstrom/Data/Sounds/*.wav` (the 35 SFX).
