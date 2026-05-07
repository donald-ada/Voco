import XCTest
@testable import VocoAppCore

final class TranscriptionModelsTests: XCTestCase {
    func testProviderStatusHasUserVisibleMetadata() {
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.title, "未配置")
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.systemImage, "exclamationmark.triangle")
        XCTAssertFalse(TranscriptionProviderStatus.notConfigured.isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "火山引擎").title, "火山引擎")
        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "火山引擎").detail, "模型已配置")
        XCTAssertTrue(TranscriptionProviderStatus.ready(providerName: "火山引擎").isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.authenticationRequired(providerName: "火山引擎").title, "火山引擎需要认证")
        XCTAssertFalse(TranscriptionProviderStatus.authenticationRequired(providerName: "火山引擎").isUsable)
    }

    func testProviderErrorsAreLocalizedAndClassified() {
        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription,
            "模型未配置：请先在设置中配置火山引擎凭证。"
        )
        XCTAssertEqual(
            TranscriptionProviderError.authentication(providerName: "火山引擎", message: "invalid token").localizedDescription,
            "火山引擎认证失败：invalid token"
        )
        XCTAssertTrue(TranscriptionProviderError.transport(providerName: "火山引擎", message: "timeout", retryable: true).isRetryable)
        XCTAssertFalse(TranscriptionProviderError.authentication(providerName: "火山引擎", message: "invalid token").isRetryable)
    }

    func testTranscriptSnapshotAppendsNonEmptyPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "火山引擎",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "火山引擎")
        )

        XCTAssertEqual(updated.finalText, "")
        XCTAssertEqual(updated.partials, ["你好"])
        XCTAssertEqual(updated.providerName, "火山引擎")
    }

    func testTranscriptSnapshotIgnoresBlankPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: ["你好"],
            providerName: "火山引擎",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: " \n ", stablePrefixLength: 0, providerName: "火山引擎")
        )

        XCTAssertEqual(updated.partials, ["你好"])
    }

    func testVolcengineRequestBuilderRejectsSingleAPIKeyForOpenSpeechStreaming() {
        XCTAssertThrowsError(
            try VolcengineTranscriptionRequest.make(
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
                    providerName: "火山引擎",
                    message: "OpenSpeech 流式 ASR 需要 App ID 和 Access Token；单个 API Key 属于新网关协议，当前版本不会用它连接 wss://openspeech.bytedance.com。"
                )
            )
        }
    }

    func testVolcengineRealtimeGatewayRequestBuilderUsesBearerAuthWithoutLeakingSecret() throws {
        let request = try VolcengineRealtimeGatewayTranscriptionRequest.make(
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

    func testVolcengineRealtimeGatewayProtocolBuildsEventsAndParsesTranscriptEvents() throws {
        let sessionUpdate = try VolcengineRealtimeGatewayProtocol.buildSessionUpdateEvent(model: "bigmodel")
        XCTAssertTrue(sessionUpdate.contains(#""type":"transcription_session.update""#))
        XCTAssertTrue(sessionUpdate.contains(#""input_audio_sample_rate":16000"#))
        XCTAssertTrue(sessionUpdate.contains(#""model":"bigmodel""#))

        let appendEvent = try VolcengineRealtimeGatewayProtocol.buildAudioAppendEvent(pcm16Samples: [1, -2])
        XCTAssertTrue(appendEvent.contains(#""type":"input_audio_buffer.append""#))
        XCTAssertTrue(appendEvent.contains(#""audio":"AQD+/w==""#))

        XCTAssertEqual(
            try VolcengineRealtimeGatewayProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.result","transcript":"你好"}"#
            ),
            .partial(TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "火山引擎"))
        )
        XCTAssertEqual(
            try VolcengineRealtimeGatewayProtocol.parseServerEvent(
                #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"你好世界"}"#
            ),
            .final("你好世界")
        )
    }

    func testVolcengineRequestBuilderUsesAppIDAccessTokenHeadersWithoutLeakingSecret() throws {
        let request = try VolcengineTranscriptionRequest.make(
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

    func testVolcengineRequestBuilderSupportsLegacyAppIDAccessTokenCredentials() throws {
        let request = try VolcengineTranscriptionRequest.make(
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

    func testVolcengineRequestBuilderRejectsMissingCredentialAndAudio() {
        XCTAssertThrowsError(
            try VolcengineTranscriptionRequest.make(
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
                .authentication(providerName: "火山引擎", message: "Keychain 中没有保存火山引擎 API Key。")
            )
        }

        XCTAssertThrowsError(
            try VolcengineTranscriptionRequest.make(
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

    func testVolcengineServerErrorCodesMapToProviderErrors() {
        XCTAssertEqual(
            VolcengineTranscriptionErrorMapper.providerError(code: 45000002, message: "empty audio"),
            .emptyAudio
        )
        XCTAssertEqual(
            VolcengineTranscriptionErrorMapper.providerError(code: 45000081, message: "timeout"),
            .transport(providerName: "火山引擎", message: "server timeout (45000081): timeout", retryable: true)
        )
        XCTAssertEqual(
            VolcengineTranscriptionErrorMapper.providerError(code: 55000031, message: "busy"),
            .transport(providerName: "火山引擎", message: "server busy (55000031): busy", retryable: true)
        )
    }

    func testVolcengineBadServerResponseMapsToActionableHandshakeError() {
        let error = VolcengineTranscriptionErrorMapper.transportError(
            URLError(.badServerResponse),
            endpoint: URL(string: volcengineDefaultEndpoint)!,
            resourceID: volcengineLegacyOpenSpeechResourceID
        )

        guard case .transport(let providerName, let message, let retryable) = error else {
            XCTFail("Expected transport error, got \(error)")
            return
        }

        XCTAssertEqual(providerName, "火山引擎")
        XCTAssertTrue(message.contains("OpenSpeech WebSocket 握手被服务端拒绝"))
        XCTAssertTrue(message.contains("App ID + Access Token"))
        XCTAssertTrue(message.contains(volcengineDefaultEndpoint))
        XCTAssertTrue(message.contains(volcengineLegacyOpenSpeechResourceID))
        XCTAssertTrue(retryable)
    }

    func testVolcengineRealtimeGatewayBadServerResponseMapsToAPIKeyHandshakeError() {
        let error = VolcengineTranscriptionErrorMapper.transportError(
            URLError(.badServerResponse),
            endpoint: URL(string: volcengineRealtimeGatewayEndpoint)!
        )

        guard case .transport(let providerName, let message, let retryable) = error else {
            XCTFail("Expected transport error, got \(error)")
            return
        }

        XCTAssertEqual(providerName, "火山引擎")
        XCTAssertTrue(message.contains("Realtime 网关 WebSocket 握手被服务端拒绝"))
        XCTAssertTrue(message.contains("API Key"))
        XCTAssertTrue(message.contains(volcengineRealtimeGatewayEndpoint))
        XCTAssertTrue(retryable)
    }

    func testVolcengineResponseParserExtractsPartialAndFinalText() throws {
        let partial = try VolcengineServerResponse.parsePartial(
            Data(
                #"{"result":{"utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":false}]}}"#.utf8
            )
        )
        XCTAssertEqual(
            partial,
            TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "火山引擎")
        )

        let final = try VolcengineServerResponse.parseFinalText(
            Data(
                #"{"result":{"text":"你好世界","utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":true},{"text":"世界","start_time":500,"end_time":900,"definite":true}]}}"#.utf8
            )
        )
        XCTAssertEqual(final, "你好世界")
    }

    func testVolcengineResponseParserToleratesIncompleteUtteranceObjects() throws {
        let payload = Data(
            #"{"result":{"text":"你好世界","utterances":[{"start_time":0,"end_time":500,"definite":false},{}]}}"#.utf8
        )

        let partial = try VolcengineServerResponse.parsePartial(payload)
        let final = try VolcengineServerResponse.parseFinalText(payload)

        XCTAssertEqual(
            partial,
            TranscriptPartialSnapshot(text: "你好世界", stablePrefixLength: 0, providerName: "火山引擎")
        )
        XCTAssertEqual(final, "你好世界")
    }

    func testVolcengineWireProtocolBuildsClientFramesAndParsesFinalServerFrame() throws {
        let fullClientRequest = try VolcengineWireProtocol.buildFullClientRequestFrame()
        XCTAssertEqual(Array(fullClientRequest.prefix(4)), [0x11, 0x10, 0x11, 0x00])

        let audioFrame = try VolcengineWireProtocol.buildAudioFrame(
            pcm16Samples: [1, -2],
            last: true
        )
        XCTAssertEqual(Array(audioFrame.prefix(4)), [0x11, 0x22, 0x01, 0x00])

        let serverFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )

        let parsed = try VolcengineWireProtocol.parseServerFrame(serverFrame)
        guard case .response(let flags, let payload) = parsed else {
            XCTFail("Expected response frame")
            return
        }

        XCTAssertTrue(flags.isLast)
        XCTAssertEqual(try VolcengineServerResponse.parseFinalText(payload), "hello world")
    }

    func testLiveVolcengineSmokeIsExplicitlyOptIn() throws {
        guard ProcessInfo.processInfo.environment["VOCO_LIVE_VOLCENGINE_ASR"] == "1" else {
            throw XCTSkip("Set VOCO_LIVE_VOLCENGINE_ASR=1 to run the live Volcengine native smoke test.")
        }

        guard let appID = ProcessInfo.processInfo.environment["VOCO_VOLCENGINE_APP_ID"], !appID.isEmpty,
              let accessToken = ProcessInfo.processInfo.environment["VOCO_VOLCENGINE_ACCESS_TOKEN"], !accessToken.isEmpty
        else {
            XCTFail("VOCO_LIVE_VOLCENGINE_ASR=1 requires VOCO_VOLCENGINE_APP_ID and VOCO_VOLCENGINE_ACCESS_TOKEN.")
            return
        }

        let request = try VolcengineTranscriptionRequest.make(
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
