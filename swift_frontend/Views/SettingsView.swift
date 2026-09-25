import SwiftUI
import AppKit

public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showRealAccountConfirm = false
    @State private var selectedAccountIsDemo = true

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
            // NOTE: deliberately NOT applying .textSelection(.enabled) to this
            // whole ScrollView. On macOS that modifier installs a selection
            // gesture over everything beneath it, which was intercepting
            // clicks meant for the NSViewRepresentable text fields below and
            // is why typing stopped working in every field on this screen.
            // Instead, selection is enabled individually on the plain label/
            // caption Text views further down, which is all that's needed
            // for "select and copy" without blocking keyboard input.
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Bot Settings")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: copyAllSettings) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                }
            }
            .onChange(of: viewModel.config.account_type) { _, newValue in
                let newIsDemo = newValue != "real"
                if selectedAccountIsDemo != newIsDemo { selectedAccountIsDemo = newIsDemo }
            }
            .onChange(of: selectedAccountIsDemo) { _, newIsDemo in
                DispatchQueue.main.async {
                    if newIsDemo {
                        viewModel.config.account_type = "demo"
                    } else if viewModel.config.account_type != "real" {
                        showRealAccountConfirm = true
                    }
                }
            }
            .alert("Switch to a real-money account?", isPresented: $showRealAccountConfirm) {
                Button("Switch to Real Account", role: .destructive) {
                    viewModel.config.account_type = "real"
                }
                Button("Stay on Demo", role: .cancel) { selectedAccountIsDemo = true }
            } message: {
                Text("The bot will place trades using real funds from your Deriv account. Make sure your risk settings are correct before switching.")
            }
        }
    }

    private var accountModeCard: some View {
        settingsCard("Trading Account", systemImage: "creditcard.fill") {
            Picker("Account Mode", selection: $selectedAccountIsDemo) {
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
                    .textSelection(.enabled)
            }
        }
    }

    private var credentialsCard: some View {
        settingsCard("Account & Credentials", systemImage: "person.crop.circle.fill") {
            editableRow("Deriv API Token") {
                EditableTextField(text: $viewModel.config.api_token, placeholder: "Enter your Deriv Personal Access Token", isSecure: true)
                    .frame(minWidth: 260, maxWidth: 420, minHeight: 24)
            }

            editableRow("App ID") {
                EditableTextField(text: $viewModel.config.app_id, placeholder: "Enter current Deriv App ID")
                    .frame(minWidth: 180, maxWidth: 320, minHeight: 24)
            }

            editableRow("Market Symbol") {
                EditableTextField(text: $viewModel.config.symbol, placeholder: "e.g. R_100")
                    .frame(minWidth: 160, maxWidth: 320, minHeight: 26)
            }

            editableRow("Currency") {
                EditableTextField(text: $viewModel.config.currency, placeholder: "e.g. USD")
                    .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
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
            editableDigitRow("Under Trigger Digit", value: $viewModel.config.under_trigger_digit)
            editableDigitRow("Over Trigger Digit", value: $viewModel.config.over_trigger_digit)
            editableDigitRow("Win Prediction Digit", value: $viewModel.config.win_predict_digit)
            editableDigitRow("Loss Prediction Digit", value: $viewModel.config.loss_predict_digit)
            editableDigitRow("Recovery Wins Target", value: $viewModel.config.recovery_wins_required, range: 1...10)

            editableRow("Allowed Contract Types") {
                Picker("", selection: $viewModel.config.contract_type_mode) {
                    Text("DIGITUNDER").tag("DIGITUNDER")
                    Text("DIGITOVER").tag("DIGITOVER")
                    Text("Both").tag("BOTH")
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 240, maxWidth: 340)
            }

            Text("Controls which digit contract types the strategy is allowed to place. Both preserves the existing UNDER/OVER recovery behavior.")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
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
            Text(title)
                .frame(minWidth: 180, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            control()
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        editableRow(title) {
            EditableNumberField(value: value, placeholder: title)
                .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
        }
    }

    private func integerRow(_ title: String, value: Binding<Int>) -> some View {
        editableRow(title) {
            EditableIntegerField(value: value, placeholder: title)
                .frame(minWidth: 100, maxWidth: 200, minHeight: 26)
        }
    }

    private func editableDigitRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int> = 0...9) -> some View {
        editableRow(title) {
            EditableIntegerField(value: value, placeholder: title, range: range)
                .frame(minWidth: 100, maxWidth: 200, minHeight: 26)
        }
    }
}

private extension SettingsView {
    func copyAllSettings() {
        let c = viewModel.config
        let maskedToken = c.api_token.isEmpty
            ? "(not set)"
            : String(repeating: "•", count: max(0, c.api_token.count - 4)) + c.api_token.suffix(4)
        let lines: [String] = [
            "DERIV ENGINE — BOT SETTINGS",
            "Account Type: \(c.account_type.uppercased())",
            "API Token: \(maskedToken)",
            "App ID: \(c.app_id)",
            "Market Symbol: \(c.symbol)",
            "Currency: \(c.currency)",
            "",
            String(format: "Base Stake: $%.2f", c.base_stake),
            String(format: "Max Stake Limit: $%.2f", c.max_stake),
            "Martingale Multiplier: \(c.martingale)x",
            "",
            String(format: "Take Profit: $%.2f", c.take_profit),
            String(format: "Stop Loss: $%.2f", c.stop_loss),
            "Max Runs / Trades: \(c.max_runs)",
            "Max Loss Streak: \(c.max_loss_streak)",
            "",
            "Under Trigger Digit: \(c.under_trigger_digit)",
            "Over Trigger Digit: \(c.over_trigger_digit)",
            "Win Prediction Digit: \(c.win_predict_digit)",
            "Loss Prediction Digit: \(c.loss_predict_digit)",
            "Recovery Wins Target: \(c.recovery_wins_required)",
            "Allowed Contract Types: \(c.contract_type_mode)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - SwiftUI editing controls

/// These controls intentionally keep a local String while the field has focus.
/// Updating a Double/Int binding on every keystroke makes empty/intermediate
/// values impossible to represent and can cause SwiftUI to rebuild the field
/// while macOS is processing the key event. Local drafts avoid that responder
/// churn and allow normal typing, deletion, selection and paste on macOS 26.
private struct EditableTextField: View {
    @Binding var text: String
    let placeholder: String
    var isSecure = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $draft)
            } else {
                TextField(placeholder, text: $draft)
            }
        }
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onAppear { draft = text }
        .onChange(of: focused) { _, isFocused in
            if isFocused { draft = text }
            else { text = draft }
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
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    draft = String(format: "%.2f", value)
                } else if let parsed = Double(draft.replacingOccurrences(of: ",", with: ".")) {
                    value = parsed
                    draft = String(format: "%.2f", parsed)
                } else {
                    draft = String(format: "%.2f", value)
                }
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

    init(value: Binding<Int>, placeholder: String, range: ClosedRange<Int> = Int.min...Int.max) {
        self._value = value
        self.placeholder = placeholder
        self.range = range
    }

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = String(value) }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    draft = String(value)
                } else {
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
