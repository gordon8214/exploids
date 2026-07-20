# Exploids

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center"><img src="Icon/icon_1024.png" width="180" alt="Exploids app icon"></p>

A native macOS Asteroids-style arcade shooter (Swift 6 · SpriteKit) with a Commodore‑64‑inspired vector look, rendered at modern high resolution and butter‑smooth frame rates (Apple Silicon, ProMotion 120 Hz). Almost every graphic is procedural vector geometry — only the two bosses use traced vector‑contour textures — and every sound effect is synthesized in real time; the bundled media are two chiptune music tracks, the boss textures and an optional pack of recorded sound effects. Three game modes, nine power‑ups, gravity wells, enemy saucers, two bosses, a pixel‑font HUD, and a deterministic replay system that can render promo GIFs headlessly.

## Download

**[➜ Download the latest signed & notarized DMG](https://github.com/DanielMuellerIR/exploids/releases/latest)** — open it, drag *Exploids* into Applications and double‑click. Signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper warning. Requires macOS 11 or newer (Apple Silicon).

Prefer to build from source? See [Build & run](#build--run-cli--headless-friendly) below.

## Screenshots

<p align="center"><img src="screenshots/sc0.jpg" width="860" alt="Survival mode in full flow — the ship fires a rainbow stream of shots past a purple gravity well as asteroids and an enemy saucer close in"></p>

| Option drone + shield | In-game glossary |
|:--:|:--:|
| ![Asteroid field with an option drone acquired, the ship shielded and compressed](screenshots/sc1.jpg) | ![In-game glossary of objects and power-ups](screenshots/sc3.jpg) |
| **Laser beam** | **Gravity well + screen bomb** |
| ![The hold-to-fire laser beam sweeping the field](screenshots/sc2.jpg) | ![A gravity well warps space as a screen bomb detonates](screenshots/sc4.jpg) |

## Build & run (CLI / headless‑friendly)

No Xcode project — a Swift Package Manager executable compiled into a `.app` bundle. The whole toolchain is scriptable (handy for automation and AI agents):

```bash
./build-app.sh                                   # build -> Exploids.app (double-clickable)
open Exploids.app                                # launch
.build/release/exploids                          # launch the bare binary (logs in the terminal)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # run the unit tests
```

### Signed + notarized DMG

```bash
bash wrappers/sign-and-release.sh                # -> build/Exploids-<version>.dmg, Gatekeeper-clean
bash wrappers/sign-and-release.sh --publish      # also tags + uploads the DMG to GitHub Releases
```

## Game modes

Pick on the start screen (▲/▼ to switch, ◀/▶ for the Ancient/Mad starting level, Space to start):

- **Ancient Asteroids** — the original Exploids mode. Fixed playfield; objects wrap around the screen edges.
- **Mad Meteoroids** — the whole field (asteroids, gravity wells, power‑ups, starfield) rotates continuously around the screen center while your ship stays exempt (Crazy‑Comets style). Rotation speed ramps with the level, with scheduled direction changes and occasional "record‑scratch" jolts at higher levels.
- **Classic Asteroids** — a dedicated, one-player 1979-inspired ruleset: monochrome white gameplay vectors, wave-based normal rocks, four-shot firing that is single-press by default with optional hold-to-rapid-fire, horizontal large/small saucers, three starting ships, a bonus ship at each 10,000 points and `H` hyperspace. It always begins at wave 1, has no power-ups, bosses, special rocks, timer or hands-free auto-fire, and keeps its own high-score board. The modern starfield, HUD colors, music toggle and HDR/EDR glow remain.

Classic behavior was implemented from the [original operations manual](https://www.classicgaming.cc/classics/asteroids/files/tech-info/asteroids_manual.pdf) and [recovered program source](https://github.com/historicalsource/asteroids/blob/main/A35131.1A) as references. No Atari art, audio samples, logos, coordinate tables or source code are included.

## Power‑ups

Ancient and Mad include nine pickups, each with its own vector glyph. Classic has none:

| Glyph | Power‑up | Effect |
|:--:|--|--|
| `S` | Shield | Energy shield absorbs a hit |
| `W` | Spread | Triple spread shot |
| `R` | Rapid | Greatly increased fire rate |
| `O` | Option | A satellite drone fires alongside you |
| `B` | Bomb | Screen‑clearing explosion |
| `L` | Laser beam | Hold to fire a sweeping, edge‑wrapping beam |
| `T` | Rear | Adds a backward‑firing shot |
| `C` | Compress | Shrinks the ship to ~30 % (smaller target) |
| `+` | Extra life | Revive centered with brief invincibility |

## Enemies & bosses

In Ancient and Mad, the field fills up as you climb the levels:

- **Enemy saucers** — a large green UFO that fires in random directions, and a small pink one that snipes at your ship. Both drift in with a slight homing pull.
- **Gravity wells** — black holes that warp space, drag everything inward and crush the ship on contact.
- **Imploding asteroids** — magenta‑outlined rocks that collapse into a fresh gravity well when you shoot them.
- **Wobbling bombs** — red rocks that pulse and grow through stages, then detonate into a spread of fast fragments.
- **Space Cat** — a stalking boss that takes cover behind asteroids, leads your movement and fires twin eye‑beams; takes three hits to drive off.
- **The Idol** — a large floating stone head that drifts in, dodges your fire and spews an armada of saucers from its mouth; takes ten hits to destroy.

## Controls

- **Start screen:** ▲/▼ switch game mode · ◀/▶ choose the Ancient/Mad starting level (Classic always starts at wave 1) · Space/Enter start · D (or 30 s idle) watch an Ancient autopilot demo · I glossary · O settings · 1–5 watch a replay from the selected mode's high-score board
- **Ancient / Mad:** Arrow keys / WASD to fly · Space to fire (hold for auto-fire / the sweeping beam) · M toggle music · G toggle HDR Glow · Esc pause / quit
- **Classic:** Arrow keys / WASD to fly · press Space once per shot, or enable Rapid Fire in Settings and hold it · H hyperspace · M toggle music · G toggle HDR Glow · Esc pause / quit
- **Classic display:** the arcade playfield is always a fixed 1024×768 logical arena. Window and full-screen changes scale it uniformly; non-4:3 displays use black bars rather than stretching or expanding gameplay.
- **Settings:** M music · N SFX style · F auto-fire / Classic Rapid Fire · G HDR Glow · Control-Command-F native full screen on Mac. Classic always uses its procedural synth profile and offers hold-to-fire Rapid Fire, which starts off on every launch and never fires without the key being held; music and HDR remain independently toggleable. HDR Glow defaults to on, remembers your choice and reports `UNAVAILABLE` on SDR-only displays. Mac full screen defaults to off, follows both the shortcut and green window button, remembers successful changes across launches, and hides the cursor only during full-screen gameplay.
- **Replay view:** Esc exits the replay back to the title screen.
- High scores are saved locally; enter your name on the board when you make the cut.
- **Cheat:** press `#` for a free extra life — handy for testing, or for a relaxed, no‑pressure run.

## Replay & GIF export

The simulation is **deterministic**: every run is recorded as just its seed plus your key presses, so it can be reproduced bit‑for‑bit. Two things fall out of that:

- **Watch high‑score runs again** — on the title screen press `1`–`5` to replay that entry exactly as it was played; `Esc` exits.
- **Render promo GIFs headlessly** — turn a replay into a clean, cursor‑free animated GIF straight from the command line, no window needed:

```bash
exploids --render-demo --out demo.gif            # scripted sample run -> GIF (pipeline self-test)
exploids --export-replay 0 --out run.replay      # export standard-board entry #0 (the default)
exploids --export-replay 0 --mode classic --out classic.replay
exploids --render-replay run.replay --out run.gif --scale 480 --fps 30
```

## How it compares

Exploids is a hobby clone, not a product. For honest context, with the weak spots named too:

**Versus the original Asteroids (1979)** — Classic Asteroids is now a separate arcade-faithful mode with monochrome outline rocks, two saucers, hyperspace, wave scoring and bonus ships, while retaining Exploids' modern HDR/EDR renderer and deterministic replay system. Ancient Asteroids and the rotating Mad Meteoroids remain the expanded, colorful experience with nine power-ups, gravity wells, special rocks, bosses, a sweeping laser beam and chiptune music.

**Versus Maelstrom** — [Maelstrom](https://github.com/libsdl-org/Maelstrom) (Ambrosia, 1992; a GPL SDL port since 1995, today an SDL2/SDL3 build that runs on Apple Silicon) is the best-known still-maintained open-source Asteroids clone for the Mac, and the fairer yardstick: it already has power-ups, bonus objects and rich sound. Where Exploids actually differs:

- **Rendering:** Exploids is real-time *vector* geometry drawn procedurally at high resolution and 120 Hz ProMotion, with HDR/EDR neon glow on supported displays; Maelstrom is bitmap / sprite raster art.
- **Audio:** Exploids synthesizes its sound effects live on the audio thread (only the two music tracks are files); Maelstrom plays sampled sound.
- **Mechanics:** the rotating Mad Meteoroids mode, gravity wells and imploding asteroids are specific to Exploids.
- **Stack:** native Swift 6 / SpriteKit / AppKit on Apple Silicon, versus a C/SDL port.

**Where Maelstrom is plainly ahead:** it has single- *and* multiplayer (cooperative and competitive), game-controller and touch support, runs on more platforms, and carries 30 years of refinement and community. Exploids is single-player, primarily keyboard and macOS-desktop (an iOS touch target is an early work in progress), and young. It also ships non-commercial music (see below), a restriction Maelstrom's CC-licensed assets don't impose.

## Licensing

- **Code:** [MIT](LICENSE) — © 2026 Daniel Müller.
- **Heading font** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P): **SIL Open Font License 1.1** (`Sources/GameCore/Fonts/OFL.txt`) — free for any use, including commercial.
- **⚠️ Music** `Sources/GameCore/Music/*.mp3` (two chiptune tracks): generated with **[musely.ai](https://musely.ai)** on its Free Plan — **personal, non‑commercial use only**. These tracks are **not** covered by the MIT code license and keep musely.ai's separate terms. Before any commercial use, replace them with your own / CC0 / commercially‑licensed music. All other audio is synthesized at runtime (no third‑party rights).

## iOS target (work in progress)

The repo also contains an iOS app target under `ios/` (SpriteKit + on‑screen touch controls) that links the same `GameCore` engine as the macOS build. In Classic, its left flight cluster is unchanged and the right column becomes **HYPER** (tap), **THRUST** (hold) and **FIRE** (hold; one shot while Rapid Fire is off, repeated shots while it is on); Ancient and Mad retain their existing controls. It is a young work in progress and not yet released.

## Requirements

macOS **14+**, Apple Silicon. To build: a full Xcode install (the scripts use `DEVELOPER_DIR=/Applications/Xcode.app/...` for the SpriteKit/XCTest toolchain).

---

*Status: private / personal project — a procedural, vector‑style homage to the 1979 Asteroids arcade classic, with no code or assets taken from it.*
