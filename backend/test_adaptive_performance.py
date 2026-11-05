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
        bot = self.make_bot(contract_type_mode="DIGITOVER", adaptive_stop_loss_enabled=True)
        self.add_outcomes(bot, 15, 15)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["mode"], "not_applicable")
        self.assertEqual(snapshot["active_take_profit"], 100.0)
        self.assertEqual(snapshot["active_stop_loss"], 100.0)

    def test_configurable_minimum_sample_and_stop_threshold(self):
        bot = self.make_bot(adaptive_minimum_sample_size=2, adaptive_stop_win_rate=30.0)
        self.add_outcomes(bot, 0, 2)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["mode"], "stop")
        self.assertEqual(snapshot["rolling_win_rate"], 0.0)

    def test_zero_minimum_sample_still_requires_one_decisive_outcome(self):
        bot = self.make_bot(adaptive_minimum_sample_size=0)
        self.assertEqual(bot._adaptive_performance_snapshot()["mode"], "warming_up")
        self.add_outcomes(bot, 1, 0)
        self.assertEqual(bot._adaptive_performance_snapshot()["mode"], "normal")

    def test_break_even_is_excluded_from_rolling_win_rate(self):
        bot = self.make_bot()
        bot._record_adaptive_outcome(1.0)
        bot._record_adaptive_outcome(0.0)
        bot._record_adaptive_outcome(-1.0)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 2)
        self.assertEqual(snapshot["rolling_win_rate"], 50.0)

    def test_full_take_profit_is_preserved_at_target_benchmark(self):
        bot = self.make_bot()
        self.add_outcomes(bot, 33, 17)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_win_rate"], 66.0)
        self.assertEqual(snapshot["mode"], "normal")
        self.assertEqual(snapshot["active_take_profit"], 100.0)

    def test_take_profit_reduces_proportionally_below_benchmark(self):
        bot = self.make_bot(adaptive_rolling_window=100)
        self.add_outcomes(bot, 55, 45)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_win_rate"], 55.0)
        self.assertEqual(snapshot["mode"], "caution")
        self.assertEqual(snapshot["active_take_profit"], 76.09)

    def test_custom_tp_stop_threshold_is_respected(self):
        bot = self.make_bot(adaptive_rolling_window=50, adaptive_stop_win_rate=10)
        self.add_outcomes(bot, 5, 45)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_win_rate"], 10.0)
        self.assertEqual(snapshot["mode"], "stop")

    def test_zero_tp_window_uses_all_session_outcomes(self):
        bot = self.make_bot(adaptive_rolling_window=0)
        self.add_outcomes(bot, 60, 40)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 100)
        self.assertEqual(snapshot["rolling_win_rate"], 60.0)
        self.assertEqual(len(bot.recent_outcomes), 100)

    def test_tp_window_is_capped_at_two_hundred(self):
        bot = self.make_bot(adaptive_rolling_window=200, adaptive_stop_loss_rolling_window=200)
        self.add_outcomes(bot, 120, 100)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["rolling_sample_size"], 200)
        self.assertEqual(len(bot.recent_outcomes), 200)

    def test_adaptive_sl_uses_independent_min_max_rates_and_window(self):
        bot = self.make_bot(
            adaptive_rolling_window=50,
            adaptive_stop_loss_enabled=True,
            adaptive_stop_loss_min_win_rate=30,
            adaptive_stop_loss_max_win_rate=60,
            adaptive_stop_loss_rolling_window=100,
        )
        self.add_outcomes(bot, 45, 55)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["sl_rolling_sample_size"], 100)
        self.assertEqual(snapshot["sl_rolling_win_rate"], 45.0)
        self.assertEqual(snapshot["active_stop_loss"], 75.0)

    def test_adaptive_sl_returns_to_full_hard_limit_at_max_rate(self):
        bot = self.make_bot(
            adaptive_stop_loss_enabled=True,
            adaptive_stop_loss_min_win_rate=20,
            adaptive_stop_loss_max_win_rate=66,
        )
        self.add_outcomes(bot, 40, 10)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["active_stop_loss"], 100.0)

    def test_adaptive_sl_uses_all_session_trades_when_window_is_zero(self):
        bot = self.make_bot(
            adaptive_stop_loss_enabled=True,
            adaptive_stop_loss_rolling_window=0,
        )
        self.add_outcomes(bot, 40, 10)
        snapshot = bot._adaptive_performance_snapshot()
        self.assertEqual(snapshot["sl_rolling_sample_size"], 50)
        self.assertEqual(snapshot["sl_rolling_win_rate"], 80.0)

    def test_adaptive_settings_validate_supported_ranges_and_rate_order(self):
        for kwargs in (
            {"adaptive_rolling_window": -1},
            {"adaptive_rolling_window": 201},
            {"adaptive_stop_win_rate": -1},
            {"adaptive_stop_win_rate": 31},
            {"adaptive_minimum_sample_size": -1},
            {"adaptive_minimum_sample_size": 31},
            {"adaptive_stop_loss_rolling_window": 201},
        ):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValidationError):
                TradingConfig(**kwargs)

        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_stop_loss_min_win_rate=66, adaptive_stop_loss_max_win_rate=66)
        with self.assertRaises(ValidationError):
            TradingConfig(adaptive_stop_loss_min_win_rate=70, adaptive_stop_loss_max_win_rate=60)


if __name__ == "__main__":
    unittest.main()
