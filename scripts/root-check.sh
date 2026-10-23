#!/usr/bin/env bash
# root-check.sh - estado del root del NBRiq en un vistazo
#
# Uso:  ./scripts/root-check.sh
#       ADB="adb -s 10.0.0.132:5555" ./scripts/root-check.sh
set -uo pipefail

ADB="${ADB:-adb}"
sh_() { $ADB shell "$@" 2>/dev/null | tr -d '\r'; }
su_() { $ADB shell "su -c \"$1\"" 2>/dev/null | tr -d '\r'; }

$ADB shell true 2>/dev/null || { echo "ERROR: no hay reloj conectado"; exit 1; }

echo "=== dispositivo ==="
echo "modelo    : $(sh_ getprop ro.product.model) ($(sh_ getprop ro.product.device))"
echo "android   : $(sh_ getprop ro.build.version.release) / API $(sh_ getprop ro.build.version.sdk)"
echo "build     : $(sh_ getprop ro.build.id)  tipo=$(sh_ getprop ro.build.type)  debuggable=$(sh_ getprop ro.debuggable)"
echo "bootloader: $(sh_ getprop ro.bootloader)"
echo "serial    : $(sh_ getprop ro.serialno)"
echo "bootreason: $(sh_ getprop ro.boot.bootreason)"

echo
echo "=== root (su) ==="
ID=$(su_ 'id')
if echo "$ID" | grep -q 'uid=0'; then
  echo "su        : OK  ->  $ID"
else
  echo "su        : NO responde o no da root (¿magiskd caído? reinicia el reloj)"
  exit 1
fi
echo "magisk    : $(su_ 'magisk -v')   path=$(su_ 'magisk --path')"
echo "selinux   : enforcing=$(su_ 'cat /sys/fs/selinux/enforce')  (1 = activo)"

echo
echo "=== politicas de root concedidas (magisk.db) ==="
POL=$($ADB shell 'su -c "magisk --sqlite \"select uid,policy from policies\""' 2>/dev/null | tr -d '\r')
if [ -n "$POL" ]; then
  echo "$POL" | sed 's/^/  /'
  echo "  (policy=2 permitir, 0 preguntar, 1 denegar)"
else
  echo "  (ninguna, o magiskd no responde -> prueba ./scripts/grant-su.sh --list)"
fi

echo
echo "=== modulos ==="
MODS=$(su_ 'ls /data/adb/modules 2>/dev/null')
[ -n "$MODS" ] && echo "$MODS" | sed 's/^/  /' || echo "  (ninguno)"

echo
echo "=== script de arranque propio ==="
sh_ ls -l /data/adb/service.d/ | sed 's/^/  /'
echo "  prop nbr.tune.start = $(sh_ getprop nbr.tune.start)"
echo "  prop nbr.tune.done  = $(sh_ getprop nbr.tune.done)"

echo
echo "=== memoria ==="
sh_ cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable' | sed 's/  */ /g; s/^/  /'
