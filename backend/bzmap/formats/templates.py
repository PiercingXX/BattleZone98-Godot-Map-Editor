"""Verbatim template blocks for template-and-mutate (docs/02 §6 R2).

Rule 3 (template-and-mutate) forbids assembling BZN field lists from the spec:
field *order* is load-bearing and the corpus is the authority. This module is
the single place that loads the known-good blocks a generator clones.

Two sources are supported:

- ``reference/`` — the repo's checked-in reference templates
  (``bzn-object-template.txt`` and ``bzn-header-tail-template.txt``). This is
  the default and the only source available in a fresh checkout.
- the stock worlds — any installed ``.bzn`` (e.g. a stock map or a community pack)
  passed as a ``bzn_path``. The loader reuses :mod:`bzmap.formats.bzn` to parse
  the file and extracts per-``PrjID`` object blocks verbatim, plus the file's
  header and tail. This lets a generator clone a real object of any class the
  stock worlds ship, not just the single geyser in ``reference/``.

Blocks are returned as text with template ``#`` annotation lines stripped, ready
to hand to :class:`bzmap.formats.bzn.GameObject.from_template` /
:meth:`bzmap.formats.bzn.BznFile.build`.
"""

from __future__ import annotations

from pathlib import Path

from bzmap.formats.bzn import BznFile, GameObject

# Repo-root-relative names of the checked-in reference template files.
_OBJECT_TEMPLATE = "bzn-object-template.txt"
_HEADER_TAIL_TEMPLATE = "bzn-header-tail-template.txt"

# Default base directory for reference templates: <repo>/reference.
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_REFERENCE_DIR = _REPO_ROOT / "reference"


def _strip_comments(text):
    """Drop template annotation lines (``#`` / ``###``) from a reference block.

    The ``reference/*-template.txt`` files carry ``#`` comment lines that are
    documentation, not part of the on-disk format. They are stripped when a
    block is loaded for generation; round-tripped files never contain them.
    """
    lines = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        lines.append(line)
    return lines


class TemplateLoader:
    """Loads verbatim header/tail/object blocks for template-and-mutate.

    ``reference_dir`` points at a directory holding the checked-in reference
    template files (defaults to ``reference/``). ``bzn_path`` optionally points
    at a stock ``.bzn`` file whose per-object blocks, header and tail are used
    as the source instead. When ``bzn_path`` is set it takes precedence for the
    blocks it can supply; the reference files remain the fallback.
    """

    def __init__(self, reference_dir=None, bzn_path=None):
        self.reference_dir = Path(reference_dir) if reference_dir else DEFAULT_REFERENCE_DIR
        self.bzn_path = Path(bzn_path) if bzn_path else None
        self._bzn = None  # lazily parsed stock file

    # -- sources --------------------------------------------------------------

    def _load_bzn(self):
        """Parse and cache the stock ``.bzn`` file (if configured)."""
        if self.bzn_path is None:
            return None
        if self._bzn is None:
            self._bzn = BznFile.read(self.bzn_path)
        return self._bzn

    def _read_reference(self, filename):
        """Return the raw text of a reference template file."""
        path = self.reference_dir / filename
        if not path.is_file():
            raise FileNotFoundError(f"reference template not found: {path}")
        return path.read_text(encoding="utf-8")

    # -- header / tail ---------------------------------------------------------

    def header(self):
        """Return the verbatim BZN header block (``#`` comments stripped)."""
        bzn = self._load_bzn()
        if bzn is not None and bzn.header:
            return "\r\n".join(bzn.header)
        return self._header_from_reference()

    def tail(self):
        """Return the verbatim BZN trailing block (``#`` comments stripped)."""
        bzn = self._load_bzn()
        if bzn is not None and bzn.tail:
            return "\r\n".join(bzn.tail)
        return self._tail_from_reference()

    def _header_from_reference(self):
        return "\r\n".join(_strip_comments(self._read_reference(_HEADER_TAIL_TEMPLATE)))

    def _tail_from_reference(self):
        return "\r\n".join(_strip_comments(self._read_reference(_HEADER_TAIL_TEMPLATE)))

    # -- objects ---------------------------------------------------------------

    def object(self, prjid):
        """Return the verbatim ``[GameObject]`` block for ``prjid``.

        The block is returned as CRLF text with ``#`` annotation lines stripped,
        ready for :meth:`bzmap.formats.bzn.GameObject.from_template`. Raises
        ``KeyError`` when no object with that ``PrjID`` is available from either
        source.
        """
        bzn = self._load_bzn()
        if bzn is not None:
            for obj in bzn.objects:
                if obj.prjid == prjid:
                    return obj.render()
        return self._object_from_reference(prjid)

    def _object_from_reference(self, prjid):
        text = self._read_reference(_OBJECT_TEMPLATE)
        lines = _strip_comments(text)
        obj = GameObject.from_template("\r\n".join(lines))
        if obj.prjid != prjid:
            raise KeyError(
                f"no object template for {prjid!r} in reference/ "
                f"(only {obj.prjid!r} is available); pass a stock bzn_path"
            )
        return obj.render()

    # -- convenience -----------------------------------------------------------

    def available_prjids(self):
        """Return the set of ``PrjID`` values this loader can clone.

        Includes the reference object (if present) plus every object in a
        configured stock ``.bzn`` file.
        """
        prjids = set()
        try:
            text = self._read_reference(_OBJECT_TEMPLATE)
            obj = GameObject.from_template("\r\n".join(_strip_comments(text)))
            prjids.add(obj.prjid)
        except FileNotFoundError:
            pass
        bzn = self._load_bzn()
        if bzn is not None:
            prjids.update(o.prjid for o in bzn.objects if o.prjid is not None)
        return prjids


# -- module-level convenience --------------------------------------------------


def template(prjid, bzn_path=None):
    """Return the verbatim ``[GameObject]`` block for ``prjid``.

    Thin wrapper over :class:`TemplateLoader` for the docs/02 §6 R2 idiom
    ``obj = template("eggeizr1")``. ``bzn_path`` optionally points at a stock
    ``.bzn`` to source the block from.
    """
    return TemplateLoader(bzn_path=bzn_path).object(prjid)