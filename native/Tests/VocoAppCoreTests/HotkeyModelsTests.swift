import XCTest
@testable import VocoAppCore

final class HotkeyModelsTests: XCTestCase {
    func testDefaultHotkeyBindingIsRightCommand() {
        let binding = HotkeyBinding.default

        XCTAssertEqual(binding.keyCode, 54)
        XCTAssertEqual(binding.modifierFlags, 0)
        XCTAssertEqual(binding.displayName, "Right Command")
    }

    func testHotkeyPresetsExposeSelectableBindings() {
        XCTAssertEqual(HotkeyPreset.allCases.map(\.title), ["Right Command", "Fn", "F19", "Caps Lock"])
        XCTAssertEqual(HotkeyPreset.fn.binding.keyCode, 63)
        XCTAssertEqual(HotkeyPreset.f19.binding.displayName, "F19")
        XCTAssertEqual(HotkeyPreset.capsLock.binding.keyCode, 57)
        XCTAssertEqual(HotkeyPreset.matching(.default), .rightCommand)
    }

    func testToggleMatcherEmitsToggleForModifierOnlyHotkey() {
        var matcher = HotkeyMatcher(binding: .default, mode: .toggle)

        XCTAssertEqual(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: HotkeyBinding.rightCommandFlag)),
            .toggleRecording
        )
        XCTAssertNil(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: HotkeyBinding.rightCommandFlag))
        )
        XCTAssertNil(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: 0))
        )
        XCTAssertEqual(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: HotkeyBinding.rightCommandFlag)),
            .toggleRecording
        )
    }

    func testPressAndHoldMatcherEmitsStartAndStop() {
        var matcher = HotkeyMatcher(binding: .default, mode: .pressAndHold)

        XCTAssertEqual(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: HotkeyBinding.rightCommandFlag)),
            .startRecording
        )
        XCTAssertNil(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: HotkeyBinding.rightCommandFlag))
        )
        XCTAssertEqual(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 54, modifierFlags: 0)),
            .stopRecording
        )
    }

    func testNonMatchingHotkeyDoesNotEmitAction() {
        var matcher = HotkeyMatcher(binding: .default, mode: .toggle)

        XCTAssertNil(
            matcher.handle(HotkeyInputEvent(kind: .keyDown, keyCode: 12, modifierFlags: HotkeyBinding.rightCommandFlag))
        )
        XCTAssertNil(
            matcher.handle(HotkeyInputEvent(kind: .flagsChanged, keyCode: 55, modifierFlags: HotkeyBinding.rightCommandFlag))
        )
    }

    func testHotkeyRuntimeStateExposesUserVisibleMetadata() {
        XCTAssertEqual(HotkeyRuntimeState.inactive.title, "未监听")
        XCTAssertEqual(HotkeyRuntimeState.listening.title, "监听中")
        XCTAssertEqual(HotkeyRuntimeState.permissionNeeded.title, "需要权限")
        XCTAssertEqual(HotkeyRuntimeState.failed("boom").title, "出错")
        XCTAssertTrue(HotkeyRuntimeState.listening.canReceiveEvents)
        XCTAssertFalse(HotkeyRuntimeState.failed("boom").canReceiveEvents)
    }
}
