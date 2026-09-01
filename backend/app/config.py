from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    database_url: str
    app_env: str
    dev_student_id: str
    dev_faculty_id: str
    institution_signing_seed_b64url: str
    ict_admin_approval_key: str

    @property
    def development_enabled(self) -> bool:
        return self.app_env == "development"


def get_settings() -> Settings:
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
        ict_admin_approval_key=os.environ.get(
            "ICT_ADMIN_APPROVAL_KEY",
            "development-ict-approval-key-change-me",
        ),
    )


def validate_production_settings() -> None:
    """Fail closed when a production deployment still has demo credentials."""
    settings = get_settings()
    if settings.development_enabled:
        return
    if settings.institution_signing_seed_b64url == "ERERERERERERERERERERERERERERERERERERERERERE":
        raise RuntimeError("INSTITUTION_SIGNING_SEED_B64URL must be set outside development")
    if len(settings.ict_admin_approval_key) < 32:
        raise RuntimeError("ICT_ADMIN_APPROVAL_KEY must be at least 32 characters outside development")
