"""Workshop item thumbnail generation (docs/07 pack layout).

The pack ships a per-map ``.png`` and ``.BMP`` and a top-level ``preview.png``
workshop thumbnail. All derive from the same rendered image, resized to the
workshop thumbnail size. ``.BMP`` is written separately because PIL's ``save``
format is inferred from the extension, and workshop items expect the
uncompressed BMP container.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

# Default workshop thumbnail size in pixels (square).
THUMBNAIL_SIZE = (512, 512)


def _resized(img, size):
    """Return ``img`` resized to ``size`` (no-op when already that size)."""
    if img.size == tuple(size):
        return img
    return img.resize(tuple(size), Image.LANCZOS)


def write_png(img, path, size=THUMBNAIL_SIZE):
    """Resize ``img`` to ``size`` and write it as a PNG to ``path``."""
    _resized(img, size).save(Path(path), format="PNG")


def write_bmp(img, path, size=THUMBNAIL_SIZE):
    """Resize ``img`` to ``size`` and write it as a BMP to ``path``."""
    _resized(img, size).save(Path(path), format="BMP")


def write_thumbnail(img, png_path, bmp_path, size=THUMBNAIL_SIZE):
    """Write both the PNG and BMP thumbnails from ``img`` at ``size``."""
    resized = _resized(img, size)
    resized.save(Path(png_path), format="PNG")
    resized.save(Path(bmp_path), format="BMP")