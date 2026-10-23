#!/usr/bin/env python3
"""Crea el zip de prueba sideload (update-binary + updater-script) para el NBRiq."""
import zipfile

ZIP = 'nbriq-probe.zip'

entries = [
    ('META-INF/com/google/android/update-binary', open('update-binary', 'rb').read(), 0o755),
    ('META-INF/com/google/android/updater-script', b'# dummy\n', 0o644),
]

with zipfile.ZipFile(ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data, mode in entries:
        zi = zipfile.ZipInfo(name)
        zi.external_attr = mode << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(zi, data)

print('zip creado: %s' % ZIP)
