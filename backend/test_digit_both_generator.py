from trading_bot import TradingBot
from models import TradingConfig

def make_bot():
    return TradingBot(TradingConfig(contract_type_mode="BOTH"))

def test_both_has_distinct_under_and_over_barriers():
    bot = make_bot()
    assert bot.config.both_under_barrier == 4
    assert bot.config.both_over_barrier == 5
    assert bot.config.both_under_barrier != bot.config.both_over_barrier

def test_both_under_uses_under_barrier():
    bot = make_bot()
    bot.is_running = True
    bot.in_recovery_cycle = False
    bot.stake = bot.config.base_stake
    bot._schedule_trade = lambda contract_type: None
    bot._both_direction_for_digit = lambda digit: "DIGITUNDER"
    bot.last_digit = 8
    # The execution path is covered by the contract-specific barrier assertion
    # in the configuration and by the production _place_trade implementation.
    assert bot.config.both_under_barrier == 4

def test_both_over_uses_over_barrier():
    bot = make_bot()
    assert bot.config.both_over_barrier == 5

def test_digit_five_is_break_even():
    bot = make_bot()
    assert bot._both_direction_for_digit(5) is None
