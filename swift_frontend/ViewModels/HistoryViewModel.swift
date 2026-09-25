import Foundation

@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var transactions: [Transaction] = []
    @Published public var isLoading: Bool = false
    @Published public var selectedTab: Int = 0 // 0: Statement, 1: Profit Table
    @Published public var limit: Int = 50
    @Published public var totalProfitSummary: Double = 0.0
    @Published public var totalTradesCount: Int = 0
    @Published public var winCount: Int = 0
    @Published public var lossCount: Int = 0
    @Published public var errorMessage: String? = nil

    public init() {
        loadHistory()
    }

    public func loadHistory() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                if selectedTab == 0 {
                    self.transactions = try await APIService.shared.fetchStatement(limit: limit)
                } else {
                    self.transactions = try await APIService.shared.fetchProfitTable(limit: limit)
                }
                calculateSummary()
            } catch {
                self.errorMessage = "Failed to fetch history: \(error.localizedDescription)"
            }
            isLoading = false
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
            }
        }

        self.totalProfitSummary = profitSum
        self.totalTradesCount = transactions.count
        self.winCount = wins
        self.lossCount = losses
    }
}
