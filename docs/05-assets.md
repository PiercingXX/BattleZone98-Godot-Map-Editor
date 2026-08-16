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

**Install layout: answered** (`docs/10` Q-A, 2026-08-16). Assets are **loose on
disk**; `.zfs` unpacking is not needed to reach modern content.

- `BZ_ASSETS/common/models/` — base-game models (plus `models/TRO/` for Red
  Odyssey); `BZ_ASSETS/common/textures/` and `…/materials/` alongside.
- `<install>/packaged_mods/<id>/` **and**
  `<library>/steamapps/workshop/content/301650/<id>/` — one **flat** directory
  per workshop item, in two places. See §2b: they hold different sets and both
  must be scanned. BZP is one of these, and it carries the whole 128-map
  corpus.
- `Edit/trn/` — terrain templates.
- `*.zfs` — legacy and localised content, including the **base-game maps**.

So the base-vs-BZP layering in §5 is a real directory split, not an abstraction:
`BZ_ASSETS/` is the base layer, each `packaged_mods/<id>/` is a pack layer.

The extension set to walk is in `docs/formats/F7` §7, and every one of those
formats now has a functional spec in `docs/formats/`. **The one gap is `.zfs`** —
no spec, and it gates reading stock (non-BZP) maps. When it is needed it becomes
a `bzmap` format module with its own tests, like every other format there. Do
not write an unpacker in GDScript.

## 2a. Finding the install — first-run auto-import

**The user should never have to type a path.** On first launch the editor finds
the install itself, shows what it found, and asks for one confirmation. Manual
path entry is the fallback for an install the search misses, not the front door.

Both platforms are first-class (`AGENTS.md`, Environment). The discovery routine
is **backend work** (`bzmap editor probe`, `docs/02` §3) so the path logic is
written once in Python rather than twice in GDScript.

### Steam App ID

**`301650`** — Battlezone 98 Redux. Install directory name is
`Battlezone 98 Redux`.

### Search order

1. **An explicit override**, if set: a CLI flag, an env var, or a previously
   saved path in editor settings. Always wins; always re-validated (§2a
   "Validation") before use.

2. **Steam's own library index.** Locate the Steam root, then read
   `steamapps/libraryfolders.vdf` from it and collect every `"path"` entry —
   users routinely put games on a second drive, and assuming the default library
   is the single most common discovery failure.

   **Windows** — Steam root, in order:
   - registry `HKEY_CURRENT_USER\Software\Valve\Steam` → `SteamPath`
   - registry `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam` →
     `InstallPath`
   - `%ProgramFiles(x86)%\Steam`, then `%ProgramFiles%\Steam`

   **Linux** — Steam root, in order:
   - `~/.steam/steam` (a symlink on most setups — resolve it)
   - `~/.local/share/Steam`
   - `~/.var/app/com.valvesoftware.Steam/.local/share/Steam` (Flatpak)
   - `~/.steam/root`, `~/.steam/debian-installation`

   For each library path found, the install is
   `<library>/steamapps/common/Battlezone 98 Redux`, and
   `<library>/steamapps/appmanifest_301650.acf` confirms it. **Note the Flatpak
   and native Steam installs can both be present with the same game** — this
   machine has exactly that. Deduplicate by resolved real path, and if two
   genuinely distinct installs remain, ask rather than guess.

3. **GOG and other non-Steam copies.** The game is sold outside Steam.
   - Windows: registry `HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\*` →
     `path`, matched on `gameName`.
   - Linux: no registry — check common Wine/Proton prefixes and
     `~/GOG Games/`, then give up gracefully to step 4.

4. **Ask the user**, with a directory picker, pre-seeded with the most likely
   parent directory for the platform.

### Validation — never trust a path, on either platform

A directory is a BZ98R install only if it contains **`battlezone98redux.exe`**
and a **`BZ_ASSETS/common/models/`** directory. Check both. A path that passes
one and not the other is a broken or partial install and must be reported as
such, not half-used.

Record the resolved path plus the `source_fingerprint` (§6) so the next launch
skips discovery entirely, and re-validate on every launch — users move drives,
uninstall, and switch between Flatpak and native Steam.

### Cross-platform hazards, all of which have bitten someone

- **Never hardcode a separator.** Build every path with the platform's join.
- **The install directory name contains spaces** (`Battlezone 98 Redux`) and so
  do Windows program-files paths. Every subprocess invocation must pass
  arguments as a list, never as a concatenated shell string.
- **Case.** Windows is case-insensitive, Linux is not, and stock content mixes
  cases freely (`MN00SA0.MAP` next to `mn00sa0.map`). Every asset lookup is
  case-insensitive — `docs/formats/F8` §5. This is the single most likely
  source of "works on my machine" between the operator's two boxes.
- **Steam is not required to be running** and the game need not have been
  launched; discovery reads files on disk only.
- **`libraryfolders.vdf` format has changed across Steam versions.** Parse
  defensively — pull every `"path"` value regardless of nesting — rather than
  matching a fixed schema.
- **Read-only, always.** `AGENTS.md` rule 1: the install is reference data.
  Discovery opens files for reading and writes nothing, ever, including no
  temp files inside the install tree.

### What "auto-import" actually does

On confirmation, the first-run flow runs the Phase 4 converter (§2) against the
discovered install and populates the cache (§6): asset index, converted meshes,
icons, terrain atlases. It is a **long** operation on a 2.5 GB install with
~1500 ODFs — show real progress, make it cancellable, and make a cancelled run
resumable rather than starting over.

## 2b. Workshop items live in two places, and they disagree

Measured on the operator's install, 2026-08-16. **Scanning only one of these
finds a third of the user's content.**

| Location | What it is | On this machine |
|---|---|---|
| `<library>/steamapps/workshop/content/301650/<id>/` | everything Steam has **subscribed and downloaded** | **9 items, ~2 GB** |
| `<install>/packaged_mods/<id>/` | items the game has **materialised for use** | **3 items** |

They are **copies, not hardlinks** — verified by inode — so an item present in
both occupies disk twice and must be deduplicated by **workshop ID**, not by
inode and not by content hash.

The sets overlap but neither contains the other:

- BZP (`3406347034`, 3608 files, 498 MB, the 128-map corpus) is in **both**,
  with identical file counts.
- Six subscribed items are **only** in `workshop/content/` — including a
  599 MB item and a second BZP-flavoured pack (`3781900699`, 3387 files,
  50 `.bzn`).
- `packaged_mods/9990001` (a lone `net.ini`) and `packaged_mods/819834262`
  (3.8 MB of campaign assets) are **only** in `packaged_mods/` — so that
  directory is not simply a subset, and IDs there are not all Steam workshop
  IDs.

### Rules for the scanner

1. Enumerate the **union**, keyed by workshop ID.
2. When an ID appears in both, prefer `packaged_mods/<id>/` — that is the copy
   the game actually loads — and record that a workshop copy exists.
3. Never assume a workshop item is an asset pack. Sizes here run from **4 files
   to 3608**, and one item is a single `.ini`. An item with no recognisable
   assets is skipped silently, not reported as an error.
4. `workshop/content/` lives under the **Steam library**, not under the install
   — on a multi-drive setup they can be on different disks. Resolve it from the
   same `libraryfolders.vdf` walk as §2a, not by climbing up from the install
   path.

Present the result as a checklist, with **BZP pre-selected if found**, because
it is the layer nearly every corpus map depends on. Show each item's ID, file
count, and size, since workshop items have no reliable human-readable name —
several here are identifiable only by a marker file such as `[BZP.png`.

## 3. The fidelity chain

Q4 was "I want it all if possible". The honest engineering answer is a defined
degradation chain, so that "as good as possible" is a per-asset outcome rather
than an all-or-nothing gamble:

| `mesh_fidelity` | What it is | When |
|---|---|---|
| `hd` | The Redux HD model, textured | **Format identified and specified** (`docs/10` Q-B): OGRE binary `.mesh`/`.skeleton` + `.material` + `.dds` — full chunk layouts in `docs/formats/F7` |
| `geo_textured` | Legacy `.geo`/`.sdf` geometry with its material textures applied | The expected common case for buildings |
| `geo_flat` | Legacy geometry with per-face flat colours from the `.geo` face records | Geometry parsed, textures unresolved |
| `proxy` | A labelled box at the class's real footprint and height | Nothing decodable |

The chain is per-class and recorded in the index, so the editor can show the
user exactly what they are looking at, and so an improvement to the converter
lifts everything without an editor change.

Three converter rules, each specified in full in `docs/formats/`:

- **Skip non-render geometry nodes.** VDF/SDF geometry nodes carry class IDs,
  and eyepoints, headlight masks, hardpoints (all five types), and
  flame/smoke/dust emitters must not be emitted into the `.glb` — otherwise
  every craft grows visible gizmo boxes in the viewport. Exact ID list:
  `docs/formats/F5` §8. Keep their transforms as named attachment points.
- **`geo_flat` is engine-faithful, not a fallback we invented.** `.geo` faces
  carry per-face RGB, and the engine itself renders flat face colours when a
  texture doesn't resolve (`docs/formats/F4` §6).
- **Mind three classic-format traps** (`F4` §5, `F5` §6): `.geo` UV V is
  flipped (`v = 1 − v_file`); UVs live on face nodes so vertices must be split
  per unique (position, normal, uv); and **VDF geometry records are a flat
  100-byte stride** — a 120-byte reader desyncs. (The earlier note here about a
  "20-byte overlapping tail" was one reference implementation's artefact, now
  resolved — see `F5` §6.)

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

- **The MAT bit layout is now settled, and it is not what E3 guessed.** The
  generator repo's `docs/01` §2 has `[matA:4][matB:4][variant:4][0:4]` with an
  always-zero nibble. There is no always-zero nibble: the word is
  `[orientation:4][variant:4]` then `[base:4][transition:4]`, verified against
  independent read and write paths (`docs/formats/F2` §2). Fix E3 in the
  generator repo. What remains experimental is the **orientation sign** and the
  diagonal mirror remap — load a stock map, splat it, compare against the game.
  Agreement promotes those to verified; disagreement is a real finding.
- Fall back gracefully: if the atlas cannot be extracted, splat with the
  `[TextureType*]` `FlatColor` values instead. A flat-coloured map that shows
  material *boundaries* correctly is still a usable painting surface.
- **Cross-check against the recorded atlas tables.** `docs/formats/F2` §4
  carries known-working per-world atlas UV tables for all nine worlds (8×8 grids
  at 0.125 steps, 4×4 at 0.25) plus the tile naming rule
  `<planet><base><transition><S|C|D><variant>0.MAP`, which gives you the lookup
  key straight from the tile word. They validate our extraction and are an
  emergency fallback for UV layout — the atlas *images* still must come from the
  user's install.

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
