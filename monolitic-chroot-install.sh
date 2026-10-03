#!/data/data/com.termux/files/usr/bin/bash
# Download the selected desktop's helpers, then run the requested action.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
SELF=$(realpath "$0")
SOURCE_DIR=$(dirname "$SELF")
STATE="$HOME/.local/share/chroot-manager"
# Upload this script and all its helpers to this directory in the repository.
SCRIPTS_URL=https://raw.githubusercontent.com/Dr4kzor/Chroot_Ubuntu/main

[[ $HOME == /data/data/com.termux/files/home && $(id -u) != 0 ]] || {
 echo 'Run this as the normal Termux user.'; exit 1;
}
VERSION=${1:-}
if [[ -z $VERSION ]]; then
 printf '\nUbuntu Chroot\n1) Termux-X11 / XFCE\n2) AnLand / KDE\n0) Exit\n'
 read -r -p 'Choose version: ' ANSWER
 case $ANSWER in
  1) VERSION=termux-x11 ;;
  2) VERSION=anland ;;
  0) exit 0 ;;
  *) echo 'Invalid choice.'; exit 1 ;;
 esac
fi
[[ $VERSION != x11 ]] || VERSION=termux-x11
case $VERSION in termux-x11|anland) ;; *) echo 'Choose termux-x11 or anland.'; exit 1 ;; esac
ACTION=${2:-}
if [[ -z $ACTION ]]; then
 printf '\n%s\n1) Run\n2) Install / Reinstall\n3) Update app and Termux package\n4) Uninstall\n5) Safe mode\n6) Save backup\n7) Restore backup\n8) Stop\n0) Exit\n' "$VERSION"
 read -r -p 'Choose action: ' ANSWER
 case $ANSWER in
  1) ACTION=run ;;
  2) ACTION=install ;;
  3) ACTION=update ;;
  4) ACTION=uninstall ;;
  5) ACTION=safe-mode ;;
  6) ACTION=backup ;;
  7) ACTION=restore ;;
  8) ACTION=stop ;;
  0) exit 0 ;;
  *) echo 'Invalid choice.'; exit 1 ;;
 esac
fi
[[ $ACTION != reinstall ]] || ACTION=install
case $ACTION in
 run|install|update|uninstall|safe-mode|backup|restore|stop) ;;
 *) echo 'Unknown action.'; exit 1 ;;
esac

# Install/refresh ALL helpers for the chosen desktop. Other actions work offline
# once helpers are installed. Files beside this menu are used before downloading.
HELPERS="$STATE/$VERSION"
WORK=$(mktemp -d "$PREFIX/tmp/chroot-helpers.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
NAMES=(install update uninstall run safe-mode backup restore stop)
[[ $VERSION != anland ]] || NAMES+=(preinstall)
for NAME in "${NAMES[@]}"; do
 FILE="$NAME-chroot-$VERSION.sh"
 if [[ $SOURCE_DIR != "$STATE" && -f $SOURCE_DIR/$FILE ]]; then
  cp "$SOURCE_DIR/$FILE" "$WORK/$FILE"
 elif [[ -f $HELPERS/$FILE && $ACTION != install && $ACTION != update ]]; then
  cp "$HELPERS/$FILE" "$WORK/$FILE"
 else
  command -v curl >/dev/null || apt install -y curl
  echo "Downloading $SCRIPTS_URL/$FILE"
  curl -fL --retry 3 "$SCRIPTS_URL/$FILE" -o "$WORK/$FILE"
 fi
 bash -n "$WORK/$FILE"
done
mkdir -p "$HELPERS"
for FILE in "$WORK"/*.sh; do install -m 700 "$FILE" "$HELPERS/${FILE##*/}"; done
if [[ $SELF != "$STATE/chroot-manager.sh" ]]; then
 install -m 700 "$SELF" "$STATE/chroot-manager.sh"
fi
ln -sfn "$STATE/chroot-manager.sh" "$PREFIX/bin/chroot_manager"

# Helpers handle their own confirmations, dependencies and desktop operations.
case $VERSION:$ACTION in
 anland:install) bash "$HELPERS/install-chroot-anland.sh" install "${@:3}" ;;
 anland:update) bash "$HELPERS/install-chroot-anland.sh" update ;;
 anland:uninstall) bash "$HELPERS/uninstall-chroot-anland.sh" ;;
 *) bash "$HELPERS/$ACTION-chroot-$VERSION.sh" "${@:3}" ;;
esac
printf '\nOpen the menu again with:\n\n  chroot_manager\n\n'
