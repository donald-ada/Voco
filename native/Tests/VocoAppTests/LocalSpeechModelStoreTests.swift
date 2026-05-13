import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class LocalSpeechModelStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSpeechModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testStatusReturnsReadyWhenRequiredFilesExist() throws {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        try createRequiredModelFiles(in: store.modelDirectory(for: .recommended))

        XCTAssertEqual(store.status(for: .recommended), .ready)
    }

    func testStatusFailsWhenRequiredFileIsMissing() throws {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)
        let modelDirectory = store.modelDirectory(for: .recommended)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("encoder".utf8).write(to: modelDirectory.appendingPathComponent("encoder.int8.onnx"))
        try Data("decoder".utf8).write(to: modelDirectory.appendingPathComponent("decoder.int8.onnx"))

        XCTAssertEqual(store.status(for: .recommended), .failed("本地模型缺少文件：tokens.txt"))
    }

    func testValidateInstalledModelThrowsNotDownloadedWhenDirectoryIsMissing() {
        let store = LocalSpeechModelStore(applicationSupportURL: temporaryRoot)

        XCTAssertThrowsError(try store.validateInstalledModel(for: .recommended)) { error in
            XCTAssertEqual(error as? LocalSpeechModelError, .notDownloaded)
        }
    }

    private func createRequiredModelFiles(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for filename in LocalSpeechModelManifest.recommended.requiredFiles {
            try Data(filename.utf8).write(to: directory.appendingPathComponent(filename))
        }
    }
}
