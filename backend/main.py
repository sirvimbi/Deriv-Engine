import asyncio
import json
import logging
import time
from pathlib import Path
from typing import List, Dict, Any
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from models import TradingConfig, BotStatus, ManualTradeRequest, LogMessage
from trading_bot import TradingBot
from deriv_client import DerivClient
from runtime import ENGINE_BUILD, ENGINE_DESCRIPTION

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
CONFIG_FILE = Path(__file__).resolve().parent / "trading_config.json"

def _normalized_config(config: TradingConfig) -> TradingConfig:
    """Normalize persisted settings to the same canonical values used by the UI."""
    mode = str(config.contract_type_mode).upper()
    if mode not in ("DIGITUNDER", "DIGITOVER", "BOTH"):
        mode = "BOTH"
    data = config.dict()
    data["contract_type_mode"] = mode
    return TradingConfig.parse_obj(data)


def load_persisted_config() -> TradingConfig:
    if not CONFIG_FILE.exists():
        return _normalized_config(default_config)
    try:
        with CONFIG_FILE.open("r", encoding="utf-8") as fh:
            return _normalized_config(TradingConfig.parse_obj(json.load(fh)))
    except Exception as exc:
        logger.warning("Unable to load persisted trading config: %s", exc)
        return _normalized_config(default_config)

def persist_config(config: TradingConfig):
    normalized = _normalized_config(config)
    tmp = CONFIG_FILE.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(normalized.dict(), fh, indent=2)
        fh.flush()
    tmp.replace(CONFIG_FILE)

bot = TradingBot(load_persisted_config())

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


async def equity_broadcast_loop():
    """Keep account balance/equity live using the bot's authenticated WS.

    Deriv's balance endpoint is the authoritative account value and supports
    real-time subscriptions. Reusing the bot's authenticated client avoids
    creating a new OTP/WebSocket session every five seconds, which can race
    with trading and make the balance path unreliable.
    """
    while True:
        try:
            # Do not authenticate from the background refresh loop. The bot,
            # dashboard balance endpoint, and manual trade endpoint all own
            # authentication and can race if this loop opens a second OTP
            # session. Once an authenticated client exists, refresh it here.
            if bot.client.authorized:
                balance = await bot.client.get_balance()
                await bot._on_balance(balance)
        except Exception as e:
            logger.warning(f"Equity refresh skipped: {e}")
        await asyncio.sleep(3)


@app.on_event("startup")
async def _start_background_tasks():
    asyncio.create_task(equity_broadcast_loop())


@app.get("/api/runtime")
def get_runtime():
    """Expose the backend build identity so the macOS client cannot trade against a stale process."""
    return {
        "engine_build": ENGINE_BUILD,
        "description": ENGINE_DESCRIPTION,
        "api": "current-deriv-options-v1"
    }

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
    # Pydantic validates the numeric ranges; normalize the contract mode once
    # and persist the canonical configuration that the bot actually receives.
    config = _normalized_config(config)
    bot.update_config(config)
    persist_config(bot.config)
    return bot.config

@app.post("/api/bot/start")
async def start_bot():
    if bot.is_running:
        return {"status": "already_running", "message": "Bot is already running"}
    try:
        # Stamp a fresh session and tell every connected client to wipe its
        # Transactions view before the bot places its first trade, so a new
        # run never mixes in transactions from a previous session.
        bot.session_start_epoch = int(time.time())
        await broadcast_ws_event("history_reset", {})
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

@app.post("/api/bot/logs/clear")
async def clear_bot_logs():
    bot.clear_logs()
    return {"status": "success", "message": "Execution logs cleared"}

async def _monitor_manual_contract(contract_id: int):
    """Refresh equity when a manually placed contract settles."""
    done = asyncio.Event()

    async def on_update(poc: Dict[str, Any]):
        if poc.get("is_sold"):
            try:
                settled = await bot.client.get_balance()
                await bot._on_balance(settled)
                await broadcast_ws_event("history_refresh", {"reason": "manual_trade_settled", "contract_id": contract_id})
            except Exception as exc:
                logger.warning("Manual trade equity refresh failed: %s", exc)
            finally:
                bot.client.unsubscribe_contract(contract_id)
                done.set()

    try:
        await bot.client.subscribe_contract(contract_id, on_update)
        await asyncio.wait_for(done.wait(), timeout=60.0)
    except asyncio.TimeoutError:
        logger.warning("Manual contract %s did not settle within 60 seconds.", contract_id)
        bot.client.unsubscribe_contract(contract_id)
    except Exception as exc:
        logger.warning("Manual contract %s monitoring failed: %s", contract_id, exc)
        bot.client.unsubscribe_contract(contract_id)


@app.post("/api/trade/place")
async def place_manual_trade(req: ManualTradeRequest):
    try:
        # Manual trades use the same authenticated Deriv client as the bot so
        # their balance/equity updates are reflected in the dashboard.
        if not bot.client.authorized:
            await bot.client.authorize(bot.config.api_token)
            await bot.client.subscribe_balance(bot._on_balance)

        buy_res = await bot.client.buy_contract(
            symbol=req.symbol,
            contract_type=req.contract_type,
            amount=req.amount,
            duration=req.duration,
            duration_unit=req.duration_unit,
            barrier=req.prediction,
            currency=req.currency
        )

        # Refresh immediately after purchase (stake has been charged), then
        # monitor settlement so the final win/loss balance is also displayed.
        try:
            await bot._on_balance(await bot.client.get_balance())
        except Exception as balance_error:
            logger.warning("Manual trade immediate equity refresh failed: %s", balance_error)

        contract_id = buy_res.get("contract_id")
        if contract_id:
            asyncio.create_task(_monitor_manual_contract(int(contract_id)))

        if not bot.session_start_epoch:
            bot.session_start_epoch = int(time.time())
        await bot.status_broadcast_callback("history_refresh", {"reason": "manual_trade"})
        return {"status": "success", "contract": buy_res}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Manual trade failed: {str(e)}")

@app.get("/api/history/session")
def get_history_session():
    return {
        "started_at": bot.session_start_epoch or None,
        "active": bool(bot.session_start_epoch)
    }

@app.get("/api/history/statement")
async def get_statement(limit: int = 50, token: str = None):
    api_token = token or bot.config.api_token
    client = DerivClient(app_id=bot.config.app_id, account_type=bot.config.account_type)
    try:
        await client.authorize(api_token)
        statement = await client.get_statement(limit=limit, date_from=bot.session_start_epoch or None)
        await client.disconnect()
        return {"status": "success", "transactions": statement}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/history/profit-table")
async def get_profit_table(limit: int = 50, token: str = None):
    api_token = token or bot.config.api_token
    client = DerivClient(app_id=bot.config.app_id, account_type=bot.config.account_type)
    try:
        await client.authorize(api_token)
        profit_table = await client.get_profit_table(limit=limit, date_from=bot.session_start_epoch or None)
        await client.disconnect()
        return {"status": "success", "transactions": profit_table}
    except Exception as e:
        await client.disconnect()
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/account/balance")
async def get_account_balance(token: str = None):
    """Return the current account balance and synchronize the bot/dashboard state.

    Prefer the bot's already-authenticated Deriv socket. This avoids creating
    another OTP session for every dashboard refresh and keeps the displayed
    equity on the same authenticated account used for trading.
    """
    api_token = token or bot.config.api_token
    try:
        if bot.client.authorized:
            balance = await bot.client.get_balance()
        else:
            if not api_token:
                raise RuntimeError("Deriv API token is not configured.")
            await bot.client.authorize(api_token)
            await bot.client.subscribe_balance(bot._on_balance)
            balance = await bot.client.get_balance()

        await bot._on_balance(balance)
        return {
            "status": "success",
            "balance": balance,
            "equity": bot.account_equity,
            "currency": balance.get("currency", bot.config.currency)
        }
    except Exception as e:
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
            elif action == "clear_logs":
                bot.clear_logs()
                await websocket.send_text(json.dumps({"type": "logs_reset", "data": {}}))
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
