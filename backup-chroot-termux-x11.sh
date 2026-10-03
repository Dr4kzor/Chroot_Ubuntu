#!/data/data/com.termux/files/usr/bin/bash
# Save the regular Ubuntu under its own backup filename.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=/data/local/ubuntu
BACKUP="$HOME/ubuntu-backup.tar.gz"
sudo test -d "$ROOT/etc" || { echo 'Install Termux-X11 Ubuntu first.'; exit 1; }
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
sudo rm -rf "$ROOT/opt/.shortcuts"
sudo mkdir -p "$ROOT/opt/.shortcuts"
tar -C "$HOME/.shortcuts" --exclude='./anland-*' --exclude='./icons/anland-*' --exclude='./*chroot-anland*' --exclude='./icons/*chroot-anland*' -cf - . |
 sudo tar -C "$ROOT/opt/.shortcuts" -xf -
# Save the actual launch settings as well as the menu shortcut.
sudo cp "$SCRIPT_DIR/run-chroot-termux-x11.sh" "$ROOT/opt/.shortcuts/1-ubuntu.sh"
[[ ! -f $BACKUP ]] || cp "$BACKUP" "$HOME/old_snapshot_ubuntu-backup.tar.gz"
sudo tar --numeric-owner --xattrs --acls -czpf "$BACKUP" -C / \
 --exclude=data/local/ubuntu/proc --exclude=data/local/ubuntu/sys \
 --exclude=data/local/ubuntu/dev --exclude=data/local/ubuntu/run \
 --exclude=data/local/ubuntu/tmp data/local/ubuntu
sudo chmod 766 "$BACKUP"
echo "Saved: $BACKUP"
