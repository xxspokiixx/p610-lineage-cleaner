#!/bin/sh
# Install official Magisk on a Galaxy Tab S6 Lite Wi-Fi (SM-P610) if it is
# not already installed, then install the P610 Lean module.
#
# Magisk's own recovery installer, shipped inside the official APK, patches
# the boot image that is already on this tablet. This script never downloads
# a boot image and never writes vbmeta, recovery, or super.
#
# Needs a computer with adb and python3, USB debugging on, and the tablet
# booted into LineageOS. You must tap "Yes" when Lineage recovery says the
# signature does not match. That prompt is expected.

set -u

ADB=${P610_ADB:-adb}
YES=0
CHECK_ONLY=0
NO_MODULE=0
APK=${P610_MAGISK_APK:-}
MODULE_ZIP=${P610_MODULE_ZIP:-}

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PARSER="$HERE/magisk_release.py"
WORK="$HERE/../work"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
usage: root-magisk.sh [--check] [--yes] [--apk FILE] [--module ZIP] [--no-module]

  --check      Print whether this SM-P610 already has Magisk. Change nothing.
  --yes        Install official Magisk when it is missing. Reboots to recovery.
  --apk FILE   Use this already-downloaded official Magisk APK. Skip the download.
  --module ZIP Install this Lean zip after Magisk is present.
  --no-module  Do not install the Lean zip.

Without --module, dist/p610-lean-v1.0.0.zip is used when it exists.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --check) CHECK_ONLY=1 ;;
    --no-module) NO_MODULE=1 ;;
    --apk)
      shift
      APK=${1:-}
      [ -n "$APK" ] || die "--apk needs a path"
      ;;
    --module)
      shift
      MODULE_ZIP=${1:-}
      [ -n "$MODULE_ZIP" ] || die "--module needs a path"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

if [ ! -x "$ADB" ] && ! command -v "$ADB" >/dev/null 2>&1; then
  die "adb was not found. Install platform-tools and connect the tablet."
fi

adb_text() {
  "$ADB" "$@" | tr -d '\r'
}

device_lines() {
  "$ADB" devices | tr -d '\r' | awk 'NR>1 && $1 !~ /^$/ { print $1, $2 }'
}

require_one_tablet() {
  _n=$(device_lines | awk '$2=="device" || $2=="recovery" || $2=="sideload" { n++ } END { print n+0 }')
  if device_lines | awk '$2=="unauthorized" { found=1 } END { exit !found }'; then
    die "USB debugging is not allowed yet. Unlock the tablet and tap Allow."
  fi
  if [ "$_n" -eq 0 ]; then
    die "No tablet in adb. Plug it in, boot Lineage, and enable USB debugging."
  fi
  if [ "$_n" -gt 1 ]; then
    die "More than one adb device is connected. Unplug the others."
  fi
}

prop() {
  adb_text shell getprop "$1" | head -n 1
}

require_p610() {
  _d=$(prop ro.product.device)
  _m=$(prop ro.product.model)
  printf '%s\n' "Device: ${_d:-unknown}  Model: ${_m:-unknown}"
  if [ "$_d" != "gta4xlwifi" ]; then
    die "Refusing: this is only for the Wi-Fi Tab S6 Lite (gta4xlwifi), not ${_d:-unknown}."
  fi
  case "${_m:-}" in
    *SM-P610*) ;;
    *) die "Refusing: model ${_m:-unknown} is not SM-P610." ;;
  esac
}

magisk_version() {
  _v=$(adb_text shell magisk -v 2>/dev/null | head -n 1 || true)
  case "$_v" in
    [0-9]*)
      printf '%s\n' "$_v"
      return 0
      ;;
  esac
  return 1
}

foreign_root() {
  _hit=$(adb_text shell "command -v ksud || command -v apd || true" | head -n 1 || true)
  case "$_hit" in
    "" | *not\ found* | *inaccessible*) return 1 ;;
    /*) return 0 ;;
  esac
  return 1
}

verify_apk() {
  _apk=$1
  [ -f "$_apk" ] || die "Magisk apk not found: $_apk"
  unzip -t "$_apk" >/dev/null || die "Magisk file is not a valid zip: $_apk"
  _list=$(unzip -l "$_apk")
  printf '%s\n' "$_list" | grep -q 'lib/arm64-v8a/libmagiskboot.so' || die "Not an official Magisk apk (no magiskboot)."
  printf '%s\n' "$_list" | grep -q 'META-INF/com/google/android/update-binary' || die "Not a flashable Magisk package."
  printf '%s\n' "$_list" | grep -q 'assets/util_functions.sh' || die "Magisk apk is missing util_functions.sh."
  unzip -p "$_apk" assets/util_functions.sh | grep -q "MAGISK_VER=" || die "Magisk apk has no MAGISK_VER."
  unzip -p "$_apk" META-INF/com/google/android/updater-script | grep -q "#MAGISK" || die "Magisk updater-script is not the Magisk installer."
  unzip -p "$_apk" META-INF/com/google/android/update-binary | grep -q "libbusybox.so" || die "Magisk update-binary is not the official installer."
  printf '%s\n' "Magisk apk checks out: $_apk"
}

download_magisk() {
  [ -f "$PARSER" ] || die "Missing $PARSER"
  command -v python3 >/dev/null 2>&1 || die "python3 is required to read the Magisk release."
  command -v curl >/dev/null 2>&1 || die "curl is required to download Magisk."
  mkdir -p "$WORK"
  _json=$(curl -fsSL --retry 3 https://api.github.com/repos/topjohnwu/Magisk/releases/latest) || die "Could not read the official Magisk release list."
  _parsed=$(printf '%s' "$_json" | python3 "$PARSER") || die "Official Magisk release was rejected."
  _url=$(printf '%s\n' "$_parsed" | sed -n '1p')
  _size=$(printf '%s\n' "$_parsed" | sed -n '2p')
  _tag=$(printf '%s\n' "$_parsed" | sed -n '3p')
  case "$_url" in
    https://github.com/topjohnwu/Magisk/releases/download/v*/Magisk-v*.apk) ;;
    *) die "Refusing download URL." ;;
  esac
  _out="$WORK/Magisk-${_tag}.apk"
  printf '%s\n' "Downloading $_url"
  curl -fL --retry 3 -o "$_out.partial" "$_url" || die "Magisk download failed."
  mv "$_out.partial" "$_out"
  _got=$(wc -c < "$_out" | tr -d ' ')
  [ "$_got" = "$_size" ] || die "Download size ${_got} does not match the release size ${_size}."
  printf '%s\n' "$_out"
}

default_module() {
  if [ -n "$MODULE_ZIP" ]; then
    [ -f "$MODULE_ZIP" ] || die "Module zip not found: $MODULE_ZIP"
    printf '%s\n' "$MODULE_ZIP"
    return 0
  fi
  _cand="$HERE/../dist/p610-lean-v1.0.0.zip"
  if [ -f "$_cand" ]; then
    printf '%s\n' "$_cand"
    return 0
  fi
  return 1
}

install_module() {
  if [ "$NO_MODULE" -eq 1 ]; then
    printf '%s\n' "Skipping the Lean module."
    return 0
  fi
  _zip=$(default_module) || {
    printf '%s\n' "Magisk is installed. No Lean zip was found next to this script."
    printf '%s\n' "Install dist/p610-lean-v1.0.0.zip from Magisk, or re-run with --module."
    return 0
  }
  printf '%s\n' "Installing Lean module: $_zip"
  printf '%s\n' "If the tablet asks, grant root to Shell."
  "$ADB" push "$_zip" /data/local/tmp/p610-lean.zip >/dev/null || die "Could not copy the module to the tablet."
  "$ADB" shell su -c "magisk --install-module /data/local/tmp/p610-lean.zip" || die "Magisk did not install the module. Grant Shell when asked, then run this again."
  printf '%s\n' "Rebooting so the module can apply."
  "$ADB" reboot
}

wait_for_sideload() {
  printf '%s\n' "On the tablet: Apply update → Apply from ADB."
  printf '%s\n' "When recovery says signature verification failed, tap Yes. Magisk is not signed by Lineage."
  _i=0
  while [ "$_i" -lt 90 ]; do
    if device_lines | awk '$2=="sideload" { found=1 } END { exit !found }'; then
      return 0
    fi
    _i=$((_i + 1))
    if [ $((_i % 10)) -eq 0 ]; then
      printf '%s\n' "Still waiting for ADB sideload mode..."
    fi
    sleep 2
  done
  die "Sideload mode did not start. On the tablet open Apply update, then Apply from ADB, and run this script again."
}

wait_for_android() {
  printf '%s\n' "Waiting for Android to finish booting."
  "$ADB" wait-for-device
  _i=0
  while [ "$_i" -lt 90 ]; do
    if [ "$(prop sys.boot_completed)" = "1" ]; then
      sleep 5
      return 0
    fi
    _i=$((_i + 1))
    sleep 2
  done
  die "Android did not finish booting. If the tablet is stuck on the logo, reboot to recovery (Volume Up + Power while plugged into the PC) and sideload the same LineageOS zip you already installed. That restores boot without using a foreign boot image."
}

require_one_tablet
require_p610

if magisk_version >/tmp/p610-magisk-ver.$$ 2>/dev/null; then
  _ver=$(cat /tmp/p610-magisk-ver.$$)
  rm -f /tmp/p610-magisk-ver.$$
  printf '%s\n' "Magisk is already installed (${_ver})."
  if [ "$CHECK_ONLY" -eq 1 ]; then
    exit 0
  fi
  install_module
  exit 0
fi
rm -f /tmp/p610-magisk-ver.$$

if [ "$CHECK_ONLY" -eq 1 ]; then
  printf '%s\n' "Magisk is not installed."
  exit 0
fi

if foreign_root; then
  die "This tablet already has KernelSU or APatch. Install the Lean zip from that manager. Magisk will not be added on top."
fi

if [ "$YES" -ne 1 ]; then
  die "Magisk is not installed. Re-run with --yes to download official Magisk and sideload it in Lineage recovery. The boot image already on this tablet is what gets patched."
fi

if [ -n "$APK" ]; then
  verify_apk "$APK"
  _apk=$APK
else
  _apk=$(download_magisk)
  verify_apk "$_apk"
fi

if [ "${P610_STOP_BEFORE_REBOOT:-0}" = "1" ]; then
  printf '%s\n' "Stop requested before recovery. Nothing was flashed."
  exit 0
fi

mkdir -p "$WORK"
_side="$WORK/magisk-install.zip"
cp "$_apk" "$_side" || die "Could not prepare the sideload zip."
case "$_side" in
  *uninstall*) die "Internal name must not contain uninstall." ;;
esac

printf '%s\n' "Rebooting into Lineage recovery. The tablet will disconnect."
"$ADB" reboot recovery
sleep 3
wait_for_sideload
printf '%s\n' "Sideloading official Magisk. This patches the boot image on the tablet."
"$ADB" sideload "$_side" || die "Sideload failed. Boot was left to Magisk's installer. If the tablet still boots, run --check. If it loops on the logo, sideload your current LineageOS zip from recovery."

printf '%s\n' "If recovery is still open, choose Reboot system now."
wait_for_android

if ! magisk_version >/dev/null 2>&1; then
  printf '%s\n' "Magisk was flashed but the app is not on the home screen yet. Installing the app."
  "$ADB" install -r "$_apk" || die "Could not install the Magisk app. Copy the apk onto the tablet and install it, open it, and if it asks to reinstall, use Direct Install, then run this script again."
  printf '%s\n' "Open Magisk. If it asks to finish setup, use Direct Install and reboot. Then run this script again to install Lean."
  exit 0
fi

install_module
