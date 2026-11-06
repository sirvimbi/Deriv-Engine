import asyncio
import json
import logging
import re
import ssl
import time
import certifi
import requests
import websockets
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from decimal import Decimal, ROUND_HALF_UP, ROUND_UP, ROUND_DOWN
from typing import Optional, Dict, Any, Callable
from websockets.protocol import State

logger = logging.getLogger("DerivClient")


class DerivTransientServiceError(RuntimeError):
    """A retryable Deriv REST/network failure, not an invalid-token response."""

    def __init__(self, message: str, status_code: Optional[int] = None):
        super().__init__(message)
        self.status_code = status_code


class DerivClient:
    """Deriv WebSocket client using the current REST OTP authentication flow."""

    REST_RETRYABLE_STATUS_CODES = frozenset({408, 425, 429, 500, 502, 503, 504})
    REST_REQUEST_MAX_ATTEMPTS = 5
    REST_RETRY_BASE_DELAY_SECONDS = 1.0
    REST_RETRY_MAX_DELAY_SECONDS = 12.0
    REST_RETRY_AFTER_MAX_SECONDS = 30.0

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
        self._auth_token = ""
        # Authentication is a shared resource: the bot, balance endpoint,
        # background equity loop, and manual trading all use this client.
        # Serialize OTP creation/replacement so concurrent callers cannot
        # invalidate each other's one-time WebSocket sessions.
        self._auth_lock = asyncio.Lock()

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

    @classmethod
    def _rest_retry_delay(cls, response: Any, attempt: int) -> float:
        """Respect Retry-After where supplied, otherwise use bounded exponential backoff."""
        headers = getattr(response, "headers", {}) or {}
        retry_after = headers.get("Retry-After") if hasattr(headers, "get") else None
        if retry_after is not None:
            try:
                return min(
                    cls.REST_RETRY_AFTER_MAX_SECONDS,
                    max(0.0, float(retry_after)),
                )
            except (TypeError, ValueError):
                try:
                    retry_at = parsedate_to_datetime(str(retry_after))
                    if retry_at.tzinfo is None:
                        retry_at = retry_at.replace(tzinfo=timezone.utc)
                    return min(
                        cls.REST_RETRY_AFTER_MAX_SECONDS,
                        max(0.0, (retry_at - datetime.now(timezone.utc)).total_seconds()),
                    )
                except (TypeError, ValueError, OverflowError):
                    pass

        return min(
            cls.REST_RETRY_MAX_DELAY_SECONDS,
            cls.REST_RETRY_BASE_DELAY_SECONDS * (2 ** max(0, attempt - 1)),
        )

    def _request_json(self, method: str, path: str, token: str) -> Dict[str, Any]:
        """Make a REST request, retrying temporary 429/5xx and network failures.

        Authentication failures (401/403) are deliberately not retried: these
        indicate token/scope configuration problems, not a transient outage.
        """
        url = f"{self.REST_BASE_URL}{path}"
        last_transient_error: Optional[BaseException] = None

        for attempt in range(1, self.REST_REQUEST_MAX_ATTEMPTS + 1):
            try:
                response = requests.request(
                    method,
                    url,
                    headers=self._headers(token),
                    timeout=15,
                )
            except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as exc:
                last_transient_error = exc
                if attempt >= self.REST_REQUEST_MAX_ATTEMPTS:
                    raise DerivTransientServiceError(
                        f"Deriv REST request failed after {attempt} attempts due to a temporary network error: {exc}"
                    ) from exc

                delay = min(
                    self.REST_RETRY_MAX_DELAY_SECONDS,
                    self.REST_RETRY_BASE_DELAY_SECONDS * (2 ** (attempt - 1)),
                )
                logger.warning(
                    "Temporary Deriv REST network failure for %s %s "
                    "(attempt %d/%d): %s. Retrying in %.1fs.",
                    method,
                    path,
                    attempt,
                    self.REST_REQUEST_MAX_ATTEMPTS,
                    exc,
                    delay,
                )
                time.sleep(delay)
                continue

            try:
                data = response.json()
            except ValueError:
                data = {}
            if not isinstance(data, dict):
                data = {}

            if response.status_code >= 400:
                errors = data.get("errors") or []
                error = errors[0] if errors and isinstance(errors[0], dict) else {}
                message = (
                    error.get("message")
                    or response.text.strip()
                    or f"HTTP {response.status_code}"
                )
                code = error.get("code")

                if response.status_code == 401:
                    if code in {"Unauthorized", "InvalidToken", "AuthenticationError"} or "token" in message.lower():
                        raise RuntimeError(
                            "Deriv rejected the authorization token (401). "
                            "Generate a new Personal Access Token for this Deriv App in the Developer Dashboard "
                            "with the trade scope, then replace the token in Settings. "
                            "Do not use a legacy API token or an expired OAuth access token."
                        )
                    raise RuntimeError(f"Deriv rejected authentication (401): {message}")

                if response.status_code == 403:
                    raise RuntimeError(
                        "Deriv accepted the token but denied access (403). "
                        "Ensure the token has the trade scope and belongs to the selected Deriv App."
                    )

                if response.status_code in self.REST_RETRYABLE_STATUS_CODES:
                    last_transient_error = RuntimeError(
                        f"HTTP {response.status_code}: {message}"
                    )
                    if attempt >= self.REST_REQUEST_MAX_ATTEMPTS:
                        raise DerivTransientServiceError(
                            f"Deriv REST request failed ({response.status_code}) after "
                            f"{attempt} attempts: {message}",
                            status_code=response.status_code,
                        ) from last_transient_error

                    delay = self._rest_retry_delay(response, attempt)
                    logger.warning(
                        "Deriv REST %s %s returned HTTP %s "
                        "(attempt %d/%d): %s. Retrying in %.1fs.",
                        method,
                        path,
                        response.status_code,
                        attempt,
                        self.REST_REQUEST_MAX_ATTEMPTS,
                        message,
                        delay,
                    )
                    time.sleep(delay)
                    continue

                raise RuntimeError(
                    f"Deriv REST request failed ({response.status_code}): {message}"
                )

            return data

        # Defensive fallback: the loop either returns a response or raises.
        raise DerivTransientServiceError(
            f"Deriv REST request failed after {self.REST_REQUEST_MAX_ATTEMPTS} attempts: "
            f"{last_transient_error or 'unknown temporary failure'}"
        )

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

        # An authenticated OTP URL is single-use. Never reconnect an
        # authenticated client to an old OTP or to the public socket.
        # If the authenticated socket disappeared, authorize() obtains a
        # fresh OTP before another account-scoped request is sent.
        if url is None and self._auth_token:
            await self.authorize(self._auth_token)
            return

        target = url or self.PUBLIC_WS_URL
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
        self._auth_token = ""
        logger.info("Disconnected from Deriv WS.")

    async def send_request(
        self,
        payload: Dict[str, Any],
        exact_numeric_fields: Optional[Dict[str, str]] = None,
        retries: int = 3
    ) -> Dict[str, Any]:
        last_exception: Optional[BaseException] = None

        for attempt in range(1, retries + 1):
            try:
                await self.connect()
                if not self.ws or self.ws.state is not State.OPEN:
                    raise ConnectionError("Deriv WebSocket is not connected.")

                req_id = self._get_req_id()
                payload["req_id"] = req_id

                future = asyncio.get_running_loop().create_future()
                self.pending_requests[req_id] = future

                try:
                    encoded = json.dumps(payload, separators=(",", ":"), allow_nan=False)
                    for field, raw_number in (exact_numeric_fields or {}).items():
                        if field not in payload:
                            raise ValueError(f"Exact numeric field '{field}' is missing from payload.")
                        Decimal(raw_number)
                        encoded_field = json.dumps(field, separators=(",", ":"))
                        encoded_value = json.dumps(payload[field], separators=(",", ":"))
                        encoded = encoded.replace(
                            f"{encoded_field}:{encoded_value}",
                            f"{encoded_field}:{raw_number}",
                            1
                        )
                    await self.ws.send(encoded)
                    return await asyncio.wait_for(future, timeout=15.0)
                finally:
                    self.pending_requests.pop(req_id, None)

            except (ConnectionError, websockets.exceptions.ConnectionClosed, asyncio.TimeoutError) as exc:
                last_exception = exc
                logger.warning(
                    f"WebSocket request failed on attempt {attempt}/{retries} ({exc}). Re-connecting..."
                )
                self.ws = None
                self.authorized = False
                if self._auth_token:
                    try:
                        await self.authorize(self._auth_token)
                    except Exception as reauth_err:
                        logger.warning(f"Re-authorization failed on retry attempt {attempt}: {reauth_err}")
                await asyncio.sleep(0.5 * attempt)

        if last_exception:
            raise last_exception
        raise ConnectionError("Deriv WebSocket request failed after retries.")

    async def _listen_loop(self):
        try:
            async for message in self.ws:
                data = json.loads(message, parse_float=Decimal)
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
            if self.ws is not None:
                try:
                    await self.ws.close()
                except Exception:
                    pass
            self.ws = None
            self.authorized = False
            # Preserve the bearer token. A closed authenticated socket must
            # be replaced with a fresh OTP, not downgraded to public access.
            for future in list(self.pending_requests.values()):
                if not future.done():
                    future.set_exception(ConnectionError(f"Deriv WebSocket disconnected: {e}"))

        else:
            # A remote close can end the async iterator cleanly without raising
            # an exception. Treat that exactly like a socket failure so pending
            # requests fail immediately and the next request can reconnect.
            logger.warning("Deriv WebSocket listener ended because the connection closed.")
            self.ws = None
            self.authorized = False
            # Preserve the bearer token for fresh OTP recovery.
            for future in list(self.pending_requests.values()):
                if not future.done():
                    future.set_exception(ConnectionError("Deriv WebSocket connection closed."))

    async def authorize(self, token: str) -> Dict[str, Any]:
        """Authenticate with a serialized REST Bearer -> OTP -> WebSocket flow."""
        normalized_token = self._normalize_token(token)
        if not normalized_token:
            raise ValueError("Deriv API token is required.")

        async with self._auth_lock:
            # Authentication is idempotent for the shared client. If already authorized
            # and socket is OPEN, return current account info immediately.
            if (
                self.authorized
                and self.ws
                and self.ws.state is State.OPEN
            ):
                if not self._auth_token or self._auth_token == normalized_token:
                    return {"authorize": self.account_info}

            try:
                # Disconnect any old socket cleanly before requesting a new OTP/auth socket
                if self.ws:
                    await self.disconnect()

                auth = await self._get_authenticated_ws_url(normalized_token)
                await self._connect_url(auth["url"])
                self._auth_token = normalized_token
                self.authorized = True
                self.account_info = auth["account"]
                logger.info(
                    f"Authenticated Deriv WebSocket for {self.account_info.get('account_id', 'unknown')} "
                    f"({self.account_info.get('account_type', self.account_type)})."
                )
                return {"authorize": self.account_info}
            except Exception as e:
                err_msg = str(e).lower()
                if "already subscribed" in err_msg or "alreadysubscribed" in err_msg:
                    logger.info("Deriv WebSocket already authorized and subscribed to balance.")
                    self.authorized = True
                    return {"authorize": self.account_info}
                self.authorized = False
                raise

    async def subscribe_balance(self, callback: Callable):
        """Subscribe to Deriv balance updates on the authenticated WebSocket."""
        if callback not in self.balance_callbacks:
            self.balance_callbacks.append(callback)

        try:
            response = await self.send_request({"balance": 1, "subscribe": 1})
            if "error" in response:
                err = response["error"]
                err_msg = err.get("message", "")
                err_code = err.get("code", "")
                if "already subscribed" in err_msg.lower() or err_code == "AlreadySubscribed":
                    logger.info("Already subscribed to balance updates for account.")
                    return response
                if callback in self.balance_callbacks:
                    self.balance_callbacks.remove(callback)
                raise Exception(err_msg or "Balance subscription failed")
            return response
        except Exception as e:
            err_msg = str(e).lower()
            if "already subscribed" in err_msg or "alreadysubscribed" in err_msg:
                logger.info("Already subscribed to balance updates for account.")
                return {"balance": 1, "subscribe": 1}
            if callback in self.balance_callbacks:
                self.balance_callbacks.remove(callback)
            raise e

    async def subscribe_ticks(self, symbol: str, callback: Callable):
        if callback not in self.tick_callbacks:
            self.tick_callbacks.append(callback)

        last_error: Optional[BaseException] = None
        for attempt in range(1, 4):
            try:
                response = await self.send_request({"ticks": symbol, "subscribe": 1})
                if "error" in response:
                    raise Exception(response["error"].get("message", "Tick subscription failed"))
                logger.info("Tick subscription established | symbol=%s | attempt=%d", symbol, attempt)
                return response
            except (asyncio.CancelledError, ConnectionError, TimeoutError, websockets.exceptions.ConnectionClosed) as exc:
                last_error = exc
                if attempt >= 3:
                    break
                if self._auth_token:
                    logger.warning(
                        "Tick subscription interrupted for %s (attempt %d/3); requesting a fresh authenticated WebSocket.",
                        symbol, attempt
                    )
                    try:
                        await self.authorize(self._auth_token)
                    except Exception as reconnect_error:
                        last_error = reconnect_error
                        await asyncio.sleep(0.5 * attempt)
                else:
                    await asyncio.sleep(0.5 * attempt)

        if last_error:
            if isinstance(last_error, asyncio.CancelledError):
                raise ConnectionError(f"Unable to subscribe to ticks for {symbol}: WebSocket cancelled after 3 attempts.") from last_error
            raise ConnectionError(f"Unable to subscribe to ticks for {symbol} after 3 attempts: {last_error}") from last_error
        raise ConnectionError(f"Unable to subscribe to ticks for {symbol}.")

    async def get_active_symbols(self, contract_types: Optional[list[str]] = None) -> list[Dict[str, Any]]:
        """Fetch currently active public symbols, optionally filtered by contract type."""
        client = DerivClient()
        try:
            await client.connect(self.PUBLIC_WS_URL)
            payload: Dict[str, Any] = {"active_symbols": "brief"}
            if contract_types:
                payload["contract_type"] = contract_types
            response = await client.send_request(payload)
            if "error" in response:
                raise Exception(response["error"].get("message", "Active symbols request failed"))
            symbols = response.get("active_symbols", [])
            return symbols if isinstance(symbols, list) else []
        finally:
            await client.disconnect()

    async def unsubscribe_ticks(self, symbol: str):
        response = await self.send_request({"forget_all": "ticks"})
        self.tick_callbacks.clear()
        return response

    async def _request_proposal_with_minimum_retry(
        self,
        proposal_params: Dict[str, Any],
        requested_amount: Decimal,
    ) -> tuple[Dict[str, Any], Decimal]:
        """Request a proposal and recover cleanly from Deriv minimum-stake errors.

        Loss-cycle recovery can legitimately calculate a stake below the market's
        minimum when the outstanding loss is spread over many target wins. Deriv
        rejects that proposal before purchase. If the response tells us the
        required minimum, retry once at that exact minimum and return the effective
        amount so the caller never buys using a stale pre-retry amount.
        """
        response = await self.send_request(proposal_params)
        if "error" not in response:
            return response, requested_amount

        error = response.get("error") or {}
        message = str(error.get("message", ""))
        match = re.search(
            r"(?:at least|minimum(?:\s+stake)?(?:\s+amount)?(?:\s+is)?)\s*\$?\s*(\d+(?:\.\d+)?)",
            message,
            re.IGNORECASE,
        )
        if not match:
            return response, requested_amount

        minimum_amount = Decimal(match.group(1)).quantize(Decimal("0.01"), rounding=ROUND_UP)
        if requested_amount >= minimum_amount:
            return response, requested_amount

        retry_params = dict(proposal_params)
        retry_params["amount"] = float(minimum_amount)
        logger.warning(
            "Deriv minimum stake adjusted | requested=%s | minimum=%s | retrying proposal",
            f"{requested_amount:.2f}",
            f"{minimum_amount:.2f}",
        )
        retry_response = await self.send_request(retry_params)
        return retry_response, minimum_amount

    async def buy_contract(
        self,
        symbol: str,
        contract_type: str,
        amount: float,
        duration: int = 1,
        duration_unit: str = "t",
        barrier: Optional[int] = None,
        currency: str = "USD",
        target_profit: Optional[float] = None,
        max_amount: Optional[float] = None,
        _proposal_retry_attempt: int = 0
    ) -> Dict[str, Any]:
        """
        Buy a contract from a live proposal.

        For loss-cycle recovery, target_profit is a minimum desired winning
        profit. Deriv can change payout between proposal requests, so the
        sizing loop re-quotes after resizing and only buys from the final live
        proposal. This avoids using an obsolete payout percentage.
        """
        requested_amount = Decimal(str(amount)).quantize(
            Decimal("0.01"),
            rounding=ROUND_HALF_UP
        )
        if requested_amount < Decimal("0.01"):
            raise ValueError("Trade amount must be at least 0.01.")

        target_profit_decimal = None
        if target_profit is not None and float(target_profit) > 0:
            target_profit_decimal = Decimal(str(target_profit)).quantize(
                Decimal("0.01"),
                rounding=ROUND_HALF_UP
            )

        def build_proposal(amount_decimal: Decimal) -> Dict[str, Any]:
            params: Dict[str, Any] = {
                "proposal": 1,
                "amount": float(amount_decimal),
                "basis": "stake",
                "contract_type": contract_type,
                "currency": currency,
                "duration": int(duration),
                "duration_unit": duration_unit,
                "underlying_symbol": symbol
            }
            if barrier is not None:
                params["barrier"] = str(barrier)
            return params

        proposal_params = build_proposal(requested_amount)
        proposal_response, normalized_amount = await self._request_proposal_with_minimum_retry(
            proposal_params, requested_amount
        )
        if "error" in proposal_response:
            raise Exception(
                proposal_response["error"].get("message", "Contract proposal failed")
            )

        proposal = proposal_response.get("proposal") or {}
        proposal_id = proposal.get("id")
        ask_price_raw = proposal.get("ask_price")
        if not proposal_id or ask_price_raw is None:
            raise Exception("Deriv returned an incomplete contract proposal.")

        recovery_target_capped = False
        recovery_required_amount: Optional[Decimal] = None
        if target_profit_decimal is not None:
            for _ in range(3):
                try:
                    ask_price_decimal = Decimal(str(ask_price_raw))
                    payout_raw = proposal.get("payout")
                    if payout_raw is None:
                        break
                    payout_decimal = Decimal(str(payout_raw))
                    quoted_profit = payout_decimal - ask_price_decimal
                    profit_rate = quoted_profit / ask_price_decimal if ask_price_decimal > 0 else Decimal("0")
                except (TypeError, ValueError, ArithmeticError):
                    break

                if profit_rate <= 0:
                    logger.warning(
                        "Recovery target sizing skipped: proposal payout did not exceed ask_price."
                    )
                    break

                calculated_amount = (target_profit_decimal / profit_rate).quantize(
                    Decimal("0.01"),
                    rounding=ROUND_UP
                )
                # Recovery target_profit is a minimum profit requirement. Never
                # reduce the configured Martingale/loss-cycle stake merely
                # because the live payout can recover the target with less.
                calculated_amount = max(calculated_amount, requested_amount)
                recovery_required_amount = calculated_amount
                if max_amount is not None:
                    max_amount_decimal = Decimal(str(max_amount)).quantize(
                        Decimal("0.01"), rounding=ROUND_DOWN
                    )
                    if calculated_amount > max_amount_decimal:
                        recovery_target_capped = True
                        logger.warning(
                            "Recovery target exceeds configured max stake | target_profit=%s | "
                            "required_stake=%s | max_stake=%s. Buying at max stake and continuing "
                            "recovery across subsequent wins.",
                            f"{target_profit_decimal:.2f}",
                            f"{calculated_amount:.2f}",
                            f"{max_amount_decimal:.2f}",
                        )
                        calculated_amount = max_amount_decimal
                    else:
                        recovery_target_capped = False
                    # Use the cap only when the live quote requires more;
                    # otherwise preserve the calculated stake.
                calculated_amount = max(Decimal("0.01"), calculated_amount)

                logger.info(
                    "Recovery proposal quote | target_profit=%s | ask_price=%s | payout=%s | "
                    "profit_rate=%.6f | required_stake=%s",
                    f"{target_profit_decimal:.2f}",
                    str(ask_price_raw),
                    str(proposal.get("payout")),
                    float(profit_rate),
                    f"{calculated_amount:.2f}"
                )

                if calculated_amount == normalized_amount:
                    break

                normalized_amount = calculated_amount
                proposal_params = build_proposal(normalized_amount)
                proposal_response, normalized_amount = await self._request_proposal_with_minimum_retry(
                    proposal_params, normalized_amount
                )
                if "error" in proposal_response:
                    raise Exception(
                        proposal_response["error"].get("message", "Recovery proposal failed")
                    )
                proposal = proposal_response.get("proposal") or {}
                proposal_id = proposal.get("id")
                ask_price_raw = proposal.get("ask_price")
                if not proposal_id or ask_price_raw is None:
                    raise Exception("Deriv returned an incomplete recovery proposal.")

        # Do not call balance here. The authenticated client subscribes to
        # balance updates once, and every extra balance request consumes the
        # account's much smaller balance/statement rate-limit budget. Deriv's
        # buy response is authoritative for insufficient funds.
        buy_price_decimal = Decimal(str(ask_price_raw)).quantize(
            Decimal("0.01"),
            rounding=ROUND_UP
        )
        if buy_price_decimal < Decimal("0.01"):
            raise Exception("Deriv returned an invalid proposal ask_price.")

        buy_price_text = f"{buy_price_decimal:.2f}"

        logger.info(
            "Buying proposal %s | stake=%s | ask_price=%s | buy_price=%s%s",
            proposal_id,
            f"{normalized_amount:.2f}",
            str(ask_price_raw),
            buy_price_text,
            f" | target_profit={target_profit_decimal:.2f}" if target_profit_decimal is not None else ""
        )

        response = await self.send_request(
            {"buy": str(proposal_id), "price": float(buy_price_decimal)},
            exact_numeric_fields={"price": buy_price_text}
        )
        if "error" in response:
            error = response.get("error") or {}
            error_message = str(error.get("message", "Contract purchase failed"))
            if "unknown contract proposal" in error_message.lower() and _proposal_retry_attempt < 2:
                logger.warning(
                    "Deriv rejected a stale/unknown proposal; fetching a fresh proposal "
                    "and retrying purchase (attempt %d/2).",
                    _proposal_retry_attempt + 1,
                )
                return await self.buy_contract(
                    symbol=symbol,
                    contract_type=contract_type,
                    amount=float(normalized_amount),
                    duration=duration,
                    duration_unit=duration_unit,
                    barrier=barrier,
                    currency=currency,
                    target_profit=float(target_profit_decimal) if target_profit_decimal is not None else None,
                    max_amount=max_amount,
                    _proposal_retry_attempt=_proposal_retry_attempt + 1,
                )
            raise Exception(error_message)

        buy = response.get("buy", {})
        if isinstance(buy, dict):
            buy.setdefault("stake", float(normalized_amount))
            buy.setdefault("buy_price", float(buy_price_decimal))
            if recovery_target_capped and recovery_required_amount is not None:
                buy["recovery_target_capped"] = True
                buy["recovery_required_stake"] = float(recovery_required_amount)
                buy["recovery_target_profit"] = float(target_profit_decimal)
        return buy

    async def subscribe_contract(self, contract_id: int, callback: Callable):
        if contract_id not in self.contract_callbacks:
            self.contract_callbacks[contract_id] = []
        if callback not in self.contract_callbacks[contract_id]:
            self.contract_callbacks[contract_id].append(callback)
        response = await self.send_request({"proposal_open_contract": 1, "contract_id": contract_id, "subscribe": 1})
        if "error" in response:
            raise Exception(response["error"].get("message", "Contract subscription failed"))
        return response

    async def get_contract_status(self, contract_id: int) -> Dict[str, Any]:
        """Fetch a one-shot snapshot without creating another subscription."""
        response = await self.send_request({
            "proposal_open_contract": 1,
            "contract_id": int(contract_id),
        })
        if "error" in response:
            error = response.get("error") or {}
            raise RuntimeError(
                error.get("message", "Contract status request failed")
            )
        contract = response.get("proposal_open_contract")
        if not isinstance(contract, dict) or not contract:
            raise RuntimeError(
                f"Deriv returned no proposal_open_contract snapshot for contract {contract_id}."
            )
        return contract

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
            err = res["error"]
            err_msg = err.get("message", "")
            err_code = err.get("code", "")
            if "already subscribed" in err_msg.lower() or err_code == "AlreadySubscribed":
                logger.info("Balance request noted existing balance subscription.")
                return res.get("balance", {})
            raise Exception(err_msg or "Failed to fetch balance")
        return res.get("balance", {})
