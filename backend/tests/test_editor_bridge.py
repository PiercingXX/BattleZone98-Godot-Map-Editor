"""Tests for ``bzmap editor`` (map-editor docs/02, Phase 1)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bzmap.editor.discover import discover, is_game_install, parse_libraryfolders_vdf
from bzmap.editor.open import open_map
from bzmap.editor.save import save_session
from bzmap.editor.worlds import worlds_from_game
from bzmap.cli import main as bzmap_main

_DEFAULT_PACK = (
    Path.home()
    / ".steam/steam/steamapps/workshop/content/301650/3406347034"
)
_DEFAULT_GAME = (
    Path.home()
    / ".local/share/Steam/steamapps/common/Battlezone 98 Redux"
)


def _pack_dir() -> Path:
    import os
    env = os.environ.get("BZP_PACK_DIR")
    return Path(env) if env else _DEFAULT_PACK


@pytest.fixture(scope="module")
def pack_dir() -> Path:
    d = _pack_dir()
    if not d.is_dir():
        pytest.skip(f"BZP pack not found at {d}")
    return d


@pytest.fixture(scope="module")
def game_root() -> Path:
    if not is_game_install(_DEFAULT_GAME):
        found = discover()
        for item in found["installs"]:
            if item.get("kind") == "game":
                return Path(item["path"])
        pytest.skip("no BZ98R install")
    return _DEFAULT_GAME


def _hg2_files(pack: Path):
    return [p for p in pack.iterdir() if p.is_file() and p.suffix.lower() == ".hg2"]


def test_parse_libraryfolders_vdf_tight_and_spaced():
    text = (
        '"libraryfolders"\n{\n'
        '"0"\n{\n'
        '"path""/home/x/.local/share/Steam"\n'
        '}\n'
        '"1"\n{\n'
        '"path"\t\t"/mnt/games"\n'
        '}\n}\n'
    )
    paths = parse_libraryfolders_vdf(text)
    assert [str(p) for p in paths] == [
        "/home/x/.local/share/Steam",
        "/mnt/games",
    ]


def test_probe_finds_linux_install(game_root):
    found = discover()
    games = [i for i in found["installs"] if i.get("kind") == "game"]
    assert games, found
    assert any(is_game_install(i["path"]) for i in games)
    items = [i for i in found["installs"] if i.get("kind") == "workshop_item"]
    # BZP should be visible on the operator's machine.
    assert any(i.get("id") == "3406347034" for i in items)


def test_probe_cli_json(capsys):
    code = bzmap_main(["editor", "probe", "--json"])
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload["ok"] is True
    assert payload["contract_version"] == 1
    assert "installs" in payload
    assert code == 0


def test_worlds_lists_stock_nine(game_root):
    worlds = worlds_from_game(game_root)
    ids = [w["id"] for w in worlds]
    for expected in ("mars", "io", "elysium", "moon"):
        assert expected in ids
    mars = next(w for w in worlds if w["id"] == "mars")
    assert mars["texture_types"], mars
    assert mars["atlas"]
    assert mars.get("atlas_image"), mars
    assert Path(mars["atlas_image"]).is_file()
    assert mars.get("tile_uvs") and len(mars["tile_uvs"]) == 16


def _roundtrip(pack: Path, hg2: Path, tmp_path: Path):
    session = tmp_path / "session"
    out = tmp_path / "out"
    result = open_map(hg2, session)
    assert result["ok"] is True
    saved = save_session(session, out)
    assert saved["ok"] is True
    # Every residue source file must reappear, byte-identical.
    source = session / "residue" / "source"
    src_files = [p for p in source.iterdir() if p.is_file()]
    assert src_files
    mismatches = []
    for src in src_files:
        dest = out / src.name
        if not dest.is_file():
            mismatches.append(f"missing {src.name}")
            continue
        if dest.read_bytes() != src.read_bytes():
            mismatches.append(
                f"{src.name}: {dest.stat().st_size} bytes out != "
                f"{src.stat().st_size} bytes in"
            )
    assert not mismatches, mismatches
    assert saved["regenerated"] == []
    return result, saved


def test_open_save_no_edits_single_zone(pack_dir, tmp_path):
    ones = [p for p in _hg2_files(pack_dir) if p.stat().st_size == 131084]
    if not ones:
        pytest.skip("no 1-zone hg2 in pack")
    _roundtrip(pack_dir, ones[0], tmp_path)


def test_open_save_no_edits_multi_zone(pack_dir, tmp_path):
    multi = [p for p in _hg2_files(pack_dir) if p.stat().st_size > 131084]
    if not multi:
        pytest.skip("no multi-zone hg2 in pack")
    # Prefer a 2x2 (2560 m) over a 4x4 for speed; any multi-zone catches the
    # zone-layout class of bug.
    multi.sort(key=lambda p: p.stat().st_size)
    _roundtrip(pack_dir, multi[0], tmp_path)


def test_new_save_validate(game_root, tmp_path):
    from bzmap.editor.new import create_map
    from bzmap.editor.validate import validate_session

    session = tmp_path / "new-session"
    out = tmp_path / "new-out"
    created = create_map(
        "xxedtest",
        "mars",
        1280,
        1280,
        session,
        game_root,
        base_height=1000,
        pack_kind="bzp",
    )
    assert created["ok"] is True
    saved = save_session(session, out)
    assert saved["ok"] is True
    assert (out / "xxedtest.hg2").is_file()
    assert (out / "xxedtest.mat").is_file()
    assert (out / "xxedtest.trn").is_file()
    report = validate_session(session, game_root=str(game_root))
    # Starter maps may still carry validator noise (spawn placement, etc.).
    # What we require: the file set exists and the validator runs.
    assert "findings" in report
    assert (session / "report.json").is_file()


def test_binary_bzn_is_reported(tmp_path):
    from bzmap.editor.open import is_binary_bzn, open_map
    from bzmap.editor.errors import EditorError

    fake = tmp_path / "oldmap.bzn"
    fake.write_bytes(b"\x00\x01\x02binary leftover")
    assert is_binary_bzn(fake) is True
    # A basename group with only a binary BZN and no hg2 still fails open,
    # but the binary is identified before we invent an ASCII rewrite.
    hg2 = tmp_path / "oldmap.hg2"
    hg2.write_bytes(b"not-a-real-hg2")
    try:
        open_map(fake, tmp_path / "sess")
    except EditorError as exc:
        assert exc.code in {"binary_bzn_unsupported", "missing_hg2"} or "binary" in exc.message.lower()
    else:
        raise AssertionError("binary BZN must not silently convert")


def test_assets_builds_index(game_root, tmp_path):
    from bzmap.editor.assets import build_assets

    cache = tmp_path / "cache"
    result = build_assets(game_root, cache, pack_paths=[], refresh=True, convert=False)
    assert result["ok"] is True
    assert len(result["classes"]) > 100, result.get("unresolved")
    prjids = {c["prjid"] for c in result["classes"]}
    assert any(p.startswith("pspwn") or "tank" in p or "recy" in p for p in prjids)
    assert (cache / "index.json").is_file()
    # Second call hits the fingerprint cache.
    again = build_assets(game_root, cache, pack_paths=[], refresh=False, convert=False)
    assert again["source_fingerprint"] == result["source_fingerprint"]


def test_render_writes_north_up_png(game_root, tmp_path):
    from bzmap.editor.new import create_map
    from bzmap.editor.render_cmd import render_session

    session = tmp_path / "rsess"
    create_map("xxrendr", "mars", 1280, 1280, session, game_root)
    out = tmp_path / "thumbs"
    result = render_session(session, out)
    assert result["ok"] is True
    assert result["north_up"] is True
    assert Path(result["png"]).is_file()
    assert Path(result["preview"]).is_file()


def test_clone_new_object_on_save(game_root, pack_dir, tmp_path):
    from bzmap.editor.new import create_map
    from bzmap.editor.session import read_json, write_json, session_paths

    session = tmp_path / "csess"
    created = create_map("xxclone", "mars", 1280, 1280, session, game_root)
    if not created.get("ok"):
        pytest.skip("new map failed")
    paths = session_paths(session)
    objects = read_json(paths["objects"])
    dirty = read_json(paths["dirty"])
    # Place a spawn by cloning the scaffold already in residue.
    rec = {
        "id": "new-0001",
        "origin": "new",
        "prjid": "pspwn_1",
        "x": 200.0, "y": 100.0, "z": 200.0,
        "yaw_deg": 0.0,
        "team": 0,
        "label": "xxclone99_spawn",
        "up_convention": "upright",
        "pinned_y": False,
        "managed": False,
        "required": False,
        "template_verified": True,
        "placement_mode": "bzn",
    }
    objects.setdefault("", []).append(rec)
    dirty.setdefault("objects", {}).setdefault("", []).append("new-0001")
    write_json(paths["objects"], objects)
    write_json(paths["dirty"], dirty)
    out = tmp_path / "cout"
    saved = save_session(session, out)
    assert saved["ok"] is True
    text = (out / "xxclone.bzn").read_text(encoding="utf-8", errors="replace")
    assert "xxclone99_spawn" in text


def test_terrain_dirty_reencodes(game_root, tmp_path):
    from bzmap.editor.new import create_map
    from bzmap.editor.session import read_json, write_json, session_paths
    import numpy as np

    session = tmp_path / "tsess"
    create_map("xxsculp", "mars", 1280, 1280, session, game_root)
    paths = session_paths(session)
    dirty = read_json(paths["dirty"])
    dirty["terrain"] = True
    write_json(paths["dirty"], dirty)
    raw = np.fromfile(paths["terrain"], dtype="<u2")
    raw[100] = 1500
    raw.tofile(paths["terrain"])
    out = tmp_path / "tout"
    saved = save_session(session, out)
    assert saved["ok"] is True
    assert "xxsculp.hg2" in saved["regenerated"]
    from bzmap.formats.hg2 import read_hg2
    hm = read_hg2(out / "xxsculp.hg2")
    assert int(hm.data.reshape(-1)[100]) & 0x1FFF == 1500
