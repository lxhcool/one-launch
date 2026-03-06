import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("设置")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            iconSizeSection

            Divider().overlay(Color.white.opacity(0.1))

            sortModeSection

            Divider().overlay(Color.white.opacity(0.1))

            backgroundSection

            Divider().overlay(Color.white.opacity(0.1))

            launchAtLoginSection

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("恢复默认设置") {
                    settingsStore.resetToDefaults()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(28)
        .frame(width: 420, height: 580)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .onTapGesture {}
    }

    private var iconSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("图标大小")

            HStack(spacing: 16) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Slider(value: $settingsStore.iconSize, in: 48...96, step: 4)
                    .tint(.white.opacity(0.6))

                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)

                Text("\(Int(settingsStore.iconSize))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private var sortModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("排序方式")

            HStack(spacing: 8) {
                ForEach(SortMode.allCases, id: \.rawValue) { mode in
                    Button {
                        settingsStore.sortMode = mode
                    } label: {
                        Text(mode.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(settingsStore.sortMode == mode ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                settingsStore.sortMode == mode
                                    ? Color.white.opacity(0.18)
                                    : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    settingsStore.sortMode == mode
                                        ? Color.white.opacity(0.25)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("背景图片")

            HStack(spacing: 12) {
                if let path = settingsStore.backgroundImagePath,
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 80, height: 50)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button("选择图片") {
                        pickBackgroundImage()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1), in: Capsule())

                    if settingsStore.backgroundImagePath != nil {
                        Button("移除背景") {
                            settingsStore.backgroundImagePath = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var launchAtLoginSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("开机自动启动")
                Text("登录时自动在后台运行 OneLaunch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $settingsStore.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.accentColor)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func pickBackgroundImage() {
        guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else {
            return
        }

        let originalLevel = window.level
        window.level = .normal

        let panel = NSOpenPanel()
        panel.title = "选择背景图片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                settingsStore.backgroundImagePath = url.path
            }
            window.level = originalLevel
            window.makeKeyAndOrderFront(nil)
        }
    }
}
