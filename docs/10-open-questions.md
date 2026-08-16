# 10 — Open questions and risks

Things that are genuinely unknown in **this** repo. Each has an experiment that
resolves it. Record findings here as they land.

**Format questions do not belong here.** Those go in the generator repo's
`docs/09-open-questions.md`, which is where format truth is tracked. Cross-
reference from here and move on.

---

## Q-A — Where do game assets physically live?

**Status:** unknown. **Blocks:** Phase 4 (assets). **Does not block:** 1–3, 5.

The generator repo has verified `.geo` and `.sdf` parsers and knows `Edit/trn/`
holds terrain templates, but nothing documents where ODFs, vehicle meshes, and
textures actually sit in a BZ98R install — loose in directories, or packed in
`.zfs` archives. The game ships a `MakeZFS.exe`, which is suggestive and not
evidence.

**Experiment (Phase 0):** inventory a real install. List the directory tree,
identify every extension present, and open one of each. Write the findings into
the generator repo's format docs.

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

**Known violation, still outstanding — `git history`, not the working tree.**
`resources/BZMapIO/BZMapIO.blend` (123 MB, committed in `a389e46`) is BZMapIO's
`BZ_Unit_Models` library and almost certainly contains game-derived meshes. It
was **deleted from the working tree** in the clean-room change, along with the
rest of `resources/`.

**That is not sufficient.** The blob is still reachable in history, and so is
`resources/BZMapIO/BZMapIO.py`. Before this repo goes public, history must be
rewritten (`git filter-repo`) or the repo published fresh from a squashed
initial commit. Deleting a file in a later commit never removes it.

Two reasons, not one: the `.blend` is a **game-content** violation of
`AGENTS.md` rule 3, and both files are the **clean-room reference material** —
leaving them recoverable from history weakens the wall described in
`docs/formats/README.md`.
