import Foundation
#if canImport(CSherpaOnnx)
import CSherpaOnnx
#endif

struct SherpaOnnxRecognitionResult: Equatable, Sendable {
    let text: String
}

protocol SherpaOnnxOnlineRecognizing: AnyObject, Sendable {
    func acceptWaveform(samples: [Float], sampleRate: Int)
    func inputFinished()
    func decode()
    func reset()
    var isReady: Bool { get }
    var currentResult: SherpaOnnxRecognitionResult { get }
}

protocol SherpaOnnxRuntimeing: Sendable {
    func makeOnlineRecognizer(modelDirectory: URL) throws -> any SherpaOnnxOnlineRecognizing
}

enum SherpaOnnxRuntimeError: LocalizedError, Sendable {
    case unavailable(String)
    case createRecognizerFailed
    case createStreamFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .createRecognizerFailed:
            return "无法创建 sherpa-onnx recognizer。"
        case .createStreamFailed:
            return "无法创建 sherpa-onnx stream。"
        }
    }
}

#if canImport(CSherpaOnnx)
private func sherpaOnnxCPointer(_ string: String) -> UnsafePointer<Int8>? {
    UnsafePointer((string as NSString).utf8String)
}

private func sherpaOnnxOnlineParaformerModelConfig(
    encoder: String,
    decoder: String
) -> SherpaOnnxOnlineParaformerModelConfig {
    SherpaOnnxOnlineParaformerModelConfig(
        encoder: sherpaOnnxCPointer(encoder),
        decoder: sherpaOnnxCPointer(decoder)
    )
}

private func sherpaOnnxOnlineModelConfig(
    tokens: String,
    paraformer: SherpaOnnxOnlineParaformerModelConfig,
    numThreads: Int = 1,
    modelType: String = "paraformer"
) -> SherpaOnnxOnlineModelConfig {
    SherpaOnnxOnlineModelConfig(
        transducer: SherpaOnnxOnlineTransducerModelConfig(),
        paraformer: paraformer,
        zipformer2_ctc: SherpaOnnxOnlineZipformer2CtcModelConfig(),
        tokens: sherpaOnnxCPointer(tokens),
        num_threads: Int32(numThreads),
        provider: sherpaOnnxCPointer("cpu"),
        debug: 0,
        model_type: sherpaOnnxCPointer(modelType),
        modeling_unit: sherpaOnnxCPointer("cjkchar"),
        bpe_vocab: sherpaOnnxCPointer(""),
        tokens_buf: sherpaOnnxCPointer(""),
        tokens_buf_size: 0,
        nemo_ctc: SherpaOnnxOnlineNemoCtcModelConfig(),
        t_one_ctc: SherpaOnnxOnlineToneCtcModelConfig()
    )
}

private func sherpaOnnxFeatureConfig(
    sampleRate: Int = 16_000,
    featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
    SherpaOnnxFeatureConfig(
        sample_rate: Int32(sampleRate),
        feature_dim: Int32(featureDim)
    )
}

private func sherpaOnnxOnlineRecognizerConfig(
    featureConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOnlineModelConfig
) -> SherpaOnnxOnlineRecognizerConfig {
    SherpaOnnxOnlineRecognizerConfig(
        feat_config: featureConfig,
        model_config: modelConfig,
        decoding_method: sherpaOnnxCPointer("greedy_search"),
        max_active_paths: 4,
        enable_endpoint: 0,
        rule1_min_trailing_silence: 2.4,
        rule2_min_trailing_silence: 1.2,
        rule3_min_utterance_length: 30,
        hotwords_file: sherpaOnnxCPointer(""),
        hotwords_score: 1.5,
        ctc_fst_decoder_config: SherpaOnnxOnlineCtcFstDecoderConfig(),
        rule_fsts: sherpaOnnxCPointer(""),
        rule_fars: sherpaOnnxCPointer(""),
        blank_penalty: 0,
        hotwords_buf: sherpaOnnxCPointer(""),
        hotwords_buf_size: 0,
        hr: SherpaOnnxHomophoneReplacerConfig()
    )
}

final class NativeSherpaOnnxRuntime: SherpaOnnxRuntimeing, @unchecked Sendable {
    func makeOnlineRecognizer(modelDirectory: URL) throws -> any SherpaOnnxOnlineRecognizing {
        let encoder = modelDirectory.appendingPathComponent("encoder.int8.onnx").path
        let decoder = modelDirectory.appendingPathComponent("decoder.int8.onnx").path
        let tokens = modelDirectory.appendingPathComponent("tokens.txt").path

        let paraformer = sherpaOnnxOnlineParaformerModelConfig(
            encoder: encoder,
            decoder: decoder
        )
        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokens,
            paraformer: paraformer
        )
        let featureConfig = sherpaOnnxFeatureConfig()
        var config = sherpaOnnxOnlineRecognizerConfig(
            featureConfig: featureConfig,
            modelConfig: modelConfig
        )

        return try NativeSherpaOnnxOnlineRecognizer(config: &config)
    }
}

private final class NativeSherpaOnnxOnlineRecognizer: SherpaOnnxOnlineRecognizing, @unchecked Sendable {
    private let recognizer: OpaquePointer
    private let stream: OpaquePointer

    init(config: inout SherpaOnnxOnlineRecognizerConfig) throws {
        guard let recognizer = SherpaOnnxCreateOnlineRecognizer(&config) else {
            throw SherpaOnnxRuntimeError.createRecognizerFailed
        }
        guard let stream = SherpaOnnxCreateOnlineStream(recognizer) else {
            SherpaOnnxDestroyOnlineRecognizer(recognizer)
            throw SherpaOnnxRuntimeError.createStreamFailed
        }

        self.recognizer = recognizer
        self.stream = stream
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func acceptWaveform(samples: [Float], sampleRate: Int) {
        SherpaOnnxOnlineStreamAcceptWaveform(
            stream,
            Int32(sampleRate),
            samples,
            Int32(samples.count)
        )
    }

    func inputFinished() {
        SherpaOnnxOnlineStreamInputFinished(stream)
    }

    func decode() {
        SherpaOnnxDecodeOnlineStream(recognizer, stream)
    }

    func reset() {
        SherpaOnnxOnlineStreamReset(recognizer, stream)
    }

    var isReady: Bool {
        SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0
    }

    var currentResult: SherpaOnnxRecognitionResult {
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else {
            return SherpaOnnxRecognitionResult(text: "")
        }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        guard let text = result.pointee.text else {
            return SherpaOnnxRecognitionResult(text: "")
        }
        return SherpaOnnxRecognitionResult(text: String(cString: text))
    }
}
#else
final class NativeSherpaOnnxRuntime: SherpaOnnxRuntimeing, @unchecked Sendable {
    func makeOnlineRecognizer(modelDirectory: URL) throws -> any SherpaOnnxOnlineRecognizing {
        throw SherpaOnnxRuntimeError.unavailable("sherpa-onnx runtime is unavailable in this build.")
    }
}
#endif
