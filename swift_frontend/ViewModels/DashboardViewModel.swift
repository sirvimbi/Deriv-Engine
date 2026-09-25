import Foundation
import Combine

@MainActor
public class DashboardViewModel: ObservableObject {
    @Published public var botStatus: BotStatus = BotStatus.defaultStatus
    @Published public var logs: [LogMessage] = []
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
