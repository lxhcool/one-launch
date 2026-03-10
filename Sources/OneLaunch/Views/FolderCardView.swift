import SwiftUI

struct FolderCardView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let iconSize: Double
    let onOpenFolder: () -> Void
    let onLaunchApp: (AppItem) -> Void

    private let previewGridCount = 3
    private var entryTileIndex: Int { previewGridCount * previewGridCount - 1 } // 8

    private var cornerRadius: Double {
        max(12, iconSize * 0.18)
    }

    private var clickablePreviewApps: [AppItem] {
        Array(apps.prefix(entryTileIndex)) // 8 个可点
    }

    private var cardHeight: Double {
        iconSize + 42
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
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )

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
            }
            .frame(width: iconSize, height: iconSize)

            Text(folder.name)
                .font(.system(size: max(11, iconSize * 0.19), weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenFolder)
        .help(apps.map(\.name).joined(separator: "\n"))
    }

    @ViewBuilder
    private func folderPreviewTile(index: Int) -> some View {
        let isFolderEntryTile = index == entryTileIndex

        if isFolderEntryTile {
            Button(action: onOpenFolder) {
                Image(systemName: "ellipsis")
                    .font(.system(size: max(9, tileSize * 0.40), weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: tileSize, height: tileSize)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: tileCorner, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if clickablePreviewApps.indices.contains(index) {
            let app = clickablePreviewApps[index]
            Button(action: { onLaunchApp(app) }) {
                Image(nsImage: AppIconProvider.shared.icon(for: app))
                    .resizable()
                    .scaledToFit()
                    .frame(width: tileSize, height: tileSize)
                    .scaleEffect(1.03)
                    .clipShape(RoundedRectangle(cornerRadius: tileCorner, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(width: tileSize, height: tileSize)
        }
    }
}
