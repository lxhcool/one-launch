import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var settingsStore: SettingsStore
    let onClose: () -> Void
    @State private var gridFrames: [String: GridDropFrameEntry] = [:]
    @State private var draggingAppID: String?
    @State private var draggingFolderID: String?
    @State private var draggingAppTranslation: CGSize = .zero
    @State private var draggingFolderTranslation: CGSize = .zero
    @State private var hoverGroupTarget: FolderDropTarget?
    @State private var reorderPosition: GridReorderPosition?
    @State private var folderNameDraft = ""
    @State private var draggingAppIDFromFolder: String?
    @State private var draggingAppFromFolderTranslation: CGSize = .zero
    @State private var folderPanelFrame: CGRect = .zero
    @State private var folderPanelAppFrames: [String: FolderPanelAppFrameEntry] = [:]
    @State private var folderPanelReorderPosition: FolderPanelReorderPosition?

    private var effectiveIconSize: Double {
        settingsStore.iconSize + 12
    }

    private var folderPanelIconSize: Double {
        min(effectiveIconSize, 80)
    }

    private var columns: [GridItem] {
        let size = effectiveIconSize
        let minimum = size + 44
        let maximum = size + 72
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16)]
    }

    private var contentMaxWidth: CGFloat {
        CGFloat(settingsStore.listContentWidth)
    }

    private var gridItemIDs: [String] {
        viewModel.gridItems.map(\.id)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayers(geometry: geometry)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.showSettings {
                            dismissSettings()
                        } else if viewModel.presentedFolder != nil {
                            viewModel.closeFolder()
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
                }
                .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 52)
                .padding(.top, max(geometry.safeAreaInsets.top + 26, 44))
                .padding(.bottom, 14)
                .opacity(viewModel.isPresented ? 1 : 0)
                .scaleEffect(viewModel.isPresented ? 1 : 0.92)

                topLeadingMeta(geometry: geometry)
                    .opacity(viewModel.isPresented ? 1 : 0)

                topTrailingActions(geometry: geometry)
                    .opacity(viewModel.isPresented ? 1 : 0)

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

                if let folder = viewModel.presentedFolder {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { viewModel.closeFolder() }

                    folderPanel(for: folder)
                }
            }
            .coordinateSpace(name: "launcherGridSpace")
            .onPreferenceChange(GridDropFramePreferenceKey.self) { entries in
                gridFrames = Dictionary(uniqueKeysWithValues: entries.map { ($0.itemID, $0) })
            }
            .onPreferenceChange(FolderPanelAppFramePreferenceKey.self) { entries in
                folderPanelAppFrames = Dictionary(uniqueKeysWithValues: entries.map { ($0.appID, $0) })
            }
            .onPreferenceChange(FolderPanelFramePreferenceKey.self) { frame in
                folderPanelFrame = frame
            }
            .onChange(of: viewModel.activeFolderID) { _, _ in
                if let folder = viewModel.presentedFolder {
                    folderNameDraft = folder.folder.name
                } else {
                    folderNameDraft = ""
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
        }
        .ignoresSafeArea()
        .background(Color.clear)
        .onExitCommand {
            if viewModel.showSettings {
                dismissSettings()
            } else if viewModel.presentedFolder != nil {
                viewModel.closeFolder()
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
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            searchBar

            if !viewModel.query.isEmpty {
                headerButton(systemImage: "xmark.circle", action: viewModel.clearSearch, helpText: "清空搜索")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 40)
        .padding(.horizontal, 8)
        .onTapGesture {}
    }

    private func topTrailingActions(geometry: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            headerButton(systemImage: "gearshape", action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showSettings.toggle()
                }
            }, helpText: "设置")
            headerButton(systemImage: "arrow.clockwise", action: viewModel.refreshApplications, helpText: "重新扫描应用")
            headerButton(systemImage: "xmark", action: onClose, helpText: "关闭")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 24)
        .padding(.top, max(geometry.safeAreaInsets.top + 24, 24))
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

                    // 底部空白区域也能点击关闭（ScrollView 否则会吞掉点击）
                    Color.clear
                        .frame(height: 320)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if viewModel.showSettings {
                                dismissSettings()
                            } else if viewModel.presentedFolder != nil {
                                viewModel.closeFolder()
                            } else {
                                onClose()
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var appGrid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(viewModel.gridItems) { item in
                switch item {
                case let .app(app):
                    appGridItem(for: app)
                case let .folder(folder):
                    folderGridItem(for: folder)
                }
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.86, blendDuration: 0.12), value: gridItemIDs)
    }

    private func appGridItem(for app: AppItem) -> some View {
        let target = FolderDropTarget.app(app.id)
        let isDragging = draggingAppID == app.id
        let isHoverTarget = hoverGroupTarget == target && draggingAppID != app.id
        let itemID = app.id

        return AppCardView(app: app, iconSize: effectiveIconSize) {
            onClose()
            viewModel.launch(app)
        }
        .overlay {
            itemChromeOverlay(isHoverTarget: isHoverTarget, itemID: itemID)
        }
        .offset(isDragging ? draggingAppTranslation : .zero)
        .scaleEffect(isDragging ? 1.04 : 1)
        .opacity(isDragging ? 0.92 : 1)
        .zIndex(isDragging ? 10 : 0)
        .highPriorityGesture(dragGesture(for: app.id))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GridDropFramePreferenceKey.self,
                    value: [
                        GridDropFrameEntry(
                            itemID: itemID,
                            target: target,
                            frame: proxy.frame(in: .named("launcherGridSpace"))
                        )
                    ]
                )
            }
        )
    }

    private func folderGridItem(for folder: FolderDisplay) -> some View {
        let target = FolderDropTarget.folder(folder.id)
        let isDragging = draggingFolderID == folder.id
        let isHoverTarget = hoverGroupTarget == target && draggingFolderID != folder.id
        let itemID = "folder:\(folder.id)"

        return FolderCardView(
            folder: folder.folder,
            apps: folder.apps,
            iconSize: effectiveIconSize,
            onOpenFolder: { viewModel.openFolder(folder.id) },
            onLaunchApp: { app in
                onClose()
                viewModel.launch(app)
            }
        )
        .overlay {
            itemChromeOverlay(isHoverTarget: isHoverTarget, itemID: itemID)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GridDropFramePreferenceKey.self,
                    value: [
                        GridDropFrameEntry(
                            itemID: itemID,
                            target: target,
                            frame: proxy.frame(in: .named("launcherGridSpace"))
                        )
                    ]
                )
            }
        )
        .offset(isDragging ? draggingFolderTranslation : .zero)
        .scaleEffect(isDragging ? 1.04 : 1)
        .opacity(isDragging ? 0.92 : 1)
        .zIndex(isDragging ? 10 : 0)
        .highPriorityGesture(folderDragGesture(for: folder.id))
        .contextMenu {
            Button("解散文件夹") {
                viewModel.dissolveFolder(folder.id)
            }
        }
    }

    private func dragGesture(for appID: String) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard draggingFolderID == nil else { return }

                if draggingAppID == nil {
                    draggingAppID = appID
                }
                guard draggingAppID == appID else { return }

                draggingAppTranslation = value.translation
                let sourceItemID = appID
                hoverGroupTarget = groupTarget(at: value.location, excludingItemID: sourceItemID)
                reorderPosition = hoverGroupTarget == nil
                    ? reorderTarget(at: value.location, excludingItemID: sourceItemID)
                    : nil
            }
            .onEnded { value in
                guard !viewModel.isSearching else { return }
                guard draggingAppID == appID else { return }

                let sourceItemID = appID
                let target = groupTarget(at: value.location, excludingItemID: sourceItemID) ?? hoverGroupTarget
                let reorder = reorderTarget(at: value.location, excludingItemID: sourceItemID) ?? reorderPosition

                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84, blendDuration: 0.12)) {
                    if let target {
                        viewModel.groupApp(sourceID: appID, onto: target)
                    } else if let reorder {
                        viewModel.moveGridItem(sourceItemID: sourceItemID, relativeTo: reorder.targetItemID, placeAfter: reorder.placeAfter)
                    }

                    draggingAppID = nil
                    draggingAppTranslation = .zero
                    hoverGroupTarget = nil
                    reorderPosition = nil
                }
            }
    }

    private func folderDragGesture(for folderID: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard draggingAppID == nil else { return }

                if draggingFolderID == nil {
                    draggingFolderID = folderID
                }
                guard draggingFolderID == folderID else { return }

                draggingFolderTranslation = value.translation
                hoverGroupTarget = nil
                reorderPosition = reorderTarget(at: value.location, excludingItemID: "folder:\(folderID)")
            }
            .onEnded { value in
                guard !viewModel.isSearching else { return }
                guard draggingFolderID == folderID else { return }

                let sourceItemID = "folder:\(folderID)"
                let reorder = reorderTarget(at: value.location, excludingItemID: sourceItemID) ?? reorderPosition

                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84, blendDuration: 0.12)) {
                    if let reorder {
                        viewModel.moveGridItem(sourceItemID: sourceItemID, relativeTo: reorder.targetItemID, placeAfter: reorder.placeAfter)
                    }

                    draggingFolderID = nil
                    draggingFolderTranslation = .zero
                    hoverGroupTarget = nil
                    reorderPosition = nil
                }
            }
    }

    private func groupTarget(at point: CGPoint, excludingItemID excludedItemID: String) -> FolderDropTarget? {
        let candidates = gridFrames.values.filter { entry in
            entry.itemID != excludedItemID && groupingFrame(for: entry.frame).contains(point)
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            return lhsArea < rhsArea
        }

        return sortedCandidates.first?.target
    }

    private func reorderTarget(at point: CGPoint, excludingItemID excludedItemID: String) -> GridReorderPosition? {
        let orderedEntries = viewModel.gridItems.compactMap { item in
            let entry = gridFrames[item.id]
            return entry?.itemID == excludedItemID ? nil : entry
        }

        guard let nearest = orderedEntries.min(by: {
            distanceSquared(from: point, to: CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                < distanceSquared(from: point, to: CGPoint(x: $1.frame.midX, y: $1.frame.midY))
        }) else {
            return nil
        }

        let useVerticalDecision = abs(point.y - nearest.frame.midY) > nearest.frame.height * 0.35
        let placeAfter = useVerticalDecision ? point.y > nearest.frame.midY : point.x > nearest.frame.midX
        return GridReorderPosition(targetItemID: nearest.itemID, placeAfter: placeAfter)
    }

    private func groupingFrame(for frame: CGRect) -> CGRect {
        frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18)
    }

    private func distanceSquared(from point: CGPoint, to target: CGPoint) -> CGFloat {
        let dx = point.x - target.x
        let dy = point.y - target.y
        return dx * dx + dy * dy
    }

    @ViewBuilder
    private func itemChromeOverlay(isHoverTarget: Bool, itemID: String) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isHoverTarget ? Color.white.opacity(0.78) : Color.clear, lineWidth: 2)
            .padding(4)

        if let reorderPosition, reorderPosition.targetItemID == itemID, hoverGroupTarget == nil {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: 4)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: reorderPosition.placeAfter ? .trailing : .leading)
                .shadow(color: .white.opacity(0.35), radius: 8)
                .padding(reorderPosition.placeAfter ? .trailing : .leading, 1)
        }
    }

    private func folderPanel(for folder: FolderDisplay) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                folderHeroPreview(for: folder)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("文件夹名称", text: Binding(
                        get: { folderNameDraft },
                        set: { folderNameDraft = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .onSubmit {
                        commitFolderName(for: folder.id)
                    }

                    HStack(spacing: 10) {
                        folderInfoBadge(systemImage: "square.grid.2x2", title: "\(folder.apps.count) 个应用")
                        folderInfoBadge(systemImage: "slider.horizontal.3", title: "支持自定义名称")
                    }

                    Text("打开常用应用、统一整理分组，拖拽排序后会保留当前位置。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        viewModel.dissolveFolder(folder.id)
                    } label: {
                        Label("解散", systemImage: "folder.badge.minus")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    Button {
                        commitFolderName(for: folder.id)
                        viewModel.closeFolder()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("文件夹内应用")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("点击即可打开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    let size = folderPanelIconSize
                    let minimum = size + 44
                    let maximum = size + 72
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16)], spacing: 16) {
                        ForEach(folder.apps) { app in
                            folderAppCard(app: app, folder: folder)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(26)
        .frame(width: 760, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        .onAppear {
            folderNameDraft = folder.folder.name
        }
        .onTapGesture {}
        .modifier(FolderPanelFramePreferenceSetter())
    }

    private func folderAppCard(app: AppItem, folder: FolderDisplay) -> some View {
        let isDragging = draggingAppIDFromFolder == app.id
        let itemID = app.id

        return AppCardView(app: app, iconSize: folderPanelIconSize) {
            commitFolderName(for: folder.id)
            viewModel.closeFolder()
            onClose()
            viewModel.launch(app)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .offset(isDragging ? draggingAppFromFolderTranslation : .zero)
        .scaleEffect(isDragging ? 1.05 : 1)
        .opacity(isDragging ? 0.9 : 1)
        .zIndex(isDragging ? 10 : 0)
        .highPriorityGesture(folderAppDragGesture(appID: app.id, folderID: folder.id))
        .help("拖到面板外可移出文件夹")
        .overlay {
            if let folderPanelReorderPosition, folderPanelReorderPosition.targetAppID == itemID {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(height: 4)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity, alignment: folderPanelReorderPosition.placeAfter ? .bottom : .top)
                    .shadow(color: .white.opacity(0.35), radius: 8)
                    .padding(folderPanelReorderPosition.placeAfter ? .bottom : .top, 2)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FolderPanelAppFramePreferenceKey.self,
                    value: [
                        FolderPanelAppFrameEntry(
                            appID: itemID,
                            frame: proxy.frame(in: .named("launcherGridSpace"))
                        )
                    ]
                )
            }
        )
    }

    private func folderAppDragGesture(appID: String, folderID: String) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                if draggingAppIDFromFolder == nil {
                    draggingAppIDFromFolder = appID
                }
                guard draggingAppIDFromFolder == appID else { return }
                draggingAppFromFolderTranslation = value.translation

                // 文件夹内拖拽排序
                guard folderPanelFrame != .zero else { return }
                if folderPanelFrame.contains(value.location) {
                    folderPanelReorderPosition = folderPanelReorderTarget(
                        at: value.location,
                        excludingAppID: appID
                    )
                } else {
                    folderPanelReorderPosition = nil
                }
            }
            .onEnded { value in
                guard draggingAppIDFromFolder == appID else { return }

                let endLocation = CGPoint(
                    x: value.startLocation.x + value.translation.width,
                    y: value.startLocation.y + value.translation.height
                )
                let isOutsidePanel = folderPanelFrame != .zero && !folderPanelFrame.contains(endLocation)

                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84, blendDuration: 0.12)) {
                    if let folderPanelReorderPosition, !isOutsidePanel {
                        viewModel.moveAppInFolder(
                            folderID: folderID,
                            sourceAppID: appID,
                            relativeTo: folderPanelReorderPosition.targetAppID,
                            placeAfter: folderPanelReorderPosition.placeAfter
                        )
                    } else if isOutsidePanel {
                        viewModel.removeAppFromFolder(appID: appID, folderID: folderID)
                    }
                    draggingAppIDFromFolder = nil
                    draggingAppFromFolderTranslation = .zero
                    folderPanelReorderPosition = nil
                }
            }
    }

    private func folderPanelReorderTarget(at point: CGPoint, excludingAppID excludedAppID: String) -> FolderPanelReorderPosition? {
        let entries = folderPanelAppFrames.values.filter { $0.appID != excludedAppID }
        guard let nearest = entries.min(by: {
            distanceSquared(from: point, to: CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                < distanceSquared(from: point, to: CGPoint(x: $1.frame.midX, y: $1.frame.midY))
        }) else {
            return nil
        }

        let useVerticalDecision = abs(point.y - nearest.frame.midY) > nearest.frame.height * 0.35
        let placeAfter = useVerticalDecision ? point.y > nearest.frame.midY : point.x > nearest.frame.midX
        return FolderPanelReorderPosition(targetAppID: nearest.appID, placeAfter: placeAfter)
    }

    private func commitFolderName(for folderID: String) {
        viewModel.renameFolder(folderID, to: folderNameDraft)
        if let folder = viewModel.presentedFolder, folder.id == folderID {
            folderNameDraft = folder.folder.name
        }
    }

    private func folderHeroPreview(for folder: FolderDisplay) -> some View {
        let heroSize: Double = 124
        let gap: Double = 8
        let tileSize: Double = 42

        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if folder.apps.indices.contains(index) {
                                Image(nsImage: AppIconProvider.shared.icon(for: folder.apps[index]))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: tileSize, height: tileSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                Color.clear
                                    .frame(width: tileSize, height: tileSize)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: heroSize, height: heroSize)
    }

    private func folderInfoBadge(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func spotlightCard(for app: AppItem) -> some View {
        Button {
            onClose()
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

    private var hintsRow: some View {
        HStack(spacing: 14) {
            footerHint(systemImage: "cursorarrow.motionlines", title: "拖拽排序 / 叠放分组")
            footerHint(systemImage: "command", title: "⌥ Space 快速呼出")
            footerHint(systemImage: "sparkles", title: "搜索 + 网格双模式")
        }
        .onTapGesture {}
    }

    private func topLeadingMeta(geometry: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            actionBadge(title: viewModel.subtitleText)
            actionBadge(title: "⌥ Space")
            hintsRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 24)
        .padding(.top, max(geometry.safeAreaInsets.top + 24, 24))
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
                onCommit: {
                    onClose()
                    viewModel.launchFirstResult()
                }
            )
        }
        .padding(.horizontal, 20)
        .frame(width: 600, height: 58)
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

private struct GridDropFrameEntry: Equatable {
    let itemID: String
    let target: FolderDropTarget
    let frame: CGRect
}

private struct GridReorderPosition: Equatable {
    let targetItemID: String
    let placeAfter: Bool
}

private struct GridDropFramePreferenceKey: PreferenceKey {
    static let defaultValue: [GridDropFrameEntry] = []

    static func reduce(value: inout [GridDropFrameEntry], nextValue: () -> [GridDropFrameEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FolderPanelAppFrameEntry: Equatable {
    let appID: String
    let frame: CGRect
}

private struct FolderPanelReorderPosition: Equatable {
    let targetAppID: String
    let placeAfter: Bool
}

private struct FolderPanelAppFramePreferenceKey: PreferenceKey {
    static let defaultValue: [FolderPanelAppFrameEntry] = []
    static func reduce(value: inout [FolderPanelAppFrameEntry], nextValue: () -> [FolderPanelAppFrameEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FolderPanelFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct FolderPanelFramePreferenceSetter: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FolderPanelFramePreferenceKey.self,
                    value: proxy.frame(in: .named("launcherGridSpace"))
                )
            }
        )
    }
}
