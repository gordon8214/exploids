import Foundation

/// Persistenz der Highscore-Liste und des maximal erreichten Levels (UserDefaults).
///
/// Aus `GameScene` extrahiert, damit die Szene bei der Spiellogik bleibt und das
/// Laden/Speichern eigenständig testbar ist. Reines I/O — kein Draht zur Simulation,
/// kein RNG, daher ohne Einfluss auf das deterministische Replay-System.
public struct HighScoreStore {

    /// UserDefaults-Keys — unverändert aus `GameScene` übernommen, damit bestehende
    /// Spielstände (und Tests, die die Keys direkt setzen) weiter funktionieren.
    public static let highScoresKey = "exploids_high_scores"
    public static let classicHighScoresKey = "exploids_classic_high_scores"
    public static let maxLevelKey = "exploids_max_level_reached"

    public init() {}

    /// Lädt die gespeicherte Highscore-Liste. Beim allerersten Start (noch nichts
    /// gespeichert) kommt eine Default-Liste zurück — mit Todesmeldung, damit die
    /// Einträge genauso formatiert sind wie eigene (Format-Stil siehe
    /// `GameScene.recordHighScore`).
    public func loadHighScores() -> [HighScore] {
        guard let data = UserDefaults.standard.data(forKey: Self.highScoresKey) else {
            return [
                HighScore(initials: "DM ", score: 10000, date: Date(), deathMessage: "Crushed in a black hole on Level 9"),
                HighScore(initials: "JAB", score: 7500, date: Date(), deathMessage: "Vaporized by UFO laser on Level 7"),
                HighScore(initials: "HAL", score: 5000, date: Date(), deathMessage: "Blown to bits by wobbling bomb on Level 6"),
                HighScore(initials: "MAC", score: 2500, date: Date(), deathMessage: "Rammed by an alien UFO on Level 4"),
                HighScore(initials: "C64", score: 1000, date: Date(), deathMessage: "Hull breach (large asteroid) on Level 2")
            ]
        }

        do {
            return try JSONDecoder().decode([HighScore].self, from: data)
        } catch {
            print("Failed to decode high scores: \(error)")
            return []
        }
    }

    /// Speichert die komplette Highscore-Liste (überschreibt den alten Stand).
    /// Best-effort: ein Encode-Fehler wird geloggt, nie geworfen.
    public func save(_ highScores: [HighScore]) {
        save(highScores, key: Self.highScoresKey)
    }

    /// Classic beginnt absichtlich mit einer leeren, vollständig getrennten Bestenliste.
    public func loadClassicHighScores() -> [HighScore] {
        guard let data = UserDefaults.standard.data(forKey: Self.classicHighScoresKey) else { return [] }
        do {
            return try JSONDecoder().decode([HighScore].self, from: data)
        } catch {
            print("Failed to decode Classic high scores: \(error)")
            return []
        }
    }

    public func saveClassic(_ highScores: [HighScore]) {
        save(highScores, key: Self.classicHighScoresKey)
    }

    private func save(_ highScores: [HighScore], key: String) {
        do {
            let data = try JSONEncoder().encode(highScores)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to encode high scores: \(error)")
        }
    }

    /// Maximal erreichtes Level (für die Level-Vorwahl auf dem Startbildschirm);
    /// mindestens 1, auch wenn noch nie etwas gespeichert wurde.
    public func loadMaxLevelReached() -> Int {
        max(1, UserDefaults.standard.integer(forKey: Self.maxLevelKey))
    }

    /// Merkt sich das maximal erreichte Level dauerhaft.
    public func saveMaxLevelReached(_ level: Int) {
        UserDefaults.standard.set(level, forKey: Self.maxLevelKey)
    }
}
