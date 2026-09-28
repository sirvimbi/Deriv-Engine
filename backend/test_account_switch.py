import unittest

from models import TradingConfig
from trading_bot import TradingBot


class FakeAccountClient:
    def __init__(self, account_type="demo", authorized=True):
        self.account_type = account_type
        self.app_id = "1234"
        self.authorized = authorized
        self._auth_token = "token"
        self.account_info = {
            "account_id": "DEMO123" if account_type == "demo" else "REAL123",
            "account_type": account_type,
            "currency": "USD",
        }
        self.disconnect_calls = 0
        self.authorize_calls = []

    async def disconnect(self):
        self.disconnect_calls += 1
        self.authorized = False
        self._auth_token = ""

    async def authorize(self, token):
        self.authorized = True
        self._auth_token = token
        self.authorize_calls.append(token)
        self.account_info["account_type"] = self.account_type
        self.account_info["account_id"] = "DEMO123" if self.account_type == "demo" else "REAL123"
        return {"authorize": self.account_info}

    async def subscribe_balance(self, callback):
        return {"balance": 1, "subscribe": 1}

    async def get_balance(self):
        return {"balance": 1000.0 if self.account_type == "demo" else 250.0, "currency": "USD"}


class AccountSwitchTests(unittest.IsolatedAsyncioTestCase):
    async def test_switch_reauthenticates_target_account_and_refreshes_balance(self):
        bot = TradingBot(TradingConfig(api_token="token", app_id="1234", account_type="demo"))
        client = FakeAccountClient("demo")
        bot.client = client

        account = await bot.switch_account("real")

        self.assertEqual(client.account_type, "real")
        self.assertTrue(client.authorized)
        self.assertEqual(account["account_type"], "real")
        self.assertEqual(account["account_id"], "REAL123")
        self.assertEqual(bot.account_equity, 250.0)
        self.assertGreaterEqual(client.disconnect_calls, 1)
        self.assertEqual(client.authorize_calls, ["token"])

    async def test_switch_is_blocked_while_bot_is_running(self):
        bot = TradingBot(TradingConfig(api_token="token", app_id="1234", account_type="demo"))
        bot.client = FakeAccountClient("demo")
        bot.is_running = True

        with self.assertRaisesRegex(RuntimeError, "Stop the bot before switching"):
            await bot.switch_account("real")
