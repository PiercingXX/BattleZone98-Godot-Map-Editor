"""Stdout JSON emission for ``bzmap editor`` verbs.

stdout is exactly one JSON object. Progress and diagnostics go to stderr.
"""

from __future__ import annotations

import json
import sys


def emit(payload, *, exit_code=0):
    """Write ``payload`` as one JSON object to stdout and return ``exit_code``."""
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2))
    sys.stdout.write("\n")
    sys.stdout.flush()
    return exit_code
