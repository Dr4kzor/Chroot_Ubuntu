#!/data/data/com.termux/files/usr/bin/bash
# Restore only the regular Ubuntu, using the original sudo/tar method.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=/data/local/ubuntu
MODE=${1:-}
case $MODE in --check|--confirmed|--shortcuts-only) shift ;; esac
if [[ $MODE != --shortcuts-only ]]; then
BACKUP=${1:-$HOME/ubuntu-termux-x11-backup.tar.gz}
[[ -f $BACKUP ]] || { echo "Snapshot not found: $BACKUP"; exit 1; }
tar -tzf "$BACKUP" | (
 VALID=yes
 COUNT=0
 while IFS= read -r ENTRY; do
  ENTRY=${ENTRY#./}
  COUNT=$((COUNT + 1))
  case "$ENTRY" in data/local/ubuntu|data/local/ubuntu/*) ;; *) VALID=no ;; esac
  case "/$ENTRY/" in */../*) VALID=no ;; esac
 done
 [[ $VALID == yes && $COUNT -gt 0 ]]
) || { echo 'Not a valid Termux-X11 Ubuntu snapshot.'; exit 1; }
[[ $MODE != --check ]] || exit 0
if [[ $MODE != --confirmed ]]; then
 read -r -p 'Replace Termux-X11 Ubuntu with this snapshot? [y/N] ' ANSWER
 [[ $ANSWER == [yY] || $ANSWER == [yY][eE][sS] ]] || exit 0
fi
sudo test ! -L "$ROOT" || { echo 'Unexpected Ubuntu directory symlink.'; exit 1; }
bash "$SCRIPT_DIR/stop-chroot-termux-x11.sh"
sudo rm -rf "$ROOT"
sudo mkdir -p "$ROOT"/{proc,sys,dev,sdcard,tmp}
sudo tar --numeric-owner --xattrs --acls -xpf "$BACKUP" -C /
sudo mkdir -p "$ROOT/tmp"
sudo chmod 1777 "$ROOT/tmp"
fi

# Restore snapshot shortcuts without touching AnLand's shortcuts or icons.
mkdir -p "$HOME/.shortcuts/icons"
# Import only this desktop's five saved scripts and icons in the loop below.
# Unrelated host shortcuts, including refresh-rate controls, stay untouched.
# Filenames determine Widget ordering; each icon must match its script exactly.
while read -r NUMBER LABEL ACTION LEGACY; do
 NAME="$NUMBER-termux-x11-$LABEL.sh"
 ICON="$HOME/.shortcuts/icons/$NAME.png"
 if [[ $MODE != --shortcuts-only ]]; then
  for OLD in "$NAME" "$LEGACY.sh" "$ACTION-chroot-termux-x11.sh"; do
   if sudo test -f "$ROOT/opt/.shortcuts/icons/$OLD.png"; then
    sudo cp "$ROOT/opt/.shortcuts/icons/$OLD.png" "$ICON"
    sudo chown "$(id -u):$(id -g)" "$ICON"; break
   fi
  done
 fi
 if [[ ! -f $ICON ]]; then
  for OLD in "$LEGACY.sh" "$ACTION-chroot-termux-x11.sh"; do
   if [[ -f $HOME/.shortcuts/icons/$OLD.png ]]; then
    cp "$HOME/.shortcuts/icons/$OLD.png" "$ICON"; break
   fi
  done
 fi
 # Earlier X11 snapshots have no Stop icon; use XFCE's existing logout PNG.
 if [[ ! -f $ICON && $ACTION == stop ]]; then
  for SOURCE in "$ROOT/usr/share/icons/hicolor/48x48/actions/xfsm-logout.png" "$ROOT/usr/share/icons/elementary-xfce/actions/48/system-log-out.png"; do
   if sudo test -f "$SOURCE"; then
    sudo cp "$SOURCE" "$ICON"; sudo chown "$(id -u):$(id -g)" "$ICON"; break
   fi
  done
  [[ -f $ICON ]] || cp "$HOME/.shortcuts/icons/1-termux-x11-run.sh.png" "$ICON"
 fi
 [[ -f $ICON ]] || { echo "Missing shortcut icon: $NAME" >&2; exit 1; }
 chmod 644 "$ICON"
 # Preserve the saved script's contents; only change its filename.
 SOURCE=
 if [[ $MODE == --shortcuts-only ]]; then
  for OLD in "$NAME" "$LEGACY.sh" "$ACTION-chroot-termux-x11.sh"; do
   [[ ! -f $HOME/.shortcuts/$OLD ]] || { SOURCE="$HOME/.shortcuts/$OLD"; break; }
  done
  if [[ -n $SOURCE ]]; then cp "$SOURCE" "$HOME/.shortcuts/$NAME.new"; fi
 else
  for OLD in "$NAME" "$LEGACY.sh" "$ACTION-chroot-termux-x11.sh"; do
   if sudo test -f "$ROOT/opt/.shortcuts/$OLD"; then SOURCE="$ROOT/opt/.shortcuts/$OLD"; break; fi
  done
  if [[ -n $SOURCE ]]; then
   sudo cp "$SOURCE" "$HOME/.shortcuts/$NAME.new"
   sudo chown "$(id -u):$(id -g)" "$HOME/.shortcuts/$NAME.new"
  fi
 fi
 if [[ -n $SOURCE ]]; then
  mv -f "$HOME/.shortcuts/$NAME.new" "$HOME/.shortcuts/$NAME"
 else
 case $ACTION in
  run|safe-mode) echo "Missing saved shortcut: $NAME" >&2; exit 1 ;;
  stop) printf '#!/data/data/com.termux/files/usr/bin/bash\nexec bash "%s/stop-chroot-termux-x11.sh"\n' "$SCRIPT_DIR" > "$HOME/.shortcuts/$NAME" ;;
  backup) printf '#!/data/data/com.termux/files/usr/bin/bash\nexec bash "%s/backup-chroot-termux-x11.sh"\n' "$SCRIPT_DIR" > "$HOME/.shortcuts/$NAME" ;;
  restore)
   printf '#!/data/data/com.termux/files/usr/bin/bash\nBACKUP="$HOME/ubuntu-termux-x11-backup.tar.gz"\n[[ -f $BACKUP ]] || read -r -p "Snapshot path: " BACKUP\nexec bash "%s/restore-chroot-termux-x11.sh" "$BACKUP"\n' "$SCRIPT_DIR" > "$HOME/.shortcuts/$NAME"
   ;;
 esac
 fi
 chmod 755 "$HOME/.shortcuts/$NAME"
 rm -f "$HOME/.shortcuts/$LEGACY.sh" "$HOME/.shortcuts/icons/$LEGACY.sh.png" "$HOME/.shortcuts/$ACTION-chroot-termux-x11.sh" "$HOME/.shortcuts/icons/$ACTION-chroot-termux-x11.sh.png"
done <<'SHORTCUT_NAMES'
1 run run 1-ubuntu
2 safe-mode safe-mode 2-safe_mode
3 save-snapshot backup 3-save_ubuntu_snapshot
4 load-snapshot restore 4-load_ubuntu_snapshot
5 stop stop stop-termux-x11
SHORTCUT_NAMES
rm -f "$HOME/.shortcuts/"{0-Ubuntu,0-ubuntu}.sh "$HOME/.shortcuts/icons/"{0-Ubuntu,0-ubuntu}.sh.png
if [[ $MODE == --shortcuts-only ]]; then
 echo 'Termux-X11 shortcuts ready. Use 1-termux-x11-run.'
else
 echo 'Termux-X11 Ubuntu restored. Open the menu with: chroot_manager'
fi
