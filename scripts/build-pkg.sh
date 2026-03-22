#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/RemoteSudoTouch.xcodeproj"
SCHEME="RemoteSudoTouch"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="$ROOT_DIR/build/RemoteSudoTouch.xcarchive"
DIST_DIR="$ROOT_DIR/dist"
PKG_WORK_DIR="$ROOT_DIR/build/pkg"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
PRODUCTS_DIR="$ROOT_DIR/build/products/$CONFIGURATION"
LOCAL_TMP_DIR="$ROOT_DIR/build/tmp"
LOCAL_CACHE_DIR="$ROOT_DIR/build/cache"
APP_SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:-}"
PKG_SIGNING_IDENTITY="${PKG_SIGNING_IDENTITY:-}"
EXISTING_APP_PATH="${APP_PATH:-}"

mkdir -p "$DIST_DIR" "$PKG_WORK_DIR" "$DERIVED_DATA_PATH" "$LOCAL_TMP_DIR" "$LOCAL_CACHE_DIR" "$PRODUCTS_DIR"
rm -rf "$ARCHIVE_PATH" "$PKG_WORK_DIR" "$DERIVED_DATA_PATH" "$PRODUCTS_DIR"
mkdir -p "$PKG_WORK_DIR" "$DERIVED_DATA_PATH" "$LOCAL_TMP_DIR" "$LOCAL_CACHE_DIR" "$PRODUCTS_DIR"

if [[ "$LOCAL_TMP_DIR" != */ ]]; then
  LOCAL_TMP_DIR="$LOCAL_TMP_DIR/"
fi

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ -n "$APP_SIGNING_IDENTITY" ]]; then
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$APP_SIGNING_IDENTITY"
  )
fi

run_xcodebuild() {
  env \
    TMPDIR="$LOCAL_TMP_DIR" \
    CFFIXED_USER_HOME="${CFFIXED_USER_HOME:-$HOME}" \
    XDG_CACHE_HOME="$LOCAL_CACHE_DIR" \
    /usr/bin/xcodebuild "$@"
}

build_local_app() {
  local app_output_dir="$PRODUCTS_DIR"
  local build_args=(
    "${XCODEBUILD_ARGS[@]}"
    build
    "CONFIGURATION_BUILD_DIR=$app_output_dir"
    SKIP_INSTALL=NO
  )

  echo "== Building local app bundle =="
  run_xcodebuild "${build_args[@]}"
}

if [[ -n "$EXISTING_APP_PATH" ]]; then
  APP_PATH="$EXISTING_APP_PATH"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "build-pkg: APP_PATH does not exist: $APP_PATH" >&2
    exit 1
  fi
  echo "== Using existing app bundle =="
  echo "$APP_PATH"
else
  echo "== Building app archive =="
  archive_args=(
    "${XCODEBUILD_ARGS[@]}"
    -archivePath "$ARCHIVE_PATH"
    archive
    SKIP_INSTALL=NO
  )
  if run_xcodebuild "${archive_args[@]}"; then
    APP_PATH="$ARCHIVE_PATH/Products/Applications/RemoteSudoTouch.app"
    if [[ ! -d "$APP_PATH" ]]; then
      echo "build-pkg: expected app not found at $APP_PATH" >&2
      exit 1
    fi
  else
    echo >&2
    echo "build-pkg: xcodebuild archive failed. Falling back to an in-tree app build under build/products/." >&2
    build_local_app
    APP_PATH="$PRODUCTS_DIR/RemoteSudoTouch.app"
    if [[ ! -d "$APP_PATH" ]]; then
      echo "build-pkg: expected local app not found at $APP_PATH" >&2
      exit 1
    fi
  fi
fi

VERSION=""
if [[ -f "$ARCHIVE_PATH/Info.plist" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
fi
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
