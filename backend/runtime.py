"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v6-both-mode-stake-cap"
ENGINE_DESCRIPTION = "Serialized authentication and rate-limit-safe balance subscriptions; generator-driven BOTH recovery; loss-cycle stake caps without martingale compounding"
