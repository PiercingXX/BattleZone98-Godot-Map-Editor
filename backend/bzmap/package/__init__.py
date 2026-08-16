"""Packaging and local-testing install helpers (docs/07).

- :mod:`bzmap.package.install` — copy a generated map into a separate test mod
  dir under ``mods/<test-id>/`` (never touching the installed corpus pack) with ``modEnabled.dat``
  snapshot/restore.
- :mod:`bzmap.package.assemble` — assemble ``build/Expansion-Pack/`` (added
  by its own build task).
"""