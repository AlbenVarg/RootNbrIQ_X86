#!/usr/bin/env python3
"""Extrae la version de kernel de un bzImage (x86) buscando payload gzip/xz."""
import gzip
import lzma
import re
import sys

blob = open(sys.argv[1], 'rb').read()
found = False

for magic, kind in ((b'\x1f\x8b\x08', 'gzip'), (b'\xfd7zXZ\x00', 'xz')):
    start = 0
    while True:
        pos = blob.find(magic, start)
        if pos < 0:
            break
        start = pos + 1
        try:
            data = gzip.decompress(blob[pos:]) if kind == 'gzip' else lzma.decompress(blob[pos:])
        except Exception:
            continue
        m = re.search(rb'Linux version [^\x00]{0,200}', data)
        if m:
            print('%s @0x%x -> %s' % (kind, pos, m.group(0).decode('utf-8', 'replace')))
            found = True
            break
    if found:
        break

if not found:
    print('no encontre version de kernel')
