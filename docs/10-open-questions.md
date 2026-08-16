# 10 — Open questions and risks

Things that are genuinely unknown in **this** repo. Each has an experiment that
resolves it. Record findings here as they land.

**Format questions do not belong here.** Those go in the generator repo's
`docs/09-open-questions.md`, which is where format truth is tracked. Cross-
reference from here and move on.

---

## Q-A — Where do game assets physically live?

**Status: ANSWERED (2026-08-16).** Inventoried a real Steam install of BZ98R
(2.5 GB). **Assets are loose on disk. `.zfs` unpacking is not needed to reach
modern content.**

### Layout

| Path | Holds |
|---|---|
| `BZ_ASSETS/common/models/` | base-game models — 377 files |
| `BZ_ASSETS/common/models/TRO/` | Red Odyssey models — 104 files |
| `BZ_ASSETS/common/{materials,textures}/`, `BZ_ASSETS/pc/…` | materials and textures, split common vs pc |
| `BZ_ASSETS_CORE/` | movies, shader programs, UI, `BZ_MATERIALS` — no unit models |
| `Edit/trn/` | 9 terrain templates, as the generator repo already knew |
| `packaged_mods/<id>/` | one flat directory per installed workshop item |
| `*.zfs` (10 archives, 25–63 MB each) | legacy/localised content; `bzone.zfs`, `tro_cam.zfs`, and one per language |

Whole-install extension census: **1496 `.odf`, 1016 `.dds`, 706 `.png`,
533 `.mesh`, 475 `.material`, 287 `.skeleton`, 128 `.bzn`, 100 `.des`,
94 `.vdf`, 76 `.geo`, 46 `.trn`, 37 `.lgt`, 36 `.vxt`, 36 `.mat`, 36 `.hg2`,
25 `.sdf`, 66 `.lua`.**

Every format specified in `docs/formats/` is present as loose files, which means
the asset converter can be built and tested without touching `.zfs` at all.

### The corpus is BZP's, and that matters

`packaged_mods/3406347034/` is **BZP** — 498 MB, 3608 files in one flat
directory — and it contains **exactly** the corpus the generator repo
round-trips: 36 `.hg2`, 36 `.mat`, 128 `.bzn`, 37 `.trn`. Base-game maps are
*not* loose; they are presumably inside `bzone.zfs`.

Two consequences:

- **`pack_context` filtering (`docs/05` §5) is not theoretical.** A workshop
  item is a flat asset directory that layers over the base game, and BZP is the
  layer nearly every corpus map depends on. The palette's base-vs-BZP split maps
  directly onto `BZ_ASSETS/` vs `packaged_mods/<id>/`.
- **Reading stock (non-BZP) maps still needs `.zfs`.** Not a blocker for Phase 4
  — BZP alone supplies a 128-map corpus — but it caps what "open ALL maps" (Q7)
  can mean until an unpacker exists.

### Workshop content is in two places

`<library>/steamapps/workshop/content/301650/<id>/` holds **9 subscribed items
(~2 GB)**; `<install>/packaged_mods/<id>/` holds **3**. They are copies, not
hardlinks (verified by inode), and neither set contains the other — BZP is in
both, six items are workshop-only, and two (`819834262`, `9990001`) are
`packaged_mods`-only with IDs that are not all Steam workshop IDs.

**A scanner that looks at only one location finds a third of the user's
content.** Rules in `docs/05` §2b; `probe`'s contract corrected in `docs/02`
§3.

Item sizes range from 4 files to 3608, and one is a single `net.ini` — so
"workshop item" does not imply "asset pack", and the scanner must tolerate
both without erroring.

### Install discovery

Specified cross-platform in `docs/05` §2a: Steam App ID **`301650`**, Windows
registry + default paths, Linux native + Flatpak roots, `libraryfolders.vdf`
for secondary drives, GOG fallback, then ask. Validation requires **both**
`battlezone98redux.exe` and `BZ_ASSETS/common/models/`.

**The Linux half is measured; the Windows half is written from documentation
and is unverified.** Phase 0 item 6 checks it against a real Windows install.

**Still open:** the `.zfs` container format. It is the only format in this
pipeline with no specification behind it (`docs/formats/README.md`).

**Partial finding (2026-08-16):** the extension set to look for is now known —
classic `.odf .geo .vdf .sdf .map .act` plus Redux `.mesh .skeleton .material
.dds` (textures named `<name>_D.dds` with `_N`/`_S`/`_E` variants); see
`docs/formats/F7` §7. Every one of those formats now has a functional spec.
Where they physically sit (loose vs `.zfs`) is still the open half, and `.zfs`
is the only format in the pipeline with no spec behind it.

**Fallback if `.zfs` unpacking is required:** it becomes a `bzmap` format module
with round-trip tests, like every other format there. Do not write an unpacker
in GDScript.

---

## Q-B — Is the Redux HD model format decodable?

**Status: ANSWERED (2026-08-16).** Yes. The Redux runtime format is **OGRE**:
binary `.mesh` (`MeshSerializer_v1.100`), binary `.skeleton`
(`Serializer_v1.80`), text `.material` scripts, `.dds` textures. Vertices are
position/normal/colour/uv — a straight map to glTF.

**Fully specified as of 2026-08-16:** `docs/formats/F7` carries the complete
chunk-id tables, payload layouts, vertex element enumerations, the two
size-detection traps in `.skeleton` (optional bone/keyframe scale, and bone
names being excluded from the declared chunk size), and the Redux `.material`
conventions (`BZBase`/`BZBaseCockpit`, the four texture aliases, `_D.dds`
naming).

The `hd` rung of the fidelity chain is therefore achievable. Remaining work is
generator-repo work: an OGRE-mesh format module in `bzmap` feeding the `.glb`
converter, written from `F7` alone. **License handling (done):** the reference
addon was GPL-3.0, so the specs were produced **clean-room** and the reference
tree has been deleted from this repo — see `docs/formats/README.md` and
`AGENTS.md` rule 8.

Residual unknown: whether stock installs also carry DXT-compressed `.dds`
(the porter writes uncompressed A8R8G8B8) — handle both in the converter.

---

## Q-C — Does the inferred MAT bit layout hold?

**Status: ANSWERED for the layout (2026-08-16); the orientation *sign* is still
the experiment.**

E3's hypothesis was `[matA:4][matB:4][variant:4][0:4]`. **It is wrong in a
specific, useful way: there is no always-zero nibble.** The tile word is

```
byte0 = [orientation:4][variant:4]
byte1 = [base:4][transition:4]
```

verified against independent read and write paths — full statement in
`docs/formats/F2` §2. `base == transition` → solid; differ → cap; orientation
≥ 8 → diagonal corner. Orientation 0–7 covers four rotations × mirror for
solids and caps, 8–15 the same for diagonals, with a mirror remap applied to
four of the diagonal codes on write.

**Fix E3 in the generator repo** — it is not "inferred, pending", it is
superseded.

What genuinely remains open: the absolute **sign** of the rotations (the
reference measurements were taken in a tool whose UV origin differs from the
engine's) and whether the diagonal mirror remap applies in the read direction
too. Both are settled by the same experiment below.

**Experiment (Phase 4):** splat a stock map in the viewport using the layout
above, then compare against the same map in game. Agreement confirms E3;
disagreement is a real finding.

**Either outcome is a result, and it belongs in the generator repo.** Note here
that it was run, and where the answer went.

---

## Q-D — Python bundling on Windows

**Status:** unresolved. **Blocks:** public release (Phase 7), not the operator's
own use.

The backend needs Python 3.11+ with `numpy`, `Pillow`, and `scipy`. The operator
can run a sibling checkout on both machines. A community user cannot reasonably
be asked to set up a Python environment to run a map editor.

**Options, in preference order:**
1. Bundle an embeddable Python plus wheels under `./backend/` in the Windows
   export.
2. Ship the backend as a frozen single binary (PyInstaller/Nuitka) invoked the
   same way — the contract is a subprocess, so the editor does not care which.
3. Document the manual setup and accept the friction.

**Do not let this stay silent.** Option 3 is a real answer only if written down
where users will read it. Track it to a decision before Phase 7.

---

## Q-E — Is the `/startedit` launch button reliable enough to ship?

**Status:** open. **Blocks:** nothing — the button is optional (`docs/08` §3).

`battlezone98redux.exe <map>.bzn /startedit /win` loads a map straight into the
in-game editor. Native on Windows; through Proton on Linux, which is where it
gets fragile.

**Experiment (Phase 6):** try it on both platforms. Ship the button only where
it works without fragile shell plumbing; hide it elsewhere rather than
presenting a button that sometimes does nothing.

---

## Q-F — How many object classes have verified templates?

**Status:** partially known. **Affects:** how much of the palette is BZN-placeable
versus runtime-spawned (`docs/06` §6).

Verified today: geysers, scrap, spawn points, the player, depots, environment
carriers. Craft layouts beyond wingman are explicitly unverified — apc, tug,
walker, howitzer, and turrettank are named as unknown in the generator repo.

Growing this set is generator-repo work (clone a corpus block of the class, load
it in game, promote it to verified). The editor picks up any improvement for
free through the asset index.

**Watch for:** a palette where most interesting units are runtime-only. That is
survivable — runtime spawning is a legitimate mode with real advantages — but if
it is the common case, the UI should present runtime as the normal path rather
than the exception.

---

## Q-G — Does runtime spawning work on base-game maps?

**Status:** unknown. **Blocks:** `placement_mode: "runtime"` for
`pack_context: base` only; BZP maps are unaffected.

The `<stem>MAP.lua` hook, its module shape, and the script plumbing around it
are **BZP conventions**. The engine loads a `<stem>.lua` for stock maps, but
whether a plain base-game multiplayer map's script reliably gets an `Update`
loop and `BuildObject` rights — without BZP's loader — is unverified here.

**Experiment (Phase 1, cheap):** a base-game test map whose `.lua` does a
host-guarded `BuildObject` of a scrap piece; load it in game and look for the
scrap.

**If it fails:** unverified classes are simply unavailable on base-game maps,
stated in the palette with the reason (`docs/02` §6). The feature degrades to
exactly what verified templates cover.

---

## Standing risks

### R1 — The editor and the validators share the same readers
Neither can catch a disagreement with the **engine's** interpretation of a file.
The MAT zone-layout bug passed every offline check and was only caught in game.
Mitigation: the in-game load gate stays part of the workflow, and the editor
never claims a map is "valid" (`docs/08` §4).

### R2 — Performance found late is architectural
A sculpt brush that stutters at 5120 m cannot be fixed by tuning if the design
rebuilds meshes. Mitigation: the GPU-displacement architecture is specified up
front (`docs/03` §2) and Phase 2 has a measured frame-rate gate before
sculpting is built on top of it.

### R3 — Two repos, one contract
The bridge spans a private repo and a public one, on separate release
timelines. A change on one side that is not made on the other produces confusing
runtime failures. Mitigation: `contract_version` (`docs/02` §8), checked at
startup, with a clear message rather than a mysterious parse error.

### R4 — Scope
Q3–Q5 were answered "I want it all". That is the right ambition and it is also
the classic way a tool never ships. Mitigation: the fidelity chain (`docs/05`
§3) makes "all" a gradient rather than a gate, and the build plan puts
placement-on-proxies ahead of asset fidelity so the editor is useful before it
is beautiful.

### R5 — The public repo must stay clean of game content
Every asset the editor touches belongs to Rebellion or to the BZP authors.
`.gitignore` blocks the obvious cases, but a cache path pointed somewhere
careless, or a test fixture committed for convenience, would put licensed
content in a public repo. Mitigation: the cache lives in user data, never in the
repo, and `AGENTS.md` rule 3 is absolute.

**History check, 2026-08-16.** The cited commit `a389e46` is not in this
repository. Current `main` is five commits, all spec/docs, with **zero** blobs
over 100 KB. The working tree has no `resources/`. Before a public release,
re-run `git rev-list --objects --all` and confirm no game-content blobs have
landed; do not treat the old hash as still reachable.

---

## Q-H — Binary BZN reader (Phase 1 leftover)

**Status:** open. **Blocks:** Phase 1 acceptance item 3 (open a stock binary
BZN, save as ASCII) only.

`bzmap editor open` detects binary BZNs (`NUL` in the first 256 bytes, a
non-UTF-8 decode, or `binarySave = true`) and returns
`binary_bzn_unsupported`. There is no binary reader in `bzmap`, and
WorldBuilder is not vendored in git. A binary module belongs in the generator
repo, written from a spec, not ported from WorldBuilder. ASCII BZP BZNs (the
128-map corpus) open and save.

---

## Q-I — Windows install discovery / export (Phase 0 leftover)

**Status:** code is written, **unverified on a Windows box**. **Blocks:**
Phase 0 acceptance on Windows only.

`bzmap/editor/discover.py` implements the registry + `libraryfolders.vdf` +
GOG walk from `docs/05` §2a. It has not been run on Windows. Linux probe is
measured. Godot 4.7.1 is installed here; export templates are not, so a
Windows `.exe` was not produced on this machine.
