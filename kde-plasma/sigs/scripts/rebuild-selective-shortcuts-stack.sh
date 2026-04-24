#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build"
ARCH="$(dpkg --print-architecture)"
LOCAL_SUFFIX="${LOCAL_SUFFIX:-selective1}"

usage() {
    cat <<EOF
Usage:
  scripts/rebuild-selective-shortcuts-stack.sh [--hold]

Options:
  --hold   Mark installed patched packages as held after installation.

Environment:
  LOCAL_SUFFIX=selective1   Local Debian version suffix.
EOF
}

hold_packages=false
for arg in "$@"; do
    case "$arg" in
        --hold)
            hold_packages=true
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

prepend_changelog() {
    local source_dir="$1"
    local package="$2"
    local message="$3"
    local old_version new_version distribution

    old_version="$(cd "$source_dir" && dpkg-parsechangelog -S Version)"
    distribution="$(cd "$source_dir" && dpkg-parsechangelog -S Distribution)"

    if [[ "$old_version" == *"+$LOCAL_SUFFIX" ]]; then
        new_version="$old_version"
    else
        new_version="${old_version}+$LOCAL_SUFFIX"
    fi

    {
        printf '%s (%s) %s; urgency=medium\n\n' "$package" "$new_version" "$distribution"
        printf '  * %s\n\n' "$message"
        printf ' -- %s <%s>  %s\n\n' "${DEBFULLNAME:-local builder}" "${DEBEMAIL:-local@example.invalid}" "$(date -R)"
        cat "$source_dir/debian/changelog"
    } >"$source_dir/debian/changelog.new"
    mv "$source_dir/debian/changelog.new" "$source_dir/debian/changelog"
}

download_source() {
    local package="$1"
    local dest="$2"

    mkdir -p "$dest"
    (
        cd "$dest"
        apt source "$package"
    )
}

single_source_dir() {
    local parent="$1"
    find "$parent" -maxdepth 1 -mindepth 1 -type d | sort | head -n 1
}

build_kglobalacceld() {
    local work="$BUILD_ROOT/kglobalacceld"
    local source_dir

    rm -rf "$work"
    download_source kglobalacceld "$work"
    source_dir="$(single_source_dir "$work")"

    (
        cd "$source_dir"
        patch -p1 < "$PROJECT_ROOT/patches/kglobalacceld-selective-api.patch"
    )
    prepend_changelog "$source_dir" kglobalacceld "Add config-backed selective global shortcut blocking DBus methods."

    sudo apt build-dep kglobalacceld -y
    (
        cd "$source_dir"
        dpkg-buildpackage -us -uc -b
    )

    sudo dpkg -i \
        "$work"/kglobalacceld_*+"$LOCAL_SUFFIX"_"$ARCH".deb \
        "$work"/libkglobalacceld0_*+"$LOCAL_SUFFIX"_"$ARCH".deb \
        "$work"/libkglobalacceld-dev_*+"$LOCAL_SUFFIX"_"$ARCH".deb
}

build_kwin() {
    local work="$BUILD_ROOT/kwin"
    local source_dir

    rm -rf "$work"
    download_source kwin "$work"
    source_dir="$(single_source_dir "$work")"

    (
        cd "$source_dir"
        patch -p1 < "$PROJECT_ROOT/patches/kwin-selective-window-rule.patch"
    )
    prepend_changelog "$source_dir" kwin "Add a separate selective global shortcuts window rule."

    sudo apt build-dep kwin -y
    (
        cd "$source_dir"
        dpkg-buildpackage -us -uc -b
    )

    sudo dpkg -i \
        "$work"/kwin-common_*+"$LOCAL_SUFFIX"_"$ARCH".deb \
        "$work"/kwin-data_*+"$LOCAL_SUFFIX"_all.deb \
        "$work"/kwin-wayland_*+"$LOCAL_SUFFIX"_"$ARCH".deb \
        "$work"/libkwin6_*+"$LOCAL_SUFFIX"_"$ARCH".deb
}

main() {
    mkdir -p "$BUILD_ROOT"

    build_kglobalacceld
    build_kwin

    "$PROJECT_ROOT/scripts/selective-global-shortcuts.sh" configure
    systemctl --user restart plasma-kglobalaccel.service || true

    if $hold_packages; then
        sudo apt-mark hold kglobalacceld libkglobalacceld0 kwin-common kwin-data kwin-wayland libkwin6
    fi

    cat <<EOF
Selective global shortcuts stack installed.

Log out and back in, or restart KWin, before using the KWin window rule UI.
Use this to edit the action allowlist:

  $PROJECT_ROOT/scripts/selective-global-shortcuts.sh gui
EOF
}

main
