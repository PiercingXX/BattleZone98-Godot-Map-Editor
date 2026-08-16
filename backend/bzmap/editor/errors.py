"""Structured editor-bridge errors (map-editor docs/02 §5)."""

from __future__ import annotations


class EditorError(Exception):
    """A verb failed in a way the editor can show and branch on."""

    def __init__(self, code, message, hint=None, path=None):
        super().__init__(message)
        self.code = str(code)
        self.message = str(message)
        self.hint = hint
        self.path = str(path) if path is not None else None

    def as_dict(self):
        error = {"code": self.code, "message": self.message}
        if self.hint:
            error["hint"] = self.hint
        if self.path:
            error["path"] = self.path
        return {"ok": False, "error": error}
