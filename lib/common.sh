#!/usr/bin/env bash
# Shared helpers for the onn 4K debloat scripts. Source this file; don't run it.
# Written for bash 3.2+ so it works with the stock bash on macOS.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/packages"
BACKUP_DIR="$ROOT_DIR/backups"
LOG_DIR="$ROOT_DIR/logs"

ADB="${ADB:-adb}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

PROJECTIVY_PKG="com.spocky.projengmenu"

# Settings this toolkit may change. backup saves them; restore puts them back.
SETTINGS_KEYS="global private_dns_mode
global private_dns_specifier
global send_action_app_error
global wifi_scan_always_enabled
global ble_scan_always_enabled
secure location_mode
global window_animation_scale
global transition_animation_scale
global animator_duration_scale"

# Apps whose microphone access gets cut (typing still works).
MIC_PKGS="com.google.android.katniss
com.google.android.googlequicksearchbox
com.google.android.apps.tv.launcherx
com.google.android.gms
com.google.android.apps.mediashell
com.google.android.inputmethod.latin
com.google.android.tvrecommendations"

mkdir -p "$LOG_DIR"
if [ -z "${LOG_FILE:-}" ]; then
  LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
fi
export LOG_FILE DRY_RUN ASSUME_YES

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_DIM=""; C_OFF=""
fi

_out() { # color, message
  local color="$1"; shift
  printf '%s%s%s\n' "$color" "$*" "$C_OFF"
  printf '%s\n' "$*" >> "$LOG_FILE"
}
info()  { _out "$C_BLU" "==> $*"; }
ok()    { _out "$C_GRN" "  ✓ $*"; }
warn()  { _out "$C_YLW" "  ! $*"; }
note()  { _out "$C_DIM" "    $*"; }
die()   { _out "$C_RED" "ERROR: $*" >&2; exit 1; }

# Handle flags every script understands. Returns 1 if the flag isn't one of them.
handle_common_flag() {
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) return 1 ;;
  esac
  export DRY_RUN ASSUME_YES
}

confirm() { # prompt
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  local ans=""
  if [ -r /dev/tty ]; then
    read -r -p "$1 [y/N] " ans < /dev/tty || true
  else
    read -r -p "$1 [y/N] " ans || true
  fi
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

pause_for_user() { # prompt
  if [ "$ASSUME_YES" = 1 ] || [ "$DRY_RUN" = 1 ]; then return 0; fi
  local _=""
  read -r -p "$1 " _ < /dev/tty || true
}

# Read-only adb shell call (always runs, even in dry-run). Strips CRs.
adb_sh() {
  "$ADB" shell "$@" 2>/dev/null | tr -d '\r'
}

# Mutating adb shell call. Honors --dry-run. Output lands in RUN_OUT.
RUN_OUT=""
run_sh() {
  RUN_OUT=""
  if [ "$DRY_RUN" = 1 ]; then
    _out "$C_DIM" "    [dry-run] adb shell $*"
    return 0
  fi
  printf '    $ adb shell %s\n' "$*" >> "$LOG_FILE"
  local rc=0
  RUN_OUT="$("$ADB" shell "$@" 2>&1 | tr -d '\r')" || rc=$?
  if [ -n "$RUN_OUT" ]; then printf '      %s\n' "$RUN_OUT" >> "$LOG_FILE"; fi
  if [ "$rc" -ne 0 ]; then return "$rc"; fi
  case "$RUN_OUT" in
    *Failure*|*Exception*|*"Unknown package"*|*"not found"*|*Error:*) return 1 ;;
  esac
  return 0
}

# Mutating local adb call (install, reboot...). Honors --dry-run.
run_adb() {
  if [ "$DRY_RUN" = 1 ]; then
    _out "$C_DIM" "    [dry-run] adb $*"
    return 0
  fi
  printf '    $ adb %s\n' "$*" >> "$LOG_FILE"
  "$ADB" "$@" 2>&1 | tee -a "$LOG_FILE"
}

require_adb() {
  command -v "$ADB" >/dev/null 2>&1 || die "adb not found.
  Mac:   brew install android-platform-tools
  Linux: sudo apt install adb   (or your distro's android-tools package)"
}

DEVICE_CHECKED="${DEVICE_CHECKED:-0}"
require_device() {
  require_adb
  local devices count
  devices="$("$ADB" devices 2>/dev/null | tr -d '\r' | awk 'NR>1 && NF>=2')"
  if printf '%s\n' "$devices" | grep -q 'unauthorized'; then
    die "The TV hasn't authorized this computer yet. Accept the 'Allow debugging?' prompt on the TV (tick 'Always allow'), then re-run."
  fi
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    [ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" = "device" ] || die "Device $ANDROID_SERIAL isn't connected. Run scripts/00-connect.sh first."
  else
    count="$(printf '%s\n' "$devices" | awk '$2=="device"' | grep -c . || true)"
    if [ "$count" -eq 0 ]; then die "No device connected. Run: scripts/00-connect.sh <tv-ip>"; fi
    if [ "$count" -gt 1 ]; then die "More than one device connected. Pick one: export ANDROID_SERIAL=<ip:port>"; fi
  fi

  if [ "$DEVICE_CHECKED" = 1 ]; then return 0; fi
  local brand model release sdk
  brand="$(adb_sh getprop ro.product.brand)"
  model="$(adb_sh getprop ro.product.model)"
  release="$(adb_sh getprop ro.build.version.release)"
  sdk="$(adb_sh getprop ro.build.version.sdk)"
  info "Connected: $brand $model (Android $release, SDK $sdk)"
  case "$(printf '%s %s' "$brand" "$model" | tr '[:upper:]' '[:lower:]')" in
    *onn*) ;;
    *) warn "This doesn't look like an onn device. The package lists target onn Google TV boxes."
       confirm "Continue anyway?" || exit 1 ;;
  esac
  DEVICE_CHECKED=1
  export DEVICE_CHECKED
}

# Installed-for-user package cache.
_PKG_CACHE=""
refresh_pkgs() {
  _PKG_CACHE="$(adb_sh pm list packages | sed 's/^package://')"
}
has_pkg() { # pkg
  if [ -z "$_PKG_CACHE" ]; then refresh_pkgs; fi
  case $'\n'"$_PKG_CACHE"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}
in_lines() { # needle, newline-separated haystack
  case $'\n'"$2"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print package names from a list file, ignoring comments and blanks.
read_list() { # file
  [ -f "$1" ] || die "Missing package list: $1"
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' || true
}

PROTECTED="$(read_list "$PKG_DIR/NEVER-REMOVE.txt")"
is_protected() { in_lines "$1" "$PROTECTED"; }

latest_backup() {
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1 || true
}

# Component that currently answers the HOME intent, e.g. com.foo/.Main
current_home() {
  adb_sh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
    | tail -1 | tr -d ' '
}

# First HOME activity component exposed by a package.
home_component_for() { # pkg
  adb_sh cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
    | grep -o "$1/[^ ]*" | head -1 || true
}
