#!/usr/bin/env python3
"""Aplica un patch IMGDIFF2 (formato de las OTA de Android) sin necesitar el updater.

Referencia: bootable/recovery/applypatch/imgpatch.cpp (Android 7.1.2).

Formato:
  "IMGDIFF2" (8) + num_chunks (int32 LE)
  por cada chunk: type (int32 LE)
    CHUNK_NORMAL  (0): src_start, src_len, patch_offset (3 x int64 LE) + bsdiff embebido
    CHUNK_DEFLATE (2): 60 bytes de cabecera (4 x int64 + 7 int32 de zlib) + bsdiff
    CHUNK_RAW     (3): data_len (int32) + datos crudos

Uso: python3 imgpatch.py <viejo.img> <patch> <salida.img> [--sha1 esperado]
"""
import bz2
import hashlib
import struct
import sys
import zlib

CHUNK_NORMAL = 0
CHUNK_DEFLATE = 2
CHUNK_RAW = 3


def offtin(buf: bytes) -> int:
    """Lee un int64 con signo y magnitud (formato bsdiff)."""
    y = buf[7] & 0x7F
    for i in (6, 5, 4, 3, 2, 1, 0):
        y = y * 256 + buf[i]
    return -y if buf[7] & 0x80 else y


def bspatch(old: bytes, patch: bytes, offset: int = 0) -> bytes:
    """Aplica un BSDIFF40 almacenado dentro de `patch` a partir de `offset`."""
    if patch[offset:offset + 8] != b'BSDIFF40':
        raise ValueError('no encontre cabecera BSDIFF40 en offset %d (%r)'
                         % (offset, patch[offset:offset + 8]))
    ctrl_len = offtin(patch[offset + 8:offset + 16])
    diff_len = offtin(patch[offset + 16:offset + 24])
    new_size = offtin(patch[offset + 24:offset + 32])

    pos = offset + 32
    ctrl = bz2.decompress(patch[pos:pos + ctrl_len])
    pos += ctrl_len
    diff = bz2.decompress(patch[pos:pos + diff_len])
    pos += diff_len
    # El bloque "extra" tambien va comprimido con bzip2 (ver bspatch.cpp de AOSP).
    # Puede haber datos de otros blobs despues del fin de stream, asi que usamos
    # un descompresor que se detiene solo en EOF del stream.
    d = bz2.BZ2Decompressor()
    try:
        extra = d.decompress(patch[pos:])
    except OSError:
        extra = b''

    new = bytearray(new_size)
    oldpos = newpos = diffpos = 0
    cpos = 0
    extrapos = 0
    while newpos < new_size:
        x = offtin(ctrl[cpos:cpos + 8])
        y = offtin(ctrl[cpos + 8:cpos + 16])
        z = offtin(ctrl[cpos + 16:cpos + 24])
        cpos += 24
        if newpos + x > new_size:
            raise ValueError('ctrl invalido')
        for i in range(x):
            add = old[oldpos + i] if 0 <= oldpos + i < len(old) else 0
            new[newpos + i] = (diff[diffpos + i] + add) & 0xFF
        newpos += x
        oldpos += x
        diffpos += x
        if newpos + y > new_size:
            raise ValueError('extra invalido')
        new[newpos:newpos + y] = extra[extrapos:extrapos + y]
        extrapos += y
        newpos += y
        oldpos += z
    return bytes(new)


def apply(old: bytes, patch: bytes) -> bytes:
    if patch[:8] != b'IMGDIFF2':
        raise ValueError('magic distinto de IMGDIFF2: %r' % patch[:8])
    num_chunks = struct.unpack_from('<i', patch, 8)[0]
    out = bytearray()
    pos = 12
    for i in range(num_chunks):
        ctype = struct.unpack_from('<i', patch, pos)[0]
        pos += 4
        if ctype == CHUNK_NORMAL:
            src_start, src_len, patch_offset = struct.unpack_from('<qqq', patch, pos)
            pos += 24
            out += bspatch(old[src_start:src_start + src_len], patch, patch_offset)
        elif ctype == CHUNK_RAW:
            data_len = struct.unpack_from('<i', patch, pos)[0]
            pos += 4
            out += patch[pos:pos + data_len]
            pos += data_len
        elif ctype == CHUNK_DEFLATE:
            (src_start, src_len, patch_offset,
             expanded_len) = struct.unpack_from('<qqqq', patch, pos)
            level, method, wbits, memlevel, strategy = struct.unpack_from(
                '<iiiii', patch, pos + 40)
            pos += 60
            raw = old[src_start:src_start + src_len]
            src = zlib.decompressobj(-15).decompress(raw, expanded_len)
            if len(src) != expanded_len:
                raise ValueError('chunk %d: expansio %d != %d'
                                 % (i, len(src), expanded_len))
            dst = bspatch(src, patch, patch_offset)
            if level == 0:
                out += dst
                continue
            comp = zlib.compressobj(level, method, wbits, memlevel, strategy)
            out += comp.compress(dst) + comp.flush()
        else:
            raise ValueError('chunk %d de tipo desconocido %d' % (i, ctype))
    return bytes(out)


def main() -> None:
    old_path, patch_path, out_path = sys.argv[1:4]
    expected = None
    if '--sha1' in sys.argv:
        expected = sys.argv[sys.argv.index('--sha1') + 1]

    old = open(old_path, 'rb').read()
    patch = open(patch_path, 'rb').read()
    new = apply(old, patch)
    open(out_path, 'wb').write(new)

    digest = hashlib.sha1(new).hexdigest()
    print('entrada : %s (%d bytes, sha1 %s)'
          % (old_path, len(old), hashlib.sha1(old).hexdigest()))
    print('patch   : %s (%d bytes)' % (patch_path, len(patch)))
    print('salida  : %s (%d bytes, sha1 %s)' % (out_path, len(new), digest))
    if expected:
        print('esperado: %s -> %s' % (expected, 'OK' if digest == expected else 'NO COINCIDE'))
        if digest != expected:
            sys.exit(1)


if __name__ == '__main__':
    main()
