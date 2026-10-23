#!/usr/bin/env bash
# fix-selinux-data.sh - deja que `su` pueda escribir en /data/data en el NBRiq
#
# En esta ROM `su -c` ejecuta los comandos en el dominio SELinux `shell`, al que
# la politica no le deja crear ficheros ni hacer chmod/chown dentro de
# /data/data (system_data_file / app_data_file). Con esto se anaden las reglas
# en caliente.
#
# OJO: no persiste. Se pierde al reiniciar (y esta bien que sea asi: no queremos
# dejar el reloj con SELinux mas flojo de lo normal). Vuelve a ejecutarlo cuando
# lo necesites.
#
# Uso:  ./scripts/fix-selinux-data.sh
#       ADB="adb -s 10.0.0.132:5555" ./scripts/fix-selinux-data.sh
set -uo pipefail

ADB="${ADB:-adb}"
MP="/data/adb/magisk/magiskpolicy"

die() { echo "ERROR: $*" >&2; exit 1; }

$ADB shell true 2>/dev/null || die "no hay reloj conectado (adb devices)"

cat > /tmp/nbriq-fixpolicy.sh <<'EOS'
#!/system/bin/sh
# Sintaxis de este magiskpolicy: allow <src> <tgt> <clase> { permisos }
# (sin ":" entre tipo y clase; "file"/"dir" son clases, no tipos)
MP=/data/adb/magisk/magiskpolicy
[ -x "$MP" ] || { echo "no encuentro $MP"; exit 1; }
rc=0
for DOM in shell magisk; do
  "$MP" --live \
    "allow $DOM system_data_file dir { create write read search setattr add_name remove_name rmdir }" \
    "allow $DOM system_data_file file { create write read getattr setattr unlink rename }" \
    "allow $DOM system_data_file lnk_file { create read getattr setattr unlink }" \
    "allow $DOM app_data_file dir { create write read search setattr add_name remove_name rmdir }" \
    "allow $DOM app_data_file file { create write read getattr setattr unlink rename }" \
    "allow $DOM app_data_file lnk_file { create read getattr setattr unlink }"
  r=$?
  echo "  dominio $DOM -> rc=$r"
  [ "$r" -eq 0 ] || rc=1
done
# prueba de fuego: crear y borrar un fichero en /data/data
if mkdir -p /data/data/zz-selinux-test 2>/dev/null && echo ok > /data/data/zz-selinux-test/a 2>/dev/null; then
  echo "  prueba: escribir en /data/data -> OK"
  rm -rf /data/data/zz-selinux-test
else
  echo "  prueba: escribir en /data/data -> FALLA"
  rc=1
fi
exit $rc
EOS

$ADB push /tmp/nbriq-fixpolicy.sh /data/local/tmp/fixpolicy.sh >/dev/null || die "no pude subir el script"
echo "Cargando reglas SELinux en el reloj..."
$ADB shell "su -c 'sh /data/local/tmp/fixpolicy.sh'"
echo
echo "Recuerda: no persiste. Tras reiniciar, vuelve a lanzarlo."
