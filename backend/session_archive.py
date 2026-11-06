"""Durable archive for completed and in-progress bot sessions."""
import csv
import json
import os
import sys
import threading
import time
import uuid
from copy import deepcopy
from io import StringIO
from pathlib import Path
from typing import Any, Dict, List, Optional

SESSION_SETUP_FIELDS = (
    "symbol", "account_type", "currency", "contract_type_mode",
    "base_stake", "max_stake", "martingale_enabled", "martingale",
    "take_profit", "stop_loss",
    "under_trigger_digit", "over_trigger_digit", "win_predict_digit",
    "both_under_barrier", "both_over_barrier", "both_inverse_enabled",
    "both_inverse_interval_hours", "loss_predict_digit",
    "recovery_over_barrier", "recovery_under_barrier",
    "recovery_wins_required", "loss_cycle_target", "max_loss_streak",
    "duration", "duration_unit",
    "adaptive_performance_enabled", "adaptive_target_win_rate",
    "adaptive_stop_win_rate", "adaptive_minimum_sample_size",
    "adaptive_rolling_window", "adaptive_stop_loss_enabled",
    "adaptive_stop_loss_min_win_rate", "adaptive_stop_loss_max_win_rate",
    "adaptive_stop_loss_rolling_window",
)

CSV_BASE_FIELDS = (
    "session_id", "session_status", "started_at", "finished_at",
    "duration_seconds", "stop_reason", "session_trade_count",
    "session_wins", "session_losses", "session_break_even",
    "session_total_profit", "session_total_stake", "session_max_trade_stake",
    "trade_contract_id", "trade_placed_at", "trade_settled_at",
    "trade_contract_type", "trade_entry_signal_digit", "trade_generator_digit",
    "trade_barrier", "trade_stake", "trade_buy_price", "trade_payout",
    "trade_profit", "trade_outcome", "trade_deriv_status",
    "trade_entry_spot", "trade_exit_spot", "trade_exit_digit",
    "trade_active_take_profit", "trade_active_stop_loss",
    "trade_rolling_win_rate", "trade_sl_rolling_win_rate",
)


class SessionArchive:
    """Thread-safe JSON-backed store. It never deletes data automatically."""

    def __init__(self, storage_path: Optional[str] = None):
        configured_path = storage_path or os.environ.get("DERIV_SESSION_HISTORY_FILE")
        if configured_path:
            self.path = Path(configured_path).expanduser()
        elif sys.platform == "darwin":
            self.path = (
                Path.home()
                / "Library"
                / "Application Support"
                / "Deriv Engine"
                / "session_history.json"
            )
        else:
            self.path = (
                Path.home()
                / ".local"
                / "share"
                / "deriv-engine"
                / "session_history.json"
            )
        self._lock = threading.RLock()
        self._sessions: List[Dict[str, Any]] = self._load()
        self._recover_interrupted_sessions()

    @staticmethod
    def _config_data(config: Any) -> Dict[str, Any]:
        if isinstance(config, dict):
            return dict(config)
        if hasattr(config, "model_dump"):
            return config.model_dump()
        if hasattr(config, "dict"):
            return config.dict()
        raise TypeError("Session configuration must be a mapping or model.")

    def _load(self) -> List[Dict[str, Any]]:
        if not self.path.exists():
            return []
        try:
            with self.path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
            if not isinstance(payload, list):
                raise ValueError("Session archive root must be a JSON array.")
            return payload
        except Exception as exc:
            damaged = self.path.with_name(
                self.path.name + ".corrupt-" + str(int(time.time()))
            )
            try:
                self.path.replace(damaged)
            except OSError:
                pass
            raise RuntimeError(
                f"Unable to read session archive ({exc}); original file was preserved where possible."
            ) from exc

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self.path.with_name(self.path.name + ".tmp")
        with temporary_path.open("w", encoding="utf-8") as handle:
            json.dump(self._sessions, handle, indent=2, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, self.path)

    def _recover_interrupted_sessions(self) -> None:
        now = int(time.time())
        changed = False
        for session in self._sessions:
            if session.get("status") == "running":
                session["status"] = "interrupted"
                session["finished_at"] = now
                session["duration_seconds"] = max(
                    0, now - int(session.get("started_at") or now)
                )
                session["stop_reason"] = (
                    "Backend restarted before the session was stopped"
                )
                changed = True
        if changed:
            with self._lock:
                self._save()

    def start_session(self, config: Any, started_at: Optional[int] = None) -> str:
        raw_config = self._config_data(config)
        setup = {key: raw_config.get(key) for key in SESSION_SETUP_FIELDS}
        start_epoch = int(started_at or time.time())
        session = {
            "id": str(uuid.uuid4()),
            "started_at": start_epoch,
            "finished_at": None,
            "duration_seconds": None,
            "status": "running",
            "stop_reason": None,
            "setup": setup,
            "summary": {
                "trade_count": 0,
                "wins": 0,
                "losses": 0,
                "break_even": 0,
                "total_profit": 0.0,
                "total_stake": 0.0,
                "max_trade_stake": 0.0,
            },
            "trades": [],
        }
        with self._lock:
            self._sessions.append(session)
            self._save()
        return session["id"]

    def record_trade_open(self, session_id: Optional[str], trade: Dict[str, Any]) -> bool:
        """Persist the purchased contract immediately, before settlement arrives."""
        if not session_id:
            return False
        with self._lock:
            session = next(
                (item for item in self._sessions if item.get("id") == session_id),
                None,
            )
            if session is None or session.get("status") != "running":
                return False
            contract_id = trade.get("contract_id")
            if contract_id is not None and any(
                item.get("contract_id") == contract_id
                for item in session.get("trades", [])
            ):
                return False

            saved_trade = dict(trade)
            saved_trade["outcome"] = "OPEN"
            saved_trade["profit"] = 0.0
            session.setdefault("trades", []).append(saved_trade)
            summary = session.setdefault("summary", {})
            stake = float(saved_trade.get("stake") or 0.0)
            summary["trade_count"] = int(summary.get("trade_count", 0)) + 1
            summary["total_stake"] = round(
                float(summary.get("total_stake", 0.0)) + stake, 8
            )
            summary["max_trade_stake"] = max(
                float(summary.get("max_trade_stake", 0.0)), stake
            )
            self._save()
            return True

    def record_trade(self, session_id: Optional[str], trade: Dict[str, Any]) -> bool:
        """Attach the settlement to its opening row, or add a settled row directly."""
        if not session_id:
            return False
        with self._lock:
            session = next(
                (item for item in self._sessions if item.get("id") == session_id),
                None,
            )
            # A contract may settle after the user stops the bot. The record
            # must remain writable until its result is received. A deleted
            # session (manual archive clear) cannot be recreated here.
            if session is None:
                return False

            saved_trades = session.setdefault("trades", [])
            contract_id = trade.get("contract_id")
            existing = next(
                (
                    item for item in saved_trades
                    if contract_id is not None and item.get("contract_id") == contract_id
                ),
                None,
            )
            if existing is not None and str(existing.get("outcome") or "").upper() != "OPEN":
                return False

            saved_trade = dict(trade)
            summary = session.setdefault("summary", {})
            stake = float(saved_trade.get("stake") or 0.0)
            profit = float(saved_trade.get("profit") or 0.0)
            outcome = str(saved_trade.get("outcome") or "").upper()

            if existing is None:
                saved_trades.append(saved_trade)
                summary["trade_count"] = int(summary.get("trade_count", 0)) + 1
                summary["total_stake"] = round(
                    float(summary.get("total_stake", 0.0)) + stake, 8
                )
                summary["max_trade_stake"] = max(
                    float(summary.get("max_trade_stake", 0.0)), stake
                )
            else:
                old_stake = float(existing.get("stake") or 0.0)
                # These fields describe the protection state at entry and must
                # not be replaced by the new rolling rates after this trade settles.
                entry_protection_snapshot = {
                    key: existing[key]
                    for key in (
                        "active_take_profit",
                        "active_stop_loss",
                        "rolling_win_rate",
                        "sl_rolling_win_rate",
                    )
                    if key in existing
                }
                existing.update(saved_trade)
                existing.update(entry_protection_snapshot)
                summary["total_stake"] = round(
                    float(summary.get("total_stake", 0.0)) + stake - old_stake, 8
                )
                summary["max_trade_stake"] = max(
                    float(summary.get("max_trade_stake", 0.0)), stake
                )

            summary["total_profit"] = round(
                float(summary.get("total_profit", 0.0)) + profit, 8
            )
            if outcome == "WIN":
                summary["wins"] = int(summary.get("wins", 0)) + 1
            elif outcome == "LOSS":
                summary["losses"] = int(summary.get("losses", 0)) + 1
            else:
                summary["break_even"] = int(summary.get("break_even", 0)) + 1
            self._save()
            return True


    def finish_session(
        self,
        session_id: Optional[str],
        stop_reason: str,
        finished_at: Optional[int] = None,
    ) -> bool:
        if not session_id:
            return False
        end_epoch = int(finished_at or time.time())
        with self._lock:
            session = next(
                (item for item in self._sessions if item.get("id") == session_id),
                None,
            )
            if session is None or session.get("status") != "running":
                return False
            session["finished_at"] = end_epoch
            session["duration_seconds"] = max(
                0, end_epoch - int(session.get("started_at") or end_epoch)
            )
            session["status"] = "completed"
            session["stop_reason"] = str(stop_reason or "Stopped")
            self._save()
            return True

    def get_sessions(self) -> List[Dict[str, Any]]:
        with self._lock:
            ordered = sorted(
                self._sessions,
                key=lambda item: int(item.get("started_at") or 0),
                reverse=True,
            )
            return deepcopy(ordered)

    def clear(self) -> None:
        with self._lock:
            self._sessions.clear()
            self._save()

    def export_csv(self) -> str:
        sessions = self.get_sessions()
        fieldnames = list(CSV_BASE_FIELDS) + [
            "setup_" + field for field in SESSION_SETUP_FIELDS
        ]
        output = StringIO(newline="")
        writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for session in sessions:
            summary = session.get("summary") or {}
            base = {
                "session_id": session.get("id"),
                "session_status": session.get("status"),
                "started_at": session.get("started_at"),
                "finished_at": session.get("finished_at"),
                "duration_seconds": session.get("duration_seconds"),
                "stop_reason": session.get("stop_reason"),
                "session_trade_count": summary.get("trade_count", 0),
                "session_wins": summary.get("wins", 0),
                "session_losses": summary.get("losses", 0),
                "session_break_even": summary.get("break_even", 0),
                "session_total_profit": summary.get("total_profit", 0.0),
                "session_total_stake": summary.get("total_stake", 0.0),
                "session_max_trade_stake": summary.get("max_trade_stake", 0.0),
            }
            for key, value in (session.get("setup") or {}).items():
                base["setup_" + key] = value
            for trade in session.get("trades") or [None]:
                row = dict(base)
                if trade:
                    row.update({
                        "trade_contract_id": trade.get("contract_id"),
                        "trade_placed_at": trade.get("placed_at"),
                        "trade_settled_at": trade.get("settled_at"),
                        "trade_contract_type": trade.get("contract_type"),
                        "trade_entry_signal_digit": trade.get("entry_signal_digit"),
                        "trade_generator_digit": trade.get("generator_digit"),
                        "trade_barrier": trade.get("barrier"),
                        "trade_stake": trade.get("stake"),
                        "trade_buy_price": trade.get("buy_price"),
                        "trade_payout": trade.get("payout"),
                        "trade_profit": trade.get("profit"),
                        "trade_outcome": trade.get("outcome"),
                        "trade_deriv_status": trade.get("deriv_status"),
                        "trade_entry_spot": trade.get("entry_spot"),
                        "trade_exit_spot": trade.get("exit_spot"),
                        "trade_exit_digit": trade.get("exit_digit"),
                        "trade_active_take_profit": trade.get("active_take_profit"),
                        "trade_active_stop_loss": trade.get("active_stop_loss"),
                        "trade_rolling_win_rate": trade.get("rolling_win_rate"),
                        "trade_sl_rolling_win_rate": trade.get("sl_rolling_win_rate"),
                    })
                writer.writerow(row)
        return output.getvalue()
