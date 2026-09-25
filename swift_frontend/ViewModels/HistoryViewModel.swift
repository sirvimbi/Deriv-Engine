import Foundation
import Combine

@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var transactions: [Transaction] = []
    /// Full-screen spinner — reserved for the very first load, when there is
    /// nothing on screen yet to preserve.
    @Published public var isLoading: Bool = false
    /// Small, non-blocking indicator for background/pushed refreshes so the
    /// user can see data is live without the list ever disappearing.
    @Published public var isSyncing: Bool = false
    @Published public var selectedTab: Int = 0 // 0: Statement, 1: Profit Table
    @Published public var limit: Int = 50
    @Published public var totalProfitSummary: Double = 0.0
    @Published public var totalTradesCount: Int = 0
    @Published public var winCount: Int = 0
    @Published public var lossCount: Int = 0
    @Published public var errorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var suppressAutoRefresh = false

    public init() {
        setupLiveUpdates()
        loadHistory()
        startAutoRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    private func setupLiveUpdates() {
        WebSocketManager.shared.$historyResetToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearSession()
            }
            .store(in: &cancellables)

        // Pushed the instant a trade settles server-side — this is what
        // makes the list feel instantaneous. Always silent: a push should
        // never interrupt someone reading the list.
        WebSocketManager.shared.$historyRefreshToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadHistory(force: true, silent: true)
            }
            .store(in: &cancellables)
    }

    private func startAutoRefresh() {
        // Fallback safety net only, in case a push is ever missed. Always
        // silent — the list must never flash to a spinner on its own.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.loadHistoryAsync()
            }
        }
    }

    private func loadHistoryAsync() async {
        loadHistory(silent: true)
    }

    public func refreshNow() {
        suppressAutoRefresh = false
        loadHistory(force: true)
    }

    /// Wipes the list back to an empty slate. Called both when the user taps
    /// "Clear" and automatically whenever the backend reports a fresh bot
    /// session (bot start), so the Transactions page never mixes trades from
    /// a previous run into the current one.
    public func clearSession() {
        suppressAutoRefresh = true
        transactions.removeAll()
        totalProfitSummary = 0
        totalTradesCount = 0
        winCount = 0
        lossCount = 0
        errorMessage = nil
    }

    /// - Parameter silent: when true, the full-screen spinner never appears —
    ///   used for every background or pushed refresh. The blocking spinner
    ///   only ever appears for the very first load, when there's no existing
    ///   content on screen to protect.
    public func loadHistory(force: Bool = false, silent: Bool = false) {
        if suppressAutoRefresh && !force { return }
        Task {
            let shouldBlock = !silent && transactions.isEmpty
            if shouldBlock {
                isLoading = true
            } else {
                isSyncing = true
            }
            errorMessage = nil
            do {
                // The history endpoints already apply the active bot session
                // timestamp server-side. Do not perform a second session
                // probe: older running backends can return 404 here and
                // prevent all transaction/profit data from loading.
                let fetched: [Transaction]
                if selectedTab == 0 {
                    fetched = try await APIService.shared.fetchStatement(limit: limit)
                } else {
                    fetched = try await APIService.shared.fetchProfitTable(limit: limit)
                }
                self.transactions = fetched
                calculateSummary()
            } catch {
                self.errorMessage = "Failed to fetch history: \(error.localizedDescription)"
            }
            isLoading = false
            isSyncing = false
        }
    }

    private func calculateSummary() {
        var profitSum = 0.0
        var wins = 0
        var losses = 0

        for tx in transactions {
            if let p = tx.profit {
                profitSum += p
                if p > 0 { wins += 1 }
                else if p < 0 { losses += 1 }
            } else if let sp = tx.sell_price, let bp = tx.buy_price {
                let diff = sp - bp
                profitSum += diff
                if diff > 0 { wins += 1 }
                else if diff < 0 { losses += 1 }
            } else if let payout = tx.payout, let bp = tx.buy_price {
                let diff = payout - bp
                profitSum += diff
                if diff > 0 { wins += 1 }
                else if diff < 0 { losses += 1 }
            } else if let amount = tx.amount {
                // Statement rows expose the cash-flow amount. Summing the
                // session's buy/sell cash flows gives the realized net P/L
                // even when the statement response has no profit field.
                profitSum += amount
            }
        }

        self.totalProfitSummary = profitSum
        self.totalTradesCount = transactions.count
        self.winCount = wins
        self.lossCount = losses
    }
}
