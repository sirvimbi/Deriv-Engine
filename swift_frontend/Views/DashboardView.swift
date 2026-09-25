import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var pulse = false
    @State private var showExportSuccess = false

    public init() {}

    private let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    accountEquityStrip

                    if let err = viewModel.errorMessage {
                        ErrorBanner(err)
                    }

                    LastDigitWidget(
                        lastQuote: viewModel.lastQuote,
                        lastDigit: viewModel.lastDigit,
                        tickHistory: viewModel.tickHistory
                    )

                    metricsGrid
                    logSection
                }
                    .padding(Theme.gutter)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayModeCompat()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: copyAllDashboard) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    Button(action: exportLogs) {
                        Label("Export Logs", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Logs Exported", isPresented: $showExportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Execution logs were saved to the location you chose.")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        botStatusBadge
                        accountModeBadge
                    }

                    Text("Deriv Algorithmic Trader")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
            }

            Button(action: { viewModel.toggleBot() }) {
                HStack(spacing: 8) {
                    if viewModel.isConnecting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: viewModel.botStatus.is_running ? "stop.fill" : "play.fill")
                        Text(viewModel.botStatus.is_running ? "Stop Bot" : "Start Bot")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous)
                        .fill(viewModel.botStatus.is_running ? Color.red.opacity(0.92) : .white.opacity(0.95))
                )
                .foregroundColor(viewModel.botStatus.is_running ? .white : Theme.brandStart)
            }
            .disabled(viewModel.isConnecting)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .fill(Theme.brandGradient)
        )
        .shadow(color: Theme.brandStart.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private var botStatusBadge: some View {
        let running = viewModel.botStatus.is_running
        return HStack(spacing: 6) {
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .scaleEffect(running && pulse ? 1.7 : 1.0)
                .opacity(running ? (pulse ? 0.35 : 1.0) : 0.6)
                .animation(running ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: pulse)
            Text(running ? "BOT ACTIVE" : "BOT IDLE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.white.opacity(0.22))
        .foregroundColor(.white)
        .clipShape(Capsule())
        .onAppear { pulse = true }
    }

    private var accountModeBadge: some View {
        let isDemo = viewModel.botStatus.config.isDemo
        return HStack(spacing: 4) {
            Image(systemName: isDemo ? "flask.fill" : "bolt.fill")
                .font(.system(size: 9, weight: .bold))
            Text(isDemo ? "DEMO" : "LIVE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((isDemo ? Theme.demo : Theme.real).opacity(0.9))
        .foregroundColor(.white)
        .clipShape(Capsule())
    }

    // MARK: Equity strip

    private var accountEquityStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ACCOUNT EQUITY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.secondary)
                    if viewModel.botStatus.equity != nil {
                        Circle()
                            .fill(Theme.profit)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Live")
                    }
                }
                if let equity = viewModel.botStatus.equity {
                    Text(String(format: "$%.2f", equity))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.profit)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: equity)
                } else {
                    Text("Awaiting balance from backend…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: { viewModel.refreshEquityNow() }) {
                if viewModel.isRefreshingEquity {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help("Refresh account equity")
            .disabled(viewModel.isRefreshingEquity)

            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.brandGradient)
        }
        .cardStyle(padding: 16, radius: Theme.cornerRadiusLarge)
    }

    // MARK: Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            MetricCard(
                title: "TOTAL PROFIT",
                value: String(format: "$%.2f", viewModel.botStatus.total_profit),
                subtitle: "Target: $\(String(format: "%.0f", viewModel.botStatus.config.take_profit))",
                iconName: "dollarsign.circle.fill",
                color: viewModel.botStatus.total_profit >= 0 ? Theme.profit : Theme.loss
            )

            MetricCard(
                title: "WIN RATE",
                value: String(format: "%.1f%%", viewModel.botStatus.win_rate),
                subtitle: "Wins: \(viewModel.botStatus.total_wins) / Runs: \(viewModel.botStatus.runs)",
                iconName: "chart.bar.fill",
                color: Theme.info
            )

            MetricCard(
                title: "CURRENT STAKE",
                value: String(format: "$%.2f", viewModel.botStatus.current_stake),
                subtitle: "Base: $\(String(format: "%.0f", viewModel.botStatus.config.base_stake))",
                iconName: "banknote.fill",
                color: .purple
            )

            MetricCard(
                title: "LOSS STREAK",
                value: "\(viewModel.botStatus.loss_streak) / \(viewModel.botStatus.config.max_loss_streak)",
                subtitle: "Max Row: \(viewModel.botStatus.loss_in_row)",
                iconName: "flame.fill",
                color: viewModel.botStatus.loss_streak > 0 ? Theme.warning : .gray
            )

            MetricCard(
                title: "RECOVERY WINS",
                value: "\(viewModel.botStatus.recovery_win_count) / \(viewModel.botStatus.config.recovery_wins_required)",
                subtitle: "Target to reset base",
                iconName: "arrow.triangle.2.circlepath",
                color: .teal
            )

            MetricCard(
                title: "LOWEST BALANCE",
                value: String(format: "$%.2f", viewModel.botStatus.lowest_balance),
                subtitle: "Lowest Loss: $\(String(format: "%.2f", viewModel.botStatus.lowest_loss))",
                iconName: "arrow.down.right.circle.fill",
                color: Theme.loss
            )
        }
    }

    // MARK: Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(Theme.profit)
                Text("LIVE EXECUTION LOG")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.logs.count) entries")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 8) {
                Button(action: { viewModel.clearLogs() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button(action: copyAllDashboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: exportLogs) {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .controlSize(.small)

            // Newest entries render at the top (list is reversed below), and
            // the ScrollViewReader forces the view back to that newest entry
            // whenever the log count changes — so the latest line is always
            // on screen without the user needing to scroll for it.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.logs.reversed()) { log in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(log.timestamp)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)

                                Text(log.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(logColor(log.level))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .id(log.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 190)
                .textSelection(.enabled)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous))
                .onChange(of: viewModel.logs.count) { _, _ in
                    scrollToNewestLog(proxy)
                }
                .onAppear {
                    scrollToNewestLog(proxy)
                }
            }
        }
    }

    private func scrollToNewestLog(_ proxy: ScrollViewProxy) {
        guard let newestID = viewModel.logs.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(newestID, anchor: .top)
        }
    }

    private func logColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "success": return .green
        case "error": return .red
        case "warn": return .orange
        default: return .white
        }
    }
}

// Small helper so this file compiles identically on macOS (no navigationBarTitleDisplayMode there).
private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeCompat() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}


private extension DashboardView {
    func copyAllDashboard() {
        let status = viewModel.botStatus
        var lines: [String] = [
            "DERIV ENGINE BOT SNAPSHOT",
            "Status: \(status.is_running ? "RUNNING" : "STOPPED")",
            "Market: \(status.config.symbol)",
            "Account: \(status.config.account_type.uppercased())",
            "Contract Mode: \(status.config.contract_type_mode)",
            String(format: "Total Profit: $%.2f", status.total_profit),
            "Runs: \(status.runs)",
            "Wins: \(status.total_wins)",
            "Losses: \(status.total_losses)",
            String(format: "Win Rate: %.2f%%", status.win_rate),
            String(format: "Current Stake: $%.2f", status.current_stake),
            "Current Prediction: \(status.current_predict)",
            "Loss Streak: \(status.loss_streak)",
            "Recovery Wins: \(status.recovery_win_count)/\(status.config.recovery_wins_required)",
            "Take Profit: $\(status.config.take_profit)",
            "Stop Loss: $\(status.config.stop_loss)",
            "Max Runs: \(status.config.max_runs)",
            "Max Loss Streak: \(status.config.max_loss_streak)",
        ]
        if let equity = status.equity {
            lines.insert(String(format: "Account Equity: $%.2f", equity), at: 2)
        }
        lines.append(contentsOf: ["", "EXECUTION LOGS"])
        lines.append(contentsOf: viewModel.logs.map { "[\($0.timestamp)] [\($0.level.uppercased())] \($0.message)" })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "deriv-execution-logs.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let header = "Timestamp,Level,Message\n"
            let rows = viewModel.logs.map {
                "\($0.timestamp),\($0.level.csvEscaped),\($0.message.csvEscaped)"
            }.joined(separator: "\n")
            do {
                try (header + rows + "\n").write(to: url, atomically: true, encoding: .utf8)
                showExportSuccess = true
            } catch {
                print("Failed to export logs: \(error.localizedDescription)")
            }
        }
    }
}

private extension String {
    var csvEscaped: String {
        return "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
