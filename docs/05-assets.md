# 05 — Assets: enumeration, conversion, and fidelity

Q3 and Q4: every placeable class, enumerated **live** from the user's own
install — base game *and* BZP asset layers, units and buildings, not just props
— rendered as faithfully as we can manage.

## 1. Nothing ships with the editor

The editor contains **no game assets**. Not meshes, not textures, not ODFs, not
corpus BZN blocks. This repo is going public and that content belongs to
Rebellion and to the BZP authors.

Everything comes from the user's own installation at runtime, converted into a
local cache outside both repos. A user without the game gets an editor that
runs, navigates, and sculpts, and says clearly why the object palette is empty.

## 2. Enumeration is a backend job

`bzmap editor assets` (`docs/02` §3) walks the install and produces the asset
index plus a cache of converted meshes and icons. It runs in Python because the
binary parsing already lives there (`bzmap/formats/geo.py`, `sdf.py`, `odf.py`)
and because the editor is forbidden from parsing game formats (`AGENTS.md`).

Sources, in layers:
- the base game install (all stock classes),
- each subscribed workshop item the user points at, BZP being the important one.

Each class in the index records which layer it came from, because of §5.

**Phase 0 discovery task, not a guess:** the generator repo has verified parsers
for `.geo` and `.sdf` and knows where `Edit/trn/` templates live, but it does
**not** document where ODFs, vehicle meshes, and textures physically live in a
BZ98R install — loose in directories, or packed in `.zfs` archives (a
`MakeZFS.exe` ships with the game, which is suggestive but not evidence). Nor
does it document the Redux **HD** model format.

Skippy must inventory a real install first and write the findings into the
generator repo's format docs before building the converter. Do not guess a
layout. If `.zfs` unpacking turns out to be required, that is a `bzmap`
format module with its own tests, like every other format in that repo.

## 3. The fidelity chain

Q4 was "I want it all if possible". The honest engineering answer is a defined
degradation chain, so that "as good as possible" is a per-asset outcome rather
than an all-or-nothing gamble:

| `mesh_fidelity` | What it is | When |
|---|---|---|
| `hd` | The Redux HD model, textured | If the HD format is decodable (unknown today — see `docs/10`) |
| `geo_textured` | Legacy `.geo`/`.sdf` geometry with its material textures applied | The expected common case for buildings |
| `geo_flat` | Legacy geometry with per-face flat colours from the `.geo` face records | Geometry parsed, textures unresolved |
| `proxy` | A labelled box at the class's real footprint and height | Nothing decodable |

The chain is per-class and recorded in the index, so the editor can show the
user exactly what they are looking at, and so an improvement to the converter
lifts everything without an editor change.

**A proxy is not a failure state to hide.** Correct footprint and height are
what placement decisions actually depend on — spacing buildings ≥ 40 m apart,
seeing whether a hangar fits on a pad. A labelled box at true size is a working
tool. Render proxies in a distinct style and list unresolved classes in the
asset panel so gaps are visible and fixable.

## 4. Terrain atlases

Q5 asks for real splatting in the viewport. The atlas named in the `.trn`'s
`[Atlases] MaterialName` is extracted and converted by the same backend pass and
referenced by the terrain shader (`docs/03` §3).

Two things to get right:

- **The MAT bit layout is still marked INFERRED** in the generator repo
  (`docs/01` §2, open question E3): `[matA:4][matB:4][variant:4][0:4]`. The
  viewport is the best test that has ever existed for it — load a stock map,
  splat it, and compare against the same map in game. Agreement confirms E3;
  disagreement is a real finding that belongs back in the generator repo's docs.
  **Treat this as an experiment with an expected outcome, not as settled.**
- Fall back gracefully: if the atlas cannot be extracted, splat with the
  `[TextureType*]` `FlatColor` values instead. A flat-coloured map that shows
  material *boundaries* correctly is still a usable painting surface.

## 5. Assets do not cross workshop items

An engine rule with direct UI consequences: ODFs, meshes, sounds, and textures
resolve from the base game **plus the map's own pack only**. Lua crosses via
`RequireFix`; assets never do.

So the palette is filtered by the map's `pack_context` (`docs/02` §4):

- `{"kind": "base"}` — base-game classes only.
- `{"kind": "bzp", ...}` — base game plus the BZP asset layer.

A class from a layer the current map cannot reach must be **visibly
unavailable**, with the reason stated, rather than absent or silently placeable.
Placing one produces a map that loads for the author and fails for everyone
else, which is the worst failure mode there is.

## 6. The cache

- Lives in the user data directory, never in either repo, never committed.
- Keyed by a fingerprint of the source install (`source_fingerprint` in the
  index). A game patch or a BZP update changes it, and the editor offers a
  rebuild rather than serving stale meshes.
- Rebuildable at any time from the asset panel; a corrupted cache is never a
  reason to reinstall anything.
- Meshes as `.glb`, icons and textures as `.png` — both loadable by Godot at
  runtime with no import step, which is what makes an exported build able to
  use them at all.

## 7. Icons

Every class needs a palette thumbnail. Generate them in the backend at cache
build time by rendering each converted mesh from a fixed three-quarter angle to
a PNG. Uniform framing and lighting across the set; the palette is a grid of
hundreds of entries and inconsistent icons make it unscannable.

Proxy-only classes get a generated placeholder icon carrying the class name and
footprint, not a blank.
