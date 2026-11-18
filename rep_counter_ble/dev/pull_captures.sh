#!/usr/bin/env bash
# Copies the developer-mode captures from the iPhone (USB) to ./captures.
#
#   ./pull_captures.sh [destination]
#
# Needs libimobiledevice (afcclient) and the app installed with
# UIFileSharingEnabled, which xtool dev builds have.
set -euo pipefail

# xtool registers free-account apps as XTL-<team>.<bundle id>; a paid
# account keeps the plain one. Override with APP=... if neither matches.
BUNDLE=com.mauromm.repcounter
DEST="${1:-$(dirname "$0")/captures}"
mkdir -p "$DEST"

if ! idevice_id -l | grep -q .; then
  echo "No hay ningún iPhone conectado por USB (o no confía en esta computadora)." >&2
  exit 1
fi

if [ -z "${APP:-}" ]; then
  for candidate in $(xtool ds identifiers list 2>/dev/null | sed -n "s/^ *identifier: \(.*\.$BUNDLE\)$/\1/p") "$BUNDLE"; do
    if afcclient --documents "$candidate" ls /Documents >/dev/null 2>&1; then APP=$candidate; break; fi
  done
fi
if [ -z "${APP:-}" ]; then
  echo "No encontré la app en el iPhone. Pasa su identificador: APP=... $0" >&2
  exit 1
fi

# afcclient takes the command on the line; older builds only read it from stdin.
if ! afcclient --documents "$APP" get -rf /Documents/captures "$DEST" 2>/dev/null; then
  printf 'get -rf /Documents/captures %s\nquit\n' "$DEST" | afcclient --documents "$APP" >/dev/null
fi

# Some versions copy the folder itself into the destination.
if [ -d "$DEST/captures" ]; then
  mv -f "$DEST"/captures/*.json "$DEST"/ 2>/dev/null || true
  rmdir "$DEST/captures" 2>/dev/null || true
fi

echo "$(ls "$DEST"/*.json 2>/dev/null | wc -l) capturas en $DEST"
