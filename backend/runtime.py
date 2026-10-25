"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v8-break-even-continuation"
ENGINE_DESCRIPTION = "Execution-time BOTH direction audit; neutral digit-5 retry without trade-loop stall; capped loss-cycle recovery with configured win-target enforcement"
