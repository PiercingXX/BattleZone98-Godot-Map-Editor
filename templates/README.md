# Starter templates

Each subfolder is a complete, generic base-game map file set that appears in
the editor's **New map** dialog under "Start from". Picking one opens a copy
into a fresh session under your chosen stem — **the template itself is never
modified**: the editor treats this folder as read-only and refuses to save
into it.

To add your own template, drop a full map file set (`.trn`, `.hg2`, `.mat`,
`.bzn`, …) into a new subfolder here. The folder name is the label shown in
the dialog; the `.trn` inside is what gets opened.

The stock templates are generated from the repo's vendored reference data by
`scripts/make_templates.gd` (no game content involved):

| Folder | Size | Shape |
|---|---|---|
| `crater-arena` | 1280 m | central bowl ringed by a rim |
| `valley-2team` | 2560 m | north–south valley between two ridges |
| `highlands-4team` | 2560 m | four corner plateaus, open middle |
