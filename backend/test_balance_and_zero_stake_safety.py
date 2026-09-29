import asyncio
from unittest.mock import AsyncMock

from deriv_client import DerivClient
from models import TradingConfig
from trading_bot import TradingBot


def test_zero_martingale_keeps_recovery_stake_at_base():
    config = TradingConfig(
        base_stake=1.0,
        martingale=0.0,
        recovery_wins_required=1,
    )
    bot = TradingBot(config)
    bot.stake = 1.0

    bot._apply_martingale_after_loss()

    assert bot.stake == 1.0
    assert any("MARTINGALE DISABLED" in item.message for item in bot.logs)


def test_buy_contract_does_not_poll_balance_before_purchase(monkeypatch):
    client = DerivClient()
    client.authorized = True
    client.send_request = AsyncMock(side_effect=[
        {
            "proposal": {
                "id": "proposal-1",
                "ask_price": "1.00",
                "payout": "1.33",
            }
        },
        {
            "buy": {
                "contract_id": 123,
                "buy_price": 1.0,
                "stake": 1.0,
            }
        },
    ])
    client.get_balance = AsyncMock(side_effect=AssertionError("buy_contract must not poll balance"))

    result = asyncio.run(
        client.buy_contract(
            symbol="R_100",
            contract_type="DIGITOVER",
            amount=1.0,
            duration=1,
            duration_unit="t",
            barrier=2,
            currency="USD",
        )
    )

    assert result["contract_id"] == 123
    client.get_balance.assert_not_awaited()
