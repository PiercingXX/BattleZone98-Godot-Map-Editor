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
- **Cross-platform: Linux and Windows, both first-class.** Every path,
  subprocess call, and install-discovery routine must work on both. No
  shell-isms, no hardcoded separators, no assuming Proton.
- The Python backend must be locatable on both platforms — see `docs/02` §7.
- The game may not be installed on the machine where you are building.
  Anything that requires a live install needs a graceful, explicit failure
  path and must not block the rest of the editor from running.

---

## What is already here

Standalone smoke build: probe / open / new / save / validate against the
bundled backend, GPU-displaced terrain, free-fly camera, object markers.

## What is left

Build in this order. Do not start a phase whose predecessor is not working.

1. **Bridge goldens** — `open` then `save` with no edits is byte-identical on
   a stock map, a multi-zone map, and a binary BZN (ASCII conversion reported).
2. **Viewport** — 5120 m at 60 fps, analytic raycast agreeing with
   `height_at()` to a centimetre.
3. **Sculpting + undo** — raise/lower, flatten, smooth, ramp; clamp raw 1 and
   4095 on *writes* (inherited out-of-range stock data passes through);
   mixed sculpt/object undo; sculpted `.hg2` re-opens identical.
4. **Assets** — install auto-discovery on Linux and Windows, first-run import,
   fidelity chain HD → textured geo → flat geo → labeled proxy, terrain atlas
   splatting.
5. **Placement** — live palette from the user's install, raycast + terrain
   normal, clone-only BZN blocks, required singular player object.
6. **Map data + packaging** — new-map wizard, metadata, water/plants,
   validation panel, thumbnail / install-to-test-mod / pack assembly.
7. **Ship** — a map authored entirely in the editor loads in BZ98R; Linux and
   Windows exports both run.

When blocked, write what you tried and continue with work that does not depend
on it. Do not stall the whole build on one unknown, and do not silently guess.

A phase is done when the criteria above pass **and** you have written down
what you verified and how. For anything visual: a screenshot plus the numbers
it was checked against. Verify placement, not counts.
