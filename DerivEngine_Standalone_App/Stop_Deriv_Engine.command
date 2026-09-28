#!/bin/bash
echo "Stopping Deriv Engine..."

# Stop running backend server on port 8000
PORT_PID=$(lsof -t -i:8000 2>/dev/null || true)
if [ -n "$PORT_PID" ]; then
    echo "Stopping backend server (PID $PORT_PID)..."
    kill -9 $PORT_PID 2>/dev/null || true
fi

# Close macOS app if running
pkill -f "Deriv Engine" || true

echo "Deriv Engine stopped successfully."
