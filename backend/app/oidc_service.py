from __future__ import annotations

from functools import lru_cache

import jwt
from jwt import PyJWKClient

from .config import get_settings
from .errors import ApiError
from .institution_identity import institution_email_allowed


@lru_cache(maxsize=1)
def _jwks_client() -> PyJWKClient:
    settings = get_settings()
    if not settings.oidc_jwks_url:
        raise ApiError("OIDC_UNAVAILABLE", "Institutional sign-in is not configured.", 503)
    return PyJWKClient(settings.oidc_jwks_url, cache_keys=True, lifespan=300, timeout=5)


def verify_oidc_identity(id_token: str) -> dict[str, str]:
    if not 32 <= len(id_token) <= 16_384:
        raise ApiError("OIDC_TOKEN_INVALID", "Institutional identity token is invalid.", 401)
    settings = get_settings()
    if not settings.oidc_issuer or not settings.oidc_client_id:
        raise ApiError("OIDC_UNAVAILABLE", "Institutional sign-in is not configured.", 503)
    try:
        signing_key = _jwks_client().get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            signing_key.key,
            algorithms=["RS256", "ES256"],
            audience=settings.oidc_client_id,
            issuer=settings.oidc_issuer,
            options={"require": ["exp", "iat", "iss", "aud", "sub", "email"]},
        )
    except jwt.PyJWTError as exc:
        raise ApiError("OIDC_TOKEN_INVALID", "Institutional identity token could not be verified.", 401) from exc
    email = str(claims.get("email", "")).strip().lower()
    if claims.get("email_verified") is not True or not institution_email_allowed(email):
        raise ApiError("OIDC_IDENTITY_NOT_ALLOWED", "A verified institutional identity is required.", 403)
    return {"subject": str(claims["sub"]), "email": email}
