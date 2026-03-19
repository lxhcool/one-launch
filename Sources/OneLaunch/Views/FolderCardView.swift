import SwiftUI

struct FolderCardView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let iconSize: Double
    let onOpenFolder: () -> Void
    let onLaunchApp: (AppItem) -> Void

    @State private var isHovered = false
    @ObservedObject private var iconProvider = AppIconProvider.shared

    private let previewGridCount = 3
    private var entryTileIndex: Int { previewGridCount * previewGridCount - 1 }

    private var cornerRadius: Double {
        max(12, iconSize * 0.18)
    }

    private var clickablePreviewApps: [AppItem] {
        Array(apps.prefix(entryTileIndex))
    }

    private var cardHeight: Double {
        iconSize + 36
    }

    private var cardWidth: Double {
        iconSize + 6
    }

    private var tileGap: Double {
        max(1.5, iconSize * 0.028)
    }

    private var tileSize: Double {
        let count = Double(previewGridCount)
        let inset = iconSize * 0.06
        return max(9, (iconSize - inset * 2 - tileGap * (count - 1)) / count)
    }

    private var tileCorner: Double {
        max(4, tileSize * 0.22)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(isHovered ? 0.3 : 0.15), lineWidth: isHovered ? 1.5 : 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)

                VStack(spacing: tileGap) {
                    ForEach(0..<previewGridCount, id: \.self) { row in
                        HStack(spacing: tileGap) {
                            ForEach(0..<previewGridCount, id: \.self) { col in
                                let index = row * previewGridCount + col
                                folderPreviewTile(index: index)
                            }
                        }
                    }
                }
                .scaleEffect(isHovered ? 1.02 : 1)
            }
            .frame(width: cardWidth)

            Text(folder.name)
                .font(.system(size: max(10, iconSize * 0.155), weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cardWidth)
        }
        .frame(width: cardWidth + 6, height: cardHeight, alignment: .top)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenFolder)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(apps.map(\.name).joined(separator: "\n"))
    }

    @ViewBuilder
    private func folderPreviewTile(index: Int) -> some View {
        let isFolderEntryTile = index == entryTileIndex

        if isFolderEntryTile {
            Button(action: onOpenFolder) {
                Image(systemName: "ellipsis")
                    .font(.system(size: max(9, tileSize * 0.40), weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: tileSize, height: tileSize)
                    .background(
                        RoundedRectangle(cornerRadius: tileCorner, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        } else if clickablePreviewApps.indices.contains(index) {
            let app = clickablePreviewApps[index]
            Button(action: { onLaunchApp(app) }) {
                Image(nsImage: iconProvider.icon(for: app))
                    .resizable()
                    .scaledToFit()
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: tileCorner, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(width: tileSize, height: tileSize)
        }
    }
}
