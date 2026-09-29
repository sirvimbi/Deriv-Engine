import unittest

from fastapi import HTTPException

from models import TradingConfig
from main import _validate_trade_config


class MartingaleSafetyTests(unittest.TestCase):
    def test_zero_martingale_is_rejected_before_trading(self):
        config = TradingConfig(martingale=0.0)
        with self.assertRaises(HTTPException) as raised:
            _validate_trade_config(config)
        self.assertEqual(raised.exception.status_code, 422)
        self.assertIn("at least 1.0", str(raised.exception.detail))

    def test_positive_martingale_is_accepted(self):
        config = TradingConfig(martingale=1.0)
        _validate_trade_config(config)


if __name__ == "__main__":
    unittest.main()
