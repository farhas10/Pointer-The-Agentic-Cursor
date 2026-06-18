#!/bin/bash
# Strip Finder/iCloud extended attributes immediately before CodeSign.
# Desktop + iCloud Drive adds com.apple.provenance / FinderInfo that breaks codesign.
set -euo pipefail
APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
if [[ ! -d "$APP" ]]; then
  exit 0
fi
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/dot_clean -m "$APP" 2>/dev/null || true
/usr/bin/find "$APP" -name '._*' -delete 2>/dev/null || true
# Re-strip after dot_clean; iCloud sometimes re-tags the bundle root last.
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/xattr -d com.apple.fileprovider.fpfs#P "$APP" 2>/dev/null || true
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
