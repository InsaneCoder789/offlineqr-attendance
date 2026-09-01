from fastapi import Request
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(self, code: str, message: str, status_code: int = 400) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code


async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    correlation_id = getattr(request.state, "correlation_id", None) or request.headers.get("x-correlation-id", "development")
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "correlation_id": correlation_id,
            }
        },
    )
