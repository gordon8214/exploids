# Changelog

All notable changes to Exploids. Dates are ISO 8601 (YYYY-MM-DD).

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
