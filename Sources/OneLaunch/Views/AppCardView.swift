import SwiftUI

struct AppCardView: View {
    let app: AppItem
    let iconSize: Double
    let action: () -> Void

    private var cornerRadius: Double {
        iconSize * 0.18
    }

    private var cardHeight: Double {
        iconSize + 42
    }

    private var cardWidth: Double {
        iconSize + 10
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: AppIconProvider.shared.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            Text(app.name)
                .font(.system(size: max(10, iconSize * 0.16), weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .allowsTightening(true)
                .minimumScaleFactor(0.72)
                .frame(width: cardWidth)
                .frame(minHeight: 28, maxHeight: 28, alignment: .top)
                .clipped()
        }
        .frame(width: cardWidth)
        .frame(minHeight: cardHeight, maxHeight: cardHeight, alignment: .top)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: action)
        .help(app.bundleIdentifier ?? app.url.path)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
