import unittest

from pydantic import ValidationError

from models import TradingConfig
from trading_bot import TradingBot


class AdaptivePerformanceTests(unittest.TestCase):
    def make_bot(self, **overrides):
        values = {
            "adaptive_performance_enabled": True,
            "take_profit": 100.0,
            "stop_loss": 100.0,
            "contract_type_mode": "BOTH",
        }
        values.update(overrides)
        return TradingBot(TradingConfig(**values))

    def add_outcomes(self, bot, wins, losses):
        for _ in range(wins):
            bot._record_adaptive_outcome(1.0)
        for _ in range(losses):
            bot._record_adaptive_outcome(-1.0)

    def test_adaptive_protection_is_off_by_default(self):
        bot = TradingBot(TradingConfig(take_profit=100.0, stop_loss=100.0))
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["mode"], "disabled")
        self.assertEqual(snapshot["active_take_profit"], 100.0)
        self.assertEqual(snapshot["active_stop_loss"], 100.0)

    def test_other_contract_modes_keep_fixed_targets(self):
        bot = self.make_bot(contract_type_mode="DIGITOVER")
        self.add_outcomes(bot, 15, 15)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["mode"], "not_applicable")
        self.assertEqual(snapshot["active_take_profit"], 100.0)
        self.assertEqual(snapshot["active_stop_loss"], 100.0)

    def test_waits_for_thirty_decisive_settlements(self):
        bot = self.make_bot()
        self.add_outcomes(bot, 8, 21)
        self.assertEqual(bot._adaptive_performance_snapshot()["mode"], "warming_up")
        self.add_outcomes(bot, 1, 0)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 30)
        self.assertEqual(snapshot["mode"], "protection")

    def test_break_even_is_excluded_from_rolling_win_rate(self):
        bot = self.make_bot()
        bot._record_adaptive_outcome(1.0)
        bot._record_adaptive_outcome(0.0)
        bot._record_adaptive_outcome(-1.0)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 2)
        self.assertEqual(snapshot["rolling_win_rate"], 50.0)

    def test_take_profit_reduces_proportionally_below_benchmark(self):
        bot = self.make_bot()
        self.add_outcomes(bot, 55, 45)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_win_rate"], 55.0)
        self.assertEqual(snapshot["mode"], "caution")
        self.assertEqual(snapshot["active_take_profit"], 76.09)

    def test_adaptive_stop_loss_tightens_but_never_exceeds_configured_limit(self):
        bot = self.make_bot(adaptive_stop_loss_enabled=True)
        self.add_outcomes(bot, 55, 45)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertLess(snapshot["active_stop_loss"], bot.config.stop_loss)
        self.assertGreaterEqual(snapshot["active_stop_loss"], bot.config.stop_loss * 0.5)

    def test_win_rate_at_or_below_twenty_percent_triggers_stop_mode(self):
        bot = self.make_bot()
        self.add_outcomes(bot, 6, 24)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_win_rate"], 20.0)
        self.assertEqual(snapshot["mode"], "stop")
        self.assertEqual(snapshot["active_take_profit"], 0.0)

    def test_rolling_window_discards_oldest_settled_outcomes(self):
        bot = self.make_bot(adaptive_rolling_window=30)
        self.add_outcomes(bot, 30, 0)
        bot._record_adaptive_outcome(-1.0)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 30)
        self.assertLess(snapshot["rolling_win_rate"], 100.0)

    def test_adaptive_settings_validate_supported_ranges(self):
        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_target_win_rate=49.0)
        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_target_win_rate=91.0)
        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_rolling_window=29)
        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_rolling_window=201)


if __name__ == "__main__":
    unittest.main()
