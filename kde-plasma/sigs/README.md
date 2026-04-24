# sigs

Selective Ignore Global Shortcuts for KDE Plasma.

SIGS adds a separate `Ignore selective global shortcuts` window rule without changing KDE's stock `Ignore global shortcuts` behavior.

Selective mode uses KDE action identifiers, not physical key combinations.

## Release

https://github.com/JonBiryon/Linux-tweaks/releases/download/sigs/sigs.tar.gz

## Scope

- KDE Plasma systems using KWin and KGlobalAccel
- Current build and install flow: Ubuntu-based systems, especially Kubuntu

## Install

```bash
./install.sh
```

Install and rebuild in one step:

```bash
./install.sh --rebuild
```

## Usage

```bash
sigs gui
sigs edit
sigs apply
sigs list
sigs rebuild
```

## Notes

Canonical allowlist:

```text
~/.config/sigs/allowlist
```

KDE updates may overwrite patched packages. If that happens, run:

```bash
sigs rebuild
```
