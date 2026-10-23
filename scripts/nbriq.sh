#!/usr/bin/env bash
# nbriq.sh — utilidades ADB/fastboot para el New Balance RunIQ (device: shasta, x86)
# Build verificado en esta sesión: NWD1.171016.002 / Android 7.1.1 / bootloader SHASTA-03.54
#
# Uso:
#   ./nbriq.sh status          # estado en ADB y en fastboot (no cambia nada)
#   ./nbriq.sh bootloader      # adb reboot bootloader
#   ./nbriq.sh unlock [--yes]  # fastboot flashing unlock  (BORRA /data)
#   ./nbriq.sh relock [--yes]  # fastboot flashing lock    (solo con sistema de fábrica)
#   ./nbriq.sh reboot          # vuelve a Android
#
# Serial: exporta NBR_SERIAL=<serial> si tienes más de un dispositivo.
set -euo pipefail

SERIAL="${NBR_SERIAL:-}"
if [ -z "$SERIAL" ]; then
  SERIAL="$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
fi
if [ -z "$SERIAL" ]; then
  SERIAL="$(fastboot devices | awk 'NF{print $1; exit}')"
fi

ADB=(adb)
FB=(fastboot)
if [ -n "$SERIAL" ]; then
  ADB+=(-s "$SERIAL")
  FB+=(-s "$SERIAL")
fi

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_adb()      { command -v adb >/dev/null      || die "adb no está en el PATH"; }
need_fastboot() { command -v fastboot >/dev/null || die "fastboot no está en el PATH"; }
in_fastboot()   { [ -n "$(fastboot devices)" ]; }
in_adb()        { [ -n "$(adb devices | awk 'NR>1 && $2=="device"')" ]; }

cmd_status() {
  say "adb devices"
  adb devices -l || true
  say "fastboot devices"
  fastboot devices || true

  if in_adb; then
    say "Android"
    adb -s "$SERIAL" shell 'for p in ro.product.model ro.product.device ro.build.version.release \
      ro.build.id ro.bootloader ro.build.type; do echo "$p=$(getprop $p)"; done' || true
  elif in_fastboot; then
    say "Bootloader"
    fastboot -s "$SERIAL" getvar unlocked      2>&1 | head -2 || true
    fastboot -s "$SERIAL" getvar device_state  2>&1 | head -2 || true
    fastboot -s "$SERIAL" getvar version-bootloader 2>&1 | head -2 || true
  else
    printf 'Sin dispositivo: revisa cable, "ADB debugging" en el reloj, o el modo de arranque.\n'
  fi
}

cmd_bootloader() {
  need_adb
  in_adb || die "no hay dispositivo en ADB (¿depuración ADB desactivada tras el wipe?)"
  case "$SERIAL" in
    *:*|localhost*)
      printf 'AVISO: estás por Wi-Fi/Bluetooth (%s). fastboot NO funciona inalámbrico:\n' "$SERIAL"
      printf '       tras el reinicio hay que conectar el reloj por USB a la cuna.\n' ;;
  esac
  adb -s "$SERIAL" reboot bootloader
  for _ in $(seq 1 15); do
    sleep 2
    if in_fastboot; then echo "en fastboot: $(fastboot devices)"; return 0; fi
  done
  die "no apareció en fastboot (¿cuna/cable solo de carga?)"
}

cmd_unlock() {
  need_fastboot
  in_fastboot || die "el reloj tiene que estar en fastboot (./nbriq.sh bootloader)"
  if [ "${1:-}" != "--yes" ]; then
    printf 'Esto BORRA /data y deja el reloj en setup de fábrica. Escribe "si" para continuar: '
    read -r ans
    [ "$ans" = "si" ] || die "cancelado"
  fi
  # timeout: algunos bootloaders esperan confirmación en pantalla
  if command -v gtimeout >/dev/null; then
    gtimeout 90 fastboot -s "$SERIAL" flashing unlock
  else
    perl -e 'alarm shift; exec @ARGV' 90 fastboot -s "$SERIAL" flashing unlock
  fi
  cmd_status
}

cmd_relock() {
  need_fastboot
  in_fastboot || die "el reloj tiene que estar en fastboot"
  if [ "${1:-}" != "--yes" ]; then
    printf 'Relock SOLO con sistema sin modificar; si no, el reloj no arranca. Escribe "si": '
    read -r ans
    [ "$ans" = "si" ] || die "cancelado"
  fi
  fastboot -s "$SERIAL" flashing lock
  cmd_status
}

cmd_reboot() {
  if in_fastboot; then
    fastboot -s "$SERIAL" reboot
  elif in_adb; then
    adb -s "$SERIAL" reboot
  else
    die "no hay dispositivo"
  fi
}

case "${1:-}" in
  status)     need_adb; need_fastboot; cmd_status ;;
  bootloader) cmd_bootloader ;;
  unlock)     shift; cmd_unlock "${1:-}" ;;
  relock)     shift; cmd_relock "${1:-}" ;;
  reboot)     cmd_reboot ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
