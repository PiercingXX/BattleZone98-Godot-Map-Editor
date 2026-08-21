# Battlezone 98 Redux file formats — functional specification set

These documents are the **only** format authority available to the implementer.
The reference material they were derived from has been deleted from this
repository (see *Provenance* below). Do not go looking for it; it is gone on
purpose.

## What these are

Functional specifications: byte layouts, field tables, value semantics, ordering
rules, edge cases, and test vectors. They describe **what the files contain**,
not how anyone's program reads them. There is no code here, and there was no
code copied to produce them.

## Where implementations go

Every one of these formats is implemented in the **GDScript format layer**
under `project/backend/formats/`, ported from
the `bzmap` Python toolchain originally developed in the sibling repo
`battlezone98-map-generator`. Format code lives there and only there — the
editor UI never parses game bytes itself. See `AGENTS.md` §"the single most
important thing to understand".

When a module is added, record per module that it was built from this
specification set (directly or via the `bzmap` port) under the clean-room
process below. That note is the evidence if provenance is ever questioned.

## The documents

| Doc | Format | Used by |
|---|---|---|
| [F1](F1-hg2-heightfield.md) | `.hg2` terrain heightfield | session heights, sculpting |
| [F2](F2-mat-tilemap.md) | `.mat` terrain material tilemap, atlas layout, autotiling | material paint, atlas splat |
| [F3](F3-trn-and-bzn-ascii.md) | `.trn` terrain config, ASCII `.bzn` mission save | open / save / objects |
| [F4](F4-geo-mesh.md) | `.geo` classic mesh | viewport fidelity chain |
| [F5](F5-bwd2-vdf-sdf.md) | `.vdf` / `.sdf` BWD2 model containers | viewport fidelity chain |
| [F6](F6-map-act-textures.md) | `.map` texture image, `.act` palette | terrain atlas |
| [F7](F7-ogre-mesh-skeleton-material.md) | Redux HD: OGRE `.mesh` / `.skeleton` / `.material` | `hd` fidelity rung |
| [F8](F8-conventions-and-test-vectors.md) | Coordinate frames, enumerations, cross-format conventions, acceptance vectors | everything |

## Confidence marking

Every claim in these documents carries one of three markings. Respect them.

- **VERIFIED** — corroborated by two independent implementations that both
  round-trip real game files, or derivable from internal arithmetic that would
  not hold otherwise (e.g. a declared chunk size matching a computed record
  stride). Build on these.
- **OBSERVED** — a single working implementation depends on it, and real game
  files load. Almost certainly right; if reality disagrees, reality wins.
- **INFERRED** — reasoning from surrounding facts, not directly demonstrated.
  Treat as a hypothesis with an expected outcome. Confirming or refuting one is
  a real finding; write it into the generator repo's `docs/09-open-questions.md`.

An unmarked statement inherits the marking of its section heading.

## Provenance — the clean-room process

Two community Blender addons encoded more verified format knowledge than any
document available: a heightmap-based map editor addon (terrain side) and a
model-format addon (model side). One was GPL-3.0; the other stated no license at
all. Deriving `bzmap`'s converters from either by porting code would have made
`bzmap` a derivative work.

So the formats were **clean-roomed**, with a wall between two roles:

1. **Spec role.** Read the reference sources; write this specification set —
   facts, layouts, field semantics, edge cases, test vectors. No code, no
   excerpts, no paraphrased code structure. Where the two lineages disagreed,
   both readings are recorded and the disagreement is flagged rather than
   silently resolved.
2. **Implementation role.** Write `bzmap`'s format modules from this set alone,
   having never opened the reference sources. If a spec is ambiguous, the
   question goes back as a spec clarification request — not a peek.

The spec pass completed 2026-08-16 and the reference tree
(`resources/`) was deleted in the same change. The implementation role has
never had access to it.

**Interface facts are not copyrightable expression.** A struct layout, a chunk
ID, a nibble packing, a coordinate convention, and a value enumeration are
facts about a file produced by a third-party game engine, not creative
expression belonging to the addon authors. Sequences that *are* expression —
control flow, function decomposition, variable naming, algorithm implementation
— were deliberately not carried across. Where an algorithm was unavoidable
(§F2 autotiling), this set states the **requirement the output must satisfy**
and leaves the method to the implementer.

## Credit

The community authors whose reverse-engineering work made these facts knowable
are credited in the repository `README.md`. Losing the code does not mean losing
the acknowledgement.
