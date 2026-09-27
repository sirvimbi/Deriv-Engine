import json
import unittest
from decimal import Decimal

from deriv_client import DerivClient
from trading_bot import TradingBot


class DataReadingTests(unittest.TestCase):
    def test_deriv_json_preserves_quote_decimal_scale(self):
        payload = json.loads(
            '{"msg_type":"tick","tick":{"quote":100.10,"symbol":"R_100","epoch":1}}',
            parse_float=Decimal
        )
        quote = payload["tick"]["quote"]
        self.assertIsInstance(quote, Decimal)
        self.assertEqual(str(quote), "100.10")

    def test_quote_last_digit_uses_json_scale_when_pip_size_missing(self):
        self.assertEqual(
            TradingBot._extract_last_digit_from_quote(Decimal("100.10")),
            0
        )
        self.assertEqual(
            TradingBot._extract_last_digit_from_quote(Decimal("100.15")),
            5
        )

    def test_quote_last_digit_respects_explicit_pip_size(self):
        self.assertEqual(
            TradingBot._extract_last_digit_from_quote(Decimal("100.100"), 3),
            0
        )
        self.assertEqual(
            TradingBot._extract_last_digit_from_quote(Decimal("100.125"), 3),
            5
        )

    def test_settlement_last_digit_preserves_trailing_zero(self):
        self.assertEqual(
            TradingBot._extract_last_digit_from_spot(Decimal("100.10")),
            0
        )
        self.assertEqual(
            TradingBot._extract_last_digit_from_spot("100.17"),
            7
        )


if __name__ == "__main__":
    unittest.main()
