#!/bin/bash
# XFCE / Thunar access to the Android Primitive FTPd server.
# Run in the selected Ubuntu desktop terminal; these extras do not change the installer.
set -euo pipefail
if [[ -d /data/data/com.termux/files/usr ]]; then
 echo 'Run this script INSIDE the indicated Ubuntu desktop terminal, as its regular user.' >&2
 exit 1
fi
[[ $(id -u) != 0 ]] || { echo 'Run as your regular desktop user; sudo will be used for apt.'; exit 1; }
SERVER_USER=${PRIM_FTPD_USER:-user}
SERVER_PORT=${PRIM_FTPD_PORT:-1234}
[[ $SERVER_USER =~ ^[a-zA-Z0-9_-]+$ && $SERVER_PORT =~ ^[0-9]+$ ]] || { echo 'Invalid SFTP username or port.'; exit 1; }
URI="sftp://$SERVER_USER@127.0.0.1:$SERVER_PORT/"
sudo apt update
sudo apt install -y gvfs-backends gvfs-fuse openssh-client
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.local/share/applications"
BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
touch "$BOOKMARKS"
if ! grep -F "$URI " "$BOOKMARKS" >/dev/null; then
 printf '%s Android Storage (SFTP)\n' "$URI" >> "$BOOKMARKS"
fi
cat > "$HOME/.local/share/applications/android-storage-prim-ftpd.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Android Storage (SFTP)
Comment=Browse Android storage through Primitive FTPd
Exec=thunar $URI
Icon=folder-remote
Terminal=false
Categories=Network;FileManager;
ENTRY
echo "Added Android Storage (SFTP) to Thunar bookmarks and the application menu: $URI"
echo 'Keep Primitive FTPd running in Android. On first connection, accept its host key and enter your SFTP password.'
