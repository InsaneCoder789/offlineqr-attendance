"""Compatibility entry point for the branded commercial PDF generator."""

import runpy
from pathlib import Path

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("create_branded_commercial_pdf.py")), run_name="__main__")
