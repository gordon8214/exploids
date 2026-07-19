import SpriteKit

/// Predefined projectile types for exploids.
public enum LaserType: Sendable {
    case normal
    case enemy
    /// Augen-Laser der Weltraumkatze: optisch deutlich anders (zwei parallele, **längere** Streifen),
    /// langsamer als Spielerschüsse. Wirkt wie ein Gegner-Schuss (tötet das Schiff bei Kontakt).
    case catEye
}

/// A subclass of `SKShapeNode` representing a high-velocity laser projectile.
public final class Laser: SKShapeNode {
    
    // MARK: - Properties
    
    /// The laser's velocity vector in points per second.
    public var velocity: CGPoint = .zero
    
    /// The total duration the laser can exist before expiring.
    public let lifetime: TimeInterval
    
    /// The classification of this laser.
    public let type: LaserType
    
    /// The maximum number of asteroids this laser can pierce before being destroyed.
    public var pierceLimit: Int = 1
    
    /// The number of asteroids this laser has already pierced.
    public var pierceCount: Int = 0
    
    /// The elapsed time since the laser was fired.
    private var elapsedTime: TimeInterval = 0.0
    
    // MARK: - Initializers
    
    /// Initializes a new laser projectile.
    public init(position: CGPoint, angle: CGFloat, type: LaserType = .normal, speed: CGFloat = 600.0, lifetime: TimeInterval = 1.2) {
        self.type = type
        self.lifetime = lifetime
        super.init()
        
        self.position = position
        self.zRotation = angle
        
        // Define physics properties based on type
        switch type {
        case .normal, .enemy, .catEye:
            self.pierceLimit = 1
        }

        let actualSpeed: CGFloat
        switch type {
        case .normal:
            actualSpeed = speed
        case .enemy:
            actualSpeed = speed * 0.65
        case .catEye:
            // Katzen-Laser nutzen die übergebene Geschwindigkeit direkt (Aufrufer gibt die halbe
            // Spielerschuss-Geschwindigkeit vor).
            actualSpeed = speed
        }
        
        self.velocity = CGPoint(
            x: actualSpeed * cos(angle),
            y: actualSpeed * sin(angle)
        )
        
        setupLaser()
    }
    
    /// Convenience initializer for backwards compatibility with Stage 3 tests.
    public convenience init(position: CGPoint, angle: CGFloat, speed: CGFloat, lifetime: TimeInterval) {
        self.init(position: position, angle: angle, type: .normal, speed: speed, lifetime: lifetime)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.type = .normal
        self.lifetime = 1.2
        super.init(coder: aDecoder)
        setupLaser()
    }
    
    // MARK: - Setup Helpers
    
    private func setupLaser() {
        let linePath = CGMutablePath()
        
        switch type {
        case .normal:
            // High-res yellow/amber line segment
            linePath.move(to: CGPoint(x: -6, y: 0))
            linePath.addLine(to: CGPoint(x: 6, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
            self.lineWidth = 2.0

        case .enemy:
            // Red warning line segment
            linePath.move(to: CGPoint(x: -5, y: 0))
            linePath.addLine(to: CGPoint(x: 5, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0)
            self.lineWidth = 2.0

        case .catEye:
            // Langer, dicker oranger Streifen – passend zu den glühenden Katzenaugen und bewusst
            // deutlich anders als der schmale rote UFO-Schuss und der gelbe Spielerschuss.
            linePath.move(to: CGPoint(x: -16, y: 0))
            linePath.addLine(to: CGPoint(x: 16, y: 0))
            self.path = linePath
            self.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1.0)
            self.lineWidth = 2.8
        }
        
        self.fillColor = .clear
        self.lineCap = .round
        VectorGlowRenderer.markStroke(self)
    }
    
    // MARK: - Update
    
    /// Updates the laser's position and lifetime.
    public func update(deltaTime: TimeInterval) -> Bool {
        let dt = CGFloat(deltaTime)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        
        elapsedTime += deltaTime
        return elapsedTime >= lifetime
    }
    
    /// Returns the world-space start and end points of the laser segment.
    public func getWorldSegment() -> (CGPoint, CGPoint) {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        
        let halfLength: CGFloat
        switch type {
        case .normal: halfLength = 6.0
        case .enemy: halfLength = 5.0
        case .catEye: halfLength = 16.0
        }
        
        let start = CGPoint(
            x: position.x - halfLength * cosTheta,
            y: position.y - halfLength * sinTheta
        )
        let end = CGPoint(
            x: position.x + halfLength * cosTheta,
            y: position.y + halfLength * sinTheta
        )
        return (start, end)
    }
    
    /// Wraps the laser around screen boundaries.
    public func wrapAround(screenSize: CGSize) {
        let halfWidth = screenSize.width / 2
        let halfHeight = screenSize.height / 2
        
        if position.x < -halfWidth {
            position.x += screenSize.width
        } else if position.x > halfWidth {
            position.x -= screenSize.width
        }
        
        if position.y < -halfHeight {
            position.y += screenSize.height
        } else if position.y > halfHeight {
            position.y -= screenSize.height
        }
    }
}
