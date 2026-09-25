import SwiftUI
import AppKit

public struct ManualTradeView: View {
    @StateObject private var viewModel = ManualTradeViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard("Trade Configuration", systemImage: "slider.horizontal.3") {
                        editableRow("Symbol") {
                            EditableTextField(text: $viewModel.symbol, placeholder: "e.g. R_100")
                                .frame(minWidth: 220, maxWidth: 360, minHeight: 26)
                        }

                        editableRow("Contract Type") {
                            Picker("", selection: $viewModel.contractType) {
                                Text("DIGIT UNDER").tag("DIGITUNDER")
                                Text("DIGIT OVER").tag("DIGITOVER")
                                Text("RISE (CALL)").tag("CALL")
                                Text("FALL (PUT)").tag("PUT")
                                Text("DIGIT MATCH").tag("DIGITMATCH")
                                Text("DIGIT DIFFER").tag("DIGITDIFF")
                            }
                            .frame(minWidth: 180, maxWidth: 260)
                        }

                        editableRow("Stake Amount ($)") {
                            EditableNumberField(value: $viewModel.amount, placeholder: "Stake amount")
                                .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                        }

                        if viewModel.contractType.contains("DIGIT") {
                            editableRow("Prediction Digit") {
                                EditableIntegerField(value: $viewModel.prediction, placeholder: "0-9", range: 0...9)
                                    .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                            }
                        }

                        editableRow("Duration (Ticks)") {
                            EditableIntegerField(value: $viewModel.duration, placeholder: "1-10", range: 1...10)
                                .frame(minWidth: 140, maxWidth: 220, minHeight: 26)
                        }

                        editableRow("Currency") {
                            EditableTextField(text: $viewModel.currency, placeholder: "e.g. USD")
                                .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
                        }
                    }

                    settingsCard("Trade Preview", systemImage: "doc.text.magnifyingglass") {
                        tradeSummaryRow
                    }

                    settingsCard("Execution", systemImage: "bolt.fill") {
                        Button(action: { viewModel.executeTrade() }) {
                            HStack {
                                Spacer()
                                if viewModel.isSubmitting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("Execute Manual Trade").fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.profit)
                        .disabled(viewModel.isSubmitting)

                        if let result = viewModel.lastResult {
                            Text(result)
                                .font(.caption)
                                .textSelection(.enabled)
                                .foregroundColor(Theme.profit)
                        }

                        if let err = viewModel.errorMessage {
                            ErrorBanner(err)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // NOTE: no blanket .textSelection(.enabled) on this ScrollView —
            // see the comment in SettingsView.swift. It was blocking keyboard
            // input into the native fields above. Selection is applied to
            // the individual label/preview Text views below instead.
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Manual Trade")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: copyAllManualTrade) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
    private var tradeSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundColor(Theme.info)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.contractType) · \(viewModel.symbol)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                Text("Stake $\(String(format: "%.2f", viewModel.amount)) · \(viewModel.duration)t · \(viewModel.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                if viewModel.contractType.contains("DIGIT") {
                    Text("Prediction: \(viewModel.prediction)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func settingsCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous).fill(Theme.cardBackground(.light)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func editableRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(minWidth: 180, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            control()
        }
    }
}

private struct EditableTextField: View {
    @Binding var text: String
    let placeholder: String
    var isSecure = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if isSecure { SecureField(placeholder, text: $draft) }
            else { TextField(placeholder, text: $draft) }
        }
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onAppear { draft = text }
        .onChange(of: focused) { _, active in
            if active { draft = text } else { text = draft }
        }
        .onChange(of: text) { _, newValue in
            if !focused && draft != newValue { draft = newValue }
        }
    }
}

private struct EditableNumberField: View {
    @Binding var value: Double
    let placeholder: String
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = String(format: "%.2f", value) }
            .onChange(of: focused) { _, active in
                if active { draft = String(format: "%.2f", value) }
                else if let parsed = Double(draft.replacingOccurrences(of: ",", with: ".")) {
                    value = parsed; draft = String(format: "%.2f", parsed)
                } else { draft = String(format: "%.2f", value) }
            }
            .onChange(of: value) { _, newValue in
                if !focused { draft = String(format: "%.2f", newValue) }
            }
    }
}

private struct EditableIntegerField: View {
    @Binding var value: Int
    let placeholder: String
    let range: ClosedRange<Int>
    @State private var draft = ""
    @FocusState private var focused: Bool
    init(value: Binding<Int>, placeholder: String, range: ClosedRange<Int>) {
        self._value = value; self.placeholder = placeholder; self.range = range
    }
    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = String(value) }
            .onChange(of: focused) { _, active in
                if active { draft = String(value) }
                else {
                    let parsed = Int(draft.filter { $0.isNumber || $0 == "-" }) ?? value
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                    draft = String(value)
                }
            }
            .onChange(of: value) { _, newValue in
                if !focused { draft = String(newValue) }
            }
    }
}

private extension ManualTradeView {
    func copyAllManualTrade() {
        var lines = [
            "DERIV ENGINE — MANUAL TRADE",
            "Symbol: \(viewModel.symbol)",
            "Contract Type: \(viewModel.contractType)",
            String(format: "Stake: $%.2f", viewModel.amount),
            "Duration: \(viewModel.duration)t",
            "Currency: \(viewModel.currency)"
        ]
        if viewModel.contractType.contains("DIGIT") {
            lines.append("Prediction Digit: \(viewModel.prediction)")
        }
        if let result = viewModel.lastResult {
            lines.append("")
            lines.append("Last Result: \(result)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
