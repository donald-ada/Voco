import XCTest
@testable import VocoAppCore

final class TranscriptionModelsTests: XCTestCase {
    func testProviderStatusUsesEnglishMetadata() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.title(strings: strings), "Not Configured")
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.detail(strings: strings), "Configure Volcengine credentials first.")
        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "火山引擎").detail(strings: strings), "Model configured")
        XCTAssertEqual(
            TranscriptionProviderStatus.authenticationRequired(providerName: "火山引擎").detail(strings: strings),
            "Check Volcengine credentials."
        )
        XCTAssertEqual(
            TranscriptionProviderStatus.offline(providerName: "火山引擎").detail(strings: strings),
            "The model is temporarily unavailable. Try again later."
        )
    }

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

    func testProviderErrorCanRenderEnglishDescription() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription(strings: strings),
            "Model not configured: configure Volcengine credentials in Settings first."
        )
        XCTAssertEqual(
            TranscriptionProviderError.authentication(providerName: "火山引擎", message: "invalid token")
                .localizedDescription(strings: strings),
            "Volcengine authentication failed: invalid token"
        )
        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription,
            "模型未配置：请先在设置中配置火山引擎凭证。"
        )
    }

    func testProviderErrorCanRenderKnownAppGeneratedDetailsInEnglish() {
        let strings = VocoStrings(language: .en)
        let endpoint = URL(string: "wss://example.test/asr")!

        XCTAssertEqual(
            TranscriptionProviderError.authentication(
                providerName: "火山引擎",
                message: "Keychain 中没有保存火山引擎凭证。"
            ).localizedDescription(strings: strings),
            "Volcengine authentication failed: No Volcengine credentials are saved in Keychain."
        )
        XCTAssertEqual(
            VolcengineTranscriptionErrorMapper.transportError(
                URLError(.badServerResponse),
                endpoint: endpoint,
                resourceID: "volc.test"
            ).localizedDescription(strings: strings),
            "Volcengine network error: OpenSpeech WebSocket handshake was rejected by the server. Check Volcengine credentials and confirm the Resource ID is enabled. endpoint=wss://example.test/asr resourceID=volc.test"
        )
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

    func testVolcengineRequestBuilderSupportsNewConsoleAPIKeyCredentials() throws {
        let request = try VolcengineTranscriptionRequest.make(
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
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        )
        XCTAssertEqual(request.headers["X-Api-Key"], "sk-test-secret")
        XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
        XCTAssertNil(request.headers["X-Api-App-Key"])
        XCTAssertNil(request.headers["X-Api-Access-Key"])
        XCTAssertNil(request.safeDebugDescription.range(of: "sk-test-secret"))
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
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
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
        XCTAssertTrue(message.contains("火山引擎凭证"))
        XCTAssertTrue(message.contains(volcengineDefaultEndpoint))
        XCTAssertTrue(message.contains(volcengineLegacyOpenSpeechResourceID))
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
        let payloadJSON = try VolcengineWireProtocol.buildFullClientRequestPayloadJSON()
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadJSON) as? [String: Any]
        )
        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_nonstream"] as? Bool, true)
        XCTAssertEqual(request["show_utterances"] as? Bool, true)

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
