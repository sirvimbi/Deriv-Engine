import asyncio
import logging
import random
import time
from decimal import Decimal
from datetime import datetime
from typing import Optional, List, Dict, Any, Callable
from models import TradingConfig, BotStatus, LogMessage, validate_digit_barrier
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
        # Positive amount of loss stake still outstanding in optional loss-cycle recovery mode.
        self.recovery_loss_stake = 0.0
        self.in_recovery_cycle = False
        self.recovery_phase = 0  # 0 normal, 1 loss digit, 2 recovery target digit
        self.recovery_prediction_active = False
        self.recovery_cooldown_until = 0.0
        self._recovery_cooldown_logged = False
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
        self.previous_tick_quote: Optional[float] = None
        self.last_tick_pip_size: Optional[int] = None
        self.start_time_epoch = time.time()
        self.session_start_epoch = 0
        # BOTH mode is anchored to configurable wall-clock inverse windows,
        # never bot runtime. The current window gets an independent random
        # orientation when inverse logic is enabled.
        self.both_direction_window = 0
        self.both_direction_anchor_digit: Optional[int] = None
        self.both_generator_digit: Optional[int] = None
        self._both_rng = random.SystemRandom()
        self.stop_reason: Optional[str] = None
        self._auto_restart_task: Optional[asyncio.Task] = None
        
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

    async def switch_account(self, account_type: str, api_token: Optional[str] = None, app_id: Optional[str] = None):
        """Switch the authenticated Deriv Options account before trading resumes.

        Deriv account-scoped WebSockets are tied to the account selected when
        the OTP is issued. Changing only the local account_type flag is not
        enough; the existing socket must be closed and a fresh OTP/socket must
        be established for the target account.
        """
        target = str(account_type).strip().lower()
        if target not in ("demo", "real"):
            raise ValueError("Account type must be either 'demo' or 'real'.")
        if self.is_running:
            raise RuntimeError("Stop the bot before switching trading accounts. No account switch is allowed while the bot is running.")
        if self.is_trade_in_progress:
            raise RuntimeError("An active trade is still settling. Wait for settlement before switching accounts.")

        token = api_token if api_token is not None else self.config.api_token
        target_app_id = app_id if app_id is not None else self.config.app_id
        if not token:
            raise ValueError("Deriv API token is required before switching accounts.")
        if not target_app_id:
            raise ValueError("Deriv App ID is required before switching accounts.")

        previous_type = self.client.account_type
        previous_app_id = self.client.app_id
        previous_token = self.client._auth_token or self.config.api_token
        previous_authorized = self.client.authorized

        if previous_type == target and previous_app_id == target_app_id and self.client.authorized:
            balance = await self.client.get_balance()
            await self._on_balance(balance)
            return self.client.account_info

        try:
            await self.client.disconnect()
            self.client.app_id = target_app_id
            self.client.account_type = target
            await self.client.authorize(token)
            await self.client.subscribe_balance(self._on_balance)
            balance = await self.client.get_balance()
            await self._on_balance(balance)
            account = dict(self.client.account_info)
            actual_type = str(account.get("account_type", target)).lower()
            if actual_type != target:
                raise RuntimeError("Deriv authenticated a %s account instead of the requested %s account." % (actual_type, target))
            self.add_log(
                "success",
                "ACCOUNT SWITCHED | account_type=%s | account_id=%s | balance=$%.2f" % (actual_type, account.get("account_id", "unknown"), self.account_balance or 0.0)
            )
            return account
        except Exception:
            try:
                await self.client.disconnect()
                self.client.app_id = previous_app_id
                self.client.account_type = previous_type
                if previous_authorized and previous_token:
                    await self.client.authorize(previous_token)
                    await self.client.subscribe_balance(self._on_balance)
                    balance = await self.client.get_balance()
                    await self._on_balance(balance)
            except Exception as restore_error:
                logger.error("Unable to restore previous Deriv account after switch failure: %s", restore_error)
            raise

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

    def _both_direction_for_digit(self, digit: Optional[int]) -> Optional[str]:
        """Map a generated 0-9 digit to BOTH contract direction.

        Normal six-hour window: 0-4 -> OVER, 5 -> skip, 6-9 -> UNDER.
        Every six-hour wall-clock window the mapping is inverted.
        The generated digit is independent of the market quote and uses
        SystemRandom, matching the requested random.randint(0, 9) behavior.
        """
        if digit is None or digit == 5 or not 0 <= int(digit) <= 9:
            return None

        interval_hours = max(1, int(self.config.both_inverse_interval_hours))
        interval_seconds = interval_hours * 60 * 60
        window = int(time.time() // interval_seconds)
        self.both_direction_window = window
        inverted = bool(self.config.both_inverse_enabled) and (window % 2) == 1

        if not inverted:
            return "DIGITOVER" if digit <= 4 else "DIGITUNDER"
        return "DIGITUNDER" if digit <= 4 else "DIGITOVER"

    def _next_both_direction(self) -> Optional[str]:
        """Generate a fresh 0-9 decision digit for BOTH mode."""
        digit = self._both_rng.randint(0, 9)
        self.both_generator_digit = digit
        return self._both_direction_for_digit(digit)

    def _apply_martingale_after_loss(self):
        """Apply Martingale only when its multiplier is explicitly enabled.

        A Martingale value of 0 means disabled. It must never produce a
        zero-dollar stake or alter the next stake.
        """
        if not self.config.martingale_enabled or self.config.martingale <= 0:
            self.stake = self.config.base_stake
            self.add_log(
                "info",
                f"MARTINGALE DISABLED | no multiplier applied after loss; "
                f"next recovery stake remains at base ${self.stake:.2f}."
            )
            return

        self.stake = min(
            self.stake * self.config.martingale,
            self.config.max_stake
        )
        self.add_log(
            "info",
            f"MARTINGALE APPLIED | multiplier=x{self.config.martingale:.2f} | "
            f"next stake=${self.stake:.2f}."
        )

    async def start(self):
        if self.is_running:
            return
        self.add_log("info", "Authorizing bot with Deriv API Token...")
        try:
            # authorize() obtains a current Deriv OTP URL and establishes the authenticated socket.
            await self.client.authorize(self.config.api_token)
            try:
                await self.client.subscribe_balance(self._on_balance)
            except Exception as sub_err:
                logger.warning(f"Balance subscription notice: {sub_err}")

            try:
                initial_balance = await self.client.get_balance()
                await self._on_balance(initial_balance)
            except Exception as balance_error:
                self.add_log("warn", f"Initial account balance unavailable: {balance_error}")
        except Exception as e:
            err_str = str(e)
            if "already subscribed to balance" in err_str.lower():
                self.add_log("info", "Connected and authorized on Deriv account.")
            else:
                self.add_log("error", f"Authorization failed: {err_str}")
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
        self.recovery_loss_stake = 0.0
        self.in_recovery_cycle = False
        self.recovery_phase = 0
        self.recovery_prediction_active = False
        self.recovery_cooldown_until = 0.0
        self._recovery_cooldown_logged = False
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
        # Do not reset BOTH direction from bot start time. Direction is derived
        # from the wall-clock six-hour window in _both_direction_for_digit().
        self.both_direction_window = int(time.time() // (6 * 60 * 60))
        self.both_direction_anchor_digit = None
        self.both_generator_digit = None
        self.stop_reason = None

        self.add_log(
            "success",
            f"Bot started | Build={ENGINE_BUILD} | Market={self.config.symbol} | "
            f"Mode={self.config.contract_type_mode} | Base stake=${self.stake:.2f} | "
            f"Under trigger={self.config.under_trigger_digit} | Over trigger={self.config.over_trigger_digit} | "
            f"Win prediction={self.config.win_predict_digit} | Loss prediction={self.config.loss_predict_digit} | "
            f"Recovery prediction={self.config.recovery_win_predict_digit} | "
            f"Recovery target={self.config.recovery_wins_required} wins "
            f"({'enabled' if self.config.recovery_wins_required > 0 else 'disabled'}) | "
            f"Loss cycle target={self.config.loss_cycle_target} "
            f"({'enabled' if self.config.loss_cycle_target > 0 else 'disabled'}) | "
            f"Martingale={'enabled' if self.config.martingale_enabled and self.config.martingale > 0 else 'disabled'} | "
            f"BOTH inverse={'enabled' if self.config.both_inverse_enabled else 'disabled'} | "
            f"inverse interval={self.config.both_inverse_interval_hours}h"
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
        if (reason.startswith(("Take Profit limit reached", "Stop Loss limit reached")) and self.config.auto_restart_after_stop and (self._auto_restart_task is None or self._auto_restart_task.done())):
            self.add_log("info", "AUTO-RESTART ARMED | Take Profit reached. Bot will restart in 60 seconds.")
            self._auto_restart_task = asyncio.create_task(self._restart_after_take_profit())
        if self.status_broadcast_callback:
            try:
                await self.status_broadcast_callback("status", self.get_status().dict())
            except Exception:
                pass

    async def _restart_after_take_profit(self):
        """Restart once, 60 seconds after a Take Profit stop when enabled."""
        try:
            await asyncio.sleep(60)
            if self.is_running or not self.config.auto_restart_after_take_profit:
                return
            self.add_log("info", "AUTO-RESTART | 60-second Take Profit cooldown complete. Restarting bot.")
            await self.start()
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self.add_log("error", f"AUTO-RESTART FAILED | {exc}")

    async def _refresh_balance_after_settlement(self):
        """Compatibility hook for settlement callers.

        Balance is delivered by the authenticated WebSocket subscription. Do
        not issue a balance request from a contract callback or after every
        settlement; the balance endpoint has a separate, much smaller quota.
        """
        return

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

        current_quote = float(quote)
        previous_quote = self.last_tick_quote
        self.previous_tick_quote = previous_quote
        self.last_tick_quote = current_quote
        mode = self.config.contract_type_mode.upper()
        rise_fall_mode = mode in ("CALL", "PUT", "RISEFALL")
        
        # Deriv's current tick schema makes pip_size optional. Never assume
        # two decimals: doing so changes the last digit for markets whose
        # quote precision differs, and it also loses trailing-zero precision
        # when a JSON number is decoded as a binary float.
        raw_pip_size = tick_data.get("pip_size")
        try:
            pip_size = int(raw_pip_size) if raw_pip_size is not None else None
        except (TypeError, ValueError):
            pip_size = None

        self.last_tick_pip_size = max(0, pip_size) if pip_size is not None else None
        self.last_digit = self._extract_last_digit_from_quote(quote, pip_size)

        if self.last_digit is None and not rise_fall_mode:
            self.add_log(
                "warn",
                f"Unable to determine last digit from tick quote={quote!r} "
                f"pip_size={raw_pip_size!r}; tick ignored for digit entry decisions."
            )
            return

        # Broadcast live tick to frontend
        if self.status_broadcast_callback:
            try:
                asyncio.create_task(self.status_broadcast_callback("tick", {
                    "quote": self.last_tick_quote,
                    "last_digit": self.last_digit,
                    "symbol": self.config.symbol,
                    "pip_size": pip_size,
                    "epoch": tick_data.get("epoch")
                }))
            except Exception:
                pass

        if self.is_trade_in_progress:
            return

        # Recovery state is authoritative. Do not use stake > base_stake
        # as the recovery test: max_stake can clamp recovery to base_stake.
        if self.in_recovery_cycle:
            # Recovery must not fire immediately after a loss. The cooldown is
            # measured from settlement using a monotonic clock.
            remaining = self.recovery_cooldown_until - time.monotonic()
            if remaining > 0:
                if not self._recovery_cooldown_logged:
                    self._recovery_cooldown_logged = True
                    self.add_log(
                        "info",
                        f"RECOVERY COOLDOWN | waiting {remaining:.1f}s after loss before next recovery trade."
                    )
                return

            if self._recovery_cooldown_logged:
                self._recovery_cooldown_logged = False
                self.add_log("info", "RECOVERY COOLDOWN COMPLETE | recovery trading re-armed.")

            if mode == "BOTH":
                direction = self._next_both_direction()
                if direction is None:
                    self.add_log(
                        "info",
                        f"BOTH RECOVERY SIGNAL SKIPPED | generator_digit={self.both_generator_digit} | "
                        "result=BREAK_EVEN | no contract placed."
                    )
                    return
                barrier = (
                    self.config.both_under_barrier
                    if direction == "DIGITUNDER"
                    else self.config.both_over_barrier
                )
                self.add_log(
                    "info",
                    f"BOTH RECOVERY SIGNAL | generator_digit={self.both_generator_digit} | "
                    f"type={direction} | barrier={barrier} | recovery_phase={self.recovery_phase} | "
                    f"six_hour_window={self.both_direction_window + 1} | "
                    f"inverted={'YES' if self.both_direction_window % 2 else 'NO'} | "
                    f"stake=${self.stake:.2f}"
                )
                self._schedule_trade(direction)
                return

            if not self.active_contract_type:
                self.add_log("error", "RECOVERY BLOCKED | no active contract type is available.")
                return

            self.predict = (self.config.loss_predict_digit if self.recovery_phase == 1 else self.config.recovery_win_predict_digit)
            self._schedule_trade(self.active_contract_type)
            return

        # Normal/base-stake entry supports both digit contracts and Rise/Fall.
        if self.in_recovery_cycle:
            return

        if mode in ("CALL", "PUT", "RISEFALL"):
            if abs(self.stake - self.config.base_stake) >= 0.001:
                return
            direction = mode
            if mode == "RISEFALL":
                if previous_quote is None or current_quote == previous_quote:
                    return
                direction = "CALL" if current_quote > previous_quote else "PUT"
            direction_label = "RISE" if direction == "CALL" else "FALL"
            self.add_log(
                "info",
                f"ENTRY TRIGGER HIT | type={direction} | direction={direction_label} | "
                f"previous_quote={previous_quote if previous_quote is not None else 'n/a'} | "
                f"current_quote={current_quote} | stake=${self.stake:.2f}"
            )
            self._schedule_trade(direction)
            return

        if mode == "BOTH":
            if abs(self.stake - self.config.base_stake) >= 0.001:
                return

            direction = self._next_both_direction()
            window = self.both_direction_window
            if direction is None:
                if self.both_generator_digit == 5:
                    self.add_log(
                        "info",
                        "BOTH SIGNAL SKIPPED | generator_digit=5 | result=BREAK_EVEN | no contract placed."
                    )
                return

            inverted = bool(self.config.both_inverse_enabled) and (window % 2) == 1
            mapping = (
                "0-4=UNDER, 6-9=OVER" if inverted
                else "0-4=OVER, 6-9=UNDER"
            )
            self.add_log(
                "info",
                f"BOTH SIGNAL | generator_digit={self.both_generator_digit} | type={direction} | "
                f"barrier={(self.config.both_under_barrier if direction == "DIGITUNDER" else self.config.both_over_barrier)} | inverse_window={window + 1} | "
                f"mapping={mapping} | inverted={'YES' if inverted else 'NO'} | "
                f"stake=${self.stake:.2f}"
            )
            self._schedule_trade(direction)
            return

        if mode == "DIGITUNDER" and self.last_digit == self.config.under_trigger_digit and abs(self.stake - self.config.base_stake) < 0.001:
            self.add_log(
                "info",
                f"ENTRY TRIGGER HIT | type=DIGITUNDER | trigger_digit={self.last_digit} | "
                f"barrier={self.config.win_predict_digit} | stake=${self.stake:.2f}"
            )
            self._schedule_trade("DIGITUNDER")
        elif mode == "DIGITOVER" and self.last_digit == self.config.over_trigger_digit and abs(self.stake - self.config.base_stake) < 0.001:
            self.add_log(
                "info",
                f"ENTRY TRIGGER HIT | type=DIGITOVER | trigger_digit={self.last_digit} | "
                f"barrier={self.config.win_predict_digit} | stake=${self.stake:.2f}"
            )
            self._schedule_trade("DIGITOVER")

    def _schedule_trade(self, contract_type: str):
        if self.is_trade_in_progress or not self.is_running:
            return
        # Reserve the slot before create_task so two ticks cannot queue trades
        # against the same mutable recovery state.
        self.is_trade_in_progress = True
        asyncio.create_task(self._place_trade(contract_type))

    def _barrier_for_contract(self, contract_type: str) -> Optional[int]:
        """Return the barrier belonging to the actual contract type."""
        contract_type = contract_type.upper()
        if contract_type == "DIGITUNDER":
            return int(self.config.both_under_barrier) if self.config.contract_type_mode.upper() == "BOTH" else int(self.config.win_predict_digit)
        if contract_type == "DIGITOVER":
            return int(self.config.both_over_barrier) if self.config.contract_type_mode.upper() == "BOTH" else int(self.config.win_predict_digit)
        if contract_type in ("CALL", "PUT"):
            return None
        return int(self.config.win_predict_digit)

    async def _place_trade(self, contract_type: str):
        if not self.is_running:
            self.is_trade_in_progress = False
            return

        # Capture immutable trade context before any await. Settlement uses
        # this exact context rather than whatever state the next step has.
        # BOTH must choose its contract independently for every trade.
        # Never let the previous recovery contract override a new BOTH signal.
        if self.config.contract_type_mode.upper() == "BOTH":
            if contract_type.upper() not in ("DIGITUNDER", "DIGITOVER"):
                self.is_trade_in_progress = False
                self.add_log(
                    "error",
                    f"INVALID BOTH CONTRACT | requested={contract_type}. "
                    "Only DIGITUNDER or DIGITOVER is permitted."
                )
                return
            self.active_contract_type = None
        elif self.in_recovery_cycle and self.active_contract_type:
            contract_type = self.active_contract_type
        elif not self.in_recovery_cycle:
            self.active_contract_type = contract_type

        trade_contract_type = contract_type.upper()
        if self.in_recovery_cycle:
            if self.config.contract_type_mode.upper() == "BOTH" and trade_contract_type in ("DIGITUNDER", "DIGITOVER"):
                trade_prediction = self.config.both_under_barrier if trade_contract_type == "DIGITUNDER" else self.config.both_over_barrier
            else:
                trade_prediction = None if trade_contract_type in ("CALL", "PUT") else (self.config.loss_predict_digit if self.recovery_phase == 1 else self.config.recovery_win_predict_digit)
            if trade_prediction is not None:
                self.predict = trade_prediction
        else:
            if (
                self.config.contract_type_mode.upper() == "BOTH"
                and trade_contract_type in ("DIGITUNDER", "DIGITOVER")
            ):
                trade_prediction = self._barrier_for_contract(trade_contract_type)
            else:
                trade_prediction = self._barrier_for_contract(trade_contract_type)
            if trade_prediction is not None:
                self.predict = trade_prediction
        trade_stake = float(self.stake)
        if trade_stake <= 0:
            self.is_trade_in_progress = False
            self.add_log(
                "error",
                f"INVALID STAKE BLOCKED | calculated stake=${trade_stake:.2f}. "
                f"Martingale=DISABLED when multiplier is 0; recovery must never submit a zero stake."
            )
            if self.in_recovery_cycle:
                await self.stop("Zero or negative recovery stake blocked")
            return

        recovery_target_profit: Optional[float] = None
        if (
            self.in_recovery_cycle
            and self.config.loss_cycle_target > 0
            and self.recovery_loss_stake > 0
        ):
            remaining_recovery_wins = max(1, self.config.loss_cycle_target - self.recovery_win_count)
            recovery_target_profit = self.recovery_loss_stake / remaining_recovery_wins
            self.add_log(
                "info",
                f"LOSS-CYCLE TARGET | outstanding=${self.recovery_loss_stake:.2f} | "
                f"recovered_wins={self.recovery_win_count} | "
                f"remaining_target_wins={remaining_recovery_wins} | "
                f"target_profit=${recovery_target_profit:.2f}"
            )

        # CALL/PUT (Rise/Fall) do not use a digit barrier.
        if trade_contract_type not in ("CALL", "PUT"):
            try:
                trade_prediction = validate_digit_barrier(trade_contract_type, int(trade_prediction))
            except (ValueError, TypeError) as validation_error:
                self.add_log(
                    "error",
                    f"INVALID DIGIT BARRIER | type={trade_contract_type} | barrier={trade_prediction} | "
                    f"{validation_error}. Trade skipped before Deriv proposal."
                )
                self.is_trade_in_progress = False
                if self.in_recovery_cycle:
                    await self.stop("Invalid recovery digit barrier for locked contract")
                else:
                    self.active_contract_type = None
                return

        self.add_log(
            "info",
            f"EXECUTION REQUEST | type={trade_contract_type} | barrier={trade_prediction} | "
            f"stake=${trade_stake:.2f} | recovery={self.in_recovery_cycle} | phase={self.recovery_phase} | "
            f"recovery_wins={self.recovery_win_count}/{max(1, self.config.recovery_wins_required)} | "
            f"locked_contract={self.active_contract_type or 'NONE (BOTH rotates)'}"
        )

        try:
            buy_res = await self.client.buy_contract(
                symbol=self.config.symbol,
                contract_type=trade_contract_type,
                amount=trade_stake,
                duration=self.time_duration,
                duration_unit=self.config.duration_unit,
                barrier=trade_prediction,
                currency=self.config.currency,
                target_profit=recovery_target_profit,
                max_amount=self.config.max_stake if recovery_target_profit is not None else None
            )

            # The client may resize a loss-cycle recovery trade from the live proposal payout.
            # Settlement must use the actual purchased stake.
            trade_stake = float(buy_res.get("stake", trade_stake))
            if recovery_target_profit is not None:
                self.stake = trade_stake

            contract_id = buy_res.get("contract_id")
            if not contract_id:
                self.add_log("error", "Received invalid contract_id from Deriv.")
                self.is_trade_in_progress = False
                return

            contract_id = int(contract_id)
            self.active_trade_contract_id = contract_id
            actual_buy_price = float(buy_res.get("buy_price", trade_stake))
            self.add_log(
                "info",
                f"Contract #{contract_id} placed. Type={trade_contract_type} | "
                f"Prediction={trade_prediction} | BuyPrice=${actual_buy_price:.2f} | "
                f"Stake=${trade_stake:.2f} | Waiting for outcome..."
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
            message = str(e)
            self.add_log("error", f"Error placing trade: {message}")
            self.is_trade_in_progress = False

            if message.startswith("Insufficient Deriv balance:"):
                await self.stop("Insufficient account balance for configured stake")

    @staticmethod
    def _extract_last_digit_from_quote(quote: Any, pip_size: Optional[int] = None) -> Optional[int]:
        """Extract the displayed final quote digit without losing decimal scale."""
        if quote is None:
            return None

        try:
            if isinstance(quote, Decimal):
                value = quote
            elif isinstance(quote, str):
                text = quote.strip()
                if not text:
                    return None
                value = Decimal(text)
            else:
                value = Decimal(str(quote))

            if pip_size is not None:
                formatted = format(value, f".{max(0, int(pip_size))}f")
            else:
                # Decimal preserves the scale parsed from the JSON token,
                # including trailing zeroes such as 100.10.
                formatted = format(value, "f")

            digits = [char for char in formatted if char.isdigit()]
            return int(digits[-1]) if digits else None
        except (TypeError, ValueError, ArithmeticError):
            return None

    @staticmethod
    def _extract_last_digit_from_spot(spot: Any, pip_size: Optional[int] = None) -> Optional[int]:
        """Extract the actual settlement digit without losing trailing zeros."""
        if spot is None:
            return None

        try:
            if isinstance(spot, Decimal):
                value = spot
            elif isinstance(spot, str):
                text = spot.strip()
                if not text:
                    return None
                value = Decimal(text)
            else:
                value = Decimal(str(spot))

            if pip_size is not None:
                formatted = format(value, f".{max(0, int(pip_size))}f")
            else:
                formatted = format(value, "f")

            digits = [char for char in formatted if char.isdigit()]
            return int(digits[-1]) if digits else None
        except (TypeError, ValueError, ArithmeticError):
            return None

    async def _handle_contract_finished(
        self,
        poc: Dict[str, Any],
        trade_contract_type: str,
        trade_prediction: Optional[int],
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

        profit_raw = poc.get("profit", 0.0)
        profit = float(profit_raw or 0.0)
        status = str(poc.get("status") or "").lower()  # "won" or "lost"

        entry_spot = poc.get("entry_spot")
        exit_spot = poc.get("exit_spot")
        exit_digit = self._extract_last_digit_from_spot(
            exit_spot,
            self.last_tick_pip_size
        )

        buy_price_raw = poc.get("buy_price")
        try:
            settlement_buy_price = float(buy_price_raw)
        except (TypeError, ValueError):
            settlement_buy_price = float(trade_stake)

        is_win = (profit > 0 or status == "won")

        # Deriv is authoritative for the financial result. Independently
        # derive the final digit from the actual exit spot so every digit
        # contract can be audited instead of relying only on profit/status.
        expected_win: Optional[bool] = None
        contract_upper = str(trade_contract_type).upper()
        if exit_digit is not None:
            if contract_upper == "DIGITOVER" and trade_prediction is not None:
                expected_win = exit_digit > int(trade_prediction)
            elif contract_upper == "DIGITUNDER" and trade_prediction is not None:
                expected_win = exit_digit < int(trade_prediction)
            elif contract_upper in ("CALL", "PUT") and entry_spot is not None and exit_spot is not None:
                try:
                    entry_value = Decimal(str(entry_spot))
                    exit_value = Decimal(str(exit_spot))
                    expected_win = exit_value > entry_value if contract_upper == "CALL" else exit_value < entry_value
                except (TypeError, ValueError, ArithmeticError):
                    expected_win = None

        settlement_parts = [
            f"CONTRACT SETTLED | id={contract_id}",
            f"type={trade_contract_type}",
            f"barrier={trade_prediction}",
            f"entry_spot={entry_spot if entry_spot is not None else 'n/a'}",
            f"exit_spot={exit_spot if exit_spot is not None else 'n/a'}",
            f"exit_digit={exit_digit if exit_digit is not None else 'n/a'}",
            f"status={status or 'n/a'}",
            f"buy_price=${settlement_buy_price:.2f}",
            f"stake=${trade_stake:.2f}",
            f"P/L=${profit:+.2f}"
        ]
        self.add_log("info", " | ".join(settlement_parts))

        if expected_win is None:
            self.add_log(
                "warn",
                f"SETTLEMENT AUDIT | id={contract_id} | Unable to derive exit digit "
                f"from exit_spot={exit_spot!r}."
            )
        elif expected_win != is_win:
            self.add_log(
                "error",
                f"SETTLEMENT MISMATCH | id={contract_id} | type={trade_contract_type} | "
                f"barrier={trade_prediction} | exit_digit={exit_digit} | "
                f"DerivStatus={status or 'n/a'} | DerivWin={is_win} | "
                f"DigitRuleWin={expected_win}"
            )
        else:
            self.add_log(
                "info",
                f"SETTLEMENT VERIFIED | id={contract_id} | type={trade_contract_type} | "
                f"barrier={trade_prediction} | exit_digit={exit_digit} | "
                f"result={'WIN' if is_win else 'LOSS'}"
            )

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
            self.recovery_cooldown_until = 0.0
            self._recovery_cooldown_logged = False

            # Recovery cycle has two modes. loss_cycle_target > 0 tracks the
            # outstanding loss stake financially; zero preserves the existing
            # recovery-win-count behavior.
            if self.in_recovery_cycle:
                if self.config.loss_cycle_target > 0:
                    self.recovery_win_count += 1
                    recovered_profit = max(0.0, profit)
                    self.recovery_loss_stake = max(0.0, self.recovery_loss_stake - recovered_profit)
                    if self.recovery_loss_stake <= 0.005:
                        self.recovery_loss_stake = 0.0
                        self.stake = self.config.base_stake
                        self.recovery_win_count = 0
                        self.in_recovery_cycle = False
                        self.recovery_phase = 0
                        self.recovery_prediction_active = False
                        self.active_contract_type = None
                        self.predict = self.config.win_predict_digit
                        self.add_log(
                            "info",
                            f"LOSS-CYCLE RECOVERED | recovery_profit=${recovered_profit:.2f} | "
                            f"remaining_loss=${self.recovery_loss_stake:.2f}. "
                            f"Resetting stake to base ${self.stake:.2f}."
                        )
                    else:
                        self.recovery_phase = 2
                        self.recovery_prediction_active = True
                        self.predict = self.config.recovery_win_predict_digit
                        remaining_wins = max(1, self.config.loss_cycle_target - self.recovery_win_count)
                        next_target = self.recovery_loss_stake / remaining_wins
                        self.add_log(
                            "info",
                            f"LOSS-CYCLE RECOVERY WIN | recovered=${recovered_profit:.2f} | "
                            f"outstanding=${self.recovery_loss_stake:.2f} | "
                            f"recovery_wins={self.recovery_win_count} | "
                            f"next_target_profit=${next_target:.2f}.",
                        )
                else:
                    self.recovery_win_count += 1
                    target = self.config.recovery_wins_required
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
                self.recovery_loss_stake = 0.0
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

            # Recovery is entirely opt-in:
            #   recovery_wins_required=0 -> win-count recovery disabled
            #   loss_cycle_target=0       -> financial loss-cycle disabled
            # If both are zero, a loss ends recovery immediately and the next
            # normal trade always uses the configured base stake.
            if self.config.loss_cycle_target > 0:
                self.recovery_loss_stake += max(0.0, trade_stake)
                if not self.in_recovery_cycle:
                    self.recovery_win_count = 0

                self._apply_martingale_after_loss()
                self.in_recovery_cycle = True
                self.recovery_phase = 1
                self.active_contract_type = None if self.config.contract_type_mode.upper() == "BOTH" else trade_contract_type
                self.recovery_prediction_active = False
                self.predict = self.config.loss_predict_digit
                self.time_duration = self.config.duration

                remaining_wins = max(1, self.config.loss_cycle_target - self.recovery_win_count)
                target_profit = self.recovery_loss_stake / remaining_wins
                self.add_log(
                    "info",
                    f"LOSS-CYCLE UPDATED | loss_stake_added=${trade_stake:.2f} | "
                    f"outstanding=${self.recovery_loss_stake:.2f} | "
                    f"recovery_wins={self.recovery_win_count} | "
                    f"target_wins={self.config.loss_cycle_target} | "
                    f"next_target_profit=${target_profit:.2f} | "
                    f"contract={self.active_contract_type}.",
                )
            elif self.config.recovery_wins_required > 0:
                if self.loss_streak >= self.config.max_loss_streak:
                    self.stake = self.config.base_stake
                    self.recovery_win_count = 0
                    self.recovery_loss_stake = 0.0
                    self.in_recovery_cycle = False
                    self.recovery_phase = 0
                    self.recovery_prediction_active = False
                    self.active_contract_type = None
                    self.predict = self.config.win_predict_digit
                    self.time_duration = self.config.duration
                    self.loss_streak = 0
                    self.add_log("warn", f"Max loss streak threshold ({self.config.max_loss_streak}) hit! Resetting stake to base: ${self.stake:.2f}")
                else:
                    self._apply_martingale_after_loss()
                    self.recovery_win_count = 0
                    self.recovery_loss_stake = 0.0
                    self.in_recovery_cycle = True
                    self.recovery_phase = 1
                    self.active_contract_type = trade_contract_type
                    self.recovery_prediction_active = False
                    self.predict = self.config.loss_predict_digit
                    self.time_duration = self.config.duration
                    self.add_log(
                        "info",
                        f"Recovery contract LOCKED to {self.active_contract_type}; "
                        f"next recovery prediction={self.predict}; recovery wins reset to 0.",
                    )
            else:
                self.stake = self.config.base_stake
                self.recovery_win_count = 0
                self.recovery_loss_stake = 0.0
                self.in_recovery_cycle = False
                self.recovery_phase = 0
                self.recovery_prediction_active = False
                self.active_contract_type = None
                self.predict = self.config.win_predict_digit
                self.time_duration = self.config.duration
                self.add_log(
                    "info",
                    f"RECOVERY DISABLED | recovery_wins_required=0 and loss_cycle_target=0; "
                    f"next stake reset to base ${self.stake:.2f}. No recovery trade will be scheduled."
                )
        # Start a fresh five-second cooldown after every loss that leaves the
        # bot in recovery. This applies to the initial loss and to additional
        # losses occurring during recovery.
        if not is_win and self.in_recovery_cycle:
            self.recovery_cooldown_until = time.monotonic() + 5.0
            self._recovery_cooldown_logged = False
            self.add_log("info", "RECOVERY COOLDOWN STARTED | 5.0s after loss before next recovery trade.")

        # Check stopping criteria
        if self.config.take_profit > 0 and self.total_profit >= self.config.take_profit:
            await self.stop(f"Take Profit limit reached (+${self.total_profit:.2f} >= ${self.config.take_profit:.2f})")
        elif self.config.stop_loss > 0 and self.total_profit <= -self.config.stop_loss:
            await self.stop(f"Stop Loss limit reached (${self.total_profit:.2f} <= -${self.config.stop_loss:.2f})")
        elif self.runs >= self.config.max_runs:
            await self.stop(f"Max runs limit reached ({self.runs} >= {self.config.max_runs})")

        self.is_trade_in_progress = False
        if self.active_trade_contract_id == contract_id:
            self.active_trade_contract_id = None

        # Do not await get_balance() here. This method is called from a
        # contract callback that DerivClient._listen_loop awaits; awaiting a
        # second websocket request here would deadlock the receiver.
        asyncio.create_task(self._refresh_balance_after_settlement())

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
