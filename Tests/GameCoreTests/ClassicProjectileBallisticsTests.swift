import SpriteKit
import XCTest
@testable import GameCore

@MainActor
final class ClassicProjectileBallisticsTests: GameCoreTestCase {
    private let canonicalArena = CGSize(width: 1024.0, height: 768.0)

    func testAngleQuantizationRecreatesCardinalDiagonalAndOppositeVectors() {
        let cases: [(angle: CGFloat, byte: UInt8, vector: ClassicRawVector)] = [
            (0.0, 0x00, ClassicRawVector(x: 63, y: 0)),
            (.pi / 4.0, 0x20, ClassicRawVector(x: 45, y: 45)),
            (.pi / 2.0, 0x40, ClassicRawVector(x: 0, y: 63)),
            (.pi, 0x80, ClassicRawVector(x: -64, y: 0)),
            (3.0 * .pi / 2.0, 0xC0, ClassicRawVector(x: 0, y: -64)),
            (-.pi / 2.0, 0xC0, ClassicRawVector(x: 0, y: -64))
        ]

        for testCase in cases {
            let byte = ClassicProjectileCalibrator.angleByte(for: testCase.angle)
            XCTAssertEqual(byte, testCase.byte)
            XCTAssertEqual(ClassicProjectileCalibrator.baseVelocity(for: byte), testCase.vector)
        }
    }

    func testInheritedVelocityClampSpawnOffsetAndCancellation() {
        XCTAssertEqual(
            ClassicProjectileCalibrator.inheritedVelocity(
                for: CGPoint(x: 120.0, y: -120.0)
            ),
            ClassicRawVector(x: 16, y: -16)
        )

        let stationary = calibration(angle: 0.0, shooterVelocity: .zero)
        let aligned = calibration(angle: 0.0, shooterVelocity: CGPoint(x: 120.0, y: 0.0))
        let opposed = calibration(angle: 0.0, shooterVelocity: CGPoint(x: -120.0, y: 0.0))
        let maximum = calibration(angle: 0.0, shooterVelocity: CGPoint(x: 480.0, y: 0.0))
        let negativeMaximum = calibration(angle: .pi,
                                          shooterVelocity: CGPoint(x: -480.0, y: 0.0))
        let verticalMaximum = calibration(angle: .pi / 2.0,
                                          shooterVelocity: CGPoint(x: 0.0, y: 480.0))
        let negativeVerticalMaximum = calibration(angle: 3.0 * .pi / 2.0,
                                                  shooterVelocity: CGPoint(x: 0.0, y: -480.0))
        let cancelled = calibration(angle: 0.0,
                                    shooterVelocity: CGPoint(x: -472.5, y: 0.0))
        let smoothCancellation = calibration(angle: 0.0,
                                             shooterVelocity: CGPoint(x: -480.0, y: 0.0))

        XCTAssertEqual(stationary.clampedVelocity, ClassicRawVector(x: 63, y: 0))
        XCTAssertEqual(aligned.clampedVelocity, ClassicRawVector(x: 79, y: 0))
        XCTAssertEqual(opposed.clampedVelocity, ClassicRawVector(x: 47, y: 0))
        XCTAssertEqual(maximum.clampedVelocity, ClassicRawVector(x: 111, y: 0))
        XCTAssertEqual(negativeMaximum.clampedVelocity, ClassicRawVector(x: -111, y: 0))
        XCTAssertEqual(verticalMaximum.clampedVelocity, ClassicRawVector(x: 0, y: 111))
        XCTAssertEqual(negativeVerticalMaximum.clampedVelocity, ClassicRawVector(x: 0, y: -111))
        XCTAssertEqual(cancelled.clampedVelocity, ClassicRawVector(x: 0, y: 0))
        XCTAssertEqual(cancelled.velocity, .zero)
        XCTAssertEqual(smoothCancellation.clampedVelocity, ClassicRawVector(x: -1, y: 0))
        XCTAssertLessThan(smoothCancellation.velocity.x, 0.0,
                          "Bei glatter Vollaufhebung muss der diskrete Atari-Vektor übernehmen")

        XCTAssertEqual(stationary.spawnOffsetRaw, ClassicRawVector(x: 94, y: 0))
        XCTAssertEqual(stationary.canonicalSpawnOffsetDistance, 11.75, accuracy: 0.000_001)
        let opposite = calibration(angle: .pi, shooterVelocity: .zero)
        XCTAssertEqual(opposite.spawnOffsetRaw, ClassicRawVector(x: -96, y: 0))
        XCTAssertEqual(opposite.canonicalSpawnOffsetDistance, 12.0, accuracy: 0.000_001)
        let diagonal = calibration(angle: .pi / 4.0, shooterVelocity: .zero)
        XCTAssertEqual(diagonal.spawnOffsetRaw, ClassicRawVector(x: 67, y: 67))
    }

    func testAllLaunchPhasesAndSaucerUseExactFrameCountsDurationsAndRanges() {
        let expectedFrames = [69, 72, 71, 70]
        let expectedTravel = [543.375, 567.0, 559.125, 551.25]
        let expectedTotalRange = [555.125, 578.75, 570.875, 563.0]

        for phase in 0..<4 {
            let frames = ClassicProjectileCalibrator.playerMovementFrames(forLaunchPhase: phase)
            let result = calibration(angle: 0.0, shooterVelocity: .zero,
                                     movementFrames: frames)
            XCTAssertEqual(frames, expectedFrames[phase])
            XCTAssertEqual(result.lifetime, Double(expectedFrames[phase]) / 62.5,
                           accuracy: 0.000_000_001)
            XCTAssertEqual(result.canonicalTravelDistance, expectedTravel[phase],
                           accuracy: 0.000_001)
            XCTAssertEqual(result.canonicalSpawnOffsetDistance
                + result.canonicalTravelDistance, expectedTotalRange[phase], accuracy: 0.000_001)
        }

        let saucer = calibration(
            angle: 0.0,
            shooterVelocity: .zero,
            movementFrames: ClassicProjectileCalibrator.saucerMovementFrames
        )
        XCTAssertEqual(saucer.movementFrames, 69)
        XCTAssertEqual(saucer.lifetime, 69.0 / 62.5, accuracy: 0.000_000_001)
        XCTAssertEqual(saucer.canonicalTravelDistance, 543.375, accuracy: 0.000_001)
    }

    func testRationalArcadeClockIsDeterministicAndDrivesPlayerLifetime() throws {
        var session = ClassicSession()
        XCTAssertEqual(session.nextArcadeFramePhase, 0)

        session.advanceArcadeClock()
        XCTAssertEqual(session.nextArcadeFrame, 0)
        XCTAssertEqual(session.arcadeClockAccumulator, 125)
        session.advanceArcadeClock()
        XCTAssertEqual(session.nextArcadeFrame, 1)
        XCTAssertEqual(session.arcadeClockAccumulator, 10)
        for _ in 2..<240 { session.advanceArcadeClock() }
        XCTAssertEqual(session.nextArcadeFrame, 125)
        XCTAssertEqual(session.arcadeClockAccumulator, 0)

        session.reset()
        XCTAssertEqual(session.nextArcadeFrame, 0)
        XCTAssertEqual(session.arcadeClockAccumulator, 0)

        for phase in 0..<4 {
            let (scene, view) = makeClassicScene(size: canonicalArena, seed: UInt64(phase + 1))
            _ = view
            scene.clearAllEntitiesForTesting()
            scene.classicSession.nextArcadeFrame = UInt8(phase)
            scene.ship.position = .zero
            scene.ship.velocity = .zero
            scene.ship.zRotation = 0.0

            scene.fireClassicLaser()
            let shot = try XCTUnwrap(scene.activeLasers.last)
            let frames = ClassicProjectileCalibrator.playerMovementFrames(forLaunchPhase: phase)
            XCTAssertEqual(shot.lifetime, Double(frames) / 62.5, accuracy: 0.000_000_001)
        }
    }

    func testDirectionalArenaScalingPreservesNormalizedReach() {
        let arenas = [
            canonicalArena,
            CGSize(width: 2048.0, height: 1536.0),
            CGSize(width: 1728.0, height: 1084.0)
        ]
        let angles: [CGFloat] = [0.0, .pi / 2.0, .pi / 4.0]

        for arena in arenas {
            for angle in angles {
                let result = ClassicProjectileCalibrator.calibrate(
                    angle: angle,
                    shooterVelocity: .zero,
                    arenaSize: arena,
                    movementFrames: 69
                )
                let normalizedTravel = normalizedDistance(
                    CGPoint(x: result.velocity.x * CGFloat(result.lifetime),
                            y: result.velocity.y * CGFloat(result.lifetime)),
                    in: arena
                )
                XCTAssertEqual(normalizedTravel, result.canonicalTravelDistance,
                               accuracy: 0.000_001)
                XCTAssertEqual(normalizedDistance(result.spawnOffset, in: arena),
                               result.canonicalSpawnOffsetDistance, accuracy: 0.000_001)
            }
        }

        let motion = CGPoint(x: 120.0, y: -45.0)
        let angle: CGFloat = 0.37
        let result = ClassicProjectileCalibrator.calibrate(
            angle: angle,
            shooterVelocity: motion,
            arenaSize: CGSize(width: 1728.0, height: 1084.0),
            movementFrames: 69
        )
        let smooth = CGPoint(x: 480.0 * cos(angle) + motion.x,
                             y: 480.0 * sin(angle) + motion.y)
        XCTAssertEqual(result.velocity.x * smooth.y - result.velocity.y * smooth.x,
                       0.0, accuracy: 0.000_001,
                       "Die Korrektur darf Exploids' glatte Flugrichtung nicht quantisieren")
        XCTAssertGreaterThan(result.velocity.x * smooth.x + result.velocity.y * smooth.y, 0.0)
    }

    func testCalibratedLaserStopsAtExactEndpointThenFreezesForOneArcadeFrame() {
        let result = calibration(angle: 0.0, shooterVelocity: .zero)
        let laser = Laser(position: .zero, angle: 0.0, type: .normal,
                          speed: 0.0, lifetime: result.lifetime)
        laser.applyClassicBallistics(velocity: result.velocity)
        laser.applyClassicAppearance()

        XCTAssertFalse(laser.update(deltaTime: result.lifetime - GameScene.simStep / 2.0))
        XCTAssertFalse(laser.isClassicSpent)
        XCTAssertFalse(laser.update(deltaTime: GameScene.simStep))
        XCTAssertTrue(laser.isClassicSpent)
        XCTAssertEqual(laser.position.x, result.canonicalTravelDistance, accuracy: 0.000_001)
        XCTAssertEqual(laser.position.y, 0.0, accuracy: 0.000_001)

        let endpoint = laser.position
        let remainingDisplayTime = ClassicProjectileCalibrator.displayFrameDuration
            - GameScene.simStep / 2.0
        XCTAssertFalse(laser.update(deltaTime: remainingDisplayTime - 0.000_001))
        XCTAssertEqual(laser.position, endpoint)
        XCTAssertTrue(laser.update(deltaTime: 0.000_002))
        XCTAssertEqual(laser.position, endpoint)

        let appearanceOnly = Laser(position: .zero, angle: 0.0, type: .normal,
                                   speed: 100.0, lifetime: 0.5)
        appearanceOnly.applyClassicAppearance()
        XCTAssertTrue(appearanceOnly.update(deltaTime: 0.5))
        XCTAssertFalse(appearanceOnly.isClassicSpent,
                       "Weißes Classic-Aussehen allein darf das normale Testverhalten nicht ändern")
    }

    func testCalibratedShotKeepsExactRangeAcrossWrap() {
        let result = calibration(angle: 0.0, shooterVelocity: .zero)
        let laser = Laser(position: CGPoint(x: 510.0, y: 0.0), angle: 0.0,
                          type: .normal, speed: 0.0, lifetime: result.lifetime)
        laser.applyClassicBallistics(velocity: result.velocity)

        while !laser.isClassicSpent {
            XCTAssertFalse(laser.update(deltaTime: GameScene.simStep))
            laser.wrapAround(screenSize: canonicalArena)
        }

        XCTAssertEqual(laser.position.x, 510.0 + result.canonicalTravelDistance - 1024.0,
                       accuracy: 0.000_001)
        XCTAssertEqual(laser.position.y, 0.0, accuracy: 0.000_001)
    }

    func testSpentShotsAreNonDamagingSlotFreeAndIgnoredForRespawn() throws {
        let (scene, view) = makeClassicScene(size: canonicalArena, seed: 0x5A07)
        _ = view
        scene.clearAllEntitiesForTesting()

        let rock = Asteroid(sizeClass: .small)
        rock.applyClassicAppearance(family: 0)
        rock.position = CGPoint(x: 250.0, y: 180.0)
        rock.velocity = .zero
        rock.hasEnteredScreen = true
        scene.addAsteroidForTesting(rock)
        let spentPlayerShot = makeSpentLaser(type: .normal, position: rock.position)
        scene.addLaserForTesting(spentPlayerShot)

        scene.advanceOneStep()
        XCTAssertTrue(scene.activeAsteroids.contains { $0 === rock })
        XCTAssertTrue(scene.activeLasers.contains { $0 === spentPlayerShot })

        scene.clearAllEntitiesForTesting()
        scene.classicSession.shipPhase = .active
        scene.ship.position = .zero
        scene.ship.isHidden = false
        let spentEnemyShot = makeSpentLaser(type: .enemy, position: scene.ship.position)
        scene.addLaserForTesting(spentEnemyShot)
        scene.advanceOneStep()
        XCTAssertFalse(scene.ship.isHidden, "Ein sichtbarer Endpunkt darf das Schiff nicht mehr treffen")

        scene.clearAllEntitiesForTesting()
        for index in 0..<4 {
            scene.addLaserForTesting(makeSpentLaser(
                type: .normal,
                position: CGPoint(x: CGFloat(index) * 20.0, y: 200.0)
            ))
        }
        scene.fireClassicLaser()
        XCTAssertEqual(scene.activeLasers.filter { $0.type == .normal && !$0.isClassicSpent }.count, 1)
        XCTAssertEqual(scene.activeLasers.filter { $0.type == .normal }.count, 5)

        scene.clearAllEntitiesForTesting()
        for index in 0..<2 {
            scene.addLaserForTesting(makeSpentLaser(
                type: .enemy,
                position: CGPoint(x: CGFloat(index) * 20.0, y: -200.0)
            ))
        }
        var saucerRNG = GameRandom(seed: 0x5A0CE2)
        let saucer = UFO(isSmall: false, startOnLeft: true,
                          screenSize: canonicalArena, using: &saucerRNG)
        saucer.applyClassicBehavior(
            startOnLeft: true,
            currentTime: scene.classicSession.elapsedTime - ClassicTuning.saucerHoldFireDuration
        )
        saucer.position = CGPoint(x: -300.0, y: 220.0)
        saucer.velocity = .zero
        scene.addChild(saucer)
        scene.activeUFOs.append(saucer)
        scene.advanceOneStep()
        XCTAssertEqual(scene.activeLasers.filter { $0.type == .enemy && !$0.isClassicSpent }.count, 1)
        XCTAssertEqual(scene.activeLasers.filter { $0.type == .enemy }.count, 3)

        scene.clearAllEntitiesForTesting()
        scene.classicSession.shipPhase = .destroyed(
            reappearAt: scene.classicSession.elapsedTime
        )
        scene.classicSession.shipsRemaining = 3
        scene.ship.isHidden = true
        scene.addLaserForTesting(makeSpentLaser(type: .enemy, position: .zero))
        scene.advanceOneStep()
        XCTAssertFalse(scene.ship.isHidden,
                       "Ein verbrauchter Gegnerpunkt darf die freie Bildschirmmitte nicht blockieren")
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    private func calibration(angle: CGFloat, shooterVelocity: CGPoint,
                             movementFrames: Int = 69) -> ClassicProjectileCalibration {
        ClassicProjectileCalibrator.calibrate(
            angle: angle,
            shooterVelocity: shooterVelocity,
            arenaSize: canonicalArena,
            movementFrames: movementFrames
        )
    }

    private func normalizedDistance(_ vector: CGPoint, in arena: CGSize) -> CGFloat {
        let scaleX = arena.width / canonicalArena.width
        let scaleY = arena.height / canonicalArena.height
        return hypot(vector.x / scaleX, vector.y / scaleY)
    }

    private func makeClassicScene(size: CGSize, seed: UInt64) -> (GameScene, SKView) {
        let scene = GameScene(size: size)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        scene.externalStepDriving = true
        scene.startNewGameForTesting(seed: seed, startLevel: 1, mode: .classicAsteroids)
        return (scene, view)
    }

    private func makeSpentLaser(type: LaserType, position: CGPoint) -> Laser {
        let result = calibration(angle: 0.0, shooterVelocity: .zero)
        let laser = Laser(position: .zero, angle: 0.0, type: type,
                          speed: 0.0, lifetime: result.lifetime)
        laser.applyClassicBallistics(velocity: result.velocity)
        laser.applyClassicAppearance()
        XCTAssertFalse(laser.update(deltaTime: result.lifetime))
        XCTAssertTrue(laser.isClassicSpent)
        laser.position = position
        return laser
    }
}
