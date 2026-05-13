import Foundation

public let localRecommendedTranscriptionProviderName = "本地模型"

public enum TranscriptionModelProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case volcengine
    case localRecommended

    public var id: String {
        rawValue
    }

    public func title(strings: VocoStrings = VocoStrings()) -> String {
        switch (self, strings.language) {
        case (.volcengine, .zhHans):
            return "火山引擎"
        case (.volcengine, .en):
            return "Volcengine"
        case (.localRecommended, .zhHans):
            return "本地模型"
        case (.localRecommended, .en):
            return "Local Model"
        }
    }
}

public enum LocalSpeechModelID: String, Codable, Identifiable, Sendable {
    case recommendedSherpaOnnx = "sherpa-onnx-streaming-paraformer-bilingual-zh-en"

    public var id: String {
        rawValue
    }
}

public struct TranscriptionModelSelection: Codable, Equatable, Sendable {
    public let providerID: TranscriptionModelProviderID
    public let localModelID: LocalSpeechModelID

    public static let `default` = TranscriptionModelSelection(
        providerID: .volcengine,
        localModelID: .recommendedSherpaOnnx
    )

    public init(
        providerID: TranscriptionModelProviderID = .volcengine,
        localModelID: LocalSpeechModelID = .recommendedSherpaOnnx
    ) {
        self.providerID = providerID
        self.localModelID = localModelID
    }
}

public struct LocalSpeechModelManifest: Equatable, Sendable {
    public let id: LocalSpeechModelID
    public let displayName: String
    public let version: String
    public let archiveURL: URL
    public let archiveFilename: String
    public let requiredFiles: [String]
    public let expectedSHA256: String?

    public static let recommended = LocalSpeechModelManifest(
        id: .recommendedSherpaOnnx,
        displayName: "sherpa-onnx streaming paraformer bilingual zh-en",
        version: "asr-models",
        archiveURL: URL(
            string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2"
        )!,
        archiveFilename: "sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2",
        requiredFiles: ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"],
        expectedSHA256: "5462a1fce42693deae572af1e8c4687124b12aa85fe61ff4d3168bb5280e205f"
    )
}

public struct LocalSpeechModelDownloadProgress: Equatable, Sendable {
    public let bytesWritten: Int64
    public let totalBytes: Int64?

    public init(bytesWritten: Int64, totalBytes: Int64?) {
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else {
            return nil
        }
        return min(1, max(0, Double(bytesWritten) / Double(totalBytes)))
    }
}

public enum LocalSpeechModelStatus: Equatable, Sendable {
    case notDownloaded
    case downloading(LocalSpeechModelDownloadProgress)
    case verifying
    case ready
    case failed(String)
    case unavailable(String)

    public var canApply: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

public enum LocalSpeechModelError: LocalizedError, Equatable, Sendable {
    case notDownloaded
    case missingRequiredFile(String)
    case checksumMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case extractionFailed(String)
    case fileSystem(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notDownloaded:
            return "本地模型未下载。"
        case .missingRequiredFile(let filename):
            return "本地模型缺少文件：\(filename)"
        case .checksumMismatch(let expected, let actual):
            return "本地模型校验失败：expected \(expected), actual \(actual)"
        case .downloadFailed(let message):
            return "本地模型下载失败：\(message)"
        case .extractionFailed(let message):
            return "本地模型解压失败：\(message)"
        case .fileSystem(let message):
            return "本地模型文件访问失败：\(message)"
        case .cancelled:
            return "本地模型下载已取消。"
        }
    }
}

@MainActor
public protocol TranscriptionModelSelectionStoring: AnyObject {
    var selection: TranscriptionModelSelection { get }
    func saveSelection(_ selection: TranscriptionModelSelection)
}

public final class NoOpTranscriptionModelSelectionStore: TranscriptionModelSelectionStoring {
    public init() {}

    public var selection: TranscriptionModelSelection {
        .default
    }

    public func saveSelection(_ selection: TranscriptionModelSelection) {}
}
