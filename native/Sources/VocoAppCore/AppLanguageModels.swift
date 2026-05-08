import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case en

    public static let `default`: AppLanguage = .zhHans

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans:
            "中文"
        case .en:
            "English"
        }
    }
}
