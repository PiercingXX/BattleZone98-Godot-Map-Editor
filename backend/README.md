# Bundled `bzmap` backend

This directory is the editor's format toolchain. The Godot app never parses
`.hg2` / `.bzn` / `.mat` — it shells out to `python -m bzmap.cli editor …`.

Install once from the repo root:

```
python3 -m venv .venv
.venv/bin/pip install -e backend
```

Smoke the CLI:

```
.venv/bin/python -m bzmap.cli editor probe --json
```
