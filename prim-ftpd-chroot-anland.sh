#!/data/data/com.termux/files/usr/bin/bash
# Termux-side setup for KDE / Dolphin: authenticate with a dedicated SSH key.
ROOT=/data/local/anland-ubuntu26
DESKTOP_UID=$(sudo cat "$ROOT/etc/anland-user.uid")
DESKTOP_USER=${CHROOT_USER:-$(sudo cat "$ROOT/etc/passwd" | while IFS=: read -r NAME PASSWORD ACCOUNT_UID REST; do
 if [ "$ACCOUNT_UID" = "$DESKTOP_UID" ]; then echo "$NAME"; break; fi
done)}
FILE_MANAGER=dolphin
PACKAGES='kio-extras openssh-client'
# Run this standalone integration script in TERMUX, not inside Ubuntu.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
[[ $HOME == /data/data/com.termux/files/home ]] || { echo 'Run this script in Termux.'; exit 1; }
WORK=$(mktemp -d "$PREFIX/tmp/prim-key-setup.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
umask 077
command -v ssh-keygen >/dev/null || apt install -y openssh
sudo test -d "$ROOT/etc" || { echo 'Ubuntu rootfs not found.'; exit 1; }

# Read the running Android profile and the server's actual configuration.
ANDROID_USER=$( (unset LD_PRELOAD LD_LIBRARY_PATH; su -c '/system/bin/am get-current-user </dev/null 2>&1') | tr -d '\r')
[[ $ANDROID_USER =~ ^[0-9]+$ ]] || { echo 'Cannot determine the Android user.'; exit 1; }
APP_DIR="/data/user/$ANDROID_USER/org.primftpd"
PREFS="$APP_DIR/shared_prefs/org.primftpd_preferences.xml"
AUTHORIZED="/storage/emulated/$ANDROID_USER/Android/data/org.primftpd/files/.ssh/authorized_keys"
sudo test -f "$PREFS" || { echo 'Run install-prim-ftpd-android.sh first.'; exit 1; }
sudo cat "$PREFS" > "$WORK/server-preferences.xml"
read_setting() {
 sed -n "s|.*<string name=\"$1\">\(.*\)</string>.*|\1|p" "$WORK/server-preferences.xml" |
  sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&apos;/'"'"'/g; s/&amp;/\&/g'
}
SERVER_USER=$(read_setting userNamePref)
SERVER_PORT=$(read_setting securePortPref)
SERVER_DIRECTORY=$(read_setting startDirPref)
SERVER_BIND=$(read_setting bindIpPref)
[[ $SERVER_BIND == 127.0.0.1 ]] || { echo 'Configure Primitive FTPd to bind to 127.0.0.1 first.'; exit 1; }
[[ $SERVER_USER =~ ^[a-zA-Z0-9_-]+$ && $SERVER_PORT =~ ^[0-9]+$ && $SERVER_DIRECTORY == /* ]] || {
 echo 'Set the SFTP username, port and storage directory in Primitive FTPd first.'; exit 1;
}
# Escape spaces and other URL characters in the configured directory.
URI_PATH=
LC_ALL=C
for ((INDEX=0; INDEX<${#SERVER_DIRECTORY}; INDEX++)); do
 CHARACTER=${SERVER_DIRECTORY:INDEX:1}
 case "$CHARACTER" in
  [a-zA-Z0-9/._~-]) URI_PATH+=$CHARACTER ;;
  *) printf -v HEX '%%%02X' "'$CHARACTER"; URI_PATH+=$HEX ;;
 esac
done
URI="sftp://$SERVER_USER@android-storage-prim-ftpd:$SERVER_PORT${URI_PATH%/}/"
# Resolve the desktop user's existing home and ownership.
LOGIN= USER_HOME= USER_UID= USER_GID=
sudo cat "$ROOT/etc/passwd" > "$WORK/passwd"
while IFS=: read -r NAME PASSWORD ACCOUNT_UID ACCOUNT_GID DESCRIPTION ACCOUNT_HOME ACCOUNT_SHELL; do
 if [[ $NAME == "$DESKTOP_USER" ]]; then
  LOGIN=$NAME; USER_HOME=$ACCOUNT_HOME; USER_UID=$ACCOUNT_UID; USER_GID=$ACCOUNT_GID
  break
 fi
done < "$WORK/passwd"
[[ -n $LOGIN && $USER_HOME == /home/* ]] || { echo "User $DESKTOP_USER not found. Set CHROOT_USER to your desktop username."; exit 1; }
SSH_DIR="$ROOT$USER_HOME/.ssh"
sudo mkdir -p "$SSH_DIR"
if ! sudo test -f "$SSH_DIR/id_prim_ftpd"; then
 ssh-keygen -q -t ed25519 -N '' -C "$LOGIN-prim-ftpd" -f "$WORK/id_prim_ftpd"
 sudo cp "$WORK/id_prim_ftpd" "$WORK/id_prim_ftpd.pub" "$SSH_DIR/"
fi
sudo cat "$SSH_DIR/id_prim_ftpd.pub" > "$WORK/client.pub"
sudo mkdir -p "${AUTHORIZED%/*}"
sudo touch "$AUTHORIZED"
if ! sudo grep -Fx -f "$WORK/client.pub" "$AUTHORIZED" >/dev/null; then
 sudo tee -a "$AUTHORIZED" < "$WORK/client.pub" >/dev/null
fi
# The app's external files directory is read under its Android app UID.
APP_OWNER=$(sudo stat -c '%u:%g' "$APP_DIR")
sudo chown "$APP_OWNER" "${AUTHORIZED%/*}" "$AUTHORIZED"

# Get the server key directly from its private app directory, not from the network.
sudo cat "$APP_DIR/files/id_ed25519.pub" > "$WORK/host.pub"
grep '^ssh-ed25519 ' "$WORK/host.pub" >/dev/null || { echo 'Open Primitive FTPd once to generate its host key.'; exit 1; }
sudo touch "$SSH_DIR/known_hosts"
sudo ssh-keygen -R "[127.0.0.1]:$SERVER_PORT" -f "$SSH_DIR/known_hosts" >/dev/null 2>&1
{ printf '[127.0.0.1]:%s ' "$SERVER_PORT"; cat "$WORK/host.pub"; printf '\n'; } | sudo tee -a "$SSH_DIR/known_hosts" >/dev/null
# Use a dedicated alias so other SSH connections retain their existing settings.
sudo touch "$SSH_DIR/config"
sudo cat "$SSH_DIR/config" | sed '/^# BEGIN Primitive FTPd$/,/^# END Primitive FTPd$/d' > "$WORK/config.old"
cat > "$WORK/config" <<SETTINGS
# BEGIN Primitive FTPd
Host android-storage-prim-ftpd
    HostName 127.0.0.1
    Port $SERVER_PORT
    User $SERVER_USER
    IdentityFile $USER_HOME/.ssh/id_prim_ftpd
    IdentitiesOnly yes
    StrictHostKeyChecking yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
# END Primitive FTPd

SETTINGS
cat "$WORK/config.old" >> "$WORK/config"
sudo cp "$WORK/config" "$SSH_DIR/config"
sudo chown "$USER_UID:$USER_GID" "$SSH_DIR" "$SSH_DIR/"{config,known_hosts,id_prim_ftpd,id_prim_ftpd.pub}
sudo chmod 700 "$SSH_DIR"
sudo chmod 600 "$SSH_DIR/"{config,known_hosts,id_prim_ftpd}
sudo chmod 644 "$SSH_DIR/id_prim_ftpd.pub"

# Install the SFTP client components with temporary, private Android mounts.
# The mounts disappear when this shell exits; neither desktop is stopped.
(unset LD_PRELOAD LD_LIBRARY_PATH; su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh -s") <<SYSTEM
set -e
export PATH=$PREFIX/bin:/system/bin
mount --bind /dev '$ROOT/dev'
mount -t proc proc '$ROOT/proc'
chroot '$ROOT' /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get -o APT::Sandbox::User=root update
chroot '$ROOT' /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get -o APT::Sandbox::User=root install -y $PACKAGES
SYSTEM

# Enable key authentication, preserving the password and all other settings.
(unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/am force-stop --user '$ANDROID_USER' org.primftpd </dev/null >'$WORK/android.log' 2>&1")
sudo cp "$PREFS" "$PREFS.before-keys-$(date +%s)"
sudo cat "$PREFS" | sed '/name="pubKeyAuthPref"/d; /<\/map>/i\    <boolean name="pubKeyAuthPref" value="true" />' > "$WORK/preferences.xml"
sudo cp "$WORK/preferences.xml" "$PREFS"
sudo chown "$APP_OWNER" "$PREFS"
sudo chmod 600 "$PREFS"
(unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/am start --user '$ANDROID_USER' -n org.primftpd/.ui.MainTabsActivity </dev/null >'$WORK/android.log' 2>&1")
for ((TRY=0; TRY<30; TRY++)); do
 if (exec 3<>/dev/tcp/127.0.0.1/$SERVER_PORT) 2>/dev/null; then break; fi
 sleep 1
done
# Verify using the actual Ubuntu account, with all password prompts disabled.
(unset LD_PRELOAD LD_LIBRARY_PATH; su -c "$PREFIX/bin/unshare --mount --propagation private /system/bin/sh -s") <<VERIFY
set -e
export PATH=$PREFIX/bin:/system/bin
mount --bind /dev '$ROOT/dev'
chroot '$ROOT' /bin/su '$LOGIN' -c 'printf "pwd\\n" | sftp -oBatchMode=yes -b - android-storage-prim-ftpd'
VERIFY
EXEC_URI=${URI//%/%%}
APP_DESKTOP="$ROOT$USER_HOME/.local/share/applications/android-storage-prim-ftpd.desktop"
sudo mkdir -p "${APP_DESKTOP%/*}"
cat > "$WORK/application.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Android Storage (SFTP)
Exec=$FILE_MANAGER $EXEC_URI
Icon=folder-remote
Terminal=false
Categories=Network;FileManager;
ENTRY
sudo cp "$WORK/application.desktop" "$APP_DESKTOP"
sudo chown "$USER_UID:$USER_GID" "$APP_DESKTOP"
sudo chmod 644 "$APP_DESKTOP"
REMOTE="$ROOT$USER_HOME/.local/share/remoteview/android-storage-prim-ftpd.desktop"
sudo mkdir -p "${REMOTE%/*}"
cat > "$WORK/remote.desktop" <<ENTRY
[Desktop Entry]
Type=Link
Name=Android Storage (SFTP)
URL=$URI
Icon=folder-remote
ENTRY
sudo cp "$WORK/remote.desktop" "$REMOTE"
sudo chown "$USER_UID:$USER_GID" "$REMOTE"
sudo chmod 644 "$REMOTE"
echo 'Dolphin is configured to connect with its SSH key, without password prompts.'
