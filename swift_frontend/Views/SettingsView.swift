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
            .onChange(of: viewModel.config.contract_type_mode) { _, _ in
                viewModel.clampDigitBarriersForSelectedMode()
            }
            .onChange(of: selectedAccountIsDemo) { _, newIsDemo in
                guard !viewModel.isSwitchingAccount else { return }
                if newIsDemo {
                    guard viewModel.config.account_type != "demo" else { return }
                    Task {
                        let success = await viewModel.switchAccount(to: "demo", confirmRealAccount: false)
                        if !success {
                            selectedAccountIsDemo = false
                        }
                    }
                } else {
                    guard viewModel.config.account_type != "real" else { return }
                    showRealAccountConfirm = true
                }
            }
            .alert("Switch to a real-money account?", isPresented: $showRealAccountConfirm) {
                Button("Switch to Real Account", role: .destructive) {
                    Task {
                        let success = await viewModel.switchAccount(to: "real", confirmRealAccount: true)
                        if !success {
                            selectedAccountIsDemo = true
                        }
                    }
                }
                Button("Stay on Demo", role: .cancel) {
                    selectedAccountIsDemo = true
                }
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
            .disabled(viewModel.isSwitchingAccount)

            if viewModel.isSwitchingAccount {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Authenticating the selected Deriv account…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

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

    // Credentials intentionally remain text inputs as requested.
    private var credentialsCard: some View {
        settingsCard("Account & Credentials", systemImage: "person.crop.circle.fill") {
            editableRow("Deriv API Token") {
                NativeTextInput(text: $viewModel.config.api_token, placeholder: "Enter your Deriv Personal Access Token", secure: true)
                    .frame(minWidth: 260, maxWidth: 420, minHeight: 24)
            }
            editableRow("App ID") {
                NativeTextInput(text: $viewModel.config.app_id, placeholder: "Enter current Deriv App ID")
                    .frame(minWidth: 180, maxWidth: 320, minHeight: 24)
            }
            editableRow("Market Symbol") {
                if viewModel.availableSymbols.isEmpty {
                    HStack(spacing: 8) {
                        Text(viewModel.config.symbol.isEmpty ? "No symbols loaded" : viewModel.config.symbol)
                            .foregroundStyle(.secondary)
                        Button("Refresh") {
                            viewModel.loadDigitSymbols()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Picker("Market Symbol", selection: $viewModel.config.symbol) {
                        ForEach(viewModel.availableSymbols) { item in
                            Text("\(item.name) (\(item.symbol))")
                                .tag(item.symbol)
                        }
                    }
                    .pickerStyle(.menu)
                    .menuOrder(.fixed)
                    .frame(minWidth: 260, maxWidth: 420)
                }
            }
            Text("Symbols are loaded live from Deriv and limited to markets currently advertising DigitOver/DigitUnder contracts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            editableRow("Currency") {
                NativeTextInput(text: $viewModel.config.currency, placeholder: "e.g. USD")
                    .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
            }
        }
    }

    private var stakeCard: some View {
        settingsCard("Stake & Martingale Settings", systemImage: "chart.line.uptrend.xyaxis") {
            Text("Stake amounts use separate whole-dollar and cents selectors — no typing required.")
                .font(.caption)
                .foregroundStyle(.secondary)
            dropdownRow("Base Stake ($)") {
                DecimalAmountDropdown("Base Stake", value: $viewModel.config.base_stake, range: 0...100)
            }
            dropdownRow("Max Stake Limit ($)") {
                DecimalAmountDropdown("Max Stake Limit", value: $viewModel.config.max_stake, range: 0...1000)
            }
            Toggle("Enable Martingale", isOn: $viewModel.config.martingale_enabled)
                .toggleStyle(.switch)
            if viewModel.config.martingale_enabled {
                dropdownRow("Martingale Multiplier") {
                    HStack(spacing: 10) {
                        DoubleDropdown("Martingale Multiplier", value: $viewModel.config.martingale, range: 0.1...50, step: 0.1)
                        Text(String(format: "%.1fx", viewModel.config.martingale))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("After a loss, the next stake is multiplied by the configured value, capped by Max Stake Limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Martingale: OFF — losses will not multiply the stake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var riskCard: some View {
        settingsCard("Risk & Profit Targets", systemImage: "shield.fill") {
            dropdownRow("Take Profit ($)") {
                DecimalAmountDropdown("Take Profit", value: $viewModel.config.take_profit, range: 0...500)
            }
            dropdownRow("Hard Stop Loss ($)") {
                DecimalAmountDropdown("Hard Stop Loss", value: $viewModel.config.stop_loss, range: 0...500)
            }
            Toggle("Auto-start after Take Profit / Stop Loss", isOn: $viewModel.config.auto_restart_after_stop)
                .toggleStyle(.switch)
            Text("When enabled, a Take Profit or Hard Stop Loss starts a fresh bot session automatically after 1 minute. A manual stop does not trigger auto-restart.")
                .font(.caption)
                .foregroundStyle(.secondary)
            dropdownRow("Max Runs / Trades") {
                IntegerDropdown("Max Runs / Trades", value: $viewModel.config.max_runs, range: 0...500)
            }
            dropdownRow("Max Loss Streak") {
                IntegerDropdown("Max Loss Streak", value: $viewModel.config.max_loss_streak, range: 0...50)
            }
        }
    }

    private var strategyCard: some View {
        settingsCard("Trading Strategy", systemImage: "chart.line.uptrend.xyaxis") {
            dropdownRow("Trading Type") {
                ContractModeDropdown(value: $viewModel.config.contract_type_mode)
            }

            if viewModel.isRiseFallMode {
                Text("Rise/Fall mode trades CALL (Rise), PUT (Fall), or follows the latest tick direction. No digit barrier is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                dropdownRow("Under Entry Trigger Digit") {
                    IntegerDropdown("Under Entry Trigger Digit", value: $viewModel.config.under_trigger_digit, range: 0...9)
                }
                dropdownRow("Over Entry Trigger Digit") {
                    IntegerDropdown("Over Entry Trigger Digit", value: $viewModel.config.over_trigger_digit, range: 0...9)
                }
                if viewModel.config.contract_type_mode.uppercased() == "BOTH" {
                    dropdownRow("BOTH — DigitUNDER Barrier") {
                        IntegerDropdown("BOTH — DigitUNDER Barrier", value: $viewModel.config.both_under_barrier, range: 1...9)
                    }
                    dropdownRow("BOTH — DigitOVER Barrier") {
                        IntegerDropdown("BOTH — DigitOVER Barrier", value: $viewModel.config.both_over_barrier, range: 0...8)
                    }
                    Text("BOTH uses separate barriers. Defaults: UNDER 4 (0-3 wins) and OVER 5 (6-9 wins), keeping the two sides at the same 40% digit probability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Enable Inverse Generator Logic", isOn: $viewModel.config.both_inverse_enabled)
                        .toggleStyle(.switch)
                    if viewModel.config.both_inverse_enabled {
                        dropdownRow("Inverse Every (hours)") {
                            IntegerDropdown("Inverse Every (hours)", value: $viewModel.config.both_inverse_interval_hours, range: 1...24)
                        }
                        Text("When enabled, BOTH alternates its digit-to-contract mapping at each wall-clock interval. Default: every 6 hours. When OFF, the normal mapping is always used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Inverse Generator Logic: OFF — BOTH stays on the normal 0-4 → OVER and 6-9 → UNDER mapping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    dropdownRow("Digit Contract Barrier (Win)") {
                        IntegerDropdown("Digit Contract Barrier (Win)", value: $viewModel.config.win_predict_digit, range: viewModel.digitBarrierRange)
                    }
                }
                dropdownRow("Loss Prediction Digit") {
                    IntegerDropdown("Loss Prediction Digit", value: $viewModel.config.loss_predict_digit, range: viewModel.digitBarrierRange)
                }
                dropdownRow("Recovery Win Target Prediction Digit") {
                    IntegerDropdown("Recovery Win Target Prediction Digit", value: $viewModel.config.recovery_win_predict_digit, range: viewModel.digitBarrierRange)
                }
            }

            dropdownRow("Recovery Win Target") {
                IntegerDropdown("Recovery Win Target", value: $viewModel.config.recovery_wins_required, range: 0...50)
            }
            dropdownRow("Loss Cycle Target") {
                IntegerDropdown("Loss Cycle Target", value: $viewModel.config.loss_cycle_target, range: 0...20)
            }
            Text("Recovery Win Target 0 = disabled. Loss Cycle Target 0 = disabled. If both are 0, losses do not start recovery.")
                .font(.caption)
                .foregroundStyle(.secondary)
            dropdownRow("Ticks") {
                IntegerDropdown("Ticks", value: $viewModel.config.duration, range: 0...50)
            }
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

    private func dropdownRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title).frame(minWidth: 220, alignment: .leading)
            Spacer(minLength: 8)
            control()
        }
    }
}

private extension SettingsView {
    func copyAllSettings() {
        let c = viewModel.config
        let maskedToken = c.api_token.isEmpty ? "(not set)" : String(repeating: "•", count: max(0, c.api_token.count - 4)) + c.api_token.suffix(4)
        let lines = [
            "DERIV ENGINE — BOT SETTINGS",
            "Account Type: \(c.account_type.uppercased())",
            "API Token: \(maskedToken)",
            "App ID: \(c.app_id)",
            "Market Symbol: \(c.symbol)",
            "Currency: \(c.currency)",
            "",
            "Base Stake: $\(c.base_stake)",
            "Max Stake Limit: $\(c.max_stake)",
            c.martingale_enabled
                ? String(format: "Martingale: ON (%.1fx)", c.martingale)
                : "Martingale: OFF",
            "",
            "Take Profit: $\(c.take_profit)",
            "Hard Stop Loss: $\(c.stop_loss)",
            "Auto-start after Take Profit: \(c.auto_restart_after_take_profit ? "ON (1 minute)" : "OFF")",
            "Max Runs / Trades: \(c.max_runs)",
            "Max Loss Streak: \(c.max_loss_streak)",
            "",
            "Under Trigger Digit: \(c.under_trigger_digit)",
            "Over Trigger Digit: \(c.over_trigger_digit)",
            "Win Prediction Digit: \(c.win_predict_digit)",
            "BOTH DigitUNDER Barrier: \(c.both_under_barrier)",
            "BOTH DigitOVER Barrier: \(c.both_over_barrier)",
            "BOTH Inverse Generator: \(c.both_inverse_enabled ? "ON" : "OFF")",
            "BOTH Inverse Interval Hours: \(c.both_inverse_interval_hours)",
            "Loss Prediction Digit: \(c.loss_predict_digit)",
            "Recovery Win Target Prediction Digit: \(c.recovery_win_predict_digit)",
            "Recovery Win Target: \(c.recovery_wins_required)",
            "Loss Cycle Target: \(c.loss_cycle_target)",
            "Allowed Contracts: \(c.contract_type_mode)",
            "Ticks: \(c.duration)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
