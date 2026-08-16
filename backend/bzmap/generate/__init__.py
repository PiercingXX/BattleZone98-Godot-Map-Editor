"""Map generators (docs/05 ``generate/``).

Each generator turns the validated layout graph into one layer of the map:

- :mod:`bzmap.generate.terrain_gen` — plateau → carve → erode → flatten-pads
  synthesis producing a :class:`~bzmap.formats.hg2.HeightMap` at a nonzero
  base elevation (docs/04 §7 step 2).
- :mod:`bzmap.generate.economy` — geyser and scrap placement (rules E1–E5).
- :mod:`bzmap.generate.spawns` — spawn clusters (rules B1–B3).
- :mod:`bzmap.generate.variants` — base / _S / _ST / _SW object sets from one
  layout.
"""