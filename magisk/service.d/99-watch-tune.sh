#!/system/bin/sh
# Instalado por debloat.sh (NBRiq) como /data/adb/service.d/99-watch-tune.sh.
# Se ejecuta como root en cada arranque.
#
# - Animaciones a 0: menos trabajo de GPU/CPU al abrir apps.
# - screen_off_timeout: la app de Ajustes de Wear lo reescribe a 30 s al arrancar,
#   así que se vuelve a poner aquí (15 s) pasada la ventana de arranque.
# - La app de Magisk ocupa ~53 MB y aquí no hace falta: magiskd vive en la
#   partición boot y `su` sigue funcionando. Se para tras el arranque.
setprop nbr.tune.start 1
(
  sleep 60
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  settings put system screen_off_timeout 15000
  am force-stop com.topjohnwu.magisk
  setprop nbr.tune.done 1
) &
