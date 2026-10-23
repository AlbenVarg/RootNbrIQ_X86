#!/usr/bin/env bash
# grant-su.sh — concede root permanente (Magisk) a una app del New Balance RunIQ sin
# tocar la pantalla del reloj (el diálogo "Superuser request" es difícil de pulsar en 400x400).
#
# Uso:
#   ./grant-su.sh --list                 # muestra las políticas actuales (uid|policy)
#   ./grant-su.sh <paquete|uid>          # concede root (policy=2) y reinicia para recargar
#   ./grant-su.sh <paquete|uid> --no-reboot   # escribe la BD pero NO reinicia
#
# Esquema real de /data/adb/magisk.db (Magisk v30.7):
#   policies (uid INT, policy INT, until INT, logging INT, notification INT, PRIMARY KEY(uid))
#   policy=2 -> permitir (allow)   policy=1 -> denegar
#
# Ojo: magiskd cachea las políticas en memoria, por eso hace falta reiniciar el reloj
# (o al menos reiniciar magiskd) para que el cambio surta efecto.
#
# Serial: exporta NBR_SERIAL=<serial|ip:5555> si tienes más de un dispositivo conectado.
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

# Cada `su` desde el shell despierta la app de Magisk (SuRequestActivity / .core.Provider),
# que ocupa ~53 MB: se vuelve a parar al terminar para no dejar el reloj cargado.
# Ojo: hay que pararla SIN `su` (el propio `su` la resucita); el shell de adb tiene permiso.
# Se mata dos veces porque magiskd la relanza de forma asíncrona tras la petición de su.
MAGISK_APP="com.topjohnwu.magisk"
quiet_app() {
  "${ADB[@]}" shell "am force-stop $MAGISK_APP" >/dev/null 2>&1 || true
  sleep 2
  "${ADB[@]}" shell "am force-stop $MAGISK_APP" >/dev/null 2>&1 || true
}

need_device() {
  command -v adb >/dev/null || die "adb no está en el PATH"
  [ -n "$SERIAL" ] || die "no hay dispositivo adb en estado 'device' (usa NBR_SERIAL=...)"
}

need_root() {
  "${ADB[@]}" shell su -c id >/dev/null 2>&1 \
    || die "su no funciona (¿magiskd caído? si 'su' da 'Illegal instruction', reinicia el reloj)"
}

uid_of() {
  local arg="$1"
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    echo "$arg"
    return
  fi
  local uid
  uid="$("${ADB[@]}" shell "dumpsys package $arg | grep -m1 userId=" | tr -dc '0-9')"
  [ -n "$uid" ] || die "no se pudo resolver el uid de '$arg' (¿está instalado?)"
  echo "$uid"
}

cmd_list() {
  need_device; need_root
  say "políticas en /data/adb/magisk.db"
  "${ADB[@]}" shell "su -c 'magisk --sqlite \"select uid,policy from policies;\"'"
  quiet_app
}

cmd_grant() {
  local arg="$1" reboot="$2" uid tmp
  need_device; need_root
  uid="$(uid_of "$arg")"
  tmp="$(mktemp -t magiskdb).db"

  say "uid de '$arg' = $uid"
  "${ADB[@]}" shell "su -c 'cp /data/adb/magisk.db /data/local/tmp/magisk.db; chmod 666 /data/local/tmp/magisk.db'"
  "${ADB[@]}" pull /data/local/tmp/magisk.db "$tmp" >/dev/null

  python3 - "$tmp" "$uid" <<'PY'
import sqlite3, sys
path, uid = sys.argv[1], int(sys.argv[2])
db = sqlite3.connect(path)
db.execute("insert or replace into policies (uid,policy,until,logging,notification) "
           "values (?,2,0,1,1)", (uid,))
db.commit()
print("policies:", list(db.execute("select uid,policy from policies")))
PY

  "${ADB[@]}" push "$tmp" /data/local/tmp/magisk.db >/dev/null
  "${ADB[@]}" shell "su -c 'cat /data/local/tmp/magisk.db > /data/adb/magisk.db; chmod 600 /data/adb/magisk.db'"
  rm -f "$tmp"

  if [ "$reboot" = "yes" ]; then
    say "reiniciando para que magiskd recargue las políticas"
    "${ADB[@]}" reboot || true
    if [[ "$SERIAL" == *:* ]]; then
      adb disconnect "$SERIAL" >/dev/null 2>&1 || true
    fi
    for _ in $(seq 1 40); do
      [[ "$SERIAL" == *:* ]] && adb connect "$SERIAL" >/dev/null 2>&1 || true
      if adb devices | awk -v s="$SERIAL" 'NR>1 && $1==s && $2=="device"' | grep -q .; then
        echo "online de nuevo"
        break
      fi
      sleep 4
    done
    sleep 15
    cmd_list || true
  else
    say "BD escrita (recuerda reiniciar el reloj para aplicarla)"
  fi
  quiet_app
}

usage() {
  cat <<'TXT'
grant-su.sh — concede root permanente (Magisk) sin tocar la pantalla del reloj.

Uso:
  ./grant-su.sh --list                        # políticas actuales (uid|policy)
  ./grant-su.sh <paquete|uid>                 # concede root (policy=2) + reinicia
  ./grant-su.sh <paquete|uid> --no-reboot     # escribe la BD pero NO reinicia

Esquema real de /data/adb/magisk.db (Magisk v30.7):
  policies (uid, policy, until, logging, notification)   policy=2 permitir / 1 denegar

magiskd cachea las políticas en memoria: sin reiniciar el reloj el cambio no aplica.
TXT
}

case "${1:-}" in
  ""|-h|--help)
    usage
    ;;
  --list)
    cmd_list
    ;;
  *)
    arg="$1"; shift || true
    reboot="yes"
    [ "${1:-}" = "--no-reboot" ] && reboot="no"
    cmd_grant "$arg" "$reboot"
    ;;
esac
