#!/usr/bin/env python3
"""Genera boot.img parcheados a partir de boot-stock.img.

Ejemplos:
  # root por adb (ro.secure=0, ro.debuggable=1): shell root en u:r:su:s0
  python3 mkpatch.py --debug-adb boot-stock.img boot-root-adb.img

  # reemplazar/anadir ficheros arbitrarios en el ramdisk
  python3 mkpatch.py --add sbin/magiskinit=magisk/x86/magiskinit boot.img out.img
"""
import argparse
import sys

import bootimg_pack as bp
import cpio

PATCH_PROPS = {
    b'ro.secure=1': b'ro.secure=0',
    b'ro.debuggable=0': b'ro.debuggable=1',
    b'ro.adb.secure=1': b'ro.adb.secure=0',
}


def patch_props(entry: cpio.Entry, verbose: bool = True) -> int:
    lines = entry.data.split(b'\n')
    changed = 0
    for i, line in enumerate(lines):
        s = line.strip()
        if s in PATCH_PROPS:
            lines[i] = PATCH_PROPS[s]
            changed += 1
            if verbose:
                print('  %s -> %s' % (s.decode(), PATCH_PROPS[s].decode()))
    entry.data = b'\n'.join(lines)
    return changed


def build(boot_src: str, out: str, debug_adb: bool = False, adds=None) -> str:
    blob = open(boot_src, 'rb').read()
    h, kernel, ramdisk_gz, second, dt = bp.split_image(blob)
    level = bp.find_gzip_level(ramdisk_gz, bp.gunzip(ramdisk_gz)) or 6
    entries = cpio.parse(bp.gunzip(ramdisk_gz))
    print('ramdisk: %d entradas, gzip nivel %d' % (len(entries), level))

    if debug_adb:
        e = cpio.find(entries, 'default.prop')
        if e is None:
            sys.exit('no hay default.prop en el ramdisk')
        print('parcheando default.prop:')
        if patch_props(e) == 0:
            sys.exit('no se cambio ninguna propiedad (default.prop inesperado)')

    for name, path in (adds or []):
        data = open(path, 'rb').read()
        e = cpio.find(entries, name)
        if e is None:
            entries.insert(len(entries) - 1, cpio.Entry(name, 0o100750, data))
            print('  + %s (%d bytes)' % (name, len(data)))
        else:
            e.data = data
            print('  ~ %s (%d bytes)' % (name, len(data)))

    new_cpio = cpio.build(entries, pad=True)
    new_gz = bp.gzip_with(level, new_cpio)
    image = bp.build_image(h, kernel, new_gz, second, dt)
    open(out, 'wb').write(image)
    print('escrito %s (%d bytes, ramdisk %d bytes -> %d gz)'
          % (out, len(image), len(new_cpio), len(new_gz)))
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('boot_src')
    ap.add_argument('out')
    ap.add_argument('--debug-adb', action='store_true',
                    help='ro.secure=0 / ro.debuggable=1 / ro.adb.secure=0')
    ap.add_argument('--add', action='append', default=[], metavar='NOMBRE=RUTA',
                    help='fichero del host a colocar en el ramdisk')
    a = ap.parse_args()
    adds = []
    for spec in a.add:
        name, _, path = spec.partition('=')
        adds.append((name, path))
    build(a.boot_src, a.out, a.debug_adb, adds)
