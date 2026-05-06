import SwiftUI
import VocoAppCore

struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let snapshot = coordinator.hudSnapshot

        HStack(spacing: 12) {
            Image(systemName: snapshot.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(iconTint(snapshot.phase))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(snapshot.transcriptPreview ?? snapshot.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .frame(minHeight: 72, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private func iconTint(_ phase: HUDPhase) -> Color {
        switch phase {
        case .recording:
            .red
        case .transcribing, .injecting:
            .blue
        case .success:
            .green
        case .error:
            .orange
        case .hidden:
            .secondary
        }
    }
}
