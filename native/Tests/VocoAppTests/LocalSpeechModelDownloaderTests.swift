import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class LocalSpeechModelDownloaderTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSpeechModelDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testDownloadInstallsValidatedModel() async throws {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        let transport = FakeLocalSpeechModelDownloadTransport()
        let extractor = FakeLocalSpeechModelExtractor()
        let downloader = LocalSpeechModelDownloader(store: store, transport: transport, extractor: extractor)
        let progressBox = LocalSpeechModelDownloadProgressBox()

        let status = await downloader.download(manifest: .fixture) { progress in
            progressBox.append(progress)
        }
        let progressEvents = progressBox.values

        XCTAssertEqual(status, .ready)
        XCTAssertEqual(store.status(for: .fixture), .ready)
        XCTAssertEqual(progressEvents.map(\.bytesWritten), [4, 10])
    }

    func testDownloadFailureReturnsFailedStatus() async {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        let transport = FakeLocalSpeechModelDownloadTransport(error: LocalSpeechModelError.downloadFailed("network down"))
        let downloader = LocalSpeechModelDownloader(
            store: store,
            transport: transport,
            extractor: FakeLocalSpeechModelExtractor()
        )

        let status = await downloader.download(manifest: .fixture)

        XCTAssertEqual(status, .failed("本地模型下载失败：network down"))
    }

    func testExtractionFailureReturnsFailedStatusAndCleansTemporaryFiles() async throws {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        let downloader = LocalSpeechModelDownloader(
            store: store,
            transport: FakeLocalSpeechModelDownloadTransport(),
            extractor: FakeLocalSpeechModelExtractor(error: LocalSpeechModelError.extractionFailed("bad archive"))
        )

        let status = await downloader.download(manifest: .fixture)

        XCTAssertEqual(status, .failed("本地模型解压失败：bad archive"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.downloadsDirectory().path))
    }

    func testValidationFailureReturnsFailedStatusAndDoesNotInstallModel() async {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        let downloader = LocalSpeechModelDownloader(
            store: store,
            transport: FakeLocalSpeechModelDownloadTransport(),
            extractor: FakeLocalSpeechModelExtractor(filesToCreate: ["encoder.int8.onnx", "decoder.int8.onnx"])
        )

        let status = await downloader.download(manifest: .fixture)

        XCTAssertEqual(status, .failed("本地模型缺少文件：tokens.txt"))
        XCTAssertEqual(store.status(for: .fixture), .notDownloaded)
    }
}

private extension LocalSpeechModelManifest {
    static let fixture = LocalSpeechModelManifest(
        id: .recommendedSherpaOnnx,
        displayName: "Fixture Model",
        version: "fixture",
        archiveURL: URL(string: "https://example.com/fixture.tar.bz2")!,
        archiveFilename: "fixture.tar.bz2",
        requiredFiles: ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"],
        expectedSHA256: nil
    )
}

private final class FakeLocalSpeechModelDownloadTransport: LocalSpeechModelDownloadTransport {
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func download(
        from url: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (LocalSpeechModelDownloadProgress) -> Void
    ) async throws {
        progress(LocalSpeechModelDownloadProgress(bytesWritten: 4, totalBytes: 10))
        if let error {
            throw error
        }
        try Data("archive".utf8).write(to: destinationURL)
        progress(LocalSpeechModelDownloadProgress(bytesWritten: 10, totalBytes: 10))
    }
}

private final class FakeLocalSpeechModelExtractor: LocalSpeechModelExtracting {
    let error: Error?
    let filesToCreate: [String]

    init(
        error: Error? = nil,
        filesToCreate: [String] = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]
    ) {
        self.error = error
        self.filesToCreate = filesToCreate
    }

    func extractArchive(at archiveURL: URL, to destinationDirectory: URL) async throws {
        if let error {
            throw error
        }

        let modelDirectory = destinationDirectory.appendingPathComponent(LocalSpeechModelID.recommendedSherpaOnnx.rawValue)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for filename in filesToCreate {
            try Data(filename.utf8).write(to: modelDirectory.appendingPathComponent(filename))
        }
    }
}

private final class LocalSpeechModelDownloadProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalSpeechModelDownloadProgress] = []

    func append(_ progress: LocalSpeechModelDownloadProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var values: [LocalSpeechModelDownloadProgress] {
        lock.lock()
        let values = storage
        lock.unlock()
        return values
    }
}
