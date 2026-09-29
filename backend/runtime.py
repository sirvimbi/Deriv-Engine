"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v5-disabled-recovery-safety"
ENGINE_DESCRIPTION = "Deterministic recovery state machine with serialized Deriv OTP authentication"
