import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Design tokens
// Centralized so every screen shares one consistent, modern look.
// Nothing in this file touches app state or business logic.

public enum Theme {

    // Brand
    public static let brandStart = Color(red: 0.36, green: 0.42, blue: 0.98) // indigo
    public static let brandEnd   = Color(red: 0.55, green: 0.32, blue: 0.98) // violet

    public static let brandGradient = LinearGradient(
        colors: [brandStart, brandEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic
    public static let profit  = Color(red: 0.16, green: 0.74, blue: 0.48)
    public static let loss    = Color(red: 0.95, green: 0.31, blue: 0.36)
    public static let warning = Color(red: 0.98, green: 0.65, blue: 0.15)
    public static let info    = Color(red: 0.29, green: 0.62, blue: 0.98)

    public static let demo = Color(red: 0.98, green: 0.65, blue: 0.15)  // orange — "you can't lose real money"
    public static let real = Color(red: 0.16, green: 0.74, blue: 0.48)  // green  — "this is live money"

    // Surfaces — platform-specific system background, since UIColor and
    // NSColor aren't interchangeable between iOS and macOS.
    public static var pageBackground: Color {
        // Keep the trading surface dark so small digits and live values remain
        // readable during long sessions, regardless of macOS appearance mode.
        #if os(iOS)
        return Color(red: 0.055, green: 0.065, blue: 0.085)
        #else
        return Color(red: 0.045, green: 0.055, blue: 0.070)
        #endif
    }

    public static func cardBackground(_ scheme: ColorScheme) -> Color {
        // Keep cards dark in both system appearance modes.
        scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.055)
    }

    // Radii / spacing
    public static let cornerRadiusLarge: CGFloat = 22
    public static let cornerRadiusMedium: CGFloat = 16
    public static let cornerRadiusSmall: CGFloat = 10
    public static let gutter: CGFloat = 16
}

// MARK: - Cross-platform keyboard type helper
// iOS-only keyboard hints (.keyboardType) don't exist on macOS; this lets
// every form field opt in without each view needing its own #if block.

public enum KeyboardKindCompat {
    case decimalPad, numberPad
}

public extension View {
    @ViewBuilder
    func keyboardTypeCompat(_ kind: KeyboardKindCompat) -> some View {
        #if os(iOS)
        switch kind {
        case .decimalPad: self.keyboardType(.decimalPad)
        case .numberPad: self.keyboardType(.numberPad)
        }
        #else
        self
        #endif
    }
}

// MARK: - Reusable modifiers

public struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.cornerRadiusLarge

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardBackground(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

public extension View {
    func cardStyle(padding: CGFloat = 16, radius: CGFloat = Theme.cornerRadiusLarge) -> some View {
        modifier(CardStyle(padding: padding, radius: radius))
    }

    /// Soft, tinted "chip" background — used for badges/pills.
    func chipStyle(_ color: Color) -> some View {
        self
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Small reusable components

/// A pill-shaped status badge, e.g. "LIVE" / "DEMO" / "BOT ACTIVE".
public struct StatusPill: View {
    let text: String
    let color: Color
    let pulsing: Bool

    public init(_ text: String, color: Color, pulsing: Bool = false) {
        self.text = text
        self.color = color
        self.pulsing = pulsing
    }

    @State private var animate = false

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing && animate ? 1.6 : 1.0)
                .opacity(pulsing && animate ? 0.4 : 1.0)
                .animation(pulsing ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: animate)
            Text(text)
                .font(.caption2)
                .fontWeight(.heavy)
                .tracking(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
        .onAppear { animate = true }
    }
}

/// A banner used for surfacing an error inline, replacing the old plain HStack.
public struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    public init(_ message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.loss)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let retry {
                    Button(action: retry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous)
                .fill(Theme.loss.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous)
                .stroke(Theme.loss.opacity(0.3), lineWidth: 1)
        )
    }
}
