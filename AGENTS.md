# Operating instructions for Skippy

You are building the **BattleZone 98 Godot Map Editor** — a standalone Godot
4.7 application. The Godot tree is the editor. `backend/bzmap` is the format
toolchain, invoked as a subprocess. The contract between them is
`docs/02-bzmap-bridge.md`.

---

## The single most important thing to understand

**This editor does not parse or write Battlezone file formats.** Not one byte.

Every read and write of `.hg2` / `.mat` / `.lgt` / `.trn` / `.bzn` / `.ini` /
`.des` / `.odf` / `.vxt` / `.mesh` goes through the **`bzmap` Python
toolchain** bundled in this repo as `backend/bzmap`. `bzmap` round-trips all
128 corpus BZNs and all 36 corpus HG2s byte-identically; that guarantee is the
foundation this editor is built on and you inherit it for free **only if you
never go around it**.

If you find yourself writing a `PackedByteArray` struct-unpack in GDScript for
a game format, stop. The correct move is to add a subcommand to `bzmap` and
call it. The bridge contract is `docs/02-bzmap-bridge.md`.

The one exception, spelled out in `docs/02`: the editor reads and writes the
**session buffers** (`terrain.r16`, `materials.u16`) which are plain row-major
arrays that `bzmap` produces and consumes. Those are an interchange format we
define, not a game format.

---

## Ground rules

1. **Never modify the installed game, the installed BZP pack, or any workshop
   content.** Treat every game/workshop path as read-only reference data. All
   output goes to the editor's own session/cache directories or to an explicit
   user-chosen output path.

2. **Do not paper over a format bug in editor code.** Format truth lives in
   `docs/formats/` (clean-room functional specs) and in `backend/bzmap`. If
   reality disagrees with a spec, fix `bzmap` and the spec — not GDScript.

3. **This repo is public. Game assets are not.** Never commit anything
   extracted from the game install, the BZP pack, or any workshop item — no
   meshes, textures, ODFs, atlases, or corpus BZN blocks. The editor reads
   those from the user's own install at runtime.

4. **Tunnels are out of scope, entirely.** Do not reference them, build for
   them, or leave hooks for them.

5. **The corpus is the authority on object blocks, and cloning is the only safe
   construction.** Do not assemble or re-type a `[GameObject]` block. Placement
   must clone a verified same-class block.

6. **Interactive performance is a correctness requirement, not polish.** A
   sculpt brush that stutters on a 5120 m map is a failed feature. Use GPU
   height-texture displacement, analytic raycast, and dirty-rect updates. Do
   not replace that with per-frame mesh rebuilds.

7. **Every destructive action needs undo.** Sculpting and object edits both go
   through the undo stack. Do not ship an edit without it.

8. **Format specs are `docs/formats/F1`–`F8`.** Two third-party Blender addons
   encoded most of what is known about these formats. They were studied under a
   clean-room process and are not in this repository. Implement from the specs
   and from `bzmap`. Do not go looking for the originals.

---

## Environment

- **Godot 4.7 stable**, pinned. GDScript, not C#.
- Tests: `scripts/test.sh` runs `pytest backend/tests` then the headless
  GDScript suite (`scripts/test-editor.sh`). Run it after any task that
  touches `backend/` or editor GDScript.
- **Cross-platform: Linux and Windows, both first-class.** Every path,
  subprocess call, and install-discovery routine must work on both. No
  shell-isms, no hardcoded separators, no assuming Proton.
- The Python backend must be locatable on both platforms — see `docs/02` §7.
- The game may not be installed on the machine where you are building.
  Anything that requires a live install needs a graceful, explicit failure
  path and must not block the rest of the editor from running.

---

## What is already here

Working editor, not a smoke shell:

- Bridge goldens: open→save with no edits is byte-identical (single-zone and
  multi-zone). Binary BZNs are detected and refused — there is still no
  binary reader, so they are not silently converted.
- Viewport: GPU-displaced chunks, analytic raycast, slope / material / brush
  overlays, fly camera (walk-the-surface is V).
- Sculpt + paint + ramp + undo. Writes clamp to raw 1..4095; inherited
  out-of-range cells pass through until touched.
- Assets: `bzmap editor assets` enumerates the install, writes proxy icons,
  marks verified classes. Viewport fidelity is **proxy** until a `.glb`
  appears in the cache (HD / geo conversion is the next converter job).
- Placement: live palette, raycast, clone-on-save for verified classes,
  runtime `BuildObject` for the rest, singular undeletable player.
- Map data, findings panel (click-to-fly), thumbnail, install-to-test-mod,
  pack assembly.

## Still open

- Binary BZN *read*. F3 takes it out of the spec set on purpose — the file
  must be re-saved from the game with `asciisave`. Do not invent a layout.
- Windows *export templates* are a machine install, not repo content. The
  bundle script in `scripts/` is the packaging half; it still needs templates
  on the box that runs `godot --export-release`.
- An in-game play-test of a map authored entirely here. Offline checks are
  not that test.

When blocked, write what you tried and continue with work that does not depend
on it. Do not stall the whole build on one unknown, and do not silently guess.

A phase is done when the criteria above pass **and** you have written down
what you verified and how. For anything visual: a screenshot plus the numbers
it was checked against. Verify placement, not counts.
