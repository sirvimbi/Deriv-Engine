#!/bin/bash
echo "Starting Deriv Engine Python Backend..."

# Automatically release port 8000 if an old backend instance is running
PORT_PID=$(lsof -t -i:8000 2>/dev/null || true)
if [ -n "$PORT_PID" ]; then
    echo "Releasing port 8000 (stopping old PID $PORT_PID)..."
    kill -9 $PORT_PID 2>/dev/null || true
    sleep 1
fi

python3 -m venv venv
source venv/bin/activate
pip install -q -r requirements.txt
exec uvicorn main:app --host 0.0.0.0 --port 8000
