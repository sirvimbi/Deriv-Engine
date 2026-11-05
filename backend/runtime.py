"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v11-session-trades-recovery-cap"
ENGINE_DESCRIPTION = "Retains all session trade logs, supports a $1,000 hard stop loss, and continues capped recovery trades until outstanding losses clear"
