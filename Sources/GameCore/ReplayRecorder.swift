import Foundation

/// Zeichnet einen laufenden Spieldurchlauf auf: Anfangsbedingungen (Seed/Level/Modus), alle
/// Tastenereignisse und die Anzahl der Simulationsschritte. Aus dem Gesammelten entsteht am Ende ein
/// `Replay` (siehe `Replay.swift`). Bei Fixed-Timestep ist jeder Schritt gleich lang
/// (`GameScene.simStep`), darum genügt die Schrittzahl – kein `dt` mehr nötig.
///
/// Der Recorder ist bewusst „dumm": Er weiß nichts über Spiel-Logik, er hängt nur Werte an. Die
/// GameScene ruft `recordEvent` in den Tasten-Handlern und `recordStep` einmal pro Simulationsschritt.
public final class ReplayRecorder {

    private let seed: UInt64
    private let startLevel: Int
    private let gameMode: GameMode
    private let autoFire: Bool
    private let classicRapidFire: Bool
    private let width: Int
    private let height: Int

    private var events: [InputEvent] = []
    private var steps: UInt32 = 0

    public init(seed: UInt64, startLevel: Int, gameMode: GameMode, autoFire: Bool,
                classicRapidFire: Bool = false,
                width: Int, height: Int) {
        self.seed = seed
        self.startLevel = startLevel
        self.gameMode = gameMode
        self.autoFire = autoFire
        self.classicRapidFire = classicRapidFire
        self.width = width
        self.height = height
    }

    /// Index des nächsten aufzuzeichnenden Schritts (= Anzahl bereits aufgezeichneter Schritte). Ein
    /// Tastenereignis, das jetzt eintrifft, gehört zu genau diesem (noch kommenden) Schritt.
    public var nextFrameIndex: UInt32 { steps }

    /// Hält ein Tastenereignis fest (mit dem aktuellen Schritt-Index).
    public func recordEvent(keyCode: UInt16, isDown: Bool) {
        events.append(InputEvent(frameIndex: nextFrameIndex, keyCode: keyCode, isDown: isDown))
    }

    /// Zählt einen ausgeführten Simulationsschritt mit.
    public func recordStep() {
        steps += 1
    }

    /// Baut aus dem bisher Gesammelten eine `Replay`-Aufnahme. Nicht-destruktiv: kann auch
    /// zwischendurch (z. B. in Tests) aufgerufen werden, ohne die Aufnahme zu beenden.
    public func makeReplay() -> Replay {
        Replay(seed: seed, startLevel: startLevel, gameMode: gameMode,
               events: events, frameCount: Int(steps), autoFire: autoFire,
               classicRapidFire: classicRapidFire,
               width: width, height: height)
    }
}
