import SpriteKit

/// A subclass of `SKShapeNode` representing a gravitational singularity (black hole) that pulls entities towards it.
public final class GravityWell: SKShapeNode {
    
    // MARK: - Properties
    
    /// The strength coefficient for the gravitational pull.
    public let gravityStrength: CGFloat
    
    /// Radius of the core singularity. Touching this triggers instant destruction.
    /// 20 % kleiner als zuvor (22.0) – schwarze Löcher waren zu schwer.
    public let eventHorizonRadius: CGFloat = 17.6

    /// Maximum range of gravitational influence.
    /// Reichweite um 20 % reduziert (war 360.0), passend zum 20 % kleineren Loch.
    public let influenceRadius: CGFloat = 288.0
    
    /// The total duration this black hole exists.
    public let lifetime: TimeInterval
    
    /// The elapsed time since spawning.
    public private(set) var elapsedTime: TimeInterval = 0.0
    
    // Child node for the swirling vortex lines
    private let vortexNode = SKShapeNode()
    
    // MARK: - Initializer
    
    public init(strength: CGFloat = 320000.0, lifetime: TimeInterval = 18.0) {
        self.gravityStrength = strength
        self.lifetime = lifetime
        super.init()
        setupGravityWell()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.gravityStrength = 320000.0
        self.lifetime = 18.0
        super.init(coder: aDecoder)
        setupGravityWell()
    }
    
    // MARK: - Setup
    
    private func setupGravityWell() {
        // 1. Core singularity representation (dark event horizon)
        let corePath = CGPath(ellipseIn: CGRect(x: -eventHorizonRadius, y: -eventHorizonRadius, width: eventHorizonRadius * 2, height: eventHorizonRadius * 2), transform: nil)
        self.path = corePath
        self.strokeColor = .white
        self.fillColor = .black
        self.lineWidth = 2.0
        VectorGlowRenderer.markStroke(self)
        
        // 2. Swirling spiral arms (influence boundary)
        let spiralPath = CGMutablePath()
        let numArms = 5
        let steps = 40
        let maxVisualRadius: CGFloat = 88.0   // 20 % kleiner (war 110.0)
        
        for arm in 0..<numArms {
            let baseAngle = (CGFloat(arm) / CGFloat(numArms)) * 2.0 * .pi
            for step in 0..<steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let r = eventHorizonRadius + progress * (maxVisualRadius - eventHorizonRadius)
                // Spiral formula: angle increments with radius
                let angle = baseAngle + progress * 3.0 * .pi
                let x = r * cos(angle)
                let y = r * sin(angle)
                
                if step == 0 {
                    spiralPath.move(to: CGPoint(x: x, y: y))
                } else {
                    spiralPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        
        vortexNode.path = spiralPath
        // Glowing space violet / purple
        vortexNode.strokeColor = SKColor(red: 0.6, green: 0.1, blue: 1.0, alpha: 0.8)
        vortexNode.fillColor = .clear
        vortexNode.lineWidth = 1.5
        VectorGlowRenderer.markStroke(vortexNode)
        self.addChild(vortexNode)
        
        // Setup initial fade-in animation
        self.alpha = 0.0
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 2.0)
        self.run(fadeIn)
    }
    
    // MARK: - Update
    
    /// Updates lifetime and rotates the vortex.
    /// - Returns: `true` if the gravity well should explode/collapse, otherwise `false`.
    public func update(deltaTime: TimeInterval) -> Bool {
        elapsedTime += deltaTime
        let dt = CGFloat(deltaTime)
        
        // Vortex swirls counter-clockwise
        vortexNode.zRotation += 2.0 * dt
        
        // Handle collapse / fade-out in final 2 seconds
        if elapsedTime >= lifetime - 2.0 {
            if self.action(forKey: "fadeOut") == nil {
                let fadeOut = SKAction.fadeAlpha(to: 0.0, duration: 2.0)
                self.run(fadeOut, withKey: "fadeOut")
            }
        }
        
        return elapsedTime >= lifetime
    }
    
    // MARK: - Physics Math
    
    /// Calculates the gravitational acceleration pull vector acting on an entity at a given position.
    /// Uses a smoothed inverse-squared-distance gravity calculation.
    public func calculatePull(on entityPosition: CGPoint) -> CGPoint {
        // Do not pull if the black hole has faded out
        guard elapsedTime < lifetime - 1.0 else { return .zero }
        
        let dx = self.position.x - entityPosition.x
        let dy = self.position.y - entityPosition.y
        let distSq = dx * dx + dy * dy
        let distance = sqrt(distSq)
        
        // Only pull if within influence bounds and outside the event horizon core
        guard distance > eventHorizonRadius, distance < influenceRadius else { return .zero }
        
        // Inverse-squared-distance gravity calculation: a = G / r^2
        // Hinweis: der guard oben stellt sicher, dass distance > eventHorizonRadius gilt,
        // daher ist min(eventHorizonRadius, distance) immer gleich distance — kein max nötig.
        let accelerationMagnitude = gravityStrength / (distance * distance)
        
        return CGPoint(
            x: accelerationMagnitude * (dx / distance),
            y: accelerationMagnitude * (dy / distance)
        )
    }
}
