#!/usr/bin/env bash
# Privacy and ad-blocking settings.
#  - Cuts microphone access for Google search/Assistant, Gboard, Cast and Play
#    services. Typed search with the remote keeps working; the mic button won't hear you.
#  - Sets Private DNS to an ad/tracker-blocking resolver (AdGuard by default).
#  - Turns off location, background Wi-Fi/Bluetooth scanning and error reporting.
#
#   --dns HOST         Private DNS hostname (default: dns.adguard-dns.com)
#   --no-dns           leave DNS alone
#   --keep-mic         leave microphone permissions alone
#   --fast-animations  set UI animations to 0.5x (snappier menus)
#   -n, --dry-run      show what would happen
#   -y, --yes          don't ask for confirmation
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

DNS_HOST="dns.adguard-dns.com"; DO_DNS=1; DO_MIC=1; FAST_ANIM=0
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    --dns)             [ $# -ge 2 ] || die "--dns needs a hostname"; DNS_HOST="$2"; shift ;;
    --no-dns)          DO_DNS=0 ;;
    --keep-mic)        DO_MIC=0 ;;
    --fast-animations) FAST_ANIM=1 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

require_device

if [ -z "$(latest_backup)" ] && [ "$DRY_RUN" != 1 ]; then
  info "No backup yet. Making one first."
  "$(dirname "$0")/01-backup.sh"
fi

put() { # namespace key value
  if run_sh settings put "$1" "$2" "$3"; then ok "$1/$2 = $3"; else warn "couldn't set $1/$2: $RUN_OUT"; fi
}

if [ "$DO_MIC" = 1 ]; then
  info "Cutting microphone access (typed search still works)"
  for pkg in $MIC_PKGS; do
    has_pkg "$pkg" || continue
    # The runtime permission. Privileged apps may refuse this; the app-op below still applies.
    run_sh pm revoke "$pkg" android.permission.RECORD_AUDIO || true
    if run_sh appops set "$pkg" RECORD_AUDIO ignore; then
      ok "$pkg: microphone blocked"
    else
      warn "$pkg: couldn't block microphone ($RUN_OUT)"
    fi
  done
fi

if [ "$DO_DNS" = 1 ]; then
  info "Private DNS -> $DNS_HOST (blocks ads and trackers for every app)"
  put global private_dns_mode hostname
  put global private_dns_specifier "$DNS_HOST"
fi

info "Location, background scanning, error reporting"
if run_sh cmd location set-location-enabled false; then
  ok "location off"
else
  put secure location_mode 0
fi
put global wifi_scan_always_enabled 0
put global ble_scan_always_enabled 0
put global send_action_app_error 0

if [ "$FAST_ANIM" = 1 ]; then
  info "Animations at 0.5x"
  put global window_animation_scale 0.5
  put global transition_animation_scale 0.5
  put global animator_duration_scale 0.5
fi

info "Done. A few things can only be changed on the TV itself:"
note "Settings > Privacy > Ads > Delete advertising ID (or 'Opt out of Ads Personalization')"
note "Settings > Privacy > Usage & diagnostics > OFF"
note "Settings > Privacy > Google Assistant / Search > turn off personal results & 'Hey Google'"
note "Settings > Accounts > your Google account > turn off 'Personalized recommendations'"
note "myactivity.google.com (on your phone): pause Web & App Activity and YouTube History"
[ "$DRY_RUN" = 1 ] && note "(dry run, nothing was changed)"
exit 0
