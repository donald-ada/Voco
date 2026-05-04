import Foundation
import SwiftUI

public struct CapsuleView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            let entry = model.entryProgress(now: now)
            ZStack {
                HStack(spacing: HudTheme.Layout.contentSpacing) {
                    statusLabel(at: now)
                    if model.state == .transcribing {
                        TranscribingSpinner(time: now.timeIntervalSinceReferenceDate)
                    } else {
                        WaveformBars(
                            amplitude: model.amplitude,
                            state: model.state,
                            time: now.timeIntervalSinceReferenceDate
                        )
                    }
                }
                .padding(.horizontal, 16)
                .frame(width: HudTheme.Layout.capsuleWidth, height: HudTheme.Layout.capsuleHeight)
                .background {
                    Capsule()
                        .fill(HudTheme.ColorToken.capsule.color)
                        .shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
                }
                .overlay(
                    Capsule().strokeBorder(
                        HudTheme.ColorToken.capsuleBorder.color,
                        lineWidth: 1
                    )
                )
                .opacity(entry)
                .scaleEffect(0.94 + (0.06 * entry))
            }
            .frame(width: HudTheme.Layout.panelWidth, height: HudTheme.Layout.panelHeight)
            .background(Color.clear)
        }
    }

    private func statusLabel(at date: Date) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        let recordingPulse = model.state == .recording
            ? 1.0 + (0.025 * normalizedSine(time, speed: 0.95, offset: 0))
            : 1.0
        let color: Color = model.state == .error
            ? HudTheme.ColorToken.error.color
            : HudTheme.ColorToken.recordingMic.color

        return Text(HudTheme.Layout.statusLabelText)
            .font(.system(size: HudTheme.Layout.statusLabelFontSize, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(recordingPulse)
            .shadow(
                color: color.opacity(model.state == .recording ? 0.38 : 0.22),
                radius: model.state == .recording ? 5 : 3
            )
    }
}

private struct WaveformBars: View {
    let amplitude: Double
    let state: HudState
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 5, height: barHeight(idx))
            }
        }
        .frame(width: HudTheme.Layout.waveformWidth, height: HudTheme.Layout.waveformHeight)
    }

    private var color: Color {
        state == .error ? HudTheme.ColorToken.error.color : HudTheme.ColorToken.waveform.color
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern = [0.42, 0.76, 1.0, 0.82, 0.52, 0.68, 0.46][index]
        if state == .hidden {
            return 8
        }
        if state == .transcribing {
            let moving = normalizedSine(time, speed: 0.7, offset: Double(index) * 0.55)
            return CGFloat(10.0 + moving * 18.0 * pattern)
        }
        let baseline = 4.0 + normalizedSine(time, speed: 0.72, offset: Double(index) * 0.65) * 7.0
        let boosted = max(amplitude, 0.08) * pattern * 18.0
        return CGFloat(min(max(8.0 + baseline + boosted, 8.0), 32.0))
    }
}

private struct TranscribingSpinner: View {
    let time: TimeInterval

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                HudTheme.ColorToken.waveform.color,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees((time * 360.0).truncatingRemainder(dividingBy: 360.0)))
            .shadow(color: HudTheme.ColorToken.waveform.color.opacity(0.35), radius: 6)
    }
}

private func normalizedSine(_ time: TimeInterval, speed: Double, offset: Double) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
