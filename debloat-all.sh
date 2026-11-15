#!/usr/bin/env bash
# Run the full debloat in order: backup -> remove bloat -> privacy -> launcher.
# Connect first with: scripts/00-connect.sh <tv-ip>
#
#   -n, --dry-run    preview every command without changing anything
#   -y, --yes        don't stop to ask between steps
#   --keep-apps      keep the preinstalled streaming apps (YouTube, Netflix...)
#   --keep-stock     set Projectivy as home but don't disable the stock launcher
#   --apk FILE       install Projectivy from a local APK instead of the Play Store
#   --dns HOST       Private DNS host (default dns.adguard-dns.com), --no-dns to skip
#   --fast-animations
source "$(dirname "$0")/lib/common.sh"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

DEBLOAT_ARGS=(); PRIVACY_ARGS=(); LAUNCHER_ARGS=()
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    --keep-apps)       DEBLOAT_ARGS+=("$1") ;;
    --keep-stock)      LAUNCHER_ARGS+=("$1") ;;
    --no-dns|--fast-animations|--keep-mic) PRIVACY_ARGS+=("$1") ;;
    --apk) [ $# -ge 2 ] || die "--apk needs a file"; LAUNCHER_ARGS+=("$1" "$2"); shift ;;
    --dns) [ $# -ge 2 ] || die "--dns needs a hostname"; PRIVACY_ARGS+=("$1" "$2"); shift ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

S="$ROOT_DIR/scripts"
require_device

step() { # title, script, args...
  local title="$1"; shift
  echo
  if confirm "Next: $title. Continue?"; then "$@"; else warn "skipped: $title"; fi
}

if [ "$DRY_RUN" = 1 ]; then
  info "DRY RUN: nothing on the TV will change."
else
  "$S/01-backup.sh"
fi
step "remove ads, telemetry and preinstalled apps" "$S/02-debloat.sh" ${DEBLOAT_ARGS[@]+"${DEBLOAT_ARGS[@]}"}
step "privacy (mic off, ad-blocking DNS, location off)" "$S/03-privacy.sh" ${PRIVACY_ARGS[@]+"${PRIVACY_ARGS[@]}"}
step "install Projectivy and make it the boot launcher" "$S/04-launcher.sh" ${LAUNCHER_ARGS[@]+"${LAUNCHER_ARGS[@]}"}

echo
info "All done. Log: ${LOG_FILE#"$ROOT_DIR"/}"
note "To undo anything: scripts/restore.sh --help"
