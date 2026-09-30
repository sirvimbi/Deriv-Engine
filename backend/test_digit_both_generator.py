import asyncio
import time

from trading_bot import TradingBot
from models import TradingConfig


def make_bot(**kwargs):
    return TradingBot(
        TradingConfig(
            contract_type_mode="BOTH",
            **kwargs,
        )
    )


def test_both_normal_mapping():
    bot = make_bot()
    bot.both_direction_window = 0

    assert bot._both_direction_for_digit(0) == "DIGITOVER"
    assert bot._both_direction_for_digit(4) == "DIGITOVER"
    assert bot._both_direction_for_digit(5) is None
    assert bot._both_direction_for_digit(6) == "DIGITUNDER"
    assert bot._both_direction_for_digit(9) == "DIGITUNDER"


def test_both_mapping_inverts_on_configured_interval(monkeypatch):
    bot = make_bot(both_inverse_enabled=True, both_inverse_interval_hours=6)
    six_hours = 6 * 60 * 60

    monkeypatch.setattr(time, "time", lambda: 100 * six_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITOVER"

    monkeypatch.setattr(time, "time", lambda: 101 * six_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITUNDER"

    monkeypatch.setattr(time, "time", lambda: 101 * six_hours + 1)
    assert bot._both_direction_for_digit(8) == "DIGITOVER"


def test_both_inverse_can_be_disabled(monkeypatch):
    bot = make_bot(both_inverse_enabled=False, both_inverse_interval_hours=1)

    monkeypatch.setattr(time, "time", lambda: 100 * 60 * 60 + 1)
    assert bot._both_direction_for_digit(2) == "DIGITOVER"

    monkeypatch.setattr(time, "time", lambda: 101 * 60 * 60 + 1)
    assert bot._both_direction_for_digit(2) == "DIGITOVER"


def test_both_inverse_uses_custom_interval(monkeypatch):
    bot = make_bot(both_inverse_enabled=True, both_inverse_interval_hours=3)
    three_hours = 3 * 60 * 60

    monkeypatch.setattr(time, "time", lambda: 100 * three_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITOVER"

    monkeypatch.setattr(time, "time", lambda: 101 * three_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITUNDER"


def test_next_both_direction_uses_fresh_random_digit():
    bot = make_bot()

    class FakeRng:
        def __init__(self):
            self.values = iter([2, 8, 5])

        def randint(self, start, end):
            assert (start, end) == (0, 9)
            return next(self.values)

    bot._both_rng = FakeRng()
    bot.both_direction_window = 0

    assert bot._next_both_direction() == "DIGITOVER"
    assert bot.both_generator_digit == 2

    assert bot._next_both_direction() == "DIGITUNDER"
    assert bot.both_generator_digit == 8

    assert bot._next_both_direction() is None
    assert bot.both_generator_digit == 5


def test_both_recovery_does_not_lock_to_previous_contract():
    bot = make_bot(loss_cycle_target=2)
    bot.active_trade_contract_id = 123
    bot.is_running = True
    bot.in_recovery_cycle = True
    bot.active_contract_type = "DIGITUNDER"

    asyncio.run(
        bot._handle_contract_finished(
            {
                "profit": -1.0,
                "status": "lost",
                "entry_spot": "100.00",
                "exit_spot": "100.09",
                "buy_price": "1.00",
            },
            "DIGITUNDER",
            4,
            1.0,
            123,
        )
    )

    assert bot.active_contract_type is None
    assert bot.in_recovery_cycle is True


def test_both_recovery_barriers_are_distinct():
    bot = make_bot()
    assert bot.config.both_under_barrier == 4
    assert bot.config.both_over_barrier == 5
    assert bot.config.both_under_barrier != bot.config.both_over_barrier


def test_both_barrier_follows_actual_contract_type():
    bot = make_bot()
    assert bot._barrier_for_contract("DIGITUNDER") == 4
    assert bot._barrier_for_contract("DIGITOVER") == 5


def test_martingale_requires_explicit_enable():
    disabled = make_bot(martingale_enabled=False, martingale=2.0, base_stake=5.0)
    disabled.stake = 5.0
    disabled._apply_martingale_after_loss()
    assert disabled.stake == 5.0

    enabled = make_bot(martingale_enabled=True, martingale=2.0, base_stake=5.0)
    enabled.stake = 5.0
    enabled._apply_martingale_after_loss()
    assert enabled.stake == 10.0


def test_both_recovery_does_not_replace_new_direction_with_old_lock():
    bot = make_bot()
    bot.in_recovery_cycle = True
    bot.active_contract_type = "DIGITUNDER"

    # The execution layer must preserve the freshly selected BOTH direction.
    # This is the regression contract for the bug seen in the execution logs.
    assert bot.config.contract_type_mode == "BOTH"
    assert bot._barrier_for_contract("DIGITOVER") == bot.config.both_over_barrier
