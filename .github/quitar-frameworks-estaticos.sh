#!/bin/bash
# Saca de Alma.app los frameworks que en realidad son bibliotecas estáticas (archivo «ar»).
#
# Por qué: sherpa-onnx (Modo calle) y onnxruntime llegan por Swift Package como xcframework ESTÁTICOS
# (SherpaOnnxC.framework y onnxruntime.framework con un archivo .a adentro). Su código ya queda dentro del
# ejecutable de Alma al enlazar, pero Xcode igual copia las carpetas a Alma.app/Frameworks. Un archivo estático
# no se puede firmar como código, y App Store Connect rechaza la subida:
#   «Invalid Signature … Alma.app/Frameworks/SherpaOnnxC.framework/SherpaOnnxC is not properly signed».
# Quitar esas copias no cambia nada de lo que corre la app.
#
# Uso: quitar-frameworks-estaticos.sh <ruta de Alma.app>
# Los frameworks dinámicos se dejan; si alguno trae piezas del simulador o le falta MinimumOSVersion, falla.
set -euo pipefail

APP="${1:?Falta la ruta de Alma.app}"
FW="$APP/Frameworks"
EXE="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
CARGA="$(otool -L "$EXE")"   # lo que Alma carga al abrir (sin tubos con grep -q: con pipefail darían falsos «no»)

if [ ! -d "$FW" ]; then
  echo "Alma.app no trae carpeta Frameworks: nada que quitar."
  exit 0
fi

for f in "$FW"/*.framework; do
  [ -e "$f" ] || continue
  nombre="$(basename "$f" .framework)"
  binario="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$f/Info.plist" 2>/dev/null || echo "$nombre")"
  tipo="$(file -b "$f/$binario")"
  if [[ "$tipo" == *"ar archive"* ]]; then
    # Si Alma lo cargara al abrir (dinámico), quitarlo la rompería: entonces mejor fallar aquí.
    if [[ "$CARGA" == *"/$nombre.framework/"* ]]; then
      echo "::error::Alma carga $nombre.framework al abrir y es estático; no se puede quitar."
      exit 1
    fi
    rm -rf "$f"
    echo "Quitado $nombre.framework (biblioteca estática, ya va dentro de Alma)."
  else
    echo "Se deja $nombre.framework ($tipo)."
    archs="$(lipo -archs "$f/$binario")"
    if [ "$archs" != "arm64" ]; then
      echo "::error::$nombre.framework trae $archs; para el iPhone debe ser solo arm64."
      exit 1
    fi
    if ! /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$f/Info.plist" >/dev/null 2>&1; then
      echo "::error::$nombre.framework no tiene MinimumOSVersion en su Info.plist."
      exit 1
    fi
  fi
done

# Si la carpeta quedó vacía, se borra (una carpeta Frameworks vacía no sirve).
rmdir "$FW" 2>/dev/null || true
