"""``.vxt`` observer vehicle list writer (docs/01 §8).

Tab-separated text, one entry per line, blank-line separated:

::

    avobserv avobserv.des\tx\tNSDF

    svobserv svobserv.des\tx\tCCA

    bvobserv bvobserv.des\tx\tBDOG

There is no reason to vary it — copy it **verbatim** from a stock map. This
module writes the text byte-for-byte as given, so the caller supplies the stock
verbatim block (loaded from ``reference/`` or a stock map).
"""

from __future__ import annotations

from pathlib import Path


def write_vxt(path, text):
    """Write the ``.vxt`` observer list ``text`` to ``path`` verbatim.

    ``text`` is written exactly as provided (no added or stripped line endings),
    so a stock block round-trips byte-for-byte.
    """
    path = Path(path)
    path.write_text(text, encoding="utf-8", newline="")

#: The five observer entries every one of the corpus's 36 maps carries — one craft per
#: race plus the spectator (measured across the corpus). The generator once emitted only
#: the NSDF line, which left CCA/BDOG/CRA/spectator players with no observer.
STANDARD_OBSERVERS = (
    "avobserv avobserv.des\tx\tNSDF",
    "svobserv svobserv.des\tx\tCCA",
    "bvobserv bvobserv.des\tx\tBDOG",
    "cvobserv cvobserv.des\tx\tCRA",
    "observer observer.des\tx\tObserver",
)

#: The standard file text: entries separated by blank lines, matching the
#: corpus byte layout.
STANDARD_VXT_TEXT = "\n\n".join(STANDARD_OBSERVERS)


def write_standard_vxt(path):
    """Write the full five-observer standard list to ``path``."""
    write_vxt(path, STANDARD_VXT_TEXT)
    return Path(path)
