#!/bin/zsh
# Installs (or updates) DNS Doctor from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Fahimefto/dns-doctor/master/install.sh | zsh
#
set -euo pipefail

REPO="Fahimefto/dns-doctor"
APP_NAME="DNS Doctor.app"
DEST="/Applications/$APP_NAME"
URL="https://github.com/$REPO/releases/latest/download/DNS-Doctor.dmg"

say() { print -P "%F{blue}==>%f $1"; }
fail() { print -P "%F{red}Error:%f $1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "DNS Doctor only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 13 )) || fail "DNS Doctor needs macOS 13 (Ventura) or newer."

TMP="$(mktemp -d)"
MNT="$TMP/mnt"
cleanup() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

say "Downloading the latest DNS Doctor…"
curl -fL --progress-bar -o "$TMP/DNS-Doctor.dmg" "$URL" || fail "Download failed. Check your internet connection (or DNS!)."

say "Opening the disk image…"
mkdir -p "$MNT"
hdiutil attach "$TMP/DNS-Doctor.dmg" -nobrowse -readonly -mountpoint "$MNT" -quiet
[[ -d "$MNT/$APP_NAME" ]] || fail "The download didn't contain $APP_NAME."

if pgrep -x DNSDoctor >/dev/null; then
  say "Closing the running copy…"
  pkill -x DNSDoctor || true
  sleep 1
fi

say "Installing to /Applications…"
if [[ -w /Applications ]]; then
  rm -rf "$DEST"
  ditto "$MNT/$APP_NAME" "$DEST"
else
  print "Your Mac password is needed to write to /Applications."
  sudo rm -rf "$DEST"
  sudo ditto "$MNT/$APP_NAME" "$DEST"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

say "Starting DNS Doctor…"
open "$DEST"

print -P "%F{green}Done.%f Look for the globe icon in your menu bar."
