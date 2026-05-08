import SwiftUI
import VocoAppCore

struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let snapshot = coordinator.hudSnapshot

        HUDNotchIslandOverlay(snapshot: snapshot)
    }
}

private struct HUDNotchIslandOverlay: View {
    let snapshot: HUDSnapshot

    var body: some View {
        let preview = transcriptPreview
        let hasTranscript = preview != nil
        let width = hasTranscript
            ? HUDOverlayChrome.Layout.notchExpandedWidth
            : HUDOverlayChrome.Layout.notchCollapsedWidth
        let height = hasTranscript
            ? HUDOverlayChrome.Layout.notchExpandedHeight
            : HUDOverlayChrome.Layout.notchCollapsedHeight
        let cornerRadius = hasTranscript
            ? 28.0
            : HUDOverlayChrome.Layout.notchCollapsedHeight / 2.0

        ZStack(alignment: .top) {
            islandContent(transcriptPreview: preview)
                .padding(.horizontal, hasTranscript ? 20 : 16)
                .frame(width: width, height: height)
                .clipped()
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(HUDOverlayChrome.ColorToken.notchCapsule.color)
                        .shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            HUDOverlayChrome.ColorToken.notchCapsuleBorder.color,
                            lineWidth: 1
                        )
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.86), value: hasTranscript)
                .padding(.top, HUDOverlayChrome.Layout.notchShadowPadding)
        }
        .opacity(snapshot.isVisible ? 1.0 : 0.0)
        .frame(
            width: HUDOverlayChrome.Layout.panelSize.width,
            height: HUDOverlayChrome.Layout.panelSize.height,
            alignment: .top
        )
        .background(Color.clear)
    }

    @ViewBuilder
    private func islandContent(transcriptPreview: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow

            if let transcriptPreview {
                transcriptLine(transcriptPreview)
                    .transition(transcriptRevealTransition)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: HUDOverlayChrome.Layout.contentSpacing) {
            statusLabel
            Spacer(minLength: 12)
            HUDMiniWaveform(phase: snapshot.phase)
        }
    }

    private var transcriptRevealTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(
                with: .offset(y: HUDOverlayChrome.Layout.transcriptRevealOffsetY)
            ),
            removal: .opacity.combined(
                with: .offset(y: HUDOverlayChrome.Layout.transcriptRevealOffsetY)
            )
        )
    }

    private var statusLabel: some View {
        let color = snapshot.phase == .error
            ? HUDOverlayChrome.ColorToken.error.color
            : HUDOverlayChrome.ColorToken.recordingMic.color

        return Text(statusText)
            .font(.system(
                size: HUDOverlayChrome.Layout.transcriptStatusFontSize,
                weight: .semibold
            ))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(
                color: color.opacity(snapshot.phase == .error ? 0.34 : 0.24),
                radius: 4
            )
    }

    private var statusText: String {
        if snapshot.phase == .error {
            return "输入失败"
        }
        return HUDOverlayChrome.Layout.statusLabelText
    }

    private var transcriptPreview: String? {
        guard snapshot.phase != .error else {
            return nil
        }
        let trimmed = snapshot.transcriptPreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func transcriptLine(_ text: String) -> some View {
        Text(text)
            .font(.system(
                size: HUDOverlayChrome.Layout.transcriptFontSize,
                weight: .semibold
            ))
            .foregroundStyle(HUDOverlayChrome.ColorToken.transcriptLive.color)
            .lineLimit(HUDOverlayChrome.Layout.transcriptLineLimit)
            .truncationMode(.head)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
    }
}

private struct HUDMiniWaveform: View {
    let phase: HUDPhase

    var body: some View {
        TimelineView(
            .animation(minimumInterval: HUDOverlayChrome.Layout.waveformRefreshInterval)
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            waveformBars(time: time)
        }
    }

    private var color: Color {
        phase == .error
            ? HUDOverlayChrome.ColorToken.error.color
            : HUDOverlayChrome.ColorToken.waveform.color
    }

    private func waveformBars(time: TimeInterval) -> some View {
        HStack(spacing: HUDOverlayChrome.Layout.waveformBarSpacing) {
            ForEach(0..<HUDOverlayChrome.Layout.waveformBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: HUDOverlayChrome.Layout.waveformBarWidth / 2.0)
                    .fill(color)
                    .frame(
                        width: HUDOverlayChrome.Layout.waveformBarWidth,
                        height: barHeight(index, time: time)
                    )
            }
        }
        .frame(
            width: HUDOverlayChrome.Layout.waveformWidth,
            height: HUDOverlayChrome.Layout.waveformHeight
        )
    }

    private func barHeight(_ index: Int, time: TimeInterval) -> CGFloat {
        let pattern = [0.40, 0.70, 1.0, 0.78, 0.48, 0.62, 0.42][index]

        switch phase {
        case .hidden:
            return 6
        case .recording, .transcribing, .injecting, .success, .error:
            let baseline = 3.0 + normalizedSine(time, speed: 0.78, offset: Double(index) * 0.65) * 5.0
            let boosted = pattern * 12.0
            return CGFloat(min(max(6.0 + baseline + boosted, 6.0), 26.0))
        }
    }
}

private func normalizedSine(_ time: TimeInterval, speed: Double, offset: Double) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
