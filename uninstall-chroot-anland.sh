#!/data/data/com.termux/files/usr/bin/bash
# Uninstall only Ubuntu-AnLand. --stop-only safely stops it without deleting it.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
BASE="$HOME/anland-termux"
ROOT=/data/local/anland-ubuntu26

# The loader uses this same shell helper for status, logout and force cleanup.
if [[ ${1:-} == --print-stop-script ]]; then
 cat <<'ANLAND_STOP_SCRIPT'
#!/system/bin/sh
# Called as root. Only this AnLand chroot and its private services are selected.
PREFIX=/data/data/com.termux/files/usr
ROOT=/data/local/anland-ubuntu26
BASE=/data/data/com.termux/files/home/anland-termux
export PATH="$PREFIX/bin:/system/bin" LC_ALL=C
unset LD_PRELOAD LD_LIBRARY_PATH
MODE=${1:-stop}

# Get the chroot's processes without selecting Android processes by shared UID.
chroot_pids() {
 stat -c '%N' /proc/[0-9]*/root 2>/dev/null |
  grep -F " -> '$ROOT'" |
  cut -d / -f 3
}
PIDS=$(chroot_pids)
# Include only the display/audio services using AnLand's private runtime.
for PID in $(pgrep -f "^($PREFIX/bin/)?(anland|anland-compatible|pulseaudio)( |$)"); do
 if tr '\000' '\n' < "/proc/$PID/environ" 2>/dev/null | grep -Fx "TMPDIR=$BASE/runtime" >/dev/null; then
  PIDS="$PIDS $PID"
 fi
done

# Keep normal KDE logout and its save dialogs working.
if [ "$MODE" = request ]; then
 for PID in $PIDS; do
  [ "$(cat "/proc/$PID/comm" 2>/dev/null)" = kwin_wayland ] || continue
  UID_NUMBER=$(cat "$ROOT/etc/anland-user.uid") || exit 1
  USER_NAME=
  while IFS=: read -r LOGIN PASSWORD USER_UID REST; do
   [ "$USER_UID" = "$UID_NUMBER" ] || continue
   USER_NAME=$LOGIN
   break
  done < "$ROOT/etc/passwd"
  [ -n "$USER_NAME" ] || exit 1
  nsenter -t "$PID" -m chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/bin:/bin /bin/su - "$USER_NAME" -c '
   export XDG_RUNTIME_DIR=/run/anland/$(id -u)
   export DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG_RUNTIME_DIR/session-bus-address")"
   exec qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
  ' || exit 1
  exit 10
 done
fi

if [ "$MODE" != status ]; then
 # Uninstall/replacement: KILL directly. Normal logout: allow processes to exit.
 SIGNAL=TERM
 [ "$MODE" != force ] || SIGNAL=KILL
 for PID in $PIDS; do kill -"$SIGNAL" "$PID" 2>/dev/null || true; done
 /system/bin/am force-stop com.anland.termux
 sleep 1

 # Private mounts disappear when their processes exit. Unmount leftovers here.
 for DIR in dev/pts dev proc sys sdcard tmp run; do
  mountpoint -q "$ROOT/$DIR" && umount -R "$ROOT/$DIR"
 done
 mountpoint -q "$ROOT" && umount -R "$ROOT"
fi

# Do not delete a rootfs still used by a process or another mount namespace.
LEFT=$(chroot_pids)
for PID in $(pgrep -f "^($PREFIX/bin/)?(anland|anland-compatible|pulseaudio)( |$)"); do
 if tr '\000' '\n' < "/proc/$PID/environ" 2>/dev/null | grep -Fx "TMPDIR=$BASE/runtime" >/dev/null; then
  LEFT="$LEFT $PID"
 fi
done
MOUNTS=$(grep -h -F -e '/local/anland-ubuntu26' -e '/anland-termux/runtime' /proc/[0-9]*/mountinfo 2>/dev/null | sort -u)
if [ -n "$LEFT$MOUNTS" ]; then
 [ -z "$LEFT" ] || echo "AnLand processes still running: $LEFT" >&2
 [ -z "$MOUNTS" ] || printf 'Mounts still present:\n%s\n' "$MOUNTS" >&2
 echo '{ "stopped": false }'
 [ "$MODE" = status ] && exit 0
 exit 1
fi
echo '{ "stopped": true }'
ANLAND_STOP_SCRIPT
 exit 0
fi

[[ $HOME == /data/data/com.termux/files/home && $(id -u) != 0 ]] || {
 echo 'Run this as the normal Termux user.'; exit 1;
}
case ${1:-} in
 --stop-only) ;;
 '')
  echo 'This removes Ubuntu-AnLand, its app, daemon and shortcuts.'
  echo 'Running AnLand programs will be closed. Backups and Termux-X11 are kept.'
  read -r -p 'Uninstall AnLand? [y/N] ' ANSWER
  [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0 ;;
 *) echo 'Usage: bash uninstall-chroot-anland.sh [--stop-only]'; exit 1 ;;
esac
[[ ! -L $BASE && ! -L $ROOT ]] || { echo 'Unexpected AnLand directory symlink; nothing removed.'; exit 1; }

# Kill AnLand and unmount its rootfs before deleting it.
CONTROL=$(mktemp "$PREFIX/tmp/anland-cleanup.XXXXXX.sh")
trap 'rm -f "$CONTROL"' EXIT
bash "$0" --print-stop-script > "$CONTROL"
mkdir -p "$BASE"
mkdir "$BASE/.uninstalling" || { echo 'Another AnLand operation is in progress.'; exit 1; }
trap 'rm -f "$CONTROL"; rmdir "$BASE/.uninstalling" 2>/dev/null || true' EXIT
if ! (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/sh '$CONTROL' force"); then
 echo 'Nothing deleted. Fix the remaining processes/mounts reported above.' >&2
 exit 1
fi
[[ ${1:-} != --stop-only ]] || exit 0

# Cleanup succeeded: deletion is now safe and limited to AnLand.
sudo rm -rf "$ROOT"
if su -c '/system/bin/pm path com.anland.termux </dev/null 2>&1' | grep '^package:' >/dev/null; then
 su -c '/system/bin/pm uninstall com.anland.termux </dev/null 2>&1' | cat
fi
if dpkg-query -W -f='${Status}' anland 2>/dev/null | grep 'install ok installed' >/dev/null; then
 dpkg -r anland
fi
for NAME in start stop safe-mode save-backup restore-backup; do
 rm -f "$HOME/.shortcuts/anland-$NAME.sh" "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
done
for NAME in 1-anland-run 2-anland-safe-mode 3-anland-save-snapshot 4-anland-load-snapshot 5-anland-stop; do
 rm -f "$HOME/.shortcuts/$NAME.sh" "$HOME/.shortcuts/icons/$NAME.sh.png"
done
rm -f "$HOME/anland" "$HOME/anland.sh"
sudo rm -rf "$BASE"
echo 'AnLand uninstalled. Backups and your other Ubuntu were kept.'
