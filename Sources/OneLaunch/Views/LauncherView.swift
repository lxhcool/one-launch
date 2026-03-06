import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let onClose: () -> Void

    private var settingsStore: SettingsStore {
        viewModel.settingsStore
    }

    private var columns: [GridItem] {
        let size = settingsStore.iconSize
        let minimum = size + 44
        let maximum = size + 72
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16)]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayers(geometry: geometry)
                    .opacity(viewModel.isPresented ? 1 : 0)
                    .scaleEffect(viewModel.isPresented ? 1 : 1.08)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.showSettings {
                            dismissSettings()
                        } else {
                            onClose()
                        }
                    }

                VStack(spacing: 28) {
                    header

                    if let spotlightResult = viewModel.spotlightResult {
                        spotlightCard(for: spotlightResult)
                    }

                    content

                    footer
                }
                .frame(maxWidth: 1320, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 52)
                .padding(.top, max(geometry.safeAreaInsets.top + 26, 44))
                .padding(.bottom, 30)
                .opacity(viewModel.isPresented ? 1 : 0)
                .scaleEffect(viewModel.isPresented ? 1 : 0.92)

                Color.black.opacity(viewModel.showSettings ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismissSettings() }
                    .allowsHitTesting(viewModel.showSettings)

                SettingsView(settingsStore: settingsStore) {
                    dismissSettings()
                }
                .opacity(viewModel.showSettings ? 1 : 0)
                .scaleEffect(viewModel.showSettings ? 1 : 0.95)
                .allowsHitTesting(viewModel.showSettings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
        }
        .ignoresSafeArea()
        .background(Color.clear)
        .onExitCommand {
            if viewModel.showSettings {
                dismissSettings()
            } else {
                onClose()
            }
        }
    }

    private func dismissSettings() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.showSettings = false
        }
    }

    private func backgroundLayers(geometry: GeometryProxy) -> some View {
        ZStack {
            if let nsImage = settingsStore.backgroundImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)

                Color.black.opacity(0.15)
            } else {
                VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            backgroundAccent(geometry: geometry)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                actionBadge(title: viewModel.subtitleText)
                actionBadge(title: "⌥ Space")

                Spacer()

                headerButton(systemImage: "gearshape", action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showSettings.toggle()
                    }
                }, helpText: "设置")
                headerButton(systemImage: "arrow.clockwise", action: viewModel.refreshApplications, helpText: "重新扫描应用")
                headerButton(systemImage: "xmark", action: onClose, helpText: "关闭")
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                searchBar

                if !viewModel.query.isEmpty {
                    headerButton(systemImage: "xmark.circle", action: viewModel.clearSearch, helpText: "清空搜索")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .onTapGesture {}
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.filteredApps.isEmpty {
            ContentUnavailableView(
                "没有找到应用",
                systemImage: "magnifyingglass",
                description: Text(viewModel.isRefreshing ? "正在扫描应用目录" : "换个关键词试试，或者重新扫描应用")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ScrollViewConfigurator()
                        .frame(width: 0, height: 0)

                    appGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var appGrid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(viewModel.gridApps) { app in
                AppCardView(app: app, iconSize: settingsStore.iconSize) {
                    viewModel.launch(app)
                }
            }
            .onMove { source, destination in
                viewModel.moveApps(from: source, to: destination)
            }
        }
        .padding(24)
        .drawingGroup()
    }

    private func spotlightCard(for app: AppItem) -> some View {
        Button {
            viewModel.launch(app)
        } label: {
            HStack(spacing: 18) {
                Image(nsImage: AppIconProvider.shared.icon(for: app))
                    .resizable()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("最佳匹配")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(app.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(app.bundleIdentifier ?? app.url.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("回车启动")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(panelFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onTapGesture {}
    }

    private var footer: some View {
        HStack(spacing: 14) {
            footerHint(systemImage: "cursorarrow.motionlines", title: "点空白区域关闭")
            footerHint(systemImage: "command", title: "⌥ Space 快速呼出")
            footerHint(systemImage: "sparkles", title: "搜索 + 网格双模式")
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {}
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            SearchField(
                text: $viewModel.query,
                shouldFocus: $viewModel.shouldFocusSearchField,
                placeholder: "搜索应用",
                onCommit: viewModel.launchFirstResult
            )
        }
        .padding(.horizontal, 20)
        .frame(width: 500, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func actionBadge(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func headerButton(systemImage: String, action: @escaping () -> Void, helpText: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func footerHint(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func backgroundAccent(geometry: GeometryProxy) -> some View {
        ZStack {
            RadialGradient(
                colors: [Color.accentColor.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: min(geometry.size.width, geometry.size.height) * 0.65
            )

            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: min(geometry.size.width, geometry.size.height) * 0.55
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var panelFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.10),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
