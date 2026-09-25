import asyncio
import json
import logging
import websockets
from typing import Optional, Dict, Any, Callable
from websockets.protocol import State

logger = logging.getLogger("DerivClient")

class DerivClient:
    def __init__(self, app_id: int = 1089):
        self.app_id = app_id
        self.ws_urls = [
            "wss://ws.derivws.com/websockets/v3",
            "wss://ws.binaryws.com/websockets/v3",
            "wss://blue.derivws.com/websockets/v3"
        ]
        self.ws: Optional[Any] = None
        self.req_id_counter = 1
        self.pending_requests: Dict[int, asyncio.Future] = {}
        self.tick_callbacks: list = []
        self.contract_callbacks: Dict[int, list] = {}
        self.listen_task: Optional[asyncio.Task] = None
        self.authorized = False
        self.account_info: Dict[str, Any] = {}

    def _get_req_id(self) -> int:
        req_id = self.req_id_counter
        self.req_id_counter += 1
        return req_id

    async def connect(self):
        if self.ws and self.ws.state is State.OPEN:
            return
        
        last_err = None
        for url in self.ws_urls:
            try:
                logger.info(f"Attempting connection to Deriv WS at {url}...")
                self.ws = await websockets.connect(
                    url,
                    proxy=None,
                    open_timeout=15,
                    ping_interval=20,
                    ping_timeout=20
                )
                self.listen_task = asyncio.create_task(self._listen_loop())
                logger.info(f"Connected to Deriv WS successfully at {url}.")
                return
            except Exception as e:
                logger.warning(f"Failed to connect to {url}: {e}")
                last_err = e

        if last_err:
            raise last_err

    async def disconnect(self):
        if self.listen_task:
            self.listen_task.cancel()
            try:
                await self.listen_task
            except asyncio.CancelledError:
                pass
            self.listen_task = None
        if self.ws:
            await self.ws.close()
            self.ws = None
        for future in list(self.pending_requests.values()):
            if not future.done():
                future.cancel()
        self.pending_requests.clear()
        self.authorized = False
        logger.info("Disconnected from Deriv WS.")

    async def send_request(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        await self.connect()
        req_id = self._get_req_id()
        payload["req_id"] = req_id
        
        future = asyncio.get_running_loop().create_future()
        self.pending_requests[req_id] = future

        try:
            await self.ws.send(json.dumps(payload))
            return await asyncio.wait_for(future, timeout=15.0)
        except Exception:
            if not future.done():
                future.cancel()
            raise
        finally:
            self.pending_requests.pop(req_id, None)

    async def _listen_loop(self):
        try:
            async for message in self.ws:
                data = json.loads(message)
                msg_type = data.get("msg_type")
                req_id = data.get("req_id")

                if req_id and req_id in self.pending_requests:
                    if not self.pending_requests[req_id].done():
                        self.pending_requests[req_id].set_result(data)

                # Handle Tick updates
                if msg_type == "tick":
                    tick = data.get("tick")
                    if tick:
                        for cb in list(self.tick_callbacks):
                            try:
                                if asyncio.iscoroutinefunction(cb):
                                    await cb(tick)
                                else:
                                    cb(tick)
                            except Exception as e:
                                logger.error(f"Error in tick callback: {e}")

                # Handle Contract updates
                if msg_type == "proposal_open_contract":
                    poc = data.get("proposal_open_contract")
                    if poc:
                        contract_id = poc.get("contract_id")
                        if contract_id and contract_id in self.contract_callbacks:
                            for cb in list(self.contract_callbacks[contract_id]):
                                try:
                                    if asyncio.iscoroutinefunction(cb):
                                        await cb(poc)
                                    else:
                                        cb(poc)
                                except Exception as e:
                                    logger.error(f"Error in contract callback: {e}")

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"WebSocket listen loop error: {e}")

    async def authorize(self, token: str) -> Dict[str, Any]:
        if not token or not token.strip():
            raise ValueError("Deriv API token is required.")
        response = await self.send_request({"authorize": token})
        if "error" in response:
            self.authorized = False
            raise Exception(response["error"].get("message", "Authorization failed"))
        self.authorized = True
        self.account_info = response.get("authorize", {})
        return response

    async def subscribe_ticks(self, symbol: str, callback: Callable):
        if callback not in self.tick_callbacks:
            self.tick_callbacks.append(callback)
        response = await self.send_request({"ticks": symbol, "subscribe": 1})
        return response

    async def unsubscribe_ticks(self, symbol: str):
        response = await self.send_request({"forget_all": "ticks"})
        self.tick_callbacks.clear()
        return response

    async def buy_contract(
        self,
        symbol: str,
        contract_type: str,
        amount: float,
        duration: int = 1,
        duration_unit: str = "t",
        barrier: Optional[int] = None,
        currency: str = "USD"
    ) -> Dict[str, Any]:
        params = {
            "amount": amount,
            "basis": "stake",
            "contract_type": contract_type,
            "currency": currency,
            "duration": duration,
            "duration_unit": duration_unit,
            "symbol": symbol
        }
        if barrier is not None:
            params["barrier"] = str(barrier)

        request = {
            "buy": 1,
            "price": amount,
            "parameters": params
        }
        
        response = await self.send_request(request)
        if "error" in response:
            raise Exception(response["error"].get("message", "Contract purchase failed"))
        return response.get("buy", {})

    async def subscribe_contract(self, contract_id: int, callback: Callable):
        if contract_id not in self.contract_callbacks:
            self.contract_callbacks[contract_id] = []
        if callback not in self.contract_callbacks[contract_id]:
            self.contract_callbacks[contract_id].append(callback)

        response = await self.send_request({
            "proposal_open_contract": 1,
            "contract_id": contract_id,
            "subscribe": 1
        })
        return response

    def unsubscribe_contract(self, contract_id: int):
        self.contract_callbacks.pop(contract_id, None)

    async def get_statement(self, limit: int = 50) -> list:
        res = await self.send_request({
            "statement": 1,
            "description": 1,
            "limit": limit
        })
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch statement"))
        return res.get("statement", {}).get("transactions", [])

    async def get_profit_table(self, limit: int = 50) -> list:
        res = await self.send_request({
            "profit_table": 1,
            "description": 1,
            "limit": limit
        })
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch profit table"))
        return res.get("profit_table", {}).get("transactions", [])

    async def get_balance(self) -> Dict[str, Any]:
        res = await self.send_request({"balance": 1})
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch balance"))
        return res.get("balance", {})
