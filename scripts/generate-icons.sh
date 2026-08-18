#!/usr/bin/env bash
#
# generate-icons.sh — regenerate all production icon assets from the single
# source image (assets/app_icon.png).
#
# Outputs (all git-tracked, so this only needs to be re-run when the source
# icon changes):
#   assets/icons/app/AppIcon.iconset/*         organized source iconset
#   assets/icons/menubar/*                     organized source menu-bar pngs
#   Sources/App/Resources/AppIcon.icns         app bundle icon (CFBundleIconFile)
#   Sources/App/Resources/MenuBarIcon.png      status-bar image (1x, 18pt)
#   Sources/App/Resources/MenuBarIcon@2x.png   status-bar image (2x, 36pt)
#
# NOTE: the source is only 128x128, so the large app-icon slots (256/512/1024)
# are upscaled and will look soft. Replace assets/app_icon.png with a 1024x1024
# master and re-run for crisp production icons.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/app_icon.png"

APP_ICONSET="$ROOT/assets/icons/app/AppIcon.iconset"
MENUBAR_SRC="$ROOT/assets/icons/menubar"
RES="$ROOT/Sources/App/Resources"

[ -f "$SRC" ] || { echo "error: source icon not found at $SRC" >&2; exit 1; }

mkdir -p "$APP_ICONSET" "$MENUBAR_SRC" "$RES"

echo "==> Generating app iconset from $SRC"
gen() { sips -z "$1" "$1" "$SRC" --out "$2" >/dev/null; }
gen 16   "$APP_ICONSET/icon_16x16.png"
gen 32   "$APP_ICONSET/icon_16x16@2x.png"
gen 32   "$APP_ICONSET/icon_32x32.png"
gen 64   "$APP_ICONSET/icon_32x32@2x.png"
gen 128  "$APP_ICONSET/icon_128x128.png"
gen 256  "$APP_ICONSET/icon_128x128@2x.png"
gen 256  "$APP_ICONSET/icon_256x256.png"
gen 512  "$APP_ICONSET/icon_256x256@2x.png"
gen 512  "$APP_ICONSET/icon_512x512.png"
gen 1024 "$APP_ICONSET/icon_512x512@2x.png"

echo "==> Building AppIcon.icns"
iconutil -c icns "$APP_ICONSET" -o "$RES/AppIcon.icns"

echo "==> Generating menu-bar images (18pt / 36pt)"
sips -z 18 18 "$SRC" --out "$MENUBAR_SRC/MenuBarIcon.png"    >/dev/null
sips -z 36 36 "$SRC" --out "$MENUBAR_SRC/MenuBarIcon@2x.png" >/dev/null
cp "$MENUBAR_SRC/MenuBarIcon.png"    "$RES/MenuBarIcon.png"
cp "$MENUBAR_SRC/MenuBarIcon@2x.png" "$RES/MenuBarIcon@2x.png"

echo "==> Done. Icons written to Sources/App/Resources and assets/icons."