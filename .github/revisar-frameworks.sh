#!/bin/bash
# Guardia antes de subir a TestFlight: revisa cada framework dentro de Alma.app con las reglas que Apple aplicó en sus
# correos del 3-nov-2026 (versiones 123, 130 y 131, que se subieron pero Apple tiró al procesarlas):
#   · ITMS-90035 «Invalid Signature»: ningún framework estático (archivo «ar», no se puede firmar) y cada uno con firma
#     válida (codesign --verify --strict).
#   · ITMS-90208 «Invalid Bundle»: el MinimumOSVersion del Info.plist de cada framework es el mismo «minos» con que se
#     compiló su binario y no pasa del de la app.
# Uso: revisar-frameworks.sh <ruta de Alma.app> (después de firmar; si algo falla, sale con error y no se sube).
set -uo pipefail

APP="${1:?Falta la ruta de Alma.app}"
APP_MIN="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")"
mal=0
falla() { echo "::error::$1"; mal=1; }

for f in "$APP"/Frameworks/*.framework; do
  [ -d "$f" ] || continue
  n="$(basename "$f")"
  bin="$f/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$f/Info.plist")"
  tipo="$(file -b "$bin")"
  [[ "$tipo" == *"ar archive"* ]] && { falla "$n es estático (no se puede firmar: ITMS-90035)."; continue; }
  minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{b=1} /LC_VERSION_MIN_IPHONEOS/{v=1} b && $1=="minos" && m==""{m=$2} v && $1=="version" && m==""{m=$2} END{print m}')"
  plist="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$f/Info.plist" 2>/dev/null)"
  [ -n "$minos" ] || falla "$n: no pude leer el minos de su binario."
  [ "$plist" = "$minos" ] || falla "$n: MinimumOSVersion del Info.plist ($plist) distinto del binario ($minos) (ITMS-90208)."
  [ "$(printf '%s\n%s\n' "$minos" "$APP_MIN" | sort -V | tail -1)" = "$APP_MIN" ] \
    || falla "$n pide iOS $minos y la app arranca en iOS $APP_MIN (ITMS-90208)."
  codesign --verify --strict "$f" 2>&1 || falla "$n: firma inválida (ITMS-90035)."
  echo "OK $n · iOS $minos · firmado"
done
codesign --verify --strict --deep "$APP" 2>&1 || falla "Alma.app: firma inválida."
[ $mal = 0 ] && echo "Frameworks listos para Apple (app: iOS $APP_MIN)."
exit $mal
