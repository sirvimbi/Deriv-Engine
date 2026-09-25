import SwiftUI

public struct MetricCard: View {
    public let title: String
    public let value: String
    public var subtitle: String? = nil
    public var iconName: String? = nil
    public var color: Color = .blue
    /// Optional: shows a muted placeholder style when the value isn't available yet.
    public var isPlaceholder: Bool = false

    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        color: Color = .blue,
        isPlaceholder: Bool = false
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.iconName = iconName
        self.color = color
        self.isPlaceholder = isPlaceholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon = iconName {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(color)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(isPlaceholder ? .secondary : color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14, radius: Theme.cornerRadiusMedium)
    }
}
