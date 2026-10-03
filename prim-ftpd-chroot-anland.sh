#!/bin/bash
# KDE / Dolphin access to the Android Primitive FTPd server.
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
sudo apt install -y kio-extras openssh-client
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/remoteview"
# KDE's Network view reads .desktop links from remoteview; no XML Places rewrite.
cat > "$HOME/.local/share/remoteview/android-storage-prim-ftpd.desktop" <<ENTRY
[Desktop Entry]
Type=Link
Name=Android Storage (SFTP)
URL=$URI
Icon=folder-remote
ENTRY
cat > "$HOME/.local/share/applications/android-storage-prim-ftpd.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Android Storage (SFTP)
Comment=Browse Android storage through Primitive FTPd
Exec=dolphin $URI
Icon=folder-remote
Terminal=false
Categories=Network;FileManager;
ENTRY
echo "Added Android Storage (SFTP) to Dolphin's Network view and the application menu: $URI"
echo 'Keep Primitive FTPd running in Android. On first connection, accept its host key and enter your SFTP password.'
