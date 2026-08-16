# F1 — `.hg2` terrain heightfield

Little-endian throughout. No magic number, no checksum, no trailing data.
Confidence: **VERIFIED** unless a line says otherwise.

## 1. File layout

```
offset  size  type    field
0x00    2     uint16  structure_version
0x02    2     uint16  zone_bits
0x04    2     uint16  map_width          (in zones)
0x06    2     uint16  map_depth          (in zones)
0x08    4     uint32  map_version
0x0C    ...   uint16  height word array
```

Header is 12 bytes. The height array immediately follows and runs to EOF.

- `structure_version` is 1 in every file observed.
- `map_version` is 10 in every file observed.
- Neither is validated by any known reader. Preserve both verbatim on rewrite;
  do not synthesise them.

## 2. Derived quantities

```
zone_length  = 2 ** zone_bits            vertices along one zone edge
zone_count   = map_width * map_depth
vertex_count = zone_count * zone_length**2
file_size    = 12 + 2 * vertex_count
```

For every stock and community map examined, `zone_bits == 8`, so
`zone_length == 256`.

**A zone is 1280 m square** and holds 256×256 height samples, giving a **5 m
horizontal sample spacing**. Map extent in metres is
`map_width * 1280` by `map_depth * 1280`.

Observed sizes: 1×1 (1280 m) through 4×4 (5120 m). 4 zones per side is the
maximum the reference editor would produce — **OBSERVED**, not proven to be an
engine limit.

## 3. Height word encoding

Each entry is a `uint16` split as:

```
bits 15..13   flag bits  (3 bits)   purpose unknown
bits 12..0    height     (13 bits)  0..8191, unit = decimetres
```

**Height in metres = raw & 0x1FFF, divided by 10.** So the encodable range is
0.0 m to 819.1 m.

The 13-bit width is **VERIFIED**: the reference reader masks `& 0x1FFF` with an
explicit note that doing so discards flag bits. The **meaning** of the upper
bits is **unknown** — no reference implementation reads or writes them, and no
observed behaviour depends on them.

### Consequences that are not optional

- **Preserve the flag bits.** When re-encoding a height the editor touched,
  read the original word, replace only bits 12..0, and write the original
  upper bits back. Writing zeros there is a silent data loss whose effect is
  unknown, which is the worst kind. Untouched cells must be byte-identical.
- **The 4095 (409.5 m) ceiling is an editor convention, not a format limit.**
  The reference editor clamps authored terrain to 0..409.5 m before writing.
  Stock maps exceed it: one observed stock map carries a raw value of 7630
  (763.0 m) and loads correctly in game. A reader that assumes 4095 is the
  maximum will corrupt stock terrain.

  This resolves the generator repo's open question E7 in favour of "13-bit
  field, editor-clamped authoring range". The editor may keep 409.5 m as its
  *brush* ceiling for authored terrain, but the *loader* must accept the full
  13-bit range and round-trip it.

## 4. Storage order — zone-interleaved, not row-major

This is the single easiest thing to get wrong. Heights are **not** stored as one
row-major grid across the whole map. They are stored zone by zone, and each zone
is row-major within itself.

Given a global vertex coordinate `(x, z)` with `x` in `[0, zone_length*map_width)`
and `z` in `[0, zone_length*map_depth)`:

```
zone_x = x // zone_length        sub_x = x % zone_length
zone_z = z // zone_length        sub_z = z % zone_length

index  = ((zone_z * map_width + zone_x) * zone_length + sub_z) * zone_length + sub_x
```

Reading that outward: zones are ordered row-major by `(zone_z, zone_x)` with
`map_width` zones per zone-row; within a zone, samples are ordered row-major by
`(sub_z, sub_x)` with `zone_length` samples per row.

The inverse, for iterating the file in storage order:

```
zone_i, sub_i = divmod(index, zone_length**2)
zone_z, zone_x = divmod(zone_i, map_width)
sub_z, sub_x   = divmod(sub_i, zone_length)
x = zone_x * zone_length + sub_x
z = zone_z * zone_length + sub_z
```

On a 1×1 map the interleave is the identity and a row-major reader appears to
work. It breaks on every larger map. **Test on a 2×2 map or larger.**

`.mat` uses the same zone-interleaved scheme at its own resolution — see F2 §3.

## 5. Axis orientation

`x` increases along the map's width axis; `z` increases along the map's depth
axis. Height is the up axis and is not stored per-axis.

The reference tooling had to flip its X vertex ordering and rotate its generated
mesh to align with in-game terrain, which means **the storage handedness does
not match a naive right-handed viewer setup**. The reliable calibration is not
an argument about signs — it is §7's test.

Relation to world/object coordinates (BZN `pos`, TRN `MinX`/`MinZ`) is specified
in F3 §2 and F8 §1. Terrain sample `(x, z)` and object position are **not** in
the same frame until the TRN offsets are applied.

## 6. Interchange buffer for the editor

`docs/02` defines `terrain.r16` as the session interchange buffer. Nail the
contract down here so both sides agree:

- `terrain.r16` is **plain row-major** across the whole map, `uint16`,
  little-endian, `(map_width*256)` values per row, `(map_depth*256)` rows.
- It carries **raw 13-bit height values only** — masked, flag bits stripped.
- The de-interleave (§4) and the flag-bit residue (§3) are `bzmap`'s
  responsibility, on both the read and the write side. The editor never sees a
  zone index and never sees a flag bit.
- On write-back, `bzmap` requires the original `.hg2` as the residue source. A
  write with no residue available must fail loudly rather than write zero flags.

## 7. Acceptance tests

1. **Byte-identical round trip.** Read and rewrite every corpus `.hg2` with no
   edits; every output must be byte-identical to its input, including the
   header's `structure_version` / `map_version` and every flag bit.
2. **Interleave correctness on a multi-zone map.** On a map ≥ 2×2, set exactly
   one vertex — say global `(x, z) = (300, 5)` on a 2×2 map — to a distinctive
   height, write, reload, and confirm the same global coordinate reads back
   changed and every other vertex is unchanged. A row-major reader passes the
   1×1 case and fails this one.
3. **13-bit range.** A map containing a raw value above 4095 must survive a
   round trip with that value intact. If no corpus map has one, synthesise it:
   set one cell to raw 7630, round trip, and confirm 7630 comes back.
4. **Flag-bit preservation.** Set a flag bit in a source file's word, round trip
   through an edit that changes a *different* cell, and confirm the flagged
   cell's upper bits survive.
5. **Size arithmetic.** `file_size == 12 + 2 * map_width * map_depth * 2**(2*zone_bits)`
   for every corpus file. A mismatch means the header was misread.
