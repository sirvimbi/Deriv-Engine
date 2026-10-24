import asyncio
from decimal import Decimal

from deriv_client import DerivClient
from models import TradingConfig
from trading_bot import TradingBot


class RecordingBotClient:
    def __init__(self):
        self.calls = []

    async def buy_contract(self, **kwargs):
        self.calls.append(kwargs)
        # Stop before contract monitoring; this test only verifies the exact
        # request that reaches the purchase API.
        return {}


class FakeProposalClient(DerivClient):
    def __init__(self):
        self.proposal_amounts = []
        self.buy_request = None

    async def _request_proposal_with_minimum_retry(self, proposal_params, requested_amount):
        amount = Decimal(str(proposal_params["amount"]))
        self.proposal_amounts.append(amount)
        return {
            "proposal": {
                "id": f"proposal-{len(self.proposal_amounts)}",
                "ask_price": str(amount),
                # A 50% net profit rate keeps the example deterministic.
                "payout": str(amount * Decimal("1.5")),
            }
        }, amount

    async def send_request(self, payload, exact_numeric_fields=None):
        self.buy_request = payload
        return {"buy": {"contract_id": 12345, "buy_price": payload["price"]}}


def test_both_recovery_executes_the_freshly_generated_direction_and_barrier():
    config = TradingConfig(
        contract_type_mode="BOTH",
        base_stake=10.0,
        max_stake=200.0,
        loss_cycle_target=2,
        both_over_barrier=3,
        both_under_barrier=6,
        recovery_over_barrier=7,
        recovery_under_barrier=2,
    )
    bot = TradingBot(config)
    client = RecordingBotClient()
    bot.client = client
    bot.is_running = True
    bot.in_recovery_cycle = True
    bot.recovery_phase = 2
    bot.recovery_loss_stake = 10.0
    bot.active_contract_type = "DIGITUNDER"  # stale direction from an earlier loss
    bot._next_both_direction = lambda: "DIGITOVER"
    bot.both_generator_digit = 4
    bot.both_direction_window = 0

    asyncio.run(bot._place_trade("BOTH"))

    assert len(client.calls) == 1
    assert client.calls[0]["contract_type"] == "DIGITOVER"
    assert client.calls[0]["barrier"] == 7  # recovery barrier follows current direction
    assert bot.active_contract_type is None
    assert any("BOTH EXECUTION SIGNAL | generator_digit=4 | type=DIGITOVER" in item.message for item in bot.logs)


def test_loss_cycle_recovery_stake_does_not_compound_previous_trade_stake():
    bot = TradingBot(TradingConfig(
        contract_type_mode="BOTH",
        base_stake=10.0,
        max_stake=200.0,
        martingale=2.0,
        martingale_enabled=True,
        recovery_wins_required=3,
        loss_cycle_target=3,
    ))
    bot.in_recovery_cycle = True
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0
    bot.martingale_executions_remaining = 3

    # $20 base-multiplier component + $10 / 3 / 95% loss-cycle component.
    expected = 20.0 + (10.0 / 3.0 / 0.95)
    assert abs(bot._calculate_recovery_stake(500.0) - expected) < 0.0001

    # Once the configured martingale executions are consumed, the multiplier
    # no longer applies, even if the setting remains enabled.
    bot.martingale_executions_remaining = 0
    expected_without_martingale = 10.0 + (10.0 / 3.0 / 0.95)
    assert abs(bot._next_recovery_stake() - expected_without_martingale) < 0.0001


def test_loss_cycle_proposal_sizing_does_not_force_stake_to_maximum():
    client = FakeProposalClient()

    result = asyncio.run(client.buy_contract(
        symbol="1HZ10V",
        contract_type="DIGITUNDER",
        amount=13.51,
        duration=1,
        duration_unit="t",
        barrier=6,
        currency="USD",
        target_profit=3.33,
        max_amount=200.0,
    ))

    assert client.proposal_amounts == [Decimal("13.51")]
    assert result["stake"] == 13.51
    assert client.buy_request["price"] == 13.51


def test_loss_cycle_sizing_fails_safely_when_target_exceeds_maximum_stake():
    client = FakeProposalClient()

    try:
        asyncio.run(client.buy_contract(
            symbol="1HZ10V",
            contract_type="DIGITUNDER",
            amount=13.51,
            duration=1,
            duration_unit="t",
            barrier=6,
            currency="USD",
            target_profit=150.0,
            max_amount=200.0,
        ))
    except Exception as exc:
        assert "cannot be achieved within max stake" in str(exc)
    else:
        raise AssertionError("Sizing should stop rather than exceed the configured maximum.")
    assert client.buy_request is None



def test_loss_cycle_does_not_reset_before_configured_recovery_win_target():
    bot = TradingBot(TradingConfig(
        contract_type_mode="BOTH",
        base_stake=0.50,
        max_stake=200.0,
        recovery_wins_required=2,
        loss_cycle_target=2,
    ))
    bot.is_running = True
    bot.in_recovery_cycle = True
    bot.recovery_phase = 1
    bot.recovery_loss_stake = 4.19
    bot.recovery_win_count = 0
    bot.active_trade_contract_id = 1

    asyncio.run(bot._handle_contract_finished(
        {"profit": 5.21, "status": "won", "exit_spot": "100.07"},
        "DIGITOVER",
        6,
        2.71,
        1,
    ))

    # The first profit clears the monetary ledger, but the configured two-win
    # recovery target must still be honored.
    assert bot.in_recovery_cycle is True
    assert bot.recovery_win_count == 1
    assert bot.recovery_loss_stake == 0.0
    assert bot.recovery_phase == 2

    bot.active_trade_contract_id = 2
    asyncio.run(bot._handle_contract_finished(
        {"profit": 0.96, "status": "won", "exit_spot": "100.08"},
        "DIGITOVER",
        6,
        0.50,
        2,
    ))

    assert bot.in_recovery_cycle is False
    assert bot.recovery_win_count == 0
    assert bot.recovery_phase == 0
    assert bot.stake == 0.50
