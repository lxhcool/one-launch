import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onClose: () -> Void
    @State private var newCategoryName = ""

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
                    categorySection
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

    private var categorySection: some View {
        SettingsCard(title: "分类", icon: "folder.badge.plus") {
            VStack(alignment: .leading, spacing: 16) {
                categoryPositionArea

                Divider().overlay(Color.white.opacity(0.06))

                // 新增分类区域
                addCategoryArea

                Divider().overlay(Color.white.opacity(0.06))
                systemCategoryList

                if settingsStore.customCategories.isEmpty {
                    Divider().overlay(Color.white.opacity(0.06))
                    emptyCategoryState
                } else {
                    Divider().overlay(Color.white.opacity(0.06))
                    categoryList
                }
            }
        }
    }

    private var categoryPositionArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("分类栏位置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(CategoryBarPosition.allCases, id: \.rawValue) { position in
                    Button {
                        settingsStore.categoryBarPosition = position
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: position.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(position.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(settingsStore.categoryBarPosition == position ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    settingsStore.categoryBarPosition == position
                                        ? Color.accentColor.opacity(0.85)
                                        : Color.white.opacity(0.06)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    settingsStore.categoryBarPosition == position
                                        ? Color.accentColor.opacity(0.45)
                                        : Color.white.opacity(0.09),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var systemCategoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("系统分类排序")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("左侧列表也会同步")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(settingsStore.orderedSystemCategories.enumerated()), id: \.element.rawValue) { index, category in
                    SystemCategoryOrderRow(
                        category: category,
                        isFirstMovable: index <= 1,
                        isLastMovable: index == settingsStore.orderedSystemCategories.count - 1,
                        onMoveUp: { settingsStore.moveSystemCategoryUp(category) },
                        onMoveDown: { settingsStore.moveSystemCategoryDown(category) }
                    )
                }
            }
        }
    }

    private var addCategoryArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("新建分类")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("输入分类名称", text: $newCategoryName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .onSubmit { addCustomCategory() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(newCategoryName.isEmpty ? 0.08 : 0.2), lineWidth: 1)
                        )
                )

                Button {
                    addCustomCategory()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(CategoryAddButtonStyle())
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))

                Text("创建后可在应用上右键选择分类，或拖拽应用到左侧分类栏")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
    }

    private var emptyCategoryState: some View {
        HStack(spacing: 10) {
            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))

                Text("暂无自定义分类")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("添加后会显示在左侧分类栏")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.vertical, 20)

            Spacer()
        }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("我的分类 (\(settingsStore.customCategories.count)个)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("点击箭头排序")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(settingsStore.customCategories.enumerated()), id: \.element.id) { index, category in
                    CategoryListRow(
                        category: category,
                        isFirst: index == 0,
                        isLast: index == settingsStore.customCategories.count - 1,
                        onRename: { newName in
                            settingsStore.renameCustomCategory(category.id, to: newName)
                        },
                        onMoveUp: {
                            settingsStore.moveCustomCategoryUp(category.id)
                        },
                        onMoveDown: {
                            settingsStore.moveCustomCategoryDown(category.id)
                        },
                        onDelete: {
                            settingsStore.deleteCustomCategory(category.id)
                        }
                    )
                }
            }
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

    private func addCustomCategory() {
        if settingsStore.addCustomCategory(named: newCategoryName) != nil {
            newCategoryName = ""
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

struct CategoryAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SystemCategoryOrderRow: View {
    let category: AppCategory
    let isFirstMovable: Bool
    let isLastMovable: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text(category.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if category == .all {
                Text("固定")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                    )
            } else {
                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(CategoryActionButtonStyle())
                    .disabled(isFirstMovable)

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(CategoryActionButtonStyle())
                    .disabled(isLastMovable)
                }
                .opacity(isHovered ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CategoryListRow: View {
    let category: CustomCategory
    let isFirst: Bool
    let isLast: Bool
    let onRename: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editName: String = ""

    var body: some View {
        HStack(spacing: 10) {
            // 分类图标
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: "tag.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            // 分类名称
            if isEditing {
                TextField("分类名称", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit {
                        onRename(editName)
                        isEditing = false
                    }
                    .onAppear {
                        editName = category.name
                    }
            } else {
                Text(category.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // 应用数量
            HStack(spacing: 3) {
                Image(systemName: "app.fill")
                    .font(.system(size: 8))
                Text("\(category.appIDs.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )

            // 操作按钮
            HStack(spacing: 4) {
                Menu {
                    Button("上移", action: onMoveUp)
                        .disabled(isFirst)
                    Button("下移", action: onMoveDown)
                        .disabled(isLast)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.button)
                .buttonStyle(CategoryActionButtonStyle())

                Button {
                    isEditing = true
                    editName = category.name
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(CategoryActionButtonStyle())
                .opacity(isHovered ? 1 : 0.25)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(CategoryDeleteButtonStyle())
                .opacity(isHovered ? 1 : 0.25)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.1 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CategoryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CategoryDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.red.opacity(0.8))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
