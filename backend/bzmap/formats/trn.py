"""``.trn`` terrain INI reader/writer — ordered, comment-preserving (docs/01 §4).

The ``.trn`` is a plain INI text file (CRLF line endings) with sections
``[Size]``, ``[NormalView]``, ``[Atlases]``, ``[World]``, ``[Sky]``,
``[Clouds]``, ``[Color]`` and ``[TextureType0..N]``. It is **VERIFIED** in
docs/01 §4.

The critical requirement is that a stock terrain config round-trips **verbatim**
(Rule 4: parse → re-emit → byte-identical). Real ``.trn`` files carry comments,
blank lines, and whitespace that a normal ``configparser`` would destroy, and the
``[TextureType*]`` blocks are long, world-specific, and reference asset names
that must exist — so they must never be re-serialized from a parsed dict.

:class:`TerrainConfig` therefore keeps the **original text verbatim** and only
re-emits the whole file when a value has actually been changed. Reads and writes
are line-preserving:

- ``read`` parses the file into an ordered list of sections and their key/value
  pairs, recording which source line each key lives on.
- ``write`` emits the original text unchanged unless ``set`` was called, in which
  case only the affected lines are rewritten and everything else (comments, blank
  lines, ordering, whitespace) is preserved byte-for-byte.
"""

from __future__ import annotations

from pathlib import Path

# Line endings are CRLF per docs/01 §4.
_EOL = "\r\n"


class TerrainConfig:
    """Ordered, comment-preserving representation of a ``.trn`` INI.

    ``sections`` is an ordered list of ``Section`` objects. ``set``/``get``
    provide key access; setting a value marks the config dirty so ``write``
    re-emits only the changed lines. An untouched config round-trips the source
    file byte-for-byte.
    """

    __slots__ = ("_dirty", "_lines", "sections")

    def __init__(self, sections, lines):
        self.sections = sections
        self._lines = lines  # list of str, one per source line (no EOL)
        self._dirty = False

    # -- serialization -----------------------------------------------------

    @classmethod
    def read(cls, path):
        """Read a ``.trn`` file into a :class:`TerrainConfig`.

        Comment lines (leading ``;`` or ``#``), blank lines, and section headers
        are preserved verbatim in the internal line store; only ``key = value``
        pairs are parsed for access. Non-INI lines that do not match a section
        header or a key/value pair are kept as opaque lines.
        """
        path = Path(path)
        text = path.read_text(encoding="utf-8-sig")
        lines = text.splitlines()
        sections = []
        current = None
        for lineno, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith((";", "#")):
                # Comment, blank, or opaque line — not part of any section.
                continue
            if stripped.startswith("["):
                # Section headers may carry trailing text after the bracket —
                # The corpus maps write every texture block as e.g. ``[TextureType0] // Lava``
                # (and one as ``[TextureType1] Lava Pool`` with no comment marker
                # at all). Requiring the line to *end* with ``]`` silently
                # dropped every such section, which is how the terrain validator
                # missed [TextureType*] blocks across the whole pack.
                close = stripped.find("]")
                if close > 0:
                    current = Section(stripped[1:close], lineno)
                    sections.append(current)
                    continue
            if current is not None and "=" in line:
                key, _, value = line.partition("=")
                current._add(key.strip(), value.strip(), lineno)
        return cls(sections, lines)

    def write(self, path):
        """Write this config to ``path``.

        If no value was set, the source text is emitted byte-for-byte (CRLF
        line endings preserved). Otherwise only the lines holding changed keys
        are rewritten; comments, blank lines, ordering and whitespace elsewhere
        are untouched.
        """
        path = Path(path)
        if self._dirty:
            out_lines = list(self._lines)
            for section in self.sections:
                for key, value, lineno, orig in section._items:
                    if value == orig:
                        continue  # untouched line keeps its original spacing
                    if lineno is not None and lineno < len(out_lines):
                        out_lines[lineno] = f"{key} = {value}"
                if section._pending:
                    # Append queued keys after the section's last existing line
                    # (falling back to the section header, or the file end).
                    insert = -1
                    for _, _, lineno, _ in section._items:
                        if lineno is not None:
                            insert = max(insert, lineno)
                    if insert < 0:
                        insert = len(out_lines)
                    else:
                        insert += 1
                    pending = [f"{k} = {v}" for k, v in section._pending]
                    out_lines[insert:insert] = pending
            text = _EOL.join(out_lines)
            if self._lines:
                text += _EOL
        else:
            text = _EOL.join(self._lines)
            if self._lines:
                text += _EOL
        path.write_text(text, encoding="utf-8", newline="")

    # -- access -------------------------------------------------------------

    def sections_named(self, name):
        """Return all sections whose name equals ``name`` (in file order)."""
        return [s for s in self.sections if s.name == name]

    def section(self, name, first_only=True):
        """Return the first (or all, if ``first_only=False``) section(s) named ``name``.

        Returns ``None`` when no such section exists and ``first_only`` is true;
        returns an empty list when ``first_only`` is false and none exist.
        """
        found = self.sections_named(name)
        if first_only:
            return found[0] if found else None
        return found

    def get(self, section, key, default=None):
        """Return the value of ``key`` in ``section``, or ``default`` if absent.

        ``section`` may be a :class:`Section` or a section name string. The first
        matching section is consulted.
        """
        sec = section if isinstance(section, Section) else self.section(section)
        if sec is None:
            return default
        return sec.get(key, default)

    def set(self, section, key, value):
        """Set ``key`` in ``section`` to ``value``, marking the config dirty.

        ``section`` may be a :class:`Section` or a section name string. If the
        key already exists its line is rewritten on ``write``; if it does not,
        it is appended to the section (before the next section header, or at the
        end of the file). ``value`` is written as ``key = value``.
        """
        sec = section if isinstance(section, Section) else self.section(section)
        if sec is None:
            raise KeyError(f"no section named {section!r}")
        sec._set(key, value)
        self._dirty = True


class Section:
    """One ``[name]`` block of a ``.trn`` file.

    ``_items`` is an ordered list of ``(key, value, lineno)`` triples where
    ``lineno`` is the 0-based source line holding the key (``None`` for keys
    added after read). ``_pending`` holds keys queued to be appended.
    """

    __slots__ = ("_items", "_pending", "name")

    def __init__(self, name, lineno):
        self.name = name
        self._items = []          # [(key, value, lineno), ...]
        self._pending = []        # [(key, value), ...] to append on write

    def _add(self, key, value, lineno):
        # Keep the original parsed value so write() can tell whether a line was
        # actually changed and leave untouched lines at their original spacing.
        self._items.append((key, value, lineno, value))

    def _set(self, key, value):
        value = str(value)
        for i, (k, v, lineno, orig) in enumerate(self._items):
            if k == key:
                self._items[i] = (k, value, lineno, orig)
                return
        # Key not present: queue it for appending on write.
        for i, (k, v) in enumerate(self._pending):
            if k == key:
                self._pending[i] = (k, value)
                return
        self._pending.append((key, value))

    def get(self, key, default=None):
        """Return the value of ``key`` in this section, or ``default``."""
        for k, v, _, _ in self._items:
            if k == key:
                return v
        for k, v in self._pending:
            if k == key:
                return v
        return default

    def keys(self):
        """Ordered keys in this section (including pending appends)."""
        keys = [k for k, _, _, _ in self._items]
        keys.extend(k for k, _ in self._pending)
        return keys

    def items(self):
        """Ordered ``(key, value)`` pairs in this section."""
        items = [(k, v) for k, v, _, _ in self._items]
        items.extend(self._pending)
        return items

    def __repr__(self):
        return f"Section({self.name!r})"


# -- convenience wrappers ----------------------------------------------------


def read_trn(path):
    """Read a ``.trn`` file into a :class:`TerrainConfig`."""
    return TerrainConfig.read(path)


def write_trn(path, config):
    """Write a :class:`TerrainConfig` to ``path``."""
    config.write(path)

# -- complete-file writer (template-and-mutate, AGENTS.md rule 3) -------------

#: Repo-root-relative default template: the stock Elysium world config, vendored
#: verbatim from the game's ``Edit/trn/elysium.trn``. It carries everything a
#: real terrain config needs — ``[Color]``, ``[Sky]``, ``[Clouds]``,
#: ``[Atlases]``, ``[NormalView]``, ``[World]`` and ``[TextureType0..4]`` —
#: which the previous [Size]-only stubs did not, leaving maps with no palette,
#: sky or ground textures in game.
_TRN_TEMPLATE = "elysium.trn"

#: ``[Size]`` origin values for a standalone map. The stock template is a
#: campaign world config (``MinZ=98560``, an atlas offset; ``Height=20``); a
#: standalone workshop map sits at the origin — verified against the corpus's own
#: standalone Elysium maps ``uexmap10.trn`` / ``ubltstg2.trn``.
_STANDALONE_SIZE = (("MinX", "0"), ("MinZ", "0"), ("Height", "0.000000"))


def _default_template():
    """Locate ``reference/elysium.trn`` relative to the repo root."""
    return Path(__file__).resolve().parent.parent.parent / "reference" / _TRN_TEMPLATE


def write_complete_trn(path, width_m, depth_m, template_path=None):
    """Write a **complete** ``.trn`` for a ``width_m`` × ``depth_m`` map.

    Template-and-mutate: the stock world config is cloned verbatim and only
    ``[Size]`` is rewritten — origin values to standalone, ``Width``/``Depth``
    to the map's own dimensions. Nothing is synthesized from the spec, so every
    section a real map needs arrives intact from the template.

    ``template_path`` overrides the default vendored Elysium template (e.g. the
    game's ``Edit/trn/io.trn`` for an Io map — know that world's
    ``[TextureType*]`` semantics before painting the ``.MAT``).

    Returns the written path.
    """
    template = Path(template_path) if template_path else _default_template()
    if not template.is_file():
        raise FileNotFoundError(
            f"trn template not found: {template} (vendored reference/elysium.trn "
            "ships with the repo)"
        )
    cfg = read_trn(template)
    if cfg.section("Size") is None:
        raise ValueError(f"trn template has no [Size] section: {template}")
    for key, value in _STANDALONE_SIZE:
        cfg.set("Size", key, value)
    cfg.set("Size", "Width", str(int(width_m)))
    cfg.set("Size", "Depth", str(int(depth_m)))
    path = Path(path)
    cfg.write(path)
    return path
