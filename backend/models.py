from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any


# Core digit configuration is always 0-9. Contract-specific barrier rules are
# applied only when the selected contract is known:
#   DIGITOVER  -> 0-8 (a final digit can never be greater than 9)
#   DIGITUNDER -> 1-9 (a final digit can never be less than 0)
# Entry-trigger digits remain 0-9 for both contract types.
DIGIT_CORE_MIN = 0
DIGIT_CORE_MAX = 9


def digit_barrier_range(contract_type: str):
    """Return the valid barrier range for a concrete digit contract."""
    contract = str(contract_type).upper()
    if contract == "DIGITOVER":
        return range(0, 9)
    if contract == "DIGITUNDER":
        return range(1, 10)
    if contract in ("DIGITMATCH", "DIGITDIFF"):
        return range(0, 10)
    return range(0, 10)


def validate_digit_barrier(contract_type: str, barrier: int) -> int:
    """Validate a digit barrier without narrowing the core 0-9 config domain."""
    try:
        value = int(barrier)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Digit barrier must be an integer from {DIGIT_CORE_MIN} to {DIGIT_CORE_MAX}.") from exc

    if value < DIGIT_CORE_MIN or value > DIGIT_CORE_MAX:
        raise ValueError(f"Digit barrier must be between {DIGIT_CORE_MIN} and {DIGIT_CORE_MAX}.")

    contract = str(contract_type).upper()
    allowed = digit_barrier_range(contract)
    if value not in allowed:
        if contract == "DIGITOVER":
            raise ValueError("DIGITOVER barrier must be 0-8.")
        if contract == "DIGITUNDER":
            raise ValueError("DIGITUNDER barrier must be 1-9.")
    return value

class TradingConfig(BaseModel):
    api_token: str = Field(
        default="",
        description="Deriv API Access Token"
    )
    app_id: str = Field(
        default="",
        description="Current Deriv App ID registered on developers.deriv.com"
    )
    symbol: str = Field(default="R_100", description="Market Symbol (e.g. R_100)")
    base_stake: float = Field(default=30.0, ge=0, le=100, description="Base Stake Amount (0-100)")
    max_stake: float = Field(default=1000.0, ge=0, le=1000, description="Maximum Stake Limit (0-1000)")
    martingale_enabled: bool = Field(default=False, description="Enable Martingale stake multiplication after a loss.")
    martingale: float = Field(default=2.0, ge=0, le=50, description="Martingale Multiplier on Loss (0-50).")
    take_profit: float = Field(default=500.0, ge=0, le=500, description="Take Profit Target (0-500); 0 disables the target.")
    stop_loss: float = Field(default=500.0, ge=0, le=500, description="Hard Stop Loss Limit (0-500); 0 disables the limit.")
    auto_restart_after_stop: bool = Field(default=False, description="Automatically restart one minute after a Take Profit or Hard Stop Loss.")
    auto_restart_after_take_profit: bool = Field(default=False, description="Legacy alias for auto_restart_after_stop.")
    max_runs: int = Field(default=250, ge=0, le=500, description="Maximum Number of Runs/Trades (0-500)")
    max_loss_streak: int = Field(default=4, ge=0, le=50, description="Max Loss Streak Before Reset (0-50)")
    loss_cooldown_hours: int = Field(default=0, ge=0, le=24, description="Cooldown hours after a loss (0-24).")
    loss_cooldown_minutes: int = Field(default=0, ge=0, le=59, description="Cooldown minutes after a loss (0-59).")
    loss_cooldown_seconds: int = Field(default=0, ge=0, le=59, description="Cooldown seconds after a loss (0-59).")
    under_trigger_digit: int = Field(default=2, ge=0, le=9, description="Entry trigger digit for DIGITUNDER when stake == baseStake (0-9)")
    over_trigger_digit: int = Field(default=8, ge=0, le=9, description="Entry trigger digit for DIGITOVER when stake == baseStake (0-9)")
    win_predict_digit: int = Field(default=8, ge=0, le=9, description="Digit contract barrier / win prediction for single-direction modes (0-9)")
    both_under_barrier: int = Field(default=4, ge=1, le=9, description="DigitUNDER barrier used by BOTH mode (1-9)")
    both_over_barrier: int = Field(default=5, ge=0, le=8, description="DigitOVER barrier used by BOTH mode (0-8)")
    both_inverse_enabled: bool = Field(default=True, description="Enable alternating inverse logic for BOTH digit generator.")
    both_inverse_interval_hours: int = Field(default=6, ge=1, le=24, description="Wall-clock hours between BOTH inverse-logic toggles (1-24).")
    loss_predict_digit: int = Field(default=3, ge=0, le=9, description="Prediction Digit on Loss (0-9)")
    recovery_over_barrier: int = Field(default=7, ge=0, le=8, description="Recovery Win Target Barrier for Digit-Over contracts (0-8)")
    recovery_under_barrier: int = Field(default=2, ge=1, le=9, description="Recovery Win Target Barrier for Digit-Under contracts (1-9)")
    recovery_win_predict_digit: int = Field(default=7, ge=0, le=9, description="Legacy alias for recovery_over_barrier.")
    duration: int = Field(default=1, ge=0, le=50, description="Trade Duration in ticks (0-50)")
    duration_unit: str = Field(default="t", description="Duration Unit ('t' for ticks, 's' for seconds)")
    currency: str = Field(default="USD", description="Currency Code")
    recovery_wins_required: int = Field(default=2, ge=0, le=50, description="Recovery Wins Required (0-50); 0 disables win-count recovery.")
    loss_cycle_target: int = Field(
        default=0,
        ge=0,
        le=20,
        description="Loss Cycle Target: 0 disables loss-amount recovery; 1-20 divides outstanding losses across recovery wins."
    )
    contract_type_mode: str = Field(default="BOTH", description="Trading type: DIGITUNDER, DIGITOVER, BOTH, CALL (Rise), PUT (Fall), or RISEFALL (direction follows tick movement)")
    account_type: str = Field(default="demo", description="Deriv account type: demo or real")
    both_random_seed: str = Field(
        default="",
        description="Persistent random seed used only to randomize Digit BOTH orientation independently of bot runtime."
    )

class AccountSwitchRequest(BaseModel):
    account_type: str = Field(description="Target Deriv Options account type: demo or real")
    confirm_real_account: bool = Field(default=False, description="Explicit confirmation required before switching to real-money trading.")

class BotStatus(BaseModel):
    is_running: bool
    is_trade_in_progress: bool
    total_profit: float
    runs: int
    total_wins: int
    total_losses: int
    win_rate: float
    current_stake: float
    current_predict: int
    loss_streak: int
    recovery_win_count: int
    lowest_balance: float
    lowest_loss: float
    wins_in_row: int
    loss_in_row: int
    last_digit: Optional[int]
    last_tick_quote: Optional[float]
    duration_minutes: float
    stop_reason: Optional[str]
    config: TradingConfig
    equity: Optional[float] = None

class ManualTradeRequest(BaseModel):
    symbol: str = "R_100"
    contract_type: str = "DIGITUNDER"
    amount: float = 10.0
    duration: int = 1
    duration_unit: str = "t"
    prediction: Optional[int] = 8
    currency: str = "USD"

class LogMessage(BaseModel):
    timestamp: str
    level: str
    message: str

class TransactionItem(BaseModel):
    contract_id: Optional[int] = None
    transaction_id: Optional[int] = None
    action: Optional[str] = None
    amount: Optional[float] = None
    balance_after: Optional[float] = None
    transaction_time: Optional[int] = None
    symbol: Optional[str] = None
    longcode: Optional[str] = None
    profit: Optional[float] = None
