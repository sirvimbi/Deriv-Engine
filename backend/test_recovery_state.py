import asyncio
import unittest

from models import TradingConfig
from trading_bot import TradingBot


class FakeClient:
    authorized = True

    async def get_balance(self):
        return {"balance": 1000.0, "currency": "USD"}


class RecoveryStateTests(unittest.IsolatedAsyncioTestCase):
    def make_bot(self):
        config = TradingConfig(
            base_stake=5.0,
            max_stake=500.0,
            martingale=2.5,
            recovery_wins_required=2,
            win_predict_digit=8,
            loss_predict_digit=3,
            recovery_win_predict_digit=3,
            contract_type_mode="BOTH",
        )
        bot = TradingBot(config)
        bot.client = FakeClient()
        bot.is_running = True
        return bot

    async def test_recovery_locks_contract_and_requires_target_wins(self):
        bot = self.make_bot()

        bot.in_recovery_cycle = True
        bot.active_contract_type = "DIGITUNDER"
        bot.stake = 12.5
        bot.predict = 3
        bot.active_trade_contract_id = 1

        await bot._handle_contract_finished(
            {"contract_id": 1, "profit": 6.73, "status": "won", "is_sold": 1},
            trade_contract_type="DIGITUNDER",
            trade_prediction=3,
            trade_stake=12.5,
            contract_id=1,
        )

        self.assertTrue(bot.in_recovery_cycle)
        self.assertEqual(bot.active_contract_type, "DIGITUNDER")
        self.assertEqual(bot.recovery_win_count, 1)
        self.assertEqual(bot.predict, 3)
        self.assertEqual(bot.stake, 12.5)

        bot.is_trade_in_progress = True
        bot.active_trade_contract_id = 2

        await bot._handle_contract_finished(
            {"contract_id": 2, "profit": 6.73, "status": "won", "is_sold": 1},
            trade_contract_type="DIGITUNDER",
            trade_prediction=3,
            trade_stake=12.5,
            contract_id=2,
        )

        self.assertFalse(bot.in_recovery_cycle)
        self.assertIsNone(bot.active_contract_type)
        self.assertEqual(bot.recovery_win_count, 0)
        self.assertEqual(bot.stake, 5.0)
        self.assertEqual(bot.predict, 8)

    async def test_loss_restarts_recovery_with_same_contract_and_loss_digit(self):
        bot = self.make_bot()

        bot.in_recovery_cycle = True
        bot.active_contract_type = "DIGITOVER"
        bot.recovery_win_count = 1
        bot.recovery_prediction_active = True
        bot.stake = 31.25
        bot.predict = 3
        bot.active_trade_contract_id = 10

        await bot._handle_contract_finished(
            {"contract_id": 10, "profit": -31.25, "status": "lost", "is_sold": 1},
            trade_contract_type="DIGITOVER",
            trade_prediction=3,
            trade_stake=31.25,
            contract_id=10,
        )

        self.assertTrue(bot.in_recovery_cycle)
        self.assertEqual(bot.active_contract_type, "DIGITOVER")
        self.assertEqual(bot.recovery_win_count, 0)
        self.assertFalse(bot.recovery_prediction_active)
        self.assertEqual(bot.predict, 3)
        self.assertEqual(bot.stake, 78.125)

    async def test_duplicate_settlement_is_ignored(self):
        bot = self.make_bot()
        bot.in_recovery_cycle = True
        bot.active_contract_type = "DIGITUNDER"
        bot.stake = 12.5
        bot.predict = 3
        bot.active_trade_contract_id = 20

        result = {
            "contract_id": 20,
            "profit": 6.73,
            "status": "won",
            "is_sold": 1,
        }

        await bot._handle_contract_finished(
            result,
            trade_contract_type="DIGITUNDER",
            trade_prediction=3,
            trade_stake=12.5,
            contract_id=20,
        )
        first_runs = bot.runs
        first_profit = bot.total_profit

        await bot._handle_contract_finished(
            result,
            trade_contract_type="DIGITUNDER",
            trade_prediction=3,
            trade_stake=12.5,
            contract_id=20,
        )

        self.assertEqual(bot.runs, first_runs)
        self.assertEqual(bot.total_profit, first_profit)


if __name__ == "__main__":
    unittest.main()
