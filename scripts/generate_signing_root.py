from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re

from nacl.signing import SigningKey


KEY_ID_PATTERN = re.compile(r"^institution-root-[0-9]{4}-[0-9]{2}$")


def encoded(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a versioned institution signing root without printing its seed."
    )
    parser.add_argument("key_id", help="Versioned identifier such as institution-root-2027-01")
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    if not KEY_ID_PATTERN.fullmatch(args.key_id):
        raise SystemExit("key_id must match institution-root-YYYY-NN")

    args.output_directory.mkdir(parents=True, exist_ok=True)
    signing_key = SigningKey.generate()
    secret_path = args.output_directory / f"{args.key_id}.env"
    public_path = args.output_directory / f"{args.key_id}.public.json"
    secret_path.write_text(
        f"INSTITUTION_SIGNING_KEY_ID={args.key_id}\n"
        f"INSTITUTION_SIGNING_SEED_B64URL={encoded(bytes(signing_key))}\n"
    )
    os.chmod(secret_path, 0o600)
    public_path.write_text(
        json.dumps(
            {
                "key_id": args.key_id,
                "algorithm": "Ed25519",
                "public_key": encoded(bytes(signing_key.verify_key)),
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Secret material written with owner-only permissions: {secret_path}")
    print(f"Public trust metadata: {public_path}")


if __name__ == "__main__":
    main()
