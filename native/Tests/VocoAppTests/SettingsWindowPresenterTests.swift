import AppKit
import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
    func testPresenterReusesExistingSettingsWindowWhenPresenterInstanceChanges() {
        Self.closeSettingsWindows()
        defer { Self.closeSettingsWindows() }

        let coordinator = AppCoordinator()
        let firstPresenter = SettingsWindowPresenter(windowFactory: Self.makeTestWindow)
        let secondPresenter = SettingsWindowPresenter(windowFactory: Self.makeTestWindow)

        firstPresenter.show(coordinator: coordinator)
        let firstWindow = firstPresenter.presentedWindowForTesting

        secondPresenter.show(coordinator: coordinator)
        let secondWindow = secondPresenter.presentedWindowForTesting

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow === secondWindow)

        firstWindow?.close()
    }

    func testPresenterDisablesNativeFullscreenTransitions() {
        Self.closeSettingsWindows()
        defer { Self.closeSettingsWindows() }

        let coordinator = AppCoordinator()
        let presenter = SettingsWindowPresenter(windowFactory: Self.makeTestWindow)

        presenter.show(coordinator: coordinator)
        let settingsWindow = presenter.presentedWindowForTesting

        XCTAssertEqual(settingsWindow?.collectionBehavior.contains(.fullScreenNone), true)
        XCTAssertEqual(settingsWindow?.collectionBehavior.contains(.fullScreenPrimary), false)

        settingsWindow?.close()
    }

    func testPresenterReappliesConfigurationWhenReusingExistingSettingsWindow() {
        Self.closeSettingsWindows()
        defer { Self.closeSettingsWindows() }

        let coordinator = AppCoordinator()
        let existingWindow = Self.makeTestWindow(coordinator)
        existingWindow.identifier = SettingsWindowPresenter.settingsWindowIdentifier
        existingWindow.collectionBehavior = []
        let presenter = SettingsWindowPresenter { _ in
            XCTFail("Expected presenter to reuse existing settings window")
            return Self.makeTestWindow(coordinator)
        }

        presenter.show(coordinator: coordinator)
        let settingsWindow = presenter.presentedWindowForTesting

        XCTAssertTrue(settingsWindow === existingWindow)
        XCTAssertEqual(existingWindow.collectionBehavior.contains(.fullScreenNone), true)

        existingWindow.close()
    }

    func testPresenterAppliesLocalizedWindowTitle() {
        Self.closeSettingsWindows()
        defer { Self.closeSettingsWindows() }

        let coordinator = AppCoordinator(appPreferenceStore: NoOpAppPreferenceStore())
        let presenter = SettingsWindowPresenter(windowFactory: Self.makeTestWindow)

        presenter.show(coordinator: coordinator)
        XCTAssertEqual(presenter.presentedWindowForTesting?.title, "Voco 设置")

        coordinator.setAppLanguage(.en)
        presenter.show(coordinator: coordinator)
        XCTAssertEqual(presenter.presentedWindowForTesting?.title, "Voco Settings")
    }

    private static func makeTestWindow(_: AppCoordinator) -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    private static func closeSettingsWindows() {
        for settingsWindow in NSApplication.shared.windows where settingsWindow.identifier == SettingsWindowPresenter.settingsWindowIdentifier {
            settingsWindow.identifier = nil
            settingsWindow.orderOut(nil)
            settingsWindow.close()
        }
    }
}
