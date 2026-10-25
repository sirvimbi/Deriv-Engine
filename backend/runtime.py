"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v10-unknown-proposal-retry"
ENGINE_DESCRIPTION = "Retries stale/unknown Deriv proposals with fresh quotes; resumes after rejected unpurchased entries; digit-5 retry and contract-status recovery"
