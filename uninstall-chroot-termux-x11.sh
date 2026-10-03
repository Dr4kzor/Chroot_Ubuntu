#!/data/data/com.termux/files/usr/bin/bash
# Keep AnLand, shared Termux dependencies and saved backups.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
read -r -p 'Uninstall Termux-X11 Ubuntu? [y/N] ' ANSWER
[[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
sudo test ! -L /data/local/ubuntu || { echo 'Unexpected Ubuntu directory symlink.'; exit 1; }
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
sudo rm -rf /data/local/ubuntu
for ACTION in run safe-mode backup restore; do
 rm -f "$HOME/.shortcuts/$ACTION-chroot-termux-x11.sh" "$HOME/.shortcuts/icons/$ACTION-chroot-termux-x11.sh.png"
done
rm -f "$HOME/.shortcuts/"{1-ubuntu,2-safe_mode,3-save_ubuntu_snapshot,4-load_ubuntu_snapshot}.sh
echo 'Termux-X11 Ubuntu uninstalled. Backups and AnLand were kept.'
