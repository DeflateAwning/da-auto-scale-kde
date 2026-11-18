#!/usr/bin/env bash
# Installs auto-scale-kde.sh to ~/.local/bin and enables it as a systemd user service.
set -euo pipefail
cd "$(dirname "$0")"

install -Dm755 auto-scale-kde.sh "$HOME/.local/bin/auto-scale-kde.sh"
install -Dm644 auto-scale-kde.service "$HOME/.config/systemd/user/auto-scale-kde.service"

systemctl --user daemon-reload
systemctl --user enable --now auto-scale-kde.service
systemctl --user --no-pager status auto-scale-kde.service | head -n 5
