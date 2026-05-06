import Foundation
import VocoAppCore

struct MacInstallLocationProvider: InstallLocationProviding {
    private let bundleURL: URL

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    func currentInstallLocation() -> InstallLocationSnapshot {
        InstallLocationCheck.snapshot(forAppBundlePath: bundleURL.path)
    }
}
