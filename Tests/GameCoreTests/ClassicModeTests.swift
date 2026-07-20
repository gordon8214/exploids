import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class ClassicModeTests: GameCoreTestCase {
    private let arenaSize = CGSize(width: 800, height: 600)

    func testThreeWayModeSelectionRemembersStandardLevelAndForcesClassicWaveOne() {
        let (scene, view) = makeScene()
        _ = view
        scene.transitionTo(.startScreen)
        for _ in 0..<3 { scene.simulateKeyDown(keyCode: 124) }
        XCTAssertEqual(scene.selectedStartLevel, 4)

        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.selectedGameMode, .madMeteoroids)
        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.selectedGameMode, .classicAsteroids)
        XCTAssertTrue(scene.levelSelectionLabel.isHidden)

        scene.simulateKeyDown(keyCode: 124)
        XCTAssertEqual(scene.selectedStartLevel, 4, "Classic darf die gemerkte Standard-Auswahl nicht ändern")
        scene.simulateKeyDown(keyCode: 36)

        XCTAssertEqual(scene.gameMode, .classicAsteroids)
        XCTAssertEqual(scene.currentLevel, 1)
        XCTAssertEqual(scene.classicSession.wave, 1)
        XCTAssertEqual(scene.currentReplayForTesting()?.startLevel, 1)
        XCTAssertEqual(scene.currentReplayForTesting()?.gameMode.rawValue, 2)

        scene.transitionTo(.startScreen)
        scene.simulateKeyDown(keyCode: 125)
        XCTAssertEqual(scene.selectedGameMode, .madMeteoroids)
        XCTAssertEqual(scene.selectedStartLevel, 4)
        XCTAssertFalse(scene.levelSelectionLabel.isHidden)
    }

    func testClassicWaveCountsDelayAndEntityIsolation() {
        XCTAssertEqual((1...6).map(ClassicTuning.largeAsteroidCount), [4, 6, 8, 10, 11, 11])
        let (scene, view) = makeClassicScene(seed: 11)
        _ = view
        let unlockedLevel = scene.maxLevelReached

        XCTAssertEqual(scene.activeAsteroids.count, 4)
        XCTAssertTrue(scene.activeAsteroids.allSatisfy { $0.sizeClass == .large })
        XCTAssertTrue(scene.activeUFOs.isEmpty)
        XCTAssertTrue(scene.activeGravityWells.isEmpty)
        XCTAssertTrue(scene.activePowerUps.isEmpty)
        XCTAssertFalse(scene.children.contains { $0 is OptionDrone })
        XCTAssertNil(scene.activeHead)
        XCTAssertTrue(scene.activeCats.isEmpty)
        XCTAssertTrue(scene.timerLabel.isHidden)
        XCTAssertEqual(scene.levelLabel.text, "WAVE: 1")

        scene.clearAllEntitiesForTesting()
        advance(scene, seconds: ClassicTuning.waveDelay - 0.02)
        XCTAssertEqual(scene.classicSession.wave, 1)
        XCTAssertTrue(scene.activeAsteroids.isEmpty)
        advance(scene, seconds: 0.05)
        XCTAssertEqual(scene.classicSession.wave, 2)
        XCTAssertEqual(scene.activeAsteroids.count, 6)
        XCTAssertEqual(scene.maxLevelReached, unlockedLevel,
                       "Classic-Wellen dürfen die Standard-Level-Freischaltung nicht verändern")
    }

    func testClassicWaveDelayDoesNotWaitForActiveSaucer() {
        let (scene, view) = makeClassicScene(seed: 111)
        _ = view
        scene.clearAllEntitiesForTesting()
        scene.classicSession.shipPhase = .destroyed(reappearAt: .greatestFiniteMagnitude)
        scene.ship.isHidden = true

        var saucerRNG = GameRandom(seed: 9)
        let saucer = UFO(isSmall: false, startOnLeft: true,
                          screenSize: arenaSize, using: &saucerRNG)
        saucer.applyClassicBehavior(startOnLeft: true, currentTime: 100)
        saucer.position = CGPoint(x: 250, y: 200)
        saucer.velocity = .zero
        scene.addChild(saucer)
        scene.activeUFOs.append(saucer)

        scene.advanceOneStep() // Legt die 127/60-Wellenfrist an.
        // Ein zusätzlicher Fixed-Step vermeidet eine reine Double-Rundungsgrenze bei 127/60.
        advance(scene, steps: Int(round(ClassicTuning.waveDelay / GameScene.simStep)) + 1)

        XCTAssertEqual(scene.classicSession.wave, 2)
        XCTAssertEqual(scene.activeAsteroids.count, 6)
        XCTAssertTrue(scene.activeUFOs.contains { $0 === saucer },
                      "Eine aktive Untertasse darf den nächsten Satz Felsen nicht verzögern")
    }

    func testClassicCapReducesSplitChildrenAndUsesArcadeScore() {
        let (scene, view) = makeClassicScene(seed: 12)
        _ = view
        scene.clearAllEntitiesForTesting()

        let medium = makeClassicAsteroid(.medium, position: CGPoint(x: 260, y: 180))
        scene.addAsteroidForTesting(medium)
        let mediumShot = Laser(position: medium.position, angle: 0, type: .normal,
                               speed: 0, lifetime: 1)
        mediumShot.applyClassicAppearance()
        scene.addLaserForTesting(mediumShot)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 50)

        scene.clearAllEntitiesForTesting()
        scene.score = 0

        let target = makeClassicAsteroid(.large, position: CGPoint(x: 260, y: 180))
        scene.addAsteroidForTesting(target)
        for index in 1..<ClassicTuning.maximumAsteroids {
            let filler = makeClassicAsteroid(.small,
                                              position: CGPoint(x: -360 + CGFloat(index) * 3.0, y: 260))
            scene.addAsteroidForTesting(filler)
        }
        let shot = Laser(position: target.position, angle: 0, type: .normal, speed: 0, lifetime: 1)
        shot.applyClassicAppearance()
        scene.addLaserForTesting(shot)
        scene.advanceOneStep()

        XCTAssertEqual(scene.score, 20)
        XCTAssertEqual(scene.activeAsteroids.count, ClassicTuning.maximumAsteroids)
        XCTAssertEqual(scene.activeAsteroids.filter { $0.sizeClass == .medium }.count, 1,
                       "Bei nur einem freien Slot darf nur ein Split-Kind entstehen")
        XCTAssertTrue(scene.activeAsteroids.allSatisfy { $0.usesClassicAppearance })
    }

    func testClassicFiringIsEdgeTriggeredCappedAtFourAndInheritsVelocity() {
        let (scene, view) = makeClassicScene(seed: 13)
        _ = view
        scene.clearAllEntitiesForTesting()
        scene.ship.zRotation = 0
        scene.ship.velocity = CGPoint(x: 37, y: -12)
        scene.autoFire = true

        scene.simulateKeyDown(keyCode: 49)
        scene.simulateKeyDown(keyCode: 49)
        XCTAssertEqual(scene.activeLasers.count, 1, "Key-Repeat darf keinen weiteren Schuss auslösen")
        XCTAssertEqual(scene.activeLasers[0].velocity.x, 517, accuracy: 0.001)
        XCTAssertEqual(scene.activeLasers[0].velocity.y, -12, accuracy: 0.001)
        XCTAssertEqual(scene.activeLasers[0].lifetime, 0.8, accuracy: 0.0001)

        for _ in 0..<4 {
            scene.simulateKeyUp(keyCode: 49)
            scene.simulateKeyDown(keyCode: 49)
        }
        XCTAssertEqual(scene.activeLasers.count, 4)
        scene.simulateKeyUp(keyCode: 49)
        advance(scene, steps: 2)
        XCTAssertEqual(scene.activeLasers.count, 4, "Auto-Feuer bleibt in Classic wirkungslos")
        XCTAssertEqual(scene.currentReplayForTesting()?.autoFire, false)
    }

    func testClassicSettingsFixSynthAndAutoFireAndSuppressThemeWithoutChangingPreference() {
        let originalSampleSetting = SoundManager.shared.useSampledSFX
        let musicPlayer = MusicPlayer.shared
        let originalMusicSetting = musicPlayer.isEnabled
        defer {
            SoundManager.shared.useSampledSFX = originalSampleSetting
            musicPlayer.setPlaybackSuppressed(false)
            musicPlayer.setEnabled(originalMusicSetting)
        }
        musicPlayer.setEnabled(true)

        let (scene, view) = makeClassicScene(seed: 131)
        _ = view
        scene.autoFire = false
        scene.simulateTypeCharacter("n")
        scene.simulateTypeCharacter("f")
        XCTAssertEqual(SoundManager.shared.useSampledSFX, originalSampleSetting)
        XCTAssertFalse(scene.autoFire)
        XCTAssertEqual(scene.settingsSfxLabel.text, "SFX STYLE: CLASSIC SYNTH (FIXED)")
        XCTAssertEqual(scene.settingsAutoFireLabel.text, "AUTO-FIRE: DISABLED")
        XCTAssertTrue(musicPlayer.isEnabled, "Classic darf die Spielerpräferenz nicht ausschalten")
        XCTAssertTrue(musicPlayer.isPlaybackSuppressed, "Classic muss die Theme-Musik pausieren")

        scene.simulateTypeCharacter("m")
        XCTAssertFalse(musicPlayer.isEnabled)
        scene.simulateTypeCharacter("m")
        XCTAssertTrue(musicPlayer.isEnabled)
        XCTAssertTrue(musicPlayer.isPlaybackSuppressed,
                      "Aktivieren per M darf die Theme-Musik in Classic nicht starten")

        scene.transitionTo(.quitConfirmation)
        XCTAssertTrue(musicPlayer.isPlaybackSuppressed)
        scene.transitionTo(.playing)
        XCTAssertTrue(musicPlayer.isPlaybackSuppressed)
        scene.transitionTo(.gameOver)
        XCTAssertTrue(musicPlayer.isPlaybackSuppressed)
        scene.transitionTo(.startScreen)
        XCTAssertFalse(musicPlayer.isPlaybackSuppressed,
                       "Nach Classic muss eine aktivierte Theme-Musik wieder freigegeben werden")
        XCTAssertTrue(musicPlayer.isEnabled)
    }

    func testClassicShipsBonusAndClearCenterRespawnWithoutInvulnerability() {
        let (scene, view) = makeClassicScene(seed: 14)
        _ = view
        scene.clearAllEntitiesForTesting()
        XCTAssertEqual(scene.classicSession.shipsRemaining, 3)

        scene.score = 9_990
        let scoringRock = makeClassicAsteroid(.small, position: CGPoint(x: 260, y: 180))
        scene.addAsteroidForTesting(scoringRock)
        let scoringShot = Laser(position: scoringRock.position, angle: 0, type: .normal,
                                speed: 0, lifetime: 1)
        scoringShot.applyClassicAppearance()
        scene.addLaserForTesting(scoringShot)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 10_090)
        XCTAssertEqual(scene.classicSession.shipsRemaining, 4)

        let blocker = makeClassicAsteroid(.small, position: .zero, velocity: .zero)
        scene.addAsteroidForTesting(blocker)
        scene.damageShipForTesting()
        XCTAssertEqual(scene.classicSession.shipsRemaining, 3)
        XCTAssertTrue(scene.ship.isHidden)
        advance(scene, seconds: ClassicTuning.respawnDelay + 0.1)
        XCTAssertTrue(scene.ship.isHidden, "Ein belegtes Zentrum muss den Respawn weiter verzögern")

        blocker.removeFromParent()
        scene.activeAsteroids.removeAll { $0 === blocker }
        scene.advanceOneStep()
        XCTAssertFalse(scene.ship.isHidden)
        XCTAssertEqual(scene.ship.position, .zero)
        XCTAssertEqual(scene.ship.velocity, .zero)

        let immediateCollision = makeClassicAsteroid(.small, position: .zero, velocity: .zero)
        scene.addAsteroidForTesting(immediateCollision)
        let scoreBeforeCollision = scene.score
        scene.advanceOneStep()
        XCTAssertTrue(scene.ship.isHidden, "Classic hat nach dem Respawn keine Unverwundbarkeit")
        XCTAssertEqual(scene.classicSession.shipsRemaining, 2)
        XCTAssertEqual(scene.score, scoreBeforeCollision + 100,
                       "Auch das Spielerschiff selbst kann im Arcade-Regelsatz Felsenpunkte erzielen")
    }

    func testClassicSmallSaucerWaitsBeforeFirstShotAcrossSceneSizes() {
        let cases: [(size: CGSize, seed: UInt64)] = [
            (CGSize(width: 1024, height: 768), 0x51),
            (CGSize(width: 1728, height: 1084), 0x52)
        ]

        for testCase in cases {
            var rng = GameRandom(seed: testCase.seed)
            let saucer = UFO(isSmall: true, startOnLeft: true,
                              screenSize: testCase.size, using: &rng)
            let startTime = 10.0
            saucer.applyClassicBehavior(startOnLeft: true, currentTime: startTime)

            XCTAssertNil(saucer.shootClassic(target: .zero, score: 35_000,
                                              currentTime: startTime, using: &rng))
            XCTAssertNil(saucer.shootClassic(
                target: .zero,
                score: 35_000,
                currentTime: startTime + ClassicTuning.saucerHoldFireDuration - GameScene.simStep,
                using: &rng
            ))

            let firstFireTime = startTime + ClassicTuning.saucerHoldFireDuration
            XCTAssertNotNil(saucer.shootClassic(target: .zero, score: 35_000,
                                                 currentTime: firstFireTime, using: &rng))
            XCTAssertNil(saucer.shootClassic(target: .zero, score: 35_000,
                                              currentTime: firstFireTime + 0.67 - GameScene.simStep,
                                              using: &rng))
            XCTAssertNotNil(saucer.shootClassic(target: .zero, score: 35_000,
                                                 currentTime: firstFireTime + 0.67, using: &rng))
        }
    }

    func testClassicRespawnPostponesReadySaucerWithoutInvulnerability() {
        let (scene, view) = makeClassicScene(seed: 145)
        _ = view
        scene.clearAllEntitiesForTesting()
        scene.addAsteroidForTesting(makeClassicAsteroid(
            .small,
            position: CGPoint(x: 400, y: 300),
            velocity: .zero
        ))
        _ = addReadyClassicSmallSaucer(to: scene)

        scene.damageShipForTesting()
        advanceUntilShipVisible(
            scene,
            maximumSteps: Int(ceil(ClassicTuning.respawnDelay / GameScene.simStep)) + 2
        )

        XCTAssertFalse(scene.ship.isHidden)
        XCTAssertTrue(scene.activeLasers.filter { $0.type != .normal }.isEmpty,
                      "Die Untertasse darf nicht im Respawn-Schritt feuern")

        let holdFireSteps = Int((ClassicTuning.saucerHoldFireDuration / GameScene.simStep).rounded())
        advance(scene, steps: holdFireSteps - 1)
        XCTAssertTrue(scene.activeLasers.filter { $0.type != .normal }.isEmpty)
        advance(scene, steps: 1)
        XCTAssertEqual(scene.activeLasers.filter { $0.type != .normal }.count, 1)
    }

    func testClassicSuccessfulHyperspacePostponesReadySaucer() {
        let (scene, view) = makeClassicScene(seed: 146)
        _ = view
        scene.clearAllEntitiesForTesting()
        addFarClassicAsteroids(26, to: scene)
        let saucer = addReadyClassicSmallSaucer(to: scene)
        scene.rng = GameRandom(seed: hyperspaceFailureSeed())

        scene.simulateKeyDown(keyCode: 4)
        advanceUntilShipVisible(
            scene,
            maximumSteps: Int(ceil(ClassicTuning.hyperspaceDelay / GameScene.simStep)) + 2
        )

        XCTAssertFalse(scene.ship.isHidden, "26 Felsen machen diesen Quell-Risikowert sicher")
        XCTAssertTrue(scene.activeLasers.filter { $0.type != .normal }.isEmpty,
                      "Die Untertasse darf nicht im Hyperraum-Rückkehrschritt feuern")

        // Die 26 Felsen bestimmen nur das Hyperraum-Risiko. Danach entfernen wir sie,
        // damit ein erneuter Schiffstreffer nicht die Feuerzeit-Prüfung verfälscht.
        scene.activeAsteroids.forEach { $0.removeFromParent() }
        scene.activeAsteroids.removeAll()
        scene.ship.position = .zero
        saucer.position = CGPoint(x: -300, y: 220)
        saucer.velocity = .zero

        let holdFireSteps = Int((ClassicTuning.saucerHoldFireDuration / GameScene.simStep).rounded())
        advance(scene, steps: holdFireSteps - 1)
        XCTAssertTrue(scene.activeLasers.filter { $0.type != .normal }.isEmpty)
        advance(scene, steps: 1)
        XCTAssertEqual(scene.activeLasers.filter { $0.type != .normal }.count, 1)
    }

    func testClassicShipCollisionsAwardRockAndSaucerPoints() {
        let (scene, view) = makeClassicScene(seed: 141)
        _ = view
        scene.clearAllEntitiesForTesting()
        scene.score = 0

        let rock = makeClassicAsteroid(.large, position: .zero, velocity: .zero)
        scene.addAsteroidForTesting(rock)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 20)

        scene.clearAllEntitiesForTesting()
        scene.classicSession.shipPhase = .active
        scene.ship.position = .zero
        scene.ship.isHidden = false

        var saucerRNG = GameRandom(seed: 10)
        let saucer = UFO(isSmall: false, startOnLeft: true,
                          screenSize: arenaSize, using: &saucerRNG)
        saucer.applyClassicBehavior(startOnLeft: true, currentTime: 100)
        saucer.position = .zero
        saucer.velocity = .zero
        scene.addChild(saucer)
        scene.activeUFOs.append(saucer)
        scene.advanceOneStep()

        XCTAssertEqual(scene.score, 220)
        XCTAssertNil(saucer.parent)
        XCTAssertTrue(scene.ship.isHidden)
    }

    func testHyperspaceIsDeterministicAndCoversSuccessAndSourceStyleFailure() {
        let failingSeed = hyperspaceFailureSeed()

        let (failure, failureView) = makeClassicScene(seed: 15)
        _ = failureView
        failure.clearAllEntitiesForTesting()
        addFarClassicAsteroids(4, to: failure)
        failure.rng = GameRandom(seed: failingSeed)
        failure.simulateKeyDown(keyCode: 4)
        let failurePosition = failure.ship.position
        XCTAssertTrue(failure.ship.isHidden)
        XCTAssertEqual(failure.ship.velocity, .zero)
        advance(failure, seconds: ClassicTuning.hyperspaceDelay + 0.02)
        XCTAssertTrue(failure.ship.isHidden)
        XCTAssertEqual(failure.classicSession.shipsRemaining, 2)
        XCTAssertEqual(failure.lastDeathCause, .hyperspaceMalfunction)

        let (repeatFailure, repeatView) = makeClassicScene(seed: 16)
        _ = repeatView
        repeatFailure.clearAllEntitiesForTesting()
        addFarClassicAsteroids(4, to: repeatFailure)
        repeatFailure.rng = GameRandom(seed: failingSeed)
        repeatFailure.simulateKeyDown(keyCode: 4)
        XCTAssertEqual(repeatFailure.ship.position, failurePosition)

        let (success, successView) = makeClassicScene(seed: 17)
        _ = successView
        success.clearAllEntitiesForTesting()
        addFarClassicAsteroids(26, to: success)
        success.rng = GameRandom(seed: failingSeed)
        success.simulateKeyDown(keyCode: 4)
        advance(success, seconds: ClassicTuning.hyperspaceDelay + 0.02)
        XCTAssertFalse(success.ship.isHidden, "Bei 26 Felsen liegt die Quell-Schwelle stets unter der Anzahl")
        XCTAssertEqual(success.classicSession.shipsRemaining, 3)
    }

    func testClassicPauseFreezesHyperspaceDeadline() {
        let (scene, view) = makeClassicScene(seed: 171)
        _ = view
        scene.clearAllEntitiesForTesting()
        addFarClassicAsteroids(26, to: scene)

        scene.simulateKeyDown(keyCode: 4)
        advance(scene, steps: 24) // 0,2 s der 0,8-s-Frist verbrauchen.
        let elapsedBeforePause = scene.classicSession.elapsedTime

        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .quitConfirmation)
        for _ in 0..<240 { scene.advanceOneStep() } // Zwei Sekunden Pausenzeit.
        XCTAssertEqual(scene.classicSession.elapsedTime, elapsedBeforePause, accuracy: 0.000_001)

        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .playing)
        advance(scene, steps: 70)
        XCTAssertTrue(scene.ship.isHidden, "Pausenzeit darf die Hyperraumfrist nicht verbrauchen")
        advance(scene, steps: 3)
        XCTAssertFalse(scene.ship.isHidden)
        XCTAssertEqual(scene.classicSession.shipsRemaining, 3)
    }

    func testReplayRecordsClassicRawValueForcedSettingsAndHyperspaceInput() {
        let (scene, view) = makeScene()
        _ = view
        scene.autoFire = true
        scene.startNewGameForTesting(seed: 0xC1A551C, startLevel: 9, mode: .classicAsteroids)
        scene.simulateKeyDown(keyCode: 4)
        scene.simulateKeyUp(keyCode: 4)
        scene.advanceOneStep()

        let replay = scene.currentReplayForTesting()
        XCTAssertEqual(Replay.currentLogicVersion, 4)
        XCTAssertEqual(replay?.gameMode.rawValue, 2)
        XCTAssertEqual(replay?.startLevel, 1)
        XCTAssertEqual(replay?.autoFire, false)
        XCTAssertTrue(replay?.events.contains { $0.keyCode == 4 && $0.isDown } == true)
    }

    func testClassicSaucerSelectionAimScoringAndRockInteractions() {
        let (scene, view) = makeClassicScene(seed: 18)
        _ = view
        scene.clearAllEntitiesForTesting()
        let first = scene.spawnClassicSaucer()
        let second = scene.spawnClassicSaucer()
        let third = scene.spawnClassicSaucer()
        XCTAssertFalse(first.isSmall)
        XCTAssertFalse(second.isSmall)
        XCTAssertFalse(third.isSmall)
        scene.score = 30_000
        XCTAssertTrue(scene.spawnClassicSaucer().isSmall)

        var lowRNG = GameRandom(seed: 333)
        var highRNG = GameRandom(seed: 333)
        let lowAim = UFO(isSmall: true, startOnLeft: true, screenSize: arenaSize, using: &lowRNG)
        let highAim = UFO(isSmall: true, startOnLeft: true, screenSize: arenaSize, using: &highRNG)
        lowAim.position = .zero
        highAim.position = .zero
        lowAim.applyClassicBehavior(startOnLeft: true, currentTime: 0)
        highAim.applyClassicBehavior(startOnLeft: true, currentTime: 0)
        let target = CGPoint(x: 400, y: 140)
        let ideal = atan2(target.y, target.x)
        let firstFireTime = ClassicTuning.saucerHoldFireDuration
        let lowShot = lowAim.shootClassic(target: target, score: 0,
                                          currentTime: firstFireTime, using: &lowRNG)
        let highShot = highAim.shootClassic(target: target, score: 35_000,
                                            currentTime: firstFireTime, using: &highRNG)
        XCTAssertLessThanOrEqual(abs(normalizedAngle((highShot?.zRotation ?? 0) - ideal)),
                                 abs(normalizedAngle((lowShot?.zRotation ?? 0) - ideal)) + 0.0001)

        scene.clearAllEntitiesForTesting()
        scene.score = 0
        var enemyRNG = GameRandom(seed: 9)
        let enemy = UFO(isSmall: false, startOnLeft: true, screenSize: arenaSize, using: &enemyRNG)
        enemy.applyClassicBehavior(startOnLeft: true, currentTime: 0)
        enemy.position = CGPoint(x: 250, y: 180)
        scene.addChild(enemy)
        scene.activeUFOs.append(enemy)
        let playerShot = Laser(position: enemy.position, angle: 0, type: .normal, speed: 0, lifetime: 1)
        playerShot.applyClassicAppearance()
        scene.addLaserForTesting(playerShot)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 200)

        scene.clearAllEntitiesForTesting()
        scene.score = 0
        let rock = makeClassicAsteroid(.small, position: CGPoint(x: 220, y: 160))
        scene.addAsteroidForTesting(rock)
        let enemyShot = Laser(position: rock.position, angle: 0, type: .enemy, speed: 0, lifetime: 1)
        enemyShot.applyClassicAppearance()
        scene.addLaserForTesting(enemyShot)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 0)
        XCTAssertNil(rock.parent)
        XCTAssertTrue(scene.activeLasers.isEmpty)

        scene.clearAllEntitiesForTesting()
        scene.score = 0
        scene.damageShipForTesting()
        var collisionRNG = GameRandom(seed: 10)
        let collidingSaucer = UFO(isSmall: false, startOnLeft: true,
                                  screenSize: arenaSize, using: &collisionRNG)
        collidingSaucer.applyClassicBehavior(startOnLeft: true, currentTime: 0)
        collidingSaucer.position = CGPoint(x: 230, y: 170)
        scene.addChild(collidingSaucer)
        scene.activeUFOs.append(collidingSaucer)
        let collidingRock = makeClassicAsteroid(.small, position: collidingSaucer.position)
        scene.addAsteroidForTesting(collidingRock)
        scene.advanceOneStep()
        XCTAssertEqual(scene.score, 0)
        XCTAssertNil(collidingSaucer.parent)
        XCTAssertNil(collidingRock.parent)

        scene.clearAllEntitiesForTesting()
        scene.classicSession.shipPhase = .active
        scene.ship.isHidden = false
        var firingRNG = GameRandom(seed: 11)
        let firingSaucer = UFO(isSmall: false, startOnLeft: true,
                               screenSize: arenaSize, using: &firingRNG)
        firingSaucer.applyClassicBehavior(
            startOnLeft: true,
            currentTime: scene.classicSession.elapsedTime - ClassicTuning.saucerHoldFireDuration
        )
        firingSaucer.position = CGPoint(x: -300, y: 250)
        scene.addChild(firingSaucer)
        scene.activeUFOs.append(firingSaucer)
        for x in [-320.0, 320.0] {
            let existing = Laser(position: CGPoint(x: x, y: -250), angle: 0,
                                 type: .enemy, speed: 0, lifetime: 1)
            existing.applyClassicAppearance()
            scene.addLaserForTesting(existing)
        }
        scene.advanceOneStep()
        XCTAssertEqual(scene.activeLasers.filter { $0.type == .enemy }.count, 3,
                       "Classic erlaubt höchstens drei Untertassen-Schüsse gleichzeitig")
    }

    func testClassicLeaderboardIsSeparateAndSelectsItsOwnReplay() throws {
        let defaults = UserDefaults.standard
        let oldStandard = defaults.data(forKey: HighScoreStore.highScoresKey)
        let oldClassic = defaults.data(forKey: HighScoreStore.classicHighScoresKey)
        defer {
            restore(oldStandard, key: HighScoreStore.highScoresKey)
            restore(oldClassic, key: HighScoreStore.classicHighScoresKey)
        }
        defaults.removeObject(forKey: HighScoreStore.classicHighScoresKey)
        XCTAssertTrue(HighScoreStore().loadClassicHighScores().isEmpty,
                      "Eine neue Classic-Bestenliste beginnt leer")

        let standardReplay = Replay(seed: 1, startLevel: 2, gameMode: .ancientAsteroids,
                                    events: [], frameCount: 1)
        let classicReplay = Replay(seed: 2, startLevel: 1, gameMode: .classicAsteroids,
                                   events: [], frameCount: 1, autoFire: false)
        let standard = HighScore(initials: "STD", score: 123, date: Date(),
                                 replayData: try standardReplay.encoded())
        let classic = HighScore(initials: "CLS", score: 456, date: Date(),
                                replayData: try classicReplay.encoded())
        let store = HighScoreStore()
        store.save([standard])
        store.saveClassic([classic])

        let (scene, view) = makeScene()
        _ = view
        scene.loadHighScores()
        XCTAssertEqual(scene.highScores(for: .ancientAsteroids).map(\.initials), ["STD"])
        XCTAssertEqual(scene.highScores(for: .madMeteoroids).map(\.initials), ["STD"])
        XCTAssertEqual(scene.highScores(for: .classicAsteroids).map(\.initials), ["CLS"])

        scene.transitionTo(.startScreen)
        scene.simulateKeyDown(keyCode: 126)
        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.highScores.first?.initials, "CLS")
        XCTAssertEqual(scene.highScoresTitleLabel.text, "CLASSIC HIGH SCORES")
        XCTAssertTrue(scene.highScoreLineLabels.first?.text?.contains("CLS") == true)
        XCTAssertTrue(scene.watchHighScoreReplay(at: 0))
        XCTAssertEqual(scene.gameMode, .classicAsteroids)
        XCTAssertEqual(scene.currentLevel, 1)

        scene.clearHighScores()
        XCTAssertTrue(scene.highScores(for: .ancientAsteroids).isEmpty)
        XCTAssertTrue(scene.highScores(for: .classicAsteroids).isEmpty)
        XCTAssertTrue(try JSONDecoder().decode([HighScore].self,
                                               from: defaults.data(forKey: HighScoreStore.highScoresKey)!).isEmpty)
        XCTAssertTrue(try JSONDecoder().decode([HighScore].self,
                                               from: defaults.data(forKey: HighScoreStore.classicHighScoresKey)!).isEmpty)
    }

    func testClassicGameplayShapesAreWhiteUnfilledDistinctAndHDRMarked() {
        let (scene, view) = makeClassicScene(seed: 19)
        _ = view
        XCTAssertTrue(scene.ship.usesClassicAppearance)
        XCTAssertTrue(isOpaqueWhite(scene.ship.strokeColor))
        XCTAssertEqual(scene.ship.fillColor.alphaComponent, 0)
        XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(scene.ship))
        scene.simulateKeyDown(keyCode: 126)
        scene.advanceOneStep()
        let visibleShipDetails = scene.ship.children.compactMap { $0 as? SKShapeNode }
            .filter { !$0.isHidden }
        XCTAssertFalse(visibleShipDetails.isEmpty)
        XCTAssertTrue(visibleShipDetails.allSatisfy {
            isOpaqueWhite($0.strokeColor) && VectorGlowRenderer.isStrokeMarked($0)
        })
        scene.simulateKeyUp(keyCode: 126)

        for asteroid in scene.activeAsteroids {
            XCTAssertTrue(isOpaqueWhite(asteroid.strokeColor))
            XCTAssertEqual(asteroid.fillColor.alphaComponent, 0)
            XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(asteroid))
            XCTAssertTrue(asteroid.children.compactMap { $0 as? SKShapeNode }.allSatisfy(\.isHidden))
        }

        var vertexFamilies = Set<String>()
        for family in 0..<4 {
            let asteroid = Asteroid(sizeClass: .large)
            asteroid.applyClassicAppearance(family: family)
            vertexFamilies.insert(asteroid.vertices.map { "\($0.x.rounded()),\($0.y.rounded())" }.joined(separator: ";"))
        }
        XCTAssertEqual(vertexFamilies.count, 4)

        scene.clearAllEntitiesForTesting()
        scene.simulateKeyDown(keyCode: 49)
        XCTAssertTrue(scene.activeLasers.first.map { isOpaqueWhite($0.strokeColor) } == true)
        XCTAssertTrue(scene.activeLasers.allSatisfy(VectorGlowRenderer.isStrokeMarked))

        let saucer = scene.spawnClassicSaucer()
        XCTAssertTrue(isOpaqueWhite(saucer.strokeColor))
        XCTAssertEqual(saucer.fillColor.alphaComponent, 0)
        XCTAssertTrue(VectorGlowRenderer.isStrokeMarked(saucer))
        var shotRNG = GameRandom(seed: 44)
        let enemyShot = saucer.shootClassic(target: scene.ship.position, score: 0,
                                            currentTime: scene.classicSession.elapsedTime
                                                + ClassicTuning.saucerHoldFireDuration,
                                            using: &shotRNG)
        XCTAssertTrue(enemyShot.map { isOpaqueWhite($0.strokeColor) } == true)
        XCTAssertTrue(enemyShot.map(VectorGlowRenderer.isStrokeMarked) == true)

        let rock = makeClassicAsteroid(.small, position: scene.activeLasers[0].position)
        scene.addAsteroidForTesting(rock)
        scene.advanceOneStep()
        let debris = scene.children.compactMap { $0 as? SKShapeNode }
            .filter { $0.name == "classicVectorDebris" }
        XCTAssertFalse(debris.isEmpty)
        XCTAssertTrue(debris.allSatisfy { isOpaqueWhite($0.strokeColor) && $0.fillColor.alphaComponent == 0 })
        XCTAssertTrue(debris.allSatisfy(VectorGlowRenderer.isStrokeMarked))

        // Hintergrund/HUD behalten ihre vorhandene Farbgebung.
        XCTAssertEqual(scene.scoreLabel.fontColor, .cyan)
        XCTAssertEqual(scene.hiScoreLabel.fontColor,
                       SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0))
        XCTAssertTrue(scene.children.compactMap { $0 as? SKSpriteNode }
            .filter { $0.zPosition == -10 }
            .contains { $0.color != SKColor.white })
    }

    // MARK: - Helpers

    private func makeScene() -> (GameScene, SKView) {
        let scene = GameScene(size: arenaSize)
        let view = SKView(frame: CGRect(origin: .zero, size: arenaSize))
        view.presentScene(scene)
        scene.externalStepDriving = true
        return (scene, view)
    }

    private func makeClassicScene(seed: UInt64) -> (GameScene, SKView) {
        let (scene, view) = makeScene()
        scene.startNewGameForTesting(seed: seed, startLevel: 9, mode: .classicAsteroids)
        return (scene, view)
    }

    private func makeClassicAsteroid(_ size: Asteroid.AsteroidSize, position: CGPoint,
                                     velocity: CGPoint = .zero) -> Asteroid {
        let asteroid = Asteroid(sizeClass: size)
        asteroid.applyClassicAppearance(family: 0)
        asteroid.position = position
        asteroid.velocity = velocity
        asteroid.hasEnteredScreen = true
        return asteroid
    }

    private func addFarClassicAsteroids(_ count: Int, to scene: GameScene) {
        for index in 0..<count {
            let asteroid = makeClassicAsteroid(.small,
                                                position: CGPoint(x: 5_000 + CGFloat(index) * 20, y: 5_000))
            asteroid.hasEnteredScreen = false
            scene.addAsteroidForTesting(asteroid)
        }
    }

    @discardableResult
    private func addReadyClassicSmallSaucer(to scene: GameScene) -> UFO {
        var saucerRNG = GameRandom(seed: 0x5A0CE2)
        let saucer = UFO(isSmall: true, startOnLeft: true,
                          screenSize: scene.size, using: &saucerRNG)
        saucer.applyClassicBehavior(
            startOnLeft: true,
            currentTime: scene.classicSession.elapsedTime - ClassicTuning.saucerHoldFireDuration
        )
        saucer.classicNextCourseChange = .greatestFiniteMagnitude
        saucer.position = CGPoint(x: -300, y: 220)
        saucer.velocity = .zero
        scene.addChild(saucer)
        scene.activeUFOs.append(saucer)
        return saucer
    }

    private func advance(_ scene: GameScene, seconds: TimeInterval) {
        advance(scene, steps: Int(ceil(seconds / GameScene.simStep)))
    }

    private func advanceUntilShipVisible(_ scene: GameScene, maximumSteps: Int) {
        for _ in 0..<maximumSteps where scene.ship.isHidden {
            scene.advanceOneStep()
        }
    }

    private func advance(_ scene: GameScene, steps: Int) {
        for _ in 0..<steps where scene.gameState == .playing { scene.advanceOneStep() }
    }

    private func hyperspaceFailureSeed() -> UInt64 {
        for candidate in UInt64(0)..<10_000 {
            var generator = GameRandom(seed: candidate)
            _ = generator.next()
            var raw = 0
            for _ in 0..<5 { raw = Int(generator.next() & 0x1F) }
            if raw >= 24 { return candidate }
        }
        XCTFail("Kein Hyperraum-Fehlfunktions-Seed im Suchbereich")
        return 0
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }

    private func restore(_ data: Data?, key: String) {
        if let data { UserDefaults.standard.set(data, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func isOpaqueWhite(_ color: SKColor) -> Bool {
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let converted = color.cgColor.converted(to: rgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 4 else { return false }
        return components[0] > 0.999 && components[1] > 0.999 && components[2] > 0.999
            && components[3] > 0.999
    }
}
