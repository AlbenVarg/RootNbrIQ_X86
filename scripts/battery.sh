#!/usr/bin/env bash
# battery.sh — salud de la batería y quién la gasta en el New Balance RunIQ (shasta).
#
# El reloj tiene una MAX17047 (fuel gauge) con 416 mAh de diseño y 400 mAh reales:
#   /sys/class/power_supply/max17047_battery/{charge_full_design,charge_full,current_avg,...}
#
# Uso:
#   ./battery.sh health        # capacidad real vs diseño, temperatura, voltaje, ritmo de descarga
#   ./battery.sh drain         # quién despierta al reloj (kernel wakeups, alarmas, sensores)
#   ./battery.sh wifi off|on   # apaga/enciende la Wi-Fi (el mayor consumidor medido)
#   ./battery.sh tweaks        # muestra los ajustes que afectan al consumo
#   ./battery.sh tweaks apply  # aplica los ajustes conservadores (reversible)
#   ./battery.sh tweaks revert # vuelve a los valores de fábrica
#
# Serial: exporta NBR_SERIAL=<serial|ip:5555>. Si es una IP, reintenta `adb connect`
# porque el reloj corta adb al entrar en Doze (tarda hasta ~40 s en aceptar).
set -euo pipefail

ADB=(adb)
SERIAL="${NBR_SERIAL:-}"
if [ -z "$SERIAL" ]; then
  SERIAL="$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
fi
if [ -n "$SERIAL" ]; then
  ADB+=(-s "$SERIAL")
fi

BATT=/sys/class/power_supply/max17047_battery
MAGISK_APP=com.topjohnwu.magisk

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
root() { "${ADB[@]}" shell "su -c '$*'"; }

# El reloj apaga la Wi-Fi en Doze: adb se cae y hay que reintentar (30-40 s).
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
  die "no consigo hablar con $SERIAL (¿pantalla apagada y en Doze?)"
}

# Igual que en debloat.sh: cualquier `su` despierta la app de Magisk (~53 MB) y hay
# que pararla SIN `su`, dos veces, porque magiskd la relanza de forma asíncrona.
quiet_app() {
  "${ADB[@]}" shell "am force-stop $MAGISK_APP" >/dev/null 2>&1 || true
  sleep 2
  "${ADB[@]}" shell "am force-stop $MAGISK_APP" >/dev/null 2>&1 || true
}

need_device() {
  command -v adb >/dev/null || die "adb no está en el PATH"
  [ -n "$SERIAL" ] || die "no hay dispositivo adb en estado 'device' (usa NBR_SERIAL=...)"
}

cmd_health() {
  need_device; wait_device
  say "salud (MAX17047)"
  root "cd $BATT; \
    d=\$(cat charge_full_design); f=\$(cat charge_full); \
    echo \"diseño:      \$((d/1000)) mAh\"; \
    echo \"capacidad:   \$((f/1000)) mAh  -> \$((f*100/d)) % de salud\"; \
    echo \"carga:       \$((\$(cat charge_now)/1000)) mAh  (\$(cat capacity) %)\"; \
    echo \"voltaje:     \$(cat voltage_now) uV  (OCV \$(cat voltage_ocv) uV)\"; \
    echo \"temperatura: \$((\$(cat temp)/10)) C\"; \
    echo \"corriente:   media \$((\$(cat current_avg)/1000)) mA / ahora \$((\$(cat current_now)/1000)) mA\"" \
    | tr -d '\r'
  say "ritmo de descarga (batterystats)"
  "${ADB[@]}" shell 'dumpsys batterystats' \
    | tr -d '\r' | sed -n '/^Discharge step durations:/,/^$/p' | head -12
  say "estimación del sistema"
  "${ADB[@]}" shell dumpsys batterystats \
    | tr -d '\r' | grep -E "^  (Battery time remaining|Time on battery:|Discharge:)" 
  quiet_app
}

cmd_drain() {
  need_device; wait_device
  # un solo volcado (235 KB): grep tres veces sobre el mismo fichero
  "${ADB[@]}" shell 'dumpsys batterystats > /data/local/tmp/bs.txt' >/dev/null 2>&1

  say "kernel: quién mantiene despierta la CPU"
  "${ADB[@]}" shell "sed -n '/^  All kernel wake locks:/,/^$/p' /data/local/tmp/bs.txt | head -8" 2>/dev/null | tr -d '\r'

  say "por qué se despierta (wakeup reasons)"
  "${ADB[@]}" shell "sed -n '/^  All wakeup reasons:/,/^$/p' /data/local/tmp/bs.txt | head -6" 2>/dev/null | tr -d '\r'

  say "wakelocks de apps (top)"
  "${ADB[@]}" shell "sed -n '/^  All partial wake locks:/,/^$/p' /data/local/tmp/bs.txt | head -9" 2>/dev/null | tr -d '\r'

  say "sensores activos (el acelerómetro lo mantiene com.google.android.wearable.ambient)"
  "${ADB[@]}" shell 'dumpsys sensorservice | sed -n "/^Active sensors:/,/^Socket/p" | head -8' 2>/dev/null | tr -d '\r'

  say "wi-fi"
  "${ADB[@]}" shell 'dumpsys wifi | grep -m1 "Wi-Fi is"; \
      dumpsys wifi | grep -m1 mMulticastEnabled; \
      ip -s link show wlan0 | grep -A1 "RX:"' | tr -d '\r'

  say "corriente y cpu"
  root "echo \"corriente media: \$((\$(cat $BATT/current_avg)/1000)) mA\"; \
        cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state" | tr -d '\r'
  quiet_app
}

cmd_wifi() {
  need_device; wait_device
  case "${1:-}" in
    off) say "apagando wi-fi (adb se cae hasta que vuelvas a encenderla)"
         root 'svc wifi disable'; echo done ;;
    on)  say "encendiendo wi-fi"; root 'svc wifi enable'; echo done ;;
    *)   die "uso: battery.sh wifi off|on" ;;
  esac
  quiet_app
}

# Ajustes conservadores: no quitan funciones, sólo reducen el tiempo despierto.
#   wifi_sleep_policy=1      la Wi-Fi puede dormir si no está cargando (2 = nunca duerme)
#   screen_off_timeout=15000 la pantalla se apaga en 15 s en vez de 30
#   wake_gesture_enabled=0   inútil en este firmware (ver nota): el sensor lo mantiene
#                            com.google.android.wearable.ambient y sigue activo tras reiniciar
show_tweaks() {
  "${ADB[@]}" shell 'echo "wifi_sleep_policy (2=nunca duerme):   $(settings get global wifi_sleep_policy)"; \
    echo "screen_off_timeout (ms):             $(settings get system screen_off_timeout)"; \
    echo "wake_gesture_enabled (no-op aquí):    $(settings get secure wake_gesture_enabled)"; \
    echo "screen_brightness (0-255):           $(settings get system screen_brightness)"' | tr -d '\r'
}

cmd_tweaks() {
  need_device; wait_device
  case "${1:-}" in
    "")
      say "ajustes actuales"; show_tweaks ;;
    apply)
      say "aplicando ajustes"
      root 'settings put global wifi_sleep_policy 1; \
            settings put system screen_off_timeout 15000;
            settings put secure wake_gesture_enabled 0'
      show_tweaks
      say "notas"
      echo "  pantalla: la app de Ajustes de Wear reescribe el timeout al arrancar;"
      echo "            99-watch-tune.sh lo vuelve a poner en cada boot."
      echo "  tilt-to-wake: wake_gesture_enabled no lo desactiva en NWD1.171016.002"
      echo "            ('Wrist Tilt Gesture' sigue en Active sensors). Su coste real es"
      echo "            mínimo: GazeStateEstimationWakeLock ~5 s en 30 min." ;;
    revert)
      say "volviendo a fábrica"
      root 'settings put global wifi_sleep_policy 2; \
            settings put system screen_off_timeout 30000;
            settings put secure wake_gesture_enabled 1'
      show_tweaks ;;
    *) die "uso: battery.sh tweaks [apply|revert]" ;;
  esac
  quiet_app
}

case "${1:-}" in
  health) shift; cmd_health "$@" ;;
  drain)  shift; cmd_drain "$@" ;;
  wifi)   shift; cmd_wifi "$@" ;;
  tweaks) shift; cmd_tweaks "$@" ;;
  *) cat <<'EOS'
battery.sh — salud de la batería y consumo del New Balance RunIQ.

Uso:
  ./battery.sh health        # capacidad real, temperatura, ritmo de descarga
  ./battery.sh drain         # kernel wakeups, alarmas, sensores, wi-fi
  ./battery.sh wifi off|on   # la Wi-Fi es el mayor consumidor
  ./battery.sh tweaks        # ver ajustes de consumo
  ./battery.sh tweaks apply  # wifi sleep + pantalla 15 s
  ./battery.sh tweaks revert # volver a fábrica

Serial: exporta NBR_SERIAL=<serial|ip:5555>.
EOS
     ;;
esac

