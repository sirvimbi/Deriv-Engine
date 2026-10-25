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
