#!/data/data/com.termux/files/usr/bin/bash
# Restore only the regular Ubuntu, using the original sudo/tar method.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=/data/local/ubuntu
MODE=${1:-}
case $MODE in --check|--confirmed) shift ;; esac
BACKUP=${1:-$HOME/ubuntu-backup.tar.gz}
[[ -f $BACKUP ]] || { echo "Snapshot not found: $BACKUP"; exit 1; }
tar -tzf "$BACKUP" | (
 VALID=yes
 COUNT=0
 while IFS= read -r ENTRY; do
  ENTRY=${ENTRY#./}
  COUNT=$((COUNT + 1))
  case "$ENTRY" in data/local/ubuntu|data/local/ubuntu/*) ;; *) VALID=no ;; esac
  case "/$ENTRY/" in */../*) VALID=no ;; esac
 done
 [[ $VALID == yes && $COUNT -gt 0 ]]
) || { echo 'Not a valid Termux-X11 Ubuntu snapshot.'; exit 1; }
[[ $MODE != --check ]] || exit 0
if [[ $MODE != --confirmed ]]; then
 read -r -p 'Replace Termux-X11 Ubuntu with this snapshot? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
fi
sudo test ! -L "$ROOT" || { echo 'Unexpected Ubuntu directory symlink.'; exit 1; }
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
sudo rm -rf "$ROOT"
sudo mkdir -p "$ROOT"/{proc,sys,dev,sdcard,tmp}
sudo tar --numeric-owner --xattrs --acls -xpf "$BACKUP" -C /
sudo mkdir -p "$ROOT/tmp"
sudo chmod 1777 "$ROOT/tmp"

# Restore snapshot shortcuts without touching AnLand's shortcuts or icons.
mkdir -p "$HOME/.shortcuts"
sudo tar -C "$ROOT/opt/.shortcuts" --exclude='./anland-*' --exclude='./icons/anland-*' --exclude='./*chroot-anland*' --exclude='./icons/*chroot-anland*' -cf - . |
 tar -C "$HOME/.shortcuts" --no-same-owner -xf -
# Keep the original shortcut names and icons. Install the real launch scripts,
# with the sudo fix and default user, rather than creating menu wrappers.
install -m 755 "$SCRIPT_DIR/run-chroot-termux-x11.sh" "$HOME/.shortcuts/1-ubuntu.sh"
install -m 755 "$SCRIPT_DIR/safe-mode-chroot-termux-x11.sh" "$HOME/.shortcuts/2-safe_mode.sh"
for ACTION in run safe-mode backup restore; do
 rm -f "$HOME/.shortcuts/$ACTION-chroot-termux-x11.sh" "$HOME/.shortcuts/icons/$ACTION-chroot-termux-x11.sh.png"
done
rm -f "$HOME/.shortcuts/0-Ubuntu.sh" "$HOME/.shortcuts/icons/0-Ubuntu.sh.png"
echo 'Termux-X11 Ubuntu restored. Open the menu with: chroot_manager'
