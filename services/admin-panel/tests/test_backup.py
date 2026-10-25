import os
import re
import tarfile
import threading
import time

from app import backup
from conftest import post_action, wait_for_backup

NAME_RE = re.compile(r"^world-\d{8}-\d{6}\.tar\.gz$")


def run_backup():
    assert backup.start()
    wait_for_backup()


def archive_names(backup_dir):
    (archive,) = backup_dir.iterdir()
    with tarfile.open(archive) as tar:
        return archive.name, set(tar.getnames())


def test_creates_archive(data_dir, backup_dir, rcon):
    run_backup()
    name, members = archive_names(backup_dir)
    assert NAME_RE.match(name)
    assert {"./server.properties", "./world/level.dat", "./world/region/r.0.0.mca"} <= members
    assert backup.status() == {"running": False, "error": None}


def test_rcon_sequence(data_dir, backup_dir, rcon):
    run_backup()
    assert rcon.commands == ["save-off", "save-all flush", "save-on"]


def test_excludes(data_dir, backup_dir, rcon):
    (data_dir / "logs").mkdir()
    (data_dir / "logs" / "latest.log").write_text("log")
    (data_dir / "cache").mkdir()
    (data_dir / "cache" / "x").write_text("c")
    (data_dir / "server.jar").write_text("jar")
    (data_dir / "world" / "session.tmp").write_text("t")
    (data_dir / ".mc-backup-lock").write_text("")
    run_backup()
    _, members = archive_names(backup_dir)
    assert not any(
        part in ("logs", "cache", ".mc-backup-lock") or part.endswith((".jar", ".tmp"))
        for m in members for part in m.split("/")
    )


def test_failure_resumes_saving(data_dir, backup_dir, rcon):
    rcon.fail_on = "save-all flush"
    run_backup()
    assert rcon.commands == ["save-off", "save-all flush", "save-on"]
    assert backup.status()["error"] == "server offline"
    assert list(backup_dir.iterdir()) == []


def test_server_offline(data_dir, backup_dir, rcon):
    rcon.fail_on = "*"
    run_backup()
    assert backup.status()["error"] == "server offline"
    assert list(backup_dir.iterdir()) == []


def test_no_partial_file_on_write_error(data_dir, backup_dir, rcon, monkeypatch):
    def broken(*args, **kwargs):
        raise OSError("disk full")
    monkeypatch.setattr(backup.os, "replace", broken)
    run_backup()
    assert backup.status()["error"] == "disk full"
    assert list(backup_dir.iterdir()) == []
    assert rcon.commands[-1] == "save-on"


def test_only_one_at_a_time(data_dir, backup_dir, rcon, monkeypatch):
    release = threading.Event()
    real = rcon.__call__

    def slow(command):
        if command == "save-all flush":
            release.wait(5)
        return real(command)

    monkeypatch.setattr(backup.rcon_client, "run", slow)
    assert backup.start()
    assert not backup.start()
    release.set()
    wait_for_backup()
    assert backup.start()


def test_latest(backup_dir):
    assert backup.latest() is None
    old = backup_dir / "world-20260101-000000.tar.gz"
    new = backup_dir / "world-20260102-000000.tar.gz"
    old.write_text("")
    new.write_text("")
    os.utime(old, (time.time() - 7200,) * 2)
    os.utime(new, (time.time() - 600,) * 2)
    name, age = backup.latest()
    assert name == new.name
    assert 590 < age < 700


def test_button(logged_in, backup_dir, rcon):
    r = post_action(logged_in, action="backup")
    assert "Backup started." in r.text
    wait_for_backup()
    page = logged_in.get("/").text
    assert "Create backup" in page
    assert "Save world" not in page
    assert re.search(r"Latest backup: world-\d{8}-\d{6}\.tar\.gz \(0 min ago\)", page)


def test_button_while_running(logged_in, backup_dir, rcon, monkeypatch):
    release = threading.Event()
    real = rcon.__call__

    def slow(command):
        if command == "save-all flush":
            release.wait(5)
        return real(command)

    monkeypatch.setattr(backup.rcon_client, "run", slow)
    post_action(logged_in, action="backup")
    r = post_action(logged_in, action="backup")
    assert "A backup is already running." in r.text
    assert "Backup in progress" in r.text
    release.set()
