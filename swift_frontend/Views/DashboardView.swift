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
                HStack(alignment: .top, spacing: 16) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    activityPanel
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayModeCompat()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: copySelectedActivity) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(action: exportSelectedActivity) {
                        Label("Export", systemImage: "square.and.arrow.down")
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

    // MARK: Activity panel

    private enum ActivityTab: String, CaseIterable {
        case logs = "Logs"
        case trades = "Trades"
    }

    @State private var activityTab: ActivityTab = .logs

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: activityTab == .logs ? "terminal.fill" : "tablecells.fill")
                    .foregroundColor(Theme.profit)
                Text(activityTab == .logs ? "LIVE EXECUTION LOG" : "TRADE TABLE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                Spacer()
                Text(activityTab == .logs
                     ? "\(viewModel.logs.count) entries"
                     : "\(viewModel.tradeLogRows.count) trades")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Picker("Activity", selection: $activityTab) {
                ForEach(ActivityTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button(action: { viewModel.clearLogs() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button(action: copySelectedActivity) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: exportSelectedActivity) {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .controlSize(.small)

            if activityTab == .logs {
                logList
            } else {
                tradeTable
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .fill(Color.black.opacity(0.10))
        )
    }

    private var logList: some View {
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
            .frame(minHeight: 520, maxHeight: 720)
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

    private var tradeTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("TYPE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("BUY / STAKE")
                    .frame(width: 82, alignment: .trailing)
                Text("P/L")
                    .frame(width: 78, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.16))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.tradeLogRows.reversed()) { row in
                        HStack(spacing: 0) {
                            Text(row.contractType)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(String(format: "$%.2f", row.stake))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .frame(width: 82, alignment: .trailing)

                            Text(String(format: "%@%.2f", row.profitLoss >= 0 ? "+$" : "-$", abs(row.profitLoss)))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(width: 78, alignment: .trailing)
                        }
                        .foregroundColor(row.isWin ? Theme.profit : Theme.loss)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill((row.isWin ? Theme.profit : Theme.loss).opacity(0.10))
                        )
                    }
                }
                .padding(4)
            }
        }
        .frame(minHeight: 520, maxHeight: 720)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous))
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
    func copySelectedActivity() {
        if activityTab == .logs {
            let text = viewModel.logs.map {
                "[($0.timestamp)] [($0.level.uppercased())] ($0.message)"
            }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }

        let rows = viewModel.tradeLogRows.map {
            "\($0.contractType)\t\(String(format: "$%.2f", $0.stake))\t\(String(format: "%+.2f", $0.profitLoss))"
        }
        let text = (["Contract Type\tBuy / Stake\tP/L"] + rows).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportSelectedActivity() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = activityTab == .logs
            ? "deriv-execution-logs.csv"
            : "deriv-trade-table.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let csv: String
            if activityTab == .logs {
                let header = "Timestamp,Level,Message\n"
                let rows = viewModel.logs.map {
                    "\($0.timestamp.csvEscaped),\($0.level.csvEscaped),\($0.message.csvEscaped)"
                }.joined(separator: "\n")
                csv = header + rows + "\n"
            } else {
                let header = "Contract Type,Buy / Stake,P/L\n"
                let rows = viewModel.tradeLogRows.map {
                    "\($0.contractType.csvEscaped),\(String(format: "%.2f", $0.stake).csvEscaped),\(String(format: "%.2f", $0.profitLoss).csvEscaped)"
                }.joined(separator: "\n")
                csv = header + rows + "\n"
            }

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                showExportSuccess = true
            } catch {
                print("Failed to export activity: \(error.localizedDescription)")
            }
        }
    }
}

private extension String {
    var csvEscaped: String {
        return "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
