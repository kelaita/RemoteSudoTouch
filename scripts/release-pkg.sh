#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-pkg.sh"
DIST_DIR="$ROOT_DIR/dist"

APP_SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:-}"
PKG_SIGNING_IDENTITY="${PKG_SIGNING_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
PKG_PATH="${PKG_PATH:-}"

usage() {
  cat <<'EOF'
Usage: release-pkg.sh

Required environment variables:
  APP_SIGNING_IDENTITY      Developer ID Application identity
  PKG_SIGNING_IDENTITY      Developer ID Installer identity
  NOTARY_KEYCHAIN_PROFILE   notarytool keychain profile name

Optional environment variables:
  BUILD_DESTINATION         xcodebuild destination passed through to build-pkg.sh
  PKG_PATH                  existing pkg to notarize and staple instead of building
  APP_PATH                  existing app bundle passed through to build-pkg.sh
  CONFIGURATION             xcode build configuration passed through to build-pkg.sh
EOF
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "release-pkg: missing required environment variable: $name" >&2
    usage >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_env APP_SIGNING_IDENTITY
require_env PKG_SIGNING_IDENTITY
require_env NOTARY_KEYCHAIN_PROFILE

if [[ -z "$PKG_PATH" ]]; then
  if [[ ! -x "$BUILD_SCRIPT" ]]; then
    echo "release-pkg: build script not found or not executable: $BUILD_SCRIPT" >&2
    exit 1
  fi

  echo "== Building signed installer package =="
  APP_SIGNING_IDENTITY="$APP_SIGNING_IDENTITY" \
  PKG_SIGNING_IDENTITY="$PKG_SIGNING_IDENTITY" \
  BUILD_DESTINATION="${BUILD_DESTINATION:-}" \
  APP_PATH="${APP_PATH:-}" \
  CONFIGURATION="${CONFIGURATION:-}" \
  "$BUILD_SCRIPT"

  PKG_PATH="$(ls -t "$DIST_DIR"/RemoteSudoTouch-*.pkg 2>/dev/null | head -n 1 || true)"
  if [[ -z "$PKG_PATH" ]]; then
    echo "release-pkg: could not find built pkg in $DIST_DIR" >&2
    exit 1
  fi
else
  if [[ ! -f "$PKG_PATH" ]]; then
    echo "release-pkg: PKG_PATH does not exist: $PKG_PATH" >&2
    exit 1
  fi
fi

echo
echo "== Submitting pkg for notarization =="
xcrun notarytool submit "$PKG_PATH" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait

echo
echo "== Stapling notarization ticket =="
xcrun stapler staple "$PKG_PATH"

echo
echo "== Validating stapled pkg =="
xcrun stapler validate "$PKG_PATH"
spctl -a -vv -t install "$PKG_PATH"

echo
echo "Release package ready:"
echo "  $PKG_PATH"
