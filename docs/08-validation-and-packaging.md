# 08 — Validation panel and packaging buttons

Q8 (report panel) and Q9 (buttons). Both are thin UI over machinery that already
exists in the generator repo. **The editor implements no validation logic of its
own.**

## 1. Why no editor-side validation

The generator repo's validators are calibrated against the whole 36-map corpus:
every stock map must pass every error-severity check, and there are deliberate
broken fixtures asserting each validator actually catches its defect. That
calibration is the thing that stops a validator being confidently, invisibly
wrong.

A second implementation in GDScript would have none of that, would drift, and
would produce the worst outcome available: two tools disagreeing about whether a
map is valid. So the panel is a **view over `bzmap editor validate`** output,
and nothing else. DoD #5 is exactly this.

The one thing the editor *does* own is **live authoring feedback** — the 40 m
building-spacing warning while placing, the slope readout on the ramp tool, the
stem-length check in the wizard. Those are hints at the moment of the action,
not verdicts on the map, and they are cheap enough to run per-frame. They never
contradict the validators; where they overlap, the validator is authoritative.

## 2. The findings panel

Runs on save, and on demand from the toolbar.

Each finding shows severity, id, title, and detail, and — this is what makes the
panel worth building — **click to fly the camera to it**. The backend supplies
`world_pos`, `object_id`, and `variant` per finding (`docs/02` §3), so a
connectivity failure or an underwater spawn becomes a place you go look at
rather than a coordinate you decode.

- Group by severity, then by rule id.
- Filter by variant, since a finding on `_SW` is invisible while editing `_S`.
- Highlight the offending object in the viewport on selection.
- Findings persist until the next run; a stale set is labelled stale after any
  edit, so nobody trusts a report that predates their change.

Zero findings is the target and is achievable — the generator repo's Tier 1
validator scores 0 on a correct map, and the noise has been cleaned out, so any
non-zero count means something. Present it that way.

## 3. The packaging buttons

Each calls `bzmap editor package` or `render` (`docs/02` §3):

**Save** — write the file set to the map's output directory. Reports which
files came out byte-identical to the source (`docs/07` §2).

**Render thumbnail** — regenerate `.png` and `.BMP` from the current state,
north-up, and show them in the overview panel. Run automatically on save; the
button is for iterating on the image without a full save.

**Install to test mod** — copy the file set into a **separate test mod
directory** and enable it. Never into the game directory, never into BZP.
Both of those are read-only reference data, without exception.

**Assemble pack** — wrap the existing pack assembly for the BZP-T style
workflow. Only shown when `pack_context` is BZP.

**Launch in game** *(optional, if it proves reliable)* — the game accepts
`battlezone98redux.exe <map>.bzn /startedit /win`, which loads a map directly
into the in-game editor. That is a **load gate only** — the in-game editor has
no collision — but "does the engine accept this file set at all" is the single
most valuable answer in the whole loop, and getting it without a manual launch
is worth a button. On Linux this goes through Proton, which is why it is
optional: build it only if it works without fragile shell plumbing.

## 4. What the editor must never claim

The operator's standing rule, and it applies to this panel's wording:

> Nothing is verified in-game until it is played.

A clean validation report means the offline checks passed. It does not mean the
map is good, and it does not mean the engine will load it — the generator repo's
own MAT zone-layout bug **passed every offline check** and was only caught when
a multi-zone map reached the game with scrambled textures. The validators and
the editor share the same readers, so they can never catch a disagreement with
the *engine's* interpretation.

Word the panel accordingly. "No findings" is honest; "map is valid" is not.
