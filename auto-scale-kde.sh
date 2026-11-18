#!/usr/bin/env bash
# auto-scale-kde.sh — watch the VM's virtual display for resolution changes
# (i.e. the VM viewer window being resized, via SPICE / virtio-gpu dynamic
# resize) and ask whether KDE Plasma (Wayland) should be at 100% or 200% scale.
#
# Usage:
#   auto-scale-kde.sh            # watch; prompt whenever the screen size changes
#   auto-scale-kde.sh --now      # prompt once for the current size, then exit
#
# Tunables (environment variables):
#   MIN_WIDTH_2X   physical width  at/above which 200% is the suggestion (default 2560)
#   MIN_HEIGHT_2X  physical height at/above which 200% is the suggestion (default 1080)
#   POLL_INTERVAL  seconds between checks                                 (default 2)

set -euo pipefail

MIN_WIDTH_2X="${MIN_WIDTH_2X:-2560}"
MIN_HEIGHT_2X="${MIN_HEIGHT_2X:-1080}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

once=0
for arg in "$@"; do
    case "$arg" in
        --now)     once=1 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

for cmd in kscreen-doctor jq kdialog; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

log() { echo "[$(date +%H:%M:%S)] $*"; }

# One line per enabled output: "<name> <physical-width> <physical-height> <scale>".
# Physical size comes from the current mode (output .size is logical and shrinks with scale).
read_outputs() {
    kscreen-doctor -j | jq -r '
        .outputs[]
        | select(.enabled and .connected)
        | . as $o
        | ($o.modes[] | select(.id == $o.currentModeId)) as $m
        | "\($o.name) \($m.size.width) \($m.size.height) \($o.scale)"'
}

# Physical sizes only — changing the scale must not count as a "size change".
size_signature() { read_outputs 2>/dev/null | awk '{print $1, $2, $3}' || true; }

# Ask the user and apply their choice to every enabled output.
prompt_and_apply() {
    local name w h scale suggest current_pct summary="" args=() choice rc

    while read -r name w h scale; do
        [[ -z "$name" ]] && continue
        current_pct=$(awk -v s="$scale" 'BEGIN{printf "%d", s*100}')
        summary+="$name: ${w}×${h} (currently ${current_pct}%)<br>"
        (( w >= MIN_WIDTH_2X && h >= MIN_HEIGHT_2X )) && suggest=200 || suggest=${suggest:-100}
    done < <(read_outputs)
    [[ -z "$summary" ]] && return 0

    rc=0
    kdialog --title "Display size changed" \
        --yes-label "200%" --no-label "100%" --cancel-label "Leave as is" \
        --yesnocancel "<b>The screen size changed.</b><br><br>${summary}<br>Suggested: <b>${suggest}%</b><br><br>Which scale do you want?" \
        || rc=$?

    case $rc in
        0) choice=2 ;;
        1) choice=1 ;;
        *) log "Left unchanged"; return 0 ;;
    esac

    while read -r name w h scale; do
        [[ -n "$name" ]] && args+=("output.${name}.scale.${choice}")
    done < <(read_outputs)

    log "Setting ${choice}00%: ${args[*]}"
    kscreen-doctor "${args[@]}" >/dev/null || log "kscreen-doctor failed"
}

if (( once )); then
    prompt_and_apply
    exit 0
fi

log "Watching for screen size changes (poll ${POLL_INTERVAL}s)"
handled_sig=$(size_signature)   # don't prompt for the size we start at
last_sig="$handled_sig"
while true; do
    sleep "$POLL_INTERVAL"
    sig=$(size_signature)
    # Only act once the size has stayed the same for one poll, so we don't
    # prompt repeatedly while the window is being dragged.
    if [[ -n "$sig" && "$sig" == "$last_sig" && "$sig" != "$handled_sig" ]]; then
        log "Size changed: $(tr '\n' ' ' <<<"$sig")"
        handled_sig="$sig"
        prompt_and_apply
    fi
    last_sig="$sig"
done
