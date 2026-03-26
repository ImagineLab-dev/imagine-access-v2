#!/bin/bash
# ============================================================
# deploy_ios.sh — Build & deploy Imagine Access to iPhone
# ============================================================
# Uso:
#   ./deploy_ios.sh                    (profile - arranca sin debugger)
#   ./deploy_ios.sh debug              (debug)
#   ./deploy_ios.sh release            (release - para App Store)
#   ./deploy_ios.sh profile <DEVICE>   (profile a device específico)
#
# El script copia el proyecto a /tmp para evitar que macOS Sequoia
# agregue com.apple.provenance a los archivos, rompiendo codesign.
# ============================================================

set -euo pipefail

MODE="${1:-profile}"
BUNDLE_ID="com.imagineaccess.app"
# Detectar directorio del proyecto (funciona desde cualquier Mac)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/imagine-access-build-$(whoami)"

echo "Mode:    $MODE"
echo "Source:  $PROJECT_DIR"
echo "Build:   $BUILD_DIR"
echo ""

# 1. Copiar proyecto fuera de iCloud / Desktop
echo "Copying project to $BUILD_DIR..."
mkdir -p "$BUILD_DIR"
rsync -a --delete \
  --exclude='build' \
  --exclude='build_old' \
  --exclude='build_temp_old' \
  --exclude='.dart_tool' \
  --exclude='.git' \
  "$PROJECT_DIR/" "$BUILD_DIR/"
echo "   Done"

# 2. Obtener dependencias
echo "Getting dependencies..."
cd "$BUILD_DIR"
flutter pub get 2>&1 | tail -3
echo "   Done"

# 3. Build
echo "Building iOS ($MODE)..."
if [ "$MODE" = "release" ]; then
  flutter build ios --flavor prod --release -t lib/main.dart 2>&1
elif [ "$MODE" = "debug" ]; then
  flutter build ios --flavor dev --debug -t lib/main_dev.dart 2>&1
else
  flutter build ios --flavor prod --profile -t lib/main.dart 2>&1
fi
echo "   Build complete"

# 4. Encontrar .app
APP_PATH="$BUILD_DIR/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Runner.app not found at $APP_PATH"
  exit 1
fi
echo "App: $APP_PATH"

# 5. Detectar device (argumento 2 o primer dispositivo conectado)
if [ -n "${2:-}" ]; then
  DEVICE_ID="$2"
else
  echo "Detecting connected iPhone..."
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | awk '{print $NF}' | head -1 || true)
  if [ -z "$DEVICE_ID" ]; then
    # Fallback: usar instruments
    DEVICE_ID=$(instruments -s devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v Simulator | awk -F'[()]' '{print $(NF-1)}' | head -1 || true)
  fi
fi

if [ -z "$DEVICE_ID" ]; then
  echo "WARNING: No device detected. Install manually via Xcode."
  echo "App built at: $APP_PATH"
  exit 0
fi

echo "Device: $DEVICE_ID"

# 6. Instalar
echo "Installing on device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1
echo "   Installed"

# 7. Lanzar
echo "Launching app..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1

echo ""
echo "Imagine Access deployed successfully!"
