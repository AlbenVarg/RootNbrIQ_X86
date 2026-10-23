# RootNbrIQ_X86

**Root + optimización de un reloj New Balance RunIQ (NBRiq)** — SoC Intel Atom x86,
Wear OS 2.0 / **Android 7.1.1 (API 25)**, bootloader Intel `SHASTA-03.54`.

Todo lo de este repo se hizo y se verificó **sobre el reloj real** (22-23/oct/2026).
No hay teoría: cada paso tiene el comando y la salida que lo confirma.

> El otro proyecto de la misma sesión (Spotify en el reloj) vive aparte:
> [Sp0tiold-X86](https://github.com/AlbenVarg/Sp0tiold-X86).

---

## El reloj

| dato | valor |
|---|---|
| modelo | `NB RunIQ` (New Balance RunIQ) |
| device / name / board | `shasta` / `shasta` / `robby` |
| SoC | Intel Atom **x86** (`ro.product.cpu.abi=x86`, sin ARM) |
| sistema | Android 7.1.1 / API 25, Wear OS 2.0 |
| build | `NWD1.171016.002` (`newbalance/shasta/shasta:7.1.1/...:user/release-keys`) |
| build type | `user`, `ro.debuggable=0` → **`adb root` NO funciona** |
| bootloader | `SHASTA-03.54` (droidboot Intel, **no** Qualcomm; sin particiones A/B) |
| RAM | 455 MB (`MemTotal`), 110 MB de swap |
| serial | `BIB7UX7D9PBGSE` (USB) / `10.0.0.132:5555` (Wi-Fi) — ver [Serial del reloj](#serial-del-reloj-privacidad) |

---

## Guía paso a paso

### 0. Requisitos y ADB

```bash
adb devices -l                      # BIB7UX7D9PBGSE  device usb
adb connect 10.0.0.132:5555         # por Wi-Fi (acepta el diálogo RSA en el reloj)
```

> ⚠️ En la misma red hay otro dispositivo (`10.0.0.180:5555`): usa siempre `-s`.
> Reloj: `adb -s BIB7UX7D9PBGSE …` o `adb -s 10.0.0.132:5555 …`.

### 1. Desbloquear el bootloader (borra /data)

```bash
fastboot getvar all                    # boot 16 MiB, userdata ~2.4 GB, sin A/B
fastboot flashing get_unlock_ability   # OK (existe el set "flashing")
fastboot flashing unlock               # OKAY en 6.7 s -> device_state: unlocked
fastboot reboot
```

Trampas del bootloader Intel (no Qualcomm):

```
fastboot oem device-info      -> FAILED (remote: 'unknown command')
fastboot oem unlock-go        -> unknown command
fastboot getvar device_state  -> unlocked   # esta es la buena
```

Los props `ro.boot.verifiedbootstate` / `ro.boot.flash.locked` salen **vacíos**
(el droidboot de Intel no los exporta): el estado del candado solo se lee en el bootloader.

Tras el wipe el reloj arranca en el asistente y **la depuración ADB queda apagada**:

1. Empareja otra vez con el móvil (app Wear OS).
2. Ajustes → Sistema → Información → toca *Número de compilación* 7 veces.
3. Ajustes → Sistema → Opciones de desarrollador → **Depuración ADB** (+ *Depurar por Wi-Fi*).
4. `adb devices` y acepta el RSA en el reloj.

*(ADB por Bluetooth no sirve en Wear OS 2: va puenteado por el teléfono. Ver
[`docs/SESION-COMPLETA.md`](docs/SESION-COMPLETA.md).)*

### 2. Root con Magisk v30.7

Partición `boot`: **16 MiB**. Imágenes usadas (no están en git, pesan ~9 MB cada una;
ver [Estructura](#estructura-del-repo)):

| imagen | tamaño | sha1 | para qué |
|---|---|---|---|
| `ota/boot-stock.img` | 9.007.104 B | `99a5980288bb…` | stock (rescate) |
| `ota/boot-magisk.img` | 9.236.480 B | `b4251b27aa7b…` | **la que está flasheada** |
| `ota/boot-magisk-slim.img` | — | — | ❌ **no sirve**: el `magiskinit` legacy necesita `.backup/init.xz` |
| `ota/boot-root-adb.img` | 9.007.104 B | — | rescate: `ro.secure=0`, `ro.debuggable=1`, `ro.adb.secure=0` |

```bash
fastboot boot  ota/boot-magisk.img     # prueba en RAM (no escribe la partición)
fastboot flash boot ota/boot-magisk.img
fastboot reboot
adb install -r magisk/Magisk-v30.7.apk # app oficial completa
```

El parcheo del boot se hizo con `magiskboot` + `magiskinit` (carpeta `mpatch/`, scripts en
`mpatch/work/run_patch.sh` y `run_patch_slim.sh`).

Verificación:

```console
$ adb -s 10.0.0.132:5555 shell "su -c 'magisk -v; magisk --path; id'"
30.7:MAGISK:R
/sbin
uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0
```

Comprobado además con una app independiente (**Root Checker Basic 6.5.12**, uid 10043):
diálogo *Superuser request* → *"Congratulations! Root access is properly installed on this
device!"*.

> La tarjeta de inicio de la app Magisk dice *"Download Magisk"* aunque el backend esté
> instalado: es un **falso negativo de la UI Wear**, `su` funciona igual.

### 3. Conceder root a una app (sin pelear con el diálogo de 400×400)

```bash
./scripts/grant-su.sh --list                  # uid | policy actuales
./scripts/grant-su.sh com.mi.app              # concede (policy=2) y reinicia
./scripts/grant-su.sh com.mi.app --no-reboot  # solo escribe la BD
```

Escribe en `/data/adb/magisk.db` con el esquema real de Magisk v30.7:
`policies (uid, policy, until, logging, notification)`, `policy=2` = permitir.
**Sin reinicio `magiskd` no recarga la BD** (la tiene en memoria).

Políticas que quedaron: `uid=2000` (shell adb), `uid=10042` (app Magisk), `uid=10043` (Root Checker).

### 4. Debloat y rendimiento

El cuello de botella del reloj es la **RAM (455 MB)**, no la CPU. Todo es reversible
(`pm disable-user` no borra APKs):

```bash
./scripts/debloat.sh status    # qué está deshabilitado + memoria
./scripts/debloat.sh apply     # 20 paquetes + animaciones + script de arranque
./scripts/debloat.sh restore   # vuelve a fábrica
```

- Listas exactas: `debloat/packages-before.txt` y `debloat/packages-disabled.txt`.
- El mayor consumidor era **la propia app de Magisk** (53 MB con `:root:0`): como `magiskd`
  vive en la partición `boot`, `/data/adb/service.d/99-watch-tune.sh` la para 60 s después de
  cada arranque y ajusta las animaciones. La app sigue instalada y funciona si la abres.
- Extra opcional (quita funciones): `com.android.providers.calendar`, `com.google.android.tts`,
  `com.ustwo.watchfaces.hero`, `com.google.android.wearable.setupwizard` → ~10 MB más.

### 5. SELinux: el detalle que nadie cuenta

En esta ROM `su -c` ejecuta los comandos en el dominio **`shell`**, no en `magisk`
(lo delata `dmesg`):

```
avc: denied { setattr } for comm="chmod" name="zzC"
  scontext=u:r:shell:s0 tcontext=u:object_r:system_data_file:s0 tclass=dir permissive=0
```

Consecuencia: `su` es root para leer, pero **no puede crear ficheros en `/data/data`**
(`touch`, `chmod`, `cp -a` → `Permission denied`). Se arregla en caliente con `magiskpolicy`
(**no persiste**, se pierde al reiniciar):

```bash
./scripts/fix-selinux-data.sh          # carga las reglas mínimas
```

Detalle completo, sintaxis correcta de `magiskpolicy` y cómo se usó para migrar los datos de
una app entre instalaciones: [`docs/SELINUX.md`](docs/SELINUX.md).

### 6. Extras que se hicieron en la misma sesión

- **Batería**: salud de la celda (MAX17047) y consumo medido → `scripts/battery.sh`.
- **Actualizar la app de Wear OS** del reloj: 2.0.0 → **2.35.0** (con copia del APK de fábrica).
- **Esfera propia estilo Pixel Watch** (`wearapp/`, Kotlin, `compileSdk 35` + `minSdk 25`,
  JDK 17 obligatorio): `./scripts/wearapp.sh install|face`.

### 7. Serial del reloj (privacidad)

El serial real identifica el dispositivo: sale en `adb devices`, en capturas y en
cualquier log que compartas. Se sustituyó por uno aleatorio **en el propio reloj**:

```bash
./scripts/random-serial.sh              # genera uno aleatorio, lo aplica y lo hace persistente
./scripts/random-serial.sh BIXXXXXXXXXXXX   # o el valor que tu quieras
./scripts/random-serial.sh --show       # que reporta ahora
./scripts/random-serial.sh --remove     # deshacerlo (vuelve el real al reiniciar)
```

Cómo: `magisk resetprop -n ro.serialno …` (Magisk puede reescribir props de solo lectura) y un
script en `/data/adb/post-fs-data.d/00-random-serial.sh` para que se aplique en cada arranque
antes de que arranquen las apps. Verificado tras reiniciar:

```console
$ adb shell getprop ro.serialno
BIB7UX7D9PBGSE
```

> ⚠️ **Límite honesto**: el descriptor USB lo fija el kernel desde la línea de comandos del
> bootloader, así que `adb devices -l` **por USB** puede seguir mostrando el original. Por
> Wi-Fi aparece `IP:puerto`, no el serial. Si te conectas por USB y te importa, usa Wi-Fi
> (`adb connect`).

### 8. Rescate

```bash
fastboot flash boot ota/boot-stock.img     # quitar el root (vuelve a stock)
fastboot boot  ota/boot-root-adb.img       # adb root en RAM, sin escribir nada
```

⚠️ **No hagas `fastboot flashing lock` con Magisk dentro**: el reloj no volvería a arrancar.

---

## Scripts

| Script | Para qué |
|---|---|
| `scripts/nbriq.sh` | estado ADB/fastboot, entrar al bootloader, unlock/relock, reboot |
| `scripts/grant-su.sh` | concede root a un paquete editando `magisk.db` + reinicio |
| `scripts/debloat.sh` | deshabilita paquetes/animaciones (apply / status / restore) |
| `scripts/battery.sh` | informe de batería: salud, consumo, wakeups |
| `scripts/wearapp.sh` | compila e instala la esfera propia (`wearapp/`) |
| `scripts/root-check.sh` | **verifica** el estado: `su`, `magisk -v`, políticas, SELinux, bootreason |
| `scripts/fix-selinux-data.sh` | reglas `magiskpolicy --live` para poder escribir en `/data/data` |
| `scripts/random-serial.sh` | cambia el serial que reporta el reloj por uno aleatorio (persistente) |

---

## Estructura del repo

```
docs/
  SESION-COMPLETA.md      bitácora íntegra de la sesión (unlock, Magisk, debloat, batería, esfera)
  SELINUX.md              el dominio shell, magiskpolicy y la migración de datos de una app
  fastboot-getvar-all.txt salida cruda de `fastboot getvar all`
scripts/                  los 7 scripts de arriba
debloat/                  listas de paquetes antes/después
magisk/                   Magisk-v30.7.apk, assets/, x86/*.so, service.d/99-watch-tune.sh
mpatch/                   work/ con el parcheo del boot (scripts + imágenes)
ota/                      imágenes boot y OTA del firmware
ota-prober/               herramienta de terceros clonada (google-ota-prober) — ignorada por git
ota-test/                 fabricación de un OTA de prueba (mkzip.py + test keys de AOSP)
backup-sdcard/            volcado de /sdcard antes del wipe
wearapp/                  proyecto Gradle de la esfera propia
```

### Qué NO está en git (y por qué)

Imágenes, APKs y binarios pesados están en `.gitignore` porque superan de largo el tamaño
razonable de un repo (los ficheros siguen en tu disco):

| ruta | tamaño | nota |
|---|---|---|
| `ota/*.zip` | 415 MB + 103 MB + 54 MB | OTA completos e incrementales del firmware |
| `ota/*.img`, `mpatch/work/*.img` | ~9 MB cada uno | boot stock/parcheado; recuperables parcheando el stock |
| `magisk/*.apk` | 11 MB + 12 MB | Magisk oficial y Root Checker |
| `magisk/x86/*.so`, `magisk/assets/*.jar` | 3.6 MB + 1 MB | binarios del APK de Magisk |
| `ota-prober/` | 21 MB | clon de https://github.com/tangalbert919/google-ota-prober |
| `wearapp/**/build/` | ~20 MB | salida de Gradle |

Si necesitas las imágenes: descarga el OTA y parchea con `mpatch/work/run_patch.sh`.

---

## Trampas encontradas (para no repetirlas)

- **`magisk --sqlite` no avisa**: con columnas inexistentes devuelve `rc=0` y no inserta nada.
  Usa el esquema real de `policies`.
- **Si `magiskd` no está vivo**, `su`/`magisk` mueren con **SIGILL** (`ud2` en
  `/sbin/magisk+0x269df`). No es falta de SSE3: se recupera reiniciando.
- **Pantalla en Doze**: `screencap` devuelve el último frame (ficheros idénticos byte a byte) y
  `uiautomator` falla con `null root node`. Despierta con `input keyevent 224`.
- **`adb root` imposible** (`adbd cannot run as root in production builds`): el root va por `su`.
- **`cp -a` falla** al restaurar datos de una app: intenta escribir el contexto SELinux del
  origen. Usa `cp -r` + `restorecon -R`.
- **`tar -xzf` no funciona** en el reloj: el `tar` de toybox comprime pero no descomprime
  (no hay `gunzip`). Descomprime en el ordenador y copia el árbol.
- **Los reinicios del reloj no son de las apps**: son resets del **watchdog** del kernel
  (`ro.boot.bootreason=watchdog`), con `Oops` en `ipt_do_table` dentro de `suspend_enter`.
  Análisis: [Sp0tiold-X86 › docs/FINDINGS.md §10](https://github.com/AlbenVarg/Sp0tiold-X86/blob/main/docs/FINDINGS.md).

---

## Aviso

Desbloquear el bootloader **borra el reloj** y anula la garantía; flashear `boot` mal puede
dejarlo sin arrancar (para eso están `boot-stock.img` y el modo fastboot). Todo lo de este
repo se aplicó a un dispositivo propio, con el firmware `NWD1.171016.002`.
