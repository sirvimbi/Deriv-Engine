from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any

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
    martingale: float = Field(default=2.0, ge=0, le=50, description="Martingale Multiplier on Loss (0-50)")
    take_profit: float = Field(default=500.0, ge=0, le=10000, description="Take Profit Target (0-10000)")
    stop_loss: float = Field(default=500.0, description="Stop Loss Limit")
    max_runs: int = Field(default=250, ge=0, le=500, description="Maximum Number of Runs/Trades (0-500)")
    max_loss_streak: int = Field(default=4, ge=0, le=50, description="Max Loss Streak Before Reset (0-50)")
    under_trigger_digit: int = Field(default=2, ge=0, le=9, description="Digit Trigger for DIGITUNDER when stake == baseStake (0-9)")
    over_trigger_digit: int = Field(default=8, ge=0, le=9, description="Digit Trigger for DIGITOVER when stake > baseStake (0-9)")
    win_predict_digit: int = Field(default=8, ge=0, le=9, description="Prediction Digit on Win (0-9)")
    loss_predict_digit: int = Field(default=3, ge=0, le=9, description="Prediction Digit on Loss (0-9)")
    recovery_win_predict_digit: int = Field(default=3, ge=0, le=9, description="Prediction Digit during recovery win target cycle (0-9)")
    duration: int = Field(default=1, ge=0, le=50, description="Trade Duration in ticks (0-50)")
    duration_unit: str = Field(default="t", description="Duration Unit ('t' for ticks, 's' for seconds)")
    currency: str = Field(default="USD", description="Currency Code")
    recovery_wins_required: int = Field(default=2, ge=0, le=50, description="Recovery Wins Required (0-50)")
    contract_type_mode: str = Field(default="BOTH", description="Allowed digit contract types: DIGITUNDER, DIGITOVER, or BOTH")
    account_type: str = Field(default="demo", description="Deriv account type: demo or real")

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
