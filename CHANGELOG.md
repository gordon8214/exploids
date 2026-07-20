# Changelog

All notable changes to Exploids. Dates are ISO 8601 (YYYY-MM-DD).

## [0.16.11] — 2026-07-20

**For players:**
- Classic now uses an Atari-inspired white vector HUD: the unlabelled player score sits at the
  upper-left, remaining ships appear as upward-facing outlines beneath it, the high score is centered
  and the wave counter occupies the upper-right.
- Classic scores no longer show padded zeroes or modern text labels; a new game begins at `00`, as on
  the original display. Ancient and Mad retain their existing coloured text HUDs.

**Under the hood:**
- The HUD uses small path-based glyphs and the existing Exploids ship outline, so it adds no font,
  artwork or Atari coordinate-table asset. This presentation-only change leaves replay version 8 and
  all simulation state unchanged.

## [0.16.10] — 2026-07-20

**For players:**
- Classic ship, saucers and all three asteroid tiers now use Atari Rev. 4's original vector
  centerline bounds: 24×16 for the ship, 40×24 / 20×12 for the saucers and 64 / 32 / 16 for rocks.
- Classic now always plays in a fixed 1024×768 logical arena. Resizing the window or entering full
  screen scales the complete playfield uniformly with black bars where needed; it no longer reveals
  more arena, stretches objects or changes the simulation. Ancient and Mad keep their adaptive field.

**Under the hood:**
- The existing source-independent Exploids silhouettes are normalized to the arcade envelopes, so
  their visible outlines and polygon collisions agree without including Atari coordinate tables.
- Replay logic is now version 8. The schema is unchanged; v3–v7 Ancient/Mad recordings remain
  compatible, while pre-v8 Classic recordings are rejected instead of drifting.

## [0.16.9] — 2026-07-20

**For players:**
- Classic now plays Atari Asteroids' dedicated extra-ship signal whenever a new ship is awarded at
  a 10,000-point boundary. The award cadence is unchanged; the new cue is a gated 3 kHz tone rather
  than the unrelated explosion that happens to accompany most scoring hits.

**Under the hood:**
- The procedural, sample-free cue follows the Rev. 4 `$B0` timer envelope: 88 frames at the arcade's
  62.5 Hz cadence, alternating four frames of tone with four frames of silence.

## [0.16.8] — 2026-07-20

**For players:**
- Classic player and saucer shots now reproduce Atari's original range and timing envelope. Each
  shot uses the source's angle-derived fixed-point speed, inherited shooter motion, per-axis speed
  cap, muzzle offset and 69–72-frame lifetime while retaining Exploids' smooth aiming direction.
- Projectile distance scales with the arena dimensions, so default, resized and full-screen games
  preserve the same fractional screen reach. A shot's final source-authentic position remains
  visible for one arcade frame but can no longer damage anything or occupy a projectile slot.

**Under the hood:**
- Classic ballistics derive the 256-angle integer trigonometry algorithmically and run their phase
  timing from a deterministic rational 62.5 Hz clock inside the 120 Hz simulation. No Atari lookup
  table or source data is included.
- Replay logic is now version 7. The replay schema is unchanged; v3–v6 Ancient/Mad recordings
  remain compatible, while every pre-v7 Classic recording is rejected instead of drifting.

## [0.16.7] — 2026-07-20

**For players:**
- Classic saucer arrivals now follow Atari's original stateful counters instead of random,
  score-based deadlines. A new wave starts with the arcade `$7F` delay; after each saucer, the
  reload drops by `$06` from `$92` to the `$20` floor, making appearances progressively more
  frequent over a run.
- The arrival counter pauses while the ship is unavailable or a saucer is already active. Recent
  asteroid hits also apply Atari's `$50` low-rock gate and 18-tick retry, and a cleared wave waits
  for an active saucer to leave before the next set of rocks appears.

**Under the hood:**
- The 8-bit saucer counters run on the arcade routine's 15 Hz cadence and reset when a saucer is
  destroyed or exits the screen. Replay logic is now version 6; v3/v4/v5 Ancient/Mad recordings
  remain compatible, while older Classic recordings are rejected instead of drifting.

## [0.16.6] — 2026-07-19

**For players:**
- Classic large and small saucers now share the original arcade movement speed. Both use the same
  firing cadence; the large saucer fires randomly, while the small one aims with the original
  deliberately imperfect accuracy bands and becomes more accurate at 35,000 points.
- Classic saucer fire now matches the arcade ballistics more closely: at most two enemy shots can be
  active, their base speed and lifetime match the source values, and each shot inherits its saucer's
  velocity.

**Under the hood:**
- Classic saucer timing uses exact 60 Hz counter-derived intervals and the original 8-bit angular
  error masks. Replay logic is now version 5; v3/v4 Ancient/Mad recordings remain compatible, while
  older Classic recordings are rejected instead of drifting.

## [0.16.5] — 2026-07-19

**For players:**
- Classic saucers now wait 1.2 seconds before their first shot and after the player's ship
  reappears from a destroyed state or successful hyperspace. This follows the fairer original Atari
  [Rev. 2 timing](https://www.computerarcheology.com/Arcade/Asteroids/Code.html#6C34) instead of the
  [later difficulty ROM's immediate-fire behavior](https://github.com/mamedev/mame/blob/master/src/mame/atari/asteroid.cpp#L17-L24),
  while leaving the ship fully vulnerable to rocks, collisions and already-flying shots.

**Under the hood:**
- Replay logic is now version 4 because the delayed Classic shots move deterministic RNG draws.
  Version 3 Ancient/Mad recordings remain compatible; version 3 Classic recordings are rejected
  rather than replaying with simulation drift.

## [0.16.4] — 2026-07-19

**For players:**
- macOS settings now show a persistent `FULL SCREEN` option. Native full screen can be toggled with
  Control-Command-F or the green window button; successful changes are restored on the next launch,
  while new installations continue to start windowed.
- During full-screen gameplay the mouse cursor is hidden. It returns immediately in menus and
  pauses, when leaving full screen, or when Exploids loses focus.

**Under the hood:**
- Native AppKit transition callbacks are the source of truth for persistence, including failed
  transition reconciliation and shutdown handling. The iOS settings screen remains unchanged.

## [0.16.3] — 2026-07-19

**For players:**
- Ancient Asteroids and Mad Meteoroids now play the explosion sound for every asteroid hit by a
  player laser, laser beam or screen bomb. Imploding asteroids give feedback on every shot instead
  of remaining silent until their final collapse, and the procedural explosion is substantially
  louder in the gameplay mix.

**Under the hood:**
- The existing explosion cue now runs through the shared non-Classic asteroid-hit path without
  changing collision, gameplay RNG or replay behavior.

## [0.16.2] — 2026-07-19

**For players:**
- Fixed ProMotion rendering remaining at SpriteKit's default 60 FPS. The macOS and iOS apps now
  request up to 120 FPS on supported displays while retaining automatic fallback on other displays.

**Under the hood:**
- The render preference remains independent from the deterministic 120 Hz fixed-timestep
  simulation, so gameplay, RNG and replay compatibility are unchanged.

## [0.16.1] — 2026-07-19

**For players:**
- Fixed the regular theme music continuing over Classic Asteroids' procedural arcade heartbeat.
  The theme now stays paused for the full Classic session and resumes on returning to the menu,
  without changing the player's MUSIC preference.

## [0.16.0] — 2026-07-19

**For players:**
- Added **Classic Asteroids**, a third mode with arcade waves, monochrome white outline gameplay,
  four single-press shots, three ships, 10,000-point bonus ships, delayed safe respawns and
  deterministic hyperspace. It has no power-ups, special rocks, bosses, timer or auto-fire.
- Classic adds horizontal large and small saucers, rock interactions, its own procedural heartbeat,
  thrust, shot, explosion and saucer synth cues, plus a separate local high-score board. Music and
  the existing HDR/EDR glow remain available.
- iOS Classic controls add a **HYPER** tap button and rearrange the right column into HYPER, THRUST
  and FIRE without changing Ancient or Mad controls.

**Under the hood:**
- Added an isolated Classic session/simulation path while preserving Ancient/Mad raw mode values
  and replay logic version 3. Classic recordings use mode value 2, wave 1, edge-triggered fire,
  effective auto-fire off and recorded hyperspace input.
- Added board-selectable replay export (`--mode standard|classic`), dual-board high-score reset,
  procedural four-family Classic rock outlines and regression coverage for Classic rules, replay,
  persistence, rendering, audio and iOS-facing state.

## [0.15.0] — 2026-07-19

**For players:**
- Gameplay vectors now use HDR/EDR headroom on supported Mac, iPhone and iPad displays for bright
  neon output without changing their line weight. Text, stars, touch controls and raster boss art
  stay SDR.
- A new persistent `HDR GLOW` setting defaults to on. Press `G` on Mac or use the fourth settings
  button on iOS; unsupported displays report the option as unavailable and keep the legacy look.

**Under the hood:**
- SpriteKit shape shaders follow the current display headroom up to 3× SDR white, while GIF/video
  replay export is explicitly pinned to SDR and the deterministic simulation/replay format is
  unchanged.
- Added float-render regression coverage for overbright output, exact SDR fallback, translucent
  fills, vector-family opt-in and settings persistence.

## [0.14.4] — 2026-07-12

First signed & notarized release since v0.13.0 — this DMG bundles everything from v0.14.0 through
v0.14.4.

**For players:**
- Fix: watching the title-screen demo no longer leaves a movement key "stuck" when you then start a
  game (the ship could keep rotating on its own).
- Asteroid rendering is a little smoother, especially on lower-end hardware.

Everything else in this range is internal — a large refactor, a new automated test workflow (CI),
and build-portability fixes — with no effect on gameplay. Details below and in the entries for
v0.14.0–v0.14.3.

**Under the hood (v0.14.4):**
- Build/CI: fixed Swift 6 concurrency errors that only surfaced on the stable toolchain
  (Swift 6.1 on the CI runner) and were hidden by newer local toolchains (6.3+, which infer the
  isolation by default). `ReplayPlayer.advanceStep` calls the MainActor-isolated
  `GameScene.injectReplayInput`, and the entire `ExploidsMac` CLI layer (`Main`, `ReplayRenderer`)
  drives a MainActor `GameScene`/SpriteKit — all three are now explicitly `@MainActor`, which builds
  on both toolchains. Caught by the freshly added CI on its very first run.

## [0.14.3] — 2026-07-12
- Cleanup: removed the dead "Wave Cannon / charge shot" feature — the charge level was never
  raised, so the ship charge indicator, the `playChargeShot` SFX + charge-hum synthesis, and the
  unused `chargeshot_0.m4a` sample were all inert. Docs (README / AGENTS.md) corrected accordingly.
- Perf: the asteroid wireframe path is now rebuilt once per rendered frame instead of once per
  120 Hz simulation step (roughly halves the SKShapeNode path rebuilds on a 60 Hz display). Purely
  visual — the golden replay still reproduces bit-exact and GIF/video rendering is unchanged.
- Fix: a failed replay encode when saving a high score is now logged instead of silently swallowed
  (`try?` → `do/catch`); the high score is still stored, just without the replay.

## [0.14.2] — 2026-07-12
- Internal: split the 4.8k-line `GameScene.swift` into thematic `extension GameScene` files
  (HUD, attract/autopilot, glossary, Mad-Meteoroids rotation, test hooks) plus standalone
  `OptionDrone.swift` — pure code move, verified bit-exact against a golden replay.
- Internal: deduplicated the entities' `distance`/`moveToward`/`wrapAround` helpers into a shared
  `VectorMath.swift`, and gathered scattered gameplay magic numbers into a `GameplayTuning` enum.
- Tests: split the 2.3k-line single-file test suite by domain (physics, power-ups/weapons, bosses,
  modes, replay determinism, autopilot, scene state) over a shared `GameCoreTestCase` base, and
  added `AudioSmokeTests` covering the previously untested `SoundManager` / `MusicPlayer` surface
  (muted, no real audio engine). 101 tests, all green.

## [0.14.1] — 2026-07-12
- Build: the macOS app-bundle version now comes from the central `VERSION` file instead of being
  hard-coded in `build-app.sh`; the bundle build number is derived from the git commit count
  (monotonic, no more manual bumping).
- iOS: new `ios/generate.sh` syncs `MARKETING_VERSION` from `VERSION` before generating the Xcode
  project — the iOS version had silently drifted to 0.9.0 while macOS was at 0.14.0.
- CI: added a GitHub Actions workflow that runs the full test suite (`swift test`) on every push
  and pull request (tests are headless and deterministic, so no extra setup is needed).
- Internal: extracted high-score persistence (`HighScoreStore`) and the on-disk replay archive
  (`ReplayArchive`) out of `GameScene` into their own types — no behavior change, all 97 tests pass.

## [0.14.0] — 2026-07-08
- iOS: the demo / attract mode now runs on the mobile build too — after 30 s idle (or via a new
  **DEMO** button on the title screen) an autopilot plays a full game; a touch, or the on-screen
  **ESC**, hands control back. A "> DEMO — <persona>" marker shows while it plays.
- iOS: redesigned in-game HUD to free up the playfield — smaller score, high score hidden during
  play, and level / time / demo shown as one centered line just below ESC (same size, three colors).
- iOS: the on-screen touch controls are dimmer and thinner in-game (visible for orientation, but out
  of the way), and are hidden entirely during a demo — only **ESC** stays so a viewer can stop it.
- iOS: the glossary now opens already scrolled in so its content is visible immediately, and the
  settings screen no longer shows the redundant control hint.
- Fix: after watching a demo, starting a game no longer leaves an autopilot movement key "stuck"
  (the ship kept rotating on its own) — held keys are now cleared on every fresh game and demo abort.

## [0.13.0] — 2026-07-07
- Demo / attract mode on the title screen: after 30 s of no input (or on pressing **D**), an
  autopilot plays a full game on its own. When it dies it does **not** enter the high-score list,
  but the high-score screen is shown for 10 s, then the title screen for 15 s, then the next demo —
  looping. Any key hands control back to a human.
- Four autopilot personas that play with distinct styles (cautious ↔ reckless, skilled ↔ sloppy)
  and each start at a fitting level: **Ace** (L4, the expert — reaches level 10 and can survive the
  full ~10 minutes), **Cowboy** (L6, offensive but clean), **Rookie** (L5, cautious but sloppy) and
  **Kamikaze** (L7, reckless — dies youngest but spectacularly). The autopilot uses a potential-field
  navigator (threats repel, shooters/power-ups weakly attract, look-ahead dodging) that keeps the
  ship weaving through the gaps and firing along its path; it also collects shields/extra-lives.

## [0.12.1] — 2026-06-25
- Replay fix: a recording now stores the scene size it was played at. The simulation depends on the
  scene size (spawn positions, wrap bounds, enemy entry), so replaying or rendering at a different
  size made the run drift completely. The headless renderer and `--replay-verify` now use the
  recorded size by default; older recordings without the field assume the macOS window default of
  1024×768 (so existing replays render correctly without manual flags).
- The GIF renderer can now decouple simulation size from output size (`--sim-scale` for the sim,
  `--scale` for the GIF), so a faithful 1024×768 run can be rendered to a compact GIF.
- New CLI `--render-video <file> --out <mp4>`: render a whole replay to a real-time h264 video
  (via AVAssetWriter). For long runs that would be absurdly large as a GIF — scrub it to pick a
  GIF segment.

## [0.12.0] — 2026-06-25
- Fixed-timestep simulation: the game loop now advances in fixed steps (1/120 s) driven by a
  time accumulator, decoupled from the display refresh rate, instead of integrating one variable
  step per frame. On 120 Hz this is effectively one step per frame as before; on other refresh
  rates the simulation stays consistent.
- Because every step is the same length, a replay no longer needs the recorded per-frame `dt`
  sequence — it depends only on (seed + inputs). Replay format bumped to v3; older replays
  (v2, variable timestep) are rejected as incompatible.
- The headless GIF renderer drives the simulation one fixed step at a time and picks a capture
  stride automatically so the GIF plays in real time (`--stride` still overrides).
- Replays are now auto-saved to disk on every game over (not only high-score runs), under
  `~/Library/Application Support/Exploids/replays`, so a good run can be turned into a GIF even if
  it didn't make the board. New CLI `--render-last-replay --out <gif>` renders the most recent one.
- New CLI `--reset-highscores` clears the saved high-score list (when the board fills with
  unbeatable scores).
- No gameplay-balance changes intended; this is an engine/feel change to be confirmed by playtest.

## [0.11.1] — 2026-06-24
- Replay fix: the auto-fire setting is now recorded in a replay and restored on playback. Before
  this, a run played with auto-fire on would not reproduce (the replayed ship barely fired and died
  early). Replay format bumped to v2; pre-fix replays are rejected as incompatible.
- Replay GIF renderer gained `--from <frame>`, `--max-frames <n>` and `--auto-fire` options, plus a
  `--replay-verify` diagnostic.
- Note: faithful replay requires the exact binary that recorded the run — a rebuilt binary can drift
  (floating-point reproducibility is binary-specific). In-app replays and GIFs from the same
  installed build are reliable.

## [0.11.0] — 2026-06-24
- Deterministic replay system: every run is recorded (seed + inputs) and the simulation is now
  bit-exact reproducible. High-score runs can be watched again in-app — press 1–5 on the title
  screen to replay an entry; ESC exits.
- Headless GIF rendering: turn a replay into a clean, cursor-free animated GIF from the command
  line (`exploids --render-replay <file> --out <gif>`, plus `--export-replay` and `--render-demo`).
- Under the hood: seeded PRNG for all gameplay randomness and a single accumulated game-time
  clock (no more wall-clock reads in the gameplay path), which also makes the test suite
  deterministic.

## [0.6.1] — 2026-06-20
- Pixel font (Press Start 2P) for the EXPLOIDS / GAME OVER headings.
- High-score name entry fix (first responder).
- Reworked object glossary: every power-up listed individually, with a title strip.
- Fixes: extra life with gravity wells, entzerrtes start-screen layout, "#" extra-life cheat (for testing).

## [0.6.0] — 2026-06-19
- Two selectable game modes: **Ancient Asteroids** (classic) and **Mad Meteoroids** (rotating field).
- Four new power-ups: Rear, Compress, Extra Life and Laser beam.
- App icon (ship + flame) and chiptune background music with an M toggle.
- Flatter difficulty curve; asteroids now reliably fly in from the screen edge instead of spawning mid-screen.
