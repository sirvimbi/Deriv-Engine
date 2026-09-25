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

    public init() {
        setupSubscriptions()
        fetchInitialData()
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
            let balance = try await APIService.shared.getAccountBalance()
            guard !Task.isCancelled else { return }
            botStatus.equity = balance
        } catch {
            // WebSocket balance subscription remains the primary live path.
            // Polling is a recovery path for dropped/misordered WS events.
        }
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
                    _ = try await APIService.shared.startBot()
                }
                self.botStatus = try await APIService.shared.getBotStatus()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
