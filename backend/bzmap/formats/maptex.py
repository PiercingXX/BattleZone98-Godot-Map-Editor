"""``.map`` / ``.act`` texture decode (docs/formats/F6)."""

from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

_BPP = {0: 1, 1: 2, 2: 2, 3: 4, 4: 4}


def read_act(path):
    data = Path(path).read_bytes()
    if len(data) != 768:
        raise ValueError(f"{path}: .act must be 768 bytes, got {len(data)}")
    return [(data[i], data[i + 1], data[i + 2]) for i in range(0, 768, 3)]


def read_map(path, palette=None) -> Image.Image:
    data = Path(path).read_bytes()
    if len(data) < 8:
        raise ValueError(f"{path}: too short")
    row_b, fmt, height, _unk = struct.unpack_from("<HHHH", data, 0)
    bpp = _BPP.get(fmt)
    if not bpp or row_b == 0:
        raise ValueError(f"{path}: bad format {fmt} row_b {row_b}")
    width = row_b // bpp
    need = 8 + row_b * height
    if len(data) < need:
        raise ValueError(f"{path}: truncated ({len(data)} < {need})")
    pixels = bytearray()
    src = 8
    for _y in range(height):
        row = data[src:src + row_b]
        src += row_b
        if fmt == 0:
            pal = palette or [(i, i, i) for i in range(256)]
            for i in row:
                r, g, b = pal[i]
                pixels.extend((r, g, b, 255))
        elif fmt == 1:
            for i in range(0, len(row), 2):
                w = row[i] | (row[i + 1] << 8)
                a = ((w >> 12) & 15) * 17
                r = ((w >> 8) & 15) * 17
                g = ((w >> 4) & 15) * 17
                b = (w & 15) * 17
                pixels.extend((r, g, b, a))
        elif fmt == 2:
            for i in range(0, len(row), 2):
                w = row[i] | (row[i + 1] << 8)
                r = int(((w >> 11) & 31) * 255 / 31)
                g = int(((w >> 5) & 63) * 255 / 63)
                b = int((w & 31) * 255 / 31)
                pixels.extend((r, g, b, 255))
        else:
            # BGRA on disk
            for i in range(0, len(row), 4):
                b, g, r, a = row[i], row[i + 1], row[i + 2], row[i + 3]
                if fmt == 4:
                    a = 255
                pixels.extend((r, g, b, a))
    return Image.frombytes("RGBA", (width, height), bytes(pixels))
