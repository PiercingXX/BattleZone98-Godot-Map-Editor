"""``bzmap editor package`` — install-to-test-mod and pack assembly."""

from __future__ import annotations

import tempfile
from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.save import save_session
from bzmap.editor.session import read_json, session_paths
from bzmap.package.assemble import assemble_pack
from bzmap.package.install import install_map, set_mod_enabled


def package_session(session_dir, mode, *, game_root=None, test_id=None, out_dir=None):
    """``mode`` is ``install`` or ``pack``."""
    paths = session_paths(session_dir)
    if not paths["manifest"].is_file():
        raise EditorError("no_session", f"no manifest.json in {session_dir}", path=session_dir)
    manifest = read_json(paths["manifest"])
    stem = manifest.get("stem") or "map"

    staging = Path(tempfile.mkdtemp(prefix="bzmap-package-"))
    saved = save_session(session_dir, staging, stem=stem)
    try:
        from bzmap.editor.render_cmd import render_session
        render_session(session_dir, staging)
    except Exception as exc:  # noqa: BLE001 — pack still ships without a pretty thumb
        saved.setdefault("warnings", []).append(f"thumbnail skipped: {exc}")

    if mode == "install":
        if not game_root:
            raise EditorError("no_game", "package --mode install needs --game-root")
        tid = test_id or f"bzeditor-{stem}"
        files = [p for p in staging.iterdir() if p.is_file()]
        dest = install_map(game_root, tid, files)
        previous = set_mod_enabled(game_root, tid)
        return {
            "ok": True,
            "mode": "install",
            "dest": str(dest.resolve()),
            "test_id": tid,
            "previous_mod": previous.decode("ascii", "replace") if isinstance(previous, (bytes, bytearray)) else previous,
            "files": saved.get("files", []),
        }

    if mode == "pack":
        if not out_dir:
            raise EditorError("no_out", "package --mode pack needs --out")
        dest = assemble_pack(staging, Path(out_dir))
        return {
            "ok": True,
            "mode": "pack",
            "dest": str(Path(dest).resolve()),
            "files": saved.get("files", []),
        }

    raise EditorError("bad_mode", f"unknown package mode {mode!r}", hint="use install or pack")
