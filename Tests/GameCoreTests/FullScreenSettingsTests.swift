import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class FullScreenSettingsTests: GameCoreTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FullScreenPreferenceStore.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FullScreenPreferenceStore.key)
        super.tearDown()
    }

    func testFullScreenDefaultsOffAndPersistsConfirmedNativeState() {
        let (scene, view) = makeScene()
        _ = view
        scene.configureFullScreenSetting(available: true)
        scene.transitionTo(.settings)

        XCTAssertFalse(scene.fullScreenEnabled)
        XCTAssertFalse(scene.settingsFullScreenLabel.isHidden)
        XCTAssertEqual(scene.settingsFullScreenLabel.text, "FULL SCREEN: OFF")
        XCTAssertNil(UserDefaults.standard.object(forKey: FullScreenPreferenceStore.key))

        scene.synchronizeFullScreenState(true)

        XCTAssertTrue(scene.fullScreenEnabled)
        XCTAssertEqual(scene.settingsFullScreenLabel.text, "FULL SCREEN: ON")
        XCTAssertEqual(UserDefaults.standard.object(forKey: FullScreenPreferenceStore.key) as? Bool, true)

        let reloadedScene = GameScene(size: CGSize(width: 800, height: 600))
        XCTAssertTrue(reloadedScene.fullScreenEnabled)

        reloadedScene.configureFullScreenSetting(available: true)
        reloadedScene.synchronizeFullScreenState(false)

        XCTAssertFalse(reloadedScene.fullScreenEnabled)
        XCTAssertEqual(UserDefaults.standard.object(forKey: FullScreenPreferenceStore.key) as? Bool, false)
        XCTAssertFalse(GameScene(size: CGSize(width: 800, height: 600)).fullScreenEnabled)
    }

    func testUnavailableHostKeepsFullScreenRowHiddenAndDoesNotPersist() {
        let (scene, view) = makeScene()
        _ = view
        scene.transitionTo(.settings)

        XCTAssertFalse(scene.isFullScreenSettingAvailable)
        XCTAssertTrue(scene.settingsFullScreenLabel.isHidden)
        XCTAssertNil(UserDefaults.standard.object(forKey: FullScreenPreferenceStore.key))

        scene.synchronizeFullScreenState(true)

        XCTAssertFalse(scene.fullScreenEnabled)
        XCTAssertTrue(scene.settingsFullScreenLabel.isHidden)
        XCTAssertNil(UserDefaults.standard.object(forKey: FullScreenPreferenceStore.key))
    }

    private func makeScene() -> (GameScene, SKView) {
        let size = CGSize(width: 800, height: 600)
        let scene = GameScene(size: size)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        return (scene, view)
    }
}
