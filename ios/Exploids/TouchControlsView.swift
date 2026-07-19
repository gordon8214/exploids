import UIKit
import CoreText
import GameCore

// MARK: - Modell-Typen

/// Beschreibt, wie ein Touch-Button die GameScene-API aufruft.
enum ButtonKind {
    /// Taste bleibt gedrückt, solange der Finger auf dem Button liegt (drehen, Schub, Feuer).
    case hold(keyCode: UInt16)
    /// Einmaliger Tap: keyDown sofort gefolgt von keyUp (Start, Replay, ESC, …).
    case tap(keyCode: UInt16)
    /// Zeichen-Eingabe: simulateTypeCharacter(_:) – für Initialen, Glossar- und Highscore-Taste.
    case typeChar(String)
    /// Startet sofort eine Demo (DEMO-Button am Startbildschirm) – ruft scene.startDemoFromMenu().
    case startDemo
}

/// Ein einzelner rechteckiger Button.
struct TouchButton {
    /// Eindeutige ID – Schlüssel für berechnete Frames und aktive Hold-Touches.
    let id: Int
    /// Position und Größe relativ zum sicheren Bereich (0…1). Wird in layoutSubviews zu absoluten Frames.
    let relativeRect: CGRect
    /// Beschriftung auf dem Button.
    let label: String
    /// Verhalten beim Berühren.
    let kind: ButtonKind
}

// MARK: - TouchControlsView

/// Transparentes Overlay über dem SKView. Es zeigt rechteckige Buttons und mappt Touches
/// (inkl. Multitouch) auf die öffentliche GameScene-Eingabe-API.
///
/// Steuerung im Spiel (`.playing`): Drehen ist auf den LINKEN Daumen gelegt (◄ / ►),
/// Schub und Feuer auf den RECHTEN (SCHUB / FEUER, Feuer halten = Charge-Shot). Dreh- und
/// Schub-Eingabe sind so auf zwei Daumen getrennt – gleichzeitig drehen + schub + feuer geht.
final class TouchControlsView: UIView {

    // MARK: - Öffentliche Eigenschaften

    /// Schwache Referenz auf die GameScene – das Overlay kennt nur die öffentliche Bridge-API.
    weak var scene: GameScene?

    // MARK: - Zustand

    /// Aktueller Spielzustand – bestimmt das angezeigte Button-Set.
    private var currentState: GameState = .startScreen

    /// Buttons des aktuellen Zustands.
    private var buttons: [TouchButton] = []
    /// Berechnete absolute Frames je Button-ID (aktualisiert in layoutSubviews).
    private var buttonFrames: [Int: CGRect] = [:]
    /// Welcher Finger hält gerade welchen Hold-Button? (Touch-Identität → Button-ID)
    private var activeHoldTouches: [UITouch: Int] = [:]
    /// Wie viele Finger halten gerade welchen keyCode? Referenzzählung, damit zwei Buttons mit
    /// demselben keyCode (z.B. der redundante Schub links + rechts) sich nicht gegenseitig
    /// aufheben: keyDown erst beim ersten Finger, keyUp erst, wenn der letzte loslässt.
    private var holdCounts: [UInt16: Int] = [:]

    // MARK: - Schrift

    /// Liefert den gebündelten Retro-Pixel-Font (wie der EXPLOIDS-Titel) in der gewünschten Größe.
    /// Fällt auf eine Monospace-Systemschrift zurück, falls der Font (noch) nicht geladen ist.
    private func pixelFont(ofSize size: CGFloat) -> UIFont {
        RetroFont.registerIfNeeded()   // idempotent – stellt sicher, dass der Font im Prozess ist
        return UIFont(name: RetroFont.pixel, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("Nur programmatisch initialisieren")
    }

    // MARK: - Zustandswechsel

    /// Vom GameViewController bei jedem GameState- oder Demo-Wechsel aufgerufen.
    /// - Parameter demoActive: Läuft gerade eine Autopilot-Demo? Dann werden im Spiel KEINE
    ///   Steuer-Buttons gezeichnet – der Zuschauer braucht sie nicht und es sieht ruhiger aus.
    func update(for state: GameState, demoActive: Bool = false) {
        // Beim Verlassen eines Zustands alle gehaltenen Tasten lösen, sonst bliebe z.B. „Schub"
        // hängen, wenn man während des Drückens stirbt.
        releaseAllHolds()
        currentState = state
        // Im laufenden Demo-Spiel nur den ESC-Button zeigen (Rest ausblenden): der Zuschauer braucht
        // die Steuerung nicht, soll die Demo aber abbrechen können. Ohne einen Button käme gar keine
        // Berührung mehr in der Scene an (kein simulateKeyDown → kein Attract-Abbruch).
        buttons = (state == .playing && demoActive)
            ? makeButtons(for: state).filter { $0.label == "ESC" }
            : makeButtons(for: state)
        buttonFrames = [:]          // wird in layoutSubviews neu berechnet
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Lässt alle aktuell gehaltenen Hold-Tasten los.
    private func releaseAllHolds() {
        for touch in Array(activeHoldTouches.keys) { releaseTouchHold(touch) }
        activeHoldTouches.removeAll()
        holdCounts.removeAll()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Sicheren Bereich (Notch, Home-Indikator) berücksichtigen.
        let safe = bounds.inset(by: safeAreaInsets)
        buttonFrames = [:]
        for btn in buttons {
            let r = btn.relativeRect
            buttonFrames[btn.id] = CGRect(
                x: safe.minX + r.minX * safe.width,
                y: safe.minY + r.minY * safe.height,
                width:  r.width  * safe.width,
                height: r.height * safe.height
            )
        }
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)
        for btn in buttons {
            guard let frame = buttonFrames[btn.id] else { continue }
            drawButton(ctx: ctx, frame: frame, label: btn.label)
        }
    }

    /// Zeichnet einen rechteckigen Button: dezente Füllung, dünner Rand, graue Pixel-Font-
    /// Beschriftung. Im Spiel (.playing) liegen die Buttons über dem Spielfeld und werden daher
    /// deutlich transparenter gezeichnet als in den Menüs. Dreh-Buttons (◄/►) bekommen statt
    /// eines Schriftzeichens einen großen Kontur-Pfeil (nur Umriss, innen leer).
    private func drawButton(ctx: CGContext, frame: CGRect, label: String) {
        let inGame = (currentState == .playing)
        // Im Spiel bewusst sehr dezent: die Steuerung muss man nur EINMAL finden, danach soll sie
        // möglichst wenig vom Spielfeld ablenken – aber zur Orientierung dauerhaft schwach sichtbar
        // bleiben. Darum in-game deutlich dunklere/transparentere Alphas und dünnere Striche als in
        // den Menüs (dort bleiben die Buttons kräftig und gut lesbar).
        let borderAlpha: CGFloat = inGame ? 0.09 : 0.5
        let fillAlpha:   CGFloat = inGame ? 0.015 : 0.05
        let textAlpha:   CGFloat = inGame ? 0.24 : 0.95
        // Rand-/Symbol-Strichstärke: im Spiel dünner, in den Menüs wie gehabt.
        let borderLineWidth: CGFloat = inGame ? 0.75 : 1.0
        let symbolLineWidth: CGFloat = inGame ? 1.8 : 2.5

        let inset = frame.insetBy(dx: 3, dy: 3)
        let radius = min(inset.height, inset.width) * 0.22
        let path = UIBezierPath(roundedRect: inset, cornerRadius: radius)
        ctx.setFillColor(UIColor(white: 1.0, alpha: fillAlpha).cgColor)
        ctx.addPath(path.cgPath); ctx.fillPath()
        ctx.setStrokeColor(UIColor(white: 0.6, alpha: borderAlpha).cgColor)
        ctx.setLineWidth(borderLineWidth)
        ctx.addPath(path.cgPath); ctx.strokePath()

        // Symbol-Buttons als Vektor-Form zeichnen (kein Font): Dreh-Pfeile, Schließen-X,
        // Scroll-Dreiecke. So hängt keiner dieser Buttons an einer Fremdschrift.
        // In-game etwas weniger Aufschlag auf die Symbol-Sichtbarkeit als in den Menüs, damit auch
        // die Pfeile/Icons dezent bleiben.
        let symbolAlpha = textAlpha + (inGame ? 0.10 : 0.15)
        switch label {
        case "◄": drawArrowOutline(ctx: ctx, frame: frame, pointingLeft: true,  alpha: symbolAlpha, lineWidth: symbolLineWidth); return
        case "►": drawArrowOutline(ctx: ctx, frame: frame, pointingLeft: false, alpha: symbolAlpha, lineWidth: symbolLineWidth); return
        case "✕": drawCloseX(ctx: ctx, frame: frame, alpha: symbolAlpha, lineWidth: symbolLineWidth); return
        case "▲": drawTriangle(ctx: ctx, frame: frame, up: true,  alpha: symbolAlpha, lineWidth: symbolLineWidth); return
        case "▼": drawTriangle(ctx: ctx, frame: frame, up: false, alpha: symbolAlpha, lineWidth: symbolLineWidth); return
        default: break
        }

        // Text-Label im Retro-Pixel-Font (wie der Titel). Systemschrift nur als Notnagel, falls
        // der Pixel-Font ein Zeichen nicht enthält – verhindert leere Kästchen.
        let str = label as NSString
        var fontSize = min(inset.height * 0.42, 16)
        var font = fontForLabel(label, size: fontSize)
        while fontSize > 6 && str.size(withAttributes: [.font: font]).width > inset.width - 8 {
            fontSize -= 1
            font = fontForLabel(label, size: fontSize)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(white: 0.72, alpha: textAlpha)
        ]
        let ts = str.size(withAttributes: attrs)
        str.draw(in: CGRect(x: frame.midX - ts.width / 2, y: frame.midY - ts.height / 2,
                            width: ts.width, height: ts.height), withAttributes: attrs)
    }

    /// Wählt für ein Text-Label den Retro-Pixel-Font – aber nur, wenn dieser ALLE Zeichen
    /// darstellen kann (z.B. „ZURÜCK" mit Ü). Sonst Systemschrift, damit keine leeren Kästchen
    /// entstehen.
    private func fontForLabel(_ label: String, size: CGFloat) -> UIFont {
        let pixel = pixelFont(ofSize: size)
        let ctFont = CTFontCreateWithName(pixel.fontName as CFString, size, nil)
        let utf16 = Array(label.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let hasAllGlyphs = CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count)
        return hasAllGlyphs ? pixel : .monospacedSystemFont(ofSize: size, weight: .medium)
    }

    /// Zeichnet ein Schließen-„X" als zwei gekreuzte Linien (für die Zurück-/Schließen-Buttons).
    private func drawCloseX(ctx: CGContext, frame: CGRect, alpha: CGFloat, lineWidth: CGFloat = 2.5) {
        let s = min(frame.width, frame.height) * 0.22
        let cx = frame.midX, cy = frame.midY
        ctx.setStrokeColor(UIColor(white: 0.82, alpha: alpha).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - s, y: cy - s)); ctx.addLine(to: CGPoint(x: cx + s, y: cy + s))
        ctx.move(to: CGPoint(x: cx + s, y: cy - s)); ctx.addLine(to: CGPoint(x: cx - s, y: cy + s))
        ctx.strokePath()
    }

    /// Zeichnet ein Kontur-Dreieck nach oben (▲) bzw. unten (▼) – für die Scroll-Buttons.
    private func drawTriangle(ctx: CGContext, frame: CGRect, up: Bool, alpha: CGFloat, lineWidth: CGFloat = 2.5) {
        let s = min(frame.width, frame.height) * 0.26
        let cx = frame.midX, cy = frame.midY
        ctx.setStrokeColor(UIColor(white: 0.82, alpha: alpha).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        if up {
            ctx.move(to: CGPoint(x: cx, y: cy - s))
            ctx.addLine(to: CGPoint(x: cx + s, y: cy + s))
            ctx.addLine(to: CGPoint(x: cx - s, y: cy + s))
        } else {
            ctx.move(to: CGPoint(x: cx, y: cy + s))
            ctx.addLine(to: CGPoint(x: cx + s, y: cy - s))
            ctx.addLine(to: CGPoint(x: cx - s, y: cy - s))
        }
        ctx.closePath()
        ctx.strokePath()
    }

    /// Zeichnet einen großen, innen leeren Kontur-Pfeil (Dreieck) nach links bzw. rechts.
    private func drawArrowOutline(ctx: CGContext, frame: CGRect, pointingLeft: Bool, alpha: CGFloat, lineWidth: CGFloat = 2.5) {
        let s = min(frame.width, frame.height) * 0.30   // halbe Pfeilgröße
        let cx = frame.midX, cy = frame.midY
        ctx.setStrokeColor(UIColor(white: 0.82, alpha: alpha).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        if pointingLeft {
            ctx.move(to: CGPoint(x: cx - s, y: cy))
            ctx.addLine(to: CGPoint(x: cx + s, y: cy - s))
            ctx.addLine(to: CGPoint(x: cx + s, y: cy + s))
        } else {
            ctx.move(to: CGPoint(x: cx + s, y: cy))
            ctx.addLine(to: CGPoint(x: cx - s, y: cy - s))
            ctx.addLine(to: CGPoint(x: cx - s, y: cy + s))
        }
        ctx.closePath()
        ctx.strokePath()
    }

    // MARK: - Touch-Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let btn = hitButton(at: touch.location(in: self)) else { continue }
            press(btn, with: touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Robustheit gegen „Finger rutscht vom Button": einen gehaltenen Button loslassen, wenn
        // der Finger ihn verlässt, und ggf. den neu berührten Hold-Button übernehmen.
        for touch in touches {
            guard let heldId = activeHoldTouches[touch] else { continue }
            let nowBtn = hitButton(at: touch.location(in: self))
            if nowBtn?.id == heldId { continue }   // noch auf demselben Button

            releaseTouchHold(touch)
            if let nb = nowBtn, case .hold(let kc) = nb.kind {
                activeHoldTouches[touch] = nb.id
                beginHold(kc)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches { releaseTouchHold(touch) }
    }

    // MARK: - Hilfsfunktionen

    /// Verarbeitet das Antippen eines Buttons je nach Art (hold / tap / typeChar).
    private func press(_ btn: TouchButton, with touch: UITouch) {
        switch btn.kind {
        case .hold(let kc):
            activeHoldTouches[touch] = btn.id
            beginHold(kc)
        case .tap(let kc):
            scene?.simulateKeyDown(keyCode: kc)
            scene?.simulateKeyUp(keyCode: kc)
        case .typeChar(let ch):
            scene?.simulateTypeCharacter(ch)
        case .startDemo:
            scene?.startDemoFromMenu()
        }
    }

    /// Beginnt das Halten eines keyCodes (referenzgezählt → keyDown nur beim ersten Finger).
    private func beginHold(_ kc: UInt16) {
        holdCounts[kc, default: 0] += 1
        if holdCounts[kc] == 1 { scene?.simulateKeyDown(keyCode: kc) }
    }

    /// Beendet das Halten eines keyCodes (keyUp erst, wenn der letzte Finger loslässt).
    private func endHold(_ kc: UInt16) {
        guard let n = holdCounts[kc] else { return }
        if n <= 1 {
            holdCounts[kc] = nil
            scene?.simulateKeyUp(keyCode: kc)
        } else {
            holdCounts[kc] = n - 1
        }
    }

    /// Löst den von diesem Finger gehaltenen Button (falls vorhanden) referenzgezählt.
    private func releaseTouchHold(_ touch: UITouch) {
        guard let id = activeHoldTouches.removeValue(forKey: touch) else { return }
        if let b = buttons.first(where: { $0.id == id }), case .hold(let kc) = b.kind {
            endHold(kc)
        }
    }

    /// Treffertest: erster Button, dessen absoluter Frame den Punkt enthält.
    private func hitButton(at point: CGPoint) -> TouchButton? {
        for btn in buttons {
            if let frame = buttonFrames[btn.id], frame.contains(point) { return btn }
        }
        return nil
    }

    // MARK: - Button-Definitionen je GameState

    /// Erzeugt die Button-Liste für einen GameState. Rects sind 0…1, relativ zum sicheren Bereich.
    private func makeButtons(for state: GameState) -> [TouchButton] {
        switch state {

        // Im Spiel: Drehen links (◄ ► unten), Schub redundant links DARÜBER. Rechts Schub +
        // Feuer ÜBEREINANDER. So lässt sich Schub mit beiden Daumen geben; kleiner ESC oben Mitte.
        // Schub (126) liegt doppelt vor (links + rechts) – die Referenzzählung verhindert, dass
        // das Loslassen des einen den anderen aufhebt.
        case .playing:
            return [
                // Links: großer Schub-Button – füllt fast die ganze linke Spalte ÜBER den
                // Dreh-Pfeilen (von knapp unter ESC bis kurz über die Pfeile). So lässt sich
                // Schub geben, egal wo man oben links tippt.
                TouchButton(id: 6, relativeRect: CGRect(x: 0.02, y: 0.03, width: 0.31, height: 0.54),
                            label: "SCHUB", kind: .hold(keyCode: 126)),
                // Links unten: drehen (große Kontur-Pfeile)
                TouchButton(id: 1, relativeRect: CGRect(x: 0.02, y: 0.59, width: 0.15, height: 0.36),
                            label: "◄", kind: .hold(keyCode: 123)),   // gegen den Uhrzeigersinn
                TouchButton(id: 2, relativeRect: CGRect(x: 0.18, y: 0.59, width: 0.15, height: 0.36),
                            label: "►", kind: .hold(keyCode: 124)),   // im Uhrzeigersinn
                // Rechts: zwei große Buttons übereinander, die die ganze rechte Spalte füllen –
                // Schub oben (bis ganz oben), Feuer unten (bis ganz unten).
                TouchButton(id: 3, relativeRect: CGRect(x: 0.83, y: 0.03, width: 0.15, height: 0.46),
                            label: "SCHUB", kind: .hold(keyCode: 126)),
                TouchButton(id: 4, relativeRect: CGRect(x: 0.83, y: 0.51, width: 0.15, height: 0.46),
                            label: "FEUER", kind: .hold(keyCode: 49)),  // halten = Charge-Shot
                // Oben Mitte: ESC (Quit-Bestätigung)
                TouchButton(id: 5, relativeRect: CGRect(x: 0.45, y: 0.0, width: 0.10, height: 0.10),
                            label: "ESC", kind: .tap(keyCode: 53)),
            ]

        case .startScreen:
            return [
                // Level −/+ flankieren die zentrale „STARTING LEVEL"-Anzeige (Bildmitte).
                TouchButton(id: 10, relativeRect: CGRect(x: 0.19, y: 0.49, width: 0.13, height: 0.15),
                            label: "LVL-", kind: .tap(keyCode: 123)),
                TouchButton(id: 11, relativeRect: CGRect(x: 0.68, y: 0.49, width: 0.13, height: 0.15),
                            label: "LVL+", kind: .tap(keyCode: 124)),
                // Obere Ecke links: Einstellungen öffnen (Musik / SFX / Auto-Feuer / HDR-Glow).
                // „o" öffnet in der Scene den .settings-State.
                TouchButton(id: 16, relativeRect: CGRect(x: 0.02, y: 0.06, width: 0.16, height: 0.16),
                            label: "SETTINGS", kind: .typeChar("o")),
                // Obere Ecke rechts: Highscore-Ansicht
                TouchButton(id: 15, relativeRect: CGRect(x: 0.84, y: 0.06, width: 0.14, height: 0.16),
                            label: "HISCORE", kind: .typeChar("h")),
                // Untere Reihe: Modus links (bleibt), START groß in der Mitte, Glossar (INFO) rechts
                TouchButton(id: 12, relativeRect: CGRect(x: 0.02, y: 0.78, width: 0.17, height: 0.17),
                            label: "MODUS", kind: .tap(keyCode: 126)),
                TouchButton(id: 13, relativeRect: CGRect(x: 0.40, y: 0.76, width: 0.20, height: 0.19),
                            label: "START", kind: .tap(keyCode: 36)),
                // DEMO: löst sofort eine Autopilot-Demo aus (Pendant zur macOS-Taste „D"); zwischen
                // START und INFO in der unteren Reihe.
                TouchButton(id: 17, relativeRect: CGRect(x: 0.63, y: 0.78, width: 0.15, height: 0.17),
                            label: "DEMO", kind: .startDemo),
                TouchButton(id: 14, relativeRect: CGRect(x: 0.85, y: 0.78, width: 0.13, height: 0.17),
                            label: "INFO", kind: .typeChar("i")),
            ]

        case .nameEntry:
            // Keine eigenen Buttons: Die Initialen-Eingabe nutzt die native iOS-Bildschirmtastatur
            // (eingeblendet vom GameViewController via UIKeyInput). Daher ist das Overlay hier leer.
            return []

        case .gameOver:
            return [
                TouchButton(id: 100, relativeRect: CGRect(x: 0.28, y: 0.80, width: 0.20, height: 0.16),
                            label: "REPLAY", kind: .tap(keyCode: 49)),
                TouchButton(id: 101, relativeRect: CGRect(x: 0.52, y: 0.80, width: 0.20, height: 0.16),
                            label: "ZURÜCK", kind: .tap(keyCode: 53)),
            ]

        // Esc(53) = weiterspielen, „y" = beenden (zur Startseite).
        case .quitConfirmation:
            return [
                TouchButton(id: 110, relativeRect: CGRect(x: 0.28, y: 0.62, width: 0.20, height: 0.20),
                            label: "WEITER", kind: .tap(keyCode: 53)),
                TouchButton(id: 111, relativeRect: CGRect(x: 0.52, y: 0.62, width: 0.20, height: 0.20),
                            label: "BEENDEN", kind: .typeChar("y")),
            ]

        // Esc(53) = zurück. Scroll-Buttons nach Scrollbar-Logik: ▼ fährt im Text weiter nach
        // unten (Text läuft hoch – wie der Auto-Scroll, keyCode 126), ▲ fährt zurück (keyCode 125).
        // Auf macOS bleiben die echten Pfeiltasten unverändert (dort steuert die Engine 126/125).
        case .glossary:
            return [
                TouchButton(id: 120, relativeRect: CGRect(x: 0.88, y: 0.04, width: 0.10, height: 0.18),
                            label: "✕", kind: .tap(keyCode: 53)),
                TouchButton(id: 121, relativeRect: CGRect(x: 0.88, y: 0.30, width: 0.10, height: 0.24),
                            label: "▲", kind: .tap(keyCode: 125)),
                TouchButton(id: 122, relativeRect: CGRect(x: 0.88, y: 0.62, width: 0.10, height: 0.24),
                            label: "▼", kind: .tap(keyCode: 126)),
            ]

        // Eigene Highscore-Ansicht: nur ein Zurück-Knopf oben rechts.
        case .highScores:
            return [
                TouchButton(id: 130, relativeRect: CGRect(x: 0.86, y: 0.04, width: 0.11, height: 0.16),
                            label: "✕", kind: .tap(keyCode: 53)),
            ]

        // Einstellungen: vier Umschalt-Buttons (lösen dieselben globalen Toggles wie M/N/F/G aus)
        // plus Zurück. Die aktuellen Werte zeigt die Scene als Textzeilen darüber an.
        case .settings:
            return [
                TouchButton(id: 140, relativeRect: CGRect(x: 0.06, y: 0.72, width: 0.20, height: 0.17),
                            label: "MUSIC", kind: .typeChar("m")),
                TouchButton(id: 141, relativeRect: CGRect(x: 0.29, y: 0.72, width: 0.20, height: 0.17),
                            label: "SFX", kind: .typeChar("n")),
                TouchButton(id: 142, relativeRect: CGRect(x: 0.52, y: 0.72, width: 0.20, height: 0.17),
                            label: "AUTO-FIRE", kind: .typeChar("f")),
                TouchButton(id: 143, relativeRect: CGRect(x: 0.75, y: 0.72, width: 0.20, height: 0.17),
                            label: "HDR GLOW", kind: .typeChar("g")),
                TouchButton(id: 144, relativeRect: CGRect(x: 0.88, y: 0.04, width: 0.10, height: 0.16),
                            label: "✕", kind: .tap(keyCode: 53)),
            ]
        }
    }
}
