import Foundation
import SpriteKit

/// Persistiert ausschließlich die vom Spieler gewählte HDR-Glow-Präferenz. Ob das aktuelle
/// Display den Modus tatsächlich darstellen kann, bleibt Sache der jeweiligen App-Shell.
enum HDRGlowPreferenceStore {
    static let key = "exploids_hdr_glow_enabled"

    static func load() -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}

/// Gemeinsamer SpriteKit-Shader für die hellen Vektorlinien. Die Shell liefert pro Renderbild
/// den aktuell nutzbaren EDR-Headroom; Gameplay und Replaydaten bleiben davon vollständig getrennt.
@MainActor
enum VectorGlowRenderer {
    static let maximumHeadroom: CGFloat = 3.0

    private static let strokeMarker = "exploids_vector_glow_stroke"
    private static let fillMarker = "exploids_vector_glow_fill"
    private static let uniformName = "u_hdrHeadroom"

    private static let shaderSource = """
    void main() {
        vec4 shaded = SKDefaultShading();
        gl_FragColor = vec4(shaded.rgb * u_hdrHeadroom, shaded.a);
    }
    """

    private static let strokeHeadroom = SKUniform(name: uniformName, float: 1.0)
    private static let fillHeadroom = SKUniform(name: uniformName, float: 1.0)
    private static let strokeShader = SKShader(source: shaderSource, uniforms: [strokeHeadroom])
    private static let fillShader = SKShader(source: shaderSource, uniforms: [fillHeadroom])

    private(set) static var isActive = false
    private(set) static var currentHeadroom: CGFloat = 1.0

    /// Kennzeichnet einen Knoten als leuchtende Vektorkontur. Der Marker bleibt auch im SDR-Modus
    /// erhalten, während der Shader dann vollständig entfernt wird. Linienbreite und Glow bleiben
    /// absichtlich unangetastet, damit HDR die Geometrie und das Treffergefühl nicht verändert.
    static func markStroke(_ node: SKShapeNode) {
        metadata(for: node)[strokeMarker] = true
        applyCurrentState(to: node)
    }

    /// Kennzeichnet eine bewusst emissive, deckende Füllung. Transparente Innenflächen dürfen
    /// diese Markierung nicht bekommen, damit sie weder heller noch milchig werden.
    static func markFill(_ node: SKShapeNode) {
        metadata(for: node)[fillMarker] = true
        applyCurrentState(to: node)
    }

    /// Aktualisiert die beiden gemeinsamen Uniforms pro Renderbild. Ein Szenengraph-Durchlauf ist
    /// nur beim Wechsel SDR↔HDR nötig; der dynamische Headroom selbst kostet keine Node-Iteration.
    static func update(in root: SKNode, active: Bool, headroom: CGFloat) {
        let effectiveHeadroom = active
            ? min(max(1.0, headroom), maximumHeadroom)
            : 1.0
        strokeHeadroom.floatValue = Float(effectiveHeadroom)
        fillHeadroom.floatValue = Float(effectiveHeadroom)
        currentHeadroom = effectiveHeadroom

        guard active != isActive else { return }
        isActive = active
        refreshMarkedNodes(in: root)
    }

    static func isStrokeMarked(_ node: SKShapeNode) -> Bool {
        node.userData?[strokeMarker] as? Bool == true
    }

    static func isFillMarked(_ node: SKShapeNode) -> Bool {
        node.userData?[fillMarker] as? Bool == true
    }

    private static func metadata(for node: SKShapeNode) -> NSMutableDictionary {
        if let data = node.userData { return data }
        let data = NSMutableDictionary()
        node.userData = data
        return data
    }

    private static func refreshMarkedNodes(in node: SKNode) {
        if let shape = node as? SKShapeNode {
            applyCurrentState(to: shape)
        }
        for child in node.children {
            refreshMarkedNodes(in: child)
        }
    }

    private static func applyCurrentState(to node: SKShapeNode) {
        let strokeMarked = isStrokeMarked(node)
        let fillMarked = isFillMarked(node)

        node.strokeShader = strokeMarked && isActive ? strokeShader : nil
        node.fillShader = fillMarked && isActive ? fillShader : nil
    }
}
