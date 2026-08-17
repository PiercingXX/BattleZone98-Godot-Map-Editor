# Windows export with a bundled Python

Godot export templates are not part of this repo. On a Windows machine (or a
Linux box with the 4.7 Windows templates installed):

1. Install Godot **4.7** export templates.
2. Copy `scripts/export_presets.cfg.example` to `export_presets.cfg` in the
   project root and set the Windows export path.
3. Run the bundle script, then export.

```powershell
# From the repo root, on Windows:
powershell -File scripts/make-windows-bundle.ps1
godot --headless --export-release "Windows Desktop" dist/BZ98MapEditor.exe
```

`make-windows-bundle.ps1` downloads CPython's official **embeddable** amd64
build, installs `numpy` / `Pillow` / `scipy` into it with pip, and copies
`backend/` next to the planned exe as `dist/backend/`.

The editor's backend discovery already looks at `./backend` beside the
executable (`Backend.gd` step 3). No user Python install is required once
that folder ships next to the `.exe`.
