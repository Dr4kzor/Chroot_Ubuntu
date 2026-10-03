#!/data/data/com.termux/files/usr/bin/bash
# Reusable FTP setup: Android plus termux-x11, anland, or both (the default).
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
TARGET=${1:-both}
case $TARGET in termux-x11|anland|both) ;; *) echo 'Choose termux-x11, anland or both.'; exit 1 ;; esac
[[ $HOME == /data/data/com.termux/files/home ]] || { echo 'Run this script in Termux.'; exit 1; }
for FILE in install-prim-ftpd-android.sh prim-ftpd-chroot-termux-x11.sh prim-ftpd-chroot-anland.sh; do
 [[ -f $SCRIPT_DIR/$FILE ]] || { echo "Place $FILE beside this script."; exit 1; }
done
# Avoid concurrent changes to Android preferences and the shared authorized keys.
exec 9>"$PREFIX/tmp/prim-ftpd-setup.lock"
flock -n 9 || { echo 'Another FTP setup is running. Try again when it finishes.'; exit 1; }
apt install -y sudo
X11=no
ANLAND=no
if [[ $TARGET != anland ]] && sudo test -d /data/local/ubuntu/etc; then X11=yes; fi
if [[ $TARGET != termux-x11 ]] && sudo test -d /data/local/anland-ubuntu26/etc; then ANLAND=yes; fi
[[ $X11 == yes || $ANLAND == yes ]] || { echo 'Install the selected Ubuntu chroot first.'; exit 1; }
# Install Android if missing. Otherwise repair settings/permissions without
# reinstalling the APK, changing the password, or removing authorized keys.
bash "$SCRIPT_DIR/install-prim-ftpd-android.sh" --configure-only
if [[ $X11 == yes ]]; then
 X11_USER=${CHROOT_X11_USER:-user}
 if ! sudo grep -q "^$X11_USER:" /data/local/ubuntu/etc/passwd; then
  X11_USER=$(sudo cat /data/local/ubuntu/etc/passwd | while IFS=: read -r NAME PASSWORD ACCOUNT_UID ACCOUNT_GID DESCRIPTION ACCOUNT_HOME ACCOUNT_SHELL; do
   [ "$ACCOUNT_UID" -ge 1000 ] && [ "$ACCOUNT_UID" -lt 60000 ] || continue
   case "$ACCOUNT_HOME" in /home/*) ;; *) continue ;; esac
   case "$ACCOUNT_SHELL" in */false|*/nologin) continue ;; esac
   echo "$NAME"; break
  done)
 fi
 CHROOT_USER="$X11_USER" bash "$SCRIPT_DIR/prim-ftpd-chroot-termux-x11.sh"
fi
if [[ $ANLAND == yes ]]; then bash "$SCRIPT_DIR/prim-ftpd-chroot-anland.sh"; fi
if [[ $TARGET == both && $X11 == no ]]; then echo 'Termux-X11 Ubuntu is not installed; skipped.'; fi
if [[ $TARGET == both && $ANLAND == no ]]; then echo 'AnLand Ubuntu is not installed; skipped.'; fi
printf '\nFTP setup complete. Open Android Storage in the selected desktop.\nExisting passwords and keys were kept. Primitive FTPd must remain running.\n'
