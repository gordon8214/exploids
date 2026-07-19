import SpriteKit

/// A subclass of `SKShapeNode` representing the player's retro spaceship.
public final class Ship: SKShapeNode {
    
    // MARK: - Properties
    
    /// The ship's current velocity vector in points per second.
    public var velocity: CGPoint = .zero

    /// Akkumulierte Zeit (aus dt) für den rein optischen Schild-Puls. Deterministisch, damit der
    /// Gameplay-Pfad keine rohe Echtzeit (`systemUptime`) mehr liest.
    private var shieldPulseTime: TimeInterval = 0.0
    
    /// The maximum velocity speed clamp.
    public var maxVelocity: CGFloat = 350.0
    
    /// The thrust acceleration force in points per second squared.
    public var thrustAcceleration: CGFloat = 450.0
    
    /// The rotation speed in radians per second.
    public var rotationSpeed: CGFloat = 4.0
    
    /// The rate at which velocity decays per second (linear friction).
    /// A value of 0.85 means the velocity decays by 15% every second.
    public var frictionDecayRate: CGFloat = 0.85
    
    /// The local vertices defining the ship's outline shape.
    public let vertices: [CGPoint] = [
        CGPoint(x: 18, y: 0),
        CGPoint(x: -12, y: 10),
        CGPoint(x: -8, y: 0),
        CGPoint(x: -12, y: -10)
    ]
    
    /// The flame node visual effect at the rear of the ship.
    private let flameNode = SKShapeNode()

    /// Internes Darstellungsprofil; öffentliche Initializer und Standardfarben bleiben unverändert.
    private(set) var usesClassicAppearance = false
    
    /// The emitter node for particle-based thruster fire.
    private var thrusterEmitter: SKEmitterNode?
    
    // Shield Visual Elements – bis zu drei konzentrische Ringe, einer je Schild-Stufe.
    private let shieldRings: [SKShapeNode] = [SKShapeNode(), SKShapeNode(), SKShapeNode()]

    /// Schild-Stufe 0…3 = Anzahl der absorbierbaren tödlichen Treffer. Zeigt entsprechend viele Ringe.
    public var shieldLevel: Int = 0 {
        didSet {
            let lvl = max(0, min(shieldRings.count, shieldLevel))
            for (i, ring) in shieldRings.enumerated() {
                ring.isHidden = (i >= lvl)
            }
        }
    }

    /// Convenience: mindestens eine Schild-Stufe aktiv?
    public var isShieldActive: Bool { shieldLevel > 0 }

    public override var isHidden: Bool {
        didSet {
            if isHidden {
                flameNode.isHidden = true
                thrusterEmitter?.particleBirthRate = 0
                thrusterEmitter?.resetSimulation()
            }
        }
    }
    
    // MARK: - Initializer
    
    /// Initializes a new retro spaceship.
    public override init() {
        super.init()
        setupShip()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupShip()
    }
    
    // MARK: - Setup Helpers
    
    private func setupShip() {
        // Setup a sharp retro spaceship triangle outline path pointing along +x (right).
        let shipPath = CGMutablePath()
        if let first = vertices.first {
            shipPath.move(to: first)
            for pt in vertices.dropFirst() {
                shipPath.addLine(to: pt)
            }
            shipPath.closeSubpath()
        }
        
        self.path = shipPath
        self.strokeColor = .cyan
        self.fillColor = .clear
        self.lineWidth = 2.0
        self.lineJoin = .miter
        VectorGlowRenderer.markStroke(self)
        
        // Setup flame node path pointing backwards (left from the rear center indentation)
        let flamePath = CGMutablePath()
        flamePath.move(to: CGPoint(x: -8, y: 0))
        flamePath.addLine(to: CGPoint(x: -16, y: 5))
        flamePath.addLine(to: CGPoint(x: -24, y: 0))
        flamePath.addLine(to: CGPoint(x: -16, y: -5))
        flamePath.closeSubpath()
        
        flameNode.path = flamePath
        flameNode.strokeColor = .orange
        flameNode.fillColor = .clear
        flameNode.lineWidth = 1.5
        flameNode.isHidden = true
        VectorGlowRenderer.markStroke(flameNode)
        self.addChild(flameNode)
        
        // Setup Shield Nodes: drei konzentrische Ringe mit wachsendem Radius (innerster = Stufe 1).
        let shieldRadii: [CGFloat] = [28, 35, 42]
        for (i, ring) in shieldRings.enumerated() {
            let r = shieldRadii[i]
            ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            ring.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0 - CGFloat(i) * 0.22)
            ring.fillColor = (i == 0) ? SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.08) : .clear
            ring.lineWidth = 1.5
            ring.isHidden = true
            VectorGlowRenderer.markStroke(ring)
            self.addChild(ring)
        }
        
        // Setup emitter node for procedural particle thruster
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeParticleTexture()
        emitter.particleBirthRate = 0 // Started/stopped via isThrusting
        emitter.particleLifetime = 0.25
        emitter.particleLifetimeRange = 0.1
        emitter.particleSpeed = 200.0
        emitter.particleSpeedRange = 50.0
        emitter.emissionAngle = .pi // Pointing backwards from local ship space
        emitter.emissionAngleRange = 0.35 // about 20 degrees spread
        emitter.xAcceleration = 0
        emitter.yAcceleration = 0
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -2.0 // Shrunk to 0 quickly
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.0
        emitter.particleAlphaSpeed = -1.0 // Fade out
        emitter.particleColorBlendFactor = 1.0
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.yellow, SKColor.orange, SKColor.red, SKColor.clear],
            times: [0.0, 0.3, 0.7, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        
        emitter.position = CGPoint(x: -12, y: 0)
        self.thrusterEmitter = emitter
        self.addChild(emitter)
    }
    
    private func makeParticleTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        
        context.setFillColor(SKColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        
        let cgImage = context.makeImage()!
        return SKTexture(cgImage: cgImage)
    }

    /// Wechselt ausschließlich Darstellung und Arcade-Physikprofil. Beim Zurückschalten werden die
    /// bisherigen Exploids-Werte vollständig wiederhergestellt.
    func applyClassicProfile(_ enabled: Bool) {
        usesClassicAppearance = enabled
        if enabled {
            strokeColor = .white
            flameNode.strokeColor = .white
            thrusterEmitter?.particleBirthRate = 0
            maxVelocity = 480.0
            thrustAcceleration = 225.0
            rotationSpeed = 4.42
            frictionDecayRate = 0.79
        } else {
            strokeColor = .cyan
            flameNode.strokeColor = .orange
            maxVelocity = 350.0
            thrustAcceleration = 450.0
            rotationSpeed = 4.0
            frictionDecayRate = 0.85
        }
        VectorGlowRenderer.markStroke(self)
        VectorGlowRenderer.markStroke(flameNode)
    }
    
    // MARK: - Update & Physics
    
    /// Updates the spaceship's orientation, velocity, and position.
    public func update(deltaTime: TimeInterval, isThrusting: Bool, rotationInput: CGFloat) {
        let dt = CGFloat(deltaTime)
        // Akkumulierte Zeit (aus dt) für den optischen Schild-Puls – deterministisch statt rohem
        // systemUptime, damit im Gameplay-Pfad keine Echtzeit-Lesestelle mehr steckt.
        shieldPulseTime += deltaTime

        // 1. Update zRotation based on rotationInput and rotationSpeed
        zRotation += rotationInput * rotationSpeed * dt
        
        // 2. Add thrust acceleration if thrust is active
        if isThrusting {
            let accelX = thrustAcceleration * cos(zRotation)
            let accelY = thrustAcceleration * sin(zRotation)
            velocity.x += accelX * dt
            velocity.y += accelY * dt
            
            // Retro flickering flame effect (randomized size/scaling and color)
            // codereview-ok: Ship-Flacker (flameNode, rein optisch, keine Position/Velocity) per Plan-Doku bewusst vom Determinismus ausgenommen — by design (2026-07-01)
            flameNode.isHidden = false
            let randomScaleX = CGFloat.random(in: 0.7...1.3)
            let randomScaleY = CGFloat.random(in: 0.8...1.2)
            flameNode.xScale = randomScaleX
            flameNode.yScale = randomScaleY
            flameNode.strokeColor = usesClassicAppearance ? .white : (Bool.random() ? .orange : .red)
            
            // Enable particle emitter emission
            thrusterEmitter?.particleBirthRate = usesClassicAppearance ? 0 : 180
        } else {
            flameNode.isHidden = true
            thrusterEmitter?.particleBirthRate = 0
        }
        
        // Animate Shield Pulsing (alle sichtbaren Ringe)
        if isShieldActive {
            let pulse = 1.0 + 0.05 * sin(CGFloat(shieldPulseTime) * 6.0)
            for ring in shieldRings where !ring.isHidden {
                ring.xScale = pulse
                ring.yScale = pulse
            }
        }
        
        // Ensure particle target is the scene so they trail behind naturally
        if let emitter = thrusterEmitter, emitter.targetNode == nil, let scene = self.scene {
            emitter.targetNode = scene
        }
        
        // 3. Apply linear friction
        let frictionFactor = pow(frictionDecayRate, dt)
        velocity.x *= frictionFactor
        velocity.y *= frictionFactor
        
        // 4. Clamp maximum velocity
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if speed > maxVelocity {
            velocity.x = (velocity.x / speed) * maxVelocity
            velocity.y = (velocity.y / speed) * maxVelocity
        }
        
        // 5. Update position based on velocity
        position.x += velocity.x * dt
        position.y += velocity.y * dt
    }
    
    /// Wraps the spaceship around screen boundaries. (Gemeinsame Logik: VectorMath.swift)
    public func wrapAround(screenSize: CGSize) {
        wrapPositionAround(screenSize: screenSize)
    }
    
    /// Returns world-space coordinates of the ship's vertices.
    public func getWorldVertices() -> [CGPoint] {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        // Skalierung berücksichtigen, damit z.B. das Compress-Power-Up (Schiff auf ~30%) auch die
        // Kollisionsfläche schrumpft – nicht nur die Optik.
        return vertices.map { pt in
            let sx = pt.x * xScale
            let sy = pt.y * yScale
            return CGPoint(
                x: position.x + sx * cosTheta - sy * sinTheta,
                y: position.y + sx * sinTheta + sy * cosTheta
            )
        }
    }
    
    // MARK: - Drone Targeting helper
    
    /// Returns target positions for R-Type Options to follow the ship with a spacing offset.
    public func getOptionTargetPosition(index: Int, totalOptions: Int) -> CGPoint {
        let baseAngle = zRotation + .pi // Directly behind the ship
        let spacing: CGFloat = 38.0
        let angleOffset: CGFloat
        if totalOptions <= 1 {
            angleOffset = 0
        } else {
            let step = CGFloat.pi / 4.5
            angleOffset = (CGFloat(index) - CGFloat(totalOptions - 1) / 2.0) * step
        }
        let targetAngle = baseAngle + angleOffset
        return CGPoint(
            x: position.x + spacing * cos(targetAngle),
            y: position.y + spacing * sin(targetAngle)
        )
    }
}
