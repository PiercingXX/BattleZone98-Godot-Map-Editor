"""``bzmap editor render`` — north-up thumbnail / overview."""

from __future__ import annotations

from pathlib import Path

from bzmap.editor.errors import EditorError
from bzmap.editor.session import (
    read_json,
    reconstruct_heightmap,
    session_paths,
)
from bzmap.render.preview import Preview
from bzmap.render.thumbnail import write_thumbnail


def render_session(session_dir, out_dir, debug=False):
    """Write ``<stem>.png`` / ``<stem>.BMP`` and ``preview.png`` to ``out_dir``."""
    paths = session_paths(session_dir)
    if not paths["manifest"].is_file():
        raise EditorError("no_session", f"no manifest.json in {session_dir}", path=session_dir)
    manifest = read_json(paths["manifest"])
    header = read_json(paths["hg2_header"]) if paths["hg2_header"].is_file() else None
    if header is None:
        raise EditorError("no_terrain", "session has no residue hg2 header")
    heightmap = reconstruct_heightmap(paths, header)
    preview = Preview(heightmap, size=(512, 512))

    objects = {}
    if paths["objects"].is_file():
        objects = read_json(paths["objects"])
    points = []
    for records in objects.values():
        if not isinstance(records, list):
            continue
        for rec in records:
            if isinstance(rec, dict):
                points.append((float(rec.get("x", 0.0)), float(rec.get("z", 0.0))))
    if points:
        preview.draw_points(points, color=(255, 220, 40), radius=2)

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = manifest.get("stem") or "map"
    png = out_dir / f"{stem}.png"
    bmp = out_dir / f"{stem}.BMP"
    write_thumbnail(preview.image, png, bmp, size=(512, 512))
    overview = out_dir / "preview.png"
    preview.image.save(overview, format="PNG")
    _ = debug
    return {
        "ok": True,
        "png": str(png.resolve()),
        "bmp": str(bmp.resolve()),
        "preview": str(overview.resolve()),
        "north_up": True,
    }
