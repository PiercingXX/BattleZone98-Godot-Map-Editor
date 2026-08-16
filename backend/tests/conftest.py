"""Shared pytest fixtures and path setup for the test suite.

The repo is not installed as a package during normal development; tests run
straight from the checkout via ``.venv/bin/pytest``.  Add the repository root
to ``sys.path`` so ``bzmap`` is importable without an editable install.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))