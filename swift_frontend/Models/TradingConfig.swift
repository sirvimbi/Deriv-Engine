import Foundation

public struct TradingConfig: Codable, Equatable {
    public var api_token: String
    public var app_id: String
    public var symbol: String
    public var base_stake: Double
    public var max_stake: Double
    public var martingale_enabled: Bool
    public var martingale: Double
    public var take_profit: Double
    public var stop_loss: Double
    public var auto_restart_after_take_profit: Bool
    public var max_runs: Int
    public var max_loss_streak: Int
    public var under_trigger_digit: Int
    public var over_trigger_digit: Int
    public var win_predict_digit: Int
    public var both_under_barrier: Int
    public var both_over_barrier: Int
    public var both_inverse_enabled: Bool
    public var both_inverse_interval_hours: Int
    public var loss_predict_digit: Int
    public var recovery_win_predict_digit: Int
    public var duration: Int
    public var duration_unit: String
    public var currency: String
    public var recovery_wins_required: Int
    public var loss_cycle_target: Int
    public var contract_type_mode: String
    public var account_type: String

    public var isDemo: Bool { account_type.lowercased() != "real" }

    public init(
        api_token: String = "",
        app_id: String = "",
        symbol: String = "R_100",
        base_stake: Double = 30.0,
        max_stake: Double = 1000.0,
        martingale_enabled: Bool = false,
        martingale: Double = 2.0,
        take_profit: Double = 500.0,
        stop_loss: Double = 500.0,
        auto_restart_after_take_profit: Bool = false,
        max_runs: Int = 250,
        max_loss_streak: Int = 4,
        under_trigger_digit: Int = 2,
        over_trigger_digit: Int = 8,
        win_predict_digit: Int = 8,
        both_under_barrier: Int = 4,
        both_over_barrier: Int = 5,
        both_inverse_enabled: Bool = true,
        both_inverse_interval_hours: Int = 6,
        loss_predict_digit: Int = 3,
        recovery_win_predict_digit: Int = 3,
        duration: Int = 1,
        duration_unit: String = "t",
        currency: String = "USD",
        recovery_wins_required: Int = 2,
        loss_cycle_target: Int = 0,
        contract_type_mode: String = "BOTH",
        account_type: String = "demo"
    ) {
        self.api_token = api_token
        self.app_id = app_id
        self.symbol = symbol
        self.base_stake = base_stake
        self.max_stake = max_stake
        self.martingale_enabled = martingale_enabled
        self.martingale = martingale
        self.take_profit = take_profit
        self.stop_loss = stop_loss
        self.auto_restart_after_take_profit = auto_restart_after_take_profit
        self.max_runs = max_runs
        self.max_loss_streak = max_loss_streak
        self.under_trigger_digit = under_trigger_digit
        self.over_trigger_digit = over_trigger_digit
        self.win_predict_digit = win_predict_digit
        self.both_under_barrier = both_under_barrier
        self.both_over_barrier = both_over_barrier
        self.both_inverse_enabled = both_inverse_enabled
        self.both_inverse_interval_hours = both_inverse_interval_hours
        self.loss_predict_digit = loss_predict_digit
        self.recovery_win_predict_digit = recovery_win_predict_digit
        self.duration = duration
        self.duration_unit = duration_unit
        self.currency = currency
        self.recovery_wins_required = recovery_wins_required
        self.loss_cycle_target = loss_cycle_target
        self.contract_type_mode = contract_type_mode
        self.account_type = account_type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        api_token = try c.decodeIfPresent(String.self, forKey: .api_token) ?? ""
        if let stringID = try c.decodeIfPresent(String.self, forKey: .app_id) {
            app_id = stringID
        } else if let numericID = try c.decodeIfPresent(Int.self, forKey: .app_id) {
            app_id = String(numericID)
        } else {
            app_id = ""
        }
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "R_100"
        base_stake = try c.decodeIfPresent(Double.self, forKey: .base_stake) ?? 30.0
        max_stake = try c.decodeIfPresent(Double.self, forKey: .max_stake) ?? 1000.0
        martingale_enabled = try c.decodeIfPresent(Bool.self, forKey: .martingale_enabled) ?? false
        martingale = try c.decodeIfPresent(Double.self, forKey: .martingale) ?? 2.0
        take_profit = try c.decodeIfPresent(Double.self, forKey: .take_profit) ?? 500.0
        stop_loss = min(max(try c.decodeIfPresent(Double.self, forKey: .stop_loss) ?? 500.0, 0), 500)
        auto_restart_after_take_profit = try c.decodeIfPresent(Bool.self, forKey: .auto_restart_after_take_profit) ?? false
        max_runs = try c.decodeIfPresent(Int.self, forKey: .max_runs) ?? 250
        max_loss_streak = try c.decodeIfPresent(Int.self, forKey: .max_loss_streak) ?? 4
        under_trigger_digit = try c.decodeIfPresent(Int.self, forKey: .under_trigger_digit) ?? 2
        over_trigger_digit = try c.decodeIfPresent(Int.self, forKey: .over_trigger_digit) ?? 8
        win_predict_digit = try c.decodeIfPresent(Int.self, forKey: .win_predict_digit) ?? 8
        both_under_barrier = try c.decodeIfPresent(Int.self, forKey: .both_under_barrier) ?? 4
        both_over_barrier = try c.decodeIfPresent(Int.self, forKey: .both_over_barrier) ?? 5
        both_inverse_enabled = try c.decodeIfPresent(Bool.self, forKey: .both_inverse_enabled) ?? true
        both_inverse_interval_hours = min(max(try c.decodeIfPresent(Int.self, forKey: .both_inverse_interval_hours) ?? 6, 1), 24)
        loss_predict_digit = try c.decodeIfPresent(Int.self, forKey: .loss_predict_digit) ?? 3
        recovery_win_predict_digit = try c.decodeIfPresent(Int.self, forKey: .recovery_win_predict_digit) ?? 3
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 1
        duration_unit = try c.decodeIfPresent(String.self, forKey: .duration_unit) ?? "t"
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        recovery_wins_required = try c.decodeIfPresent(Int.self, forKey: .recovery_wins_required) ?? 2
        loss_cycle_target = min(max(try c.decodeIfPresent(Int.self, forKey: .loss_cycle_target) ?? 0, 0), 20)
        contract_type_mode = try c.decodeIfPresent(String.self, forKey: .contract_type_mode) ?? "BOTH"
        account_type = try c.decodeIfPresent(String.self, forKey: .account_type) ?? "demo"
    }
}


public struct DerivSymbol: Codable, Equatable, Identifiable {
    public let symbol: String
    public let name: String
    public let market: String
    public let submarket: String
    public let underlying_symbol_type: String

    public var id: String { symbol }

    public init(symbol: String, name: String, market: String, submarket: String, underlying_symbol_type: String) {
        self.symbol = symbol
        self.name = name
        self.market = market
        self.submarket = submarket
        self.underlying_symbol_type = underlying_symbol_type
    }
}
