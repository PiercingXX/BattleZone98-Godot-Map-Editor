# 03 — The pure-GDScript backend port

**Decision (2026-08-17), completed same day:** the Python `backend/bzmap`
toolchain was ported to GDScript in full, minus the map *generator*
(`bzmap/generate/*`, the `corpus`/`generate` CLI verbs, and everything only
they import). The editor is a self-contained Godot 4.7 project: no Python, no
venv, no per-platform dependency install. This supersedes the "never parse
formats in GDScript" rule that used to live in `AGENTS.md` — the guarantee
behind that rule (byte-identical round-trips) is carried forward as a **test
requirement** on the port instead (`tests/gd/test_bridge_goldens.gd` and the
per-format round-trip tests).

The Python code was the **reference implementation** and was deleted once the
port was verified; it lives in git history (the parent of commit `af28863`).
The port mirrors it faithfully: same behavior, same JSON payload shapes
(docs/02 §3), same round-trip guarantees. Where Python behavior and a format
spec (`docs/formats/F1–F8`) disagree, the Python behavior wins — each case is
flagged in a comment in the ported module.

---

## Target layout

All new code goes under `project/backend/`. One class per file, file named
after the class. Every class gets a `class_name` with a `Bz` prefix so modules
reference each other without preloads.

| Python source | GDScript target | class_name |
|---|---|---|
| formats/hg2.py | project/backend/formats/BzHg2.gd | BzHg2 |
| formats/mat.py | project/backend/formats/BzMat.gd | BzMat |
| formats/lgt.py | project/backend/formats/BzLgt.gd | BzLgt |
| formats/bzn.py | project/backend/formats/BzBzn.gd | BzBzn |
| formats/trn.py | project/backend/formats/BzTrn.gd | BzTrn |
| formats/ini.py | project/backend/formats/BzIni.gd | BzIni |
| formats/odf.py | project/backend/formats/BzOdf.gd | BzOdf |
| formats/des.py | project/backend/formats/BzDes.gd | BzDes |
| formats/templates.py | project/backend/formats/BzTemplates.gd | BzTemplates |
| formats/geo.py | project/backend/formats/BzGeo.gd | BzGeo |
| formats/bwd2.py | project/backend/formats/BzBwd2.gd | BzBwd2 |
| formats/vxt.py | project/backend/formats/BzVxt.gd | BzVxt |
| formats/mesh.py | project/backend/formats/BzMeshData.gd | BzMeshData |
| formats/maptex.py | project/backend/formats/BzMaptex.gd | BzMaptex |
| formats/glb.py | project/backend/formats/BzGlb.gd | BzGlb |
| formats/ogre.py | project/backend/formats/BzOgre.gd | BzOgre |
| editor/errors.py | project/backend/editor/BzErrors.gd | BzErrors |
| editor/session.py | project/backend/editor/BzSession.gd | BzSession |
| editor/objects.py | project/backend/editor/BzObjects.gd | BzObjects |
| editor/open.py | project/backend/editor/BzOpen.gd | BzOpen |
| editor/convert.py | project/backend/editor/BzConvert.gd | BzConvert |
| editor/save.py | project/backend/editor/BzSave.gd | BzSave |
| editor/new.py | project/backend/editor/BzNew.gd | BzNew |
| editor/worlds.py | project/backend/editor/BzWorlds.gd | BzWorlds |
| editor/discover.py | project/backend/editor/BzDiscover.gd | BzDiscover |
| editor/assets.py | project/backend/editor/BzAssets.gd | BzAssets |
| editor/validate.py | project/backend/editor/BzValidate.gd | BzValidate |
| validate/formats.py | project/backend/validate/BzCheckFormats.gd | BzCheckFormats |
| validate/terrain.py | project/backend/validate/BzCheckTerrain.gd | BzCheckTerrain |
| validate/balance.py | project/backend/validate/BzCheckBalance.gd | BzCheckBalance |
| validate/connectivity.py | project/backend/validate/BzCheckConnectivity.gd | BzCheckConnectivity |
| validate/report.py | project/backend/validate/BzReport.gd | BzReport |
| model/layout.py (only what validate needs) | project/backend/validate/BzLayout.gd | BzLayout |
| render/preview.py + thumbnail.py + debug_map.py + editor/render_cmd.py | project/backend/editor/BzRender.gd | BzRender |
| package/assemble.py + package/install.py + editor/package_cmd.py | project/backend/editor/BzPackage.gd | BzPackage |
| editor/cli.py + jsonio.py | (not ported — Backend.gd calls verb classes directly) | — |

Not ported: `bzmap/generate/*`, `bzmap/cli.py` (top-level corpus/generate),
`bzmap/model/layout.py` beyond what `validate/connectivity.py` actually uses,
`render/debug_map.py` features that only served the generator (keep what the
`render` verb emits).

## Conventions

- **Godot 4.7 typed GDScript.** Tabs for indentation. `extends RefCounted`
  unless the Python class suggests otherwise. Stateless helpers are
  `static func`. Method names stay snake_case, mirroring the Python API 1:1
  (same function names, same argument order) so a reader can diff port
  against reference.
- **No exceptions.** Python raises `EditorError(code, message, hint)`; GDScript
  returns error Dictionaries. Success: `{"ok": true, ...verb payload...}`.
  Failure: `{"ok": false, "error": {"code": ..., "message": ..., "hint": ...}}`
  — built via `BzErrors.err(code, message, hint)`. Internal helpers that can
  fail return `{"ok": bool, ...}` and callers propagate.
- **Binary I/O** is little-endian throughout: `FileAccess.get_buffer()` into
  `PackedByteArray` + `decode_u16/decode_u32/decode_float/...`, or
  `StreamPeerBuffer`. Never assume host endianness.
- **Verbatim round-trips.** Where the Python keeps source lines/bytes verbatim
  (trn, bzn, residue copies), the port must too. Open→save with no edits is
  byte-identical — that is a test, not an aspiration.
- **Row-major is the law** (docs/02 §1). Zone-major conversion happens inside
  format code only; everything above sees `[z * grid_x + x]`, `+z` north.
- **Images:** PIL/imageio → Godot `Image` (`Image.create_empty`, `set_pixel`,
  `resize`, `save_png`). No external image libs.
- **Paths:** `String.path_join`, `FileAccess`/`DirAccess` — no shell-isms, must
  work on Linux and Windows.
- **Verb payloads** (probe/worlds/new/open/save/validate/assets/render/package)
  keep the exact JSON shapes of docs/02 §3. The UI already parses them.

## Testing

- Tests are `tests/gd/test_*.gd`, auto-discovered by `tests/gd/run_tests.gd`,
  each exposing `func run(t) -> void` and asserting via `t.eq/ok/near/fail`
  (async allowed — the runner awaits). Run with `bash scripts/test-editor.sh`.
- **Fixtures are synthetic only.** Never commit anything derived from a game
  install, the BZP pack, workshop items, or the corpus (AGENTS.md rule 3 still
  stands). Build fixtures in-test, or generate small synthetic files with the
  Python reference (`PYTHONPATH=backend python3 - <<EOF ... EOF` — numpy is
  installed; scipy and PIL are NOT) and commit them under
  `tests/gd/fixtures/<module>/` with a note on how they were made.
- Every ported format needs at minimum: a parse test against a known-good
  synthetic fixture (docs/formats/F8 has test vectors), a write→parse
  round-trip test, and — where the Python is a matched parse/emit pair — a
  byte-identical round-trip test.

## Shared files — ownership

Porting agents create only their assigned `project/backend/**` files, their
`tests/gd/test_*.gd` files, and their `tests/gd/fixtures/<module>/` data.
Do not edit `tests/gd/run_tests.gd`, `project/autoload/Backend.gd`, existing
UI code, `AGENTS.md`, or the docs — the integrator owns those.
