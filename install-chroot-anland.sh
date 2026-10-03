#!/data/data/com.termux/files/usr/bin/bash
# Install once, then use anland_chroot to manage Ubuntu-AnLand.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
SCRIPT=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
MANAGER="$HOME/.local/share/chroot-manager/anland"
ROOT=/data/local/anland-ubuntu26
SCRIPTS_URL=https://raw.githubusercontent.com/Dr4kzor/Chroot_Ubuntu/main
SNAPSHOT_URL=https://github.com/Dr4kzor/Chroot_Ubuntu/releases/latest/download/ubuntu-anland-backup.tar.gz

[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home && $(uname -m) == aarch64 ]] || {
 echo 'Run this as the normal user in ARM64 Termux.'; exit 1;
}
ACTION=${1:-}
if [[ -z $ACTION ]]; then
 if [[ -x $HOME/anland-termux/anland.sh ]]; then
  printf '\nUbuntu-AnLand\n1) Run\n2) Reinstall from snapshot\n3) Update AnLand app and daemon\n4) Uninstall\n0) Exit\n'
  read -r -p 'Choose: ' CHOICE
  case $CHOICE in 1) ACTION=run ;; 2) ACTION=reinstall ;; 3) ACTION=update ;; 4) ACTION=uninstall ;; 0) exit 0 ;; *) echo 'Invalid choice.'; exit 1 ;; esac
 else
  read -r -p 'Install Ubuntu-AnLand? [y/N] ' ANSWER
  [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
  ACTION=install
 fi
fi
case $ACTION in
 run) exec "$HOME/anland-termux/anland.sh" ;;
 stop|status|safe-mode|rename-user|shell) exec "$HOME/anland-termux/anland.sh" "$ACTION" ;;
 install|reinstall|update|uninstall) ;;
 *) echo 'Usage: anland_chroot [run|install|reinstall|update|uninstall]'; exit 1 ;;
esac
[[ $(su -c id -u | tr -d '\r\n') == 0 ]] || { echo 'Grant Termux root access first.'; exit 1; }

# Confirm replacement before downloads, stopping the desktop or changing files.
OVERWRITE=()
if [[ $ACTION == install || $ACTION == reinstall ]]; then
 if [[ -e $HOME/anland || -d $HOME/anland-termux ]] || sudo test -e "$ROOT"; then
  echo 'This closes AnLand and replaces its Ubuntu data. Backups and Termux-X11 are kept.'
  read -r -p 'Replace the existing installation? [y/N] ' ANSWER
  [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
  OVERWRITE=(--overwrite)
 fi
fi
if [[ $ACTION == update ]]; then
 read -r -p 'Close AnLand and update its app and daemon? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
fi

# Keep only the reusable shell scripts. All download work is temporary.
WORK=$(mktemp -d "$PREFIX/tmp/anland-install.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$MANAGER"
for FILE in preinstall-chroot-anland.sh update-chroot-anland.sh uninstall-chroot-anland.sh restore-chroot-anland.sh; do
 if [[ -f $SCRIPT_DIR/$FILE ]]; then
  cp "$SCRIPT_DIR/$FILE" "$WORK/$FILE"
 elif [[ -f $MANAGER/$FILE ]]; then
  cp "$MANAGER/$FILE" "$WORK/$FILE"
 else
  command -v curl >/dev/null || apt install -y curl
  curl -fL --retry 3 "$SCRIPTS_URL/$FILE" -o "$WORK/$FILE"
 fi
 bash -n "$WORK/$FILE"
 install -m 700 "$WORK/$FILE" "$MANAGER/$FILE"
done
# The command in bin points to the actual .sh file with the other helpers.
if [[ $SCRIPT != "$MANAGER/anland_chroot.sh" ]]; then
 install -m 700 "$SCRIPT" "$MANAGER/anland_chroot.sh"
fi
ln -sfn "$MANAGER/anland_chroot.sh" "$PREFIX/bin/anland_chroot"

# Migrate the old restore shortcut before removing duplicate home scripts.
if [[ -f $HOME/.shortcuts/anland-restore-backup.sh ]]; then
 cat > "$HOME/.shortcuts/anland-restore-backup.sh" <<'RESTORE'
#!/data/data/com.termux/files/usr/bin/bash
BACKUP="$HOME/ubuntu-anland-backup.tar.gz"
[[ -f $BACKUP ]] || read -r -p 'Snapshot path: ' BACKUP
exec bash "$HOME/.local/share/chroot-manager/anland/restore-chroot-anland.sh" "$BACKUP"
RESTORE
 chmod 755 "$HOME/.shortcuts/anland-restore-backup.sh"
fi
rm -f "$HOME/restore-chroot-anland.sh" "$HOME/uninstall-chroot-anland.sh"
# Shortcuts call the installed launcher directly.
for SHORTCUT in "$HOME"/.shortcuts/anland-*.sh; do
 [[ -f $SHORTCUT ]] || continue
 sed -i 's#/data/data/com.termux/files/home/anland\([[:space:]]\|$\)#/data/data/com.termux/files/home/anland-termux/anland.sh\1#g; s#\./anland\([[:space:]]\|$\)#/data/data/com.termux/files/home/anland-termux/anland.sh\1#g' "$SHORTCUT"
done
rm -f "$HOME/anland" "$HOME/anland.sh"
# Remove obsolete downloads and installer copies, keeping saved backups.
rm -rf "$HOME/anland-downloads"
for OLD in "$HOME"/anland-install.??????; do
 [[ -d $OLD && ! -L $OLD ]] || continue
 rm -rf "$OLD"
done

case $ACTION in
 uninstall)
  bash "$MANAGER/uninstall-chroot-anland.sh"
  exit ;;
 update)
  bash "$MANAGER/uninstall-chroot-anland.sh" --stop-only
  bash "$MANAGER/update-chroot-anland.sh"
  exit ;;
esac
apt update
bash "$MANAGER/preinstall-chroot-anland.sh"

# Optional second argument: a local snapshot. Otherwise use the release snapshot.
BACKUP=${2:-$SCRIPT_DIR/ubuntu-anland-backup.tar.gz}
if [[ ! -f $BACKUP ]]; then
 if [[ $# -ge 2 ]]; then echo "Snapshot not found: $BACKUP"; exit 1; fi
 BACKUP="$WORK/ubuntu-anland-backup.tar.gz"
 echo "Downloading $SNAPSHOT_URL"
 curl -fL --retry 3 "$SNAPSHOT_URL" -o "$BACKUP.part"
 mv "$BACKUP.part" "$BACKUP"
fi
bash "$MANAGER/restore-chroot-anland.sh" --check "$BACKUP"
if ((${#OVERWRITE[@]})); then bash "$MANAGER/uninstall-chroot-anland.sh" --stop-only; fi
bash "$MANAGER/update-chroot-anland.sh"
bash "$MANAGER/restore-chroot-anland.sh" "${OVERWRITE[@]}" "$BACKUP"
printf '\nInstallation complete.\nOpen the Run / Reinstall / Update / Uninstall menu with:\n\n  anland_chroot\n\n'
