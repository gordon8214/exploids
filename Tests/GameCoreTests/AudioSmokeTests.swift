// Smoke-Tests für die Audio-Schicht (SoundManager, MusicPlayer). Bewusst konservativ:
// sie starten NIE die echte AVAudioEngine (kein Audio-Hardware-Zugriff, CI-tauglich),
// sondern prüfen nur, dass die öffentliche API im gemuteten Zustand nicht abstürzt und
// die reinen Zustands-Schalter (Flags) korrekt sind. Deckt die zuvor komplett
// ungetestete SoundManager/MusicPlayer-Oberfläche mit Basis-Invarianten ab.

import XCTest
@testable import GameCore

@MainActor
final class AudioSmokeTests: GameCoreTestCase {

    // MARK: - SoundManager

    /// Alle SFX-Auslöser dürfen bei gemutetem Manager gefahrlos aufgerufen werden
    /// (guard !isMuted → früher return, kein Engine-Start). Basisklasse mutet in setUp.
    func testMutedSoundManagerPlayMethodsDoNotCrash() {
        let sm = SoundManager.shared
        XCTAssertTrue(sm.isMuted, "Basisklasse sollte den SoundManager im setUp muten.")

        sm.playLaser()
        sm.playExplosion()
        sm.playPowerUp()
        sm.playBomb()
        sm.playUfoSound()
        sm.playLevelComplete()
        sm.playImplosion()
        sm.playClassicShot()
        sm.playClassicExplosion()
        sm.playClassicExtraLife()
        sm.playClassicHeartbeat(high: false)
        sm.playClassicHeartbeat(high: true)
        sm.playClassicSaucerFire()
        sm.playBossHead()
        sm.stopBossHead()
        sm.stopAllHeadSounds()
        // Kommt bis hierher ohne Absturz/Engine-Start durch → bestanden.
    }

    /// Die prozedurale Explosion wird direkt und ohne Audio-Hardware gerendert. So bleiben Dauer,
    /// hörbarer Pegel und Abklingkurve des Treffer-Sounds abgesichert.
    func testGenericExplosionIsAudibleBoundedAndDecays() {
        let sampleRate = 1_000.0
        let sound = ActiveSound(type: .explosion, sampleRate: sampleRate)
        var samples: [Double] = []

        while let sample = sound.nextSample(sampleRate: sampleRate) {
            samples.append(sample)
        }

        XCTAssertEqual(samples.count, 500)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))

        let peak = samples.map(abs).max() ?? 0.0
        XCTAssertGreaterThan(peak, 0.25)
        XCTAssertLessThanOrEqual(peak, 1.0)

        let headEnergy = samples.prefix(50).reduce(0.0) { $0 + abs($1) }
        let tailEnergy = samples.suffix(50).reduce(0.0) { $0 + abs($1) }
        XCTAssertGreaterThan(headEnergy, tailEnergy * 4.0)
    }

    /// Rev. 4 legt beim Extra-Leben einen festen 3-kHz-Ton für vier Arcade-Bilder an und
    /// schaltet ihn für vier Bilder ab. 12 kHz teilt sowohl den Ton als auch den 62,5-Hz-Takt
    /// ganzzahlig, sodass Frequenz, Gate und die aus $B0 abgeleitete Dauer exakt prüfbar sind.
    func testClassicExtraLifeMatchesAtariToneAndGateCadence() {
        let sampleRate = 12_000.0
        let sound = ActiveSound(type: .classicExtraLife, sampleRate: sampleRate)
        var samples: [Double] = []

        while let sample = sound.nextSample(sampleRate: sampleRate) {
            samples.append(sample)
        }

        let samplesPerFourArcadeFrames = 768
        XCTAssertEqual(samples.count, 16_896, "88 Arcade-Bilder bei 62,5 Hz")
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertEqual(samples[0], 0.18, accuracy: 0.000_001)
        XCTAssertEqual(samples[2], -0.18, accuracy: 0.000_001,
                       "3 kHz müssen bei 12 kHz alle zwei Samples das Vorzeichen wechseln")
        XCTAssertTrue(samples[..<samplesPerFourArcadeFrames].allSatisfy { abs($0) == 0.18 })
        XCTAssertTrue(samples[samplesPerFourArcadeFrames..<(2 * samplesPerFourArcadeFrames)]
            .allSatisfy { $0 == 0.0 })
        XCTAssertTrue(samples[(2 * samplesPerFourArcadeFrames)..<(3 * samplesPerFourArcadeFrames)]
            .allSatisfy { abs($0) == 0.18 })
    }

    /// Die Dauer-Zustands-Schalter (Schub-Hum, Kopf-Stimme) dürfen im gemuteten Zustand in
    /// beliebiger Reihenfolge an/aus geschaltet werden, ohne die Engine zu starten.
    func testMutedSoundManagerStateSettersDoNotCrash() {
        let sm = SoundManager.shared
        sm.setThrustActive(true)
        sm.setThrustActive(false)
        sm.setHeadVoice(active: true, openness: 0.5)
        sm.setHeadVoice(active: false, openness: 0.0)
        sm.setClassicProfileActive(true)
        sm.setClassicSaucer(isSmall: false)
        sm.setClassicSaucer(isSmall: true)
        sm.setClassicSaucer(isSmall: nil)
        sm.setClassicProfileActive(false)
    }

    /// Der Sample-Modus ist ein reiner Laufzeit-Schalter und muss unabhängig vom Audio-Start
    /// zuverlässig gesetzt/gelesen werden können.
    func testSampledSFXFlagRoundTrips() {
        let sm = SoundManager.shared
        let original = sm.useSampledSFX
        sm.useSampledSFX = true
        XCTAssertTrue(sm.useSampledSFX)
        sm.useSampledSFX = false
        XCTAssertFalse(sm.useSampledSFX)
        sm.useSampledSFX = original
    }

    // MARK: - MusicPlayer

    /// Unter XCTest ist der MusicPlayer intern „suppressed" (spielt nichts), aber der
    /// `isEnabled`-Schalter muss die Logik trotzdem korrekt abbilden.
    func testMusicPlayerEnabledFlagRoundTrips() {
        let mp = MusicPlayer.shared
        let original = mp.isEnabled

        mp.setEnabled(false)
        XCTAssertFalse(mp.isEnabled)
        mp.setEnabled(true)
        XCTAssertTrue(mp.isEnabled)

        // toggle() invertiert den aktuellen Zustand.
        let before = mp.isEnabled
        mp.toggle()
        XCTAssertEqual(mp.isEnabled, !before)
        mp.toggle()
        XCTAssertEqual(mp.isEnabled, before)

        mp.setEnabled(original)
    }
}
