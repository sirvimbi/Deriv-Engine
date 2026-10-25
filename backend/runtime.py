"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v9-contract-status-recovery"
ENGINE_DESCRIPTION = "Execution-time BOTH direction audit; digit-5 retry; one-shot contract-status reconciliation and safe recovery after stream timeouts; capped loss-cycle recovery"
