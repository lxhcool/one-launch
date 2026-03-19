import SwiftUI

struct AppCardView: View {
    let app: AppItem
    let iconSize: Double
    let action: () -> Void

    @State private var isHovered = false

    private var cornerRadius: Double {
        iconSize * 0.18
    }

    private var cardHeight: Double {
        iconSize + 36
    }

    private var cardWidth: Double {
        iconSize + 6
    }

    var body: some View {
        VStack(spacing: 6) {
            // Icon with simple hover effect
            Image(nsImage: AppIconProvider.shared.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.2), radius: isHovered ? 10 : 4, x: 0, y: isHovered ? 4 : 2)
                .scaleEffect(isHovered ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: isHovered)

            // App name
            Text(app.name)
                .font(.system(size: max(10, iconSize * 0.155), weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: cardWidth)
        }
        .frame(width: cardWidth + 6, height: cardHeight, alignment: .top)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(app.bundleIdentifier ?? app.url.path)
    }
}
