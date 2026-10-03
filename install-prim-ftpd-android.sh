#!/data/data/com.termux/files/usr/bin/bash
# Standalone extra: install Primitive FTPd and serve Android storage over local SFTP.
# Source: https://github.com/wolpi/prim-ftpd
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
REPO=https://github.com/wolpi/prim-ftpd
API=https://api.github.com/repos/wolpi/prim-ftpd/releases/latest
PACKAGE=org.primftpd
# Both chroots share Android's network, so neither needs a port forward.
SERVER_USER=user
SERVER_PORT=1234
SERVER_DIRECTORY=/storage/emulated/0
apt install -y curl openssl-tool coreutils sudo
WORK=$(mktemp -d "$PREFIX/tmp/prim-ftpd.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
umask 077

# Android services must not inherit Termux's terminal file descriptors.
android() {
 local RESULT=0
 (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "$1 </dev/null >'$WORK/android.log' 2>&1") || RESULT=$?
 sudo cat "$WORK/android.log"
 return "$RESULT"
}
echo "Repository: $REPO"
curl -fL --retry 3 "$API" -o "$WORK/release.json"
NAME= DIGEST= URL= TAG=
while IFS= read -r LINE; do
 case "$LINE" in
  *'"tag_name":'*) TAG=$(printf '%s' "$LINE" | cut -d '"' -f 4) ;;
  *'"name":'*) NAME=$(printf '%s' "$LINE" | cut -d '"' -f 4); DIGEST= ;;
  *'"digest":'*) DIGEST=$(printf '%s' "$LINE" | cut -d '"' -f 4) ;;
  *'"browser_download_url":'*)
   case "$NAME" in primitiveFTPd-*.apk) URL=$(printf '%s' "$LINE" | cut -d '"' -f 4); break ;; esac ;;
 esac
done < "$WORK/release.json"
[[ $URL == "$REPO/releases/download/"* && $DIGEST =~ ^sha256:[a-f0-9]{64}$ && $TAG =~ ^[a-zA-Z0-9._-]+$ ]] || {
 echo 'Cannot identify the official APK and checksum.'; exit 1;
}
# Verify that the latest version still uses the preference/password format below.
curl -fsSL "https://raw.githubusercontent.com/wolpi/prim-ftpd/$TAG/primitiveFTPd/src/org/primftpd/util/EncryptionUtil.java" -o "$WORK/EncryptionUtil.java"
grep -F '"H§R&q}9"' "$WORK/EncryptionUtil.java" >/dev/null &&
grep -F 'getInstance("SHA-512")' "$WORK/EncryptionUtil.java" >/dev/null || {
 echo "Password format changed. Check $REPO before configuring this release."; exit 1;
}
echo "Downloading $URL"
curl -fL --retry 3 "$URL" -o "$WORK/prim-ftpd.apk"
printf '%s  %s\n' "${DIGEST#sha256:}" "$WORK/prim-ftpd.apk" | sha256sum -c -
android "/system/bin/pm install -r '$WORK/prim-ftpd.apk'"
ANDROID_USER=$(android '/system/bin/am get-current-user')
[[ $ANDROID_USER =~ ^[0-9]+$ ]] || { echo 'Cannot determine the Android user.'; exit 1; }
APP_DIR="/data/user/$ANDROID_USER/$PACKAGE"
PREFS="$APP_DIR/shared_prefs/${PACKAGE}_preferences.xml"
if sudo test -f "$PREFS"; then
 read -r -p 'Configure the existing FTPd app for local SFTP? Existing preferences will be backed up. [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
fi
printf 'SFTP login: %s, address: 127.0.0.1:%s\n' "$SERVER_USER" "$SERVER_PORT"
read -r -s -p 'Choose an SFTP password: ' PASSWORD; echo
read -r -s -p 'Repeat password: ' CONFIRM; echo
[[ -n $PASSWORD && $PASSWORD == "$CONFIRM" ]] || { echo 'Passwords must match and cannot be empty.'; exit 1; }
# This is the app's native salted password hash, not an encoded script/file.
PASSWORD_HASH=$(printf '%s%s' "$PASSWORD" 'H§R&q}9' | openssl dgst -sha512 -binary | openssl base64 -A)
unset PASSWORD CONFIRM
android "/system/bin/am force-stop --user '$ANDROID_USER' '$PACKAGE'"
if sudo test -f "$PREFS"; then
 sudo cp "$PREFS" "$PREFS.before-chroot-$(date +%s)"
 sudo cat "$PREFS" > "$WORK/preferences.xml"
else
 printf '<?xml version="1.0" encoding="utf-8" standalone="yes" ?>\n<map>\n</map>\n' > "$WORK/preferences.xml"
fi
# Replace only the settings needed for this connection. Preserve unrelated settings.
for KEY in userNamePref passwordPref anonymousLoginPref pubKeyAuthPref whichServerToStartPref securePortPref bindIpPref chooseIpToBindToPref startDirPref storageTypePref startOnOpenPref startOnBootPref idleTimeoutServerStopPref; do
 sed -i "/name=\"$KEY\"/d" "$WORK/preferences.xml"
done
sed -i '/<\/map>/d' "$WORK/preferences.xml"
cat >> "$WORK/preferences.xml" <<SETTINGS
    <string name="userNamePref">$SERVER_USER</string>
    <string name="passwordPref">$PASSWORD_HASH</string>
    <boolean name="anonymousLoginPref" value="false" />
    <boolean name="pubKeyAuthPref" value="true" />
    <string name="whichServerToStartPref">2</string>
    <string name="securePortPref">$SERVER_PORT</string>
    <string name="bindIpPref">127.0.0.1</string>
    <boolean name="chooseIpToBindToPref" value="false" />
    <string name="startDirPref">$SERVER_DIRECTORY</string>
    <string name="storageTypePref">1</string>
    <boolean name="startOnOpenPref" value="true" />
    <boolean name="startOnBootPref" value="false" />
    <string name="idleTimeoutServerStopPref">0</string>
</map>
SETTINGS
OWNER=$(sudo stat -c '%u:%g' "$APP_DIR")
sudo mkdir -p "$APP_DIR/shared_prefs"
sudo cp "$WORK/preferences.xml" "$PREFS"
sudo chown "$OWNER" "$APP_DIR/shared_prefs" "$PREFS"
sudo chmod 700 "$APP_DIR/shared_prefs"
sudo chmod 600 "$PREFS"
android "/system/bin/restorecon -R '$APP_DIR/shared_prefs'"
SDK=$(getprop ro.build.version.sdk)
if (( SDK >= 30 )); then
 android "/system/bin/appops set --user '$ANDROID_USER' '$PACKAGE' MANAGE_EXTERNAL_STORAGE allow"
else
 android "/system/bin/pm grant --user '$ANDROID_USER' '$PACKAGE' android.permission.WRITE_EXTERNAL_STORAGE"
fi
if (( SDK >= 33 )); then
 android "/system/bin/pm grant --user '$ANDROID_USER' '$PACKAGE' android.permission.POST_NOTIFICATIONS"
fi
android "/system/bin/am start --user '$ANDROID_USER' -n '$PACKAGE/.ui.MainTabsActivity'"
for ((TRY=0; TRY<30; TRY++)); do
 if (exec 3<>/dev/tcp/127.0.0.1/1234) 2>/dev/null; then
  echo 'SFTP is listening. Connect as user to sftp://127.0.0.1:1234/ with your chosen password.'
  exit 0
 fi
 sleep 1
done
echo 'App installed and configured, but SFTP did not start. Check the app for a permissions or host-key prompt.' >&2
exit 1
