# Windows export

The editor is pure GDScript — the exported `.exe` is the whole application.
No Python, no bundled runtime, no side-by-side folders.

Godot export templates are not part of this repo. On a Windows machine (or a
Linux box with the 4.7 Windows templates installed):

1. Install Godot **4.7** export templates.
2. Copy `scripts/export_presets.cfg.example` to `export_presets.cfg` in the
   project root and set the Windows export path.
3. Export:

```powershell
godot --headless --export-release "Windows Desktop" dist/BZ98MapEditor.exe
```

The Linux export works the same way with the "Linux/X11" preset.
