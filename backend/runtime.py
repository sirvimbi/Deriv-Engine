"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v6-both-mode-stake-cap"
ENGINE_DESCRIPTION = "BOTH recovery direction stays generator-driven; loss-cycle stake sizing respects max stake and avoids martingale compounding"
