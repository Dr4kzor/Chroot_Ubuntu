#!/data/data/com.termux/files/usr/bin/bash
# Install AnLand and restore our Ubuntu snapshot. Run as the normal Termux user.
set -euo pipefail
SCRIPTS_URL=https://raw.githubusercontent.com/Dr4kzor/Chroot_Ubuntu/main
SNAPSHOT_URL=https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-anland-backup.tar.gz
cd /data/data/com.termux/files/home

# Refuse an existing AnLand installation; the load script handles later restores.
[[ $(id -u) != 0 ]] || { echo 'Run this as the normal Termux user.'; exit 1; }
[[ ! -e $HOME/anland && ! -e $HOME/anland-termux ]] || { echo 'AnLand is already installed.'; exit 1; }
[[ $(su -c id -u | tr -d '\r\n') == 0 ]] || { echo 'Grant Termux root access first.'; exit 1; }
su -c 'test ! -e /data/local/anland-ubuntu26' || { echo 'AnLand rootfs already exists.'; exit 1; }
[[ ! -e ubuntu-anland-backup.tar.gz ]] || { echo 'A local AnLand backup exists; move it aside first.'; exit 1; }

# Bootstrap curl to download the preinstaller, which contains all dependencies.
apt update
command -v curl >/dev/null || apt install -y curl

# Download the four companion scripts. All are readable source code.
echo "Downloading AnLand scripts from $SCRIPTS_URL"
for FILE in preinstall-anland.sh install-latest-anland.sh uninstall-anland.sh load-anland-snapshot.sh; do
 curl -fL --retry 3 "$SCRIPTS_URL/$FILE" -o "$FILE.part"
 bash -n "$FILE.part"
 chmod 700 "$FILE.part"
 mv "$FILE.part" "$FILE"
done

# Install dependencies, then the latest matching Android app and Termux daemon.
bash ./preinstall-anland.sh
bash ./install-latest-anland.sh

# Download the snapshot as a separate file and load it with sudo/tar.
echo "Downloading Ubuntu-AnLand from $SNAPSHOT_URL"
curl -fL --retry 3 "$SNAPSHOT_URL" -o ubuntu-anland-backup.tar.gz.part
mv ubuntu-anland-backup.tar.gz.part ubuntu-anland-backup.tar.gz
bash ./load-anland-snapshot.sh

echo 'Installed. Start Ubuntu-AnLand with ~/anland.'
echo 'Termux:Widget is optional; the shortcuts are in ~/.shortcuts/.'
