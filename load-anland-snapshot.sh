#!/data/data/com.termux/files/usr/bin/bash
# Restore our snapshot and recreate the Termux-side scripts, using shell only.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PREFIX=/data/data/com.termux/files/usr
ROOT=/data/local/anland-ubuntu26
BASE="$HOME/anland-termux"
MODE=${1:-}
case "$MODE" in --check|--overwrite) shift ;; esac
BACKUP=${1:-$HOME/ubuntu-anland-backup.tar.gz}
BACKUP=$(realpath "$BACKUP")
[[ -f $BACKUP ]] || { echo "Snapshot not found: $BACKUP"; exit 1; }
[[ -f $SCRIPT_DIR/uninstall-anland.sh ]] || { echo 'Place uninstall-anland.sh beside this loader.'; exit 1; }

# Wrong or damaged archives must not replace an existing system.
tar -tzf "$BACKUP" | awk '
 {sub(/^\.\//, "")}
 $0 !~ /^data\/local\/anland-ubuntu26(\/|$)/ || $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1}
 END {exit bad || NR == 0}' || { echo 'Not a valid Ubuntu-AnLand snapshot.'; exit 1; }
[[ $MODE != --check ]] || { echo 'Snapshot check passed.'; exit 0; }
[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home ]] || { echo 'Run as the normal Termux user.'; exit 1; }

if [[ $MODE != --overwrite ]] && { [[ -e $BASE || -e $HOME/anland ]] || sudo test -e "$ROOT"; }; then
 echo 'This closes AnLand and replaces its Ubuntu data with the snapshot.'
 read -r -p 'Overwrite the existing AnLand installation? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || { echo 'Cancelled.'; exit 0; }
fi
# The self-contained uninstaller also provides verified stop-only cleanup.
bash "$SCRIPT_DIR/uninstall-anland.sh" --stop-only
mkdir "$BASE/.uninstalling"
trap 'rmdir "$BASE/.uninstalling" 2>/dev/null || true' EXIT

# Restore exactly as saved. The snapshot archive itself is never changed.
sudo rm -rf "$ROOT"
sudo tar --numeric-owner --xattrs --xattrs-include='*' --acls -xpf "$BACKUP" -C /
sudo mkdir -p "$ROOT"/{proc,sys,dev/pts,run,tmp,sdcard}
sudo chmod 1777 "$ROOT/tmp"
mkdir -p "$BASE/runtime/anland" "$BASE/logs" "$HOME/.shortcuts/icons"
chmod 1777 "$BASE/runtime"
chmod 711 "$BASE/runtime/anland"

# These plain shell sources run outside Ubuntu and are not in the old snapshot.

# anland.sh
cat > "$BASE/anland.sh.new" <<'END_ANLAND_SH'
#!/data/data/com.termux/files/usr/bin/bash
# Start the separate Ubuntu-Anland desktop. Default: KDE on XWayland :1.
# Usage: ./anland [desktop|stop|status|safe-mode|rename-user|shell|weston|benchmark]
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
 for name in daemon bridge audio; do
  [[ -f "$LOGDIR/$name.pid" ]] || continue
  read -r pid < "$LOGDIR/$name.pid"
  [[ $pid =~ ^[0-9]+$ ]] || continue
  expected=anland
  [[ $name == bridge ]] && expected=anland-compatible
  [[ $name == audio ]] && expected=pulseaudio
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
 safe-mode|rename-user|desktop|weston|shell|check|test|install-benchmark|benchmark|build-backend|install-godot|godot|maintenance|session-command) ;;
 *) echo 'Usage: ~/anland [desktop|weston|shell|check|benchmark|stop]'; exit 2 ;;
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
# Installer/maintenance commands need the chroot but not an Android display.
case $mode in
 maintenance|session-command|build-backend|install-benchmark|install-godot)
 unset LD_PRELOAD LD_LIBRARY_PATH
 exec su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh $BASE/enter-chroot.sh $mode" ;;
esac
graphical=0
case $mode in desktop|weston|benchmark|test|godot) graphical=1 ;; esac
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
# Use an independent instance of Termux’s proven AAudio backend.
if ! service_running "$LOGDIR/audio.pid" pulseaudio ||
   ! timeout 2 "$PREFIX/bin/pactl" --server="unix:$TMPDIR/pulse/native" info >/dev/null 2>&1; then
 # A surviving process may have lost its listening socket. Replace only ours.
 if service_running "$LOGDIR/audio.pid" pulseaudio; then
  read -r audio_pid < "$LOGDIR/audio.pid"
  sudo kill -KILL "$audio_pid"
 fi
 "$BASE/start-audio.sh"
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
CHROOT_USER=$(awk -F: -v uid="$DESKTOP_UID" '$3 == uid && $3 >= 1000 {print $1; exit}' "$ROOT/etc/passwd")
case "$MODE" in
 safe-mode|rename-user|maintenance|build-backend) ;;
 *) [ -n "$CHROOT_USER" ] || { echo 'Anland desktop account not found.' >&2; exit 1; } ;;
esac
if [ "$MODE" = session-command ]; then
 for proc in /proc/[0-9]*; do
  [ "$(readlink "$proc/root" 2>/dev/null || true)" = "$ROOT" ] || continue
  [ "$(cat "$proc/comm" 2>/dev/null || true)" = kwin_wayland ] || continue
  exec "$PREFIX/bin/nsenter" -t "${proc##*/}" -m chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/su - "$CHROOT_USER" -c 'export XDG_RUNTIME_DIR=/run/anland/$(id -u); export DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG_RUNTIME_DIR/session-bus-address")"; export WAYLAND_DISPLAY=wayland-0 DISPLAY=:1 QT_QPA_PLATFORM=wayland; exec bash /tmp/session-command.sh'
 done
 echo 'No KDE session running.' >&2
 exit 1
fi
if [ "$MODE" = desktop ] || [ "$MODE" = weston ] || [ "$MODE" = test ] || [ "$MODE" = benchmark ] || [ "$MODE" = godot ]; then
 if /system/bin/grep -Eq "[[:space:]]@?/tmp/\.X11-unix/X1$" /proc/net/unix; then
  echo "Display :1 is already in use. Refusing to interfere with that session." >&2
  exit 1
 fi
 /system/bin/cmd activity start -n com.anland.termux/.MainActivity </dev/null >/dev/null 2>&1 || echo 'Open Anland Termux to view the desktop.'
fi
if [ "$MODE" = godot ]; then
 for proc in /proc/[0-9]*; do
  [ "$(readlink "$proc/root" 2>/dev/null || true)" = "$ROOT" ] || continue
  [ "$(cat "$proc/comm" 2>/dev/null || true)" = weston ] || continue
  exec "$PREFIX/bin/nsenter" -t "${proc##*/}" -m chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/su - "$CHROOT_USER" -c 'exec godot --project-manager > "$HOME/anland-logs/godot.log" 2>&1'
 done
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
 DESKTOP_GID=$(awk -F: -v uid="$DESKTOP_UID" '$3 == uid {print $4; exit}' "$ROOT/etc/passwd")
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
 maintenance)
 cp /data/data/com.termux/files/home/anland-termux/maintenance.sh "$ROOT/tmp/anland-maintenance.sh"
 exec chroot "$ROOT" /usr/bin/env -i HOME=/root DEBIAN_FRONTEND=noninteractive PATH=/opt/lfdevs/anland:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /tmp/anland-maintenance.sh ;;
 godot)
 cp /data/data/com.termux/files/home/anland-termux/benchmark-session.sh "$ROOT/usr/local/bin/anland-benchmark-session"
 chmod 755 "$ROOT/usr/local/bin/anland-benchmark-session"
 COMMAND='exec /usr/local/bin/anland-benchmark-session godot' ;;
 install-godot)
 mkdir -p "$ROOT/opt/godot"
 cp /data/data/com.termux/files/home/anland-termux/downloads/godot4/Godot* "$ROOT/opt/godot/godot"
 chmod 755 "$ROOT/opt/godot/godot"
 cp /data/data/com.termux/files/home/anland-termux/godot-chroot "$ROOT/usr/local/bin/godot"
 chmod 755 "$ROOT/usr/local/bin/godot"
 printf '#!/bin/bash\npkill -TERM -u "$(id -u)" -x weston\n' > "$ROOT/usr/local/bin/anland-exit"
 chmod 755 "$ROOT/usr/local/bin/anland-exit"
 exec chroot "$ROOT" /usr/bin/env -i HOME=/root DEBIAN_FRONTEND=noninteractive PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c 'apt-get -o APT::Sandbox::User=root install -y --no-install-recommends libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 libasound2t64 libfontconfig1 libgl1 libwayland-client0 libdecor-0-0; /opt/godot/godot --headless --version' ;;
 build-backend)
 mkdir -p "$ROOT/opt/anland-build"
 mount --bind /data/data/com.termux/files/home/anland-termux/weston-source "$ROOT/opt/anland-build"
 cp /data/data/com.termux/files/home/anland-termux/build-backend.sh "$ROOT/tmp/build-anland-backend.sh"
 exec chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /tmp/build-anland-backend.sh ;;
 benchmark)
 cp /data/data/com.termux/files/home/anland-termux/benchmark-session.sh "$ROOT/usr/local/bin/anland-benchmark-session"
 chmod 755 "$ROOT/usr/local/bin/anland-benchmark-session"
 COMMAND='exec /usr/local/bin/anland-benchmark-session' ;;
 install-benchmark) exec chroot "$ROOT" /usr/bin/env -i HOME=/root DEBIAN_FRONTEND=noninteractive PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c 'getent group android_inet >/dev/null || groupadd -g 3003 android_inet; usermod -aG android_inet "$1"; usermod -aG android_inet _apt; apt-get -o APT::Sandbox::User=root -o APT::Update::Error-Mode=any update && apt-get -o APT::Sandbox::User=root install -y --no-install-recommends glmark2-wayland glmark2-es2-wayland gdb adwaita-icon-theme' bash "$CHROOT_USER" ;;
 desktop) COMMAND='export FD_MESA_DEBUG=noubwc,notile; mkdir -p "$HOME/anland-logs"; exec /usr/local/bin/startplasma-anland' ;;
 weston) COMMAND='export ANLAND_WESTON_SCALE=2 FD_MESA_DEBUG=noubwc,notile; exec startweston-anland' ;;
 test) COMMAND='export ANLAND_WESTON_SCALE=2 ANLAND_WESTON_START_ATTEMPTS=1 FD_MESA_DEBUG=noubwc,notile; exec timeout 20s startweston-anland' ;;
 shell) COMMAND='exec bash -l' ;;
 check) COMMAND='set -e; cat /etc/os-release; id; command -v sudo; weston --version; command -v glmark2-wayland; glmark2-wayland --help >/dev/null; test -S /tmp/anland/display_daemon.sock; test -r /dev/kgsl-3d0; echo "Chroot checks passed"' ;;
 *) echo 'Unknown mode' >&2; exit 2 ;;
esac
exec chroot "$ROOT" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=en_US.UTF-8 PATH=/opt/lfdevs/anland:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/su - "$CHROOT_USER" -c "$COMMAND"


END_ENTER_CHROOT_SH
chmod 700 "$BASE/enter-chroot.sh.new"
mv -f "$BASE/enter-chroot.sh.new" "$BASE/enter-chroot.sh"

# start-audio.sh
cat > "$BASE/start-audio.sh.new" <<'END_START_AUDIO_SH'
#!/data/data/com.termux/files/usr/bin/bash
# Independent instance of the same Android AAudio backend used by Termux-X11.
set -euo pipefail
BASE=/data/data/com.termux/files/home/anland-termux
PREFIX=/data/data/com.termux/files/usr
export TMPDIR="$BASE/runtime"
export PULSE_RUNTIME_PATH="$BASE/audio-runtime"
export PULSE_STATE_PATH="$BASE/audio-state"
export PULSE_CONFIG_PATH="$BASE/audio-config"
mkdir -p "$PULSE_RUNTIME_PATH" "$PULSE_STATE_PATH" "$PULSE_CONFIG_PATH" "$TMPDIR/pulse"
chmod 700 "$PULSE_RUNTIME_PATH" "$PULSE_STATE_PATH" "$PULSE_CONFIG_PATH"
chmod 755 "$TMPDIR/pulse"
# No default startup file, shared PID, shared socket, or TCP listener.
nohup "$PREFIX/bin/pulseaudio" -n --daemonize=no --use-pid-file=no \
 --exit-idle-time=-1 --disable-shm=yes --disallow-exit=yes \
 --load='module-aaudio-sink sink_name=anland-speaker' \
 --load="module-native-protocol-unix auth-anonymous=1 socket=$TMPDIR/pulse/native" \
 >"$BASE/logs/audio.log" 2>&1 </dev/null 9>&- &
pid=$!
echo "$pid" > "$BASE/logs/audio.pid"
for ((i=0; i<50; i++)); do
 kill -0 "$pid" 2>/dev/null || { cat "$BASE/logs/audio.log"; exit 1; }
 if timeout 2 "$PREFIX/bin/pactl" --server="unix:$TMPDIR/pulse/native" info >/dev/null 2>&1; then exit 0; fi
 sleep 0.1
done
echo "AnLand audio did not become ready. See $BASE/logs/audio.log" >&2
exit 1


END_START_AUDIO_SH
chmod 700 "$BASE/start-audio.sh.new"
mv -f "$BASE/start-audio.sh.new" "$BASE/start-audio.sh"

# benchmark-session.sh
cat > "$BASE/benchmark-session.sh.new" <<'END_BENCHMARK_SESSION_SH'
#!/bin/bash
set -euo pipefail
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-anland
export ANLAND_WESTON_SCALE=2 ANLAND_WESTON_START_ATTEMPTS=1
export MESA_LOADER_DRIVER_OVERRIDE=kgsl TURNIP_KMD=kgsl GALLIUM_DRIVER=freedreno FD_FORCE_KGSL=1
export FD_MESA_DEBUG=noubwc,notile
export XCURSOR_THEME=Adwaita
mkdir -p "$HOME/anland-logs"
if [[ ${ANLAND_DEBUG:-0} == 1 ]]; then
 weston() {
  command gdb --batch -ex 'set pagination off' -ex run -ex 'thread apply all bt' --args /usr/bin/weston "$@"
 }
 export -f weston
fi
startweston-anland >"$HOME/anland-logs/weston-debug.log" 2>&1 &
session_pid=$!
benchmark_pid=
cleanup() {
 [[ -z $benchmark_pid ]] || kill "$benchmark_pid" 2>/dev/null || true
 pkill -TERM -x -u "$(id -u)" weston 2>/dev/null || true
 kill "$session_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
for ((i=0;i<300;i++)); do
 [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
 kill -0 "$session_pid" 2>/dev/null || { tail -n 60 "$HOME/anland-logs/weston-debug.log"; exit 1; }
 sleep 0.1
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { echo 'Wayland did not start'; exit 1; }
if [[ ${1:-benchmark} == godot ]]; then
 godot --project-manager >"$HOME/anland-logs/godot.log" 2>&1 &
else
 EGL_PLATFORM=wayland glmark2-wayland --size 1280x800 --run-forever >"$HOME/anland-logs/glmark2.log" 2>&1 &
fi
benchmark_pid=$!
echo "${1:-glmark2} is running in the Anland display."
wait "$session_pid"


END_BENCHMARK_SESSION_SH
chmod 700 "$BASE/benchmark-session.sh.new"
mv -f "$BASE/benchmark-session.sh.new" "$BASE/benchmark-session.sh"
# Install the shared shell cleanup helper. The launcher is anland_chroot in bin.
bash "$SCRIPT_DIR/uninstall-anland.sh" --print-stop-script > "$BASE/stop-chroot.sh.new"
chmod 700 "$BASE/stop-chroot.sh.new"
mv -f "$BASE/stop-chroot.sh.new" "$BASE/stop-chroot.sh"
rm -f "$HOME/anland" "$HOME/anland.sh"
# Remove the obsolete helper from installations created with the earlier installer.
rm -f "$BASE/stop-chroot.cjs"
MANAGER="$HOME/.local/share/anland"
mkdir -p "$MANAGER"
for FILE in uninstall-anland.sh load-anland-snapshot.sh; do
 if [[ $(realpath "$SCRIPT_DIR/$FILE") != "$MANAGER/$FILE" ]]; then
  install -m 700 "$SCRIPT_DIR/$FILE" "$MANAGER/$FILE"
 fi
done

# Restore the existing shortcut icons from the unchanged snapshot.
for NAME in start stop safe-mode save-backup restore-backup; do
 sudo cp "$ROOT/opt/.shortcuts-anland/anland-$NAME.sh" "$HOME/.shortcuts/anland-$NAME.sh.new"
 sudo cp "$ROOT/opt/.shortcuts-anland/icons/anland-$NAME.sh.png" "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 sudo chown "$(id -u):$(id -g)" "$HOME/.shortcuts/anland-$NAME.sh.new" "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 chmod 755 "$HOME/.shortcuts/anland-$NAME.sh.new"
 chmod 644 "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 mv -f "$HOME/.shortcuts/anland-$NAME.sh.new" "$HOME/.shortcuts/anland-$NAME.sh"
 sed -i 's|/data/data/com.termux/files/home/anland |/data/data/com.termux/files/usr/bin/anland_chroot |g; s|/data/data/com.termux/files/home/anland$|/data/data/com.termux/files/usr/bin/anland_chroot run|; s|\./anland |anland_chroot |g' "$HOME/.shortcuts/anland-$NAME.sh"
done
# Restore a saved backup; installer downloads are temporary and are removed.
{
 echo '#!/data/data/com.termux/files/usr/bin/bash'
 echo 'BACKUP="$HOME/ubuntu-anland-backup.tar.gz"'
 echo '[[ -f $BACKUP ]] || read -r -p "Snapshot path: " BACKUP'
 echo 'exec bash "$HOME/.local/share/anland/load-anland-snapshot.sh" "$BACKUP"'
} > "$HOME/.shortcuts/anland-restore-backup.sh"
chmod 755 "$HOME/.shortcuts/anland-restore-backup.sh"
echo 'Ubuntu-AnLand restored. Open the menu with: anland_chroot'
