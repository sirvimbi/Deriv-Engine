import asyncio
import unittest
from unittest.mock import AsyncMock, patch

from models import TradingConfig
from trading_bot import TradingBot


class RiseFallTradingTests(unittest.IsolatedAsyncioTestCase):
    def make_bot(self, mode):
        config = TradingConfig(
            contract_type_mode=mode,
            base_stake=1.0,
            martingale=0.0,
            recovery_wins_required=0,
            loss_cycle_target=0,
        )
        bot = TradingBot(config)
        bot.is_running = True
        return bot

    async def test_call_mode_schedules_rise_trade(self):
        bot = self.make_bot("CALL")
        scheduled = []
        bot._schedule_trade = lambda contract_type: scheduled.append(contract_type)

        await bot._on_tick({"quote": 100.10, "pip_size": 2, "epoch": 1})

        self.assertEqual(scheduled, ["CALL"])

    async def test_put_mode_schedules_fall_trade(self):
        bot = self.make_bot("PUT")
        scheduled = []
        bot._schedule_trade = lambda contract_type: scheduled.append(contract_type)

        await bot._on_tick({"quote": 100.10, "pip_size": 2, "epoch": 1})

        self.assertEqual(scheduled, ["PUT"])

    async def test_rise_fall_mode_follows_tick_direction(self):
        bot = self.make_bot("RISEFALL")
        scheduled = []
        bot._schedule_trade = lambda contract_type: scheduled.append(contract_type)

        await bot._on_tick({"quote": 100.10, "pip_size": 2, "epoch": 1})
        await bot._on_tick({"quote": 100.20, "pip_size": 2, "epoch": 2})
        await bot._on_tick({"quote": 100.15, "pip_size": 2, "epoch": 3})

        self.assertEqual(scheduled, ["CALL", "PUT"])

    async def test_call_settlement_audit_uses_entry_and_exit_spots(self):
        bot = self.make_bot("CALL")
        bot.active_trade_contract_id = 123

        poc = {
            "profit": 0.50,
            "status": "won",
            "entry_spot": "100.10",
            "exit_spot": "100.20",
            "buy_price": "1.00",
        }

        with patch.object(bot, "_refresh_balance_after_settlement", new=AsyncMock()):
            with patch.object(bot, "status_broadcast_callback", None):
                await bot._handle_contract_finished(
                    poc,
                    trade_contract_type="CALL",
                    trade_prediction=None,
                    trade_stake=1.0,
                    contract_id=123,
                )

        self.assertEqual(bot.total_wins, 1)
        self.assertFalse(any("SETTLEMENT MISMATCH" in log.message for log in bot.logs))


if __name__ == "__main__":
    unittest.main()
