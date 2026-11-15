#!/usr/bin/env bash
# Connect to the onn box over Wi-Fi ADB.
#
#   scripts/00-connect.sh 192.168.1.50            # connects to :5555
#   scripts/00-connect.sh 192.168.1.50:41234      # port shown under "Wireless debugging"
#   scripts/00-connect.sh pair 192.168.1.50:37123 # one-time pairing (asks for the 6-digit code)
source "$(dirname "$0")/../lib/common.sh"

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

MODE="connect"; TARGET=""
while [ $# -gt 0 ]; do
  if handle_common_flag "$1"; then shift; continue; fi
  case "$1" in
    pair) MODE="pair" ;;
    -*)   die "Unknown option: $1" ;;
    *)    TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { usage; exit 1; }
require_adb

if [ "$MODE" = "pair" ]; then
  info "Pairing with $TARGET. On the TV: Settings > System > Developer options >"
  note "Wireless debugging > Pair device with pairing code. Type that code below."
  "$ADB" pair "$TARGET"
  ok "Paired. Now connect using the IP:port shown on the main Wireless debugging screen:"
  note "scripts/00-connect.sh <ip:port>"
  exit 0
fi

case "$TARGET" in *:*) ;; *) TARGET="$TARGET:5555" ;; esac
info "Connecting to $TARGET ..."
out="$("$ADB" connect "$TARGET" 2>&1 | tr -d '\r')"
note "$out"
case "$out" in
  *"connected to"*) ;;
  *) die "Couldn't connect. Check that:
  - the TV and this computer are on the same network
  - Developer options > USB debugging is ON (enables :5555 on many builds), or
  - Developer options > Wireless debugging is ON and you use the port it shows
    (pair first: scripts/00-connect.sh pair <ip:pairing-port>)" ;;
esac
export ANDROID_SERIAL="$TARGET"

info "Waiting for you to accept the debugging prompt on the TV (tick 'Always allow')..."
for _ in $(seq 1 60); do
  state="$("$ADB" -s "$TARGET" get-state 2>/dev/null | tr -d '\r' || true)"
  [ "$state" = "device" ] && break
  sleep 1
done
[ "${state:-}" = "device" ] || die "Not authorized after 60s. Accept the prompt on the TV and run this again."

require_device
ok "Ready. Next: ./debloat-all.sh --dry-run   (to preview), then ./debloat-all.sh"
