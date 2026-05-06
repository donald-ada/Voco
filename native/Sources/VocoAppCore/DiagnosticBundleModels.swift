import Foundation

public struct DiagnosticRedactionContext: Equatable, Sendable {
    public let secrets: [String]
    public let transcriptBodies: [String]

    public init(secrets: [String] = [], transcriptBodies: [String] = []) {
        self.secrets = secrets
        self.transcriptBodies = transcriptBodies
    }
}

public struct DiagnosticBundle: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let appStatusTitle: String
    public let overallSeverity: DiagnosticSeverity
    public let events: [DiagnosticEvent]
    public let redactionNotice: String

    public init(
        snapshot: DiagnosticsSnapshot,
        redaction: DiagnosticRedactionContext = DiagnosticRedactionContext()
    ) {
        self.generatedAt = snapshot.generatedAt
        self.appStatusTitle = DiagnosticRedactor.redact(
            snapshot.appStatusTitle,
            secrets: redaction.secrets,
            transcriptBodies: redaction.transcriptBodies
        )
        self.overallSeverity = snapshot.overallSeverity
        self.events = snapshot.events.map { event in
            DiagnosticEvent(
                id: event.id,
                category: event.category,
                severity: event.severity,
                title: DiagnosticRedactor.redact(
                    event.title,
                    secrets: redaction.secrets,
                    transcriptBodies: redaction.transcriptBodies
                ),
                detail: DiagnosticRedactor.redact(
                    event.detail,
                    secrets: redaction.secrets,
                    transcriptBodies: redaction.transcriptBodies
                )
            )
        }
        self.redactionNotice = "Secrets are replaced with \(DiagnosticRedactor.secretPlaceholder); transcript bodies are replaced with \(DiagnosticRedactor.transcriptPlaceholder)."
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum DiagnosticBundleExportError: LocalizedError, Equatable, Sendable {
    case writeFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let message):
            "导出诊断包失败：无法写入 \(path)：\(message)"
        }
    }
}

public enum DiagnosticBundleExporter {
    @discardableResult
    public static func write(bundle: DiagnosticBundle, to url: URL) throws -> URL {
        do {
            try bundle.jsonData().write(to: url, options: [.atomic])
            return url
        } catch {
            throw DiagnosticBundleExportError.writeFailed(
                path: url.path,
                message: error.localizedDescription
            )
        }
    }
}
