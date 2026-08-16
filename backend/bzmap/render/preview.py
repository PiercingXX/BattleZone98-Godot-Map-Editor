"""Top-down shaded heightmap render with overlays (docs/06 Reporting).

Produces the ``preview.png`` for a candidate map: a hillshaded, height-coloured
top-down view of the terrain, plus optional overlays for objects (economy
nodes, spawns), routes (connectivity), and regions (reachable / buildable
areas). The overlay geometry is expressed in **world metres** and mapped to
pixels internally, so callers feed plain ``(x_m, z_m)`` coordinates.

The renderer is deterministic: the same ``HeightMap`` and overlay geometry
always produce the same image, so a fixed seed reproduces byte-identical
previews (docs/08 fixed-seed determinism).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from bzmap.formats.hg2 import GRID_M, HEIGHT_SCALE

# Terrain colour ramp: deep water -> shallows -> lowland -> highland -> peak.
# Rows are (r, g, b); interpolated across the raw height range.
_TERRAIN = np.array(
    [
        (20, 40, 90),    # deep
        (40, 90, 140),   # water
        (70, 130, 90),   # lowland
        (150, 170, 90),  # scrub
        (200, 190, 160), # rock
        (235, 235, 235), # peak
    ],
    dtype=np.float64,
)


def _terrain_colormap(n=256):
    """Return an ``(n, 3)`` uint8 terrain colour ramp, low height -> high."""
    xs = np.linspace(0.0, 1.0, len(_TERRAIN))
    out = np.empty((n, 3), dtype=np.float64)
    for c in range(3):
        out[:, c] = np.interp(np.linspace(0.0, 1.0, n), xs, _TERRAIN[:, c])
    return out.astype(np.uint8)


def render_heightmap(heightmap, size=None):
    """Render a hillshaded, height-coloured top-down ``PIL.Image`` (RGB).

    ``size`` is ``(width, height)`` in pixels; defaults to the full grid
    resolution ``(grid_x, grid_z)``. The image is oriented **north-up**: world
    ``+x`` points right and world ``+z`` points UP — matching the game's own
    map images. (Measured against the corpus BMPs: on the asymmetric maps the
    community-authored thumbnails are the vertical mirror of a z-down render,
    so z-down was upside down versus what players see in the shell.)
    """
    if size is None:
        size = (heightmap.grid_x, heightmap.grid_z)
    w, h = size

    raw = heightmap.data.astype(np.float64) * HEIGHT_SCALE

    # Hillshade from a north-west light: flat cells are bright, steep cells
    # darken. The ``1/(1+grad)`` form is bounded in [0, 1], monotonic, and
    # robust to arbitrarily large (even infinite) gradients — unlike a
    # ``grad/max_grad`` normalisation, it cannot produce NaN that casts to
    # black.
    dz, dx = np.gradient(raw, GRID_M, GRID_M)
    grad = np.hypot(dx, dz)
    shade = 1.0 / (1.0 + grad)

    # Colour by absolute height across the full 12-bit raw range (0-4095), so
    # a flat map renders at its own elevation colour rather than collapsing to
    # the bottom of the ramp. Playable terrain sits on a plateau well above
    # zero (hg2 docstring), so a flat map at raw 1000 is mid-ramp, not "deep".
    lo, hi = 0.0, 4095.0
    span = hi - lo
    idx = ((raw - lo) / span * 255.0).astype(np.uint8)
    colour = _terrain_colormap()[idx]

    # Combine: colour scaled by the shade factor, flipped so +z is UP.
    shaded = np.flipud((colour * shade[..., None]).astype(np.uint8))

    # Downscale/upscale from grid resolution to the requested pixel size.
    img = Image.fromarray(np.ascontiguousarray(shaded), "RGB")
    if (w, h) != (heightmap.grid_x, heightmap.grid_z):
        img = img.resize((w, h), Image.BILINEAR)
    return img


def _world_to_px(heightmap, size, x, z):
    """Map world metres ``(x, z)`` to pixel ``(col, row)`` in a ``size`` image.

    North-up: ``z = 0`` is the BOTTOM row, matching :func:`render_heightmap`.
    """
    w, h = size
    col = x / heightmap.width_m * (w - 1)
    row = (1.0 - z / heightmap.depth_m) * (h - 1)
    return round(col), round(row)


class Preview:
    """A shaded heightmap image plus overlay drawing helpers.

    Holds the rendered base image and the coordinate transform so overlays can
    be drawn in world-metre coordinates. ``size`` defaults to the full grid
    resolution.
    """

    def __init__(self, heightmap, size=None):
        self.heightmap = heightmap
        self.size = size if size is not None else (heightmap.grid_x, heightmap.grid_z)
        self.image = render_heightmap(heightmap, self.size)
        self._draw = ImageDraw.Draw(self.image)

    def _px(self, x, z):
        return _world_to_px(self.heightmap, self.size, x, z)

    def draw_points(self, points, color=(255, 0, 0), radius=3):
        """Draw filled circles at world ``(x, z)`` points."""
        for x, z in points:
            px = self._px(x, z)
            self._draw.ellipse(
                [px[0] - radius, px[1] - radius, px[0] + radius, px[1] + radius],
                fill=color,
            )

    def draw_routes(self, routes, color=(255, 255, 0), width=2):
        """Draw polylines; ``routes`` is a list of ``[(x, z), ...]`` point lists."""
        for pts in routes:
            px = [self._px(x, z) for x, z in pts]
            if len(px) >= 2:
                self._draw.line(px, fill=color, width=width)

    def draw_regions(self, regions, color=(0, 255, 0), alpha=60):
        """Tint grid-shaped boolean masks over the image.

        ``regions`` is a list of boolean arrays shaped like ``heightmap.data``;
        each True cell is tinted ``color`` at ``alpha``/255 opacity.
        """
        base = np.asarray(self.image).astype(np.int16)
        tint = np.array(color, dtype=np.int16)
        for mask in regions:
            m = np.asarray(mask, dtype=bool)
            if m.shape != self.heightmap.data.shape:
                raise ValueError(
                    f"region mask shape {m.shape} != heightmap {self.heightmap.data.shape}"
                )
            # Flip to the image's north-up orientation, then downscale the
            # mask to the pixel size with nearest-neighbour.
            mi = Image.fromarray((np.flipud(m) * 255).astype(np.uint8))
            if self.size != (self.heightmap.grid_x, self.heightmap.grid_z):
                mi = mi.resize(self.size, Image.NEAREST)
            mpx = np.asarray(mi) > 127
            base[mpx] = (base[mpx] * (255 - alpha) + tint * alpha) // 255
        self.image = Image.fromarray(base.astype(np.uint8), "RGB")
        self._draw = ImageDraw.Draw(self.image)

    def save(self, path):
        """Write the preview to ``path`` as PNG."""
        self.image.save(Path(path))


def render_preview(heightmap, objects=None, routes=None, regions=None, size=None):
    """Build a full preview: shaded terrain plus optional overlays.

    - ``objects`` — list of ``(x_m, z_m)`` points (economy nodes, spawns).
    - ``routes`` — list of ``[(x_m, z_m), ...]`` polylines (connectivity).
    - ``regions`` — list of boolean grid masks (reachable / buildable areas).

    Returns a :class:`Preview` whose ``.image`` is the finished render.
    """
    pv = Preview(heightmap, size)
    if regions:
        pv.draw_regions(regions)
    if routes:
        pv.draw_routes(routes)
    if objects:
        pv.draw_points(objects)
    return pv