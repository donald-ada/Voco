import SwiftUI

public struct TranscriptIslandView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            let hasTranscript = model.hasTranscript
            let width = hasTranscript
                ? HudTheme.Layout.notchExpandedWidth
                : HudTheme.Layout.notchCollapsedWidth
            let height = hasTranscript
                ? HudTheme.Layout.notchExpandedHeight
                : HudTheme.Layout.notchCollapsedHeight
            let cornerRadius = hasTranscript ? 28.0 : HudTheme.Layout.notchCollapsedHeight / 2.0

            ZStack {
                islandContent(
                    time: now.timeIntervalSinceReferenceDate,
                    hasTranscript: hasTranscript
                )
                .padding(.horizontal, hasTranscript ? 20 : 16)
                .frame(width: width, height: height)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(HudTheme.ColorToken.capsule.color)
                        .shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(HudTheme.ColorToken.capsuleBorder.color, lineWidth: 1)
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.86), value: hasTranscript)
            }
            .frame(width: HudTheme.Layout.notchPanelWidth, height: HudTheme.Layout.notchPanelHeight)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    private func islandContent(time: TimeInterval, hasTranscript: Bool) -> some View {
        if hasTranscript {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusLabel
                    Spacer(minLength: 12)
                    TranscriptMiniWaveform(amplitude: model.amplitude, time: time)
                }
                transcriptLine
            }
        } else {
            HStack(spacing: HudTheme.Layout.contentSpacing) {
                statusLabel
                Spacer(minLength: 6)
                TranscriptMiniWaveform(amplitude: model.amplitude, time: time)
            }
        }
    }

    private var statusLabel: some View {
        Text(HudTheme.Layout.statusLabelText)
            .font(.system(size: HudTheme.Layout.transcriptStatusFontSize, weight: .semibold))
            .foregroundStyle(HudTheme.ColorToken.recordingMic.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(color: HudTheme.ColorToken.recordingMic.color.opacity(0.24), radius: 4)
    }

    private var transcriptLine: some View {
        let display = model.transcriptDisplay
        return (Text(display.stable).foregroundStyle(HudTheme.ColorToken.transcriptStable.color)
            + Text(display.live).foregroundStyle(HudTheme.ColorToken.transcriptLive.color))
            .font(.system(size: HudTheme.Layout.transcriptFontSize, weight: .semibold))
            .lineLimit(HudTheme.Layout.transcriptLineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptMiniWaveform: View {
    let amplitude: Double
    let time: TimeInterval

    var body: some View {
        HStack(spacing: HudTheme.Layout.waveformBarSpacing) {
            ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: HudTheme.Layout.waveformBarWidth / 2.0)
                    .fill(HudTheme.ColorToken.waveform.color)
                    .frame(width: HudTheme.Layout.waveformBarWidth, height: barHeight(index))
            }
        }
        .frame(width: HudTheme.Layout.waveformWidth, height: HudTheme.Layout.waveformHeight)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern = [0.40, 0.70, 1.0, 0.78, 0.48, 0.62, 0.42][index]
        let baseline = 3.0 + normalizedTranscriptSine(
            time,
            speed: 0.78,
            offset: Double(index) * 0.65
        ) * 5.0
        let boosted = max(amplitude, 0.06) * pattern * 12.0
        return CGFloat(min(max(6.0 + baseline + boosted, 6.0), 26.0))
    }
}

private func normalizedTranscriptSine(
    _ time: TimeInterval,
    speed: Double,
    offset: Double
) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
