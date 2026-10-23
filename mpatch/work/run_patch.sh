#!/bin/sh
# Replica la secuencia de assets/boot_patch.sh de Magisk v30.7 para ABI x86 (32-bit).
# Se ejecuta dentro de un contenedor linux/386 (magiskboot es un ELF bionic estatico).
#
# Antes de ejecutarlo hace falta la imagen stock en este directorio (no se versiona
# dos veces; en ota/ esta la buena):
#     cp ../ota/boot-stock.img .
set -e
cd /w

export KEEPVERITY=false
export KEEPFORCEENCRYPT=false

echo "== unpack =="
./magiskboot unpack boot-stock.img

echo "== cpio test (0 = stock) =="
./magiskboot cpio ramdisk.cpio test

echo "== comprimir fragmentos =="
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

echo "== parchear ramdisk =="
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
  "add 000 .backup/.magisk config"

echo "== repack =="
./magiskboot repack boot-stock.img new-boot.img

echo "== resultado =="
ls -l new-boot.img
