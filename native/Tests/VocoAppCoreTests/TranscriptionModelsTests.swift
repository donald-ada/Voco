import XCTest
@testable import VocoAppCore

final class TranscriptionModelsTests: XCTestCase {
    func testProviderStatusHasUserVisibleMetadata() {
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.title, "未配置")
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.systemImage, "exclamationmark.triangle")
        XCTAssertFalse(TranscriptionProviderStatus.notConfigured.isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").title, "Doubao")
        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").detail, "转写服务已配置")
        XCTAssertTrue(TranscriptionProviderStatus.ready(providerName: "Doubao").isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").title, "Doubao 需要认证")
        XCTAssertFalse(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").isUsable)
    }

    func testProviderErrorsAreLocalizedAndClassified() {
        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription,
            "转写服务未配置：请先在设置中配置 ASR provider。"
        )
        XCTAssertEqual(
            TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").localizedDescription,
            "Doubao 认证失败：invalid token"
        )
        XCTAssertTrue(TranscriptionProviderError.transport(providerName: "Doubao", message: "timeout", retryable: true).isRetryable)
        XCTAssertFalse(TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").isRetryable)
    }

    func testTranscriptSnapshotAppendsNonEmptyPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Doubao",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao")
        )

        XCTAssertEqual(updated.finalText, "")
        XCTAssertEqual(updated.partials, ["你好"])
        XCTAssertEqual(updated.providerName, "Doubao")
    }

    func testTranscriptSnapshotIgnoresBlankPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: ["你好"],
            providerName: "Doubao",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: " \n ", stablePrefixLength: 0, providerName: "Doubao")
        )

        XCTAssertEqual(updated.partials, ["你好"])
    }

    func testDoubaoRequestBuilderUsesAPIKeyHeadersWithoutLeakingSecret() throws {
        let request = try DoubaoTranscriptionRequest.make(
            apiKey: " sk-test-secret ",
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        )

        XCTAssertEqual(
            request.endpoint.absoluteString,
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
        )
        XCTAssertEqual(request.resourceID, "volc.seedasr.sauc.duration")
        XCTAssertEqual(request.headers["X-Api-Key"], "sk-test-secret")
        XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
        XCTAssertNil(request.safeDebugDescription.range(of: "sk-test-secret"))
        XCTAssertTrue(request.safeDebugDescription.contains("wss://openspeech.bytedance.com"))
    }

    func testDoubaoRequestBuilderSupportsLegacyAppIDAccessTokenCredentials() throws {
        let request = try DoubaoTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: " 3145608744 ", accessToken: " old-token "),
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        )

        XCTAssertEqual(request.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(request.headers["X-Api-Access-Key"], "old-token")
        XCTAssertNil(request.headers["X-Api-Key"])
        XCTAssertNil(request.safeDebugDescription.range(of: "old-token"))
        XCTAssertTrue(request.safeDebugDescription.contains("X-Api-Access-Key"))
    }

    func testDoubaoRequestBuilderRejectsMissingCredentialAndAudio() {
        XCTAssertThrowsError(
            try DoubaoTranscriptionRequest.make(
                apiKey: " ",
                audio: CapturedAudioSnapshot(
                    durationSeconds: 1,
                    sampleRate: 16_000,
                    peakAmplitude: 0.2,
                    pcm16Samples: [1]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? TranscriptionProviderError,
                .authentication(providerName: "Doubao", message: "Keychain 中没有保存 Doubao API Key。")
            )
        }

        XCTAssertThrowsError(
            try DoubaoTranscriptionRequest.make(
                apiKey: "sk-test",
                audio: CapturedAudioSnapshot(
                    durationSeconds: 0,
                    sampleRate: 16_000,
                    peakAmplitude: 0,
                    pcm16Samples: []
                )
            )
        ) { error in
            XCTAssertEqual(error as? TranscriptionProviderError, .emptyAudio)
        }
    }

    func testDoubaoServerErrorCodesMapToProviderErrors() {
        XCTAssertEqual(
            DoubaoTranscriptionErrorMapper.providerError(code: 45000002, message: "empty audio"),
            .emptyAudio
        )
        XCTAssertEqual(
            DoubaoTranscriptionErrorMapper.providerError(code: 45000081, message: "timeout"),
            .transport(providerName: "Doubao", message: "server timeout (45000081): timeout", retryable: true)
        )
        XCTAssertEqual(
            DoubaoTranscriptionErrorMapper.providerError(code: 55000031, message: "busy"),
            .transport(providerName: "Doubao", message: "server busy (55000031): busy", retryable: true)
        )
    }

    func testDoubaoResponseParserExtractsPartialAndFinalText() throws {
        let partial = try DoubaoServerResponse.parsePartial(
            Data(
                #"{"result":{"utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":false}]}}"#.utf8
            )
        )
        XCTAssertEqual(
            partial,
            TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao")
        )

        let final = try DoubaoServerResponse.parseFinalText(
            Data(
                #"{"result":{"text":"你好世界","utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":true},{"text":"世界","start_time":500,"end_time":900,"definite":true}]}}"#.utf8
            )
        )
        XCTAssertEqual(final, "你好世界")
    }

    func testDoubaoResponseParserToleratesIncompleteUtteranceObjects() throws {
        let payload = Data(
            #"{"result":{"text":"你好世界","utterances":[{"start_time":0,"end_time":500,"definite":false},{}]}}"#.utf8
        )

        let partial = try DoubaoServerResponse.parsePartial(payload)
        let final = try DoubaoServerResponse.parseFinalText(payload)

        XCTAssertEqual(
            partial,
            TranscriptPartialSnapshot(text: "你好世界", stablePrefixLength: 0, providerName: "Doubao")
        )
        XCTAssertEqual(final, "你好世界")
    }

    func testDoubaoWireProtocolBuildsClientFramesAndParsesFinalServerFrame() throws {
        let fullClientRequest = try DoubaoWireProtocol.buildFullClientRequestFrame()
        XCTAssertEqual(Array(fullClientRequest.prefix(4)), [0x11, 0x10, 0x11, 0x00])

        let audioFrame = try DoubaoWireProtocol.buildAudioFrame(
            pcm16Samples: [1, -2],
            last: true
        )
        XCTAssertEqual(Array(audioFrame.prefix(4)), [0x11, 0x22, 0x01, 0x00])

        let serverFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )

        let parsed = try DoubaoWireProtocol.parseServerFrame(serverFrame)
        guard case .response(let flags, let payload) = parsed else {
            XCTFail("Expected response frame")
            return
        }

        XCTAssertTrue(flags.isLast)
        XCTAssertEqual(try DoubaoServerResponse.parseFinalText(payload), "hello world")
    }

    func testLiveDoubaoSmokeIsExplicitlyOptIn() throws {
        guard ProcessInfo.processInfo.environment["VOCO_LIVE_DOUBAO_ASR"] == "1" else {
            throw XCTSkip("Set VOCO_LIVE_DOUBAO_ASR=1 to run the live Doubao native smoke test.")
        }

        guard let apiKey = ProcessInfo.processInfo.environment["VOCO_DOUBAO_API_KEY"], !apiKey.isEmpty else {
            XCTFail("VOCO_LIVE_DOUBAO_ASR=1 requires VOCO_DOUBAO_API_KEY.")
            return
        }

        let request = try DoubaoTranscriptionRequest.make(
            apiKey: apiKey,
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.1,
                sampleRate: 16_000,
                peakAmplitude: 0.1,
                pcm16Samples: [0, 0, 0, 0]
            )
        )

        XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
        XCTAssertNil(request.safeDebugDescription.range(of: apiKey))
    }
}
