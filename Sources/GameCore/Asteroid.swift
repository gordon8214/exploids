import SpriteKit

/// A structure representing a 3D vector for asteroid vertices.
public struct Vector3D: Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    
    public init(x: CGFloat, y: CGFloat, z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// A subclass of `SKShapeNode` representing a procedurally generated retro asteroid with 3D wireframe rendering.
public final class Asteroid: SKShapeNode {
    
    /// Predefined size categories for asteroids.
    public enum AsteroidSize: CGFloat, CaseIterable, Sendable {
        case large = 40.0
        case medium = 20.0
        case small = 10.0
    }
    
    // MARK: - Properties
    
    /// The asteroid's current velocity vector in points per second.
    public var velocity: CGPoint = .zero
    
    /// The slow rotation speed in radians per second.
    public var angularVelocity: CGFloat = 0.0
    
    /// The size classification of this asteroid.
    public var sizeClass: AsteroidSize
    
    /// Whether this is an imploding type asteroid that collapses into a black hole when shot or grown.
    public let isImplodingType: Bool
    
    /// Whether this is a wobbling type asteroid that expands and detonates.
    public let isWobblingType: Bool
    
    /// The elapsed time in the current wobbling growth phase.
    public var timeInCurrentPhase: TimeInterval = 0.0

    /// Durchgehend akkumulierte Zeit (aus dt) nur für den optischen Wobble-Puls – deterministisch,
    /// damit der Asteroid-Zustand reproduzierbar bleibt (statt rohem `systemUptime`).
    private var wobbleTime: TimeInterval = 0.0
    
    /// The current phase index of the wobbling asteroid (0 = small, 1 = medium, 2 = large).
    public var wobblePhase: Int = 0
    
    /// The number of times this imploding asteroid has been shot by a player laser.
    public var hitCount: Int = 0

    /// Whether the asteroid has already been fully inside the visible screen at least once.
    /// Frisch gespawnte Asteroiden fliegen von außerhalb des Bildschirms herein. Solange das
    /// noch nicht passiert ist, darf `wrapAround()` sie NICHT an die gegenüberliegende Kante
    /// umklappen — sonst würden sie mitten im Bild erscheinen statt von der Kante einzufliegen.
    public var hasEnteredScreen: Bool = false
    
    /// The local vertices defining the 2D silhouette outline (used for background fill and collision).
    public private(set) var vertices: [CGPoint] = []
    
    // 3D Wireframe Properties
    private var local3DVertices: [Vector3D] = []
    private var edges: [(Int, Int)] = []
    private let wireframeNode = SKShapeNode()

    /// Classic Asteroids zeichnet nur die flache, ungefüllte Außenkontur. Das Profil ist intern,
    /// damit die öffentlichen Initializer stabil bleiben und Ancient/Mad weiterhin exakt denselben
    /// prozeduralen Aufbau (einschließlich RNG-Ziehungen) benutzen.
    private(set) var usesClassicAppearance = false
    
    // 3D rotation angles
    public var pitch: CGFloat = 0.0
    public var yaw: CGFloat = 0.0
    
    // 3D rotation velocities (radians per second)
    public var pitchVelocity: CGFloat = 0.0
    public var yawVelocity: CGFloat = 0.0
    
    // MARK: - Initializer
    
    /// Deterministischer Initializer: zieht ALLE Zufallswerte (Form, Geschwindigkeit, Spin) aus dem
    /// übergebenen `rng`. Das ist der Pfad, den das echte Spiel nutzt, damit ein Lauf bei gleichem
    /// Seed bit-genau reproduzierbar ist.
    public init(sizeClass: AsteroidSize = .large, isImplodingType: Bool = false, isWobblingType: Bool = false,
                using rng: inout GameRandom) {
        self.isImplodingType = isImplodingType
        self.isWobblingType = isWobblingType
        // Wobbling type always starts small
        self.sizeClass = isWobblingType ? .small : sizeClass
        super.init()
        setupAsteroid(using: &rng)
    }

    /// Convenience-Initializer ohne Seed für Tests/Editor-Vorschauen — würfelt aus dem System-RNG.
    /// NICHT im deterministischen Gameplay-Pfad verwenden (dafür den Initializer mit `using rng:`).
    public convenience init(sizeClass: AsteroidSize = .large, isImplodingType: Bool = false, isWobblingType: Bool = false) {
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        self.init(sizeClass: sizeClass, isImplodingType: isImplodingType, isWobblingType: isWobblingType, using: &throwaway)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.sizeClass = .large
        self.isImplodingType = false
        self.isWobblingType = false
        super.init(coder: aDecoder)
        // Archivierungs-Pfad ist nicht Teil des deterministischen Spiels → System-RNG genügt.
        var throwaway = GameRandom(seed: GameRandom.systemSeed())
        setupAsteroid(using: &throwaway)
    }

    // MARK: - Setup Helpers

    /// Lässt einen wobbelnden Asteroiden auf die nächste Größe wachsen und baut seine Form neu auf.
    /// Da das im Gameplay passiert, muss der `rng` durchgereicht werden (Determinismus).
    public func growToNextSize(newSize: AsteroidSize, using rng: inout GameRandom) {
        guard isWobblingType else { return }
        self.sizeClass = newSize
        setupAsteroid(using: &rng)
        self.xScale = 1.0
        self.yScale = 1.0
    }

    private func setupAsteroid(using rng: inout GameRandom) {
        let radius = sizeClass.rawValue
        
        // Reset 3D wireframe configuration arrays to allow clean re-generation when growing
        local3DVertices.removeAll()
        edges.removeAll()
        
        // 1. Setup 2D Silhouette (for backdrop and collision)
        let numVertices = Int.random(in: 8...12, using: &rng)
        var generatedPoints: [CGPoint] = []
        for i in 0..<numVertices {
            let angle = (CGFloat(i) / CGFloat(numVertices)) * 2.0 * .pi
            let perturbedRadius = radius * CGFloat.random(in: 0.75...1.25, using: &rng)
            let x = perturbedRadius * cos(angle)
            let y = perturbedRadius * sin(angle)
            generatedPoints.append(CGPoint(x: x, y: y))
        }
        self.vertices = generatedPoints
        
        let astPath = CGMutablePath()
        if let first = generatedPoints.first {
            astPath.move(to: first)
            for pt in generatedPoints.dropFirst() {
                astPath.addLine(to: pt)
            }
            astPath.closeSubpath()
            
            // Add concentric inner core line for imploding vector styling
            if isImplodingType {
                astPath.addEllipse(in: CGRect(x: -radius * 0.45, y: -radius * 0.45, width: radius * 0.9, height: radius * 0.9), transform: .identity)
            }
        }
        self.path = astPath
        
        // C-64 inspired styling: Translucent fill, outline color
        // Imploding ones have a distinct warm orange/magenta warning color
        // Wobbling ones have a bright neon red outline
        let strokeColor: SKColor
        if isImplodingType {
            strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0)
        } else if isWobblingType {
            strokeColor = SKColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
        } else {
            strokeColor = .white
        }
        
        self.strokeColor = strokeColor
        self.fillColor = SKColor(white: 0.15, alpha: 0.8)
        self.lineWidth = 2.0
        self.lineJoin = .miter
        VectorGlowRenderer.markStroke(self)
        
        // 2. Setup 3D Wireframe (perturbed icosahedron)
        let phi = (1.0 + sqrt(5.0)) / 2.0
        let len = sqrt(1.0 + phi * phi)
        let h = 1.0 / len
        let w = phi / len
        
        let unitVertices = [
            Vector3D(x: 0, y: h, z: w),
            Vector3D(x: 0, y: h, z: -w),
            Vector3D(x: 0, y: -h, z: w),
            Vector3D(x: 0, y: -h, z: -w),
            Vector3D(x: h, y: w, z: 0),
            Vector3D(x: h, y: -w, z: 0),
            Vector3D(x: -h, y: w, z: 0),
            Vector3D(x: -h, y: -w, z: 0),
            Vector3D(x: w, y: 0, z: h),
            Vector3D(x: w, y: 0, z: -h),
            Vector3D(x: -w, y: 0, z: h),
            Vector3D(x: -w, y: 0, z: -h)
        ]
        
        // Perturb 3D vertices
        self.local3DVertices = unitVertices.map { v in
            let perturbedRadius = radius * CGFloat.random(in: 0.75...1.25, using: &rng)
            return Vector3D(
                x: v.x * perturbedRadius,
                y: v.y * perturbedRadius,
                z: v.z * perturbedRadius
            )
        }
        
        // Generate edges dynamically (2 * h)
        let expectedDist = 2.0 * h
        for i in 0..<12 {
            for j in (i + 1)..<12 {
                let dx = unitVertices[i].x - unitVertices[j].x
                let dy = unitVertices[i].y - unitVertices[j].y
                let dz = unitVertices[i].z - unitVertices[j].z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                if abs(dist - expectedDist) < 0.01 {
                    self.edges.append((i, j))
                }
            }
        }
        
        // Configure wireframe child node
        wireframeNode.strokeColor = strokeColor
        wireframeNode.fillColor = .clear
        wireframeNode.lineWidth = 1.5
        wireframeNode.lineJoin = .round
        VectorGlowRenderer.markStroke(wireframeNode)
        if wireframeNode.parent == nil {
            self.addChild(wireframeNode)
        }
        
        // 3. Setup Velocities
        let randomSpeed = CGFloat.random(in: 40.0...100.0, using: &rng)
        let randomAngle = CGFloat.random(in: 0..<(2.0 * .pi), using: &rng)
        self.velocity = CGPoint(
            x: randomSpeed * cos(randomAngle),
            y: randomSpeed * sin(randomAngle)
        )
        
        // Spin velocities
        self.angularVelocity = CGFloat.random(in: -1.2...1.2, using: &rng)
        self.pitchVelocity = CGFloat.random(in: -1.0...1.0, using: &rng)
        self.yawVelocity = CGFloat.random(in: -1.0...1.0, using: &rng)
        
        // Draw the initial frame
        updateWireframePath()
    }

    /// Schaltet einen bereits deterministisch erzeugten Asteroiden auf eine von vier eigenständig
    /// entworfenen Classic-Konturfamilien um. Die Formen entstehen aus unterschiedlichen harmonischen
    /// Kurven statt aus historischen Koordinatentabellen.
    func applyClassicAppearance(family: Int) {
        usesClassicAppearance = true
        let radius = sizeClass.rawValue
        let familyIndex = ((family % 4) + 4) % 4
        let pointCount = 12
        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let angle = CGFloat(index) / CGFloat(pointCount) * 2.0 * .pi
            let radiusFactor: CGFloat
            switch familyIndex {
            case 0:
                radiusFactor = 0.88 + 0.17 * sin(angle * 3.0 + 0.35)
                    + 0.10 * cos(angle * 5.0 - 0.2)
            case 1:
                radiusFactor = 0.90 + 0.14 * cos(angle * 4.0 + 0.8)
                    - 0.12 * sin(angle * 2.0 - 0.45)
            case 2:
                radiusFactor = 0.87 + 0.16 * sin(angle * 5.0 - 0.7)
                    + 0.09 * cos(angle * 3.0 + 1.1)
            default:
                radiusFactor = 0.91 + 0.13 * cos(angle * 6.0 + 0.25)
                    - 0.11 * sin(angle * 3.0 + 0.55)
            }
            let clamped = min(1.16, max(0.66, radiusFactor))
            points.append(CGPoint(x: cos(angle) * radius * clamped,
                                  y: sin(angle) * radius * clamped))
        }

        vertices = points
        let outline = CGMutablePath()
        if let first = points.first {
            outline.move(to: first)
            points.dropFirst().forEach { outline.addLine(to: $0) }
            outline.closeSubpath()
        }
        path = outline
        strokeColor = .white
        fillColor = .clear
        lineWidth = 2.0
        lineJoin = .miter
        wireframeNode.isHidden = true
        VectorGlowRenderer.markStroke(self)
    }
    
    private func updateWireframePath() {
        let cosP = cos(pitch)
        let sinP = sin(pitch)
        let cosY = cos(yaw)
        let sinY = sin(yaw)
        
        // Project 3D vertices to 2D
        let projected = local3DVertices.map { v in
            let x1 = v.x
            let y1 = v.y * cosP - v.z * sinP
            let z1 = v.y * sinP + v.z * cosP
            
            let x2 = x1 * cosY + z1 * sinY
            let y2 = y1
            
            return CGPoint(x: x2, y: y2)
        }
        
        let path = CGMutablePath()
        
        // Draw outer 3D wireframe edges
        for (i, j) in edges {
            if i < projected.count, j < projected.count {
                path.move(to: projected[i])
                path.addLine(to: projected[j])
            }
        }
        
        // Draw secondary concentric inner 3D wireframe core for imploding types
        if isImplodingType {
            let innerProjected = projected.map { CGPoint(x: $0.x * 0.45, y: $0.y * 0.45) }
            for (i, j) in edges {
                if i < innerProjected.count, j < innerProjected.count {
                    path.move(to: innerProjected[i])
                    path.addLine(to: innerProjected[j])
                }
            }
        }
        
        wireframeNode.path = path
    }
    
    // MARK: - Updates
    
    /// Updates position and 3D rotation.
    public func update(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        zRotation += angularVelocity * dt
        
        pitch += pitchVelocity * dt
        yaw += yawVelocity * dt
        
        pitch = pitch.truncatingRemainder(dividingBy: 2.0 * .pi)
        yaw = yaw.truncatingRemainder(dividingBy: 2.0 * .pi)

        if isWobblingType {
            timeInCurrentPhase += deltaTime
            // wobble scale oscillates between 0.85 and 1.15 scale.
            // Gegen die akkumulierte `wobbleTime` (aus dt) statt gegen Echtzeit rechnen, damit der
            // Asteroid-Zustand deterministisch bleibt (Replay) – und dennoch ein durchgehender,
            // phasenübergreifender Puls entsteht (nicht der pro Phase zurückgesetzte timeInCurrentPhase).
            wobbleTime += deltaTime
            let wobbleScale = 1.0 + 0.15 * sin(CGFloat(wobbleTime * 18.0))
            self.xScale = wobbleScale
            self.yScale = wobbleScale
        }
        // Der (teure) SKShapeNode-Path-Neuaufbau passiert NICHT mehr hier pro Sim-Schritt, sondern
        // einmal pro gerendertem Bild über `refreshWireframe()` (aufgerufen vom Host bzw. Renderer).
        // Bei 120 Hz Sim / 60 Hz Bild halbiert das die Path-Rebuilds; rein visuell, kein Sim-Einfluss.
    }

    /// Baut den 3D-projizierten Drahtgitter-Pfad aus dem aktuellen `pitch`/`yaw` neu auf. Rein
    /// visuell (kein Kollisions-/Sim-State) — wird einmal pro gerendertem Bild aufgerufen, nicht
    /// pro Simulationsschritt (siehe `update(deltaTime:)`).
    public func refreshWireframe() {
        guard !usesClassicAppearance else { return }
        updateWireframePath()
    }
    
    /// Wraps the asteroid around screen boundaries. (Gemeinsame Wrap-Logik: VectorMath.swift)
    public func wrapAround(screenSize: CGSize) {
        // Solange der Asteroid noch von außen hereinfliegt (Mittelpunkt außerhalb des
        // sichtbaren Rechtecks), NICHT umklappen. Erst wenn sein Mittelpunkt einmal im Bild
        // war, gilt er als "eingetreten" und nimmt danach normal am Kanten-Umlauf teil.
        if !hasEnteredScreen {
            let halfWidth = screenSize.width / 2
            let halfHeight = screenSize.height / 2
            let centerInside = position.x >= -halfWidth && position.x <= halfWidth
                && position.y >= -halfHeight && position.y <= halfHeight
            if centerInside {
                hasEnteredScreen = true
            }
            return
        }

        wrapPositionAround(screenSize: screenSize)
    }
    
    /// Returns world-space coordinates of the 2D silhouette vertices (correctly transformed by scale).
    public func getWorldVertices() -> [CGPoint] {
        let cosTheta = cos(zRotation)
        let sinTheta = sin(zRotation)
        let scaleX = xScale
        let scaleY = yScale
        return vertices.map { pt in
            CGPoint(
                x: position.x + (pt.x * scaleX) * cosTheta - (pt.y * scaleY) * sinTheta,
                y: position.y + (pt.x * scaleX) * sinTheta + (pt.y * scaleY) * cosTheta
            )
        }
    }
}
