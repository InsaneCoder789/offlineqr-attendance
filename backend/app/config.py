from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    database_url: str
    app_env: str
    dev_student_id: str
    dev_faculty_id: str
    institution_signing_seed_b64url: str

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
    )
