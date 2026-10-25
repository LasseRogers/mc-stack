import pytest

from app import rcon_client, server_files


@pytest.mark.parametrize("output, expected", [
    ("There are 2 of a max of 20 players online: Steve, Alex", (2, 20, ["Steve", "Alex"])),
    ("There are 0 of a max of 20 players online: ", (0, 20, [])),
    ("There are 1/10 players online:\nSteve", (1, 10, ["Steve"])),
    ("unexpected output", (0, 0, [])),
])
def test_list_players(rcon, output, expected):
    rcon.list_output = output
    assert rcon_client.list_players() == expected


def test_whitelist_sorted_case_insensitive(data_dir):
    assert server_files.whitelist() == ["alex", "Steve"]


def test_ops_lowercased(data_dir):
    assert server_files.ops() == {"steve"}


def test_banned(data_dir):
    assert server_files.banned() == ["Griefer"]


def test_missing_files(data_dir):
    for name in ("whitelist.json", "ops.json", "banned-players.json"):
        (data_dir / name).unlink()
    assert server_files.whitelist() == []
    assert server_files.ops() == set()
    assert server_files.banned() == []


def test_corrupt_json(data_dir):
    (data_dir / "whitelist.json").write_text("{not json")
    assert server_files.whitelist() == []


@pytest.mark.parametrize("properties, expected", [
    ("white-list=true\n", True),
    ("white-list=false\n", False),
    ("motd=hi\n", None),
])
def test_whitelist_enabled(data_dir, properties, expected):
    (data_dir / "server.properties").write_text(properties)
    assert server_files.whitelist_enabled() is expected


def test_whitelist_enabled_without_file(data_dir):
    (data_dir / "server.properties").unlink()
    assert server_files.whitelist_enabled() is None
