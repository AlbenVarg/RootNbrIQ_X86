#!/bin/sh
# Variante "slim": igual que run_patch.sh pero sin .backup/init.xz (516 KB) para que
# la imagen quepa en la particion boot (ultima imagen conocida: 9.154.560 B).
# El respaldo del init original no es necesario para arrancar; el boot.img stock
# verificado (sha1 99a5980...) hace de respaldo permanente.
set -e
cd /w

export KEEPVERITY=false
export KEEPFORCEENCRYPT=false

rm -f kernel ramdisk.cpio second ramdisk.cpio.orig new-boot.img
./magiskboot unpack boot-stock.img > /dev/null

./magiskboot compress=xz magisk magisk.xz
./magiskboot compress=xz stub.apk stub.xz
./magiskboot compress=xz init-ld init-ld.xz

cat > config <<EOF
KEEPVERITY=false
KEEPFORCEENCRYPT=false
RECOVERYMODE=false
VENDORBOOT=false
EOF

cp -f ramdisk.cpio ramdisk.cpio.orig

./magiskboot cpio ramdisk.cpio \
  "add 0750 init magiskinit" \
  "mkdir 0750 overlay.d" \
  "mkdir 0750 overlay.d/sbin" \
  "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
  "add 0644 overlay.d/sbin/stub.xz stub.xz" \
  "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
  "patch" \
  "backup ramdisk.cpio.orig" \
  "mkdir 000 .backup" \
  "add 000 .backup/.magisk config" \
  "rm .backup/init.xz"

./magiskboot repack boot-stock.img new-boot-slim.img > /tmp/repack.log 2>&1
grep -E 'RAMDISK_SZ' /tmp/repack.log
ls -l new-boot-slim.img
