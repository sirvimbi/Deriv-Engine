import unittest
from models import TradingConfig
from trading_bot import TradingBot

class RecoveryStateMachineTests(unittest.IsolatedAsyncioTestCase):
    def make_bot(self):
        c = TradingConfig(
            base_stake=5, max_stake=500, martingale=2,
            win_predict_digit=8, loss_predict_digit=2,
            recovery_win_predict_digit=3, recovery_wins_required=2,
            contract_type_mode="BOTH"
        )
        b = TradingBot(c)
        b.is_running = True
        return b

    async def test_first_recovery_win_moves_to_target_prediction_without_reset(self):
        b = self.make_bot()
        b.in_recovery_cycle = True
        b.recovery_phase = 1
        b.active_contract_type = "DIGITUNDER"
        b.stake = 10
        b.predict = 2
        b.active_trade_contract_id = 1

        await b._handle_contract_finished(
            {"profit": 3.33, "status": "won", "is_sold": 1},
            "DIGITUNDER", 2, 10, 1
        )

        self.assertTrue(b.in_recovery_cycle)
        self.assertEqual(b.recovery_win_count, 1)
        self.assertEqual(b.recovery_phase, 2)
        self.assertEqual(b.active_contract_type, "DIGITUNDER")
        self.assertEqual(b.predict, 3)

    async def test_second_recovery_win_resets_only_after_target(self):
        b = self.make_bot()
        b.in_recovery_cycle = True
        b.recovery_phase = 2
        b.recovery_win_count = 1
        b.active_contract_type = "DIGITOVER"
        b.stake = 20
        b.predict = 3
        b.active_trade_contract_id = 2

        await b._handle_contract_finished(
            {"profit": 6.67, "status": "won", "is_sold": 1},
            "DIGITOVER", 3, 20, 2
        )

        self.assertFalse(b.in_recovery_cycle)
        self.assertEqual(b.recovery_win_count, 0)
        self.assertEqual(b.recovery_phase, 0)
        self.assertIsNone(b.active_contract_type)
        self.assertEqual(b.stake, 5)
        self.assertEqual(b.predict, 8)

    async def test_loss_always_returns_to_first_recovery_phase(self):
        b = self.make_bot()
        b.in_recovery_cycle = True
        b.recovery_phase = 2
        b.recovery_win_count = 1
        b.active_contract_type = "DIGITOVER"
        b.stake = 20
        b.predict = 3
        b.active_trade_contract_id = 3

        await b._handle_contract_finished(
            {"profit": -20, "status": "lost", "is_sold": 1},
            "DIGITOVER", 3, 20, 3
        )

        self.assertTrue(b.in_recovery_cycle)
        self.assertEqual(b.recovery_phase, 1)
        self.assertEqual(b.recovery_win_count, 0)
        self.assertEqual(b.active_contract_type, "DIGITOVER")
        self.assertEqual(b.predict, 2)

if __name__ == "__main__":
    unittest.main()
