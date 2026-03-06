import SwiftUI

struct AppCardView: View {
    let app: AppItem
    let iconSize: Double
    let action: () -> Void

    private var cornerRadius: Double {
        iconSize * 0.18
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(nsImage: AppIconProvider.shared.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                Text(app.name)
                    .font(.system(size: max(11, iconSize * 0.19), weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: iconSize + 52)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .help(app.bundleIdentifier ?? app.url.path)
    }
}
