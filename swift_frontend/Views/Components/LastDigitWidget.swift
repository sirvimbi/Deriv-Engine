import SwiftUI

public struct LastDigitWidget: View {
    public let lastQuote: Double?
    public let quotePrecision: Int?
    public let lastDigit: Int?
    public let tickHistory: [Int]

    public init(lastQuote: Double?, quotePrecision: Int? = nil, lastDigit: Int?, tickHistory: [Int]) {
        self.lastQuote = lastQuote
        self.quotePrecision = quotePrecision
        self.lastDigit = lastDigit
        self.tickHistory = tickHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE TICK PRICE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.secondary)

                    if let quote = lastQuote {
                        Text(formattedQuote(quote))
                            .font(.system(size: 30, weight: .heavy, design: .monospaced))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                    } else {
                        Text("---.----")
                            .font(.system(size: 30, weight: .heavy, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer(minLength: 12)

                VStack(spacing: 6) {
                    Text("LAST DIGIT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.secondary)

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [digitColor(lastDigit), digitColor(lastDigit).opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: digitColor(lastDigit).opacity(0.45), radius: 8, x: 0, y: 4)

                        Text(lastDigit.map(String.init) ?? "–")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }

            if !tickHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT DIGITS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(tickHistory.enumerated()), id: \.offset) { index, digit in
                                let isLatest = index == tickHistory.count - 1
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(digitColor(digit).opacity(isLatest ? 0.9 : 0.14))
                                        .frame(width: 34, height: 34)
                                    Text("\(digit)")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(isLatest ? .white : digitColor(digit))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .cardStyle(padding: 16, radius: Theme.cornerRadiusLarge)
    }

    private func formattedQuote(_ quote: Double) -> String {
        // Use Deriv's pip_size instead of forcing every market to four
        // decimal places. For example R_100 quotes at two decimals should
        // display 782.64, not the misleading 782.6400. Markets that actually
        // provide four decimal places will still display all four.
        let precision = max(0, min(10, quotePrecision ?? 2))
        return String(format: "%.*f", precision, quote)
    }

    private func digitColor(_ digit: Int?) -> Color {
        guard let d = digit else { return .gray }
        return d >= 5 ? Theme.info : Theme.warning
    }
}
