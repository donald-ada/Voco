import Foundation

public struct VoiceInputSessionSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let transcriptText: String
    public let rawTranscriptText: String
    public let postProcessingDiagnostics: [TranscriptPostProcessingDiagnostic]
    public let wordCount: Int
    public let durationSeconds: Double
    public let createdAt: Date
    public let targetAppName: String?
    public let providerName: String

    public init(
        id: UUID = UUID(),
        transcriptText: String,
        rawTranscriptText: String? = nil,
        postProcessingDiagnostics: [TranscriptPostProcessingDiagnostic] = [],
        wordCount: Int,
        durationSeconds: Double,
        createdAt: Date = Date(),
        targetAppName: String?,
        providerName: String
    ) {
        self.id = id
        self.transcriptText = transcriptText
        self.rawTranscriptText = rawTranscriptText ?? transcriptText
        self.postProcessingDiagnostics = postProcessingDiagnostics
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.targetAppName = targetAppName
        self.providerName = providerName
    }

    public init(
        result: RecordingWorkflowResult,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        let processedText = result.postProcessing.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: id,
            transcriptText: processedText,
            rawTranscriptText: result.postProcessing.originalText,
            postProcessingDiagnostics: result.postProcessing.diagnostics,
            wordCount: processedText.count,
            durationSeconds: result.audio.durationSeconds,
            createdAt: createdAt,
            targetAppName: result.injection.targetAppName,
            providerName: result.transcript.providerName
        )
    }

    public func previewText(maxLength: Int) -> String {
        guard maxLength > 0 else {
            return ""
        }

        let normalized = transcriptText.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > maxLength else {
            return normalized
        }

        return "\(normalized.prefix(maxLength))..."
    }

    public var durationTitle: String {
        "\(Int(durationSeconds.rounded()))s"
    }
}

public struct VoiceInputSessionPage: Equatable, Sendable {
    public static let defaultPageSize = 10

    public let entries: [VoiceInputSessionSnapshot]
    public let page: Int
    public let pageSize: Int
    public let totalCount: Int
    public let totalPages: Int

    public init(
        sessions: [VoiceInputSessionSnapshot],
        page: Int,
        pageSize: Int = VoiceInputSessionPage.defaultPageSize
    ) {
        let normalizedPageSize = max(1, pageSize)
        let computedTotalPages = max(1, Int(ceil(Double(sessions.count) / Double(normalizedPageSize))))
        let clampedPage = min(max(1, page), computedTotalPages)
        let startIndex = min((clampedPage - 1) * normalizedPageSize, sessions.count)
        let endIndex = min(startIndex + normalizedPageSize, sessions.count)

        self.entries = Array(sessions[startIndex..<endIndex])
        self.page = clampedPage
        self.pageSize = normalizedPageSize
        self.totalCount = sessions.count
        self.totalPages = computedTotalPages
    }

    public var visibleRangeTitle: String {
        visibleRangeTitle(strings: VocoStrings())
    }

    public func visibleRangeTitle(strings: VocoStrings) -> String {
        guard totalCount > 0 else {
            return strings.sessions.visibleRangeTitle(start: 0, end: 0, total: 0)
        }

        let start = (page - 1) * pageSize + 1
        let end = min(start + entries.count - 1, totalCount)
        return strings.sessions.visibleRangeTitle(start: start, end: end, total: totalCount)
    }
}

public enum VoiceInputSessionRetention {
    public static let defaultPolicy = VoiceInputSessionRetentionPolicy.last1000
    public static let defaultLimit = defaultPolicy.loadLimit
}

public enum VoiceInputSessionStoreError: LocalizedError, Sendable {
    case loadFailed(message: String)
    case saveFailed(message: String)

    public var errorDescription: String? {
        localizedDescription(strings: VocoStrings())
    }

    public func localizedDescription(strings: VocoStrings) -> String {
        strings.sessions.storeErrorDescription(for: self)
    }
}

public protocol VoiceInputSessionStoring: AnyObject {
    func loadRecentSessions(limit: Int) throws -> [VoiceInputSessionSnapshot]
    func save(_ session: VoiceInputSessionSnapshot) throws
    func trimRecentSessions(limit: Int?) throws
}

public final class InMemoryVoiceInputSessionStore: VoiceInputSessionStoring {
    private var sessions: [VoiceInputSessionSnapshot]

    public init(
        storedSessions: [VoiceInputSessionSnapshot] = [],
        retentionLimit: Int = VoiceInputSessionRetention.defaultLimit
    ) {
        self.sessions = Array(storedSessions.prefix(max(1, retentionLimit)))
    }

    public func loadRecentSessions(limit: Int) throws -> [VoiceInputSessionSnapshot] {
        Array(sessions.prefix(max(0, limit)))
    }

    public func save(_ session: VoiceInputSessionSnapshot) throws {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
    }

    public func trimRecentSessions(limit: Int?) throws {
        guard let limit else {
            return
        }

        sessions = Array(sessions.prefix(max(0, limit)))
    }
}
