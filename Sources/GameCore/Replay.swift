import Foundation

/// Ein einzelnes Tastenereignis innerhalb einer Aufnahme: An welchem Frame es passierte, welche
/// Taste, und ob sie gedrückt (`true`) oder losgelassen (`false`) wurde. `frameIndex` zählt die
/// Simulationsframes ab Spielstart (0-basiert) – beim Abspielen wird das Ereignis genau vor dem
/// Update dieses Frames eingespeist.
public struct InputEvent: Codable, Equatable, Sendable {
    public let frameIndex: UInt32
    public let keyCode: UInt16
    public let isDown: Bool

    public init(frameIndex: UInt32, keyCode: UInt16, isDown: Bool) {
        self.frameIndex = frameIndex
        self.keyCode = keyCode
        self.isDown = isDown
    }
}

/// Vollständige, kompakte Aufnahme eines Spieldurchlaufs. Zusammen mit der unveränderten Binary
/// reicht das aus, um den Lauf bit-genau nachzuspielen (siehe `docs/replay-system-plan.md`).
///
/// - `version`: Logik-Versions-Tag. Ändert sich die Spiel-Logik (andere RNG-Nutzung, andere
///   Physik), wird es erhöht und alte Aufnahmen werden beim Abspielen abgelehnt (sie würden sonst
///   auseinanderdriften).
/// - `seed`: Startwert des deterministischen PRNG (`GameRandom`).
/// - `startLevel` / `gameMode`: Anfangsbedingungen des Laufs.
/// - `events`: alle Tastenereignisse in zeitlicher Reihenfolge.
/// - `frameCount`: Anzahl der Simulationsschritte (fester Zeitschritt). Ersetzt die früher
///   gespeicherte `dt`-Folge (Phase 3, Fixed-Timestep).
public struct Replay: Codable, Equatable, Sendable {

    /// Aktuelles Logik-Versions-Tag. **Erhöhen, sobald eine Änderung die Simulation bei gleichem
    /// Seed/Input anders laufen lässt** (sonst werden alte Replays falsch wiedergegeben).
    /// v2: Auto-Feuer-Zustand wird in der Aufnahme gespeichert und beim Abspielen wiederhergestellt
    ///     (vorher fehlte er → mit Auto-Feuer gespielte Läufe ließen sich nicht reproduzieren).
    /// v3: Fixed-Timestep. Die Simulation läuft in festen Schritten (`GameScene.simStep`), daher
    ///     hängt ein Lauf nur noch an (Seed + Eingaben) – die `dt`-Folge entfällt; gespeichert wird
    ///     nur die Anzahl der Simulationsschritte (`frameCount`). v2-Aufnahmen (variabler Zeitschritt)
    ///     sind damit inkompatibel und werden beim Abspielen abgelehnt.
    /// v4: Classic-Untertassen warten beim Eintritt und nach dem Wiedererscheinen des Schiffs. Das
    ///     verschiebt RNG-Ziehungen und macht v3-Classic-Läufe inkompatibel; Ancient/Mad v3 bleiben
    ///     bitgleich und werden deshalb weiterhin angenommen.
    /// v5: Classic-Untertassen teilen das originale Bewegungsprofil; Feuerintervall, Projektilslots,
    ///     Ballistik und Zielabweichung folgen dem Arcadecode. Classic-v4-Läufe driften dadurch;
    ///     Ancient/Mad v3/v4 bleiben bitgleich.
    /// v6: Classic-Untertassen erscheinen nach Ataris zustandsbehafteten EDELAY-/SEDLAY-/RTIMER-
    ///     Zählern. Zufällige, punktabhängige Fristen entfallen; Classic-v5-Läufe driften,
    ///     Ancient/Mad v3/v4/v5 bleiben bitgleich.
    /// v7: Classic-Spieler- und Untertassenschüsse verwenden Ataris 62,5-Hz-Lebensdauer,
    ///     Fixed-Point-Geschwindigkeit, Phasenlage, Spawn-Offset und Endpunktzustand. Classic-v6-
    ///     Läufe driften; Ancient/Mad v3 bis v6 bleiben bitgleich.
    /// v8: Classic verwendet feste 1024×768-Simulationsgrenzen und die Rev.-4-Hüllkurven für
    ///     Schiff, Untertassen und Felsen. Kollisionen und Spawns driften gegenüber v7; Ancient/Mad
    ///     v3 bis v7 bleiben bitgleich.
    public static let currentLogicVersion: Int = 8

    public let version: Int
    public let seed: UInt64
    public let startLevel: Int
    public let gameMode: GameMode
    public let events: [InputEvent]
    /// Anzahl der Simulationsschritte des Laufs. Bei Fixed-Timestep reicht das (zusammen mit Seed +
    /// Eingaben) zur bit-exakten Wiedergabe – der Player treibt genau so viele Schritte.
    public let frameCount: Int
    /// War Auto-Feuer beim aufgezeichneten Lauf aktiv? Auto-Feuer lässt das Schiff in `update()`
    /// ohne Tastendruck schießen und beeinflusst damit den Spielverlauf (Sim-Zustand). Muss daher
    /// fürs Replay festgehalten und wiederhergestellt werden. Bei alten Aufnahmen ohne dieses Feld
    /// (vor dem Fix) wird `false` angenommen.
    public let autoFire: Bool
    /// Szenengröße der Aufnahme (Pixel). Ancient/Mad hängen weiterhin an `size` und müssen in dieser
    /// Größe wiedergegeben werden. Classic zeichnet seit v8 stets seine feste 1024×768-Arena auf.
    /// Default 1024×768 = macOS-Fenster-Standardgröße; v3-Aufnahmen ohne dieses Feld (vor dem Fix)
    /// werden damit korrekt interpretiert.
    public let width: Int
    public let height: Int

    public init(version: Int = Replay.currentLogicVersion,
                seed: UInt64,
                startLevel: Int,
                gameMode: GameMode,
                events: [InputEvent],
                frameCount: Int,
                autoFire: Bool = false,
                width: Int = 1024,
                height: Int = 768) {
        self.version = version
        self.seed = seed
        self.startLevel = startLevel
        self.gameMode = gameMode
        self.events = events
        self.frameCount = frameCount
        self.autoFire = autoFire
        self.width = width
        self.height = height
    }

    // `dtSequence` bleibt nur als Legacy-Decodier-Schlüssel: alte v2-Aufnahmen tragen statt
    // `frameCount` noch die dt-Folge. Daraus leiten wir die Schrittzahl ab, damit das Dekodieren
    // nicht wirft – die Aufnahme wird dann ohnehin über `isCompatible` abgelehnt.
    private enum CodingKeys: String, CodingKey {
        case version, seed, startLevel, gameMode, events, frameCount, autoFire, width, height, dtSequence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.seed = try c.decode(UInt64.self, forKey: .seed)
        self.startLevel = try c.decode(Int.self, forKey: .startLevel)
        self.gameMode = try c.decode(GameMode.self, forKey: .gameMode)
        self.events = try c.decode([InputEvent].self, forKey: .events)
        if let fc = try c.decodeIfPresent(Int.self, forKey: .frameCount) {
            self.frameCount = fc
        } else {
            // Legacy v2: aus der dt-Folge ableiten (Aufnahme ist über `isCompatible` ohnehin raus).
            self.frameCount = (try c.decodeIfPresent([Float].self, forKey: .dtSequence))?.count ?? 0
        }
        self.autoFire = try c.decodeIfPresent(Bool.self, forKey: .autoFire) ?? false
        // Größe fehlt in v3-Aufnahmen vor dem Fix → macOS-Fenster-Standard 1024×768 annehmen.
        self.width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 1024
        self.height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 768
    }

    /// Schreibt die kompakte Fixed-Timestep-Form (ohne dt-Folge, mit Aufnahme-Größe).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(seed, forKey: .seed)
        try c.encode(startLevel, forKey: .startLevel)
        try c.encode(gameMode, forKey: .gameMode)
        try c.encode(events, forKey: .events)
        try c.encode(frameCount, forKey: .frameCount)
        try c.encode(autoFire, forKey: .autoFire)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
    }

    /// Stimmt die Aufnahme mit der aktuellen Spiel-Logik überein? v3 bis v7 bleiben für Ancient/Mad
    /// kompatibel, weil v4 bis v8 ausschließlich Classic-Verhalten ändern. Ältere Classic-Läufe
    /// würden durch andere Projektil-/Untertassenlogik und RNG-Zeitpunkte driften und werden klar
    /// abgelehnt.
    public var isCompatible: Bool {
        if version == Replay.currentLogicVersion { return true }
        guard (3...7).contains(version) else { return false }
        switch gameMode {
        case .ancientAsteroids, .madMeteoroids:
            return true
        case .classicAsteroids:
            return false
        }
    }

    // MARK: - Kompakte Kodierung (Binär-Property-List)

    /// Serialisiert die Aufnahme als kompakte Binär-Property-List (Foundation-eigenes Binärformat –
    /// deutlich kleiner als JSON, ohne eigenen Encoder). Geeignet zum Speichern an einem Highscore.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// Liest eine Aufnahme aus den von `encoded()` erzeugten Daten zurück.
    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(Replay.self, from: data)
    }
}
