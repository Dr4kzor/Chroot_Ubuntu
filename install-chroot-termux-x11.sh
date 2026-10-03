#!/data/data/com.termux/files/usr/bin/bash
# Prepare Termux, install the X11 app/package, then load the regular Ubuntu snapshot.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
SNAPSHOT_URL=https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-backup.tar.gz
read -r -p 'Install/reinstall Termux-X11 Ubuntu? Existing X11 Ubuntu data will be replaced. [y/N] ' ANSWER
[[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
apt update
apt install -y sudo x11-repo curl tar gzip mount-utils procps coreutils
apt install -y pulseaudio
termux-setup-storage
WORK=$(mktemp -d "$PREFIX/tmp/chroot-termux-x11-install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BACKUP=${1:-}
if [[ -z $BACKUP ]]; then
 BACKUP="$WORK/ubuntu-backup.tar.gz"
 echo "Downloading $SNAPSHOT_URL"
 curl -fL --retry 3 "$SNAPSHOT_URL" -o "$BACKUP"
fi
# Validate before closing the existing desktop or changing its files.
bash "$SCRIPT_DIR/restore-chroot-termux-x11.sh" --check "$BACKUP"
# The updater installs the latest APT companion package and Android nightly APK.
bash "$SCRIPT_DIR/update-chroot-termux-x11.sh" --confirmed
bash "$SCRIPT_DIR/restore-chroot-termux-x11.sh" --confirmed "$BACKUP"
echo 'Installation complete. Open the menu with: chroot_manager'
