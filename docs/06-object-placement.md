# 06 — Object placement

Mandatory feature #4: an openable panel showing every stock unit, placed onto
the map by raycast, aligned to the terrain normal as the user moves it.

## 1. The palette panel

A dockable panel over the asset index (`docs/05`):

- **Grid of icons**, grouped by category (craft, buildings, props, scrap,
  spawns, environment) and by faction where one applies (NSDF, CCA, Black Dog).
- **Search** by class name and by label.
- **Filter** by source layer (base game / BZP), with layers the current map
  cannot reach shown as unavailable and explained (`docs/05` §5).
- Each entry shows its **placement mode** — BZN or runtime (§5). This is not a
  detail to bury; it changes what the object *is* in the saved map.

Selecting an entry arms placement. `Esc` disarms.

## 2. Placement

With a class armed, a **ghost** of it follows the cursor across the terrain:

- Position from the analytic raycast (`docs/03` §4), snapped to the surface with
  **bilinear** height sampling.
- Orientation aligned to the **terrain normal** while moving, as specified.
- Click places. `Shift`+click places repeatedly without disarming.

### Terrain-normal alignment, and what to save

Aligning the ghost to the normal is what makes placement feel right and is what
was asked for. But the saved value needs care:

Stock objects are **pure yaw rotations about Y**; some props carry a slight tilt
in `up` matching the terrain normal (the generator repo measured a geyser at
`up = (0.019992, 0.9996, -0.019992)`), and its open question E5 has not settled
whether emitting a clean `up = (0,1,0)` looks wrong on slopes.

So: **align the ghost to the normal for feedback, and expose the saved
convention as a per-object choice** — `Upright` (clean `up`, the safe default)
or `Follow terrain` (tilt baked in). Default upright; let the user opt in per
object or per class. If E5 resolves in the generator repo, the default changes
there.

Note also that environment mesh carriers have their own hard rule: they ship the
**corpus basis byte-for-byte**, because the engine's internal axis handling
means no mathematically-derived basis reproduces it. Those objects are not
user-rotatable; the backend owns their transform (`docs/07` §5).

### Placement aids
- Optional grid snap (metres) and yaw snap (degrees).
- **Live spacing warning**: solid buildings closer than 40 m to another are
  flagged as they are placed — co-located buildings are a known map-breaker.
- Height readout under the cursor while placing.

## 3. Selection and manipulation

- Click to select, `Ctrl`+click to add, box-select by drag, `Ctrl`+`A` for all
  in the active variant.
- Move / rotate gizmos, plus numeric entry in the inspector. Rotation is yaw
  only for BZN objects, matching the corpus.
- Copy / paste / duplicate / delete.
- Multi-select edits apply to every selected object.
- Every operation goes through `ObjectCommand` on the undo stack (`docs/04` §4).

## 4. Objects re-snap when the ground moves

If a sculpt changes terrain under a placed object, the object's `y` is
re-derived by bilinear sample and its command is folded into that stroke's undo
record.

This is not optional polish. Objects sitting at a stale `y` after a sculpt is
exactly the class of defect the generator repo describes as certifying a map
that had *eight spawns underwater* — and the rule it wrote down afterwards was
**verify placement, not counts**. The editor's advantage is that it can simply
never let them drift.

Exception: objects the user has explicitly pinned to a fixed height (an
inspector toggle), which are flagged in the validation panel if they end up
below terrain.

## 5. The inspector

For the selected object(s):

| Field | Notes |
|---|---|
| Class (PrjID) | Re-typeable, within the same class layout only (§6) |
| Position | Metres, editable; `y` is derived unless pinned |
| Yaw | Degrees |
| Up convention | Upright / follow terrain (§2) |
| Team | 0 = neutral/world, 1 = team one, 8 = team two |
| Label | Auto-generated as `<PrjID><index>_<role>`; editable |
| Variant membership | Which of `` / `_S` / `_ST` / `_SW` this object belongs to |
| Placement mode | BZN or runtime — **read-only, from the asset index** |

Team defaults matter and are easy to get wrong: **scrap, geysers, and spawn
points are team 0**; the player is team 1; the wingman second base is team 8;
environment mesh carriers are team 0. The generator repo shipped team-1 economy
once and the scrap rendered as allied.

## 6. The class-layout law

**Read `docs/02` §6 and the generator repo's `docs/16` before implementing
placement.** The short version, because it constrains this panel directly:

A `[GameObject]` block's field set is **class-specific**, and the engine's
loader derails on a mismatch — usually crashing on the *next* object, which
makes it maximally confusing to debug. Five consecutive crash-to-lobby bugs in
the generator repo came from assembling, re-typing, or value-tweaking a block
instead of cloning a verified same-class one.

Consequences for this panel:

1. **The editor never constructs a block.** It records intent — class,
   position, yaw, team, label, variant — and the backend clones a verified
   template on save.
2. **Re-typing a class is restricted to the same class layout.** Turning a
   wingman into a howitzer in the inspector is not a text edit; it is a
   different block layout. Offer only compatible classes, and say why the others
   are excluded.
3. **Classes without a verified template are placed as runtime spawns**
   (`placement_mode: "runtime"`), emitted into the map's `MAP.lua` as
   host-guarded `BuildObject` calls rather than BZN blocks. Show this in the
   palette and inspector. It is not a lesser mode — it is what the operator
   arrived at independently, because BZN-placed craft acquire pilots at load and
   turn hostile even with an empty `curPilot`.

## 7. Variants

A map carries up to four object sets: base (deathmatch), `_S` (strategy), `_ST`,
`_SW` (wingman teams). The editor edits **one active variant at a time**, chosen
in the panel, with the others optionally shown ghosted for reference.

Rules the UI must encode, each one paid for by a crash or a play-test:

- **The base/deathmatch variant carries spawns, the player, and static meshes
  only.** No geysers, no scrap — zero of 36 corpus deathmatch files have them,
  and the DM loader dies on them *silently*. Economy belongs in `_S`/`_ST`/`_SW`.
- **Spawn counts**: base, `_ST`, and `_SW` carry the full ring (~14
  `pspwn_1`); only `_S` uses 2. A short `_SW` list makes
  `MapSpawnPoints[n]` nil and crashes the wingman game mode.
- **`_SW` spawns are side-grouped, not alternating**: indices 1–7 on one side,
  8–14 on the other. Alternating them puts players on the wrong side.

Offer a **"copy objects to variant"** action, since most maps share most of
their economy across `_S`/`_ST`/`_SW`, and flag violations of the rules above in
the validation panel (`docs/08`) rather than blocking the edit — the user may be
mid-way through a legitimate sequence.
