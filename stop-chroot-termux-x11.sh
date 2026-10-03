#!/data/data/com.termux/files/usr/bin/bash
# Stop only the regular Ubuntu and its X11/audio services.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
ROOT=/data/local/ubuntu
sudo /system/bin/sh -c '
 for entry in /proc/[0-9]*/root; do
  [ "$(readlink "$entry" 2>/dev/null)" = /data/local/ubuntu ] || continue
  pid=${entry#/proc/}; pid=${pid%/root}
  kill -KILL "$pid" 2>/dev/null || true
 done
'
pkill -x termux-x11 2>/dev/null || true
pkill -f 'app_process / com.termux.x11' 2>/dev/null || true
PULSE_RUNTIME_PATH="$PREFIX/var/run/pulse" pulseaudio --kill 2>/dev/null || true
# Do not lazily detach busy mounts before removing or archiving their directories.
for DIR in proc sys dev/pts dev sdcard tmp/.X11-unix tmp/pulse; do
 if sudo mountpoint -q "$ROOT/$DIR"; then sudo umount -R "$ROOT/$DIR"; fi
done
if sudo mountpoint -q "$ROOT"; then sudo umount -R "$ROOT"; fi
if sudo grep -F '/local/ubuntu/' /proc/self/mountinfo; then
 echo 'Ubuntu still has mounted paths. Nothing will be deleted.' >&2
 exit 1
fi
