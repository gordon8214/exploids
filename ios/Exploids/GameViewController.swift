import UIKit
import SpriteKit
import QuartzCore
import Metal
import GameCore

/// Haupt-ViewController der iOS-App.
/// Er erzeugt den SpriteKit-View, hostet die GameScene und legt ein Touch-Overlay darüber.
/// Entspricht der Rolle von GameWindow auf macOS (Sources/ExploidsMac/GameWindow.swift).
final class GameViewController: UIViewController {

    // MARK: - Eigenschaften

    /// SpriteKit-Renderansicht – füllt den gesamten Screen.
    private let skView = SKView()

    /// Die laufende Spiel-Scene. Starke Referenz notwendig, damit sie nicht freigegeben wird.
    private var scene: GameScene!

    /// Das transparente Touch-Overlay über dem SpriteKit-View.
    /// Empfängt alle Touches und leitet sie als Tastencodes an die GameScene weiter.
    private var overlay: TouchControlsView!

    /// CADisplayLink verbindet sich mit dem Bildschirm-Refresh-Takt (~60/120 Hz).
    /// Pro Frame liest er gameState und benachrichtigt das Overlay bei Zustandswechseln.
    private var displayLink: CADisplayLink?

    /// Zuletzt gesehener GameState – zum Erkennen von Zustandswechseln ohne ständiges Neuzeichnen.
    private var lastKnownState: GameState?

    /// Zuletzt gesehener Demo-Status – ein Wechsel (Demo startet/endet) muss das Overlay ebenfalls
    /// neu aufbauen, damit die Controls im Demo-Modus aus- und danach wieder eingeblendet werden.
    private var lastKnownDemo: Bool = false

    /// Die Modusauswahl kann sich ändern, ohne dass der GameState wechselt. Das Touch-Overlay muss
    /// dann Level-Tasten bzw. Classic-Steuerung ebenfalls neu aufbauen.
    private var lastKnownMode: GameMode?

    /// Das Float-Drawable wird pro SKView nur einmal aktiviert. Der EDR-Wunsch selbst kann danach
    /// billig mit der Benutzereinstellung bzw. einem Displaywechsel an- und ausgeschaltet werden.
    private var hdrSurfaceConfigured = false

    // MARK: - Lifecycle

    override func loadView() {
        // SKView direkt als Root-View setzen (kein UIView-Wrapper nötig)
        // SpriteKit begrenzt SKView standardmäßig auf 60 Bilder/s. 120 ist eine reine
        // Renderpräferenz und bleibt bewusst unabhängig vom festen Simulationszeitschritt.
        skView.preferredFramesPerSecond = 120
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view = skView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupOverlay()
        setupDisplayLink()

        // Hintergrundmusik starten – das Pendant zu macOS (Main.swift:29 ruft dasselbe auf).
        // Ohne diesen Aufruf bleibt die App auf iOS stumm (SFX laufen, weil sie bei Spiel-Events
        // on-demand abgespielt werden; Musik muss dagegen aktiv gestartet werden). MusicPlayer.start()
        // aktiviert intern die AVAudioSession und respektiert den Musik-Schalter aus den Einstellungen.
        MusicPlayer.shared.start()
    }

    // MARK: - Setup

    /// Erzeugt und präsentiert die GameScene in der SKView.
    /// Entspricht dem Init-Code in GameWindow.swift (macOS).
    private func setupScene() {
        // Szenen-Größe: 1024×768 – identisch mit der macOS-Variante.
        // scaleMode .resizeFill passt die Szene an den tatsächlichen View-Frame an.
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .resizeFill
        s.backgroundColor = .black

        // iOS-spezifische Layout-Konfiguration (macOS lässt die Defaults stehen → unverändert):
        // kompaktes Breitformat-Menü + Highscores in eigener Ansicht statt am Startbildschirm.
        s.isCompactLayout = true
        s.showsHighScoresOnStartScreen = false
        s.autoFire = true   // Auto-Feuer standardmäßig an (kein Dauertippen, ideal fürs iPhone)
        // Attract-/Demo-Modus aktivieren (identisch zu macOS, GameWindow.swift:42): nach 30 s Leerlauf
        // am Startbildschirm spielt ein Autopilot eine Demo, danach 10 s Highscore-Liste + 15 s
        // Startbildschirm, dann die nächste Persona – immer weiter. Auf iOS gibt es keine „D"-Taste
        // zum manuellen Start, aber der 30-s-Autostart greift trotzdem; eine echte Berührung bricht
        // die Demo ab (Touch → simulateKeyDown → handleKeyDown übernimmt „Mensch spielt"). Der
        // „PRESS D FOR DEMO"-Hinweis erscheint dank isCompactLayout hier bewusst nicht.
        s.attractModeEnabled = true
        // Fixed-Timestep: nach einem Hänger (App im Hintergrund, Anruf) höchstens 0.25 s Echtzeit
        // als Sim-Schritte nachholen, statt die ganze Pause aufzuarbeiten.
        s.maxFrameDelta = 0.25

        // onQuit absichtlich NICHT setzen: iOS-Apps dürfen sich nicht selbst beenden (Apple HIG).

        self.scene = s
        s.onHDRGlowPreferenceChanged = { [weak self] _ in
            self?.refreshHDRDisplay()
        }
        refreshHDRDisplay()
        skView.presentScene(s)
    }

    /// Legt das Touch-Overlay als transparente Subview über den SKView.
    private func setupOverlay() {
        // Gleiche Bounds wie skView; autoresizing hält das auch nach Rotation korrekt.
        overlay = TouchControlsView(frame: skView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isMultipleTouchEnabled = true
        overlay.backgroundColor = .clear

        // Schwache Referenz auf die Scene: das Overlay kennt nur die öffentliche API.
        overlay.scene = scene

        skView.addSubview(overlay)
    }

    /// Startet den CADisplayLink, der pro Frame den GameState prüft und bei Wechsel
    /// das Overlay benachrichtigt, damit es seine Button-Anordnung anpasst.
    private func setupDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    /// Wird jeden Frame auf dem Main-Thread aufgerufen (CADisplayLink-Callback).
    @objc private func onDisplayLink() {
        // UIScreen sendet für normalen Headroom-Wechsel (z. B. Helligkeit) keine Notification;
        // deshalb direkt im ohnehin vorhandenen Render-Takt abfragen.
        refreshHDRDisplay()

        let current = scene.gameState
        let demo = scene.isDemoRunning
        let mode = currentStateUsesRunningMode(current) ? scene.gameMode : scene.selectedGameMode
        // Overlay nur aktualisieren, wenn sich State ODER Demo-Status geändert hat.
        if case .some(let last) = lastKnownState, statesEqual(last, current),
           demo == lastKnownDemo, mode == lastKnownMode { return }
        lastKnownState = current
        lastKnownDemo = demo
        lastKnownMode = mode
        overlay.update(for: current, demoActive: demo)
        updateKeyboard(for: current)
    }

    private func currentStateUsesRunningMode(_ state: GameState) -> Bool {
        switch state {
        case .playing, .quitConfirmation, .nameEntry, .gameOver: return true
        case .startScreen, .glossary, .highScores, .settings: return false
        }
    }

    /// Bindet SpriteKits CAMetalLayer an den tatsächlich hostenden Bildschirm. Simulatoren und
    /// SDR-Geräte bleiben im bisherigen Pfad; die gespeicherte Nutzerpräferenz wird nicht verändert.
    private func refreshHDRDisplay() {
        guard let scene else { return }
        guard let metalLayer = skView.layer as? CAMetalLayer,
              metalLayer.device != nil else {
            scene.updateHDRDisplay(available: false, currentHeadroom: 1.0)
            return
        }
        // Beim ersten Aufruf ist die View eventuell noch nicht am Fenster. Der Main-Screen erlaubt
        // trotzdem die EDR-Konfiguration vor presentScene; danach gewinnt immer der echte Host-Screen.
        let display = skView.window?.screen ?? UIScreen.main

        let displaySupportsHDR = display.potentialEDRHeadroom > 1.0
        if displaySupportsHDR && !hdrSurfaceConfigured,
           let extendedColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) {
            // SpriteKits sRGB-Transferkurve für normale Farben beibehalten, den Farbraum aber als
            // extended markieren, damit der Compositor Float-Werte oberhalb von 1 nicht abschneidet.
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.colorspace = extendedColorSpace
            metalLayer.edrMetadata = nil
            hdrSurfaceConfigured = metalLayer.pixelFormat == .rgba16Float
                && metalLayer.colorspace != nil
        }

        let available = displaySupportsHDR && hdrSurfaceConfigured
        let enabled = available && scene.hdrGlowEnabled
        metalLayer.wantsExtendedDynamicRangeContent = enabled
        let headroom = enabled ? display.currentEDRHeadroom : 1.0
        scene.updateHDRDisplay(available: available, currentHeadroom: headroom)
    }

    // MARK: - System-Tastatur für die Initialen-Eingabe

    /// Blendet bei `.nameEntry` die native iOS-Tastatur ein (statt eines selbstgezeichneten
    /// Buchstaben-Grids) und versteckt sie in allen anderen Zuständen wieder.
    /// Technik: Der ViewController wird zum First Responder und konformt zu `UIKeyInput` –
    /// dadurch zeigt UIKit automatisch die Bildschirmtastatur. Die getippten Zeichen leiten wir
    /// an dieselbe Scene-API weiter, die auch die macOS-Tastatur bedient.
    private func updateKeyboard(for state: GameState) {
        if case .nameEntry = state {
            becomeFirstResponder()      // Tastatur einblenden
        } else if isFirstResponder {
            resignFirstResponder()      // Tastatur ausblenden, sobald die Eingabe vorbei ist
        }
    }

    /// Nur als First Responder erscheint die Tastatur – Default bei ViewControllern ist `false`.
    override var canBecomeFirstResponder: Bool { true }

    // MARK: - Interface-Konfiguration

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    // MARK: - Hilfsfunktion

    // In Swift 6 ist deinit nonisolated; CADisplayLink ist nicht Sendable.
    // Daher stoppen wir den Link bereits in viewDidDisappear (Main-Thread),
    // sodass deinit nichts mehr anfassen muss.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }
}

// MARK: - Tastatur-Eingabe (UIKeyInput / UITextInputTraits)

/// Macht den ViewController zu einer Texteingabe-Senke für die System-Tastatur.
/// Jeder Tastendruck wird in die plattformneutrale Scene-Eingabe übersetzt – exakt dieselben
/// Aufrufe, die auch die macOS-Tastatur auslöst (Buchstabe tippen, löschen, Eingabe abschließen).
extension GameViewController: UIKeyInput, UITextInputTraits {

    /// Steuert die Löschtaste der Tastatur: solange Initialen da sind, ist „Text vorhanden".
    var hasText: Bool { (scene?.enteredInitialsCount ?? 0) > 0 }

    /// Eingetippte Zeichen. Die „Done"-Taste liefert ein Newline – das werten wir als Eingabe-Ende
    /// (Return/keyCode 36). Sonst wird jedes Zeichen einzeln an die Scene gereicht; die Scene
    /// filtert selbst (nur Buchstaben/Ziffern) und begrenzt auf drei Initialen.
    func insertText(_ text: String) {
        if text.contains("\n") {
            scene?.simulateKeyDown(keyCode: 36)   // Return → Highscore eintragen
            return
        }
        for ch in text {
            scene?.simulateTypeCharacter(String(ch))
        }
    }

    /// Löschtaste → Backspace (keyCode 51), entfernt die zuletzt eingegebene Initiale.
    func deleteBackward() {
        scene?.simulateKeyDown(keyCode: 51)
    }

    // UITextInputTraits: Großbuchstaben (Initialen sind Versalien), keine Autokorrektur/Vorschläge,
    // dunkles Tastatur-Design passend zum schwarzen Spiel, „Done" als Bestätigungstaste.
    var autocapitalizationType: UITextAutocapitalizationType { get { .allCharacters } set {} }
    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }
    var keyboardAppearance: UIKeyboardAppearance { get { .dark } set {} }
    var returnKeyType: UIReturnKeyType { get { .done } set {} }
}

/// Hilfsfunktion: vergleicht zwei GameState-Werte auf Gleichheit.
/// GameState hat keinen synthetisierten Equatable-Konformismus – einfacher manueller Vergleich.
private func statesEqual(_ a: GameState, _ b: GameState) -> Bool {
    switch (a, b) {
    case (.startScreen,      .startScreen):      return true
    case (.playing,          .playing):          return true
    case (.nameEntry,        .nameEntry):         return true
    case (.gameOver,         .gameOver):          return true
    case (.quitConfirmation, .quitConfirmation): return true
    case (.glossary,         .glossary):         return true
    case (.highScores,       .highScores):       return true
    case (.settings,         .settings):         return true
    default:                                     return false
    }
}
