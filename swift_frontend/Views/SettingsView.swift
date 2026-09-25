import SwiftUI

public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showRealAccountConfirm = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                accountModeSection

                Section {
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(Theme.info).frame(width: 22)
                        SecureField("Deriv API Token", text: $viewModel.config.api_token)
                    }

                    HStack {
                        Image(systemName: "number").foregroundColor(Theme.info).frame(width: 22)
                        Text("App ID")
                        Spacer()
                        TextField("App ID", value: $viewModel.config.app_id, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardTypeCompat(.numberPad)
                    }

                    Picker("Market Symbol", selection: $viewModel.config.symbol) {
                        Text("Volatility 100 Index (R_100)").tag("R_100")
                        Text("Volatility 75 Index (R_75)").tag("R_75")
                        Text("Volatility 50 Index (R_50)").tag("R_50")
                        Text("Volatility 25 Index (R_25)").tag("R_25")
                        Text("Volatility 10 Index (R_10)").tag("R_10")
                        Text("1HZ100V Index (1HZ100V)").tag("1HZ100V")
                    }

                    Picker("Currency", selection: $viewModel.config.currency) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                    }
                } header: {
                    Label("Account & Credentials", systemImage: "person.crop.circle.fill")
                }

                Section {
                    labeledNumberField("Base Stake ($)", value: $viewModel.config.base_stake)
                    labeledNumberField("Max Stake Limit ($)", value: $viewModel.config.max_stake)
                    labeledNumberField("Martingale Multiplier", value: $viewModel.config.martingale)
                } header: {
                    Label("Stake & Martingale Settings", systemImage: "chart.line.uptrend.xyaxis")
                }

                Section {
                    labeledNumberField("Take Profit ($)", value: $viewModel.config.take_profit)
                    labeledNumberField("Stop Loss ($)", value: $viewModel.config.stop_loss)

                    HStack {
                        Text("Max Runs / Trades")
                        Spacer()
                        TextField("Max Runs", value: $viewModel.config.max_runs, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardTypeCompat(.numberPad)
                    }

                    HStack {
                        Text("Max Loss Streak")
                        Spacer()
                        TextField("Max Loss Streak", value: $viewModel.config.max_loss_streak, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardTypeCompat(.numberPad)
                    }
                } header: {
                    Label("Risk & Profit Targets", systemImage: "shield.fill")
                }

                Section {
                    Stepper("Under Trigger Digit: \(viewModel.config.under_trigger_digit)", value: $viewModel.config.under_trigger_digit, in: 0...9)
                    Stepper("Over Trigger Digit: \(viewModel.config.over_trigger_digit)", value: $viewModel.config.over_trigger_digit, in: 0...9)
                    Stepper("Win Prediction Digit: \(viewModel.config.win_predict_digit)", value: $viewModel.config.win_predict_digit, in: 0...9)
                    Stepper("Loss Prediction Digit: \(viewModel.config.loss_predict_digit)", value: $viewModel.config.loss_predict_digit, in: 0...9)
                    Stepper("Recovery Wins Target: \(viewModel.config.recovery_wins_required)", value: $viewModel.config.recovery_wins_required, in: 1...10)
                } header: {
                    Label("Digit Strategy Rules", systemImage: "die.face.5.fill")
                }

                Section {
                    Button(action: { viewModel.saveConfig() }) {
                        HStack {
                            Spacer()
                            if viewModel.isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Save Settings").fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(Theme.brandStart)

                    Button(role: .destructive, action: { viewModel.resetToDefaults() }) {
                        HStack {
                            Spacer()
                            Text("Reset All to Defaults")
                            Spacer()
                        }
                    }
                }

                if let msg = viewModel.errorMessage {
                    Section { ErrorBanner(msg).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }

                if viewModel.saveSuccess {
                    Section {
                        Label("Settings saved successfully!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(Theme.profit)
                    }
                }
            }
            .navigationTitle("Bot Settings")
            .confirmationDialog(
                "Switch to a real-money account?",
                isPresented: $showRealAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Switch to Real Account", role: .destructive) {
                    viewModel.config.account_type = "real"
                }
                Button("Stay on Demo", role: .cancel) {}
            } message: {
                Text("The bot will place trades using real funds from your Deriv account. Make sure your risk settings below are correct before switching.")
            }
        }
    }

    // MARK: Account mode switcher

    private var accountModeSection: some View {
        Section {
            Picker("Account Mode", selection: Binding(
                get: { viewModel.config.isDemo },
                set: { newIsDemo in
                    if newIsDemo {
                        viewModel.config.account_type = "demo"
                    } else {
                        showRealAccountConfirm = true
                    }
                }
            )) {
                Text("Demo").tag(true)
                Text("Real").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            HStack(spacing: 8) {
                Image(systemName: viewModel.config.isDemo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(viewModel.config.isDemo ? Theme.info : Theme.warning)
                Text(viewModel.config.isDemo
                     ? "Practice mode — no real money is at risk."
                     : "Live mode — trades use real funds from your Deriv account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Label("Trading Account", systemImage: "creditcard.fill")
        }
    }

    @ViewBuilder
    private func labeledNumberField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardTypeCompat(.decimalPad)
        }
    }
}
