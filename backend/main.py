import asyncio
import json
import logging
from typing import List, Dict, Any
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from models import TradingConfig, BotStatus, ManualTradeRequest, LogMessage
from trading_bot import TradingBot
from deriv_client import DerivClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("MainServer")

app = FastAPI(
    title="Deriv Trading Bot Engine",
    description="Backend service connecting Swift UI frontend to Deriv WebSocket API for Options Trading",
    version="1.0.0"
)

# Enable CORS for cross-platform clients (Swift, Web, Mobile)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global bot instance
default_config = TradingConfig()
bot = TradingBot(default_config)

# Connected WebSocket Clients
connected_websockets: List[WebSocket] = []

async def broadcast_ws_event(event_type: str, data: Any):
    payload = json.dumps({"type": event_type, "data": data})
    disconnected = []
    for ws in connected_websockets:
        try:
            await ws.send_text(payload)
        except Exception:
            disconnected.append(ws)
    for ws in disconnected:
        if ws in connected_websockets:
            connected_websockets.remove(ws)

bot.set_broadcast_callback(broadcast_ws_event)

@app.get("/")
def read_root():
    return {
        "status": "online",
        "app_name": "Deriv Trading Engine",
        "bot_running": bot.is_running
    }

@app.get("/api/config", response_model=TradingConfig)
def get_config():
    return bot.config

@app.post("/api/config", response_model=TradingConfig)
async def update_config(config: TradingConfig):
    bot.update_config(config)
    return bot.config

@app.post("/api/bot/start")
async def start_bot():
    if bot.is_running:
        return {"status": "already_running", "message": "Bot is already running"}
    try:
        await bot.start()
        return {"status": "started", "message": "Bot started successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/bot/stop")
async def stop_bot():
    if not bot.is_running:
        return {"status": "not_running", "message": "Bot is not running"}
    await bot.stop("Stopped by API user")
    return {"status": "stopped", "message": "Bot stopped successfully"}

@app.get("/api/bot/status", response_model=BotStatus)
def get_bot_status():
    return bot.get_status()

@app.get("/api/bot/logs", response_model=List[LogMessage])
def get_bot_logs():
    return bot.logs

@app.post("/api/trade/place")
async def place_manual_trade(req: ManualTradeRequest):
    client = DerivClient(app_id=bot.config.app_id, account_type=bot.config.account_type)
    try:
        await client.authorize(bot.config.api_token)
        buy_res = await client.buy_contract(
            symbol=req.symbol,
            contract_type=req.contract_type,
            amount=req.amount,
            duration=req.duration,
            duration_unit=req.duration_unit,
            barrier=req.prediction,
            currency=req.currency
        )
        await client.disconnect()
        return {"status": "success", "contract": buy_res}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=f"Manual trade failed: {str(e)}")

@app.get("/api/history/statement")
async def get_statement(limit: int = 50, token: str = None):
    api_token = token or bot.config.api_token
    client = DerivClient(app_id=bot.config.app_id)
    try:
        await client.authorize(api_token)
        statement = await client.get_statement(limit=limit)
        await client.disconnect()
        return {"status": "success", "transactions": statement}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/history/profit-table")
async def get_profit_table(limit: int = 50, token: str = None):
    api_token = token or bot.config.api_token
    client = DerivClient(app_id=bot.config.app_id)
    try:
        await client.authorize(api_token)
        profit_table = await client.get_profit_table(limit=limit)
        await client.disconnect()
        return {"status": "success", "transactions": profit_table}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/account/balance")
async def get_account_balance(token: str = None):
    api_token = token or bot.config.api_token
    client = DerivClient(app_id=bot.config.app_id)
    try:
        await client.authorize(api_token)
        balance = await client.get_balance()
        await client.disconnect()
        return {"status": "success", "balance": balance}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=str(e))

@app.websocket("/ws/live")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    connected_websockets.append(websocket)
    logger.info("New WebSocket client connected.")
    try:
        # Send initial status & logs
        initial_payload = {
            "type": "init",
            "data": {
                "status": bot.get_status().dict(),
                "logs": [l.dict() for l in bot.logs]
            }
        }
        await websocket.send_text(json.dumps(initial_payload))
        
        # Keep connection open and handle incoming messages
        while True:
            msg = await websocket.receive_text()
            data = json.loads(msg)
            action = data.get("action")
            if action == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
            elif action == "get_status":
                await websocket.send_text(json.dumps({"type": "status", "data": bot.get_status().dict()}))

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        if websocket in connected_websockets:
            connected_websockets.remove(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
