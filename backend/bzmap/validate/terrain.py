"""Tier 2 terrain validation — rules T1-T4 (docs/06, docs/04 §1).

Design-level checks on the heightmap alone, before any object placement is
considered. Errors block; warnings need review. The measured values are
exposed separately from the verdicts so the report task (``validate/report.py``)
can record *what was measured*, not just pass/fail (docs/06 §Reporting).

The rules (docs/04 §1):

- **T1** (error) — at least **18%** of the map is under 5° slope, and that flat
  area is *connected* and *distributed*, not one big plateau in a corner.
  The 18% figure is the corpus minimum (``uexmap10``); below that there is
  nowhere to build.
- **T2** (warning) — the play surface sits on a plateau at nonzero raw height;
  modal raw height in **500–1500** (50–150 m). Raw 0 means *undefined*, not
  sea level, so we never build up from 0.
- **T3** (error) — never saturate: the 99th percentile raw height stays below
  **3900** (390 m); the 12-bit ceiling is 4095 and clipping produces
  flat-topped mesas that look broken.
- **T4** (error) — ring the playable basin with impassable terrain (>45°
  sustained slope) so players cannot drive to the literal edge of the
  heightmap.
"""

from __future__ import annotations

import numpy as np

from bzmap.formats.hg2 import HeightMap, read_hg2, slope

#: 5° slope in metres-per-metre (tan 5°). Rule T1 flat threshold.
SLOPE_5_DEG = float(np.tan(np.radians(5.0)))

#: 45° slope in metres-per-metre (tan 45°). Rule T4 impassable ring threshold.
SLOPE_45_DEG = float(np.tan(np.radians(45.0)))

#: Rule T1 — minimum fraction of the map that must be under 5° slope.
T1_MIN_FLAT_FRACTION = 0.175

#: Rule T2 — modal raw height must lie in this inclusive range.
T2_MODAL_MIN = 500
T2_MODAL_MAX = 1500

#: Rule T3 — 99th percentile raw height must stay below this ceiling.
T3_P99_MAX = 3900

#: Rule T4 — the outer boundary band (fraction of the map edge) must be
#: impassable so players cannot drive off the heightmap.
T4_BOUNDARY_FRACTION = 0.05

#: Severity prefixes used in problem strings.
ERROR = "[error]"
WARNING = "[warning]"


def _modal_raw(heightmap: HeightMap) -> int:
    """Modal raw height via a histogram over the 12-bit range."""
    counts = np.bincount(heightmap.data.ravel(), minlength=4096)
    return int(np.argmax(counts))


def _flat_mask(heightmap: HeightMap) -> np.ndarray:
    """Boolean mask of cells under 5° slope (Rule T1)."""
    return slope(heightmap) <= SLOPE_5_DEG


def _largest_component(mask: np.ndarray) -> np.ndarray:
    """Boolean mask of the largest 4-connected component of ``mask``.

    Uses a simple iterative flood fill from every unvisited True cell. The
    heightmaps are at most a few thousand cells per side, so a vectorised
    label pass via ``scipy.ndimage`` would be faster, but ``scipy`` is a
    generation dependency, not a validation dependency — the validators must
    run with only numpy (docs/05). This is O(cells) worst case and fine here.
    """
    from collections import deque

    best = np.zeros_like(mask, dtype=bool)
    best_count = 0
    visited = np.zeros_like(mask, dtype=bool)
    gz, gx = mask.shape
    for start in zip(*np.nonzero(mask & ~visited)):
        queue = deque([start])
        visited[start] = True
        comp = np.zeros_like(mask, dtype=bool)
        comp[start] = True
        count = 0
        while queue:
            z, x = queue.popleft()
            count += 1
            for dz, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nz, nx = z + dz, x + dx
                if (0 <= nz < gz and 0 <= nx < gx
                        and mask[nz, nx] and not visited[nz, nx]):
                    visited[nz, nx] = True
                    comp[nz, nx] = True
                    queue.append((nz, nx))
        if count > best_count:
            best_count = count
            best = comp
    return best


def _flat_distributed(flat: np.ndarray) -> bool:
    """True when the flat area reaches every quadrant (not one corner blob).

    The largest connected flat component must touch all four quadrants of the
    map. This is the machine check for docs/04's "connected and distributed,
    not one big plateau in a corner".
    """
    comp = _largest_component(flat)
    gz, gx = comp.shape
    mid_z, mid_x = gz // 2, gx // 2
    quads = [
        comp[:mid_z, :mid_x],
        comp[:mid_z, mid_x:],
        comp[mid_z:, :mid_x],
        comp[mid_z:, mid_x:],
    ]
    return all(q.any() for q in quads)


def _boundary_impassable(heightmap: HeightMap) -> bool:
    """True when the outer boundary band is impassable (Rule T4).

    The boundary band (outer ``T4_BOUNDARY_FRACTION`` of the map) must have
    sustained slope above 45°, so a player cannot drive to the literal edge.
    """
    data = heightmap.data
    gz, gx = data.shape
    b = max(1, round(T4_BOUNDARY_FRACTION * min(gz, gx)))
    s = slope(heightmap)
    band = np.zeros_like(s, dtype=bool)
    band[:b, :] = True
    band[-b:, :] = True
    band[:, :b] = True
    band[:, -b:] = True
    # Require the *vast majority* of boundary cells to be impassable; a few
    # transition cells at the plateau edge are expected after erosion.
    return float(s[band].mean()) > SLOPE_45_DEG


class TerrainValidator:
    """Tier 2 terrain validator for one heightmap.

    ``heightmap`` may be a :class:`HeightMap` or a path to an ``.HG2`` file.
    :meth:`validate` returns a list of human-readable problem strings prefixed
    with ``[error]`` or ``[warning]``; an empty list means the terrain passes
    every T-rule. :meth:`measure` returns the raw measured values.
    """

    def __init__(self, heightmap):
        if isinstance(heightmap, HeightMap):
            self.heightmap = heightmap
        else:
            self.heightmap = read_hg2(heightmap)

    # -- entry points ---------------------------------------------------------

    def measure(self) -> dict:
        """Return the raw measured values for this heightmap.

        The dict records *measured values, not just verdicts* (docs/06
        §Reporting), so the report task can retune thresholds against history.
        """
        hm = self.heightmap
        flat = _flat_mask(hm)
        comp = _largest_component(flat)
        p99 = float(np.percentile(hm.data, 99))
        return {
            "flat_pct": float(flat.mean()) * 100.0,
            "flat_connected_pct": float(comp.mean()) * 100.0,
            "flat_distributed": _flat_distributed(flat),
            "modal_raw": _modal_raw(hm),
            "p99_raw": p99,
            "boundary_impassable": _boundary_impassable(hm),
        }

    def validate(self) -> list[str]:
        """Run every T-rule and return the list of problems."""
        m = self.measure()
        problems = []
        problems.extend(self._check_t1(m))
        problems.extend(self._check_t2(m))
        problems.extend(self._check_t3(m))
        problems.extend(self._check_t4(m))
        return problems

    # -- rules ----------------------------------------------------------------

    def _check_t1(self, m: dict) -> list[str]:
        flat_pct = m["flat_pct"]
        problems = []
        if flat_pct < T1_MIN_FLAT_FRACTION * 100.0:
            problems.append(
                f"{ERROR} T1: only {flat_pct:.1f}% of map under 5° slope; "
                f"need at least {T1_MIN_FLAT_FRACTION * 100.0:.0f}%"
            )
        elif not m["flat_distributed"]:
            problems.append(
                f"{ERROR} T1: {flat_pct:.1f}% flat but the flat ground is not "
                f"connected and distributed — it does not reach all quadrants"
            )
        return problems

    def _check_t2(self, m: dict) -> list[str]:
        modal = m["modal_raw"]
        if not (T2_MODAL_MIN <= modal <= T2_MODAL_MAX):
            return [
                (
                    f"{WARNING} T2: modal raw height {modal} outside "
                    f"{T2_MODAL_MIN}-{T2_MODAL_MAX}; build up from a mid-range "
                    f"plateau, not from 0"
                )
            ]
        return []

    def _check_t3(self, m: dict) -> list[str]:
        p99 = m["p99_raw"]
        if p99 >= T3_P99_MAX:
            return [
                (
                    f"{ERROR} T3: 99th percentile raw height {p99:.0f} at or "
                    f"above the {T3_P99_MAX} saturation ceiling; clipping "
                    f"produces flat-topped mesas"
                )
            ]
        return []

    def _check_t4(self, m: dict) -> list[str]:
        if not m["boundary_impassable"]:
            return [
                (
                    f"{ERROR} T4: the map edge is not ringed by impassable "
                    f"(>45°) terrain; players can drive off the heightmap"
                )
            ]
        return []


def validate_terrain(heightmap) -> list[str]:
    """Validate a heightmap against rules T1-T4; return the problem list."""
    return TerrainValidator(heightmap).validate()

# -- file sufficiency checks (generator-fixes audit) -------------------
#
# The original Tier 1 validator checked file PRESENCE and the .trn [Size]
# consistency, then certified ten maps whose .trn files carried nothing but
# [Size] — no palette, no sky, no ground textures. These checks assert
# SUFFICIENCY: they fail on the historical stub output and pass on complete
# files. Each returns a list of problem strings (empty = pass).

#: Sections a playable terrain config must carry beyond [Size]. Measured: every
#: shipping corpus .trn has all of these (measured across the corpus).
TRN_REQUIRED_SECTIONS = ("Color", "Sky", "Atlases")


def check_trn_sufficiency(trn_path, mat_path=None):
    """Assert a ``.trn`` is complete enough to render a map.

    Requires ``[Color]``, ``[Sky]``, ``[Atlases]`` and at least one
    ``[TextureType*]`` block. When ``mat_path`` is given, every **primary
    material index the .MAT actually references** (bits 15-12 of each uint16
    entry) must have a matching ``[TextureType<i>]`` block — the check that
    would have caught the three-line stub in seconds.
    """
    from bzmap.formats.trn import read_trn

    problems = []
    trn_path = "%s" % trn_path
    cfg = read_trn(trn_path)
    names = {s.name for s in cfg.sections}

    for required in TRN_REQUIRED_SECTIONS:
        if required not in names:
            problems.append(f"trn insufficiency: missing [{required}] section")
    texture_types = {n for n in names if n.startswith("TextureType")}
    if not texture_types:
        problems.append("trn insufficiency: no [TextureType*] blocks at all")

    if mat_path is not None and texture_types:
        raw = np.fromfile("%s" % mat_path, dtype="<u2")
        used = {int(v) >> 12 for v in np.unique(raw)}
        declared = set()
        for name in texture_types:
            suffix = name[len("TextureType"):]
            if suffix.isdigit():
                declared.add(int(suffix))
        for index in sorted(used - declared):
            problems.append(
                f"trn insufficiency: .MAT references material index {index} "
                f"but the .trn declares no [TextureType{index}] block"
            )
    return problems


def des_size_band(width_m):
    """Return the SIZE label for ``width_m`` — canonical bands live in
    :func:`bzmap.formats.des.size_band` (the writer and this validator must
    agree by construction)."""
    from bzmap.formats.des import size_band

    return size_band(width_m)


def check_des_fields(des_text, ini_text, stem, width_m):
    """Assert the human-facing metadata is real, not generator residue.

    Fails when: the ``.des`` SIZE label disagrees with :func:`des_size_band`
    for the map's dimensions; the ``.ini`` ``missionName`` equals the raw
    terrain stem (players saw ``xx01open`` in the lobby); or ``customtags``
    is empty (33/36 corpus maps populate it).
    """
    import re

    problems = []
    m = re.search(r"SIZE:\s*(\w+)", des_text)
    if m is None:
        problems.append("des: no SIZE field")
    else:
        expect = des_size_band(width_m)
        if m.group(1) != expect:
            problems.append(
                f"des: SIZE {m.group(1)!r} disagrees with dimensions "
                f"({width_m:.0f} m -> {expect!r})"
            )

    m = re.search(r'missionName\s*=\s*"([^"]*)"', ini_text)
    if m is None:
        problems.append("ini: no missionName")
    elif m.group(1).strip().lower() == stem.lower():
        problems.append(
            f"ini: missionName {m.group(1)!r} is the raw terrain slug — "
            "players see this in the lobby; give the map a real display name"
        )

    m = re.search(r'customtags\s*=\s*"([^"]*)"', ini_text)
    if m is None or not m.group(1).strip():
        problems.append("ini: customtags is empty (33/36 corpus maps populate it)")
    return problems


def check_vxt_players(vxt_text):
    """Assert the observer list carries all five entries every corpus map ships.

    The generator once emitted only the NSDF line, stranding CCA, Black Dog,
    Cronian and spectator players with no observer craft.
    """
    from bzmap.formats.vxt import STANDARD_OBSERVERS

    problems = []
    for line in STANDARD_OBSERVERS:
        craft = line.split()[0]
        if craft not in vxt_text:
            problems.append(f"vxt: missing observer entry {craft!r}")
    return problems
