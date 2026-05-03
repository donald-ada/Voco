import SwiftUI

public struct CapsuleView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 14) {
            statusDot
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
            WaveformBars(amplitude: model.amplitude, state: model.state)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 260, height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
    }

    private var foreground: Color {
        model.state == .error ? .red : Color(red: 0.16, green: 0.18, blue: 0.22)
    }

    private var iconName: String {
        switch model.state {
        case .hidden, .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(model.state == .error ? Color.red : Color.yellow)
            .frame(width: 10, height: 10)
            .opacity(model.state == .transcribing ? 0.45 : 1.0)
    }
}

private struct WaveformBars: View {
    let amplitude: Double
    let state: HudState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 5, height: barHeight(idx))
                    .animation(.easeOut(duration: 0.12), value: amplitude)
            }
        }
        .frame(width: 70, height: 32)
    }

    private var color: Color {
        state == .error ? .red : Color(red: 0.16, green: 0.18, blue: 0.22)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        if state == .transcribing {
            return [10, 18, 26, 18, 10, 14, 20][index]
        }
        let pattern = [0.45, 0.72, 1.0, 0.82, 0.55, 0.68, 0.5][index]
        let scaled = 8.0 + max(amplitude, 0.06) * pattern * 24.0
        return CGFloat(min(max(scaled, 8.0), 32.0))
    }
}
