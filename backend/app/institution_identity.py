"""Deployment-level identity policy; account membership is enforced in the DB."""

import os
import re


def institution_email_allowed(value: str) -> bool:
    email = value.strip().lower()
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        return False
    configured = os.environ.get("INSTITUTION_EMAIL_DOMAINS", "example.edu")
    domains = {domain.strip().lower() for domain in configured.split(",") if domain.strip()}
    return email.rsplit("@", 1)[1] in domains
