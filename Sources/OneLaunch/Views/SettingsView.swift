import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("设置", systemImage: "gearshape.2")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    appearanceSection
                    layoutSection
                    behaviorSection
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 420, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 40, x: 0, y: 12)
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        SettingsCard(title: "外观", icon: "paintbrush") {
            VStack(spacing: 20) {
                // Icon Size
                SettingsRow(icon: "square.grid.2x2", title: "图标大小") {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        CustomSlider(
                            value: $settingsStore.iconSize,
                            range: 56...112,
                            step: 4
                        )
                        .frame(width: 120)

                        Image(systemName: "app.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)

                        Text("\(Int(settingsStore.iconSize))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                Divider().overlay(Color.white.opacity(0.06))

                // Background Image
                SettingsRow(icon: "photo", title: "背景图片") {
                    Button("选择") {
                        pickBackgroundImage()
                    }
                    .buttonStyle(SettingsButtonStyle())
                }

                if settingsStore.backgroundImagePath != nil {
                    backgroundPreview
                }

                if settingsStore.backgroundImagePath != nil {
                    Divider().overlay(Color.white.opacity(0.06))

                    // Blur Radius
                    SettingsRow(icon: "drop.fill", title: "模糊程度") {
                        HStack(spacing: 12) {
                            CustomSlider(
                                value: $settingsStore.backgroundBlurRadius,
                                range: 0...36,
                                step: 1
                            )
                            .frame(width: 120)

                            Text("\(Int(settingsStore.backgroundBlurRadius))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var backgroundPreview: some View {
        HStack(spacing: 12) {
            if let path = settingsStore.backgroundImagePath,
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("已设置自定义背景")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("移除") {
                    settingsStore.clearBackgroundImage()
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red.opacity(0.8))
            }

            Spacer()
        }
        .padding(.leading, 28)
    }

    private var layoutSection: some View {
        SettingsCard(title: "布局", icon: "rectangle.split.2x1") {
            VStack(spacing: 20) {
                // List Width
                SettingsRow(icon: "arrow.left.arrow.right", title: "列表宽度") {
                    HStack(spacing: 12) {
                        CustomSlider(
                            value: $settingsStore.listContentWidth,
                            range: 1180...1720,
                            step: 20
                        )
                        .frame(width: 140)

                        Text("\(Int(settingsStore.listContentWidth))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Divider().overlay(Color.white.opacity(0.06))

                // Sort Mode
                SettingsRow(icon: "arrow.up.arrow.down", title: "排序方式") {
                    Menu {
                        ForEach(SortMode.allCases, id: \.rawValue) { mode in
                            Button {
                                settingsStore.sortMode = mode
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                    if settingsStore.sortMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(settingsStore.sortMode.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard(title: "行为", icon: "gear") {
            SettingsRow(icon: "power", title: "开机自动启动") {
                Toggle("", isOn: $settingsStore.launchAtLogin)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
            }

            Text("登录时自动在后台运行 OneLaunch")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            .padding(.leading, 28)
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "关于", icon: "info.circle") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OneLaunch")
                            .font(.system(size: 14, weight: .semibold))
                        Text("版本 1.0")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("恢复默认") {
                        settingsStore.resetToDefaults()
                    }
                    .buttonStyle(SettingsButtonStyle())
                }

                Text("快捷键 ⌥ Space 快速呼出")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28)
            }
        }
    }

    // MARK: - Helper Methods

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
                settingsStore.setBackgroundImage(from: url)
            }
            window.level = originalLevel
            window.makeKeyAndOrderFront(nil)
        }
    }

}

// MARK: - Subviews

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // Card Content
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            content
        }
    }
}

struct CustomSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.allowsTickMarkValuesOnly = false
        slider.numberOfTickMarks = 0
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.isContinuous = true

        // 自定义样式
        slider.appearance = NSAppearance(named: .aqua)

        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = value
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, step: step)
    }

    class Coordinator: NSObject {
        @Binding var value: Double
        let step: Double

        init(value: Binding<Double>, step: Double) {
            self._value = value
            self.step = step
        }

        @MainActor @objc func valueChanged(_ sender: NSSlider) {
            // 应用步长
            let rawValue = sender.doubleValue
            let steppedValue = round((rawValue - sender.minValue) / step) * step + sender.minValue
            value = steppedValue
        }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
