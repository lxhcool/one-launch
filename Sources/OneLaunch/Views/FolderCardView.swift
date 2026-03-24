import SwiftUI

/// 文件夹卡片 — <9 用 2×2 预览，≥9 用 3×3 预览
/// 点击图标直接打开应用，最后一个格子为入口按钮进入文件夹
struct FolderCardView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let iconSize: Double
    let onOpenFolder: () -> Void
    let onLaunchApp: (AppItem) -> Void

    @State private var isHovered = false
    @ObservedObject private var iconProvider = AppIconProvider.shared

    private var useLargeGrid: Bool { apps.count >= 9 }
    private var gridColumns: Int { useLargeGrid ? 3 : 2 }
    private var gridSlots: Int { gridColumns * gridColumns }

    /// 最多展示 gridSlots-1 个 app，最后一格留给入口
    private var maxPreviewApps: Int { gridSlots - 1 }

    // MARK: - 尺寸

    private var cardPadding: Double {
        max(4, iconSize * 0.05)
    }

    private var cardTotalSize: Double {
        iconSize + cardPadding * 2
    }

    private var cardCornerRadius: Double {
        max(14, iconSize * 0.26)
    }

    private var tileGap: Double {
        useLargeGrid ? max(2, iconSize * 0.03) : max(2, iconSize * 0.03)
    }

    private var tileSize: Double {
        let inset = useLargeGrid ? iconSize * 0.06 : iconSize * 0.06
        return max(10, (iconSize - inset * 2 - tileGap * Double(gridColumns - 1)) / Double(gridColumns))
    }

    private var tileCorner: Double {
        max(4, tileSize * 0.22)
    }

    private var previewApps: [AppItem] {
        Array(apps.prefix(maxPreviewApps))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(isHovered ? 0.10 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(isHovered ? 0.22 : 0.10), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                    .shadow(color: Color.black.opacity(isHovered ? 0.18 : 0), radius: isHovered ? 14 : 0, y: isHovered ? 5 : 0)

                gridPreview
                    .scaleEffect(isHovered ? 1.03 : 1)
            }
            .frame(width: cardTotalSize, height: cardTotalSize)
            .scaleEffect(isHovered ? 1.06 : 1)

            Text(folder.name)
                .font(.system(size: 11, weight: isHovered ? .medium : .regular))
                .foregroundStyle(.primary.opacity(isHovered ? 1 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cardTotalSize + 8)
        }
        .frame(width: cardTotalSize + 14, height: cardTotalSize + 32, alignment: .top)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovered = hovering
            }
        }
        .help(apps.map(\.name).joined(separator: "\n"))
    }

    // MARK: - 网格预览

    private var gridPreview: some View {
        VStack(spacing: tileGap) {
            ForEach(0..<gridColumns, id: \.self) { row in
                HStack(spacing: tileGap) {
                    ForEach(0..<gridColumns, id: \.self) { col in
                        let index = row * gridColumns + col
                        let isEntrySlot = index == gridSlots - 1
                        if isEntrySlot {
                            entryTile
                        } else if previewApps.indices.contains(index) {
                            tileButton(for: previewApps[index])
                        } else {
                            RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: tileSize, height: tileSize)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tiles

    private func tileButton(for app: AppItem) -> some View {
        Button {
            onLaunchApp(app)
        } label: {
            Image(nsImage: iconProvider.icon(for: app))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: tileCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(app.name)
    }

    private var entryTile: some View {
        Button(action: onOpenFolder) {
            ZStack {
                RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Image(systemName: "ellipsis")
                    .font(.system(size: max(8, tileSize * 0.30), weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(.plain)
        .help("打开文件夹")
    }
}
