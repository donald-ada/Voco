import CryptoKit
import Foundation
import VocoAppCore

protocol LocalSpeechModelDownloadTransport {
    func download(
        from url: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (LocalSpeechModelDownloadProgress) -> Void
    ) async throws
}

protocol LocalSpeechModelExtracting {
    func extractArchive(at archiveURL: URL, to destinationDirectory: URL) async throws
}

final class LocalSpeechModelDownloader: @unchecked Sendable {
    private let store: LocalSpeechModelStore
    private let transport: any LocalSpeechModelDownloadTransport
    private let extractor: any LocalSpeechModelExtracting
    private let fileManager: FileManager

    init(
        store: LocalSpeechModelStore,
        transport: any LocalSpeechModelDownloadTransport = URLSessionLocalSpeechModelDownloadTransport(),
        extractor: any LocalSpeechModelExtracting = TarLocalSpeechModelExtractor(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.transport = transport
        self.extractor = extractor
        self.fileManager = fileManager
    }

    func download(
        manifest: LocalSpeechModelManifest,
        progress: @escaping @Sendable (LocalSpeechModelDownloadProgress) -> Void = { _ in }
    ) async -> LocalSpeechModelStatus {
        let downloadsDirectory = store.downloadsDirectory()
        let partialArchiveURL = downloadsDirectory.appendingPathComponent("\(manifest.archiveFilename).partial")
        let extractionDirectory = downloadsDirectory.appendingPathComponent(
            "\(manifest.id.rawValue)-\(manifest.version).extracting",
            isDirectory: true
        )
        let finalDirectory = store.modelDirectory(for: manifest)

        do {
            try cleanTemporaryItems(partialArchiveURL: partialArchiveURL, extractionDirectory: extractionDirectory)
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

            try await transport.download(from: manifest.archiveURL, to: partialArchiveURL, progress: progress)
            try validateArchiveChecksumIfNeeded(partialArchiveURL, manifest: manifest)

            try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try await extractor.extractArchive(at: partialArchiveURL, to: extractionDirectory)

            let extractedModelDirectory = try validExtractedModelDirectory(
                in: extractionDirectory,
                manifest: manifest
            )
            try installValidatedModel(from: extractedModelDirectory, to: finalDirectory)
            try cleanTemporaryItems(partialArchiveURL: partialArchiveURL, extractionDirectory: extractionDirectory)
            return .ready
        } catch {
            try? cleanTemporaryItems(partialArchiveURL: partialArchiveURL, extractionDirectory: extractionDirectory)
            let message = error.localizedDescription
            NSLog("Voco: Local speech model download failed: \(message)")
            return .failed(message)
        }
    }

    private func cleanTemporaryItems(partialArchiveURL: URL, extractionDirectory: URL) throws {
        for url in [partialArchiveURL, extractionDirectory] where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw LocalSpeechModelError.fileSystem(error.localizedDescription)
            }
        }

        let downloadsDirectory = extractionDirectory.deletingLastPathComponent()
        if fileManager.fileExists(atPath: downloadsDirectory.path),
           (try? fileManager.contentsOfDirectory(atPath: downloadsDirectory.path).isEmpty) == true {
            try? fileManager.removeItem(at: downloadsDirectory)
        }
    }

    private func validateArchiveChecksumIfNeeded(
        _ archiveURL: URL,
        manifest: LocalSpeechModelManifest
    ) throws {
        guard let expectedSHA256 = manifest.expectedSHA256 else {
            return
        }

        let actualSHA256 = try Self.sha256HexDigest(of: archiveURL)
        guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw LocalSpeechModelError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
        }
    }

    private func validExtractedModelDirectory(
        in extractionDirectory: URL,
        manifest: LocalSpeechModelManifest
    ) throws -> URL {
        let directCandidate = extractionDirectory
        if isValidModelDirectory(directCandidate, manifest: manifest) {
            return directCandidate
        }

        let nestedCandidate = extractionDirectory.appendingPathComponent(manifest.id.rawValue, isDirectory: true)
        try store.validateModelDirectory(nestedCandidate, manifest: manifest)
        return nestedCandidate
    }

    private func isValidModelDirectory(_ directory: URL, manifest: LocalSpeechModelManifest) -> Bool {
        do {
            try store.validateModelDirectory(directory, manifest: manifest)
            return true
        } catch {
            return false
        }
    }

    private func installValidatedModel(from sourceDirectory: URL, to finalDirectory: URL) throws {
        let parentDirectory = finalDirectory.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: finalDirectory.path) {
                try fileManager.removeItem(at: finalDirectory)
            }
            try fileManager.moveItem(at: sourceDirectory, to: finalDirectory)
        } catch {
            throw LocalSpeechModelError.fileSystem(error.localizedDescription)
        }
    }

    private static func sha256HexDigest(of fileURL: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw LocalSpeechModelError.fileSystem(error.localizedDescription)
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class URLSessionLocalSpeechModelDownloadTransport: LocalSpeechModelDownloadTransport {
    func download(
        from url: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (LocalSpeechModelDownloadProgress) -> Void
    ) async throws {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let bytesWritten = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : bytesWritten
            progress(LocalSpeechModelDownloadProgress(bytesWritten: bytesWritten, totalBytes: totalBytes))

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw LocalSpeechModelError.downloadFailed(error.localizedDescription)
        }
    }
}

final class TarLocalSpeechModelExtractor: LocalSpeechModelExtracting {
    func extractArchive(at archiveURL: URL, to destinationDirectory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", destinationDirectory.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LocalSpeechModelError.extractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            throw LocalSpeechModelError.extractionFailed("tar exited with status \(process.terminationStatus)")
        }
    }
}
