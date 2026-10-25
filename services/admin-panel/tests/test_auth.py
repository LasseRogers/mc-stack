import time

from app import auth, config
from conftest import PASSWORD, csrf, login


def test_requires_login(client):
    r = client.get("/")
    assert r.status_code == 302
    assert r.headers["Location"].endswith("/login")


def test_wrong_password(client):
    r = login(client, "wrong")
    assert "Wrong password." in r.text
    assert client.get("/").status_code == 302


def test_correct_password(client):
    r = login(client, PASSWORD)
    assert r.status_code == 302
    assert client.get("/").status_code == 200


def test_lockout_after_max_failures(client):
    for _ in range(config.MAX_LOGIN_FAILURES):
        assert login(client, "wrong").status_code == 200
    r = login(client, PASSWORD)
    assert r.status_code == 429
    assert "Too many wrong passwords" in r.text
    assert client.get("/").status_code == 302


def test_lockout_expires(client):
    for _ in range(config.MAX_LOGIN_FAILURES):
        login(client, "wrong")
    expired = time.time() - config.LOCKOUT_SECONDS - 1
    for ip in auth._failures:
        auth._failures[ip] = [expired] * len(auth._failures[ip])
    assert login(client, PASSWORD).status_code == 302


def test_success_resets_failures(client):
    for _ in range(config.MAX_LOGIN_FAILURES - 1):
        login(client, "wrong")
    login(client, PASSWORD)
    assert auth._failures == {}


def test_post_without_csrf_rejected(logged_in):
    assert logged_in.post("/action", data={"action": "day"}).status_code == 400


def test_post_with_wrong_csrf_rejected(logged_in):
    r = logged_in.post("/action", data={"action": "day", "csrf": "nope"})
    assert r.status_code == 400


def test_logout(logged_in):
    logged_in.post("/logout", data={"csrf": csrf(logged_in, "/")})
    assert logged_in.get("/").status_code == 302
