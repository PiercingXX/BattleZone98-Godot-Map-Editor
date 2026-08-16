"""Install and workshop discovery for ``bzmap editor probe``.

Specified in the map editor's ``docs/05`` §2a / §2b. Path logic lives here
once so the Godot side never reimplements it.

A directory is a BZ98R install only if it contains ``battlezone98redux.exe``
and ``BZ_ASSETS/common/models/``. Workshop items are the union of
``steamapps/workshop/content/301650/<id>/`` and ``<install>/packaged_mods/<id>/``,
keyed by ID, with ``packaged_mods`` preferred when both exist.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from bzmap.editor.errors import EditorError

STEAM_APP_ID = "301650"
INSTALL_DIR_NAME = "Battlezone 98 Redux"
EXE_NAME = "battlezone98redux.exe"
MODELS_REL = Path("BZ_ASSETS") / "common" / "models"

# Asset extensions that mean "this workshop item is an asset pack".
_ASSET_SUFFIXES = {
    ".odf", ".mesh", ".skeleton", ".material", ".dds", ".png",
    ".geo", ".vdf", ".sdf", ".map", ".act",
    ".bzn", ".trn", ".hg2", ".mat", ".lgt", ".vxt", ".des",
}

_PATH_RE = re.compile(r'"path"\s*"([^"]+)"', re.IGNORECASE)


def _linux_steam_roots():
    home = Path.home()
    return [
        home / ".steam" / "steam",
        home / ".local" / "share" / "Steam",
        home / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
        home / ".steam" / "root",
        home / ".steam" / "debian-installation",
    ]


def _windows_steam_roots():
    roots = []
    if sys.platform != "win32":
        return roots
    try:
        import winreg
    except ImportError:
        winreg = None
    if winreg is not None:
        for hive, subkey, value_name in (
            (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
        ):
            try:
                with winreg.OpenKey(hive, subkey) as key:
                    val, _ = winreg.QueryValueEx(key, value_name)
                if val:
                    roots.append(Path(val))
            except OSError:
                pass
    for env in ("ProgramFiles(x86)", "ProgramFiles"):
        base = os.environ.get(env)
        if base:
            roots.append(Path(base) / "Steam")
    return roots


def _steam_roots():
    if sys.platform == "win32":
        return _windows_steam_roots()
    return _linux_steam_roots()


def parse_libraryfolders_vdf(text):
    """Return every ``"path"`` value in a Steam ``libraryfolders.vdf``.

    The schema has changed across Steam versions; we pull every path regardless
    of nesting rather than matching a fixed tree.
    """
    paths = []
    for match in _PATH_RE.finditer(text):
        raw = match.group(1).replace("\\\\", "\\")
        paths.append(Path(raw))
    return paths


def _libraries_from_root(steam_root):
    steam_root = Path(steam_root)
    try:
        steam_root = steam_root.resolve()
    except OSError:
        steam_root = steam_root.expanduser()
    libraries = [steam_root]
    vdf = steam_root / "steamapps" / "libraryfolders.vdf"
    if vdf.is_file():
        try:
            text = vdf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        for lib in parse_libraryfolders_vdf(text):
            libraries.append(lib)
    # Dedup by resolved path when possible.
    seen = set()
    out = []
    for lib in libraries:
        try:
            key = str(lib.resolve())
        except OSError:
            key = str(lib)
        if key in seen:
            continue
        seen.add(key)
        out.append(lib)
    return out


def _has_exe(install):
    """Case-insensitive look for the game executable."""
    if not install.is_dir():
        return False
    target = EXE_NAME.lower()
    try:
        for child in install.iterdir():
            if child.is_file() and child.name.lower() == target:
                return True
    except OSError:
        return False
    return False


def is_game_install(path):
    """True when ``path`` has the exe and ``BZ_ASSETS/common/models/``."""
    path = Path(path)
    if not path.is_dir():
        return False
    models = path / MODELS_REL
    return _has_exe(path) and models.is_dir()


def _appmanifest(library):
    return Path(library) / "steamapps" / f"appmanifest_{STEAM_APP_ID}.acf"


def _read_acf_field(path, field):
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    match = re.search(rf'"{re.escape(field)}"\s*"([^"]*)"', text)
    return match.group(1) if match else None


def _gog_installs():
    found = []
    if sys.platform == "win32":
        try:
            import winreg
        except ImportError:
            winreg = None
        if winreg is not None:
            for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
                for sub in (
                    r"SOFTWARE\WOW6432Node\GOG.com\Games",
                    r"SOFTWARE\GOG.com\Games",
                ):
                    try:
                        with winreg.OpenKey(hive, sub) as root:
                            i = 0
                            while True:
                                try:
                                    name = winreg.EnumKey(root, i)
                                except OSError:
                                    break
                                i += 1
                                try:
                                    with winreg.OpenKey(root, name) as key:
                                        game_name, _ = winreg.QueryValueEx(key, "gameName")
                                        game_path, _ = winreg.QueryValueEx(key, "path")
                                except OSError:
                                    continue
                                if "battlezone" in str(game_name).lower() and game_path:
                                    found.append(Path(game_path))
                    except OSError:
                        continue
    else:
        for candidate in (
            Path.home() / "GOG Games" / "Battlezone 98 Redux",
            Path.home() / "GOG Games" / INSTALL_DIR_NAME,
        ):
            if candidate.is_dir():
                found.append(candidate)
    return found


def _item_has_assets(directory):
    try:
        for child in directory.iterdir():
            if child.is_file() and child.suffix.lower() in _ASSET_SUFFIXES:
                return True
    except OSError:
        return False
    return False


def _item_stats(directory):
    count = 0
    size = 0
    try:
        for child in directory.iterdir():
            if child.is_file():
                count += 1
                try:
                    size += child.stat().st_size
                except OSError:
                    pass
    except OSError:
        return 0, 0
    return count, size


def discover(override=None):
    """Return ``{"installs": [...], "warnings": [...]}``.

    ``override`` is an explicit game-root the caller already chose; it is
    validated and listed first when it passes.
    """
    warnings = []
    installs = []
    seen_installs = set()

    def add_install(path, *, kind="game", platform_hint=None, version=None):
        path = Path(path)
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        key = str(resolved).lower() if sys.platform == "win32" else str(resolved)
        if key in seen_installs:
            return
        if not is_game_install(resolved):
            return
        seen_installs.add(key)
        if platform_hint is None:
            if sys.platform == "win32":
                platform_hint = "windows"
            else:
                platform_hint = "proton"
        entry = {
            "kind": kind,
            "path": str(resolved),
            "version": version or "",
            "platform_hint": platform_hint,
        }
        installs.append(entry)

    if override:
        override_path = Path(override).expanduser()
        if is_game_install(override_path):
            add_install(override_path)
        else:
            raise EditorError(
                "install_invalid",
                f"not a BZ98R install: {override_path}",
                hint="need battlezone98redux.exe and BZ_ASSETS/common/models/",
                path=override_path,
            )

    libraries = []
    seen_libs = set()
    for root in _steam_roots():
        if not root.exists():
            continue
        for lib in _libraries_from_root(root):
            try:
                key = str(lib.resolve())
            except OSError:
                key = str(lib)
            if key in seen_libs:
                continue
            seen_libs.add(key)
            libraries.append(lib)

    for lib in libraries:
        candidate = lib / "steamapps" / "common" / INSTALL_DIR_NAME
        version = _read_acf_field(_appmanifest(lib), "buildid")
        add_install(candidate, version=version)

    for gog in _gog_installs():
        add_install(gog, platform_hint="gog")

    # Workshop layers, union by ID.
    workshop_items = {}  # id -> {workshop_path, packaged_path, name}

    def note_item(item_id, path, source):
        rec = workshop_items.setdefault(
            item_id, {"workshop": None, "packaged": None, "name": item_id}
        )
        rec[source] = path

    for lib in libraries:
        workshop = lib / "steamapps" / "workshop" / "content" / STEAM_APP_ID
        if not workshop.is_dir():
            continue
        try:
            children = list(workshop.iterdir())
        except OSError:
            continue
        for child in children:
            if child.is_dir():
                note_item(child.name, child, "workshop")

    for inst in installs:
        packaged = Path(inst["path"]) / "packaged_mods"
        if not packaged.is_dir():
            continue
        try:
            children = list(packaged.iterdir())
        except OSError:
            continue
        for child in children:
            if child.is_dir():
                note_item(child.name, child, "packaged")

    for item_id, rec in sorted(workshop_items.items()):
        packaged_path = rec["packaged"]
        workshop_path = rec["workshop"]
        if packaged_path is not None and workshop_path is not None:
            source = "both"
            path = packaged_path  # the copy the game actually loads
        elif packaged_path is not None:
            source = "packaged"
            path = packaged_path
        else:
            source = "workshop"
            path = workshop_path
        if path is None or not _item_has_assets(path):
            continue
        count, size = _item_stats(path)
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path
        installs.append({
            "kind": "workshop_item",
            "path": str(resolved),
            "name": rec["name"],
            "id": str(item_id),
            "source": source,
            "file_count": count,
            "size_bytes": size,
        })

    if not any(i.get("kind") == "game" for i in installs):
        warnings.append("no game install found at any default path")

    return {"installs": installs, "warnings": warnings, "libraries": [str(p) for p in libraries]}


def first_game_root(discovery=None):
    """Return the first discovered game install path, or None."""
    if discovery is None:
        discovery = discover()
    for item in discovery["installs"]:
        if item.get("kind") == "game":
            return Path(item["path"])
    return None
