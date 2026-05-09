import Foundation
import XCTest
@testable import VocoApp
import VocoAppCore

@MainActor
final class MacVoiceInputSessionStoreTests: XCTestCase {
    func testSQLiteStorePersistsSessionsAcrossInstances() throws {
        let databaseURL = try temporaryDatabaseURL()
        let firstStore = try MacVoiceInputSessionStore(databaseURL: databaseURL)
        let session = makeSession(text: "第一条录音内容", offset: 1)

        try firstStore.save(session)

        let reloadedStore = try MacVoiceInputSessionStore(databaseURL: databaseURL)
        let sessions = try reloadedStore.loadRecentSessions(limit: 10)

        XCTAssertEqual(sessions, [session])
    }

    func testSQLiteStorePersistsRawTranscriptAndPostProcessingDiagnostics() throws {
        let databaseURL = try temporaryDatabaseURL()
        let store = try MacVoiceInputSessionStore(databaseURL: databaseURL)
        let session = VoiceInputSessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            transcriptText: "今天开始",
            rawTranscriptText: "嗯今天开始",
            postProcessingDiagnostics: [
                TranscriptPostProcessingDiagnostic(
                    skillID: FillerCleanupSkill.skillID,
                    ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                    ruleDisplayName: "删除嗯",
                    matchedText: "嗯",
                    replacementText: "",
                    matchCount: 1
                )
            ],
            wordCount: 4,
            durationSeconds: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            targetAppName: "Notes",
            providerName: "TestProvider"
        )

        try store.save(session)

        let loaded = try store.loadRecentSessions(limit: 10)
        XCTAssertEqual(loaded, [session])
    }

    func testSQLiteStoreTrimsOlderSessionsWhenCustomerChoosesLimitedRetention() throws {
        let databaseURL = try temporaryDatabaseURL()
        let store = try MacVoiceInputSessionStore(databaseURL: databaseURL)

        for offset in 1...105 {
            try store.save(makeSession(text: "录音 \(offset)", offset: TimeInterval(offset)))
        }
        try store.trimRecentSessions(limit: VoiceInputSessionRetentionPolicy.last100.limit)

        let sessions = try store.loadRecentSessions(limit: VoiceInputSessionRetentionPolicy.last100.loadLimit)

        XCTAssertEqual(sessions.count, 100)
        XCTAssertEqual(sessions.first?.transcriptText, "录音 105")
        XCTAssertEqual(sessions.last?.transcriptText, "录音 6")
    }

    func testSQLiteStoreKeepsAllSessionsWhenCustomerChoosesForeverRetention() throws {
        let databaseURL = try temporaryDatabaseURL()
        let store = try MacVoiceInputSessionStore(databaseURL: databaseURL)

        for offset in 1...105 {
            try store.save(makeSession(text: "录音 \(offset)", offset: TimeInterval(offset)))
        }
        try store.trimRecentSessions(limit: VoiceInputSessionRetentionPolicy.forever.limit)

        let sessions = try store.loadRecentSessions(limit: 200)

        XCTAssertEqual(sessions.count, 105)
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocoSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        return directory.appendingPathComponent("voice-input-sessions.sqlite")
    }

    private func makeSession(text: String, offset: TimeInterval) -> VoiceInputSessionSnapshot {
        VoiceInputSessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", Int(offset)))")!,
            transcriptText: text,
            wordCount: text.count,
            durationSeconds: offset,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 + offset),
            targetAppName: "Codex",
            providerName: "火山引擎"
        )
    }
}
