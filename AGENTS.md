# Operating instructions for Skippy

You are building the **Battlezone 98 Redux Map Editor** — a standalone Godot
4.7 application specified in `docs/`.

Read `docs/00-project-brief.md` first, then `docs/01-architecture.md`, then
`docs/02-bzmap-bridge.md` (the contract that everything else depends on), then
build in the phase order given in `docs/09-build-plan.md`.

---

## The single most important thing to understand

**This editor does not parse or write Battlezone file formats.** Not one byte.

Every read and write of `.hg2` / `.mat` / `.lgt` / `.trn` / `.bzn` / `.ini` /
`.des` / `.odf` / `.vxt` / `.mesh` goes through the **`bzmap` Python
toolchain** bundled in this repo as `backend/bzmap`, invoked as a
subprocess. `bzmap` round-trips all 128 corpus BZNs and all 36 corpus HG2s
byte-identically; that guarantee is the foundation this editor is built on and
you inherit it for free **only if you never go around it**.

If you find yourself writing a `PackedByteArray` struct-unpack in GDScript for
a game format, stop. The correct move is to add a subcommand to `bzmap` (in the
generator repo) and call it. The bridge contract is `docs/02-bzmap-bridge.md`.

The one exception, spelled out in `docs/02`: the editor reads and writes the
**session buffers** (`terrain.r16`, `materials.u16`) which are plain row-major
arrays that `bzmap` produces and consumes. Those are an interchange format we
define, not a game format.

---

## Ground rules

1. **Never modify the installed game, the installed BZP pack, or any workshop
   content.** Treat every game/workshop path as read-only reference data. All
   output goes to the editor's own session/cache directories or to an explicit
   user-chosen output path. This rule is inherited from the generator repo and
   is absolute.

2. **Do not trust format claims you cannot re-verify — but do not re-verify
   them here.** The format truth lives in the generator repo's `docs/01` and
   `docs/02`. If reality disagrees with a spec, the fix belongs in *that* repo,
   in `bzmap`, with its round-trip tests. Do not paper over a format bug with a
   correction in editor code.

3. **This repo is going public. The generator repo's content is approved for
   use here, but game assets are not.** Never commit anything extracted from
   the game install, the BZP pack, or any workshop item — no meshes, textures,
   ODFs, atlases, or corpus BZN blocks. The editor reads those from the user's
   own install at runtime. `.gitignore` blocks the obvious cases; that is a
   safety net, not permission to try.

4. **Tunnels are out of scope, entirely.** Ignore all `tunnel-testing/` material
   in the generator repo. Do not reference it, build for it, or leave hooks for
   it. If it ever pans out it will arrive as a new spec.

5. **The corpus is the authority on object blocks, and cloning is the only safe
   construction.** The generator repo's `docs/16` records four consecutive
   crash-to-lobby bugs whose root cause was assembling or re-typing a
   `[GameObject]` block instead of cloning a verified same-class one. The
   editor's placement UI must never invent a block. See `docs/06`.

6. **Interactive performance is a correctness requirement, not polish.** A
   sculpt brush that stutters on a 5120 m map is a failed feature. The
   architecture in `docs/03`/`docs/04` (GPU height-texture displacement,
   analytic raycast, dirty-rect updates) exists specifically to make that
   achievable — do not replace it with per-frame mesh rebuilds.

7. **Every destructive action needs undo.** Sculpting and object edits both go
   through the undo stack (`docs/04` §4). "I'll add undo later" produces an
   editor nobody can safely use, and retrofitting it is worse than building it
   in.

8. **Format truth comes from `docs/formats/`, and there is nothing else to
   look at.** Two third-party Blender addons — one GPL-3.0, one with no stated
   license — encoded most of what is known about these formats. Porting their
   code would have made `bzmap` a derivative work, so the formats were
   **clean-roomed**: the spec role read them and wrote `docs/formats/F1`–`F8`
   (facts, layouts, field semantics, edge cases, test vectors — no code), and
   the reference tree was then **deleted from this repository**.

   You implement from those specs alone. Do not go looking for the originals,
   do not re-vendor them, and do not "check the upstream repo" — the wall is
   the whole point, and crossing it retroactively contaminates work already
   done. If a spec is ambiguous or contradicted by reality, say so and ask for
   the spec to be clarified. The process and its rationale are recorded in
   `docs/formats/README.md`.

---

## Environment

- **Godot 4.7 stable**, pinned. GDScript, not C#.
- **Cross-platform: Linux and Windows, both first-class.** The operator uses
  both. Every path, subprocess call, and install-discovery routine must work on
  both. No shell-isms, no hardcoded separators, no assuming Proton.
- The Python backend must be locatable on both platforms — see `docs/02` §7 for
  the discovery order and the bundling requirement.
- The game may not be installed on the machine where you are building. Anything
  that requires a live install (asset extraction, mesh loading) needs a
  graceful, explicit failure path and must not block the rest of the editor
  from running.

---

## When you are blocked

Write the blocker into `docs/10-open-questions.md` with what you tried and what
you observed, then continue with work that does not depend on it. Do not stall
the whole build on one unknown, and do not silently guess and move on.

If the blocker is a **format** question, it belongs in the generator repo's
`docs/09-open-questions.md` instead — that is where format truth is tracked.
Note the cross-reference here and move on.

---

## Definition of "done" for any phase

A phase is done when its acceptance criteria in `docs/09-build-plan.md` pass
**and** you have written down what you verified and how. "It looks right" is not
evidence. For anything visual, the evidence is a screenshot plus the numbers it
was checked against (dimensions, heights, object counts) — the operator's own
rule from the generator repo: *verify placement, not counts*, and measure
features rather than eyeballing them.
