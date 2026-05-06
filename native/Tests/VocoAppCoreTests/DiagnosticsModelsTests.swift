import Foundation
import XCTest
@testable import VocoAppCore

final class DiagnosticsModelsTests: XCTestCase {
    func testManualDiagnosticSnapshotCoversRequiredCategoriesAndOverallSeverity() {
        let snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1),
            appStatusTitle: "错误",
            events: [
                DiagnosticEvent(category: .permission, severity: .ok, title: "麦克风", detail: "已允许"),
                DiagnosticEvent(category: .audio, severity: .warning, title: "音频", detail: "无近期采样"),
                DiagnosticEvent(category: .hotkey, severity: .ok, title: "快捷键", detail: "监听中"),
                DiagnosticEvent(category: .asr, severity: .error, title: "ASR", detail: "认证失败"),
                DiagnosticEvent(category: .injection, severity: .ok, title: "输入", detail: "已插入"),
                DiagnosticEvent(category: .failure, severity: .error, title: "最近失败", detail: "认证失败")
            ]
        )

        XCTAssertEqual(snapshot.categories, [.permission, .audio, .hotkey, .asr, .injection, .failure])
        XCTAssertEqual(snapshot.overallSeverity, .error)
        XCTAssertEqual(DiagnosticCategory.asr.title, "ASR")
        XCTAssertEqual(DiagnosticSeverity.warning.systemImage, "exclamationmark.triangle.fill")
    }

    func testDiagnosticRedactorRemovesSecretsAndTranscriptContent() {
        let text = "raw key sk-live-abcdef123456 and transcript 你好 Voco"
        let redacted = DiagnosticRedactor.redact(
            text,
            secrets: ["sk-live-abcdef123456"],
            transcriptBodies: ["你好 Voco"]
        )

        XCTAssertFalse(redacted.contains("sk-live-abcdef123456"))
        XCTAssertFalse(redacted.contains("你好 Voco"))
        XCTAssertTrue(redacted.contains("[redacted secret]"))
        XCTAssertTrue(redacted.contains("[redacted transcript]"))
    }

    func testDiagnosticBundleJSONRedactsSecretsAndTranscriptBody() throws {
        let snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1),
            appStatusTitle: "就绪",
            events: [
                DiagnosticEvent(
                    id: "asr",
                    category: .asr,
                    severity: .ok,
                    title: "Doubao",
                    detail: "stored secret sk-live-abcdef123456"
                ),
                DiagnosticEvent(
                    id: "transcript",
                    category: .asr,
                    severity: .ok,
                    title: "转写",
                    detail: "raw transcript body"
                )
            ]
        )

        let bundle = DiagnosticBundle(
            snapshot: snapshot,
            redaction: DiagnosticRedactionContext(
                secrets: ["sk-live-abcdef123456"],
                transcriptBodies: ["raw transcript body"]
            )
        )
        let json = String(decoding: try bundle.jsonData(), as: UTF8.self)

        XCTAssertFalse(json.contains("sk-live-abcdef123456"))
        XCTAssertFalse(json.contains("raw transcript body"))
        XCTAssertTrue(json.contains("[redacted secret]"))
        XCTAssertTrue(json.contains("[redacted transcript]"))
    }

    func testDiagnosticBundleExporterMapsWriteFailuresToDescriptiveError() throws {
        let snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1),
            appStatusTitle: "就绪",
            events: []
        )
        let bundle = DiagnosticBundle(snapshot: snapshot)
        let blockedURL = URL(fileURLWithPath: "/dev/null/voco-diagnostics.json")

        XCTAssertThrowsError(try DiagnosticBundleExporter.write(bundle: bundle, to: blockedURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("导出诊断包失败"))
            XCTAssertTrue(error.localizedDescription.contains(blockedURL.path))
        }
    }

    @MainActor
    func testCoordinatorDiagnosticBundleRedactsTranscriptByDefault() async throws {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.2, sampleRate: 16_000, peakAmplitude: 0.64),
            transcript: TranscriptSnapshot(
                finalText: "do not export this transcript",
                partials: ["do not export this partial"],
                providerName: "Fake ASR",
                latencyMilliseconds: 42
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "Inserted"
            )
        )
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-live-abcdef123456"),
            recordingWorkflow: StaticRecordingWorkflow(result: result, transcriptionStatus: .ready(providerName: "Fake ASR"))
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        let json = String(decoding: try coordinator.diagnosticBundle().jsonData(), as: UTF8.self)
        XCTAssertFalse(json.contains("do not export this transcript"))
        XCTAssertFalse(json.contains("do not export this partial"))
        XCTAssertFalse(json.contains("sk-live-abcdef123456"))
        XCTAssertTrue(json.contains("[redacted transcript]"))
    }

    @MainActor
    func testCoordinatorDiagnosticsSnapshotIncludesRuntimeCategories() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.2, sampleRate: 16_000, peakAmplitude: 0.64),
            transcript: TranscriptSnapshot(
                finalText: "raw transcript body",
                partials: ["raw partial"],
                providerName: "Fake ASR",
                latencyMilliseconds: 42
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "已通过 Unicode 事件插入文本。"
            )
        )
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-live-abcdef123456"),
            recordingWorkflow: StaticRecordingWorkflow(result: result, transcriptionStatus: .ready(providerName: "Fake ASR")),
            hotkeyProvider: StaticHotkeyProvider(state: .listening)
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        let snapshot = coordinator.diagnosticsSnapshot
        XCTAssertEqual(snapshot.categories, [.permission, .audio, .hotkey, .asr, .injection, .failure])
        XCTAssertTrue(snapshot.events.contains { $0.category == .permission && $0.title.contains("麦克风") })
        XCTAssertTrue(snapshot.events.contains { $0.category == .audio && $0.detail.contains("1.20s") })
        XCTAssertTrue(snapshot.events.contains { $0.category == .hotkey && $0.detail.contains("Right Command") })
        XCTAssertTrue(snapshot.events.contains { $0.category == .asr && $0.title.contains("Fake ASR") })
        XCTAssertTrue(snapshot.events.contains { $0.category == .injection && $0.detail.contains("TextEdit") })
        XCTAssertTrue(snapshot.events.contains { $0.category == .failure && $0.severity == .ok })
    }

    @MainActor
    func testCoordinatorDiagnosticsSnapshotCapturesRecentFailure() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()

        coordinator.fail("provider offline")

        let failure = coordinator.diagnosticsSnapshot.events.first { $0.category == .failure }
        XCTAssertEqual(failure?.severity, .error)
        XCTAssertEqual(failure?.detail, "provider offline")
    }
}
