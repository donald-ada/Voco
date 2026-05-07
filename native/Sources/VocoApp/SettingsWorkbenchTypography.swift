import CoreText
import Foundation
import SwiftUI

enum SettingsWorkbenchTypography {
    static let bodyFamilyName = "IBM Plex Sans"
    static let monoFamilyName = "IBM Plex Mono"

    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(bodyPostScriptName(for: weight), size: size)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(monoPostScriptName(for: weight), size: size)
    }

    static func bodyPostScriptName(for weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "IBMPlexSans-Bold"
        }
        if weight == .semibold {
            return "IBMPlexSans-SmBld"
        }
        if weight == .medium {
            return "IBMPlexSans-Medm"
        }
        return "IBMPlexSans"
    }

    static func monoPostScriptName(for weight: Font.Weight) -> String {
        if weight == .semibold || weight == .bold || weight == .heavy || weight == .black {
            return "IBMPlexMono-SmBld"
        }
        if weight == .medium {
            return "IBMPlexMono-Medm"
        }
        return "IBMPlexMono"
    }
}

enum SettingsWorkbenchFontRegistrar {
    static let requiredFontResourceFilenames = [
        "IBMPlexSans-Regular.ttf",
        "IBMPlexSans-Medium.ttf",
        "IBMPlexSans-SemiBold.ttf",
        "IBMPlexSans-Bold.ttf",
        "IBMPlexMono-Regular.ttf",
        "IBMPlexMono-Medium.ttf",
        "IBMPlexMono-SemiBold.ttf"
    ]

    static func registerBundledFonts(bundle: Bundle? = nil) {
        let missing = missingRequiredFontResourceFilenames(bundle: bundle)
        if !missing.isEmpty {
            NSLog("Voco settings fonts missing: \(missing.joined(separator: ", "))")
        }

        for url in existingFontResourceURLs(bundle: bundle) {
            var registrationError: Unmanaged<CFError>?
            let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
            if !didRegister, let error = registrationError?.takeRetainedValue() {
                NSLog("Voco settings font registration failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    static func requiredFontResourceURLs(bundle: Bundle? = nil) -> [URL] {
        requiredFontResourceFilenames.map { filename in
            fontResourceURL(filename: filename, bundle: bundle)
                ?? URL(fileURLWithPath: "/__missing_voco_font_resource__/\(filename)")
        }
    }

    private static func missingRequiredFontResourceFilenames(bundle: Bundle?) -> [String] {
        requiredFontResourceFilenames.filter { fontResourceURL(filename: $0, bundle: bundle) == nil }
    }

    private static func existingFontResourceURLs(bundle: Bundle?) -> [URL] {
        requiredFontResourceFilenames.compactMap { fontResourceURL(filename: $0, bundle: bundle) }
    }

    private static func fontResourceURL(filename: String, bundle: Bundle?) -> URL? {
        let url = URL(fileURLWithPath: filename)
        let resourceName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        for bundle in candidateBundles(preferredBundle: bundle) {
            if let url = bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Fonts")
                ?? bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Resources/Fonts")
                ?? bundle.url(forResource: resourceName, withExtension: fileExtension) {
                return url
            }
        }

        return sourceFontDirectoryURL()
            .appendingPathComponent(filename)
            .existingFileURL
    }

    private static func candidateBundles(preferredBundle: Bundle?) -> [Bundle] {
        if let preferredBundle {
            return [preferredBundle]
        }

        let mainBundle = Bundle.main
        let bundleName = "VocoNative_VocoApp"
        let candidateBundleURLs = [
            mainBundle.bundleURL.appendingPathComponent("\(bundleName).bundle"),
            mainBundle.resourceURL?.appendingPathComponent("\(bundleName).bundle")
        ].compactMap(\.self)

        let resourceBundles = candidateBundleURLs.compactMap(Bundle.init(url:))
        return [mainBundle] + resourceBundles
    }

    private static func sourceFontDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
    }
}

private extension URL {
    var existingFileURL: URL? {
        FileManager.default.fileExists(atPath: path) ? self : nil
    }
}
