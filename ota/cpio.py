#!/usr/bin/env python3
"""Lector/escritor de ramdisks cpio formato "newc" (070701), como los del boot.img."""
import struct
import sys

MAGIC = b'070701'
TRAILER = 'TRAILER!!!'


class Entry:
    __slots__ = ('name', 'ino', 'mode', 'uid', 'gid', 'nlink', 'mtime', 'devmajor',
                 'devminor', 'rdevmajor', 'rdevminor', 'data')

    def __init__(self, name='', mode=0o100644, data=b'', ino=0, uid=0, gid=0,
                 nlink=1, mtime=0, devmajor=0, devminor=0, rdevmajor=0, rdevminor=0):
        self.name = name
        self.mode = mode
        self.data = data
        self.ino = ino
        self.uid = uid
        self.gid = gid
        self.nlink = nlink
        self.mtime = mtime
        self.devmajor = devmajor
        self.devminor = devminor
        self.rdevmajor = rdevmajor
        self.rdevminor = rdevminor

    @property
    def is_dir(self):
        return (self.mode & 0o170000) == 0o040000

    @property
    def is_symlink(self):
        return (self.mode & 0o170000) == 0o120000

    def __repr__(self):
        return '<Entry %s mode=%o size=%d>' % (self.name, self.mode, len(self.data))


def parse(data: bytes) -> list:
    """Devuelve la lista de entradas del cpio newc (incluye TRAILER!!!)."""
    entries = []
    off = 0
    while off + 110 <= len(data):
        if data[off:off + 6] != MAGIC:
            raise ValueError('no es un cpio newc en el offset %d' % off)
        f = [int(data[off + 6 + i * 8:off + 14 + i * 8], 16) for i in range(13)]
        (ino, mode, uid, gid, nlink, mtime, size, devmajor, devminor,
         rdevmajor, rdevminor, namesize, _check) = f
        name_start = off + 110
        name = data[name_start:name_start + namesize - 1].decode('utf-8', 'surrogateescape')
        data_start = (name_start + namesize + 3) & ~3
        blob = data[data_start:data_start + size]
        off = (data_start + size + 3) & ~3
        entries.append(Entry(name, mode, blob, ino, uid, gid, nlink, mtime,
                             devmajor, devminor, rdevmajor, rdevminor))
        if name == TRAILER:
            break
    return entries


def build(entries: list, pad: bool = True) -> bytes:
    """Serializa las entradas a cpio newc (anade TRAILER!!! si falta)."""
    out = bytearray()
    names = [e.name for e in entries]
    if TRAILER not in names:
        entries = list(entries) + [Entry(TRAILER, 0)]
    for e in entries:
        nb = e.name.encode('utf-8', 'surrogateescape') + b'\x00'
        fields = (e.ino, e.mode, e.uid, e.gid, e.nlink, e.mtime, len(e.data),
                  e.devmajor, e.devminor, e.rdevmajor, e.rdevminor, len(nb), 0)
        out += MAGIC + b''.join(b'%08X' % v for v in fields)
        out += nb
        out += b'\x00' * ((-len(out)) % 4)
        out += e.data
        out += b'\x00' * ((-len(out)) % 4)
    if pad:
        # el kernel espera el final del ramdisk alineado a 512 (padding de initramfs)
        out += b'\x00' * ((-len(out)) % 512)
    return bytes(out)


def find(entries: list, name: str):
    for e in entries:
        if e.name == name:
            return e
    return None


def listing(entries: list, limit: int = 40) -> str:
    lines = []
    for e in entries[:limit]:
        kind = 'd' if e.is_dir else ('l' if e.is_symlink else '-')
        lines.append('%s %06o %8d %s%s' % (kind, e.mode & 0o7777, len(e.data), e.name,
                                          '' if kind != 'l' else ' -> ' + e.data.decode('utf-8', 'replace')))
    if len(entries) > limit:
        lines.append('... (%d entradas)' % len(entries))
    return '\n'.join(lines)


if __name__ == '__main__':
    ents = parse(open(sys.argv[1], 'rb').read())
    if len(sys.argv) > 2 and sys.argv[2] == 'cat':
        e = find(ents, sys.argv[3])
        if e is None:
            sys.exit('no existe %s' % sys.argv[3])
        sys.stdout.write(e.data.decode('utf-8', 'replace'))
    else:
        print('%d entradas, %d bytes totales' % (len(ents), sum(len(e.data) for e in ents)))
        print(listing(ents, int(sys.argv[2]) if len(sys.argv) > 2 else 40))
