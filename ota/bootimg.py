#!/usr/bin/env python3
"""Parsea un boot.img AOSP (header v0), extrae kernel y ramdisk y reporta compresion.

Uso: python3 bootimg.py boot.img salida_dir
"""
import os
import struct
import sys
import gzip
import lzma
import zlib

HDR = struct.Struct('<8s9I16s512s32s1024s')


def sniff(data: bytes) -> str:
    if data[:2] == b'\x1f\x8b':
        return 'gzip'
    if data[:6] == b'\xfd7zXZ\x00':
        return 'xz'
    if data[:4] == b'\x04\x22\x4d\x18':
        return 'lz4'
    if data[:3] == b'\x5d\x00\x00':
        return 'lzma'
    if data[:3] == b'BZh':
        return 'bzip2'
    if data[:4] == b'\x02\x21\x4c\x18':
        return 'lz4-legacy'
    return 'raw'


def decompress(data: bytes, kind: str) -> bytes:
    if kind == 'gzip':
        return gzip.decompress(data)
    if kind == 'xz':
        return lzma.decompress(data)
    if kind == 'lzma':
        return lzma.decompress(data, format=lzma.FORMAT_ALONE)
    if kind == 'bzip2':
        import bz2
        return bz2.decompress(data)
    raise SystemExit('compresion no soportada: %s' % kind)


def main() -> None:
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    blob = open(src, 'rb').read()
    (magic, ksize, kaddr, rsize, raddr, ssize, saddr, tags, page,
     osver, name, cmdline, imgid, extra) = HDR.unpack_from(blob, 0)
    print('magic      : %r' % magic)
    print('kernel     : %d bytes @0x%x' % (ksize, kaddr))
    print('ramdisk    : %d bytes @0x%x' % (rsize, raddr))
    print('second     : %d bytes @0x%x' % (ssize, saddr))
    print('tags_addr  : 0x%x' % tags)
    print('page_size  : %d' % page)
    print('os_version : 0x%08x' % osver)
    print('name       : %r' % name.rstrip(b'\x00'))
    print('cmdline    : %r' % cmdline.rstrip(b'\x00'))
    print('image id   : %s' % imgid.hex())
    if extra.rstrip(b'\x00'):
        print('extra cmd  : %r' % extra.rstrip(b'\x00'))

    pages = lambda n: (n + page - 1) // page
    off = page
    ker = blob[off:off + ksize]
    rawoff = off + pages(ksize) * page
    rd = blob[rawoff:rawoff + rsize]

    kk = sniff(ker)
    rk = sniff(rd)
    print('kernel comp: %s' % kk)
    print('ramdisk comp: %s' % rk)

    open(os.path.join(outdir, 'kernel.' + ('gz' if kk == 'gzip' else kk)), 'wb').write(ker)
    open(os.path.join(outdir, 'ramdisk.' + ('gz' if rk == 'gzip' else rk)), 'wb').write(rd)

    try:
        kout = decompress(ker, kk)
        open(os.path.join(outdir, 'kernel.bin'), 'wb').write(kout)
        print('kernel descomprimido: %d bytes' % len(kout))
    except Exception as exc:  # noqa: BLE001
        print('no pude descomprimir kernel: %s' % exc)

    try:
        rout = decompress(rd, rk)
        open(os.path.join(outdir, 'ramdisk.cpio'), 'wb').write(rout)
        print('ramdisk descomprimido: %d bytes' % len(rout))
    except Exception as exc:  # noqa: BLE001
        print('no pude descomprimir ramdisk: %s' % exc)


if __name__ == '__main__':
    main()
