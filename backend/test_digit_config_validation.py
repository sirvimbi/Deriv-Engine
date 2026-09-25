from models import TradingConfig, digit_barrier_range, validate_digit_barrier


def test_core_configuration_accepts_all_digits_0_through_9():
    for digit in range(10):
        config = TradingConfig(
            under_trigger_digit=digit,
            over_trigger_digit=digit,
            win_predict_digit=digit,
            loss_predict_digit=digit,
            recovery_win_predict_digit=digit,
        )
        assert config.under_trigger_digit == digit
        assert config.over_trigger_digit == digit
        assert config.win_predict_digit == digit
        assert config.loss_predict_digit == digit
        assert config.recovery_win_predict_digit == digit


def test_contract_barrier_ranges_are_asymmetric_at_the_edges():
    assert list(digit_barrier_range("DIGITOVER")) == list(range(0, 9))
    assert list(digit_barrier_range("DIGITUNDER")) == list(range(1, 10))


def test_digit_over_rejects_9_but_allows_0_to_8():
    for digit in range(9):
        assert validate_digit_barrier("DIGITOVER", digit) == digit
    try:
        validate_digit_barrier("DIGITOVER", 9)
        assert False, "DIGITOVER 9 must be rejected"
    except ValueError as exc:
        assert "0-8" in str(exc)


def test_digit_under_rejects_0_but_allows_1_to_9():
    try:
        validate_digit_barrier("DIGITUNDER", 0)
        assert False, "DIGITUNDER 0 must be rejected"
    except ValueError as exc:
        assert "1-9" in str(exc)

    for digit in range(1, 10):
        assert validate_digit_barrier("DIGITUNDER", digit) == digit
