from dataclasses import dataclass
import os
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


@dataclass(frozen=True)
class Settings:
    database_url: str
    app_env: str
    dev_student_id: str
    dev_faculty_id: str
    institution_signing_seed_b64url: str
    redis_url: str
    redis_required: bool
    faculty_session_ttl_seconds: int
    student_session_ttl_seconds: int
    faculty_cookie_secure: bool
    cors_allowed_origins: tuple[str, ...]
    institution_timezone: str
    oidc_issuer: str
    oidc_client_id: str
    oidc_client_secret: str
    oidc_jwks_url: str
    password_auth_enabled: bool
    device_attestation_required: bool
    device_attestation_verifier_url: str
    device_attestation_verifier_token: str

    @property
    def development_enabled(self) -> bool:
        return self.app_env == "development"


def get_settings() -> Settings:
    configured_origins = tuple(
        origin.strip()
        for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    )
    return Settings(
        database_url=os.environ.get(
            "DATABASE_URL",
            "postgresql://localhost/kiit_attendance_goal02",
        ),
        app_env=os.environ.get("APP_ENV", "development"),
        dev_student_id=os.environ.get(
            "DEV_STUDENT_ID",
            "50000000-0000-4000-8000-000000000001",
        ),
        dev_faculty_id=os.environ.get(
            "DEV_FACULTY_ID",
            "40000000-0000-4000-8000-000000000001",
        ),
        institution_signing_seed_b64url=os.environ.get(
            "INSTITUTION_SIGNING_SEED_B64URL",
            "ERERERERERERERERERERERERERERERERERERERERERE",
        ),
        redis_url=os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0"),
        redis_required=os.environ.get("REDIS_REQUIRED", "").lower() in {"1", "true", "yes"}
        or os.environ.get("APP_ENV", "development") != "development",
        faculty_session_ttl_seconds=int(os.environ.get("FACULTY_SESSION_TTL_SECONDS", "28800")),
        student_session_ttl_seconds=int(os.environ.get("STUDENT_SESSION_TTL_SECONDS", "43200")),
        faculty_cookie_secure=os.environ.get("FACULTY_COOKIE_SECURE", "").lower() in {"1", "true", "yes"}
        or os.environ.get("APP_ENV", "development") != "development",
        cors_allowed_origins=configured_origins,
        institution_timezone=os.environ.get("INSTITUTION_TIMEZONE", "Asia/Kolkata"),
        oidc_issuer=os.environ.get("OIDC_ISSUER", ""),
        oidc_client_id=os.environ.get("OIDC_CLIENT_ID", ""),
        oidc_client_secret=os.environ.get("OIDC_CLIENT_SECRET", ""),
        oidc_jwks_url=os.environ.get("OIDC_JWKS_URL", ""),
        password_auth_enabled=os.environ.get(
            "PASSWORD_AUTH_ENABLED",
            "true" if os.environ.get("APP_ENV", "development") == "development" else "false",
        ).lower() in {"1", "true", "yes"},
        device_attestation_required=os.environ.get("DEVICE_ATTESTATION_REQUIRED", "").lower()
        in {"1", "true", "yes"},
        device_attestation_verifier_url=os.environ.get("DEVICE_ATTESTATION_VERIFIER_URL", ""),
        device_attestation_verifier_token=os.environ.get("DEVICE_ATTESTATION_VERIFIER_TOKEN", ""),
    )


def validate_production_settings() -> None:
    """Fail closed when a production deployment still has demo credentials."""
    settings = get_settings()
    if settings.development_enabled:
        return
    if settings.institution_signing_seed_b64url == "ERERERERERERERERERERERERERERERERERERERERERE":
        raise RuntimeError("INSTITUTION_SIGNING_SEED_B64URL must be set outside development")
    if not settings.redis_required:
        raise RuntimeError("REDIS_REQUIRED must remain enabled outside development")
    if not settings.redis_url.startswith(("redis://", "rediss://")):
        raise RuntimeError("REDIS_URL must use redis:// or rediss:// outside development")
    if not settings.faculty_cookie_secure:
        raise RuntimeError("FACULTY_COOKIE_SECURE must remain enabled outside development")
    if not settings.cors_allowed_origins:
        raise RuntimeError("CORS_ALLOWED_ORIGINS must list the deployed faculty portal origins outside development")
    try:
        ZoneInfo(settings.institution_timezone)
    except ZoneInfoNotFoundError as exc:
        raise RuntimeError("INSTITUTION_TIMEZONE must be a valid IANA timezone") from exc
    if not settings.oidc_issuer or not settings.oidc_client_id or not settings.oidc_client_secret or not settings.oidc_jwks_url:
        raise RuntimeError("OIDC issuer, client ID, client secret, and JWKS URL are required outside development")
    if not settings.oidc_issuer.startswith("https://"):
        raise RuntimeError("OIDC_ISSUER must use HTTPS outside development")
    if not settings.device_attestation_required:
        raise RuntimeError("DEVICE_ATTESTATION_REQUIRED must remain enabled outside development")
    if not settings.device_attestation_verifier_url.startswith("https://"):
        raise RuntimeError("DEVICE_ATTESTATION_VERIFIER_URL must use HTTPS outside development")
    if len(settings.device_attestation_verifier_token) < 32:
        raise RuntimeError("DEVICE_ATTESTATION_VERIFIER_TOKEN must be a strong server credential")
    if settings.password_auth_enabled:
        raise RuntimeError("PASSWORD_AUTH_ENABLED must be disabled outside development")
