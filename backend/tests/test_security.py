from __future__ import annotations

import unittest

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


if __name__ == "__main__":
    unittest.main()
