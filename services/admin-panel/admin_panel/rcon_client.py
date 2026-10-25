"""Talking to the Minecraft server over RCON."""
import re

from rcon.source import Client

from . import config


def run(command):
    """Send one command and return the server's reply."""
    with Client(config.RCON_HOST, config.RCON_PORT,
                passwd=config.RCON_PASSWORD, timeout=5) as client:
        return client.run(command)


def list_players():
    """Return (online_count, max_players, names) from the /list command."""
    output = run("list")
    m = re.search(r"There are (\d+)(?: of a max of |/)(\d+) players online:?\s*(.*)",
                  output, re.S)
    if not m:
        return 0, 0, []
    names = [n.strip() for n in m.group(3).split(",") if n.strip()]
    return int(m.group(1)), int(m.group(2)), names
