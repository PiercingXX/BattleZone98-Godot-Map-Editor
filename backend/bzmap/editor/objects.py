"""``objects.json`` <-> BZN object blocks (map-editor docs/02 §4a)."""

from __future__ import annotations

import math

from bzmap.formats.bzn import GameObject, read_bzn


def objects_from_bzn(bzn, *, id_prefix="obj"):
    """Return ``(records, blocks)`` for one parsed :class:`BznFile`.

    ``records`` is the editor-facing list. ``blocks`` is the same-order list of
    verbatim :class:`GameObject` instances, stored in residue by id so save
    can re-emit untouched blocks byte-for-byte.
    """
    records = []
    blocks = {}
    for i, obj in enumerate(bzn.objects, start=1):
        obj_id = f"{id_prefix}-{i:04d}"
        pos = obj.position() or (0.0, 0.0, 0.0)
        required = obj.is_user() or (obj.prjid or "").lower() == "player"
        record = {
            "id": obj_id,
            "origin": "source",
            "prjid": obj.prjid,
            "x": pos[0],
            "y": pos[1],
            "z": pos[2],
            "yaw_deg": obj.yaw_deg(),
            "team": obj.team if obj.team is not None else 0,
            "label": obj.label or "",
            "up_convention": "upright",
            "pinned_y": False,
            "managed": False,
            "required": required,
        }
        records.append(record)
        blocks[obj_id] = obj
    return records, blocks


def load_variant_objects(path, *, id_prefix="obj"):
    """Read a BZN path into ``(records, blocks, bzn)``."""
    bzn = read_bzn(path)
    records, blocks = objects_from_bzn(bzn, id_prefix=id_prefix)
    return records, blocks, bzn


def apply_record_to_block(obj: GameObject, record):
    """Mutate a cloned/source block to match an editor record."""
    obj.set_position(record["x"], record["y"], record["z"])
    obj.set_yaw(math.radians(float(record.get("yaw_deg", 0.0))))
    if record.get("team") is not None:
        try:
            obj.set_team(record["team"])
        except KeyError:
            pass
    if record.get("label"):
        obj.set_identity(
            seqno=obj.seqno if obj.seqno is not None else 0,
            addr=obj.obj_addr if obj.obj_addr is not None else 1,
            label=record["label"],
        )
    return obj
