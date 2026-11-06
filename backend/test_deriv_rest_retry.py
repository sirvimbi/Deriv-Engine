import unittest
from unittest.mock import AsyncMock, Mock, patch

import requests

from deriv_client import DerivClient, DerivTransientServiceError
from models import TradingConfig
from trading_bot import TradingBot


class FakeResponse:
    def __init__(self, status_code, payload=None, text="", headers=None):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = text
        self.headers = headers or {}

    def json(self):
        return self._payload


class DerivRestRetryTests(unittest.TestCase):
    def setUp(self):
        self.client = DerivClient(app_id="test-app", account_type="demo")

    @patch("deriv_client.time.sleep")
    @patch("deriv_client.requests.request")
    def test_health_probe_503_retries_and_recovers(self, request, sleep):
        request.side_effect = [
            FakeResponse(
                503,
                {"errors": [{"message": "Service temporarily unavailable. A health probe is in progress."}]},
                text="Service temporarily unavailable. A health probe is in progress.",
            ),
            FakeResponse(200, {"data": [{"account_id": "CR123", "account_type": "demo"}]}),
        ]

        result = self.client._request_json(
            "GET", "/trading/v1/options/accounts", "test-token"
        )

        self.assertEqual(result["data"][0]["account_id"], "CR123")
        self.assertEqual(request.call_count, 2)
        sleep.assert_called_once_with(10.0)

    @patch("deriv_client.time.sleep")
    @patch("deriv_client.requests.request")
    def test_retry_after_header_is_respected(self, request, sleep):
        request.side_effect = [
            FakeResponse(503, {"errors": [{"message": "maintenance"}]}, headers={"Retry-After": "3"}),
            FakeResponse(200, {"data": []}),
        ]

        self.client._request_json("GET", "/health", "test-token")

        sleep.assert_called_once_with(10.0)

    @patch("deriv_client.time.sleep")
    @patch("deriv_client.requests.get")
    @patch("deriv_client.requests.request")
    def test_persistent_503_reports_public_health_probe_after_bounded_attempts(self, request, health_get, sleep):
        request.return_value = FakeResponse(
            503,
            {"errors": [{"message": "A health probe is in progress."}]},
        )
        health_get.return_value = FakeResponse(200, text="OK")

        with self.assertRaises(DerivTransientServiceError) as raised:
            self.client._request_json("GET", "/trading/v1/options/accounts", "test-token")

        self.assertEqual(raised.exception.status_code, 503)
        self.assertIn("after 5 attempts", str(raised.exception))
        self.assertIn("Public Deriv API health check returned HTTP 200", str(raised.exception))
        self.assertEqual(request.call_count, 5)
        self.assertEqual(health_get.call_count, 1)
        self.assertEqual(sleep.call_count, 4)

    @patch("deriv_client.time.sleep")
    @patch("deriv_client.requests.request")
    def test_invalid_token_is_not_retried(self, request, sleep):
        request.return_value = FakeResponse(
            401,
            {"errors": [{"code": "InvalidToken", "message": "Invalid token"}]},
        )

        with self.assertRaisesRegex(RuntimeError, "rejected the authorization token"):
            self.client._request_json("GET", "/trading/v1/options/accounts", "bad-token")

        request.assert_called_once()
        sleep.assert_not_called()

    @patch("deriv_client.time.sleep")
    @patch("deriv_client.requests.request")
    def test_network_timeout_is_retried(self, request, sleep):
        request.side_effect = [
            requests.exceptions.Timeout("temporary timeout"),
            FakeResponse(200, {"ok": True}),
        ]

        self.assertEqual(
            self.client._request_json("GET", "/health", "test-token"),
            {"ok": True},
        )
        self.assertEqual(request.call_count, 2)
        sleep.assert_called_once_with(1.0)


class AutoRestartRetryTests(unittest.IsolatedAsyncioTestCase):
    async def test_auto_restart_retries_temporary_deriv_outage(self):
        bot = TradingBot(TradingConfig(auto_restart_after_stop=True), session_archive=Mock())
        attempts = 0

        async def start_with_temporary_failure():
            nonlocal attempts
            attempts += 1
            if attempts == 1:
                raise DerivTransientServiceError("HTTP 503: health probe in progress", 503)
            bot.is_running = True

        bot.start = start_with_temporary_failure

        with patch("trading_bot.asyncio.sleep", new=AsyncMock()):
            await bot._restart_after_stop(0)

        self.assertEqual(attempts, 2)
        self.assertTrue(bot.is_running)
        self.assertTrue(any("AUTO-RESTART SUCCESS" in item.message for item in bot.logs))

    async def test_auto_restart_does_not_loop_on_permanent_auth_error(self):
        bot = TradingBot(TradingConfig(auto_restart_after_stop=True), session_archive=Mock())
        attempts = 0

        async def start_with_invalid_token():
            nonlocal attempts
            attempts += 1
            raise RuntimeError("Deriv rejected the authorization token (401).")

        bot.start = start_with_invalid_token

        with patch("trading_bot.asyncio.sleep", new=AsyncMock()):
            await bot._restart_after_stop(0)

        self.assertEqual(attempts, 1)
        self.assertTrue(any("AUTO-RESTART FAILED" in item.message for item in bot.logs))


if __name__ == "__main__":
    unittest.main()
