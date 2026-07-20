import AppKit
import SpriteKit
import QuartzCore
import Metal
import GameCore

/// A custom NSWindow subclass that hosts the SpriteKit rendering view.
@MainActor
public final class GameWindow: NSWindow, @preconcurrency SKViewDelegate, NSWindowDelegate {

    private let gameView: SKView
    private let gameScene: GameScene
    private var hdrSurfaceConfigured = false
    /// Bewusst getrennt von `styleMask`: Während AppKits Vollbildanimation gilt der Zustand erst
    /// nach `windowDidEnterFullScreen` als aktiv und bereits ab `windowWillExitFullScreen` als aus.
    private var isNativeFullScreen = false
    /// NSCursor.hide()/unhide() sind gepaart. Dieses Flag verhindert doppelte Aufrufe und damit
    /// einen global falsch bilanzierten Cursor-Hide-Count.
    private var cursorHiddenByGame = false
    private var isPreparingForTermination = false
    private var didRequestSavedFullScreen = false

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

        let gameView = SKView(frame: contentRect)
        // SpriteKit begrenzt SKView standardmäßig auf 60 Bilder/s. 120 ist eine reine
        // Renderpräferenz und bleibt bewusst unabhängig vom festen Simulationszeitschritt.
        gameView.preferredFramesPerSecond = 120
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
        self.collectionBehavior.insert(.fullScreenPrimary)
        self.delegate = self

        // Apply modern macOS dark aqua appearance to the window
        self.appearance = NSAppearance(named: .darkAqua)

        // Initialize SKView to enable SpriteKit rendering
        gameView.autoresizingMask = [.width, .height]
        // `.aspectFit` lässt im Classic-Modus bei Nicht-4:3-Fenstern freie Randflächen. Diese
        // explizit schwarz halten, statt vom Fenster-/Layer-Default abhängig zu sein.
        gameView.wantsLayer = true
        gameView.layer?.backgroundColor = NSColor.black.cgColor

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
        // Nur die macOS-Shell bietet die native Vollbildoption an. iOS und Headless-Renderer lassen
        // die gemeinsame Settings-Zeile mit ihrem Default `false` vollständig verborgen.
        scene.configureFullScreenSetting(available: true)
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

    /// Wird vom AppDelegate aufgerufen, nachdem das Fenster sichtbar und die App aktiv ist. Ein
    /// gespeichertes ON startet genau einen nativen AppKit-Übergang; OFF erhält das bisherige
    /// Fenster-Startverhalten. Der bestätigte Delegate-Callback persistiert anschließend den Stand.
    public func restoreSavedFullScreenPreference() {
        guard !didRequestSavedFullScreen else { return }
        didRequestSavedFullScreen = true
        guard gameScene.fullScreenEnabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.isPreparingForTermination,
                  self.isVisible,
                  !self.styleMask.contains(.fullScreen) else { return }
            self.toggleFullScreen(nil)
        }
    }

    /// App-Aktivierungswechsel können erfolgen, während SpriteKit nicht rendert. Deshalb stößt der
    /// AppDelegate die Cursorentscheidung zusätzlich zu den Render- und Fenster-Callbacks direkt an.
    public func applicationActivationDidChange() {
        refreshCursorVisibility()
    }

    /// Vor Fensterabbau/Prozessende den Cursor sofort freigeben und spätere AppKit-Exit-Callbacks
    /// nicht als bewusste Nutzeränderung speichern. Der bereits bestätigte Vollbildwert bleibt so
    /// für den nächsten Start erhalten.
    public func prepareForTermination() {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true
        setCursorHidden(false)
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

    /// Versteckt den Cursor ausschließlich während tatsächlich aktivem Vollbild-Gameplay. Menüs,
    /// Pausen, andere aktive Fenster und andere Apps müssen jederzeit einen sichtbaren Cursor haben.
    private func refreshCursorVisibility() {
        let shouldHide = isNativeFullScreen
            && gameScene.gameState == .playing
            && isKeyWindow
            && NSApp.isActive
            && !isPreparingForTermination
        setCursorHidden(shouldHide)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHiddenByGame else { return }
        cursorHiddenByGame = hidden
        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
    }

    /// Gleicht fehlgeschlagene native Animationen mit dem echten AppKit-Zustand ab, statt den
    /// angeforderten Zustand zu speichern.
    private func reconcileFullScreenState() {
        let actualState = styleMask.contains(.fullScreen)
        isNativeFullScreen = actualState
        if !isPreparingForTermination {
            gameScene.synchronizeFullScreenState(actualState)
        }
        refreshCursorVisibility()
    }

    public func view(_ view: SKView, shouldRenderAtTime time: TimeInterval) -> Bool {
        refreshHDRDisplay()
        refreshCursorVisibility()
        return true
    }

    // MARK: - NSWindowDelegate

    public func windowDidEnterFullScreen(_ notification: Notification) {
        isNativeFullScreen = true
        if !isPreparingForTermination {
            gameScene.synchronizeFullScreenState(true)
        }
        refreshCursorVisibility()
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        // Schon vor der Animation freigeben, damit der Cursor beim sichtbaren Desktop zurück ist.
        isNativeFullScreen = false
        refreshCursorVisibility()
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        isNativeFullScreen = false
        if !isPreparingForTermination {
            gameScene.synchronizeFullScreenState(false)
        }
        refreshCursorVisibility()
    }

    public func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        reconcileFullScreenState()
    }

    public func windowDidFailToExitFullScreen(_ window: NSWindow) {
        reconcileFullScreenState()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        refreshCursorVisibility()
    }

    public func windowDidResignKey(_ notification: Notification) {
        refreshCursorVisibility()
    }

    public func windowWillClose(_ notification: Notification) {
        prepareForTermination()
    }
}
