import AppKit
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

                permissionsSection

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 360, alignment: .topLeading)
        }
        .onAppear {
            coordinator.prepareForSettingsPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshPermissions()
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

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("权限")
                    .font(.headline)
                Spacer()
                Button {
                    coordinator.refreshPermissions()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
            }

            ForEach(coordinator.permissions) { permission in
                permissionRow(permission)
            }
        }
    }

    private func permissionRow(_ permission: PermissionSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.kind.systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(permission.kind.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Label(permission.state.title, systemImage: permission.state.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(permissionTint(permission.state))

                    Text(permission.isRequired ? "必需" : "可选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(permission.kind.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !permission.state.isGranted {
                    HStack(spacing: 8) {
                        if permission.kind == .microphone {
                            Button {
                                Task {
                                    await coordinator.requestMicrophonePermission()
                                }
                            } label: {
                                Label("请求麦克风权限", systemImage: "mic.badge.plus")
                            }
                        }

                        Button {
                            openSettings(for: permission.kind)
                        } label: {
                            Label(permission.kind.recoveryActionTitle, systemImage: "gear")
                        }
                        .disabled(URL(string: permission.kind.settingsURLString) == nil)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func permissionTint(_ state: PermissionGrantState) -> Color {
        switch state {
        case .granted:
            .green
        case .notDetermined:
            .yellow
        case .denied, .restricted:
            .red
        case .unknown:
            .orange
        }
    }

    private func openSettings(for kind: PermissionKind) {
        guard let url = URL(string: kind.settingsURLString) else {
            coordinator.fail("无法打开系统设置：\(kind.title) 的链接无效")
            return
        }

        if !NSWorkspace.shared.open(url) {
            coordinator.fail("无法打开系统设置：\(kind.title)")
        }
    }
}
