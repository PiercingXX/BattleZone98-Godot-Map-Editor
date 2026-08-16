"""Offline map validators (docs/06).

Three tiers, cheapest first; a map must clear each before the next:

- :mod:`bzmap.validate.formats` — Tier 1 structural checks: round-trip,
  per-map invariants, cross-file consistency, ground snapping. Pure file
  correctness; zero tolerance.
- :mod:`bzmap.validate.terrain` — Tier 2 rules T1-T4.
- :mod:`bzmap.validate.connectivity` — Tier 2 rules C1-C4.
- :mod:`bzmap.validate.balance` — Tier 2 rules E4-E5, B1-B3.
- :mod:`bzmap.validate.report` — one JSON + one PNG per candidate.

Validators are added by their own build tasks; this package currently exposes
the Tier 1 structural module.
"""