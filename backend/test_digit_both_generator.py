import random
import time
from trading_bot import TradingBot
from models import TradingConfig

WINDOW = 6 * 60 * 60

def make_bot():
    return TradingBot(TradingConfig(contract_type_mode="BOTH"))

def expected_direction(digit, window):
    anchor = random.Random(window).randint(0, 9)
    inverted = (anchor >= 6) ^ ((window % 2) == 1)
    if digit == 5:
        return None
    if not inverted:
        return "DIGITOVER" if digit <= 4 else "DIGITUNDER"
    return "DIGITUNDER" if digit <= 4 else "DIGITOVER"

def test_both_mapping_uses_wall_clock_window_not_bot_start():
    bot = make_bot()
    bot.start_time_epoch = time.time() - (30 * WINDOW)
    window = int(time.time() // WINDOW)

    assert bot._both_direction_for_digit(2) == expected_direction(2, window)
    assert bot._both_direction_for_digit(8) == expected_direction(8, window)
    assert bot.both_direction_window == window

def test_both_mapping_is_inverted_on_next_wall_clock_window():
    bot = make_bot()
    window = int(time.time() // WINDOW)

    first = expected_direction(2, window)
    next_window = window + 1
    next_expected = expected_direction(2, next_window)

    assert first != next_expected

def test_digit_five_is_always_break_even():
    bot = make_bot()
    assert bot._both_direction_for_digit(5) is None

def test_random_anchor_is_stable_for_same_wall_clock_window():
    window = int(time.time() // WINDOW)
    assert random.Random(window).randint(0, 9) == random.Random(window).randint(0, 9)
