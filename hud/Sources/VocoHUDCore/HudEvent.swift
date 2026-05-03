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

    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case message
        case value
    }

    private struct RawEvent: Decodable {
        let type: String
        let state: HudState?
        let message: String?
        let value: Double?
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
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown HUD event type \(raw.type)"))
        }
    }
}
