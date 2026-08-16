"""Generate per-map static meshes: water surfaces and plant fields.

Automated, no Blender. Emits an OGRE ``.mesh`` (via
:mod:`bzmap.formats.mesh`) plus its paired ``.material`` and an ``.odf`` that
the engine loads as static geometry (``classLabel = i76building2``, exactly
the corpus ``desrten1`` water-surface class). Place a single BZN object of the
mesh's PrjID at the world origin and the geometry appears in world space.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from bzmap.formats.hg2 import HEIGHT_SCALE
from bzmap.formats.mesh import write_mesh

# --- materials ---------------------------------------------------------------

#: Oasis's actual water: additive-blended blue, double-sided, depth-write off,
#: with a scrolling water texture (``thecavew.png`` - ships in the corpus pack's asset
#: layer). This is copied from the corpus ``desrten1.material`` (the water surface
#: the operator asked to match), renamed so it does not collide.
_WATER_MATERIAL = """\
import * from "BZBase.material"

// The water pass shipped community maps use, and the look play-testing
// settled on: a blue additive wash over a scrolling ripple texture.
// depth_write OFF makes the pool genuinely see-through; fog_override keeps
// distant water from tinting toward the fog colour. Deepen or lighten the
// blue by scaling ambient/diffuse together.
material {name}
{{
\ttechnique
\t{{
\t\tpass
\t\t{{
\t\t\tambient 0.12 0.35 0.80
\t\t\tdiffuse 0.12 0.35 0.80
\t\t\tscene_blend add
\t\t\tcull_hardware none
\t\t\tcull_software none
\t\t\tdepth_write off
\t\t\tfog_override true
\t\t\ttexture_unit
\t\t\t{{
\t\t\t\ttexture thecavew.png
\t\t\t\tscroll_anim 0.0 0.04
\t\t\t}}
\t\t}}
\t}}
}}
"""

#: Alpha-tested plant billboards, from the corpus ``bomadenv.material`` (EoPlnt01,
#: "Bushes"). Ships texture ``EoPlnt01_D.dds``.
_PLANT_MATERIAL = """\
import * from "BZBase.material"

material {name}
{{
\ttechnique
\t{{
\t\tpass
\t\t{{
\t\t\tscene_blend alpha_blend
\t\t\talpha_rejection greater_equal 128
\t\t\tcull_hardware none
\t\t\tcull_software none
\t\t\ttexture_unit
\t\t\t{{
\t\t\t\ttexture EoPlnt01_D.dds
\t\t\t}}
\t\t}}
\t}}
}}
"""

#: Static-geometry ODF: same class the corpus maps use for water/scenery meshes. The
#: engine loads ``<odfname>.mesh`` by basename; ``maxHealth`` huge so nothing
#: destroys it.
_STATIC_ODF = """\
[GameObjectClass] // generated static geometry
classLabel = "i76building2"
scrapCost = 0
scrapValue = 0
maxHealth = 99999999
maxAmmo = 0
unitName = "{unit}"
heatSignature = 0
imageSignature = 0
radarSignature = 0
"""


def _write_material(path, template, name):
    # OGRE material files are ASCII. A stray non-ASCII char in a comment (an
    # em-dash slipping into a template) used to crash the whole map build;
    # degrade it to '?' rather than abort.
    text = template.format(name=name).encode("ascii", "replace").decode("ascii")
    Path(path).write_text(text, newline="\r\n")


def _write_static_odf(path, unit):
    Path(path).write_text(_STATIC_ODF.format(unit=unit), encoding="ascii", newline="\r\n")


# --- water -------------------------------------------------------------------

def build_water_surface(out_dir, stem, heightmap, water_level_m, *,
                        material="water", tile_m=10.0, margin_below_m=1.0,
                        region_mask=None):
    """Emit a water-surface mesh covering every cell below ``water_level_m``.

    A horizontal plane at ``water_level_m`` is generated over the map, but only
    the quads whose underlying terrain sits below the surface (minus
    ``margin_below_m``) are kept - so the water fills low ground and trenches
    and stops at the shoreline, exactly like Oasis. Vertices are in world
    metres; place the object at the origin.

    ``region_mask`` (a heightmap-shaped boolean array) restricts water to those
    cells — pass the trench mask so water fills ONLY the trench and not every
    gully/dip that happens to sit below the waterline (the top-down debug render
    showed water pooling map-wide without this).

    Writes ``<stem>.mesh`` / ``.material`` / ``.odf`` into ``out_dir`` and
    returns the mesh PrjID (== ``stem``, <= 8 chars, the engine's basename bind).
    Returns ``None`` when no ground is underwater (no mesh written).
    """
    out_dir = Path(out_dir)
    heights = heightmap.data.astype(np.float64) * HEIGHT_SCALE  # (gz, gx) metres
    gz, gx = heights.shape
    cell_m = 5.0  # HG2 grid spacing
    step = max(1, int(round(tile_m / cell_m)))
    if region_mask is not None:
        region_mask = np.asarray(region_mask, dtype=bool)

    verts, norms, uvs, tris = [], [], [], []
    vindex = {}

    def vert(ix, iz):
        key = (ix, iz)
        v = vindex.get(key)
        if v is not None:
            return v
        wx = ix * cell_m
        wz = iz * cell_m
        v = len(verts)
        verts.append((wx, water_level_m, wz))
        norms.append((0.0, 1.0, 0.0))
        uvs.append((wx / 64.0, wz / 64.0))  # tiles the scrolling texture
        vindex[key] = v
        return v

    def underwater(iz, ix):
        z, x = min(iz, gz - 1), min(ix, gx - 1)
        if region_mask is not None and not region_mask[z, x]:
            return False
        return heights[z, x] < water_level_m - margin_below_m

    for iz in range(0, gz - step, step):
        for ix in range(0, gx - step, step):
            # keep the quad if any of its four corner cells is underwater
            corners = [(iz, ix), (iz, ix + step), (iz + step, ix), (iz + step, ix + step)]
            if not any(underwater(z, x) for z, x in corners):
                continue
            a = vert(ix, iz)
            b = vert(ix + step, iz)
            c = vert(ix, iz + step)
            d = vert(ix + step, iz + step)
            tris += [a, c, b, b, c, d]

    if not tris:
        return None

    _write_material(out_dir / f"{stem}.material", _WATER_MATERIAL, material)
    _write_static_odf(out_dir / f"{stem}.odf", f"{stem} water")
    # The submesh material name must match the .material's material name.
    # Mesh-local vertices are the TRANSPOSE of world coordinates (x<->z):
    # the engine applies the carrier object's transform basis and then
    # NEGATES Z (a handedness flip no pure-rotation basis can cancel,
    # det -1). Shipped maps therefore pair a -90-degree carrier basis
    # (right=(7.54979e-008, 0, -1), front=(1, 0, 7.54979e-008), posit 0)
    # with transposed vertices: local (wz, y, wx) lands at world (wx, wz).
    # Verified in-game: world-coordinate verts render transposed (a
    # symmetric ring sits in place while an N-S strip comes out E-W).
    write_mesh(out_dir / f"{stem}.mesh", [(z, y, x) for (x, y, z) in verts],
               norms, uvs, tris, material)
    return stem


# --- plants ------------------------------------------------------------------

def build_plant_field(out_dir, stem, heightmap, *, seed, count=260,
                      material="plants", min_slope_deg=0.0, max_slope_deg=12.0,
                      avoid=(), avoid_radius_m=140.0, blade_h_m=4.0,
                      blade_w_m=2.2, water_level_m=None):
    """Emit a plant-field mesh: ``count`` crossed alpha billboards scattered on
    gentle, dry ground, away from ``avoid`` points (bases/sites).

    Each plant is two perpendicular quads (a cross-billboard, the standard cheap
    vegetation primitive), ground-snapped and randomly rotated/scaled. Writes
    ``<stem>.mesh`` / ``.material`` / ``.odf``; returns the PrjID, or ``None``
    if nothing could be placed.
    """
    out_dir = Path(out_dir)
    heights = heightmap.data.astype(np.float64) * HEIGHT_SCALE
    gz, gx = heights.shape
    cell_m = 5.0
    gyf, gxf = np.gradient(heights, cell_m)
    slope_deg = np.degrees(np.arctan(np.hypot(gxf, gyf)))

    rng = np.random.default_rng(seed)
    verts, norms, uvs, tris = [], [], [], []
    placed = 0
    attempts = 0
    max_attempts = count * 40

    def sample_h(wx, wz):
        # bilinear - nearest-cell sampling floated billboards over the engine's
        # smoothly-interpolated terrain.
        fx, fz = wx / cell_m, wz / cell_m
        ix, iz = int(fx), int(fz)
        ix1, iz1 = min(ix + 1, gx - 1), min(iz + 1, gz - 1)
        tx, tz = fx - ix, fz - iz
        h0 = heights[iz, ix] * (1 - tx) + heights[iz, ix1] * tx
        h1 = heights[iz1, ix] * (1 - tx) + heights[iz1, ix1] * tx
        return h0 * (1 - tz) + h1 * tz, slope_deg[min(iz, gz - 1), min(ix, gx - 1)]

    while placed < count and attempts < max_attempts:
        attempts += 1
        wx = float(rng.uniform(60, (gx - 1) * cell_m - 60))
        wz = float(rng.uniform(60, (gz - 1) * cell_m - 60))
        h, s = sample_h(wx, wz)
        if not (min_slope_deg <= s <= max_slope_deg):
            continue
        if water_level_m is not None and h < water_level_m:
            continue
        h -= 2.5  # sink the billboard base well into the ground so the
        # opaque part of the plant texture (upper portion of the UV) roots at
        # ground level rather than floating, and slope-float is hidden
        if any((wx - ax) ** 2 + (wz - az) ** 2 < avoid_radius_m ** 2 for ax, az in avoid):
            continue

        placed += 1
        yaw = float(rng.uniform(0, np.pi))
        hh = blade_h_m * float(rng.uniform(0.7, 1.3))
        hw = blade_w_m * 0.5 * float(rng.uniform(0.7, 1.3))
        for a in (yaw, yaw + np.pi / 2):
            dx, dz = np.cos(a) * hw, np.sin(a) * hw
            base = len(verts)
            quad = [
                (wx - dx, h, wz - dz, 0.0, 1.0),
                (wx + dx, h, wz + dz, 1.0, 1.0),
                (wx - dx, h + hh, wz - dz, 0.0, 0.0),
                (wx + dx, h + hh, wz + dz, 1.0, 0.0),
            ]
            for x, y, z, u, v in quad:
                verts.append((x, y, z))
                norms.append((0.0, 0.0, 1.0))
                uvs.append((u, v))
            tris += [base, base + 2, base + 1, base + 1, base + 2, base + 3]
        if len(verts) > 64000:  # 16-bit index safety
            break

    if not tris:
        return None

    _write_material(out_dir / f"{stem}.material", _PLANT_MATERIAL, material)
    _write_static_odf(out_dir / f"{stem}.odf", f"{stem} plants")
    # Transposed local frame — see the identical note in build_water_surface.
    write_mesh(out_dir / f"{stem}.mesh", [(z, y, x) for (x, y, z) in verts],
               norms, uvs, tris, material)
    return stem
