// OptionDrone.swift — der R-Type-artige Options-Drohnen-Knoten (Begleiter des Schiffs).
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert
// (nur Zugriff von private auf internal gelockert, da jetzt eigene Datei).

import SpriteKit

/// A helper node representing an R-Type Option drone.
final class OptionDrone: SKShapeNode {
    override init() {
        super.init()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5, y: 0))
        path.addLine(to: CGPoint(x: -3, y: 3))
        path.addLine(to: CGPoint(x: -2, y: 0))
        path.addLine(to: CGPoint(x: -3, y: -3))
        path.closeSubpath()
        self.path = path
        self.strokeColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        self.fillColor = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.1)
        self.lineWidth = 1.5
        VectorGlowRenderer.markStroke(self)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
