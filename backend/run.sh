#!/bin/bash
echo "Starting Deriv Engine Python Backend..."
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
exec uvicorn main:app --host 0.0.0.0 --port 8000
