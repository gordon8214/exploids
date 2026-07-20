// GameScene+HUD.swift — UI-Aufbau (setupUIElements), Label-Updates und das kompakte
// iOS-Menü-/Spiel-Layout (applyCompact…/refreshCompactLayoutForCurrentState).
// Reiner Datei-Split aus GameScene.swift — kein Verhalten geändert.

import SpriteKit

extension GameScene {
    // MARK: - UI Configuration

    /// Hält das Desktop-HUD an den aktuellen Szenengrenzen. Dieselbe Berechnung wird beim ersten
    /// Aufbau und nach jedem Größenwechsel verwendet, damit beim Umschalten auf die feste
    /// Classic-Arena keine Labels an Koordinaten der vorherigen Host-Größe zurückbleiben.
    func applyStandardHUDLayout() {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        scoreLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 40)
        hiScoreLabel.position = CGPoint(x: halfWidth - 20, y: halfHeight - 40)
        timerLabel.position = CGPoint(x: 0, y: halfHeight - 40)
        levelLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 65)
        livesLabel.position = CGPoint(x: -halfWidth + 20, y: halfHeight - 90)
    }

    func setupUIElements() {
        // Power-Up Notification HUD Alert
        powerUpNotificationLabel.fontSize = 24
        powerUpNotificationLabel.horizontalAlignmentMode = .center
        powerUpNotificationLabel.verticalAlignmentMode = .center
        powerUpNotificationLabel.zPosition = 100
        powerUpNotificationLabel.isHidden = true
        self.addChild(powerUpNotificationLabel)
        
        // Title screen
        titleLabel.text = "EXPLOIDS"
        titleLabel.fontName = RetroFont.pixel
        titleLabel.fontSize = 46
        titleLabel.fontColor = .cyan
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: 250)
        titleLabel.zPosition = 100
        titleLabel.isHidden = true
        self.addChild(titleLabel)
        
        startPromptLabel.text = "PRESS SPACE TO START"
        startPromptLabel.fontSize = 20
        startPromptLabel.fontColor = .white
        startPromptLabel.position = CGPoint(x: 0, y: 170)
        startPromptLabel.zPosition = 100
        startPromptLabel.isHidden = true
        self.addChild(startPromptLabel)
        
        instructionsLabel.text = "W/▲: THRUST   A/D/◀/▶: ROTATE   SPACE: FIRE (HOLD = AUTO)   I: GLOSSARY   O: SETTINGS"
        instructionsLabel.fontSize = 14
        instructionsLabel.fontColor = .lightGray
        instructionsLabel.position = CGPoint(x: 0, y: -270)
        instructionsLabel.zPosition = 100
        instructionsLabel.isHidden = true
        self.addChild(instructionsLabel)
        
        // HUD
        scoreLabel.fontSize = 20
        scoreLabel.fontColor = .cyan
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.zPosition = 100
        scoreLabel.isHidden = true
        self.addChild(scoreLabel)
        
        hiScoreLabel.fontSize = 20
        hiScoreLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        hiScoreLabel.horizontalAlignmentMode = .right
        hiScoreLabel.zPosition = 100
        hiScoreLabel.isHidden = true
        self.addChild(hiScoreLabel)
        
        // Timer HUD
        timerLabel.fontSize = 20
        timerLabel.fontColor = .white
        timerLabel.horizontalAlignmentMode = .center
        timerLabel.zPosition = 100
        timerLabel.isHidden = true
        self.addChild(timerLabel)
        
        // Level HUD
        levelLabel.fontSize = 16
        levelLabel.fontColor = .cyan
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.zPosition = 100
        levelLabel.isHidden = true
        self.addChild(levelLabel)

        // Lives HUD (extra lives from the Extra-Life power-up)
        livesLabel.fontSize = 16
        livesLabel.fontColor = SKColor(red: 1.0, green: 0.3, blue: 0.45, alpha: 1.0)
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.zPosition = 100
        livesLabel.isHidden = true
        self.addChild(livesLabel)

        applyStandardHUDLayout()

        // Laserbeam-Visual (Polylinie, pro Frame neu aufgebaut; additives Leuchten)
        beamNode.strokeColor = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 0.95)
        beamNode.lineWidth = 7.0
        beamNode.lineCap = .round
        beamNode.blendMode = .add
        beamNode.zPosition = 50
        beamNode.isHidden = true
        VectorGlowRenderer.markStroke(beamNode)
        self.addChild(beamNode)

        // Level Selection (Start Screen)
        levelSelectionLabel.fontSize = 20
        levelSelectionLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        levelSelectionLabel.horizontalAlignmentMode = .center
        levelSelectionLabel.position = CGPoint(x: 0, y: 78)
        levelSelectionLabel.zPosition = 100
        levelSelectionLabel.isHidden = true
        self.addChild(levelSelectionLabel)

        // Mode Selection (Start Screen)
        modeSelectionLabel.fontSize = 20
        modeSelectionLabel.fontColor = SKColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1.0)
        modeSelectionLabel.horizontalAlignmentMode = .center
        modeSelectionLabel.position = CGPoint(x: 0, y: 120)
        modeSelectionLabel.zPosition = 100
        modeSelectionLabel.isHidden = true
        self.addChild(modeSelectionLabel)

        // Einstellungen-Ansicht
        settingsTitleLabel.text = "SETTINGS"
        settingsTitleLabel.fontName = RetroFont.pixel
        settingsTitleLabel.fontSize = 32
        settingsTitleLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        settingsTitleLabel.position = CGPoint(x: 0, y: 120)
        settingsTitleLabel.zPosition = 100
        settingsTitleLabel.isHidden = true
        self.addChild(settingsTitleLabel)

        let settingsRows: [(SKLabelNode, CGFloat)] = [
            (settingsMusicLabel, 70), (settingsSfxLabel, 25),
            (settingsAutoFireLabel, -20), (settingsHDRGlowLabel, -65),
            (settingsFullScreenLabel, -110)
        ]
        for (label, y) in settingsRows {
            label.fontSize = 22
            label.fontColor = .white
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: y)
            label.zPosition = 100
            label.isHidden = true
            self.addChild(label)
        }

        settingsHintLabel.fontSize = 16
        settingsHintLabel.fontColor = .lightGray
        settingsHintLabel.horizontalAlignmentMode = .center
        settingsHintLabel.position = CGPoint(x: 0, y: -165)
        settingsHintLabel.zPosition = 100
        settingsHintLabel.isHidden = true
        self.addChild(settingsHintLabel)
        updateSettingsLabels()

        // Level Cleared Overlay
        levelClearedLabel.fontSize = 40
        levelClearedLabel.fontColor = .green
        levelClearedLabel.horizontalAlignmentMode = .center
        levelClearedLabel.position = CGPoint(x: 0, y: 50)
        levelClearedLabel.zPosition = 100
        levelClearedLabel.isHidden = true
        self.addChild(levelClearedLabel)
        
        prepareNextLevelLabel.fontSize = 20
        prepareNextLevelLabel.fontColor = .white
        prepareNextLevelLabel.horizontalAlignmentMode = .center
        prepareNextLevelLabel.position = CGPoint(x: 0, y: 0)
        prepareNextLevelLabel.zPosition = 100
        prepareNextLevelLabel.isHidden = true
        self.addChild(prepareNextLevelLabel)
        
        // Name Entry
        nameEntryPromptLabel.text = "NEW HIGH SCORE!"
        nameEntryPromptLabel.fontSize = 36
        nameEntryPromptLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        nameEntryPromptLabel.position = CGPoint(x: 0, y: 100)
        nameEntryPromptLabel.zPosition = 100
        nameEntryPromptLabel.isHidden = true
        self.addChild(nameEntryPromptLabel)
        
        nameEntryInputLabel.fontSize = 24
        nameEntryInputLabel.fontColor = .white
        nameEntryInputLabel.position = CGPoint(x: 0, y: 30)
        nameEntryInputLabel.zPosition = 100
        nameEntryInputLabel.isHidden = true
        self.addChild(nameEntryInputLabel)
        
        // Game Over
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.fontName = RetroFont.pixel
        gameOverLabel.fontSize = 40
        gameOverLabel.fontColor = .red
        gameOverLabel.position = CGPoint(x: 0, y: 180)
        gameOverLabel.zPosition = 100
        gameOverLabel.isHidden = true
        self.addChild(gameOverLabel)
        
        finalScoreLabel.fontSize = 20
        finalScoreLabel.fontColor = .white
        finalScoreLabel.position = CGPoint(x: 0, y: 120)
        finalScoreLabel.zPosition = 100
        finalScoreLabel.isHidden = true
        self.addChild(finalScoreLabel)
        
        restartLabel.text = "PRESS R TO REPLAY   ESC FOR TITLE"
        restartLabel.fontSize = 20
        restartLabel.fontColor = .white
        restartLabel.position = CGPoint(x: 0, y: -180)
        restartLabel.zPosition = 100
        restartLabel.isHidden = true
        self.addChild(restartLabel)

        // „▶ REPLAY"-Overlay (Wiedergabe eines Highscore-Laufs). Oben am Bildrand, dezent.
        replayOverlayLabel.text = "▶ REPLAY  (ESC TO EXIT)"
        replayOverlayLabel.fontName = RetroFont.pixel
        replayOverlayLabel.fontSize = 16
        replayOverlayLabel.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        replayOverlayLabel.position = CGPoint(x: 0, y: 250)
        replayOverlayLabel.zPosition = 200
        replayOverlayLabel.isHidden = true
        self.addChild(replayOverlayLabel)
        
        // High scores
        highScoresTitleLabel.text = "HIGH SCORES"
        highScoresTitleLabel.fontSize = 24
        highScoresTitleLabel.fontColor = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
        highScoresTitleLabel.position = CGPoint(x: 0, y: 35)
        highScoresTitleLabel.zPosition = 100
        highScoresTitleLabel.isHidden = true
        self.addChild(highScoresTitleLabel)

        for i in 0..<5 {
            let label = SKLabelNode(fontNamed: "Courier")
            label.fontSize = 20
            label.fontColor = .white
            label.position = CGPoint(x: 0, y: CGFloat(-8 - i * 30))
            label.zPosition = 100
            label.isHidden = true
            self.addChild(label)
            highScoreLineLabels.append(label)
        }
        
        // Quit confirmation labels
        quitPromptLabel.text = "QUIT GAME?"
        quitPromptLabel.fontSize = 40
        quitPromptLabel.fontColor = .red
        quitPromptLabel.position = CGPoint(x: 0, y: 50)
        quitPromptLabel.zPosition = 100
        quitPromptLabel.isHidden = true
        self.addChild(quitPromptLabel)
        
        quitSubPromptLabel.text = "PRESS Y TO CONFIRM / ESC TO CANCEL"
        quitSubPromptLabel.fontSize = 20
        quitSubPromptLabel.fontColor = .white
        quitSubPromptLabel.position = CGPoint(x: 0, y: -10)
        quitSubPromptLabel.zPosition = 100
        quitSubPromptLabel.isHidden = true
        self.addChild(quitSubPromptLabel)
        
        // Glossary container
        glossaryContainer.isHidden = true
        self.addChild(glossaryContainer)
        
        glossaryStaticContainer.isHidden = true
        self.addChild(glossaryStaticContainer)
        
        // Deutlich sichtbare Einstiege in Glossar und Einstellungen auf dem macOS-Startbildschirm.
        glossaryPromptLabel.text = "PRESS I FOR GLOSSARY   O FOR SETTINGS"
        glossaryPromptLabel.fontSize = 18
        glossaryPromptLabel.fontColor = .cyan
        glossaryPromptLabel.position = CGPoint(x: 0, y: -340)
        glossaryPromptLabel.zPosition = 100
        glossaryPromptLabel.isHidden = true
        self.addChild(glossaryPromptLabel)

        // Demo-Hinweis auf dem Startbildschirm (nur bei aktivem Attract-Modus eingeblendet).
        demoPromptLabel.text = "PRESS D FOR DEMO"
        demoPromptLabel.fontName = RetroFont.pixel
        demoPromptLabel.fontSize = 16
        demoPromptLabel.fontColor = SKColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0)
        demoPromptLabel.position = CGPoint(x: 0, y: -370)
        demoPromptLabel.zPosition = 100
        demoPromptLabel.isHidden = true
        self.addChild(demoPromptLabel)

        // Overlay während eines Demo-Laufs (Autopilot spielt).
        demoOverlayLabel.fontName = RetroFont.pixel
        demoOverlayLabel.fontSize = 16
        demoOverlayLabel.fontColor = SKColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0)
        demoOverlayLabel.position = CGPoint(x: 0, y: 250)
        demoOverlayLabel.zPosition = 200
        demoOverlayLabel.isHidden = true
        self.addChild(demoOverlayLabel)
    }
    
    func updateHighScoreLabels() {
        highScoresTitleLabel.text = isClassicInterfaceActive ? "CLASSIC HIGH SCORES" : "HIGH SCORES"
        for (index, label) in highScoreLineLabels.enumerated() {
            if index < highScores.count {
                let entry = highScores[index]
                let initials = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
                let baseText = "\(index + 1). \(initials)   \(entry.score)"
                if let dm = entry.deathMessage {
                    label.text = "\(baseText) - \(dm)"
                } else {
                    label.text = baseText
                }
            } else {
                label.text = "\(index + 1). ---       0"
            }
        }
    }
    
    func updateNameEntryInputLabel() {
        var displayStr = "ENTER INITIALS: "
        for i in 0..<3 {
            if i < typedInitials.count {
                let idx = typedInitials.index(typedInitials.startIndex, offsetBy: i)
                displayStr += "\(typedInitials[idx]) "
            } else {
                displayStr += "_ "
            }
        }
        nameEntryInputLabel.text = displayStr.trimmingCharacters(in: .whitespaces)
    }

    /// iOS-Breitformat: positioniert die Startbildschirm-Labels passend zur aktuellen Bildhöhe
    /// und blendet die tastatur-zentrierten Hinweise aus (die Touch-Buttons übernehmen das).
    /// Idempotent – wird auch bei Größenänderung (didChangeSize) erneut aufgerufen.
    func applyCompactStartScreenLayout() {
        let topY = size.height / 2
        titleLabel.fontSize = 40
        titleLabel.position = CGPoint(x: 0, y: topY - 44)
        modeSelectionLabel.position = CGPoint(x: 0, y: 24)
        levelSelectionLabel.position = CGPoint(x: 0, y: -24)
        startPromptLabel.isHidden = true
        instructionsLabel.isHidden = true
        glossaryPromptLabel.isHidden = true
    }

    /// iOS-Breitformat: Highscore-Liste kompakt unter einem Titel oben anordnen (eigene
    /// `.highScores`-Ansicht). Setzt die Schriftgrößen explizit zurück, falls zuvor das
    /// kompaktere Game-Over-Layout (kleinere Titel-Schrift) aktiv war – dieselben Label-Objekte.
    func applyCompactHighScoresLayout() {
        let topY = size.height / 2
        highScoresTitleLabel.verticalAlignmentMode = .baseline
        highScoresTitleLabel.fontSize = 24
        highScoresTitleLabel.position = CGPoint(x: 0, y: topY - 50)
        let firstLineY = topY - 95
        for (i, label) in highScoreLineLabels.enumerated() {
            label.verticalAlignmentMode = .baseline
            label.fontSize = 16
            label.position = CGPoint(x: 0, y: firstLineY - CGFloat(i) * 28)
        }
    }

    /// iOS-Breitformat: kompakte Game-Over-Anordnung. Stapelt GAME OVER, Punktzahl, Highscore-Titel
    /// und -Liste platzsparend von oben nach unten – damit nichts überlappt (im Querformat ist
    /// wenig Höhe da). Blendet den Tastatur-Hinweis aus; die Touch-Buttons REPLAY/ZURÜCK am unteren
    /// Rand übernehmen diese Funktion. macOS nutzt unverändert das feste 4:3-Layout.
    func applyCompactGameOverLayout() {
        let topY = size.height / 2
        // Alle Labels mittig ausrichten (verticalAlignmentMode .center): Bei der Default-Baseline
        // wächst der Text über die Position hinaus nach oben – dadurch ragte „GAME OVER" oben raus.
        // Mit .center ist die y-Position der Mittelpunkt, das Stapeln wird vorhersagbar.
        gameOverLabel.verticalAlignmentMode = .center
        gameOverLabel.fontSize = 32
        gameOverLabel.position = CGPoint(x: 0, y: topY - 30)
        finalScoreLabel.verticalAlignmentMode = .center
        finalScoreLabel.fontSize = 16
        finalScoreLabel.position = CGPoint(x: 0, y: topY - 62)
        highScoresTitleLabel.verticalAlignmentMode = .center
        highScoresTitleLabel.fontSize = 18
        highScoresTitleLabel.position = CGPoint(x: 0, y: topY - 92)
        let firstLineY = topY - 120
        for (i, label) in highScoreLineLabels.enumerated() {
            label.verticalAlignmentMode = .center
            label.fontSize = 15
            label.position = CGPoint(x: 0, y: firstLineY - CGFloat(i) * 24)
        }
        // Tastatur-Hinweis ("PRESS R …") ausblenden – auf iOS gibt es nur die Touch-Buttons.
        restartLabel.isHidden = true
    }

    /// iOS-Breitformat: aktualisiert das kompakte Menü-Layout nach einer Größenänderung.
    /// Wird aus der bestehenden didChangeSize-Override aufgerufen. Auf macOS (isCompactLayout
    /// = false) ein No-op – das 4:3-Layout bleibt unverändert.
    func refreshCompactLayoutForCurrentState() {
        guard isCompactLayout else { return }
        switch gameState {
        case .startScreen: applyCompactStartScreenLayout()
        case .highScores: applyCompactHighScoresLayout()
        case .gameOver: applyCompactGameOverLayout()
        case .playing: applyCompactPlayingLayout()
        default: break
        }
    }

    /// iOS-Spiel-HUD (nur Kompaktlayout): platzsparend, damit möglichst viel Bildfläche fürs
    /// Spielfeld bleibt. Score klein oben links, Hi-Score im Spiel ausgeblendet, und Level/Zeit/Demo
    /// als eine mittig zentrierte Zeile knapp unter dem ESC-Knopf – gleiche Schriftgröße wie der
    /// Score, aber jeweils eigene Farbe (Level cyan, Zeit weiß, Demo grün). Nutzt die TATSÄCHLICHE
    /// Szenengröße (nach resizeFill ~874×402), nicht die fest verdrahteten Setup-Werte.
    func applyCompactPlayingLayout() {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        // Score ~30 % kleiner als der macOS-Default (20 → 14) und kompakt oben links.
        let hudFontSize: CGFloat = 14
        scoreLabel.fontSize = hudFontSize
        scoreLabel.position = CGPoint(x: -halfWidth + 16, y: halfHeight - 26)
        // Hi-Score im Spiel komplett weg (spart oben rechts Platz).
        hiScoreLabel.isHidden = true
        // Leben direkt unter den Score (kompakt oben links, gleiche Größe).
        livesLabel.fontSize = hudFontSize
        livesLabel.position = CGPoint(x: -halfWidth + 16, y: halfHeight - 26 - hudFontSize - 6)

        // Level / Zeit / Demo: eine Schriftgröße (= Score), drei Farben, als Gruppe horizontal
        // zentriert. Y liegt knapp unter dem ESC-Knopf (dieser belegt die obersten ~10 % der Höhe).
        levelLabel.fontSize = hudFontSize
        timerLabel.fontSize = hudFontSize
        // Demo-Zeile exakt wie Level rendern: GLEICHE Schrift und Größe – nur andere Farbe (grün).
        // Sonst fällt der abweichende Pixel-Font (Press Start 2P, aus dem macOS-Overlay) durch eine
        // größere/fettere Optik auf. Auf macOS bleibt das Overlay unberührt (Compact-Layout nur iOS).
        demoOverlayLabel.fontName = levelLabel.fontName
        demoOverlayLabel.fontSize = hudFontSize
        for label in [levelLabel, timerLabel, demoOverlayLabel] {
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
        }
        let rowY = halfHeight - size.height * 0.15   // etwas unter ESC
        let gap = size.width * 0.025                 // Abstand zwischen den drei Einträgen
        let showDemo = isDemoActive
        // Textbreiten messen (die Zeit ändert sich sekündlich → jede Frame neu zentrieren).
        let wLevel = levelLabel.frame.width
        let showTime = gameMode != .classicAsteroids
        let wTime  = showTime ? timerLabel.frame.width : 0
        let wDemo  = showDemo ? demoOverlayLabel.frame.width : 0
        let total  = wLevel + (showTime ? gap + wTime : 0) + (showDemo ? gap + wDemo : 0)
        var x = -total / 2
        levelLabel.position = CGPoint(x: x, y: rowY); x += wLevel
        if showTime {
            x += gap
            timerLabel.position = CGPoint(x: x, y: rowY)
            x += wTime
        }
        if showDemo { x += gap }
        if showDemo { demoOverlayLabel.position = CGPoint(x: x, y: rowY) }
    }
    
    func updateLevelSelectionLabel() {
        if selectedMode == .classicAsteroids {
            levelSelectionLabel.text = "STARTING WAVE: 1"
            if gameState == .startScreen { levelSelectionLabel.isHidden = true }
            return
        }
        let isCompleted = selectedStartLevel < maxLevelReached
        let starStr = isCompleted ? " ★" : ""
        // Auf Touch-Geräten übernehmen die Buttons die Auswahl -> Tastatur-Hinweis weglassen.
        let hint = isCompactLayout ? "" : "  (◀/▶ TO SELECT)"
        levelSelectionLabel.text = "STARTING LEVEL: \(selectedStartLevel)\(starStr)\(hint)"
        if gameState == .startScreen { levelSelectionLabel.isHidden = false }
    }

    func updateModeSelectionLabel() {
        let modeName: String
        switch selectedMode {
        case .ancientAsteroids: modeName = "ANCIENT ASTEROIDS"
        case .madMeteoroids: modeName = "MAD METEOROIDS"
        case .classicAsteroids: modeName = "CLASSIC ASTEROIDS"
        }
        let hint = isCompactLayout ? "" : "  (▲/▼ TO SELECT)"
        modeSelectionLabel.text = "MODE: \(modeName)\(hint)"
        if selectedMode == .classicAsteroids {
            instructionsLabel.text = "W/▲: THRUST   A/D/◀/▶: ROTATE   SPACE: FIRE   H: HYPERSPACE   I: GLOSSARY   O: SETTINGS"
        } else {
            instructionsLabel.text = "W/▲: THRUST   A/D/◀/▶: ROTATE   SPACE: FIRE (HOLD = AUTO)   I: GLOSSARY   O: SETTINGS"
        }
    }

    /// Aktualisiert die Umschalt-Zeilen der Einstellungen mit dem aktuellen Stand.
    func updateSettingsLabels() {
        settingsMusicLabel.text = "MUSIC: \(MusicPlayer.shared.isEnabled ? "ON" : "OFF")"
        settingsSfxLabel.text = isClassicInterfaceActive
            ? "SFX STYLE: CLASSIC SYNTH (FIXED)"
            : "SFX STYLE: \(SoundManager.shared.useSampledSFX ? "SAMPLE" : "PROCEDURAL")"
        settingsAutoFireLabel.text = isClassicInterfaceActive
            ? "AUTO-FIRE: DISABLED"
            : "AUTO-FIRE: \(autoFire ? "ON" : "OFF")"
        if isHDRGlowAvailable {
            settingsHDRGlowLabel.text = "HDR GLOW: \(hdrGlowEnabled ? "ON" : "OFF")"
        } else {
            settingsHDRGlowLabel.text = "HDR GLOW: UNAVAILABLE"
        }
        settingsFullScreenLabel.text = "FULL SCREEN: \(fullScreenEnabled ? "ON" : "OFF")"
        let macHint = "M: MUSIC   N: SFX   F: AUTO-FIRE   G: HDR GLOW   "
            + "⌃⌘F: FULL SCREEN   ESC: BACK"
        settingsHintLabel.text = isCompactLayout ? "TAP TO TOGGLE   X: BACK"
                                                 : macHint
    }

    /// Aktualisiert die Extra-Leben-Anzeige (nur sichtbar, wenn welche vorhanden).
    func updateLivesLabel() {
        if gameMode == .classicAsteroids && gameState == .playing {
            livesLabel.text = "SHIPS: \(classicSession.shipsRemaining)"
            livesLabel.isHidden = false
            return
        }
        if extraLives > 0 {
            livesLabel.text = "LIVES: \(extraLives)"
            livesLabel.isHidden = (gameState != .playing)
        } else {
            livesLabel.isHidden = true
        }
    }
}
