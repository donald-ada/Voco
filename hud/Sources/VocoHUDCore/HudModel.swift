import Foundation
import SwiftUI

@MainActor
public final class HudModel: ObservableObject {
    @Published public private(set) var state: HudState = .hidden
    @Published public private(set) var amplitude: Double = 0.0
    @Published public private(set) var message: String?
    @Published public private(set) var presentationEpoch: Int = 0
    private var becameVisibleAt: Date?

    public init() {}

    public var isVisible: Bool {
        state != .hidden
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
                becameVisibleAt = nil
            } else if wasHidden {
                presentationEpoch += 1
                becameVisibleAt = Date()
            }
        case .amplitude(let value):
            amplitude = min(max(value, 0.0), 1.0)
        }
    }

    public func entryProgress(now: Date) -> Double {
        guard let becameVisibleAt else {
            return isVisible ? 1.0 : 0.0
        }
        let elapsed = now.timeIntervalSince(becameVisibleAt)
        return min(max(elapsed / 0.28, 0.0), 1.0)
    }
}
