import Foundation

public struct TradingConfig: Codable, Equatable {
    public var api_token: String
    public var app_id: Int
    public var symbol: String
    public var base_stake: Double
    public var max_stake: Double
    public var martingale: Double
    public var take_profit: Double
    public var stop_loss: Double
    public var max_runs: Int
    public var max_loss_streak: Int
    public var under_trigger_digit: Int
    public var over_trigger_digit: Int
    public var win_predict_digit: Int
    public var loss_predict_digit: Int
    public var duration: Int
    public var duration_unit: String
    public var currency: String
    public var recovery_wins_required: Int

    /// New: "demo" or "real". Additive field for the account switcher —
    /// decoded defensively below so older backend responses that don't
    /// include it yet still decode without crashing.
    public var account_type: String

    public var isDemo: Bool { account_type.lowercased() != "real" }

    public init(
        api_token: String = "",
        app_id: Int = 1089,
        symbol: String = "R_100",
        base_stake: Double = 30.0,
        max_stake: Double = 1000.0,
        martingale: Double = 2.0,
        take_profit: Double = 500.0,
        stop_loss: Double = 500.0,
        max_runs: Int = 250,
        max_loss_streak: Int = 4,
        under_trigger_digit: Int = 2,
        over_trigger_digit: Int = 8,
        win_predict_digit: Int = 8,
        loss_predict_digit: Int = 3,
        duration: Int = 1,
        duration_unit: String = "t",
        currency: String = "USD",
        recovery_wins_required: Int = 2,
        account_type: String = "demo"
    ) {
        self.api_token = api_token
        self.app_id = app_id
        self.symbol = symbol
        self.base_stake = base_stake
        self.max_stake = max_stake
        self.martingale = martingale
        self.take_profit = take_profit
        self.stop_loss = stop_loss
        self.max_runs = max_runs
        self.max_loss_streak = max_loss_streak
        self.under_trigger_digit = under_trigger_digit
        self.over_trigger_digit = over_trigger_digit
        self.win_predict_digit = win_predict_digit
        self.loss_predict_digit = loss_predict_digit
        self.duration = duration
        self.duration_unit = duration_unit
        self.currency = currency
        self.recovery_wins_required = recovery_wins_required
        self.account_type = account_type
    }

    // Custom decoding: every field falls back to its default if the
    // backend response is missing it, instead of failing the whole decode.
    // This is what lets us add `account_type` (and any future field)
    // without requiring the Python backend to be updated in lockstep.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        api_token = try c.decodeIfPresent(String.self, forKey: .api_token) ?? ""
        app_id = try c.decodeIfPresent(Int.self, forKey: .app_id) ?? 1089
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "R_100"
        base_stake = try c.decodeIfPresent(Double.self, forKey: .base_stake) ?? 30.0
        max_stake = try c.decodeIfPresent(Double.self, forKey: .max_stake) ?? 1000.0
        martingale = try c.decodeIfPresent(Double.self, forKey: .martingale) ?? 2.0
        take_profit = try c.decodeIfPresent(Double.self, forKey: .take_profit) ?? 500.0
        stop_loss = try c.decodeIfPresent(Double.self, forKey: .stop_loss) ?? 500.0
        max_runs = try c.decodeIfPresent(Int.self, forKey: .max_runs) ?? 250
        max_loss_streak = try c.decodeIfPresent(Int.self, forKey: .max_loss_streak) ?? 4
        under_trigger_digit = try c.decodeIfPresent(Int.self, forKey: .under_trigger_digit) ?? 2
        over_trigger_digit = try c.decodeIfPresent(Int.self, forKey: .over_trigger_digit) ?? 8
        win_predict_digit = try c.decodeIfPresent(Int.self, forKey: .win_predict_digit) ?? 8
        loss_predict_digit = try c.decodeIfPresent(Int.self, forKey: .loss_predict_digit) ?? 3
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 1
        duration_unit = try c.decodeIfPresent(String.self, forKey: .duration_unit) ?? "t"
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        recovery_wins_required = try c.decodeIfPresent(Int.self, forKey: .recovery_wins_required) ?? 2
        account_type = try c.decodeIfPresent(String.self, forKey: .account_type) ?? "demo"
    }
}
