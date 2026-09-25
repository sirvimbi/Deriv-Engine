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
        stride(from: Double(range.lowerBound), through: Double(range.upperBound), by: step).map { $0 }
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
    }
}

public struct ContractModeDropdown: View {
    @Binding public var value: String

    public init(value: Binding<String>) {
        self._value = value
    }

    public var body: some View {
        Picker("Allowed Contracts", selection: $value) {
            Text("DigitUnder").tag("DIGITUNDER")
            Text("Both").tag("BOTH")
            Text("DigitOver").tag("DIGITOVER")
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
