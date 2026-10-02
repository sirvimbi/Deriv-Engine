import unittest
from models import TradingConfig
from trading_bot import TradingBot

class MartingaleRulesTests(unittest.IsolatedAsyncioTestCase):
    def test_rule1_martingale_multiplies_stake_or_keeps_base_stake(self):
        # When martingale is enabled and set to 2 and base stake is 10 -> stake = 2x10 = 20
        config_enabled = TradingConfig(base_stake=10.0, martingale_enabled=True, martingale=2.0)
        bot = TradingBot(config_enabled)
        bot.stake = 10.0
        stake = bot._calculate_recovery_stake(10.0)
        self.assertEqual(stake, 20.0)

        # When martingale is disabled, base stake remains the same (10.0)
        config_disabled = TradingConfig(base_stake=10.0, martingale_enabled=False, martingale=2.0)
        bot_dis = TradingBot(config_disabled)
        bot_dis.stake = 10.0
        stake_dis = bot_dis._calculate_recovery_stake(10.0)
        self.assertEqual(stake_dis, 10.0)

    def test_rule2_martingale_applied_for_recovery_wins_required_executions(self):
        # Base stake 10, multiplier 2, recovery win target 3
        # Total stake = 2x10 = 20 for the next three executions
        config = TradingConfig(
            base_stake=10.0,
            martingale_enabled=True,
            martingale=2.0,
            recovery_wins_required=3,
            loss_cycle_target=0
        )
        bot = TradingBot(config)
        bot.stake = 10.0

        stake = bot._calculate_recovery_stake(10.0)
        self.assertEqual(stake, 20.0)

    def test_rule3_martingale_plus_loss_cycle_target(self):
        # Base stake 10, multiplier 2, recovery win target 3, loss cycle target 2
        # Total stake = (2 x 10) + ((10 / 2) / 0.95) = 20 + 5.2632 = 25.2632
        config = TradingConfig(
            base_stake=10.0,
            martingale_enabled=True,
            martingale=2.0,
            recovery_wins_required=3,
            loss_cycle_target=2
        )
        bot = TradingBot(config)
        bot.stake = 10.0

        stake = bot._calculate_recovery_stake(10.0)
        self.assertAlmostEqual(stake, 25.2632, places=3)

if __name__ == "__main__":
    unittest.main()
