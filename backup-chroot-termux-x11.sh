#!/data/data/com.termux/files/usr/bin/bash
# Save the regular Ubuntu under its own backup filename.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=/data/local/ubuntu
BACKUP="$HOME/ubuntu-termux-x11-backup.tar.gz"
sudo test -d "$ROOT/etc" || { echo 'Install Termux-X11 Ubuntu first.'; exit 1; }
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
sudo rm -rf "$ROOT/opt/.shortcuts"
sudo mkdir -p "$ROOT/opt/.shortcuts"
sudo mkdir -p "$ROOT/opt/.shortcuts/icons"
for NAME in 1-termux-x11-run 2-termux-x11-safe-mode 3-termux-x11-save-snapshot 4-termux-x11-load-snapshot 5-termux-x11-stop; do
 sudo cp "$HOME/.shortcuts/$NAME.sh" "$ROOT/opt/.shortcuts/$NAME.sh"
 sudo cp "$HOME/.shortcuts/icons/$NAME.sh.png" "$ROOT/opt/.shortcuts/icons/$NAME.sh.png"
done
# The copied shortcut is authoritative, including a renamed username and settings.
[[ ! -f $BACKUP ]] || cp "$BACKUP" "$HOME/old_snapshot_ubuntu-termux-x11-backup.tar.gz"
sudo tar --numeric-owner --xattrs --acls -czpf "$BACKUP" -C / \
 --exclude=data/local/ubuntu/proc --exclude=data/local/ubuntu/sys \
 --exclude=data/local/ubuntu/dev --exclude=data/local/ubuntu/run \
 --exclude=data/local/ubuntu/tmp data/local/ubuntu
sudo chmod 766 "$BACKUP"
echo "Saved: $BACKUP"
