# ⚠️ Aviso de responsabilidad (brick, garantía y datos)

**Lee esto antes de tocar nada.** Todo lo que hay en este repositorio se hizo y se probó
sobre **mi propio reloj** (un New Balance RunIQ con el firmware `NWD1.171016.002`). Se
comparte porque a mí me sirvió, **no porque sea seguro para tu dispositivo**.

## Lo que estás a punto de hacer

| Acción | Consecuencia real |
|---|---|
| `fastboot flashing unlock` | **Borra todo** (`/data`): configuración, apps, sesiones, datos de salud. El reloj vuelve al asistente de fábrica. |
| `fastboot flash boot …` | Si la imagen no es la de tu firmware, el reloj **no arranca** (bootloop o pantalla negra). |
| Root con Magisk | Cualquier app con root puede leer/escribir todo. Si instalas algo malicioso, el daño es total. |
| `magiskpolicy --live` (SELinux) | Baja la protección del sistema mientras esté aplicado. Por eso **no persiste** al reiniciar. |
| `pm disable-user` (debloat) | Puede desactivar algo que necesitas (avisos, calendario, asistente). Es reversible, pero hay que saber deshacerlo. |
| Cambiar el serial / props | Apps que se basan en ellos (licencias, garantías, servicios) pueden comportarse raro o dejar de funcionar. |

## No hay garantía de nada

- **Ni el autor ni los colaboradores nos hacemos responsables** de ningún daño directo o
  indirecto: reloj bloqueado ("brick" total o parcial), pérdida de datos, pérdida de
  garantía, problemas de batería, inestabilidad, reinicios, imposibilidad de actualizar, o
  cualquier otro perjuicio derivado de seguir esta documentación o de usar estos scripts.
- **Lo usas bajo tu propio riesgo y tu propia responsabilidad.** Si no entiendes un paso,
  no lo ejecutes.
- El software se ofrece **"tal cual"**, sin garantía de ningún tipo, tal y como establece la
  [licencia MIT](LICENSE) de este repositorio.
- Lo probado aquí es **un dispositivo concreto con un firmware concreto**. Otro RunIQ, otra
  revisión de hardware, otro `bootloader` o una actualización distinta pueden necesitar
  imágenes y pasos diferentes. No des por hecho que funcionará igual.

## Cosas que pueden salir mal (y pasaron en esta sesión)

- Reinicios aleatorios por el **watchdog del kernel** de este ROM (`Oops` en `ipt_do_table`
  dentro de `suspend_enter`): no es culpa del root, pero convive con él.
- `magiskd` puede morir y `su` falla con `SIGILL`; se recupera reiniciando.
- Un `boot` parcheado que no corresponde → **no arranca**. La variante "slim" que probamos
  (`boot-magisk-slim.img`) es justo un ejemplo: no funciona y se guarda solo como evidencia.
- `fastboot flashing lock` con Magisk dentro → el reloj **no vuelve a arrancar**. No lo hagas
  hasta tener `boot` de fábrica.

## Antes de empezar: cómo reducir el riesgo

1. **Copia de seguridad** de lo que te importe (`adb pull /sdcard`, ajustes, listas de apps).
2. Guarda una **imagen de tu `boot` original** antes de flashear cualquier cosa
   (en este repo tienes `ota/boot-stock.img`, pero el tuyo puede ser distinto).
3. Prueba siempre con `fastboot boot imagen.img` (**arranca en RAM, no escribe**) antes de
   usar `fastboot flash`.
4. Ten a mano `fastboot` y el firmware original. Si algo va mal, ahí está tu salida.
5. No bloquees el bootloader de nuevo hasta estar seguro de que el reloj arranca bien.

## Si algo va mal

- El reloj no arranca pero entra en `fastboot` → recuperable: `fastboot flash boot boot-stock.img`.
- No entra ni en `fastboot` → probablemente solo quede el servicio técnico (y con el
  bootloader desbloqueado, la garantía no cubre).
- Arranca pero con cosas raras → `./scripts/debloat.sh restore` y quita Magisk
  (`fastboot flash boot` de fábrica).

---

## English (short version)

**Use this at your own risk.** Everything here was tested on **my own watch** (New Balance
RunIQ, firmware `NWD1.171016.002`) and is shared as-is, with **no warranty of any kind**.
Unlocking the bootloader **wipes the device**; flashing a wrong `boot` image can **brick** it.
Neither the author nor any contributor is liable for any damage, data loss, voided warranty or
any other harm resulting from following this documentation or running these scripts. If you
don't understand a step, don't run it. Licensed under MIT (see [LICENSE](LICENSE)).
