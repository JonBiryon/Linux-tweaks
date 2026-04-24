#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  sigs apply
  sigs edit
  sigs pick
  sigs gui
  sigs on
  sigs off
  sigs list
  sigs rebuild [--hold]

Actions are read from:
  ~/.config/sigs/allowlist

Each line is a KDE global shortcut action identifier:
  component/action
EOF
}

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SIGS_CONFIG_DIR="$CONFIG_HOME/sigs"
ALLOWLIST="$SIGS_CONFIG_DIR/allowlist"

read_allowlist() {
    mkdir -p "$SIGS_CONFIG_DIR"
    touch "$ALLOWLIST"
    mapfile -t allowed_actions < <(
        sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*(#|$)/d; s/^[[:space:]]+//; s/[[:space:]]+$//' "$ALLOWLIST"
    )
}

apply_allowlist() {
    read_allowlist
    if ((${#allowed_actions[@]} == 0)); then
        dbus-send \
            --session \
            --dest=org.kde.kglobalaccel \
            --type=method_call \
            /kglobalaccel \
            org.kde.KGlobalAccel.setSelectiveGlobalShortcuts \
            array:string:
        return
    fi

    local joined
    printf -v joined '%s,' "${allowed_actions[@]}"
    joined="${joined%,}"

    dbus-send \
        --session \
        --dest=org.kde.kglobalaccel \
        --type=method_call \
        /kglobalaccel \
        org.kde.KGlobalAccel.setSelectiveGlobalShortcuts \
        "array:string:$joined"
}

pick_allowlist() {
    command -v kdialog >/dev/null || {
        echo "kdialog is not installed." >&2
        exit 1
    }

    read_allowlist
    local current
    current="$(printf '%s\n' "${allowed_actions[@]}")"

    local -a choices
    local section=""
    local key=""
    local label=""
    local id=""
    local checked=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "$line" == *=* ]] || continue
        [[ "$line" == _k_* ]] && continue
        key="${line%%=*}"
        label="${line##*,}"
        id="$section/$key"
        if grep -Fxq "$id" <<<"$current"; then
            checked=on
        else
            checked=off
        fi
        choices+=("$id" "$section / $label ($key)" "$checked")
    done <"$HOME/.config/kglobalshortcutsrc"

    local selected
    selected="$(kdialog --separate-output --checklist "Allowed KDE global shortcut actions" "${choices[@]}")" || return 1

    {
        cat <<'HEADER'
# Selective global shortcut action allowlist.
#
# Format:
#   component/action
#
# These are KDE global shortcut action identifiers, not physical key bindings.
HEADER
        printf '%s\n' "$selected"
    } >"$ALLOWLIST"

    apply_allowlist
}

case "${1:-}" in
    apply)
        apply_allowlist
        ;;
    edit)
        "${EDITOR:-nano}" "$ALLOWLIST"
        apply_allowlist
        ;;
    pick)
        pick_allowlist
        ;;
    gui)
        "$PROJECT_ROOT/ui/selective-global-shortcuts-gui.py"
        ;;
    on)
        qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.blockGlobalShortcutsSelective true
        ;;
    off)
        qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.blockGlobalShortcutsSelective false
        ;;
    list)
        qdbus6 org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.selectiveGlobalShortcuts
        ;;
    rebuild)
        shift
        "$PROJECT_ROOT/scripts/rebuild-selective-shortcuts-stack.sh" "$@"
        ;;
    *)
        usage
        exit 2
        ;;
esac
