import Foundation
import Combine

public struct TradeLogRow: Identifiable, Equatable {
    public let id: String
    public let contractType: String
    public let buyPrice: Double
    public let stake: Double
    public let profitLoss: Double
    public let isWin: Bool
}

@MainActor
public class DashboardViewModel: ObservableObject {
    @Published public var botStatus: BotStatus = BotStatus.defaultStatus
    @Published public var logs: [LogMessage] = []

    /// A compact, tabular projection of the execution log. The backend log
    /// remains the source of truth; rows are reconstructed from the placement
    /// and settlement messages so the table stays synchronized with Clear,
    /// live updates, copy and export without a second persistence path.
    public var tradeLogRows: [TradeLogRow] {
        var pending: [(id: String, type: String, buyPrice: Double, stake: Double)] = []
        var rows: [TradeLogRow] = []

        let placementPattern = #"Contract #(\d+) placed\. Type=(DIGITUNDER|DIGITOVER|BOTH).*?(?:BuyPrice=\$([0-9]+(?:\.[0-9]+)?)\s*\|\s*)?Stake=\$([0-9]+(?:\.[0-9]+)?)"#
        let outcomePattern = #"Trade (WON|LOST)! ([+-])\$([0-9]+(?:\.[0-9]+)?)"#

        guard let placementRegex = try? NSRegularExpression(pattern: placementPattern),
              let outcomeRegex = try? NSRegularExpression(pattern: outcomePattern) else {
            return rows
        }

        for log in logs {
            let message = log.message
            let nsRange = NSRange(message.startIndex..<message.endIndex, in: message)

            if let match = placementRegex.firstMatch(in: message, range: nsRange),
               let idRange = Range(match.range(at: 1), in: message),
               let typeRange = Range(match.range(at: 2), in: message),
               let stakeRange = Range(match.range(at: 4), in: message),
               let stake = Double(message[stakeRange]) {
                let buyPrice: Double
                if match.range(at: 3).location != NSNotFound,
                   let buyPriceRange = Range(match.range(at: 3), in: message),
                   let parsedBuyPrice = Double(message[buyPriceRange]) {
                    buyPrice = parsedBuyPrice
                } else {
                    // Older execution logs did not contain BuyPrice, so use
                    // the recorded stake as the backward-compatible value.
                    buyPrice = stake
                }

                pending.append((
                    id: String(message[idRange]),
                    type: String(message[typeRange]).uppercased(),
                    buyPrice: buyPrice,
                    stake: stake
                ))
                continue
            }

            if let match = outcomeRegex.firstMatch(in: message, range: nsRange),
               let resultRange = Range(match.range(at: 1), in: message),
               let signRange = Range(match.range(at: 2), in: message),
               let amountRange = Range(match.range(at: 3), in: message),
               let amount = Double(message[amountRange]),
               !pending.isEmpty {
                let result = String(message[resultRange])
                let sign = String(message[signRange])
                let pnl = (sign == "-" ? -amount : amount)
                let trade = pending.removeFirst()
                rows.append(
                    TradeLogRow(
                        id: trade.id,
                        contractType: trade.type,
                        buyPrice: trade.buyPrice,
                        stake: trade.stake,
                        profitLoss: pnl,
                        isWin: result == "WON" || pnl > 0
                    )
                )
            }
        }

        return rows
    }
    @Published public var lastQuote: Double? = nil
    @Published public var lastDigit: Int? = nil
    @Published public var tickHistory: [Int] = [] // recent last digits
    @Published public var isConnecting: Bool = false
    @Published public var errorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()
    private var equityTask: Task<Void, Never>?
    @Published public var isRefreshingEquity = false

    public init() {
        setupSubscriptions()
        fetchInitialData()
    }

    deinit {
        equityTask?.cancel()
    }

    private func setupSubscriptions() {
        WebSocketManager.shared.$latestStatus
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.botStatus = status
                if let digit = status.last_digit {
                    self?.lastDigit = digit
                }
                if let quote = status.last_tick_quote {
                    self?.lastQuote = quote
                }
            }
            .store(in: &cancellables)

        WebSocketManager.shared.$latestTick
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tick in
                guard let self = self else { return }
                self.lastQuote = tick.quote
                self.lastDigit = tick.last_digit
                self.tickHistory.append(tick.last_digit)
                if self.tickHistory.count > 20 {
                    self.tickHistory.removeFirst()
                }
            }
            .store(in: &cancellables)

        WebSocketManager.shared.$newLogs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.logs = logs
            }
            .store(in: &cancellables)
    }

    public func fetchInitialData() {
        WebSocketManager.shared.connect()
        equityTask?.cancel()
        equityTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshEquity()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        Task {
            do {
                self.botStatus = try await APIService.shared.getBotStatus()
                self.logs = try await APIService.shared.getBotLogs()
            } catch {
                self.errorMessage = "Backend connection error: \(error.localizedDescription)"
            }
        }
    }

    private func refreshEquity() async {
        do {
            guard !Task.isCancelled else { return }
            let equity = try await APIService.shared.getAccountBalance()
            guard !Task.isCancelled else { return }
            self.applyEquity(equity)
        } catch {
            // Fall back to the status endpoint so a transient balance request
            // does not erase a previously displayed equity value.
            do {
                let latestStatus = try await APIService.shared.getBotStatus()
                guard !Task.isCancelled else { return }
                self.botStatus = latestStatus
            } catch {
                // WebSocket balance subscription remains the primary live path.
            }
        }
    }

    public func refreshEquityNow() {
        guard !isRefreshingEquity else { return }
        isRefreshingEquity = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isRefreshingEquity = false }
            do {
                let equity = try await APIService.shared.getAccountBalance()
                guard !Task.isCancelled else { return }
                self.applyEquity(equity)
            } catch {
                self.errorMessage = "Unable to refresh account equity: (error.localizedDescription)"
            }
        }
    }

    private func applyEquity(_ equity: Double) {
        let rounded = (equity * 100).rounded() / 100
        let current = botStatus
        botStatus = BotStatus(
            is_running: current.is_running,
            is_trade_in_progress: current.is_trade_in_progress,
            total_profit: current.total_profit,
            runs: current.runs,
            total_wins: current.total_wins,
            total_losses: current.total_losses,
            win_rate: current.win_rate,
            current_stake: current.current_stake,
            current_predict: current.current_predict,
            loss_streak: current.loss_streak,
            recovery_win_count: current.recovery_win_count,
            lowest_balance: current.lowest_balance,
            lowest_loss: current.lowest_loss,
            wins_in_row: current.wins_in_row,
            loss_in_row: current.loss_in_row,
            last_digit: current.last_digit,
            last_tick_quote: current.last_tick_quote,
            duration_minutes: current.duration_minutes,
            stop_reason: current.stop_reason,
            config: current.config,
            equity: rounded
        )
        WebSocketManager.shared.setLocalEquity(rounded)
    }

    public func clearLogs() {
        // Clear the visible dashboard immediately. The backend reset is best-effort
        // so a stale backend cannot make the button appear broken.
        logs.removeAll()
        WebSocketManager.shared.newLogs.removeAll()
        WebSocketManager.shared.clearServerLogs()
        Task {
            do {
                try await APIService.shared.clearBotLogs()
                logs.removeAll()
            } catch {
                errorMessage = "Unable to clear execution logs: \(error.localizedDescription)"
            }
        }
    }

    public func toggleBot() {
        Task {
            isConnecting = true
            errorMessage = nil
            do {
                if botStatus.is_running {
                    _ = try await APIService.shared.stopBot()
                } else {
                    let runtime = try await APIService.shared.getRuntime()
                    guard runtime.engine_build == "recovery-state-v3" else {
                        throw NSError(
                            domain: "BackendRuntime",
                            code: 409,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Backend is outdated (\(runtime.engine_build)). Restart the backend from the current repository before starting."]
                        )
                    }
                    _ = try await APIService.shared.startBot()
                }
                self.botStatus = try await APIService.shared.getBotStatus()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    /// Persists the current configuration to storage.
    func saveConfig() {
        // TODO: Replace with your real persistence mechanism (e.g., SwiftData, UserDefaults, Keychain, or a repository/service).
        // Example placeholder: notify a config store or write to disk.
        // configStore.save(config)
    }

    /// Refreshes any data or UI that depends on the active account.
    func refreshAfterAccountSwitch() {
        // TODO: Replace with your real refresh logic.
        // Examples: re-authenticate endpoints, reload balances, refresh open positions, and update UI bindings.
        // reloadBalances()
        // reloadOpenPositions()
        // reconnectIfNeeded()
    }
}
