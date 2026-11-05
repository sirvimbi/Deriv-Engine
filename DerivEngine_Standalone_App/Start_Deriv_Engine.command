#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$DIR/.." && pwd )"

echo "Starting Deriv Engine..."

# Free port 8000 if occupied
lsof -ti:8000 | xargs kill -9 2>/dev/null

# Start Python backend in background
cd "$PROJECT_ROOT/backend"
PYTHONPATH="$PROJECT_ROOT/backend" "$PROJECT_ROOT/backend/venv/bin/python3" -m uvicorn main:app --host 0.0.0.0 --port 8000 > "$DIR/backend.log" 2>&1 &

echo "Launching Deriv Engine macOS App..."
open "$DIR/Deriv Engine.app"
