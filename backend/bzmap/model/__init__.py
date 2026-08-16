"""Format-agnostic in-memory model of a generated map (docs/05 ``model/``).

The model layer knows nothing about bytes.  It is the intermediate
representation the generators build and the validators inspect:

- :mod:`bzmap.model.layout` — :class:`LayoutGraph`: base sites, economy
  nodes, and the routes connecting them, plus the graph-level validation
  that runs *before* terrain synthesis (docs/04 §7 step 1).
"""