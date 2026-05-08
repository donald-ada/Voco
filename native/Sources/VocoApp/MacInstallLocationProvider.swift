import Foundation
import VocoAppCore

struct MacInstallLocationProvider: InstallLocationProviding {
    private let bundleURL: URL

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    func currentInstallLocation(strings: VocoStrings = VocoStrings()) -> InstallLocationSnapshot {
        InstallLocationCheck.snapshot(forAppBundlePath: bundleURL.path, strings: strings)
    }
}
