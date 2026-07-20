import SpriteKit

/// A subclass of `SKShapeNode` representing a retro vector alien flying saucer (UFO) enemy.
public final class UFO: SKShapeNode {
    
    // MARK: - Properties
    
    /// Whether this is a small (dangerous, sniping) UFO or a large (random shooting) UFO.
    public let isSmall: Bool
    
    /// The UFO's velocity vector.
    public var velocity: CGPoint = .zero
    
    /// Base points awarded when destroyed.
    public var pointValue: Int {
        if usesClassicBehavior { return isSmall ? 1000 : 200 }
        return isSmall ? 500 : 200
    }

    /// Internes Classic-Profil; die öffentlichen Initializer bleiben unverändert.
    private(set) var usesClassicBehavior = false
    var classicNextCourseChange: TimeInterval = 0.0
    private var classicNextFireTime: TimeInterval = .infinity
    
    // Bewegungs-Parameter: leichtes seitliches Schlingern + sanfte Verfolgung des Spielers.
    private var wavyTime: TimeInterval = 0.0
    private let wavyFrequency: CGFloat = 3.5
    /// Sanfte Beschleunigung Richtung Spieler (px/s²) – bewusst klein, damit es nicht zu schwer wird:
    /// die horizontale Grund-Bewegung trägt das UFO trotzdem über den Schirm und wieder hinaus.
    private let homingAccel: CGFloat = 72.0
    /// Stärke des seitlichen Schlingerns (Retro-Charakter, summiert sich nicht zu Drift auf).
    private let wobbleAccel: CGFloat = 240.0
    /// Maximale Geschwindigkeit (gedeckelt): klein/wendig vs. groß/träge.
    private var maxSpeed: CGFloat { isSmall ? 235.0 : 155.0 }
    
    // Local outline vertices (unscaled)
    public let baseVertices: [CGPoint] = [
        CGPoint(x: -18, y: -3),
        CGPoint(x: -10, y: 3),
        CGPoint(x: -6, y: 8),
        CGPoint(x: 6, y: 8),
        CGPoint(x: 10, y: 3),
        CGPoint(x: 18, y: -3),
        CGPoint(x: 10, y: -3),
        CGPoint(x: 6, y: -7),
        CGPoint(x: -6, y: -7),
        CGPoint(x: -10, y: -3)
    ]
    
    // Actual vertices scaled for this instance
    public var vertices: [CGPoint] = []
    
    // Firing cooldown parameters
    private var lastFireTime: TimeInterval = 0.0
    public let fireCooldown: TimeInterval
    
    // MARK: - Initializer
    
    /// Initializes a new UFO enemy.
    /// - Parameters:
    ///   - isSmall: True if the UFO is small and aims at the player, false if it is large and shoots randomly.
    ///   - startOnLeft: True if it enters from the left edge of the screen, false if it enters from the right.
    ///   - screenSize: The screen dimensions to determine bounds and spawn heights.
    public init(isSmall: Bool, startOnLeft: Bool, screenSize: CGSize, using rng: inout GameRandom) {
        self.isSmall = isSmall
        self.fireCooldown = isSmall ? 1.5 : 2.2
        super.init()
        
        // Setup scaling and vertices
        let scale: CGFloat = isSmall ? 0.6 : 1.2
        self.vertices = baseVertices.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        
        // Setup shape path
        let ufoPath = CGMutablePath()
        if let first = vertices.first {
            ufoPath.move(to: first)
            for pt in vertices.dropFirst() {
                ufoPath.addLine(to: pt)
            }
            ufoPath.closeSubpath()
            
            // Draw secondary cockpit dome line
            ufoPath.move(to: CGPoint(x: -10 * scale, y: 3 * scale))
            ufoPath.addLine(to: CGPoint(x: 10 * scale, y: 3 * scale))
        }
        self.path = ufoPath
        
        // Colors: Large is green, Small is hot pink/orange
        if isSmall {
            self.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0)
            self.fillColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 0.15)
        } else {
            self.strokeColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            self.fillColor = SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 0.15)
        }
        self.lineWidth = 1.8
        self.lineJoin = .miter
        VectorGlowRenderer.markStroke(self)
        
        // Initialize position completely off-screen
        let halfWidth = screenSize.width / 2
        let startX = startOnLeft ? -halfWidth - 50.0 : halfWidth + 50.0
        let startY = CGFloat.random(in: -screenSize.height * 0.25...screenSize.height * 0.25, using: &rng)
        self.position = CGPoint(x: startX, y: startY)
        
        // Initialize velocity (horizontal constant, wavy vertical)
        let speedX = isSmall ? CGFloat(150.0) : CGFloat(90.0)
        self.velocity = CGPoint(
            x: startOnLeft ? speedX : -speedX,
            y: 0.0
        )
    }
    
    /// Convenience-Initializer ohne Seed für Tests/Helfer — würfelt aus dem System-RNG.
    /// NICHT im deterministischen Gameplay-Pfad verwenden (dafür den Initializer mit `using rng:`).
    public convenience init(isSmall: Bool, startOnLeft: Bool, screenSize: CGSize) {
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        self.init(isSmall: isSmall, startOnLeft: startOnLeft, screenSize: screenSize, using: &throwaway)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.isSmall = false
        self.fireCooldown = 2.0
        super.init(coder: aDecoder)
    }
    
    // MARK: - Updates
    
    /// Aktualisiert Position und Flugbahn. `target` (Schiffsposition) wird – falls vorhanden – für
    /// eine **sanfte Verfolgung** genutzt: Das UFO beschleunigt leicht in Spielerrichtung, sodass es
    /// nicht stumpf seitlich wegfliegt, sondern „ein bisschen auf uns zu" kommt. Der Effekt ist
    /// gedeckelt (siehe `homingAccel`/`maxSpeed`), damit es nicht zu schwer wird.
    public func update(deltaTime: TimeInterval, target: CGPoint? = nil) {
        let dt = CGFloat(deltaTime)

        if usesClassicBehavior {
            position.x += velocity.x * dt
            position.y += velocity.y * dt
            return
        }

        wavyTime += deltaTime

        // Sanfte Verfolgung: leicht Richtung Spieler beschleunigen.
        if let target = target {
            let dx = target.x - position.x
            let dy = target.y - position.y
            let d = hypot(dx, dy)
            if d > 0.001 {
                velocity.x += dx / d * homingAccel * dt
                velocity.y += dy / d * homingAccel * dt
            }
        }

        // Seitliches Schlingern senkrecht zur Flugrichtung (Charakter, ohne Netto-Drift).
        let speedNow = hypot(velocity.x, velocity.y)
        if speedNow > 0.001 {
            let perpX = -velocity.y / speedNow
            let perpY = velocity.x / speedNow
            let wob = sin(CGFloat(wavyTime) * wavyFrequency) * wobbleAccel * dt
            velocity.x += perpX * wob
            velocity.y += perpY * wob
        }

        // Geschwindigkeit deckeln.
        let speed = hypot(velocity.x, velocity.y)
        if speed > maxSpeed {
            velocity.x *= maxSpeed / speed
            velocity.y *= maxSpeed / speed
        }

        position.x += velocity.x * dt
        position.y += velocity.y * dt
    }
    
    /// Determines if the UFO has completely exited screen bounds.
    public func isExited(screenSize: CGSize) -> Bool {
        let threshold = screenSize.width / 2 + 60.0
        return abs(position.x) > threshold
    }
    
    /// Shoots a warning laser directed towards a target position or randomly.
    public func shoot(target: CGPoint, currentTime: TimeInterval, using rng: inout GameRandom) -> Laser? {
        guard currentTime - lastFireTime >= fireCooldown else { return nil }
        lastFireTime = currentTime

        let angle: CGFloat
        if isSmall {
            // Snipes at player ship with minor random error
            let baseAngle = atan2(target.y - position.y, target.x - position.x)
            angle = baseAngle + CGFloat.random(in: -0.12...0.12, using: &rng)
        } else {
            // Large saucer fires in a completely random direction
            angle = CGFloat.random(in: 0..<(2.0 * .pi), using: &rng)
        }
        
        // Spawn laser slightly offset from center
        let spawnPos = CGPoint(
            x: position.x + 15 * cos(angle),
            y: position.y + 15 * sin(angle)
        )
        
        return Laser(position: spawnPos, angle: angle, type: .enemy)
    }

    /// Aktiviert die weiße, ungefüllte Arcade-Darstellung und die rein horizontale Grundbewegung.
    func applyClassicBehavior(startOnLeft: Bool, currentTime: TimeInterval) {
        usesClassicBehavior = true
        strokeColor = .white
        fillColor = .clear
        lineWidth = 1.8
        velocity = CGPoint(x: startOnLeft ? ClassicTuning.saucerSpeed : -ClassicTuning.saucerSpeed,
                           y: 0.0)
        classicNextCourseChange = currentTime + ClassicTuning.saucerCourseInterval
        classicNextFireTime = currentTime + ClassicTuning.saucerHoldFireDuration
        VectorGlowRenderer.markStroke(self)
    }

    /// Verschiebt die Classic-Schussfreigabe nur nach hinten. So kann ein Respawn eine noch
    /// laufende Eintrittsfrist niemals versehentlich verkürzen.
    func postponeClassicFire(until nextEligibleFireTime: TimeInterval) {
        guard usesClassicBehavior else { return }
        classicNextFireTime = max(classicNextFireTime, nextEligibleFireTime)
    }

    /// Classic-Saucer-Schuss: große Untertasse zufällig, kleine mit ab 35.000 Punkten engerem Fehler.
    func shootClassic(target: CGPoint, score: Int, currentTime: TimeInterval,
                      arenaSize: CGSize, using rng: inout GameRandom) -> Laser? {
        // Wiederholtes Addieren des 1/120-s-Schritts kann wenige ULP unter der mathematischen
        // Deadline landen. Die winzige Toleranz korrigiert nur diesen Rundungsfehler; ein ganzer
        // Simulationsschritt vor der Frist bleibt um Größenordnungen zu früh.
        guard usesClassicBehavior, currentTime + 1e-9 >= classicNextFireTime else { return nil }
        classicNextFireTime = currentTime + ClassicTuning.saucerFireInterval

        let angle: CGFloat
        if isSmall {
            // Der Arcadecode kompensiert die geerbte Untertassenbewegung über 32 Frames und bildet
            // den absichtlich groben Zielfehler aus einem maskierten 8-Bit-Zufallswinkel. Unter
            // 35.000 Punkten sind es -16...+15, danach -7...+8 Schritte eines 256er-Kreises.
            let compensation = CGFloat(ClassicTuning.saucerAimCompensationDuration)
            let dx = target.x - position.x - velocity.x * compensation
            let dy = target.y - position.y - velocity.y * compensation
            let base = atan2(dy, dx)
            let randomAngle = UInt8(truncatingIfNeeded: rng.next())
            let errorMask: UInt8 = score >= 35_000 ? 0x87 : 0x8F
            let signExtensionMask: UInt8 = score >= 35_000 ? 0x78 : 0x70
            var errorByte = randomAngle & errorMask
            if errorByte & 0x80 != 0 { errorByte |= signExtensionMask }
            // Bei >= 35.000 bleibt der Carry des 6502-Vergleichs bis zum abschließenden ADC gesetzt.
            // Deshalb verschiebt sich das engere Band von -8...+7 auf tatsächlich -7...+8.
            let comparisonCarry = score >= 35_000 ? 1 : 0
            let errorUnits = Int(Int8(bitPattern: errorByte)) + comparisonCarry
            angle = base + CGFloat(errorUnits) * ClassicTuning.angleStep
        } else {
            let randomAngle = UInt8(truncatingIfNeeded: rng.next())
            angle = CGFloat(randomAngle) * ClassicTuning.angleStep
        }
        let calibration = ClassicProjectileCalibrator.calibrate(
            angle: angle,
            shooterVelocity: velocity,
            arenaSize: arenaSize,
            movementFrames: ClassicProjectileCalibrator.saucerMovementFrames
        )
        let spawn = CGPoint(x: position.x + calibration.spawnOffset.x,
                            y: position.y + calibration.spawnOffset.y)
        let laser = Laser(position: spawn, angle: angle, type: .enemy,
                          speed: 0.0, lifetime: calibration.lifetime)
        laser.applyClassicBallistics(velocity: calibration.velocity)
        laser.applyClassicAppearance()
        return laser
    }
    
    /// Returns world-space coordinates of the UFO vertices.
    public func getWorldVertices() -> [CGPoint] {
        return vertices.map { pt in
            CGPoint(x: position.x + pt.x, y: position.y + pt.y)
        }
    }
}
