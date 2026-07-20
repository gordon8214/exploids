import AVFoundation
import Foundation

/// Spielt die Chiptune-Hintergrundmusik ab: die vorhandenen Tracks laufen abwechselnd in
/// Endlosschleife – durchgehend über Start-, Spiel- und Game-Over-Screen. Während einer
/// Classic-Asteroids-Partie wird sie vorübergehend pausiert, damit nur deren Arcade-Herzschlag
/// zu hören ist.
///
/// Die Musik lässt sich global mit „M" ein-/ausschalten. Einmal ausgeschaltet, bleibt sie bis zum
/// Programmende aus (reiner Laufzeit-Schalter, kein Persistieren) – außer man schaltet sie wieder ein.
///
/// Plattform-Unterschied bei der Wiedergabe:
/// - **macOS**: eigenständiger `AVAudioPlayer` (funktioniert dort einwandfrei).
/// - **iOS**: die Musik läuft als `AVAudioPlayerNode` an derselben `AVAudioEngine` wie die SFX
///   (siehe `SoundManager.makeMusicNode`). Grund: Ein separater `AVAudioPlayer` neben der laufenden
///   SFX-Engine erzeugt auf iOS Verzerrungen (zwei Render-Pfade auf dieselbe Audio-Hardware). Über
///   einen gemeinsamen Knoten gibt es nur einen Render-Pfad und damit saubere Musik.
public final class MusicPlayer: NSObject, @unchecked Sendable {

    /// Gemeinsame Singleton-Instanz.
    public static let shared = MusicPlayer()

    private var tracks: [URL] = []
    private var index = 0

    /// Ob Musik aktuell gewünscht ist (Schalter über „M").
    public private(set) var isEnabled = true

    /// Vorübergehende Unterdrückung durch den laufenden Spielmodus. Anders als `isEnabled` ist das
    /// keine Spielerpräferenz: Beim Verlassen von Classic wird eine zuvor aktivierte Musik
    /// automatisch fortgesetzt.
    private(set) var isPlaybackSuppressed = false

    // In Tests bzw. mit --no-sound spielt keine Musik.
    private let isSuppressed: Bool = {
        let env = ProcessInfo.processInfo.environment
        let testing = env["XCTestConfigurationFilePath"] != nil
        let noSound = CommandLine.arguments.contains("--no-sound")
        return testing || noSound
    }()

    #if os(iOS)
    // iOS: Musik als Knoten in der gemeinsamen SFX-Engine. `lock` schützt Knoten + Index gegen
    // den Completion-Handler des Schedulers (läuft auf einem internen Audio-Thread).
    private let lock = NSLock()
    private var musicNode: AVAudioPlayerNode?
    private var started = false
    #else
    // macOS: eigenständiger AVAudioPlayer.
    private var player: AVAudioPlayer?
    #endif

    private override init() {
        super.init()
        loadTracks()
    }

    /// Lädt die mitgelieferten Musik-Tracks aus dem Modul-Bundle.
    private func loadTracks() {
        // Reihenfolge bestimmt die Abwechslung; weitere Tracks hier ergänzen.
        let names = ["asteroid-storm", "neon-vectors"]
        for name in names {
            if let url = Bundle.module.url(forResource: name, withExtension: "mp3", subdirectory: "Music") {
                tracks.append(url)
            }
        }
    }

    /// Startet die Wiedergabe (falls aktiviert und noch nicht laufend).
    public func start() {
        guard isEnabled, !isPlaybackSuppressed, !isSuppressed, !tracks.isEmpty else { return }
        #if os(iOS)
        startEngineMusic()
        #else
        if player?.isPlaying == true { return }
        if let existing = player {
            existing.play() // aus Pause fortsetzen
        } else {
            playCurrent()
        }
        #endif
    }

    /// Schaltet die Musik ein bzw. aus.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            #if os(iOS)
            lock.lock()
            musicNode?.pause()
            lock.unlock()
            #else
            player?.pause()
            #endif
        }
    }

    /// Pausiert oder reaktiviert die Theme-Musik, ohne den „M"-Schalter zu verändern.
    func setPlaybackSuppressed(_ suppressed: Bool) {
        guard isPlaybackSuppressed != suppressed else { return }
        isPlaybackSuppressed = suppressed
        if suppressed {
            #if os(iOS)
            lock.lock()
            musicNode?.pause()
            lock.unlock()
            #else
            player?.pause()
            #endif
        } else {
            start()
        }
    }

    /// Umschalten (für die „M"-Taste).
    public func toggle() {
        setEnabled(!isEnabled)
    }

    #if os(iOS)

    // MARK: - iOS: Musik über die gemeinsame Engine

    /// Startet (oder setzt fort) die Musik als Knoten an der SFX-Engine.
    private func startEngineMusic() {
        lock.lock()
        defer { lock.unlock() }

        // Schon eingerichtet → nur aus der Pause fortsetzen.
        if started {
            musicNode?.play()
            return
        }

        // Knoten anhand des Formats des ersten Tracks erzeugen. Alle Tracks liegen im selben
        // Format vor (48 kHz Stereo), daher genügt das Format des ersten zum Verbinden.
        guard let firstURL = tracks.first,
              let firstFile = try? AVAudioFile(forReading: firstURL),
              let node = SoundManager.shared.makeMusicNode(format: firstFile.processingFormat) else {
            return
        }
        musicNode = node
        node.volume = 0.8
        started = true

        // Nach einem Engine-Neustart (Konfigurationswechsel) muss der Knoten neu eingeplant werden –
        // die Engine hat beim Stopp alle geplanten Daten verworfen.
        SoundManager.shared.onEngineReset = { [weak self] in
            self?.handleEngineReset()
        }

        scheduleCurrentLocked()
        node.play()
    }

    /// Nach einem Engine-Neustart den (noch attachten) Knoten neu einplanen und nur dann
    /// weiterspielen, wenn weder Einstellung noch Classic-Modus die Musik pausieren.
    private func handleEngineReset() {
        lock.lock()
        defer { lock.unlock() }
        guard started, let node = musicNode, !isSuppressed else { return }
        node.stop()              // verwirft Reste, setzt den Knoten zurück
        scheduleCurrentLocked()  // aktuellen Track neu anhängen
        if isEnabled && !isPlaybackSuppressed {
            node.play()
        }
    }

    /// Plant den aktuellen Track ein; im Completion-Handler wird auf den nächsten Track gewechselt
    /// und dieser angehängt – so läuft die Playlist in Endlosschleife. „Locked" = der Aufrufer hält
    /// bereits `lock`.
    private func scheduleCurrentLocked() {
        guard let node = musicNode, index >= 0, index < tracks.count else { return }
        guard let file = try? AVAudioFile(forReading: tracks[index]) else { return }
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            // Zum nächsten Track wechseln (abwechselnd, dann von vorn).
            if !self.tracks.isEmpty {
                self.index = (self.index + 1) % self.tracks.count
            }
            if self.isEnabled && !self.isPlaybackSuppressed && !self.isSuppressed {
                self.scheduleCurrentLocked()
            }
        }
    }

    #else

    // MARK: - macOS: eigenständiger AVAudioPlayer

    private func playCurrent() {
        guard index >= 0 && index < tracks.count else { index = 0; return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: tracks[index])
            newPlayer.delegate = self
            newPlayer.volume = 0.8
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            print("MusicPlayer: Track konnte nicht geladen werden: \(error)")
        }
    }

    #endif
}

#if !os(iOS)
// Nur macOS verwendet AVAudioPlayer. Die Conformance darf nicht am gemeinsamen Typ hängen, weil
// dessen MainActor-Isolation sonst auch in den iOS-Audio-Callbacks fälschlich inferiert wird.
extension MusicPlayer: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Zum nächsten Track wechseln (abwechselnd, dann von vorn).
        if !tracks.isEmpty {
            index = (index + 1) % tracks.count
        }
        if isEnabled && !isPlaybackSuppressed && !isSuppressed {
            playCurrent()
        }
    }
}
#endif
