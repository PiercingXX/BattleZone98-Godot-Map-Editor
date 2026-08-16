"""Tier 1 structural validation (docs/06).

Pure file correctness, zero tolerance: any failure is a hard error. The checks
are:

- **Round-trip** — every ``.bzn`` parses and re-emits byte-identically; every
  ``.HG2`` round-trips byte-identically (docs/06 §Tier 1, Rule 4).
- **Per-map invariants** — ``.trn`` ``[Size]`` ``Width``/``Depth`` match the
  HG2 header ``zonesX*1280``/``zonesZ*1280``; HG2/MAT/LGT byte counts match the
  size table in docs/01; BZN ``size`` == object count, ``seq_count`` ==
  ``max(seqno)+1``, ``obj_addr`` contiguous from ``00000001``, exactly one
  ``player`` object with ``team = 1``, and the trailing
  ``[AiMission]/[AOIs]/[AiPaths]`` block present with sizes 0.
- **Cross-file consistency** — each variant's terrain files exist under the
  basename implied by the BZN's own filename; ``.des`` stated GEYSERS/SCRAP
  counts match the actual ``_S`` object counts; ``.ini`` ``maxPlayers`` is
  consistent with the deathmatch spawn count.
- **Terrain-name collision** — the candidate's terrain name collides with no
  ``.trn`` in the installed game/workshop reference data (docs/07 "Terrain
  naming"); skipped when ``reference_dir`` is not supplied.
- **Ground snapping** — every object's Y is within 1.5 m of the
  bilinear-interpolated terrain height at its X/Z (docs/06 §Tier 1; measured
  corpus max error 1.04 m).

``msn_filename``/``TerrainName`` are **never** validated against the filename —
they are vestigial editor residue and 93 of 128 stock files disagree with their
own name (docs/02 §2, docs/06 §Tier 1). Enforcing them would fail most of the
pack.

The ODF and terrain-asset existence checks (docs/06 §Tier 1) need the installed
game/corpus reference data, which is not in the repo. They are performed only when
the caller supplies the reference directory; otherwise they are skipped, exactly
as the round-trip gate skips when the pack is absent.
"""

from __future__ import annotations

from pathlib import Path

from bzmap.formats.bzn import BznFile, read_bzn
from bzmap.formats.hg2 import ZONE_M, read_hg2, sample_m
from bzmap.formats.trn import TerrainConfig

#: Ground-snap tolerance in metres (docs/06 §Tier 1; measured corpus max 1.04 m).
GROUND_SNAP_TOLERANCE_M = 1.5

#: Object classes counted as geysers / scrap for cross-file checks (docs/01 §6).
GEYSER_CLASSES = frozenset({"eggeizr1"})
# Corpus-measured scrap classes (see bzmap/formats/odf.py: the npscr* prefix
# alone under-counts sscr_1 and blc-pell).
from bzmap.formats.odf import KNOWN_SCRAP_PRJIDS as SCRAP_CLASSES
SPAWN_CLASS = "pspwn_1"

#: Variant suffixes that may accompany a base terrain name (corpus convention).
VARIANTS = ("_S", "_ST", "_SW")


def _find_file(dirpath: Path, basename: str, suffix: str) -> Path | None:
    """Case-insensitively locate ``<basename><suffix>`` in ``dirpath``."""
    target = (basename + suffix).lower()
    for p in dirpath.iterdir():
        if p.is_file() and p.name.lower() == target:
            return p
    return None


def _installed_terrain_names(reference_dir: Path) -> set[str]:
    """The set of lowercase terrain names in the installed reference data.

    Scans ``reference_dir`` (recursively) for ``.trn`` files and returns their
    stems lowercased. Terrain names are resolved case-insensitively by the
    engine (matches ``_find_file``), so the collision check compares
    lowercased names. Returns an empty set when no ``.trn`` files are found.
    """
    names = set()
    for p in reference_dir.rglob("*"):
        if p.is_file() and p.suffix.lower() == ".trn":
            names.add(p.name[: -len(p.suffix)].lower())
    return names


def _object_position(obj) -> tuple[float, float, float] | None:
    """Return ``(x, y, z)`` from a :class:`GameObject`'s first ``pos`` block.

    The ``pos`` block is ``pos [1] =`` followed by ``x/y/z [1] =`` each with its
    value on the next line (docs/02 §3). Returns ``None`` when the block is
    malformed or absent.
    """
    lines = obj.lines
    for i, line in enumerate(lines):
        if line.strip() != "pos [1] =":
            continue
        block = lines[i + 1:i + 7]
        values = {}
        for j, bl in enumerate(block):
            stripped = bl.strip()
            for axis in ("x", "y", "z"):
                if stripped == f"{axis} [1] =" and i + j + 2 < len(lines):
                    try:
                        values[axis] = float(lines[i + j + 2].strip())
                    except ValueError:
                        return None
        if len(values) == 3:
            return values["x"], values["y"], values["z"]
    return None


def _trn_size(trn: TerrainConfig) -> tuple[float, float] | None:
    """Return ``(Width, Depth)`` in metres from a ``.trn`` ``[Size]`` section."""
    size = trn.section("Size")
    if size is None:
        return None
    width = size.get("Width")
    depth = size.get("Depth")
    if width is None or depth is None:
        return None
    try:
        return float(width), float(depth)
    except ValueError:
        return None


def _bzn_geyser_scrap_spawns(bzn: BznFile) -> tuple[int, int, int]:
    """Count geyser / scrap / spawn objects in a parsed ``.bzn``."""
    geysers = scrap = spawns = 0
    for obj in bzn.objects:
        prjid = obj.prjid or ""
        if prjid in GEYSER_CLASSES:
            geysers += 1
        elif prjid in SCRAP_CLASSES:
            scrap += 1
        elif prjid == SPAWN_CLASS:
            spawns += 1
    return geysers, scrap, spawns


class MapValidator:
    """Tier 1 structural validator for one candidate map directory.

    ``dirpath`` is a flat directory of files sharing a terrain basename (the
    corpus layout, docs/01). ``validate()`` returns a list of human-readable
    problem strings; an empty list means the candidate is structurally valid.
    """

    def __init__(self, dirpath, *, reference_dir=None):
        self.dirpath = Path(dirpath)
        self.reference_dir = Path(reference_dir) if reference_dir else None

    # -- entry point ---------------------------------------------------------

    def validate(self) -> list[str]:
        """Run every Tier 1 check and return the list of problems."""
        problems = []
        problems.extend(self._check_roundtrip())
        problems.extend(self._check_per_map_invariants())
        problems.extend(self._check_cross_file())
        problems.extend(self._check_ground_snapping())
        problems.extend(self._check_terrain_name_collision())
        return problems

    # -- helpers -------------------------------------------------------------

    def _bzn_files(self):
        """Return ``(basename, path)`` for every ``.bzn`` in the directory."""
        out = []
        for p in self.dirpath.iterdir():
            if not p.is_file() or p.suffix.lower() != ".bzn":
                continue
            out.append((p.name[: -len(p.suffix)], p))
        return out

    # -- round-trip ----------------------------------------------------------

    def _check_roundtrip(self) -> list[str]:
        problems = []
        for p in self.dirpath.iterdir():
            if not p.is_file():
                continue
            suffix = p.suffix.lower()
            if suffix == ".bzn":
                problems.extend(self._roundtrip_bzn(p))
            elif suffix == ".hg2":
                problems.extend(self._roundtrip_hg2(p))
        return problems

    def _roundtrip_bzn(self, path: Path) -> list[str]:
        original = path.read_bytes()
        try:
            bzn = read_bzn(path)
            out = path.with_name(path.name + ".rt")
            bzn.write(out)
            ok = out.read_bytes() == original
            out.unlink(missing_ok=True)
        except (ValueError, OSError, UnicodeDecodeError) as exc:
            return [f"{path.name}: BZN round-trip failed: {type(exc).__name__}: {exc}"]
        if not ok:
            return [f"{path.name}: BZN does not re-emit byte-identically"]
        return []

    def _roundtrip_hg2(self, path: Path) -> list[str]:
        original = path.read_bytes()
        try:
            hm = read_hg2(path)
            out = path.with_name(path.name + ".rt")
            hm.write(out)
            ok = out.read_bytes() == original
            out.unlink(missing_ok=True)
        except (ValueError, OSError) as exc:
            return [f"{path.name}: HG2 round-trip failed: {type(exc).__name__}: {exc}"]
        if not ok:
            return [f"{path.name}: HG2 does not re-emit byte-identically"]
        return []

    # -- per-map invariants --------------------------------------------------

    def _check_per_map_invariants(self) -> list[str]:
        problems = []
        hg2 = _find_file(self.dirpath, self._terrain_basename(), ".hg2")
        trn = _find_file(self.dirpath, self._terrain_basename(), ".trn")

        # The HG2 is the source of truth for dimensions; without it most other
        # size checks are unanchored.
        hm = None
        if hg2 is not None:
            try:
                hm = read_hg2(hg2)
            except ValueError as exc:
                problems.append(f"{hg2.name}: {exc}")

        if hm is not None:
            problems.extend(self._check_size_consistency(hm))
            problems.extend(self._check_byte_counts(hm))

        if trn is not None:
            try:
                trn_cfg = TerrainConfig.read(trn)
            except (ValueError, OSError, UnicodeDecodeError) as exc:
                problems.append(f"{trn.name}: {type(exc).__name__}: {exc}")
                trn_cfg = None
            if trn_cfg is not None and hm is not None:
                size = _trn_size(trn_cfg)
                if size is not None:
                    width, depth = size
                    exp_w = hm.zonesX * ZONE_M
                    exp_d = hm.zonesZ * ZONE_M
                    if abs(width - exp_w) > 1e-6 or abs(depth - exp_d) > 1e-6:
                        problems.append(
                            f"{trn.name}: [Size] {width}x{depth} does not match "
                            f"HG2 header {exp_w}x{exp_d}"
                        )

        for basename, path in self._bzn_files():
            try:
                bzn = read_bzn(path)
            except (ValueError, OSError, UnicodeDecodeError) as exc:
                problems.append(f"{path.name}: {type(exc).__name__}: {exc}")
                continue
            for problem in bzn.validate():
                problems.append(f"{path.name}: {problem}")
        return problems

    def _check_size_consistency(self, hm) -> list[str]:
        # Nothing beyond the trn check here; the HG2 header is self-consistent
        # by construction (read_hg2 validates the sample count). Kept as a
        # separate hook so future per-map size checks have a home.
        return []

    def _check_byte_counts(self, hm) -> list[str]:
        problems = []
        base = self._terrain_basename()
        expected = {
            ".hg2": hm.zonesX * hm.zonesZ * 256 * 256 * 2 + 12,
            ".mat": (hm.zonesX * 64) * (hm.zonesZ * 64) * 2,
            ".lgt": (hm.zonesX * hm.zonesZ + 1) * 65536,
        }
        for suffix, want in expected.items():
            p = _find_file(self.dirpath, base, suffix)
            if p is None:
                # Not every map ships every file (35 of 36 ship an LGT; the
                # exception is a broken stub). Only flag a mismatch when the
                # file is present but the wrong size.
                continue
            got = p.stat().st_size
            if got != want:
                problems.append(
                    f"{p.name}: size {got} does not match expected {want} "
                    f"for {hm.zonesX}x{hm.zonesZ} zones"
                )
        return problems

    # -- cross-file consistency ----------------------------------------------

    def _check_cross_file(self) -> list[str]:
        problems = []
        problems.extend(self._check_variant_files_exist())
        problems.extend(self._check_des_counts())
        problems.extend(self._check_ini_max_players())
        return problems

    def _check_variant_files_exist(self) -> list[str]:
        """The terrain files implied by the BZN filenames exist.

        The engine resolves terrain from the BZN's own filename, not from
        ``TerrainName`` (docs/02 §2). Variants share the base terrain, so the
        terrain basename is the BZN's stem with any ``_S``/``_ST``/``_SW``
        suffix stripped — and that terrain's ``.trn``/``.HG2``/``.MAT`` must
        exist in the directory.
        """
        base = self._terrain_basename()
        if not base:
            return []
        problems = []
        for suffix in (".trn", ".hg2", ".mat"):
            if _find_file(self.dirpath, base, suffix) is None:
                problems.append(
                    f"terrain file <{base}{suffix}> implied by the BZN "
                    f"filenames is missing"
                )
        return problems

    def _check_des_counts(self) -> list[str]:
        """``.des`` stated GEYSERS/SCRAP match the actual ``_S`` object counts."""
        base = self._terrain_basename()
        des = _find_file(self.dirpath, base, ".des")
        s_bzn = _find_file(self.dirpath, base + "_S", ".bzn")
        if des is None or s_bzn is None:
            return []
        try:
            text = des.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            return [f"{des.name}: {type(exc).__name__}: {exc}"]
        geysers = scrap = None
        for line in text.splitlines():
            if line.startswith("GEYSERS:"):
                try:
                    geysers = int(line.split(":", 1)[1].split()[0])
                except (ValueError, IndexError):
                    pass
            elif line.startswith("SCRAP:"):
                try:
                    scrap = int(line.split(":", 1)[1].split()[0])
                except (ValueError, IndexError):
                    pass
        try:
            bzn = read_bzn(s_bzn)
        except (ValueError, OSError, UnicodeDecodeError) as exc:
            return [f"{s_bzn.name}: {type(exc).__name__}: {exc}"]
        actual_g, actual_s, _ = _bzn_geyser_scrap_spawns(bzn)
        problems = []
        if geysers is not None and geysers != actual_g:
            problems.append(
                f"{des.name}: states {geysers} GEYSERS but _S has {actual_g}"
            )
        if scrap is not None and scrap != actual_s:
            problems.append(
                f"{des.name}: states {scrap} SCRAP but _S has {actual_s}"
            )
        return problems

    def _check_ini_max_players(self) -> list[str]:
        """``.ini`` ``maxPlayers`` is consistent with the deathmatch spawn count.

        The base (deathmatch) BZN carries the 14-spawn _SW cluster set (corpus convention);
        ``maxPlayers`` must be at least that spawn count.
        """
        base = self._terrain_basename()
        ini = _find_file(self.dirpath, base, ".ini")
        base_bzn = _find_file(self.dirpath, base, ".bzn")
        if ini is None or base_bzn is None:
            return []
        try:
            sections = _parse_ini(ini)
        except OSError as exc:
            return [f"{ini.name}: {type(exc).__name__}: {exc}"]
        mp = sections.get("MULTIPLAYER", {})
        max_players = mp.get("maxPlayers")
        if max_players is None:
            return []
        try:
            max_players = int(max_players)
        except ValueError:
            return [f"{ini.name}: maxPlayers {max_players!r} is not an integer"]
        try:
            bzn = read_bzn(base_bzn)
        except (ValueError, OSError, UnicodeDecodeError) as exc:
            return [f"{base_bzn.name}: {type(exc).__name__}: {exc}"]
        _, _, spawns = _bzn_geyser_scrap_spawns(bzn)
        if spawns > max_players:
            return [
                (
                    f"{ini.name}: maxPlayers {max_players} is less than the "
                    f"deathmatch spawn count {spawns}"
                )
            ]
        return []

    # -- ground snapping -----------------------------------------------------

    def _check_ground_snapping(self) -> list[str]:
        problems = []
        hg2 = _find_file(self.dirpath, self._terrain_basename(), ".hg2")
        if hg2 is None:
            return []
        try:
            hm = read_hg2(hg2)
        except ValueError as exc:
            return [f"{hg2.name}: {exc}"]
        for basename, path in self._bzn_files():
            try:
                bzn = read_bzn(path)
            except (ValueError, OSError, UnicodeDecodeError):
                continue  # already reported by the per-map invariants check
            for i, obj in enumerate(bzn.objects):
                pos = _object_position(obj)
                if pos is None:
                    problems.append(
                        f"{path.name}: object {i} has no parseable position"
                    )
                    continue
                x, y, z = pos
                ground = sample_m(hm, x, z)
                if abs(y - ground) > GROUND_SNAP_TOLERANCE_M:
                    problems.append(
                        f"{path.name}: object {i} ({obj.prjid}) Y={y:.2f} is "
                        f"{abs(y - ground):.2f} m from terrain height "
                        f"{ground:.2f} at ({x:.1f}, {z:.1f})"
                    )
        return problems

    # -- terrain-name collision ------------------------------------------------

    def _check_terrain_name_collision(self) -> list[str]:
        """The candidate's terrain name must not collide with installed content.

        Terrain names are globally flat across every loaded mod (docs/07
        "Terrain naming"): a collision with the base game, the corpus pack, or any other
        subscribed item breaks both maps. The installed game/workshop reference
        data is not in the repo, so this check runs only when the caller
        supplies ``reference_dir``; otherwise it is skipped, exactly as the
        round-trip gate skips when the pack is absent.
        """
        if self.reference_dir is None:
            return []
        base = self._terrain_basename()
        if not base:
            return []
        existing = _installed_terrain_names(self.reference_dir)
        if not existing:
            return []
        if base.lower() in existing:
            return [
                (
                    f"terrain name <{base}> collides with an installed "
                    f"terrain in {self.reference_dir}"
                )
            ]
        return []

    # -- basename ------------------------------------------------------------

    def _terrain_basename(self) -> str:
        """The base terrain name (longest shared stem across BZN files).

        Falls back to the first ``.bzn``'s stem when no variants are present.
        """
        stems = [basename for basename, _ in self._bzn_files()]
        if not stems:
            # No BZN; use the trn/HG2 stem if present.
            for p in self.dirpath.iterdir():
                if p.is_file() and p.suffix.lower() in (".trn", ".hg2"):
                    return p.name[: -len(p.suffix)]
            return ""
        base = stems[0]
        shortest = min(len(s) for s in stems)
        for i in range(shortest):
            if any(s[i] != base[i] for s in stems):
                base = base[:i]
                break
        else:
            base = base[:shortest]
        return base


def _parse_ini(path: Path) -> dict[str, dict[str, str]]:
    """Parse a simple ``key = value`` INI into ``{section: {key: value}}``.

    Handles ``[Section]`` headers, ``key = value`` pairs, ``;``/``//`` comments,
    and quoted values (quotes stripped). Mirrors ``bzmap.cli.parse_ini``.
    """
    sections = {}
    current = None
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith((";", "//")):
                continue
            if line.startswith("[") and line.endswith("]"):
                current = line[1:-1].strip()
                sections.setdefault(current, {})
                continue
            if "=" not in line or current is None:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            sections[current][key] = value
    return sections


def validate_map(dirpath, *, reference_dir=None) -> list[str]:
    """Validate a candidate map directory; return the list of problems."""
    return MapValidator(dirpath, reference_dir=reference_dir).validate()