import asyncio
import logging
import time
from datetime import datetime
from typing import Optional, List, Dict, Any, Callable
from models import TradingConfig, BotStatus, LogMessage
from deriv_client import DerivClient
from runtime import ENGINE_BUILD

logger = logging.getLogger("TradingBot")

class TradingBot:
    def __init__(self, config: TradingConfig):
        self.config = config
        self.client = DerivClient(app_id=config.app_id, account_type=config.account_type)
        
        # State variables
        self.is_running = False
        self.is_trade_in_progress = False
        self.stake = config.base_stake
        self.predict = config.win_predict_digit
        self.time_duration = config.duration
        self.loss_streak = 0
        self.recovery_win_count = 0
        self.in_recovery_cycle = False
        self.recovery_phase = 0  # 0 normal, 1 loss digit, 2 recovery target digit
        self.recovery_prediction_active = False
        # Contract type is locked when recovery starts and is never inferred
        # from the stake amount.
        self.active_contract_type: Optional[str] = None
        self.active_trade_contract_id: Optional[int] = None
        self.settled_contract_ids = set()
        
        # Reporting / Metrics
        self.total_profit = 0.0
        self.runs = 0
        self.total_wins = 0
        self.total_losses = 0
        self.lowest_balance = 0.0
        self.lowest_loss = 0.0
        self.account_equity: Optional[float] = None
        self.account_balance: Optional[float] = None
        self.wins_in_row = 0
        self.current_win_streak = 0
        self.loss_in_row = 0
        self.current_loss_streak = 0
        
        self.last_digit: Optional[int] = None
        self.last_tick_quote: Optional[float] = None
        self.start_time_epoch = time.time()
        self.session_start_epoch = 0
        self.stop_reason: Optional[str] = None
        
        self.logs: List[LogMessage] = []
        self.status_broadcast_callback: Optional[Callable] = None

    def set_broadcast_callback(self, cb: Callable):
        self.status_broadcast_callback = cb

    def add_log(self, level: str, message: str):
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_item = LogMessage(timestamp=timestamp, level=level, message=message)
        self.logs.append(log_item)
        if len(self.logs) > 200:
            self.logs.pop(0)
        logger.info(f"[{level.upper()}] {message}")
        if self.status_broadcast_callback:
            try:
                result = self.status_broadcast_callback("log", log_item.dict())
                if asyncio.iscoroutine(result):
                    asyncio.create_task(result)
            except Exception as e:
                logger.debug(f"Unable to broadcast log event: {e}")

    def clear_logs(self):
        """Clear the in-memory execution log and notify connected dashboards."""
        self.logs.clear()
        if self.status_broadcast_callback:
            try:
                result = self.status_broadcast_callback("logs_reset", {})
                if asyncio.iscoroutine(result):
                    asyncio.create_task(result)
            except Exception as e:
                logger.debug(f"Unable to broadcast log reset: {e}")

    def update_config(self, new_config: TradingConfig):
        mode = new_config.contract_type_mode.upper()
        if mode not in ("DIGITUNDER", "DIGITOVER", "BOTH"):
            mode = "BOTH"
        new_config.contract_type_mode = mode
        self.config = new_config
        self.client.app_id = new_config.app_id
        self.client.account_type = new_config.account_type
        if not self.is_running:
            self.stake = new_config.base_stake
            self.predict = new_config.win_predict_digit
            self.time_duration = new_config.duration
        self.add_log("info", "Bot strategy configuration updated.")

    async def start(self):
        if self.is_running:
            return
        self.add_log("info", f"Authorizing bot with Deriv API Token...")
        try:
            # authorize() obtains a current Deriv OTP URL and establishes the authenticated socket.
            # Do not call connect() first: that falls back to the legacy WebSocket host and can return HTTP 520.
            await self.client.authorize(self.config.api_token)
            await self.client.subscribe_balance(self._on_balance)
            try:
                initial_balance = await self.client.get_balance()
                await self._on_balance(initial_balance)
            except Exception as balance_error:
                self.add_log("warn", f"Initial account balance unavailable: {balance_error}")
        except Exception as e:
            self.add_log("error", f"Authorization failed: {str(e)}")
            raise e

        # Reset session metrics and start a fresh execution-log/history session.
        self.logs.clear()
        self.session_start_epoch = int(time.time())
        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("logs_reset", {"started_at": self.session_start_epoch})
            except Exception:
                pass
        self.is_running = True
        self.is_trade_in_progress = False
        self.stake = self.config.base_stake
        self.predict = self.config.win_predict_digit
        self.time_duration = self.config.duration
        self.loss_streak = 0
        self.recovery_win_count = 0
        self.in_recovery_cycle = False
        self.recovery_phase = 0
        self.recovery_prediction_active = False
        self.active_contract_type = None
        self.active_trade_contract_id = None
        self.settled_contract_ids.clear()
        self.total_profit = 0.0
        self.runs = 0
        self.total_wins = 0
        self.total_losses = 0
        self.lowest_balance = 0.0
        self.lowest_loss = 0.0
        self.wins_in_row = 0
        self.current_win_streak = 0
        self.loss_in_row = 0
        self.current_loss_streak = 0
        self.start_time_epoch = time.time()
        self.stop_reason = None

        self.add_log(
            "success",
            f"Bot started | Build={ENGINE_BUILD} | Market={self.config.symbol} | "
            f"Mode={self.config.contract_type_mode} | Base stake=${self.stake:.2f} | "
            f"Under trigger={self.config.under_trigger_digit} | Over trigger={self.config.over_trigger_digit} | "
            f"Win prediction={self.config.win_predict_digit} | Loss prediction={self.config.loss_predict_digit} | "
            f"Recovery prediction={self.config.recovery_win_predict_digit} | "
            f"Recovery target={max(1, self.config.recovery_wins_required)} wins"
        )
        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("history_reset", {"started_at": int(self.start_time_epoch)})
            except Exception:
                pass

        # Subscribe to ticks
        try:
            await self.client.subscribe_ticks(self.config.symbol, self._on_tick)
        except Exception as e:
            self.is_running = False
            self.add_log("error", f"Failed to subscribe to ticks: {str(e)}")
            raise e

    async def stop(self, reason: str = "Stopped by user"):
        if not self.is_running:
            return
        self.is_running = False
        self.stop_reason = reason
        try:
            await self.client.unsubscribe_ticks(self.config.symbol)
        except Exception:
            pass
        self.add_log("warn", f"Bot stopped: {reason} | Total Profit: ${self.total_profit:.2f} | Runs: {self.runs}")
        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("status", self.get_status().dict())
            except Exception:
                pass

    async def _on_balance(self, balance_data: Dict[str, Any]):
        value = balance_data.get("balance")
        if value is None:
            return
        self.account_balance = round(float(value), 2)
        self.account_equity = self.account_balance
        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("account_equity", {"equity": self.account_equity, "balance": self.account_balance, "currency": balance_data.get("currency", self.config.currency)})
                await self.status_broadcast_callback("status", self.get_status().dict())
            except Exception as e:
                logger.debug(f"Unable to broadcast account equity: {e}")

    async def _on_tick(self, tick_data: Dict[str, Any]):
        if not self.is_running:
            return

        quote = tick_data.get("quote")
        if quote is None:
            return

        self.last_tick_quote = float(quote)
        
        # Calculate last digit accurately from price representation
        pip_size = tick_data.get("pip_size", 2)
        quote_str = f"{self.last_tick_quote:.{pip_size}f}"
        self.last_digit = int(quote_str[-1])

        # Broadcast live tick to frontend
        if self.status_broadcast_callback:
            try:
                asyncio.create_task(self.status_broadcast_callback("tick", {
                    "quote": self.last_tick_quote,
                    "last_digit": self.last_digit,
                    "symbol": self.config.symbol
                }))
            except Exception:
                pass

        if self.is_trade_in_progress:
            return

        # Recovery state is authoritative. Do not use stake > base_stake
        # as the recovery test: max_stake can clamp recovery to base_stake.
        if self.in_recovery_cycle and self.active_contract_type:
            self.predict = (self.config.loss_predict_digit if self.recovery_phase == 1 else self.config.recovery_win_predict_digit)
            self._schedule_trade(self.active_contract_type)
            return

        # Normal/base-stake entry respects the configured allowed contract mode.
        # The first valid trigger selects the contract type; that type remains
        # fixed through recovery until the recovery target is completed.
        if self.in_recovery_cycle:
            return

        mode = self.config.contract_type_mode.upper()
        under_allowed = mode in ("DIGITUNDER", "BOTH")
        over_allowed = mode in ("DIGITOVER", "BOTH")

        if under_allowed and self.last_digit == self.config.under_trigger_digit and abs(self.stake - self.config.base_stake) < 0.001:
            self._schedule_trade("DIGITUNDER")
        elif over_allowed and self.last_digit == self.config.over_trigger_digit and abs(self.stake - self.config.base_stake) < 0.001:
            self._schedule_trade("DIGITOVER")

    def _schedule_trade(self, contract_type: str):
        if self.is_trade_in_progress or not self.is_running:
            return
        # Reserve the slot before create_task so two ticks cannot queue trades
        # against the same mutable recovery state.
        self.is_trade_in_progress = True
        asyncio.create_task(self._place_trade(contract_type))

    async def _place_trade(self, contract_type: str):
        if not self.is_running:
            self.is_trade_in_progress = False
            return

        # Capture immutable trade context before any await. Settlement uses
        # this exact context rather than whatever state the next step has.
        if self.in_recovery_cycle and self.active_contract_type:
            contract_type = self.active_contract_type
        elif not self.in_recovery_cycle:
            self.active_contract_type = contract_type

        trade_contract_type = contract_type
        if self.in_recovery_cycle:
            trade_prediction = (self.config.loss_predict_digit if self.recovery_phase == 1 else self.config.recovery_win_predict_digit)
            self.predict = trade_prediction
        else:
            trade_prediction = int(self.config.win_predict_digit)
            self.predict = trade_prediction
        trade_stake = float(self.stake)

        self.add_log(
            "info",
            f"EXECUTION REQUEST | type={trade_contract_type} | barrier={trade_prediction} | "
            f"stake=${trade_stake:.2f} | recovery={self.in_recovery_cycle} | phase={self.recovery_phase} | "
            f"recovery_wins={self.recovery_win_count}/{max(1, self.config.recovery_wins_required)} | "
            f"locked_contract={self.active_contract_type or trade_contract_type}"
        )

        try:
            buy_res = await self.client.buy_contract(
                symbol=self.config.symbol,
                contract_type=trade_contract_type,
                amount=trade_stake,
                duration=self.time_duration,
                duration_unit=self.config.duration_unit,
                barrier=trade_prediction,
                currency=self.config.currency
            )
            
            contract_id = buy_res.get("contract_id")
            if not contract_id:
                self.add_log("error", "Received invalid contract_id from Deriv.")
                self.is_trade_in_progress = False
                return

            contract_id = int(contract_id)
            self.active_trade_contract_id = contract_id
            self.add_log(
                "info",
                f"Contract #{contract_id} placed. Type={trade_contract_type} | "
                f"Prediction={trade_prediction} | Stake=${trade_stake:.2f} | Waiting for outcome..."
            )

            # The contract id is an idempotency key. Duplicate final updates
            # must never advance the recovery state twice.
            done_event = asyncio.Event()

            contract_verified = False

            async def _on_contract_update(poc: Dict[str, Any]):
                nonlocal contract_verified
                if not contract_verified:
                    returned_type = poc.get("contract_type")
                    if returned_type:
                        contract_verified = True
                        if str(returned_type).upper() != str(trade_contract_type).upper():
                            self.add_log(
                                "error",
                                f"CONTRACT MISMATCH | requested={trade_contract_type} | "
                                f"Deriv returned={returned_type} | contract_id={contract_id}. "
                                f"Stopping bot to prevent further trades."
                            )
                            await self.stop("Deriv contract type mismatch")
                            done_event.set()
                            return
                        self.add_log(
                            "info",
                            f"CONTRACT VERIFIED | id={contract_id} | type={returned_type} | "
                            f"requested={trade_contract_type} | barrier={trade_prediction}"
                        )

                if poc.get("is_sold"):
                    if contract_id in self.settled_contract_ids:
                        return
                    self.settled_contract_ids.add(contract_id)
                    self.client.unsubscribe_contract(contract_id)
                    await self._handle_contract_finished(
                        poc,
                        trade_contract_type=trade_contract_type,
                        trade_prediction=trade_prediction,
                        trade_stake=trade_stake,
                        contract_id=contract_id
                    )
                    done_event.set()

            await self.client.subscribe_contract(contract_id, _on_contract_update)
            
            # Timeout safety after 30 seconds. A settlement callback may
            # have completed the trade immediately before the wait timed out,
            # or the bot may have stopped because the settlement triggered a
            # risk limit. In either case this is a normal monitor shutdown,
            # not a failed contract.
            try:
                await asyncio.wait_for(done_event.wait(), timeout=30.0)
            except asyncio.TimeoutError:
                if contract_id in self.settled_contract_ids or not self.is_running:
                    self.client.unsubscribe_contract(contract_id)
                    self.is_trade_in_progress = False
                    return
                self.client.unsubscribe_contract(contract_id)
                self.add_log("error", f"Contract #{contract_id} status timeout.")
                self.is_trade_in_progress = False

        except Exception as e:
            self.add_log("error", f"Error placing trade: {str(e)}")
            self.is_trade_in_progress = False

    async def _handle_contract_finished(
        self,
        poc: Dict[str, Any],
        trade_contract_type: str,
        trade_prediction: int,
        trade_stake: float,
        contract_id: int
    ):
        if contract_id != self.active_trade_contract_id:
            self.add_log(
                "warn",
                f"Ignoring stale settlement for contract #{contract_id}; "
                f"active contract is #{self.active_trade_contract_id}."
            )
            return

        profit = float(poc.get("profit", 0.0))
        status = poc.get("status")  # "won" or "lost"
        is_win = (profit > 0 or status == "won")

        self.total_profit += profit
        self.runs += 1

        # Lowest balance calculation
        if self.total_profit < self.lowest_balance:
            self.lowest_balance = self.total_profit

        if is_win:
            self.total_wins += 1
            self.current_win_streak += 1
            self.current_loss_streak = 0
            if self.current_win_streak > self.wins_in_row:
                self.wins_in_row = self.current_win_streak

            self.add_log("success", f"Trade WON! +${profit:.2f} | Total Profit: ${self.total_profit:.2f}")

            # Recovery cycle: the first Martingale trade keeps the existing
            # loss prediction. Once that trade completes, every subsequent
            # recovery trade uses the dedicated recovery-win prediction until
            # the configured number of recovery wins is completed.
            if self.in_recovery_cycle:
                self.recovery_win_count += 1
                target = max(1, self.config.recovery_wins_required)
                if self.recovery_win_count >= target:
                    self.stake = self.config.base_stake
                    self.recovery_win_count = 0
                    self.in_recovery_cycle = False
                    self.recovery_phase = 0
                    self.recovery_prediction_active = False
                    self.active_contract_type = None
                    self.predict = self.config.win_predict_digit
                    self.add_log(
                        "info",
                        f"Recovery win goal reached ({target} wins). Contract={trade_contract_type}; "
                        f"resetting stake to base ${self.stake:.2f} and prediction digit to {self.predict}."
                    )
                else:
                    self.recovery_phase = 2
                    self.recovery_prediction_active = True
                    self.predict = self.config.recovery_win_predict_digit
                    self.add_log(
                        "info",
                        f"Recovery win {self.recovery_win_count}/{target}. Continuing "
                        f"{trade_contract_type} recovery with prediction digit {self.predict}."
                    )
            else:
                self.stake = self.config.base_stake
                self.recovery_win_count = 0
                self.recovery_prediction_active = False
                self.recovery_phase = 0
                self.active_contract_type = None
                self.predict = self.config.win_predict_digit

            self.time_duration = self.config.duration
            self.loss_streak = 0

        else:
            self.total_losses += 1
            self.current_loss_streak += 1
            self.current_win_streak = 0
            if self.current_loss_streak > self.loss_in_row:
                self.loss_in_row = self.current_loss_streak

            if profit < self.lowest_loss:
                self.lowest_loss = profit

            self.loss_streak += 1
            self.add_log("error", f"Trade LOST! -${abs(profit):.2f} | Loss Streak: {self.loss_streak} | Total Profit: ${self.total_profit:.2f}")

            # Loss safety streak check
            if self.loss_streak >= self.config.max_loss_streak:
                self.stake = self.config.base_stake
                self.recovery_win_count = 0
                self.in_recovery_cycle = False
                self.recovery_phase = 0
                self.recovery_prediction_active = False
                self.active_contract_type = None
                self.predict = self.config.win_predict_digit
                self.time_duration = self.config.duration
                self.loss_streak = 0
                self.add_log("warn", f"Max loss streak threshold ({self.config.max_loss_streak}) hit! Resetting stake to base: ${self.stake:.2f}")
            else:
                # Preserve the existing loss-prediction trade immediately after
                # a loss. The following trade(s) in the recovery cycle switch to
                # the dedicated recovery-win prediction digit.
                self.stake = min(self.stake * self.config.martingale, self.config.max_stake)
                self.recovery_win_count = 0
                self.in_recovery_cycle = True
                self.recovery_phase = 1
                self.active_contract_type = trade_contract_type
                self.recovery_prediction_active = False
                self.predict = self.config.loss_predict_digit
                self.time_duration = self.config.duration
                self.add_log(
                    "info",
                    f"Next stake increased to ${self.stake:.2f} (Martingale x{self.config.martingale}). "
                    f"Recovery contract LOCKED to {self.active_contract_type}; "
                    f"next recovery prediction={self.predict}; recovery wins reset to 0."
                )

        # Check stopping criteria
        if self.total_profit >= self.config.take_profit:
            await self.stop(f"Take Profit limit reached (+${self.total_profit:.2f} >= ${self.config.take_profit:.2f})")
        elif self.total_profit <= -self.config.stop_loss:
            await self.stop(f"Stop Loss limit reached (${self.total_profit:.2f} <= -${self.config.stop_loss:.2f})")
        elif self.runs >= self.config.max_runs:
            await self.stop(f"Max runs limit reached ({self.runs} >= {self.config.max_runs})")

        self.is_trade_in_progress = False
        if self.active_trade_contract_id == contract_id:
            self.active_trade_contract_id = None

        try:
            settled_balance = await self.client.get_balance()
            await self._on_balance(settled_balance)
        except Exception as balance_error:
            logger.debug(f"Unable to refresh settled account balance: {balance_error}")

        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("status", self.get_status().dict())
                await self.status_broadcast_callback("history_refresh", {"reason": "contract_finished"})
            except Exception:
                pass

    def get_status(self) -> BotStatus:
        win_rate = (self.total_wins / self.runs * 100.0) if self.runs > 0 else 0.0
        duration_mins = (time.time() - self.start_time_epoch) / 60.0 if self.is_running else 0.0

        return BotStatus(
            is_running=self.is_running,
            is_trade_in_progress=self.is_trade_in_progress,
            total_profit=round(self.total_profit, 2),
            runs=self.runs,
            total_wins=self.total_wins,
            total_losses=self.total_losses,
            win_rate=round(win_rate, 2),
            current_stake=round(self.stake, 2),
            current_predict=self.predict,
            loss_streak=self.loss_streak,
            recovery_win_count=self.recovery_win_count,
            lowest_balance=round(self.lowest_balance, 2),
            lowest_loss=round(self.lowest_loss, 2),
            wins_in_row=self.wins_in_row,
            loss_in_row=self.loss_in_row,
            last_digit=self.last_digit,
            last_tick_quote=self.last_tick_quote,
            duration_minutes=round(duration_mins, 1),
            stop_reason=self.stop_reason,
            config=self.config,
            equity=self.account_equity
        )
