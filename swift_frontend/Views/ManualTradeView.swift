import SwiftUI

public struct ManualTradeView: View {
    @StateObject private var viewModel = ManualTradeViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Symbol", selection: $viewModel.symbol) {
                        Text("Volatility 100 Index (R_100)").tag("R_100")
                        Text("Volatility 75 Index (R_75)").tag("R_75")
                        Text("Volatility 50 Index (R_50)").tag("R_50")
                        Text("Volatility 25 Index (R_25)").tag("R_25")
                        Text("Volatility 10 Index (R_10)").tag("R_10")
                    }

                    Picker("Contract Type", selection: $viewModel.contractType) {
                        Text("DIGIT UNDER").tag("DIGITUNDER")
                        Text("DIGIT OVER").tag("DIGITOVER")
                        Text("RISE (CALL)").tag("CALL")
                        Text("FALL (PUT)").tag("PUT")
                        Text("DIGIT MATCH").tag("DIGITMATCH")
                        Text("DIGIT DIFF").tag("DIGITDIFF")
                    }

                    HStack {
                        Text("Stake Amount ($)")
                        Spacer()
                        TextField("Amount", value: $viewModel.amount, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardTypeCompat(.decimalPad)
                            .frame(minWidth: 70)
                    }

                    if viewModel.contractType.contains("DIGIT") {
                        Stepper(value: $viewModel.prediction, in: 0...9) {
                            HStack {
                                Text("Prediction Digit")
                                Spacer()
                                Text("\(viewModel.prediction)")
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.brandStart)
                            }
                        }
                    }

                    HStack {
                        Text("Duration (Ticks)")
                        Spacer()
                        Stepper("\(viewModel.duration) t", value: $viewModel.duration, in: 1...10)
                            .fixedSize()
                    }
                } header: {
                    Label("Trade Configuration", systemImage: "slider.horizontal.3")
                }

                Section {
                    tradeSummaryRow
                }

                Section {
                    Button(action: { viewModel.executeTrade() }) {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Execute Manual Trade").fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(
                        LinearGradient(colors: [Theme.profit, Theme.profit.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                    )
                    .disabled(viewModel.isSubmitting)
                }

                if let result = viewModel.lastResult {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.profit)
                    } header: {
                        Text("Execution Output")
                    }
                }

                if let err = viewModel.errorMessage {
                    Section {
                        ErrorBanner(err)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Manual Options")
        }
    }

    private var tradeSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundColor(Theme.info)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.contractType) · \(viewModel.symbol)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Stake $\(String(format: "%.2f", viewModel.amount)) for \(viewModel.duration)t in \(viewModel.currency)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
