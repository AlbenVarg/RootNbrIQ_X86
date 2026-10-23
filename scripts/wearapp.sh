#!/usr/bin/env bash
# wearapp.sh — esfera propia estilo Pixel Watch para el NBRiq (shasta, Wear OS 2.0 / API 25).
#
# El proyecto vive en wearapp/ (Gradle 8.9 + AGP 8.7.3 + Kotlin 2.1). Solo hay un módulo,
# :watchface, que usa la API clásica de esferas (com.google.android.support:wearable:2.9.0):
# CanvasWatchFaceService + ComplicationDrawable. APK 100% dex (sin NDK), así que la x86 del
# reloj no es un problema.
#
# Uso:
#   ./wearapp.sh build        # compila el APK debug
#   ./wearapp.sh install      # compila e instala (adb install -r)
#   ./wearapp.sh face         # abre el selector de esferas del reloj
#   ./wearapp.sh shot [file]  # captura de pantalla (por defecto ./wearapp-shot.png)
#   ./wearapp.sh preview      # regenera el preview del selector desde una captura real
#   ./wearapp.sh status       # esfera activa, versión instalada y memoria
#   ./wearapp.sh log          # logcat filtrado de la esfera
#   ./wearapp.sh uninstall    # desinstala y vuelve a la esfera de fábrica
#
# Serial: exporta NBR_SERIAL=<serial|ip:5555>. Si es una IP, reintenta `adb connect` porque el
# reloj corta adb al entrar en Doze.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$ROOT/wearapp"
APK="$PROJ/watchface/build/outputs/apk/debug/watchface-debug.apk"
RES="$PROJ/watchface/src/main/res"
PKG="dev.nbriq.wear.watchface"
WEAR_APP="com.google.android.wearable.app"
PICKER="$WEAR_APP/com.google.android.clockwork.home.module.watchfacepicker.WatchFacePickerAllFacesActivity"

# AGP 8.7 exige JDK 17: el `openjdk` "latest" de Homebrew (27) revienta Gradle 8.9 con
# "What went wrong: 27". Se puede sobreescribir con NBR_JAVA_HOME.
JDK_HOME="${NBR_JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
if [ -x "$JDK_HOME/bin/java" ]; then
  export JAVA_HOME="$JDK_HOME"
fi

ADB=(adb)
SERIAL="${NBR_SERIAL:-}"
if [ -z "$SERIAL" ]; then
  SERIAL="$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
fi
if [ -n "$SERIAL" ]; then
  ADB+=(-s "$SERIAL")
fi

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
wake() { "${ADB[@]}" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; }

wait_device() {
  local i
  for i in $(seq 1 15); do
    case "$SERIAL" in
      *:*) adb connect "$SERIAL" >/dev/null 2>&1 || true ;;
    esac
    if [ "$("${ADB[@]}" shell 'echo ok' 2>/dev/null | tr -d '\r')" = ok ]; then
      return 0
    fi
    sleep 4
  done
  die "el reloj no responde en adb (¿Wi-Fi apagada o en Doze?)"
}

need_gradle() { [ -x "$PROJ/gradlew" ] || die "falta $PROJ/gradlew"; }
need_apk()    { [ -f "$APK" ] || die "no hay APK: ejecuta ./wearapp.sh build"; }

cmd_build() {
  need_gradle
  say "compilando :watchface (JAVA_HOME=$JAVA_HOME)"
  ( cd "$PROJ" && ./gradlew :watchface:assembleDebug --console=plain )
  say "APK"
  ls -lh "$APK"
}

cmd_install() {
  cmd_build
  wait_device
  say "instalando en $SERIAL"
  "${ADB[@]}" install -r "$APK"
  # Tras instalar/actualizar, la esfera nueva solo sale en el selector si la app de Wear
  # vuelve a enumerar los WallpaperService; un force-stop + reapertura lo refresca.
  "${ADB[@]}" shell am force-stop "$WEAR_APP" >/dev/null 2>&1 || true
  say "hecho: abre el selector con ./wearapp.sh face (sección 'P' de la lista)"
}

cmd_face() {
  wait_device
  wake
  "${ADB[@]}" shell am force-stop "$WEAR_APP" >/dev/null 2>&1 || true
  sleep 2
  "${ADB[@]}" shell am start -n "$PICKER" >/dev/null
  printf 'Selector abierto: busca "Pixel NBRiq" (orden alfabético, sección P) y tócala.\n'
}

cmd_shot() {
  local out="${1:-$ROOT/wearapp-shot.png}"
  wait_device
  wake
  sleep 2
  "${ADB[@]}" exec-out screencap -p > "$out"
  say "captura guardada en $out"
}

cmd_preview() {
  local tmp=/tmp/nbriq-face-preview.png
  wait_device
  wake
  sleep 2
  "${ADB[@]}" exec-out screencap -p > "$tmp"
  if python3 -c 'import PIL' >/dev/null 2>&1; then
    python3 -c "
from PIL import Image, ImageDraw
im = Image.open('$tmp').convert('RGBA')
mask = Image.new('L', im.size, 0)
w, h = im.size
ImageDraw.Draw(mask).ellipse((2, 2, w - 3, h - 3), fill=255)
im.putalpha(mask)
im.save('$tmp')
"
  else
    printf 'aviso: sin Pillow, el preview se guarda sin recorte circular.\n'
  fi
  mkdir -p "$RES/drawable-nodpi"
  cp "$tmp" "$RES/drawable-nodpi/preview.png"
  rm -f "$RES/drawable/preview.xml"
  say "preview regenerado desde la pantalla actual"
  cmd_install
}

cmd_status() {
  wait_device
  say "esfera activa"
  "${ADB[@]}" shell dumpsys wallpaper | grep mWallpaperComponent | head -2 || true
  say "app instalada"
  "${ADB[@]}" shell dumpsys package "$PKG" 2>/dev/null \
    | grep -E 'versionName|versionCode|codePath' | head -3 || printf 'no instalada\n'
  say "memoria"
  "${ADB[@]}" shell dumpsys meminfo "$PKG" 2>/dev/null | grep -E 'TOTAL:' | head -2 || true
  "${ADB[@]}" shell cat /proc/meminfo | head -3
}

cmd_log() {
  wait_device
  "${ADB[@]}" logcat -c
  printf 'Ctrl+C para salir.\n'
  "${ADB[@]}" logcat | grep -iE "nbriq|PixelWatchFace|ComplicationDrawable|WatchFaceService"
}

cmd_uninstall() {
  wait_device
  say "desinstalando $PKG"
  "${ADB[@]}" uninstall "$PKG" || true
  say "el reloj vuelve a la esfera de fábrica; si no, elige otra con ./wearapp.sh face"
}

case "${1:-}" in
  build)     cmd_build ;;
  install)   cmd_install ;;
  face)      cmd_face ;;
  shot)      shift; cmd_shot "${1:-}" ;;
  preview)   cmd_preview ;;
  status)    cmd_status ;;
  log)       cmd_log ;;
  uninstall) cmd_uninstall ;;
  *)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
