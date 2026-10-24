"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v7-both-execution-audit"
ENGINE_DESCRIPTION = "Serialized authentication and rate-limit-safe balance subscriptions; execution-time BOTH direction audit; capped loss-cycle recovery with configured win-target enforcement"
