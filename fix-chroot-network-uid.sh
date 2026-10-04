#!/data/data/com.termux/files/usr/bin/bash
# Termux post-restore repair. Run before starting the desktop.
# Usage: bash fix-chroot-network-uid.sh anland|termux-x11|both [--dry-run|--apply]
# Uses standard Termux/Linux utilities; no separate helper.
# Optional: CHROOT_UID_MIN/MAX and CHROOT_UID_EXCLUDE (comma separated).
set -euo pipefail
PREFIX=/data/data/com.termux/files/usr

root_repair() {
 local NAME=$1 ROOT=$2 MODE=$3 LOW=$4 HIGH=$5 EXTRA=$6 BASE_PORT=$7
 export PATH="$PREFIX/bin:/system/bin" LC_ALL=C
 [[ $(id -u) == 0 && -d $ROOT/etc && ! -L $ROOT ]] || { echo 'Invalid rootfs or missing root access.'; return 1; }
 # Supply standard device/proc files even when a snapshot has empty mount points.
 mkdir -p "$ROOT/dev" "$ROOT/proc"
 mount --bind /dev "$ROOT/dev"
 mountpoint -q "$ROOT/proc" || mount -t proc proc "$ROOT/proc"
 local STATE="$ROOT/var/lib/chroot-network-uid/shell" JOB= LOGIN= OLD= NEW= PHASE= GID= USER_HOME= GROUPS_CSV=
 local PORT= TOKEN="uid-probe-$$-$BASE_PORT" ATTEMPT RETRY INODE FD READY
 LISTENER=
 cleanup_listener() { if [[ -n ${LISTENER:-} ]]; then kill "$LISTENER" 2>/dev/null || true; wait "$LISTENER" 2>/dev/null || true; fi; }
 trap cleanup_listener EXIT
 for ATTEMPT in {0..19}; do
  PORT=$((BASE_PORT + ATTEMPT))
  /system/bin/toybox nc -L -s 127.0.0.1 -p "$PORT" /system/bin/cat </dev/null >/dev/null 2>&1 &
  LISTENER=$!; READY=no
  for RETRY in {1..20}; do
   kill -0 "$LISTENER" 2>/dev/null || break
   INODE=$(awk -v port="$(printf '%04X' "$PORT")" '$2 == "0100007F:" port && $4 == "0A" {print $10}' /proc/net/tcp)
   if [[ -n $INODE ]]; then
    for FD in /proc/"$LISTENER"/fd/*; do [[ $(readlink "$FD" 2>/dev/null || true) != "socket:[$INODE]" ]] || READY=yes; done
   fi
   [[ $READY != yes ]] || break
   sleep 0.05
  done
  [[ $READY != yes ]] || break
  cleanup_listener; LISTENER=
 done
 [[ $READY == yes ]] || { echo 'Cannot start the local socket-test listener.'; return 1; }
 linux() { "$PREFIX/bin/chroot" "$ROOT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
 linux /bin/bash -c 'command -v setpriv >/dev/null && command -v timeout >/dev/null' || { echo 'Ubuntu needs its standard setpriv and timeout utilities.'; return 1; }
 probe() {
  linux /usr/bin/timeout 4 /usr/bin/setpriv --reuid "$1" --regid "$GID" --groups "$GROUPS_CSV" --inh-caps=-all --ambient-caps=-all \
   /bin/bash --noprofile --norc -c 'exec 3<>/dev/tcp/127.0.0.1/"$1"; printf "%s\n" "$2" >&3; IFS= read -r -t 2 reply <&3; [[ $reply == "$2" ]] && exec 4<>/dev/udp/127.0.0.1/"$1"' _ "$PORT" "$TOKEN" >/dev/null 2>&1
 }
 if [[ -f $STATE/pending ]]; then
  read -r JOB < "$STATE/pending"
  [[ $JOB =~ ^job-[0-9]+-[0-9]+$ && ! -L $STATE/$JOB ]] || { echo 'Invalid migration journal.'; return 1; }
  JOB="$STATE/$JOB"; read -r LOGIN OLD NEW PHASE < "$JOB/state"
  [[ $LOGIN =~ ^[a-zA-Z0-9_-]+$ && $OLD =~ ^[0-9]+$ && $NEW =~ ^[0-9]+$ && $(cat "$JOB/root") == "$ROOT" ]] || { echo 'Journal does not match this rootfs.'; return 1; }
 else
  if [[ $NAME == anland ]]; then
   [[ -f $ROOT/etc/anland-user.uid && ! -L $ROOT/etc/anland-user.uid ]] || { echo 'Missing AnLand user UID marker.'; return 1; }
   read -r OLD < "$ROOT/etc/anland-user.uid"; [[ $OLD =~ ^[0-9]+$ ]] || return 1
   LOGIN=$(awk -F: -v uid="$OLD" '$3 == uid {print $1; exit}' "$ROOT/etc/passwd")
  elif grep -q '^user:' "$ROOT/etc/passwd"; then LOGIN=user
  else
   LOGIN=$(awk -F: '$3 >= 1000 && $3 < 90000 && $6 ~ /^\/home\// && $7 !~ /(false|nologin)$/ {name=$1; count++} END {if(count == 1) print name}' "$ROOT/etc/passwd")
  fi
 fi
 [[ $LOGIN =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Cannot identify the desktop account unambiguously.'; return 1; }
 local ACCOUNT CURRENT_UID PASSWORD DESCRIPTION USER_SHELL
 ACCOUNT=$(linux /usr/bin/getent passwd "$LOGIN")
 IFS=: read -r LOGIN PASSWORD CURRENT_UID GID DESCRIPTION USER_HOME USER_SHELL <<< "$ACCOUNT"
 [[ $CURRENT_UID =~ ^[0-9]+$ && $GID =~ ^[0-9]+$ && $USER_HOME == /home/* && $(realpath -e "$ROOT$USER_HOME") == "$ROOT$USER_HOME" ]] || return 1
 GROUPS_CSV=$(linux /usr/bin/id -G "$LOGIN" | tr ' ' ',')
 if [[ -z $JOB ]] && probe "$CURRENT_UID"; then echo "$NAME: $LOGIN UID $CURRENT_UID already passes TCP/UDP checks."; return 0; fi
 local ENTRY PID PROCESS_ROOT BUSY= FILE MOUNT
 for ENTRY in /proc/[0-9]*/root; do
  PID=${ENTRY#/proc/}; PID=${PID%/root}; [[ $PID != $$ ]] || continue
  PROCESS_ROOT=$(readlink "$ENTRY" 2>/dev/null || true)
  if [[ $PROCESS_ROOT == "$ROOT" || $PROCESS_ROOT == "$ROOT/"* ]]; then BUSY+=" $PID"; fi
 done
 [[ -z $BUSY ]] || { echo "Stop $NAME before migration; active process IDs:$BUSY"; return 1; }
 local -a PRUNE=('(' -path "$ROOT/proc" -o -path "$ROOT/sys" -o -path "$ROOT/dev" -o -path "$ROOT/sdcard" -o -path "$ROOT/storage" -o -path "$ROOT/run" -o -path "$ROOT/tmp" -o -path "$ROOT/var/lib/chroot-network-uid")
 while IFS= read -r MOUNT; do
  printf -v MOUNT '%b' "$MOUNT"; [[ $MOUNT == "$ROOT/"* ]] || continue
  [[ $MOUNT != "$ROOT$USER_HOME" && $MOUNT != "$ROOT$USER_HOME/"* ]] || { echo 'Unmount paths in the desktop home before migration.'; return 1; }
  [[ $MOUNT != *[\[\]*?]* ]] || { echo 'Unmount paths containing glob characters before migration.'; return 1; }
  PRUNE+=(-o -path "$MOUNT")
 done < <(awk '{print $5}' /proc/self/mountinfo)
 PRUNE+=(')' -prune -o)
 if [[ -n $JOB ]]; then
  [[ $CURRENT_UID == "$OLD" || $CURRENT_UID == "$NEW" ]] && probe "$NEW" || { echo 'Pending migration conflicts with account/network state.'; return 1; }
  case $PHASE in prepared|ready|ownership|complete) ;; *) echo 'Unknown migration phase.'; return 1 ;; esac
 else
  local -A USED=(); local UID_NUMBER
  while read -r UID_NUMBER; do [[ ! $UID_NUMBER =~ ^[0-9]+$ ]] || USED[$UID_NUMBER]=1; done < <(
   awk -F: '{print $3}' "$ROOT/etc/passwd"
   /system/bin/pm list packages -U --user 0 | sed -n 's/.*uid:\([0-9][0-9]*\).*/\1/p'
   awk '/^Uid:/ {for(i=2;i<=NF;i++) print $i}' /proc/[0-9]*/status 2>/dev/null || true
   for FILE in /system/etc/passwd /vendor/etc/passwd; do [[ ! -f $FILE ]] || awk -F: '{print $3}' "$FILE"; done
   printf '%s\n' "${EXTRA//,/$'\n'}"
  )
  for ((UID_NUMBER=LOW; UID_NUMBER<=HIGH; UID_NUMBER++)); do
   [[ -z ${USED[$UID_NUMBER]:-} ]] || continue
   (( UID_NUMBER >= 30000 )) || continue
   if probe "$UID_NUMBER"; then NEW=$UID_NUMBER; break; fi
  done
  [[ -n $NEW ]] || { echo 'No working unused UID found in the configured range.'; return 1; }; OLD=$CURRENT_UID
 fi
 echo "$NAME: discovered UID $NEW for $LOGIN (current UID $OLD); primary GID $GID stays unchanged."
 if [[ $MODE == --dry-run ]]; then echo 'Dry run: no accounts or files changed.'; return 0; fi
 write_phase() {
  printf '%s %s %s %s\n' "$LOGIN" "$OLD" "$NEW" "$1" > "$JOB/state.tmp"
  sync -f "$JOB/state.tmp"; mv -- "$JOB/state.tmp" "$JOB/state"; PHASE=$1
 }
 umask 077
 if [[ -z $JOB ]]; then
  [[ ! -L $STATE && ! -L $ROOT/var/lib/chroot-network-uid ]] || { echo 'Unexpected journal symlink.'; return 1; }
  mkdir -p "$STATE"; JOB="$STATE/job-$(date +%s)-$$"; mkdir "$JOB"
  printf '%s\n' "$ROOT" > "$JOB/root"
  for FILE in passwd shadow group gshadow anland-user.uid; do [[ ! -f $ROOT/etc/$FILE ]] || cp -p -- "$ROOT/etc/$FILE" "$JOB/$FILE.before"; done
  write_phase prepared
  printf '%s\n' "${JOB##*/}" > "$STATE/pending.tmp"
  sync -f "$STATE/pending.tmp"; mv -- "$STATE/pending.tmp" "$STATE/pending"
 fi
 if [[ $PHASE == prepared ]]; then
  find "$ROOT" -xdev "${PRUNE[@]}" -uid "$OLD" -print0 > "$JOB/owned.files"
  # ACL records retain ownership, modes, and setuid/setgid flags as well.
  find "$ROOT" -xdev "${PRUNE[@]}" -uid "$OLD" ! -type l -print0 > "$JOB/owned.acl.files"
  xargs -0 -r getfacl -P -p -n -- < "$JOB/owned.acl.files" > "$JOB/owned.acl"
  find "$ROOT" -xdev "${PRUNE[@]}" ! -type l -print0 > "$JOB/acl.files"
  xargs -0 -r getfacl -P -p -n -s -- < "$JOB/acl.files" > "$JOB/extended.acl"
  xargs -0 -r getfattr --absolute-names -h -d -e hex -m '^security\.capability$' -- < "$JOB/owned.files" > "$JOB/capabilities.before"
  awk -v old="$OLD" -v new="$NEW" '
   $0 == "# owner: " old {$0="# owner: " new}
   {sub("^user:" old ":", "user:" new ":"); sub("^default:user:" old ":", "default:user:" new ":"); print}
  ' "$JOB/owned.acl" "$JOB/extended.acl" > "$JOB/permissions.after"
  sync -f "$JOB/permissions.after"; write_phase ready
 fi
 if [[ $(linux /usr/bin/id -u "$LOGIN") == "$OLD" ]]; then linux /usr/sbin/usermod -u "$NEW" "$LOGIN"; fi
 write_phase ownership
 while IFS= read -r -d '' FILE; do
  [[ -e $FILE || -L $FILE ]] || continue
  chown -h --from="$OLD" "$NEW" -- "$FILE"
 done < "$JOB/owned.files"
 # Apply records individually: newer ACL --restore -P needs openat2, which
 # Android 13's 4.19 kernel does not provide. Validate paths before each write.
 local ACL_PATH= ACL_TEXT= ACL_FLAGS=--- LINE
 restore_acl_record() {
  [[ -n $ACL_PATH ]] || return 0
  [[ $ACL_PATH == "$ROOT" || $ACL_PATH == "$ROOT/"* ]] || return 1
  [[ ! -L $ACL_PATH && $(realpath -e "$ACL_PATH") == "$ACL_PATH" ]] || { echo 'ACL path changed during migration.'; return 1; }
  setfacl --set-file=- -- "$ACL_PATH" <<< "$ACL_TEXT"
  chmod u-s,g-s,o-t -- "$ACL_PATH"
  [[ ${ACL_FLAGS:0:1} != s ]] || chmod u+s -- "$ACL_PATH"
  [[ ${ACL_FLAGS:1:1} != s ]] || chmod g+s -- "$ACL_PATH"
  [[ ${ACL_FLAGS:2:1} != t ]] || chmod o+t -- "$ACL_PATH"
 }
 while IFS= read -r LINE || [[ -n $LINE ]]; do
  case $LINE in
   '# file: '*) restore_acl_record; printf -v ACL_PATH '%b' "${LINE#\# file: }"; ACL_TEXT=; ACL_FLAGS=--- ;;
   '# flags: '*) ACL_FLAGS=${LINE#\# flags: } ;;
   '#'*|'') ;;
   *) ACL_TEXT+="$LINE"$'\n' ;;
  esac
 done < "$JOB/permissions.after"
 restore_acl_record
 local CAP_PATH= CAP_VALUE
 while IFS= read -r LINE || [[ -n $LINE ]]; do
  case $LINE in
   '# file: '*) printf -v CAP_PATH '%b' "${LINE#\# file: }" ;;
   security.capability=*)
    CAP_VALUE=${LINE#security.capability=}
    [[ $CAP_PATH == "$ROOT/"* && ! -L $CAP_PATH && $(realpath -e "$CAP_PATH") == "$CAP_PATH" && $CAP_VALUE =~ ^0x[0-9a-fA-F]+$ ]] || return 1
    setfattr -h -n security.capability -v "$CAP_VALUE" -- "$CAP_PATH"
    ;;
  esac
 done < "$JOB/capabilities.before"
 if [[ $NAME == anland ]]; then printf '%s\n' "$NEW" > "$ROOT/etc/anland-user.uid"; fi
 [[ $(linux /usr/bin/id -u "$LOGIN") == "$NEW" ]] && probe "$NEW" || { echo "Post-migration check failed; rerun to resume. Journal: $JOB"; return 1; }
 write_phase complete; rm -f -- "$STATE/pending"
 echo "$NAME: repair complete; TCP/UDP checks passed. Recovery records: $JOB"
}

if [[ ${1:-} == --root-repair ]]; then shift; root_repair "$@"; exit; fi
TARGET=${1:-both}; MODE=${2:---dry-run}
LOW=${CHROOT_UID_MIN:-60000}; HIGH=${CHROOT_UID_MAX:-60999}; EXTRA=${CHROOT_UID_EXCLUDE:-}
case "$TARGET" in anland|termux-x11|both) ;; *) echo 'Target: anland, termux-x11, or both'; exit 2 ;; esac
case "$MODE" in --dry-run|--apply) ;; *) echo 'Mode: --dry-run or --apply'; exit 2 ;; esac
[[ $LOW =~ ^[0-9]+$ && $HIGH =~ ^[0-9]+$ && $EXTRA =~ ^[0-9,]*$ ]] || { echo 'UID limits/exclusions must be numeric.'; exit 2; }
LOW=$((10#$LOW)); HIGH=$((10#$HIGH))
((LOW >= 5000 && LOW <= HIGH && HIGH < 90000 && HIGH-LOW <= 10000)) || { echo 'Choose a bounded UID range between 5000 and 89999.'; exit 2; }
export PATH="$PREFIX/bin:/system/bin"
for TOOL in flock unshare chroot find xargs getfacl setfacl getfattr setfattr; do command -v "$TOOL" >/dev/null || { echo "Missing standard Termux utility: $TOOL"; exit 1; }; done
SELF=$(realpath "$0")
exec 9>"$PREFIX/tmp/chroot-network-uid.lock"
flock -n 9 || { echo 'Another UID repair is running.'; exit 1; }
for NAME in termux-x11 anland; do
 [[ "$TARGET" == both || "$TARGET" == "$NAME" ]] || continue
 if [[ $NAME == anland ]]; then ROOT=/data/local/anland-ubuntu26; else ROOT=/data/local/ubuntu; fi
 BASE_PORT=$((32768 + RANDOM % 20000))
 printf -v ROOT_COMMAND '%q ' "$PREFIX/bin/unshare" --mount --propagation private "$PREFIX/bin/bash" "$SELF" --root-repair "$NAME" "$ROOT" "$MODE" "$LOW" "$HIGH" "$EXTRA" "$BASE_PORT"
 (unset LD_PRELOAD LD_LIBRARY_PATH; su -c "$ROOT_COMMAND")
done
