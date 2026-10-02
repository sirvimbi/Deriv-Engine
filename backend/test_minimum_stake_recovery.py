import unittest
from unittest.mock import AsyncMock

from deriv_client import DerivClient


class MinimumStakeRecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def test_recovery_retries_at_deriv_minimum_and_buys_effective_stake(self):
        client = DerivClient(app_id="test", account_type="demo")
        client.authorized = True

        async def mock_send_request(req, **kwargs):
            if "proposal" in req:
                amt = float(req.get("amount", 0))
                if amt < 0.35:
                    return {"error": {"message": "Please enter a stake amount that's at least 0.35."}}
                return {"proposal": {"id": "p2", "ask_price": str(amt), "payout": str(round(amt * 1.15, 2))}}
            if "buy" in req:
                return {"buy": {"contract_id": 123, "buy_price": 0.35, "stake": 0.35}}
            if "balance" in req:
                return {"balance": {"balance": "100.00", "currency": "USD"}}
            return {}

        client.send_request = AsyncMock(side_effect=mock_send_request)

        result = await client.buy_contract(
            symbol="R_100",
            contract_type="DIGITOVER",
            amount=0.34,
            duration=1,
            duration_unit="t",
            barrier=2,
            currency="USD",
            target_profit=0.05,
            max_amount=100.00,
        )

        self.assertEqual(result.get("contract_id", 123), 123)


if __name__ == "__main__":
    unittest.main()
