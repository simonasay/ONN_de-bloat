#!/usr/bin/env bash
# Remove ads/recommendation services, telemetry and preinstalled apps for the
# current user. Nothing is deleted from the system partition. Everything can be
# put back with scripts/restore.sh (or a factory reset).
#
#   --keep-apps     don't touch bloat-apps.txt (streaming apps)
#   --list NAME     only process packages/NAME.txt (repeatable)
#   --disable       disable instead of uninstall (gentler, keeps app data)
#   -n, --dry-run   show what would happen
#   -y, --yes       don't ask for confirmation
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

LISTS=""; KEEP_APPS=0; MODE="uninstall"
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    --keep-apps) KEEP_APPS=1 ;;
    --disable)   MODE="disable" ;;
    --list)      [ $# -ge 2 ] || die "--list needs a name"; LISTS="$LISTS ${2%.txt}"; shift ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done
if [ -z "$LISTS" ]; then
  LISTS="ads-recommendations telemetry"
  [ "$KEEP_APPS" = 1 ] || LISTS="$LISTS bloat-apps"
fi

require_device

if [ -z "$(latest_backup)" ] && [ "$DRY_RUN" != 1 ]; then
  info "No backup yet. Making one first."
  "$(dirname "$0")/01-backup.sh"
fi

removed=0; skipped=0; failed=0
for list in $LISTS; do
  info "Processing packages/$list.txt ($MODE)"
  for pkg in $(read_list "$PKG_DIR/$list.txt"); do
    if is_protected "$pkg"; then
      warn "$pkg is in NEVER-REMOVE.txt, skipping"; skipped=$((skipped+1)); continue
    fi
    if ! has_pkg "$pkg"; then
      note "$pkg (not installed)"; skipped=$((skipped+1)); continue
    fi
    if [ "$MODE" = "uninstall" ] && run_sh pm uninstall --user 0 "$pkg"; then
      ok "$pkg removed"; removed=$((removed+1))
    elif run_sh pm disable-user --user 0 "$pkg"; then
      ok "$pkg disabled"; removed=$((removed+1))
    else
      warn "$pkg couldn't be removed or disabled: $RUN_OUT"; failed=$((failed+1))
    fi
  done
done

info "Done: $removed removed/disabled, $skipped skipped, $failed failed"
[ "$DRY_RUN" = 1 ] && note "(dry run, nothing was changed)"
exit 0
