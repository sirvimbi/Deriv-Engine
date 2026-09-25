import unittest

from trading_bot import TradingBot


class DigitSettlementAuditTests(unittest.TestCase):
    def test_extracts_trailing_zero_from_string_spot(self):
        self.assertEqual(TradingBot._extract_last_digit_from_spot("123.40", 2), 0)

    def test_extracts_nonzero_last_digit_from_string_spot(self):
        self.assertEqual(TradingBot._extract_last_digit_from_spot("123.47", 2), 7)

    def test_formats_numeric_spot_with_known_precision(self):
        self.assertEqual(TradingBot._extract_last_digit_from_spot(123.4, 2), 0)

    def test_missing_spot_returns_none(self):
        self.assertIsNone(TradingBot._extract_last_digit_from_spot(None, 2))


if __name__ == "__main__":
    unittest.main()
