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


def test_both_mapping_inverts_on_next_six_hour_window(monkeypatch):
    bot = make_bot()
    six_hours = 6 * 60 * 60

    monkeypatch.setattr(time, "time", lambda: 100 * six_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITOVER"

    monkeypatch.setattr(time, "time", lambda: 101 * six_hours + 1)
    assert bot._both_direction_for_digit(2) == "DIGITUNDER"

    monkeypatch.setattr(time, "time", lambda: 101 * six_hours + 1)
    assert bot._both_direction_for_digit(8) == "DIGITOVER"


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
