import CoreGraphics
import Foundation

/// Ein vorzeichenbehafteter Arcade-Vektor mit drei Nachkommabits.
struct ClassicRawVector: Equatable {
    let x: Int
    let y: Int

    var magnitude: CGFloat {
        hypot(CGFloat(x), CGFloat(y))
    }
}

/// Vollständige, bereits auf die aktuelle Szenengröße abgebildete Ballistik eines Classic-Schusses.
struct ClassicProjectileCalibration {
    let angleByte: UInt8
    let baseVelocity: ClassicRawVector
    let inheritedVelocity: ClassicRawVector
    let clampedVelocity: ClassicRawVector
    let spawnOffsetRaw: ClassicRawVector
    let movementFrames: Int
    let lifetime: TimeInterval
    let velocity: CGPoint
    let spawnOffset: CGPoint

    var canonicalTravelDistance: CGFloat {
        clampedVelocity.magnitude * CGFloat(movementFrames) / ClassicProjectileCalibrator.fixedPointScale
    }

    var canonicalSpawnOffsetDistance: CGFloat {
        spawnOffsetRaw.magnitude / ClassicProjectileCalibrator.fixedPointScale
    }
}

/// Rekonstruiert nur die Zahlenregeln der Atari-Schüsse. Die Flugrichtung selbst bleibt bewusst
/// glatt, damit Exploids' kontinuierliche Steuerung erhalten bleibt; Quellwinkel und Fixed-Point-
/// Werte bestimmen dagegen Geschwindigkeit, Lebensdauer, Offset, Vererbung und Clamp.
enum ClassicProjectileCalibrator {
    static let arcadeFramesPerSecond: TimeInterval = 62.5
    static let displayFrameDuration: TimeInterval = 1.0 / arcadeFramesPerSecond
    static let fixedPointScale: CGFloat = 8.0
    static let canonicalArenaSize = CGSize(width: 1024.0, height: 768.0)
    static let saucerMovementFrames = 69

    private static let angleCount = 256
    private static let trigAmplitude: CGFloat = 127.0
    private static let maximumVelocityComponent = 0x6F
    /// Die vorhandenen Classic-Schiffs- und Untertassengeschwindigkeiten wurden in 60-Hz-
    /// Quellschritte übersetzt. Erst der fertige Projektilvektor läuft mit dem echten 62,5-Hz-Takt.
    private static let inheritedVelocityFramesPerSecond: CGFloat = 60.0

    /// FIRE3 startet bei $12 und dekrementiert nur bei `FRAME & 3 == 0`. Weil die Bewegung vor
    /// diesem Test stattfindet, ergeben die vier möglichen Startphasen genau diese Bildzahlen.
    static func playerMovementFrames(forLaunchPhase phase: Int) -> Int {
        switch phase & 3 {
        case 0: return 69
        case 1: return 72
        case 2: return 71
        default: return 70
        }
    }

    static func angleByte(for angle: CGFloat) -> UInt8 {
        let fullTurn = 2.0 * CGFloat.pi
        let wrapped = angle.truncatingRemainder(dividingBy: fullTurn)
        let sourceUnits = Int((wrapped / fullTurn * CGFloat(angleCount)).rounded())
        return UInt8(truncatingIfNeeded: sourceUnits)
    }

    static func baseVelocity(for angleByte: UInt8) -> ClassicRawVector {
        let angle = CGFloat(angleByte) * 2.0 * .pi / CGFloat(angleCount)
        let cosine = Int((trigAmplitude * cos(angle)).rounded())
        let sine = Int((trigAmplitude * sin(angle)).rounded())
        // Swifts Shift auf vorzeichenbehafteten Ints ist arithmetisch und bildet damit Ataris
        // halbierten 8-Bit-Sinus inklusive der Asymmetrie +63/-64 nach.
        return ClassicRawVector(x: cosine >> 1, y: sine >> 1)
    }

    static func inheritedVelocity(for velocity: CGPoint) -> ClassicRawVector {
        ClassicRawVector(
            x: inheritedComponent(for: velocity.x),
            y: inheritedComponent(for: velocity.y)
        )
    }

    static func calibrate(angle: CGFloat, shooterVelocity: CGPoint, arenaSize: CGSize,
                          movementFrames: Int) -> ClassicProjectileCalibration {
        let quantizedAngle = angleByte(for: angle)
        let base = baseVelocity(for: quantizedAngle)
        let inherited = inheritedVelocity(for: shooterVelocity)
        let clamped = ClassicRawVector(
            x: clampVelocity(base.x + inherited.x),
            y: clampVelocity(base.y + inherited.y)
        )
        let spawnRaw = ClassicRawVector(
            x: base.x + (base.x >> 1),
            y: base.y + (base.y >> 1)
        )

        let sceneScaleX = arenaSize.width > 0
            ? arenaSize.width / canonicalArenaSize.width
            : 1.0
        let sceneScaleY = arenaSize.height > 0
            ? arenaSize.height / canonicalArenaSize.height
            : 1.0

        // Richtung wie bisher: glatter Zielwinkel plus kontinuierliche Schützenbewegung. Nur wenn
        // sich beides exakt aufhebt, liefert der diskrete Atari-Vektor eine stabile Ersatzrichtung.
        let smoothVector = CGPoint(
            x: ClassicTuning.playerShotSpeed * cos(angle) + shooterVelocity.x,
            y: ClassicTuning.playerShotSpeed * sin(angle) + shooterVelocity.y
        )
        let sourceFallback = CGPoint(
            x: CGFloat(clamped.x) * sceneScaleX,
            y: CGFloat(clamped.y) * sceneScaleY
        )
        let baseFallback = CGPoint(
            x: cos(angle) * sceneScaleX,
            y: sin(angle) * sceneScaleY
        )
        let direction = unitVector(for: smoothVector)
            ?? unitVector(for: sourceFallback)
            ?? unitVector(for: baseFallback)
            ?? CGPoint(x: 1.0, y: 0.0)

        // Ein Weg von `r` kanonischen Punkten wird entlang der beibehaltenen Szenenrichtung so
        // skaliert, dass sqrt((dx/sx)^2 + (dy/sy)^2) weiterhin exakt `r` ergibt.
        let referenceMetric = hypot(direction.x / sceneScaleX, direction.y / sceneScaleY)
        let scenePointsPerCanonicalPoint = referenceMetric > 0 ? 1.0 / referenceMetric : 1.0
        let canonicalSpeed = clamped.magnitude / fixedPointScale
            * CGFloat(arcadeFramesPerSecond)
        let sceneSpeed = canonicalSpeed * scenePointsPerCanonicalPoint
        let canonicalSpawnOffset = spawnRaw.magnitude / fixedPointScale
        let sceneSpawnOffset = canonicalSpawnOffset * scenePointsPerCanonicalPoint
        let lifetime = TimeInterval(movementFrames) / arcadeFramesPerSecond

        return ClassicProjectileCalibration(
            angleByte: quantizedAngle,
            baseVelocity: base,
            inheritedVelocity: inherited,
            clampedVelocity: clamped,
            spawnOffsetRaw: spawnRaw,
            movementFrames: movementFrames,
            lifetime: lifetime,
            velocity: CGPoint(x: direction.x * sceneSpeed, y: direction.y * sceneSpeed),
            spawnOffset: CGPoint(
                x: direction.x * sceneSpawnOffset,
                y: direction.y * sceneSpawnOffset
            )
        )
    }

    private static func inheritedComponent(for velocity: CGFloat) -> Int {
        Int(floor(velocity * fixedPointScale / inheritedVelocityFramesPerSecond))
    }

    private static func clampVelocity(_ value: Int) -> Int {
        min(maximumVelocityComponent, max(-maximumVelocityComponent, value))
    }

    private static func unitVector(for vector: CGPoint) -> CGPoint? {
        let length = hypot(vector.x, vector.y)
        guard length > 1e-9 else { return nil }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
}
