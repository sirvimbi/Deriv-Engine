import unittest
from unittest.mock import patch

from models import TradingConfig
from trading_bot import TradingBot


class DisabledRecoverySettingsTests(unittest.IsolatedAsyncioTestCase):
    def _config(self, **overrides):
        values = {
            "base_stake": 1.0,
            "max_stake": 100.0,
            "martingale": 0.0,
            "recovery_wins_required": 0,
            "loss_cycle_target": 0,
            "max_loss_streak": 4,
        }
        values.update(overrides)
        return TradingConfig(**values)

    def test_martingale_zero_keeps_base_stake(self):
        bot = TradingBot(self._config())
        bot.stake = 1.0

        bot._apply_martingale_after_loss()

        self.assertEqual(bot.stake, 1.0)

    async def test_both_recovery_modes_zero_disable_recovery(self):
        bot = TradingBot(self._config())
        bot.is_running = True
        bot.is_trade_in_progress = True
        bot.active_trade_contract_id = 1
        bot.stake = 1.0

        poc = {
            "profit": -1.0,
            "status": "lost",
            "entry_spot": "100.10",
            "exit_spot": "100.11",
            "buy_price": 1.0,
        }

        with patch("trading_bot.asyncio.create_task"):
            await bot._handle_contract_finished(
                poc,
                trade_contract_type="DIGITOVER",
                trade_prediction=1,
                trade_stake=1.0,
                contract_id=1,
            )

        self.assertFalse(bot.in_recovery_cycle)
        self.assertEqual(bot.recovery_win_count, 0)
        self.assertEqual(bot.recovery_loss_stake, 0.0)
        self.assertEqual(bot.stake, 1.0)

    async def test_recovery_can_run_without_martingale(self):
        bot = TradingBot(self._config(recovery_wins_required=2))
        bot.is_running = True
        bot.is_trade_in_progress = True
        bot.active_trade_contract_id = 1
        bot.stake = 1.0

        poc = {"profit": -1.0, "status": "lost"}

        with patch("trading_bot.asyncio.create_task"):
            await bot._handle_contract_finished(
                poc,
                trade_contract_type="DIGITOVER",
                trade_prediction=1,
                trade_stake=1.0,
                contract_id=1,
            )

        self.assertTrue(bot.in_recovery_cycle)
        self.assertEqual(bot.stake, 1.0)
        self.assertEqual(bot.recovery_win_count, 0)

    async def test_loss_cycle_can_run_without_martingale(self):
        bot = TradingBot(self._config(loss_cycle_target=3))
        bot.is_running = True
        bot.is_trade_in_progress = True
        bot.active_trade_contract_id = 1
        bot.stake = 1.0

        poc = {"profit": -1.0, "status": "lost"}

        with patch("trading_bot.asyncio.create_task"):
            await bot._handle_contract_finished(
                poc,
                trade_contract_type="DIGITOVER",
                trade_prediction=1,
                trade_stake=1.0,
                contract_id=1,
            )

        self.assertTrue(bot.in_recovery_cycle)
        self.assertEqual(bot.stake, 1.0)
        self.assertEqual(bot.recovery_loss_stake, 1.0)

    async def test_enabled_martingale_still_scales_recovery_stake(self):
        bot = TradingBot(self._config(martingale=2.0, recovery_wins_required=2))
        bot.is_running = True
        bot.is_trade_in_progress = True
        bot.active_trade_contract_id = 1
        bot.stake = 1.0

        poc = {"profit": -1.0, "status": "lost"}

        with patch("trading_bot.asyncio.create_task"):
            await bot._handle_contract_finished(
                poc,
                trade_contract_type="DIGITOVER",
                trade_prediction=1,
                trade_stake=1.0,
                contract_id=1,
            )

        self.assertTrue(bot.in_recovery_cycle)
        self.assertEqual(bot.stake, 2.0)


if __name__ == "__main__":
    unittest.main()
