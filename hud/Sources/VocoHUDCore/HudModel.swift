import Foundation
import SwiftUI

@MainActor
public final class HudModel: ObservableObject {
    @Published public private(set) var state: HudState = .hidden
    @Published public private(set) var amplitude: Double = 0.0
    @Published public private(set) var message: String?

    public init() {}

    public var isVisible: Bool {
        state != .hidden
    }

    public func apply(_ event: HudEvent) {
        switch event {
        case .state(let next, let message):
            state = next
            self.message = message
            if next == .hidden {
                amplitude = 0.0
                self.message = nil
            }
        case .amplitude(let value):
            amplitude = min(max(value, 0.0), 1.0)
        }
    }
}
