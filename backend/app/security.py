from __future__ import annotations

import json
import logging
import os
from hashlib import sha256
from time import perf_counter
from uuid import uuid4

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware

from .config import get_settings
from .errors import ApiError
from .redis_service import consume_rate_limit


logger = logging.getLogger("offlineqr.access")


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("x-correlation-id") or str(uuid4())
        request.state.correlation_id = correlation_id
        started = perf_counter()
        response: Response = await call_next(request)
        elapsed_ms = round((perf_counter() - started) * 1000, 1)
        logger.info(
            "request_completed",
            extra={"correlation_id": correlation_id, "method": request.method, "path": request.url.path, "status": response.status_code, "duration_ms": elapsed_ms},
        )
        response.headers["X-Correlation-Id"] = correlation_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(self), geolocation=(), microphone=()"
        if not get_settings().development_enabled:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response


class RedisRateLimitMiddleware(BaseHTTPMiddleware):
    """Distributed request boundary shared by every API worker."""

    protected_prefixes = (
        "/api/v1/attendance",
        "/api/v1/devices",
        "/api/v1/faculty",
        "/api/v1/student/auth",
        "/api/v1/admin",
        "/api/v1/sync",
        "/api/v1/me",
    )

    async def dispatch(self, request: Request, call_next):
        if not request.url.path.startswith(self.protected_prefixes):
            return await call_next(request)
        source = self._subject(request)
        path = request.url.path
        if path.startswith("/api/v1/faculty/auth"):
            scope, limit = "faculty-auth", 120
        elif path.startswith("/api/v1/student/auth"):
            scope, limit = "student-auth", 120
        elif path.startswith("/api/v1/attendance"):
            scope, limit = "attendance", ATTENDANCE_RATE_PER_MIN
        else:
            scope, limit = path.split("/")[3], 180
        try:
            if scope in {"faculty-auth", "student-auth", "attendance"}:
                # Per-IP ceiling: rotating a bogus credential must not mint a fresh bucket.
                ip_limit = ATTENDANCE_IP_RATE_PER_MIN if scope == "attendance" else limit * 3
                ip_result = consume_rate_limit(f"{scope}-ip", f"ip:{self._client_ip(request)}", limit=ip_limit, window_seconds=60)
                if not ip_result.allowed:
                    return JSONResponse(
                        status_code=429,
                        content={"error": {"code": "RATE_LIMITED", "message": "Too many requests. Try again shortly."}},
                        headers={"Retry-After": str(ip_result.retry_after_seconds)},
                    )
            result = consume_rate_limit(scope, source, limit=limit, window_seconds=60)
        except ApiError as exc:
            return JSONResponse(
                status_code=exc.status_code,
                content={"error": {"code": exc.code, "message": exc.message}},
            )
        if not result.allowed:
            return JSONResponse(
                status_code=429,
                content={"error": {"code": "RATE_LIMITED", "message": "Too many requests. Try again shortly."}},
                headers={"Retry-After": str(result.retry_after_seconds)},
            )
        return await call_next(request)

    @staticmethod
    def _subject(request: Request) -> str:
        authorization = request.headers.get("authorization", "")[:512]
        faculty_session = request.cookies.get("offlineqr_faculty_session", "")[:256]
        credential = authorization or faculty_session
        if credential:
            return f"session:{sha256(credential.encode('utf-8')).hexdigest()}"
        return f"ip:{RedisRateLimitMiddleware._client_ip(request)}"

    @staticmethod
    def _client_ip(request: Request) -> str:
        """Peer address, or the Nth-from-right X-Forwarded-For entry when proxies are trusted."""
        hops = get_settings().trusted_proxy_hops
        if hops > 0:
            parts = [p.strip() for p in request.headers.get("x-forwarded-for", "").split(",") if p.strip()]
            if len(parts) >= hops:
                return parts[-hops][:64]
        return request.client.host if request.client else "unknown"


# Attendance proofs are device-signed and arrive in class-start bursts, often from one campus NAT address.
# Defaults are conservative; set both to the expected students-per-address before launch (measured: with
# 600/3000 a single NAT address drains only ~14 proofs/s, i.e. 37 minutes for 30,000 students).
ATTENDANCE_RATE_PER_MIN = int(os.environ.get("ATTENDANCE_RATE_PER_MIN", "600"))
ATTENDANCE_IP_RATE_PER_MIN = int(os.environ.get("ATTENDANCE_IP_RATE_PER_MIN", "3000"))
MAX_REQUEST_BODY_BYTES = int(os.environ.get("MAX_REQUEST_BODY_BYTES", str(1024 * 1024)))


class _BodyTooLarge(Exception):
    pass


class BodySizeLimitMiddleware:
    """Reject oversized request bodies before they are buffered (largest legitimate call is a 50-proof batch, ~200 KB)."""

    def __init__(self, app, max_bytes: int | None = None) -> None:
        self.app = app
        self.max_bytes = max_bytes if max_bytes is not None else MAX_REQUEST_BODY_BYTES

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        declared = dict(scope["headers"]).get(b"content-length")
        try:
            too_big = declared is not None and int(declared) > self.max_bytes
        except ValueError:
            too_big = True
        if too_big:
            await self._reject(send)
            return
        received = 0
        started = False

        async def limited_receive():
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise _BodyTooLarge
            return message

        async def tracking_send(message):
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except _BodyTooLarge:
            if not started:
                await self._reject(send)

    @staticmethod
    async def _reject(send) -> None:
        body = json.dumps({"error": {"code": "PAYLOAD_TOO_LARGE", "message": "Request body is too large."}}).encode()
        await send({"type": "http.response.start", "status": 413, "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
        await send({"type": "http.response.body", "body": body})
