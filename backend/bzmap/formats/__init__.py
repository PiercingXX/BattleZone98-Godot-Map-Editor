"""Binary/text format readers and writers for Battlezone map files.

Each submodule owns one file format:

- :mod:`bzmap.formats.hg2` — the ``.HG2`` heightmap (zone-major binary).
- :mod:`bzmap.formats.mat` — the ``.MAT`` material grid.
- :mod:`bzmap.formats.lgt` — the ``.LGT`` baked lightmap.
- :mod:`bzmap.formats.trn` — the ``.trn`` terrain INI config.
- :mod:`bzmap.formats.bzn` — the ``.bzn`` mission object file.
- :mod:`bzmap.formats.des` — the ``.des`` map description text.
- :mod:`bzmap.formats.ini` — the ``.ini`` workshop + multiplayer metadata.
- :mod:`bzmap.formats.odf` — the ``.odf`` per-map settings.
- :mod:`bzmap.formats.vxt` — the ``.vxt`` observer vehicle list.
- :mod:`bzmap.formats.templates` — verbatim template blocks for template-and-mutate.

Formats are added by their own build tasks; this package currently exposes the
heightmap module.
"""