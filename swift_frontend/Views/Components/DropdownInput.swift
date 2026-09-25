import SwiftUI

/// Non-editable numeric controls used throughout the app.
/// These deliberately avoid NSTextField/TextField so there is no keyboard,
/// focus, responder-chain, or text-selection path involved.
public struct IntegerDropdown: View {
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    public let label: String

    public init(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) {
        self.label = label
        self._value = value
        self.range = range
    }

    public var body: some View {
        Picker(label, selection: $value) {
            ForEach(Array(range), id: \.self) { item in
                Text("\(item)").tag(item)
            }
        }
        .pickerStyle(.menu)
        .menuOrder(.fixed)
        .frame(minWidth: 130, maxWidth: 220)
        .onAppear {
            value = min(max(value, range.lowerBound), range.upperBound)
        }
    }
}

public struct DoubleDropdown: View {
    @Binding public var value: Double
    public let range: ClosedRange<Int>
    public let step: Double
    public let label: String

    public init(_ label: String, value: Binding<Double>, range: ClosedRange<Int>, step: Double = 1.0) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
    }

    private var values: [Double] {
        let count = Int((Double(range.upperBound - range.lowerBound) / step).rounded(.down))
        return (0...count).map { index in
            Double(range.lowerBound) + (Double(index) * step)
        }.filter { $0 <= Double(range.upperBound) + 0.000001 }
    }

    public var body: some View {
        Picker(label, selection: $value) {
            ForEach(values, id: \.self) { item in
                Text(item.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))))
                    .tag(item)
            }
        }
        .pickerStyle(.menu)
        .menuOrder(.fixed)
        .frame(minWidth: 130, maxWidth: 220)
        .onAppear {
            let clamped = min(max(value, Double(range.lowerBound)), Double(range.upperBound))
            let nearest = values.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? Double(range.lowerBound)
            value = nearest
        }
    }
}


/// Decimal amount control for monetary values. It deliberately avoids text input:
/// the user selects whole dollars and cents independently, so values such as
/// $2.50 remain easy to enter even when macOS text fields are unreliable.
public struct DecimalAmountDropdown: View {
    @Binding public var value: Double
    public let range: ClosedRange<Int>
    public let label: String

    public init(_ label: String, value: Binding<Double>, range: ClosedRange<Int>) {
        self.label = label
        self._value = value
        self.range = range
    }

    private var normalizedCents: Int {
        let raw = Int((value * 100.0).rounded())
        let minimum = range.lowerBound * 100
        let maximum = range.upperBound * 100
        return min(max(raw, minimum), maximum)
    }

    private var wholeDollars: Int {
        normalizedCents / 100
    }

    private var cents: Int {
        normalizedCents % 100
    }

    private var wholeBinding: Binding<Int> {
        Binding(
            get: { wholeDollars },
            set: { newWhole in
                let clampedWhole = min(max(newWhole, range.lowerBound), range.upperBound)
                let proposed = clampedWhole * 100 + cents
                let minimum = range.lowerBound * 100
                let maximum = range.upperBound * 100
                value = Double(min(max(proposed, minimum), maximum)) / 100.0
            }
        )
    }

    private var centsBinding: Binding<Int> {
        Binding(
            get: { cents },
            set: { newCents in
                let clampedCents = min(max(newCents, 0), 99)
                let proposed = wholeDollars * 100 + clampedCents
                let minimum = range.lowerBound * 100
                let maximum = range.upperBound * 100
                value = Double(min(max(proposed, minimum), maximum)) / 100.0
            }
        )
    }

    public var body: some View {
        HStack(spacing: 4) {
            Picker("(label) dollars", selection: wholeBinding) {
                ForEach(Array(range), id: \.self) { item in
                    Text("\(item)").tag(item)
                }
            }
            .pickerStyle(.menu)
            .menuOrder(.fixed)
            .labelsHidden()
            .frame(minWidth: 78, maxWidth: 120)

            Text(".")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("(label) cents", selection: centsBinding) {
                ForEach(0..<100, id: \.self) { item in
                    Text(String(format: "%02d", item)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .menuOrder(.fixed)
            .labelsHidden()
            .frame(minWidth: 62, maxWidth: 82)

            Text("USD")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .onAppear {
            value = Double(normalizedCents) / 100.0
        }
    }
}

public struct ContractModeDropdown: View {
    @Binding public var value: String

    public init(value: Binding<String>) {
        self._value = value
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                switch value.uppercased() {
                case "DIGITUNDER": return 0
                case "DIGITOVER": return 2
                default: return 1
                }
            },
            set: { index in
                value = ["DIGITUNDER", "BOTH", "DIGITOVER"][min(max(index, 0), 2)]
            }
        )
    }

    public var body: some View {
        Picker("Allowed Contracts", selection: selection) {
            Text("DigitUnder").tag(0)
            Text("Both").tag(1)
            Text("DigitOver").tag(2)
        }
        .pickerStyle(.menu)
        .menuOrder(.fixed)
        .frame(minWidth: 150, maxWidth: 220)
    }
}

public struct ManualContractDropdown: View {
    @Binding public var value: String

    public init(value: Binding<String>) {
        self._value = value
    }

    public var body: some View {
        Picker("Contract Type", selection: $value) {
            Text("DigitUnder").tag("DIGITUNDER")
            Text("DigitOver").tag("DIGITOVER")
            Text("Rise (CALL)").tag("CALL")
            Text("Fall (PUT)").tag("PUT")
            Text("Digit Match").tag("DIGITMATCH")
            Text("Digit Differ").tag("DIGITDIFF")
        }
        .pickerStyle(.menu)
        .menuOrder(.fixed)
        .frame(minWidth: 150, maxWidth: 220)
    }
}
