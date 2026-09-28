import unittest
from unittest.mock import AsyncMock

from deriv_client import DerivClient


class MinimumStakeRecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def test_recovery_retries_at_deriv_minimum_and_buys_effective_stake(self):
        client = DerivClient(app_id="test", account_type="demo")
        client.authorized = True

        responses = [
            {"proposal": {"id": "p1", "ask_price": "0.50", "payout": "0.575"}},
            {"error": {"message": "Please enter a stake amount that's at least 0.35."}},
            {"proposal": {"id": "p2", "ask_price": "0.35", "payout": "0.4025"}},
            {"balance": {"balance": "100.00", "currency": "USD"}},
            {"buy": {"contract_id": 123, "buy_price": 0.35, "stake": 0.35}},
        ]
        client.send_request = AsyncMock(side_effect=responses)

        result = await client.buy_contract(
            symbol="R_100",
            contract_type="DIGITOVER",
            amount=1.00,
            duration=1,
            duration_unit="t",
            barrier=2,
            currency="USD",
            target_profit=0.05,
            max_amount=100.00,
        )

        self.assertEqual(result["contract_id"], 123)
        self.assertAlmostEqual(result["stake"], 0.35)
        proposal_requests = [
            call.args[0]
            for call in client.send_request.await_args_list
            if call.args and call.args[0].get("proposal") == 1
        ]
        self.assertEqual([p["amount"] for p in proposal_requests], [1.0, 0.34, 0.35])


if __name__ == "__main__":
    unittest.main()
