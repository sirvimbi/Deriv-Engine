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


def test_martingale_is_fixed_base_multiplier_not_compounded():
    bot = make_bot(martingale_enabled=True, martingale=2.0, base_stake=10.0)
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 3
    bot.recovery_win_count = 0
    assert bot._next_recovery_stake() == 20.0

    bot.martingale_executions_remaining = 2
    assert bot._next_recovery_stake() == 20.0

    bot.martingale_executions_remaining = 1
    assert bot._next_recovery_stake() == 20.0


def test_martingale_target_zero_means_single_next_execution():
    bot = make_bot(martingale_enabled=True, martingale=2.0, base_stake=10.0)
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 1
    assert bot._next_recovery_stake() == 20.0

    bot.martingale_executions_remaining = 0
    assert bot._next_recovery_stake() == 10.0


def test_martingale_with_zero_recovery_target_adds_loss_cycle_component():
    bot = make_bot(
        martingale_enabled=True,
        martingale=2.0,
        base_stake=10.0,
        recovery_wins_required=0,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    # Recovery target=0 still gives Martingale exactly one recovery execution.
    bot.martingale_executions_remaining = 1
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0

    # $20 fixed Martingale component + $5 loss-cycle component = $25 total.
    assert bot._next_recovery_stake() == 25.0

    # After the one Martingale execution is consumed, subsequent loss-cycle
    # executions revert to base + the remaining loss-cycle component.
    bot.martingale_executions_remaining = 0
    bot.recovery_win_count = 1
    bot.recovery_loss_stake = 10.0
    assert bot._next_recovery_stake() == 20.0




def test_recovery_math_uses_actual_outstanding_loss_and_remaining_wins():
    bot = make_bot(
        base_stake=10.0,
        martingale_enabled=True,
        martingale=2.0,
        recovery_wins_required=2,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 2
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0

    assert bot._next_recovery_stake() == 25.0

    bot.recovery_win_count = 1
    bot.recovery_loss_stake = 4.09
    assert bot._next_recovery_stake() == 24.09

    bot.recovery_win_count = 0
    bot.martingale_executions_remaining = 2
    assert bot._next_recovery_stake() == 22.045


def test_recovery_math_keeps_loss_ledger_at_currency_precision():
    bot = make_bot(
        base_stake=10.0,
        martingale_enabled=True,
        martingale=2.0,
        recovery_wins_required=2,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 2
    bot.recovery_loss_stake = 10.01

    assert bot._next_recovery_stake() == 25.015
\n\ndef test_disabled_martingale_keeps_base_stake():
    bot = make_bot(martingale_enabled=False, martingale=2.0, base_stake=10.0)
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 3
    assert bot._next_recovery_stake() == 10.0


def test_loss_cycle_adds_recovery_component_to_martingale_stake():
    bot = make_bot(
        martingale_enabled=True,
        martingale=2.0,
        base_stake=10.0,
        recovery_wins_required=3,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 3
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0

    # 2x base Martingale ($20) + $10 outstanding loss / 2 remaining wins = $25.
    assert bot._next_recovery_stake() == 25.0

    bot.recovery_win_count = 1
    bot.recovery_loss_stake = 4.0
    # After one recovery win, the remaining loss must still be recovered.
    assert bot._next_recovery_stake() == 24.0


def test_loss_cycle_without_martingale_still_recovers_financial_loss():
    bot = make_bot(
        martingale_enabled=False,
        martingale=2.0,
        base_stake=10.0,
        recovery_wins_required=0,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 0
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0
    assert bot._next_recovery_stake() == 15.0


def test_loss_cycle_target_is_profit_based_not_stake_division():
    bot = make_bot(
        martingale_enabled=True,
        martingale=2.0,
        base_stake=10.0,
        recovery_wins_required=3,
        loss_cycle_target=2,
    )
    bot.in_recovery_cycle = True
    bot.martingale_executions_remaining = 3
    bot.recovery_loss_stake = 10.0
    bot.recovery_win_count = 0

    # The trade stake can be $25, but the required profit is $5 per remaining
    # cycle win. A low payout must therefore resize upward, never downward.
    assert bot.recovery_loss_stake / 2 == 5.0


def test_configurable_loss_cooldown_uses_hours_minutes_seconds():
    bot = make_bot(
        loss_cooldown_hours=1,
        loss_cooldown_minutes=2,
        loss_cooldown_seconds=3,
    )

    start = time.monotonic()
    bot._set_loss_cooldown()
    remaining = bot.recovery_cooldown_until - start

    assert 3725.0 <= remaining <= 3726.0


def test_zero_loss_cooldown_disables_post_loss_delay():
    bot = make_bot(
        loss_cooldown_hours=0,
        loss_cooldown_minutes=0,
        loss_cooldown_seconds=0,
    )

    bot._set_loss_cooldown()

    assert bot.recovery_cooldown_until == 0.0
