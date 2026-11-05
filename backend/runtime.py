"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v14-configurable-adaptive-rate-bounds"
ENGINE_DESCRIPTION = "Adds configurable TP and adaptive SL win-rate thresholds, independent calculation windows, and sample controls"
