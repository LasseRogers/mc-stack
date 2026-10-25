"""Reading the server's own files (whitelist, ops, bans, settings)."""
import json

from . import config


def _read_json(name):
    try:
        return json.loads((config.DATA_DIR / name).read_text())
    except (OSError, ValueError):
        return []


def _names(filename):
    return sorted((entry.get("name", "") for entry in _read_json(filename)), key=str.lower)


def whitelist():
    return _names("whitelist.json")


def banned():
    return _names("banned-players.json")


def ops():
    """Lowercased names, for case-insensitive checks."""
    return {name.lower() for name in _names("ops.json")}


def whitelist_enabled():
    """True/False from server.properties, or None if it can't be read."""
    try:
        for line in (config.DATA_DIR / "server.properties").read_text().splitlines():
            if line.startswith("white-list="):
                return line.split("=", 1)[1].strip() == "true"
    except OSError:
        pass
    return None
