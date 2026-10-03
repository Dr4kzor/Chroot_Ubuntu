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
# Keep the maintained launcher; old snapshots may contain an unsafe kill command
# or a username from the machine on which the snapshot was created.
for ACTION in run safe-mode backup restore; do
 printf '#!/data/data/com.termux/files/usr/bin/bash\nexec bash "%s/%s-chroot-termux-x11.sh"\n' "$SCRIPT_DIR" "$ACTION" > "$HOME/.shortcuts/$ACTION-chroot-termux-x11.sh"
 chmod 755 "$HOME/.shortcuts/$ACTION-chroot-termux-x11.sh"
done
# Rename matching icons and remove the four obsolete shortcut names.
while read -r OLD NEW; do
 if [[ -f $HOME/.shortcuts/icons/$OLD.sh.png ]]; then
  mv -f "$HOME/.shortcuts/icons/$OLD.sh.png" "$HOME/.shortcuts/icons/$NEW-chroot-termux-x11.sh.png"
 fi
 rm -f "$HOME/.shortcuts/$OLD.sh"
done <<'NAMES'
1-ubuntu run
2-safe_mode safe-mode
3-save_ubuntu_snapshot backup
4-load_ubuntu_snapshot restore
NAMES
echo 'Termux-X11 Ubuntu restored. Open the menu with: chroot_manager'
