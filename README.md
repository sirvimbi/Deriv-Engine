# Deriv Engine Options Trading Application

A full-stack, modular, automated algorithmic options trading solution for **Deriv.com** based on DBot/Blockly XML strategy specification.

## Architecture Overview

1. **Python Backend (`backend/`)**:
   - Built with **FastAPI**, **WebSockets**, and **asyncio**.
   - Directly connects to **Deriv WebSocket API** (`wss://ws.derivws.com/websockets/v3?app_id=...`).
   - Implements the exact XML trade definition, entry triggers (`DIGITUNDER`, `DIGITOVER`), recovery win reset logic, and martingale loss escalation rules.
   - Exposes REST API and real-time WebSocket endpoints for live telemetry, tick streaming, status, and manual options placement.

2. **Swift Frontend (`swift_frontend/`)**:
   - Built with **SwiftUI** for iOS / macOS / iPadOS.
   - **Dashboard**: Live P&L card grid, live last digit stream widget, real-time strategy statistics, and live terminal logs.
   - **Bot Settings**: Complete control interface where **NO variable is hardcoded**. The user can configure API Token, Base Stake, Max Stake, Martingale Multiplier, Take Profit, Stop Loss, Max Runs, Loss Streaks, and Trigger Digits manually.
   - **Transactions**: Displays transaction statement and profit table fetched directly from the Deriv API.
   - **Manual Options**: Interface to execute custom options trades on demand.

---

## Strategy Details (from XML)

- **Market**: Synthetic Index (`R_100` Volatility 100 Index)
- **Trade Category**: Digits Over/Under (`overunder`)
- **Duration**: 1 Tick (`1t`)
- **Entry Rules**:
  - **Digit Under**: Triggered when `last_digit == under_trigger_digit` (default: 2) AND `current_stake == base_stake`. Target digit prediction: 8.
  - **Digit Over**: Triggered when `last_digit == over_trigger_digit` (default: 8) AND `current_stake > base_stake`. Target digit prediction: 3.
- **After Contract Result**:
  - **On Win**:
    - If `stake > base_stake`: Increment recovery win counter. When `recovery_win_count >= recovery_wins_required` (default: 2), reset stake to `base_stake`.
    - Else: Reset stake to `base_stake`.
    - Reset prediction to `win_predict_digit` (8) and reset loss streak counter.
  - **On Loss**:
    - Increment loss streak counter.
    - If `loss_streak >= max_loss_streak` (default: 4), trigger safety reset: reset stake to `base_stake` and reset loss streak.
    - Otherwise: Multiply stake by `martingale` multiplier (capped at `max_stake`), set next prediction to `loss_predict_digit` (3).
- **Stopping Limits**: Bot automatically halts trading when `total_profit >= take_profit`, `total_profit <= -stop_loss`, or `runs >= max_runs`.

---

## Getting Started

### 1. Run the Python Backend

```bash
cd backend
chmod +x run.sh
./run.sh
```

Or manually:
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

The backend server will run at: `http://localhost:8000`  
Swagger API Docs will be available at: `http://localhost:8000/docs`

### 2. Run the Swift Frontend Application

1. Open Xcode and create or load the Swift project using the source files in `swift_frontend/`.
2. Select your iOS Simulator or macOS target.
3. Build & Run (`Cmd + R`).

---

## Default API Configuration

- **Deriv API Token**: Pre-filled with `pat_63d70ebd7948f94b89f50cb0fced0450e011f4361213ae11838f190bebb618ab` (user configurable in Settings screen).
- **App ID**: `1089` (user configurable).
