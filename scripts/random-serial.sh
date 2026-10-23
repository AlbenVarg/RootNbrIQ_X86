#!/usr/bin/env bash
# random-serial.sh - cambia el serial que reporta el reloj por uno aleatorio
#
# Para que? El serial real identifica el dispositivo: aparece en `adb devices`, en
# capturas y en cualquier log que publiques. Con esto el reloj reporta otro valor.
#
# Como funciona? Magisk puede reescribir propiedades de solo lectura
# (`magisk resetprop -n ro.serialno ...`). Para que aguante los reinicios se deja
# un script en /data/adb/post-fs-data.d/ que se ejecuta antes de que arranquen
# las apps.
#
# Uso:
#   ./scripts/random-serial.sh              # genera uno aleatorio, lo instala y lo aplica
#   ./scripts/random-serial.sh BIXXXXXXXXXXXX   # usa ese valor
#   ./scripts/random-serial.sh --show       # que serial reporta ahora el reloj
#   ./scripts/random-serial.sh --remove     # quita el script (tras reiniciar vuelve el real)
#
# OJO: el descriptor USB lo fija el kernel desde la linea de comandos del
# bootloader, asi que `adb devices -l` **por USB** puede seguir mostrando el
# original. Por Wi-Fi aparece IP:puerto, no el serial.
set -uo pipefail

ADB="${ADB:-adb}"
BOOT_SCRIPT="/data/adb/post-fs-data.d/00-random-serial.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
sh_() { $ADB shell "$@" 2>/dev/null | tr -d '\r'; }
su_() { $ADB shell "su -c \"$1\"" 2>/dev/null | tr -d '\r'; }

$ADB shell true 2>/dev/null || die "no hay reloj conectado (adb devices)"
su_ 'id -u' | grep -q 0 || die "hace falta root (Magisk) en el reloj"

case "${1:-}" in
  --show)
    echo "ro.serialno      : $(sh_ getprop ro.serialno)"
    echo "ro.boot.serialno : $(sh_ getprop ro.boot.serialno)"
    echo "script de arranque: $(su_ "ls -l $BOOT_SCRIPT 2>/dev/null" | awk '{print $NF" "$5" bytes"}')"
    exit 0
    ;;
  --remove)
    su_ "rm -f $BOOT_SCRIPT"
    echo "Quitado $BOOT_SCRIPT"
    echo "El serial real volvera en el proximo reinicio (ahora mismo sigue el de la prop)."
    exit 0
    ;;
  "")  NEW="BI$(python3 -c 'import secrets,string;print("".join(secrets.choice(string.ascii_uppercase+string.digits) for _ in range(12)))')" ;;
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)   NEW="$1" ;;
esac

echo "$NEW" | grep -Eq '^[A-Z0-9]{8,20}$' || die "serial poco realista: usa A-Z y 0-9 (8-20 caracteres)"

echo "Serial nuevo: $NEW"

# 1) aplicarlo ya (sin reiniciar)
su_ "magisk resetprop -n ro.serialno $NEW; magisk resetprop -n ro.boot.serialno $NEW"

# 2) dejarlo persistente: script que Magisk ejecuta en cada arranque
cat > /tmp/nbriq-random-serial.sh <<EOS
#!/system/bin/sh
# Oculta el serial real del reloj (instalado por RootNbrIQ_X86)
NEW_SERIAL="$NEW"
MAGISK=""
for c in /data/adb/magisk/magisk /sbin/magisk magisk; do
  [ -x "\$c" ] && MAGISK="\$c" && break
done
[ -n "\$MAGISK" ] || exit 1
"\$MAGISK" resetprop -n ro.serialno "\$NEW_SERIAL"
"\$MAGISK" resetprop -n ro.boot.serialno "\$NEW_SERIAL"
EOS

$ADB push /tmp/nbriq-random-serial.sh /data/local/tmp/00-random-serial.sh >/dev/null || die "no pude subir el script"
su_ "mkdir -p /data/adb/post-fs-data.d"
su_ "cp /data/local/tmp/00-random-serial.sh $BOOT_SCRIPT && chmod 755 $BOOT_SCRIPT" || die "no pude instalar el script"
su_ "rm -f /data/local/tmp/00-random-serial.sh"

# 3) verificar
AHORA=$(sh_ getprop ro.serialno)
echo
echo "El reloj reporta ahora: $AHORA"
if [ "$AHORA" = "$NEW" ]; then
  echo "OK. Se mantendra tras reiniciar (comprueba con: $0 --show)."
else
  die "no ha cuajado: sigue diciendo '$AHORA'"
fi
echo
echo "Recuerda: por USB, 'adb devices -l' puede seguir mostrando el serial del bootloader."
