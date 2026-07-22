#!/bin/bash

# Installer for the Quickshell desktop setup.
# Copies QML configs + scripts + wallpaper and installs dependencies.

set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QS_DIR="$HOME/.config/quickshell"
SCRIPTS_DIR="$HOME/Scripts"
PICTURES_DIR="$HOME/Pictures"

info()  { echo -e "\e[32m==>\e[0m $*"; }
warn()  { echo -e "\e[33m==>\e[0m $*"; }

# --- Dependencies ---------------------------------------------------------
# Official repo packages.
PACMAN_PKGS=(
  quickshell            # the shell itself
  qt6-declarative       # QML runtime
  qt6-multimedia
  curl                  # weather fetch
  fzf                   # installpkg / removepkg pickers
  pacman-contrib        # checkupdates (update count)
  flatpak               # flatpak updates / apps
  ghostty               # terminal used by the menus
  ttf-cascadia-code-nerd # CaskaydiaMono Nerd Font (icons/glyphs)
)

# AUR packages (need an AUR helper). Optional.
AUR_PKGS=(
  bibata-cursor-theme      # cursor theme (optional, referenced by configs)
)

install_deps() {
  if ! command -v pacman >/dev/null 2>&1; then
    warn "Not an Arch-based system; skipping dependency install."
    warn "Install manually: ${PACMAN_PKGS[*]} ${AUR_PKGS[*]}"
    return
  fi

  info "Installing repo packages..."
  sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}" || \
    warn "Some repo packages failed; continue and fix manually if needed."

  local helper=""
  for h in yay paru; do
    command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }
  done

  if [[ -n $helper ]]; then
    info "Installing AUR packages with $helper..."
    "$helper" -S --needed --noconfirm "${AUR_PKGS[@]}" || \
      warn "Some AUR packages failed; install them manually: ${AUR_PKGS[*]}"
  else
    warn "No AUR helper (yay/paru) found. Install these manually: ${AUR_PKGS[*]}"
  fi
}

# --- File copy ------------------------------------------------------------
install_files() {
  info "Installing Quickshell config to $QS_DIR"
  mkdir -p "$QS_DIR"
  cp -v "$SRC_DIR"/quickshell/*.qml "$QS_DIR/"

  info "Installing scripts to $SCRIPTS_DIR"
  mkdir -p "$SCRIPTS_DIR"
  cp -v "$SRC_DIR"/scripts/* "$SCRIPTS_DIR/"
  chmod +x "$SCRIPTS_DIR"/*

  if [[ -f "$SRC_DIR/wallpaper.png" ]]; then
    info "Installing wallpaper to $PICTURES_DIR/wallpaper.png"
    mkdir -p "$PICTURES_DIR"
    cp -v "$SRC_DIR/wallpaper.png" "$PICTURES_DIR/wallpaper.png"
  fi
}

# --- Post-install notes ---------------------------------------------------
print_notes() {
  cat <<'EOF'

============================================================
  Quickshell setup installed.

  Start the shell:            qs
  Reload after changes:       (auto-reloads on save)

  This package is Quickshell-only. Add these to your
  compositor (niri example ~/.config/niri/config.kdl):

    spawn-at-startup "qs"
    spawn-sh-at-startup "swaybg -i ~/Pictures/wallpaper.png -m fill"

    binds {
      Mod+Space      { spawn "qs" "ipc" "call" "launcher" "toggle"; }
      Mod+Alt+Space  { spawn "qs" "ipc" "call" "packages" "toggle"; }
      Mod+X          { spawn "qs" "ipc" "call" "controlcenter" "toggle"; }
      Super+Alt+L    { spawn "qs" "-p" "~/.config/quickshell/Lock.qml"; }
    }

  Notes:
   - Notifications replace mako: run
       systemctl --user mask mako.service
   - Install a Nerd Font (CaskaydiaMono) for icons/glyphs.
   - The package scripts assume Arch (pacman/yay) + flatpak.
============================================================
EOF
}

install_deps
install_files
print_notes
