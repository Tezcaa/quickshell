#!/bin/bash

# Sync the live Quickshell config + scripts into this repo and push.
# Run from anywhere; it operates on the repo this script lives in.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS_DIR="$HOME/.config/quickshell"
SCRIPTS_DIR="$HOME/Scripts"
WALLPAPER="$HOME/Pictures/wallpaper.png"

info() { echo -e "\e[32m==>\e[0m $*"; }

info "Copying Quickshell QML files..."
cp -v "$QS_DIR"/*.qml "$REPO_DIR/quickshell/"

info "Copying scripts..."
# Only the scripts this project ships (avoid pulling unrelated ~/Scripts files).
for s in installpkg removepkg launch-webapp webapp-install webapp-remove \
         update-all update-count reboot-needed samplerate; do
  [[ -f "$SCRIPTS_DIR/$s" ]] && cp -v "$SCRIPTS_DIR/$s" "$REPO_DIR/scripts/"
done
chmod +x "$REPO_DIR/scripts/"*

if [[ -f "$WALLPAPER" ]]; then
  info "Copying wallpaper..."
  cp -v "$WALLPAPER" "$REPO_DIR/wallpaper.png"
fi

cd "$REPO_DIR"

if git diff --quiet && git diff --cached --quiet; then
  info "No changes to sync."
  exit 0
fi

git add -A
msg="${1:-Sync live config $(date +%Y-%m-%d\ %H:%M)}"
git commit -m "$msg"

info "Pushing to origin..."
if git push 2>/dev/null; then
  info "Done."
else
  echo -e "\e[33m==>\e[0m Push failed (auth needed). Run manually, e.g.:"
  echo "    cd $REPO_DIR"
  echo "    git push https://<TOKEN>@github.com/Tezcaa/quickshell.git main"
fi
