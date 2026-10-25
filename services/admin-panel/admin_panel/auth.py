"""Login, logout, login lockout and CSRF protection."""
import hmac
import secrets
import threading
import time
from functools import wraps

from flask import (abort, flash, redirect, render_template, request, session,
                   url_for)

from . import config

_failures = {}  # ip -> list of failure timestamps
_failures_lock = threading.Lock()


def _recent_failures(ip, now):
    times = [t for t in _failures.get(ip, []) if now - t < config.LOCKOUT_SECONDS]
    if times:
        _failures[ip] = times
    else:
        _failures.pop(ip, None)
    return times


def is_locked_out(ip):
    with _failures_lock:
        return len(_recent_failures(ip, time.time())) >= config.MAX_LOGIN_FAILURES


def record_failure(ip):
    with _failures_lock:
        now = time.time()
        _recent_failures(ip, now)
        _failures.setdefault(ip, []).append(now)


def clear_failures(ip):
    with _failures_lock:
        _failures.pop(ip, None)


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapper


def register(app):
    @app.before_request
    def csrf_protect():
        if request.method == "POST":
            token = session.get("csrf")
            if not token or not hmac.compare_digest(token, request.form.get("csrf", "")):
                abort(400)

    @app.context_processor
    def inject_csrf():
        if "csrf" not in session:
            session["csrf"] = secrets.token_hex(16)
        return {"csrf": session["csrf"]}

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            ip = request.remote_addr or "unknown"
            if is_locked_out(ip):
                flash("Too many wrong passwords. Try again in 15 minutes.", "error")
                return render_template("login.html"), 429
            if hmac.compare_digest(request.form.get("password", ""), config.ADMIN_PASSWORD):
                clear_failures(ip)
                session.clear()
                session["logged_in"] = True
                session["csrf"] = secrets.token_hex(16)
                return redirect(url_for("index"))
            record_failure(ip)
            time.sleep(1)  # slow down password guessing
            flash("Wrong password.", "error")
        return render_template("login.html")

    @app.route("/logout", methods=["POST"])
    def logout():
        session.clear()
        return redirect(url_for("login"))
