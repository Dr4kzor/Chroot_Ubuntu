#!/data/data/com.termux/files/usr/bin/bash
# Restore the unchanged Ubuntu-AnLand snapshot and set up its Termux launcher.
set -euo pipefail
cd /data/data/com.termux/files/home
ROOT=/data/local/anland-ubuntu26
BASE="$HOME/anland-termux"
BACKUP="$HOME/ubuntu-anland-backup.tar.gz"

# Check the snapshot before stopping or replacing anything.
[[ -f $BACKUP ]] || { echo "Missing snapshot: $BACKUP"; exit 1; }
tar -tzf "$BACKUP" | awk '
 { sub(/^\.\//, "") }
 $0 !~ /^data\/local\/anland-ubuntu26(\/|$)/ || $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1}
 END {exit bad || NR == 0}' || { echo 'Not an Ubuntu-AnLand snapshot.'; exit 1; }

# Existing installs must finish normal logout and release their mounts first.
if [[ -x $HOME/anland ]]; then
 "$HOME/anland" stop
 until "$HOME/anland" status | grep '"stopped": true' >/dev/null; do sleep 1; done
elif sudo test -e "$ROOT"; then
 echo 'AnLand rootfs exists without its launcher. Cannot verify safe shutdown.'
 exit 1
fi

# Use the same sudo/tar restore as the normal Load Backup shortcut.
sudo rm -rf "$ROOT"
sudo tar --numeric-owner --xattrs --xattrs-include='*' --acls -xpf "$BACKUP" -C /
sudo mkdir -p "$ROOT"/{proc,sys,dev/pts,run,tmp,sdcard}
sudo chmod 1777 "$ROOT/tmp"

# Host files are plain source below, not a base64/archive payload.
# They live outside Ubuntu and are absent from the existing snapshot.
mkdir -p "$BASE/runtime/anland" "$BASE/logs" "$HOME/.shortcuts/icons"
chmod 1777 "$BASE/runtime"
chmod 711 "$BASE/runtime/anland"

# anland
cat > "$HOME/anland.new" <<'END_ANLAND'
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
if ! service_running "$LOGDIR/audio.pid" pulseaudio; then
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

END_ANLAND
chmod 700 "$HOME/anland.new"
mv -f "$HOME/anland.new" "$HOME/anland"

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
 --load='module-suspend-on-idle timeout=3' \
 --load="module-native-protocol-unix auth-anonymous=1 socket=$TMPDIR/pulse/native" \
 >"$BASE/logs/audio.log" 2>&1 </dev/null 9>&- &
pid=$!
echo "$pid" > "$BASE/logs/audio.pid"
for ((i=0; i<50; i++)); do
 kill -0 "$pid" 2>/dev/null || { cat "$BASE/logs/audio.log"; exit 1; }
 if "$PREFIX/bin/pactl" --server="unix:$TMPDIR/pulse/native" info >/dev/null 2>&1; then exit 0; fi
 sleep 0.1
done
echo "AnLand audio did not become ready. See $BASE/logs/audio.log" >&2
exit 1

END_START_AUDIO_SH
chmod 700 "$BASE/start-audio.sh.new"
mv -f "$BASE/start-audio.sh.new" "$BASE/start-audio.sh"

# stop-chroot.sh
cat > "$BASE/stop-chroot.sh.new" <<'END_STOP_CHROOT_SH'
#!/system/bin/sh
unset LD_PRELOAD LD_LIBRARY_PATH
exec /data/data/com.termux/files/usr/bin/node /data/data/com.termux/files/home/anland-termux/stop-chroot.cjs "$@"

END_STOP_CHROOT_SH
chmod 700 "$BASE/stop-chroot.sh.new"
mv -f "$BASE/stop-chroot.sh.new" "$BASE/stop-chroot.sh"

# stop-chroot.cjs
cat > "$BASE/stop-chroot.cjs.new" <<'END_STOP_CHROOT_CJS'
// Root-side lifecycle control. Never select processes by UID or broad process name.
const fs = require('node:fs');
const cp = require('node:child_process');
const ROOT = '/data/local/anland-ubuntu26';
const BASE = '/data/data/com.termux/files/home/anland-termux';
const PREFIX = '/data/data/com.termux/files/usr';
function read(file) { try { return fs.readFileSync(file,'utf8'); } catch { return ''; } }
function processes() {
 return fs.readdirSync('/proc').filter(n=>/^\d+$/.test(n)).map(Number);
}
function rooted(pid) { try { return fs.readlinkSync(`/proc/${pid}/root`)===ROOT; } catch { return false; } }
function desktopUser() {
 const uid=(read(ROOT+'/etc/anland-user.uid').trim()||'1001');
 const entry=read(ROOT+'/etc/passwd').split('\n').map(line=>line.split(':')).find(fields=>fields[2]===uid && Number(uid)>=1000);
 if(!entry || !/^[A-Za-z_][A-Za-z0-9_-]*$/.test(entry[0])) throw Error('Anland desktop account not found.');
 return entry[0];
}
function chrootPids() { return processes().filter(rooted); }
function mountNamespaces() {
 const seen=new Set(), found=[];
 for(const pid of processes()) {
  try {
   const namespace=fs.readlinkSync(`/proc/${pid}/ns/mnt`);
   if(seen.has(namespace)) continue;
   const mounts=fs.readFileSync(`/proc/${pid}/mountinfo`,'utf8').split('\n').filter(line=>{
    const fields=line.split(' '), source=fields[3]||'', target=fields[4]||'';
    return source==='/local/anland-ubuntu26' || source.startsWith('/local/anland-ubuntu26/') ||
      source.includes('/anland-termux/runtime') || target===ROOT || target.startsWith(ROOT+'/');
   });
   seen.add(namespace);
   if(mounts.length) found.push({pid,namespace,mounts});
  } catch(error) { if(!['ENOENT','ESRCH','EINVAL'].includes(error.code)) throw error; }
 }
 return found;
}
function service(pid) {
 const argv0=read(`/proc/${pid}/cmdline`).split('\0')[0].trim();
 const name=argv0.split('/').pop();
 const env=read(`/proc/${pid}/environ`).split('\0');
 return env.includes(`TMPDIR=${BASE}/runtime`) &&
  (['anland','anland-compatible'].includes(name) ||
   (name==='pulseaudio' && env.includes(`PULSE_RUNTIME_PATH=${BASE}/audio-runtime`)));
}
function signal(pid, kind='SIGTERM') { try { process.kill(pid,kind); } catch(error) { if(error.code!=='ESRCH') throw error; } }
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

// Uninstall is explicitly destructive. Select only this chroot and its launchers.
function launcher(pid) {
 const args=read(`/proc/${pid}/cmdline`).split('\0');
 return args.some(arg=>[BASE+'/enter-chroot.sh',BASE+'/setup-fresh.sh',BASE+'/setup-chroot.sh',BASE.replace('/anland-termux','/anland')].includes(arg)) ||
  (args.includes('./anland') && (()=>{try{return fs.readlinkSync(`/proc/${pid}/cwd`)===BASE.replace('/anland-termux','');}catch{return false;}})());
}
function androidApp(pid) { return read(`/proc/${pid}/cmdline`).split('\0')[0]==='com.anland.termux'; }
async function forceStop() {
 cp.execFileSync('/system/bin/am',['force-stop','com.anland.termux'],{stdio:'ignore'});
 const owned=()=>processes().filter(pid=>pid!==process.pid&&(rooted(pid)||service(pid)||launcher(pid)||androidApp(pid)));
 for(const kind of ['SIGTERM','SIGKILL']) {
  for(const pid of owned()) signal(pid,kind);
  const deadline=Date.now()+5000;
  while(owned().length && Date.now()<deadline) await sleep(200);
 }
 const remaining=owned();
 if(remaining.length) throw Error('Cannot uninstall: processes still running: '+remaining.map(pid=>pid+' '+read('/proc/'+pid+'/cmdline').replaceAll('\0',' ')).join('\n'));
 // Normally private namespaces disappear with their last process. Unmount any
 // surviving host-visible mounts normally; never hide busy mounts with -l.
 for(const ns of mountNamespaces()) {
  const targets=ns.mounts.map(line=>line.split(' ')[4].replace(/\\040/g,' ')).sort((a,b)=>b.length-a.length);
  for(const target of [...new Set(targets)]) {
   if(target!==ROOT && !target.startsWith(ROOT+'/')) continue;
   const result=cp.spawnSync(PREFIX+'/bin/nsenter',['-t',String(ns.pid),'-m','/system/bin/umount',target],{encoding:'utf8'});
   if(result.status!==0) console.error('Unmount failed: '+target+' in '+ns.namespace+': '+(result.stderr||result.error||''));
  }
 }
 const mounts=mountNamespaces();
 if(owned().length||mounts.length) throw Error('Cannot uninstall: remaining processes/mounts:\n'+JSON.stringify({processes:owned(),mounts},null,2));
 cp.execFileSync('/system/bin/sync');
 console.log('Verified: no Anland processes, app, display services or mounts remain.');
}

async function main() {
 const mode=process.argv[2];
 if(mode==='force') return forceStop();
 if(mode==='status') {
  const linux=chrootPids(), services=processes().filter(service);
  const mounts=mountNamespaces();
  console.log(JSON.stringify({chrootProcesses:linux,displayServices:services,mountNamespaces:mounts,stopped:!linux.length&&!services.length&&!mounts.length},null,2));
  return;
 }
 if(mode==='request') {
  const kwin=chrootPids().find(pid=>read(`/proc/${pid}/comm`).trim()==='kwin_wayland');
  if(kwin) {
   const command='export XDG_RUNTIME_DIR=/run/anland/$(id -u); export DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG_RUNTIME_DIR/session-bus-address")"; exec qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout';
   cp.execFileSync(`${PREFIX}/bin/nsenter`,['-t',String(kwin),'-m','chroot',ROOT,'/usr/bin/env','-i','HOME=/root','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','/bin/su','-',desktopUser(),'-c',command],{stdio:'inherit'});
   console.log('KDE logout requested. Respond to any save dialog; Anland closes after logout.');
   process.exitCode=10;
   return;
  }
 }
 console.log('Closing Anland services...');
 for(const pid of chrootPids()) if(rooted(pid)) signal(pid);
 const deadline=Date.now()+15000;
 while(chrootPids().length && Date.now()<deadline) await sleep(200);
 const remaining=chrootPids();
 if(remaining.length) throw Error(`Anland processes are still exiting: ${remaining.join(', ')}. Display services remain available; no forced termination was used.`);
 cp.execFileSync('/system/bin/sync',[],{stdio:'ignore'});
 for(const pid of processes().filter(service)) if(service(pid)) signal(pid);
 const serviceDeadline=Date.now()+5000;
 while(processes().some(service) && Date.now()<serviceDeadline) await sleep(100);
 if(processes().some(service)) throw Error('Anland display services did not exit.');
 const mounts=mountNamespaces();
 if(mounts.length) throw Error(`Anland mount namespaces remain: ${mounts.map(x=>x.namespace).join(', ')}. Refusing to report full shutdown.`);
 cp.execFileSync('/system/bin/am',['force-stop','com.anland.termux'],{stdio:'ignore'});
 console.log('Anland fully stopped. No chroot, compositor, audio, daemon, or bridge processes remain.');
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});

END_STOP_CHROOT_CJS
chmod 700 "$BASE/stop-chroot.cjs.new"
mv -f "$BASE/stop-chroot.cjs.new" "$BASE/stop-chroot.cjs"

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

# Restore the shortcuts and KDE icons already stored inside the snapshot.
for NAME in start stop safe-mode save-backup restore-backup; do
 sudo cp "$ROOT/opt/.shortcuts-anland/anland-$NAME.sh" "$HOME/.shortcuts/anland-$NAME.sh.new"
 sudo cp "$ROOT/opt/.shortcuts-anland/icons/anland-$NAME.sh.png" "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 sudo chown "$(id -u):$(id -g)" "$HOME/.shortcuts/anland-$NAME.sh.new" "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 chmod 755 "$HOME/.shortcuts/anland-$NAME.sh.new"
 chmod 644 "$HOME/.shortcuts/icons/anland-$NAME.sh.png"
 mv -f "$HOME/.shortcuts/anland-$NAME.sh.new" "$HOME/.shortcuts/anland-$NAME.sh"
done
echo 'Ubuntu-AnLand restored. Start with ~/anland or its Start shortcut.'
echo 'The snapshot archive itself was not modified.'
