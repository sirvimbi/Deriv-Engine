import SwiftUI
import AppKit

public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showRealAccountConfirm = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    accountModeCard
                    credentialsCard
                    stakeCard
                    riskCard
                    strategyCard
                    actionsCard

                    if let msg = viewModel.errorMessage {
                        ErrorBanner(msg)
                    }

                    if viewModel.saveSuccess {
                        Label("Settings saved successfully!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(Theme.profit)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Bot Settings")
            .alert("Switch to a real-money account?", isPresented: $showRealAccountConfirm) {
                Button("Switch to Real Account", role: .destructive) {
                    viewModel.config.account_type = "real"
                }
                Button("Stay on Demo", role: .cancel) {}
            } message: {
                Text("The bot will place trades using real funds from your Deriv account. Make sure your risk settings are correct before switching.")
            }
        }
    }

    private var accountModeCard: some View {
        settingsCard("Trading Account", systemImage: "creditcard.fill") {
            Picker("Account Mode", selection: Binding(
                get: { viewModel.config.isDemo },
                set: { newIsDemo in
                    if newIsDemo {
                        viewModel.config.account_type = "demo"
                    } else if viewModel.config.account_type != "real" {
                        showRealAccountConfirm = true
                    }
                }
            )) {
                Text("Demo").tag(true)
                Text("Real").tag(false)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: viewModel.config.isDemo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(viewModel.config.isDemo ? Theme.info : Theme.warning)
                Text(viewModel.config.isDemo
                     ? "Practice mode — no real money is at risk."
                     : "Live mode — trades use real funds from your Deriv account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var credentialsCard: some View {
        settingsCard("Account & Credentials", systemImage: "person.crop.circle.fill") {
            editableRow("Deriv API Token") {
                NativeEditableField(text: $viewModel.config.api_token, placeholder: "Enter your Deriv Personal Access Token", isSecure: true)
                    .frame(width: 360, height: 24)
            }

            editableRow("App ID") {
                NativeEditableField(text: $viewModel.config.app_id, placeholder: "Enter current Deriv App ID")
                    .frame(width: 260, height: 24)
            }

            editableRow("Market Symbol") {
                Picker("", selection: $viewModel.config.symbol) {
                    Text("Volatility 100 Index (R_100)").tag("R_100")
                    Text("Volatility 75 Index (R_75)").tag("R_75")
                    Text("Volatility 50 Index (R_50)").tag("R_50")
                    Text("Volatility 25 Index (R_25)").tag("R_25")
                    Text("Volatility 10 Index (R_10)").tag("R_10")
                    Text("1HZ100V Index (1HZ100V)").tag("1HZ100V")
                }
                .frame(width: 280)
            }

            editableRow("Currency") {
                Picker("", selection: $viewModel.config.currency) {
                    Text("USD").tag("USD")
                    Text("EUR").tag("EUR")
                    Text("GBP").tag("GBP")
                }
                .frame(width: 180)
            }
        }
    }

    private var stakeCard: some View {
        settingsCard("Stake & Martingale Settings", systemImage: "chart.line.uptrend.xyaxis") {
            numberRow("Base Stake ($)", value: $viewModel.config.base_stake)
            numberRow("Max Stake Limit ($)", value: $viewModel.config.max_stake)
            numberRow("Martingale Multiplier", value: $viewModel.config.martingale)
        }
    }

    private var riskCard: some View {
        settingsCard("Risk & Profit Targets", systemImage: "shield.fill") {
            numberRow("Take Profit ($)", value: $viewModel.config.take_profit)
            numberRow("Stop Loss ($)", value: $viewModel.config.stop_loss)
            integerRow("Max Runs / Trades", value: $viewModel.config.max_runs)
            integerRow("Max Loss Streak", value: $viewModel.config.max_loss_streak)
        }
    }

    private var strategyCard: some View {
        settingsCard("Digit Strategy Rules", systemImage: "die.face.5.fill") {
            stepperRow("Under Trigger Digit", value: $viewModel.config.under_trigger_digit)
            stepperRow("Over Trigger Digit", value: $viewModel.config.over_trigger_digit)
            stepperRow("Win Prediction Digit", value: $viewModel.config.win_predict_digit)
            stepperRow("Loss Prediction Digit", value: $viewModel.config.loss_predict_digit)
            stepperRow("Recovery Wins Target", value: $viewModel.config.recovery_wins_required, range: 1...10)
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
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
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandStart)
            .disabled(viewModel.isSaving)

            Button(role: .destructive, action: { viewModel.resetToDefaults() }) {
                Text("Reset All to Defaults")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        editableRow(title) {
            NativeEditableField(
                text: Binding(
                    get: { String(value.wrappedValue) },
                    set: { newValue in
                        let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                        if let parsed = Double(normalized) {
                            value.wrappedValue = parsed
                        } else if normalized.isEmpty {
                            value.wrappedValue = 0
                        }
                    }
                ),
                placeholder: title
            ).frame(width: 180, height: 24)
        }
    }

    private func integerRow(_ title: String, value: Binding<Int>) -> some View {
        editableRow(title) {
            NativeEditableField(
                text: Binding(
                    get: { String(value.wrappedValue) },
                    set: { newValue in
                        let digits = newValue.filter(\.isNumber)
                        value.wrappedValue = Int(digits) ?? 0
                    }
                ),
                placeholder: title
            ).frame(width: 180, height: 24)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int> = 0...9) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)").fontWeight(.semibold).frame(minWidth: 32)
            }.fixedSize()
        }
    }
}

private struct NativeEditableField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        field.stringValue = text
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text && !context.coordinator.isEditing {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var binding: Binding<String>
        var isEditing = false

        init(text: Binding<String>) {
            self.binding = text
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.binding.wrappedValue = value
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.binding.wrappedValue = value
                self.isEditing = false
            }
        }
    }
}
