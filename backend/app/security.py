from __future__ import annotations

from hashlib import sha256
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
            scope, limit = "attendance", 600
        else:
            scope, limit = path.split("/")[3], 180
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

    @staticmethod
    def _subject(request: Request) -> str:
        authorization = request.headers.get("authorization", "")[:512]
        faculty_session = request.cookies.get("kiit_faculty_session", "")[:256]
        credential = authorization or faculty_session
        if credential:
            return f"session:{sha256(credential.encode('utf-8')).hexdigest()}"
        source_ip = request.client.host if request.client else "unknown"
        return f"ip:{source_ip}"
