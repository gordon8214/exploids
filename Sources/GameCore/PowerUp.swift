import SpriteKit

/// The available power-up types in exploids.
public enum PowerUpType: String, CaseIterable, Sendable {
    case shield = "S"      // Grants an energy shield
    case triple = "W"      // Grants triple laser spread shot
    case rapid = "R"       // Grants extremely fast firing speed
    case option = "O"      // Spawns a supplementary option drone
    case bomb = "B"        // Triggers a screen clearing bomb explosion
    case beam = "L"        // Hold-to-fire sweeping laser beam (half-screen length, wraps edges)
    case rear = "T"        // Fires an additional laser backwards with every shot
    case compress = "C"    // Shrinks the ship to ~30% (smaller target)
    case extraLife = "+"   // Extra life: revive centered + brief invincibility instead of dying
}

/// A subclass of `SKShapeNode` representing a collectable floating power-up capsule.
public final class PowerUp: SKShapeNode {
    
    // MARK: - Properties
    
    /// The type of power-up.
    public let type: PowerUpType
    
    /// The drift velocity.
    public var velocity: CGPoint = .zero
    
    /// The duration this power-up remains on screen before dissolving.
    public let lifetime: TimeInterval = 10.0
    
    /// The elapsed time since spawning.
    public private(set) var elapsedTime: TimeInterval = 0.0
    
    private let rotationSpeed: CGFloat = 1.2
    private let labelNode = SKLabelNode(fontNamed: "Courier-Bold")
    
    // MARK: - Initializer
    
    /// Initializes a new power-up capsule.
    /// - Parameters:
    ///   - type: The power-up type. If nil, a random one is chosen.
    ///   - position: The spawning position in scene coordinates.
    public init(type: PowerUpType? = nil, position: CGPoint, using rng: inout GameRandom) {
        self.type = type ?? PowerUpType.allCases.randomElement(using: &rng)!
        super.init()

        self.position = position
        setupPowerUp(using: &rng)
    }

    /// Convenience-Initializer ohne Seed für Tests/Helfer — würfelt aus dem System-RNG.
    /// NICHT im deterministischen Gameplay-Pfad verwenden (dafür den Initializer mit `using rng:`).
    public convenience init(type: PowerUpType? = nil, position: CGPoint) {
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        self.init(type: type, position: position, using: &throwaway)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.type = .shield
        super.init(coder: aDecoder)
    }
    
    // MARK: - Setup
    
    private func setupPowerUp(using rng: inout GameRandom) {
        let path = CGMutablePath()
        let strokeColor: SKColor
        let fillColor: SKColor
        
        switch type {
        case .shield: // Cyan double concentric circle
            path.addEllipse(in: CGRect(x: -18, y: -18, width: 36, height: 36))
            path.addEllipse(in: CGRect(x: -12, y: -12, width: 24, height: 24))
            strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
            fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.15)
            
        case .triple: // Red/Orange double upward triangle with direction ticks
            // Outer triangle
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 18, y: -14))
            path.addLine(to: CGPoint(x: -18, y: -14))
            path.closeSubpath()
            
            // Inner triangle
            path.move(to: CGPoint(x: 0, y: 11))
            path.addLine(to: CGPoint(x: 10, y: -8))
            path.addLine(to: CGPoint(x: -10, y: -8))
            path.closeSubpath()
            
            // Corner ticks representing spread direction
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 25))
            
            path.move(to: CGPoint(x: 18, y: -14))
            path.addLine(to: CGPoint(x: 23, y: -18))
            
            path.move(to: CGPoint(x: -18, y: -14))
            path.addLine(to: CGPoint(x: -23, y: -18))
            
            strokeColor = SKColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)
            fillColor = SKColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 0.15)
            
        case .rapid: // Yellow double diamond with speed wings
            // Outer diamond
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 20, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -20))
            path.addLine(to: CGPoint(x: -20, y: 0))
            path.closeSubpath()
            
            // Inner diamond
            path.move(to: CGPoint(x: 0, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -12))
            path.addLine(to: CGPoint(x: -12, y: 0))
            path.closeSubpath()
            
            // Speed wings
            path.move(to: CGPoint(x: -26, y: 0))
            path.addLine(to: CGPoint(x: -20, y: 0))
            
            path.move(to: CGPoint(x: 20, y: 0))
            path.addLine(to: CGPoint(x: 26, y: 0))
            
            strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
            fillColor = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.15)
            
        case .option: // Purple square with corner satellites
            // Core square
            path.addRect(CGRect(x: -14, y: -14, width: 28, height: 28))
            
            // Corner satellites
            path.addRect(CGRect(x: -21, y: 15, width: 6, height: 6))
            path.addRect(CGRect(x: 15, y: 15, width: 6, height: 6))
            path.addRect(CGRect(x: 15, y: -21, width: 6, height: 6))
            path.addRect(CGRect(x: -21, y: -21, width: 6, height: 6))
            
            strokeColor = SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 1.0)
            fillColor = SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 0.15)
            
        case .bomb: // Bright Red octagon with crosshairs and inner ring
            // Outer octagon
            path.move(to: CGPoint(x: -7, y: 18))
            path.addLine(to: CGPoint(x: 7, y: 18))
            path.addLine(to: CGPoint(x: 18, y: 7))
            path.addLine(to: CGPoint(x: 18, y: -7))
            path.addLine(to: CGPoint(x: 7, y: -18))
            path.addLine(to: CGPoint(x: -7, y: -18))
            path.addLine(to: CGPoint(x: -18, y: -7))
            path.addLine(to: CGPoint(x: -18, y: 7))
            path.closeSubpath()
            
            // Inner circle
            path.addEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
            
            // Crosshairs extending outward
            path.move(to: CGPoint(x: -25, y: 0))
            path.addLine(to: CGPoint(x: -18, y: 0))
            
            path.move(to: CGPoint(x: 18, y: 0))
            path.addLine(to: CGPoint(x: 25, y: 0))
            
            path.move(to: CGPoint(x: 0, y: -25))
            path.addLine(to: CGPoint(x: 0, y: -18))
            
            path.move(to: CGPoint(x: 0, y: 18))
            path.addLine(to: CGPoint(x: 0, y: 25))
            
            strokeColor = SKColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0)
            fillColor = SKColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 0.15)

        case .beam: // Lime green vertical beam bar with end caps
            path.addRect(CGRect(x: -5, y: -20, width: 10, height: 40))
            path.move(to: CGPoint(x: -11, y: 20))
            path.addLine(to: CGPoint(x: 11, y: 20))
            path.move(to: CGPoint(x: -11, y: -20))
            path.addLine(to: CGPoint(x: 11, y: -20))
            strokeColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
            fillColor = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 0.15)

        case .rear: // Light blue bidirectional double triangle (forward + backward)
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 14, y: 4))
            path.addLine(to: CGPoint(x: -14, y: 4))
            path.closeSubpath()
            path.move(to: CGPoint(x: 0, y: -20))
            path.addLine(to: CGPoint(x: 14, y: -4))
            path.addLine(to: CGPoint(x: -14, y: -4))
            path.closeSubpath()
            strokeColor = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            fillColor = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.15)

        case .compress: // White concentric squares with inward corner ticks (shrinking)
            path.addRect(CGRect(x: -18, y: -18, width: 36, height: 36))
            path.addRect(CGRect(x: -9, y: -9, width: 18, height: 18))
            path.move(to: CGPoint(x: -18, y: -18)); path.addLine(to: CGPoint(x: -11, y: -11))
            path.move(to: CGPoint(x: 18, y: 18)); path.addLine(to: CGPoint(x: 11, y: 11))
            path.move(to: CGPoint(x: -18, y: 18)); path.addLine(to: CGPoint(x: -11, y: 11))
            path.move(to: CGPoint(x: 18, y: -18)); path.addLine(to: CGPoint(x: 11, y: -11))
            strokeColor = SKColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
            fillColor = SKColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 0.15)

        case .extraLife: // Pink-red plus / cross (extra life)
            path.addRect(CGRect(x: -5, y: -18, width: 10, height: 36))
            path.addRect(CGRect(x: -18, y: -5, width: 36, height: 10))
            strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0)
            fillColor = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 0.15)
        }

        self.path = path
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = 2.0
        VectorGlowRenderer.markStroke(self)
        
        // Add centered letter label matching the outline color
        labelNode.text = type.rawValue
        labelNode.fontSize = 16
        labelNode.fontColor = strokeColor
        labelNode.horizontalAlignmentMode = .center
        labelNode.verticalAlignmentMode = .center
        labelNode.zPosition = 10
        self.addChild(labelNode)
        
        // Setup slow random drift velocity
        let speed = CGFloat.random(in: 25.0...55.0, using: &rng)
        let angle = CGFloat.random(in: 0..<(2.0 * .pi), using: &rng)
        self.velocity = CGPoint(
            x: speed * cos(angle),
            y: speed * sin(angle)
        )
        
        // Fade pulse animation
        let fadeOut = SKAction.fadeAlpha(to: 0.4, duration: 0.6)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.6)
        let pulse = SKAction.sequence([fadeOut, fadeIn])
        self.run(SKAction.repeatForever(pulse))
    }
    
    /// Sets the remaining lifetime of this power-up.
    public func setRemainingLifetime(to duration: TimeInterval) {
        self.elapsedTime = max(0.0, lifetime - duration)
    }
    
    // MARK: - Update
    
    /// Updates position, rotates shape, and keeps the text label upright.
    /// - Returns: `true` if the power-up has expired, otherwise `false`.
    public func update(deltaTime: TimeInterval) -> Bool {
        elapsedTime += deltaTime
        let dt = CGFloat(deltaTime)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        
        zRotation += rotationSpeed * dt
        
        // Counter-rotate label so the letter remains upright and readable
        labelNode.zRotation = -zRotation
        
        // Dissolve in the final 2 seconds
        if elapsedTime >= lifetime - 2.0 {
            self.alpha = CGFloat(max(0.0, (lifetime - elapsedTime) / 2.0))
        }
        
        return elapsedTime >= lifetime
    }
    
    /// Wraps the power-up around screen boundaries. (Gemeinsame Logik: VectorMath.swift)
    public func wrapAround(screenSize: CGSize) {
        wrapPositionAround(screenSize: screenSize)
    }
    
    /// Returns world-space coordinates of the vertices for collision check.
    public func getWorldVertices() -> [CGPoint] {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        let localPts: [CGPoint]
        switch type {
        case .shield:
            localPts = [
                CGPoint(x: 0, y: 18),
                CGPoint(x: 13, y: 13),
                CGPoint(x: 18, y: 0),
                CGPoint(x: 13, y: -13),
                CGPoint(x: 0, y: -18),
                CGPoint(x: -13, y: -13),
                CGPoint(x: -18, y: 0),
                CGPoint(x: -13, y: 13)
            ]
        case .triple:
            localPts = [
                CGPoint(x: 0, y: 20),
                CGPoint(x: 18, y: -14),
                CGPoint(x: -18, y: -14)
            ]
        case .rapid:
            localPts = [
                CGPoint(x: 0, y: 20),
                CGPoint(x: 20, y: 0),
                CGPoint(x: 0, y: -20),
                CGPoint(x: -20, y: 0)
            ]
        case .option:
            localPts = [
                CGPoint(x: -15, y: 15),
                CGPoint(x: 15, y: 15),
                CGPoint(x: 15, y: -15),
                CGPoint(x: -15, y: -15)
            ]
        case .bomb:
            localPts = [
                CGPoint(x: -7, y: 18),
                CGPoint(x: 7, y: 18),
                CGPoint(x: 18, y: 7),
                CGPoint(x: 18, y: -7),
                CGPoint(x: 7, y: -18),
                CGPoint(x: -7, y: -18),
                CGPoint(x: -18, y: -7),
                CGPoint(x: -18, y: 7)
            ]
        case .beam, .rear, .compress, .extraLife:
            // Vereinfachte Diamant-Kollisionsform (~18) für die neuen Power-Up-Typen.
            localPts = [
                CGPoint(x: 0, y: 18),
                CGPoint(x: 18, y: 0),
                CGPoint(x: 0, y: -18),
                CGPoint(x: -18, y: 0)
            ]
        }
        return localPts.map { pt in
            CGPoint(
                x: position.x + pt.x * cosTheta - pt.y * sinTheta,
                y: position.y + pt.x * sinTheta + pt.y * cosTheta
            )
        }
    }
}
