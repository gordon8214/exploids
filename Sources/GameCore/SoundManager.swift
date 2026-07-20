import AVFoundation
import Foundation

/// A procedural retro synthesizer for generating game sound effects and engine hum.
/// Handles audio graph configuration, overlapping sound effects, and the continuous engine hum.
public final class SoundManager: @unchecked Sendable {
    
    /// The shared singleton instance.
    public static let shared = SoundManager()
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private var sfxNode: AVAudioSourceNode?
    private var engineNode: AVAudioSourceNode?
    
    private let sampleRate: Double = 44100.0
    
    // SFX Mixer State
    private let sfxLock = NSLock()
    private var activeSounds: [ActiveSound] = []

    // MARK: - Sample-basierte SFX (optionaler Modus, umschaltbar zur Laufzeit)

    /// Umschalter: false = prozedurale Synth-Effekte (Default, bisheriges Verhalten),
    /// true = abgespielte generierte Samples aus dem Bundle (SFX/). Pro Effekt können mehrere
    /// Varianten vorliegen – die werden reihum abgespielt, damit es weniger eintönig klingt.
    public var useSampledSFX: Bool = false

    private let sampleLock = NSLock()
    /// Vorgeladene Sample-Puffer je Effektname (z.B. "laser" -> [variante0, variante1]).
    private var sampleBuffers: [String: [AVAudioPCMBuffer]] = [:]
    /// Pool von Player-Knoten für überlappende Wiedergabe (Round-Robin).
    private var samplePlayers: [AVAudioPlayerNode] = []
    private var samplePlayerIndex = 0
    /// Eigener Knoten für die lange Kopf-Boss-Stimme (damit sie gezielt gestoppt werden kann).
    private var bossHeadPlayer: AVAudioPlayerNode?
    /// Zähler je Effekt für das reihum-Abspielen der Varianten.
    private var sampleVariantIndex: [String: Int] = [:]
    private var samplesLoaded = false
    
    // Engine Hum State
    private let engineLock = NSLock()
    private var isThrustActive: Bool = false
    private var isClassicProfileActive: Bool = false
    private var classicSaucerIsSmall: Bool?

    // Kopf-Boss-Stimme: ein tiefes, aufsteigendes „Moooo" (vokal-artig). Gesteuert über
    // setHeadVoice(active:openness:); `openness` (0=Lippen zu/gedämpft, 1=Mund offen/voller) wird
    // vom Mund-Öffnungsgrad gespeist. Diese drei Felder werden vom Main-Thread unter engineLock gesetzt.
    private var isHeadVoiceActive: Bool = false
    private var headVoiceOpenness: Double = 0.0
    private var headVoiceRestart: Bool = false

    // Engine Hum Synthesis State (only mutated on the audio render thread)
    private var enginePhase: Double = 0.0
    private var engineLfoPhase: Double = 0.0
    private var engineVolLfoPhase: Double = 0.0
    private var engineCurrentFrequency: Double = 50.0
    private var engineCurrentVolume: Double = 0.0
    private var classicNoiseState: UInt32 = 0x6D2B_79F5
    private var classicNoiseLP: Double = 0.0
    private var classicSaucerPhase: Double = 0.0
    private var classicSaucerLFOPhase: Double = 0.0
    private var classicSaucerVolume: Double = 0.0
    private var classicSaucerWasSmall = false

    // Head Voice Synthesis State (only mutated on the audio render thread)
    private var headVoicePhase: Double = 0.0       // Grundton-Phase
    private var headVoiceVolume: Double = 0.0      // gerampte Lautstärke (sanftes Ein-/Ausblenden)
    private var headVoiceTime: Double = 0.0        // Zeit seit Stimm-Start (für das Aufsteigen)
    private var headVoiceLP: Double = 0.0          // Tiefpass-Zustand (Vokal-Öffnung „m" -> „oo")
    private var headVoiceVibPhase: Double = 0.0    // Vibrato-Phase

    /// Mute state of the synthesizer. If true, audio engine setup/start is skipped and no sounds are generated.
    public var isMuted: Bool = CommandLine.arguments.contains("--no-sound") {
        didSet {
            if isMuted {
                stop()
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        #if os(iOS)
        // iOS meldet über diese Notification, dass sich die Audio-Konfiguration geändert hat
        // (z.B. wenn sich beim Kaltstart die Audio-Route/Session erst einpendelt oder Kopfhörer
        // ein-/ausgesteckt werden). Dabei STOPPT die AVAudioEngine sich selbst – ohne Neustart
        // bleibt der Ton sonst im kaputten/verzerrten Zustand. Wir starten daher neu und lassen
        // den MusicPlayer seinen Knoten neu einplanen (dessen Planung geht beim Stopp verloren).
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        #endif
        // Automatically set up and start the audio engine
        start()
    }

    #if os(iOS)
    /// Wird aufgerufen, nachdem die Engine neu gestartet wurde (Konfigurationswechsel) – damit der
    /// MusicPlayer seinen Musik-Knoten neu einplanen kann. Wird vom MusicPlayer gesetzt.
    public var onEngineReset: (@Sendable () -> Void)?

    /// Reagiert auf AVAudioEngineConfigurationChange: Engine neu starten und Abnehmer benachrichtigen.
    private func handleConfigurationChange() {
        guard !isMuted else { return }
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("SoundManager: Neustart nach ConfigurationChange fehlgeschlagen: \(error.localizedDescription)")
        }
        onEngineReset?()
    }
    #endif
    
    // MARK: - Public API
    
    /// Starts the audio engine if it is not already running.
    public func start() {
        guard !isMuted else { return }
        guard !audioEngine.isRunning else { return }

        #if os(iOS)
        // Ohne aktive AVAudioSession bleibt die AVAudioEngine auf iOS stumm.
        AudioSessionConfig.activate()
        #endif

        do {
            if sfxNode == nil || engineNode == nil {
                setupAudioGraph()
            }
            try audioEngine.start()
            print("SoundManager: AVAudioEngine started successfully.")
        } catch {
            print("SoundManager: Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    /// Stops the audio engine.
    public func stop() {
        audioEngine.stop()
        print("SoundManager: AVAudioEngine stopped.")
    }
    
    /// Plays a retro laser sound effect.
    public func playLaser() {
        playSound(.laser)
    }
    
    /// Plays a retro explosion sound effect.
    public func playExplosion() {
        playSound(.explosion)
    }
    
    /// Plays a glistening retro power-up collection sound.
    public func playPowerUp() {
        playSound(.powerUp)
    }
    
    /// Plays a deep screen-clearing bomb detonation sound.
    public func playBomb() {
        playSound(.bomb)
    }
    
    /// Plays a wavy UFO scanning sound.
    public func playUfoSound() {
        playSound(.ufo)
    }
    
    /// Plays a retro level completion fanfare.
    public func playLevelComplete() {
        playSound(.levelComplete)
    }
    
    /// Plays a deep black hole implosion suction sound.
    public func playImplosion() {
        playSound(.implosion)
    }

    /// Classic-Effekte umgehen den Sample-Schalter absichtlich: dieses Profil ist immer der neu
    /// erzeugte Synth und enthält keinerlei übernommene Samples.
    public func playClassicShot() { playSound(.classicShot, forceSynth: true) }
    public func playClassicExplosion() { playSound(.classicExplosion, forceSynth: true) }
    public func playClassicSaucerFire() { playSound(.classicSaucerFire, forceSynth: true) }
    public func playClassicHeartbeat(high: Bool) {
        playSound(high ? .classicHeartbeatHigh : .classicHeartbeatLow, forceSynth: true)
    }

    public func setClassicProfileActive(_ active: Bool) {
        engineLock.lock()
        isClassicProfileActive = active
        if !active { classicSaucerIsSmall = nil }
        engineLock.unlock()
    }

    /// `nil` stoppt den Dauerton, `false`/`true` wählen große/kleine Untertasse.
    public func setClassicSaucer(isSmall: Bool?) {
        engineLock.lock()
        classicSaucerIsSmall = isClassicProfileActive ? isSmall : nil
        engineLock.unlock()
    }
    
    /// Sets whether the thrust active state is true or false, ramping the engine hum.
    public func setThrustActive(_ active: Bool) {
        guard !isMuted else { return }
        if active && !audioEngine.isRunning {
            start()
        }
        
        engineLock.lock()
        isThrustActive = active
        engineLock.unlock()
    }
    
    /// Steuert die Kopf-Boss-Stimme (tiefes, aufsteigendes „Moooo").
    /// - active: ob die Stimme klingen soll (typisch: während der Kopf den Mund öffnet + UFOs ausspeit).
    /// - openness: 0 = Lippen geschlossen (gedämpftes „m"), 1 = Mund offen (volleres „oo").
    public func setHeadVoice(active: Bool, openness: Double) {
        guard !isMuted else { return }
        if active && !audioEngine.isRunning {
            start()
        }
        engineLock.lock()
        if active && !isHeadVoiceActive {
            headVoiceRestart = true   // beim (Wieder-)Einsetzen das Aufsteigen von vorn beginnen
        }
        isHeadVoiceActive = active
        headVoiceOpenness = max(0.0, min(1.0, openness))
        engineLock.unlock()
    }

    // MARK: - Private Setup
    
    private func setupAudioGraph() {
        if let sfx = sfxNode {
            audioEngine.detach(sfx)
        }
        if let engine = engineNode {
            audioEngine.detach(engine)
        }
        
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            print("SoundManager: Failed to create AVAudioFormat.")
            return
        }
        
        // SFX Source Node
        let sfxNode = AVAudioSourceNode { [weak self] (isSilence, timestamp, frameCount, outputData) -> OSStatus in
            guard let self = self else { return noErr }
            
            self.sfxLock.lock()
            defer { self.sfxLock.unlock() }
            
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            
            for buffer in abl {
                if let mData = buffer.mData {
                    memset(mData, 0, Int(buffer.mDataByteSize))
                }
            }
            
            if self.activeSounds.isEmpty {
                isSilence.pointee = true
                return noErr
            }
            
            isSilence.pointee = false
            let localSampleRate = self.sampleRate
            
            for frame in 0..<Int(frameCount) {
                var sum: Double = 0.0
                var i = 0
                while i < self.activeSounds.count {
                    let sound = self.activeSounds[i]
                    if let sample = sound.nextSample(sampleRate: localSampleRate) {
                        sum += sample
                        i += 1
                    } else {
                        self.activeSounds.remove(at: i)
                    }
                }
                
                let finalSample = Float(max(-1.0, min(1.0, sum)))
                for buffer in abl {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = finalSample
                    }
                }
            }
            
            return noErr
        }
        
        // Engine Hum Source Node
        let engineNode = AVAudioSourceNode { [weak self] (isSilence, timestamp, frameCount, outputData) -> OSStatus in
            guard let self = self else { return noErr }
            
            self.engineLock.lock()
            let thrustActive = self.isThrustActive
            let classicProfile = self.isClassicProfileActive
            let classicSaucer = self.classicSaucerIsSmall
            let headActive = self.isHeadVoiceActive
            let headOpen = self.headVoiceOpenness
            let headRestart = self.headVoiceRestart
            if headRestart { self.headVoiceRestart = false }
            self.engineLock.unlock()

            if headRestart {
                self.headVoiceTime = 0.0
                self.headVoicePhase = 0.0
            }

            let targetFreq: Double = thrustActive ? (classicProfile ? 92.0 : 120.0) : 50.0
            let targetVol: Double = thrustActive ? (classicProfile ? 0.28 : 0.35) : 0.0
            
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            let localSampleRate = self.sampleRate
            
            for buffer in abl {
                if let mData = buffer.mData {
                    memset(mData, 0, Int(buffer.mDataByteSize))
                }
            }
            
            if self.engineCurrentVolume < 0.001 && !thrustActive
                && !headActive && self.headVoiceVolume < 0.001
                && classicSaucer == nil && self.classicSaucerVolume < 0.001 {
                isSilence.pointee = true
                self.engineCurrentVolume = 0.0
                self.headVoiceVolume = 0.0
                return noErr
            }
            
            isSilence.pointee = false
            
            for frame in 0..<Int(frameCount) {
                // 1. Synthesize Engine Hum
                let freqRampFactor = thrustActive ? 0.0005 : 0.001
                self.engineCurrentFrequency += (targetFreq - self.engineCurrentFrequency) * freqRampFactor
                
                let volRampFactor = thrustActive ? 0.0002 : 0.001
                self.engineCurrentVolume += (targetVol - self.engineCurrentVolume) * volRampFactor
                
                let lfoFreq = 6.0
                let lfoDepth = 3.0
                self.engineLfoPhase += 2.0 * .pi * lfoFreq / localSampleRate
                if self.engineLfoPhase >= 2.0 * .pi {
                    self.engineLfoPhase -= 2.0 * .pi
                }
                let lfoValue = sin(self.engineLfoPhase)
                let modulatedFreq = self.engineCurrentFrequency + lfoValue * lfoDepth
                
                let volLfoFreq = 8.5
                let volLfoDepth = 0.05
                self.engineVolLfoPhase += 2.0 * .pi * volLfoFreq / localSampleRate
                if self.engineVolLfoPhase >= 2.0 * .pi {
                    self.engineVolLfoPhase -= 2.0 * .pi
                }
                let volLfoValue = 1.0 + sin(self.engineVolLfoPhase) * volLfoDepth
                let finalVolume = self.engineCurrentVolume * volLfoValue
                
                let fraction = self.enginePhase / (2.0 * .pi)
                let norm = fraction - floor(fraction)
                let triangle = 4.0 * abs(norm - 0.5) - 1.0
                let square = (self.enginePhase.truncatingRemainder(dividingBy: 2.0 * .pi) < .pi) ? 1.0 : -1.0
                let mixedWave = 0.7 * triangle + 0.3 * square
                var sampleValue: Double
                if classicProfile {
                    // Kleiner allocation-freier Xorshift-Generator nur für Audio-Rauschen.
                    var n = self.classicNoiseState
                    n ^= n << 13; n ^= n >> 17; n ^= n << 5
                    self.classicNoiseState = n
                    let noise = Double(Int32(bitPattern: n)) / Double(Int32.max)
                    self.classicNoiseLP += 0.18 * (noise - self.classicNoiseLP)
                    sampleValue = self.classicNoiseLP * finalVolume
                } else {
                    // codereview-ok: SoundManager-Jitter ausdrücklich vom Determinismus/Replay ausgenommen (Plan-Doku, AGENTS.md); Fix optional/niedrige Priorität (2026-07-01)
                    let noise = Double.random(in: -0.05...0.05)
                    sampleValue = (mixedWave + noise) * finalVolume
                }

                // Eigenständiger Dauerton für große/kleine Classic-Untertassen.
                let saucerTarget = classicSaucer == nil ? 0.0 : 0.16
                self.classicSaucerVolume += (saucerTarget - self.classicSaucerVolume) * 0.0015
                if let isSmall = classicSaucer { self.classicSaucerWasSmall = isSmall }
                if classicSaucer != nil || self.classicSaucerVolume > 0.0008 {
                    let isSmall = self.classicSaucerWasSmall
                    self.classicSaucerLFOPhase += 2.0 * .pi * (isSmall ? 7.0 : 4.0) / localSampleRate
                    if self.classicSaucerLFOPhase >= 2.0 * .pi {
                        self.classicSaucerLFOPhase -= 2.0 * .pi
                    }
                    let base = isSmall ? 510.0 : 230.0
                    let depth = isSmall ? 65.0 : 38.0
                    let frequency = base + sin(self.classicSaucerLFOPhase) * depth
                    let saucerSquare = self.classicSaucerPhase < .pi ? 1.0 : -1.0
                    sampleValue += saucerSquare * self.classicSaucerVolume
                    self.classicSaucerPhase += 2.0 * .pi * frequency / localSampleRate
                    if self.classicSaucerPhase >= 2.0 * .pi { self.classicSaucerPhase -= 2.0 * .pi }
                }

                // 2. Synthesize Head Voice (tiefes, aufsteigendes „Moooo")
                let headTarget = headActive ? 0.45 : 0.0
                // Schneller Einsatz, aber sanftes AUSFADEN am Ende (~0,4 s Release statt abruptem Stopp).
                let headRamp = headActive ? 0.0008 : 0.00006
                self.headVoiceVolume += (headTarget - self.headVoiceVolume) * headRamp
                if headActive || self.headVoiceVolume > 0.0008 {
                    self.headVoiceTime += 1.0 / localSampleRate
                    // Grundton steigt von ~70 Hz auf ~135 Hz über ~1.6 s und hält dann.
                    let rise = min(1.0, self.headVoiceTime / 1.6)
                    let baseFreq = 70.0 + 65.0 * rise
                    // leichtes Vibrato
                    self.headVoiceVibPhase += 2.0 * .pi * 5.2 / localSampleRate
                    if self.headVoiceVibPhase >= 2.0 * .pi { self.headVoiceVibPhase -= 2.0 * .pi }
                    let f0 = baseFreq * (1.0 + 0.02 * sin(self.headVoiceVibPhase))
                    // Sägezahn als oberwellenreiche Stimmband-Quelle.
                    let frac = self.headVoicePhase / (2.0 * .pi)
                    let saw = 2.0 * (frac - floor(frac + 0.5))
                    // Vokal-Öffnung: Tiefpass-Cutoff steigt mit `headOpen` (zu = dumpfes „m", offen = „oo").
                    let cutoff = 320.0 + 1100.0 * headOpen
                    let alpha = min(1.0, max(0.02, 2.0 * .pi * cutoff / localSampleRate))
                    self.headVoiceLP += alpha * (saw - self.headVoiceLP)
                    let openGain = 0.55 + 0.45 * headOpen
                    sampleValue += self.headVoiceLP * self.headVoiceVolume * openGain
                    self.headVoicePhase += 2.0 * .pi * f0 / localSampleRate
                    if self.headVoicePhase >= 2.0 * .pi { self.headVoicePhase -= 2.0 * .pi }
                }

                let finalSample = Float(max(-1.0, min(1.0, sampleValue)))
                for buffer in abl {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = finalSample
                    }
                }
                
                self.enginePhase += 2.0 * .pi * modulatedFreq / localSampleRate
                if self.enginePhase >= 2.0 * .pi {
                    self.enginePhase -= 2.0 * .pi
                }
            }
            
            return noErr
        }
        
        audioEngine.attach(sfxNode)
        audioEngine.attach(engineNode)
        
        let mixer = audioEngine.mainMixerNode
        audioEngine.connect(sfxNode, to: mixer, format: audioFormat)
        audioEngine.connect(engineNode, to: mixer, format: audioFormat)
        
        self.sfxNode = sfxNode
        self.engineNode = engineNode
        
        sfxLock.lock()
        activeSounds.reserveCapacity(32)
        sfxLock.unlock()
    }
    
    private func playSound(_ type: ActiveSound.SoundType, forceSynth: Bool = false) {
        guard !isMuted else { return }
        if !audioEngine.isRunning {
            start()
        }

        // Sample-Modus: erst versuchen, ein generiertes Sample abzuspielen. Klappt das nicht
        // (kein Sample vorhanden), fällt es unten auf den prozeduralen Synth zurück.
        if useSampledSFX && !forceSynth {
            loadSamplesIfNeeded()
            if playSampled(name(for: type)) { return }
        }

        sfxLock.lock()
        defer { self.sfxLock.unlock() }

        guard activeSounds.count < 16 else { return }
        activeSounds.append(ActiveSound(type: type, sampleRate: sampleRate))
    }

    // MARK: - Sample-basierte SFX: Laden & Abspielen

    /// Effektname (Dateipräfix im SFX-Bundle) zu einem Sound-Typ.
    private func name(for type: ActiveSound.SoundType) -> String {
        switch type {
        case .laser:         return "laser"
        case .explosion:     return "explosion"
        case .powerUp:       return "powerup"
        case .bomb:          return "bomb"
        case .ufo:           return "ufo"
        case .levelComplete: return "levelcomplete"
        case .implosion:     return "implosion"
        case .classicShot, .classicExplosion, .classicHeartbeatLow, .classicHeartbeatHigh,
             .classicSaucerFire:
            return ""
        }
    }

    /// Lädt einmalig alle Samples aus dem Bundle (SFX/<name>_<n>.m4a) und legt den Player-Pool an.
    /// Idempotent. Alle Puffer werden auf das kanonische Engine-Format (mono, sampleRate) konvertiert,
    /// damit sie problemlos auf demselben Mixer laufen.
    private func loadSamplesIfNeeded() {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        guard !samplesLoaded else { return }
        samplesLoaded = true

        // Stereo/sampleRate – passt zum Format der generierten .m4a-Dateien, daher ist beim Laden
        // keine Format-Konvertierung nötig (Puffer werden direkt verwendet).
        guard let canonical = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let names = ["laser", "explosion", "powerup", "bomb", "ufo", "levelcomplete", "implosion", "bosshead"]
        for n in names {
            var variants: [AVAudioPCMBuffer] = []
            var idx = 0
            while let url = Bundle.module.url(forResource: "\(n)_\(idx)", withExtension: "m4a", subdirectory: "SFX") {
                if let buf = SoundManager.loadBuffer(url: url, expected: canonical) {
                    variants.append(buf)
                }
                idx += 1
            }
            if !variants.isEmpty { sampleBuffers[n] = variants }
        }

        // Pool aus Player-Knoten für überlappende Wiedergabe (mehr als die meisten Spielszenen brauchen).
        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: canonical)
            samplePlayers.append(node)
        }

        // Eigener Knoten für die lange Kopf-Boss-Stimme.
        let bhNode = AVAudioPlayerNode()
        audioEngine.attach(bhNode)
        audioEngine.connect(bhNode, to: audioEngine.mainMixerNode, format: canonical)
        bossHeadPlayer = bhNode
    }

    /// Spielt die gesampelte Kopf-Boss-Stimme einmal ab (langes „Moooo" mit End-Fade). Nur sinnvoll
    /// im Sample-Modus; im prozeduralen Modus übernimmt stattdessen `setHeadVoice(...)`.
    public func playBossHead() {
        guard !isMuted else { return }
        if !audioEngine.isRunning { start() }
        loadSamplesIfNeeded()
        sampleLock.lock()
        let buf = sampleBuffers["bosshead"]?.first
        let node = bossHeadPlayer
        sampleLock.unlock()
        guard let buffer = buf, let player = node else { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    /// Stoppt die gesampelte Kopf-Boss-Stimme sofort (z.B. wenn der Boss zerstört wird).
    /// Der Lock schützt den Zugriff auf `bossHeadPlayer` konsistent mit `playBossHead()`.
    public func stopBossHead() {
        sampleLock.lock()
        let player = bossHeadPlayer
        sampleLock.unlock()
        player?.stop()
    }

    /// Stoppt beide Kopf-Stimm-Varianten (prozedural + Sample) – für sichere Übergänge.
    public func stopAllHeadSounds() {
        setHeadVoice(active: false, openness: 0)
        stopBossHead()
    }

    /// Spielt ein Sample des Effekts ab (reihum die nächste Variante, Round-Robin über den Player-Pool).
    /// Gibt false zurück, wenn kein Sample vorliegt -> Aufrufer nutzt dann den prozeduralen Synth.
    private func playSampled(_ effectName: String) -> Bool {
        sampleLock.lock()
        guard let variants = sampleBuffers[effectName], !variants.isEmpty, !samplePlayers.isEmpty else {
            sampleLock.unlock()
            return false
        }
        let vi = (sampleVariantIndex[effectName] ?? 0)
        sampleVariantIndex[effectName] = vi + 1
        let buffer = variants[vi % variants.count]
        let node = samplePlayers[samplePlayerIndex % samplePlayers.count]
        samplePlayerIndex += 1
        sampleLock.unlock()

        // .interrupts: belegt der Knoten gerade noch etwas, wird es ersetzt (bei 8 Knoten selten).
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
        return true
    }

    /// Lädt eine Audiodatei in einen Puffer. Erwartet das Zielformat (Stereo/sampleRate) – die
    /// generierten SFX liegen genau so vor, daher ist keine Konvertierung nötig. Weicht eine Datei
    /// doch ab, wird sie übersprungen (statt mit falschem Format auf dem Mixer zu landen).
    private static func loadBuffer(url: URL, expected format: AVAudioFormat) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.processingFormat == format else {
                print("SoundManager: Sample-Format unerwartet (\(url.lastPathComponent)) – übersprungen")
                return nil
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("SoundManager: Sample konnte nicht geladen werden (\(url.lastPathComponent)): \(error.localizedDescription)")
            return nil
        }
    }

    #if os(iOS)
    // MARK: - Musik über die gemeinsame Engine (nur iOS)
    //
    // Auf iOS darf die Musik NICHT über einen separaten AVAudioPlayer laufen, während diese
    // AVAudioEngine (SFX) aktiv ist: zwei unabhängige Audio-Render-Pfade auf dieselbe Hardware
    // erzeugen hörbare Verzerrungen (Musik wird unkenntlich). Deshalb hängt die Musik als
    // zusätzlicher Player-Knoten an genau dieser Engine – ein einziger Render-Pfad. Auf macOS
    // gibt es dieses Problem nicht; dort bleibt der MusicPlayer beim AVAudioPlayer.

    /// Erzeugt einen an den Mixer angeschlossenen Player-Knoten für die Musik und gibt ihn zurück.
    /// Stellt sicher, dass Engine + AudioSession laufen. Liefert nil, wenn stummgeschaltet oder die
    /// Engine nicht startet. Der Aufrufer (MusicPlayer) plant die Tracks selbst ein und ruft play().
    public func makeMusicNode(format: AVAudioFormat) -> AVAudioPlayerNode? {
        guard !isMuted else { return nil }
        start()  // Engine + AVAudioSession sicherstellen
        guard audioEngine.isRunning else { return nil }
        let node = AVAudioPlayerNode()
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        return node
    }
    #endif
}

// MARK: - ActiveSound Helper Class

/// Represents a single active playing sound effect.
final class ActiveSound: @unchecked Sendable {
    enum SoundType: Sendable {
        case laser
        case explosion
        case powerUp
        case bomb
        case ufo
        case levelComplete
        case implosion
        case classicShot
        case classicExplosion
        case classicHeartbeatLow
        case classicHeartbeatHigh
        case classicSaucerFire
    }
    
    let type: SoundType
    private(set) var currentFrame: Int = 0
    let totalFrames: Int
    private var phase: Double = 0.0
    private var lastSample: Double = 0.0
    private var noiseState: UInt32 = 0xA341_316C
    
    init(type: SoundType, sampleRate: Double) {
        self.type = type
        switch type {
        case .laser:
            self.totalFrames = Int(0.15 * sampleRate)
        case .explosion:
            self.totalFrames = Int(0.5 * sampleRate)
        case .powerUp:
            self.totalFrames = Int(0.42 * sampleRate)
        case .bomb:
            self.totalFrames = Int(1.1 * sampleRate)
        case .ufo:
            self.totalFrames = Int(0.28 * sampleRate)
        case .levelComplete:
            self.totalFrames = Int(0.75 * sampleRate)
        case .implosion:
            self.totalFrames = Int(0.95 * sampleRate)
        case .classicShot:
            self.totalFrames = Int(0.12 * sampleRate)
        case .classicExplosion:
            self.totalFrames = Int(0.55 * sampleRate)
        case .classicHeartbeatLow, .classicHeartbeatHigh:
            self.totalFrames = Int(0.11 * sampleRate)
        case .classicSaucerFire:
            self.totalFrames = Int(0.16 * sampleRate)
        }
    }
    
    /// Generates the next sample frame for the sound effect.
    func nextSample(sampleRate: Double) -> Double? {
        guard currentFrame < totalFrames else { return nil }
        
        let progress = Double(currentFrame) / Double(totalFrames)
        var sampleValue: Double = 0.0
        
        switch type {
        case .laser:
            let startFreq = 800.0
            let endFreq = 150.0
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let volume = 1.0 - progress
            
            let fraction = phase / (2.0 * .pi)
            let norm = fraction - floor(fraction)
            let triangle = 4.0 * abs(norm - 0.5) - 1.0
            
            sampleValue = triangle * volume * 0.25
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .explosion:
            let volume = (1.0 - progress) * (1.0 - progress)
            let startCutoff = 800.0
            let endCutoff = 80.0
            let cutoff = startCutoff + (endCutoff - startCutoff) * progress
            let alpha = min(1.0, max(0.0, 2.0 * .pi * cutoff / sampleRate))
            
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            // Der frühere Faktor 0,3 ging im Mix aus Theme-Musik und Laserschuss praktisch unter.
            // Der Filter und die Abklingkurve bleiben unverändert; nur der Ausgangspegel steigt.
            sampleValue = filtered * volume
            
        case .powerUp:
            let notes = [280.0, 420.0, 560.0, 840.0]
            let noteIndex = Int(progress * 4.0)
            let currentFreq = notes[min(3, noteIndex)]
            let volume = 1.0 - progress
            
            let fraction = phase / (2.0 * .pi)
            let square = (fraction - floor(fraction) < 0.5) ? 0.8 : -0.8
            
            sampleValue = square * volume * 0.15
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .bomb:
            let volume = (1.0 - progress) * (1.0 - progress)
            let startCutoff = 160.0
            let endCutoff = 15.0
            let cutoff = startCutoff + (endCutoff - startCutoff) * progress
            let alpha = min(1.0, max(0.0, 2.0 * .pi * cutoff / sampleRate))
            
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            sampleValue = filtered * volume * 0.6

        case .ufo:
            let baseFreq = 580.0
            let vibrato = sin(progress * 12.0 * 2.0 * .pi) * 120.0
            let currentFreq = baseFreq + vibrato
            let volume = 0.22 * (1.0 - progress)
            
            let fraction = phase / (2.0 * .pi)
            let square = (fraction - floor(fraction) < 0.5) ? 0.9 : -0.9
            
            sampleValue = square * volume * 0.15
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .levelComplete:
            // Ascending major arpeggio sequence followed by C major chord
            let notes = [261.6, 329.6, 392.0, 523.3, 659.3, 784.0]
            let count = Double(notes.count)
            let noteIdx = Int(progress * 1.5 * count)
            
            let currentFreq: Double
            if noteIdx < notes.count {
                currentFreq = notes[noteIdx]
            } else {
                let chordFreqs = [523.3, 659.3, 784.0]
                currentFreq = chordFreqs[currentFrame % 3]
            }
            
            let volume = 1.0 - progress
            let fraction = phase / (2.0 * .pi)
            let triangle = 4.0 * abs((fraction - floor(fraction)) - 0.5) - 1.0
            
            sampleValue = triangle * volume * 0.20
            
            phase += 2.0 * .pi * currentFreq / sampleRate
            if phase >= 2.0 * .pi {
                phase -= 2.0 * .pi
            }
            
        case .implosion:
            // Sweeping downward pitch low frequency singularity suction
            let startFreq = 260.0
            let endFreq = 18.0
            let currentFreq = startFreq + (endFreq - startFreq) * progress
            let volume = (1.0 - progress) * (1.0 - progress)
            
            let alpha = min(1.0, max(0.0, 2.0 * .pi * currentFreq / sampleRate))
            let noise = Double.random(in: -1.0...1.0)
            let filtered = lastSample + alpha * (noise - lastSample)
            lastSample = filtered
            
            // Suction swirl sweep effect
            let swirl = 1.0 + 0.35 * sin(progress * 22.0 * 2.0 * .pi)
            sampleValue = filtered * volume * swirl * 0.5

        case .classicShot:
            let frequency = 1_150.0 - 780.0 * progress
            let square = phase < .pi ? 1.0 : -1.0
            sampleValue = square * (1.0 - progress) * 0.20
            phase += 2.0 * .pi * frequency / sampleRate
            if phase >= 2.0 * .pi { phase -= 2.0 * .pi }

        case .classicExplosion:
            noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5
            let noise = Double(Int32(bitPattern: noiseState)) / Double(Int32.max)
            let cutoff = 0.22 - 0.18 * progress
            lastSample += cutoff * (noise - lastSample)
            sampleValue = lastSample * (1.0 - progress) * (1.0 - progress) * 0.42

        case .classicHeartbeatLow, .classicHeartbeatHigh:
            let frequency: Double
            switch type {
            case .classicHeartbeatHigh: frequency = 78.0
            default: frequency = 58.0
            }
            let square = phase < .pi ? 1.0 : -1.0
            let envelope = sin(progress * .pi)
            sampleValue = square * envelope * 0.24
            phase += 2.0 * .pi * frequency / sampleRate
            if phase >= 2.0 * .pi { phase -= 2.0 * .pi }

        case .classicSaucerFire:
            let frequency = 760.0 - 470.0 * progress
            let triangle = 4.0 * abs((phase / (2.0 * .pi) - floor(phase / (2.0 * .pi))) - 0.5) - 1.0
            sampleValue = triangle * (1.0 - progress) * 0.23
            phase += 2.0 * .pi * frequency / sampleRate
            if phase >= 2.0 * .pi { phase -= 2.0 * .pi }
        }
        
        currentFrame += 1
        return sampleValue
    }
}
