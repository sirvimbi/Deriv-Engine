import SwiftUI

public struct ManualTradeView: View {
    @StateObject private var viewModel = ManualTradeViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard("Trade Configuration", systemImage: "slider.horizontal.3") {
                        editableRow("Symbol") {
                            NativeEditableField(text: $viewModel.symbol, placeholder: "e.g. R_100")
                                .frame(width: 300, height: 26)
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
                            .frame(width: 220)
                        }

                        editableRow("Stake Amount ($)") {
                            NativeNumberField(value: $viewModel.amount, placeholder: "Stake amount")
                                .frame(width: 180, height: 26)
                        }

                        if viewModel.contractType.contains("DIGIT") {
                            editableRow("Prediction Digit") {
                                NativeIntegerField(value: $viewModel.prediction, placeholder: "0-9", range: 0...9)
                                    .frame(width: 180, height: 26)
                            }
                        }

                        editableRow("Duration (Ticks)") {
                            NativeIntegerField(value: $viewModel.duration, placeholder: "1-10", range: 1...10)
                                .frame(width: 180, height: 26)
                        }

                        editableRow("Currency") {
                            NativeEditableField(text: $viewModel.currency, placeholder: "e.g. USD")
                                .frame(width: 180, height: 26)
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
            .textSelection(.enabled)
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Manual Trade")
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
                Text("Stake $\(String(format: "%.2f", viewModel.amount)) · \(viewModel.duration)t · \(viewModel.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if viewModel.contractType.contains("DIGIT") {
                    Text("Prediction: \(viewModel.prediction)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            Text(title).frame(minWidth: 180, alignment: .leading)
            Spacer(minLength: 8)
            control()
        }
    }
}
