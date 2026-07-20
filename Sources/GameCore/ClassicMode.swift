import SpriteKit

/// Gemeinsame logische Geometrie des Classic-Modus. Die Maße sind die Mittellinien-Hüllkurven
/// der Rev.-4-Vektorobjekte; Strichstärke und rein optische Effekte zählen bewusst nicht dazu.
/// Ancient/Mad verwenden weiterhin ihre eigenen, bisherigen Größen.
enum ClassicGeometry {
    static let logicalArenaSize = CGSize(width: 1024.0, height: 768.0)
    static let shipBodySize = CGSize(width: 24.0, height: 16.0)
    static let shipBodyScale: CGFloat = 0.8
    static let largeSaucerSize = CGSize(width: 40.0, height: 24.0)
    static let smallSaucerSize = CGSize(width: 20.0, height: 12.0)

    static func asteroidDiameter(for sizeClass: Asteroid.AsteroidSize) -> CGFloat {
        switch sizeClass {
        case .large: return 64.0
        case .medium: return 32.0
        case .small: return 16.0
        }
    }
}

/// Alle Arcade-Werte liegen in einem eigenen Profil. Ancient/Mad greifen auf keinen dieser Werte zu.
enum ClassicTuning {
    static let maximumAsteroids = 26
    static let waveDelay: TimeInterval = 127.0 / 60.0
    static let respawnDelay: TimeInterval = 129.0 / 60.0
    static let hyperspaceDelay: TimeInterval = 48.0 / 60.0
    /// Bleibt nur als glatter Exploids-Richtungsvektor erhalten; der Betrag des fertigen Schusses
    /// kommt aus dem diskreten Atari-Vektorprofil.
    static let playerShotSpeed: CGFloat = 480.0
    /// Optionale Exploids-Spielhilfe, kein Wert aus dem Arcade-ROM: Beim Halten von FIRE wird alle
    /// 0,15 Sekunden genau ein neuer Schuss versucht. Das Vier-Slot-Limit bleibt unverändert.
    static let rapidFireInterval: TimeInterval = 0.15
    static let safeRespawnRadius: CGFloat = 105.0
    /// Das Original nutzt für beide Untertassengrößen XINC = +/-$10. Mit drei
    /// Nachkommabits sind das 2 von 1024 Spielfeldeinheiten pro 60-Hz-Frame.
    static let saucerSpeed: CGFloat = 120.0
    /// Der globale 60-Hz-Zähler wechselt den Vertikalkurs bei $00/$80.
    static let saucerCourseInterval: TimeInterval = 128.0 / 60.0
    /// Atari Rev. 2 setzte den ersten Untertassen-Schusszähler auf 18 und wertete ihn nur jeden
    /// vierten 60-Hz-Frame aus: 18 * 4 / 60 = 1,2 Sekunden Reaktionszeit.
    static let saucerHoldFireDuration: TimeInterval = 18.0 * 4.0 / 60.0
    /// Nachfolgende Schüsse nutzen denselben Vier-Frame-Takt mit einem Zählerstand von zehn.
    static let saucerFireInterval: TimeInterval = 10.0 * 4.0 / 60.0
    /// Die Objektslots 2 und 3 sind für Untertassenschüsse reserviert; 4...7 gehören dem Spieler.
    static let maximumSaucerShots = 2
    /// Beim Zielen zieht der Arcadecode 32 Bewegungsframes vom Abstand ab, bevor er den Winkel bildet.
    static let saucerAimCompensationDuration: TimeInterval = 32.0 / 60.0
    static let angleStep: CGFloat = 2.0 * .pi / 256.0
    /// Ataris ENEMY-Routine bearbeitet die Eintrittszähler nur in jedem vierten 60-Hz-Frame,
    /// entsprechend acht Schritten der festen 120-Hz-Simulation.
    static let saucerTimerSimulationSteps = 8
    /// Eine neue Welle setzt EDELAY auf $7F.
    static let saucerWaveDelayTicks = 0x7F
    /// SEDLAY beginnt bei $92 und sinkt nach jedem Eintritt um $06 bis zur Untergrenze $20.
    static let saucerInitialReloadTicks = 0x92
    static let saucerMinimumReloadTicks = 0x20
    static let saucerReloadStepTicks = 0x06
    /// Falls die Felsbedingung einen Eintritt blockiert, prüft das Original nach 18 Ticks erneut.
    static let saucerRetryTicks = 18
    /// Jeder Felstreffer setzt RTIMER auf $50; solange er läuft, darf die Untertasse erst bei
    /// hinreichend wenigen verbliebenen Felsen erscheinen.
    static let saucerAsteroidHitTicks = 0x50
    /// 62,5 Arcade-Bilder pro Sekunde als exakter rationaler Anteil der 120-Hz-Simulation.
    static let arcadeClockNumerator = 125
    static let arcadeClockDenominator = 240

    static func largeAsteroidCount(for wave: Int) -> Int {
        switch wave {
        case 1: return 4
        case 2: return 6
        case 3: return 8
        case 4: return 10
        default: return 11
        }
    }

    static func saucerRockThreshold(for wave: Int) -> Int {
        min(10, 5 + max(1, wave))
    }
}

/// Kleiner, vom Level-/Power-up-System getrennter Zustand einer Classic-Partie.
struct ClassicSession {
    enum ShipPhase {
        case active
        case destroyed(reappearAt: TimeInterval)
        case hyperspace(reappearAt: TimeInterval, position: CGPoint, destroysShip: Bool)
    }

    var wave = 1
    var shipsRemaining = 3
    var nextBonusScore = 10_000
    var shipPhase: ShipPhase = .active
    /// Eigene Simulationszeit des Classic-Modus. Sie läuft ausschließlich während `.playing`,
    /// damit Quit-Bestätigung/Pause keine Respawn-, Hyperraum- oder Wellenfristen verbraucht.
    var elapsedTime: TimeInterval = 0.0
    var waveStartDeadline: TimeInterval?
    var saucerTimerTicks = ClassicTuning.saucerWaveDelayTicks
    var saucerTimerReloadTicks = ClassicTuning.saucerInitialReloadTicks
    var saucerAsteroidHitTimerTicks = 0
    var saucerTimerStepPhase = 0
    var saucerAppearances = 0
    /// Nummer des nächsten Atari-Bildes, auf dem ein zwischen Simulationsschritten empfangener
    /// Spielerschuss verarbeitet würde. Der rationale Rest verhindert jegliche Wandzeit-Abhängigkeit.
    var nextArcadeFrame: UInt8 = 0
    var arcadeClockAccumulator = 0
    var nextHeartbeatTime: TimeInterval = 0.0
    var heartbeatHigh = false
    var waveHits = 0
    var possibleWaveHits = 28
    /// Nächster fester Simulationszeitpunkt für einen gehaltenen Rapid-Fire-Impuls. `nil` bedeutet,
    /// dass FIRE nicht gehalten wird oder die optionale Spielhilfe ausgeschaltet ist.
    var nextRapidFireTime: TimeInterval?

    mutating func reset() {
        self = ClassicSession()
    }

    var isShipActive: Bool {
        if case .active = shipPhase { return true }
        return false
    }

    var nextArcadeFramePhase: Int {
        Int(nextArcadeFrame & 3)
    }

    mutating func advanceArcadeClock() {
        arcadeClockAccumulator += ClassicTuning.arcadeClockNumerator
        while arcadeClockAccumulator >= ClassicTuning.arcadeClockDenominator {
            arcadeClockAccumulator -= ClassicTuning.arcadeClockDenominator
            nextArcadeFrame &+= 1
        }
    }
}

extension GameScene {
    /// Welcher Modus bestimmt gerade die Einstellungen? Im Spiel zählt der laufende, in Menüs die
    /// Auswahl. Classic meldet dadurch zuverlässig sein festes Synth-Profil und Rapid-Fire-Menü.
    var isClassicInterfaceActive: Bool {
        switch gameState {
        case .playing, .quitConfirmation, .nameEntry, .gameOver:
            return gameMode == .classicAsteroids
        case .startScreen, .glossary, .highScores, .settings:
            return selectedMode == .classicAsteroids
        }
    }

    /// Setzt ausschließlich die Classic-Sitzung zurück und startet Welle 1.
    func initializeClassicSession() {
        classicSession.reset()
        currentLevel = 1
        levelLabel.text = "WAVE: 1"
        timerLabel.isHidden = true
        activeGravityWells.removeAll()
        activePowerUps.removeAll()
        activeHead = nil
        activeCats.removeAll()
        spawnClassicWave()
        updateLivesLabel()
    }

    /// Vollständiger Classic-Simulationsschritt. Er wird aus `stepSimulation` vor dem historischen
    /// Ancient/Mad-Rumpf aufgerufen und hält Wellenregeln, Physik und Kollisionen lokal.
    func updateClassicMode(deltaTime: TimeInterval) {
        classicSession.elapsedTime += deltaTime
        classicSession.advanceArcadeClock()
        let currentTime = classicSession.elapsedTime
        playTime += deltaTime
        updateClassicShipPhase(currentTime: currentTime)
        guard gameState == .playing else { return }

        let shipActive = classicSession.isShipActive && !ship.isHidden
        let isThrusting = shipActive && (activeKeys.contains(13) || activeKeys.contains(126))
        var rotationInput: CGFloat = 0.0
        if shipActive {
            if activeKeys.contains(0) || activeKeys.contains(123) { rotationInput += 1.0 }
            if activeKeys.contains(2) || activeKeys.contains(124) { rotationInput -= 1.0 }
            ship.update(deltaTime: deltaTime, isThrusting: isThrusting, rotationInput: rotationInput)
            ship.wrapAround(screenSize: size)
        }

        // Rapid Fire ist absichtlich ein einzelner Impuls pro Frist statt einer Aufhol-Schleife:
        // Auch nach mehreren nachgeholten Fixed Steps entstehen weder Bursts noch Wandzeitbezug.
        // `fireClassicLaser` hält weiterhin Ataris vier Spielerschuss-Slots ein.
        if classicRapidFire, isSpaceHeld,
           let nextRapidFireTime = classicSession.nextRapidFireTime,
           currentTime + GameScene.simStep / 2.0 >= nextRapidFireTime {
            if shipActive {
                fireClassicLaser()
            }
            classicSession.nextRapidFireTime = nextRapidFireTime + ClassicTuning.rapidFireInterval
        }
        SoundManager.shared.setThrustActive(isThrusting)

        for asteroid in activeAsteroids {
            asteroid.update(deltaTime: deltaTime)
            asteroid.wrapAround(screenSize: size)
        }

        var liveLasers: [Laser] = []
        liveLasers.reserveCapacity(activeLasers.count)
        for laser in activeLasers {
            if laser.update(deltaTime: deltaTime) {
                laser.removeFromParent()
            } else {
                laser.wrapAround(screenSize: size)
                liveLasers.append(laser)
            }
        }
        activeLasers = liveLasers

        updateClassicSaucers(deltaTime: deltaTime, currentTime: currentTime)
        resolveClassicCollisions()
        updateClassicWave(currentTime: currentTime)
        updateClassicSaucerSpawning()
        updateClassicHeartbeat(currentTime: currentTime)
    }

    // MARK: - Schiff, Schüsse und Hyperraum

    func fireClassicLaser() {
        guard gameMode == .classicAsteroids, gameState == .playing,
              classicSession.isShipActive, !ship.isHidden else { return }
        let playerShots = activeLasers.reduce(into: 0) { count, laser in
            if laser.type == .normal, !laser.isClassicSpent { count += 1 }
        }
        guard playerShots < 4 else { return }

        let angle = ship.zRotation
        let movementFrames = ClassicProjectileCalibrator.playerMovementFrames(
            forLaunchPhase: classicSession.nextArcadeFramePhase
        )
        let calibration = ClassicProjectileCalibrator.calibrate(
            angle: angle,
            shooterVelocity: ship.velocity,
            arenaSize: size,
            movementFrames: movementFrames
        )
        let spawn = CGPoint(x: ship.position.x + calibration.spawnOffset.x,
                            y: ship.position.y + calibration.spawnOffset.y)
        let laser = Laser(position: spawn, angle: angle, type: .normal,
                          speed: 0.0, lifetime: calibration.lifetime)
        laser.applyClassicBallistics(velocity: calibration.velocity)
        laser.applyClassicAppearance()
        addChild(laser)
        activeLasers.append(laser)
        SoundManager.shared.playClassicShot()
    }

    func activateClassicHyperspace() {
        guard gameMode == .classicAsteroids, gameState == .playing,
              classicSession.isShipActive, !ship.isHidden else { return }

        ship.isHidden = true
        ship.velocity = .zero
        SoundManager.shared.setThrustActive(false)

        // Verhalten nach dem wiederhergestellten Programm: X wird aus 0…31 gezogen und auf einen
        // Innenbereich begrenzt; nach fünf weiteren Ziehungen bestimmt derselbe Wert Y und das mit
        // sinkender Felszahl gefährlichere Fehlfunktionsrisiko.
        let rawX = Int(rng.next() & 0x1F)
        var rawYAndRisk = 0
        for _ in 0..<5 { rawYAndRisk = Int(rng.next() & 0x1F) }
        let boundedX = min(28, max(3, rawX))
        let boundedY = min(20, max(3, rawYAndRisk))

        let halfWidth = max(160.0, size.width / 2.0)
        let halfHeight = max(120.0, size.height / 2.0)
        let xFraction = CGFloat(boundedX - 3) / 25.0
        let yFraction = CGFloat(boundedY - 3) / 17.0
        let reentry = CGPoint(x: (-halfWidth + 70.0) + xFraction * (2.0 * halfWidth - 140.0),
                              y: (-halfHeight + 60.0) + yFraction * (2.0 * halfHeight - 120.0))

        let riskThreshold = (rawYAndRisk & 0x07) * 2 + 4
        let destroysShip = rawYAndRisk >= 24 && riskThreshold >= activeAsteroids.count
        ship.position = reentry
        classicSession.shipPhase = .hyperspace(
            reappearAt: classicSession.elapsedTime + ClassicTuning.hyperspaceDelay,
            position: reentry,
            destroysShip: destroysShip
        )
    }

    func destroyClassicShip(cause: DeathCause) {
        loseClassicShip(cause: cause, allowHiddenHyperspaceFailure: false)
    }

    private func loseClassicShip(cause: DeathCause, allowHiddenHyperspaceFailure: Bool) {
        if !allowHiddenHyperspaceFailure {
            guard classicSession.isShipActive, !ship.isHidden else { return }
        }
        if case .destroyed = classicSession.shipPhase { return }

        lastDeathCause = cause
        classicSession.shipsRemaining = max(0, classicSession.shipsRemaining - 1)
        classicSession.shipPhase = .destroyed(
            reappearAt: classicSession.elapsedTime + ClassicTuning.respawnDelay
        )
        ship.isHidden = true
        ship.velocity = .zero
        activeKeys.removeAll()
        SoundManager.shared.setThrustActive(false)
        SoundManager.shared.playClassicExplosion()
        createClassicVectorDebris(at: ship.position, pieces: 6)
        updateLivesLabel()
    }

    private func updateClassicShipPhase(currentTime: TimeInterval) {
        switch classicSession.shipPhase {
        case .active:
            break
        case .hyperspace(let reappearAt, let position, let destroysShip):
            guard currentTime >= reappearAt else { return }
            ship.position = position
            if destroysShip {
                loseClassicShip(cause: .hyperspaceMalfunction, allowHiddenHyperspaceFailure: true)
            } else {
                postponeClassicSaucerFire(after: currentTime)
                ship.velocity = .zero
                ship.isHidden = false
                ship.alpha = 1.0
                classicSession.shipPhase = .active
            }
        case .destroyed(let reappearAt):
            guard currentTime >= reappearAt else { return }
            guard classicSession.shipsRemaining > 0 else {
                triggerGameOver()
                return
            }
            guard isClassicCenterClear() else { return }
            ship.position = .zero
            ship.velocity = .zero
            ship.zRotation = 0.0
            ship.alpha = 1.0
            postponeClassicSaucerFire(after: currentTime)
            ship.isHidden = false
            classicSession.shipPhase = .active
        }
    }

    /// Ein verstecktes Schiff darf die Schussfrist nicht unbemerkt verbrauchen. Beim Wiedererscheinen
    /// bekommt es dieselbe kurze Vorwarnung wie beim Eintritt einer neuen Untertasse; Kollisionen und
    /// bereits fliegende Geschosse bleiben davon bewusst unberührt.
    private func postponeClassicSaucerFire(after currentTime: TimeInterval) {
        let nextEligibleFireTime = currentTime + ClassicTuning.saucerHoldFireDuration
        for ufo in activeUFOs {
            ufo.postponeClassicFire(until: nextEligibleFireTime)
        }
    }

    private func isClassicCenterClear() -> Bool {
        for asteroid in activeAsteroids {
            if classicDistance(.zero, asteroid.position)
                < ClassicTuning.safeRespawnRadius + asteroid.sizeClass.rawValue { return false }
        }
        for ufo in activeUFOs where classicDistance(.zero, ufo.position) < 135.0 { return false }
        for laser in activeLasers where laser.type != .normal && !laser.isClassicSpent {
            if classicDistance(.zero, laser.position) < 90.0 { return false }
        }
        return true
    }

    // MARK: - Wellen und Asteroiden

    func spawnClassicLargeAsteroid() {
        guard activeAsteroids.count < ClassicTuning.maximumAsteroids else { return }
        let asteroid = makeClassicAsteroid(sizeClass: .large)
        let halfWidth = max(200.0, size.width / 2.0)
        let halfHeight = max(150.0, size.height / 2.0)
        let edge = Int.random(in: 0..<4, using: &rng)
        switch edge {
        case 0:
            asteroid.position = CGPoint(x: -halfWidth + 12.0,
                                         y: CGFloat.random(in: -halfHeight...halfHeight, using: &rng))
        case 1:
            asteroid.position = CGPoint(x: halfWidth - 12.0,
                                         y: CGFloat.random(in: -halfHeight...halfHeight, using: &rng))
        case 2:
            asteroid.position = CGPoint(x: CGFloat.random(in: -halfWidth...halfWidth, using: &rng),
                                         y: -halfHeight + 12.0)
        default:
            asteroid.position = CGPoint(x: CGFloat.random(in: -halfWidth...halfWidth, using: &rng),
                                         y: halfHeight - 12.0)
        }
        asteroid.hasEnteredScreen = true
        let angle = CGFloat.random(in: 0..<(2.0 * .pi), using: &rng)
        let waveSpeed = min(1.45, 1.0 + CGFloat(max(0, classicSession.wave - 1)) * 0.035)
        let speed = CGFloat.random(in: 42.0...92.0, using: &rng) * waveSpeed
        asteroid.velocity = CGPoint(x: cos(angle) * speed, y: sin(angle) * speed)
        addChild(asteroid)
        activeAsteroids.append(asteroid)
    }

    private func makeClassicAsteroid(sizeClass: Asteroid.AsteroidSize) -> Asteroid {
        let asteroid = Asteroid(sizeClass: sizeClass, using: &rng)
        asteroid.applyClassicAppearance(family: Int.random(in: 0..<4, using: &rng))
        return asteroid
    }

    private func spawnClassicWave() {
        let count = ClassicTuning.largeAsteroidCount(for: classicSession.wave)
        classicSession.waveHits = 0
        classicSession.possibleWaveHits = count * 7
        classicSession.waveStartDeadline = nil
        classicSession.saucerTimerTicks = ClassicTuning.saucerWaveDelayTicks
        classicSession.nextHeartbeatTime = classicSession.elapsedTime + 0.35
        for _ in 0..<count { spawnClassicLargeAsteroid() }
    }

    private func updateClassicWave(currentTime: TimeInterval) {
        if activeAsteroids.isEmpty {
            if classicSession.waveStartDeadline == nil {
                classicSession.waveStartDeadline = currentTime + ClassicTuning.waveDelay
            }
            if let deadline = classicSession.waveStartDeadline,
               currentTime >= deadline,
               activeUFOs.isEmpty {
                classicSession.wave += 1
                currentLevel = classicSession.wave
                levelLabel.text = "WAVE: \(classicSession.wave)"
                classicHUD.updateWave(classicSession.wave)
                spawnClassicWave()
            }
        } else {
            classicSession.waveStartDeadline = nil
        }
    }

    @discardableResult
    private func breakClassicAsteroid(_ asteroid: Asteroid, awardsPlayerPoints: Bool) -> [Asteroid] {
        guard activeAsteroids.contains(where: { $0 === asteroid }) else { return [] }
        activeAsteroids.removeAll { $0 === asteroid }
        asteroid.removeFromParent()
        classicSession.waveHits += 1
        classicSession.saucerAsteroidHitTimerTicks = ClassicTuning.saucerAsteroidHitTicks

        if awardsPlayerPoints {
            let points: Int
            switch asteroid.sizeClass {
            case .large: points = 20
            case .medium: points = 50
            case .small: points = 100
            }
            addClassicScore(points)
        }

        SoundManager.shared.playClassicExplosion()
        createClassicVectorDebris(at: asteroid.position,
                                  pieces: asteroid.sizeClass == .large ? 6 : 4)

        let childSize: Asteroid.AsteroidSize
        switch asteroid.sizeClass {
        case .large: childSize = .medium
        case .medium: childSize = .small
        case .small: return []
        }

        let childCount = min(2, max(0, ClassicTuning.maximumAsteroids - activeAsteroids.count))
        guard childCount > 0 else { return [] }
        let baseSpeed = max(72.0, hypot(asteroid.velocity.x, asteroid.velocity.y) * 1.35)
        let baseAngle = atan2(asteroid.velocity.y, asteroid.velocity.x)
        var children: [Asteroid] = []
        children.reserveCapacity(childCount)
        for index in 0..<childCount {
            let child = makeClassicAsteroid(sizeClass: childSize)
            child.position = asteroid.position
            child.hasEnteredScreen = true
            let sign: CGFloat = index == 0 ? 1.0 : -1.0
            let angle = baseAngle + sign * 0.55
                + CGFloat.random(in: -0.08...0.08, using: &rng)
            child.velocity = CGPoint(x: cos(angle) * baseSpeed, y: sin(angle) * baseSpeed)
            addChild(child)
            activeAsteroids.append(child)
            children.append(child)
        }
        return children
    }

    private func addClassicScore(_ points: Int) {
        score += points
        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
        while score >= classicSession.nextBonusScore {
            classicSession.shipsRemaining += 1
            classicSession.nextBonusScore += 10_000
            SoundManager.shared.playClassicExtraLife()
            updateLivesLabel()
        }
    }

    // MARK: - Untertassen

    private func updateClassicSaucerSpawning() {
        classicSession.saucerTimerStepPhase += 1
        guard classicSession.saucerTimerStepPhase >= ClassicTuning.saucerTimerSimulationSteps else {
            return
        }
        classicSession.saucerTimerStepPhase = 0

        // ENEMY hält beide Zähler an, solange eine Untertasse lebt oder das Schiff nicht im
        // Spiel ist. Der globale Vier-Frame-Takt läuft dabei weiter.
        guard isSpawningEnabled, activeUFOs.isEmpty,
              classicSession.isShipActive, !ship.isHidden else { return }

        if classicSession.saucerAsteroidHitTimerTicks > 0 {
            classicSession.saucerAsteroidHitTimerTicks -= 1
        }
        if classicSession.saucerTimerTicks > 0 {
            classicSession.saucerTimerTicks -= 1
        }
        guard classicSession.saucerTimerTicks == 0 else { return }

        // Das Original lädt den kurzen Wiederholungszähler schon vor der Felsprüfung.
        classicSession.saucerTimerTicks = ClassicTuning.saucerRetryTicks
        if classicSession.saucerAsteroidHitTimerTicks > 0 {
            guard !activeAsteroids.isEmpty,
                  activeAsteroids.count < ClassicTuning.saucerRockThreshold(for: classicSession.wave)
            else { return }
        }
        _ = spawnClassicSaucer()
    }

    @discardableResult
    func spawnClassicSaucer() -> UFO {
        let isSmall: Bool
        if classicSession.saucerAppearances < 3 {
            isSmall = false
        } else if score >= 30_000 {
            isSmall = true
        } else {
            let largeChance = max(0.08, 0.25 - Double(score) / 200_000.0)
            isSmall = Double.random(in: 0...1, using: &rng) >= largeChance
        }
        let startOnLeft = Bool.random(using: &rng)
        let ufo = UFO(isSmall: isSmall, startOnLeft: startOnLeft, screenSize: size, using: &rng)
        ufo.applyClassicBehavior(startOnLeft: startOnLeft, currentTime: classicSession.elapsedTime)
        addChild(ufo)
        activeUFOs.append(ufo)
        classicSession.saucerAppearances += 1
        classicSession.saucerTimerReloadTicks = max(
            ClassicTuning.saucerMinimumReloadTicks,
            classicSession.saucerTimerReloadTicks - ClassicTuning.saucerReloadStepTicks
        )
        SoundManager.shared.setClassicSaucer(isSmall: isSmall)
        return ufo
    }

    private func updateClassicSaucers(deltaTime: TimeInterval, currentTime: TimeInterval) {
        var survivors: [UFO] = []
        var didRemoveSaucer = false
        for ufo in activeUFOs {
            if currentTime >= ufo.classicNextCourseChange {
                let courses: [CGFloat] = [
                    -ClassicTuning.saucerSpeed,
                    0.0,
                    0.0,
                    ClassicTuning.saucerSpeed
                ]
                ufo.velocity.y = courses[Int.random(in: 0..<courses.count, using: &rng)]
                ufo.classicNextCourseChange = currentTime + ClassicTuning.saucerCourseInterval
            }
            ufo.update(deltaTime: deltaTime)
            let halfHeight = size.height / 2.0
            if ufo.position.y > halfHeight { ufo.position.y -= size.height }
            if ufo.position.y < -halfHeight { ufo.position.y += size.height }

            let enemyShotCount = activeLasers.reduce(into: 0) { count, laser in
                if laser.type != .normal, !laser.isClassicSpent { count += 1 }
            }
            if classicSession.isShipActive, !ship.isHidden {
                // Atari setzt den Feuerzähler und verbraucht den Ziel-Zufall auch dann, wenn beide
                // Untertassen-Projektilslots belegt sind. Der fertige Schuss wird dann verworfen.
                let shot = ufo.shootClassic(target: ship.position, score: score,
                                            currentTime: currentTime, arenaSize: size, using: &rng)
                if enemyShotCount < ClassicTuning.maximumSaucerShots, let shot {
                    addChild(shot)
                    activeLasers.append(shot)
                    SoundManager.shared.playClassicSaucerFire()
                }
            }

            if ufo.isExited(screenSize: size) {
                ufo.removeFromParent()
                didRemoveSaucer = true
            } else {
                survivors.append(ufo)
            }
        }
        activeUFOs = survivors
        if didRemoveSaucer {
            resetClassicSaucerTimerAfterRemoval()
        }
        SoundManager.shared.setClassicSaucer(isSmall: activeUFOs.first?.isSmall)
    }

    private func removeClassicSaucer(_ ufo: UFO) {
        guard activeUFOs.contains(where: { $0 === ufo }) else { return }
        activeUFOs.removeAll { $0 === ufo }
        ufo.removeFromParent()
        resetClassicSaucerTimerAfterRemoval()
        SoundManager.shared.setClassicSaucer(isSmall: activeUFOs.first?.isSmall)
    }

    private func resetClassicSaucerTimerAfterRemoval() {
        guard activeUFOs.isEmpty else { return }
        classicSession.saucerTimerTicks = classicSession.saucerTimerReloadTicks
    }

    // MARK: - Kollisionen

    private func resolveClassicCollisions() {
        var survivingLasers: [Laser] = []
        survivingLasers.reserveCapacity(activeLasers.count)

        for laser in activeLasers {
            if laser.isClassicSpent {
                survivingLasers.append(laser)
                continue
            }
            if let asteroid = activeAsteroids.first(where: {
                CollisionHelper.laserIntersectsAsteroid(laser, $0)
            }) {
                _ = breakClassicAsteroid(asteroid, awardsPlayerPoints: laser.type == .normal)
                laser.removeFromParent()
                continue
            }

            if laser.type == .normal {
                let segment = laser.getWorldSegment()
                if let ufo = activeUFOs.first(where: { candidate in
                    let polygon = candidate.getWorldVertices()
                    return CollisionHelper.isPointInPolygon(segment.0, polygon: polygon)
                        || CollisionHelper.isPointInPolygon(segment.1, polygon: polygon)
                }) {
                    removeClassicSaucer(ufo)
                    laser.removeFromParent()
                    addClassicScore(ufo.pointValue)
                    SoundManager.shared.playClassicExplosion()
                    createClassicVectorDebris(at: ufo.position, pieces: 6)
                    continue
                }
            } else if classicSession.isShipActive && !ship.isHidden {
                let segment = laser.getWorldSegment()
                let polygon = ship.getWorldVertices()
                if CollisionHelper.isPointInPolygon(segment.0, polygon: polygon)
                    || CollisionHelper.isPointInPolygon(segment.1, polygon: polygon) {
                    laser.removeFromParent()
                    destroyClassicShip(cause: .ufoLaser)
                    continue
                }
            }
            survivingLasers.append(laser)
        }
        activeLasers = survivingLasers

        // Untertassen zerlegen Felsen beim Rammen, geben dem Spieler dafür aber keine Punkte.
        for ufo in Array(activeUFOs) {
            guard let asteroid = activeAsteroids.first(where: {
                CollisionHelper.polygonsIntersect(ufo.getWorldVertices(), $0.getWorldVertices())
            }) else { continue }
            _ = breakClassicAsteroid(asteroid, awardsPlayerPoints: false)
            removeClassicSaucer(ufo)
            SoundManager.shared.playClassicExplosion()
            createClassicVectorDebris(at: ufo.position, pieces: 5)
        }

        guard classicSession.isShipActive, !ship.isHidden else { return }
        let shipPolygon = ship.getWorldVertices()
        if let asteroid = activeAsteroids.first(where: {
            CollisionHelper.polygonsIntersect(shipPolygon, $0.getWorldVertices())
        }) {
            let cause: DeathCause
            switch asteroid.sizeClass {
            case .large: cause = .largeAsteroid
            case .medium: cause = .mediumAsteroid
            case .small: cause = .smallAsteroid
            }
            _ = breakClassicAsteroid(asteroid, awardsPlayerPoints: true)
            destroyClassicShip(cause: cause)
            return
        }
        if let ufo = activeUFOs.first(where: {
            CollisionHelper.polygonsIntersect(shipPolygon, $0.getWorldVertices())
        }) {
            removeClassicSaucer(ufo)
            addClassicScore(ufo.pointValue)
            createClassicVectorDebris(at: ufo.position, pieces: 5)
            destroyClassicShip(cause: .ufo)
        }
    }

    // MARK: - Audio und weiße Vektorreste

    private func updateClassicHeartbeat(currentTime: TimeInterval) {
        guard classicSession.isShipActive, !activeAsteroids.isEmpty,
              currentTime >= classicSession.nextHeartbeatTime else { return }
        SoundManager.shared.playClassicHeartbeat(high: classicSession.heartbeatHigh)
        classicSession.heartbeatHigh.toggle()
        let progress = min(1.0, Double(classicSession.waveHits)
            / Double(max(1, classicSession.possibleWaveHits)))
        classicSession.nextHeartbeatTime = currentTime + (0.92 - progress * 0.67)
    }

    private func createClassicVectorDebris(at position: CGPoint, pieces: Int) {
        for index in 0..<pieces {
            let angle = CGFloat(index) / CGFloat(max(1, pieces)) * 2.0 * .pi + 0.17
            let segment = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -5.0, y: 0.0))
            path.addLine(to: CGPoint(x: 5.0, y: 0.0))
            segment.path = path
            segment.position = position
            segment.zRotation = angle
            segment.strokeColor = .white
            segment.fillColor = .clear
            segment.lineWidth = 1.7
            segment.name = "classicVectorDebris"
            VectorGlowRenderer.markStroke(segment)
            addChild(segment)
            let distance: CGFloat = 28.0 + CGFloat(index % 3) * 11.0
            segment.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.62),
                    .rotate(byAngle: index.isMultiple(of: 2) ? 1.4 : -1.4, duration: 0.62),
                    .fadeOut(withDuration: 0.62)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func classicDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
