"""``bzmap editor validate`` — run the existing validators on a session."""

from __future__ import annotations

import tempfile
from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.save import _objects_dirty, save_session
from bzmap.editor.session import read_json, session_paths
from bzmap.validate.formats import validate_map


def _finding(problem, index):
    text = str(problem)
    severity = "error"
    if text.startswith("[warning]"):
        severity = "warning"
        text = text[len("[warning]"):].strip()
    elif text.startswith("[error]"):
        text = text[len("[error]"):].strip()
    return {
        "id": f"V{index}",
        "severity": severity,
        "title": text[:96],
        "detail": text,
        "world_pos": None,
        "object_id": None,
        "variant": None,
    }


def _session_is_clean(dirty):
    if dirty.get("terrain") or dirty.get("materials") or dirty.get("features"):
        return False
    if dirty.get("meta"):
        return False
    return not _objects_dirty(dirty)


def validate_session(session_dir, *, tier="1,2", game_root=None):
    """Validate the session. Materializes to a temp dir when anything is dirty."""
    paths = session_paths(session_dir)
    if not paths["manifest"].is_file():
        raise EditorError("no_session", f"no manifest.json in {session_dir}", path=session_dir)

    dirty = read_json(paths["dirty"]) if paths["dirty"].is_file() else {}
    # Unused today: tiers other than 1 still go through validate_map (Tier 1).
    # Tier 2 layout validators need a LayoutGraph the session does not have.
    _ = tier

    if _session_is_clean(dirty) and paths["source"].is_dir():
        target = paths["source"]
    else:
        tmp = Path(tempfile.mkdtemp(prefix="bzmap-validate-"))
        save_session(session_dir, tmp)
        target = tmp

    problems = validate_map(target, reference_dir=game_root)
    findings = [_finding(p, i + 1) for i, p in enumerate(problems)]
    errors = [f for f in findings if f["severity"] == "error"]
    payload = {
        "ok": len(errors) == 0,
        "findings": findings,
    }
    # Persist for the editor console.
    from bzmap.editor.session import write_json
    write_json(paths["report"], payload)
    return payload
