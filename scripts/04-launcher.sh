#!/usr/bin/env bash
# Make Projectivy Launcher the home screen (it opens on boot), then disable the
# ad-filled stock Google TV launcher. The stock launcher is only disabled once
# Projectivy is confirmed as the default home, so the box can't end up on a
# black screen.
#
#   --apk FILE      install Projectivy from a local APK instead of the Play Store
#   --keep-stock    set Projectivy as home but leave the stock launcher enabled
#   -n, --dry-run   show what would happen
#   -y, --yes       don't ask for confirmation
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

APK=""; KEEP_STOCK=0
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    --apk)        [ $# -ge 2 ] || die "--apk needs a file"; APK="$2"; shift ;;
    --keep-stock) KEEP_STOCK=1 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

require_device

if [ -z "$(latest_backup)" ] && [ "$DRY_RUN" != 1 ]; then
  info "No backup yet. Making one first."
  "$(dirname "$0")/01-backup.sh"
fi

# 1. Install Projectivy
info "Step 1/4: Projectivy Launcher"
if has_pkg "$PROJECTIVY_PKG"; then
  ok "already installed"
elif [ -n "$APK" ]; then
  [ -f "$APK" ] || die "APK not found: $APK"
  run_adb install "$APK"
  refresh_pkgs
else
  note "Opening its Play Store page on the TV. Select 'Install' with the remote."
  run_sh am start -a android.intent.action.VIEW -d "market://details?id=$PROJECTIVY_PKG" || true
  if [ "$DRY_RUN" != 1 ]; then
    for _ in $(seq 1 10); do
      pause_for_user "Press Enter here once it has finished installing on the TV..."
      refresh_pkgs
      has_pkg "$PROJECTIVY_PKG" && break
      warn "Not installed yet."
    done
  fi
fi
if [ "$DRY_RUN" != 1 ]; then
  has_pkg "$PROJECTIVY_PKG" || die "Projectivy isn't installed. Nothing was changed."
  ok "installed"
fi

# 2. Set it as the default home
info "Step 2/4: Make Projectivy the default home app"
comp="$(home_component_for "$PROJECTIVY_PKG")"
if [ -z "$comp" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    comp="$PROJECTIVY_PKG/<home-activity>"
  else
    die "Couldn't find Projectivy's home activity. Open Projectivy once on the TV, then re-run."
  fi
fi
run_sh am start -n "$comp" || true   # first launch lets it finish its own setup
run_sh cmd package set-home-activity --user 0 "$comp" || run_sh cmd package set-home-activity "$comp" \
  || die "Couldn't set the default home app: $RUN_OUT"

# 3. Verify before touching the stock launcher
info "Step 3/4: Verify"
if [ "$DRY_RUN" = 1 ]; then
  note "[dry-run] would check that HOME resolves to $PROJECTIVY_PKG"
else
  home="$(current_home)"
  case "$home" in
    "$PROJECTIVY_PKG"/*) ok "HOME -> $home" ;;
    *) die "HOME still resolves to '$home', not Projectivy. Stock launcher left untouched.
  Try: in Projectivy's settings turn on 'Override current launcher', then re-run." ;;
  esac
fi

# 4. Disable stock launcher
info "Step 4/4: Disable the stock Google TV launcher"
if [ "$KEEP_STOCK" = 1 ]; then
  note "--keep-stock given, leaving it enabled"
else
  for pkg in $(read_list "$PKG_DIR/stock-launcher.txt"); do
    has_pkg "$pkg" || { note "$pkg (not installed)"; continue; }
    if run_sh pm disable-user --user 0 "$pkg"; then ok "$pkg disabled"; else warn "$pkg: $RUN_OUT"; fi
  done
  if [ "$DRY_RUN" != 1 ]; then
    home="$(current_home)"
    case "$home" in
      "$PROJECTIVY_PKG"/*) ok "HOME -> $home" ;;
      *) warn "HOME resolves to '$home' after disabling. Re-enabling the stock launcher to be safe."
         "$(dirname "$0")/restore.sh" --launcher --yes
         exit 1 ;;
    esac
  fi
fi
run_sh input keyevent KEYCODE_HOME || true

info "Done. On the TV, in Projectivy:"
note "Projectivy settings > 'Override current launcher' -> ON (backup in case an update resets HOME)"
note "Add a 'Settings' shortcut: add the Android 'Settings' app to a row"
note "Search: add the Google search shortcut (typed search; mic is blocked if you ran 03-privacy.sh)"
if [ "$DRY_RUN" != 1 ] && confirm "Reboot now to check it opens Projectivy on boot?"; then
  run_adb reboot
  ok "Rebooting. Reconnect afterwards with scripts/00-connect.sh <tv-ip>"
fi
exit 0
