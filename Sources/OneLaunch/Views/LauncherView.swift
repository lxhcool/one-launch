import AppKit
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
    @State private var pageOffset: CGFloat = 0
    @State private var scrollEventMonitor: Any?
    @State private var accumulatedHorizontalScroll: CGFloat = 0
    @State private var shouldRenderAdjacentPages = false
    @State private var adjacentPagesWorkItem: DispatchWorkItem?

    private var effectiveIconSize: Double {
        settingsStore.iconSize + 12
    }

    private var folderPanelIconSize: Double {
        min(effectiveIconSize, 80)
    }

    private var columns: [GridItem] {
        let size = effectiveIconSize
        let minimum = size + 52
        let maximum = size + 84
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 20)]
    }

    private var pinnedColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: 132), spacing: 14),
            GridItem(.flexible(minimum: 0, maximum: 132), spacing: 14)
        ]
    }

    private var pinnedSidebarWidth: CGFloat {
        272
    }

    private var contentSectionsSpacing: CGFloat {
        viewModel.pinnedApps.isEmpty ? 0 : 28
    }

    private var contentWidthBoost: CGFloat {
        96
    }

    private var contentBottomInset: CGFloat {
        72
    }

    private var contentMaxWidth: CGFloat {
        CGFloat(settingsStore.listContentWidth)
            + contentWidthBoost
            + (viewModel.pinnedApps.isEmpty ? 0 : pinnedSidebarWidth + contentSectionsSpacing)
    }

    private var adaptiveColorScheme: ColorScheme {
        settingsStore.backgroundIsDark ? .dark : .light
    }

    private var headerElementsVisible: Bool {
        settingsStore.showDateTime || settingsStore.showSearchBar
    }

    private var pageTransitionAnimation: Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.24)
    }

    private var renderedPageDistance: Int {
        shouldRenderAdjacentPages ? 1 : 0
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
                            dismissFolder()
                        } else {
                            onClose()
                        }
                    }

                VStack(spacing: 24) {
                    if headerElementsVisible {
                        header
                    }

                    content
                }
                .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 52)
                .padding(.top, max(geometry.safeAreaInsets.top + 16, 32))
                .padding(.bottom, contentBottomInset)
                .scaleEffect(viewModel.scale)

                topLeadingMeta(geometry: geometry)

                topTrailingActions(geometry: geometry)

                // 搜索面板 - 悬浮在最上层，不影响网格布局
                if viewModel.isSearching && !viewModel.searchResults.isEmpty {
                    searchResultsPanel
                        .position(
                            x: geometry.size.width / 2,
                            y: max(geometry.safeAreaInsets.top + 16, 32) + 16 + 80 + 20 + 52 + 16 + 180 + 12
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        .animation(.easeOut(duration: 0.2), value: viewModel.isSearching)
                        .zIndex(100)
                }

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

                // 文件夹弹窗 — 与设置面板相同的动画交互
                let folderIsOpen = viewModel.presentedFolder != nil
                Color.black.opacity(folderIsOpen ? 0.35 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismissFolder() }
                    .allowsHitTesting(folderIsOpen)

                if let folder = viewModel.presentedFolder {
                    folderPanel(for: folder)
                        .opacity(folderIsOpen ? 1 : 0)
                        .scaleEffect(folderIsOpen ? 1 : 0.95)
                        .allowsHitTesting(folderIsOpen)
                }
            }
            .coordinateSpace(name: "launcherGridSpace")
            .onChange(of: viewModel.activeFolderID) { _, _ in
                if let folder = viewModel.presentedFolder {
                    folderNameDraft = folder.folder.name
                } else {
                    folderNameDraft = ""
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
            .animation(.easeInOut(duration: 0.2), value: viewModel.activeFolderID)
        }
        .ignoresSafeArea()
        .background(Color.clear)
        .onAppear {
            installTrackpadMonitorIfNeeded()
            updateAdjacentPageRendering(for: viewModel.isPresented)
        }
        .onDisappear {
            adjacentPagesWorkItem?.cancel()
            adjacentPagesWorkItem = nil
            removeTrackpadMonitor()
        }
        .onChange(of: viewModel.isPresented) { _, isPresented in
            updateAdjacentPageRendering(for: isPresented)
        }
        .onExitCommand {
            if viewModel.showSettings {
                dismissSettings()
            } else if viewModel.presentedFolder != nil {
                dismissFolder()
            } else {
                onClose()
            }
        }
        .environment(\.colorScheme, adaptiveColorScheme)
    }

    private func dismissSettings() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.showSettings = false
        }
    }

    private func dismissFolder() {
        withAnimation(.easeInOut(duration: 0.2)) {
            commitFolderNameIfNeeded()
            viewModel.closeFolder()
        }
    }

    private func commitFolderNameIfNeeded() {
        if let folder = viewModel.presentedFolder {
            commitFolderName(for: folder.id)
        }
    }

    private func backgroundLayers(geometry: GeometryProxy) -> some View {
        ZStack {
            if viewModel.isPanelTransitioning {
                if let nsImage = settingsStore.backgroundBlurImage ?? settingsStore.backgroundImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(0.92)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.20),
                            Color.black.opacity(0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color.black.opacity(0.32)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            } else {
                if let nsImage = settingsStore.backgroundBlurImage ?? settingsStore.backgroundImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    // 更接近 macOS Launchpad 的透感：高斯底图 + 轻微层次渐变
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
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

                    backgroundAccent(geometry: geometry)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 18) {
            if settingsStore.showDateTime {
                // 时间日期显示
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 6) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 12, y: 3)
                            .contentTransition(.numericText())

                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .tracking(0.5)
                    }
                }
                .onTapGesture {}
            }

            if settingsStore.showSearchBar {
                searchBar
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, 8)
        .onTapGesture {}
    }

    @State private var hoveredButton: String? = nil

    private func topTrailingActions(geometry: GeometryProxy) -> some View {
        HStack(spacing: 1) {
            ForEach(Array([
                ("gearshape", { viewModel.showSettings.toggle() }, "设置"),
                ("xmark", { onClose() }, "关闭")
            ].enumerated()), id: \.offset) { index, item in
                let (icon, action, help) = item
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            Color.white.opacity(hoveredButton == icon ? 0.12 : 0.0)
                        )
                }
                .buttonStyle(.plain)
                .help(help)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredButton = hovering ? icon : nil
                    }
                }

                if index < 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.5, height: 18)
                }
            }
        }
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
        )
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 20)
        .padding(.top, max(geometry.safeAreaInsets.top + 20, 20))
        .onTapGesture {}
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.gridApps.isEmpty {
            ContentUnavailableView(
                "没有找到应用",
                systemImage: "magnifyingglass",
                description: Text(viewModel.isRefreshing ? "正在扫描应用目录" : "换个关键词试试")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { contentGeo in
                if viewModel.gridItems.isEmpty && viewModel.pinnedApps.isEmpty {
                    ContentUnavailableView(
                        "该分类暂无应用",
                        systemImage: "square.grid.2x2",
                        description: Text("试试切换到其他分类")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if settingsStore.showPinnedBar && !viewModel.pinnedApps.isEmpty {
                            pinnedAppsSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if viewModel.gridItems.isEmpty {
                            ContentUnavailableView(
                                "该分类暂无应用",
                                systemImage: "square.grid.2x2",
                                description: Text("试试切换到其他分类")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 0) {
                                    LazyVGrid(columns: columns, spacing: 22) {
                                        ForEach(viewModel.gridItems) { item in
                                            switch item {
                                            case let .app(app):
                                                appGridItem(for: app)
                                            case let .folder(folder):
                                                folderGridItem(for: folder)
                                            }
                                        }
                                    }
                                    .padding(.top, 8)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 16)

                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if viewModel.showSettings {
                                                dismissSettings()
                                            } else if viewModel.presentedFolder != nil {
                                                dismissFolder()
                                            } else {
                                                onClose()
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }
                            .onPreferenceChange(GridDropFramePreferenceKey.self) { entries in
                                var frames: [String: GridDropFrameEntry] = [:]
                                for entry in entries {
                                    frames[entry.itemID] = entry
                                }
                                gridFrames = frames
                            }
                        }
                    }
                    .frame(width: contentGeo.size.width, height: contentGeo.size.height, alignment: .topLeading)
                }
            }
        }
    }

    private var pinnedAppsSection: some View {
        let pinnedIconSize = max(36, min(settingsStore.iconSize - 8, 48))

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.pinnedApps) { app in
                    compactPinnedAppItem(for: app, iconSize: pinnedIconSize)
                        .contextMenu {
                            customAppContextMenu(for: app)
                        }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 34)
    }

    private func compactPinnedAppItem(for app: AppItem, iconSize: Double) -> some View {
        PinnedAppButton(app: app, iconSize: iconSize) {
            onClose()
            viewModel.launch(app)
        }
    }
    private var canHandlePageSwipe: Bool {
        !viewModel.showSettings
            && viewModel.presentedFolder == nil
    }

    private func adjustedPageOffset(for translation: CGFloat) -> CGFloat {
        let atFirstPage = viewModel.currentPage == 0 && translation > 0
        let atLastPage = viewModel.currentPage >= viewModel.totalPages - 1 && translation < 0

        if atFirstPage || atLastPage {
            return translation * 0.28
        }
        return translation
    }

    private func pageSwipeThreshold(for width: CGFloat) -> CGFloat {
        max(14, min(40, width * 0.022))
    }

    private func installTrackpadMonitorIfNeeded() {
        guard scrollEventMonitor == nil else { return }

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleTrackpadScroll(event)
        }
    }

    private func removeTrackpadMonitor() {
        guard let scrollEventMonitor else { return }
        NSEvent.removeMonitor(scrollEventMonitor)
        self.scrollEventMonitor = nil
    }

    private func handleTrackpadScroll(_ event: NSEvent) -> NSEvent? {
        guard viewModel.isPresented,
              canHandlePageSwipe,
              viewModel.totalPages > 1 else {
            accumulatedHorizontalScroll = 0
            return event
        }

        if event.phase == .began {
            accumulatedHorizontalScroll = 0
        }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        guard abs(horizontal) > abs(vertical) * 1.2, abs(horizontal) > 0.5 else {
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                accumulatedHorizontalScroll = 0
            }
            return event
        }

        accumulatedHorizontalScroll += horizontal
        let threshold: CGFloat = 42

        if accumulatedHorizontalScroll >= threshold {
            if viewModel.currentPage < viewModel.totalPages - 1 {
                withAnimation(pageTransitionAnimation) {
                    viewModel.nextPage()
                }
            }
            accumulatedHorizontalScroll = 0
            return nil
        }

        if accumulatedHorizontalScroll <= -threshold {
            if viewModel.currentPage > 0 {
                withAnimation(pageTransitionAnimation) {
                    viewModel.previousPage()
                }
            }
            accumulatedHorizontalScroll = 0
            return nil
        }

        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            accumulatedHorizontalScroll = 0
        }

        return nil
    }

    private func appGridItem(for app: AppItem) -> some View {
        let isDragging = draggingAppID == app.id
        let isHoverTarget = hoverGroupTarget == .app(app.id)

        return AppCardView(app: app, iconSize: effectiveIconSize, showCardBorder: settingsStore.showAppCardBorder) {
            onClose()
            viewModel.launch(app)
        }
        .overlay(itemChromeOverlay(isHoverTarget: isHoverTarget, itemID: app.id))
        .offset(isDragging ? draggingAppTranslation : .zero)
        .scaleEffect(isDragging ? 1.05 : (isHoverTarget ? 1.08 : 1.0))
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .zIndex(isDragging ? 100 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHoverTarget)
        .background {
            if draggingAppID != nil || draggingFolderID != nil {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GridDropFramePreferenceKey.self,
                        value: [GridDropFrameEntry(
                            itemID: app.id,
                            target: .app(app.id),
                            frame: geo.frame(in: .named("launcherGridSpace"))
                        )]
                    )
                }
            }
        }
        .simultaneousGesture(dragGesture(for: app.id))
        .contextMenu {
            customAppContextMenu(for: app)
        }
    }

    private func updateAdjacentPageRendering(for isPresented: Bool) {
        adjacentPagesWorkItem?.cancel()
        adjacentPagesWorkItem = nil

        guard isPresented else {
            shouldRenderAdjacentPages = false
            return
        }

        shouldRenderAdjacentPages = false
        let workItem = DispatchWorkItem {
            shouldRenderAdjacentPages = true
        }
        adjacentPagesWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: workItem)
    }

    private func folderGridItem(for folder: FolderDisplay) -> some View {
        let folderItemID = "folder:\(folder.id)"
        let isDragging = draggingFolderID == folder.id
        let isHoverTarget = hoverGroupTarget == .folder(folder.id)

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
        .overlay(itemChromeOverlay(isHoverTarget: isHoverTarget, itemID: folderItemID))
        .offset(isDragging ? draggingFolderTranslation : .zero)
        .scaleEffect(isDragging ? 1.05 : (isHoverTarget ? 1.08 : 1.0))
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
        .zIndex(isDragging ? 100 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHoverTarget)
        .background {
            if draggingAppID != nil || draggingFolderID != nil {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GridDropFramePreferenceKey.self,
                        value: [GridDropFrameEntry(
                            itemID: folderItemID,
                            target: .folder(folder.id),
                            frame: geo.frame(in: .named("launcherGridSpace"))
                        )]
                    )
                }
            }
        }
        .simultaneousGesture(folderDragGesture(for: folder.id))
        .contextMenu {
            Button("解散文件夹") {
                viewModel.dissolveFolder(folder.id)
            }
        }
    }

    private func dragGesture(for appID: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard draggingFolderID == nil else { return }

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if draggingAppID == nil, horizontal > vertical * 1.5 {
                    return
                }

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
        DragGesture(minimumDistance: 4, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard draggingAppID == nil else { return }

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if draggingFolderID == nil, horizontal > vertical * 1.5 {
                    return
                }

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
        frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.12)
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
            VStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.0), Color.white.opacity(0.85), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: effectiveIconSize * 0.85)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: reorderPosition.placeAfter ? .trailing : .leading)
            .padding(reorderPosition.placeAfter ? .trailing : .leading, -1)
        }
    }

    private func folderPanel(for folder: FolderDisplay) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                TextField("文件夹名称", text: Binding(
                    get: { folderNameDraft },
                    set: { folderNameDraft = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .onSubmit {
                    commitFolderName(for: folder.id)
                }

                Text("\(folder.apps.count) 个应用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                Spacer(minLength: 0)

                Button {
                    viewModel.dissolveFolder(folder.id)
                } label: {
                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("解散文件夹")

                Button {
                    commitFolderName(for: folder.id)
                    dismissFolder()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.3)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                let size = folderPanelIconSize
                let minimum = size + 36
                let maximum = size + 56
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 10)], spacing: 10) {
                    ForEach(folder.apps) { app in
                        folderAppCard(app: app, folder: folder)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                .shadow(color: Color.black.opacity(0.22), radius: 32, y: 14)
        )
        .onAppear {
            folderNameDraft = folder.folder.name
        }
        .onTapGesture {}
    }

    private func folderAppCard(app: AppItem, folder: FolderDisplay) -> some View {
        return AppCardView(app: app, iconSize: folderPanelIconSize, showCardBorder: settingsStore.showAppCardBorder) {
            commitFolderName(for: folder.id)
            dismissFolder()
            onClose()
            viewModel.launch(app)
        }
        .help("点击打开应用")
        .simultaneousGesture(folderAppDragGesture(appID: app.id, folderID: folder.id))
        .contextMenu {
            customAppContextMenu(for: app)
        }
    }

    @ViewBuilder
    private func customAppContextMenu(for app: AppItem) -> some View {
        if settingsStore.showPinnedBar {
            let isPinned = viewModel.isPinned(app.id)

            Button {
                viewModel.togglePinnedState(for: app.id)
            } label: {
                Label(isPinned ? "取消固定" : "固定", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Divider()
        }

        // 文件夹菜单
        let existingFolders = viewModel.folderDisplays
        if existingFolders.isEmpty {
            Button {
                viewModel.addAppToNewFolder(appID: app.id)
            } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
        } else {
            Menu {
                ForEach(existingFolders) { folder in
                    Button {
                        viewModel.addAppToFolder(appID: app.id, folderID: folder.id)
                    } label: {
                        Label(folder.folder.name, systemImage: "folder")
                    }
                }

                Divider()

                Button {
                    viewModel.addAppToNewFolder(appID: app.id)
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("添加到文件夹", systemImage: "folder.badge.plus")
            }
        }
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

    private func topLeadingMeta(geometry: GeometryProxy) -> some View {
        HStack(spacing: 6) {
            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRefreshing ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)

                Text(viewModel.subtitleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 0.5, height: 14)

            // Shortcut hint
            HStack(spacing: 3) {
                Text("⌥")
                    .font(.system(size: 10, weight: .bold))
                Text("Space")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 20)
        .padding(.top, max(geometry.safeAreaInsets.top + 20, 20))
    }

    @State private var isSearchFocused = false

    private var searchBarActive: Bool {
        isSearchFocused || viewModel.isSearching
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(searchBarActive ? 0.8 : 0.4))

            SearchField(
                text: $viewModel.query,
                shouldFocus: $viewModel.shouldFocusSearchField,
                placeholder: "搜索应用",
                onCommit: {
                    onClose()
                    viewModel.launchFirstResult()
                },
                onMoveUp: {
                    viewModel.selectPreviousSearchResult()
                },
                onMoveDown: {
                    viewModel.selectNextSearchResult()
                }
            )

            if !viewModel.query.isEmpty {
                Button(action: viewModel.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 22)
        .frame(width: 460, height: 48)
        .background(
            Capsule()
                .fill(Color.white.opacity(searchBarActive ? 0.12 : 0.08))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(searchBarActive ? 0.20 : 0.10), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        )
        .animation(.easeInOut(duration: 0.2), value: searchBarActive)
    }

    @State private var searchScrollProxy: ScrollViewProxy? = nil

    private var searchResultsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, app in
                        searchResultRow(for: app, index: index)
                            .id("row-\(index)")
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
            }
            .onChange(of: viewModel.searchSelectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("row-\(newIndex)", anchor: .center)
                }
            }
        }
        .frame(width: 460)
        .frame(maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
    }

    private func searchResultRow(for app: AppItem, index: Int) -> some View {
        let isSelected = viewModel.searchSelectedIndex == index

        return SearchResultRowView(
            app: app,
            isSelected: isSelected,
            action: { [onClose, viewModel] in
                onClose()
                viewModel.launch(app)
            }
        )
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

    private var paginationControls: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(pageTransitionAnimation) {
                    viewModel.previousPage()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPage == 0)
            .opacity(viewModel.currentPage == 0 ? 0.4 : 1)

            Text("\(viewModel.currentPage + 1) / \(viewModel.totalPages)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60)

            Button {
                withAnimation(pageTransitionAnimation) {
                    viewModel.nextPage()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPage >= viewModel.totalPages - 1)
            .opacity(viewModel.currentPage >= viewModel.totalPages - 1 ? 0.4 : 1)
        }
        .padding(.vertical, 16)
        .onTapGesture {}
    }

    @State private var hoveredPage: Int? = nil

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<viewModel.totalPages, id: \.self) { page in
                Capsule()
                    .fill(page == viewModel.currentPage ? Color.white : Color.white.opacity(hoveredPage == page ? 0.6 : 0.35))
                    .frame(width: page == viewModel.currentPage ? 18 : (hoveredPage == page ? 8 : 6), height: 6)
                    .onTapGesture {
                        withAnimation(pageTransitionAnimation) {
                            viewModel.currentPage = page
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.1)) {
                            hoveredPage = hovering ? page : nil
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.25))
        )
    }
}

private struct PinnedAppButton: View {
    let app: AppItem
    let iconSize: Double
    let action: () -> Void
    @State private var isHovered = false
    @State private var iconVersion = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: AppIconProvider.shared.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: max(8, iconSize * 0.22), style: .continuous))
                    .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0), radius: 8, y: 4)
                    .scaleEffect(isHovered ? 1.12 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)

                Text(app.name)
                    .font(.system(size: 9.5, weight: isHovered ? .medium : .regular))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: iconSize + 12)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(AppIconProvider.shared.loadedPublisher(for: app.url.path)) { _ in
            iconVersion &+= 1
        }
        .help(app.name)
    }
}

// MARK: - Search Result Row

private struct SearchResultRowView: View {
    let app: AppItem
    let isSelected: Bool
    let action: () -> Void
    @State private var iconVersion = 0
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: AppIconProvider.shared.icon(for: app))
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.4 : 0), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Text("↵")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onReceive(AppIconProvider.shared.loadedPublisher(for: app.url.path)) { _ in
            iconVersion &+= 1
        }
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
