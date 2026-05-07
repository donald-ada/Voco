import Foundation
import zlib

public enum VolcengineMessageFlags: UInt8, Sendable {
    case noSequence = 0b0000
    case positiveSequence = 0b0001
    case lastNoSequence = 0b0010
    case lastWithSequence = 0b0011
    case withEvent = 0b0100

    public var isLast: Bool {
        self == .lastNoSequence || self == .lastWithSequence
    }

    var carriesSequence: Bool {
        self == .positiveSequence || self == .lastWithSequence
    }

    var carriesEvent: Bool {
        self == .withEvent
    }
}

public enum VolcengineServerFrame: Sendable {
    case response(flags: VolcengineMessageFlags, payload: Data)
    case error(code: Int, message: String)
}

public enum VolcengineWireProtocol {
    private static let protocolVersion: UInt8 = 1
    private static let headerSizeWords: UInt8 = 1

    public static func buildFullClientRequestFrame() throws -> Data {
        let payload = VolcengineFullClientRequestPayload.vocoDefaults()
        let json = try JSONEncoder().encode(payload)
        return try sizePrefixedFrame(
            messageType: .fullClientRequest,
            flags: .noSequence,
            serialization: .json,
            compression: .gzip,
            payload: gzip(json)
        )
    }

    public static func buildAudioFrame(
        pcm16Samples: [Int16],
        last: Bool
    ) throws -> Data {
        var pcmBytes = Data(capacity: pcm16Samples.count * 2)
        for sample in pcm16Samples {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcmBytes.append(contentsOf: $0) }
        }

        return try sizePrefixedFrame(
            messageType: .audioOnlyRequest,
            flags: last ? .lastNoSequence : .noSequence,
            serialization: .none,
            compression: .gzip,
            payload: gzip(pcmBytes)
        )
    }

    public static func parseServerFrame(_ data: Data) throws -> VolcengineServerFrame {
        var cursor = DataCursor(data)
        let headerBytes = try cursor.readBytes(count: 4)
        let header = try Header.decode(headerBytes)

        switch header.messageType {
        case .fullServerResponse:
            if header.flags.carriesSequence {
                _ = try cursor.readInt32()
            }

            if header.flags.carriesEvent {
                try skipEventFields(cursor: &cursor)
            }

            let payloadSize = Int(try cursor.readUInt32())
            let payload = try cursor.readBytes(count: payloadSize)
            let decodedPayload: Data
            switch header.compression {
            case .gzip:
                decodedPayload = try gunzip(payload)
            case .none:
                decodedPayload = payload
            }

            return .response(flags: header.flags, payload: decodedPayload)
        case .serverError:
            let code = Int(try cursor.readUInt32())
            let messageSize = Int(try cursor.readUInt32())
            let rawMessage = try cursor.readBytes(count: messageSize)
            let decodedMessage: Data
            switch header.compression {
            case .gzip:
                decodedMessage = try gunzip(rawMessage)
            case .none:
                decodedMessage = rawMessage
            }

            let message = String(data: decodedMessage, encoding: .utf8) ?? "<non-UTF8 server error>"
            return .error(code: code, message: message)
        default:
            throw wireError("unexpected server message type \(header.messageType)")
        }
    }

    static func buildTestServerResponseFrame(json: String, last: Bool) throws -> Data {
        let payload = try gzip(Data(json.utf8))
        var frame = header(
            messageType: .fullServerResponse,
            flags: last ? .lastWithSequence : .positiveSequence,
            serialization: .json,
            compression: .gzip
        )
        appendInt32(last ? -1 : 1, to: &frame)
        appendUInt32(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    static func buildTestServerErrorFrame(code: Int, message: String) -> Data {
        let payload = Data(message.utf8)
        var frame = header(
            messageType: .serverError,
            flags: .noSequence,
            serialization: .json,
            compression: .none
        )
        appendUInt32(UInt32(code), to: &frame)
        appendUInt32(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    private static func sizePrefixedFrame(
        messageType: MessageType,
        flags: VolcengineMessageFlags,
        serialization: Serialization,
        compression: VolcengineCompression,
        payload: Data
    ) throws -> Data {
        var frame = header(
            messageType: messageType,
            flags: flags,
            serialization: serialization,
            compression: compression
        )
        appendUInt32(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    private static func header(
        messageType: MessageType,
        flags: VolcengineMessageFlags,
        serialization: Serialization,
        compression: VolcengineCompression
    ) -> Data {
        Data([
            (protocolVersion << 4) | headerSizeWords,
            (messageType.rawValue << 4) | flags.rawValue,
            (serialization.rawValue << 4) | compression.rawValue,
            0x00
        ])
    }

    private static func skipEventFields(cursor: inout DataCursor) throws {
        let event = try cursor.readInt32()
        if !(event == 1 || event == 2 || (50...52).contains(event)) {
            try cursor.skipLengthPrefixedString(label: "session id")
        }
        if (50...52).contains(event) {
            try cursor.skipLengthPrefixedString(label: "connect id")
        }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func gzip(_ input: Data) throws -> Data {
        try zlibTransform(input, operation: .deflate)
    }

    private static func gunzip(_ input: Data) throws -> Data {
        try zlibTransform(input, operation: .inflate)
    }

    private static func zlibTransform(_ input: Data, operation: ZlibOperation) throws -> Data {
        var stream = z_stream()
        let initStatus: Int32
        switch operation {
        case .deflate:
            initStatus = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        case .inflate:
            initStatus = inflateInit2_(
                &stream,
                MAX_WBITS + 32,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        }

        guard initStatus == Z_OK else {
            throw wireError("\(operation.label) init failed: \(initStatus)")
        }
        defer {
            switch operation {
            case .deflate:
                deflateEnd(&stream)
            case .inflate:
                inflateEnd(&stream)
            }
        }

        let chunkSize = 16 * 1024
        var output = Data()
        var inputCopy = input
        let status: Int32 = try inputCopy.withUnsafeMutableBytes { inputBuffer in
            stream.next_in = inputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(inputBuffer.count)

            var status: Int32
            repeat {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                status = try chunk.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(chunkSize)

                    let status: Int32
                    switch operation {
                    case .deflate:
                        status = deflate(&stream, Z_FINISH)
                    case .inflate:
                        status = inflate(&stream, Z_NO_FLUSH)
                    }

                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw wireError("\(operation.label) failed: \(status)")
                    }

                    return status
                }

                let written = chunkSize - Int(stream.avail_out)
                if written > 0 {
                    output.append(contentsOf: chunk.prefix(written))
                }
            } while status != Z_STREAM_END

            return status
        }

        guard status == Z_STREAM_END else {
            throw wireError("\(operation.label) ended unexpectedly: \(status)")
        }
        return output
    }

    private static func wireError(_ message: String) -> TranscriptionProviderError {
        .provider(providerName: volcengineTranscriptionProviderName, message: "wire protocol: \(message)")
    }
}

private enum ZlibOperation {
    case deflate
    case inflate

    var label: String {
        switch self {
        case .deflate:
            "gzip"
        case .inflate:
            "gunzip"
        }
    }
}

private enum MessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case serverError = 0b1111
}

private enum Serialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

private enum VolcengineCompression: UInt8 {
    case none = 0b0000
    case gzip = 0b0001
}

private struct Header {
    let messageType: MessageType
    let flags: VolcengineMessageFlags
    let compression: VolcengineCompression

    static func decode(_ bytes: Data) throws -> Header {
        guard bytes.count == 4 else {
            throw VolcengineWireProtocol.providerWireErrorForHeader("header needs 4 bytes")
        }

        let first = bytes[bytes.startIndex]
        let protocolVersion = first >> 4
        let headerSize = first & 0x0F
        guard protocolVersion == 1, headerSize == 1 else {
            throw VolcengineWireProtocol.providerWireErrorForHeader(
                "unsupported header version=\(protocolVersion) size=\(headerSize)"
            )
        }

        let second = bytes[bytes.index(bytes.startIndex, offsetBy: 1)]
        let third = bytes[bytes.index(bytes.startIndex, offsetBy: 2)]
        guard let messageType = MessageType(rawValue: second >> 4) else {
            throw VolcengineWireProtocol.providerWireErrorForHeader("unknown message type \(second >> 4)")
        }
        guard let flags = VolcengineMessageFlags(rawValue: second & 0x0F) else {
            throw VolcengineWireProtocol.providerWireErrorForHeader("unknown flags \(second & 0x0F)")
        }
        guard let compression = VolcengineCompression(rawValue: third & 0x0F) else {
            throw VolcengineWireProtocol.providerWireErrorForHeader("unknown compression \(third & 0x0F)")
        }

        return Header(messageType: messageType, flags: flags, compression: compression)
    }
}

private extension VolcengineWireProtocol {
    static func providerWireErrorForHeader(_ message: String) -> TranscriptionProviderError {
        .provider(providerName: volcengineTranscriptionProviderName, message: "wire protocol: \(message)")
    }
}

private struct DataCursor {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "wire protocol: truncated frame"
            )
        }

        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return Data(data[start..<end])
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func skipLengthPrefixedString(label: String) throws {
        let size = Int(try readUInt32())
        _ = try readBytes(count: size)
    }
}

private struct VolcengineFullClientRequestPayload: Encodable {
    let user: UserPayload
    let audio: AudioPayload
    let request: RequestPayload

    static func vocoDefaults() -> VolcengineFullClientRequestPayload {
        VolcengineFullClientRequestPayload(
            user: UserPayload(uid: "voco", platform: "macOS"),
            audio: AudioPayload(format: "pcm", codec: "raw", rate: 16_000, bits: 16, channel: 1),
            request: RequestPayload(
                modelName: "bigmodel",
                enablePunc: true,
                enableItn: true,
                enableDdc: false,
                resultType: "full",
                endWindowSize: 800
            )
        )
    }
}

private struct UserPayload: Encodable {
    let uid: String
    let platform: String
}

private struct AudioPayload: Encodable {
    let format: String
    let codec: String
    let rate: Int
    let bits: Int
    let channel: Int
}

private struct RequestPayload: Encodable {
    let modelName: String
    let enablePunc: Bool
    let enableItn: Bool
    let enableDdc: Bool
    let resultType: String
    let endWindowSize: Int

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case enablePunc = "enable_punc"
        case enableItn = "enable_itn"
        case enableDdc = "enable_ddc"
        case resultType = "result_type"
        case endWindowSize = "end_window_size"
    }
}
