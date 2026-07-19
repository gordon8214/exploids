import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class HDRGlowSettingsTests: GameCoreTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: HDRGlowPreferenceStore.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: HDRGlowPreferenceStore.key)
        super.tearDown()
    }

    func testHDRGlowDefaultsOnAndPersistsChangedPreference() {
        let (scene, view) = makeScene()
        _ = view
        scene.updateHDRDisplay(available: true, currentHeadroom: 2.0)
        scene.transitionTo(.settings)

        XCTAssertTrue(scene.hdrGlowEnabled)
        XCTAssertEqual(scene.settingsHDRGlowLabel.text, "HDR GLOW: ON")

        var callbackValues: [Bool] = []
        scene.onHDRGlowPreferenceChanged = { callbackValues.append($0) }
        scene.simulateTypeCharacter("g")

        XCTAssertFalse(scene.hdrGlowEnabled)
        XCTAssertEqual(callbackValues, [false])
        XCTAssertEqual(scene.settingsHDRGlowLabel.text, "HDR GLOW: OFF")
        XCTAssertEqual(UserDefaults.standard.object(forKey: HDRGlowPreferenceStore.key) as? Bool, false)

        let reloadedScene = GameScene(size: CGSize(width: 800, height: 600))
        XCTAssertFalse(reloadedScene.hdrGlowEnabled)
    }

    func testUnavailableDisplayShowsUnavailableAndDoesNotChangePreference() {
        let (scene, view) = makeScene()
        _ = view
        scene.updateHDRDisplay(available: false, currentHeadroom: 1.0)
        scene.transitionTo(.settings)

        var callbackCount = 0
        scene.onHDRGlowPreferenceChanged = { _ in callbackCount += 1 }
        scene.simulateTypeCharacter("g")

        XCTAssertTrue(scene.hdrGlowEnabled)
        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(scene.settingsHDRGlowLabel.text, "HDR GLOW: UNAVAILABLE")
        XCTAssertNil(UserDefaults.standard.object(forKey: HDRGlowPreferenceStore.key))
    }

    func testNameEntryTreatsGAsTextInsteadOfTogglingGlow() {
        let (scene, view) = makeScene()
        _ = view
        scene.updateHDRDisplay(available: true, currentHeadroom: 2.0)
        scene.transitionTo(.nameEntry)

        var callbackCount = 0
        scene.onHDRGlowPreferenceChanged = { _ in callbackCount += 1 }
        scene.simulateTypeCharacter("g")

        XCTAssertTrue(scene.hdrGlowEnabled)
        XCTAssertEqual(callbackCount, 0)
    }

    private func makeScene() -> (GameScene, SKView) {
        let size = CGSize(width: 800, height: 600)
        let scene = GameScene(size: size)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        return (scene, view)
    }
}
