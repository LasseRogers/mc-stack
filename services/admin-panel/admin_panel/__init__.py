"""Minecraft server admin panel."""
from flask import Flask

from . import auth, config, routes


def create_app():
    app = Flask(__name__)
    app.secret_key = config.SECRET_KEY
    app.config.update(SESSION_COOKIE_SAMESITE="Lax", SESSION_COOKIE_HTTPONLY=True)

    auth.register(app)
    routes.register(app)
    return app
