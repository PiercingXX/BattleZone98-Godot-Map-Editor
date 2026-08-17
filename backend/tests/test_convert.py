"""Real-install conversion tests. Skip when the game is absent."""

from __future__ import annotations

from pathlib import Path

import pytest

from bzmap.editor.discover import first_game_root, is_game_install
from bzmap.formats.geo import read_geo
from bzmap.formats.ogre import read_ogre_mesh


@pytest.fixture(scope="module")
def game_root():
    root = Path.home() / ".local/share/Steam/steamapps/common/Battlezone 98 Redux"
    if not is_game_install(root):
        found = first_game_root()
        if found is None:
            pytest.skip("no BZ98R install")
        return Path(found)
    return root


def test_read_stock_ogre_mesh(game_root):
    mesh = game_root / "BZ_ASSETS" / "common" / "models" / "abbarr.mesh"
    if not mesh.is_file():
        pytest.skip("abbarr.mesh missing")
    ogre = read_ogre_mesh(mesh)
    assert ogre.submeshes
    sm = ogre.submeshes[0]
    assert len(sm.positions) > 100
    assert len(sm.indices) >= 3
    assert len(sm.indices) % 3 == 0


def test_read_pack_geo(game_root):
    pack = game_root / "packaged_mods" / "3406347034"
    geos = list(pack.glob("*.geo")) if pack.is_dir() else []
    if not geos:
        pytest.skip("no pack geos")
    mesh = read_geo(geos[0])
    assert mesh.positions
    assert mesh.faces


def test_convert_hd_glb(game_root, tmp_path):
    from bzmap.editor.convert import convert_class

    roots = [game_root / "BZ_ASSETS", game_root / "packaged_mods" / "3406347034"]
    dest = tmp_path / "abbarr.glb"
    path, fidelity, why = convert_class("abbarr", roots, dest)
    assert path is not None, why
    assert fidelity == "hd"
    assert dest.stat().st_size > 1000
    assert dest.read_bytes()[:4] == b"glTF"
