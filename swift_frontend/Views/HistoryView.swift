import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showClearSessionsConfirmation = false
    @State private var showMessageAlert = false
    @State private var messageAlertTitle = ""
    @State private var messageAlertBody = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("History Type", selection: $viewModel.selectedTab) {
                    Text("Statement").tag(0)
                    Text("Profit Table").tag(1)
                    Text("Sessions").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 12)
                .onChange(of: viewModel.selectedTab) { _, _ in
                    viewModel.refreshNow()
                }

                if viewModel.selectedTab == 2 {
                    sessionArchiveSummary
                } else {
                    summaryBanner
                }

                Group {
                    if viewModel.selectedTab == 2 {
                        sessionArchiveContent
                    } else if viewModel.isLoading {
                        Spacer()
                        ProgressView("Fetching transactions from Deriv…")
                        Spacer()
                    } else if let err = viewModel.errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            ErrorBanner(err) { viewModel.loadHistory(force: true) }
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else if viewModel.transactions.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 34))
                                .foregroundColor(.secondary)
                            Text("No transactions found.")
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    } else {
                        List(viewModel.transactions) { tx in
                            transactionRow(tx)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(PlainListStyle())
                        .refreshable { viewModel.loadHistory(force: true) }
                    }
                }
            }
            .textSelection(.enabled)
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItemGroup(placement: toolbarPlacement) {
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Syncing")
                    }
                    if viewModel.selectedTab == 2 {
                        Button(action: exportSessionArchive) {
                            Label("Export CSV", systemImage: "square.and.arrow.down")
                        }
                        Button(action: { showClearSessionsConfirmation = true }) {
                            Label("Clear Archive", systemImage: "trash")
                        }
                    } else {
                        Button(action: copyAllTransactions) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                        Button(action: { viewModel.clearSession() }) {
                            Label("Clear View", systemImage: "trash")
                        }
                    }
                    Button(action: { viewModel.refreshNow() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .confirmationDialog("Clear saved session history?", isPresented: $showClearSessionsConfirmation, titleVisibility: .visible) {
                Button("Clear Archive", role: .destructive) {
                    viewModel.clearArchivedSessions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the saved session archive. If the bot is running, a new archive segment will start and later trades will continue to be saved.")
            }
            .alert(messageAlertTitle, isPresented: $showMessageAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(messageAlertBody)
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .primaryAction
        #endif
    }

    // MARK: Summary

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOTAL PROFIT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                Text(String(format: "$%.2f", viewModel.totalProfitSummary))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(viewModel.totalProfitSummary >= 0 ? Theme.profit : Theme.loss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 30)

            VStack(alignment: .trailing, spacing: 3) {
                Text("TRADES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text("\(viewModel.totalTradesCount)")
                        .font(.system(size: 15, weight: .bold))
                    Text("W \(viewModel.winCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(Theme.profit)
                    Text("L \(viewModel.lossCount)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(Theme.loss)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: Saved session archive

    private var sessionArchiveSummary: some View {
        let sessions = viewModel.archivedSessions
        let trades = sessions.reduce(0) { $0 + $1.summary.trade_count }
        let profit = sessions.reduce(0.0) { $0 + $1.summary.total_profit }
        let wins = sessions.reduce(0) { $0 + $1.summary.wins }
        let losses = sessions.reduce(0) { $0 + $1.summary.losses }
        return HStack(spacing: 12) {
            summaryMetric(title: "SAVED SESSIONS", value: "\(sessions.count)")
            Divider().frame(height: 34)
            summaryMetric(title: "TRADES", value: "\(trades)  W \(wins) / L \(losses)")
            Divider().frame(height: 34)
            VStack(alignment: .trailing, spacing: 3) {
                Text("ARCHIVED P/L")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(String(format: "%@$%.2f", profit >= 0 ? "+" : "-", abs(profit)))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(profit >= 0 ? Theme.profit : Theme.loss)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sessionArchiveContent: some View {
        if viewModel.isLoading && viewModel.archivedSessions.isEmpty {
            Spacer()
            ProgressView("Loading saved sessions…")
            Spacer()
        } else if viewModel.archivedSessions.isEmpty, let err = viewModel.errorMessage {
            Spacer()
            ErrorBanner(err) { viewModel.loadHistory(force: true) }
                .padding(.horizontal)
            Spacer()
        } else if viewModel.archivedSessions.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("No saved sessions yet.")
                    .foregroundColor(.secondary)
                Text("Start and stop the bot to build a permanent session record.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let err = viewModel.errorMessage {
                        ErrorBanner(err) { viewModel.loadHistory(force: true) }
                    }
                    ForEach(viewModel.archivedSessions) { session in
                        sessionCard(session)
                    }
                }
                .padding(12)
            }
            .refreshable { viewModel.loadHistory(force: true) }
        }
    }

    private func sessionCard(_ session: TradingSessionRecord) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Text("SETUP")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.secondary)
                setupLine("Market / Account", "\(session.setup.symbol) • \(session.setup.account_type.uppercased()) • \(session.setup.currency)")
                setupLine("Mode", session.setup.contract_type_mode)
                setupLine("Entry digits", "UNDER trigger \(session.setup.under_trigger_digit) • OVER trigger \(session.setup.over_trigger_digit)")
                setupLine("Barriers", "Win \(session.setup.win_predict_digit) • BOTH UNDER \(session.setup.both_under_barrier) / OVER \(session.setup.both_over_barrier)")
                setupLine("Stake", "Base $\(money(session.setup.base_stake)) • Max $\(money(session.setup.max_stake)) • Max used $\(money(session.summary.max_trade_stake))")
                setupLine("Take Profit / Stop Loss", "$\(money(session.setup.take_profit)) / $\(money(session.setup.stop_loss))")
                setupLine("Adaptive TP", adaptiveTPDescription(session.setup))
                setupLine("Adaptive SL", adaptiveSLDescription(session.setup))
                setupLine("Recovery", "Wins \(session.setup.recovery_wins_required) • Loss cycle \(session.setup.loss_cycle_target) • Martingale \(session.setup.martingale_enabled ? "ON ×\(session.setup.martingale)" : "OFF")")
                setupLine("Duration", "\(session.setup.duration) \(session.setup.duration_unit == "t" ? "ticks" : "seconds") • Inverse logic \(session.setup.both_inverse_enabled ? "ON" : "OFF") / \(session.setup.both_inverse_interval_hours)h")
                if let reason = session.stop_reason, !reason.isEmpty {
                    setupLine("Stop reason", reason)
                }

                Divider()
                HStack {
                    Text("SETTLED TRADES")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Total stake $\(money(session.summary.total_stake))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if session.trades.isEmpty {
                    Text("No settled trades were recorded in this session.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(session.trades) { trade in
                        sessionTradeRow(trade)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(session.setup.symbol) • \(session.setup.contract_type_mode)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("\(dateText(session.started_at))  →  \(session.finished_at.map(dateText) ?? "Running")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(session.status.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background((session.status == "running" ? Theme.info : Theme.brandStart).opacity(0.15))
                        .clipShape(Capsule())
                }
                HStack(spacing: 10) {
                    Text("\(session.summary.trade_count) trades")
                    Text("W \(session.summary.wins)")
                        .foregroundColor(Theme.profit)
                    Text("L \(session.summary.losses)")
                        .foregroundColor(Theme.loss)
                    Text("BE \(session.summary.break_even)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%@$%.2f", session.summary.total_profit >= 0 ? "+" : "-", abs(session.summary.total_profit)))
                        .fontWeight(.heavy)
                        .foregroundColor(session.summary.total_profit >= 0 ? Theme.profit : Theme.loss)
                }
                .font(.caption)
                Text("Base stake $\(money(session.setup.base_stake)) • TP $\(money(session.setup.take_profit)) • SL $\(money(session.setup.stop_loss)) • Duration \(durationText(session))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous))
    }

    private func setupLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 145, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func sessionTradeRow(_ trade: TradingSessionTrade) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("#\(trade.contract_id.map { String($0) } ?? "—") • \(trade.contract_type)\(trade.barrier.map { " \($0)" } ?? "")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text(String(format: "%@$%.2f", trade.profit >= 0 ? "+" : "-", abs(trade.profit)))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(trade.outcome == "WIN" ? Theme.profit : (trade.outcome == "LOSS" ? Theme.loss : .secondary))
            }
            HStack(spacing: 8) {
                Text(dateText(trade.placed_at) + " → " + (trade.settled_at.map(dateText) ?? "Open"))
                Text("Stake $\(money(trade.stake))")
                Text("Buy $\(money(trade.buy_price))")
                if let payout = trade.payout { Text("Payout $\(money(payout))") }
                Text(trade.outcome)
                    .fontWeight(.bold)
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            HStack(spacing: 8) {
                if let digit = trade.entry_signal_digit { Text("Entry digit \(digit)") }
                if let digit = trade.generator_digit { Text("Generator \(digit)") }
                if let digit = trade.exit_digit { Text("Exit digit \(digit)") }
                if let spot = trade.entry_spot { Text("Entry \(spot)") }
                if let spot = trade.exit_spot { Text("Exit \(spot)") }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary)
            HStack(spacing: 8) {
                if let activeTP = trade.active_take_profit { Text("Active TP $\(money(activeTP))") }
                if let activeSL = trade.active_stop_loss { Text("Active SL $\(money(activeSL))") }
                if let rate = trade.rolling_win_rate { Text("TP WR \(rate, specifier: "%.1f")%") }
                if let rate = trade.sl_rolling_win_rate { Text("SL WR \(rate, specifier: "%.1f")%") }
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
        .padding(9)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func adaptiveTPDescription(_ setup: TradingSessionSetup) -> String {
        guard setup.adaptive_performance_enabled else { return "OFF" }
        return "ON • benchmark \(String(format: "%.1f", setup.adaptive_target_win_rate))% • stop ≤ \(String(format: "%.1f", setup.adaptive_stop_win_rate))% • min sample \(setup.adaptive_minimum_sample_size) • window \(setup.adaptive_rolling_window == 0 ? "All session" : "\(setup.adaptive_rolling_window)")"
    }

    private func adaptiveSLDescription(_ setup: TradingSessionSetup) -> String {
        guard setup.adaptive_stop_loss_enabled else { return "OFF" }
        return "ON • \(String(format: "%.1f", setup.adaptive_stop_loss_min_win_rate))%–\(String(format: "%.1f", setup.adaptive_stop_loss_max_win_rate))% • window \(setup.adaptive_stop_loss_rolling_window == 0 ? "All session" : "\(setup.adaptive_stop_loss_rolling_window)")"
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func dateText(_ epoch: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    private func durationText(_ session: TradingSessionRecord) -> String {
        guard let seconds = session.duration_seconds else { return "in progress" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let remainder = Int(seconds) % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }

    private func exportSessionArchive() {
        Task { @MainActor in
            do {
                let data = try await APIService.shared.exportSessionHistoryCSV()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.commaSeparatedText]
                panel.nameFieldStringValue = "deriv-session-history.csv"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url, options: .atomic)
                    messageAlertTitle = "Session History Exported"
                    messageAlertBody = "The complete saved session archive was exported to the selected CSV file."
                    showMessageAlert = true
                }
            } catch {
                messageAlertTitle = "Export Failed"
                messageAlertBody = error.localizedDescription
                showMessageAlert = true
            }
        }
    }

    // MARK: Row

    private func transactionRow(_ tx: Transaction) -> some View {
        let diff: Double?
        if let p = tx.profit {
            diff = p
        } else if let sp = tx.sell_price, let bp = tx.buy_price {
            diff = sp - bp
        } else if let payout = tx.payout, let bp = tx.buy_price {
            diff = payout - bp
        } else {
            diff = nil
        }
        let isUp = (diff ?? 0) >= 0

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill((isUp ? Theme.profit : Theme.loss).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(isUp ? Theme.profit : Theme.loss)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((tx.action ?? tx.action_type)?.capitalized ?? tx.symbol ?? "Option Trade")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if let code = tx.longcode {
                    Text(code)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(tx.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let diff {
                    Text(String(format: "%@$%.2f", diff >= 0 ? "+" : "", diff))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(diff >= 0 ? Theme.profit : Theme.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let amt = tx.amount ?? tx.buy_price {
                    Text("Stake: $\(String(format: "%.2f", amt))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .cardStyle(padding: 14, radius: Theme.cornerRadiusMedium)
    }
}

private extension HistoryView {
    func copyAllTransactions() {
        var lines: [String] = [
            "DERIV ENGINE TRANSACTIONS — \(viewModel.selectedTab == 0 ? "STATEMENT" : "PROFIT TABLE")",
            String(format: "Total Profit: $%.2f", viewModel.totalProfitSummary),
            "Trades: \(viewModel.totalTradesCount)  Wins: \(viewModel.winCount)  Losses: \(viewModel.lossCount)",
            ""
        ]
        for tx in viewModel.transactions {
            let label = (tx.action ?? tx.action_type)?.capitalized ?? tx.symbol ?? "Option Trade"
            let stake = tx.amount ?? tx.buy_price ?? 0
            lines.append("[\(tx.formattedTime)] \(label) — Stake $\(String(format: "%.2f", stake))")
            if let code = tx.longcode {
                lines.append("    \(code)")
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
