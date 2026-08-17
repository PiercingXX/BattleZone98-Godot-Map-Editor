"""``bzmap editor <verb>`` dispatch (map-editor docs/02)."""

from __future__ import annotations

import sys
import traceback

from bzmap import __version__ as BZMAP_VERSION
from bzmap.editor import CONTRACT_VERSION
from bzmap.editor.discover import discover
from bzmap.editor.errors import EditorError
from bzmap.editor.jsonio import emit
from bzmap.editor.new import create_map
from bzmap.editor.open import open_map
from bzmap.editor.save import save_session
from bzmap.editor.assets import build_assets
from bzmap.editor.package_cmd import package_session
from bzmap.editor.render_cmd import render_session
from bzmap.editor.validate import validate_session
from bzmap.editor.worlds import worlds_from_game


def add_editor_parser(sub):
    """Register the ``editor`` command group on the top-level parser."""
    editor = sub.add_parser(
        "editor",
        help="editor interchange: session JSON + row-major buffers",
    )
    verbs = editor.add_subparsers(dest="editor_verb", required=True)

    probe = verbs.add_parser("probe", help="find game installs and workshop items")
    probe.add_argument("--json", action="store_true")
    probe.set_defaults(editor_handler=_cmd_probe)

    worlds = verbs.add_parser("worlds", help="list stock terrain templates")
    worlds.add_argument("--game-root", required=True)
    worlds.add_argument("--json", action="store_true")
    worlds.set_defaults(editor_handler=_cmd_worlds)

    new = verbs.add_parser("new", help="create a fresh map session")
    new.add_argument("--stem", required=True)
    new.add_argument("--world", required=True)
    new.add_argument("--width", type=int, required=True)
    new.add_argument("--depth", type=int, required=True)
    new.add_argument("--base-height", type=int, default=1000)
    new.add_argument("--session", required=True)
    new.add_argument("--game-root", default="")
    new.add_argument("--pack-kind", choices=("bzp", "base"), default="bzp")
    new.add_argument("--json", action="store_true")
    new.set_defaults(editor_handler=_cmd_new)

    open_p = verbs.add_parser("open", help="open a map into a session")
    open_p.add_argument("path")
    open_p.add_argument("--session", required=True)
    open_p.add_argument("--json", action="store_true")
    open_p.set_defaults(editor_handler=_cmd_open)

    save = verbs.add_parser("save", help="write a session out to a map file set")
    save.add_argument("--session", required=True)
    save.add_argument("--out", required=True)
    save.add_argument("--stem", default="")
    save.add_argument("--json", action="store_true")
    save.set_defaults(editor_handler=_cmd_save)

    validate = verbs.add_parser("validate", help="run offline validators on a session")
    validate.add_argument("--session", required=True)
    validate.add_argument("--tier", default="1,2")
    validate.add_argument("--game-root", default="")
    validate.add_argument("--json", action="store_true")
    validate.set_defaults(editor_handler=_cmd_validate)

    assets = verbs.add_parser("assets", help="enumerate install classes into a cache")
    assets.add_argument("--game-root", required=True)
    assets.add_argument("--cache", required=True)
    assets.add_argument("--pack", action="append", default=[])
    assets.add_argument("--refresh", action="store_true")
    assets.add_argument("--json", action="store_true")
    assets.set_defaults(editor_handler=_cmd_assets)

    render = verbs.add_parser("render", help="north-up thumbnail / overview")
    render.add_argument("--session", required=True)
    render.add_argument("--out", required=True)
    render.add_argument("--debug", action="store_true")
    render.add_argument("--json", action="store_true")
    render.set_defaults(editor_handler=_cmd_render)

    package = verbs.add_parser("package", help="install to test mod or assemble a pack")
    package.add_argument("--session", required=True)
    package.add_argument("--mode", choices=("install", "pack"), required=True)
    package.add_argument("--game-root", default="")
    package.add_argument("--test-id", default="")
    package.add_argument("--out", default="")
    package.add_argument("--json", action="store_true")
    package.set_defaults(editor_handler=_cmd_package)

    editor.set_defaults(func=run_editor)
    return editor


def run_editor(args):
    """Run one editor verb. Always emits one JSON object on stdout."""
    handler = getattr(args, "editor_handler", None)
    if handler is None:
        return emit(
            EditorError("no_verb", "no editor verb").as_dict(),
            exit_code=2,
        )
    try:
        payload = handler(args)
        if not isinstance(payload, dict):
            payload = {"ok": True, "result": payload}
        payload.setdefault("ok", True)
        return emit(payload, exit_code=0 if payload.get("ok") else 1)
    except EditorError as exc:
        return emit(exc.as_dict(), exit_code=1)
    except Exception as exc:  # noqa: BLE001 — bridge must never die silent
        print(traceback.format_exc(), file=sys.stderr)
        return emit(
            EditorError(
                "backend_crash",
                f"{type(exc).__name__}: {exc}",
                hint="stderr has the traceback; the session was not modified "
                     "beyond what the verb had already written",
            ).as_dict(),
            exit_code=2,
        )


def _cmd_probe(_args):
    found = discover()
    return {
        "ok": True,
        "bzmap_version": BZMAP_VERSION,
        "contract_version": CONTRACT_VERSION,
        "python": sys.version.split()[0],
        "installs": found["installs"],
        "warnings": found["warnings"],
    }


def _cmd_worlds(args):
    worlds = worlds_from_game(args.game_root)
    return {"ok": True, "worlds": worlds}


def _cmd_new(args):
    return create_map(
        args.stem,
        args.world,
        args.width,
        args.depth,
        args.session,
        args.game_root or None,
        base_height=args.base_height,
        pack_kind=args.pack_kind,
    )


def _cmd_open(args):
    return open_map(args.path, args.session)


def _cmd_save(args):
    return save_session(args.session, args.out, stem=args.stem or None)


def _cmd_validate(args):
    return validate_session(
        args.session,
        tier=args.tier,
        game_root=args.game_root or None,
    )


def _cmd_assets(args):
    return build_assets(
        args.game_root,
        args.cache,
        pack_paths=args.pack or None,
        refresh=args.refresh,
    )


def _cmd_render(args):
    return render_session(args.session, args.out, debug=args.debug)


def _cmd_package(args):
    return package_session(
        args.session,
        args.mode,
        game_root=args.game_root or None,
        test_id=args.test_id or None,
        out_dir=args.out or None,
    )
