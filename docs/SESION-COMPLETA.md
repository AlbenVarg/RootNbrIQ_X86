# NBRiq — New Balance RunIQ (Wear OS)

> ℹ️ **Serial anonimizado.** El serial real del reloj se ha sustituido por uno aleatorio
> (`BIB7UX7D9PBGSE`) en toda esta documentación, y el reloj reporta ese mismo valor desde
> entonces (ver [`../README.md`](../README.md#7-serial-del-reloj-privacidad) y
> `scripts/random-serial.sh`). La IP `10.0.0.132` sí es la real de la red local.

Notas de la sesión de **OEM unlock** por `fastboot` (22/10/2026).

## Identidad del dispositivo (leída con `getprop`, antes del unlock)

| Prop | Valor |
|---|---|
| `ro.product.model` | `NB RunIQ` |
| `ro.product.device` / `ro.product.name` | `shasta` |
| `ro.product.board` | `robby` |
| `ro.product.manufacturer` | `Intel` |
| `ro.product.cpu.abi` | `x86` (Atom, sin ARM) |
| `ro.build.version.release` / `sdk` | `7.1.1` / `25` (Wear OS 2.0) |
| `ro.build.id` | `NWD1.171016.002` |
| `ro.build.fingerprint` | `newbalance/shasta/shasta:7.1.1/NWD1.171016.002/4398992:user/release-keys` |
| `ro.build.type` / `ro.debuggable` | `user` / `0` |
| `ro.bootloader` | `SHASTA-03.54` |
| serial | `BIB7UX7D9PBGSE` |

## Estado del bootloader

```
kernel: droidboot            <- bootloader Intel (no Qualcomm)
version-bootloader: SHASTA-03.54
device_state: locked   ->   device_state: unlocked
unlocked: no           ->   unlocked: yes
fastboot oem device-info      -> FAILED (remote: 'unknown command')   # es de Qualcomm
fastboot oem get_unlock_ability / oem unlock-go -> unknown command
fastboot flashing get_unlock_ability -> OK (existe el set "flashing")
```

## Lo que se ejecutó

```bash
adb devices -l                                   # BIB7UX7D9PBGSE  device  usb
adb pull /sdcard backup-sdcard/                  # 52 bytes (nada relevante)
adb reboot bootloader
fastboot getvar all                              # data: 0x977f7c00 (~2.4 GB), sin A/B
fastboot flashing unlock                         # OKAY en 6.7 s  <-- BORRA /data
fastboot flashing get_unlock_ability             # Device state: unlocked
fastboot reboot
```

Resultado: **unlocked correctamente**. Tras el wipe el reloj entra en setup de fábrica y
la depuración ADB queda **desactivada**, por eso `adb devices` sale vacío hasta re-configurarlo.

## Reconexión tras el wipe (hecho en esta sesión)

El reloj quedó configurado y accesible **por Wi‑Fi**, no por USB:

```
adb connect 10.0.0.132:5555
10.0.0.132:5555   device   product:shasta model:NB_RunIQ device:shasta
uptime: 1:18 (booteó justo después del fastboot reboot)   usuario shell uid=2000
/sdcard: sólo carpetas estándar vacías  ->  el wipe se aplicó
adb root -> "adbd cannot run as root in production builds" (build user)
```

Nota: los props `ro.boot.verifiedbootstate` / `ro.boot.flash.locked` / `ro.boot.veritymode`
salen **vacíos** en este dispositivo (droidboot de Intel no los exporta); el estado real del
candado sólo se lee en el bootloader (`fastboot getvar device_state`).

### ADB por Bluetooth (por qué falló)

Wear OS puentea BT a través del **teléfono** emparejado: hay que tener el teléfono como
transporte adb y lanzar el forward contra él. En la Mac el reloj sí aparece emparejado
(`NB RunIQ 01CL` en Bluetooth), pero eso no crea un transporte adb:

```bash
adb forward tcp:4444 localabstract:/adb-hub   # contra el TELÉFONO, no contra el reloj
adb connect 127.0.0.1:4444
```

Sin teléfono en `adb devices` → `no devices/emulators found` + `Connection refused`.

## Cómo volver a tener ADB

1. Reloj: emparejar de nuevo con el teléfono (Wear OS app).
2. Ajustes → Sistema → Información → tocar *Número de compilación* 7 veces.
3. Ajustes → Sistema → Opciones de desarrollador → **Depuración ADB** (y *Depurar por Wi-Fi* si quieres inalámbrico).
4. `adb devices` → aceptar el diálogo RSA en el reloj.
5. Wi-Fi: `adb connect <ip-del-reloj>:5555`.

## Script incluido

```bash
./nbriq.sh status          # estado en ADB/fastboot
./nbriq.sh bootloader      # reinicia al bootloader
./nbriq.sh unlock --yes    # flashing unlock (borra /data)
./nbriq.sh relock --yes    # ¡solo con sistema de fábrica!
./nbriq.sh reboot
```

## Root con Magisk v30.7 (conseguido el 22/10/2026)

### Partición boot

| dato | valor |
|---|---|
| tamaño | **16 MiB** (`0x01000000` = 16.777.216 B), leído con `fastboot getvar all` |
| imagen stock | `ota/boot-stock.img` — 9.007.104 B, sha1 `99a5980288bb…` (ruta de rescate) |
| imagen parcheada | `ota/boot-magisk.img` — 9.236.480 B, sha1 `b4251b27aa7b…` (la que está flasheada) |
| imagen "root adb" | `ota/boot-root-adb.img` — `ro.secure=0`, `ro.debuggable=1`, `ro.adb.secure=0` |

La variante "slim" (`ota/boot-magisk-slim.img`, sin `.backup/init.xz`) **no sirve**: el
`magiskinit` legacy necesita ese respaldo.

### Secuencia usada

```bash
fastboot boot  ota/boot-magisk.img        # prueba en RAM (no escribe nada)
fastboot flash boot ota/boot-magisk.img
fastboot reboot
adb install -r magisk/Magisk-v30.7.apk    # app oficial completa (md5 0c937d8957520a1a3585e4363a8ccab4)
```

### Estado actual (verificado)

```console
$ adb -s 10.0.0.132:5555 shell "su -c 'magisk -v; magisk --path; id'"
30.7:MAGISK:R
/sbin
uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0
```

- `magiskd` arranca **desde la partición boot** en cada reinicio (`* Found preinit dir: /data/adb`,
  `** boot-complete triggered`) y `/sbin` contiene `magisk`, `magiskinit`, `magiskpolicy` y `su`.
- Comprobado con una app independiente, **Root Checker Basic 6.5.12** (`com.joeykrim.rootcheck`,
  uid 10043): aparece el diálogo *Superuser request* del reloj y tras concederlo responde
  **"Congratulations! Root access is properly installed on this device!"**. El APK queda en
  `magisk/com-joeykrim-rootcheck-*.apk`; la app se desinstaló después al hacer el debloat
  (~45 MB de RAM cuando estaba abierta).
- La app Magisk muestra en su tarjeta de inicio *"Download Magisk"* aunque el backend está
  instalado: es un **falso negativo de la UI Wear**, no afecta a `su` (el APK instalado es el
  oficial completo, md5 idéntico al de `magisk/Magisk-v30.7.apk`).

### Conceder root a una app

El diálogo *Superuser request* en 400x400 es incómodo de pulsar, así que hay un helper:

```bash
./grant-su.sh --list                 # uid|policy actuales
./grant-su.sh com.mi.app             # concede root (policy=2) y reinicia
./grant-su.sh com.mi.app --no-reboot # sólo escribe la BD
```

Edita `/data/adb/magisk.db` con el esquema real de Magisk v30.7 —
`policies (uid, policy, until, logging, notification)`, `policy=2` = permitir — y reinicia para
que `magiskd` recargue. **Sin reinicio el cambio no se aplica** (caché en memoria).

Políticas actuales: `uid=2000` (shell adb), `uid=10042` (app Magisk), `uid=10043` (Root Checker).

### Trampas encontradas

- **`magisk --sqlite` no reporta errores**: con columnas inexistentes devuelve `rc=0` y no
  inserta nada. Usa el esquema real.
- **Si `magiskd` no está vivo**, `su`/`magisk` mueren con **SIGILL** (`Illegal instruction`,
  `ud2` en `/sbin/magisk+0x269df`): es la ruta de excepción del binario, no falta de SSE3
  (el Atom T1000 no tiene `sse3`, pero el fallo es idéntico byte a byte). Se recupera reiniciando.
- **Pantalla en Doze**: `screencap` devuelve el último frame (archivos idénticos byte a byte) y
  `uiautomator` falla con `null root node`. Despierta con `input keyevent 224`.
- Usa siempre `-s`: en la misma red hay otro dispositivo (`10.0.0.180:5555`). Reloj:
  `BIB7UX7D9PBGSE` por USB, `10.0.0.132:5555` por Wi-Fi (`adb connect` + aceptar RSA en el reloj).

## Debloat / rendimiento (aplicado el 22/10/2026)

El reloj tiene **456 MB de RAM**: el cuello de botella no era la CPU sino la memoria
(`MemFree` 20 MB, 110 MB de swap en uso, `kswapd0` al 19%). Todo lo aplicado es **reversible**:
`pm disable-user` no borra APKs, y hay script para volver atrás.

```bash
./debloat.sh status    # qué está deshabilitado + memoria
./debloat.sh apply     # 20 paquetes + animaciones + script de arranque (idempotente)
./debloat.sh restore   # deja el reloj como de fábrica
```

### Qué se deshabilitó (20 paquetes nuestros, 21 en total de 62)

`debloat/packages-disabled.txt` tiene la lista exacta. Ojo: `com.google.android.apps.fitness` ya
venía deshabilitado de fábrica, no lo tocamos.

| Grupo | Paquetes |
|---|---|
| Telemetría / demo / test | `com.intel.analytics` (19 MB + 3 servicios), `com.android.lto`, `…wearable.retailattractloop`, `…wearable.bugreportsender`, `…clockwork.gestures.tutorial`, `com.android.backupconfirm`, `com.android.wallpaperbackup`, `com.android.managedprovisioning`, `com.android.cts.ctsshim`, `com.android.cts.priv.ctsshim` |
| Apps preinstaladas sin uso | `com.newbalance.loyalty`, `com.strava`, `com.google.android.music`, `com.google.android.apps.translate`, `com.google.android.apps.handwriting.ime`, `com.google.android.wearable.reminders`, `com.google.android.syncadapters.contacts`, `com.google.android.apps.wearable.phone` |
| Pesados (quitan funciones) | `com.android.vending` (Play Store, 27 MB), `com.google.android.googlequicksearchbox` (búsqueda por voz + hotword, 10 MB) |
| App Magisk | se queda instalada, pero un script de arranque la para (~53 MB) |

Las dos del grupo «pesados» sí quitan funciones: en Wear no hay tienda donde instalar nada y
desaparece el «Ok Google». Se recuperan con `./debloat.sh restore`.

### El mayor consumidor era la app de Magisk

`com.topjohnwu.magisk` + `:root:0` sumaban **53 MB de RAM** y arrancaba sola. Como `magiskd` vive
en la partición boot, la app no hace falta: `/data/adb/service.d/99-watch-tune.sh` la para 60 s
después de cada arranque y fija las animaciones. Sigue instalada y funciona si la abres.

```console
$ adb shell getprop nbr.tune.start; adb shell getprop nbr.tune.done
1
1
```

**Detalle importante**: cualquier `su` lanzado desde adb vuelve a despertar la app
(`SuRequestActivity` + `content provider com.topjohnwu.magisk/.core.Provider`) y muestra el toast
«Shell was granted Superuser rights». Por eso `debloat.sh` y `grant-su.sh` terminan parándola… y
hay que hacerlo **sin** `su` (con el `su` se resucita otra vez) y dos veces, porque `magiskd` la
relanza de forma asíncrona.

### Resultado medido (2 min en reposo tras reiniciar)

| métrica | antes | después |
|---|---|---|
| MemAvailable | 158 MB | **220 MB** |
| swap en uso | 110 MB | **30 MB** |
| load average (1 min) | 3,51 | **0,19 – 1,00** |
| `kswapd0` | 19 % | **1,4 %** |
| `system_server` | 24 % | **7,6 %** |
| arranque → `sys.boot_completed` | — | ~45-50 s |

También: animaciones a 0 (la UI responde al instante) y `Root Checker` desinstalado tras validar.
Comprobado que la esfera, las complicaciones, los Ajustes, Bluetooth, Wi-Fi, las 12 cuentas y `su`
siguen intactos.

### Detalles técnicos que costaron

- `pm disable-user --user 0` hay que lanzarlo vía `su`; con el shell normal algunos paquetes fallan.
- `adb push` **no** puede escribir en `/data/adb` (es `700 root`): hay que pasar por
  `/data/local/tmp` y hacer `cp` como root.
- El script copiado se quedaba con el contexto SELinux heredado `adb_data_file`: sin
  `chcon u:object_r:magisk_file:s0` Magisk no lo ejecuta.
- `service.d` se ejecuta como root en el arranque; sirve para dejar el reloj «tuneado» sin apps extra.

## Batería: salud, consumo y qué lo causa (medido el 22/10/2026)

Herramienta: **`./battery.sh`** (`health`, `drain`, `wifi on|off`, `tweaks [apply|revert]`).
Necesita `NBR_SERIAL` y, para `/sys/class/power_supply`, `su`.

### Salud de la celda (cargador MAX17047)

| métrica | valor | comentario |
|---|---|---|
| `charge_full_design` | 416 mAh | lo que New Balance declaró |
| `charge_full` | 400 mAh | lo que el gas gauge aprendió |
| salud | **96 %** | buena para un reloj de 2017 |
| `charge_now` | 325 mAh (81 %) | |
| `voltage_now` / `voltage_ocv` | 4,17 V / 4,10 V | |
| `current_avg` | ±165 mA en carga, **36 mA** en reposo sin Wi-Fi | |

Ritmo de descarga medido por `batterystats` (pantalla apagada, en batería): **~4,5 min por
1 %** ≈ 13 %/hora ≈ **50 mA de media**. Con 400 mAh reales eso son ~7-8 h de uso y ~1 día
justo si no se toca; es lo esperable en este hardware, no hay celda degradada.

### Qué consume (esto es lo importante)

| causa | medida | veredicto |
|---|---|---|
| **radio Wi-Fi** (`wlan_rx_wake`) | mantiene la CPU despierta **2.893 de 6.100 s (47 %)** | **el culpable** |
| CPU | sólo 4,8 % ocupada y 91 % del tiempo a 500 MHz | no es CPU |
| wakelocks de apps | 19 s en 30 min | despreciable |
| acelerómetro + `GazeStateEstimationWakeLock` (tilt-to-wake) | 5 s en 30 min | despreciable |
| alarmas de Play Services | heartbeat cada 5 min | menor |

Es decir: el reloj no se descarga «haciendo cosas», se descarga porque **cada trama que llega
por Wi-Fi lo despierta** (el driver `bcmdhd` despierta la CPU por paquete, y con la Wi-Fi
asociada llegan ~1,5 tramas/s de la LAN).

Dos detalles que explican el mecanismo:

- `dumpsys wifi` marca **`offload-stopped`**: el filtro de paquetes del *firmware* (ARP/NS
  offload) no está activo, así que el chip **despierta al host por cada trama** en vez de
  descartarla él. Es la razón de fondo del 47 %.
- La señal es **mediocre**: `rssi=-68/-69 dBm`, 2.4 GHz (canal 5), link 65 Mbps, y el driver
  registra `wlan_wd_wake` (watchdog) 1.166 veces. A −68 dBm el chip transmite cerca de su
  potencia máxima, lo que suma bastantes mA. Acercar el reloj al router (o usar 5 GHz) baja
  el consumo sin tocar el software.

### Qué se probó y no funcionó (para no repetirlo)

- **Filtrar multicast** (`iptables`/`ip6tables -m pkttype --pkt-type multicast -j DROP`):
  el ratio de `wlan_rx_wake` no cambió (45,9 % con regla vs 43-48 % sin ella). Dos motivos:
  las tramas que despiertan son **unicast** y, sobre todo, **el filtro llega tarde**: la CPU ya
  se ha despertado en el driver/firmware antes de que netfilter vea el paquete. Revertido.
- **`wake_gesture_enabled=0`**: no desactiva el gesto en `NWD1.171016.002`. `Wrist Tilt Gesture`
  sigue en `Active sensors` tras reiniciar porque lo suscribe `com.google.android.wearable.ambient`
  (app de sistema, uid 10006). Además su coste real es mínimo (5 s de wakelock en 30 min).
- **`screen_off_timeout`**: la app de Ajustes de Wear lo reescribe a 30 s en cada arranque.
  Solución: `99-watch-tune.sh` lo vuelve a poner en 15 s (verificado, ver más abajo).

### Lo que sí sirve

1. **Apagar la Wi-Fi cuando no haga falta sincronizar**: `./battery.sh wifi off` (36 mA medidos
   frente a ~50-55 mA con radio). Inconveniente: sin Wi-Fi no hay adb ni sincronización con la nube
   (el reloj no tiene teléfono emparejado por Bluetooth, así que Wear usa la Wi-Fi para todo).
2. **`./battery.sh tweaks apply`**: `wifi_sleep_policy=1` (antes 2 = «nunca duerme») y pantalla a 15 s.
3. Ya venían apagados y conviene que sigan así: `wifi_scan_always_enabled=0`, ubicación `null`,
   always-on/doze `doze_enabled=0`, animaciones a 0, 20 paquetes deshabilitados.
4. Para medir tú mismo, **fuera del cargador** (cargando no suspende: `suspend_stats: success 0`):
   dejarlo 30 min boca abajo y lanzar `./battery.sh health`.

## Actualizar la app de Wear OS del reloj (2.0.0 → 2.35.0, hecho el 22/10/2026)

El reloj seguía con la app de Wear OS **de fábrica**: `2.0.0.169881869` (versionCode 780518230,
`targetSdk 25`, en `/system/priv-app/ClockworkHomeGoogle`, firmada con
`CN=ClockWork, O=Google Inc.`, SHA-256 `85cd5973…b6fe`). Esa firma es la clave: **cualquier
actualización tiene que venir firmada igual**, así que APK de terceros o recompilados no sirven.

Vía usada (la única fiable aquí):

1. `adb shell pm enable com.android.vending` — el Play Store estaba deshabilitado por `debloat.sh`.
2. `adb shell am start -a android.intent.action.VIEW -d 'market://details?id=com.google.android.wearable.app'`
3. Botón **Update** en el reloj. Play descarga la build **x86 / API 25** correcta y la instala como
   actualización (el APK de `/system` no se toca).
4. Al terminar se vuelve a deshabilitar la tienda (batería):
   `adb shell su -c 'pm disable-user --user 0 com.android.vending'`.

| | Antes | Después |
|---|---|---|
| Versión | `2.0.0.169881869` (780518230) | **`2.35.0.325323493`** (782004506) |
| targetSdk | 25 | 28 |
| Ruta | `/system/priv-app/…` | `/data/app/com.google.android.wearable.app-1` |
| ABI | — | `primaryCpuAbi=x86` |

Cambios visibles: la pantalla principal pasa al diseño moderno de Wear OS 2.x (hora grande con
chips de **batería**, **fecha**, **clima** y agenda), y la build incluye soporte de **tiles**
(21 referencias `Tiles`/`TileService` en el paquete). Sin `FATAL`/`ANR` en logcat.

Coste: PSS de la app ~53 MB y `MemAvailable` ~175 MB (antes ~220 MB). Sigue siendo holgado para
un dispositivo de 456 MB.

**Rollback** (la copia de fábrica sigue en `/system`, así que es inmediato):

```bash
adb uninstall com.google.android.wearable.app   # vuelve a 2.0.0 de /system
# copia de seguridad del APK de fábrica:
adb pull /system/priv-app/ClockworkHomeGoogle/ClockworkHomeGoogle.apk
```

Nota: en APKMirror la variante **x86 / Android 7.1+** sólo llega a `2.22.0.234791771` (feb 2019);
las `2.35`/`2.66` publicadas son **ARM** y no arrancarían. Por eso la actualización se hizo por
Play, que filtra por arquitectura y `minSdk` del dispositivo.

## Esfera propia estilo Pixel Watch (`wearapp/`)

Esfera hecha a medida para la pantalla de 400×400 del `shasta`, con hora grande, fecha, anillo
perimetral de batería y un chip inferior de complicación.

```bash
./wearapp.sh build        # compila el APK (Gradle 8.9 + AGP 8.7.3 + Kotlin 2.1)
./wearapp.sh install      # compila, instala y refresca el selector
./wearapp.sh face         # abre el selector de esferas (sección "P": Pixel NBRiq)
./wearapp.sh shot f.png   # captura de pantalla
./wearapp.sh preview      # regenera el thumbnail del selector desde una captura real
./wearapp.sh status       # esfera activa + versión + memoria
./wearapp.sh log          # logcat filtrado
./wearapp.sh uninstall    # desinstala y vuelve a la esfera de fábrica
```

Qué hace:

- **Hora** grande (`sans-serif-light`), 12/24 h según el sistema, y **fecha** en mayúsculas con
  `letterSpacing`. Se redibuja exactamente en el borde del minuto (`postDelayed` calculado), no
  cada segundo: en un reloj de 400 mAh eso importa.
- **Anillo de batería** desde las 12 en sentido horario, con track oscuro. Azul normal, verde
  mientras carga y rojo por debajo del 15 %.
- **Chip de complicación** tocable en la parte inferior. Proveedor por defecto:
  `BatteryComplicationProvider` (nuestro, publica `87%` + título `BAT`), así que nunca sale vacío.
  Al tocarlo se abre el selector de complicaciones del sistema (`ComplicationHelperActivity`), y
  si la complicación trae su propio `tapAction` se lanza ese. Feedback de pulsación con
  `setIsHighlighted`.
- **Ambiente / burn-in / low-bit** implementados (blanco sobre negro, sin degradado, desplazamiento
  antipixelado y AA desactivado si el panel es low-bit). Este panel es **LCD sin always-on** (no
  existe ajuste de ambiente en `settings`), así que al dormir la pantalla se apaga del todo y no
  hay frame que ver; el código está listo si se prueba en otro reloj.

Decisiones técnicas verificadas (no obvias):

- `androidx.wear:wear:1.4.0` **no trae** las clases de esfera ni de complicaciones. Hay que usar
  `com.google.android.support:wearable:2.9.0`, la última que conserva `android.support.wearable.watchface.*`;
  ya depende sólo de AndroidX, así que **no hace falta Jetifier**.
- Sin NDK y sin librerías nativas: APK 100 % dex (3,5 MB), por eso la CPU **x86** del reloj no
  supone ningún problema.
- `compileSdk 35` + `minSdk/targetSdk 25` (el techo real del reloj). Todas las APIs usadas existen
  en API 25: `setDefaultComplicationProvider`, `ComplicationDrawable`, `Paint.letterSpacing`, etc.
- **JDK 17 obligatorio**: AGP 8.7 no soporta JDK 21+ y Gradle 8.9 con el `openjdk` "latest" de
  Homebrew (27) falla con el críptico `What went wrong: 27`. `wearapp.sh` exporta
  `/opt/homebrew/opt/openjdk@17` (override con `NBR_JAVA_HOME`).
- El selector de esferas del sistema cachea la lista: tras instalar hay que hacer
  `am force-stop com.google.android.wearable.app` (lo hace `wearapp.sh install/face`) o la esfera
  nueva no aparece.
- El thumbnail del selector lo regenera el propio reloj (`WFPFavoritesCache` guarda un PNG en
  `/data/user/0/com.google.android.wearable.app/cache/`), pero además empaquetamos un
  `preview.png` real (400×400, recortado en círculo) en `res/drawable-nodpi/`.

Coste medido: **25 MB PSS** la esfera activa, `MemAvailable` ~175 MB, cero wakeups propios más
allá del tick por minuto.

## ¿Se puede portar una ROM de Galaxy Watch o subir de versión?

**No, por tres motivos independientes**, cada uno suficiente:

- **Arquitectura**: `shasta` es **Intel Atom x86** (`ro.product.cpu.abi=x86`, board `robby`).
  Galaxy Watch (2018) usa Exynos 9110 y Watch4/5/6 usan Exynos W920/W930, todos **ARM**. Un
  binario ARM no se puede ejecutar aquí, y no hay fuentes del kernel de Intel/New Balance para
  recompilar uno.
- **Cadena de arranque**: bootloader Intel `SHASTA-03.54` con particiones propias (sin A/B) e
  imágenes firmadas; una ROM de Samsung trae su propio kernel, `dtb`, layout de particiones y
  `init` de Tizen/Wear-Samsung. No arrancaría ni con el bootloader desbloqueado que tenemos.
- **Drivers**: la ROM destino no tiene `bcmdhd` para el chip Wi-Fi del RunIQ, ni MAX17047,
  LSM6DS3H, bq25898… sin ellos no hay pantalla, batería ni radio.

Y **actualizar a Wear OS 3/4 tampoco**: Google nunca publicó Wear OS 3 para x86 (Intel salió de
wearables en 2016) y el RunIQ se descatalogó en 2018; el techo real de este reloj es Wear OS 2.0
(Android 7.1.1) con Magisk + debloat, que es justo el estado en que lo hemos dejado.

## Pendiente / siguiente paso

- **Relock**: `fastboot flashing lock` sólo con `system`/`boot` de fábrica; con Magisk dentro el
  reloj no volvería a arrancar.
- **Volver a stock**: `fastboot flash boot ota/boot-stock.img` + `fastboot reboot` (revierte el root).
- **Módulos**: `/data/adb/modules` está vacío; se instalan por `adb push` + reinicio o desde la app
  (la UI Wear es muy limitada).
- Si alguna vez `su` no responde, `fastboot boot ota/boot-root-adb.img` da `adb root` en RAM sin
  escribir la partición.
- **Más debloat opcional** (más agresivo, aún reversible):
  `pm disable-user --user 0 com.android.providers.calendar com.google.android.tts
  com.ustwo.watchfaces.hero com.google.android.wearable.setupwizard` — libera ~10 MB más, pero
  quita el calendario de las complicaciones, la voz TTS, las esferas de ustwo y el asistente de
  configuración tras un reset. Los proveedores de contactos (`com.android.providers.contacts`) es
  mejor dejarlos: de ellos salen los nombres en las notificaciones.
- **Esfera propia**: activa (`Pixel NBRiq`). Falta verla **sin cargador** para comprobar el anillo
  azul (y el rojo por debajo del 15 %) y medir el consumo de un ciclo completo.
- **Opción B (launcher propio)** queda aparcada: la app de Wear 2.35 ya trae la lista de apps y
  soporte de tiles, así que aportaría poco y sí costaría RAM.
- Si la 2.35 diera problemas, `adb uninstall com.google.android.wearable.app` devuelve el reloj a
  Wear 2.0.0 al instante (la copia sigue en `/system`).
