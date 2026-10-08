#!/bin/sh
# Host-side test. Mocks Android commands and checks the boot script.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/state" "$TMP/trim-a" "$TMP/trim-b"
LOG="$TMP/mock.log"
PM_STATE="$TMP/pm-disabled"
: > "$LOG"
: > "$PM_STATE"

cat > "$TMP/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in
  ro.product.device) printf '%s\n' "${MOCK_DEVICE-gta4xlwifi}" ;;
  ro.product.vendor.device) printf '%s\n' "${MOCK_VENDOR_DEVICE-}" ;;
  ro.product.system.device) printf '%s\n' "" ;;
  ro.product.model) printf '%s\n' "${MOCK_MODEL-SM-P610}" ;;
  ro.product.vendor.model) printf '%s\n' "" ;;
  ro.lineage.version) printf '%s\n' "${MOCK_LINEAGE-23.2-20261001-NIGHTLY-gta4xlwifi}" ;;
  sys.boot_completed) printf '%s\n' "1" ;;
  *) printf '%s\n' "" ;;
esac
EOF

cat > "$TMP/bin/settings" <<'EOF'
#!/bin/sh
printf 'settings %s\n' "$*" >> "$P610_MOCK_LOG"
exit 0
EOF

cat > "$TMP/bin/pm" <<'EOF'
#!/bin/sh
printf 'pm %s\n' "$*" >> "$P610_MOCK_LOG"
sub=$1
shift
case "$sub" in
  path)
    pkg=$1
    case "$pkg" in
      com.android.traceur|com.android.egg|com.android.stk|org.lineageos.jelly|org.lineageos.twelve|org.lineageos.etar|org.lineageos.recorder|com.android.calculator2|com.android.printspooler|com.android.wallpaper.livepicker|com.android.systemui|com.android.settings)
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  list)
    if [ -f "$P610_MOCK_PM_STATE" ]; then
      while read -r pkg; do
        [ -n "$pkg" ] && printf 'package:%s\n' "$pkg"
      done < "$P610_MOCK_PM_STATE"
    fi
    exit 0
    ;;
  disable-user)
    prev=
    for a in "$@"; do prev=$a; done
    printf '%s\n' "$prev" >> "$P610_MOCK_PM_STATE"
    exit 0
    ;;
  enable)
    prev=
    for a in "$@"; do prev=$a; done
    if [ -f "$P610_MOCK_PM_STATE" ]; then
      grep -vx "$prev" "$P610_MOCK_PM_STATE" > "$P610_MOCK_PM_STATE.tmp" || true
      mv "$P610_MOCK_PM_STATE.tmp" "$P610_MOCK_PM_STATE"
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

cat > "$TMP/bin/cmd" <<'EOF'
#!/bin/sh
printf 'cmd %s\n' "$*" >> "$P610_MOCK_LOG"
exit 0
EOF

cat > "$TMP/bin/fstrim" <<'EOF'
#!/bin/sh
printf 'fstrim %s\n' "$*" >> "$P610_MOCK_LOG"
exit 0
EOF

chmod 755 "$TMP/bin/"*

export PATH="$TMP/bin:$PATH"
export P610_MOCK_LOG="$LOG"
export P610_MOCK_PM_STATE="$PM_STATE"
export P610_STATE_DIR="$TMP/state"
export P610_SKIP_BOOT_WAIT=1
export P610_TRIM_MOUNTS="$TMP/trim-a $TMP/trim-b"

fail=0
ok() { printf 'ok  %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

assert_contains() {
  if grep -q -- "$2" "$1"; then
    ok "$3"
  else
    bad "$3"
  fi
}

assert_not_contains() {
  if grep -q -- "$2" "$1"; then
    bad "$3"
  else
    ok "$3"
  fi
}

sh -n "$ROOT/apply.sh"
sh -n "$ROOT/customize.sh"
sh -n "$ROOT/service.sh"
sh -n "$ROOT/uninstall.sh"
ok "shell syntax"

sh "$ROOT/apply.sh"
assert_contains "$LOG" "settings put global window_animation_scale 0.5" "animation 0.5"
assert_contains "$LOG" "settings put global transition_animation_scale 0.5" "transition 0.5"
assert_contains "$LOG" "settings put global animator_duration_scale 0.5" "animator 0.5"
assert_contains "$LOG" "settings put global disable_window_blurs 1" "blur off"
assert_contains "$LOG" "settings put global wifi_scan_always_enabled 0" "wifi scan off"
assert_contains "$LOG" "pm disable-user --user 0 com.android.traceur" "traceur disabled"
assert_contains "$LOG" "pm disable-user --user 0 com.android.egg" "easter egg disabled"
assert_contains "$LOG" "pm disable-user --user 0 com.android.stk" "stk disabled"
assert_not_contains "$LOG" "disable-user --user 0 org.lineageos.jelly" "jelly left alone"
assert_not_contains "$LOG" "disable-user --user 0 org.lineageos.aperture" "camera not touched"
assert_contains "$LOG" "cmd package bg-dexopt-job" "dexopt once"
assert_contains "$LOG" "fstrim -v $TMP/trim-a" "fstrim data"
grep -qx "com.android.traceur" "$TMP/state/disabled.list" || bad "traceur missing from list"
grep -qx "com.android.egg" "$TMP/state/disabled.list" || bad "egg missing from list"
grep -qx "com.android.stk" "$TMP/state/disabled.list" || bad "stk missing from list"
ok "disabled.list has the three defaults"
_n=$(grep -c . "$TMP/state/disabled.list" || true)
if [ "$_n" = "3" ]; then ok "exactly three packages"; else bad "disabled.list count is $_n"; fi

: > "$LOG"
sh "$ROOT/apply.sh"
assert_not_contains "$LOG" "pm disable-user" "second boot does not disable again"
assert_not_contains "$LOG" "cmd package bg-dexopt-job" "dexopt not repeated"
assert_contains "$TMP/state/last.log" "fstrim not due" "fstrim weekly gate"

cat > "$TMP/state/config.prop" <<'EOF'
ANIMATION_SCALE=9
DISABLE_WINDOW_BLUR=0
DISABLE_WIFI_SCAN_ALWAYS=0
WEEKLY_FSTRIM=0
DEXOPT_ONCE=0
DISABLE_TRACEUR=0
DISABLE_EASTER_EGG=0
DISABLE_SIM_TOOLKIT=0
DISABLE_JELLY=1
EXTRA_DISABLE=com.android.systemui,com.android.settings,not a package,org.lineageos.jelly
EOF
: > "$LOG"
sh "$ROOT/apply.sh"
assert_contains "$LOG" "settings put global window_animation_scale 0.5" "bad scale falls back to 0.5"
assert_contains "$LOG" "settings put global disable_window_blurs 0" "blur restored when off"
assert_contains "$LOG" "settings put global wifi_scan_always_enabled 1" "wifi scan restored when off"
assert_contains "$LOG" "pm enable --user 0 com.android.traceur" "traceur re-enabled"
assert_contains "$LOG" "pm disable-user --user 0 org.lineageos.jelly" "jelly opt-in"
assert_contains "$TMP/state/last.log" "refusing protected package com.android.systemui" "systemui refused"
assert_contains "$TMP/state/last.log" "refusing protected package com.android.settings" "settings refused"
assert_not_contains "$LOG" "disable-user --user 0 com.android.systemui" "systemui not disabled"
if grep -qx "com.android.traceur" "$TMP/state/disabled.list"; then
  bad "traceur still owned after toggle off"
else
  ok "traceur dropped from disabled.list"
fi

MOCK_DEVICE=gta4xl
MOCK_MODEL=SM-P615
export MOCK_DEVICE MOCK_MODEL
: > "$LOG"
sh "$ROOT/apply.sh"
assert_contains "$TMP/state/last.log" "refusing to run: not SM-P610" "lte model refused"
assert_not_contains "$LOG" "settings put" "lte model changes nothing"
unset MOCK_DEVICE MOCK_MODEL

MOCK_DEVICE=sailfish
MOCK_MODEL="Pixel"
export MOCK_DEVICE MOCK_MODEL
sh "$ROOT/apply.sh"
assert_contains "$TMP/state/last.log" "refusing to run: not SM-P610" "random device refused"
unset MOCK_DEVICE MOCK_MODEL

: > "$TMP/state/ALLOW_OTHER_DEVICE"
: > "$LOG"
MOCK_DEVICE=sailfish
MOCK_MODEL=Pixel
export MOCK_DEVICE MOCK_MODEL
sh "$ROOT/apply.sh"
assert_contains "$LOG" "settings put global window_animation_scale 0.5" "override file allows other devices"
rm -f "$TMP/state/ALLOW_OTHER_DEVICE"
unset MOCK_DEVICE MOCK_MODEL

sh "$ROOT/apply.sh" restore
assert_contains "$LOG" "pm enable --user 0 org.lineageos.jelly" "restore enables what we disabled"
assert_contains "$LOG" "settings put global window_animation_scale 1" "restore animation 1"
assert_contains "$LOG" "settings put global disable_window_blurs 0" "restore blur"
assert_contains "$LOG" "settings put global wifi_scan_always_enabled 1" "restore wifi scan"
if [ -s "$TMP/state/disabled.list" ]; then
  bad "disabled.list not cleared"
else
  ok "disabled.list cleared"
fi

python3 "$ROOT/build-zip.py" >/dev/null
cp "$ROOT/dist/p610-lean-v1.0.0.zip" "$TMP/a.zip"
python3 "$ROOT/build-zip.py" >/dev/null
if cmp -s "$TMP/a.zip" "$ROOT/dist/p610-lean-v1.0.0.zip"; then
  ok "zip is reproducible"
else
  bad "zip is not reproducible"
fi

python3 - <<PY
import zipfile
z = zipfile.ZipFile("$ROOT/dist/p610-lean-v1.0.0.zip")
names = z.namelist()
need = ["module.prop", "customize.sh", "apply.sh", "META-INF/com/google/android/update-binary", "META-INF/com/google/android/updater-script"]
missing = [n for n in need if n not in names]
if missing:
    raise SystemExit("zip missing " + ",".join(missing))
script = z.read("META-INF/com/google/android/updater-script")
if script.strip() != b"#MAGISK":
    raise SystemExit("updater-script is not #MAGISK")
print("ok  zip layout")
PY

if [ "$fail" -ne 0 ]; then
  printf '\n%d failure(s)\n' "$fail"
  exit 1
fi
printf '\nall checks passed\n'
