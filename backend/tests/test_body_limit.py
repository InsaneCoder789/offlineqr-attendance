from __future__ import annotations

import unittest

from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from backend.app.security import BodySizeLimitMiddleware


def _app(limit: int) -> TestClient:
    app = FastAPI()

    @app.post("/echo")
    async def echo(request: Request) -> dict:
        return {"bytes": len(await request.body())}

    app.add_middleware(BodySizeLimitMiddleware, max_bytes=limit)
    return TestClient(app)


class BodySizeLimitTest(unittest.TestCase):
    def test_body_within_limit_is_served(self) -> None:
        response = _app(1000).post("/echo", content=b"x" * 900)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"bytes": 900})

    def test_declared_oversized_body_is_rejected_with_413(self) -> None:
        response = _app(1000).post("/echo", content=b"x" * 5000)
        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.json()["error"]["code"], "PAYLOAD_TOO_LARGE")

    def test_chunked_oversized_body_is_rejected_without_content_length(self) -> None:
        def chunks():
            for _ in range(10):
                yield b"y" * 300

        response = _app(1000).post("/echo", content=chunks())
        self.assertEqual(response.status_code, 413)

    def test_invalid_content_length_is_rejected(self) -> None:
        response = _app(1000).post("/echo", content=b"x", headers={"content-length": "abc"})
        self.assertIn(response.status_code, (400, 413))


if __name__ == "__main__":
    unittest.main()
