"""The panel page and the actions its buttons trigger."""
import re

from flask import abort, flash, redirect, render_template, request, url_for

from . import backup, rcon_client, server_files
from .auth import login_required

# Also guards against RCON command injection.
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")

PLAYER_ACTIONS = {
    "kick": "kick {p}",
    "ban": "ban {p}",
    "pardon": "pardon {p}",
    "op": "op {p}",
    "deop": "deop {p}",
    "whitelist_add": "whitelist add {p}",
    "whitelist_remove": "whitelist remove {p}",
}

SERVER_ACTIONS = {
    "whitelist_on": "whitelist on",
    "whitelist_off": "whitelist off",
    "day": "time set day",
    "clear_weather": "weather clear",
}


def clean_message(text):
    return " ".join(text.split())[:256]


def register(app):
    @app.route("/")
    @login_required
    def index():
        try:
            count, max_players, online = rcon_client.list_players()
            server_up = True
        except Exception:
            count, max_players, online, server_up = 0, 0, [], False

        return render_template(
            "panel.html",
            server_up=server_up,
            count=count,
            max_players=max_players,
            online=online,
            ops=server_files.ops(),
            whitelist=server_files.whitelist(),
            whitelist_on=server_files.whitelist_enabled(),
            banned=server_files.banned(),
            backup_status=backup.status(),
            latest_backup=backup.latest(),
        )

    @app.route("/action", methods=["POST"])
    @login_required
    def action():
        name = request.form.get("action", "")
        player = request.form.get("player", "").strip()

        if name in PLAYER_ACTIONS:
            if not USERNAME_RE.match(player):
                flash("That isn't a valid Minecraft username.", "error")
                return redirect(url_for("index"))
            command = PLAYER_ACTIONS[name].format(p=player)
        elif name in SERVER_ACTIONS:
            command = SERVER_ACTIONS[name]
        elif name == "backup":
            if backup.start():
                flash("Backup started.", "ok")
            else:
                flash("A backup is already running.", "error")
            return redirect(url_for("index"))
        elif name == "say":
            message = clean_message(request.form.get("message", ""))
            if not message:
                flash("Write a message first.", "error")
                return redirect(url_for("index"))
            command = f"say {message}"
        else:
            abort(400)

        try:
            reply = rcon_client.run(command)
            flash(reply.strip() or f"Done: {command}", "ok")
        except Exception as e:
            flash(f"Couldn't reach the server: {e}", "error")
        return redirect(url_for("index"))
