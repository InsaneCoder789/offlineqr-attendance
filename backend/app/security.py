from __future__ import annotations

import secrets
from collections import defaultdict, deque
from time import monotonic
from uuid import uuid4

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware

from .config import get_settings
from .errors import ApiError


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("x-correlation-id") or str(uuid4())
        request.state.correlation_id = correlation_id
        response: Response = await call_next(request)
        response.headers["X-Correlation-Id"] = correlation_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(self), geolocation=(), microphone=()"
        if not get_settings().development_enabled:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response


class SlidingWindowRateLimitMiddleware(BaseHTTPMiddleware):
    """Small dependency-free guard; production deployments should replace this with Redis."""

    protected_prefixes = ("/api/v1/attendance", "/api/v1/devices", "/api/v1/faculty/auth")

    def __init__(self, app, limit: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)

    async def dispatch(self, request: Request, call_next):
        if not request.url.path.startswith(self.protected_prefixes):
            return await call_next(request)
        now = monotonic()
        source = request.client.host if request.client else "unknown"
        group = request.url.path.split("/")[3] if len(request.url.path.split("/")) > 3 else "api"
        events = self._events[f"{source}:{group}"]
        while events and events[0] <= now - self.window_seconds:
            events.popleft()
        if len(events) >= self.limit:
            return JSONResponse(
                status_code=429,
                content={"error": {"code": "RATE_LIMITED", "message": "Too many requests. Try again shortly."}},
                headers={"Retry-After": str(self.window_seconds)},
            )
        events.append(now)
        return await call_next(request)


def require_ict_approval(request: Request, *, strict: bool = False) -> None:
    settings = get_settings()
    supplied = request.headers.get("x-ict-approval-key", "")
    if settings.development_enabled and not strict and not supplied:
        return
    if not secrets.compare_digest(supplied, settings.ict_admin_approval_key):
        raise ApiError("ICT_APPROVAL_REQUIRED", "An ICT approval credential is required.", 403)
