#!/usr/bin/env bash
# Runs the toolkit against tests/fake-adb (no TV needed).  Usage: tests/run-tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
export ADB="$HERE/fake-adb" ASSUME_YES=1
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export LOG_FILE="$WORK/test.log"
pass=0; fail=0

reset_box() {
  export FAKE_STATE="$WORK/box"; rm -rf "$FAKE_STATE" "$ROOT/backups.test"; mkdir -p "$FAKE_STATE"
  cat > "$FAKE_STATE/installed.txt" <<P
android
com.android.tv.settings
com.android.vending
com.google.android.gms
com.google.android.katniss
com.google.android.apps.mediashell
com.google.android.apps.tv.launcherx
com.google.android.tungsten.setupwraith
com.google.android.tvrecommendations
com.google.android.feedback
com.google.android.adservices.api
com.google.android.youtube.tv
com.netflix.ninja
com.google.android.tv.remote.service
P
  cp "$FAKE_STATE/installed.txt" "$FAKE_STATE/all.txt"
  echo com.spocky.projengmenu >> "$FAKE_STATE/all.txt"   # "available in Play Store"
  : > "$FAKE_STATE/disabled.txt"; : > "$FAKE_STATE/calls.log"
  echo "global private_dns_mode opportunistic" > "$FAKE_STATE/settings.txt"
  echo "com.google.android.apps.tv.launcherx/.home.HomeActivity" > "$FAKE_STATE/home.txt"
  unset FAKE_HOME_FAIL FAKE_UNINSTALL_FAIL
  rm -rf "$ROOT/backups"; [ -d "$WORK/real-backups" ] || true
}
check() { # description, command...
  local d="$1"; shift
  if "$@"; then echo "  PASS $d"; pass=$((pass+1)); else echo "  FAIL $d"; fail=$((fail+1)); fi
}
installed() { grep -qxF "$1" "$FAKE_STATE/installed.txt"; }
disabled()  { grep -qxF "$1" "$FAKE_STATE/disabled.txt"; }
not()       { ! "$@"; }
mutations() { grep -E '^shell (pm (uninstall|disable-user|enable|grant|revoke)|settings put|cmd package (install-existing|set-home)|appops set)' "$FAKE_STATE/calls.log" | grep -c . || true; }

# Don't clobber a real user's backups folder.
if [ -d "$ROOT/backups" ]; then mv "$ROOT/backups" "$WORK/real-backups"; trap 'rm -rf "$ROOT/backups"; mv "$WORK/real-backups" "$ROOT/backups"; rm -rf "$WORK"' EXIT; fi

echo "dry run changes nothing"
reset_box
"$ROOT/debloat-all.sh" --dry-run > "$WORK/out" 2>&1
check "exit 0" test $? -eq 0
check "no mutating adb calls" test "$(mutations)" -eq 0
check "youtube still installed" installed com.google.android.youtube.tv
check "dry run shows uninstall" grep -q 'dry-run] adb shell pm uninstall --user 0 com.google.android.youtube.tv' "$WORK/out"

echo "full run"
reset_box
touch "$WORK/projectivy.apk"
"$ROOT/debloat-all.sh" --apk "$WORK/projectivy.apk" > "$WORK/out" 2>&1; rc=$?
[ $rc -eq 0 ] || cat "$WORK/out"
check "exit 0" test $rc -eq 0
check "backup created" test -f "$(find "$ROOT/backups" -name packages-installed.txt | head -1)"
check "tvrecommendations removed" not installed com.google.android.tvrecommendations
check "adservices removed" not installed com.google.android.adservices.api
check "youtube removed" not installed com.google.android.youtube.tv
check "netflix removed" not installed com.netflix.ninja
for p in com.google.android.katniss com.google.android.apps.mediashell com.android.vending \
         com.google.android.gms com.android.tv.settings com.google.android.tv.remote.service; do
  check "kept $p" installed "$p"; check "not disabled $p" not disabled "$p"
done
check "projectivy installed" installed com.spocky.projengmenu
check "projectivy is home" grep -q '^com.spocky.projengmenu/' "$FAKE_STATE/home.txt"
check "stock launcher disabled" disabled com.google.android.apps.tv.launcherx
check "setupwraith disabled" disabled com.google.android.tungsten.setupwraith
check "mic blocked for katniss" grep -q 'appops set com.google.android.katniss RECORD_AUDIO ignore' "$FAKE_STATE/calls.log"
check "private dns hostname" grep -q 'global private_dns_mode hostname' "$FAKE_STATE/settings.txt"
check "private dns host" grep -q 'global private_dns_specifier dns.adguard-dns.com' "$FAKE_STATE/settings.txt"

echo "restore from backup undoes everything"
"$ROOT/scripts/restore.sh" --from-backup > "$WORK/out" 2>&1; rc=$?
check "exit 0" test $rc -eq 0
check "youtube back" installed com.google.android.youtube.tv
check "tvrecommendations back" installed com.google.android.tvrecommendations
check "stock launcher enabled" not disabled com.google.android.apps.tv.launcherx
check "setupwraith enabled" not disabled com.google.android.tungsten.setupwraith
check "stock is home" grep -q '^com.google.android.apps.tv.launcherx/' "$FAKE_STATE/home.txt"
check "dns restored" grep -qx 'global private_dns_mode opportunistic' "$FAKE_STATE/settings.txt"
check "scan setting cleared (was unset)" not grep -q wifi_scan_always_enabled "$FAKE_STATE/settings.txt"
check "dns host cleared" not grep -q private_dns_specifier "$FAKE_STATE/settings.txt"
check "mic allowed" grep -q 'appops set com.google.android.katniss RECORD_AUDIO allow' "$FAKE_STATE/calls.log"

echo "launcher aborts if Projectivy can't become home"
reset_box
echo com.spocky.projengmenu >> "$FAKE_STATE/installed.txt"
FAKE_HOME_FAIL=1 "$ROOT/scripts/04-launcher.sh" > "$WORK/out" 2>&1; rc=$?
check "non-zero exit" test $rc -ne 0
check "stock launcher untouched" not disabled com.google.android.apps.tv.launcherx
check "setupwraith untouched" not disabled com.google.android.tungsten.setupwraith

echo "NEVER-REMOVE guard"
reset_box
printf 'com.google.android.katniss\ncom.android.vending\n' > "$ROOT/packages/zz-test.txt"
"$ROOT/scripts/02-debloat.sh" --list zz-test > "$WORK/out" 2>&1
rm -f "$ROOT/packages/zz-test.txt"
check "katniss kept" installed com.google.android.katniss
check "play store kept" installed com.android.vending
check "warned" grep -q 'NEVER-REMOVE' "$WORK/out"

echo "falls back to disable when uninstall fails"
reset_box
FAKE_UNINSTALL_FAIL=com.netflix.ninja "$ROOT/scripts/02-debloat.sh" > "$WORK/out" 2>&1
check "netflix disabled instead" disabled com.netflix.ninja

rm -rf "$ROOT/backups"
echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
