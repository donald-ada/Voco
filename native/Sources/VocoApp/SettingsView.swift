import SwiftUI
import VocoAppCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationTitle("Voco")
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voco 设置")
                    .font(.title2)
                    .fontWeight(.semibold)

                statusRow

                Text("当前版本包含 native macOS app shell：菜单栏状态、设置窗口和登录项开关的界面入口。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 360, alignment: .topLeading)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: coordinator.snapshot.systemImage)
                .foregroundStyle(.yellow)
            Text(coordinator.snapshot.title)
                .font(.headline)
            if let message = coordinator.lastErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }
}
