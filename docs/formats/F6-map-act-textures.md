# F6 — `.map` texture image and `.act` palette

Little-endian. Confidence: **VERIFIED** for the layouts; **OBSERVED** for the
palette-resolution rule in §4.

**`.map` is a texture image format. It has nothing to do with terrain.** The
name collision with "map" as in "game level" is unfortunate and has burned
people; terrain lives in `.hg2` / `.mat` / `.trn` (F1–F3).

## 1. `.map` header — 8 bytes

```
offset  size  type      field
0x00    2     uint16    row_byte_size    bytes per scanline, NOT pixels
0x02    2     uint16    pixel_format     §2
0x04    2     uint16    height           rows
0x06    2     uint16    unknown          purpose unknown; preserve verbatim
```

Pixel data follows immediately: `row_byte_size × height` bytes, **top row
first**.

```
bytes_per_pixel = BPP[pixel_format]
width           = row_byte_size / bytes_per_pixel
file_size       = 8 + row_byte_size × height
```

`row_byte_size` being in **bytes** rather than pixels is the standard mistake.
For an indexed image the two coincide, which is exactly why the bug survives
until someone loads a 32-bit texture.

## 2. Pixel formats

| value | name | bytes/px | layout |
|---|---|---|---|
| 0 | INDEXED | 1 | one palette index per pixel (§3) |
| 1 | ARGB4444 | 2 | uint16; A = bits 15–12, R = 11–8, G = 7–4, B = 3–0 |
| 2 | RGB565 | 2 | uint16; R = bits 15–11, G = 10–5, B = 4–0; alpha implied opaque |
| 3 | ARGB8888 | 4 | **byte order on disk is B, G, R, A** |
| 4 | XRGB8888 | 4 | same byte order; the fourth byte is ignored, alpha is opaque |

Formats 3 and 4 are byte-ordered **BGRA on disk** despite the "ARGB" naming —
the name describes the packed word on a little-endian machine, and reading it
bytewise gives B, G, R, A. Getting this backwards produces images with red and
blue swapped, which is subtle enough on grey industrial textures to ship
unnoticed.

Channel expansion for the packed 16-bit formats: divide by the field maximum,
i.e. 4-bit fields by 15, 5-bit by 31, 6-bit by 63.

## 3. `.act` palette

A raw, headerless **768-byte** file: 256 entries × 3 bytes, `R, G, B`, each
0–255. No alpha, no header, no terminator. A file of any other length is not a
valid `.act`.

## 4. Which palette an indexed texture uses

**The texture does not say.** An indexed `.map` carries indices and nothing
else; the palette is selected by the **world's `.trn`**.

The practical consequence, recorded by the reference tooling: all indexed
textures are expected to look correct under **any** of the standard per-world
`.act` palettes, which is why a converter can get away with a single default
palette. That is a working assumption, not a guarantee — **OBSERVED**.

For the editor's asset converter:

1. Prefer the palette named by the map's `.trn`.
2. Fall back to any `.act` found near the texture.
3. Fall back to a bundled default only if the editor ships one — and it must
   not, since `.act` files are game content (`AGENTS.md` rule 3). Prefer
   failing to `proxy` fidelity with a stated reason over shipping a palette.

If no palette resolves, an indexed texture can still be rendered as greyscale
from its raw indices. That is legible enough to identify a texture and is a
better failure than a magenta placeholder.

## 5. Name resolution

`.map` names come from `.geo` face records (F4 §3) **without a path and without
an extension**. Resolve by:

1. exact `<name>.map` in the model's own directory;
2. then a case-insensitive walk of that directory tree;
3. then the configured asset search path.

Case-insensitivity is mandatory, not a nicety — stock content mixes
`MN00SA0.MAP` and `mn00sa0.map` and the game is served by a case-insensitive
filesystem. On Linux, a case-sensitive lookup silently fails on roughly half of
stock content.

## 6. Conversion targets

For the editor's mesh cache, textures are converted to **PNG**.
Straightforward: decode per §2, apply the palette per §3–4, write RGBA.

For Redux HD material scripts (F7 §5), textures are referenced as **DDS**, named
`<basename>_D.dds` — the `_D` suffix marking the diffuse map. The reference
porting tool writes uncompressed A8R8G8B8 DDS; there is no need for the editor
to write DDS at all, since it consumes rather than produces Redux content.

## 7. Acceptance tests

1. **Byte-identical round trip** on every corpus `.map`, no edits, including the
   `unknown` header field.
2. **Size arithmetic.** `file_size == 8 + row_byte_size × height` for every
   corpus file; a mismatch means `row_byte_size` was read as pixels.
3. **Format coverage.** Confirm the corpus contains at least one file of each
   `pixel_format` present in the install, and decode each without special-casing.
4. **Channel order.** Convert a 32-bit texture with a strongly-coloured region
   and compare against the same surface in game. Swapped red and blue is the
   failure signature.
5. **Palette.** Decode an indexed texture with a real `.act` and confirm the
   result is not greyscale and not obviously wrong-hued.
6. **Case-insensitive lookup** succeeds on a Linux filesystem for a texture whose
   `.geo` reference differs in case from the file on disk.
