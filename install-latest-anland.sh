#!/data/data/com.termux/files/usr/bin/bash
# Install/update the latest AnLand daemon and Android Compatible app only.
# Run as the normal Termux user. Ubuntu and our launcher scripts are unchanged.
set -euo pipefail
REPO=https://github.com/lfdevs/anland-termux
API=https://api.github.com/repos/lfdevs/anland-termux/releases/latest
DOWNLOADS="$HOME/anland-downloads"

[[ $(id -u) != 0 && $HOME == /data/data/com.termux/files/home && $(uname -m) == aarch64 ]] || {
 echo 'Run this as the normal user in ARM64 Termux (com.termux).'; exit 1;
}
[[ $(su -c id -u | tr -d '\r\n') == 0 ]] || { echo 'Grant Termux root access first.'; exit 1; }
if [[ -x $HOME/anland ]]; then
 "$HOME/anland" status | grep '"stopped": true' >/dev/null || {
  echo 'Log out of AnLand and finish its shutdown before updating.'; exit 1;
 }
fi

# Install download tools only if missing; keep existing Termux packages intact.
MISSING=()
command -v curl >/dev/null || MISSING+=(curl)
command -v node >/dev/null || MISSING+=(nodejs)
if ((${#MISSING[@]})); then
 apt-get update
 PLAN=$(apt-get -s --no-upgrade --no-remove install "${MISSING[@]}")
 if grep -E '^Remv |^Inst [^ ]+ \[' <<< "$PLAN" >/dev/null; then
  echo "$PLAN"; echo 'Dependency conflict; existing packages were left alone.'; exit 1
 fi
 apt-get --no-upgrade --no-remove install -y "${MISSING[@]}"
fi

# Ask upstream for the latest stable release, not a hardcoded version.
echo "AnLand repository: $REPO"
echo "Latest release API: $API"
mkdir -p "$DOWNLOADS"
curl -fL --retry 3 "$API" -o "$DOWNLOADS/release.json"

# Node is already needed by our logout scripts. Use it to read GitHub's JSON.
# Select the Compatible Android app and matching ARM64 Termux daemon only.
node - "$DOWNLOADS/release.json" > "$DOWNLOADS/assets.txt" <<'JS'
const release = require(process.argv[2]);
console.error(`Latest release: ${release.tag_name}\n${release.html_url}`);
for (const [file, pattern] of [
 ['anland.apk', /^AnlandTermux-.*-compatible\.apk$/],
 ['anland.deb', /^anland_.*_aarch64\.deb$/]
]) {
 const matches = (release.assets || []).filter(asset => pattern.test(asset.name));
 if (matches.length !== 1) throw Error(`Cannot identify ${file}. Check the repository's release assets.`);
 const asset = matches[0];
 if (!/^sha256:[a-f0-9]{64}$/.test(asset.digest || '')) throw Error(`Missing SHA256 for ${asset.name}. Check the release.`);
 console.log(`${file} ${asset.browser_download_url} ${asset.digest.slice(7)}`);
}
JS

# Download each file separately, then verify GitHub's published checksum.
while read -r FILE URL HASH; do
 echo "Downloading: $URL"
 curl -fL --retry 3 "$URL" -o "$DOWNLOADS/$FILE"
 printf '%s  %s\n' "$HASH" "$DOWNLOADS/$FILE" | sha256sum -c -
done < "$DOWNLOADS/assets.txt"

# Install/update the daemon in Termux and the Compatible APK in Android.
dpkg -i "$DOWNLOADS/anland.deb"
(unset LD_PRELOAD LD_LIBRARY_PATH; su -c "/system/bin/pm install -r '$DOWNLOADS/anland.apk'")

echo 'Latest AnLand daemon and Android Compatible app installed.'
echo 'Ubuntu/KDE/Mesa packages were not changed. Log in again to use the update.'
