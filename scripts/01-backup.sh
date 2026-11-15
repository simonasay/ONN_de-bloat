#!/usr/bin/env bash
# Save a snapshot of the box's packages and settings so restore.sh can undo
# everything. Read-only on the TV. Writes to backups/<timestamp>/.
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  handle_common_flag "$1" || die "Unknown option: $1"
  shift
done
require_device

dir="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dir"
info "Backing up to ${dir#"$ROOT_DIR"/}"

strip() { sed 's/^package://' | sort; }
adb_sh pm list packages      | strip > "$dir/packages-installed.txt"
adb_sh pm list packages -e   | strip > "$dir/packages-enabled.txt"
adb_sh pm list packages -d   | strip > "$dir/packages-disabled.txt"
adb_sh pm list packages -u   | strip > "$dir/packages-all.txt"
adb_sh pm list packages -s   | strip > "$dir/packages-system.txt"
adb_sh pm list packages -3   | strip > "$dir/packages-user-installed.txt"
current_home > "$dir/home.txt"

: > "$dir/settings.txt"
printf '%s\n' "$SETTINGS_KEYS" | while read -r ns key; do
  printf '%s %s %s\n' "$ns" "$key" "$(adb_sh settings get "$ns" "$key")" >> "$dir/settings.txt"
done

{
  for p in ro.product.brand ro.product.model ro.product.device ro.build.version.release \
           ro.build.version.sdk ro.build.fingerprint; do
    printf '%s=%s\n' "$p" "$(adb_sh getprop "$p")"
  done
} > "$dir/device.txt"

ok "$(wc -l < "$dir/packages-installed.txt" | tr -d ' ') packages installed, $(wc -l < "$dir/packages-disabled.txt" | tr -d ' ') disabled"
ok "Default home: $(cat "$dir/home.txt")"
note "Full package list: ${dir#"$ROOT_DIR"/}/packages-installed.txt"
