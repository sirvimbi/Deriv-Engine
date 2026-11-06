import Foundation

public struct Transaction: Codable, Identifiable {
    public var id: String {
        if let cid = contract_id { return "\(cid)" }
        if let tid = transaction_id { return "\(tid)" }
        return UUID().uuidString
    }
    
    public let contract_id: Int?
    public let transaction_id: Int?
    public let action: String?
    public let action_type: String?
    public let payout: Double?
    public let amount: Double?
    public let balance_after: Double?
    public let transaction_time: Int?
    public let symbol: String?
    public let longcode: String?
    public let profit: Double?
    public let purchase_time: Int?
    public let sell_time: Int?
    public let buy_price: Double?
    public let sell_price: Double?

    public var formattedTime: String {
        guard let timestamp = transaction_time ?? purchase_time else { return "N/A" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    public var isProfit: Bool {
        if let p = profit { return p > 0 }
        if let sp = sell_price, let bp = buy_price { return (sp - bp) > 0 }
        return false
    }
}

public struct StatementResponse: Codable {
    public let status: String
    public let transactions: [Transaction]
}

public struct ProfitTableResponse: Codable {
    public let status: String
    public let transactions: [Transaction]
}

public struct BalanceInfo: Codable {
    public let balance: Double?
    public let currency: String?
    public let id: String?
}

public struct BalanceResponse: Codable {
    public let status: String
    public let balance: BalanceInfo
}


// MARK: - Persistent bot session history

public struct SessionHistoryResponse: Codable {
    public let status: String
    public let sessions: [TradingSessionRecord]
}

public struct TradingSessionRecord: Codable, Identifiable {
    public let id: String
    public let started_at: Double
    public let finished_at: Double?
    public let duration_seconds: Double?
    public let status: String
    public let stop_reason: String?
    public let setup: TradingSessionSetup
    public let summary: TradingSessionSummary
    public let trades: [TradingSessionTrade]
}

public struct TradingSessionSummary: Codable {
    public let trade_count: Int
    public let wins: Int
    public let losses: Int
    public let break_even: Int
    public let total_profit: Double
    public let total_stake: Double
    public let max_trade_stake: Double
}

public struct TradingSessionSetup: Codable {
    public let symbol: String
    public let account_type: String
    public let currency: String
    public let contract_type_mode: String
    public let base_stake: Double
    public let max_stake: Double
    public let martingale_enabled: Bool
    public let martingale: Double
    public let take_profit: Double
    public let stop_loss: Double
    public let under_trigger_digit: Int
    public let over_trigger_digit: Int
    public let win_predict_digit: Int
    public let both_under_barrier: Int
    public let both_over_barrier: Int
    public let both_inverse_enabled: Bool
    public let both_inverse_interval_hours: Int
    public let loss_predict_digit: Int
    public let recovery_over_barrier: Int
    public let recovery_under_barrier: Int
    public let recovery_wins_required: Int
    public let loss_cycle_target: Int
    public let max_loss_streak: Int
    public let duration: Int
    public let duration_unit: String
    public let adaptive_performance_enabled: Bool
    public let adaptive_target_win_rate: Double
    public let adaptive_stop_win_rate: Double
    public let adaptive_minimum_sample_size: Int
    public let adaptive_rolling_window: Int
    public let adaptive_stop_loss_enabled: Bool
    public let adaptive_stop_loss_min_win_rate: Double
    public let adaptive_stop_loss_max_win_rate: Double
    public let adaptive_stop_loss_rolling_window: Int
}

public struct TradingSessionTrade: Codable, Identifiable {
    public var id: String { contract_id.map { String($0) } ?? String(settled_at) }
    public let contract_id: Int?
    public let placed_at: Double
    public let settled_at: Double
    public let contract_type: String
    public let entry_signal_digit: Int?
    public let generator_digit: Int?
    public let barrier: Int?
    public let stake: Double
    public let buy_price: Double
    public let payout: Double?
    public let profit: Double
    public let outcome: String
    public let deriv_status: String?
    public let entry_spot: String?
    public let exit_spot: String?
    public let exit_digit: Int?
    public let active_take_profit: Double?
    public let active_stop_loss: Double?
    public let rolling_win_rate: Double?
    public let sl_rolling_win_rate: Double?
}
