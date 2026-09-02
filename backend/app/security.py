from __future__ import annotations

from uuid import uuid4

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware

from .config import get_settings
from .errors import ApiError
from .redis_service import consume_rate_limit


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


class RedisRateLimitMiddleware(BaseHTTPMiddleware):
    """Distributed request boundary shared by every API worker."""

    protected_prefixes = ("/api/v1/attendance", "/api/v1/devices", "/api/v1/faculty/auth", "/api/v1/admin")

    async def dispatch(self, request: Request, call_next):
        if not request.url.path.startswith(self.protected_prefixes):
            return await call_next(request)
        source = request.client.host if request.client else "unknown"
        path = request.url.path
        scope = "faculty-auth" if path.startswith("/api/v1/faculty/auth") else path.split("/")[3]
        limit = 12 if scope == "faculty-auth" else 90
        try:
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
