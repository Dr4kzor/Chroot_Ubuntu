#!/data/data/com.termux/files/usr/bin/bash
# Run in Termux AFTER the Android and chroot installations.
# Enable authenticated, passwordless file-manager access for both desktops.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $HOME == /data/data/com.termux/files/home ]] || { echo 'Run this script in Termux.'; exit 1; }
for FILE in install-prim-ftpd-android.sh prim-ftpd-chroot-termux-x11.sh prim-ftpd-chroot-anland.sh; do
 [[ -f $SCRIPT_DIR/$FILE ]] || { echo "Place $FILE beside this script."; exit 1; }
done
# Preserve a configured Android server and its password. Fresh setups use the
# Android installer first; it downloads the latest release and asks for a password.
ANDROID_USER=$( (unset LD_PRELOAD LD_LIBRARY_PATH; su -c '/system/bin/am get-current-user </dev/null 2>&1') | tr -d '\r')
[[ $ANDROID_USER =~ ^[0-9]+$ ]] || { echo 'Cannot determine the Android user.'; exit 1; }
PREFS="/data/user/$ANDROID_USER/org.primftpd/shared_prefs/org.primftpd_preferences.xml"
if ! sudo test -f "$PREFS" || ! sudo grep -q 'name="bindIpPref">127.0.0.1<' "$PREFS"; then
 bash "$SCRIPT_DIR/install-prim-ftpd-android.sh"
fi

if sudo test -d /data/local/ubuntu/etc; then
 # Published images use user. Also support an already-renamed installation.
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
else
 echo 'Termux-X11 Ubuntu is not installed; skipped.'
fi
if sudo test -d /data/local/anland-ubuntu26/etc; then
 bash "$SCRIPT_DIR/prim-ftpd-chroot-anland.sh"
else
 echo 'AnLand Ubuntu is not installed; skipped.'
fi
printf '\nSetup complete. Open Android Storage (SFTP) in Thunar or Dolphin.\nKeep Primitive FTPd running in Android. SSH keys replace password prompts.\n'
