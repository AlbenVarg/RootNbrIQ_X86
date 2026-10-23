# SELinux en el NBRiq: `su` corre en el dominio `shell`

Resumen: en esta ROM (Android 7.1.1, Magisk v30.7) **`su -c` ejecuta los comandos en el
dominio `shell`**, no en `magisk`. `id` dice `uid=0(root)` y `context=u:r:magisk:s0`, pero los
procesos hijos aparecen con `scontext=u:r:shell:s0` en las denegaciones de SELinux. Efecto
práctico: **root para leer, pero no para crear ficheros en `/data/data`**.

## Cómo se detecta

```console
$ adb shell "su -c 'id'"
uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0      # <- parece correcto

$ adb shell "su -c 'chmod 777 /data/data/zzC'"
chmod: chmod '/data/data/zzC' to 40777: Permission denied          # <- y aquí no

$ adb shell "su -c 'dmesg | grep avc | tail -1'"
avc: denied { setattr } for pid=2824 comm="chmod" name="zzC" dev=mmcblk0p18 ino=32809
  scontext=u:r:shell:s0 tcontext=u:object_r:system_data_file:s0 tclass=dir permissive=0
                        ^^^^^^^^^^^^^^^ ahí está el problema
```

Síntomas que produce (todos verificados):

| operación | resultado |
|---|---|
| `mkdir /data/data/<pkg>` | ✅ funciona (el dominio `shell` sí puede crear *directorios*) |
| `touch`, `echo >`, `cp` de ficheros dentro | ❌ `Permission denied` |
| `chmod`, `chown` sobre lo que acabas de crear | ❌ `Permission denied` |
| `cp -a` de un árbol entero | ❌ falla al restaurar el contexto SELinux del origen |
| `cp -r` | ✅ (los ficheros, si el dominio lo permite) |
| `cat`, `ls`, `dumpsys` | ✅ siempre |
| `restorecon -R` | ❌ sin reglas nuevas |

`setenforce 0` **no** arregla el problema de DAC (y además `setenforce 1` puede fallar después
por falta de `CAP_MAC_ADMIN`: si lo pruebas, reinicia para volver a enforcing).

## El arreglo: `magiskpolicy --live`

Magisk trae `magiskpolicy` en `/data/adb/magisk/`. Las reglas se añaden **en caliente** y
**no persisten** (se pierden al reiniciar, que es lo deseable para no dejar el reloj flojo
de SELinux).

```sh
MP=/data/adb/magisk/magiskpolicy
for DOM in shell magisk; do
  "$MP" --live \
    "allow $DOM system_data_file dir { create write read search setattr add_name remove_name rmdir }" \
    "allow $DOM system_data_file file { create write read getattr setattr unlink rename }" \
    "allow $DOM system_data_file lnk_file { create read getattr setattr unlink }" \
    "allow $DOM app_data_file dir { create write read search setattr add_name remove_name rmdir }" \
    "allow $DOM app_data_file file { create write read getattr setattr unlink rename }" \
    "allow $DOM app_data_file lnk_file { create read getattr setattr unlink }"
done
```

Script listo para usar: [`../scripts/fix-selinux-data.sh`](../scripts/fix-selinux-data.sh).

### ⚠️ Sintaxis de este `magiskpolicy`

La versión que trae esta ROM **no** acepta la forma con dos puntos:

```
allow shell system_data_file:dir { create write }     # -> Syntax error in: "allow shell system_data_file:dir {...}"
allow shell system_data_file dir { create write }     # -> OK
```

Y `file` / `dir` son **clases**, no tipos: si los pones como tipo da
`Hint: allow *source_type *target_type *class *perm_set`.

## Para qué se usó (caso real)

Migrar los datos de una app instalada con **otra clave de firma** (sin poder usar
`adb install -r`) sin perder la sesión del usuario:

1. `su -c 'tar -czf /sdcard/datos.tgz -C /data/data com.la.app'` + `adb pull`.
   *(crear `.tgz` sí funciona; extraerlo **no**, ver abajo)*
2. `pm uninstall` + `adb install` del APK nuevo.
3. Descomprimir en el ordenador, quitar el enlace `lib` (es absoluto a `/data/app/...`),
   `adb push` del árbol a `/data/local/tmp/`.
4. `fix-selinux-data.sh`, y ya con permisos:
   `cp -r /data/local/tmp/tree/<pkg> /data/data/` →
   `ln -sfn $(dirname $(pm path <pkg> | sed s/package://))/lib/x86 /data/data/<pkg>/lib` →
   `chown -R <uid>:<uid>` → `chmod 771` → `restorecon -R`.
5. Verificar con la app abierta (en Spotify se comprobó que la home cargaba con la sesión viva).

### Tropiezos que cuesta descubrir

- **`tar -xzf` no funciona en el reloj**: el `tar` de toybox comprime pero al extraer busca un
  `gunzip` que no existe → `tar: exec gunzip: No such file or directory`.
  Descomprime en el ordenador y copia el árbol.
- **`cp -a` falla** (`-a` = `--preserve=all`, incluye `security.selinux`): usa `cp -r` y luego
  `restorecon -R`.
- **`adb push` de un symlink** que apunta a una ruta inexistente:
  `failed to read copy response: EOF` / `Is a directory`. Quítalo del árbol antes.
- El uid de la app cambia al reinstalar: léelo con
  `dumpsys package <pkg> | grep -m1 userId=`.
