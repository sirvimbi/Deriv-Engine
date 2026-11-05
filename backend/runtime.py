"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v13-adaptive-performance-protection"
ENGINE_DESCRIPTION = "Adds session rolling win-rate adaptive Take Profit and optional tighter Stop Loss protection for Digit-BOTH"
