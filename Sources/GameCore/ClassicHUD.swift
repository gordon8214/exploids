import SpriteKit

/// Kleine, assetfreie Vektorschrift fuer das Classic-HUD. Die Zeichen werden aus wenigen
/// Liniensegmenten aufgebaut, damit Punktzahl und Wellenanzeige wie Teile derselben
/// Vektoranzeige wirken und nicht wie aufgesetzte Bitmap-Schrift.
final class ClassicVectorTextNode: SKShapeNode {
    enum Alignment {
        case left
        case center
        case right
    }

    private let glyphHeight: CGFloat
    private let alignment: Alignment
    private let glyphWidth: CGFloat
    private let glyphSpacing: CGFloat

    private(set) var renderedText = ""
    private(set) var renderedWidth: CGFloat = 0

    init(glyphHeight: CGFloat, alignment: Alignment) {
        self.glyphHeight = glyphHeight
        self.alignment = alignment
        let unit = glyphHeight / 6.0
        self.glyphWidth = unit * 4.0
        self.glyphSpacing = unit * 2.0
        super.init()

        strokeColor = .white
        fillColor = .clear
        lineWidth = 1.5
        lineCap = .round
        lineJoin = .miter
        VectorGlowRenderer.markStroke(self)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("ClassicVectorTextNode wird nur programmatisch erzeugt")
    }

    func updateText(_ text: String) {
        guard renderedText != text else { return }
        renderedText = text

        let characterCount = text.count
        renderedWidth = characterCount > 0
            ? CGFloat(characterCount) * glyphWidth + CGFloat(characterCount - 1) * glyphSpacing
            : 0

        let horizontalOffset: CGFloat
        switch alignment {
        case .left: horizontalOffset = 0
        case .center: horizontalOffset = -renderedWidth / 2.0
        case .right: horizontalOffset = -renderedWidth
        }

        let unit = glyphHeight / 6.0
        let advance = glyphWidth + glyphSpacing
        let vectorPath = CGMutablePath()
        for (index, character) in text.enumerated() {
            let characterOffset = horizontalOffset + CGFloat(index) * advance
            for stroke in strokes(for: character) {
                guard let first = stroke.first else { continue }
                vectorPath.move(to: CGPoint(
                    x: characterOffset + first.x * unit,
                    y: first.y * unit
                ))
                for point in stroke.dropFirst() {
                    vectorPath.addLine(to: CGPoint(
                        x: characterOffset + point.x * unit,
                        y: point.y * unit
                    ))
                }
            }
        }
        path = vectorPath
    }

    /// Einheitliche 4x6-Segmentzeichen. Nur die fuer Classic benoetigten Ziffern und
    /// Buchstaben sind absichtlich enthalten; unbekannte Zeichen belegen lediglich ihren Platz.
    private func strokes(for character: Character) -> [[CGPoint]] {
        switch character {
        case "0":
            return [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 6),
                     CGPoint(x: 4, y: 6), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 0)]]
        case "1":
            return [[CGPoint(x: 1, y: 5), CGPoint(x: 2, y: 6), CGPoint(x: 2, y: 0)]]
        case "2":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 4, y: 6), CGPoint(x: 4, y: 3),
                     CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)]]
        case "3":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 4, y: 6), CGPoint(x: 4, y: 0),
                     CGPoint(x: 0, y: 0)],
                    [CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]]
        case "4":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)],
                    [CGPoint(x: 4, y: 6), CGPoint(x: 4, y: 0)]]
        case "5":
            return [[CGPoint(x: 4, y: 6), CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 3),
                     CGPoint(x: 4, y: 3), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 0)]]
        case "6":
            return [[CGPoint(x: 4, y: 6), CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 0),
                     CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)]]
        case "7":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 4, y: 6), CGPoint(x: 1, y: 0)]]
        case "8":
            return [[CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 6), CGPoint(x: 4, y: 6),
                     CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3),
                     CGPoint(x: 4, y: 3)]]
        case "9":
            return [[CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 6),
                     CGPoint(x: 4, y: 6), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 0)]]
        case "A":
            return [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 4), CGPoint(x: 2, y: 6),
                     CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 0)],
                    [CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]]
        case "E":
            return [[CGPoint(x: 4, y: 6), CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 0),
                     CGPoint(x: 4, y: 0)],
                    [CGPoint(x: 0, y: 3), CGPoint(x: 3, y: 3)]]
        case "V":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 2, y: 0), CGPoint(x: 4, y: 6)]]
        case "W":
            return [[CGPoint(x: 0, y: 6), CGPoint(x: 0.8, y: 0), CGPoint(x: 2, y: 3),
                     CGPoint(x: 3.2, y: 0), CGPoint(x: 4, y: 6)]]
        default:
            return []
        }
    }
}

/// Atari-inspiriertes HUD, das ausschliesslich im laufenden Classic-Modus sichtbar ist.
/// Seine Koordinaten beziehen sich auf die feste, zentrierte 1024x768-Arena.
final class ClassicHUDNode: SKNode {
    static let scorePosition = CGPoint(x: -412, y: 356)
    static let highScorePosition = CGPoint(x: 0, y: 366)
    static let wavePosition = CGPoint(x: 412, y: 366)
    static let livesPosition = CGPoint(x: -352, y: 340)
    static let lifeSpacing: CGFloat = 20

    let scoreNode = ClassicVectorTextNode(glyphHeight: 24, alignment: .left)
    let highScoreNode = ClassicVectorTextNode(glyphHeight: 14, alignment: .center)
    let waveNode = ClassicVectorTextNode(glyphHeight: 14, alignment: .right)
    let livesNode = SKNode()

    private(set) var shipsDisplayed = 0

    override init() {
        super.init()
        zPosition = 100
        isHidden = true

        scoreNode.name = "classicHUDScore"
        scoreNode.position = Self.scorePosition
        addChild(scoreNode)

        highScoreNode.name = "classicHUDHighScore"
        highScoreNode.position = Self.highScorePosition
        addChild(highScoreNode)

        waveNode.name = "classicHUDWave"
        waveNode.position = Self.wavePosition
        addChild(waveNode)

        livesNode.name = "classicHUDLives"
        livesNode.position = Self.livesPosition
        addChild(livesNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("ClassicHUDNode wird nur programmatisch erzeugt")
    }

    var lifeIconNodes: [SKShapeNode] {
        livesNode.children.compactMap { $0 as? SKShapeNode }
    }

    func update(score: Int, highScore: Int, wave: Int, shipsRemaining: Int) {
        updateScore(score)
        updateHighScore(highScore)
        updateWave(wave)
        updateShips(shipsRemaining)
    }

    func updateScore(_ score: Int) {
        scoreNode.updateText(Self.formattedScore(score))
    }

    func updateHighScore(_ highScore: Int) {
        highScoreNode.updateText(Self.formattedScore(highScore))
    }

    func updateWave(_ wave: Int) {
        waveNode.updateText("WAVE \(max(1, wave))")
    }

    func updateShips(_ shipsRemaining: Int) {
        let count = max(0, shipsRemaining)
        guard shipsDisplayed != count else { return }
        shipsDisplayed = count
        livesNode.removeAllChildren()

        for index in 0..<count {
            let icon = SKShapeNode(path: makeLifeIconPath())
            icon.name = "classicHUDLife"
            icon.position = CGPoint(x: CGFloat(index) * Self.lifeSpacing, y: 0)
            icon.strokeColor = .white
            icon.fillColor = .clear
            icon.lineWidth = 1.5
            icon.lineCap = .round
            icon.lineJoin = .miter
            VectorGlowRenderer.markStroke(icon)
            livesNode.addChild(icon)
        }
    }

    static func formattedScore(_ score: Int) -> String {
        let nonnegativeScore = max(0, score)
        return nonnegativeScore == 0 ? "00" : String(nonnegativeScore)
    }

    /// Verwendet dieselbe Exploids-Kontur wie das aktive Schiff, dreht sie nach oben und
    /// skaliert sie auf die bereits etablierte Classic-Huellkurve von 16x24 Punkten.
    private func makeLifeIconPath() -> CGPath {
        let iconPath = CGMutablePath()
        let rotatedVertices = Ship.outlineVertices.map { vertex in
            let scaled = CGPoint(
                x: vertex.x * ClassicGeometry.shipBodyScale,
                y: vertex.y * ClassicGeometry.shipBodyScale
            )
            return CGPoint(x: -scaled.y, y: scaled.x)
        }
        if let first = rotatedVertices.first {
            iconPath.move(to: first)
            for vertex in rotatedVertices.dropFirst() {
                iconPath.addLine(to: vertex)
            }
            iconPath.closeSubpath()
        }
        return iconPath
    }
}
