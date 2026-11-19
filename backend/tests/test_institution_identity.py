import os
import unittest
from unittest.mock import patch

from backend.app.institution_identity import institution_email_allowed


class InstitutionIdentityPolicyTest(unittest.TestCase):
    def test_configured_domains_are_exact_and_case_insensitive(self):
        with patch.dict(os.environ, {"INSTITUTION_EMAIL_DOMAINS": "example.edu, campus.example.org"}):
            self.assertTrue(institution_email_allowed(" Person@EXAMPLE.EDU "))
            self.assertTrue(institution_email_allowed("person@campus.example.org"))
            for email in ("person@evil-example.edu", "person@example.edu.evil.org", "person@other.edu", "a@@example.edu"):
                self.assertFalse(institution_email_allowed(email))

    def test_empty_allowlist_denies_all_identities(self):
        with patch.dict(os.environ, {"INSTITUTION_EMAIL_DOMAINS": ""}):
            self.assertFalse(institution_email_allowed("person@example.edu"))
