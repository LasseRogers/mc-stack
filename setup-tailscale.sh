#!/usr/bin/env bash
# Optional: join this host to a Tailscale tailnet for remote access.
# Usage: bash setup-tailscale.sh   (idempotent, run as a regular user)
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root."
  exit 1
fi

step() { echo; echo "==> $*"; }

step "[1/2] Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  echo "already installed"
else
  curl -fsSL https://tailscale.com/install.sh | sh
fi

step "[2/2] Login"
if tailscale status >/dev/null 2>&1; then
  echo "already logged in"
else
  echo "Open the login URL below in any browser."
  sudo tailscale up
fi

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow in on tailscale0 comment tailscale
  echo "ufw: allowed incoming on tailscale0"
fi

name="$(hostname)"
ip="$(tailscale ip -4 2>/dev/null | head -n 1)"

cat <<EOF

Tailscale address: ${name} (${ip})

  Minecraft: ${name}
  Panel:     http://${name}:8080

Install Tailscale on your own devices and log in with the same account.

To let friends play without panel access:

  1. Admin console > Machines > ${name} > Share, send them the link.
  2. Admin console > Access controls, replace the "grants" (or "acls")
     section with:

    "grants": [
      // Own devices: everything
      {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},
      // Shared users: Minecraft only
      {"src": ["autogroup:shared"], "dst": ["*"], "ip": ["tcp:25565"]},
    ],

  3. Friends connect to ${ip}.
EOF
