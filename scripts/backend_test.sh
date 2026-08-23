#!/usr/bin/env bash
set -euo pipefail

PYTHONPATH=. .venv/bin/python -m unittest discover -s backend/tests -p 'test_*.py'

