import asyncio
import json
import logging
import ssl
import certifi
import requests
import websockets
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional, Dict, Any, Callable
from websockets.protocol import State

logger = logging.getLogger("DerivClient")

class DerivClient:
    """Deriv WebSocket client using the current REST OTP authentication flow."""

    REST_BASE_URL = "https://api.derivws.com"
    PUBLIC_WS_URL = "wss://api.derivws.com/trading/v1/options/ws/public"

    def __init__(self, app_id: str = "", account_type: str = "demo"):
        self.app_id = str(app_id).strip()
        self.account_type = account_type if account_type in ("demo", "real") else "demo"
        self.ws: Optional[Any] = None
        self.ws_url: Optional[str] = None
        self.req_id_counter = 1
        self.pending_requests: Dict[int, asyncio.Future] = {}
        self.tick_callbacks: list = []
        self.contract_callbacks: Dict[int, list] = {}
        self.balance_callbacks: list = []
        self.listen_task: Optional[asyncio.Task] = None
        self.authorized = False
        self.account_info: Dict[str, Any] = {}

    def _get_req_id(self) -> int:
        req_id = self.req_id_counter
        self.req_id_counter += 1
        return req_id

    @staticmethod
    def _normalize_token(token: str) -> str:
        # Secure text fields and paste operations can introduce surrounding
        # whitespace/newlines. Do not log or expose the token.
        return "".join(str(token).split())

    def _headers(self, token: str) -> Dict[str, str]:
        normalized = self._normalize_token(token)
        headers = {
            "Authorization": f"Bearer {normalized}",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        if self.app_id:
            headers["Deriv-App-ID"] = self.app_id
        return headers

    def _request_json(self, method: str, path: str, token: str) -> Dict[str, Any]:
        url = f"{self.REST_BASE_URL}{path}"
        response = requests.request(
            method,
            url,
            headers=self._headers(token),
            timeout=15
        )
        try:
            data = response.json()
        except ValueError:
            data = {}

        if response.status_code >= 400:
            errors = data.get("errors") or []
            error = errors[0] if errors and isinstance(errors[0], dict) else {}
            message = error.get("message") or response.text.strip() or f"HTTP {response.status_code}"
            code = error.get("code")

            if response.status_code == 401:
                if code in {"Unauthorized", "InvalidToken", "AuthenticationError"} or "token" in message.lower():
                    raise RuntimeError(
                        "Deriv rejected the authorization token (401). "
                        "Generate a new Personal Access Token for this Deriv App in the Developer Dashboard "
                        "with the trade scope, then replace the token in Settings. "
                        "Do not use a legacy API token or an expired OAuth access token."
                    )
                raise RuntimeError(
                    f"Deriv rejected authentication (401): {message}"
                )

            if response.status_code == 403:
                raise RuntimeError(
                    "Deriv accepted the token but denied access (403). "
                    "Ensure the token has the trade scope and belongs to the selected Deriv App."
                )

            raise RuntimeError(f"Deriv REST request failed ({response.status_code}): {message}")

        return data

    async def _get_authenticated_ws_url(self, token: str) -> Dict[str, Any]:
        normalized_token = self._normalize_token(token)
        if not normalized_token:
            raise ValueError("Deriv API token is required.")
        if not self.app_id:
            raise ValueError(
                "A current Deriv App ID is required. Enter the App ID exactly as shown in your Deriv Developer Dashboard."
            )

        accounts = await asyncio.to_thread(
            self._request_json,
            "GET",
            "/trading/v1/options/accounts",
            normalized_token
        )

        data = accounts.get("data", [])
        if isinstance(data, dict):
            data = [data]

        matching = [
            account for account in data
            if str(account.get("account_type", "")).lower() == self.account_type
        ]

        if not matching:
            raise RuntimeError(
                f"No active {self.account_type} Options trading account was returned by Deriv. "
                "The token may not have access to Options trading or the account may not be migrated."
            )

        account = matching[0]
        account_id = account.get("account_id")
        if not account_id:
            raise RuntimeError("Deriv returned an account without an account_id.")

        otp_response = await asyncio.to_thread(
            self._request_json,
            "POST",
            f"/trading/v1/options/accounts/{account_id}/otp",
            normalized_token
        )

        otp_data = otp_response.get("data", {})
        ws_url = otp_data.get("url")
        if not ws_url:
            raise RuntimeError("Deriv OTP response did not contain a WebSocket URL.")

        return {"url": ws_url, "account": account}

    async def _connect_url(self, url: str):
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        self.ws = await websockets.connect(
            url,
            ssl=ssl_context,
            proxy=None,
            open_timeout=15,
            ping_interval=20,
            ping_timeout=20
        )
        self.ws_url = url
        self.listen_task = asyncio.create_task(self._listen_loop())
        logger.info("Connected to Deriv WebSocket successfully.")

    async def connect(self, url: Optional[str] = None):
        if self.ws and self.ws.state is State.OPEN:
            return

        target = url or self.ws_url
        if not target:
            target = self.PUBLIC_WS_URL

        try:
            logger.info(f"Attempting connection to Deriv WS at {target}...")
            await self._connect_url(target)
        except Exception:
            self.ws = None
            raise

    async def disconnect(self):
        if self.listen_task:
            self.listen_task.cancel()
            try:
                await self.listen_task
            except asyncio.CancelledError:
                pass
            self.listen_task = None

        if self.ws:
            try:
                await self.ws.close()
            except Exception:
                pass
            self.ws = None

        for future in list(self.pending_requests.values()):
            if not future.done():
                future.cancel()
        self.pending_requests.clear()
        self.authorized = False
        self.ws_url = None
        logger.info("Disconnected from Deriv WS.")

    async def send_request(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        await self.connect()
        if not self.ws or self.ws.state is not State.OPEN:
            raise ConnectionError("Deriv WebSocket is not connected.")

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

                if req_id is not None and req_id in self.pending_requests:
                    future = self.pending_requests[req_id]
                    if not future.done():
                        future.set_result(data)

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

                if msg_type == "balance":
                    balance = data.get("balance")
                    if balance:
                        for cb in list(self.balance_callbacks):
                            try:
                                if asyncio.iscoroutinefunction(cb):
                                    await cb(balance)
                                else:
                                    cb(balance)
                            except Exception as e:
                                logger.error(f"Error in balance callback: {e}")

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
            for future in list(self.pending_requests.values()):
                if not future.done():
                    future.set_exception(ConnectionError(str(e)))

    async def authorize(self, token: str) -> Dict[str, Any]:
        """Authenticate by REST Bearer token -> account lookup -> one-time WebSocket OTP."""
        normalized_token = self._normalize_token(token)
        if not normalized_token:
            raise ValueError("Deriv API token is required.")

        try:
            auth = await self._get_authenticated_ws_url(normalized_token)
            if self.ws:
                await self.disconnect()

            await self._connect_url(auth["url"])
            self.authorized = True
            self.account_info = auth["account"]
            logger.info(
                f"Authenticated Deriv WebSocket for {self.account_info.get('account_id', 'unknown')} "
                f"({self.account_info.get('account_type', self.account_type)})."
            )
            return {"authorize": self.account_info}
        except Exception:
            self.authorized = False
            raise

    async def subscribe_ticks(self, symbol: str, callback: Callable):
        if callback not in self.tick_callbacks:
            self.tick_callbacks.append(callback)
        response = await self.send_request({"ticks": symbol, "subscribe": 1})
        if "error" in response:
            raise Exception(response["error"].get("message", "Tick subscription failed"))
        return response

    async def unsubscribe_ticks(self, symbol: str):
        response = await self.send_request({"forget_all": "ticks"})
        self.tick_callbacks.clear()
        return response

    async def buy_contract(self, symbol: str, contract_type: str, amount: float, duration: int = 1, duration_unit: str = "t", barrier: Optional[int] = None, currency: str = "USD") -> Dict[str, Any]:
        normalized_amount = Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        if normalized_amount < Decimal("0.01"):
            raise ValueError("Trade amount must be at least 0.01.")
        params = {
            "amount": float(normalized_amount),
            "basis": "stake",
            "contract_type": contract_type,
            "currency": currency,
            "duration": duration,
            "duration_unit": duration_unit,
            "underlying_symbol": symbol
        }
        if barrier is not None:
            params["barrier"] = str(barrier)

        response = await self.send_request({"buy": 1, "price": float(normalized_amount), "parameters": params})
        if "error" in response:
            raise Exception(response["error"].get("message", "Contract purchase failed"))
        return response.get("buy", {})

    async def subscribe_contract(self, contract_id: int, callback: Callable):
        if contract_id not in self.contract_callbacks:
            self.contract_callbacks[contract_id] = []
        if callback not in self.contract_callbacks[contract_id]:
            self.contract_callbacks[contract_id].append(callback)
        response = await self.send_request({"proposal_open_contract": 1, "contract_id": contract_id, "subscribe": 1})
        if "error" in response:
            raise Exception(response["error"].get("message", "Contract subscription failed"))
        return response

    def unsubscribe_contract(self, contract_id: int):
        self.contract_callbacks.pop(contract_id, None)

    async def get_statement(self, limit: int = 50, date_from: Optional[int] = None) -> list:
        payload = {"statement": 1, "description": 1, "limit": limit}
        if date_from:
            payload["date_from"] = int(date_from)
        res = await self.send_request(payload)
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch statement"))
        return res.get("statement", {}).get("transactions", [])

    async def get_profit_table(self, limit: int = 50, date_from: Optional[int] = None) -> list:
        payload = {"profit_table": 1, "limit": limit}
        if date_from:
            payload["date_from"] = int(date_from)
        res = await self.send_request(payload)
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch profit table"))
        return res.get("profit_table", {}).get("transactions", [])

    async def get_balance(self) -> Dict[str, Any]:
        res = await self.send_request({"balance": 1})
        if "error" in res:
            raise Exception(res["error"].get("message", "Failed to fetch balance"))
        return res.get("balance", {})
