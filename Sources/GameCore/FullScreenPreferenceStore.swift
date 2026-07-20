import Foundation

/// Persistiert ausschließlich den vom Spieler bestätigten macOS-Vollbildzustand.
/// Die AppKit-Shell entscheidet weiterhin, ob Vollbild auf der aktuellen Plattform verfügbar ist
/// und meldet nur erfolgreich abgeschlossene native Fensterübergänge zurück an `GameScene`.
enum FullScreenPreferenceStore {
    static let key = "exploids_full_screen_enabled"

    static func load() -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}
