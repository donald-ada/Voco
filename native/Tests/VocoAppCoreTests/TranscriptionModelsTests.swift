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

    func testDoubaoRequestBuilderRejectsSingleAPIKeyForOpenSpeechStreaming() {
        XCTAssertThrowsError(
            try DoubaoTranscriptionRequest.make(
                apiKey: " sk-test-secret ",
                audio: CapturedAudioSnapshot(
                    durationSeconds: 1,
                    sampleRate: 16_000,
                    peakAmplitude: 0.2,
                    pcm16Samples: [1, 2]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? TranscriptionProviderError,
                .authentication(
                    providerName: "Doubao",
                    message: "OpenSpeech 流式 ASR 需要 App ID 和 Access Token；单个 API Key 属于新网关协议，当前版本不会用它连接 wss://openspeech.bytedance.com。"
                )
            )
        }
    }

    func testDoubaoRealtimeGatewayRequestBuilderUsesBearerAuthWithoutLeakingSecret() throws {
        let request = try DoubaoRealtimeGatewayTranscriptionRequest.make(
            apiKey: " sk-gateway-secret ",
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        )

        XCTAssertEqual(
            request.endpoint.absoluteString,
            "wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel"
        )
        XCTAssertEqual(request.model, "bigmodel")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-gateway-secret")
        XCTAssertNil(request.headers["X-Api-Key"])
        XCTAssertNil(request.safeDebugDescription.range(of: "sk-gateway-secret"))
        XCTAssertTrue(request.safeDebugDescription.contains("Authorization"))
    }

    func testDoubaoRealtimeGatewayProtocolBuildsEventsAndParsesTranscriptEvents() throws {
        let sessionUpdate = try DoubaoRealtimeGatewayProtocol.buildSessionUpdateEvent(model: "bigmodel")
        XCTAssertTrue(sessionUpdate.contains(#""type":"transcription_session.update""#))
        XCTAssertTrue(sessionUpdate.contains(#""input_audio_sample_rate":16000"#))
        XCTAssertTrue(sessionUpdate.contains(#""model":"bigmodel""#))

        let appendEvent = try DoubaoRealtimeGatewayProtocol.buildAudioAppendEvent(pcm16Samples: [1, -2])
        XCTAssertTrue(appendEvent.contains(#""type":"input_audio_buffer.append""#))
        XCTAssertTrue(appendEvent.contains(#""audio":"AQD+/w==""#))

        XCTAssertEqual(
            try DoubaoRealtimeGatewayProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.result","transcript":"你好"}"#
            ),
            .partial(TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao"))
        )
        XCTAssertEqual(
            try DoubaoRealtimeGatewayProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好世界"}"#
            ),
            .final("你好世界")
        )
    }

    func testDoubaoRequestBuilderUsesAppIDAccessTokenHeadersWithoutLeakingSecret() throws {
        let request = try DoubaoTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: " 3145608744 ", accessToken: " old-token "),
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
        XCTAssertEqual(request.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(request.headers["X-Api-Access-Key"], "old-token")
        XCTAssertNil(request.headers["X-Api-Key"])
        XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
        XCTAssertNil(request.safeDebugDescription.range(of: "old-token"))
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
                auth: .appIDAccessToken(appID: "3145608744", accessToken: "old-token"),
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

    func testDoubaoBadServerResponseMapsToActionableHandshakeError() {
        let error = DoubaoTranscriptionErrorMapper.transportError(
            URLError(.badServerResponse),
            endpoint: URL(string: doubaoDefaultEndpoint)!,
            resourceID: doubaoLegacyOpenSpeechResourceID
        )

        guard case .transport(let providerName, let message, let retryable) = error else {
            XCTFail("Expected transport error, got \(error)")
            return
        }

        XCTAssertEqual(providerName, "Doubao")
        XCTAssertTrue(message.contains("OpenSpeech WebSocket 握手被服务端拒绝"))
        XCTAssertTrue(message.contains("App ID + Access Token"))
        XCTAssertTrue(message.contains(doubaoDefaultEndpoint))
        XCTAssertTrue(message.contains(doubaoLegacyOpenSpeechResourceID))
        XCTAssertTrue(retryable)
    }

    func testDoubaoRealtimeGatewayBadServerResponseMapsToAPIKeyHandshakeError() {
        let error = DoubaoTranscriptionErrorMapper.transportError(
            URLError(.badServerResponse),
            endpoint: URL(string: doubaoRealtimeGatewayEndpoint)!
        )

        guard case .transport(let providerName, let message, let retryable) = error else {
            XCTFail("Expected transport error, got \(error)")
            return
        }

        XCTAssertEqual(providerName, "Doubao")
        XCTAssertTrue(message.contains("Realtime 网关 WebSocket 握手被服务端拒绝"))
        XCTAssertTrue(message.contains("API Key"))
        XCTAssertTrue(message.contains(doubaoRealtimeGatewayEndpoint))
        XCTAssertTrue(retryable)
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

        guard let appID = ProcessInfo.processInfo.environment["VOCO_DOUBAO_APP_ID"], !appID.isEmpty,
              let accessToken = ProcessInfo.processInfo.environment["VOCO_DOUBAO_ACCESS_TOKEN"], !accessToken.isEmpty
        else {
            XCTFail("VOCO_LIVE_DOUBAO_ASR=1 requires VOCO_DOUBAO_APP_ID and VOCO_DOUBAO_ACCESS_TOKEN.")
            return
        }

        let request = try DoubaoTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: appID, accessToken: accessToken),
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.1,
                sampleRate: 16_000,
                peakAmplitude: 0.1,
                pcm16Samples: [0, 0, 0, 0]
            )
        )

        XCTAssertEqual(request.headers["X-Api-App-Key"], appID)
        XCTAssertEqual(request.headers["X-Api-Access-Key"], accessToken)
        XCTAssertNil(request.headers["X-Api-Key"])
        XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
        XCTAssertNil(request.safeDebugDescription.range(of: accessToken))
    }
}
