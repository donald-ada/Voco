import SwiftUI
import VocoAppCore

struct DiagnosticsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var exportMessage: String?

    var body: some View {
        let snapshot = coordinator.diagnosticsSnapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(snapshot)

                ForEach(DiagnosticCategory.allCases) { category in
                    let events = snapshot.events.filter { $0.category == category }
                    if !events.isEmpty {
                        diagnosticsSection(category: category, events: events)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 460, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 420, alignment: .topLeading)
    }

    private func header(_ snapshot: DiagnosticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Voco 诊断")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Label(snapshot.overallSeverity.title, systemImage: snapshot.overallSeverity.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(severityTint(snapshot.overallSeverity))
            }

            HStack(spacing: 12) {
                Label(snapshot.appStatusTitle, systemImage: "menubar.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formattedDate(snapshot.generatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    exportDiagnostics()
                } label: {
                    Label("导出诊断包", systemImage: "square.and.arrow.up")
                }
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func diagnosticsSection(
        category: DiagnosticCategory,
        events: [DiagnosticEvent]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category.title, systemImage: category.systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    diagnosticRow(event)

                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func diagnosticRow(_ event: DiagnosticEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.severity.systemImage)
                .frame(width: 18)
                .foregroundStyle(severityTint(event.severity))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exportDiagnostics() {
        do {
            let writtenURL = try coordinator.exportDiagnosticBundleToTemporaryDirectory()
            exportMessage = "已导出：\(writtenURL.path)"
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func severityTint(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .ok:
            .green
        case .warning:
            .yellow
        case .error:
            .red
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .medium
        )
    }
}
