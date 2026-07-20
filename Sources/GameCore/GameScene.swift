import SpriteKit
// AppKit wird nur für die macOS-Tastatur-Brücke (NSEvent) gebraucht und existiert auf iOS nicht.
#if canImport(AppKit)
import AppKit
#endif

/// A structure representing a saved high score entry.
public struct HighScore: Codable, Sendable {
    public let initials: String
    public let score: Int
    public let date: Date
    public let deathMessage: String?
    /// Kompakt kodierte Aufnahme dieses Laufs (`Replay.encoded()`), falls vorhanden. Optional, damit
    /// ältere persistierte Einträge ohne Replay weiterhin dekodieren. In JSON als Base64 gespeichert.
    public let replayData: Data?

    public init(initials: String, score: Int, date: Date, deathMessage: String? = nil,
                replayData: Data? = nil) {
        self.initials = initials
        self.score = score
        self.date = date
        self.deathMessage = deathMessage
        self.replayData = replayData
    }
}

/// The state of the gameplay scene.
public enum GameState: Sendable {
    case startScreen
    case playing
    case nameEntry
    case gameOver
    case quitConfirmation
    case glossary
    /// Eigene Highscore-Ansicht (mit Zurück). Wird nur auf iOS angesteuert, wenn die
    /// Highscore-Liste vom Startbildschirm in eine separate Ansicht ausgelagert ist.
    case highScores
    /// Einstellungen (Musik / SFX-Stil / Auto-Feuer). Erreichbar vom Startbildschirm.
    case settings
}

/// Auswählbarer Spielmodus. `UInt8`-rawValue + `Codable` für stabile Persistenz im Replay-Format
/// (ancientAsteroids = 0, madMeteoroids = 1 – bestehende Werte nie ändern, sonst werden alte
/// Replays falsch dekodiert; Classic wurde kompatibel als 2 angehängt).
public enum GameMode: UInt8, Sendable, Codable {
    /// Klassischer Modus: festes Spielfeld, Objekte wrappen an den Bildschirmkanten.
    case ancientAsteroids = 0
    /// Neuer Modus: das gesamte Spielfeld (Objekte + Sternenfeld) rotiert kontinuierlich um die
    /// Bildschirmmitte, nur das Spieler-Raumschiff bleibt davon unberührt (vgl. Crazy Comets).
    case madMeteoroids = 1
    /// Arcade-orientierter Einspieler-Modus mit Wellen, drei Schiffen und monochromen Vektoren.
    case classicAsteroids = 2

    var next: GameMode {
        switch self {
        case .ancientAsteroids: return .madMeteoroids
        case .madMeteoroids: return .classicAsteroids
        case .classicAsteroids: return .ancientAsteroids
        }
    }

    var previous: GameMode {
        switch self {
        case .ancientAsteroids: return .classicAsteroids
        case .madMeteoroids: return .ancientAsteroids
        case .classicAsteroids: return .madMeteoroids
        }
    }
}

/// Zentrale Gameplay-Tuning-Konstanten (Waffen, Einsammeln, Splits) — nach dem Muster von
/// `MadRotation`/`LevelSpawnConfig`. Vorher lagen diese Werte inline im Code verstreut;
/// hier justieren, statt im 4000-Zeilen-Ablauf zu suchen. Werte unverändert übernommen
/// (Replay-Determinismus: gleiche Zahlen, gleiche Läufe).
enum GameplayTuning {
    /// Schuss-Abklingzeit in Sekunden mit aktivem Rapid-Fire-Power-up.
    static let laserCooldownRapid: TimeInterval = 0.06
    /// Schuss-Abklingzeit in Sekunden ohne Rapid Fire.
    static let laserCooldownNormal: TimeInterval = 0.15
    /// Seitlicher Streuwinkel (Radiant) der äußeren Schüsse beim Triple-Shot.
    static let tripleShotSpreadAngle: CGFloat = 0.25
    /// Einsammel-Radius für Power-ups (Abstand Schiff↔Power-up in Punkten).
    static let powerUpCollectRadius: CGFloat = 40.0
    /// Wachstum der Skalierung eines absorbierenden Asteroiden pro geschlucktem Asteroiden.
    static let asteroidAbsorbGrowthStep: CGFloat = 0.35
    /// Geschwindigkeits-Faktor der Splitter beim Asteroiden-Split (schneller als der Elter).
    static let asteroidSplitSpeedFactor: CGFloat = 1.35
    /// Implosions-Kollaps: Sog-Stärke des kurzlebigen Schwerkraft-Lochs …
    static let implosionCollapseStrength: CGFloat = 1280000.0
    /// … und seine Lebensdauer in Sekunden (bewusst kurz, nur der „Nachschlag").
    static let implosionCollapseLifetime: TimeInterval = 4.0
}

/// Level-based difficulty and entity spawn weight configuration.
public struct LevelSpawnConfig: Sendable {
    public let level: Int
    public let maxAsteroids: Int
    public let spawnRate: TimeInterval
    public let speedMultiplier: CGFloat
    public let powerUpChance: Double
    public let normalWeight: Int
    public let implodingWeight: Int
    public let wobblingWeight: Int
    public let ufoInterval: TimeInterval?
    public let blackHoleInterval: TimeInterval?
}

/// The main gameplay scene representing the Asteroids arena.
/// Handles ship setup, player inputs (keyboard), lasers, wrapping around edges, and physics updates.
public final class GameScene: SKScene {
    
    public enum DeathCause: Sendable {
        case largeAsteroid
        case mediumAsteroid
        case smallAsteroid
        case wobblingAsteroid
        case ufo
        case ufoLaser
        case gravityWell
        case bossHead
        case spaceCat        // von einer Weltraumkatze gerammt
        case spaceCatLaser   // von den Laseraugen einer Weltraumkatze getroffen
        case hyperspaceMalfunction
    }
    
    public var lastDeathCause: DeathCause = .largeAsteroid
    let powerUpNotificationLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    // Level configurations registry
    public static let levelConfigs: [LevelSpawnConfig] = [
        // Schwierigkeitskurve bewusst flach gehalten: weniger Objekte und langsamerer Anstieg von
        // Tempo/Spawn-Frequenz, damit das mittlere Level (5) sich auch wie Mitte anfühlt.
        LevelSpawnConfig(level: 1, maxAsteroids: 3, spawnRate: 2.8, speedMultiplier: 1.0, powerUpChance: 0.12, normalWeight: 100, implodingWeight: 0, wobblingWeight: 0, ufoInterval: nil, blackHoleInterval: nil),
        LevelSpawnConfig(level: 2, maxAsteroids: 4, spawnRate: 2.4, speedMultiplier: 1.08, powerUpChance: 0.14, normalWeight: 90, implodingWeight: 0, wobblingWeight: 10, ufoInterval: 35.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 3, maxAsteroids: 4, spawnRate: 2.1, speedMultiplier: 1.16, powerUpChance: 0.16, normalWeight: 85, implodingWeight: 5, wobblingWeight: 10, ufoInterval: 30.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 4, maxAsteroids: 5, spawnRate: 1.8, speedMultiplier: 1.24, powerUpChance: 0.18, normalWeight: 74, implodingWeight: 9, wobblingWeight: 17, ufoInterval: 25.0, blackHoleInterval: nil),
        LevelSpawnConfig(level: 5, maxAsteroids: 6, spawnRate: 1.5, speedMultiplier: 1.32, powerUpChance: 0.20, normalWeight: 66, implodingWeight: 12, wobblingWeight: 22, ufoInterval: 20.0, blackHoleInterval: 110.0)
    ]
    
    public func configForLevel(_ lvl: Int) -> LevelSpawnConfig {
        if lvl > GameScene.levelConfigs.count {
            let last = GameScene.levelConfigs.last!
            let extraLevels = lvl - 5
            return LevelSpawnConfig(
                level: lvl,
                maxAsteroids: min(13, last.maxAsteroids + extraLevels),
                spawnRate: max(0.6, last.spawnRate - Double(extraLevels) * 0.07),
                speedMultiplier: min(2.6, last.speedMultiplier + CGFloat(extraLevels) * 0.08),
                powerUpChance: min(0.35, last.powerUpChance + Double(extraLevels) * 0.02),
                normalWeight: max(40, last.normalWeight - extraLevels * 4),
                implodingWeight: min(20, last.implodingWeight + extraLevels),
                wobblingWeight: min(40, last.wobblingWeight + extraLevels * 2),
                ufoInterval: max(8.0, (last.ufoInterval ?? 15.0) - Double(extraLevels) * 0.8),
                blackHoleInterval: max(70.0, (last.blackHoleInterval ?? 110.0) - Double(extraLevels) * 1.5)
            )
        }
        return GameScene.levelConfigs[max(1, min(lvl, GameScene.levelConfigs.count)) - 1]
    }
    
    // MARK: - Properties
    
    /// The player's spaceship.
    public private(set) var ship: Ship!
    
    /// Active lasers currently in the scene.
    public internal(set) var activeLasers: [Laser] = []
    
    /// Active asteroids currently in the scene.
    public internal(set) var activeAsteroids: [Asteroid] = []
    
    /// The current state of the game.
    public private(set) var gameState: GameState = .startScreen
    
    /// Whether the game is in a Game Over state (for test compatibility).
    public var isGameOver: Bool {
        return gameState == .gameOver || gameState == .nameEntry
    }
    
    /// The player's current score.
    public internal(set) var score: Int = 0
    
    /// Persistent high scores.
    public private(set) var highScores: [HighScore] = []
    private var standardHighScores: [HighScore] = []
    private var classicHighScores: [HighScore] = []
    /// Persistenz für Highscores + maximal erreichtes Level (UserDefaults-Details ausgelagert).
    private let highScoreStore = HighScoreStore()

    // MARK: - Plattform-Layout-Konfiguration (vom Host gesetzt)
    // Defaults erhalten das bisherige macOS-Verhalten 1:1. Der iOS-Host schaltet sie um.

    /// true = kompaktes, touch-orientiertes Menü-Layout fürs iPhone-Breitformat
    /// (Titel sichtbar positioniert, keyboard-zentrierte Hinweise ausgeblendet).
    /// false (Default) = unverändertes 4:3-Layout (macOS).
    public var isCompactLayout: Bool = false

    /// true (Default) = Highscore-Liste erscheint am Startbildschirm (macOS).
    /// false = Liste ist ausgelagert in die eigene `.highScores`-Ansicht (iOS).
    public var showsHighScoresOnStartScreen: Bool = true

    // MARK: - Vollbild-Präferenz (native Umsetzung ausschließlich durch den Host)

    /// Zuletzt erfolgreich bestätigter nativer Vollbildzustand. Ohne gespeicherten Wert startet
    /// die App weiterhin im Fenster. Der Wert beeinflusst weder Simulation noch Replaydaten.
    public private(set) var fullScreenEnabled: Bool = FullScreenPreferenceStore.load()

    /// Nur der macOS-Host aktiviert diese Zeile. iOS ist ohnehin immer bildschirmfüllend und lässt
    /// die plattformspezifische Einstellung deshalb vollständig verborgen.
    public private(set) var isFullScreenSettingAvailable: Bool = false

    /// Teilt der gemeinsamen Settings-Ansicht mit, ob der konkrete Host natives Vollbild anbietet.
    /// Die AppKit-Shell ruft dies vor dem Präsentieren der Scene mit `true` auf.
    public func configureFullScreenSetting(available: Bool) {
        isFullScreenSettingAvailable = available
        settingsFullScreenLabel.isHidden = gameState != .settings || !available
        updateSettingsLabels()
    }

    /// Übernimmt ausschließlich einen vom Host bestätigten nativen Fensterzustand und persistiert
    /// ihn. Dadurch können fehlgeschlagene AppKit-Animationen die Einstellung nicht vorzeitig ändern.
    public func synchronizeFullScreenState(_ enabled: Bool) {
        guard isFullScreenSettingAvailable else { return }
        fullScreenEnabled = enabled
        FullScreenPreferenceStore.save(enabled)
        updateSettingsLabels()
    }

    // MARK: - HDR-Vektorglühen (Displaydaten kommen ausschließlich vom Host)

    /// Vom Spieler gewählte, dauerhaft gespeicherte Präferenz. Sie kann auch `true` bleiben, wenn
    /// das aktuelle Display kein EDR unterstützt, damit ein später angeschlossenes HDR-Display die
    /// Einstellung automatisch wieder übernimmt.
    public private(set) var hdrGlowEnabled: Bool = HDRGlowPreferenceStore.load()

    /// Ob der tatsächlich hostende Bildschirm einen nutzbaren EDR-Pfad anbietet.
    public private(set) var isHDRGlowAvailable: Bool = false

    /// Die macOS-/iOS-Shell reagiert hierauf, indem sie den CAMetalLayer-Modus umschaltet.
    public var onHDRGlowPreferenceChanged: ((Bool) -> Void)?

    private var hdrGlowCurrentHeadroom: CGFloat = 1.0

    /// Aktualisiert die vom konkreten Bildschirm gelieferten EDR-Daten. Der Wert beeinflusst nur
    /// Shader-Uniforms und niemals Simulation, RNG oder Replay-Aufzeichnung.
    public func updateHDRDisplay(available: Bool, currentHeadroom: CGFloat) {
        let availabilityChanged = isHDRGlowAvailable != available
        isHDRGlowAvailable = available
        hdrGlowCurrentHeadroom = max(1.0, currentHeadroom)
        applyHDRGlowRenderState()
        if availabilityChanged { updateSettingsLabels() }
    }

    private func applyHDRGlowRenderState() {
        VectorGlowRenderer.update(
            in: self,
            active: hdrGlowEnabled && isHDRGlowAvailable,
            headroom: hdrGlowCurrentHeadroom
        )
    }

    private func toggleHDRGlow() {
        guard isHDRGlowAvailable else { return }
        hdrGlowEnabled.toggle()
        HDRGlowPreferenceStore.save(hdrGlowEnabled)
        applyHDRGlowRenderState()
        updateSettingsLabels()
        onHDRGlowPreferenceChanged?(hdrGlowEnabled)
    }

    /// Temporary storage for initials entry.
    var typedInitials: String = ""

    /// Anzahl der bereits eingegebenen Initialen (0…3). Nur lesend – wird von der iOS-Tastatur
    /// (UIKeyInput.hasText) gebraucht, damit die Löschtaste korrekt arbeitet. macOS nutzt das nicht.
    public var enteredInitialsCount: Int { typedInitials.count }
    
    // Spielmodus-Auswahl
    /// Der aktuell laufende Spielmodus.
    public private(set) var gameMode: GameMode = .ancientAsteroids
    /// Der auf dem Startscreen vorgewählte Modus.
    var selectedMode: GameMode = .ancientAsteroids
    /// Öffentliche Nur-Lese-Sicht für die iOS-Shell, damit deren Menütasten der Auswahl folgen.
    public var selectedGameMode: GameMode { selectedMode }

    /// Kleine, ausschließlich im dritten Modus genutzte Sitzungsstruktur. Ancient/Mad lesen oder
    /// mutieren sie nicht und behalten damit ihren bisherigen Simulationspfad.
    var classicSession = ClassicSession()

    // Mad-Meteoroids: Rotations-Zustand des Spielfelds (nur im madMeteoroids-Modus aktiv)
    /// Aktuelle Winkelgeschwindigkeit des Feldes in Radiant/Sekunde (Vorzeichen = Drehrichtung).
    var fieldAngularVelocity: CGFloat = 0.0
    /// In diesem Frame angewandte Drehung in Radiant (von Objekten + Sternen genutzt).
    var fieldDeltaThisFrame: CGFloat = 0.0
    /// Vorzeichen der aktuellen Drehrichtung (+1 oder -1).
    var fieldRotationDirection: CGFloat = 1.0
    /// Zeitpunkt des nächsten geplanten Richtungswechsels.
    var nextDirectionChangeTime: TimeInterval = .greatestFiniteMagnitude
    /// Abstand zwischen Richtungswechseln im aktuellen Level (Sekunden).
    var directionChangeInterval: TimeInterval = 0.0
    /// Verbleibende Richtungswechsel im aktuellen Level (Int.max ab Level 10).
    var directionChangesRemaining: Int = 0
    /// Ob gerade ein Plattenscratch (Vor-Zurück-Ruck) läuft.
    var scratchActive: Bool = false
    /// Bereits verstrichene Zeit im aktuellen Scratch.
    var scratchElapsed: TimeInterval = 0.0
    /// Flag: Beim nächsten Frame den Rotations-Scheduler fürs aktuelle Level neu aufsetzen
    /// (gesetzt aus `transitionTo`/Level-Aufstieg, da dort die absolute Spielzeit fehlt).
    private var fieldRotationPending: Bool = false

    // Level and countdown progression state
    public internal(set) var currentLevel: Int = 1
    public private(set) var maxLevelReached: Int = 1
    public internal(set) var selectedStartLevel: Int = 1
    public internal(set) var levelTimeRemaining: TimeInterval = 120.0
    public private(set) var isLevelClearing: Bool = false
    private var levelClearEndTime: TimeInterval = 0.0
    
    // MARK: - Determinismus / Replay (Phase 1.2)

    /// Geseedeter Zufallsgenerator für die gesamte Spiel-Logik. Wird bei jedem frischen Spielstart
    /// neu aus `currentSeed` aufgesetzt. Alle gameplay-relevanten `.random`-Aufrufe ziehen in
    /// Phase 1.3 nach und nach hierüber (`Int.random(in:using:&rng)`), damit ein Lauf bei gleichem
    /// Seed exakt reproduzierbar ist.
    var rng: GameRandom = GameRandom(seed: 0)

    /// Der Seed des aktuell laufenden Spiels. Nach `startNewGame` gesetzt und auslesbar (u. a. für
    /// die spätere Replay-Aufnahme und für Tests).
    public private(set) var currentSeed: UInt64 = 0

    /// Optional injizierter Seed für den nächsten frischen Spielstart (Replay/Test). Ist er gesetzt,
    /// wird er beim nächsten Fresh-Game übernommen und danach geleert; sonst würfelt das Spiel einen
    /// neuen Seed aus dem System-RNG (einmalig, der einzige nicht-deterministische Punkt).
    private var pendingSeed: UInt64?

    /// Akkumulierte Spielzeit (Summe aller angewandten `dt`). Die EINZIGE Zeitquelle für die
    /// Spiel-Logik: Power-up-Ablauf, Spawn-/Boss-/Katzen-Timer und Laser-Cooldown rechnen alle gegen
    /// `gameTime`, nie gegen Echtzeit (`systemUptime`) oder die rohe SpriteKit-`currentTime`. Dadurch
    /// hängt ein Lauf nur an (Seed + dt-Folge) und ist reproduzierbar. Wird bei jedem frischen
    /// Spielstart auf 0 zurückgesetzt.
    private(set) var gameTime: TimeInterval = 0.0

    /// Aufzeichnung des laufenden Spiels (Seed + Eingaben + dt-Folge). Wird bei jedem frischen
    /// Spielstart neu angelegt (außer während eines Replays) und bei Game Over zu `lastReplay`
    /// finalisiert.
    var recorder: ReplayRecorder?

    /// Läuft gerade eine Replay-Wiedergabe? Dann ist dieser Player gesetzt; er liefert pro Frame das
    /// aufgezeichnete `dt` und speist die aufgezeichneten Eingaben ein. Live-Eingaben sind gesperrt.
    var replayPlayer: ReplayPlayer?

    /// Schutzflag: true, während der `replayPlayer` gerade eine aufgezeichnete Eingabe einspeist –
    /// so unterscheidet `handleKeyDown/Up` injizierte von (gesperrten) Live-Eingaben.
    private var isInjectingReplay = false

    /// Erzwingt beim nächsten `startReplay` einen Auto-Feuer-Zustand, unabhängig von dem in der
    /// Aufnahme gespeicherten. Nötig für ALTE Aufnahmen (vor dem autoFire-Fix), die das Feld nicht
    /// enthalten – z. B. um einen mit Auto-Feuer gespielten Lauf korrekt nachzustellen. `nil` = den
    /// in der Aufnahme gespeicherten Wert verwenden.
    public var replayAutoFireOverride: Bool?

    /// Die zuletzt fertig aufgezeichnete Aufnahme (gesetzt bei Game Over). Grundlage, um ein Replay
    /// an einen Highscore zu hängen (Phase 2.4).
    public private(set) var lastReplay: Replay?

    /// Verzeichnis, in das bei Game Over die Aufnahme JEDES Laufs als Datei geschrieben wird –
    /// unabhängig davon, ob der Lauf ein Highscore wird. Damit lässt sich nach einem guten Spiel ein
    /// GIF aus dem letzten Lauf rendern, ohne dass er in die Highscore-Liste muss. `nil` = aus
    /// (Default für Tests/Headless, damit kein Test echte Dateien schreibt); die App-Hosts (ExploidsMac)
    /// setzen es auf das Replay-Archiv.
    public var replaySaveDirectory: URL?
    /// Wie viele Aufnahmedateien das Archiv behält (älteste werden beim Überlauf gelöscht).
    public var replayArchiveLimit: Int = 40

    /// Headless-Render-Modus: HUD/Overlay (Score, Timer, Level, Leben, „REPLAY") dauerhaft
    /// ausgeblendet, damit ein gerendertes Promo-GIF sauber bleibt (Phase 3.5).
    private var renderHUDHidden = false

    // Difficulty and Time state
    public internal(set) var playTime: TimeInterval = 0.0
    
    /// Dynamic difficulty factor from 1.0 up to 2.5 scaling over 10 minutes.
    public var difficultyFactor: CGFloat {
        let maxDifficultyTime: TimeInterval = 600.0 // 10 minutes
        let progress = min(1.0, playTime / maxDifficultyTime)
        return 1.0 + 1.5 * CGFloat(progress)
    }
    
    /// Spawn cooldown settings
    public var isSpawningEnabled: Bool = true
    private var lastSpawnTime: TimeInterval = 0.0
    
    func currentConfig() -> LevelSpawnConfig {
        let base: LevelSpawnConfig
        if currentLevel >= 10 {
            let effectiveLevel = 10 + Int(playTime / 60.0)
            base = configForLevel(effectiveLevel)
        } else {
            base = configForLevel(currentLevel)
        }

        // Der Mad-Modus ist durch die rotierende Spielfläche ohnehin anspruchsvoller. Damit er
        // fair bleibt: weniger Objekte gleichzeitig und mehr Power-Ups. (Tuning hier anpassen.)
        guard gameMode == .madMeteoroids else { return base }
        let madAsteroidFactor = 0.6      // ~40 % weniger Asteroiden gleichzeitig
        let madPowerUpFactor = 2.0       // doppelte Power-Up-Chance
        let madPowerUpCap = 0.5          // aber höchstens 50 %
        let reducedAsteroids = max(3, Int((Double(base.maxAsteroids) * madAsteroidFactor).rounded()))
        let boostedPowerUp = min(madPowerUpCap, base.powerUpChance * madPowerUpFactor)
        return LevelSpawnConfig(
            level: base.level,
            maxAsteroids: reducedAsteroids,
            spawnRate: base.spawnRate,
            speedMultiplier: base.speedMultiplier,
            powerUpChance: boostedPowerUp,
            normalWeight: base.normalWeight,
            implodingWeight: base.implodingWeight,
            wobblingWeight: base.wobblingWeight,
            ufoInterval: base.ufoInterval,
            blackHoleInterval: base.blackHoleInterval
        )
    }

    // Active Entities
    public internal(set) var activeUFOs: [UFO] = []
    public internal(set) var activeGravityWells: [GravityWell] = []
    public internal(set) var activePowerUps: [PowerUp] = []
    private var options: [OptionDrone] = []

    /// Aktiver Kopf-Boss („Der Götze"), falls gerade einer im Bild ist (max. einer gleichzeitig).
    public internal(set) var activeHead: FloatingHead?
    /// In welchem Level der Kopf-Boss zum ersten Mal auftaucht – pro Spiel zufällig 5–7.
    /// Wird in `transitionTo(.playing)` mit geseedetem `rng` neu gesetzt; der Default hier
    /// hat keine Wirkung, soll aber einen gültigen Startwert ergeben (nicht 0 oder falsch).
    private var bossFirstTargetLevel: Int = 5
    /// Ob der erste Auftritt (Level 5–7) bereits erfolgt ist.
    private var bossFirstDone: Bool = false
    /// Ob der Auftritt in Level 10 bereits erfolgt ist.
    private var bossLevel10Done: Bool = false
    /// Nächster zeitgesteuerter Auftritt in Level 10 (alle 4–7 Min, da es kein weiteres Level gibt).
    private var nextBossTimeLevel10: TimeInterval = 0.0
    /// Flanken-Erkennung: war der Kopf im letzten Frame in der Spawn-Phase? (für den Sample-Trigger)
    private var headWasSpawning: Bool = false

    /// Aktive Weltraumkatzen (Minibosse), die gerade im Bild sind.
    public internal(set) var activeCats: [SpaceCat] = []
    /// Ab diesem Level können Katzen auftauchen (vor dem Kopf-Boss in 5–7).
    private let catFirstLevel: Int = 3
    /// Wie viele Katzen gleichzeitig erlaubt sind (bewusst klein – sie sollen besonders bleiben).
    private let maxActiveCats: Int = 1
    /// Ob der Katzen-Timer schon scharfgestellt wurde (erst ab Eignung).
    private var catTimerArmed: Bool = false
    /// Zeitpunkt des nächsten Katzen-Spawns (absolute Spielzeit).
    private var nextCatTime: TimeInterval = 0.0

    // Power-up durations
    var tripleShotEndTime: TimeInterval = 0.0
    var rapidFireEndTime: TimeInterval = 0.0
    private var beamEndTime: TimeInterval = 0.0       // Laserbeam (Space halten)
    private var rearLaserEndTime: TimeInterval = 0.0  // Zusätzlicher Schuss nach hinten
    private var compressEndTime: TimeInterval = 0.0   // Schiff auf ~30% verkleinert

    /// Gespeicherte Extra-Leben (Revive in der Mitte statt Game Over).
    var extraLives: Int = 0

    // Power-up-Tuning (Dauer in Sekunden) – hier zentral justierbar.
    private let beamDuration: TimeInterval = 10.0
    private let rearLaserDuration: TimeInterval = 12.0
    private let compressDuration: TimeInterval = 24.0
    private let compressScale: CGFloat = 0.3          // Stufe 1
    private let compressLevel2Scale: CGFloat = 0.04   // Stufe 2: nur noch ein Pixel
    /// Aktuelle Compress-Stufe (0 = normal, 1 = klein, 2 = winzig). Gilt für Schiff UND Beiboote.
    private var compressLevel: Int = 0
    /// Dämpft die Power-up-Drop-Häufigkeit global (Feedback: kamen zu oft). 1.0 = wie Level-Config.
    private let powerUpDropScale: Double = 0.55
    private let extraLifeInvincibility: TimeInterval = 5.0

    /// Visueller Knoten für den Laserbeam (wird pro Frame neu aufgebaut).
    let beamNode = SKShapeNode()

    // Invincibility state (blinking on shield burst)
    private var invincibilityEndTime: TimeInterval = 0.0
    
    // Feuertaste-Status: gehalten = Dauerfeuer (mit normaler bzw. Rapidfire-Feuerrate).
    private var isSpaceHeld: Bool = false
    /// Auto-Feuer: das Schiff schießt durchgehend von selbst, ohne dass man die Feuertaste hält.
    /// Engine-Default aus (für Headless-Tests); die App-Hosts (macOS/iOS) schalten es zum Start AN
    /// – entspanntes Spielgefühl, ideal fürs iPhone. Umschaltbar (Einstellungen).
    public var autoFire: Bool = false

    // MARK: - Autopilot / Demo-Attract-Modus

    /// Wenn `true`, betreibt die Szene den Attract-/Demo-Kreislauf: nach 30 s Leerlauf am
    /// Startbildschirm (oder auf Tastendruck „D") spielt ein computergesteuerter Pilot eine Demo,
    /// danach 10 s Highscore-Liste + 15 s Startbildschirm, dann die nächste Persona – immer weiter.
    /// Engine-Default aus (Tests/Headless-Render bleiben ruhig); die App-Hosts schalten es an.
    public var attractModeEnabled: Bool = false

    /// Die aktuell aktive Autopilot-Persona. `nil` = ein Mensch spielt (kein Autopilot). Wird beim
    /// Start einer Demo gesetzt und beim Verlassen des Demo-Spiels wieder auf `nil` gelegt.
    var autopilotPersona: AutopilotPersona?

    /// Läuft gerade ein Demo-Lauf (Autopilot steuert das `.playing`)? Steuert zwei Sonderfälle:
    /// KEIN Highscore-Namenseintrag bei Game Over und KEINE Aufnahme/Archivierung des Laufs.
    var isDemoActive: Bool { autopilotPersona != nil }

    /// Eigener geseedeter Zufallsgenerator NUR für den Autopiloten (Skill-„Zittern"/Jitter). Bewusst
    /// getrennt vom Gameplay-RNG (`rng`), damit die KI-Entscheidungen den Spielverlauf-Zufall
    /// (Spawns etc.) nicht verschieben – derselbe Seed erzeugt so mit und ohne Autopilot dieselbe Welt.
    var autopilotRng = GameRandom(seed: 0xA0710_5EED)

    /// Index der nächsten Demo-Persona im Roster (reihum).
    var nextPersonaIndex: Int = 0

    /// Phasen des Attract-Kreislaufs. Menü-Phasen laufen über eine Echtzeit-Uhr (`attractTimer`),
    /// die Demo selbst läuft bis zum Game Over.
    enum AttractPhase {
        case idle          // Startbildschirm, wartet auf Mensch ODER 30 s → Demo
        case demoPlaying   // Autopilot spielt gerade
        case demoScores    // Nach Demo-Game-Over: Highscore-Liste, 10 s
        case demoRestScreen // Startbildschirm zwischen zwei Demos, 15 s → nächste Demo
    }
    var attractPhase: AttractPhase = .idle
    /// In der aktuellen Menü-Attract-Phase verstrichene ECHTZEIT (Sekunden). Nur für idle/scores/rest.
    var attractTimer: TimeInterval = 0.0

    // Enemy Spawning times
    private var lastUFOSpawnTime: TimeInterval = 0.0
    private var lastGravityWellSpawnTime: TimeInterval = 0.0
    
    // UI Label Nodes
    let titleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let startPromptLabel = SKLabelNode(fontNamed: "Courier")
    let instructionsLabel = SKLabelNode(fontNamed: "Courier")
    
    let scoreLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let hiScoreLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    let nameEntryPromptLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let nameEntryInputLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    let gameOverLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let finalScoreLabel = SKLabelNode(fontNamed: "Courier")
    let restartLabel = SKLabelNode(fontNamed: "Courier")

    /// Overlay-Hinweis „▶ REPLAY", oben sichtbar, solange eine Aufnahme abgespielt wird.
    let replayOverlayLabel = SKLabelNode(fontNamed: "Courier-Bold")
    
    let highScoresTitleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    var highScoreLineLabels: [SKLabelNode] = []
    
    // Level and HUD labels
    let timerLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let levelLabel = SKLabelNode(fontNamed: "Courier")
    let livesLabel = SKLabelNode(fontNamed: "Courier")
    let levelSelectionLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let modeSelectionLabel = SKLabelNode(fontNamed: "Courier-Bold")
    // Einstellungen-Ansicht: Titel + Umschalt-Zeilen + Bedien-Hinweis.
    let settingsTitleLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let settingsMusicLabel = SKLabelNode(fontNamed: "Courier")
    let settingsSfxLabel = SKLabelNode(fontNamed: "Courier")
    let settingsAutoFireLabel = SKLabelNode(fontNamed: "Courier")
    let settingsHDRGlowLabel = SKLabelNode(fontNamed: "Courier")
    let settingsFullScreenLabel = SKLabelNode(fontNamed: "Courier")
    let settingsHintLabel = SKLabelNode(fontNamed: "Courier")
    let levelClearedLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let prepareNextLevelLabel = SKLabelNode(fontNamed: "Courier")
    
    // Quit Confirmation Overlay
    let quitPromptLabel = SKLabelNode(fontNamed: "Courier-Bold")
    let quitSubPromptLabel = SKLabelNode(fontNamed: "Courier")
    
    // Glossary Elements
    let glossaryContainer = SKNode()
    let glossaryStaticContainer = SKNode()
    let glossaryPromptLabel = SKLabelNode(fontNamed: "Courier")

    /// Startbildschirm-Hinweis „PRESS D FOR DEMO" (nur sichtbar, wenn der Attract-Modus aktiv ist).
    let demoPromptLabel = SKLabelNode(fontNamed: "Courier")
    /// Overlay während eines laufenden Demo-Laufs: zeigt „DEMO — <PERSONA>", damit klar ist, dass
    /// gerade der Autopilot spielt (und kein Mensch).
    let demoOverlayLabel = SKLabelNode(fontNamed: "Courier-Bold")
    /// Y-Position des untersten Glossar-Eintrags (für die Scroll-Schleifengrenzen).
    var glossaryContentBottom: CGFloat = -750
    
    /// Currently pressed keys.
    var activeKeys = Set<UInt16>()
    
    /// The timestamp of the last update.
    private var lastUpdateTime: TimeInterval = 0.0

    // MARK: - Fixed-Timestep

    /// Schritte pro Sekunde der Simulation. 120 passt zu ProMotion (120 Hz): im Idealfall genau ein
    /// Sim-Schritt pro Bild → praktisch identisches Spielgefühl wie der frühere variable Zeitschritt,
    /// nur eben fest. Bei spürbarem Stottern auf 240 erhöhen (feiner, robuster gegen Takt-Jitter).
    public static let simStepsPerSecond: Int = 120
    /// Fester Simulationszeitschritt in Sekunden. Jeder Schritt rechnet mit exakt diesem `dt`; dadurch
    /// hängt ein Lauf nur an (Seed + Eingaben) und das Replay ist ohne aufgezeichnete dt-Folge bit-exakt.
    public static let simStep: TimeInterval = 1.0 / Double(simStepsPerSecond)
    /// Aufgelaufene Echtzeit, die noch nicht in Sim-Schritte umgesetzt wurde (Fixed-Timestep-Akkumulator).
    private var timeAccumulator: TimeInterval = 0.0
    /// Obergrenze für die pro Bild verarbeitete Echtzeit. Nach einem Hänger (Fenster-Drag, App im
    /// Hintergrund) wird NICHT die ganze aufgestaute Zeit als Sim-Schritte nachgeholt (sonst langer
    /// Catch-up-Hänger / Zeit-Sprung). Default `.infinity` = aus; die echten App-Hosts (`ExploidsMac`,
    /// iOS) setzen einen sinnvollen Wert (0.25 s). Tests/Headless lassen ihn aus, damit sie die
    /// Simulation per großem `update(_:)`-Sprung deterministisch vorspulen können.
    public var maxFrameDelta: TimeInterval = .infinity
    /// Wenn `true`, wird die Simulation von außen über `advanceOneStep()` getrieben (headless
    /// GIF-Renderer, Tests) und der Echtzeit-Akkumulator in `update(_:)` macht nichts.
    public var externalStepDriving: Bool = false

    /// The timestamp when the last laser was fired.
    private var lastLaserTime: TimeInterval = 0.0
    
    /// Camera node for screen shake effects.
    private let cameraNode = SKCameraNode()
    
    /// Background stars.
    private var stars: [StarNode] = []
    
    // MARK: - Scene Lifecycle
    
    public override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Gebündelten Pixel-Font registrieren, bevor die Labels konfiguriert werden.
        RetroFont.registerIfNeeded()

        // Jeder neue Scene-Lauf setzt den prozessweit geteilten Shaderzustand aus seinen eigenen
        // Hostdaten. Headless-Renderer und Tests bleiben dadurch zuverlässig im SDR-Pfad.
        applyHDRGlowRenderState()

        // Center the anchor point for a retro coordinate system centered at (0, 0)
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        // Setup camera node
        self.addChild(cameraNode)
        self.camera = cameraNode
        cameraNode.position = .zero
        
        // Setup starfield
        setupStarfield()
        
        // Instantiate and add the ship at the center
        self.ship = Ship()
        self.ship.position = .zero
        self.addChild(self.ship)
        
        // Load high scores from storage (lädt auch maxLevelReached mit)
        loadHighScores()
        selectedStartLevel = 1
        
        // Setup UI Labels
        setupUIElements()
        
        // If we are running unit tests, start in .playing directly, otherwise start in .startScreen
        if NSClassFromString("XCTestCase") != nil {
            transitionTo(.playing)
        } else {
            transitionTo(.startScreen)
        }
        
        // Tastatur-Fokus sicherstellen: Die hostende SKView muss First Responder des Fensters sein,
        // sonst erreichen keyDown-Events die Scene nicht. Beim Aufruf von didMove ist das Fenster
        // noch nicht fertig (view.window == nil), daher verzögert auf dem Main-Loop nachsetzen.
        // Nur macOS: First-Responder/keyDown gibt es auf iOS nicht – dort kommt die Eingabe per Touch.
        #if canImport(AppKit)
        DispatchQueue.main.async { [weak view] in
            guard let view = view else { return }
            view.window?.makeFirstResponder(view)
        }
        #endif
    }
    
    // MARK: - Input Handling

    /// Wird ausgelöst, wenn der Spieler die App beenden will (Cmd+Q auf macOS). Die Plattform-Shell
    /// legt das konkrete Verhalten fest (macOS: `NSApplication.terminate`). Auf iOS bleibt das i. d. R.
    /// ungesetzt, da iOS-Apps sich laut Apple-HIG nicht selbst beenden.
    public var onQuit: (() -> Void)?

    // Die folgenden NSEvent-Overrides sind die macOS-Tastatur-Brücke: Sie ziehen die nötigen Felder
    // aus dem Event und reichen sie an die plattformunabhängige Verarbeitung weiter. NSEvent existiert
    // nur auf macOS – auf iOS kommt die Eingabe über die Touch-/Controller-Schicht in `handleKeyDown`.
    #if canImport(AppKit)
    public override func keyDown(with event: NSEvent) {
        handleKeyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isCommandDown: event.modifierFlags.contains(.command)
        )
    }

    public override func keyUp(with event: NSEvent) {
        handleKeyUp(keyCode: event.keyCode)
    }
    #endif

    /// Plattformunabhängige Verarbeitung eines Tastendrucks. Aufgerufen von der macOS-keyDown-Brücke,
    /// den Simulate-Helfern (Headless-Tests) und künftig der iOS-Touch-/Controller-Schicht.
    /// - Parameters:
    ///   - keyCode: virtueller Tastencode (macOS-Layout; die Spiellogik kennt nur diese Codes)
    ///   - characters: getippte Zeichen (für den „#"-Cheat und die Initialen-Eingabe), ggf. nil
    ///   - charactersIgnoringModifiers: Zeichen ohne Modifier (Cmd+Q, „M"-Musik-Toggle), ggf. nil
    ///   - isCommandDown: ob die Command-Taste gehalten wird (für Cmd+Q)
    func handleKeyDown(keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?, isCommandDown: Bool) {
        // Während einer Replay-Wiedergabe sind LIVE-Eingaben gesperrt (nur der Player selbst speist
        // über `injectReplayInput` ein, das setzt `isInjectingReplay`). So kann der Zuschauer das
        // laufende Replay nicht verfälschen. Einzige Ausnahme: ESC bricht die Wiedergabe ab.
        if replayPlayer != nil && !isInjectingReplay {
            if keyCode == 53 { exitReplay() } // Escape
            return
        }
        // Cmd+Q beendet immer die App – auch während einer Demo (VOR dem Attract-Abbruch prüfen,
        // sonst würde Cmd+Q während einer Demo nur die Demo stoppen statt zu beenden).
        if isCommandDown, charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit?()
            return
        }
        // Attract-/Demo-Modus: eine echte menschliche Eingabe unterbricht die Automatik. Der
        // Autopilot steuert NICHT über diesen Handler (er setzt `activeKeys` direkt), darum ist ein
        // Aufruf hier während einer Demo garantiert der Mensch.
        if attractModeEnabled && !isInjectingReplay {
            if isDemoActive || attractPhase == .demoScores || attractPhase == .demoRestScreen {
                // Läuft eine Demo oder eine Zwischen-Menü-Phase → zurück zum ruhigen Startbildschirm,
                // Mensch übernimmt. Die auslösende Taste wird bewusst nicht weiter ausgewertet.
                abortAttractToIdle()
                return
            }
            // Startbildschirm im Leerlauf: jede Eingabe setzt den 30-s-Auto-Demo-Timer zurück.
            attractTimer = 0
        }
        // Aufnahme: jedes Tastenereignis im laufenden Spiel festhalten. (Injizierte Replay-Eingaben
        // tragen keine `characters`/Modifier, lösen also weder den M- noch den Cmd-Q-Zweig aus.)
        // Cmd+Q wird bereits oben behandelt (vor dem Attract-Abbruch).
        if gameState == .playing {
            recorder?.recordEvent(keyCode: keyCode, isDown: true)
        }

        // „M" schaltet die Hintergrundmusik global ein/aus – in jedem Zustand außer der
        // Initialen-Eingabe (dort ist „M" ein einzugebender Buchstabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "m" {
            MusicPlayer.shared.toggle()
            updateSettingsLabels()
            return
        }

        // „N" schaltet den SFX-Stil um: prozedurale Synth-Effekte <-> generierte Samples.
        // Zum sofortigen Vergleich spielt direkt ein Bestätigungs-Sound im NEUEN Modus.
        // Ebenfalls überall außer bei der Initialen-Eingabe (dort ist „N" ein Buchstabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "n" {
            if isClassicInterfaceActive {
                updateSettingsLabels()
                return
            }
            SoundManager.shared.useSampledSFX.toggle()
            updateSettingsLabels()
            SoundManager.shared.playPowerUp()
            return
        }

        // „F" schaltet Auto-Feuer um (global außer bei der Initialen-Eingabe).
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "f" {
            if isClassicInterfaceActive {
                updateSettingsLabels()
                return
            }
            autoFire.toggle()
            updateSettingsLabels()
            return
        }

        // „G" schaltet den HDR-Vektorglow um. Auf einem SDR-Display ist die Taste bewusst ein
        // No-op; die gespeicherte Präferenz bleibt für ein späteres HDR-Display erhalten.
        if gameState != .nameEntry, charactersIgnoringModifiers?.lowercased() == "g" {
            toggleHDRGlow()
            return
        }

        switch gameState {
        case .startScreen:
            // Attract-Modus: „D" startet sofort eine Demo. Nur wenn der Attract-Modus aktiv ist –
            // sonst bleibt „D" der klassische Level-+1-Alias (siehe Rechts-Pfeil-Zweig unten), damit
            // Tests/Headless-Pfade unverändert bleiben.
            if attractModeEnabled, keyCode == 2, characters?.lowercased() == "d" {
                startDemo()
                return
            }
            if keyCode == 49 || keyCode == 36 { // Space or Enter
                currentLevel = selectedMode == .classicAsteroids ? 1 : selectedStartLevel
                transitionTo(.playing)
            } else if keyCode == 123 || (keyCode == 0 && characters?.lowercased() == "a") { // Left arrow or A
                if selectedMode != .classicAsteroids && selectedStartLevel > 1 {
                    selectedStartLevel -= 1
                    updateLevelSelectionLabel()
                }
            } else if keyCode == 124 || (keyCode == 2 && characters?.lowercased() == "d") { // Right arrow or D
                if selectedMode != .classicAsteroids && selectedStartLevel < 10 {
                    selectedStartLevel += 1
                    updateLevelSelectionLabel()
                }
            } else if keyCode == 126 { // Up arrow -> next game mode
                selectedMode = selectedMode.next
                activateHighScoreBoard(for: selectedMode)
                updateHighScoreLabels()
                updateModeSelectionLabel()
                updateLevelSelectionLabel()
            } else if keyCode == 125 { // Down arrow -> previous game mode
                selectedMode = selectedMode.previous
                activateHighScoreBoard(for: selectedMode)
                updateHighScoreLabels()
                updateModeSelectionLabel()
                updateLevelSelectionLabel()
            } else if let digit = digitForKey(keyCode: keyCode, characters: characters), (1...5).contains(digit) {
                // Zahlentaste 1–5: Replay des entsprechenden Highscore-Eintrags ansehen (falls einer
                // mit gespeicherter, kompatibler Aufnahme existiert).
                watchHighScoreReplay(at: digit - 1)
            } else if let characters = characters?.lowercased() {
                if characters == "i" {
                    transitionTo(.glossary)
                } else if characters == "h", !showsHighScoresOnStartScreen {
                    // Nur wenn die Liste ausgelagert ist (iOS): eigene Highscore-Ansicht öffnen.
                    transitionTo(.highScores)
                } else if characters == "o" {
                    transitionTo(.settings)
                }
            }

        case .playing:
            if keyCode == 53 { // Escape -> quit confirmation
                transitionTo(.quitConfirmation)
                return
            }
            if characters == "#" { // Undokumentierter Cheat: ein Extra-Leben (zum Testen)
                if gameMode == .classicAsteroids {
                    classicSession.shipsRemaining += 1
                } else {
                    extraLives += 1
                }
                updateLivesLabel()
                showPowerUpNotification(text: "EXTRA LIFE!", color: SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0))
                return
            }
            if gameMode == .classicAsteroids && keyCode == 4 { // H: Hyperraum
                activateClassicHyperspace()
                return
            }
            activeKeys.insert(keyCode)
            if keyCode == 49 { // Feuertaste: erster Schuss sofort, Halten feuert weiter (siehe update)
                if !isSpaceHeld {
                    isSpaceHeld = true
                    fireLaser()
                }
            }

        case .nameEntry:
            if keyCode == 36 { // Enter / Return
                if typedInitials.count == 3 {
                    recordHighScore(initials: typedInitials, score: score)
                    transitionTo(.gameOver)
                }
            } else if keyCode == 51 { // Backspace
                if !typedInitials.isEmpty {
                    typedInitials.removeLast()
                    updateNameEntryInputLabel()
                }
            } else if let chars = characters, !chars.isEmpty {
                let char = chars.first!
                let isAllowed = char.isLetter || char.isNumber || char == " "
                if isAllowed && typedInitials.count < 3 {
                    typedInitials.append(String(char).uppercased())
                    updateNameEntryInputLabel()
                }
            }

        case .gameOver:
            if keyCode == 15 || keyCode == 49 { // R key or Space bar -> replay same mode/level
                transitionTo(.playing)
            } else if keyCode == 53 { // Escape -> back to start screen (choose mode and level)
                transitionTo(.startScreen)
            }

        case .quitConfirmation:
            if keyCode == 53 { // Escape -> resume
                transitionTo(.playing)
            } else if let characters = characters?.lowercased(), characters == "y" {
                transitionTo(.startScreen)
            }

        case .glossary:
            if keyCode == 53 { // Escape -> back to title
                transitionTo(.startScreen)
            } else if keyCode == 126 || keyCode == 13 { // Up Arrow or W
                glossaryContainer.position.y += 20.0
                if glossaryContainer.position.y > glossaryScrollTop {
                    glossaryContainer.position.y = glossaryScrollBottom
                }
            } else if keyCode == 125 || keyCode == 1 { // Down Arrow or S
                glossaryContainer.position.y -= 20.0
                if glossaryContainer.position.y < glossaryScrollBottom {
                    glossaryContainer.position.y = glossaryScrollTop
                }
            } else if let characters = characters?.lowercased() {
                if characters == "i" {
                    transitionTo(.startScreen)
                }
            }

        case .highScores:
            // Eigene Highscore-Ansicht: einzige Aktion ist Zurück zum Startbildschirm.
            if keyCode == 53 { // Escape
                transitionTo(.startScreen)
            }

        case .settings:
            // Umschalten passiert global (M/N/F/G, oben); hier nur Zurück.
            if keyCode == 53 { // Escape
                transitionTo(.startScreen)
            }
        }
    }

    /// Plattformunabhängige Verarbeitung des Loslassens einer Taste.
    func handleKeyUp(keyCode: UInt16) {
        // Live-Eingaben während eines Replays sperren (siehe handleKeyDown).
        if replayPlayer != nil && !isInjectingReplay {
            return
        }
        if gameState == .playing {
            recorder?.recordEvent(keyCode: keyCode, isDown: false)
            activeKeys.remove(keyCode)
            if keyCode == 49 { // Feuertaste losgelassen: Dauerfeuer beenden
                isSpaceHeld = false
            }
        }
    }
    
    // MARK: - Laser Firing
    
    /// Spawns a laser from the ship's tip with a cooldown limit.
    func fireLaser() {
        if gameMode == .classicAsteroids {
            fireClassicLaser()
            return
        }
        let now = gameTime
        let isRapidActive = now < rapidFireEndTime
        let cooldown: TimeInterval = isRapidActive ? GameplayTuning.laserCooldownRapid
                                                   : GameplayTuning.laserCooldownNormal
        
        guard now - lastLaserTime >= cooldown else { return }
        lastLaserTime = now
        
        let angle = ship.zRotation
        let tipDistance: CGFloat = 18.0
        let spawnPos = CGPoint(
            x: ship.position.x + tipDistance * cos(angle),
            y: ship.position.y + tipDistance * sin(angle)
        )
        
        let isTripleActive = now < tripleShotEndTime
        
        if isTripleActive {
            // Spawn 3 lasers in a spread pattern
            let centerLaser = Laser(position: spawnPos, angle: angle, type: .normal)
            let leftLaser = Laser(position: spawnPos, angle: angle + GameplayTuning.tripleShotSpreadAngle, type: .normal)
            let rightLaser = Laser(position: spawnPos, angle: angle - GameplayTuning.tripleShotSpreadAngle, type: .normal)
            
            self.addChild(centerLaser)
            self.addChild(leftLaser)
            self.addChild(rightLaser)
            
            self.activeLasers.append(centerLaser)
            self.activeLasers.append(leftLaser)
            self.activeLasers.append(rightLaser)
        } else {
            // Spawn single normal laser
            let laser = Laser(position: spawnPos, angle: angle, type: .normal)
            self.addChild(laser)
            self.activeLasers.append(laser)
        }
        
        // Fire option lasers if drones are collected
        for option in options {
            let optionSpawnPos = option.position
            let optionLaser = Laser(position: optionSpawnPos, angle: angle, type: .normal)
            self.addChild(optionLaser)
            self.activeLasers.append(optionLaser)
        }

        // Rear laser power-up: additionally fire one shot straight backwards.
        if now < rearLaserEndTime {
            let rearAngle = angle + .pi
            let rearSpawn = CGPoint(
                x: ship.position.x + tipDistance * cos(rearAngle),
                y: ship.position.y + tipDistance * sin(rearAngle)
            )
            let rearLaser = Laser(position: rearSpawn, angle: rearAngle, type: .normal)
            self.addChild(rearLaser)
            self.activeLasers.append(rearLaser)
        }

        // Play laser sound effect
        SoundManager.shared.playLaser()
    }

    // MARK: - Game Loop
    
    public override func update(_ wallTime: TimeInterval) {
        // Headless/Tests treiben die Simulation extern über `advanceOneStep()` → hier nichts tun.
        if externalStepDriving { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = wallTime
            return
        }
        var frameDelta = wallTime - lastUpdateTime
        lastUpdateTime = wallTime
        if frameDelta > maxFrameDelta { frameDelta = maxFrameDelta }   // Hänger nicht nachholen

        // Attract-/Demo-Kreislauf über die Echtzeit-Uhr treiben (30 s Leerlauf → Demo, danach
        // 10 s Highscore-Liste + 15 s Startbildschirm, dann nächste Demo). Läuft unabhängig von der
        // fixed-timestep-Spielzeit (die bei jedem frischen Lauf auf 0 zurückgesetzt wird).
        if attractModeEnabled { updateAttract(realDelta: frameDelta) }

        // Demo-Overlay („▷ DEMO — <PERSONA>") pro Frame auffrischen, solange der Autopilot spielt.
        // Das einmalige Setzen in startDemo() genügt nicht zuverlässig: jeder spätere HUD-Reset über
        // transitionTo() blendet das Label wieder aus. Der Aufruf ist billig (Text wird nur bei
        // Änderung neu gesetzt), hält das Overlay aber über den ganzen Demo-Lauf sichtbar.
        if isDemoActive { updateDemoOverlay() }

        // iOS-Spiel-HUD jede Frame neu zentrieren (Zeit-Text ändert sich sekündlich, Demo-Zeile
        // kommt/geht). Nur im Kompaktlayout und nur im laufenden Spiel – auf macOS unberührt.
        if isCompactLayout && gameState == .playing { applyCompactPlayingLayout() }

        // Fixed-Timestep: die reale Frame-Zeit aufsummieren und die Simulation in festen Schritten
        // (`simStep`) voranbringen – unabhängig von der Bildwiederholrate. Dadurch hängt ein Lauf nur
        // noch an (Seed + Eingaben), nicht mehr an einer dt-Folge; das Replay ist ohne aufgezeichnete
        // dt-Werte bit-exakt. Gerendert wird der jeweils erreichte Sim-Zustand (ohne Interpolation;
        // bei simStep ≈ Bildperiode unnötig, siehe `simStepsPerSecond`).
        timeAccumulator += frameDelta
        while timeAccumulator >= GameScene.simStep {
            timeAccumulator -= GameScene.simStep
            if !advanceOneStep() { break }   // false = Wiedergabe zu Ende (wurde hier beendet)
        }

        // Asteroiden-Drahtgitter EINMAL pro gerendertem Bild neu aufbauen (nicht mehr pro Sim-Schritt).
        // Rein visuell; der headless Renderer ruft dies separat vor jedem Capture (siehe ReplayRenderer).
        refreshAsteroidWireframes()
    }

    /// Baut die (rein visuellen) Asteroiden-Drahtgitter-Pfade für alle aktiven Asteroiden neu auf.
    /// Einmal pro gerendertem Bild aufgerufen — der teure SKShapeNode-Path-Rebuild hängt damit an
    /// der Bildrate, nicht an der (bis zu doppelt so hohen) Simulationsrate. Kein Sim-/Determinismus-
    /// Einfluss; die Sim verändert nur `pitch`/`yaw` der Asteroiden, gezeichnet wird der Endstand.
    public func refreshAsteroidWireframes() {
        for asteroid in activeAsteroids {
            asteroid.refreshWireframe()
        }
    }

    /// Treibt die Simulation um GENAU einen festen Schritt (`simStep`) voran. Gemeinsamer Einstieg
    /// für den Echtzeit-Akkumulator (oben), den headless GIF-Renderer und die Tests. Während einer
    /// Wiedergabe werden zuerst die für diesen Schritt aufgezeichneten Eingaben eingespeist; im
    /// laufenden Spiel wird der Schritt für die Aufnahme mitgezählt. Rückgabe `false`, wenn eine
    /// Wiedergabe zu Ende ist (dann wurde sie hier beendet) – der Aufrufer soll abbrechen.
    @discardableResult
    public func advanceOneStep() -> Bool {
        if let player = replayPlayer {
            guard player.advanceStep(injectingInto: self) else {
                finishReplay()
                return false
            }
        } else if gameState == .playing {
            recorder?.recordStep()
        }
        stepSimulation(deltaTime: GameScene.simStep)
        return true
    }

    /// Ein einzelner Simulationsschritt mit festem `deltaTime`. Enthält den gesamten Spiel-Logik-Rumpf
    /// (Spawning, Bewegung, Kollision, HUD); wird von `advanceOneStep()` getrieben.
    private func stepSimulation(deltaTime: TimeInterval) {
        // Eine Quelle der Wahrheit für Zeit: akkumulierte Spielzeit. Ab hier benennt `currentTime` die
        // SPIELZEIT (nicht die Echtzeit) – der gesamte restliche Rumpf und alle Helfer rechnen gegen
        // `gameTime`. Grundlage für deterministisches Replay (Lauf hängt nur an Seed + Eingaben).
        gameTime += deltaTime
        let currentTime = gameTime

        if gameState == .quitConfirmation {
            return
        }

        // Mad-Meteoroids: Feld-Drehung dieses Frames bestimmen, BEVOR Sterne/Objekte sie nutzen.
        // Nur im laufenden Spiel und nicht während des Level-Übergangs.
        fieldDeltaThisFrame = 0.0
        if gameState == .playing && gameMode == .madMeteoroids && !isLevelClearing {
            if fieldRotationPending {
                configureFieldRotationForLevel(currentTime: currentTime)
                fieldRotationPending = false
            }
            updateFieldRotation(deltaTime: deltaTime, currentTime: currentTime)
            fieldDeltaThisFrame = fieldAngularVelocity * CGFloat(deltaTime)
        }

        // Background elements (stars) always update
        updateStars(deltaTime: deltaTime)
        
        if gameState == .glossary {
            let scrollSpeed: CGFloat = 35.0
            glossaryContainer.position.y += scrollSpeed * CGFloat(deltaTime)

            if glossaryContainer.position.y > glossaryScrollTop {
                glossaryContainer.position.y = glossaryScrollBottom
            } else if glossaryContainer.position.y < glossaryScrollBottom {
                glossaryContainer.position.y = glossaryScrollTop
            }
            return
        }

        // Classic besitzt einen bewusst kleinen, eigenständigen Sitzungs-/Simulationspfad. Der
        // bestehende Ancient/Mad-Rumpf darunter bleibt dadurch unverändert und alte v3-Replays
        // behalten exakt dieselbe Reihenfolge von Logik und RNG-Ziehungen.
        if gameState == .playing && gameMode == .classicAsteroids {
            updateClassicMode(deltaTime: deltaTime)
            return
        }
        
        switch gameState {
        case .startScreen:
            // Periodically spawn new asteroids for menu background decoration
            if currentTime - lastSpawnTime >= 2.0 {
                lastSpawnTime = currentTime
                if activeAsteroids.count < 4 {
                    spawnAsteroid()
                }
            }
            
        case .playing:
            playTime += deltaTime
            
            if isLevelClearing {
                if currentTime >= levelClearEndTime {
                    isLevelClearing = false
                    currentLevel += 1
                    if currentLevel > maxLevelReached {
                        maxLevelReached = currentLevel
                        highScoreStore.saveMaxLevelReached(maxLevelReached)
                    }
                    // Drehzahl/Wechsel-Frequenz fürs neue Level neu planen (Mad-Modus).
                    fieldRotationPending = true
                    levelTimeRemaining = (currentLevel >= 10) ? 999999.0 : 60.0
                    levelLabel.text = "LEVEL: \(currentLevel)"
                    if currentLevel >= 10 {
                        timerLabel.text = "TIME: SURVIVAL"
                    } else {
                        timerLabel.text = "TIME: 01:00"
                    }
                    
                    levelClearedLabel.isHidden = true
                    prepareNextLevelLabel.isHidden = true
                    
                    lastSpawnTime = currentTime
                    lastUFOSpawnTime = currentTime
                    lastGravityWellSpawnTime = currentTime
                    
                    // Extend remaining lifetime of active power-ups to at least 5s for the new level
                    for p in activePowerUps {
                        let remaining = p.lifetime - p.elapsedTime
                        if remaining < 5.0 {
                            p.setRemainingLifetime(to: 5.0)
                        }
                    }
                    
                    let initialCount = max(3, currentConfig().maxAsteroids / 2)
                    for _ in 0..<initialCount {
                        spawnAsteroid()
                    }
                }
            } else {
                // Decrement level timer only if level < 10
                if currentLevel < 10 {
                    levelTimeRemaining -= deltaTime
                    if levelTimeRemaining <= 0 {
                        levelTimeRemaining = 0
                        isLevelClearing = true
                        levelClearEndTime = currentTime + 3.5
                        
                        clearGameEntitiesKeepOptions()
                        
                        // Ensure all active powerups persist through the 3.5s transition and for 5s into the next level
                        for p in activePowerUps {
                            let remaining = p.lifetime - p.elapsedTime
                            if remaining < 8.5 {
                                p.setRemainingLifetime(to: 8.5)
                            }
                        }
                        
                        levelClearedLabel.text = "LEVEL \(currentLevel) COMPLETED!"
                        prepareNextLevelLabel.text = "PREPARE FOR LEVEL \(currentLevel + 1)"
                        levelClearedLabel.isHidden = false
                        prepareNextLevelLabel.isHidden = false
                        
                        SoundManager.shared.playLevelComplete()
                        
                        levelClearedLabel.removeAction(forKey: "blink")
                        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
                        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
                        let blink = SKAction.sequence([fadeOut, fadeIn])
                        levelClearedLabel.run(SKAction.repeatForever(blink), withKey: "blink")
                    }
                }
                
                if !isLevelClearing {
                    if currentLevel >= 10 {
                        timerLabel.text = "TIME: SURVIVAL"
                    } else {
                        let minutes = Int(levelTimeRemaining) / 60
                        let seconds = Int(levelTimeRemaining) % 60
                        timerLabel.text = String(format: "TIME: %02d:%02d", minutes, seconds)
                    }
                    
                    // Spawning Logic
                    let config = currentConfig()
                    
                    // Periodically spawn new asteroids
                    if isSpawningEnabled && currentTime - lastSpawnTime >= config.spawnRate {
                        lastSpawnTime = currentTime
                        if activeAsteroids.count < config.maxAsteroids {
                            spawnAsteroid()
                        }
                    }
                    
                    // Periodically spawn UFO enemies
                    if let ufoInt = config.ufoInterval {
                        if isSpawningEnabled && currentTime - lastUFOSpawnTime >= ufoInt {
                            lastUFOSpawnTime = currentTime
                            if activeUFOs.count < 2 {
                                let isSmallUFO = Double.random(in: 0...1, using: &rng) < 0.45
                                // startOnLeft VOR dem Init in eine lokale Variable (Exklusivität: der
                                // UFO-Init nimmt rng als inout, da darf nicht parallel daraus gezogen werden).
                                let startOnLeft = Bool.random(using: &rng)
                                let ufo = UFO(isSmall: isSmallUFO, startOnLeft: startOnLeft, screenSize: size, using: &rng)
                                self.addChild(ufo)
                                self.activeUFOs.append(ufo)
                            }
                        }
                    }
                    
                    // Periodically spawn Gravity Wells (Black Holes)
                    if let bhInt = config.blackHoleInterval {
                        if isSpawningEnabled && currentTime - lastGravityWellSpawnTime >= bhInt {
                            lastGravityWellSpawnTime = currentTime
                            if activeGravityWells.isEmpty {
                                let well = GravityWell()
                                
                                let halfW = size.width / 2
                                let halfH = size.height / 2
                                var spawnPos = CGPoint.zero
                                var attempts = 0
                                repeat {
                                    spawnPos = CGPoint(
                                        x: CGFloat.random(in: -halfW * 0.5...halfW * 0.5, using: &rng),
                                        y: CGFloat.random(in: -halfH * 0.5...halfH * 0.5, using: &rng)
                                    )
                                    attempts += 1
                                } while attempts < 50 && distanceBetween(spawnPos, ship.position) < 220.0
                                
                                well.position = spawnPos
                                self.addChild(well)
                                self.activeGravityWells.append(well)
                            }
                        }
                    }
                }
            }
            
            // Kopf-Boss (Boss-Welle) auslösen und aktualisieren – nur im laufenden Spiel.
            if !isLevelClearing {
                updateFloatingHead(currentTime: currentTime, deltaTime: deltaTime)
                updateSpaceCats(currentTime: currentTime, deltaTime: deltaTime)
            }

            // Demo-Modus: der Autopilot bestimmt die Bewegungstasten dieses Schritts (Feuern läuft
            // über `autoFire`, das beim Demo-Start gesetzt wird). Bei verstecktem Schiff (nach Tod,
            // vor Revive) nichts tun – die Tasten bleiben leer.
            if let persona = autopilotPersona, !ship.isHidden {
                applyAutopilotInput(persona: persona)
            }

            // Determine input states
            let isThrusting = activeKeys.contains(13) || activeKeys.contains(126)
            
            var rotationInput: CGFloat = 0.0
            if activeKeys.contains(0) || activeKeys.contains(123) {
                rotationInput += 1.0
            }
            if activeKeys.contains(2) || activeKeys.contains(124) {
                rotationInput -= 1.0
            }
            
            // Update the ship
            ship.update(deltaTime: deltaTime, isThrusting: isThrusting, rotationInput: rotationInput)
            ship.wrapAround(screenSize: size)

            // Power-up-Effekte mit Zeitbezug (Compress-Ablauf, Laserbeam-Strahl).
            updateTimedPowerUpEffects(currentTime: currentTime)

            // Update options follow interpolation
            let dt = CGFloat(deltaTime)
            for (index, option) in options.enumerated() {
                let targetPos = ship.getOptionTargetPosition(index: index, totalOptions: options.count)
                let t = 1.0 - pow(0.001, dt)
                option.position.x += (targetPos.x - option.position.x) * t
                option.position.y += (targetPos.y - option.position.y) * t
                option.zRotation = ship.zRotation
            }
            
            // Engine-Hum aktualisieren. Feuertaste halten = Dauerfeuer mit normaler Feuerrate
            // (fireLaser begrenzt selbst per Cooldown; mit Rapidfire wird der Cooldown kürzer).
            SoundManager.shared.setThrustActive(isThrusting)
            if (autoFire || isSpaceHeld) && !ship.isHidden {
                fireLaser()
            }
            
            // Unverwundbarkeit (z.B. nach Extra-Life-Revive) gilt für ALLE Todesarten,
            // also schon vor der Gravity-Well-Prüfung bestimmen.
            let isInvincible = currentTime < invincibilityEndTime

            // Apply Gravity Well attraction forces
            var wellsToCollapse: [GravityWell] = []
            for well in activeGravityWells {
                // Pull Ship
                if !ship.isHidden {
                    let pull = well.calculatePull(on: ship.position)
                    ship.velocity.x += pull.x * dt
                    ship.velocity.y += pull.y * dt

                    let dist = distanceBetween(well.position, ship.position)
                    if !isInvincible && dist <= well.eventHorizonRadius {
                        // Über damageShip(), damit ein Extra-Leben auch hier den Tod abfängt.
                        lastDeathCause = .gravityWell
                        damageShip()
                        // Treffer -> das Loch kollabiert sofort und zieht nicht weiter an
                        // (sonst bliebe man im Sog hängen, nachdem z.B. ein Schild verbraucht wurde).
                        wellsToCollapse.append(well)
                    }
                }
                
                // Pull Asteroids
                var remainingAsts: [Asteroid] = []
                for asteroid in activeAsteroids {
                    let pull = well.calculatePull(on: asteroid.position)
                    asteroid.velocity.x += pull.x * dt
                    asteroid.velocity.y += pull.y * dt
                    
                    let dist = distanceBetween(well.position, asteroid.position)
                    if dist <= well.eventHorizonRadius {
                        createExplosion(at: asteroid.position, sizeClass: .small)
                        asteroid.removeFromParent()
                    } else {
                        remainingAsts.append(asteroid)
                    }
                }
                self.activeAsteroids = remainingAsts
                
                // Pull UFOs
                var remainingUFOs: [UFO] = []
                for ufo in activeUFOs {
                    let pull = well.calculatePull(on: ufo.position)
                    ufo.velocity.x += pull.x * dt
                    ufo.velocity.y += pull.y * dt
                    
                    let dist = distanceBetween(well.position, ufo.position)
                    if dist <= well.eventHorizonRadius {
                        createShipExplosion(at: ufo.position)
                        ufo.removeFromParent()
                    } else {
                        remainingUFOs.append(ufo)
                    }
                }
                self.activeUFOs = remainingUFOs
            }

            // Vom Spieler getroffene Löcher kollabieren (Sog endet sofort) – kleiner Effekt zur Quittung.
            if !wellsToCollapse.isEmpty {
                for w in wellsToCollapse {
                    createExplosion(at: w.position, sizeClass: .small)
                    w.removeFromParent()
                }
                activeGravityWells.removeAll { w in wellsToCollapse.contains(where: { $0 === w }) }
            }

            // Collision detection: Ship vs. Asteroids
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                for asteroid in activeAsteroids {
                    let astPoly = asteroid.getWorldVertices()
                    if CollisionHelper.polygonsIntersect(shipPoly, astPoly) {
                        if asteroid.isWobblingType {
                            lastDeathCause = .wobblingAsteroid
                        } else {
                            switch asteroid.sizeClass {
                            case .large: lastDeathCause = .largeAsteroid
                            case .medium: lastDeathCause = .mediumAsteroid
                            case .small: lastDeathCause = .smallAsteroid
                            }
                        }
                        damageShip()
                        break
                    }
                }
            }
            
            // Collision detection: Ship vs. UFOs
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                for ufo in activeUFOs {
                    let ufoPoly = ufo.getWorldVertices()
                    if CollisionHelper.polygonsIntersect(shipPoly, ufoPoly) {
                        createShipExplosion(at: ufo.position)
                        ufo.removeFromParent()
                        activeUFOs = activeUFOs.filter { $0 != ufo }
                        lastDeathCause = .ufo
                        damageShip()
                        break
                    }
                }
            }

            // Collision detection: Ship vs. Kopf-Boss (Kontakt = Tod)
            if let head = activeHead, !ship.isHidden && !isInvincible {
                if distanceBetween(ship.position, head.position) <= head.collisionRadius {
                    lastDeathCause = .bossHead
                    damageShip()
                }
            }

            // Collision detection: Ship vs. Weltraumkatzen (Kontakt = Tod). Die Katze überlebt das
            // (Miniboss) – nur das Schiff nimmt Schaden. Kleiner Radius-Zuschlag für faires Rammen.
            if !ship.isHidden && !isInvincible {
                for cat in activeCats {
                    if distanceBetween(ship.position, cat.position) <= cat.collisionRadius + 8.0 {
                        lastDeathCause = .spaceCat
                        damageShip()
                        break
                    }
                }
            }

            // Collision detection: Ship vs. Power-ups – distanzbasiert (Abstand der Mittelpunkte),
            // NICHT über das Schiff-Polygon. Sonst sind Power-ups bei aktivem Compress (winziges
            // Schiff) praktisch nicht mehr einsammelbar und bleiben „hängen".
            if !ship.isHidden {
                // Großzügiger Sammelradius: Power-ups driften + pulsen; bei 30 ging man leicht über
                // den Rand, ohne einzusammeln. 40 = visuelles Überfliegen sammelt zuverlässig ein.
                let collectRadius = GameplayTuning.powerUpCollectRadius
                // WICHTIG: erst die einzusammelnden bestimmen, DANN einsammeln und gezielt aus dem
                // Array entfernen. Nicht „remainingPowerUps neu bauen und activePowerUps überschreiben":
                // collectPowerUp kann (Bombe -> detonateBomb -> spawnPowerUp) WÄHRENDDESSEN neue
                // Power-ups an activePowerUps anhängen; ein Überschreiben würde die verlieren — sie
                // blieben als verwaiste Nodes im Szenengraph (uneinsammelbar, laufen nie ab, überleben
                // jeden Clear). Identitäts-basiertes Entfernen bewahrt die neu gespawnten.
                let collected = activePowerUps.filter {
                    distanceBetween(ship.position, $0.position) <= collectRadius
                }
                for powerUp in collected {
                    SoundManager.shared.playPowerUp()
                    collectPowerUp(powerUp)
                    powerUp.removeFromParent()
                }
                if !collected.isEmpty {
                    activePowerUps.removeAll { p in collected.contains { $0 === p } }
                }
            }
            
            // Collision detection: Player Lasers vs. Asteroids
            var remainingLasers: [Laser] = []
            var hitAsteroids = Set<Asteroid>()
            var newAsteroids: [Asteroid] = []
            
            for laser in activeLasers {
                if laser.type != .normal {   // Gegner-Schüsse (UFO + Katze) treffen keine Asteroiden
                    remainingLasers.append(laser)
                    continue
                }

                var laserHit = false
                for asteroid in activeAsteroids {
                    if !hitAsteroids.contains(asteroid) && CollisionHelper.laserIntersectsAsteroid(laser, asteroid) {
                        laser.pierceCount += 1
                        if laser.pierceCount >= laser.pierceLimit {
                            laserHit = true
                        }
                        
                        processPlayerHitOnAsteroid(asteroid, hitPosition: laser.position,
                                                   hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)

                        if laserHit {
                            break
                        }
                    }
                }
                
                if laserHit {
                    laser.removeFromParent()
                } else {
                    remainingLasers.append(laser)
                }
            }
            
            // Process hit asteroid filtering and splitting
            if !hitAsteroids.isEmpty {
                activeAsteroids = activeAsteroids.filter { asteroid in
                    if hitAsteroids.contains(asteroid) {
                        asteroid.removeFromParent()
                        return false
                    }
                    return true
                }
            }
            activeAsteroids.append(contentsOf: newAsteroids)
            
            // Collision detection: Asteroid vs Asteroid (Absorption)
            var asteroidsToRemoval = Set<Asteroid>()
            var collapsedImplodingAsteroids = Set<Asteroid>()
            
            for i in 0..<activeAsteroids.count {
                let astA = activeAsteroids[i]
                guard !asteroidsToRemoval.contains(astA) else { continue }
                
                for j in (i+1)..<activeAsteroids.count {
                    let astB = activeAsteroids[j]
                    guard !asteroidsToRemoval.contains(astB) else { continue }
                    
                    if astA.isImplodingType || astB.isImplodingType {
                        let polyA = astA.getWorldVertices()
                        let polyB = astB.getWorldVertices()
                        if CollisionHelper.polygonsIntersect(polyA, polyB) {
                            let absorber: Asteroid
                            let absorbed: Asteroid
                            
                            if astA.isImplodingType && astB.isImplodingType {
                                if astA.xScale >= astB.xScale {
                                    absorber = astA
                                    absorbed = astB
                                } else {
                                    absorber = astB
                                    absorbed = astA
                                }
                            } else if astA.isImplodingType {
                                absorber = astA
                                absorbed = astB
                            } else {
                                absorber = astB
                                absorbed = astA
                            }
                            
                            asteroidsToRemoval.insert(absorbed)
                            
                            let currentScale = absorber.xScale
                            let newScale = currentScale + GameplayTuning.asteroidAbsorbGrowthStep
                            absorber.xScale = newScale
                            absorber.yScale = newScale
                            
                            createExplosion(at: absorbed.position, sizeClass: .small)
                            
                            if newScale >= 3.0 {
                                collapsedImplodingAsteroids.insert(absorber)
                                asteroidsToRemoval.insert(absorber)
                            }
                        }
                    }
                }
            }
            
            for ast in collapsedImplodingAsteroids {
                triggerImplosionCollapse(asteroid: ast)
            }
            
            if !asteroidsToRemoval.isEmpty {
                activeAsteroids = activeAsteroids.filter { ast in
                    if asteroidsToRemoval.contains(ast) {
                        ast.removeFromParent()
                        return false
                    }
                    return true
                }
            }
            
            // Collision detection: Player Lasers vs. UFOs
            var hitUFOs = Set<UFO>()
            var remainingLasers2: [Laser] = []
            
            for laser in remainingLasers {
                if laser.type != .normal {   // Gegner-Schüsse (UFO + Katze) treffen keine UFOs
                    remainingLasers2.append(laser)
                    continue
                }

                var laserHit = false
                let (start, end) = laser.getWorldSegment()

                for ufo in activeUFOs {
                    let ufoPoly = ufo.getWorldVertices()
                    let hit = CollisionHelper.isPointInPolygon(start, polygon: ufoPoly) || CollisionHelper.isPointInPolygon(end, polygon: ufoPoly)
                    
                    if !hitUFOs.contains(ufo) && hit {
                        laser.pierceCount += 1
                        if laser.pierceCount >= laser.pierceLimit {
                            laserHit = true
                        }
                        
                        hitUFOs.insert(ufo)
                        
                        self.score += ufo.pointValue
                        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                        
                        // Drop power-up on UFO hit
                        if Double.random(in: 0...1, using: &rng) <= 0.20 {
                            spawnPowerUp(at: ufo.position)
                        }
                        
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: ufo.position)
                        shakeCamera(amplitude: 4.0, numberOfShakes: 5, durationPerShake: 0.025)
                        
                        if laserHit {
                            break
                        }
                    }
                }
                
                if laserHit {
                    laser.removeFromParent()
                } else {
                    remainingLasers2.append(laser)
                }
            }
            remainingLasers = remainingLasers2
            
            if !hitUFOs.isEmpty {
                activeUFOs = activeUFOs.filter { ufo in
                    if hitUFOs.contains(ufo) {
                        ufo.removeFromParent()
                        return false
                    }
                    return true
                }
            }

            // Collision detection: Player Lasers vs. Kopf-Boss (3 Treffer bis zerstört)
            if let head = activeHead {
                var lasersAfterHead: [Laser] = []
                var headAlive = true
                for laser in remainingLasers {
                    // Gegner-Schüsse (UFO + Katze) ignorieren; nach dem Tod des Bosses Rest behalten.
                    if !headAlive || laser.type != .normal {
                        lasersAfterHead.append(laser)
                        continue
                    }
                    let (start, end) = laser.getWorldSegment()
                    let hit = distanceBetween(start, head.position) <= head.collisionRadius
                           || distanceBetween(end, head.position) <= head.collisionRadius
                    if hit {
                        let destroyed = head.registerHit()
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: laser.position)
                        shakeCamera(amplitude: 5.0, numberOfShakes: 6, durationPerShake: 0.025)
                        // Schuss verbraucht (kein Durchschlag durch den Boss)
                        laser.removeFromParent()

                        if destroyed {
                            self.score += 2000
                            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                            createShipExplosion(at: head.position)
                            shakeCamera(amplitude: 9.0, numberOfShakes: 10, durationPerShake: 0.03)
                            head.removeFromParent()
                            activeHead = nil
                            headAlive = false
                        }
                    } else {
                        lasersAfterHead.append(laser)
                    }
                }
                remainingLasers = lasersAfterHead
            }

            // Collision detection: Player Lasers vs. Weltraumkatzen (Miniboss mit HP)
            if !activeCats.isEmpty {
                var lasersAfterCats: [Laser] = []
                var deadCats = Set<SpaceCat>()
                for laser in remainingLasers {
                    if laser.type != .normal {   // nur Spielerschüsse treffen die Katzen
                        lasersAfterCats.append(laser)
                        continue
                    }
                    let (start, end) = laser.getWorldSegment()
                    var consumed = false
                    for cat in activeCats where !deadCats.contains(cat) {
                        let hit = distanceBetween(start, cat.position) <= cat.collisionRadius
                               || distanceBetween(end, cat.position) <= cat.collisionRadius
                        guard hit else { continue }
                        let destroyed = cat.registerHit()
                        SoundManager.shared.playExplosion()
                        createShipExplosion(at: laser.position)
                        shakeCamera(amplitude: 4.0, numberOfShakes: 5, durationPerShake: 0.025)
                        consumed = true   // Schuss verbraucht (kein Durchschlag)
                        if destroyed {
                            self.score += cat.pointValue
                            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
                            createShipExplosion(at: cat.position)
                            shakeCamera(amplitude: 6.0, numberOfShakes: 7, durationPerShake: 0.03)
                            // Miniboss: etwas großzügigere Beute als ein normales UFO.
                            if Double.random(in: 0...1, using: &rng) <= 0.5 {
                                spawnPowerUp(at: cat.position)
                            }
                            deadCats.insert(cat)
                        }
                        break
                    }
                    if consumed { laser.removeFromParent() } else { lasersAfterCats.append(laser) }
                }
                remainingLasers = lasersAfterCats
                if !deadCats.isEmpty {
                    activeCats = activeCats.filter { cat in
                        if deadCats.contains(cat) { cat.removeFromParent(); return false }
                        return true
                    }
                }
            }

            // Collision detection: Enemy Lasers vs. Ship (UFO-Schüsse UND Katzen-Augenlaser)
            if !ship.isHidden && !isInvincible {
                let shipPoly = ship.getWorldVertices()
                var remainingLasers3: [Laser] = []
                for laser in remainingLasers {
                    if laser.type != .normal {
                        let (start, end) = laser.getWorldSegment()
                        if CollisionHelper.isPointInPolygon(start, polygon: shipPoly) || CollisionHelper.isPointInPolygon(end, polygon: shipPoly) {
                            laser.removeFromParent()
                            lastDeathCause = (laser.type == .catEye) ? .spaceCatLaser : .ufoLaser
                            damageShip()
                            continue
                        }
                    }
                    remainingLasers3.append(laser)
                }
                remainingLasers = remainingLasers3
            }

            self.activeLasers = remainingLasers
            
        case .nameEntry, .gameOver, .quitConfirmation, .glossary, .highScores, .settings:
            break
        }
        
        // Update active asteroids (they move and wrap in all states)
        var remainingAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            asteroid.update(deltaTime: deltaTime)
            if gameMode == .madMeteoroids {
                applyFieldRotation(toAsteroid: asteroid)
            } else {
                asteroid.wrapAround(screenSize: size)
            }

            if gameState == .playing && asteroid.isWobblingType {
                if asteroid.timeInCurrentPhase >= 6.0 {
                    asteroid.timeInCurrentPhase = 0.0
                    if asteroid.wobblePhase == 0 {
                        asteroid.wobblePhase = 1
                        asteroid.growToNextSize(newSize: .medium, using: &rng)
                    } else if asteroid.wobblePhase == 1 {
                        asteroid.wobblePhase = 2
                        asteroid.growToNextSize(newSize: .large, using: &rng)
                    } else if asteroid.wobblePhase == 2 {
                        let spawned = detonateWobblingAsteroid(asteroid)
                        remainingAsteroids.append(contentsOf: spawned)
                        continue
                    }
                }
            }
            remainingAsteroids.append(asteroid)
        }
        self.activeAsteroids = remainingAsteroids
        
        // Update active lasers (expire or wrap)
        var remainingLasers: [Laser] = []
        for laser in activeLasers {
            let expired = laser.update(deltaTime: deltaTime)
            if expired {
                laser.removeFromParent()
            } else {
                laser.wrapAround(screenSize: size)
                remainingLasers.append(laser)
            }
        }
        self.activeLasers = remainingLasers
        
        // Update active UFOs
        var remainingUFOs: [UFO] = []
        for ufo in activeUFOs {
            // Sanfte Verfolgung nur auf das sichtbare Schiff (kein Homing auf ein „totes"/verstecktes).
            ufo.update(deltaTime: deltaTime, target: ship.isHidden ? nil : ship.position)

            // Shoot at player ship
            if !ship.isHidden {
                if let laser = ufo.shoot(target: ship.position, currentTime: currentTime, using: &rng) {
                    self.addChild(laser)
                    self.activeLasers.append(laser)
                    SoundManager.shared.playUfoSound()
                }
            }
            
            if ufo.isExited(screenSize: size) {
                ufo.removeFromParent()
            } else {
                remainingUFOs.append(ufo)
            }
        }
        self.activeUFOs = remainingUFOs
        
        // Update active Gravity Wells
        var remainingWells: [GravityWell] = []
        for well in activeGravityWells {
            let collapsed = well.update(deltaTime: deltaTime)
            if collapsed {
                well.removeFromParent()
            } else {
                if gameMode == .madMeteoroids {
                    // Gravity Wells sind stationär, kreisen aber im Mad-Modus mit dem Feld mit.
                    well.position = rotatedAroundOrigin(well.position, by: fieldDeltaThisFrame)
                }
                remainingWells.append(well)
            }
        }
        self.activeGravityWells = remainingWells
        
        // Update active PowerUps
        var remainingPowerUps: [PowerUp] = []
        for p in activePowerUps {
            let expired = p.update(deltaTime: deltaTime)
            if expired {
                p.removeFromParent()
            } else {
                if gameMode == .madMeteoroids {
                    p.position = rotatedAroundOrigin(p.position, by: fieldDeltaThisFrame)
                    p.velocity = rotatedAroundOrigin(p.velocity, by: fieldDeltaThisFrame)
                    p.position = circularWrapped(p.position, radius: madFieldRadius())
                } else {
                    p.wrapAround(screenSize: size)
                }
                remainingPowerUps.append(p)
            }
        }
        self.activePowerUps = remainingPowerUps
        
        // Process Invincibility blinks
        let isInvincible = currentTime < invincibilityEndTime
        if isInvincible {
            ship.alpha = sin(currentTime * 30.0) > 0.0 ? 0.3 : 0.8
        } else {
            ship.alpha = 1.0
        }
    }
    
    // MARK: - Damage / Shield logic
    
    func damageShip() {
        if gameMode == .classicAsteroids {
            destroyClassicShip(cause: lastDeathCause)
            return
        }
        if ship.isShieldActive {
            ship.shieldLevel -= 1   // eine Schild-Stufe absorbiert den Treffer
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ship.position)
            invincibilityEndTime = gameTime + 1.5
            shakeCamera(amplitude: 4.5, numberOfShakes: 6, durationPerShake: 0.03)
        } else if extraLives > 0 {
            // Extra-Life-Power-up: kein Game Over – stattdessen in der Mitte wiederbeleben und
            // kurz unsterblich machen. Beim Revive gehen ALLE aktiven Power-ups verloren.
            extraLives -= 1
            updateLivesLabel()
            resetPowerUpsOnRevive()
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ship.position)
            ship.position = .zero
            ship.velocity = .zero
            invincibilityEndTime = gameTime + extraLifeInvincibility
            shakeCamera(amplitude: 6.0, numberOfShakes: 7, durationPerShake: 0.035)
            showPowerUpNotification(text: "REVIVED!", color: SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0))
        } else {
            triggerGameOver()
        }
    }

    // MARK: - Camera Shake
    
    /// Triggers a subtle procedural screen shake on the camera.
    private func shakeCamera(amplitude: CGFloat = 3.0, numberOfShakes: Int = 5, durationPerShake: TimeInterval = 0.03) {
        cameraNode.removeAction(forKey: "cameraShake")
        
        var actions: [SKAction] = []
        // codereview-ok: Kamera-Shake ist ein explizit NICHT-geseedeter Stream ohne Sim-Einfluss — by design (2026-07-01)
        for _ in 0..<numberOfShakes {
            let dx = CGFloat.random(in: -amplitude...amplitude)
            let dy = CGFloat.random(in: -amplitude...amplitude)
            let move = SKAction.moveBy(x: dx, y: dy, duration: durationPerShake)
            let moveBack = move.reversed()
            actions.append(move)
            actions.append(moveBack)
        }
        
        // Reset to exact center
        actions.append(SKAction.move(to: .zero, duration: 0.0))
        
        cameraNode.run(SKAction.sequence(actions), withKey: "cameraShake")
    }
    
    // MARK: - Entity Spawning & Game Flow Management
    
    /// Spawns a new procedurally generated asteroid far away from the ship's center.
    public func spawnAsteroid() {
        if gameState == .playing && gameMode == .classicAsteroids {
            spawnClassicLargeAsteroid()
            return
        }
        let sizeClass = Asteroid.AsteroidSize.allCases.randomElement(using: &rng) ?? .large

        let config = currentConfig()
        let totalWeight = config.normalWeight + config.implodingWeight + config.wobblingWeight
        let isImploding: Bool
        let isWobbling: Bool
        if totalWeight > 0 {
            let rand = Int.random(in: 0..<totalWeight, using: &rng)
            if rand < config.normalWeight {
                isImploding = false
                isWobbling = false
            } else if rand < config.normalWeight + config.implodingWeight {
                isImploding = true
                isWobbling = false
            } else {
                isImploding = false
                isWobbling = true
            }
        } else {
            isImploding = false
            isWobbling = false
        }
        
        let asteroid = Asteroid(sizeClass: sizeClass, isImplodingType: isImploding, isWobblingType: isWobbling, using: &rng)

        // Fallback for zero screen size setup bounds
        let width = size.width > 100 ? size.width : 1024.0
        let height = size.height > 100 ? size.height : 768.0
        
        let halfWidth = width / 2
        let halfHeight = height / 2
        let diagonal = sqrt(halfWidth * halfWidth + halfHeight * halfHeight)
        let buffer: CGFloat = 80.0
        let spawnRadius = diagonal + buffer
        
        var spawnPos = CGPoint.zero
        var attempts = 0
        let minSafeDistance: CGFloat = 250.0
        
        repeat {
            let angle = CGFloat.random(in: 0..<(2.0 * .pi), using: &rng)
            let distance = spawnRadius + CGFloat.random(in: 0...50, using: &rng)
            spawnPos = CGPoint(
                x: distance * cos(angle),
                y: distance * sin(angle)
            )
            attempts += 1
            
            // Check if proposed position is in front cone of ship (45 degrees)
            let dirToAst = atan2(spawnPos.y - ship.position.y, spawnPos.x - ship.position.x)
            var diff = dirToAst - ship.zRotation
            while diff > .pi { diff -= 2.0 * .pi }
            while diff < -.pi { diff += 2.0 * .pi }
            let inFrontCone = abs(diff) < (.pi / 4.0)
            
            if distanceBetween(spawnPos, ship.position) >= minSafeDistance && !inFrontCone {
                break
            }
        } while attempts < 50
        
        if attempts >= 50 {
            // Fallback: Choose a random angle outside the front cone relative to the ship (between 45 and 315 degrees)
            let safeAngleOffset = CGFloat.random(in: (.pi / 4.0)...(7.0 * .pi / 4.0), using: &rng)
            let theta = ship.zRotation + safeAngleOffset
            let dx = cos(theta)
            let dy = sin(theta)
            
            // Ray-circle intersection to find the point on the spawnRadius circle
            let px = ship.position.x
            let py = ship.position.y
            let b = px * dx + py * dy
            let c = px * px + py * py - spawnRadius * spawnRadius
            let disc = b * b - c
            if disc >= 0 {
                let t = -b + sqrt(disc)
                spawnPos = CGPoint(x: px + t * dx, y: py + t * dy)
            } else {
                // Extreme fallback
                spawnPos = CGPoint(x: -spawnRadius, y: 0)
            }
        }
        
        asteroid.position = spawnPos
        
        // Scale speed with level configuration.
        // Der Asteroid fliegt von außerhalb des Bildschirms herein und wird auf einen
        // zufälligen Punkt im INNEREN Spielfeld-Bereich gezielt. So ist garantiert, dass seine
        // Bahn das sichtbare Rechteck durchquert (Mittelpunkt tritt ein) — er bleibt nicht durch
        // einen zu steilen Winkel am Bild vorbei hängen (siehe Asteroid.hasEnteredScreen).
        let targetX = CGFloat.random(in: -halfWidth * 0.6...halfWidth * 0.6, using: &rng)
        let targetY = CGFloat.random(in: -halfHeight * 0.6...halfHeight * 0.6, using: &rng)
        let movementAngle = atan2(targetY - asteroid.position.y, targetX - asteroid.position.x)
        let speed = CGFloat.random(in: 40.0...100.0, using: &rng) * config.speedMultiplier
        asteroid.velocity = CGPoint(
            x: speed * cos(movementAngle),
            y: speed * sin(movementAngle)
        )
        
        self.addChild(asteroid)
        self.activeAsteroids.append(asteroid)
    }
    
    private func showPowerUpNotification(text: String, color: SKColor) {
        powerUpNotificationLabel.text = text
        powerUpNotificationLabel.fontColor = color
        
        if ship.position.y > 60.0 {
            powerUpNotificationLabel.position = CGPoint(x: 0, y: -150)
        } else {
            powerUpNotificationLabel.position = CGPoint(x: 0, y: 150)
        }
        
        powerUpNotificationLabel.isHidden = false
        powerUpNotificationLabel.removeAllActions()
        powerUpNotificationLabel.xScale = 1.0
        powerUpNotificationLabel.yScale = 1.0
        powerUpNotificationLabel.alpha = 0.0
        
        let fadeIn = SKAction.fadeIn(withDuration: 0.1)
        let wait = SKAction.wait(forDuration: 1.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let hide = SKAction.run { [weak self] in
            self?.powerUpNotificationLabel.isHidden = true
        }
        powerUpNotificationLabel.run(SKAction.sequence([fadeIn, wait, fadeOut, hide]))
    }
    
    private func detonateWobblingAsteroid(_ ast: Asteroid) -> [Asteroid] {
        SoundManager.shared.playExplosion()
        createImplosionExplosion(at: ast.position)
        shakeCamera(amplitude: 8.0, numberOfShakes: 8, durationPerShake: 0.04)
        
        if !ship.isHidden && distanceBetween(ast.position, ship.position) < 150.0 {
            lastDeathCause = .wobblingAsteroid
            damageShip()
        }
        
        var spawned: [Asteroid] = []
        let directions = [0.0, .pi / 2.0, .pi, 3.0 * .pi / 2.0]
        for angle in directions {
            let smallAst = Asteroid(sizeClass: .small, using: &rng)
            smallAst.position = ast.position
            // Splitter entstehen am Ort des Eltern-Asteroiden (im Bild) und nehmen dessen
            // Eintritts-Status mit, damit sie sofort normal am Kanten-Umlauf teilnehmen.
            smallAst.hasEnteredScreen = ast.hasEnteredScreen
            let speed: CGFloat = 180.0
            smallAst.velocity = CGPoint(x: speed * cos(angle), y: speed * sin(angle))
            self.addChild(smallAst)
            spawned.append(smallAst)
        }
        
        ast.removeFromParent()
        return spawned
    }
    
    /// Spawns two split children when an asteroid breaks.
    private func createSplitChildren(for parent: Asteroid) -> [Asteroid] {
        let childSize: Asteroid.AsteroidSize
        switch parent.sizeClass {
        case .large: childSize = .medium
        case .medium: childSize = .small
        case .small: return []
        }
        
        var children: [Asteroid] = []
        for i in 0..<2 {
            let child = Asteroid(sizeClass: childSize, using: &rng)
            child.position = parent.position
            // Splitter erben den Eintritts-Status des Eltern-Asteroiden (siehe wrapAround).
            child.hasEnteredScreen = parent.hasEnteredScreen

            // Angle parent velocity +/- 30 degrees, speed up by asteroidSplitSpeedFactor
            let baseAngle = atan2(parent.velocity.y, parent.velocity.x)
            let deviation = (i == 0 ? 0.52 : -0.52) + CGFloat.random(in: -0.08...0.08, using: &rng)
            let newAngle = baseAngle + deviation
            let newSpeed = sqrt(parent.velocity.x * parent.velocity.x + parent.velocity.y * parent.velocity.y)
                * GameplayTuning.asteroidSplitSpeedFactor
            
            child.velocity = CGPoint(
                x: newSpeed * cos(newAngle),
                y: newSpeed * sin(newAngle)
            )
            
            self.addChild(child)
            children.append(child)
        }
        return children
    }
    
    /// Spawns a floating Power-Up capsule (gewichtete Typ-Auswahl).
    private func spawnPowerUp(at pos: CGPoint) {
        // Typ ZUERST in eine lokale Variable ziehen: randomPowerUpType() mutiert rng, und der
        // PowerUp-Init nimmt rng als inout — beides im selben Ausdruck würde gegen Swifts
        // Exklusivitätsprüfung verstoßen.
        let type = randomPowerUpType()
        let powerUp = PowerUp(type: type, position: pos, using: &rng)
        self.addChild(powerUp)
        self.activePowerUps.append(powerUp)
    }

    /// Wählt einen Power-up-Typ gewichtet aus (Extra Life selten, Triple etwas häufiger).
    private func randomPowerUpType() -> PowerUpType {
        // Extra Life wird in höheren Levels häufiger (mehr Reserven für die härteren Level):
        // L1 = 5, L5 = 13, L10 = 23.
        let extraLifeWeight = 5 + max(0, currentLevel - 1) * 2
        let weights: [(PowerUpType, Int)] = [
            (.shield, 12), (.triple, 14), (.rapid, 10), (.option, 10), (.bomb, 8),
            (.beam, 9), (.rear, 10), (.compress, 9), (.extraLife, extraLifeWeight)
        ]
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total, using: &rng)
        for (type, w) in weights {
            if r < w { return type }
            r -= w
        }
        return .triple
    }
    
    /// Handles collection updates for powerups.
    func collectPowerUp(_ powerUp: PowerUp) {
        let now = gameTime
        let text: String
        let color: SKColor
        
        switch powerUp.type {
        case .shield:
            // Additiv bis Stufe 3 (jede Stufe fängt einen Treffer ab); endlos bis Treffer/Revive.
            ship.shieldLevel = min(3, ship.shieldLevel + 1)
            text = "SHIELD LEVEL \(ship.shieldLevel)!"
            color = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        case .triple:
            // Endlos (additiv) bis zum Revive – kein Timer.
            tripleShotEndTime = .greatestFiniteMagnitude
            text = "TRIPLE LASER!"
            color = SKColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)
        case .rapid:
            rapidFireEndTime = now + 12.0
            text = "RAPID FIRE ACTIVE!"
            color = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        case .option:
            text = "OPTION DRONE ACQUIRED!"
            color = SKColor(red: 0.8, green: 0.0, blue: 1.0, alpha: 1.0)
            if options.count < 2 {
                let drone = OptionDrone()
                drone.position = ship.position
                self.addChild(drone)
                options.append(drone)
                applyCompressScale()   // neue Drohne an evtl. aktive Compress-Größe anpassen
            }
        case .bomb:
            detonateBomb()
            text = "SCREEN BOMB DETONATED!"
            color = SKColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0)
        case .beam:
            beamEndTime = now + beamDuration
            text = "LASER BEAM! (HOLD FIRE)"
            color = SKColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)
        case .rear:
            rearLaserEndTime = now + rearLaserDuration
            text = "REAR LASER!"
            color = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        case .compress:
            // Zwei Stufen: 1 = klein, 2 = winzig (ein Pixel) – Schiff und Beiboote. Timer (24s).
            compressLevel = min(2, compressLevel + 1)
            compressEndTime = now + compressDuration
            applyCompressScale()
            text = compressLevel >= 2 ? "COMPRESSED x2!" : "COMPRESSED!"
            color = SKColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
        case .extraLife:
            extraLives += 1
            updateLivesLabel()
            text = "EXTRA LIFE!"
            color = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0)
        }

        showPowerUpNotification(text: text, color: color)
    }

    /// Setzt Schiff UND Beiboote auf die zur aktuellen Compress-Stufe passende Größe.
    private func applyCompressScale() {
        let scale: CGFloat
        switch compressLevel {
        case 2:  scale = compressLevel2Scale
        case 1:  scale = compressScale
        default: scale = 1.0
        }
        ship.setScale(scale)
        for drone in options { drone.setScale(scale) }
    }

    /// Beim Revive (Extra Life) gehen ALLE aktiven Power-ups verloren – Timer, Schild, Beiboote,
    /// Compress. Das Schiff kehrt auf Normalgröße zurück.
    private func resetPowerUpsOnRevive() {
        tripleShotEndTime = 0.0
        rapidFireEndTime = 0.0
        beamEndTime = 0.0
        rearLaserEndTime = 0.0
        compressEndTime = 0.0
        compressLevel = 0
        beamNode.isHidden = true
        ship.shieldLevel = 0
        for drone in options { drone.removeFromParent() }
        options.removeAll()
        applyCompressScale()   // -> Normalgröße
    }

    /// Zündet die Screen Bomb: legt einen einzelnen Schuss-Treffer auf JEDES Objekt am Bildschirm
    /// (alle Asteroiden + UFOs) – über dieselbe Treffer-Logik wie ein Laser. Plus Schockwelle,
    /// Kamera-Wackeln und Bomben-Sound; gegnerische Laser werden gelöscht.
    private func detonateBomb() {
        SoundManager.shared.playBomb()
        shakeCamera(amplitude: 11.0, numberOfShakes: 11, durationPerShake: 0.035)
        
        // Detonation shockwave visual
        let shockwave = SKShapeNode(circleOfRadius: 10.0)
        shockwave.strokeColor = .white
        shockwave.fillColor = .clear
        shockwave.lineWidth = 3.0
        shockwave.position = ship.position
        VectorGlowRenderer.markStroke(shockwave)
        self.addChild(shockwave)
        
        let expand = SKAction.scale(to: 60.0, duration: 0.55)
        let fade = SKAction.fadeOut(withDuration: 0.55)
        let group = SKAction.group([expand, fade])
        let remove = SKAction.removeFromParent()
        shockwave.run(SKAction.sequence([group, remove]))
        
        // Jeden Asteroiden GENAU EINMAL treffen – exakt so, als würde ein Laserschuss ihn treffen
        // (dieselbe processPlayerHitOnAsteroid-Logik wie bei der Laser-Kollision). Damit verhalten
        // sich alle Typen konsistent: normale splitten, IMPLODIERENDE wachsen (kollabieren erst beim
        // 4. Treffer), WOBBELNDE geben Punkte und verschwinden. Commit wie bei der Laser-Kollision:
        // verbrauchte Asteroiden raus, neue Splitter rein.
        var hitAsteroids = Set<Asteroid>()
        var newAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            processPlayerHitOnAsteroid(asteroid, hitPosition: asteroid.position,
                                       hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)
        }
        if !hitAsteroids.isEmpty {
            activeAsteroids = activeAsteroids.filter { asteroid in
                if hitAsteroids.contains(asteroid) {
                    asteroid.removeFromParent()
                    return false
                }
                return true
            }
        }
        activeAsteroids.append(contentsOf: newAsteroids)

        // Ebenso jedes UFO einmal treffen – ein Schuss zerstört ein UFO sofort (Punkte,
        // mögliche Power-up-Beute, Explosion). Gleiche Wirkung wie ein Laser-Treffer.
        for ufo in activeUFOs {
            self.score += ufo.pointValue
            if Double.random(in: 0...1, using: &rng) <= 0.20 {
                spawnPowerUp(at: ufo.position)
            }
            createShipExplosion(at: ufo.position)
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()

        // Weltraumkatzen: ein Bomben-Treffer = ein direkter Schuss (eine Stufe Schaden), nicht
        // zwangsläufig tödlich (Katzen haben mehrere HP). Zerstörte geben Punkte + mögliche Beute.
        var survivingCats: [SpaceCat] = []
        for cat in activeCats {
            let destroyed = cat.registerHit()
            createShipExplosion(at: cat.position)
            if destroyed {
                self.score += cat.pointValue
                if Double.random(in: 0...1, using: &rng) <= 0.5 {
                    spawnPowerUp(at: cat.position)
                }
                cat.removeFromParent()
            } else {
                survivingCats.append(cat)
            }
        }
        activeCats = survivingCats

        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

        // Clear enemy lasers (UFO-Schüsse UND Katzen-Augenlaser)
        var remainingLasers: [Laser] = []
        for laser in activeLasers {
            if laser.type != .normal {
                laser.removeFromParent()
            } else {
                remainingLasers.append(laser)
            }
        }
        self.activeLasers = remainingLasers
    }

    /// Verarbeitet einen Spieler-Treffer auf einen Asteroiden (Implodierend wächst/kollabiert,
    /// Wobbling gibt Punkte, Normal splittet) inkl. Score, Power-up-Drop und Effekten.
    /// Wird von Laser-Treffern UND vom Laserbeam genutzt. Trägt verbrauchte Asteroiden in
    /// `hitAsteroids` und entstehende Splitter in `newAsteroids` ein (Commit erfolgt beim Aufrufer).
    private func processPlayerHitOnAsteroid(_ asteroid: Asteroid, hitPosition: CGPoint,
                                            hitAsteroids: inout Set<Asteroid>,
                                            newAsteroids: inout [Asteroid]) {
        SoundManager.shared.playExplosion()
        let config = currentConfig()
        if asteroid.isImplodingType {
            asteroid.hitCount += 1
            let newScale = 1.0 + 0.4 * CGFloat(asteroid.hitCount)
            asteroid.xScale = newScale
            asteroid.yScale = newScale

            createExplosion(at: hitPosition, sizeClass: .small)

            if asteroid.hitCount >= 4 {
                triggerImplosionCollapse(asteroid: asteroid)
                hitAsteroids.insert(asteroid)
            }
        } else if asteroid.isWobblingType {
            hitAsteroids.insert(asteroid)
            self.score += 200
            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

            if Double.random(in: 0...1, using: &rng) <= config.powerUpChance * powerUpDropScale {
                spawnPowerUp(at: asteroid.position)
            }

            createExplosion(at: asteroid.position, sizeClass: asteroid.sizeClass)
            shakeCamera(amplitude: 3.5, numberOfShakes: 4, durationPerShake: 0.02)
        } else {
            hitAsteroids.insert(asteroid)

            let points: Int
            switch asteroid.sizeClass {
            case .large:
                points = 20
                newAsteroids.append(contentsOf: createSplitChildren(for: asteroid))
            case .medium:
                points = 50
                newAsteroids.append(contentsOf: createSplitChildren(for: asteroid))
            case .small:
                points = 100
            }

            self.score += points
            scoreLabel.text = "SCORE: \(String(format: "%05d", score))"

            if Double.random(in: 0...1, using: &rng) <= config.powerUpChance * powerUpDropScale {
                spawnPowerUp(at: asteroid.position)
            }

            createExplosion(at: asteroid.position, sizeClass: asteroid.sizeClass)
            shakeCamera(amplitude: asteroid.sizeClass == .large ? 3.0 : (asteroid.sizeClass == .medium ? 2.0 : 1.0), numberOfShakes: 4, durationPerShake: 0.02)
        }
    }

    /// Wickelt zeitbasierte Power-up-Effekte pro Frame ab: Compress nach Ablauf zurücksetzen und
    /// den Laserbeam betreiben, solange das Power-up läuft UND Space gehalten wird.
    private func updateTimedPowerUpEffects(currentTime: TimeInterval) {
        let now = gameTime

        // Compress: nach Ablauf Schiff (und Beiboote) wieder auf Originalgröße.
        if compressEndTime > 0 && now >= compressEndTime {
            compressEndTime = 0
            compressLevel = 0
            applyCompressScale()
        }

        // Laserbeam: während der Power-up-Dauer, solange gefeuert wird (Auto-Feuer oder Taste).
        if now < beamEndTime && (autoFire || isSpaceHeld) && !ship.isHidden {
            fireBeam(currentTime: currentTime)
        } else {
            beamNode.isHidden = true
        }
    }

    /// Baut den Laserbeam dieses Frames auf: eine Polylinie ab der Schiffsnase in Blickrichtung,
    /// halbe Bildschirmbreite lang, an den Bildschirmkanten toroidal umgebrochen (ragt also auf der
    /// gegenüberliegenden Seite wieder herein). Zerstört Asteroiden entlang des Strahls.
    func fireBeam(currentTime: TimeInterval) {
        let halfW = (size.width > 100 ? size.width : 1024.0) / 2
        let halfH = (size.height > 100 ? size.height : 768.0) / 2
        let angle = ship.zRotation
        let dx = cos(angle)
        let dy = sin(angle)
        let beamLength = halfW * 2.0 * 0.5 // halbe Bildschirmbreite
        let step: CGFloat = 7.0
        let count = max(1, Int(beamLength / step))

        let tipX = ship.position.x + 18.0 * dx
        let tipY = ship.position.y + 18.0 * dy

        // Stützpunkte entlang der Richtung, jeweils toroidal in [-half, half] gewrappt.
        var points: [CGPoint] = []
        points.reserveCapacity(count + 1)
        for i in 0...count {
            let d = CGFloat(i) * step
            let wx = wrapCoordinate(tipX + dx * d, half: halfW)
            let wy = wrapCoordinate(tipY + dy * d, half: halfH)
            points.append(CGPoint(x: wx, y: wy))
        }

        // Visual aufbauen; bei einem Wrap-Sprung den Stift neu ansetzen.
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 1..<points.count {
            let prev = points[i - 1]
            let cur = points[i]
            if abs(cur.x - prev.x) > halfW || abs(cur.y - prev.y) > halfH {
                path.move(to: cur)
            } else {
                path.addLine(to: cur)
            }
        }
        beamNode.path = path
        beamNode.isHidden = false

        // Kollision: Asteroiden zerstören, die einen Strahl-Stützpunkt enthalten.
        var hitAsteroids = Set<Asteroid>()
        var newAsteroids: [Asteroid] = []
        for asteroid in activeAsteroids {
            if hitAsteroids.contains(asteroid) { continue }
            let poly = asteroid.getWorldVertices()
            var hit = false
            for p in points where CollisionHelper.isPointInPolygon(p, polygon: poly) {
                hit = true
                break
            }
            if hit {
                processPlayerHitOnAsteroid(asteroid, hitPosition: asteroid.position,
                                           hitAsteroids: &hitAsteroids, newAsteroids: &newAsteroids)
            }
        }
        if !hitAsteroids.isEmpty {
            activeAsteroids = activeAsteroids.filter { asteroid in
                if hitAsteroids.contains(asteroid) {
                    asteroid.removeFromParent()
                    return false
                }
                return true
            }
        }
        activeAsteroids.append(contentsOf: newAsteroids)

        // Der Strahl trifft auch die anderen Gegner – sonst kann man UFOs, Katzen und den Boss mit
        // dem Beam nicht erledigen (genau dieser Bug fiel beim Spielen auf). UFOs sterben sofort
        // (1 Treffer), Mehr-HP-Gegner (Katze/Boss) werden GEDROSSELT getroffen (lastBeamHitTime),
        // sonst würden sie beim Dauer-Strahl pro Frame Schaden nehmen und sofort zerschmelzen.
        let beamHitInterval: TimeInterval = 0.12
        var scoreChanged = false

        // UFOs: sofort zerstören (wie ein Laser-Treffer).
        var hitUFOs: [UFO] = []
        for ufo in activeUFOs {
            let poly = ufo.getWorldVertices()
            if points.contains(where: { CollisionHelper.isPointInPolygon($0, polygon: poly) }) {
                hitUFOs.append(ufo)
            }
        }
        for ufo in hitUFOs {
            self.score += ufo.pointValue
            scoreChanged = true
            if Double.random(in: 0...1, using: &rng) <= 0.20 { spawnPowerUp(at: ufo.position) }
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ufo.position)
            ufo.removeFromParent()
        }
        if !hitUFOs.isEmpty { activeUFOs.removeAll { hitUFOs.contains($0) } }

        // Weltraumkatzen: gedrosselter Treffer pro Strahl-Kontakt.
        var deadCats: [SpaceCat] = []
        for cat in activeCats {
            let near = points.contains { distanceBetween($0, cat.position) <= cat.collisionRadius }
            guard near, currentTime - cat.lastBeamHitTime >= beamHitInterval else { continue }
            cat.lastBeamHitTime = currentTime
            let destroyed = cat.registerHit()
            createShipExplosion(at: cat.position)
            if destroyed {
                self.score += cat.pointValue
                scoreChanged = true
                if Double.random(in: 0...1, using: &rng) <= 0.5 { spawnPowerUp(at: cat.position) }
                deadCats.append(cat)
            }
        }
        if !deadCats.isEmpty {
            activeCats.removeAll { deadCats.contains($0) }
            deadCats.forEach { $0.removeFromParent() }
        }

        // Kopf-Boss: ebenfalls gedrosselt.
        if let head = activeHead {
            let near = points.contains { distanceBetween($0, head.position) <= head.collisionRadius }
            if near && currentTime - head.lastBeamHitTime >= beamHitInterval {
                head.lastBeamHitTime = currentTime
                let destroyed = head.registerHit()
                createShipExplosion(at: head.position)
                shakeCamera(amplitude: 5.0, numberOfShakes: 6, durationPerShake: 0.025)
                if destroyed {
                    self.score += 2000
                    scoreChanged = true
                    createShipExplosion(at: head.position)
                    shakeCamera(amplitude: 9.0, numberOfShakes: 10, durationPerShake: 0.03)
                    head.removeFromParent()
                    activeHead = nil
                }
            }
        }

        if scoreChanged { scoreLabel.text = "SCORE: \(String(format: "%05d", score))" }
    }

    /// Wrappt eine Koordinate toroidal in den Bereich [-half, half].
    private func wrapCoordinate(_ value: CGFloat, half: CGFloat) -> CGFloat {
        let full = half * 2.0
        var v = (value + half).truncatingRemainder(dividingBy: full)
        if v < 0 { v += full }
        return v - half
    }

    private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return sqrt((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y))
    }
    
    /// Triggers the Game Over state.
    func triggerGameOver() {
        // Aufnahme dieses Laufs abschließen und als `lastReplay` bereitstellen (für die Anbindung an
        // einen Highscore). Während einer Wiedergabe läuft kein Recorder, daher passiert hier nichts.
        if let recorder = recorder {
            lastReplay = recorder.makeReplay()
            self.recorder = nil
            if let replay = lastReplay { archiveReplayIfEnabled(replay) }
        }

        ship.isHidden = true
        ship.velocity = .zero
        ship.shieldLevel = 0
        
        // Stop key states and engine sound hum
        activeKeys.removeAll()
        SoundManager.shared.setThrustActive(false)

        if gameMode == .classicAsteroids {
            // Das letzte Schiff ist im Classic-Pfad bereits beim Treffer als weiße Vektortrümmer
            // explodiert; nach der 2,15-s-Wartezeit hier weder einen zweiten cyanfarbenen Effekt
            // noch den Standard-Sample-Sound darüberlegen.
            SoundManager.shared.setClassicSaucer(isSmall: nil)
        } else {
            // Play explosion sound effect
            SoundManager.shared.playExplosion()
            createShipExplosion(at: ship.position)

            // Trigger large camera shake
            shakeCamera(amplitude: 8.0, numberOfShakes: 8, durationPerShake: 0.04)
        }
        
        // Demo-Lauf (Autopilot): KEIN Highscore-Eintrag – der Pilot darf sich nicht verewigen. Die
        // Highscore-Liste wird trotzdem 10 s gezeigt (der Game-Over-Screen enthält sie ohnehin),
        // danach schaltet der Attract-Kreislauf weiter (siehe updateAttract). Zuerst `isDemoActive`
        // auswerten, DANN die Persona lösen (sonst würde die Bedingung falsch greifen).
        if isDemoActive {
            autopilotPersona = nil
            attractPhase = .demoScores
            attractTimer = 0
            transitionTo(.gameOver)
            return
        }
        // Check for high score. Während einer Wiedergabe NICHT in die Initialen-Eingabe springen –
        // wir schauen den Lauf nur an, der Score steht bereits in der Bestenliste.
        if replayPlayer == nil && isNewHighScore(score: score) {
            transitionTo(.nameEntry)
        } else {
            transitionTo(.gameOver)
        }
    }
    
    /// Resets the game state and starts a fresh play session.
    public func restartGame() {
        // Vorher auf .startScreen setzen, damit in transitionTo(.playing) der Fresh-Game-Zweig
        // (else) greift und nicht der Resume-Pfad — sonst würde aus .quitConfirmation heraus nur
        // fortgesetzt statt zurückgesetzt (analog zu startNewGame). Der Doc-Kommentar verspricht
        // einen echten Reset, also erzwingen wir den Fresh-Game-Pfad in jedem Ausgangszustand.
        gameState = .startScreen
        transitionTo(.playing)
    }

    /// Startet ein frisches Spiel. Ohne `seed` wird einer ausgewürfelt; mit `seed` wird er
    /// übernommen — das ist der Einstiegspunkt für reproduzierbare Läufe (Replay/Tests).
    public func startNewGame(seed: UInt64? = nil) {
        pendingSeed = seed
        // Über den State-Wechsel auf .playing läuft der Fresh-Game-Pfad (setzt currentSeed/rng).
        // Aus dem laufenden Spiel heraus zuerst zurücksetzen, damit der else-Zweig greift.
        gameState = .startScreen
        transitionTo(.playing)
    }

    // MARK: - Replay-Wiedergabe (Phase 2.3)

    /// Startet die Wiedergabe einer Aufnahme: frisches Spiel mit deren Seed/Level/Modus, danach
    /// treibt der `replayPlayer` die Szene Frame für Frame (siehe update()). Inkompatible Aufnahmen
    /// (fremdes Logik-Tag) werden abgelehnt; Rückgabe `false`.
    @discardableResult
    public func startReplay(_ replay: Replay) -> Bool {
        guard replay.isCompatible else { return false }
        replayPlayer = ReplayPlayer(replay: replay)
        // Anfangsbedingungen der Aufnahme übernehmen und frisch starten. Da `replayPlayer` gesetzt
        // ist, legt der Fresh-Game-Pfad KEINEN Recorder an (wir zeichnen die Wiedergabe nicht auf).
        selectedStartLevel = replay.startLevel
        selectedMode = replay.gameMode
        // Auto-Feuer-Zustand der Aufnahme wiederherstellen (beeinflusst das Feuern in update() und
        // damit den Spielverlauf). `replayAutoFireOverride` erlaubt es, das für alte Aufnahmen ohne
        // gespeichertes Feld (vor dem Fix) von außen zu erzwingen.
        autoFire = replay.gameMode == .classicAsteroids
            ? false
            : (replayAutoFireOverride ?? replay.autoFire)
        startNewGame(seed: replay.seed)
        return true
    }

    /// Speist eine aufgezeichnete Eingabe während der Wiedergabe ein. Setzt `isInjectingReplay`, um
    /// die Live-Eingabe-Sperre in den Tasten-Handlern gezielt zu umgehen.
    func injectReplayInput(keyCode: UInt16, isDown: Bool) {
        isInjectingReplay = true
        if isDown {
            handleKeyDown(keyCode: keyCode, characters: nil, charactersIgnoringModifiers: nil, isCommandDown: false)
        } else {
            handleKeyUp(keyCode: keyCode)
        }
        isInjectingReplay = false
    }

    /// Räumt eine zu Ende gelaufene Wiedergabe ab und kehrt zum Startbildschirm zurück. Die
    /// Simulation hat den Lauf bereits selbst beendet (deterministisch dasselbe Game Over wie in der
    /// Aufnahme); hier nur Player lösen und Ansicht wechseln.
    private func finishReplay() {
        replayPlayer = nil
        transitionTo(.startScreen)
    }

    /// Bricht eine laufende Wiedergabe vorzeitig ab (ESC) und kehrt zum Startbildschirm zurück.
    private func exitReplay() {
        replayPlayer = nil
        transitionTo(.startScreen)
    }

    /// Startet die Wiedergabe des Highscore-Eintrags mit gegebenem Index (0-basiert), falls dieser
    /// eine kompatible Aufnahme trägt. Einstiegspunkt für die Highscore-Ansicht (Tasten 1–5).
    @discardableResult
    public func watchHighScoreReplay(at index: Int) -> Bool {
        guard index >= 0, index < highScores.count else { return false }
        guard let replay = replay(for: highScores[index]) else { return false }
        return startReplay(replay)
    }

    /// Aktiviert/deaktiviert den Headless-Render-Modus (HUD/Overlay dauerhaft aus). Für den
    /// GIF-Renderer gedacht; im normalen Spiel nicht nutzen.
    public func setHUDHiddenForRender(_ hidden: Bool) {
        renderHUDHidden = hidden
        if hidden { hideRenderHUD() }
    }

    /// Blendet alle HUD-/Overlay-Labels aus, die in einem Promo-GIF stören würden.
    private func hideRenderHUD() {
        scoreLabel.isHidden = true
        hiScoreLabel.isHidden = true
        timerLabel.isHidden = true
        levelLabel.isHidden = true
        livesLabel.isHidden = true
        replayOverlayLabel.isHidden = true
    }

    /// Ermittelt die Ziffer 1–9 aus einem Tastendruck – entweder aus den Zeichen (macOS-keyDown,
    /// iOS) oder aus den Zifferntasten-Keycodes der oberen Reihe (für headless/Controller). `nil`,
    /// wenn es keine Ziffer ist.
    private func digitForKey(keyCode: UInt16, characters: String?) -> Int? {
        if let c = characters, let n = Int(c) { return n }
        switch keyCode {
        case 18: return 1; case 19: return 2; case 20: return 3
        case 21: return 4; case 23: return 5; case 22: return 6
        case 26: return 7; case 28: return 8; case 25: return 9
        default: return nil
        }
    }

    /// Läuft gerade eine Replay-Wiedergabe?
    public var isReplaying: Bool { replayPlayer != nil }

    /// Für Tests: die aktuelle (noch laufende) Aufnahme als `Replay` abgreifen, ohne sie zu beenden.
    public func currentReplayForTesting() -> Replay? {
        recorder?.makeReplay()
    }

    /// Transitions between game states, configuring visible overlay nodes and sound.
    public func transitionTo(_ newState: GameState) {
        let previousState = self.gameState
        self.gameState = newState

        // Classic besitzt mit seinem beschleunigenden Herzschlag eine eigene Arcade-Musik. Die
        // Theme-Playlist bleibt deshalb für die gesamte Classic-Partie einschließlich Pause,
        // Initialeneingabe und Game Over stumm. In Menüs und Standard-Modi gilt wieder unverändert
        // die Spielerpräferenz des „M"-Schalters.
        switch newState {
        case .playing:
            MusicPlayer.shared.setPlaybackSuppressed(selectedMode == .classicAsteroids)
        case .nameEntry, .gameOver, .quitConfirmation:
            MusicPlayer.shared.setPlaybackSuppressed(gameMode == .classicAsteroids)
        case .startScreen, .glossary, .highScores, .settings:
            MusicPlayer.shared.setPlaybackSuppressed(false)
        }
        
        // Hide all labels first
        titleLabel.isHidden = true
        startPromptLabel.isHidden = true
        instructionsLabel.isHidden = true
        scoreLabel.isHidden = true
        hiScoreLabel.isHidden = true
        nameEntryPromptLabel.isHidden = true
        nameEntryInputLabel.isHidden = true
        gameOverLabel.isHidden = true
        finalScoreLabel.isHidden = true
        restartLabel.isHidden = true
        highScoresTitleLabel.isHidden = true
        for label in highScoreLineLabels {
            label.isHidden = true
        }
        timerLabel.isHidden = true
        levelLabel.isHidden = true
        livesLabel.isHidden = true
        beamNode.isHidden = true
        levelSelectionLabel.isHidden = true
        modeSelectionLabel.isHidden = true
        settingsTitleLabel.isHidden = true
        settingsMusicLabel.isHidden = true
        settingsSfxLabel.isHidden = true
        settingsAutoFireLabel.isHidden = true
        settingsHDRGlowLabel.isHidden = true
        settingsFullScreenLabel.isHidden = true
        settingsHintLabel.isHidden = true
        levelClearedLabel.isHidden = true
        prepareNextLevelLabel.isHidden = true
        
        glossaryContainer.isHidden = true
        glossaryStaticContainer.isHidden = true
        glossaryPromptLabel.isHidden = true
        quitPromptLabel.isHidden = true
        quitSubPromptLabel.isHidden = true
        // Replay-Overlay nur während einer laufenden Wiedergabe im Spielzustand sichtbar (unten gesetzt).
        replayOverlayLabel.isHidden = true
        // Demo-Labels: standardmäßig aus; unten je Zustand wieder eingeblendet.
        demoPromptLabel.isHidden = true
        demoOverlayLabel.isHidden = true

        // Stop sound engine hum
        SoundManager.shared.setThrustActive(false)
        SoundManager.shared.stopAllHeadSounds()
        if case .playing = newState {
            // Classic-Saucer-Ton wird im nächsten Simulationsschritt aus dem Entity-Zustand gesetzt.
        } else {
            SoundManager.shared.setClassicSaucer(isSmall: nil)
        }
        headWasSpawning = false
        
        switch newState {
        case .startScreen:
            SoundManager.shared.setClassicProfileActive(false)
            SoundManager.shared.setClassicSaucer(isSmall: nil)
            if ship.usesClassicAppearance { ship.applyClassicProfile(false) }
            ship.isHidden = true
            ship.position = .zero
            ship.velocity = .zero
            ship.zRotation = 0.0
            ship.shieldLevel = 0
            
            titleLabel.isHidden = false
            startPromptLabel.isHidden = false
            instructionsLabel.isHidden = false
            activateHighScoreBoard(for: selectedMode)
            // Highscore-Liste nur am Startbildschirm zeigen, wenn nicht ausgelagert (macOS).
            if showsHighScoresOnStartScreen {
                highScoresTitleLabel.isHidden = false
                updateHighScoreLabels()
                for label in highScoreLineLabels {
                    label.isHidden = false
                }
            }

            updateLevelSelectionLabel()
            levelSelectionLabel.isHidden = selectedMode == .classicAsteroids

            updateModeSelectionLabel()
            modeSelectionLabel.isHidden = false

            // Musik-/SFX-Anzeige liegt jetzt in den Einstellungen (Startscreen bleibt ruhig).

            // Blink "PRESS SPACE TO START"
            startPromptLabel.removeAction(forKey: "blink")
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let fadeIn = SKAction.fadeIn(withDuration: 0.5)
            let blink = SKAction.sequence([fadeOut, fadeIn])
            startPromptLabel.run(SKAction.repeatForever(blink), withKey: "blink")
            
            // Show & Blink "PRESS I FOR GLOSSARY"
            glossaryPromptLabel.isHidden = false
            glossaryPromptLabel.removeAction(forKey: "blink")
            let glossaryFadeOut = SKAction.fadeOut(withDuration: 0.6)
            let glossaryFadeIn = SKAction.fadeIn(withDuration: 0.6)
            let glossaryBlink = SKAction.sequence([glossaryFadeOut, glossaryFadeIn])
            glossaryPromptLabel.run(SKAction.repeatForever(glossaryBlink), withKey: "blink")
            
            // Demo-Hinweis nur bei aktivem Attract-Modus (echte App), nicht auf iOS-Kompaktlayout.
            if attractModeEnabled && !isCompactLayout {
                demoPromptLabel.isHidden = false
            }

            // iOS-Breitformat: kompaktes Startlayout (Titel sichtbar, Tastatur-Hinweise aus).
            if isCompactLayout { applyCompactStartScreenLayout() }

            // Clean active entities
            clearGameEntities()

            // Keep at least 3 asteroids drifting peacefully in the background
            while activeAsteroids.count < 3 {
                spawnAsteroid()
            }

        case .playing:
            if previousState == .quitConfirmation {
                // Resume game
                scoreLabel.isHidden = false
                hiScoreLabel.isHidden = false
                timerLabel.isHidden = gameMode == .classicAsteroids
                levelLabel.isHidden = false
                
                if isLevelClearing {
                    levelClearedLabel.isHidden = false
                    prepareNextLevelLabel.isHidden = false
                }
                
                ship.isHidden = gameMode == .classicAsteroids
                    ? !classicSession.isShipActive
                    : false
                activeKeys.removeAll()
            } else {
                // Fresh game session

                // Jedes frische Spiel ohne „geerbte" gedrückte Tasten starten. Wichtig nach einer
                // per Touch abgebrochenen Demo: der Autopilot lässt sonst Dreh-/Schub-Codes in
                // `activeKeys` zurück, die sonst ins Menschenspiel durchschlagen (Schiff dreht selbst).
                activeKeys.removeAll()

                // Seed für diesen Lauf festlegen: injizierten Seed übernehmen (Replay/Test) oder
                // einmalig einen neuen aus dem System-RNG würfeln. Danach speist sich ALLE
                // Spiel-Logik aus `rng` (deterministisch reproduzierbar bei gleichem Seed).
                // Falls eine Wiedergabe durch geänderte Logik früher Game Over erreicht, kann ein
                // später aufgezeichneter Space-Impuls als Neustart interpretiert werden. Auch dieser
                // Abweichungspfad muss reproduzierbar bleiben und verwendet daher weiter den Replay-Seed.
                currentSeed = pendingSeed ?? replayPlayer?.replay.seed
                    ?? UInt64.random(in: UInt64.min...UInt64.max)
                pendingSeed = nil
                rng = GameRandom(seed: currentSeed)

                // Aufnahme dieses Laufs starten – aber NICHT während einer Replay-Wiedergabe (sonst
                // zeichneten wir die Wiedergabe selbst wieder auf). Modus/Level werden gleich gesetzt;
                // der Recorder hält Seed + diese Startwerte fest (gameMode wird unten zugewiesen).
                if isDemoActive {
                    // Demo-Läufe (Autopilot) NICHT aufzeichnen/archivieren – sie sind flüchtig und sollen
                    // weder in der Bestenliste noch im Replay-Archiv landen. Einen evtl. noch liegenden
                    // Recorder eines zuvor ABGEBROCHENEN Menschenspiels (ESC → Startbildschirm, ohne
                    // Game Over) hier verwerfen, sonst schriebe die Demo in dessen Aufnahme.
                    recorder = nil
                    lastReplay = nil
                } else if replayPlayer == nil {
                    // Szenengröße mit aufnehmen: die Wiedergabe muss in derselben Größe laufen, sonst
                    // driftet der Lauf (size beeinflusst Spawns/Wrap/Bounds).
                    let replayStartLevel = selectedMode == .classicAsteroids ? 1 : selectedStartLevel
                    let replayAutoFire = selectedMode == .classicAsteroids ? false : autoFire
                    recorder = ReplayRecorder(seed: currentSeed, startLevel: replayStartLevel,
                                              gameMode: selectedMode, autoFire: replayAutoFire,
                                              width: Int(size.width), height: Int(size.height))
                    lastReplay = nil
                }

                // Spielzeit + alle zeitbasierten Timer auf den gemeinsamen Nullpunkt setzen, damit der
                // Lauf bei gameTime 0 beginnt (sonst würden Spawn-/Power-up-Timer aus der Menü-Phase
                // nachwirken und der Lauf wäre nicht reproduzierbar).
                gameTime = 0.0
                // Fixed-Timestep-Akkumulator leeren und das nächste `update(_:)` neu primen lassen,
                // damit aufgestaute Menü-Zeit den frischen Lauf nicht beeinflusst.
                timeAccumulator = 0.0
                lastUpdateTime = 0.0
                lastSpawnTime = 0.0
                lastUFOSpawnTime = 0.0
                lastGravityWellSpawnTime = 0.0
                // Negativ vorbelegen, damit der ERSTE Schuss bei gameTime 0 sofort den Cooldown
                // passiert (gameTime - lastLaserTime = 1.0 ≥ Cooldown). Mit 0.0 wäre der erste
                // Tastendruck fälschlich blockiert (0 - 0 < 0.15) – seit der Umstellung auf gameTime.
                lastLaserTime = -1.0

                gameMode = selectedMode
                currentLevel = gameMode == .classicAsteroids ? 1 : selectedStartLevel
                levelTimeRemaining = (currentLevel >= 10) ? 999999.0 : 60.0
                isLevelClearing = false
                playTime = 0.0
                isSpaceHeld = false
                invincibilityEndTime = 0.0
                tripleShotEndTime = 0.0
                rapidFireEndTime = 0.0
                beamEndTime = 0.0
                rearLaserEndTime = 0.0
                compressEndTime = 0.0
                compressLevel = 0
                extraLives = 0
                beamNode.isHidden = true
                updateLivesLabel()

                // Kopf-Boss pro Standard-Spiel neu auswürfeln/zurücksetzen. Der Classic-Pfad kennt
                // keine Bosse und hält seine RNG-Ziehungen in der eigenen Sitzung.
                if gameMode != .classicAsteroids {
                    bossFirstTargetLevel = Int.random(in: 5...7, using: &rng)
                }
                bossFirstDone = false
                bossLevel10Done = false
                nextBossTimeLevel10 = 0.0

                // Weltraumkatzen-Timer pro Spiel zurücksetzen.
                catTimerArmed = false
                nextCatTime = 0.0

                // Remove previous session objects
                clearGameEntities()

                // Reset ship
                ship.position = .zero
                ship.velocity = .zero
                ship.zRotation = 0.0
                ship.setScale(1.0)
                ship.isHidden = false
                ship.shieldLevel = 0
                if gameMode == .classicAsteroids {
                    ship.alpha = 1.0
                    ship.applyClassicProfile(true)
                } else if ship.usesClassicAppearance {
                    ship.applyClassicProfile(false)
                }

                activateHighScoreBoard(for: gameMode)
                SoundManager.shared.setClassicProfileActive(gameMode == .classicAsteroids)

                // Reset scoring
                score = 0
                scoreLabel.text = "SCORE: 00000"
                
                let currentHi = highScores.first?.score ?? 0
                hiScoreLabel.text = "HI-SCORE: \(String(format: "%05d", currentHi))"
                
                scoreLabel.isHidden = false
                hiScoreLabel.isHidden = false
                
                if gameMode == .classicAsteroids {
                    timerLabel.text = ""
                    levelLabel.text = "WAVE: 1"
                } else if currentLevel >= 10 {
                    timerLabel.text = "TIME: SURVIVAL"
                    levelLabel.text = "LEVEL: \(currentLevel)"
                } else {
                    timerLabel.text = "TIME: 01:00"
                    levelLabel.text = "LEVEL: \(currentLevel)"
                }
                timerLabel.isHidden = gameMode == .classicAsteroids
                levelLabel.isHidden = false
                
                if gameMode == .classicAsteroids {
                    initializeClassicSession()
                } else {
                    // Spawn initial asteroids
                    let initialCount = max(3, currentConfig().maxAsteroids / 2)
                    for _ in 0..<initialCount {
                        spawnAsteroid()
                    }
                }

                // Mad-Modus: Rotations-Scheduler beim nächsten Frame aufsetzen (dort liegt die
                // absolute Spielzeit vor) und das Sternenfeld über die Scheibe verteilen.
                fieldRotationPending = true
                scratchActive = false
                if gameMode == .madMeteoroids {
                    scatterStarsAcrossField()
                }
            }
            updateLivesLabel()
            // Während einer Replay-Wiedergabe das „▶ REPLAY"-Overlay einblenden.
            replayOverlayLabel.isHidden = !isReplaying
            // Während eines Demo-Laufs das Autopilot-Overlay einblenden.
            updateDemoOverlay()

        case .nameEntry:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            typedInitials = ""
            updateNameEntryInputLabel()
            
            nameEntryPromptLabel.isHidden = false
            nameEntryInputLabel.isHidden = false
            
        case .gameOver:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            gameOverLabel.isHidden = false
            finalScoreLabel.text = "YOUR SCORE: \(score)"
            finalScoreLabel.isHidden = false
            restartLabel.isHidden = false
            highScoresTitleLabel.isHidden = false
            updateHighScoreLabels()
            for label in highScoreLineLabels {
                label.isHidden = false
            }
            if isCompactLayout {
                // iOS-Breitformat: alle Game-Over-Labels kompakt stapeln, Tastatur-Hinweis aus
                // (die Touch-Buttons REPLAY/ZURÜCK unten übernehmen das).
                applyCompactGameOverLayout()
            } else {
                // Desktop: "PRESS R TO REPLAY"-Hinweis blinken lassen.
                restartLabel.removeAction(forKey: "blink")
                let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                let fadeIn = SKAction.fadeIn(withDuration: 0.5)
                let blink = SKAction.sequence([fadeOut, fadeIn])
                restartLabel.run(SKAction.repeatForever(blink), withKey: "blink")
            }
            
        case .quitConfirmation:
            quitPromptLabel.isHidden = false
            quitSubPromptLabel.isHidden = false
            
        case .glossary:
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            
            clearGameEntities()
            buildGlossary()
            // Auf iOS so eingescrollt starten, dass sofort Inhalt sichtbar ist, dessen Anfang (das
            // erste Item „PLAYER SHIP" bei lokal y≈150) aber noch nicht ganz oben klebt: wir schieben
            // den Container etwas nach unten, sodass das erste Item im oberen Drittel steht und die
            // folgenden Einträge den Rest füllen. Von dort scrollt es normal weiter nach oben.
            // macOS behält den bisherigen Startpunkt (unterer Rand, dann Auto-Scroll).
            glossaryContainer.position.y = isCompactLayout
                ? -size.height * 0.22
                : glossaryScrollBottom
            glossaryContainer.isHidden = false
            glossaryStaticContainer.isHidden = false

        case .highScores:
            // Eigene Highscore-Ansicht (iOS): Liste mittig, Zurück über das Touch-Overlay.
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0

            clearGameEntities()

            highScoresTitleLabel.isHidden = false
            updateHighScoreLabels()
            for label in highScoreLineLabels {
                label.isHidden = false
            }
            if isCompactLayout { applyCompactHighScoresLayout() }

        case .settings:
            // Einstellungen: Schiff/Spielfeld weg, die Umschalt-Zeilen zeigen.
            ship.isHidden = true
            ship.velocity = .zero
            ship.shieldLevel = 0
            clearGameEntities()
            updateSettingsLabels()
            settingsTitleLabel.isHidden = false
            settingsMusicLabel.isHidden = false
            settingsSfxLabel.isHidden = false
            settingsAutoFireLabel.isHidden = false
            settingsHDRGlowLabel.isHidden = false
            settingsFullScreenLabel.isHidden = !isFullScreenSettingAvailable
            // Auf iOS keinen Bedien-Hinweis zeigen (Tap-to-toggle/X-Back versteht sich von selbst und
            // überlappte den SFX-Button). macOS behält den Tastatur-/Vollbild-Hinweis.
            settingsHintLabel.isHidden = isCompactLayout
        }

        // iOS-Kompaktlayout für den neuen Zustand sofort anwenden (sonst 1 Frame Default-Layout).
        refreshCompactLayoutForCurrentState()

        // Headless-Render: HUD/Overlay durchgängig ausgeblendet halten (für ein sauberes Promo-GIF),
        // egal in welchen Zustand wir gerade gewechselt sind.
        if renderHUDHidden { hideRenderHUD() }
    }

    private func clearGameEntitiesKeepOptions() {
        for ast in activeAsteroids {
            ast.removeFromParent()
        }
        activeAsteroids.removeAll()
        
        for las in activeLasers {
            las.removeFromParent()
        }
        activeLasers.removeAll()
        
        for ufo in activeUFOs {
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()
        
        for well in activeGravityWells {
            well.removeFromParent()
        }
        activeGravityWells.removeAll()

        activeHead?.removeFromParent()
        activeHead = nil
        SoundManager.shared.stopAllHeadSounds()
        headWasSpawning = false

        for cat in activeCats { cat.removeFromParent() }
        activeCats.removeAll()
    }

    private func triggerImplosionCollapse(asteroid: Asteroid) {
        SoundManager.shared.playImplosion()
        
        let collapseWell = GravityWell(strength: GameplayTuning.implosionCollapseStrength,
                                       lifetime: GameplayTuning.implosionCollapseLifetime)
        collapseWell.position = asteroid.position
        self.addChild(collapseWell)
        self.activeGravityWells.append(collapseWell)
        
        createImplosionExplosion(at: asteroid.position)
        shakeCamera(amplitude: 6.0, numberOfShakes: 8, durationPerShake: 0.03)
        
        self.score += 250
        scoreLabel.text = "SCORE: \(String(format: "%05d", score))"
    }
    
    private func createImplosionExplosion(at pos: CGPoint) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        let count = 50
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = CGFloat(count) / 0.1
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.2
        emitter.particleSpeed = 160.0
        emitter.particleSpeedRange = 60.0
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi
        
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.2
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.3
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [
                SKColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0),
                SKColor(red: 0.6, green: 0.1, blue: 1.0, alpha: 1.0),
                SKColor.darkGray,
                SKColor.clear
            ],
            times: [0.0, 0.4, 0.8, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = pos
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.2)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    // MARK: - Kopf-Boss

    /// Löst den Kopf-Boss bei Bedarf aus und schreitet ihn voran. Auftreten: zufällig einmal in
    /// Level 5–7, erneut in Level 10, danach in Level 10 alle 4–7 Minuten (es gibt kein weiteres Level).
    private func updateFloatingHead(currentTime: TimeInterval, deltaTime: TimeInterval) {
        // Auslösen (immer nur ein Kopf gleichzeitig). Nicht spawnen, solange eine Weltraumkatze
        // im Bild ist – Boss und Miniboss sollen sich nie überlagern. Verworfene Auslöser gehen
        // nicht verloren: Die Bedingung greift im nächsten Frame erneut, sobald die Katze weg ist.
        if activeHead == nil && activeCats.isEmpty && isSpawningEnabled {
            var spawn = false
            if !bossFirstDone && currentLevel >= bossFirstTargetLevel && currentLevel <= 7 {
                spawn = true
                bossFirstDone = true
            } else if currentLevel >= 10 {
                if !bossLevel10Done {
                    spawn = true
                    bossLevel10Done = true
                    nextBossTimeLevel10 = currentTime + Double.random(in: 240.0...420.0, using: &rng)
                } else if currentTime >= nextBossTimeLevel10 {
                    spawn = true
                    nextBossTimeLevel10 = currentTime + Double.random(in: 240.0...420.0, using: &rng)
                }
            }
            if spawn {
                let head = FloatingHead(screenSize: size, using: &rng)
                self.addChild(head)
                self.activeHead = head
            }
        }

        // Voranschreiten + UFO-Armada ausspeien.
        guard let head = activeHead else {
            if headWasSpawning { SoundManager.shared.stopBossHead() }
            headWasSpawning = false
            SoundManager.shared.stopAllHeadSounds()
            return
        }
        // Spieler-Schüsse als Ausweich-Bedrohungen übergeben (nur eigene, nicht die der Gegner).
        let threats: [(position: CGPoint, velocity: CGPoint)] = activeLasers
            .filter { $0.type == .normal }
            .map { ($0.position, $0.velocity) }
        let emit = head.update(deltaTime: deltaTime, shipPosition: ship.position, laserThreats: threats)
        if emit > 0 {
            let mouth = head.mouthWorldPosition
            for _ in 0..<emit {
                spawnArmadaUFO(at: mouth)
            }
        }
        if head.isFinished {
            head.removeFromParent()
            activeHead = nil
        }

        // Boss-Stimme während Mund-auf/Spawn: im Sample-Modus das lange Mooo-Sample (einmal, mit Fade),
        // sonst die prozedurale Stimme (kontinuierlich, openness-gesteuert).
        let spawningNow = (activeHead?.phase == .spawning)
        if SoundManager.shared.useSampledSFX {
            if spawningNow && !headWasSpawning {
                SoundManager.shared.playBossHead()       // Start beim Mund-Öffnen
            } else if !spawningNow && headWasSpawning {
                SoundManager.shared.stopBossHead()        // Spawn vorbei -> Sample stoppen
            }
            SoundManager.shared.setHeadVoice(active: false, openness: 0)
        } else {
            if let head = activeHead, head.phase == .spawning {
                SoundManager.shared.setHeadVoice(active: true, openness: Double(head.mouthOpenness))
            } else {
                SoundManager.shared.setHeadVoice(active: false, openness: 0)
            }
        }
        headWasSpawning = spawningNow
    }

    /// Erzeugt ein einzelnes Armada-UFO am Mund-Mittelpunkt (Mix groß/klein) – umgeht bewusst das
    /// normale 2er-Limit für reguläre UFO-Spawns.
    private func spawnArmadaUFO(at position: CGPoint) {
        let isSmall = Double.random(in: 0...1, using: &rng) < 0.4
        let startOnLeft = Bool.random(using: &rng)
        let ufo = UFO(isSmall: isSmall, startOnLeft: startOnLeft, screenSize: size, using: &rng)
        ufo.position = position
        self.addChild(ufo)
        self.activeUFOs.append(ufo)
    }

    /// Löst Weltraumkatzen aus und schreitet ihre KI voran. Eine Katze taucht ab `catFirstLevel` und
    /// nur dann auf, wenn gerade kein Kopf-Boss im Bild ist (sie sollen sich nicht überlagern).
    private func updateSpaceCats(currentTime: TimeInterval, deltaTime: TimeInterval) {
        // Auslösen (zeitgesteuert, gedeckelt).
        if isSpawningEnabled && activeHead == nil && currentLevel >= catFirstLevel
            && activeCats.count < maxActiveCats {
            if !catTimerArmed {
                catTimerArmed = true
                nextCatTime = currentTime + Double.random(in: 12.0...25.0, using: &rng)   // erster Auftritt
            } else if currentTime >= nextCatTime {
                spawnSpaceCat()
                nextCatTime = currentTime + Double.random(in: 35.0...60.0, using: &rng)   // Abstand danach
            }
        }

        guard !activeCats.isEmpty else { return }

        // Deckungsobjekte (große/mittlere Asteroiden) und Spielerschüsse einmal aufbereiten.
        let cover: [(position: CGPoint, radius: CGFloat)] = activeAsteroids
            .filter { $0.sizeClass != .small }
            .map { ($0.position, $0.sizeClass.rawValue) }
        let threats: [(position: CGPoint, velocity: CGPoint)] = activeLasers
            .filter { $0.type == .normal }
            .map { ($0.position, $0.velocity) }

        var survivors: [SpaceCat] = []
        for cat in activeCats {
            // Nur auf ein sichtbares Schiff feuern; canFire hält sonst den Ziel-Countdown an,
            // damit kein Angriffsversuch während Spielertod/Respawn verfällt.
            let shot = cat.update(deltaTime: deltaTime, shipPosition: ship.position,
                                  shipVelocity: ship.isHidden ? .zero : ship.velocity,
                                  coverObjects: cover, laserThreats: threats,
                                  canFire: !ship.isHidden, using: &rng)
            if let shot = shot {
                fireCatTwinLaser(shot)
                SoundManager.shared.playUfoSound()
            }
            if cat.isFinished {
                cat.removeFromParent()
            } else {
                survivors.append(cat)
            }
        }
        activeCats = survivors
    }

    /// Baut aus einem Doppelschuss zwei parallele `.catEye`-Laser (halbe Spielerschuss-Geschwindigkeit,
    /// längere Lebensdauer, damit sie aus Schuss-Distanz auch ankommen).
    private func fireCatTwinLaser(_ shot: SpaceCat.TwinLaserShot) {
        // Mündungsblitz am Auge (Mittelpunkt der beiden Ursprünge): verankert sichtbar, dass die
        // Schüsse aus dem Auge kommen. Bei der kleinen, schnellen Katze ist das sonst kaum erkennbar
        // (der Ursprung liegt korrekt am Auge, wirkt aber leicht wie „aus dem Körper").
        if shot.origins.count == 2 {
            let eye = CGPoint(x: (shot.origins[0].x + shot.origins[1].x) / 2.0,
                              y: (shot.origins[0].y + shot.origins[1].y) / 2.0)
            showCatMuzzleFlash(at: eye)
        }
        for origin in shot.origins {
            // Lebensdauer großzügig (3.0 s ≈ 900 px Reichweite bei 300 px/s), damit die Schüsse
            // das Ziel auch aus größerer Distanz noch erreichen, bevor sie ablaufen.
            let laser = Laser(position: origin, angle: shot.angle, type: .catEye,
                              speed: SpaceCat.laserSpeed, lifetime: 3.0)
            self.addChild(laser)
            self.activeLasers.append(laser)
        }
    }

    /// Kurzer oranger Mündungsblitz (glühendes Katzenauge) am Schuss-Ursprung.
    private func showCatMuzzleFlash(at pos: CGPoint) {
        let flash = SKShapeNode(circleOfRadius: 5.0)
        flash.position = pos
        flash.fillColor = SKColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 0.9)
        flash.strokeColor = .clear
        flash.zPosition = 6
        VectorGlowRenderer.markFill(flash)
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 2.2, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent()
        ]))
    }

    private func spawnSpaceCat() {
        let startOnLeft = Bool.random(using: &rng)
        let cat = SpaceCat(screenSize: size, startOnLeft: startOnLeft, using: &rng)
        self.addChild(cat)
        self.activeCats.append(cat)
    }

    func clearGameEntities() {
        for ast in activeAsteroids {
            ast.removeFromParent()
        }
        activeAsteroids.removeAll()
        
        for las in activeLasers {
            las.removeFromParent()
        }
        activeLasers.removeAll()
        
        for ufo in activeUFOs {
            ufo.removeFromParent()
        }
        activeUFOs.removeAll()
        
        for well in activeGravityWells {
            well.removeFromParent()
        }
        activeGravityWells.removeAll()
        
        for p in activePowerUps {
            p.removeFromParent()
        }
        activePowerUps.removeAll()
        
        for drone in options {
            drone.removeFromParent()
        }
        options.removeAll()

        activeHead?.removeFromParent()
        activeHead = nil
        SoundManager.shared.stopAllHeadSounds()
        headWasSpawning = false

        for cat in activeCats { cat.removeFromParent() }
        activeCats.removeAll()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        scoreLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 40)
        hiScoreLabel.position = CGPoint(x: halfWidth - 20, y: halfHeight - 40)
        // iOS-Breitformat: kompaktes Menü-Layout nach Größenänderung neu setzen.
        refreshCompactLayoutForCurrentState()
    }
    
    // MARK: - High Score Storage
    
    /// Loads high scores from local storage. Made public for test framework reloading.
    /// Persistenz-Details (UserDefaults-Keys, Default-Liste) liegen im `HighScoreStore`.
    public func loadHighScores() {
        maxLevelReached = highScoreStore.loadMaxLevelReached()
        standardHighScores = highScoreStore.loadHighScores()
        classicHighScores = highScoreStore.loadClassicHighScores()
        activateHighScoreBoard(for: gameState == .playing ? gameMode : selectedMode)
    }

    private func saveHighScores() {
        if gameMode == .classicAsteroids {
            classicHighScores = highScores
            highScoreStore.saveClassic(classicHighScores)
        } else {
            standardHighScores = highScores
            highScoreStore.save(standardHighScores)
        }
    }

    /// Wählt die sichtbare Liste ohne die jeweils andere zu verändern.
    func activateHighScoreBoard(for mode: GameMode) {
        highScores = mode == .classicAsteroids ? classicHighScores : standardHighScores
    }

    /// Liefert eine bestimmte Bestenliste für CLI-Export und Tests, unabhängig von der UI-Auswahl.
    public func highScores(for mode: GameMode) -> [HighScore] {
        mode == .classicAsteroids ? classicHighScores : standardHighScores
    }

    /// Leert die Highscore-Liste und persistiert die leere Liste. Einstiegspunkt für das CLI-Flag
    /// `--reset-highscores`, wenn die gespeicherten Werte zu hoch geworden sind, um noch reinzukommen.
    public func clearHighScores() {
        standardHighScores = []
        classicHighScores = []
        highScores = []
        highScoreStore.save(standardHighScores)
        highScoreStore.saveClassic(classicHighScores)
    }

    // MARK: - Replay-Archiv (Aufnahmen als Dateien)

    /// Schreibt die Aufnahme als Datei ins `replaySaveDirectory` (falls gesetzt) und hält das Archiv
    /// auf `replayArchiveLimit` begrenzt. Wird bei Game Over für JEDEN Lauf aufgerufen (nicht nur bei
    /// Highscore), damit sich nach einem guten Spiel ein GIF aus dem letzten Lauf rendern lässt.
    /// Datei-I/O (Zeitstempel-Namen, Aufräumen der ältesten Dateien) liegt im `ReplayArchive`.
    private func archiveReplayIfEnabled(_ replay: Replay) {
        guard let dir = replaySaveDirectory else { return }
        ReplayArchive(directory: dir, limit: replayArchiveLimit)
            .archive(replay, score: score, level: currentLevel)
    }

    public func isNewHighScore(score: Int) -> Bool {
        if highScores.count < 5 { return true }
        return score > (highScores.last?.score ?? 0)
    }
    
    private func recordHighScore(initials: String, score: Int) {
        let progressName = gameMode == .classicAsteroids ? "Wave" : "Level"
        let message: String
        switch lastDeathCause {
        case .largeAsteroid:
            message = "Hull breach (large asteroid) on \(progressName) \(currentLevel)"
        case .mediumAsteroid:
            message = "Hull breach (medium asteroid) on \(progressName) \(currentLevel)"
        case .smallAsteroid:
            message = "Hull breach (small asteroid) on \(progressName) \(currentLevel)"
        case .wobblingAsteroid:
            message = "Blown to bits by wobbling bomb on \(progressName) \(currentLevel)"
        case .ufo:
            message = "Rammed by an alien UFO on \(progressName) \(currentLevel)"
        case .ufoLaser:
            message = "Vaporized by UFO laser on \(progressName) \(currentLevel)"
        case .gravityWell:
            message = "Crushed in a black hole on \(progressName) \(currentLevel)"
        case .bossHead:
            message = "Devoured by the floating idol on \(progressName) \(currentLevel)"
        case .spaceCat:
            message = "Pounced by a space cat on \(progressName) \(currentLevel)"
        case .spaceCatLaser:
            message = "Zapped by space cat eye-beams on \(progressName) \(currentLevel)"
        case .hyperspaceMalfunction:
            message = "Lost in hyperspace on Wave \(currentLevel)"
        }
        
        // Aufnahme dieses Laufs an den Eintrag hängen (falls vorhanden und kodierbar), damit der
        // Highscore-Lauf später exakt nachgespielt werden kann (Phase 2.5 / GIF in Phase 3).
        // Schlägt das Kodieren fehl, bleibt der Highscore erhalten (nur ohne Replay) — der Fehler
        // wird aber geloggt statt still verschluckt (früher `try?` ohne Meldung).
        var replayData: Data? = nil
        if let replay = lastReplay {
            do {
                replayData = try replay.encoded()
            } catch {
                print("Highscore: Replay-Kodierung fehlgeschlagen, Eintrag ohne Aufnahme gespeichert: \(error)")
            }
        }

        let newEntry = HighScore(initials: initials, score: score, date: Date(),
                                 deathMessage: message, replayData: replayData)
        highScores.append(newEntry)
        highScores.sort { $0.score > $1.score }
        if highScores.count > 5 {
            highScores = Array(highScores.prefix(5))
        }
        saveHighScores()
    }

    /// Dekodiert die an einen Highscore gehängte Aufnahme (falls vorhanden und kompatibel). Liefert
    /// `nil`, wenn kein Replay gespeichert ist oder es zu einer fremden Logik-Version gehört.
    public func replay(for highScore: HighScore) -> Replay? {
        guard let data = highScore.replayData, let replay = try? Replay(data: data),
              replay.isCompatible else { return nil }
        return replay
    }
    
    /// Verteilt die Sterne gleichmäßig über die kreisförmige Spielfeld-Scheibe. Nötig beim Start
    /// des Mad-Modus, damit das rotierende Sternenfeld keine leeren Ecken zeigt.
    private func scatterStarsAcrossField() {
        let r = madFieldRadius()
        // codereview-ok: Sternenfeld bewusst NICHT geseedet (separater Stream ohne Sim-Einfluss) — by design (2026-07-01)
        for star in stars {
            let angle = CGFloat.random(in: 0..<(2.0 * .pi))
            // sqrt für flächengleiche Verteilung in der Scheibe (sonst Häufung in der Mitte).
            let radius = r * sqrt(CGFloat.random(in: 0...1))
            star.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
    }

    // MARK: - Starfield Helpers

    private func setupStarfield() {
        let layers: [(count: Int, size: CGFloat, color: SKColor, parallax: CGFloat)] = [
            (count: 40, size: 1.0, color: SKColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0), parallax: 0.02),
            (count: 25, size: 2.0, color: SKColor(red: 0.4, green: 0.45, blue: 0.55, alpha: 1.0), parallax: 0.05),
            (count: 15, size: 3.0, color: SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0), parallax: 0.1)
        ]
        
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        for layer in layers {
            for _ in 0..<layer.count {
                let star = StarNode(color: layer.color, size: CGSize(width: layer.size, height: layer.size))
                star.parallaxFactor = layer.parallax
                let x = CGFloat.random(in: -halfWidth...halfWidth)
                let y = CGFloat.random(in: -halfHeight...halfHeight)
                star.position = CGPoint(x: x, y: y)
                star.zPosition = -10.0
                self.addChild(star)
                self.stars.append(star)
            }
        }
    }
    
    private func updateStars(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        let shipVel: CGPoint
        
        if gameState == .playing {
            shipVel = ship.velocity
        } else {
            // Gentle background drift on menu/death screens
            shipVel = CGPoint(x: 10.0, y: -5.0)
        }
        
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        
        let madFieldActive = fieldDeltaThisFrame != 0
        let fieldRadius = madFieldActive ? madFieldRadius() : 0

        for star in stars {
            star.position.x -= shipVel.x * star.parallaxFactor * dt
            star.position.y -= shipVel.y * star.parallaxFactor * dt

            if madFieldActive {
                // Mad-Modus: Stern um die Bildmitte mitdrehen und kreisförmig wrappen.
                star.position = rotatedAroundOrigin(star.position, by: fieldDeltaThisFrame)
                star.position = circularWrapped(star.position, radius: fieldRadius)
                continue
            }

            if star.position.x < -halfWidth {
                star.position.x += size.width
            } else if star.position.x > halfWidth {
                star.position.x -= size.width
            }

            if star.position.y < -halfHeight {
                star.position.y += size.height
            } else if star.position.y > halfHeight {
                star.position.y -= size.height
            }
        }
    }
    
    // MARK: - Visual Particle Explosions
    
    /// Spawns a procedural retro explosion burst using an emitter.
    private func createExplosion(at position: CGPoint, sizeClass: Asteroid.AsteroidSize) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        
        let particleCount: Int
        let speed: CGFloat
        switch sizeClass {
        case .large:
            particleCount = 40
            speed = 140.0
        case .medium:
            particleCount = 25
            speed = 190.0
        case .small:
            particleCount = 14
            speed = 240.0
        }
        
        emitter.numParticlesToEmit = particleCount
        emitter.particleBirthRate = CGFloat(particleCount) / 0.1
        emitter.particleLifetime = 0.65
        emitter.particleLifetimeRange = 0.25
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.45
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi // full circle
        
        emitter.particleScale = 1.0
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.5
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.6
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.white, SKColor.lightGray, SKColor.darkGray, SKColor.clear],
            times: [0.0, 0.35, 0.75, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = position
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.0)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    /// Spawns a large cyan procedural particle explosion on ship/UFO destruction.
    private func createShipExplosion(at position: CGPoint) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeExplosionParticleTexture()
        
        let particleCount = 60
        emitter.numParticlesToEmit = particleCount
        emitter.particleBirthRate = CGFloat(particleCount) / 0.1
        emitter.particleLifetime = 1.1
        emitter.particleLifetimeRange = 0.3
        emitter.particleSpeed = 210.0
        emitter.particleSpeedRange = 90.0
        emitter.emissionAngle = 0.0
        emitter.emissionAngleRange = 2.0 * .pi
        
        emitter.particleScale = 1.2
        emitter.particleScaleRange = 0.5
        emitter.particleScaleSpeed = -1.0
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -0.85
        
        let colorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.cyan, SKColor.blue, SKColor.darkGray, SKColor.clear],
            times: [0.0, 0.4, 0.8, 1.0] as [NSNumber]
        )
        emitter.particleColorSequence = colorSequence
        emitter.particleColorBlendFactor = 1.0
        
        emitter.position = position
        self.addChild(emitter)
        
        let wait = SKAction.wait(forDuration: 1.8)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    private func makeExplosionParticleTexture() -> SKTexture {
        let size = CGSize(width: 3.5, height: 3.5)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(SKColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let cgImage = context.makeImage()!
        return SKTexture(cgImage: cgImage)
    }
    
}

/// A node representing a background star.
private final class StarNode: SKSpriteNode {
    var parallaxFactor: CGFloat = 0.0
}
