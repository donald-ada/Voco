import Foundation
import SwiftUI

public struct TranscriptDisplay: Equatable {
    public let stable: String
    public let live: String
}

@MainActor
public final class HudModel: ObservableObject {
    @Published public private(set) var state: HudState = .hidden
    @Published public private(set) var amplitude: Double = 0.0
    @Published public private(set) var message: String?
    @Published public private(set) var presentationEpoch: Int = 0
    @Published public private(set) var transcriptText: String = ""
    @Published public private(set) var stablePrefixLen: Int = 0
    private var becameVisibleAt: Date?

    public init() {}

    public var isVisible: Bool {
        state != .hidden
    }

    public var hasTranscript: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var transcriptDisplay: TranscriptDisplay {
        Self.splitTranscript(text: transcriptText, stablePrefixLen: stablePrefixLen)
    }

    public func apply(_ event: HudEvent) {
        switch event {
        case .state(let next, let message):
            let wasHidden = state == .hidden
            state = next
            self.message = message
            if next == .hidden {
                amplitude = 0.0
                self.message = nil
                transcriptText = ""
                stablePrefixLen = 0
                becameVisibleAt = nil
            } else if wasHidden {
                presentationEpoch += 1
                becameVisibleAt = Date()
            }
        case .amplitude(let value):
            amplitude = min(max(value, 0.0), 1.0)
        case .transcript(let text, let stablePrefixLen):
            transcriptText = text
            self.stablePrefixLen = max(0, stablePrefixLen)
        }
    }

    public func entryProgress(now: Date) -> Double {
        guard let becameVisibleAt else {
            return isVisible ? 1.0 : 0.0
        }
        let elapsed = now.timeIntervalSince(becameVisibleAt)
        return min(max(elapsed / 0.28, 0.0), 1.0)
    }

    private static func splitTranscript(text: String, stablePrefixLen: Int) -> TranscriptDisplay {
        guard stablePrefixLen > 0, !text.isEmpty else {
            return TranscriptDisplay(stable: "", live: text)
        }

        var index = text.startIndex
        var bytes = 0
        while index < text.endIndex {
            let next = text.index(after: index)
            let charByteCount = text[index..<next].utf8.count
            if bytes + charByteCount > stablePrefixLen {
                break
            }
            bytes += charByteCount
            index = next
        }

        return TranscriptDisplay(
            stable: String(text[..<index]),
            live: String(text[index...])
        )
    }
}
