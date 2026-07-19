import AppKit
import SpriteKit
import QuartzCore
import Metal
import GameCore

/// A custom NSWindow subclass that hosts the SpriteKit rendering view.
@MainActor
public final class GameWindow: NSWindow, @preconcurrency SKViewDelegate {

    private let gameView: SKView
    private let gameScene: GameScene
    private var hdrSurfaceConfigured = false

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

        let gameView = SKView(frame: contentRect)
        let gameScene = GameScene(size: contentRect.size)
        self.gameView = gameView
        self.gameScene = gameScene

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        self.title = "Exploids"
        self.center()
        self.minSize = NSSize(width: 800, height: 600)
        
        // Apply modern macOS dark aqua appearance to the window
        self.appearance = NSAppearance(named: .darkAqua)
        
        // Initialize SKView to enable SpriteKit rendering
        gameView.autoresizingMask = [.width, .height]
        
        // Show diagnostic overlays for development verification
        gameView.showsFPS = true
        gameView.showsNodeCount = true

        // Früh als Content-View einsetzen, damit die HDR-Erkennung den Bildschirm des echten
        // Fensters (und nicht pauschal NSScreen.main) abfragen kann.
        self.contentView = gameView
        
        // Set up the GameScene as the content
        let scene = gameScene
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        scene.autoFire = true   // Auto-Feuer standardmäßig an (Spieler müssen nicht selbst schießen)
        // Attract-/Demo-Modus in der echten App aktivieren: nach 30 s Leerlauf am Startbildschirm
        // (oder auf Taste „D") spielt ein Autopilot eine Demo; danach 10 s Highscore-Liste + 15 s
        // Startbildschirm, dann die nächste Persona – immer weiter.
        scene.attractModeEnabled = true
        // Fixed-Timestep: nach einem Hänger (Fenster-Drag, App im Hintergrund) höchstens 0.25 s
        // Echtzeit als Sim-Schritte nachholen, statt die ganze Pause aufzuarbeiten.
        scene.maxFrameDelta = 0.25
        // Aufnahme jedes Laufs bei Game Over ins Archiv schreiben (für GIF-Erstellung, auch ohne
        // Highscore). Siehe Main.replayArchiveDirectory() + die --render-last-replay-CLI.
        scene.replaySaveDirectory = Main.replayArchiveDirectory()
        // Cmd+Q über die Scene an AppKit weiterreichen: GameCore ist plattformunabhängig und kennt
        // NSApplication nicht mehr; die macOS-Shell legt hier das Beenden-Verhalten fest.
        scene.onQuit = { NSApplication.shared.terminate(nil) }
        scene.onHDRGlowPreferenceChanged = { [weak self] _ in
            self?.refreshHDRDisplay()
        }

        // SpriteKit rendert weiter selbst; der Delegate aktualisiert nur den dynamischen Headroom
        // unmittelbar vor jedem Bild und lässt jeden Renderdurchlauf normal passieren.
        gameView.delegate = self
        refreshHDRDisplay()
        gameView.presentScene(scene)

        // Die SKView als First Responder verankern, damit Tastatur-Events zuverlässig die Scene
        // erreichen (auch nachdem das Fenster den Fokus verloren und wieder erhalten hat).
        self.initialFirstResponder = gameView
        self.makeFirstResponder(gameView)
    }

    /// Prüft immer den Bildschirm, auf dem sich das Fenster gerade befindet. Das deckt neben
    /// Helligkeitsänderungen auch das Verschieben zwischen SDR- und HDR-Monitoren ohne Neustart ab.
    private func refreshHDRDisplay() {
        guard let metalLayer = gameView.layer as? CAMetalLayer,
              metalLayer.device != nil,
              let display = gameView.window?.screen ?? self.screen ?? NSScreen.main else {
            gameScene.updateHDRDisplay(available: false, currentHeadroom: 1.0)
            return
        }

        let displaySupportsHDR = display.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
        if displaySupportsHDR && !hdrSurfaceConfigured,
           let extendedColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) {
            // SpriteKit liefert sRGB-codierte Farbwerte. Extended sRGB behält Primärfarben und
            // Transferkurve für 0...1 unverändert, erlaubt dem Compositor aber Werte > 1. Ohne
            // dieses Tag kann selbst ein Float-Drawable wieder auf SDR-Weiß begrenzt werden.
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.colorspace = extendedColorSpace
            metalLayer.edrMetadata = nil
            hdrSurfaceConfigured = metalLayer.pixelFormat == .rgba16Float
                && metalLayer.colorspace != nil
        }

        let available = displaySupportsHDR && hdrSurfaceConfigured
        let enabled = available && gameScene.hdrGlowEnabled
        metalLayer.wantsExtendedDynamicRangeContent = enabled
        let headroom = enabled
            ? display.maximumExtendedDynamicRangeColorComponentValue
            : 1.0
        gameScene.updateHDRDisplay(available: available, currentHeadroom: headroom)
    }

    public func view(_ view: SKView, shouldRenderAtTime time: TimeInterval) -> Bool {
        refreshHDRDisplay()
        return true
    }
}
