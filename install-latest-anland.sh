#!/data/data/com.termux/files/usr/bin/bash
# Install/update the latest Compatible Android app and matching Termux daemon.
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr
REPO=https://github.com/lfdevs/anland-termux
API=https://api.github.com/repos/lfdevs/anland-termux/releases/latest
[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home && $(uname -m) == aarch64 ]] || {
 echo 'Run this as the normal user in ARM64 Termux (com.termux).'; exit 1;
}
[[ $(su -c id -u | tr -d '\r\n') == 0 ]] || { echo 'Grant Termux root access first.'; exit 1; }

# Updating an active compositor is unsafe. The main installer stops it first.
if ! su -c 'for p in /proc/[0-9]*/root; do
 [ "$(readlink "$p" 2>/dev/null)" != /data/local/anland-ubuntu26 ] || exit 1
done'; then
 echo 'Close the AnLand desktop before updating its display app.'; exit 1
fi
command -v curl >/dev/null || apt install -y curl
# Downloads are temporary, including when an install fails or is interrupted.
DOWNLOADS=$(mktemp -d "$PREFIX/tmp/anland-downloads.XXXXXX")
trap 'rm -rf "$DOWNLOADS"' EXIT
echo "AnLand repository: $REPO"
echo "Latest release API: $API"
curl -fL --retry 3 "$API" -o "$DOWNLOADS/release.json"

# GitHub lists each asset's name, digest and download URL in that order.
# Select only the Compatible APK and ARM64 daemon. Stop if the format changes.
awk -F '"' '
 /"name":/ {name=$4}
 /"digest":/ {digest=$4}
 /"browser_download_url":/ {
  file=""
  if (name ~ /^AnlandTermux-.*-compatible\.apk$/) file="anland.apk"
  if (name ~ /^anland_.*_aarch64\.deb$/) file="anland.deb"
  if (file != "") print file, $4, digest
 }
' "$DOWNLOADS/release.json" > "$DOWNLOADS/assets.txt"
[[ $(wc -l < "$DOWNLOADS/assets.txt") == 2 ]] || {
 echo "Cannot identify both release files. Check $REPO/releases"; exit 1;
}
for FILE in anland.apk anland.deb; do
 [[ $(grep -c "^$FILE " "$DOWNLOADS/assets.txt") == 1 ]] || exit 1
done
while read -r FILE URL DIGEST; do
 [[ $URL == "$REPO/releases/download/"* && $DIGEST =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo 'Invalid asset URL or missing SHA256; check the upstream release.'; exit 1;
 }
 echo "Downloading: $URL"
 curl -fL --retry 3 "$URL" -o "$DOWNLOADS/$FILE.part"
 printf '%s  %s\n' "${DIGEST#sha256:}" "$DOWNLOADS/$FILE.part" | sha256sum -c -
 mv "$DOWNLOADS/$FILE.part" "$DOWNLOADS/$FILE"
done < "$DOWNLOADS/assets.txt"

dpkg -i "$DOWNLOADS/anland.deb"
# Android's Binder service can reject inherited Termux terminal descriptors.
# Redirect all three streams inside the root shell, then show the result.
APK_LOG="$DOWNLOADS/apk-install.log"
if ! (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/pm install -r '$DOWNLOADS/anland.apk' </dev/null >'$APK_LOG' 2>&1"); then
 cat "$APK_LOG"
 exit 1
fi
cat "$APK_LOG"
echo 'Latest AnLand app and daemon installed. Ubuntu packages were not changed.'
