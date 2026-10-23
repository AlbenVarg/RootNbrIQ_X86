#!/usr/bin/env python3
"""Diagnostico de un patch IMGDIFF2: lista chunks y valida los bloques bsdiff."""
import bz2
import struct
import sys

import imgpatch

old = open(sys.argv[1], 'rb').read()
p = open(sys.argv[2], 'rb').read()
print('magic %r  chunks %d  old %d' % (p[:8], struct.unpack_from('<i', p, 8)[0], len(old)))

pos = 12
for i in range(struct.unpack_from('<i', p, 8)[0]):
    t = struct.unpack_from('<i', p, pos)[0]
    pos += 4
    if t == 0:
        s, l, po = struct.unpack_from('<qqq', p, pos)
        pos += 24
        print('chunk %d NORMAL  src=%d+%d patchoff=%d' % (i, s, l, po))
    elif t == 3:
        dl = struct.unpack_from('<i', p, pos)[0]
        pos += 4 + dl
        print('chunk %d RAW     len=%d' % (i, dl))
        continue
    elif t == 2:
        s, l, po, el = struct.unpack_from('<qqqq', p, pos)
        lv, me, wb, ml, st = struct.unpack_from('<iiiii', p, pos + 40)
        pos += 60
        print('chunk %d DEFLATE src=%d+%d patchoff=%d expanded=%d zlib(level=%d,method=%d,wbits=%d,mem=%d,strat=%d)'
              % (i, s, l, po, el, lv, me, wb, ml, st))
    else:
        print('chunk %d tipo %d DESCONOCIDO' % (i, t))
        break

    if p[po:po + 8] != b'BSDIFF40':
        print('   !! sin BSDIFF40: %r' % p[po:po + 12])
        continue
    cl = imgpatch.offtin(p[po + 8:po + 16])
    dl = imgpatch.offtin(p[po + 16:po + 24])
    ns = imgpatch.offtin(p[po + 24:po + 32])
    ctrl = bz2.decompress(p[po + 32:po + 32 + cl])
    diff = bz2.decompress(p[po + 32 + cl:po + 32 + cl + dl])
    extra = p[po + 32 + cl + dl:]
    print('   bsdiff ctrl=%d diff=%d new=%d | descomprimido ctrl=%d diff=%d extra_disp=%d | restante_en_archivo=%d'
          % (cl, dl, ns, len(ctrl), len(diff), len(extra), len(p) - (po + 32 + cl + dl)))
    npos = dpos = epos = 0
    triples = 0
    while npos < ns:
        x = imgpatch.offtin(ctrl[triples * 24:triples * 24 + 8])
        y = imgpatch.offtin(ctrl[triples * 24 + 8:triples * 24 + 16])
        z = imgpatch.offtin(ctrl[triples * 24 + 16:triples * 24 + 24])
        triples += 1
        if triples < 4 or npos + x + y >= ns:
            print('     ctrl#%d x=%d y=%d z=%d (npos=%d dpos=%d epos=%d)' % (triples, x, y, z, npos, dpos, epos))
        npos += x + y
        dpos += x
        epos += y
    print('   totales: triples=%d diff_usado=%d/%d extra_usado=%d/%d fin_npos=%d/%d'
          % (triples, dpos, len(diff), epos, len(extra), npos, ns))
