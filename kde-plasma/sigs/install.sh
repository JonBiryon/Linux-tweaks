#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./install.sh [--rebuild] [--hold]

Options:
  --rebuild   After installing the SIGS files, run "sigs rebuild".
  --hold      Pass --hold to "sigs rebuild". Implies --rebuild.
EOF
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
INSTALL_ROOT="$DATA_HOME/sigs"
CONFIG_ROOT="$CONFIG_HOME/sigs"
BIN_DIR="$HOME/.local/bin"
DBUS_SERVICES_DIR="$DATA_HOME/dbus-1/services"
DBUS_SERVICE_NAME="org.kde.kglobalaccel.service"

rebuild=false
hold=false

for arg in "$@"; do
    case "$arg" in
        --rebuild)
            rebuild=true
            ;;
        --hold)
            rebuild=true
            hold=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

seed_allowlist() {
    local allowlist="$1"

    if [[ -e "$allowlist" ]]; then
        return
    fi

    mkdir -p "$(dirname "$allowlist")"
    cat >"$allowlist" <<'EOF'
# Selective global shortcut action allowlist.
#
# Format:
#   component/action
#
# These are KDE global shortcut action identifiers, not physical key bindings.
kmix/decrease_volume
kmix/decrease_volume_small
kmix/increase_volume
kmix/increase_volume_small
kmix/mute
ksmserver/Log Out
kwin/Walk Through Windows
kwin/Walk Through Windows (Reverse)
kwin/Walk Through Windows Alternative
kwin/Walk Through Windows Alternative (Reverse)
kwin/Walk Through Windows of Current Application
kwin/Walk Through Windows of Current Application (Reverse)
kwin/Walk Through Windows of Current Application Alternative
kwin/Walk Through Windows of Current Application Alternative (Reverse)
EOF
}

install_tree() {
    mkdir -p "$INSTALL_ROOT" "$CONFIG_ROOT" "$BIN_DIR" "$DBUS_SERVICES_DIR"

    if [[ "$PROJECT_ROOT" != "$INSTALL_ROOT" ]]; then
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --delete \
                --exclude 'build/' \
                --exclude '__pycache__/' \
                --exclude '*.pyc' \
                "$PROJECT_ROOT/" "$INSTALL_ROOT/"
        else
            rm -rf "$INSTALL_ROOT"
            mkdir -p "$INSTALL_ROOT"
            cp -a "$PROJECT_ROOT/." "$INSTALL_ROOT/"
            find "$INSTALL_ROOT" -type d -name __pycache__ -prune -exec rm -rf {} +
            find "$INSTALL_ROOT" -type f -name '*.pyc' -delete
        fi
    fi

    ln -sfn "$INSTALL_ROOT/scripts/selective-global-shortcuts.sh" "$BIN_DIR/sigs"
    cp -f "$INSTALL_ROOT/dbus-1/services/$DBUS_SERVICE_NAME" "$DBUS_SERVICES_DIR/$DBUS_SERVICE_NAME"
    chmod +x "$INSTALL_ROOT/scripts/selective-global-shortcuts.sh" \
        "$INSTALL_ROOT/scripts/rebuild-selective-shortcuts-stack.sh" \
        "$INSTALL_ROOT/ui/selective-global-shortcuts-gui.py"

    seed_allowlist "$CONFIG_ROOT/allowlist"
}

main() {
    install_tree

    if $rebuild; then
        if $hold; then
            "$BIN_DIR/sigs" rebuild --hold
        else
            "$BIN_DIR/sigs" rebuild
        fi
        exit 0
    fi

    cat <<EOF
SIGS files installed.

Installed code:
  $INSTALL_ROOT

Canonical allowlist:
  $CONFIG_ROOT/allowlist

Command:
  $BIN_DIR/sigs

Next step:
  $BIN_DIR/sigs rebuild
EOF
}

main
