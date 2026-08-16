"""Design-to-map-files bridge (docs/05 ``package/``, docs/07).

Takes a :class:`bzmap.cli.GenerateResult` (the deterministic output of
``generate_map``) and writes the full validated map file set for one map into
``build/<name>/``. This is the bridge between the design/generation layer and
the on-disk pack: everything the engine loads for one map, in one directory.

The bridge re-derives the heightmap, layout, economy and spawns from the
result's ``seed``/``width_m``/``depth_m``/``n_teams`` (generation is fully
deterministic in the seed, docs/08), so it can write the terrain files
(``.HG2``, ``.MAT``) that the variant object sets alone do not carry.

Files written from the pipeline:

- ``<name>.HG2`` — the heightmap (zone-major, round-trips byte-identically).
- ``<name>.MAT`` — auto-painted material grid from the heightmap.
- ``<name>.bzn``, ``<name>_S.bzn``, ``<name>_ST.bzn``, ``<name>_SW.bzn`` —
  the four variant object sets via template-and-mutate (docs/02 §6 R2).
- ``<name>.ini``, ``<name>.des``, ``<name>.odf`` — metadata derived from the
  real object counts.

Files copied verbatim from a stock source map (the ``.trn``, ``.LGT`` and
``.vxt`` formats are template/copy-only — docs/01 §3, §4, §8; the reference
data is not in the repo):

- ``<name>.trn``, ``<name>.LGT``, ``<name>.vxt`` — copied from ``source_dir``.

The BZN object templates for every class the variants emit (``player``,
``pspwn_1``, ``eggeizr1``, ``npscr1/2/3``, ``abhang``, ``absupp``) are sourced
from a stock ``.bzn`` via ``bzn_path``; the checked-in ``reference/`` templates
only carry ``eggeizr1`` (docs/02 §6 R2). When ``bzn_path`` is omitted the
loader falls back to ``reference/`` and raises for any class it cannot clone.

The written file set is validated with :class:`bzmap.validate.formats.MapValidator`
before returning (docs/06 Tier 1); any error is raised as :class:`BuildError`.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from bzmap.cli import build_layout
from bzmap.formats.bzn import BznFile, GameObject
from bzmap.formats.des import size_band, write_des
from bzmap.formats.ini import write_ini
from bzmap.formats.trn import write_complete_trn
from bzmap.formats.vxt import write_standard_vxt
from bzmap.render.preview import render_heightmap
from bzmap.render.thumbnail import THUMBNAIL_SIZE, write_bmp, write_png
from bzmap.formats.mat import auto_paint
from bzmap.formats.odf import write_odf
from bzmap.formats.templates import TemplateLoader
from bzmap.generate.economy import generate_economy
from bzmap.generate.spawns import generate_spawns
from bzmap.generate.terrain_gen import generate_terrain
from bzmap.generate.variants import generate_variants
from bzmap.validate.formats import MapValidator

#: The four variant suffixes, keyed by the BZN filename suffix (corpus convention).
VARIANT_SUFFIXES = ("", "_S", "_ST", "_SW")

#: Copy-only terrain/metadata files sourced from a stock map (docs/01 §3,§4,§8).
COPY_SUFFIXES = (".trn", ".LGT", ".vxt")

#: Default multiplayer player count for the pack (docs/01 §5: 35 of 36 use 14).
DEFAULT_MAX_PLAYERS = 14


class BuildError(RuntimeError):
    """Raised when the map file set cannot be written or validated."""


def _terrain_rules():
    """Default auto-paint material rules (elevation/slope bands)."""
    return [
        {"mat_id": 0, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.0, "max_s": 0.05},
        {"mat_id": 1, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.05, "max_s": 0.25},
        {"mat_id": 2, "min_h": 0.0, "max_h": 1000.0, "min_s": 0.25, "max_s": 10.0},
    ]


def _clone_object(loader: TemplateLoader, prjid: str) -> GameObject:
    """Clone a template block for ``prjid`` into a fresh :class:`GameObject`."""
    return GameObject.from_template(loader.object(prjid))


def _build_variant_bzn(
    loader: TemplateLoader,
    objects,
    terrain_name: str,
) -> BznFile:
    """Assemble one variant's ``.bzn`` from its object set.

    ``objects`` is a list of :class:`bzmap.generate.variants.VariantObject`.
    Each object is cloned from the template for its ``prjid``, then mutated in
    place: position (all three places it lives), pure-Y yaw, and the
    seqno/obj_addr/label identity. ``seqno`` is the object's index in the file
    and ``obj_addr`` is contiguous from ``00000001`` (docs/02 §6 R4).
    """
    blocks = []
    for i, obj in enumerate(objects):
        block = _clone_object(loader, obj.prjid)
        block.set_position(obj.x, obj.y, obj.z)
        block.set_yaw(obj.yaw)
        block.set_identity(seqno=i, addr=i + 1, label=obj.label)
        blocks.append(block)

    header = loader.header()
    tail = loader.tail()
    bzn = BznFile.build(header, blocks, tail)

    # Fix the header's size/seq_count to the actual object count (docs/02 §6 R4).
    bzn.set_header("size [1]", len(blocks))
    # seq_count is max(seqno)+1; seqnos are 0..n-1 in file order.
    bzn.set_header("seq_count [1]", len(blocks))
    return bzn


def build_map(
    result,
    name: str,
    out_dir,
    *,
    bzn_path=None,
    source_dir=None,
    mission_name=None,
    world="Elysium",
    size=None,
    customtags=None,
    max_players=DEFAULT_MAX_PLAYERS,
) -> Path:
    """Write the full validated map file set for ``result`` into ``out_dir/<name>/``.

    ``result`` is a :class:`bzmap.cli.GenerateResult` from ``generate_map``.
    ``name`` is the terrain basename (e.g. ``xx01ridg``); files are written as
    ``<name><suffix>``. ``out_dir`` is created if absent.

    ``bzn_path`` is an optional stock ``.bzn`` used to source object templates
    for classes the ``reference/`` templates do not carry. ``source_dir`` is an
    optional directory of a stock map whose ``.trn``/``.LGT``/``.vxt`` are copied
    verbatim (these formats are template/copy-only). When a copy source is
    required but absent, :class:`BuildError` is raised.

    The file set is validated with :class:`MapValidator` (docs/06 Tier 1) before
    returning; any error raises :class:`BuildError`. Returns the map directory.
    """
    out_dir = Path(out_dir)
    map_dir = out_dir / name
    map_dir.mkdir(parents=True, exist_ok=True)

    # Re-derive the full pipeline deterministically from the result's seed.
    layout = build_layout(result.width_m, result.depth_m, result.n_teams, result.seed)
    heightmap = generate_terrain(layout, result.seed)
    economy = generate_economy(layout, heightmap, result.seed)
    spawns_sw = generate_spawns(layout, heightmap, mode="sw", seed=result.seed)
    spawns_s = generate_spawns(layout, heightmap, mode="s", seed=result.seed)
    variants = generate_variants(
        layout, heightmap, economy, spawns_sw, spawns_s, result.seed
    )

    # Terrain files generated from the pipeline.
    heightmap.write(map_dir / f"{name}.HG2")
    auto_paint(heightmap, _terrain_rules()).write(map_dir / f"{name}.MAT")

    # trn/LGT/vxt: copied from a stock source map when one is given, otherwise
    # written COMPLETE by the format writers (generator-fixes audit —
    # the previous behavior of skipping them entirely shipped [Size]-only trn
    # stubs, a lone-NSDF vxt and zero-fill LGTs straight into the pack).
    if source_dir is not None:
        source_dir = Path(source_dir)
        for suffix in COPY_SUFFIXES:
            src = source_dir / f"{name}{suffix}"
            if not src.is_file():
                # Try the stock source's own basename if it differs.
                cands = [p for p in source_dir.iterdir()
                         if p.is_file() and p.suffix.lower() == suffix.lower()]
                if cands:
                    src = min(cands)
                else:
                    raise BuildError(
                        f"no stock {suffix} source for {name} in {source_dir}"
                    )
            shutil.copy2(src, map_dir / f"{name}{suffix}")
    else:
        write_complete_trn(
            map_dir / f"{name}.trn", result.width_m, result.depth_m
        )
        write_standard_vxt(map_dir / f"{name}.vxt")
        # Structurally-valid zero lightmap; a packer must bake real shading
        # before shipping — never ship zeros directly, they render the
        # in-game map radar black (docs/01 §3).
        planes = heightmap.zonesX * heightmap.zonesZ + 1
        (map_dir / f"{name}.LGT").write_bytes(b"\x00" * (planes * 65536))

    # The four variant BZNs via template-and-mutate.
    loader = TemplateLoader(bzn_path=bzn_path)
    variant_objects = variants.variants()
    for suffix in VARIANT_SUFFIXES:
        bzn = _build_variant_bzn(loader, variant_objects[suffix].objects, name)
        fname = f"{name}{suffix}.bzn"
        bzn.write(map_dir / fname)

    # Metadata derived from the real object counts and dimensions.
    _s = variant_objects["_S"]
    geysers = len(_s.geysers)
    scrap = len(_s.scrap)
    players = max_players
    if mission_name is None or mission_name.strip().lower() == name.lower():
        raise BuildError(
            f"map {name}: mission_name must be a real display name, not the "
            "terrain slug — players see it in the lobby "
            "(generator-fixes audit)"
        )
    if size is None:
        size = size_band(result.width_m)
    if customtags is None:
        customtags = f"strategy, {size.lower()}, {world.lower()}"
    write_ini(
        map_dir / f"{name}.ini",
        mission_name,
        max_players=max_players,
        customtags=customtags,
    )
    write_des(
        map_dir / f"{name}.des",
        mission_name=mission_name,
        world=world,
        size=size,
        geysers=geysers,
        scrap=scrap,
        players=players,
    )
    write_odf(map_dir / f"{name}.odf")

    # Per-map thumbnails: 512x512 .BMP (shell/lobby) + 1024x1024 .png (the
    # in-game map image — 3/30 corpus maps ship one and its absence rendered a
    # blank map radar in testing; see the corrected docs/07).
    img = render_heightmap(heightmap)
    write_bmp(img, map_dir / f"{name}.BMP", size=THUMBNAIL_SIZE)
    write_png(img, map_dir / f"{name}.png", size=(1024, 1024))

    # Validate the whole set (docs/06 Tier 1) before returning.
    problems = MapValidator(map_dir).validate()
    if problems:
        raise BuildError(
            f"map {name} failed Tier 1 validation:\n" + "\n".join(problems)
        )
    return map_dir