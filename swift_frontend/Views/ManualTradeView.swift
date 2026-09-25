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
                            NativeTextInput(text: $viewModel.symbol, placeholder: "e.g. R_100")
                                .frame(minWidth: 220, maxWidth: 360, minHeight: 26)
                        }

                        dropdownRow("Contract Type") {
                            ManualContractDropdown(value: $viewModel.contractType)
                        }

                        dropdownRow("Stake Amount ($)") {
                            DoubleDropdown("Stake Amount", value: $viewModel.amount, range: 0...100)
                        }

                        if viewModel.contractType.contains("DIGIT") {
                            dropdownRow("Prediction Digit") {
                                IntegerDropdown("Prediction Digit", value: $viewModel.prediction, range: 0...9)
                            }
                        }

                        dropdownRow("Duration (Ticks)") {
                            IntegerDropdown("Duration", value: $viewModel.duration, range: 0...50)
                        }

                        editableRow("Currency") {
                            NativeTextInput(text: $viewModel.currency, placeholder: "e.g. USD")
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
                            Text(result).font(.caption).foregroundColor(Theme.profit)
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
            Image(systemName: "doc.text.magnifyingglass").foregroundColor(Theme.info)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.contractType) · \(viewModel.symbol)").font(.subheadline).fontWeight(.semibold)
                Text("Stake $\(String(format: "%.2f", viewModel.amount)) · \(viewModel.duration)t · \(viewModel.currency)")
                    .font(.caption).foregroundColor(.secondary)
                if viewModel.contractType.contains("DIGIT") {
                    Text("Prediction: \(viewModel.prediction)").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func copyAllManualTrade() {
        var lines = [
            "Manual Trade Configuration",
            "Symbol: \(viewModel.symbol)",
            "Contract Type: \(viewModel.contractType)",
            String(format: "Stake: $%.2f", viewModel.amount),
            "Duration: \(viewModel.duration) tick\(viewModel.duration == 1 ? "" : "s")",
            "Currency: \(viewModel.currency)"
        ]
        if viewModel.contractType.contains("DIGIT") { lines.append("Prediction: \(viewModel.prediction)") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
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
            Text(title).frame(minWidth: 180, alignment: .leading)
            Spacer(minLength: 8)
            control()
        }
    }

    private func dropdownRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title).frame(minWidth: 180, alignment: .leading)
            Spacer(minLength: 8)
            control()
        }
    }
}
