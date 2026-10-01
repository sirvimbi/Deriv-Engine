import asyncio
import random
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import trading_bot


class RecoveryCooldownTests(unittest.IsolatedAsyncioTestCase):
    def make_bot(self):
        bot = trading_bot.TradingBot.__new__(trading_bot.TradingBot)
        bot.is_running = True
        bot.is_trade_in_progress = False
        bot.in_recovery_cycle = True
        bot.active_contract_type = "DIGITOVER"
        bot.recovery_phase = 1
        bot.recovery_cooldown_until = 105.0
        bot._recovery_cooldown_logged = False
        bot.last_tick_quote = None
        bot.last_tick_pip_size = None
        bot.last_digit = None
        bot.status_broadcast_callback = None
        bot.stake = 10.0
        bot._both_rng = random.Random(12345)
        bot.config = SimpleNamespace(
            symbol="R_100",
            loss_predict_digit=2,
            recovery_win_predict_digit=1,
            both_under_barrier=4,
            both_over_barrier=5,
            contract_type_mode="BOTH",
            both_inverse_interval_hours=6,
            both_inverse_enabled=True,
            both_random_seed="test_seed",
        )
        bot.predict = 2
        bot.scheduled = 0

        def schedule(_contract_type):
            bot.scheduled += 1

        bot._schedule_trade = schedule
        bot.add_log = lambda *_args, **_kwargs: None
        return bot

    async def test_recovery_trade_is_blocked_during_five_second_cooldown(self):
        bot = self.make_bot()

        with patch.object(trading_bot.time, "monotonic", return_value=104.99):
            await bot._on_tick({"quote": 619.80, "pip_size": 2})

        self.assertEqual(bot.scheduled, 0)

    async def test_recovery_trade_is_allowed_when_cooldown_expires(self):
        bot = self.make_bot()

        with patch.object(trading_bot.time, "monotonic", return_value=105.0):
            await bot._on_tick({"quote": 619.80, "pip_size": 2})

        self.assertEqual(bot.scheduled, 1)


if __name__ == "__main__":
    unittest.main()
