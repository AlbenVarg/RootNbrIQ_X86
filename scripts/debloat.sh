#!/usr/bin/env bash
# debloat.sh — aligera el New Balance RunIQ (shasta, x86, Wear 2.0) de forma REVERSIBLE.
#
# No borra nada: usa `pm disable-user --user 0` (el APK sigue en /system) y fija ajustes
# de UI. Todo se deshace con `./debloat.sh restore`.
#
# Uso:
#   ./debloat.sh status      # qué está deshabilitado ahora + memoria
#   ./debloat.sh apply       # aplica el debloat (idempotente)
#   ./debloat.sh restore     # vuelve a dejar todo como de fábrica
#   ./debloat.sh extras      # sólo animaciones + parar la app de Magisk
#
# Requiere root (Magisk): los cambios se hacen vía `su -c`.
# Serial: exporta NBR_SERIAL=<serial|ip:5555>.
#
# Medido en el reloj (22/10/2026, tras reiniciar):
#   MemAvailable  158 MB -> 220 MB      swap en uso  110 MB -> ~30 MB
#   load average  3.51 -> 0.19-1.00     kswapd0      19% -> 1,4%
set -euo pipefail

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
root() { "${ADB[@]}" shell "su -c '$*'"; }

# Cada `su` desde el shell despierta la app de Magisk (SuRequestActivity / .core.Provider),
# que ocupa ~53 MB. La app se deja instalada pero se vuelve a parar al terminar.
# Ojo: hay que pararla SIN `su` (el propio `su` la resucita); el shell de adb tiene permiso.
# Se mata dos veces porque magiskd la relanza de forma asíncrona tras la petición de su.
quiet_app() {
  "${ADB[@]}" shell 'am force-stop com.topjohnwu.magisk' >/dev/null 2>&1 || true
  sleep 2
  "${ADB[@]}" shell 'am force-stop com.topjohnwu.magisk' >/dev/null 2>&1 || true
}

# --- Telemetría, demos y apps de test: no aportan nada al usuario -----------------
BLOAT_SAFE=(
  com.intel.analytics                                  # telemetría Intel: 19 MB + 3 servicios
  com.android.lto                                      # app de test de Google
  com.google.android.apps.wearable.retailattractloop    # vídeo de demo de tienda
  com.google.android.apps.wearable.bugreportsender      # enviar bugreports
  com.google.android.clockwork.gestures.tutorial        # tutorial de gestos
  com.android.backupconfirm                            # UI de confirmación de backup
  com.android.wallpaperbackup                          # backup de fondos (no hay fondos)
  com.android.managedprovisioning                      # perfil de empresa (BYOD)
  com.android.cts.ctsshim                              # shims de tests CTS
  com.android.cts.priv.ctsshim
)

# --- Apps preinstaladas que aquí no se usan ---------------------------------------
BLOAT_APPS=(
  com.newbalance.loyalty                               # NB Wear (loyalty), 7 MB
  com.strava                                           # Strava preinstalado, 3 MB
  com.google.android.music                             # Play Music (servicio muerto), 17 MB
  com.google.android.apps.translate                    # Translate en el reloj
  com.google.android.apps.handwriting.ime              # teclado manuscrito, 17 MB
  com.google.android.wearable.reminders                # recordatorios
  com.google.android.syncadapters.contacts             # sync de contactos del teléfono
  com.google.android.apps.wearable.phone               # app Teléfono (el RunIQ no tiene LTE)
)

# --- Pesados: liberan RAM pero quitan funciones -----------------------------------
# vending              -> Play Store / facturación in-app (en Wear no hay tienda)
# googlequicksearchbox -> búsqueda por voz "Ok Google" + hotword siempre escuchando (~10 MB)
BLOAT_HEAVY=(
  com.android.vending
  com.google.android.googlequicksearchbox
)

# App de Magisk: se queda instalada, pero se para tras cada arranque (~53 MB de RAM).
MAGISK_APP="com.topjohnwu.magisk"
BOOT_SCRIPT="/data/adb/service.d/99-watch-tune.sh"

need_device() {
  command -v adb >/dev/null || die "adb no está en el PATH"
  [ -n "$SERIAL" ] || die "no hay dispositivo adb en estado 'device' (usa NBR_SERIAL=...)"
  "${ADB[@]}" shell su -c id >/dev/null 2>&1 \
    || die "su no responde (¿magiskd caído? reinicia el reloj)"
}

cmd_status() {
  need_device
  say "deshabilitados"
  "${ADB[@]}" shell 'pm list packages -d | sed s/package:// | sort' | tr -d '\r'
  say "memoria"
  "${ADB[@]}" shell 'grep -E "MemAvailable|SwapFree" /proc/meminfo; uptime' | tr -d '\r'
  say "script de arranque"
  root "test -f $BOOT_SCRIPT && echo presente || echo ausente" | tr -d '\r'
  echo -n "app de Magisk: "
  "${ADB[@]}" shell 'ps | grep -c topjohnwu' | tr -d '\r'
  quiet_app
  echo "  (parada)"
}

cmd_extras() {
  say "animaciones a 0 (la UI se siente más rápida)"
  "${ADB[@]}" shell 'settings put global window_animation_scale 0; \
                     settings put global transition_animation_scale 0; \
                     settings put global animator_duration_scale 0'

  say "script de arranque: para la app de Magisk y fija las animaciones"
  root "mkdir -p /data/adb/service.d"
  cat > /tmp/99-watch-tune.sh <<'EOS'
#!/system/bin/sh
# Instalado por debloat.sh (NBRiq). La app de Magisk ocupa ~53 MB y aquí no hace falta:
# magiskd vive en la partición boot y `su` sigue funcionando. Se para tras el arranque.
# Marcadores de diagnóstico: getprop nbr.tune.start / nbr.tune.done
setprop nbr.tune.start 1
(
  sleep 60
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  am force-stop com.topjohnwu.magisk
  setprop nbr.tune.done 1
) &
EOS
  # /data/adb es 700 root: hay que pasar por /data/local/tmp y luego copiar como root.
  "${ADB[@]}" push /tmp/99-watch-tune.sh /data/local/tmp/99-watch-tune.sh >/dev/null
  root "cp /data/local/tmp/99-watch-tune.sh $BOOT_SCRIPT; rm -f /data/local/tmp/99-watch-tune.sh; \
        chmod 755 $BOOT_SCRIPT; chown 0:0 $BOOT_SCRIPT; \
        chcon u:object_r:magisk_file:s0 $BOOT_SCRIPT; ls -lZ $BOOT_SCRIPT"
  rm -f /tmp/99-watch-tune.sh

  say "parando la app de Magisk ahora"
  quiet_app
}

cmd_apply() {
  need_device
  local p
  say "deshabilitando telemetría / demos / test"
  for p in "${BLOAT_SAFE[@]}"; do
    printf '  %-56s ' "$p"
    root "pm disable-user --user 0 $p" | tr -d '\r' | tail -1
  done
  say "deshabilitando apps preinstaladas sin uso"
  for p in "${BLOAT_APPS[@]}"; do
    printf '  %-56s ' "$p"
    root "pm disable-user --user 0 $p" | tr -d '\r' | tail -1
  done
  say "deshabilitando pesados (Play Store + búsqueda/hotword)"
  for p in "${BLOAT_HEAVY[@]}"; do
    printf '  %-56s ' "$p"
    root "pm disable-user --user 0 $p" | tr -d '\r' | tail -1
  done
  cmd_extras
  "${ADB[@]}" shell 'pm list packages -d | sed s/package:// | sort' \
    > debloat/packages-disabled.txt 2>/dev/null || true
  quiet_app
  say "hecho: reinicia para ver el efecto completo (adb reboot)"
}

cmd_restore() {
  need_device
  local p
  say "rehabilitando paquetes"
  for p in "${BLOAT_SAFE[@]}" "${BLOAT_APPS[@]}" "${BLOAT_HEAVY[@]}"; do
    printf '  %-56s ' "$p"
    root "pm enable $p" | tr -d '\r' | tail -1
  done
  say "animaciones a 1x"
  "${ADB[@]}" shell 'settings put global window_animation_scale 1; \
                     settings put global transition_animation_scale 1; \
                     settings put global animator_duration_scale 1'
  say "quitando script de arranque"
  root "rm -f $BOOT_SCRIPT"
  quiet_app
  say "restaurado (reinicia para aplicar)"
}

usage() {
  cat <<'TXT'
debloat.sh — debloat reversible del New Balance RunIQ.

Uso:
  ./debloat.sh status     # deshabilitados + memoria
  ./debloat.sh apply      # aplica el debloat (idempotente)
  ./debloat.sh restore    # vuelve a fábrica
  ./debloat.sh extras     # sólo animaciones + parar la app de Magisk

Serial: exporta NBR_SERIAL=<serial|ip:5555>.
TXT
}

case "${1:-}" in
  status)  cmd_status ;;
  apply)   cmd_apply ;;
  restore) cmd_restore ;;
  extras)  cmd_extras ;;
  *)       usage ;;
esac

