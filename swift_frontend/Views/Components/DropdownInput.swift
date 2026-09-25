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
