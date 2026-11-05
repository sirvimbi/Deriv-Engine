#!/bin/bash
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Starting Deriv Engine..."

# Check if backend server is already running
if ! curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting Python Backend Server..."
    cd "$ROOT_DIR/backend"
    nohup ./run.sh > server.log 2>&1 &
    sleep 2
fi

echo "Launching Deriv Engine macOS App..."
open "$(dirname "$0")/Deriv Engine.app"
