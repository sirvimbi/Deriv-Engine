"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v15-persistent-session-history"
ENGINE_DESCRIPTION = "Adds durable session history with configuration snapshots, settled trade records, CSV export, and manual archive clearing"
