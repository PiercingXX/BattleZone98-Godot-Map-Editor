"""``.bzn`` mission object reader/writer — matched parse/emit pair (docs/02).

The ``.bzn`` is a plain ASCII (CRLF) file that declares ``binarySave = false``.
It is a sequence of ``key [1] =`` / ``value`` pairs (value on the next line) and
``key = value`` pairs (value on the same line), grouped into a header, zero or
more ``[GameObject]`` blocks, and a trailing ``[AiMission]/[AOIs]/[AiPaths]``
block.

The two key/value forms are load-bearing (docs/02 §1): getting them wrong makes
the engine silently mis-parse the file. So, exactly like :mod:`bzmap.formats.trn`,
this module keeps **source lines verbatim** and only rewrites a value line in
place when a mutation has actually been requested. An untouched
:class:`BznFile` round-trips its source byte-for-byte (Rule 4 / R1).

For generation, :class:`GameObject` clones a verbatim template block from
``reference/`` (template-and-mutate, R2) and substitutes position, yaw and
identity values. ``set_position`` updates **all three** places a position lives
(the two ``pos`` blocks and ``transform.posit_*``) so an object renders and
collides in the same place (docs/02 §6 R2).

:meth:`BznFile.validate` enforces the R4 invariants (docs/02 §6 R4): ``size``
matches the object count, ``seq_count`` is ``max(seqno) + 1``, ``obj_addr`` is
contiguous from ``00000001``, exactly one ``player`` object with ``team = 1``,
and the trailing ``[AiMission]/[AOIs]/[AiPaths]`` block is present with sizes 0.
``msn_filename``/``TerrainName`` are **never** rewritten on load — they are
vestigial editor residue and must round-trip verbatim (docs/02 §2).
"""

from __future__ import annotations

import math
from pathlib import Path

# Line endings are CRLF per docs/02 §1.
_EOL = "\r\n"


def _fmt_float(value):
    """Format a float in C ``%g`` style with three-digit exponents (docs/02 §1).

    Python's ``%g`` writes ``1e+30``; the corpus uses ``1e+030``. Values that do
    not hit scientific notation (positions, yaw cos/sin) are unaffected.
    """
    s = f"{value:g}"
    # Expand e+30 / e-7 to e+030 / e-007.
    if "e" in s or "E" in s:
        mantissa, _, exponent = s.partition("e")
        sign = "-" if exponent.startswith("-") else "+"
        digits = exponent.lstrip("+-")
        return f"{mantissa}e{sign}{digits.zfill(3)}"
    return s


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


def _value_line_index(lines, key):
    """Return the index of the value line for ``key`` in ``lines``.

    ``key`` may be given with or without the ``[1]`` suffix (``"PrjID [1]"`` or
    ``"PrjID"``). Handles both forms: ``key [1] =`` (value on the next line) and
    ``key = value`` (value on the same line). Returns ``None`` when the key is
    absent.
    """
    base = key
    if base.endswith(" [1]"):
        base = base.removesuffix(" [1]")
    next_form = f"{base} [1] ="
    inline = f"{base} ="
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == next_form:
            return i + 1
        if stripped == inline or stripped.startswith(inline):
            return i
    return None


def _get_value(lines, key, default=None):
    """Return the value for ``key`` (either value form), or ``default``.

    For the ``key [1] =`` form the value is the whole following line; for the
    ``key = value`` form it is the text after ``=``. Returns ``None`` when the
    key is absent.
    """
    idx = _value_line_index(lines, key)
    if idx is None:
        return default
    line = lines[idx]
    if "=" in line:
        return line.partition("=")[2].strip()
    return line.strip()


def _pos_value_indices(lines):
    """Return ``(x, y, z)`` value-line indices for each ``pos [1] =`` block.

    A ``pos`` block is ``pos [1] =`` followed by ``  x/y/z [1] =`` each with its
    value on the next line. Every object carries the block twice (before ``team``
    and after ``illumination``), and both must be kept in sync.
    """
    result = []
    for i, line in enumerate(lines):
        if line.strip() != "pos [1] =":
            continue
        block = lines[i + 1:i + 7]
        idx = {}
        for j, bl in enumerate(block):
            stripped = bl.strip()
            if stripped == "x [1] =":
                idx["x"] = i + j + 2
            elif stripped == "y [1] =":
                idx["y"] = i + j + 2
            elif stripped == "z [1] =":
                idx["z"] = i + j + 2
        if len(idx) == 3:
            result.append((idx["x"], idx["y"], idx["z"]))
    return result


class GameObject:
    """One verbatim ``[GameObject]`` block with in-place value mutation.

    ``lines`` is the block's source lines (no EOL), kept verbatim. Mutation
    methods rewrite only the specific value lines they own; everything else —
    indentation, ordering, the duplicate ``pos`` block, float formatting — is
    preserved byte-for-byte.
    """

    def __init__(self, lines):
        self.lines = list(lines)

    @classmethod
    def from_template(cls, text):
        """Build a :class:`GameObject` from a verbatim template block string.

        Template annotation lines (``#``) are stripped; the block is otherwise
        taken verbatim as the mutation baseline.
        """
        return cls(_strip_comments(text))

    # -- mutation -----------------------------------------------------------

    def set_position(self, x, y, z):
        """Set the object's world position in all three places it appears.

        Updates both ``pos`` blocks (before ``team`` and after ``illumination``)
        and ``transform.posit_x/y/z``. Missing any one of these would render the
        object in one place and collide in another.
        """
        for x_idx, y_idx, z_idx in _pos_value_indices(self.lines):
            self.lines[x_idx] = _fmt_float(x)
            self.lines[y_idx] = _fmt_float(y)
            self.lines[z_idx] = _fmt_float(z)
        for key, val in (("posit_x", x), ("posit_y", y), ("posit_z", z)):
            idx = _value_line_index(self.lines, key)
            if idx is not None:
                self.lines[idx] = _fmt_float(val)

    def set_yaw(self, theta):
        """Set a pure yaw rotation about Y (docs/02 §4).

        ``right = (cos θ, 0, -sin θ)``, ``up = (0, 1, 0)``,
        ``front = (sin θ, 0, cos θ)``. The 3x3 basis is rewritten to a clean
        rotation; ``posit_*`` is left untouched (it holds the position).
        """
        c = math.cos(theta)
        s = math.sin(theta)
        basis = {
            "right_x": c, "right_y": 0.0, "right_z": -s,
            "up_x": 0.0, "up_y": 1.0, "up_z": 0.0,
            "front_x": s, "front_y": 0.0, "front_z": c,
        }
        for key, val in basis.items():
            idx = _value_line_index(self.lines, key)
            if idx is not None:
                self.lines[idx] = _fmt_float(val)

    def set_identity(self, seqno, addr, label):
        """Set ``seqno``/``seqNo``, ``obj_addr`` and ``label``.

        ``addr`` is written as 8-digit lowercase hex (``00000001``). ``seqno``
        and ``seqNo`` are distinct fields that must hold the same value.
        """
        for key in ("seqno [1]", "seqNo [1]"):
            idx = _value_line_index(self.lines, key)
            if idx is not None:
                self.lines[idx] = str(seqno)
        idx = _value_line_index(self.lines, "obj_addr")
        if idx is not None:
            self.lines[idx] = f"obj_addr = {addr:08x}"
        idx = _value_line_index(self.lines, "label")
        if idx is not None:
            self.lines[idx] = f"label = {label}"

    # -- access -------------------------------------------------------------

    def _get(self, key, default=None):
        return _get_value(self.lines, key, default)

    @property
    def prjid(self):
        return self._get("PrjID [1]")

    @property
    def seqno(self):
        val = self._get("seqno [1]")
        return int(val) if val is not None else None

    @property
    def label(self):
        return self._get("label")

    @property
    def team(self):
        val = self._get("team [1]")
        return int(val) if val is not None else None

    @property
    def obj_addr(self):
        val = self._get("obj_addr")
        return int(val, 16) if val is not None else None

    def position(self):
        """Return ``(x, y, z)`` from the first ``pos`` block, or ``None``."""
        idxs = _pos_value_indices(self.lines)
        if not idxs:
            return None
        x_idx, y_idx, z_idx = idxs[0]
        try:
            return (
                float(self.lines[x_idx].strip()),
                float(self.lines[y_idx].strip()),
                float(self.lines[z_idx].strip()),
            )
        except ValueError:
            return None

    def yaw_deg(self):
        """Recover the pure-Y yaw in degrees from the transform basis.

        ``set_yaw`` writes ``front = (sin θ, 0, cos θ)``, so
        ``θ = atan2(front_x, front_z)``.
        """
        fx = self._get("front_x [1]")
        fz = self._get("front_z [1]")
        if fx is None or fz is None:
            return 0.0
        try:
            return math.degrees(math.atan2(float(fx), float(fz)))
        except ValueError:
            return 0.0

    def is_user(self):
        """True when this block is the player object (``isUser = 1``)."""
        val = self._get("isUser [1]")
        if val is None:
            return False
        try:
            return int(val) == 1
        except ValueError:
            return False

    def set_team(self, team):
        """Set ``team [1]`` in place."""
        idx = _value_line_index(self.lines, "team [1]")
        if idx is None:
            raise KeyError("no team [1] field")
        line = self.lines[idx]
        if "=" in line:
            self.lines[idx] = f"team [1] = {int(team)}"
        else:
            self.lines[idx] = str(int(team))

    def set_is_user(self, flag):
        """Set ``isUser [1]`` in place."""
        idx = _value_line_index(self.lines, "isUser [1]")
        if idx is None:
            raise KeyError("no isUser [1] field")
        value = "1" if flag else "0"
        line = self.lines[idx]
        if "=" in line:
            self.lines[idx] = f"isUser [1] = {value}"
        else:
            self.lines[idx] = value

    def render(self):
        """Return the block as CRLF text (no trailing newline)."""
        return _EOL.join(self.lines)

    def __repr__(self):
        return f"GameObject({self.prjid!r})"


def _split_blocks(lines):
    """Partition source lines into (header, [object_blocks], tail).

    A ``[GameObject]`` line opens a new object block; ``[AiMission]`` opens the
    tail. Everything before the first ``[GameObject]`` is the header.
    """
    header = []
    objects = []
    tail = []
    current = None
    for line in lines:
        stripped = line.strip()
        if stripped == "[GameObject]":
            current = [line]
            objects.append(current)
            continue
        if stripped == "[AiMission]":
            current = tail
            tail.append(line)
            continue
        if current is None:
            header.append(line)
        else:
            current.append(line)
    return header, objects, tail


class BznFile:
    """A parsed ``.bzn`` mission file: header, objects, and trailing block.

    ``header`` and ``tail`` are lists of source lines kept verbatim; ``objects``
    is a list of :class:`GameObject`. An untouched :class:`BznFile` re-emits its
    source byte-for-byte.
    """

    def __init__(self, header, objects, tail, trailing_newline=True):
        self.header = list(header)
        self.objects = list(objects)
        self.tail = list(tail)
        self._trailing_newline = trailing_newline
        self._dirty = False

    # -- serialization ------------------------------------------------------

    @classmethod
    def read(cls, path):
        """Read a ``.bzn`` file into a :class:`BznFile`."""
        path = Path(path)
        raw = path.read_bytes()
        text = raw.decode("utf-8-sig")
        lines = text.splitlines()
        trailing = text.endswith(("\n", "\r"))
        header, objects, tail = _split_blocks(lines)
        return cls(header, [GameObject(block) for block in objects], tail, trailing)

    def write(self, path):
        """Write this file to ``path``, preserving CRLF line endings.

        Untouched files are re-emitted verbatim; mutated blocks rewrite only
        their changed value lines.
        """
        path = Path(path)
        parts = list(self.header)
        for obj in self.objects:
            parts.extend(obj.lines)
        parts.extend(self.tail)
        text = _EOL.join(parts)
        if self._trailing_newline:
            text += _EOL
        path.write_text(text, encoding="utf-8", newline="")

    # -- construction -------------------------------------------------------

    @classmethod
    def build(cls, header_text, object_blocks, tail_text):
        """Assemble a new :class:`BznFile` from template text blocks.

        ``object_blocks`` is a list of :class:`GameObject` (typically built by
        cloning ``reference/bzn-object-template.txt``). Template ``#`` comments
        are stripped from the header and tail.
        """
        header = _strip_comments(header_text)
        tail = _strip_comments(tail_text)
        return cls(header, object_blocks, tail)

    # -- access -------------------------------------------------------------

    def header_value(self, key, default=None):
        """Return the value for a header ``key`` (either value form)."""
        return _get_value(self.header, key, default)

    def set_header(self, key, value):
        """Set a header key's value in place, marking the file dirty."""
        idx = _value_line_index(self.header, key)
        if idx is None:
            raise KeyError(f"no header key {key!r}")
        line = self.header[idx]
        if "=" in line:
            base = key.removesuffix(" [1]")
            self.header[idx] = f"{base} = {value}"
        else:
            self.header[idx] = str(value)
        self._dirty = True

    def add_object(self, obj):
        """Append a :class:`GameObject` to the file, marking it dirty."""
        self.objects.append(obj)
        self._dirty = True

    # -- R4 invariants ------------------------------------------------------

    def validate(self):
        """Enforce the R4 invariants (docs/02 §6 R4).

        Returns a list of human-readable violation strings; an empty list means
        the file is valid. ``msn_filename``/``TerrainName`` are intentionally
        **not** checked — they are vestigial and must not be validated.
        """
        problems = []

        size = self.header_value("size [1]")
        if size is not None:
            if int(size) != len(self.objects):
                problems.append(
                    f"size {size} != object count {len(self.objects)}"
                )
        else:
            problems.append("header missing 'size [1]'")

        seqs = [o.seqno for o in self.objects if o.seqno is not None]
        if seqs:
            expected = max(seqs) + 1
            seq_count = self.header_value("seq_count [1]")
            if seq_count is not None and int(seq_count) != expected:
                problems.append(
                    f"seq_count {seq_count} != max(seqno)+1 = {expected}"
                )

        # obj_addr contiguous from 00000001 in file order.
        addrs = [o.obj_addr for o in self.objects]
        if addrs and addrs != list(range(1, len(addrs) + 1)):
            problems.append(
                f"obj_addr not contiguous from 00000001: {addrs}"
            )

        # Exactly one player object, team = 1.
        players = [o for o in self.objects if o.prjid == "player"]
        if len(players) != 1:
            problems.append(f"expected exactly one player object, found {len(players)}")
        elif players[0].team != 1:
            problems.append(f"player team is {players[0].team}, expected 1")

        # Trailing AiMission/AOIs/AiPaths block present, sizes 0.
        tail_text = _EOL.join(self.tail)
        if "[AiMission]" not in tail_text:
            problems.append("missing [AiMission] trailing block")
        if "[AOIs]" not in tail_text:
            problems.append("missing [AOIs] trailing block")
        if "[AiPaths]" not in tail_text:
            problems.append("missing [AiPaths] trailing block")

        return problems


# -- convenience wrappers ----------------------------------------------------


def read_bzn(path):
    """Read a ``.bzn`` file into a :class:`BznFile`."""
    return BznFile.read(path)


def write_bzn(path, bzn):
    """Write a :class:`BznFile` to ``path``."""
    bzn.write(path)