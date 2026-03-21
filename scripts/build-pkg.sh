#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/RemoteSudoTouch.xcodeproj"
SCHEME="RemoteSudoTouch"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="$ROOT_DIR/build/RemoteSudoTouch.xcarchive"
DIST_DIR="$ROOT_DIR/dist"
PKG_WORK_DIR="$ROOT_DIR/build/pkg"
APP_SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:-}"
PKG_SIGNING_IDENTITY="${PKG_SIGNING_IDENTITY:-}"

mkdir -p "$DIST_DIR" "$PKG_WORK_DIR"
rm -rf "$ARCHIVE_PATH" "$PKG_WORK_DIR"
mkdir -p "$PKG_WORK_DIR"

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  archive
  SKIP_INSTALL=NO
)

if [[ -n "$APP_SIGNING_IDENTITY" ]]; then
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$APP_SIGNING_IDENTITY"
  )
fi

echo "== Building app archive =="
/usr/bin/xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/RemoteSudoTouch.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "build-pkg: expected app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="dev"
fi

COMPONENT_PKG="$PKG_WORK_DIR/RemoteSudoTouch-component.pkg"
FINAL_PKG="$DIST_DIR/RemoteSudoTouch-$VERSION.pkg"

PKGBUILD_ARGS=(
  --component "$APP_PATH"
  --install-location /Applications
)
if [[ -n "$PKG_SIGNING_IDENTITY" ]]; then
  PKGBUILD_ARGS+=(--sign "$PKG_SIGNING_IDENTITY")
fi
PKGBUILD_ARGS+=("$COMPONENT_PKG")

echo "== Building component package =="
/usr/bin/pkgbuild "${PKGBUILD_ARGS[@]}"

PRODUCTBUILD_ARGS=(
  --package "$COMPONENT_PKG"
)
if [[ -n "$PKG_SIGNING_IDENTITY" ]]; then
  PRODUCTBUILD_ARGS+=(--sign "$PKG_SIGNING_IDENTITY")
fi
PRODUCTBUILD_ARGS+=("$FINAL_PKG")

echo "== Building final installer package =="
/usr/bin/productbuild "${PRODUCTBUILD_ARGS[@]}"

echo
echo "Created installer:"
echo "  $FINAL_PKG"
