#!/data/data/com.termux/files/usr/bin/bash
# Run this one script to prepare Termux, install AnLand and restore Ubuntu.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS_URL=https://raw.githubusercontent.com/Dr4kzor/Chroot_Ubuntu/main
SNAPSHOT_URL=https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-anland-backup.tar.gz
ROOT=/data/local/anland-ubuntu26

[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home && $(uname -m) == aarch64 ]] || {
 echo 'Run this as the normal user in ARM64 Termux.'; exit 1;
}
[[ $(su -c id -u | tr -d '\r\n') == 0 ]] || { echo 'Grant Termux root access first.'; exit 1; }

# Existing installations are allowed, but replacement must be confirmed.
OVERWRITE=()
if [[ -e $HOME/anland || -e $HOME/anland-termux ]] || su -c "test -e '$ROOT'"; then
 echo 'AnLand is already installed. Replacement closes its apps and replaces its Ubuntu data.'
 echo 'Your snapshot file and other Ubuntu installation will be kept.'
 read -r -p 'Replace the existing AnLand installation? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || { echo 'Cancelled.'; exit 0; }
 OVERWRITE=(--overwrite)
fi

# Use the companion scripts from this folder, or download them for a web install.
apt update
command -v curl >/dev/null || apt install -y curl
WORK=$(mktemp -d "$HOME/anland-install.XXXXXX")
for FILE in preinstall-anland.sh install-latest-anland.sh uninstall-anland.sh load-anland-snapshot.sh; do
 if [[ -f $SCRIPT_DIR/$FILE ]]; then
  cp "$SCRIPT_DIR/$FILE" "$WORK/$FILE"
 else
  curl -fL --retry 3 "$SCRIPTS_URL/$FILE" -o "$WORK/$FILE"
 fi
 bash -n "$WORK/$FILE"
 chmod 700 "$WORK/$FILE"
done
bash "$WORK/preinstall-anland.sh"

# Use the supplied snapshot without modifying it; otherwise download a new copy.
BACKUP="$SCRIPT_DIR/ubuntu-anland-backup.tar.gz"
if [[ ! -f $BACKUP ]]; then
 BACKUP="$WORK/ubuntu-anland-backup.tar.gz"
 echo "Downloading $SNAPSHOT_URL"
 curl -fL --retry 3 "$SNAPSHOT_URL" -o "$BACKUP.part"
 mv "$BACKUP.part" "$BACKUP"
fi
# Validate before stopping the existing installation.
bash "$WORK/load-anland-snapshot.sh" --check "$BACKUP"
if ((${#OVERWRITE[@]})); then bash "$WORK/uninstall-anland.sh" --stop-only; fi
bash "$WORK/install-latest-anland.sh"
bash "$WORK/load-anland-snapshot.sh" "${OVERWRITE[@]}" "$BACKUP"
echo 'Installed. Start Ubuntu-AnLand with ~/anland or its Start shortcut.'
