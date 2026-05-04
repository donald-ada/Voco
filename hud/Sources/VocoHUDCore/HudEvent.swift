import Foundation

public enum HudState: String, Codable, Equatable {
    case hidden
    case recording
    case transcribing
    case error
}

public enum HudEvent: Equatable {
    case state(HudState, message: String?)
    case amplitude(Double)
    case transcript(text: String, stablePrefixLen: Int)

    private struct RawEvent: Decodable {
        private enum CodingKeys: String, CodingKey {
            case type
            case state
            case message
            case value
            case text
            case stablePrefixLen = "stable_prefix_len"
        }

        let type: String
        let state: HudState?
        let message: String?
        let value: Double?
        let text: String?
        let stablePrefixLen: Int?
    }

    public static func decodeLine(_ line: String) throws -> HudEvent {
        let data = Data(line.utf8)
        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        switch raw.type {
        case "state":
            guard let state = raw.state else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "state event missing state"))
            }
            return .state(state, message: raw.message)
        case "amplitude":
            guard let value = raw.value else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "amplitude event missing value"))
            }
            return .amplitude(value)
        case "transcript":
            guard let text = raw.text else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "transcript event missing text"))
            }
            guard let stablePrefixLen = raw.stablePrefixLen else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "transcript event missing stable_prefix_len"))
            }
            return .transcript(text: text, stablePrefixLen: stablePrefixLen)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown HUD event type \(raw.type)"))
        }
    }
}
