"""Editor interchange: session buffers + JSON verbs (map-editor docs/02).

The Godot editor never parses a game file. This package is the only place
``bzmap`` speaks that contract. ``contract_version`` is 1; bump it on any
breaking change to the session directory or the verb responses.
"""

from __future__ import annotations

CONTRACT_VERSION = 1

__all__ = ["CONTRACT_VERSION"]
