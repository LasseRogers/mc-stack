import json
import os
import re
import sys
import time
from pathlib import Path

import pytest

# config.py reads these at import time.
os.environ.setdefault("RCON_PASSWORD", "test-rcon")
os.environ.setdefault("ADMIN_PASSWORD", "test-password")
os.environ.setdefault("SECRET_KEY", "test-secret")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import auth, backup, config, create_app, rcon_client  # noqa: E402

PASSWORD = os.environ["ADMIN_PASSWORD"]
LIST_OUTPUT = "There are 2 of a max of 20 players online: Steve, Alex"


class FakeRcon:
    """Records commands instead of talking to a server."""

    def __init__(self):
        self.commands = []
        self.reply = ""
        self.list_output = LIST_OUTPUT
        self.fail_on = None  # command (or "*") that raises

    def __call__(self, command):
        self.commands.append(command)
        if self.fail_on in ("*", command):
            raise ConnectionRefusedError("server offline")
        if command == "list":
            return self.list_output
        return self.reply

    @property
    def sent(self):
        """Commands other than the page's own /list calls."""
        return [c for c in self.commands if c != "list"]


@pytest.fixture
def data_dir(tmp_path, monkeypatch):
    d = tmp_path / "data"
    (d / "world" / "region").mkdir(parents=True)
    (d / "world" / "level.dat").write_text("level")
    (d / "world" / "region" / "r.0.0.mca").write_text("region")
    (d / "server.properties").write_text("level-name=world\nwhite-list=true\n")
    (d / "whitelist.json").write_text(json.dumps([{"name": "Steve"}, {"name": "alex"}]))
    (d / "ops.json").write_text(json.dumps([{"name": "Steve"}]))
    (d / "banned-players.json").write_text(json.dumps([{"name": "Griefer"}]))
    monkeypatch.setattr(config, "DATA_DIR", d)
    return d


@pytest.fixture
def backup_dir(tmp_path, monkeypatch):
    d = tmp_path / "backups"
    d.mkdir()
    monkeypatch.setattr(config, "BACKUP_DIR", d)
    return d


@pytest.fixture
def rcon(monkeypatch):
    fake = FakeRcon()
    monkeypatch.setattr(rcon_client, "run", fake)
    return fake


@pytest.fixture(autouse=True)
def reset_state(monkeypatch):
    auth._failures.clear()
    monkeypatch.setattr(auth.time, "sleep", lambda s: None)
    yield
    wait_for_backup()
    backup._state.update(running=False, error=None)


@pytest.fixture
def client(data_dir, backup_dir, rcon):
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


@pytest.fixture
def logged_in(client):
    login(client, PASSWORD)
    return client


def csrf(client, path="/login"):
    return re.search(r'name="csrf" value="(\w+)"', client.get(path).text).group(1)


def login(client, password):
    return client.post("/login", data={"csrf": csrf(client), "password": password})


def post_action(client, **data):
    data["csrf"] = csrf(client, "/")
    return client.post("/action", data=data, follow_redirects=True)


def wait_for_backup(timeout=5):
    end = time.time() + timeout
    while backup.status()["running"]:
        if time.time() > end:
            raise TimeoutError("backup still running")
        time.sleep(0.01)
