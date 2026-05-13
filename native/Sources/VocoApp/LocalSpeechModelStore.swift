import Foundation
import VocoAppCore

final class LocalSpeechModelStore: @unchecked Sendable {
    private let applicationSupportURL: URL
    private let fileManager: FileManager

    init(
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let applicationSupportURL {
            self.applicationSupportURL = applicationSupportURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.applicationSupportURL = baseURL.appendingPathComponent("Voco", isDirectory: true)
        }
    }

    func modelDirectory(for manifest: LocalSpeechModelManifest) -> URL {
        applicationSupportURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(manifest.id.rawValue, isDirectory: true)
            .appendingPathComponent(manifest.version, isDirectory: true)
    }

    func downloadsDirectory() -> URL {
        applicationSupportURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    func status(for manifest: LocalSpeechModelManifest) -> LocalSpeechModelStatus {
        do {
            _ = try validateInstalledModel(for: manifest)
            return .ready
        } catch LocalSpeechModelError.notDownloaded {
            return .notDownloaded
        } catch {
            let message = error.localizedDescription
            NSLog("Voco: Local speech model validation failed: \(message)")
            return .failed(message)
        }
    }

    @discardableResult
    func validateInstalledModel(for manifest: LocalSpeechModelManifest) throws -> URL {
        let directory = modelDirectory(for: manifest)
        try validateModelDirectory(directory, manifest: manifest)
        return directory
    }

    func validateModelDirectory(_ directory: URL, manifest: LocalSpeechModelManifest) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalSpeechModelError.notDownloaded
        }

        for filename in manifest.requiredFiles {
            let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw LocalSpeechModelError.missingRequiredFile(filename)
            }

            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            } catch {
                throw LocalSpeechModelError.fileSystem(error.localizedDescription)
            }

            let size = attributes[.size] as? NSNumber
            guard size?.int64Value ?? 0 > 0 else {
                throw LocalSpeechModelError.missingRequiredFile(filename)
            }
        }
    }

    func removeInstalledModel(for manifest: LocalSpeechModelManifest) throws {
        let directory = modelDirectory(for: manifest)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw LocalSpeechModelError.fileSystem(error.localizedDescription)
        }
    }
}
