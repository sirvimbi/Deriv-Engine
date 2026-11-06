"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v16-deriv-rest-temporary-retry"
ENGINE_DESCRIPTION = "Adds bounded retry and recovery for temporary Deriv REST authorization outages"
