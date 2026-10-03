#!/data/data/com.termux/files/usr/bin/bash
# Install matching Termux-X11 Android and Termux packages from the official nightly.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=https://github.com/termux/termux-x11
API=https://api.github.com/repos/termux/termux-x11/releases/tags/nightly
# Standard APK works with the usual Termux distributions. The sharedUid variant
# requires GitHub-signed Termux; set TERMUX_X11_APK to that filename if using it.
APK_NAME=${TERMUX_X11_APK:-termux-x11-universal-debug.apk}
if [[ ${1:-} != --confirmed ]]; then
 read -r -p 'Close Termux-X11 and update its Android app and Termux package? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
fi
command -v curl >/dev/null || apt install -y curl
DOWNLOADS=$(mktemp -d "$PREFIX/tmp/chroot-termux-x11-update.XXXXXX")
trap 'rm -rf "$DOWNLOADS"' EXIT
echo "Termux-X11 repository: $REPO"
echo "Nightly release API: $API"
curl -fL --retry 3 "$API" -o "$DOWNLOADS/release.json"
NAME=
DIGEST=
while IFS= read -r LINE; do
 case "$LINE" in
  *'"name":'*) NAME=$(printf '%s' "$LINE" | cut -d '"' -f 4); DIGEST= ;;
  *'"digest":'*) DIGEST=$(printf '%s' "$LINE" | cut -d '"' -f 4) ;;
  *'"browser_download_url":'*)
   URL=$(printf '%s' "$LINE" | cut -d '"' -f 4)
   case "$NAME" in
    "$APK_NAME") echo "termux-x11.apk $URL $DIGEST" ;;
    termux-x11-nightly-*-all.deb) echo "termux-x11.deb $URL $DIGEST" ;;
   esac ;;
 esac
done < "$DOWNLOADS/release.json" > "$DOWNLOADS/assets.txt"
[[ $(wc -l < "$DOWNLOADS/assets.txt") == 2 ]] || { echo "Check release assets at $REPO/releases/tag/nightly"; exit 1; }
for FILE in termux-x11.apk termux-x11.deb; do
 [[ $(grep -c "^$FILE " "$DOWNLOADS/assets.txt") == 1 ]] || exit 1
done
while read -r FILE URL DIGEST; do
 [[ $URL == "$REPO/releases/download/nightly/"* && $DIGEST =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid URL or missing checksum.'; exit 1; }
 echo "Downloading: $URL"
 curl -fL --retry 3 "$URL" -o "$DOWNLOADS/$FILE"
 printf '%s  %s\n' "${DIGEST#sha256:}" "$DOWNLOADS/$FILE" | sha256sum -c -
done < "$DOWNLOADS/assets.txt"
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
dpkg -i "$DOWNLOADS/termux-x11.deb"
# Redirect inside the root shell to avoid Android Binder/terminal failures.
if ! (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/pm install -r '$DOWNLOADS/termux-x11.apk' </dev/null >'$DOWNLOADS/apk-install.log' 2>&1"); then
 cat "$DOWNLOADS/apk-install.log"
 echo 'APK update failed. Existing app data was not removed.' >&2
 exit 1
fi
cat "$DOWNLOADS/apk-install.log"
echo 'Termux-X11 Android app and Termux package updated. Ubuntu data was kept.'
