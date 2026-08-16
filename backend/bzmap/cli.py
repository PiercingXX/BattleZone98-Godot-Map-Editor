"""Command-line interface for the bzmap toolchain.

Subcommands (build order):

- ``corpus`` — enumerate a snapshot of a map corpus and emit a
  corpus-stats CSV. This is the Phase 0 gate (docs/08): a script that can
  enumerate all corpus maps and print size, variants and object counts.

- ``generate`` — run the layout→terrain→economy→spawns→variants pipeline for a
  seed and emit the four variant object sets as deterministic JSON.

The later ``validate|render|package|roundtrip`` subcommands are added by their
own tasks; this module wires up the corpus enumeration and the generate
pipeline, the first two CLI surfaces the toolchain needs.
"""

import argparse
import csv
import json
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path

from bzmap.generate.economy import generate_economy
from bzmap.generate.spawns import generate_spawns
from bzmap.generate.terrain_gen import generate_terrain
from bzmap.generate.variants import generate_variants
from bzmap.model.layout import BASE, GEYSER, SCRAP, LayoutGraph

# --- object classification -------------------------------------------------
# Classified by the object's ``PrjID`` (see docs/02 §5). The class prefixes are
# the load-bearing identifiers used to count economy and spawn objects.
GEYSER_CLASSES = frozenset({"eggeizr1"})
# Corpus-measured scrap classes (see bzmap/formats/odf.py: the npscr* prefix
# alone under-counts sscr_1 and blc-pell).
from bzmap.formats.odf import KNOWN_SCRAP_PRJIDS as SCRAP_CLASSES
SPAWN_CLASS = "pspwn_1"

# Variant suffixes that may accompany a base terrain name.
VARIANTS = ("_S", "_ST", "_SW")

# CSV columns of the corpus-stats format.
CSV_FIELDS = [
    "terrain",
    "mission_name",
    "width_m",
    "depth_m",
    "atlas",
    "sky",
    "max_players",
    "game_type",
    "geysers",
    "scrap",
    "spawns_dm",
    "spawns_S",
    "spawns_ST",
    "spawns_SW",
    "has_S",
    "has_ST",
    "has_SW",
    "area_km2",
    "geysers_per_km2",
]

# --- light INI parsing ------------------------------------------------------


def parse_ini(path):
    """Parse a simple ``key = value`` INI file into ``{section: {key: value}}``.

    Handles the loose INI style used by ``.trn`` and ``.ini``: ``[Section]``
    headers, ``key = value`` pairs, ``;``/``//`` comments, and quoted values
    (quotes stripped). Values are kept as raw strings; callers coerce.
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
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if current is not None:
                sections[current][key] = value
    return sections


# --- BZN object counting -----------------------------------------------------


def _object_class(block_lines):
    """Return the ``PrjID`` of a ``[GameObject]`` block, or ``None``.

    ``block_lines`` is the list of raw lines of one ``[GameObject]`` block. The
    first field is ``PrjID [1] =`` followed by the class on the next line.
    """
    for i, line in enumerate(block_lines):
        if line.strip().startswith("PrjID"):
            if i + 1 < len(block_lines):
                return block_lines[i + 1].strip()
            return None
    return None


def count_bzn_objects(path):
    """Count geyser / scrap / spawn objects in one ASCII ``.bzn`` file.

    Returns ``(geysers, scrap, spawns)``. A ``[GameObject]`` block is identified
    by its ``PrjID`` class (docs/02 §5).
    """
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()

    geysers = scrap = spawns = 0
    block = []
    in_block = False
    for line in lines:
        if line.strip() == "[GameObject]":
            if in_block:
                g, s, sp = _tally(block)
                geysers += g
                scrap += s
                spawns += sp
            block = [line]
            in_block = True
        elif in_block:
            if line.strip().startswith("["):
                g, s, sp = _tally(block)
                geysers += g
                scrap += s
                spawns += sp
                block = []
                in_block = False
            else:
                block.append(line)
    if in_block:
        g, s, sp = _tally(block)
        geysers += g
        scrap += s
        spawns += sp
    return geysers, scrap, spawns


def _tally(block):
    """Count geyser/scrap/spawn objects in one GameObject block."""
    cls = _object_class(block)
    if cls is None:
        return 0, 0, 0
    if cls in GEYSER_CLASSES:
        return 1, 0, 0
    if cls in SCRAP_CLASSES:
        return 0, 1, 0
    if cls == SPAWN_CLASS:
        return 0, 0, 1
    return 0, 0, 0


# --- terrain enumeration -----------------------------------------------------


def _find_file(snapshot, terrain, suffix):
    """Case-insensitively locate ``<terrain><suffix>`` in the snapshot dir."""
    for p in snapshot.iterdir():
        if p.is_file() and p.name.lower() == (terrain + suffix).lower():
            return p
    return None


def enumerate_terrain(snapshot, terrain):
    """Produce one corpus-stats row dict for a single terrain in a snapshot.

    ``snapshot`` is a directory of map files sharing basenames (the flat
    layout). Returns a dict keyed by :data:`CSV_FIELDS`.
    """
    row = {
        "terrain": terrain,
        "mission_name": "",
        "width_m": "",
        "depth_m": "",
        "atlas": "",
        "sky": "",
        "max_players": "",
        "game_type": "",
        "geysers": 0,
        "scrap": 0,
        "spawns_dm": 0,
        "spawns_S": 0,
        "spawns_ST": 0,
        "spawns_SW": 0,
        "has_S": False,
        "has_ST": False,
        "has_SW": False,
    }

    trn = _find_file(snapshot, terrain, ".trn")
    if trn is not None:
        cfg = parse_ini(trn)
        size = cfg.get("Size", {})
        atl = cfg.get("Atlases", {})
        sky = cfg.get("Sky", {})
        row["width_m"] = size.get("Width", "")
        row["depth_m"] = size.get("Depth", "")
        row["atlas"] = atl.get("MaterialName", "")
        # The sky/backdrop column captures the [Sky] backdrop texture. The exact
        # key is a live-measure concern (deferred to the operator); we read the
        # conventional BackdropTexture key and fall back to any backdrop key.
        row["sky"] = sky.get("BackdropTexture", "") or _any_backdrop(sky)

    ini = _find_file(snapshot, terrain, ".ini")
    if ini is not None:
        cfg = parse_ini(ini)
        mp = cfg.get("MULTIPLAYER", {})
        desc = cfg.get("DESCRIPTION", {})
        row["mission_name"] = desc.get("missionName", "")
        row["max_players"] = mp.get("maxPlayers", "")
        row["game_type"] = mp.get("gameType", "")

    base = _find_file(snapshot, terrain, ".bzn")
    if base is not None:
        g, s, sp = count_bzn_objects(base)
        row["geysers"] = g
        row["scrap"] = s
        row["spawns_dm"] = sp

    for variant in ("_S", "_ST", "_SW"):
        vfile = _find_file(snapshot, terrain, variant + ".bzn")
        if vfile is not None:
            row["has_" + variant[1:]] = True
            _, _, sp = count_bzn_objects(vfile)
            row["spawns" + variant] = sp

    # Derived columns.
    try:
        width = float(row["width_m"])
        depth = float(row["depth_m"])
    except (TypeError, ValueError):
        width = depth = 0.0
    area_km2 = width * depth / 1_000_000.0
    row["area_km2"] = _fmt(area_km2)
    row["geysers_per_km2"] = (
        _fmt(row["geysers"] / area_km2) if area_km2 else ""
    )
    return row


def _any_backdrop(sky_section):
    """Return the first backdrop-like key's value from a [Sky] section."""
    for key in ("BackdropTexture", "Backdrop", "SkyTexture"):
        if key in sky_section:
            return sky_section[key]
    return ""


def _fmt(value):
    """Format a float the way the corpus-stats CSV format does (trimmed)."""
    if isinstance(value, float):
        text = f"{value:.3f}".rstrip("0").rstrip(".")
        return text if text else "0"
    return value


def enumerate_corpus(snapshot):
    """Enumerate every terrain in a snapshot dir into a list of row dicts.

    Terrain basenames are inferred from the distinct ``.trn``/``.bzn``/``.ini``
    basenames present, minus any variant suffix.
    """
    terrains = set()
    for p in snapshot.iterdir():
        if not p.is_file():
            continue
        name = p.name
        # Strip a variant suffix before the extension.
        stem = name.rsplit(".", 1)[0] if "." in name else name
        for variant in VARIANTS:
            if stem.endswith(variant):
                stem = stem[: -len(variant)]
                break
        terrains.add(stem)

    rows = []
    for terrain in sorted(terrains):
        rows.append(enumerate_terrain(snapshot, terrain))
    return rows


def write_corpus_csv(rows, out):
    """Write enumerated rows to ``out`` (a path or file-like) as CSV."""
    fieldnames = CSV_FIELDS
    if isinstance(out, (str, Path)):
        with open(out, "w", newline="", encoding="utf-8") as fh:
            _write_rows(fh, rows, fieldnames)
    else:
        _write_rows(out, rows, fieldnames)


def _write_rows(fh, rows, fieldnames):
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


# --- map generation ------------------------------------------------------------


@dataclass(frozen=True)
class GenerateResult:
    """The four variant object sets plus the layout report, for serialisation."""

    layout_ok: bool
    width_m: float
    depth_m: float
    n_teams: int
    seed: int
    #: ``{variant_name: [VariantObject, ...]}`` in a stable order.
    variants: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        """Deterministic plain-dict form (stable key/object order) for JSON."""
        return {
            "layout_ok": self.layout_ok,
            "width_m": self.width_m,
            "depth_m": self.depth_m,
            "n_teams": self.n_teams,
            "seed": self.seed,
            "variants": {
                name: [
                    {
                        "prjid": o.prjid,
                        "x": round(o.x, 3),
                        "z": round(o.z, 3),
                        "y": round(o.y, 3),
                        "yaw": round(o.yaw, 3),
                        "team": o.team,
                        "label": o.label,
                        "scrap_type": o.scrap_type,
                    }
                    for o in variant_set.objects
                ]
                for name, variant_set in self.variants.items()
            },
        }

    def to_json(self) -> str:
        """Deterministic, byte-stable JSON for fixed-seed determinism checks."""
        return json.dumps(
            self.to_dict(), sort_keys=True, separators=(",", ":"), indent=2
        )


def build_layout(
    width: float = 2560.0,
    depth: float = 2560.0,
    n_teams: int = 2,
    seed: int = 0,
) -> LayoutGraph:
    """Build a deterministic, graph-valid layout for ``n_teams`` bases.

    Bases sit on the horizontal midline; each adjacent pair is joined by two
    waypoint routes (the ring that satisfies C3).  Economy is placed so the
    graph-level rules E4 (per-base balance) and E5 (30–50% contested geysers)
    hold exactly: contested geysers are symmetric between a base pair and so
    assign to the first base, which is compensated with fewer local nodes.
    """
    rng = random.Random(seed)
    g = LayoutGraph(width, depth, n_teams=n_teams)

    bases = []
    for i in range(n_teams):
        x = width * (0.25 + 0.5 * i / max(1, n_teams - 1))
        g.add_node(f"base{i}", x, depth / 2, BASE, team=i)
        bases.append(f"base{i}")

    # Ring routes: two waypoints per adjacent base pair (C3: >=2 routes).
    for i in range(n_teams - 1):
        a, b = bases[i], bases[i + 1]
        midx = (g.nodes[a].x + g.nodes[b].x) / 2
        for side, zfrac in (("a", 0.25), ("b", 0.75)):
            wp = f"w{i}{side}"
            g.add_node(wp, midx, depth * zfrac, "waypoint")
            g.add_route(a, wp)
            g.add_route(wp, b)

    # Economy: per-base local nodes plus contested geysers at each pair midpoint.
    for i, bid in enumerate(bases):
        base = g.nodes[bid]
        # Local nodes: 2 geysers + 2 scrap per base, jittered by the seed so
        # the same seed yields the same placement.
        for k in range(2):
            g.add_node(
                f"{bid}_g{k}",
                base.x + rng.uniform(-120, 120),
                base.z + rng.uniform(-180, 180),
                GEYSER,
            )
            g.add_route(bid, f"{bid}_g{k}")
        for k in range(2):
            g.add_node(
                f"{bid}_s{k}",
                base.x + rng.uniform(-120, 120),
                base.z + rng.uniform(-180, 180),
                SCRAP,
            )
            g.add_route(bid, f"{bid}_s{k}")

    # Contested geysers at each pair midpoint, symmetric (E5).  They assign to
    # the first base of the pair; compensate that base with one extra scrap so
    # E4 stays balanced.
    for i in range(n_teams - 1):
        a, b = bases[i], bases[i + 1]
        midx = (g.nodes[a].x + g.nodes[b].x) / 2
        for k in range(2):
            gid = f"c{i}_{k}"
            g.add_node(
                gid,
                midx + rng.uniform(-40, 40),
                depth * (0.5 + (0.20 if k else -0.20)),
                GEYSER,
            )
            g.add_route(gid, f"w{i}a")
            g.add_route(gid, f"w{i}b")
        # Balance E4: the contested geysers above assign to base ``a`` (the
        # first of the pair), so give base ``b`` the same number of extra scrap
        # nodes to keep the per-base economy within 5%.
        for k in range(2):
            g.add_node(
                f"{b}_s_extra{k}",
                g.nodes[b].x + rng.uniform(-120, 120),
                g.nodes[b].z + rng.uniform(-180, 180),
                SCRAP,
            )
            g.add_route(b, f"{b}_s_extra{k}")

    return g


def generate_map(
    seed: int,
    width: float = 2560.0,
    depth: float = 2560.0,
    n_teams: int = 2,
) -> GenerateResult:
    """Run the full layout→terrain→economy→spawns→variants pipeline.

    Fully deterministic in ``seed``: the same seed always produces the same
    layout, heightmap, economy, spawns and variant object sets, hence the same
    serialised output (docs/08 fixed-seed determinism).
    """
    layout = build_layout(width, depth, n_teams, seed)
    report = layout.validate()
    heightmap = generate_terrain(layout, seed)
    economy = generate_economy(layout, heightmap, seed)
    spawns_sw = generate_spawns(layout, heightmap, mode="sw", seed=seed)
    spawns_s = generate_spawns(layout, heightmap, mode="s", seed=seed)
    variants = generate_variants(
        layout, heightmap, economy, spawns_sw, spawns_s, seed
    )
    return GenerateResult(
        layout_ok=report.ok,
        width_m=float(width),
        depth_m=float(depth),
        n_teams=int(n_teams),
        seed=int(seed),
        variants=variants.variants(),
    )


# --- CLI ----------------------------------------------------------------------


def _cmd_generate(args):
    try:
        result = generate_map(args.seed, args.width, args.depth, args.n_teams)
    except Exception as exc:  # noqa: BLE001 - surface any pipeline failure
        print(f"error: generation failed: {exc}", file=sys.stderr)
        return 1
    out = args.output if args.output else "-"
    text = result.to_json()
    if out == "-":
        sys.stdout.write(text + "\n")
    else:
        Path(out).write_text(text + "\n", encoding="utf-8")
        print(f"wrote {len(result.variants)} variants to {out}")
    return 0


def _cmd_corpus(args):
    snapshot = Path(args.snapshot)
    if not snapshot.is_dir():
        print(f"error: snapshot directory not found: {snapshot}", file=sys.stderr)
        return 1
    rows = enumerate_corpus(snapshot)
    out = args.output if args.output else "-"
    if out == "-":
        write_corpus_csv(rows, sys.stdout)
    else:
        write_corpus_csv(rows, out)
        print(f"wrote {len(rows)} rows to {out}")
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="bzmap",
        description="Battlezone 98 Redux map generator toolchain",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    corpus = sub.add_parser(
        "corpus",
        help="enumerate a map-corpus snapshot into a corpus-stats CSV",
    )
    corpus.add_argument("snapshot", help="directory of corpus map files")
    corpus.add_argument(
        "-o", "--output", help="output CSV path (default: stdout)"
    )
    corpus.set_defaults(func=_cmd_corpus)

    generate = sub.add_parser(
        "generate",
        help="run the layout→terrain→economy→spawns→variants pipeline",
    )
    generate.add_argument("--seed", type=int, default=0, help="determinism seed")
    generate.add_argument("--width", type=float, default=2560.0, help="map width (m)")
    generate.add_argument("--depth", type=float, default=2560.0, help="map depth (m)")
    generate.add_argument(
        "--n-teams", type=int, default=2, help="number of base teams"
    )
    generate.add_argument(
        "-o", "--output", help="output JSON path (default: stdout)"
    )
    generate.set_defaults(func=_cmd_generate)

    from bzmap.editor.cli import add_editor_parser
    add_editor_parser(sub)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())