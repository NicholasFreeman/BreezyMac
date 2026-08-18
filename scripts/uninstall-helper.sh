#!/usr/bin/env bash
#
# uninstall-helper.sh — developer convenience to fully remove the privileged
# helper daemon during iteration. The app can also remove it via the
# "Uninstall" button (SMAppService.unregister), which is the preferred path.
#
# SMAppService daemons are also listed in System Settings → General →
# Login Items & Extensions; you may need to toggle/remove it there too.
set -euo pipefail

LABEL="org.WhoCo.BreezyMac.Helper"

echo "==> Booting out $LABEL (requires sudo)"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || echo "   (not currently loaded)"

echo "==> Done."
echo "    If it reappears, open System Settings → General → Login Items &"
echo "    Extensions and remove BreezyMac's background item, or use the app's"
echo "    Uninstall button."
