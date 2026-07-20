// Determinismus- und Replay-Tests: GameRandom-PRNG, Seed-Verankerung, Regressionsproben, Replay-Datenmodell, Aufnahme/Wiedergabe, Highscore-Persistenz, In-App-Replay-UI und Archiv.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class ReplayDeterminismTests: GameCoreTestCase {

    // MARK: - GameRandom (deterministischer PRNG, Phase 1.1)

    /// Gleicher Seed muss IMMER dieselbe Sequenz liefern — das Fundament fürs Replay.
    func testGameRandomSameSeedSameSequence() {
        var a = GameRandom(seed: 12345)
        var b = GameRandom(seed: 12345)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next(), "Gleicher Seed muss identische Folge erzeugen")
        }
    }

    /// Unterschiedliche Seeds müssen unterschiedliche Sequenzen liefern (sonst wäre der Seed wirkungslos).
    func testGameRandomDifferentSeedDiffersSequence() {
        var a = GameRandom(seed: 1)
        var b = GameRandom(seed: 2)
        var anyDifferent = false
        for _ in 0..<100 where a.next() != b.next() {
            anyDifferent = true
        }
        XCTAssertTrue(anyDifferent, "Verschiedene Seeds dürfen nicht dieselbe Folge erzeugen")
    }

    /// `Int.random(in:using:)` über GameRandom muss reproduzierbar sein — das ist die Schreibweise,
    /// auf die in Phase 1.3 alle 65 Gameplay-Zufallsaufrufe umgestellt werden.
    func testGameRandomReproducibleWithStdlibAPIs() {
        var a = GameRandom(seed: 777)
        var b = GameRandom(seed: 777)
        let rollsA = (0..<50).map { _ in Int.random(in: 1...6, using: &a) }
        let rollsB = (0..<50).map { _ in Int.random(in: 1...6, using: &b) }
        XCTAssertEqual(rollsA, rollsB, "Int.random(in:using:) muss bei gleichem Seed reproduzierbar sein")
    }

    // MARK: - Seed-Verankerung in GameScene (Phase 1.2)

    /// Ein injizierter Seed muss übernommen werden; ohne Injektion wird trotzdem einer gesetzt.
    func testStartNewGameAppliesInjectedSeed() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)

        scene.startNewGame(seed: 4242)
        XCTAssertEqual(scene.currentSeed, 4242, "Injizierter Seed muss übernommen werden")

        scene.startNewGame(seed: 99)
        XCTAssertEqual(scene.currentSeed, 99, "Neuer injizierter Seed muss den alten ersetzen")

        // Ohne Injektion muss dennoch ein (ausgewürfelter) Seed gesetzt sein – pendingSeed wurde
        // beim vorigen Start geleert, also darf 99 nicht "kleben".
        scene.startNewGame()
        XCTAssertNotEqual(scene.currentSeed, 99, "Ohne Injektion darf der alte Seed nicht kleben bleiben")
    }

    // MARK: - Determinismus-Regressionsprobe (Phase 1.5, Schlussstein)

    /// Treibt ein frisches Spiel mit festem Seed über `frames` Frames mit fester dt-Folge und einem
    /// rein vom Frame-Index abhängigen (also deterministischen) Eingabe-Skript. Gibt die Szene zurück.
    /// Beide Determinismus-Läufe nutzen exakt diesen Treiber – nur der Seed unterscheidet sich.
    @MainActor
    private func runScriptedGame(seed: UInt64, startLevel: Int, frames: Int,
                                 mode: GameMode = .ancientAsteroids) -> GameScene {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: seed, startLevel: startLevel, mode: mode)

        // Tastenzustände, die wir je nach Frame setzen/lösen (deterministisch).
        var thrustHeld = false
        var rotLeftHeld = false
        var rotRightHeld = false

        for f in 0..<frames {
            // --- Deterministisches Eingabe-Skript (nur abhängig vom Frame-Index) ---
            // Schub für ein mittleres Fenster, danach aus.
            let wantThrust = (f >= 10 && f < 220)
            if wantThrust != thrustHeld {
                if wantThrust { scene.simulateKeyDown(keyCode: 13) } else { scene.simulateKeyUp(keyCode: 13) }
                thrustHeld = wantThrust
            }
            // Links-/Rechts-Drehung in zwei Phasen, damit sich Ausrichtung (und Spawn-Kegel) ändert.
            let wantLeft = (f >= 40 && f < 110)
            if wantLeft != rotLeftHeld {
                if wantLeft { scene.simulateKeyDown(keyCode: 0) } else { scene.simulateKeyUp(keyCode: 0) }
                rotLeftHeld = wantLeft
            }
            let wantRight = (f >= 130 && f < 190)
            if wantRight != rotRightHeld {
                if wantRight { scene.simulateKeyDown(keyCode: 2) } else { scene.simulateKeyUp(keyCode: 2) }
                rotRightHeld = wantRight
            }
            // Feuern: alle 9 Frames ein kurzer Tastendruck (löst Schüsse → Treffer → Splits → Drops aus).
            if f % 9 == 0 { scene.simulateKeyDown(keyCode: 49) }
            if f % 9 == 1 { scene.simulateKeyUp(keyCode: 49) }

            scene.advanceOneStep()   // ein fester Sim-Schritt (Fixed-Timestep), deterministisch
        }
        return scene
    }

    /// Baut einen kanonischen String aus dem gesamten simulationsrelevanten Zustand der Szene.
    /// Da beide Läufe Schritt für Schritt identisch verarbeitet werden, stimmen auch die Array-
    /// Reihenfolgen überein – ein direkter String-Vergleich zeigt jede Divergenz (mit Diff).
    @MainActor
    private func stateSnapshot(_ s: GameScene) -> String {
        func p(_ pt: CGPoint) -> String { "(\(pt.x.bitPattern),\(pt.y.bitPattern))" }
        var out = "score=\(s.score) gt=\(s.gameTime.bitPattern) lvl=\(s.currentLevel)\n"
        out += "ship pos=\(p(s.ship.position)) vel=\(p(s.ship.velocity)) rot=\(s.ship.zRotation.bitPattern)\n"
        out += "ast[\(s.activeAsteroids.count)]: "
        for a in s.activeAsteroids {
            out += "\(p(a.position))v\(p(a.velocity))pi\(a.pitch.bitPattern)ya\(a.yaw.bitPattern)sz\(a.sizeClass.rawValue) "
        }
        out += "\nufo[\(s.activeUFOs.count)]: "
        for u in s.activeUFOs { out += "\(p(u.position))v\(p(u.velocity)) " }
        out += "\npow[\(s.activePowerUps.count)]: "
        for pu in s.activePowerUps { out += "\(p(pu.position))t\(pu.type.rawValue) " }
        out += "\ncat[\(s.activeCats.count)]: "
        for c in s.activeCats { out += "\(p(c.position)) " }
        out += "\nwell[\(s.activeGravityWells.count)]: "
        for w in s.activeGravityWells { out += "\(p(w.position)) " }
        out += "\nlas[\(s.activeLasers.count)]: "
        for l in s.activeLasers {
            out += "\(p(l.position))v\(p(l.velocity))life\(l.lifetime.bitPattern)spent\(l.isClassicSpent) "
        }
        out += "\nclassicFrame=\(s.classicSession.nextArcadeFrame)"
        out += " classicRemainder=\(s.classicSession.arcadeClockAccumulator)"
        return out
    }

    /// Kernprobe: gleicher Seed + gleiche Eingabe/dt-Folge ⇒ bit-identischer Endzustand.
    func testSimulationIsDeterministicForSameSeedAndInput() {
        let a = runScriptedGame(seed: 0xDEADBEEF, startLevel: 1, frames: 600)
        let b = runScriptedGame(seed: 0xDEADBEEF, startLevel: 1, frames: 600)
        XCTAssertEqual(stateSnapshot(a), stateSnapshot(b),
                       "Zwei Läufe mit gleichem Seed und gleicher Eingabe müssen identisch sein")

        // Zusätzlich der RNG-Zustand: aus identischen Generatoren muss der nächste Wert gleich sein.
        var ra = a.rng, rb = b.rng
        XCTAssertEqual(ra.next(), rb.next(), "RNG-Zustand beider Läufe muss identisch sein")
    }

    /// Langzeit-Determinismus über Level-Übergänge UND Bosse: Ein langer Lauf (Level 5 aufwärts,
    /// Auto-Feuer, viele Extra-Leben, damit er nicht endet) muss bei gleichem Seed bit-identisch
    /// bleiben. Deckt ab, was die kurzen Proben nicht erreichten: UFO-/Boss-/Katzen-Spawns,
    /// Gravity-Wells, Power-up-Drops, mehrere Level-Aufstiege.
    func testSimulationDeterministicLongRunWithBossesAndLevels() {
        @MainActor func longRun(seed: UInt64) -> GameScene {
            let scene = GameScene(size: CGSize(width: 1000, height: 800))
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
            view.presentScene(scene)
            scene.autoFire = true
            scene.startNewGameForTesting(seed: seed, startLevel: 5)
            scene.setExtraLivesForTesting(99)
            let dt: TimeInterval = 1.0 / 60.0
            var rotLeft = false, rotRight = false, thrust = false
            for f in 0..<6000 {
                let wantLeft = (f % 140) < 60
                if wantLeft != rotLeft { wantLeft ? scene.simulateKeyDown(keyCode: 0) : scene.simulateKeyUp(keyCode: 0); rotLeft = wantLeft }
                let wantRight = (f % 140) >= 70 && (f % 140) < 120
                if wantRight != rotRight { wantRight ? scene.simulateKeyDown(keyCode: 2) : scene.simulateKeyUp(keyCode: 2); rotRight = wantRight }
                let wantThrust = (f % 50) < 18
                if wantThrust != thrust { wantThrust ? scene.simulateKeyDown(keyCode: 13) : scene.simulateKeyUp(keyCode: 13); thrust = wantThrust }
                scene.update(1000.0 + Double(f) * dt)
                // Extra-Leben nachfüllen, damit der Lauf garantiert nicht in Game Over endet
                // (in BEIDEN Läufen identisch -> symmetrisch -> valider Determinismus-Test).
                if scene.extraLivesForTesting < 10 { scene.setExtraLivesForTesting(99) }
            }
            return scene
        }
        let a = longRun(seed: 0xB0551)
        let b = longRun(seed: 0xB0551)
        XCTAssertEqual(stateSnapshot(a), stateSnapshot(b),
                       "Langer boss-/levelübergreifender Lauf muss bei gleichem Seed bit-identisch sein")
        XCTAssertGreaterThan(a.currentLevel, 5, "Der Lauf muss mehrere Level-Übergänge durchlaufen haben")
        XCTAssertEqual(a.gameState, .playing, "Mit Extra-Leben darf der Lauf nicht enden")
    }

    /// Gegenprobe ("der Test hat Zähne"): ein anderer Seed muss zu einem anderen Endzustand führen.
    /// Beweist, dass der Snapshot tatsächlich die zufallsgetriebene Divergenz erfasst – ein blind
    /// immer-gleicher Snapshot würde hier fälschlich bestehen.
    func testSimulationDivergesForDifferentSeed() {
        let a = runScriptedGame(seed: 1, startLevel: 1, frames: 600)
        let b = runScriptedGame(seed: 2, startLevel: 1, frames: 600)
        XCTAssertNotEqual(stateSnapshot(a), stateSnapshot(b),
                          "Verschiedene Seeds müssen zu unterschiedlichen Verläufen führen")
    }

    /// Determinismus auch im Mad-Modus auf höherem Level (Feld-Rotation, UFO-/Boss-/Katzen-Pfade).
    func testSimulationIsDeterministicMadModeHighLevel() {
        let a = runScriptedGame(seed: 4242, startLevel: 5, frames: 800, mode: .madMeteoroids)
        let b = runScriptedGame(seed: 4242, startLevel: 5, frames: 800, mode: .madMeteoroids)
        XCTAssertEqual(stateSnapshot(a), stateSnapshot(b),
                       "Auch Mad-Modus/höheres Level muss bei gleichem Seed reproduzierbar sein")
    }

    // MARK: - Replay-Datenmodell (Phase 2.1)

    /// Round-Trip: kodieren → dekodieren ergibt exakt das Original.
    func testReplayRoundTripEncodeDecode() {
        let events = [
            InputEvent(frameIndex: 0, keyCode: 49, isDown: true),
            InputEvent(frameIndex: 1, keyCode: 49, isDown: false),
            InputEvent(frameIndex: 12, keyCode: 13, isDown: true),
            InputEvent(frameIndex: 90, keyCode: 13, isDown: false)
        ]
        let original = Replay(seed: 0xCAFEBABE, startLevel: 3, gameMode: .madMeteoroids,
                              events: events, frameCount: 300)

        let data = try! original.encoded()
        let restored = try! Replay(data: data)
        XCTAssertEqual(original, restored, "Round-Trip muss das Original exakt erhalten")

        // Größenabschätzung dokumentieren: paar Events + frameCount sollten winzig bleiben.
        XCTAssertLessThan(data.count, 8000, "Eine kurze Aufnahme sollte wenige KB groß sein (war \(data.count) B)")
    }

    /// v3 bis v8 bleiben für Standardmodi kompatibel; Classic akzeptiert weiterhin erst ab v8.
    func testReplayVersionCompatibility() {
        let ok = Replay(seed: 1, startLevel: 1, gameMode: .ancientAsteroids, events: [], frameCount: 0)
        XCTAssertTrue(ok.isCompatible)
        for version in 3...8 {
            let legacyAncient = Replay(version: version, seed: 1, startLevel: 1,
                                       gameMode: .ancientAsteroids, events: [], frameCount: 0)
            let legacyMad = Replay(version: version, seed: 1, startLevel: 1,
                                   gameMode: .madMeteoroids, events: [], frameCount: 0)
            XCTAssertTrue(legacyAncient.isCompatible)
            XCTAssertTrue(legacyMad.isCompatible)
        }
        for version in 1...7 {
            let legacyClassic = Replay(version: version, seed: 1, startLevel: 1,
                                       gameMode: .classicAsteroids, events: [], frameCount: 0)
            XCTAssertFalse(legacyClassic.isCompatible)
        }
        let classicV8 = Replay(version: 8, seed: 1, startLevel: 1,
                               gameMode: .classicAsteroids, events: [], frameCount: 0)
        XCTAssertTrue(classicV8.isCompatible)
        XCTAssertFalse(classicV8.classicRapidFire)

        for version in [2, Replay.currentLogicVersion + 1] {
            let incompatible = Replay(version: version, seed: 1, startLevel: 1,
                                      gameMode: .ancientAsteroids, events: [], frameCount: 0)
            XCTAssertFalse(incompatible.isCompatible,
                           "Nicht freigegebene Logik-Versionen müssen inkompatibel bleiben")
        }
    }

    func testStartReplayAcceptsLegacyStandardAndV8ClassicButRejectsOlderClassic() {
        for version in 3...8 {
            let standardScene = GameScene(size: CGSize(width: 1000, height: 800))
            let standardView = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
            standardView.presentScene(standardScene)
            let standard = Replay(version: version, seed: 1, startLevel: 1,
                                  gameMode: .ancientAsteroids, events: [], frameCount: 1)
            XCTAssertTrue(standardScene.startReplay(standard))
        }

        for version in 3...7 {
            let classicScene = GameScene(size: CGSize(width: 1000, height: 800))
            let classicView = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
            classicView.presentScene(classicScene)
            let classic = Replay(version: version, seed: 1, startLevel: 1,
                                 gameMode: .classicAsteroids, events: [], frameCount: 1)
            XCTAssertFalse(classicScene.startReplay(classic))
            XCTAssertFalse(classicScene.isReplaying)
        }

        let classicV8Scene = GameScene(size: CGSize(width: 1000, height: 800))
        let classicV8View = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        classicV8View.presentScene(classicV8Scene)
        let classicV8 = Replay(version: 8, seed: 1, startLevel: 1,
                               gameMode: .classicAsteroids, events: [], frameCount: 1)
        XCTAssertTrue(classicV8Scene.startReplay(classicV8))
        XCTAssertFalse(classicV8Scene.classicRapidFire)
    }

    func testReplayDrivenRestartKeepsRecordedSeed() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        let replay = Replay(seed: 0x5EED, startLevel: 1, gameMode: .classicAsteroids,
                            events: [], frameCount: 10)

        XCTAssertTrue(scene.startReplay(replay))
        scene.transitionTo(.gameOver)
        scene.injectReplayInput(keyCode: 49, isDown: true)

        XCTAssertEqual(scene.gameState, .playing)
        XCTAssertEqual(scene.currentSeed, replay.seed,
                       "Auch ein durch Replay-Eingabe ausgelöster Neustart muss deterministisch bleiben")
    }

    // MARK: - Aufnahme → Wiedergabe (Phase 2.2 + 2.3)

    /// Treibt eine Szene mit einem festen, nur vom Frame-Index abhängigen Skript: NUR Drehen + Feuern,
    /// KEIN Schub. So bleibt das Schiff in der Bildmitte und fliegt garantiert nicht in einen frisch
    /// gespawnten Asteroiden – der Lauf endet im Fenster nicht (sauberer Aufnahme/Wiedergabe-Vergleich).
    @MainActor
    private func driveNoThrustScript(_ s: GameScene, frames: Int, base: TimeInterval) {
        var fireDown = false
        for f in 0..<frames {
            if f == 30 { s.simulateKeyDown(keyCode: 0) }      // Drehung links an
            if f == 90 { s.simulateKeyUp(keyCode: 0) }        // links aus
            if f == 100 { s.simulateKeyDown(keyCode: 2) }     // Drehung rechts an
            if f == 150 { s.simulateKeyUp(keyCode: 2) }       // rechts aus
            if f % 7 == 0 { s.simulateKeyDown(keyCode: 49); fireDown = true }
            else if fireDown { s.simulateKeyUp(keyCode: 49); fireDown = false }
            s.advanceOneStep()   // ein fester Sim-Schritt; `base` ist hier nicht mehr nötig
        }
    }

    /// Kernprobe Phase 2: Ein aufgezeichneter Lauf, anschließend abgespielt, ergibt exakt denselben
    /// Endzustand – damit ist die Recorder→Player-Mechanik (Eingaben + dt-Folge) validiert.
    func testRecordThenReplayReproducesRun() {
        let frames = 200
        let seed: UInt64 = 0x1234_5678

        // --- Aufnahme ---
        let a = GameScene(size: CGSize(width: 1000, height: 800))
        let viewA = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewA.presentScene(a)
        a.startNewGameForTesting(seed: seed, startLevel: 1)
        driveNoThrustScript(a, frames: frames, base: 1000.0)

        XCTAssertEqual(a.gameState, .playing, "Aufnahme-Lauf darf im Testfenster nicht enden")
        let snapA = stateSnapshot(a)
        guard let replay = a.currentReplayForTesting() else {
            return XCTFail("Es muss eine laufende Aufnahme geben")
        }
        // Fixed-Timestep, getrieben per advanceOneStep: ein Schritt pro Skript-Iteration → frameCount = frames.
        XCTAssertEqual(replay.frameCount, frames)
        XCTAssertFalse(replay.events.isEmpty, "Das Skript muss Tastenereignisse erzeugt haben")

        // --- Wiedergabe in frische Szene ---
        let b = GameScene(size: CGSize(width: 1000, height: 800))
        let viewB = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewB.presentScene(b)
        XCTAssertTrue(b.startReplay(replay), "Kompatibles Replay muss starten")
        // GENAU alle aufgezeichneten Schritte abspielen – ein weiterer Schritt würde finishReplay
        // auslösen und zum Startbildschirm wechseln (Spielzustand verworfen).
        for _ in 0..<replay.frameCount {
            b.advanceOneStep()
        }

        XCTAssertEqual(stateSnapshot(b), snapA, "Wiedergabe muss die Aufnahme bit-genau reproduzieren")
        XCTAssertTrue(b.isReplaying, "Nach genau allen Frames läuft die Wiedergabe noch (Abschluss erst im Folgeframe)")
    }

    /// Aktuelle Probe der seit v8 festen Arena: Sie muss selbst bei einem Host-Resize erhalten
    /// bleiben; Aufnahme und
    /// Wiedergabe enden einschließlich Projektilzustand und rationalem Takt bitgleich.
    func testClassicRecordThenReplaySurvivesHostResizeInCanonicalArena() {
        let frames = 240
        let seed: UInt64 = 0xA7A21_0008
        let recordingViewport = CGSize(width: 1728, height: 1084)

        @MainActor func driveClassic(_ scene: GameScene, resizing view: SKView?) {
            var fireDown = false
            for frame in 0..<frames {
                if frame == 8 { scene.simulateKeyDown(keyCode: 13) }
                if frame == 68 { scene.simulateKeyUp(keyCode: 13) }
                if frame == 24 { scene.simulateKeyDown(keyCode: 0) }
                if frame == 104 { scene.simulateKeyUp(keyCode: 0) }
                if frame.isMultiple(of: 17) {
                    scene.simulateKeyDown(keyCode: 49)
                    fireDown = true
                } else if fireDown {
                    scene.simulateKeyUp(keyCode: 49)
                    fireDown = false
                }
                if frame == frames / 2, let view {
                    view.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
                    XCTAssertEqual(scene.size, GameScene.classicLogicalArenaSize)
                }
                scene.advanceOneStep()
            }
        }

        let recordedScene = GameScene(size: recordingViewport)
        recordedScene.scaleMode = .resizeFill
        let recordedView = SKView(frame: CGRect(origin: .zero, size: recordingViewport))
        recordedView.presentScene(recordedScene)
        recordedScene.externalStepDriving = true
        recordedScene.startNewGameForTesting(seed: seed, startLevel: 1, mode: .classicAsteroids)
        XCTAssertEqual(recordedScene.size, GameScene.classicLogicalArenaSize)
        driveClassic(recordedScene, resizing: recordedView)
        XCTAssertEqual(recordedScene.gameState, .playing)
        let recordedSnapshot = stateSnapshot(recordedScene)
        guard let replay = recordedScene.currentReplayForTesting() else {
            return XCTFail("Classic-Aufnahme fehlt")
        }
        XCTAssertEqual(replay.version, Replay.currentLogicVersion)
        XCTAssertEqual(replay.frameCount, frames)
        XCTAssertEqual(replay.width, 1024)
        XCTAssertEqual(replay.height, 768)

        let replayViewport = CGSize(width: 874, height: 402)
        let replayScene = GameScene(size: replayViewport)
        replayScene.scaleMode = .resizeFill
        let replayView = SKView(frame: CGRect(origin: .zero, size: replayViewport))
        replayView.presentScene(replayScene)
        replayScene.externalStepDriving = true
        XCTAssertTrue(replayScene.startReplay(replay))
        XCTAssertEqual(replayScene.size, GameScene.classicLogicalArenaSize)
        for _ in 0..<replay.frameCount { replayScene.advanceOneStep() }

        XCTAssertEqual(stateSnapshot(replayScene), recordedSnapshot)
    }

    /// Regression: Ein mit AUTO-FEUER gespielter Lauf muss sich exakt reproduzieren. Auto-Feuer
    /// lässt das Schiff ohne Tastendruck schießen; wäre der Zustand nicht in der Aufnahme gespeichert
    /// und beim Abspielen wiederhergestellt, würde das Replay nicht feuern und völlig abweichen.
    func testRecordThenReplayReproducesAutoFireRun() {
        let frames = 300
        let seed: UInt64 = 0x0A07_0F19

        // --- Aufnahme mit Auto-Feuer, OHNE manuelles Schießen (nur Drehen) ---
        let a = GameScene(size: CGSize(width: 1000, height: 800))
        let viewA = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewA.presentScene(a)
        a.autoFire = true
        a.startNewGameForTesting(seed: seed, startLevel: 1)
        var rotLeft = false
        for f in 0..<frames {
            let wantLeft = (f % 80) < 40
            if wantLeft != rotLeft {
                if wantLeft { a.simulateKeyDown(keyCode: 0) } else { a.simulateKeyUp(keyCode: 0) }
                rotLeft = wantLeft
            }
            a.advanceOneStep()
        }
        XCTAssertEqual(a.gameState, .playing, "Auto-Feuer-Lauf darf im Fenster nicht enden")
        let snapA = stateSnapshot(a)
        guard let replay = a.currentReplayForTesting() else { return XCTFail("keine Aufnahme") }
        XCTAssertTrue(replay.autoFire, "Die Aufnahme muss den Auto-Feuer-Zustand festhalten")

        // --- Wiedergabe in frische Szene mit Auto-Feuer AUS als Default ---
        let b = GameScene(size: CGSize(width: 1000, height: 800))
        let viewB = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewB.presentScene(b)
        XCTAssertFalse(b.autoFire, "Frische Szene hat Auto-Feuer per Default aus")
        XCTAssertTrue(b.startReplay(replay))
        XCTAssertTrue(b.autoFire, "startReplay muss den Auto-Feuer-Zustand der Aufnahme wiederherstellen")
        for _ in 0..<replay.frameCount {
            b.advanceOneStep()
        }
        XCTAssertEqual(stateSnapshot(b), snapA, "Auto-Feuer-Lauf muss sich bit-genau reproduzieren")
    }

    /// Round-Trip mit gesetztem autoFire-Feld (Persistenz des neuen Feldes).
    func testReplayAutoFieldRoundTrips() {
        let r = Replay(seed: 5, startLevel: 2, gameMode: .ancientAsteroids,
                       events: [], frameCount: 1, autoFire: true)
        let restored = try! Replay(data: try! r.encoded())
        XCTAssertTrue(restored.autoFire)
        XCTAssertEqual(r, restored)
    }

    func testReplayClassicRapidFireFieldRoundTripsAndDefaultsOffWhenMissing() throws {
        let rapid = Replay(seed: 6, startLevel: 1, gameMode: .classicAsteroids,
                           events: [], frameCount: 1, classicRapidFire: true)
        let encoded = try rapid.encoded()
        let restored = try Replay(data: encoded)
        XCTAssertTrue(restored.classicRapidFire)
        XCTAssertEqual(rapid, restored)

        var format = PropertyListSerialization.PropertyListFormat.binary
        var legacyPayload = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, options: [], format: &format)
                as? [String: Any]
        )
        legacyPayload.removeValue(forKey: "classicRapidFire")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: legacyPayload,
            format: .binary,
            options: 0
        )
        let legacy = try Replay(data: legacyData)
        XCTAssertFalse(legacy.classicRapidFire)
    }

    /// Inkompatible Aufnahmen (fremdes Logik-Tag) dürfen nicht abgespielt werden.
    func testStartReplayRejectsIncompatibleVersion() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        let stale = Replay(version: Replay.currentLogicVersion + 1, seed: 1, startLevel: 1,
                           gameMode: .ancientAsteroids, events: [], frameCount: 1)
        XCTAssertFalse(scene.startReplay(stale), "Inkompatible Aufnahme darf nicht starten")
        XCTAssertFalse(scene.isReplaying)
    }

    // MARK: - Replay an Highscore persistieren (Phase 2.4)

    /// End-to-End: Ein Lauf, der als Highscore endet, hängt seine Aufnahme an den Eintrag.
    func testHighScoreEntryGetsReplayAttached() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: 0xA11CE, startLevel: 1)

        // Ein paar Frames spielen (Aufnahme läuft mit).
        driveNoThrustScript(scene, frames: 50, base: 1000.0)
        // Score über den tatsächlich geladenen Spitzenwert setzen, damit lokale Test-Defaults den
        // End-to-End-Pfad nicht davon abhängig machen, ob 99.999 Punkte bereits übertroffen wurden.
        scene.addScoreForTesting((scene.highScores.first?.score ?? 0) + 1)

        // Game Over erzwingen (Schiff hat weder Schild noch Extra-Leben → Game Over).
        var guardCount = 0
        while scene.gameState == .playing && guardCount < 5 {
            scene.damageShipForTesting()
            guardCount += 1
        }
        XCTAssertEqual(scene.gameState, .nameEntry, "Highscore-Lauf muss in die Initialen-Eingabe führen")
        XCTAssertNotNil(scene.lastReplay, "Bei Game Over muss die Aufnahme finalisiert sein")

        // Initialen eingeben + bestätigen → recordHighScore.
        scene.simulateTypeCharacter("A")
        scene.simulateTypeCharacter("C")
        scene.simulateTypeCharacter("E")
        scene.simulateKeyDown(keyCode: 36) // Enter

        guard let top = scene.highScores.first else { return XCTFail("Kein Highscore-Eintrag") }
        XCTAssertNotNil(top.replayData, "Der Highscore-Eintrag muss eine Aufnahme tragen")
        let replay = scene.replay(for: top)
        XCTAssertNotNil(replay, "Die angehängte Aufnahme muss dekodierbar sein")
        XCTAssertEqual(replay?.seed, 0xA11CE, "Die Aufnahme muss den Seed des Laufs tragen")
    }

    /// Persistenz-Round-Trip: Eine an einen Highscore gehängte Aufnahme spielt nach Speichern/Laden
    /// (JSON wie in UserDefaults) noch immer identisch ab.
    func testPersistedHighScoreReplayStillReproduces() {
        // Aufnahme + Referenz-Snapshot erzeugen.
        let a = GameScene(size: CGSize(width: 1000, height: 800))
        let viewA = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewA.presentScene(a)
        a.startNewGameForTesting(seed: 0xBEEF_F00D, startLevel: 1)
        driveNoThrustScript(a, frames: 200, base: 1000.0)
        let snapA = stateSnapshot(a)
        let replay = a.currentReplayForTesting()!

        // In einen Highscore packen und wie die Persistenz JSON-codieren/decodieren.
        let entry = HighScore(initials: "ACE", score: 12345, date: Date(),
                              replayData: try! replay.encoded())
        let json = try! JSONEncoder().encode([entry])
        let reloaded = try! JSONDecoder().decode([HighScore].self, from: json)

        // Aus dem neugeladenen Eintrag abspielen.
        let b = GameScene(size: CGSize(width: 1000, height: 800))
        let viewB = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        viewB.presentScene(b)
        guard let restored = b.replay(for: reloaded[0]) else {
            return XCTFail("Neugeladene Aufnahme nicht dekodierbar")
        }
        XCTAssertTrue(b.startReplay(restored))
        // Genau alle Schritte konsumieren (kein Abschluss-Schritt, sonst Wechsel zum Startbildschirm).
        for _ in 0..<restored.frameCount {
            b.advanceOneStep()
        }
        XCTAssertEqual(stateSnapshot(b), snapA, "Persistierte Aufnahme muss nach Neuladen identisch abspielen")
    }

    // MARK: - In-App-Replay-UI (Phase 2.5)

    /// Baut eine Szene, spielt kurz, erzwingt Game Over und trägt den Lauf als Highscore-Eintrag #1
    /// mit angehängter Aufnahme ein. Rückgabe: die Szene (Startbildschirm).
    @MainActor
    private func makeSceneWithRecordedHighScore(seed: UInt64, frames: Int) -> GameScene {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: seed, startLevel: 1)
        driveNoThrustScript(scene, frames: frames, base: 1000.0)
        scene.addScoreForTesting(99999)
        var guardCount = 0
        while scene.gameState == .playing && guardCount < 5 {
            scene.damageShipForTesting(); guardCount += 1
        }
        scene.simulateTypeCharacter("X")
        scene.simulateTypeCharacter("Y")
        scene.simulateTypeCharacter("Z")
        scene.simulateKeyDown(keyCode: 36) // Enter -> recordHighScore
        scene.transitionTo(.startScreen)
        return scene
    }

    /// Zahlentaste startet das Replay; ESC bricht ab und kehrt zum Startbildschirm zurück.
    func testInAppReplayLaunchAndExit() {
        let scene = makeSceneWithRecordedHighScore(seed: 0x5EED, frames: 80)
        XCTAssertNotNil(scene.highScores.first?.replayData, "Setup: Eintrag muss eine Aufnahme tragen")

        scene.simulateTypeCharacter("1") // Ziffer 1 -> Replay des ersten Eintrags
        XCTAssertTrue(scene.isReplaying, "Ziffer 1 muss das Replay starten")
        XCTAssertEqual(scene.gameState, .playing)

        var t = 3000.0
        for _ in 0..<10 { scene.update(t); t += 1.0 / 60.0 }
        XCTAssertTrue(scene.isReplaying, "Während der Wiedergabe läuft das Replay weiter")

        scene.simulateKeyDown(keyCode: 53) // Escape
        XCTAssertFalse(scene.isReplaying, "ESC muss die Wiedergabe abbrechen")
        XCTAssertEqual(scene.gameState, .startScreen, "Nach Abbruch zurück zum Startbildschirm")
    }

    /// Eine vollständig abgespielte Aufnahme beendet sich selbst und kehrt zum Startbildschirm zurück.
    func testInAppReplayRunsToEndAndReturns() {
        let scene = makeSceneWithRecordedHighScore(seed: 0xF00D, frames: 80)
        guard let replay = scene.replay(for: scene.highScores.first!) else {
            return XCTFail("Setup: Aufnahme fehlt")
        }
        XCTAssertTrue(scene.watchHighScoreReplay(at: 0))

        var t = 4000.0
        for _ in 0...(replay.frameCount + 2) { scene.update(t); t += 1.0 / 60.0 }
        XCTAssertFalse(scene.isReplaying, "Nach allen Frames ist die Wiedergabe beendet")
        XCTAssertEqual(scene.gameState, .startScreen, "und kehrt zum Startbildschirm zurück")
    }

    /// Ein ungültiger Index startet kein Replay (deterministisch, unabhängig von persistierten Scores).
    func testWatchReplayNoOpForInvalidIndex() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        XCTAssertFalse(scene.watchHighScoreReplay(at: 999), "Index außerhalb der Liste startet nichts")
        XCTAssertFalse(scene.watchHighScoreReplay(at: -1), "Negativer Index startet nichts")
        XCTAssertFalse(scene.isReplaying)
    }

    /// Replay-Archiv: Bei Game Over wird die Aufnahme als Datei ins gesetzte Verzeichnis geschrieben –
    /// auch wenn der Lauf KEIN Highscore ist (Voraussetzung, um nach einem guten Spiel ein GIF zu rendern).
    func testReplayArchivedToDiskOnGameOver() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("exploids-replay-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.replaySaveDirectory = tmp
        scene.startNewGameForTesting(seed: 0xAABB, startLevel: 1)
        driveNoThrustScript(scene, frames: 40, base: 1000.0)

        // Game Over erzwingen (kein Schild/Extra-Leben → Game Over).
        var guardCount = 0
        while scene.gameState == .playing && guardCount < 5 {
            scene.damageShipForTesting(); guardCount += 1
        }

        let files = ((try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "replay" }
        XCTAssertEqual(files.count, 1, "Bei Game Over muss genau eine Aufnahme im Archiv liegen")
        // Die Datei muss eine dekodierbare, kompatible Aufnahme mit dem Seed des Laufs sein.
        let replay = try Replay(data: try Data(contentsOf: files[0]))
        XCTAssertTrue(replay.isCompatible)
        XCTAssertEqual(replay.seed, 0xAABB)
    }

}
