import SwiftUI

struct AppCardView: View {
    let app: AppItem
    let iconSize: Double
    let showCardBorder: Bool
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var iconProvider = AppIconProvider.shared

    private var iconCornerRadius: Double {
        iconSize * 0.22
    }

    private var cardCornerRadius: Double {
        iconSize * 0.26
    }

    private var cardPadding: Double {
        max(6, iconSize * 0.08)
    }

    private var cardTotalSize: Double {
        iconSize + cardPadding * 2
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if showCardBorder {
                    // 常驻卡片底座 — 类似 iPadOS 图标卡片
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.14 : 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.06), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                        .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0), radius: isHovered ? 12 : 0, y: isHovered ? 5 : 0)
                }

                Image(nsImage: iconProvider.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
            }
            .frame(width: cardTotalSize, height: cardTotalSize)
            .scaleEffect(isHovered ? 1.06 : 1)
            .shadow(color: .black.opacity(showCardBorder ? 0 : (isHovered ? 0.2 : 0.08)), radius: showCardBorder ? 0 : (isHovered ? 8 : 3), y: showCardBorder ? 0 : (isHovered ? 3 : 1))

            Text(app.name)
                .font(.system(size: 11, weight: isHovered ? .medium : .regular))
                .foregroundStyle(.primary.opacity(isHovered ? 1 : 0.85))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cardTotalSize + 8)
        }
        .frame(width: cardTotalSize + 14, height: cardTotalSize + 32, alignment: .top)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovered = hovering
            }
        }
        .help(app.bundleIdentifier ?? app.url.path)
    }
}
