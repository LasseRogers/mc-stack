"""Settings, read once from environment variables."""
import os
from pathlib import Path

RCON_HOST = os.environ.get("RCON_HOST", "mc")
RCON_PORT = int(os.environ.get("RCON_PORT", "25575"))
RCON_PASSWORD = os.environ["RCON_PASSWORD"]

ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]
SECRET_KEY = os.environ["SECRET_KEY"]

# Server data volume (read-only).
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))

# Shared with the backups service (writable).
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", "/backups"))

# Per-IP login lockout.
MAX_LOGIN_FAILURES = 5
LOCKOUT_SECONDS = 15 * 60
