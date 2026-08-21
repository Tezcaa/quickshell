# Quickshell Desktop Setup

A monochrome Quickshell desktop shell: app launcher, package manager menu,
control center (clock, calendar, ARSO weather, MPRIS media controls, volume,
system tray, updates, power buttons), a lock screen, and notifications.

## Contents

```
quickshell/   Quickshell QML config (installed to ~/.config/quickshell)
scripts/      Helper scripts (installed to ~/Scripts)
wallpaper.png Wallpaper (installed to ~/Pictures/wallpaper.png)
install.sh    Installer
```

## Install

```sh
git clone <this-repo> quickshell-setup
cd quickshell-setup
./install.sh
```

The installer:
- installs dependencies via `pacman` (+ `yay`/`paru` for AUR)
- copies the QML config, scripts, and wallpaper into place
- prints the compositor keybinds you need to add

All paths in the config are resolved from `$HOME` at runtime, so it works
under any username.

## Features / keybinds (add to your compositor)

| Action           | Suggested bind   | Command                                    |
|------------------|------------------|--------------------------------------------|
| App launcher     | `Mod+Space`      | `qs ipc call launcher toggle`              |
| Package menu     | `Mod+Alt+Space`  | `qs ipc call packages toggle`              |
| Control center   | `Mod+X`          | `qs ipc call controlcenter toggle`         |
| Lock screen      | `Super+Alt+L`    | `qs -p ~/.config/quickshell/Lock.qml`      |

Start the shell with `qs` (add `spawn-at-startup "qs"` to your compositor).

## Requirements

- Arch-based system (scripts use `pacman`/`yay`/`flatpak`/`checkupdates`)
- A Wayland compositor supporting `wlr-layer-shell` + `ext-session-lock`
  (tested on niri)
- CaskaydiaMono Nerd Font (installed by the installer)

## Updating this repo from your live config

After tweaking your live config, sync it back and push:

```sh
~/quickshell/update-repo.sh "optional commit message"
```

It copies `~/.config/quickshell/*.qml`, the project scripts from `~/Scripts`,
and `~/Pictures/wallpaper.png` into the repo, commits, and pushes.

## Notes

- Notifications replace mako. To hand over the notification bus:
  `systemctl --user mask mako.service`
- The weather widget uses ARSO (Slovenia). Change the location in
  `ControlCenter.qml` (`wxLocation`) for other regions.
