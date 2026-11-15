#!/usr/bin/env bash
# Undo the debloat. With no options, restores everything.
#
#   --launcher            re-enable the stock Google TV launcher and make it home again
#   --packages            reinstall/re-enable every package from the lists
#   --privacy             give microphones back, reset DNS/location/scan settings
#   --from-backup [DIR]   use a backup (default: the latest) to restore exactly the
#                         packages and settings that existed when it was taken
#   -n, --dry-run         show what would happen
#   -y, --yes             don't ask for confirmation
#
# Anything else removed by hand can be put back with:
#   adb shell cmd package install-existing <package>
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

DO_LAUNCHER=0; DO_PACKAGES=0; DO_PRIVACY=0; FROM=""
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    --launcher) DO_LAUNCHER=1 ;;
    --packages) DO_PACKAGES=1 ;;
    --privacy)  DO_PRIVACY=1 ;;
    --from-backup)
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then FROM="$2"; shift; else FROM="latest"; fi ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done
if [ "$DO_LAUNCHER$DO_PACKAGES$DO_PRIVACY" = "000" ]; then
  DO_LAUNCHER=1; DO_PACKAGES=1; DO_PRIVACY=1
fi
if [ "$FROM" = "latest" ]; then
  FROM="$(latest_backup)"
  [ -n "$FROM" ] || die "No backups found in backups/"
fi
if [ -n "$FROM" ]; then
  [ -f "$FROM/packages-installed.txt" ] || die "Not a backup folder: $FROM"
  info "Using backup ${FROM#"$ROOT_DIR"/}"
fi

require_device
confirm "Restore (launcher=$DO_LAUNCHER packages=$DO_PACKAGES privacy=$DO_PRIVACY)?" || exit 1

DISABLED="$(adb_sh pm list packages -d | sed 's/^package://')"

bring_back() { # pkg
  local pkg="$1" did=0
  if ! has_pkg "$pkg"; then
    if run_sh cmd package install-existing --user 0 "$pkg" || run_sh cmd package install-existing "$pkg"; then
      did=1
    else
      note "$pkg (not on this device)"; return 0
    fi
  fi
  if in_lines "$pkg" "$DISABLED"; then
    if run_sh pm enable --user 0 "$pkg"; then did=1; else warn "$pkg: couldn't enable ($RUN_OUT)"; fi
  fi
  if [ "$did" = 1 ]; then ok "$pkg restored"; fi
  return 0
}

# Launcher first, so there's always a working home screen.
if [ "$DO_LAUNCHER" = 1 ]; then
  info "Re-enabling the stock launcher"
  for pkg in $(read_list "$PKG_DIR/stock-launcher.txt"); do bring_back "$pkg"; done
  refresh_pkgs
  stock="$(home_component_for com.google.android.apps.tv.launcherx)"
  if [ -n "$stock" ]; then
    run_sh cmd package set-home-activity --user 0 "$stock" || run_sh cmd package set-home-activity "$stock" || true
    ok "HOME -> $stock"
  elif [ "$DRY_RUN" = 1 ]; then
    note "[dry-run] would set HOME back to com.google.android.apps.tv.launcherx"
  else
    warn "Stock launcher has no home activity, so pressing Home will ask which launcher to use."
  fi
fi

if [ "$DO_PACKAGES" = 1 ]; then
  if [ -n "$FROM" ]; then
    info "Restoring packages from backup"
    while read -r pkg; do
      if [ -n "$pkg" ] && ! has_pkg "$pkg"; then bring_back "$pkg"; fi
    done < "$FROM/packages-installed.txt"
    while read -r pkg; do
      if [ -n "$pkg" ] && in_lines "$pkg" "$DISABLED"; then bring_back "$pkg"; fi
    done < "$FROM/packages-enabled.txt"
  else
    info "Restoring packages from the lists"
    for list in ads-recommendations telemetry bloat-apps; do
      for pkg in $(read_list "$PKG_DIR/$list.txt"); do bring_back "$pkg"; done
    done
  fi
fi

if [ "$DO_PRIVACY" = 1 ]; then
  info "Giving microphone access back"
  for pkg in $MIC_PKGS; do
    has_pkg "$pkg" || continue
    run_sh appops set "$pkg" RECORD_AUDIO allow || true
    run_sh pm grant "$pkg" android.permission.RECORD_AUDIO || true
    ok "$pkg"
  done

  info "Resetting settings"
  if [ -n "$FROM" ] && [ -f "$FROM/settings.txt" ]; then
    while read -r ns key val; do
      [ -n "$key" ] || continue
      if [ "$val" = "null" ] || [ -z "$val" ]; then
        run_sh settings delete "$ns" "$key" || true; ok "$ns/$key (cleared)"
      else
        run_sh settings put "$ns" "$key" "$val" || true; ok "$ns/$key = $val"
      fi
    done < "$FROM/settings.txt"
  else
    run_sh settings put global private_dns_mode opportunistic || true
    run_sh settings delete global private_dns_specifier || true
    run_sh settings put global wifi_scan_always_enabled 1 || true
    run_sh settings put global ble_scan_always_enabled 1 || true
    run_sh settings delete global send_action_app_error || true
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
      run_sh settings put global "$k" 1 || true
    done
    ok "DNS automatic, scanning on, animations 1x"
  fi
  run_sh cmd location set-location-enabled true || true
fi

info "Restore finished. Reboot the TV to make sure everything comes back cleanly: adb reboot"
[ "$DRY_RUN" = 1 ] && note "(dry run, nothing was changed)"
exit 0
