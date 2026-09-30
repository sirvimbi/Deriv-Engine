import time
from trading_bot import TradingBot
from models import TradingConfig

def make_bot():
    return TradingBot(TradingConfig(contract_type_mode="BOTH"))

def test_both_mapping_first_window():
    bot=make_bot()
    bot.start_time_epoch=time.time()
    assert bot._both_direction_for_digit(0)=="DIGITOVER"
    assert bot._both_direction_for_digit(4)=="DIGITOVER"
    assert bot._both_direction_for_digit(5) is None
    assert bot._both_direction_for_digit(6)=="DIGITUNDER"
    assert bot._both_direction_for_digit(9)=="DIGITUNDER"

def test_both_mapping_inverts_each_six_hours():
    bot=make_bot()
    bot.start_time_epoch=time.time()-21601
    assert bot._both_direction_for_digit(0)=="DIGITUNDER"
    assert bot._both_direction_for_digit(9)=="DIGITOVER"
    bot.start_time_epoch=time.time()-43201
    assert bot._both_direction_for_digit(0)=="DIGITOVER"
    assert bot._both_direction_for_digit(9)=="DIGITUNDER"
