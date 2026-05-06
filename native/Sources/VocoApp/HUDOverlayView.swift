import SwiftUI
import VocoAppCore

struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let snapshot = coordinator.hudSnapshot

        HUDCapsuleOverlay(snapshot: snapshot)
    }
}

private struct HUDCapsuleOverlay: View {
    let snapshot: HUDSnapshot

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: HUDOverlayChrome.Layout.contentSpacing) {
                statusLabel(time: now)

                if snapshot.phase == .transcribing || snapshot.phase == .injecting {
                    HUDTranscribingSpinner(time: now)
                } else {
                    HUDWaveformBars(phase: snapshot.phase, time: now)
                }
            }
            .padding(.horizontal, 16)
            .frame(
                width: HUDOverlayChrome.Layout.capsuleWidth,
                height: HUDOverlayChrome.Layout.capsuleHeight
            )
            .background {
                Capsule()
                    .fill(HUDOverlayChrome.ColorToken.capsule.color)
                    .shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
            }
            .overlay(
                Capsule().strokeBorder(
                    HUDOverlayChrome.ColorToken.capsuleBorder.color,
                    lineWidth: 1
                )
            )
            .opacity(snapshot.isVisible ? 1.0 : 0.0)
            .frame(
                width: HUDOverlayChrome.Layout.panelSize.width,
                height: HUDOverlayChrome.Layout.panelSize.height
            )
            .background(Color.clear)
        }
    }

    private func statusLabel(time: TimeInterval) -> some View {
        let isRecording = snapshot.phase == .recording
        let pulse = isRecording ? 1.0 + (0.025 * normalizedSine(time, speed: 0.95, offset: 0)) : 1.0
        let color = snapshot.phase == .error
            ? HUDOverlayChrome.ColorToken.error.color
            : HUDOverlayChrome.ColorToken.recordingMic.color

        return Text(HUDOverlayChrome.Layout.statusLabelText)
            .font(.system(
                size: HUDOverlayChrome.Layout.statusLabelFontSize,
                weight: .semibold
            ))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(pulse)
            .shadow(
                color: color.opacity(isRecording ? 0.38 : 0.22),
                radius: isRecording ? 5 : 3
            )
    }
}

private struct HUDWaveformBars: View {
    let phase: HUDPhase
    let time: TimeInterval

    var body: some View {
        HStack(spacing: HUDOverlayChrome.Layout.waveformBarSpacing) {
            ForEach(0..<HUDOverlayChrome.Layout.waveformBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: HUDOverlayChrome.Layout.waveformBarWidth / 2.0)
                    .fill(color)
                    .frame(
                        width: HUDOverlayChrome.Layout.waveformBarWidth,
                        height: barHeight(index)
                    )
            }
        }
        .frame(
            width: HUDOverlayChrome.Layout.waveformWidth,
            height: HUDOverlayChrome.Layout.waveformHeight
        )
    }

    private var color: Color {
        phase == .error ? HUDOverlayChrome.ColorToken.error.color : HUDOverlayChrome.ColorToken.waveform.color
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern = [0.40, 0.70, 1.0, 0.78, 0.48, 0.62, 0.42][index]

        switch phase {
        case .hidden:
            return 6
        case .success:
            return CGFloat(7.0 + pattern * 5.0)
        case .error:
            return CGFloat(8.0 + pattern * 9.0)
        case .recording, .transcribing, .injecting:
            let baseline = 3.0 + normalizedSine(time, speed: 0.78, offset: Double(index) * 0.65) * 5.0
            let boosted = pattern * 12.0
            return CGFloat(min(max(6.0 + baseline + boosted, 6.0), 26.0))
        }
    }
}

private struct HUDTranscribingSpinner: View {
    let time: TimeInterval

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                HUDOverlayChrome.ColorToken.waveform.color,
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees((time * 360.0).truncatingRemainder(dividingBy: 360.0)))
            .shadow(color: HUDOverlayChrome.ColorToken.waveform.color.opacity(0.35), radius: 6)
    }
}

private func normalizedSine(_ time: TimeInterval, speed: Double, offset: Double) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
