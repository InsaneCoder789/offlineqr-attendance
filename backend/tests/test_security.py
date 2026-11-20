from __future__ import annotations

import unittest
from unittest import mock

from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.redis_service import RateLimitResult

from starlette.requests import Request

from backend.app.security import RedisRateLimitMiddleware


class SecurityBoundaryTest(unittest.TestCase):
    def test_rate_limit_subject_uses_an_opaque_session_identifier(self) -> None:
        token = "student-secret-session-token"
        request = Request(
            {
                "type": "http",
                "method": "GET",
                "path": "/api/v1/sync/bootstrap",
                "headers": [
                    (b"authorization", f"Bearer {token}".encode("utf-8")),
                ],
                "client": ("192.0.2.10", 443),
            }
        )

        subject = RedisRateLimitMiddleware._subject(request)

        self.assertTrue(subject.startswith("session:"))
        self.assertNotIn(token, subject)

    def test_core_authenticated_routes_are_rate_limited(self) -> None:
        protected = RedisRateLimitMiddleware.protected_prefixes
        for path in (
            "/api/v1/faculty/attendance-sessions",
            "/api/v1/sync/bootstrap",
            "/api/v1/me/attendance",
            "/api/v1/devices/current",
        ):
            self.assertTrue(path.startswith(protected), path)

    def test_per_ip_limit_returns_429_even_when_authorization_varies(self) -> None:
        counters: dict[tuple[str, str], int] = {}

        def fake_consume(scope, subject, *, limit, window_seconds):
            key = (scope, subject)
            counters[key] = counters.get(key, 0) + 1
            return RateLimitResult(allowed=counters[key] <= limit, retry_after_seconds=30)

        client = TestClient(app)
        statuses = []
        with mock.patch("backend.app.security.consume_rate_limit", side_effect=fake_consume):
            # faculty-auth: 120 per credential, 360 per IP. Each request uses a fresh bogus credential.
            for index in range(365):
                response = client.get(
                    "/api/v1/faculty/auth/does-not-exist",
                    headers={"Authorization": f"Bearer rotating-{index}"},
                )
                statuses.append(response.status_code)

        self.assertNotIn(429, statuses[:360])
        self.assertEqual(statuses[360:], [429] * 5)
        self.assertEqual(response.json()["error"]["code"], "RATE_LIMITED")


if __name__ == "__main__":
    unittest.main()
