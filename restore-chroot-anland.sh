#!/data/data/com.termux/files/usr/bin/bash
# Restore our snapshot and recreate the Termux-side scripts, using shell only.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PREFIX=/data/data/com.termux/files/usr
ROOT=/data/local/anland-ubuntu26
BASE="$HOME/anland-termux"
MANAGER="$HOME/.local/share/chroot-manager/anland"
MODE=${1:-}
write_restore_shortcut() {
 mkdir -p "$HOME/.shortcuts"
 cat > "$HOME/.shortcuts/4-anland-load-snapshot.sh" <<'ANLAND_RESTORE_SHORTCUT'
#!/data/data/com.termux/files/usr/bin/bash
# Use the maintained loader so snapshot restores keep the current runtime fixes.
set -euo pipefail
if [[ $# == 0 ]]; then
 BACKUP="$HOME/ubuntu-anland-backup.tar.gz"
 [[ -f $BACKUP ]] || read -r -p 'Snapshot path: ' BACKUP
 set -- "$BACKUP"
fi
exec bash "$HOME/.local/share/chroot-manager/anland/restore-chroot-anland.sh" "$@"
ANLAND_RESTORE_SHORTCUT
 chmod 755 "$HOME/.shortcuts/4-anland-load-snapshot.sh"
}
case "$MODE" in --check|--overwrite|--shortcuts-only|--runtime-only) shift ;; esac
if [[ $MODE != --shortcuts-only ]]; then
if [[ $MODE != --runtime-only ]]; then
BACKUP=${1:-$HOME/ubuntu-anland-backup.tar.gz}
BACKUP=$(realpath "$BACKUP")
[[ -f $BACKUP ]] || { echo "Snapshot not found: $BACKUP"; exit 1; }
[[ -f $SCRIPT_DIR/uninstall-chroot-anland.sh ]] || { echo 'Place uninstall-chroot-anland.sh beside this loader.'; exit 1; }

# Wrong or damaged archives must not replace an existing system.
tar -tzf "$BACKUP" | (
 VALID=yes
 COUNT=0
 while IFS= read -r ENTRY; do
  ENTRY=${ENTRY#./}
  COUNT=$((COUNT + 1))
  case "$ENTRY" in data/local/anland-ubuntu26|data/local/anland-ubuntu26/*) ;; *) VALID=no ;; esac
  case "/$ENTRY/" in */../*) VALID=no ;; esac
 done
 [[ $VALID == yes && $COUNT -gt 0 ]]
) || { echo 'Not a valid Ubuntu-AnLand snapshot.'; exit 1; }
[[ $MODE != --check ]] || { echo 'Snapshot check passed.'; exit 0; }
[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home ]] || { echo 'Run as the normal Termux user.'; exit 1; }

if [[ $MODE != --overwrite ]] && { [[ -e $BASE || -e $HOME/anland ]] || sudo test -e "$ROOT"; }; then
 echo 'This closes AnLand and replaces its Ubuntu data with the snapshot.'
 read -r -p 'Overwrite the existing AnLand installation? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || { echo 'Cancelled.'; exit 0; }
fi
# The self-contained uninstaller also provides verified stop-only cleanup.
bash "$SCRIPT_DIR/uninstall-chroot-anland.sh" --stop-only
mkdir "$BASE/.uninstalling"
trap 'rmdir "$BASE/.uninstalling" 2>/dev/null || true' EXIT

# Restore exactly as saved. The snapshot archive itself is never changed.
sudo rm -rf "$ROOT"
sudo tar --numeric-owner --xattrs --xattrs-include='*' --acls -xpf "$BACKUP" -C /
sudo mkdir -p "$ROOT"/{proc,sys,dev/pts,run,tmp,sdcard}
sudo chmod 1777 "$ROOT/tmp"
else
 [[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home ]] || { echo 'Run as the normal Termux user.'; exit 1; }
 sudo test -f "$ROOT/etc/passwd" || { echo 'Ubuntu-AnLand is not installed.'; exit 1; }
 # Updating runtime scripts requires a stopped desktop, without replacing Ubuntu.
 if ! su -c 'for p in /proc/[0-9]*/root; do
  [ "$(readlink "$p" 2>/dev/null)" != /data/local/anland-ubuntu26 ] || exit 1
 done'; then
  echo 'Close AnLand before updating its runtime scripts.' >&2
  exit 1
 fi
fi
mkdir -p "$BASE/runtime/anland" "$BASE/logs" "$HOME/.shortcuts/icons"
chmod 1777 "$BASE/runtime"
chmod 711 "$BASE/runtime/anland"

# Migrate older snapshots to the native compositor audio path.
AUDIO_CONFIG=$(mktemp "$PREFIX/tmp/anland-audio-config.XXXXXX.sh")
cat > "$AUDIO_CONFIG" <<'NATIVE_AUDIO_CONFIG'
#!/system/bin/sh
set -eu
ROOT=/data/local/anland-ubuntu26
CONF="$ROOT/etc/pipewire"
if [ -f "$CONF/pipewire.conf.d/95-anland-aaudio.conf" ]; then
 rm -f "$CONF/pipewire.conf.d/95-anland-aaudio.conf"
fi
rm -f "$CONF/pipewire.conf.d/95-anland-aaudio.conf.disabled" "$ROOT/usr/local/bin/anland-benchmark-session"
mkdir -p "$CONF/pipewire-pulse.conf.d" "$CONF/pipewire.conf.d"
if [ -f "$ROOT/usr/local/bin/startplasma-anland" ]; then
 sed -i 's/# The Termux launcher supplies our independent Android AAudio server./# PipeWire Pulse clients use the compositor native audio bridge./' "$ROOT/usr/local/bin/startplasma-anland"
fi
cat > "$CONF/pipewire-pulse.conf.d/95-anland-native.conf" <<'PULSE_CONF'
pulse.properties = {
    server.address = [ "unix:/tmp/pulse/native" ]
    pulse.min.req = 256/48000
    pulse.default.req = 512/48000
    pulse.default.tlength = 2048/48000
    pulse.min.quantum = 256/48000
}
PULSE_CONF
cat > "$CONF/pipewire.conf.d/96-anland-latency.conf" <<'PIPEWIRE_CONF'
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 512
    default.clock.min-quantum = 256
    default.clock.max-quantum = 2048
}
PIPEWIRE_CONF
NATIVE_AUDIO_CONFIG
if ! (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/sh '$AUDIO_CONFIG'"); then
 rm -f "$AUDIO_CONFIG"
 exit 1
fi
rm -f "$AUDIO_CONFIG"

# These plain shell sources run outside Ubuntu and are not in the old snapshot.

# anland.sh
cat > "$BASE/anland.sh.new" <<'END_ANLAND_SH'
#!/data/data/com.termux/files/usr/bin/bash
# Start the separate Ubuntu-Anland desktop. Default: KDE on XWayland :1.
# Usage: anland.sh [desktop|stop|status|safe-mode|rename-user|shell|weston]
# Termux:X11 uses its own files and display; never stop it from this script.
set -euo pipefail
BASE=/data/data/com.termux/files/home/anland-termux
PREFIX=/data/data/com.termux/files/usr
export TMPDIR="$BASE/runtime"
LOGDIR="$BASE/logs"
mkdir -p "$LOGDIR" "$TMPDIR"
# A PID file alone can be stale: verify the executable before reusing/killing it.
service_running() {
 local file=$1 expected=$2 pid actual entry
 [[ -r $file ]] || return 1
 read -r pid < "$file"
 [[ $pid =~ ^[0-9]+$ ]] || return 1
 kill -0 "$pid" 2>/dev/null || return 1
 IFS= read -r -d '' actual < "/proc/$pid/cmdline" || true
 actual=${actual%% *}
 [[ ${actual##*/} == "$expected" ]] || return 1
 # Reading directly avoids a grep -q/SIGPIPE race under pipefail.
 while IFS= read -r -d '' entry; do
  [[ $entry == "TMPDIR=$BASE/runtime" ]] && return 0
 done < "/proc/$pid/environ"
 return 1
}
stop_bridges() {
 for name in daemon bridge; do
  [[ -f "$LOGDIR/$name.pid" ]] || continue
  read -r pid < "$LOGDIR/$name.pid"
  [[ $pid =~ ^[0-9]+$ ]] || continue
  expected=anland
  [[ $name == bridge ]] && expected=anland-compatible
  if service_running "$LOGDIR/$name.pid" "$expected"; then
   kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$LOGDIR/$name.pid"
 done
}
# Status and logout do not create another chroot or display connection.
if [[ ${1:-} == status ]]; then
 unset LD_PRELOAD LD_LIBRARY_PATH
 exec su -c "/system/bin/sh $BASE/stop-chroot.sh status"
fi
if [[ ${1:-} == stop ]]; then
 unset LD_PRELOAD LD_LIBRARY_PATH
 status=0
 su -c "/system/bin/sh $BASE/stop-chroot.sh request" || status=$?
 [[ $status == 10 ]] && exit 0
 [[ $status == 0 ]] || exit "$status"
 stop_bridges
 exit
fi
chmod 1777 "$TMPDIR"
mode=${1:-desktop}
[[ ! -d "$BASE/.uninstalling" ]] || {
 echo 'Anland uninstall is in progress. Finish it before starting another session.'; exit 1;
}
case $mode in
 safe-mode|rename-user|desktop|weston|shell) ;;
 *) echo 'Usage: anland.sh [desktop|weston|shell|stop|status|safe-mode|rename-user]'; exit 2 ;;
esac
# Maintenance console: finish logout, then hold the desktop lock until exit.
if [[ $mode == safe-mode || $mode == rename-user ]]; then
 "$0" stop
 for ((i=0; i<60; i++)); do
  "$0" status | grep -q '"stopped": true' && break
  sleep 1
 done
 "$0" status | grep -q '"stopped": true' || { echo 'Anland is still running. Finish logout before entering safe mode.'; exit 1; }
 exec 9>"$LOGDIR/session.lock"
 flock -n 9 || { echo 'Another Anland session is running.'; exit 1; }
 "$0" status | grep -q '"stopped": true' || { echo 'Anland started during logout; try again.'; exit 1; }
 unset LD_PRELOAD LD_LIBRARY_PATH
 trap 'su -c "/system/bin/sh $BASE/stop-chroot.sh"' EXIT
 trap 'exit 130' INT
 trap 'exit 143' TERM
 su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh $BASE/enter-chroot.sh $mode" 9>&-
 exit
fi
graphical=0
case $mode in desktop|weston) graphical=1 ;; esac
if [[ $graphical == 1 ]]; then
 # Only one desktop owns this runtime directory at a time.
 exec 9>"$LOGDIR/session.lock"
 flock -n 9 || { echo 'Anland already has a desktop or safe-mode session running. Finish that session first.'; exit 1; }
 # Keep ordinary launches diagnosable too; tee must not retain the session lock.
 exec > >(tee -a "$LOGDIR/session.log" 9>&-) 2>&1
 printf '\nAnland %s: %s\n' "$mode" "$(date -Iseconds)"
 cleanup() {
  trap - EXIT INT TERM
  echo "Desktop exited; completing Anland shutdown..."
  if su -c "/system/bin/sh $BASE/stop-chroot.sh"; then stop_bridges; fi
 }
 trap cleanup EXIT
 trap 'exit 130' INT
 trap 'exit 143' TERM
fi
# Start our private display daemon; wait for a NEW listening socket, not a stale one.
if [[ ! -S "$TMPDIR/anland/display_daemon.sock" ]] || ! service_running "$LOGDIR/daemon.pid" anland; then
 nohup "$PREFIX/bin/anland" >"$LOGDIR/daemon.log" 2>&1 </dev/null 9>&- &
 echo $! > "$LOGDIR/daemon.pid"
 for ((i=0; i<50; i++)); do
  # The previous run may have left a socket. Wait for this daemon to listen.
  if service_running "$LOGDIR/daemon.pid" anland &&
     [[ -S "$TMPDIR/anland/display_daemon.sock" ]] &&
     grep -q 'daemon: listening on ' "$LOGDIR/daemon.log"; then break; fi
  sleep 0.1
 done
fi
service_running "$LOGDIR/daemon.pid" anland &&
 [[ -S "$TMPDIR/anland/display_daemon.sock" ]] &&
 grep -q 'daemon: listening on ' "$LOGDIR/daemon.log" || { echo "Daemon failed; see $LOGDIR/daemon.log"; exit 1; }
if ! service_running "$LOGDIR/bridge.pid" anland-compatible; then
 # This bridge connects the Termux daemon to the Anland Android app.
 nohup "$PREFIX/bin/anland-compatible" >"$LOGDIR/bridge.log" 2>&1 </dev/null 9>&- &
 echo $! > "$LOGDIR/bridge.pid"
fi
unset LD_PRELOAD LD_LIBRARY_PATH
# unshare gives Anland private mounts. The kernel releases them on session exit.
if [[ $graphical == 1 ]]; then
 # Give the compatible bridge and Android surface time to become available
 # before the compositor tries to import its buffers.
 su -c '/system/bin/cmd activity start -n com.anland.termux/.MainActivity </dev/null >/dev/null 2>&1'
 ready=0
 for ((i=0; i<150; i++)); do
  if service_running "$LOGDIR/bridge.pid" anland-compatible &&
     grep -qE 'consumer connected|consumer re-deposited' "$LOGDIR/daemon.log"; then ready=1; break; fi
  sleep 0.1
 done
 [[ $ready == 1 ]] || { echo "Anland display did not become ready; see $LOGDIR/bridge.log and daemon.log."; exit 1; }
 su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh $BASE/enter-chroot.sh $mode" 9>&-
else
 exec su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh $BASE/enter-chroot.sh $mode"
fi
END_ANLAND_SH
chmod 700 "$BASE/anland.sh.new"
mv -f "$BASE/anland.sh.new" "$BASE/anland.sh"

# enter-chroot.sh
cat > "$BASE/enter-chroot.sh.new" <<'END_ENTER_CHROOT_SH'
#!/system/bin/sh
set -eu
ROOT=/data/local/anland-ubuntu26
PREFIX=/data/data/com.termux/files/usr
MODE=${1:-desktop}
# The desktop account keeps its UID when renamed. Resolve its current name.
DESKTOP_UID=$(cat "$ROOT/etc/anland-user.uid" 2>/dev/null || echo 1001)
CHROOT_USER=
DESKTOP_GID=
while IFS=: read -r LOGIN PASSWORD USER_UID USER_GID DESCRIPTION USER_HOME USER_SHELL; do
 if [ "$USER_UID" = "$DESKTOP_UID" ] && [ "$USER_UID" -ge 1000 ]; then
  CHROOT_USER=$LOGIN
  DESKTOP_GID=$USER_GID
  break
 fi
done < "$ROOT/etc/passwd"
case "$MODE" in
 safe-mode|rename-user) ;;
 *) [ -n "$CHROOT_USER" ] || { echo 'Anland desktop account not found.' >&2; exit 1; } ;;
esac
if [ "$MODE" = desktop ] || [ "$MODE" = weston ]; then
 if /system/bin/grep -Eq "[[:space:]]@?/tmp/\.X11-unix/X1$" /proc/net/unix; then
  echo "Display :1 is already in use. Refusing to interfere with that session." >&2
  exit 1
 fi
 /system/bin/cmd activity start -n com.anland.termux/.MainActivity </dev/null >/dev/null 2>&1 || echo 'Open Anland Termux to view the desktop.'
fi
# This script runs inside a private mount namespace created by the launcher.
mount --bind "$ROOT" "$ROOT"
mount -o remount,bind,suid,dev "$ROOT"
mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount --bind /data/data/com.termux/files/home/anland-termux/runtime "$ROOT/tmp"
mount -t tmpfs -o mode=755 tmpfs "$ROOT/run"
# Package hooks must recognize this chroot and avoid host binfmt registration.
mkdir -p "$ROOT/run/systemd"
printf 'chroot\n' > "$ROOT/run/systemd/container"
# Do privileged setup before dropping to the desktop account; no passwordless sudo.
mkdir -p "$ROOT/tmp/.X11-unix"
chmod 1777 "$ROOT/tmp/.X11-unix"
# ICE session sockets require a root-owned, world-writable sticky directory.
mkdir -p "$ROOT/tmp/.ICE-unix"
chown 0:0 "$ROOT/tmp/.ICE-unix"
chmod 1777 "$ROOT/tmp/.ICE-unix"
if [ -n "$CHROOT_USER" ]; then
 # The chroot user owns the single PipeWire Pulse endpoint.
 mkdir -p "$ROOT/tmp/pulse"
 chown "$DESKTOP_UID:$DESKTOP_GID" "$ROOT/tmp/pulse"
 chmod 700 "$ROOT/tmp/pulse"
 for runtime in "$ROOT/run/anland/$DESKTOP_UID" "$ROOT/run/user/$DESKTOP_UID"; do
  mkdir -p "$runtime"
  chown "$DESKTOP_UID:$DESKTOP_GID" "$runtime"
  chmod 700 "$runtime"
 done
fi
mkdir -p "$ROOT/tmp/anland"
# The Termux daemon must own its socket directory even after root maintenance.
chown "$(stat -c '%u:%g' /data/data/com.termux/files/home/anland-termux/runtime)" "$ROOT/tmp/anland"
chmod 711 "$ROOT/tmp/anland"
if [ -S "$ROOT/tmp/anland/display_daemon.sock" ]; then
 chmod 666 "$ROOT/tmp/anland/display_daemon.sock"
fi
case "$MODE" in
 safe-mode)
 echo 'Ubuntu-Anland SAFE MODE — root terminal, KDE is stopped.'
 echo 'Run rename_user.sh to rename the desktop account. Type exit when finished.'
 exec chroot "$ROOT" /usr/bin/env -i HOME=/root USER=root LOGNAME=root TERM=xterm-256color LANG=en_US.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin PS1='Anland-safe \w # ' /bin/bash --noprofile --norc -i ;;
 rename-user) exec chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /opt/rename_user.sh ;;
 desktop) COMMAND='export FD_MESA_DEBUG=noubwc,notile; mkdir -p "$HOME/anland-logs"; exec /usr/local/bin/startplasma-anland' ;;
 weston) COMMAND='export ANLAND_WESTON_SCALE=2 FD_MESA_DEBUG=noubwc,notile; exec startweston-anland' ;;
 shell) COMMAND='exec bash -l' ;;
 *) echo 'Unknown mode' >&2; exit 2 ;;
esac
exec chroot "$ROOT" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=en_US.UTF-8 PATH=/opt/lfdevs/anland:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/su - "$CHROOT_USER" -c "$COMMAND"
END_ENTER_CHROOT_SH
chmod 700 "$BASE/enter-chroot.sh.new"
mv -f "$BASE/enter-chroot.sh.new" "$BASE/enter-chroot.sh"

# Install the shared shell cleanup helper.
bash "$SCRIPT_DIR/uninstall-chroot-anland.sh" --print-stop-script > "$BASE/stop-chroot.sh.new"
chmod 700 "$BASE/stop-chroot.sh.new"
mv -f "$BASE/stop-chroot.sh.new" "$BASE/stop-chroot.sh"
rm -f "$HOME/anland" "$HOME/anland.sh"
# Remove obsolete runtime helpers when upgrading an older installation.
rm -f "$BASE/stop-chroot.cjs" "$BASE/start-audio.sh" "$BASE/benchmark-session.sh"
mkdir -p "$MANAGER"
for FILE in uninstall-chroot-anland.sh restore-chroot-anland.sh; do
 if [[ $(realpath "$SCRIPT_DIR/$FILE") != "$MANAGER/$FILE" ]]; then
  install -m 700 "$SCRIPT_DIR/$FILE" "$MANAGER/$FILE"
 fi
done

fi
if [[ $MODE == --runtime-only ]]; then
 write_restore_shortcut
 echo 'AnLand runtime updated; Ubuntu data and shortcuts were kept.'
 exit 0
fi
# Number scripts and matching icons; accept legacy and numbered snapshots.
mkdir -p "$HOME/.shortcuts/icons"
while read -r NUMBER LABEL LEGACY; do
 NAME="$NUMBER-anland-$LABEL.sh"
 SOURCE=
 if [[ $MODE == --shortcuts-only ]]; then
  for OLD in "$NAME" "anland-$LEGACY.sh"; do
   [[ ! -f $HOME/.shortcuts/$OLD ]] || { SOURCE="$HOME/.shortcuts/$OLD"; break; }
  done
 fi
 if [[ -n $SOURCE ]]; then
  cp "$SOURCE" "$HOME/.shortcuts/$NAME.new"
 else
  for OLD in "$NAME" "anland-$LEGACY.sh"; do
   if sudo test -f "$ROOT/opt/.shortcuts-anland/$OLD"; then SOURCE="$ROOT/opt/.shortcuts-anland/$OLD"; break; fi
  done
  [[ -n $SOURCE ]] || { echo "Missing snapshot shortcut: $NAME" >&2; exit 1; }
  sudo cp "$SOURCE" "$HOME/.shortcuts/$NAME.new"
  sudo chown "$(id -u):$(id -g)" "$HOME/.shortcuts/$NAME.new"
 fi
 SCRIPT_SOURCE=$SOURCE
 ICON="$HOME/.shortcuts/icons/$NAME.png"
 if [[ $MODE != --shortcuts-only || ! -f $ICON ]]; then
  SOURCE=
  if [[ $MODE == --shortcuts-only && -f $HOME/.shortcuts/icons/anland-$LEGACY.sh.png ]]; then
   cp "$HOME/.shortcuts/icons/anland-$LEGACY.sh.png" "$ICON"
  else
   for OLD in "$NAME" "anland-$LEGACY.sh"; do
    if sudo test -f "$ROOT/opt/.shortcuts-anland/icons/$OLD.png"; then SOURCE="$ROOT/opt/.shortcuts-anland/icons/$OLD.png"; break; fi
   done
   [[ -n $SOURCE ]] || { echo "Missing snapshot icon: $NAME" >&2; exit 1; }
   sudo cp "$SOURCE" "$ICON"
   sudo chown "$(id -u):$(id -g)" "$ICON"
  fi
 fi
 chmod 755 "$HOME/.shortcuts/$NAME.new"
 chmod 644 "$ICON"
 mv -f "$HOME/.shortcuts/$NAME.new" "$HOME/.shortcuts/$NAME"
 if [[ ${SCRIPT_SOURCE##*/} == anland-*.sh ]]; then
  sed -i 's#/data/data/com.termux/files/home/anland\([[:space:]]\|$\)#/data/data/com.termux/files/home/anland-termux/anland.sh\1#g; s#\./anland\([[:space:]]\|$\)#/data/data/com.termux/files/home/anland-termux/anland.sh\1#g' "$HOME/.shortcuts/$NAME"
 fi
 rm -f "$HOME/.shortcuts/anland-$LEGACY.sh" "$HOME/.shortcuts/icons/anland-$LEGACY.sh.png"
done <<'SHORTCUT_NAMES'
1 run start
2 safe-mode safe-mode
3 save-snapshot save-backup
4 load-snapshot restore-backup
5 stop stop
SHORTCUT_NAMES
# Save only this desktop's numbered shortcuts and their matching icons.
sed -i 's#~/.shortcuts/anland-\*\.sh#~/.shortcuts/[0-9]*-anland-*.sh#g; s#~/.shortcuts/icons/anland-\*\.sh\.png#~/.shortcuts/icons/[0-9]*-anland-*.sh.png#g' "$HOME/.shortcuts/3-anland-save-snapshot.sh"
# The snapshot may contain an old embedded installer; always use the maintained loader.
write_restore_shortcut
echo 'Ubuntu-AnLand shortcuts ready. Use 1-anland-run.'
