import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var iconProvider = AppIconProvider.shared
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

    private var adaptiveColorScheme: ColorScheme {
        settingsStore.backgroundIsDark ? .dark : .light
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
                            viewModel.closeFolder()
                        } else {
                            onClose()
                        }
                    }

                VStack(spacing: 68) {
                    header

                    content
                }
                .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 52)
                .padding(.top, max(geometry.safeAreaInsets.top + 26, 44))
                .padding(.bottom, 14)

                topLeadingMeta(geometry: geometry)

                topTrailingActions(geometry: geometry)

                if shouldShowLeftCategoryBar {
                    leftCategoryBar(maxHeight: geometry.size.height - 64)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 0)
                        .zIndex(20)
                }

                // 搜索面板 - 悬浮在最上层，不影响网格布局
                if viewModel.isSearching && !viewModel.searchResults.isEmpty {
                    searchResultsPanel
                        .position(
                            x: geometry.size.width / 2,
                            y: max(geometry.safeAreaInsets.top + 26, 44) + 40 + 62 + 16 + 180
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

                if let folder = viewModel.presentedFolder {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { viewModel.closeFolder() }

                    folderPanel(for: folder)
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
        .onChange(of: viewModel.selectedCategory) { _, _ in
            pageOffset = 0
            if viewModel.isPresented {
                updateAdjacentPageRendering(for: true)
            }
        }
        .onExitCommand {
            if viewModel.showSettings {
                dismissSettings()
            } else if viewModel.presentedFolder != nil {
                viewModel.closeFolder()
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
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            searchBar

            Spacer(minLength: 0)
        }
        .padding(.top, 40)
        .padding(.horizontal, 8)
        .onTapGesture {}
    }

    @State private var hoveredButton: String? = nil

    private func topTrailingActions(geometry: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            ForEach([
                ("gearshape", { viewModel.showSettings.toggle() }, "设置"),
                ("arrow.clockwise", { viewModel.refreshApplications() }, "重新扫描"),
                ("xmark", { onClose() }, "关闭")
            ], id: \.0) { icon, action, help in
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(hoveredButton == icon ? 0.12 : 0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(hoveredButton == icon ? 0.2 : 0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(help)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.1)) {
                        hoveredButton = hovering ? icon : nil
                    }
                }
            }
        }
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
                description: Text(viewModel.isRefreshing ? "正在扫描应用目录" : "换个关键词试试，或者重新扫描应用")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { gridGeo in
                if !viewModel.isSearching && viewModel.gridItems.isEmpty {
                    ContentUnavailableView(
                        "该分类暂无应用",
                        systemImage: "square.grid.2x2",
                        description: Text("试试切换到其他分类，或重新扫描应用列表")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(0..<viewModel.totalPages, id: \.self) { page in
                                if abs(page - viewModel.currentPage) <= renderedPageDistance {
                                    VStack(spacing: 0) {
                                        LazyVGrid(columns: columns, spacing: 18) {
                                            ForEach(viewModel.gridItemsForPage(page)) { item in
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

                                        Color.clear
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    .frame(width: gridGeo.size.width, height: gridGeo.size.height, alignment: .top)
                                    .allowsHitTesting(page == viewModel.currentPage)
                                } else {
                                    Color.clear
                                        .frame(width: gridGeo.size.width, height: gridGeo.size.height)
                                }
                            }
                        }
                        .offset(x: -CGFloat(viewModel.currentPage) * gridGeo.size.width + pageOffset)
                        .frame(width: gridGeo.size.width, alignment: .leading)
                        .contentShape(Rectangle())
                        .clipped()
                        .overlay(alignment: .bottom) {
                            if viewModel.totalPages > 1 {
                                pageIndicator
                                    .padding(.bottom, 18)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                                .onChanged { value in
                                    guard canHandlePageSwipe else { return }
                                    guard viewModel.totalPages > 1 else { return }

                                    let horizontal = abs(value.translation.width)
                                    let vertical = abs(value.translation.height)
                                    guard horizontal > max(6, vertical * 0.8) else { return }

                                    pageOffset = adjustedPageOffset(for: value.translation.width)
                                }
                                .onEnded { value in
                                    guard canHandlePageSwipe else { return }
                                    guard viewModel.totalPages > 1 else { return }

                                    let current = adjustedPageOffset(for: value.translation.width)
                                    let predicted = adjustedPageOffset(for: value.predictedEndTranslation.width)
                                    let effective: CGFloat
                                    if abs(predicted) > abs(current) {
                                        effective = predicted
                                    } else {
                                        effective = current
                                    }
                                    let threshold = pageSwipeThreshold(for: gridGeo.size.width)

                                    var targetPage = viewModel.currentPage
                                    if effective < -threshold {
                                        targetPage = min(viewModel.totalPages - 1, viewModel.currentPage + 1)
                                    } else if effective > threshold {
                                        targetPage = max(0, viewModel.currentPage - 1)
                                    }

                                    withAnimation(pageTransitionAnimation) {
                                        viewModel.currentPage = targetPage
                                        pageOffset = 0
                                    }
                                }
                        )
                        .onChange(of: viewModel.totalPages) { _, totalPages in
                            let maxPage = max(0, totalPages - 1)
                            if viewModel.currentPage > maxPage {
                                viewModel.currentPage = maxPage
                            }
                        }
                    }
                }
            }
        }
    }

    private func leftCategoryBar(maxHeight: CGFloat) -> some View {
        let categories = viewModel.categorySidebarItems

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    CategorySidebarItemView(
                        icon: category.icon,
                        title: category.title,
                        isSelected: viewModel.selectedCategory == category.selection,
                        extraTrailingPadding: ladderTrailingPadding(for: index),
                        action: {
                            pageOffset = 0
                            viewModel.selectedCategory = category.selection
                        }
                    )
                    .contextMenu {
                        categoryQuickActions(for: category)
                    }
                }
            }
            .padding(.leading, 0)
            .padding(.trailing, 8)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: max(220, min(CGFloat(categories.count) * 44 + 32, maxHeight)))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var shouldShowLeftCategoryBar: Bool {
        viewModel.presentedFolder == nil
    }

    private func ladderTrailingPadding(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [16, 4, 12, 0, 14, 6, 10, 2, 8, 0]
        return pattern[index % pattern.count]
    }

    @ViewBuilder
    private func categoryQuickActions(for category: CategorySidebarItem) -> some View {
        Button {
            viewModel.moveCategoryUp(category.selection)
        } label: {
            Label("上移", systemImage: "chevron.up")
        }
        .disabled(!viewModel.canMoveCategoryUp(category.selection))

        Button {
            viewModel.moveCategoryDown(category.selection)
        } label: {
            Label("下移", systemImage: "chevron.down")
        }
        .disabled(!viewModel.canMoveCategoryDown(category.selection))
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
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.08), value: gridItemIDs)
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
        return AppCardView(app: app, iconSize: effectiveIconSize) {
            onClose()
            viewModel.launch(app)
        }
        .simultaneousGesture(dragGesture(for: app.id))
        .contextMenu {
            customCategoryContextMenu(for: app)
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

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if draggingAppID == nil, horizontal > vertical * 1.15 {
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
        DragGesture(minimumDistance: 2, coordinateSpace: .named("launcherGridSpace"))
            .onChanged { value in
                guard !viewModel.isSearching else { return }
                guard draggingAppID == nil else { return }

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                if draggingFolderID == nil, horizontal > vertical * 1.15 {
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
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                folderHeroPreview(for: folder)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("文件夹名称", text: Binding(
                        get: { folderNameDraft },
                        set: { folderNameDraft = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .onSubmit {
                        commitFolderName(for: folder.id)
                    }

                    HStack(spacing: 8) {
                        folderInfoBadge(systemImage: "apps.ipad", title: "\(folder.apps.count)")
                        folderInfoBadge(systemImage: "hand.tap", title: "点击打开")
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        viewModel.dissolveFolder(folder.id)
                    } label: {
                        Label("解散", systemImage: "folder.badge.minus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(FolderPanelButtonStyle())

                    Button {
                        commitFolderName(for: folder.id)
                        viewModel.closeFolder()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(FolderPanelButtonStyle())
                }
            }

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                let size = folderPanelIconSize
                let minimum = size + 44
                let maximum = size + 72
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 12)], spacing: 12) {
                    ForEach(folder.apps) { app in
                        folderAppCard(app: app, folder: folder)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .frame(width: 600, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            folderNameDraft = folder.folder.name
        }
        .onTapGesture {}
    }

    private func folderAppCard(app: AppItem, folder: FolderDisplay) -> some View {
        return AppCardView(app: app, iconSize: folderPanelIconSize) {
            commitFolderName(for: folder.id)
            viewModel.closeFolder()
            onClose()
            viewModel.launch(app)
        }
        .help("点击打开应用")
        .simultaneousGesture(folderAppDragGesture(appID: app.id, folderID: folder.id))
        .contextMenu {
            customCategoryContextMenu(for: app)
        }
    }

    @ViewBuilder
    private func customCategoryContextMenu(for app: AppItem) -> some View {
        let customCategories = settingsStore.customCategories
        let effectiveSystemCategory = viewModel.effectiveSystemCategory(for: app)
        let hasSystemOverride = viewModel.hasSystemCategoryOverride(for: app.id)

        Menu {
            ForEach(viewModel.editableSystemCategories, id: \.rawValue) { category in
                Button {
                    viewModel.setSystemCategory(for: app, to: category)
                } label: {
                    HStack {
                        Text(category.rawValue)
                        Spacer()
                        if effectiveSystemCategory == category {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            if hasSystemOverride {
                Divider()
                Button("恢复自动分类") {
                    viewModel.restoreAutoSystemCategory(for: app.id)
                }
            }
        } label: {
            Label("系统分类", systemImage: "square.grid.2x2")
        }

        Divider()

        if customCategories.isEmpty {
            Button {
                viewModel.showSettings = true
            } label: {
                Label("新建自定义分类", systemImage: "plus")
            }
        } else {
            let assignedCategories = customCategories.filter { category in
                viewModel.isApp(app.id, inCustomCategory: category.id)
            }

            Menu {
                ForEach(customCategories, id: \.id) { category in
                    Button {
                        viewModel.toggleCustomCategoryMembership(appID: app.id, categoryID: category.id)
                    } label: {
                        HStack {
                            Text(category.name)
                            Spacer()
                            if viewModel.isApp(app.id, inCustomCategory: category.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                if !assignedCategories.isEmpty {
                    Divider()

                    Button(role: .destructive) {
                        viewModel.removeAppFromAllCustomCategories(app.id)
                    } label: {
                        Label("清除全部分类", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("自定义分类", systemImage: "tag")
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

    private func folderHeroPreview(for folder: FolderDisplay) -> some View {
        let heroSize: Double = 100
        let gap: Double = 6
        let tileSize: Double = 36

        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))

            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if folder.apps.indices.contains(index) {
                                Image(nsImage: iconProvider.icon(for: folder.apps[index]))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: tileSize, height: tileSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }

    struct FolderPanelButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }

    private func topLeadingMeta(geometry: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRefreshing ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)

                Text(viewModel.subtitleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.2))
            )

            // Shortcut hint
            HStack(spacing: 3) {
                Text("⌥")
                    .font(.system(size: 10, weight: .bold))
                Text("Space")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.2))
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 20)
        .padding(.top, max(geometry.safeAreaInsets.top + 20, 20))
    }

    @State private var isSearchFocused = false

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)

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
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 520, height: 62)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSearchFocused || viewModel.isSearching
                                ? Color.white.opacity(0.35)
                                : Color.white.opacity(0.12),
                            lineWidth: (isSearchFocused || viewModel.isSearching) ? 1.5 : 1
                        )
                )
                .shadow(
                    color: Color.black.opacity((isSearchFocused || viewModel.isSearching) ? 0.25 : 0.15),
                    radius: (isSearchFocused || viewModel.isSearching) ? 20 : 12,
                    x: 0,
                    y: (isSearchFocused || viewModel.isSearching) ? 8 : 4
                )
        )
        .animation(.easeOut(duration: 0.2), value: isSearchFocused)
        .animation(.easeOut(duration: 0.2), value: viewModel.isSearching)
    }

    @State private var searchScrollProxy: ScrollViewProxy? = nil

    private var searchResultsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, app in
                        searchResultRow(for: app, index: index)
                            .id("row-\(index)")
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.searchSelectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("row-\(newIndex)", anchor: .center)
                }
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(0.2),
                    radius: 24,
                    x: 0,
                    y: 12
                )
        )
    }

    private func searchResultRow(for app: AppItem, index: Int) -> some View {
        let isSelected = viewModel.searchSelectedIndex == index

        return Button {
            onClose()
            viewModel.launch(app)
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: iconProvider.icon(for: app))
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

                    Text(app.bundleIdentifier ?? app.url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

private struct CategorySidebarItemView: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let extraTrailingPadding: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.9))
            .padding(.leading, 8)
            .padding(.trailing, 12 + extraTrailingPadding + (isHovered ? 6 : 0))
            .padding(.vertical, 8)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 0,
                        bottomTrailing: 11,
                        topTrailing: 11
                    ),
                    style: .continuous
                )
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.06))
            )
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 0,
                        bottomTrailing: 11,
                        topTrailing: 11
                    ),
                    style: .continuous
                )
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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
