"""Runtime identity for the backend/frontend compatibility guard.

Bump ENGINE_BUILD whenever trading/execution semantics change. The macOS
client uses this value to refuse starting against an older backend process.
"""
ENGINE_BUILD = "recovery-state-v12-configurable-auto-restart-delay"
ENGINE_DESCRIPTION = "Adds configurable TP/SL auto-restart delay in hours and minutes to session log retention and capped recovery support"
