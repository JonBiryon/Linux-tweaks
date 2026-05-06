# sigs

Selective Ignore Global Shortcuts for KDE Plasma.

SIGS adds a separate `Ignore selective global shortcuts` window rule. It's similar to KDE's stock `Ignore global shortcuts` which forces a window to consume global shortcuts instead of the OS, except sigs exludes shortcut actions selected by the user.

SIGS also adds a separate KWin window rule:

```text
Keep above while active
```

That rule keeps a window above normal windows only while it is focused.

Selective mode uses KDE action identifiers, not physical key combinations.

## Scope

- KDE Plasma systems using KWin and KGlobalAccel
- current build and install flow: Ubuntu-based systems, especially Kubuntu

## Install

```bash
./build-install-selective-window-rule.sh
```

After install, log out and back in, or restart KWin.

## Usage

```bash
./selective-global-shortcuts.sh gui
./selective-global-shortcuts.sh edit
./selective-global-shortcuts.sh pick
./selective-global-shortcuts.sh configure
./selective-global-shortcuts.sh on
./selective-global-shortcuts.sh off
./selective-global-shortcuts.sh list
```

## Action Selection Menu

To choose allowed actions from a menu instead of editing the allowlist by hand,
run:

```bash
./selective-global-shortcuts.sh pick
```

This opens a `kdialog` checklist built from:

```text
~/.config/kglobalshortcutsrc
```

Each entry is a KDE action identifier in this form:

```text
component/action
```

The selection is written to:

```text
./selective-global-shortcuts.allowlist
```

and applied immediately.

## GUI

For the graphical SIGS editor, run:

```bash
./selective-global-shortcuts.sh gui
```

## Keep Above While Active

The patched KWin packages add this Window Rules option:

```text
Keep above while active
```

Use it when a window should stay above normal windows only while focused, and
drop back when it loses focus.

## Notes

Current allowlist file:

```text
./selective-global-shortcuts.allowlist
```

KDE updates may overwrite patched packages. If that happens, rebuild and
reinstall from this project.
