import XCTest
import AppKit
import SwiftUI
@testable import VocoApp

final class SettingsWorkbenchTypographyTests: XCTestCase {
    func testSettingsWorkbenchUsesPrototypeFontFamilies() {
        XCTAssertEqual(SettingsWorkbenchTypography.bodyFamilyName, "IBM Plex Sans")
        XCTAssertEqual(SettingsWorkbenchTypography.monoFamilyName, "IBM Plex Mono")
        XCTAssertEqual(
            SettingsWorkbenchFontRegistrar.requiredFontResourceFilenames,
            [
                "IBMPlexSans-Regular.ttf",
                "IBMPlexSans-Medium.ttf",
                "IBMPlexSans-SemiBold.ttf",
                "IBMPlexSans-Bold.ttf",
                "IBMPlexMono-Regular.ttf",
                "IBMPlexMono-Medium.ttf",
                "IBMPlexMono-SemiBold.ttf"
            ]
        )
    }

    func testSettingsWorkbenchFontResourcesAreBundledForSwiftPackageRuns() {
        let missingResources = SettingsWorkbenchFontRegistrar.requiredFontResourceURLs()
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)

        XCTAssertEqual(missingResources, [])
    }

    func testSettingsWorkbenchUsesBundledPostScriptFontNames() {
        XCTAssertEqual(SettingsWorkbenchTypography.bodyPostScriptName(for: .regular), "IBMPlexSans")
        XCTAssertEqual(SettingsWorkbenchTypography.bodyPostScriptName(for: .medium), "IBMPlexSans-Medm")
        XCTAssertEqual(SettingsWorkbenchTypography.bodyPostScriptName(for: .semibold), "IBMPlexSans-SmBld")
        XCTAssertEqual(SettingsWorkbenchTypography.bodyPostScriptName(for: .bold), "IBMPlexSans-Bold")
        XCTAssertEqual(SettingsWorkbenchTypography.bodyPostScriptName(for: .heavy), "IBMPlexSans-Bold")

        XCTAssertEqual(SettingsWorkbenchTypography.monoPostScriptName(for: .regular), "IBMPlexMono")
        XCTAssertEqual(SettingsWorkbenchTypography.monoPostScriptName(for: .medium), "IBMPlexMono-Medm")
        XCTAssertEqual(SettingsWorkbenchTypography.monoPostScriptName(for: .semibold), "IBMPlexMono-SmBld")
        XCTAssertEqual(SettingsWorkbenchTypography.monoPostScriptName(for: .bold), "IBMPlexMono-SmBld")
    }

    func testSettingsWorkbenchPostScriptFontNamesResolveAfterRegistration() {
        SettingsWorkbenchFontRegistrar.registerBundledFonts()

        let postScriptNames = [
            SettingsWorkbenchTypography.bodyPostScriptName(for: .regular),
            SettingsWorkbenchTypography.bodyPostScriptName(for: .medium),
            SettingsWorkbenchTypography.bodyPostScriptName(for: .semibold),
            SettingsWorkbenchTypography.bodyPostScriptName(for: .bold),
            SettingsWorkbenchTypography.monoPostScriptName(for: .regular),
            SettingsWorkbenchTypography.monoPostScriptName(for: .medium),
            SettingsWorkbenchTypography.monoPostScriptName(for: .semibold)
        ]

        let unresolvedNames = postScriptNames.filter { NSFont(name: $0, size: 12) == nil }

        XCTAssertEqual(unresolvedNames, [])
    }
}
