"""On-demand world backups, in the same format as itzg/mc-backup."""
import fnmatch
import os
import tarfile
import threading
import time
from datetime import datetime

from . import config, rcon_client

# Same defaults as itzg/mc-backup's EXCLUDES.
EXCLUDES = ["*.jar", "cache", "logs", "*.tmp", ".mc-backup-lock"]

_lock = threading.Lock()
_state = {"running": False, "error": None}


def status():
    return dict(_state)


def latest():
    """Newest backup as (name, age in seconds), or None."""
    try:
        files = [p for p in config.BACKUP_DIR.glob("world-*.tar.gz") if p.is_file()]
    except OSError:
        return None
    if not files:
        return None
    newest = max(files, key=lambda p: p.stat().st_mtime)
    return newest.name, time.time() - newest.stat().st_mtime


def start():
    """Start a backup in the background. False if one is already running."""
    if not _lock.acquire(blocking=False):
        return False
    _state.update(running=True, error=None)
    threading.Thread(target=_run, daemon=True).start()
    return True


def _run():
    try:
        rcon_client.run("save-off")
        try:
            rcon_client.run("save-all flush")
            _write_archive()
        finally:
            rcon_client.run("save-on")
    except Exception as e:
        _state["error"] = str(e)
    finally:
        _state["running"] = False
        _lock.release()


def _excluded(tarinfo):
    parts = tarinfo.name.split("/")
    for part in parts:
        if any(fnmatch.fnmatch(part, pattern) for pattern in EXCLUDES):
            return None
    return tarinfo


def _write_archive():
    name = datetime.now().strftime("world-%Y%m%d-%H%M%S.tar.gz")
    final = config.BACKUP_DIR / name
    # Hidden while being written, so sync and restore ignore partial files.
    tmp = config.BACKUP_DIR / f".{name}.part"
    try:
        with tarfile.open(tmp, "w:gz") as tar:
            tar.add(config.DATA_DIR, arcname=".", filter=_excluded)
        os.replace(tmp, final)
    finally:
        if tmp.exists():
            tmp.unlink()
    return name
