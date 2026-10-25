import pytest

from conftest import post_action


@pytest.mark.parametrize("action, command", [
    ("kick", "kick Steve"),
    ("ban", "ban Steve"),
    ("pardon", "pardon Steve"),
    ("op", "op Steve"),
    ("deop", "deop Steve"),
    ("whitelist_add", "whitelist add Steve"),
    ("whitelist_remove", "whitelist remove Steve"),
])
def test_player_actions(logged_in, rcon, action, command):
    post_action(logged_in, action=action, player="Steve")
    assert rcon.sent == [command]


@pytest.mark.parametrize("player", [
    "x; stop", "Steve stop", "ab", "a" * 17, "Steve\nstop", "", "Ste-ve",
])
def test_invalid_usernames_rejected(logged_in, rcon, player):
    r = post_action(logged_in, action="kick", player=player)
    assert "isn&#39;t a valid Minecraft username" in r.text
    assert rcon.sent == []


@pytest.mark.parametrize("action, command", [
    ("whitelist_on", "whitelist on"),
    ("whitelist_off", "whitelist off"),
    ("day", "time set day"),
    ("clear_weather", "weather clear"),
])
def test_server_actions(logged_in, rcon, action, command):
    post_action(logged_in, action=action)
    assert rcon.sent == [command]


def test_broadcast_cleans_message(logged_in, rcon):
    post_action(logged_in, action="say", message="  hello \n  world  ")
    assert rcon.sent == ["say hello world"]


def test_broadcast_truncated(logged_in, rcon):
    post_action(logged_in, action="say", message="x" * 300)
    assert rcon.sent == ["say " + "x" * 256]


def test_broadcast_empty(logged_in, rcon):
    r = post_action(logged_in, action="say", message="   ")
    assert "Write a message first." in r.text
    assert rcon.sent == []


@pytest.mark.parametrize("action", ["save", "stop", "op", ""])
def test_unknown_or_incomplete_actions(logged_in, rcon, action):
    r = post_action(logged_in, action=action)
    assert r.status_code in (200, 400)
    assert rcon.sent == []


def test_server_reply_shown(logged_in, rcon):
    rcon.reply = "Kicked Steve: Kicked by an operator"
    r = post_action(logged_in, action="kick", player="Steve")
    assert "Kicked Steve: Kicked by an operator" in r.text


def test_empty_reply_shows_command(logged_in, rcon):
    r = post_action(logged_in, action="day")
    assert "Done: time set day" in r.text


def test_server_unreachable(logged_in, rcon):
    rcon.fail_on = "kick Steve"
    r = post_action(logged_in, action="kick", player="Steve")
    assert "Couldn&#39;t reach the server" in r.text


def test_page_shows_offline(logged_in, rcon):
    rcon.fail_on = "*"
    assert "Offline" in logged_in.get("/").text
