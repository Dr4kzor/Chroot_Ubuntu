#!/data/data/com.termux/files/usr/bin/bash
# Remove only Ubuntu-Anland. Backups, installers and Termux:Widget are kept.
set -euo pipefail
BASE=/data/data/com.termux/files/home/anland-termux
ROOT=/data/local/anland-ubuntu26
PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
unset LD_PRELOAD LD_LIBRARY_PATH
[[ $(id -u) != 0 ]] || { echo 'Run as the normal Termux user.'; exit 1; }
echo "This removes $ROOT, the Anland app, daemon, launcher and five shortcuts."
echo 'Running Anland programs will be forcibly closed. Save your work first.'
read -r -p 'Type UNINSTALL to continue: ' answer
[[ $answer == UNINSTALL ]] || { echo 'Cancelled.'; exit 1; }

# Block new sessions, stop Anland, unmount, and verify BEFORE removing files.
mkdir "$BASE/.uninstalling"
trap 'rmdir "$BASE/.uninstalling" 2>/dev/null || true' EXIT
if ! su -c "$PREFIX/bin/node '$BASE/stop-chroot.cjs' force"; then
 echo 'UNINSTALL ABORTED. Nothing was deleted. Fix the processes/mounts shown above.' >&2
 exit 1
fi
# Each deletion is scoped to this installation; shared Termux packages are kept.
su -c "rm -rf '$ROOT'"
if [[ -n $(su -c '/system/bin/pm path com.anland.termux' 2>/dev/null) ]]; then
 su -c '/system/bin/pm uninstall com.anland.termux'
fi
if dpkg-query -W -f='${Status}' anland 2>/dev/null | grep -q 'install ok installed'; then
 dpkg -r anland
fi
for name in start stop safe-mode save-backup restore-backup; do
 rm -f "$HOME/.shortcuts/anland-$name.sh" "$HOME/.shortcuts/icons/anland-$name.sh.png"
done
rm -f "$HOME/anland"
# Runtime files can be root-owned; use root for this private directory only.
su -c "rm -rf '$BASE'"
trap - EXIT
echo 'Ubuntu-Anland uninstalled. Your backups, installers and other Ubuntu are preserved.'
