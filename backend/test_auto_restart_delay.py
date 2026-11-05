import asyncio
import unittest
from unittest.mock import AsyncMock

from models import TradingConfig
from trading_bot import TradingBot


class AutoRestartDelayTests(unittest.IsolatedAsyncioTestCase):
    def test_legacy_settings_keep_the_existing_one_minute_default(self):
        bot = TradingBot(TradingConfig())
        self.assertEqual(bot.config.auto_restart_delay_hours, 0)
        self.assertEqual(bot.config.auto_restart_delay_minutes, 1)
        self.assertEqual(bot._auto_restart_delay_seconds(), 60)

    def test_hours_and_minutes_are_combined_into_seconds(self):
        bot = TradingBot(TradingConfig(
            auto_restart_delay_hours=2,
            auto_restart_delay_minutes=35,
        ))
        self.assertEqual(bot._auto_restart_delay_seconds(), 9300)

    def test_zero_delay_is_allowed_for_immediate_restart(self):
        bot = TradingBot(TradingConfig(
            auto_restart_delay_hours=0,
            auto_restart_delay_minutes=0,
        ))
        self.assertEqual(bot._auto_restart_delay_seconds(), 0)

    def test_delay_fields_reject_values_outside_supported_ranges(self):
        with self.assertRaises(ValueError):
            TradingConfig(auto_restart_delay_hours=25)
        with self.assertRaises(ValueError):
            TradingConfig(auto_restart_delay_minutes=60)

    async def test_take_profit_and_stop_loss_arm_the_configured_delay(self):
        for reason in (
            "Take Profit limit reached (+$100.00 >= $100.00)",
            "Stop Loss limit reached (-$100.00 <= -$100.00)",
        ):
            bot = TradingBot(TradingConfig(
                auto_restart_after_stop=True,
                auto_restart_delay_hours=2,
                auto_restart_delay_minutes=35,
            ))
            bot.is_running = True
            bot.client.unsubscribe_ticks = AsyncMock()
            restart = AsyncMock()
            bot._restart_after_stop = restart

            await bot.stop(reason)
            await bot._auto_restart_task

            restart.assert_awaited_once_with(9300)
            self.assertTrue(any(
                "AUTO-RESTART ARMED" in item.message and "02:35" in item.message
                for item in bot.logs
            ))


if __name__ == "__main__":
    unittest.main()
