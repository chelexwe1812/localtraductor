#!/bin/bash
#
# Genera el .dmg de LocalTranslator listo para publicar en GitHub Releases.
#
#   ./scripts/release.sh
#
# Variables de entorno opcionales:
#
#   DEVELOPER_ID    Nombre exacto del certificado "Developer ID Application".
#                   Sin esto la app queda firmada ad-hoc y macOS la BLOQUEARÁ
#                   en cualquier Mac que no sea este. Ver README de publicación.
#                   Ej: DEVELOPER_ID="Developer ID Application: Nombre (ABCDE12345)"
#
#   NOTARY_PROFILE  Perfil de notarytool guardado en el llavero. Solo se usa si
#                   además hay DEVELOPER_ID. Se crea una vez con:
#                     xcrun notarytool store-credentials NOMBRE \
#                       --apple-id tu@correo --team-id ABCDE12345 \
#                       --password <app-specific-password>
#
set -euo pipefail

SCHEME="LocalTranslator"
CONFIG="Release"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/$SCHEME.xcarchive"
STAGE="$BUILD/dmg"
APP_NAME="$SCHEME.app"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\n\033[1;33m!!  %s\033[0m\n' "$1"; }

# La versión sale del proyecto, no se escribe a mano: así el nombre del .dmg y
# el tag de git no pueden divergir de lo que realmente lleva el bundle dentro.
VERSION="$(xcodebuild -project "$ROOT/$SCHEME.xcodeproj" -scheme "$SCHEME" \
  -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')"
[ -n "$VERSION" ] || { echo "No pude leer MARKETING_VERSION"; exit 1; }
DMG="$BUILD/LocalTranslator-$VERSION.dmg"

say "LocalTranslator $VERSION"
rm -rf "$ARCHIVE" "$STAGE" "$DMG"
mkdir -p "$BUILD"

# ARCHS=arm64 explícito: MLX corre la inferencia sobre Metal y solo existe para
# Apple Silicon. El target hereda "arm64 x86_64" de ARCHS_STANDARD, que haría
# un binario universal cuya mitad Intel no puede funcionar.
say "Archivando (Release, arm64)"
xcodebuild archive \
  -scheme "$SCHEME" -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  | grep -E "^(\*\*|error:|warning: )" || true

[ -d "$ARCHIVE/Products/Applications/$APP_NAME" ] || { echo "El archive no produjo la app"; exit 1; }

say "Extrayendo la app"
mkdir -p "$STAGE"
cp -R "$ARCHIVE/Products/Applications/$APP_NAME" "$STAGE/"
APP="$STAGE/$APP_NAME"

if [ -n "$DEVELOPER_ID" ]; then
    say "Firmando con Developer ID"
    # --deep está desaconsejado por Apple, pero este bundle no tiene frameworks
    # embebidos propios (MLX se enlaza estáticamente), así que basta con firmar
    # el bundle. Si algún día se añaden dylibs, hay que firmarlas antes, de
    # dentro hacia fuera, y luego el .app.
    codesign --force --timestamp --options runtime \
        --entitlements "$ROOT/LocalTranslator/LocalTranslator.entitlements" \
        --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"

    if [ -n "$NOTARY_PROFILE" ]; then
        say "Notarizando (puede tardar varios minutos)"
        ZIP="$BUILD/notarize.zip"
        ditto -c -k --keepParent "$APP" "$ZIP"
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
    else
        warn "Sin NOTARY_PROFILE: la app va firmada pero NO notarizada."
        warn "Gatekeeper la seguirá bloqueando en Macs ajenos."
    fi
else
    warn "Sin DEVELOPER_ID: la app queda firmada ad-hoc."
    warn "En cualquier otro Mac macOS dirá que está dañada y no se abrirá."
    warn "Hay que documentar el rodeo manual en el README (ver notas de publicación)."
fi

say "Construyendo el .dmg"
ln -s /Applications "$STAGE/Applications"
diskutil image create from "$STAGE" \
    --volumeName "LocalTranslator $VERSION" --format UDZO "$DMG" >/dev/null

if [ -n "$DEVELOPER_ID" ]; then
    # Firmar y grapar también el .dmg: así Gatekeeper valida el contenedor sin
    # necesidad de red al abrirlo.
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    [ -n "$NOTARY_PROFILE" ] && {
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    }
fi

say "Listo"
ls -lh "$DMG"
shasum -a 256 "$DMG"
echo
echo "Publicar con:"
echo "  gh release create v$VERSION \"$DMG\" --title \"LocalTranslator $VERSION\" --notes-file NOTAS.md"
