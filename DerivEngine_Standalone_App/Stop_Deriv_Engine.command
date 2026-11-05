#!/bin/bash
echo "Stopping Deriv Engine..."
lsof -ti:8000 | xargs kill -9 2>/dev/null
pkill -f "Deriv Engine" 2>/dev/null
echo "Deriv Engine stopped."
