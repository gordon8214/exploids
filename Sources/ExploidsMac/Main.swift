import AppKit
import SpriteKit
import Foundation
import GameCore

/// The application delegate responsible for managing the application's lifecycle,
/// drawing the programmatic Dock icon, and setting up the native macOS menu bar.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: GameWindow?
    private var aboutWindow: NSWindow?

    /// App-Version – Single Source of Truth ist die gebaute Bundle-Version (CFBundleShortVersionString,
    /// von build-app.sh gesetzt). Fallback fürs nicht-gebündelte `swift run`.
    static func appVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.8.2"
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Create and display the game window
        let gameWindow = GameWindow()
        gameWindow.makeKeyAndOrderFront(nil)
        self.window = gameWindow
        
        // 1. Programmatically draw and assign a high-res retro Dock icon
        setProgrammaticDockIcon()
        
        // 2. Configure a native macOS menu bar with About Exploids and Full Screen commands
        setupMenuBar(for: gameWindow)
        
        // Bring the app to the foreground
        NSApp.activate(ignoringOtherApps: true)
        gameWindow.applicationActivationDidChange()
        gameWindow.restoreSavedFullScreenPreference()

        // Hintergrundmusik starten (läuft durchgehend über alle Screens; mit „M" umschaltbar).
        MusicPlayer.shared.start()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Terminate the app when the game window is closed
        return true
    }
    
    public func applicationDidBecomeActive(_ notification: Notification) {
        window?.applicationActivationDidChange()
    }

    public func applicationDidResignActive(_ notification: Notification) {
        window?.applicationActivationDidChange()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        window?.prepareForTermination()
        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        window?.prepareForTermination()
    }

    // MARK: - Programmatic Dock Icon Setup
    
    private func setProgrammaticDockIcon() {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size, flipped: false) { rect in
            // Black background canvas
            let bgPath = NSBezierPath(rect: rect)
            NSColor.black.set()
            bgPath.fill()
            
            // Draw subtle vector grid background lines
            NSColor(white: 0.16, alpha: 1.0).setStroke()
            let gridPath = NSBezierPath()
            gridPath.lineWidth = 2.0
            for i in 1...7 {
                let x = CGFloat(i) * (512.0 / 8.0)
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.line(to: CGPoint(x: x, y: 512))
                
                let y = CGFloat(i) * (512.0 / 8.0)
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.line(to: CGPoint(x: 512, y: y))
            }
            gridPath.stroke()
            
            let center = CGPoint(x: 256, y: 256)
            
            // Draw large glowing cyan ship triangle outline
            let shipPath = NSBezierPath()
            shipPath.move(to: CGPoint(x: center.x + 130, y: center.y))
            shipPath.line(to: CGPoint(x: center.x - 90, y: center.y + 80))
            shipPath.line(to: CGPoint(x: center.x - 60, y: center.y))
            shipPath.line(to: CGPoint(x: center.x - 90, y: center.y - 80))
            shipPath.close()
            shipPath.lineWidth = 14
            NSColor.cyan.setStroke()
            shipPath.stroke()
            
            // Draw ship thruster orange/red flame outline
            let flamePath = NSBezierPath()
            flamePath.move(to: CGPoint(x: center.x - 60, y: center.y))
            flamePath.line(to: CGPoint(x: center.x - 140, y: center.y + 35))
            flamePath.line(to: CGPoint(x: center.x - 200, y: center.y))
            flamePath.line(to: CGPoint(x: center.x - 140, y: center.y - 35))
            flamePath.close()
            flamePath.lineWidth = 8
            NSColor.orange.setStroke()
            flamePath.stroke()
            
            return true
        }
        NSApp.applicationIconImage = image
    }
    
    // MARK: - Native macOS Menu Bar Configuration
    
    private func setupMenuBar(for gameWindow: GameWindow) {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appSubmenu = NSMenu()
        appMenuItem.submenu = appSubmenu
        
        // About Item
        let aboutItem = NSMenuItem(title: "About Exploids", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appSubmenu.addItem(aboutItem)
        
        appSubmenu.addItem(NSMenuItem.separator())
        
        // Quit Item
        let quitItem = NSMenuItem(title: "Quit Exploids", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appSubmenu.addItem(quitItem)
        
        // View-Menü mit dem nativen macOS-Vollbildkommando. Der direkte Window-Target stellt
        // sicher, dass ⌃⌘F auch dann funktioniert, wenn die SpriteKit-View First Responder ist.
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)

        let viewSubmenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewSubmenu

        let fullScreenItem = NSMenuItem(
            title: "Toggle Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        fullScreenItem.target = gameWindow
        viewSubmenu.addItem(fullScreenItem)

        NSApp.mainMenu = mainMenu
    }
    
    // MARK: - About Screen Window
    
    @objc private func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Exploids"
        // WICHTIG: Wir halten das Fenster selbst stark (aboutWindow) und geben es im
        // windowWillClose frei. Ohne isReleasedWhenClosed=false würde AppKit es zusätzlich beim
        // Schließen freigeben -> Use-after-free (Crash in einer NSWindow-Animation, siehe
        // Crash-Report 2026-06-23: _NSWindowTransformAnimation dealloc / objc_release).
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)

        // Semi-translucent visual effect HUD backdrop
        let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 520, height: 460))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 460))

        // Retro C64 Courier Header (AppKit-Koordinaten: y=0 ist UNTEN)
        let titleLabel = NSTextField(labelWithString: "EXPLOIDS")
        titleLabel.font = NSFont(name: "Courier-Bold", size: 40)
        titleLabel.textColor = .cyan
        titleLabel.frame = NSRect(x: 20, y: 395, width: 480, height: 50)
        titleLabel.alignment = .center
        container.addSubview(titleLabel)

        let versionLabel = NSTextField(labelWithString: "Version \(AppDelegate.appVersion()) — retro vectors")
        versionLabel.font = NSFont(name: "Courier", size: 14)
        versionLabel.textColor = .orange
        versionLabel.frame = NSRect(x: 20, y: 366, width: 480, height: 20)
        versionLabel.alignment = .center
        container.addSubview(versionLabel)
        
        let descText = """
        Exploids is a high-resolution vector space shooter inspired by the Commodore 64 vector aesthetics and running at modern buttery-smooth frame rates.
        
        USED TECHNOLOGY & ARCHITECTURE:
        - Language: Swift 6 (strict concurrency compliance)
        - Windowing & OS integration: macOS native AppKit
        - Graphics engine: SpriteKit (100% asset-free vector outlines)
        - Audio engine: AVFoundation (real-time procedural DSP synthesis)
        
        FEATURES & IMPLEMENTATION DETAILS:
        - Real-time 3D polyhedron vertices rotated and projected on 2D
        - Procedural particles and multi-stage physics camera shakes
        - Dual follow Option drones, protective Shields, screen-clear Bombs
        - Inverse-squared-distance Gravity Singularities (Black Holes)
        - Alphanumeric high scores leaderboard persisted in UserDefaults
        """
        
        let descLabel = NSTextView(frame: NSRect(x: 30, y: 20, width: 460, height: 335))
        descLabel.string = descText
        descLabel.font = NSFont(name: "Courier", size: 12)
        descLabel.textColor = .white
        descLabel.drawsBackground = false
        descLabel.isEditable = false
        descLabel.isSelectable = false
        container.addSubview(descLabel)
        
        visualEffectView.addSubview(container)
        window.contentView = visualEffectView
        
        // Window close helper delegate
        class WindowDelegate: NSObject, NSWindowDelegate {
            weak var appDelegate: AppDelegate?
            init(appDelegate: AppDelegate) {
                self.appDelegate = appDelegate
            }
            func windowWillClose(_ notification: Notification) {
                appDelegate?.aboutWindow = nil
            }
        }
        
        let delegate = WindowDelegate(appDelegate: self)
        window.delegate = delegate
        objc_setAssociatedObject(window, "delegate_holder", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        window.makeKeyAndOrderFront(nil)
        self.aboutWindow = window
    }
}

/// The entry point of the game application.
///
/// `@MainActor`, weil `main()` und sämtliche CLI-Helfer AppKit/SpriteKit (SKScene/SKView, alle
/// MainActor-isoliert) ansteuern. Ohne die Annotation gelten die statischen Funktionen als
/// nonisolated und die Aufrufe sind unter Swift 6.1 Fehler (neuere Toolchains leiten es per Default
/// ab und verschleierten das). Der `@main`-Einstiegspunkt läuft ohnehin auf dem Main-Thread.
@main
@MainActor
struct Main {
    static func main() {
        let arguments = CommandLine.arguments
        
        // 1. Check for --version or -v
        if arguments.contains("--version") || arguments.contains("-v") {
            print("Exploids version \(AppDelegate.appVersion())")
            exit(0)
        }
        
        // 2. Check for --help
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Exploids - Native macOS Retro-HighRes Asteroids
            
            Usage:
            -  exploids [options]
            
            Options:
              --no-sound    Mute all game sounds and disable audio engine startup.
              --test-mode   Run a headless game simulation for 10 frames and print telemetry, then exit.
              --export-replay <i> --out <file> [--mode standard|classic]
                            Export the replay attached to high-score entry <i> (0-based). The board
                            defaults to standard; classic selects the separate Classic board.
              --render-replay <file> --out <gif> [--scale S] [--sim-scale S] [--fps N] [--stride N]
                                       [--from F] [--max-frames N] [--auto-fire] [--show-hud]
                            Headlessly render a replay file to an animated GIF (no window). The sim runs
                            at the recorded scene size by default (--sim-scale overrides Ancient/Mad;
                            Classic is always 1024x768); --scale sets the GIF output size. Default output
                            480x360, fps 30, stride auto (real-time), HUD hidden. --from picks a start frame.
              --render-last-replay --out <gif> [same options as --render-replay]
                            Render the newest archived replay (the last game played) to a GIF. Replays
                            are auto-saved to ~/Library/Application Support/Exploids/replays on game over.
              --render-video <file> --out <mp4> [--scale S] [--fps N] [--from F] [--hide-hud]
                            Render a whole replay to an h264 video (mp4). For long runs that would be huge
                            as a GIF — real-time, scrub it to pick a GIF segment. HUD shown by default.
              --reset-highscores
                            Clear both saved high-score lists. Run via the app binary with the game closed.
              --replay-verify <file> [--auto-fire]
                            Replay a file headlessly (no render) and print the final state — diagnostic.
              --version, -v Show application version.
              --help, -h    Show this help message.
            """)
            exit(0)
        }

        // 2. Check for --no-sound
        if arguments.contains("--no-sound") {
            SoundManager.shared.isMuted = true
        }

        // 2b. Headless: Replay eines Highscores in eine Datei exportieren.
        if let i = arguments.firstIndex(of: "--export-replay") {
            runExportReplay(arguments: arguments, flagIndex: i)
        }

        // 2c. Headless: Replay-Datei zu animiertem GIF rendern (cursorfrei, reproduzierbar).
        if let i = arguments.firstIndex(of: "--render-replay") {
            runRenderReplay(arguments: arguments, flagIndex: i)
        }

        // 2c1. Headless: die NEUESTE Archiv-Aufnahme (letztes gespieltes Spiel) zu GIF rendern.
        if arguments.contains("--render-last-replay") {
            runRenderLastReplay(arguments: arguments)
        }

        // 2c1a. Headless: ganzes Replay als h264-Video (mp4) – für lange Läufe (zum Durchscrubben).
        if let i = arguments.firstIndex(of: "--render-video") {
            runRenderVideo(arguments: arguments, flagIndex: i)
        }

        // 2c1b. Highscore-Liste leeren (über die App-Binary ausführen; Spiel vorher beenden).
        if arguments.contains("--reset-highscores") {
            runResetHighScores()
        }

        // 2c2. Diagnose: Replay über den getesteten scene.update()-Pfad fahren (ohne Rendering) und
        // melden, wie weit der Lauf kommt – zum Vergleich mit dem aufgezeichneten Highscore.
        if let i = arguments.firstIndex(of: "--replay-verify") {
            runReplayVerify(arguments: arguments, flagIndex: i)
        }

        // 2d. Headless: einen kurzen, skriptgesteuerten Demo-Lauf erzeugen und zu GIF rendern
        // (Selbsttest der Pipeline + schnelles Demo-GIF ohne gespeicherten Highscore).
        if arguments.contains("--render-demo") {
            runRenderDemo(arguments: arguments)
        }
        
        // 3. Check for --test-mode
        if arguments.contains("--test-mode") {
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            let scene = GameScene(size: CGSize(width: 1024, height: 768))
            view.presentScene(scene)
            
            print("Starting headless simulation...")
            scene.simulateKeyDown(keyCode: 13) // W key (Thrust)
            scene.simulateKeyDown(keyCode: 0)  // A key (Rotate CCW)
            
            let frameTime: TimeInterval = 1.0 / 60.0
            var currentTime: TimeInterval = 0.0
            
            scene.update(currentTime)
            
            for frame in 1...10 {
                currentTime += frameTime
                scene.update(currentTime)
                
                let pos = scene.ship.position
                let vel = scene.ship.velocity
                let rot = scene.ship.zRotation
                print("Frame \(frame): Pos=(\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y))), Vel=(\(String(format: "%.2f", vel.x)), \(String(format: "%.2f", vel.y))), Rot=\(String(format: "%.4f", rot)) rad")
            }
            exit(0)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // Setting activation policy to .regular allows menu focus and dock visibility
        app.setActivationPolicy(.regular)
        
        // Start the Cocoa run loop
        app.run()
    }

    // MARK: - Headless-CLI: Replay-Export & GIF-Render

    /// Liest den Wert eines `--flag value`-Arguments (oder nil).
    private static func argValue(_ arguments: [String], _ flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// `--export-replay <index> --out <file> [--mode standard|classic]`: schreibt die an den
    /// gewählten Bestenlisten-Eintrag gehängte Aufnahme als Datei. Standard bleibt der Default.
    private static func runExportReplay(arguments: [String], flagIndex: Int) {
        guard flagIndex + 1 < arguments.count, let index = Int(arguments[flagIndex + 1]) else {
            FileHandle.standardError.write(Data("Fehler: --export-replay braucht einen Index.\n".utf8)); exit(2)
        }
        guard let outPath = argValue(arguments, "--out") else {
            FileHandle.standardError.write(Data("Fehler: --out <file> fehlt.\n".utf8)); exit(2)
        }
        let modeValue = argValue(arguments, "--mode") ?? "standard"
        let boardMode: GameMode
        switch modeValue {
        case "standard": boardMode = .ancientAsteroids
        case "classic": boardMode = .classicAsteroids
        default:
            FileHandle.standardError.write(Data("Fehler: --mode erwartet standard oder classic.\n".utf8)); exit(2)
        }

        // Szene aufsetzen (lädt Highscores aus dem Store) und Replay des Eintrags holen.
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        view.presentScene(scene)
        let board = scene.highScores(for: boardMode)
        guard index >= 0, index < board.count else {
            FileHandle.standardError.write(Data("Fehler: Highscore-Index \(index) existiert nicht (0..\(board.count - 1)) auf dem \(modeValue)-Board.\n".utf8)); exit(3)
        }
        guard let replay = scene.replay(for: board[index]) else {
            FileHandle.standardError.write(Data("Fehler: Eintrag \(index) trägt keine (kompatible) Aufnahme.\n".utf8)); exit(3)
        }
        do {
            try replay.encoded().write(to: URL(fileURLWithPath: outPath))
            print("Replay (Seed \(replay.seed), \(replay.frameCount) Frames) exportiert nach \(outPath)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Fehler beim Schreiben: \(error)\n".utf8)); exit(4)
        }
    }

    /// `--replay-verify <file>`: spielt ein Replay über den festen Sim-Schritt (`advanceOneStep`) ab
    /// (ohne Rendering) und meldet Endzustand/Score/Level + den Frame, an dem die Wiedergabe endete.
    private static func runReplayVerify(arguments: [String], flagIndex: Int) {
        guard flagIndex + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Fehler: --replay-verify braucht eine Datei.\n".utf8)); exit(2)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[flagIndex + 1]))
            let replay = try Replay(data: data)
            if replay.gameMode == .classicAsteroids,
               arguments.contains("--width") || arguments.contains("--height") {
                FileHandle.standardError.write(Data(
                    "Fehler: Classic verwendet immer die feste Simulationsgröße 1024x768; --width/--height sind dafür nicht zulässig.\n".utf8
                ))
                exit(2)
            }
            // Ancient/Mad brauchen die Aufnahmegröße; Classic wird unabhängig vom Host immer in
            // der gemeinsamen Rev.-4-Arena verifiziert.
            let w = replay.gameMode == .classicAsteroids
                ? Int(GameScene.classicLogicalArenaSize.width)
                : (argValue(arguments, "--width").flatMap { Int($0) } ?? replay.width)
            let h = replay.gameMode == .classicAsteroids
                ? Int(GameScene.classicLogicalArenaSize.height)
                : (argValue(arguments, "--height").flatMap { Int($0) } ?? replay.height)
            let view = SKView(frame: CGRect(x: 0, y: 0, width: w, height: h))
            let scene = GameScene(size: CGSize(width: w, height: h))
            view.presentScene(scene)
            if arguments.contains("--auto-fire") { scene.replayAutoFireOverride = true }
            if arguments.contains("--no-auto-fire") { scene.replayAutoFireOverride = false }
            guard scene.startReplay(replay) else {
                FileHandle.standardError.write(Data("Fehler: Replay inkompatibel.\n".utf8)); exit(3)
            }
            print("Replay: seed=\(replay.seed) frames=\(replay.frameCount) startLevel=\(replay.startLevel) recSize=\(replay.width)x\(replay.height) simSize=\(w)x\(h)")
            var endedAtFrame = 0
            while scene.isReplaying {
                if !scene.advanceOneStep() { break }   // false = Aufnahme zu Ende (Wiedergabe beendet)
                endedAtFrame += 1
            }
            print("Endstand via advanceOneStep(): score=\(scene.score) level=\(scene.currentLevel) state=\(scene.gameState) endedAtFrame=\(endedAtFrame)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Fehler: \(error)\n".utf8)); exit(4)
        }
    }

    /// `--render-demo --out <gif>`: skriptet intern einen kurzen Lauf, nimmt ihn auf und rendert ihn
    /// zu einem GIF. Dient dem Pipeline-Selbsttest und als schnelles Demo-GIF ohne Highscore.
    private static func runRenderDemo(arguments: [String]) {
        let outPath = argValue(arguments, "--out") ?? "demo-replay.gif"
        let frames = Int(argValue(arguments, "--frames") ?? "600") ?? 600
        let startLevel = Int(argValue(arguments, "--level") ?? "3") ?? 3

        // Szene aufsetzen und einen festen, frame-indizierten Lauf aufzeichnen.
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 480, height: 360))
        let scene = GameScene(size: CGSize(width: 480, height: 360))
        view.presentScene(scene)
        if arguments.contains("--auto-fire") { scene.autoFire = true }
        // Höheres Start-Level → mehr Asteroiden/Gegner im Demo-GIF.
        scene.startNewGameForTesting(seed: 0xC0FFEE, startLevel: startLevel, mode: .ancientAsteroids)

        let still = arguments.contains("--still")  // stationär: nur drehen, kein Schub (überlebt mit Auto-Feuer)
        var fireDown = false
        for f in 0..<frames {
            if !still {
                let wantThrust = (f % 120) < 70
                if wantThrust { scene.simulateKeyDown(keyCode: 13) } else { scene.simulateKeyUp(keyCode: 13) }
            }
            if (f % 90) < 30 { scene.simulateKeyDown(keyCode: 0) } else { scene.simulateKeyUp(keyCode: 0) }
            if (f % 90) >= 45 && (f % 90) < 70 { scene.simulateKeyDown(keyCode: 2) } else { scene.simulateKeyUp(keyCode: 2) }
            if f % 6 == 0 { scene.simulateKeyDown(keyCode: 49); fireDown = true }
            else if fireDown { scene.simulateKeyUp(keyCode: 49); fireDown = false }
            scene.update(1000.0 + Double(f) / 60.0)
            if scene.gameState != .playing { break } // bei Game Over: Aufnahme endet hier
        }
        guard let replay = scene.currentReplayForTesting() ?? scene.lastReplay else {
            FileHandle.standardError.write(Data("Fehler: Demo-Aufnahme leer.\n".utf8)); exit(4)
        }

        // Optional die Demo-Aufnahme als Replay-Datei sichern (für Determinismus-Tests).
        if let savePath = argValue(arguments, "--save-replay") {
            try? replay.encoded().write(to: URL(fileURLWithPath: savePath))
            print("Demo-Replay gespeichert: \(savePath) (\(replay.frameCount) Frames, Endstate \(scene.gameState))")
        }

        do {
            var options = ReplayRenderer.Options()
            if let s = argValue(arguments, "--scale"), let scale = Double(s), scale > 0 {
                options.width = Int(scale); options.height = Int(scale * 3.0 / 4.0)
            }
            if arguments.contains("--show-hud") { options.hideHUD = false }
            try ReplayRenderer.renderToGIF(replay, outputURL: URL(fileURLWithPath: outPath), options: options)
            print("Demo-GIF gerendert: \(outPath) (\(replay.frameCount) Frames Aufnahme)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Fehler beim Rendern: \(error)\n".utf8)); exit(4)
        }
    }

    /// Verzeichnis fürs Replay-Archiv: `~/Library/Application Support/Exploids/replays`. Gemeinsam
    /// genutzt vom Spiel (Auto-Speichern bei Game Over, siehe GameWindow) und den Render-CLI-Flags.
    static func replayArchiveDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Exploids/replays", isDirectory: true)
    }

    /// `--reset-highscores`: leert beide gespeicherten Highscore-Listen und beendet. Danach landen die
    /// nächsten Läufe wieder in den Listen. Über die App-Binary ausführen (trifft die Bundle-Defaults-
    /// Domain) und nur bei beendetem Spiel (ein laufendes überschreibt die Liste beim nächsten Game Over).
    private static func runResetHighScores() {
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.clearHighScores()
        print("Standard- und Classic-Highscores gelöscht (leere Listen gespeichert).")
        exit(0)
    }

    /// `--render-last-replay --out <gif> [...]`: rendert die NEUESTE Aufnahme aus dem Replay-Archiv
    /// (das zuletzt gespielte Spiel) zu einem GIF – unabhängig davon, ob der Lauf ein Highscore war.
    private static func runRenderLastReplay(arguments: [String]) {
        let dir = replayArchiveDirectory()
        let newest = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "replay" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
        guard let url = newest else {
            FileHandle.standardError.write(Data("Fehler: keine Aufnahme im Archiv \(dir.path).\n".utf8)); exit(3)
        }
        print("Letzte Aufnahme: \(url.lastPathComponent)")
        renderReplayFile(inPath: url.path, arguments: arguments)
    }

    /// `--render-replay <file> --out <gif> [...]`: rendert eine Replay-Datei headless zu einem GIF.
    private static func runRenderReplay(arguments: [String], flagIndex: Int) {
        guard flagIndex + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Fehler: --render-replay braucht eine Datei.\n".utf8)); exit(2)
        }
        renderReplayFile(inPath: arguments[flagIndex + 1], arguments: arguments)
    }

    /// Gemeinsamer Render-Kern für `--render-replay` und `--render-last-replay`: liest die Datei,
    /// baut die Render-Optionen aus den Argumenten und schreibt das GIF. Beendet den Prozess.
    private static func renderReplayFile(inPath: String, arguments: [String]) {
        guard let outPath = argValue(arguments, "--out") else {
            FileHandle.standardError.write(Data("Fehler: --out <gif> fehlt.\n".utf8)); exit(2)
        }

        var options = ReplayRenderer.Options()
        if let s = argValue(arguments, "--scale"), let scale = Double(s), scale > 0 {
            // 4:3-Seitenverhältnis; --scale setzt die Ausgabe-Breite, Höhe folgt 3:4.
            options.width = Int(scale)
            options.height = Int(scale * 3.0 / 4.0)
        }
        // --sim-scale: optionale Simulationsgröße für Ancient/Mad. Classic lehnt den Override nach
        // dem Einlesen der Aufnahme ab, weil seine Arena unveränderlich 1024×768 ist.
        if let s = argValue(arguments, "--sim-scale"), let sim = Int(s), sim > 0 {
            options.simWidth = sim; options.simHeight = sim * 3 / 4
        }
        if let f = argValue(arguments, "--fps"), let fps = Int(f), fps > 0 { options.fps = fps }
        if let st = argValue(arguments, "--stride"), let stride = Int(st), stride > 0 { options.frameStride = stride }
        if let fr = argValue(arguments, "--from"), let from = Int(fr), from >= 0 { options.startFrame = from }
        if let mx = argValue(arguments, "--max-frames"), let mx2 = Int(mx), mx2 >= 0 { options.maxFrames = mx2 }
        if arguments.contains("--show-hud") { options.hideHUD = false }
        if arguments.contains("--auto-fire") { options.autoFireOverride = true }
        if arguments.contains("--no-auto-fire") { options.autoFireOverride = false }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: inPath))
            let replay = try Replay(data: data)
            guard replay.isCompatible else {
                FileHandle.standardError.write(Data("Fehler: Aufnahme gehört zu einer anderen Logik-Version (inkompatibel).\n".utf8)); exit(3)
            }
            if replay.gameMode == .classicAsteroids, arguments.contains("--sim-scale") {
                FileHandle.standardError.write(Data(
                    "Fehler: Classic verwendet immer die feste Simulationsgröße 1024x768; --sim-scale ist dafür nicht zulässig.\n".utf8
                ))
                exit(2)
            }
            try ReplayRenderer.renderToGIF(replay, outputURL: URL(fileURLWithPath: outPath), options: options)
            print("GIF gerendert: \(outPath)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Fehler beim Rendern: \(error)\n".utf8)); exit(4)
        }
    }

    /// `--render-video <file> --out <mp4> [--scale S] [--fps N] [--from F] [--max-frames N] [--hide-hud]`:
    /// rendert eine Replay-Datei headless als h264-Video. Für lange Läufe gedacht (ein 8-Min-Lauf wäre
    /// als GIF absurd groß): Echtzeit-Video zum Durchscrubben und Auswählen eines GIF-Ausschnitts.
    private static func runRenderVideo(arguments: [String], flagIndex: Int) {
        guard flagIndex + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Fehler: --render-video braucht eine Datei.\n".utf8)); exit(2)
        }
        guard let outPath = argValue(arguments, "--out") else {
            FileHandle.standardError.write(Data("Fehler: --out <mp4> fehlt.\n".utf8)); exit(2)
        }
        do {
            let replay = try Replay(data: try Data(contentsOf: URL(fileURLWithPath: arguments[flagIndex + 1])))
            guard replay.isCompatible else {
                FileHandle.standardError.write(Data("Fehler: Aufnahme inkompatibel (andere Logik-Version).\n".utf8)); exit(3)
            }
            if replay.gameMode == .classicAsteroids, arguments.contains("--sim-scale") {
                FileHandle.standardError.write(Data(
                    "Fehler: Classic verwendet immer die feste Simulationsgröße 1024x768; --sim-scale ist dafür nicht zulässig.\n".utf8
                ))
                exit(2)
            }
            var options = ReplayRenderer.Options()
            // Video-Defaults: ganzes Replay, Ausgabe = Aufnahme-Größe (1:1, scharf), 30 fps, HUD AN
            // (Score/Timer/Level helfen beim Wählen des Ausschnitts), kein Frame-Deckel.
            options.width = replay.width
            options.height = replay.height
            options.hideHUD = false
            options.maxFrames = 0
            options.fps = 30
            if let s = argValue(arguments, "--scale"), let scale = Double(s), scale > 0 {
                options.width = Int(scale); options.height = Int(scale * 3.0 / 4.0)
            }
            if let s = argValue(arguments, "--sim-scale"), let sim = Int(s), sim > 0 {
                options.simWidth = sim; options.simHeight = sim * 3 / 4
            }
            if let f = argValue(arguments, "--fps"), let fps = Int(f), fps > 0 { options.fps = fps }
            if let fr = argValue(arguments, "--from"), let from = Int(fr), from >= 0 { options.startFrame = from }
            if let mx = argValue(arguments, "--max-frames"), let mx2 = Int(mx), mx2 >= 0 { options.maxFrames = mx2 }
            if arguments.contains("--hide-hud") { options.hideHUD = true }
            if arguments.contains("--auto-fire") { options.autoFireOverride = true }
            if arguments.contains("--no-auto-fire") { options.autoFireOverride = false }
            try ReplayRenderer.renderToVideo(replay, outputURL: URL(fileURLWithPath: outPath), options: options)
            // codereview-ok: Double-Division kann nicht trappen (max. Infinity, kein Integer-Overflow); frameCount als Double bleibt exakt bis 2^53 — kein Error-Handling nötig (2026-07-01)
            let secs = Double(replay.frameCount) / Double(GameScene.simStepsPerSecond)
            print(String(format: "Video gerendert: %@ (%d Frames Aufnahme, ~%.0f s Echtzeit)", outPath, replay.frameCount, secs))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Fehler beim Rendern: \(error)\n".utf8)); exit(4)
        }
    }
}
