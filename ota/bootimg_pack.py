#!/usr/bin/env python3
"""Desempaqueta/empaqueta boot.img (header v0) y reproduce el gzip del ramdisk.

Uso:
  python3 bootimg_pack.py unpack <boot.img> <dir>
  python3 bootimg_pack.py pack   <boot.img-original> <dir> <salida.img>
"""
import hashlib
import os
import struct
import sys
import zlib

HDR_FMT = '<8s10I16s512s32s1024s'
HDR_SIZE = struct.calcsize(HDR_FMT)  # 1632
FIELDS = ('magic', 'kernel_size', 'kernel_addr', 'ramdisk_size', 'ramdisk_addr',
          'second_size', 'second_addr', 'tags_addr', 'page_size', 'dt_size',
          'unused', 'name', 'cmdline', 'id', 'extra_cmdline')


def parse_header(blob: bytes) -> dict:
    return dict(zip(FIELDS, struct.unpack_from(HDR_FMT, blob, 0)))


def pages(n: int, page: int) -> int:
    return (n + page - 1) // page


def gunzip(data: bytes) -> bytes:
    return zlib.decompress(data, 16 + zlib.MAX_WBITS)


def gzip_with(level: int, data: bytes, mtime: int = 0, os_byte: int = 3) -> bytes:
    """Genera un gzip byte a byte controlable (header propio + deflate crudo)."""
    co = zlib.compressobj(level, zlib.DEFLATED, -15, 8, zlib.Z_DEFAULT_STRATEGY)
    body = co.compress(data) + co.flush()
    xfl = 2 if level == 9 else (4 if level == 1 else 0)
    header = bytes([0x1F, 0x8B, 0x08, 0x00]) + struct.pack('<I', mtime) + bytes([xfl, os_byte])
    trailer = struct.pack('<II', zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF)
    return header + body + trailer


def find_gzip_level(compressed: bytes, plain: bytes) -> int:
    """Busca el nivel de compresion que reproduce exactamente el gzip original."""
    for level in range(1, 10):
        if gzip_with(level, plain) == compressed:
            return level
    return 0


def split_image(blob: bytes) -> tuple[dict, bytes, bytes, bytes, bytes]:
    h = parse_header(blob)
    page = h['page_size']
    off = page
    kernel = blob[off:off + h['kernel_size']]
    off += pages(h['kernel_size'], page) * page
    ramdisk = blob[off:off + h['ramdisk_size']]
    off += pages(h['ramdisk_size'], page) * page
    second = blob[off:off + h['second_size']]
    off += pages(h['second_size'], page) * page
    dt = blob[off:off + h['dt_size']]
    return h, kernel, ramdisk, second, dt


def image_id(kernel: bytes, ramdisk: bytes, second: bytes) -> bytes:
    h = hashlib.sha1()
    h.update(kernel)
    h.update(struct.pack('<I', len(kernel)))
    h.update(ramdisk)
    h.update(struct.pack('<I', len(ramdisk)))
    h.update(second)
    h.update(struct.pack('<I', len(second)))
    return bytes.fromhex(h.hexdigest() + '0' * 24)


def build_image(h: dict, kernel: bytes, ramdisk: bytes, second: bytes, dt: bytes,
                image_id_bytes: bytes = None) -> bytes:
    page = h['page_size']
    hid = image_id_bytes if image_id_bytes is not None else image_id(kernel, ramdisk, second)
    header = struct.pack(
        HDR_FMT, b'ANDROID!', len(kernel), h['kernel_addr'], len(ramdisk),
        h['ramdisk_addr'], len(second), h['second_addr'], h['tags_addr'], page,
        len(dt), h['unused'], h['name'], h['cmdline'], hid, h['extra_cmdline'])
    out = bytearray(header)
    out += b'\x00' * (page - len(out) % page if len(out) % page else 0)
    for part in (kernel, ramdisk, second, dt):
        if not part:
            continue
        out += part
        rem = len(part) % page
        if rem:
            out += b'\x00' * (page - rem)
    return bytes(out)


def do_unpack(src: str, outdir: str) -> None:
    blob = open(src, 'rb').read()
    h, kernel, ramdisk, second, dt = split_image(blob)
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, 'kernel'), 'wb').write(kernel)
    open(os.path.join(outdir, 'kernel.gz'), 'wb').write(kernel) if kernel[:2] == b'\x1f\x8b' else None
    open(os.path.join(outdir, 'ramdisk.gz'), 'wb').write(ramdisk)
    if second:
        open(os.path.join(outdir, 'second'), 'wb').write(second)
    if dt:
        open(os.path.join(outdir, 'dt'), 'wb').write(dt)
    plain = gunzip(ramdisk)
    open(os.path.join(outdir, 'ramdisk.cpio'), 'wb').write(plain)
    level = find_gzip_level(ramdisk, plain)
    print('kernel %d  ramdisk %d (gz)  second %d  dt %d  page %d'
          % (len(kernel), len(ramdisk), len(second), len(dt), h['page_size']))
    print('nivel de gzip del ramdisk: %s' % (level if level else 'no reproducible'))
    open(os.path.join(outdir, 'gzip_level'), 'w').write(str(level))
    return level


def do_pack(src: str, indir: str, out: str) -> None:
    blob = open(src, 'rb').read()
    h, kernel, ramdisk, second, dt = split_image(blob)
    level = int(open(os.path.join(indir, 'gzip_level')).read().strip() or 0) or 6
    cpio = open(os.path.join(indir, 'ramdisk.cpio'), 'rb').read()
    ramdisk = gzip_with(level, cpio)
    image = build_image(h, kernel, ramdisk, second, dt)
    open(out, 'wb').write(image)
    print('escrito %s (%d bytes) ramdisk %d' % (out, len(image), len(ramdisk)))


if __name__ == '__main__':
    if sys.argv[1] == 'unpack':
        do_unpack(sys.argv[2], sys.argv[3])
    else:
        do_pack(sys.argv[2], sys.argv[3], sys.argv[4])
