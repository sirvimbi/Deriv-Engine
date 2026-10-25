import asyncio

from deriv_client import DerivClient
from models import TradingConfig
from trading_bot import TradingBot


class SnapshotClient:
    def __init__(self, snapshots):
        self.snapshots = list(snapshots)
        self.calls = []

    async def get_contract_status(self, contract_id):
        self.calls.append(contract_id)
        snapshot = self.snapshots.pop(0)
        if isinstance(snapshot, Exception):
            raise snapshot
        return snapshot


def test_status_timeout_reconciliation_processes_confirmed_terminal_snapshot():
    bot = TradingBot(TradingConfig(contract_type_mode="BOTH"))
    bot.is_running = True
    bot.is_trade_in_progress = True
    contract_id = 12345
    bot.active_trade_contract_id = contract_id
    snapshot = {
        "contract_id": contract_id,
        "contract_type": "DIGITOVER",
        "is_sold": 1,
        "status": "won",
        "profit": 0.75,
    }
    bot.client = SnapshotClient([snapshot])
    done_event = asyncio.Event()
    received = []

    async def process_update(update):
        received.append(update)
        if update.get("is_sold"):
            bot.settled_contract_ids.add(contract_id)
            bot.is_trade_in_progress = False
            done_event.set()

    recovered = asyncio.run(
        bot._reconcile_contract_status_after_timeout(
            contract_id, process_update, done_event
        )
    )

    assert recovered is True
    assert received == [snapshot]
    assert bot.client.calls == [contract_id]
    assert contract_id in bot.settled_contract_ids
    assert done_event.is_set()


def test_status_timeout_reconciliation_does_not_treat_open_contract_as_settled():
    bot = TradingBot(TradingConfig(contract_type_mode="BOTH"))
    bot.is_running = True
    bot.is_trade_in_progress = True
    contract_id = 12346
    bot.active_trade_contract_id = contract_id
    open_snapshot = {
        "contract_id": contract_id,
        "contract_type": "DIGITUNDER",
        "is_sold": 0,
        "status": "open",
    }
    bot.client = SnapshotClient([open_snapshot, open_snapshot, open_snapshot])
    done_event = asyncio.Event()
    received = []

    async def process_update(update):
        received.append(update)

    recovered = asyncio.run(
        bot._reconcile_contract_status_after_timeout(
            contract_id, process_update, done_event
        )
    )

    assert recovered is False
    assert len(bot.client.calls) == 3
    assert len(received) == 3
    assert contract_id not in bot.settled_contract_ids
    assert bot.is_trade_in_progress is True
    assert any("contract is still open" in item.message for item in bot.logs)


def test_get_contract_status_uses_one_shot_request_without_subscription():
    client = DerivClient.__new__(DerivClient)
    recorded = []
    expected = {
        "contract_id": 12347,
        "contract_type": "DIGITOVER",
        "is_sold": 1,
        "status": "lost",
    }

    async def fake_send_request(payload):
        recorded.append(payload)
        return {"proposal_open_contract": expected}

    client.send_request = fake_send_request

    result = asyncio.run(client.get_contract_status(12347))

    assert result == expected
    assert recorded == [{"proposal_open_contract": 1, "contract_id": 12347}]
    assert "subscribe" not in recorded[0]


def test_get_contract_status_reports_missing_snapshot():
    client = DerivClient.__new__(DerivClient)

    async def fake_send_request(payload):
        return {"msg_type": "proposal_open_contract"}

    client.send_request = fake_send_request

    try:
        asyncio.run(client.get_contract_status(12348))
    except RuntimeError as exc:
        assert "no proposal_open_contract snapshot" in str(exc)
    else:
        raise AssertionError("A missing contract snapshot must be reported.")


class InitialSnapshotClient:
    def __init__(self, snapshot):
        self.snapshot = snapshot
        self.callback = None
        self.buy_calls = []
        self.unsubscribed = []

    async def buy_contract(self, **kwargs):
        self.buy_calls.append(kwargs)
        return {"contract_id": 12349, "buy_price": kwargs["amount"], "stake": kwargs["amount"]}

    async def subscribe_contract(self, contract_id, callback):
        self.callback = callback
        return {"proposal_open_contract": self.snapshot}

    def unsubscribe_contract(self, contract_id):
        self.unsubscribed.append(contract_id)


def test_initial_contract_snapshot_is_processed_even_without_listener_callback():
    snapshot = {
        "contract_id": 12349,
        "contract_type": "DIGITOVER",
        "is_sold": 1,
        "status": "won",
        "profit": 0.50,
        "buy_price": "0.50",
        "entry_spot": "100.08",
        "exit_spot": "100.09",
    }
    bot = TradingBot(TradingConfig(contract_type_mode="BOTH", base_stake=0.50))
    bot.is_running = True
    bot.client = InitialSnapshotClient(snapshot)
    bot._next_both_direction = lambda: "DIGITOVER"
    bot.both_generator_digit = 8

    async def no_next_trade_in_test():
        return None

    bot._trigger_next_trade_after_settlement = no_next_trade_in_test

    asyncio.run(bot._place_trade("BOTH"))

    assert bot.client.buy_calls[0]["contract_type"] == "DIGITOVER"
    assert 12349 in bot.settled_contract_ids
    assert bot.runs == 1
    assert bot.total_wins == 1
    assert bot.is_trade_in_progress is False
    assert 12349 in bot.client.unsubscribed


def test_done_event_without_settlement_is_not_treated_as_recovered():
    bot = TradingBot(TradingConfig(contract_type_mode="BOTH"))
    bot.is_running = False
    contract_id = 12350
    bot.active_trade_contract_id = contract_id
    sold_snapshot = {
        "contract_id": contract_id,
        "contract_type": "DIGITOVER",
        "is_sold": 1,
        "status": "won",
        "profit": 0.5,
    }
    bot.client = SnapshotClient([sold_snapshot])
    done_event = asyncio.Event()

    async def incomplete_handler(update):
        # Simulates a terminal callback that signals completion for a fatal
        # mismatch/error but does not add the contract to the settled ledger.
        done_event.set()

    recovered = asyncio.run(
        bot._reconcile_contract_status_after_timeout(
            contract_id, incomplete_handler, done_event
        )
    )

    assert recovered is False
    assert contract_id not in bot.settled_contract_ids
