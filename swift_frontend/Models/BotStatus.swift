import Foundation

public struct BackendRuntime: Codable {
    public let engine_build: String
    public let description: String
    public let api: String
}

public struct BotStatus: Codable {
    public let is_running: Bool
    public let is_trade_in_progress: Bool
    public let total_profit: Double
    public let runs: Int
    public let total_wins: Int
    public let total_losses: Int
    public let win_rate: Double
    public let current_stake: Double
    public let current_predict: Int
    public let loss_streak: Int
    public let recovery_win_count: Int
    public let lowest_balance: Double
    public let lowest_loss: Double
    public let wins_in_row: Int
    public let loss_in_row: Int
    public let last_digit: Int?
    public let last_tick_quote: Double?
    public let duration_minutes: Double
    public let stop_reason: String?
    public let config: TradingConfig

    /// New: account equity/balance. Optional because the backend may not
    /// send it yet — decodes to nil rather than failing the whole payload,
    /// and the UI shows a clear "awaiting backend" state when nil.
    public let equity: Double?

    public static var defaultStatus: BotStatus {
        BotStatus(
            is_running: false,
            is_trade_in_progress: false,
            total_profit: 0.0,
            runs: 0,
            total_wins: 0,
            total_losses: 0,
            win_rate: 0.0,
            current_stake: 30.0,
            current_predict: 8,
            loss_streak: 0,
            recovery_win_count: 0,
            lowest_balance: 0.0,
            lowest_loss: 0.0,
            wins_in_row: 0,
            loss_in_row: 0,
            last_digit: nil,
            last_tick_quote: nil,
            duration_minutes: 0.0,
            stop_reason: nil,
            config: TradingConfig(),
            equity: nil
        )
    }
}

public struct LogMessage: Codable, Identifiable {
    public var id: String { "\(timestamp)-\(message)" }
    public let timestamp: String
    public let level: String
    public let message: String
}

public struct LiveTickData: Codable {
    public let quote: Double
    public let last_digit: Int
    public let symbol: String
}
