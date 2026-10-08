#!/bin/sh
# Host-side tests for the Magisk bootstrap. No device, no download.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/adb.log"
: > "$LOG"

cat > "$TMP/adb" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$P610_MOCK_LOG"
case "$1" in
  devices)
    printf '%s\n' "List of devices attached"
    printf '%s\n' "SERIAL1 device"
    ;;
  shell)
    shift
    case "$*" in
      "getprop ro.product.device") printf '%s\n' "${MOCK_DEVICE:-gta4xlwifi}" ;;
      "getprop ro.product.model") printf '%s\n' "${MOCK_MODEL:-SM-P610}" ;;
      "getprop sys.boot_completed") printf '%s\n' "1" ;;
      "magisk -v")
        if [ -n "${MOCK_MAGISK:-}" ]; then
          printf '%s\n' "$MOCK_MAGISK"
          exit 0
        fi
        echo "inaccessible or not found" >&2
        exit 127
        ;;
      "command -v ksud || command -v apd || true")
        if [ "${MOCK_KSU:-0}" = "1" ]; then
          printf '%s\n' "/data/adb/ksu/bin/ksud"
        fi
        ;;
      "su -c magisk --install-module /data/local/tmp/p610-lean.zip")
        exit 0
        ;;
      *)
        printf 'unexpected shell: %s\n' "$*" >> "$P610_MOCK_LOG"
        exit 1
        ;;
    esac
    ;;
  push | reboot | sideload | wait-for-device | install)
    exit 0
    ;;
  *)
    printf 'unexpected adb: %s\n' "$1" >> "$P610_MOCK_LOG"
    exit 1
    ;;
esac
EOF
chmod 755 "$TMP/adb"

FIX="$TMP/fake-magisk.apk"
python3 - "$FIX" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path, "w") as z:
    z.writestr("lib/arm64-v8a/libmagiskboot.so", b"not-a-real-binary")
    z.writestr("assets/util_functions.sh", "MAGISK_VER='30.7'\nMAGISK_VER_CODE=30700\n")
    z.writestr("META-INF/com/google/android/update-binary", "#!/sbin/sh\nunzip libbusybox.so\n")
    z.writestr("META-INF/com/google/android/updater-script", "#MAGISK\n")
PY
printf 'nope\n' > "$TMP/not-an-apk"
printf 'zip\n' > "$TMP/lean.zip"

fail=0
ok() { printf 'ok  %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

run() {
  : > "$LOG"
  set +e
  OUT=$(P610_ADB="$TMP/adb" P610_MOCK_LOG="$LOG" sh "$ROOT/scripts/root-magisk.sh" "$@" 2>"$TMP/err")
  CODE=$?
  set -e
  ERR=$(cat "$TMP/err")
}

sh -n "$ROOT/scripts/root-magisk.sh"
python3 -m py_compile "$ROOT/scripts/magisk_release.py"
ok "syntax"

run --check
if [ "$CODE" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "Magisk is not installed"; then
  ok "check reports missing magisk"
else
  bad "check missing magisk code=$CODE out=$OUT err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "check rebooted"; else ok "check does not reboot"; fi

MOCK_DEVICE=gta4xl MOCK_MODEL=SM-P615
export MOCK_DEVICE MOCK_MODEL
run --yes --apk "$FIX"
if [ "$CODE" -ne 0 ] && printf '%s\n' "$ERR" | grep -q "Refusing"; then
  ok "lte tablet refused"
else
  bad "lte tablet not refused code=$CODE err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "wrong device rebooted"; else ok "wrong device does not reboot"; fi
unset MOCK_DEVICE MOCK_MODEL

run --module "$TMP/lean.zip"
if [ "$CODE" -ne 0 ] && printf '%s\n' "$ERR" | grep -q "Re-run with --yes"; then
  ok "missing magisk asks for --yes"
else
  bad "missing --yes prompt code=$CODE err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "prompt path rebooted"; else ok "prompt path does not reboot"; fi

MOCK_KSU=1
export MOCK_KSU
run --yes --apk "$FIX"
if [ "$CODE" -ne 0 ] && printf '%s\n' "$ERR" | grep -q "KernelSU or APatch"; then
  ok "other root is left alone"
else
  bad "other root not detected code=$CODE err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "ksu path rebooted"; else ok "ksu path does not reboot"; fi
unset MOCK_KSU

P610_STOP_BEFORE_REBOOT=1
export P610_STOP_BEFORE_REBOOT
run --yes --apk "$FIX" --no-module
if [ "$CODE" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "Magisk apk checks out" && printf '%s\n' "$OUT" | grep -q "Nothing was flashed"; then
  ok "official-looking apk verifies and stops before recovery"
else
  bad "verify stop code=$CODE out=$OUT err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "stop-before-reboot still rebooted"; else ok "nothing flashed"; fi
unset P610_STOP_BEFORE_REBOOT

run --yes --apk "$TMP/not-an-apk"
if [ "$CODE" -ne 0 ] && printf '%s\n' "$ERR" | grep -q "not a valid zip"; then
  ok "rejects a non-zip apk"
else
  bad "bad apk accepted code=$CODE err=$ERR"
fi
if grep -q "reboot" "$LOG"; then bad "bad apk rebooted"; else ok "bad apk does not reboot"; fi

MOCK_MAGISK=30.7
export MOCK_MAGISK
run --module "$TMP/lean.zip"
if [ "$CODE" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "already installed (30.7)"; then
  ok "existing magisk is reused"
else
  bad "existing magisk code=$CODE out=$OUT err=$ERR"
fi
if grep -q "su -c magisk --install-module /data/local/tmp/p610-lean.zip" "$LOG"; then
  ok "module installed through magisk"
else
  bad "module install was not requested"
fi
if grep -q "reboot recovery" "$LOG"; then bad "existing magisk sent to recovery"; else ok "no recovery reboot"; fi
unset MOCK_MAGISK

PARSER="$ROOT/scripts/magisk_release.py"
parse() {
  printf '%s' "$1" | python3 "$PARSER" >"$TMP/parsed" 2>"$TMP/perr"
}

GOOD='{"tag_name":"v30.7","prerelease":false,"draft":false,"assets":[{"name":"app-debug.apk","browser_download_url":"https://evil.example/app-debug.apk","size":2000000},{"name":"Magisk-v30.7.apk","browser_download_url":"https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk","size":11613864}]}'
if printf '%s' "$GOOD" | python3 "$PARSER" >"$TMP/parsed"; then
  _u=$(sed -n '1p' "$TMP/parsed")
  _s=$(sed -n '2p' "$TMP/parsed")
  if [ "$_u" = "https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk" ] && [ "$_s" = "11613864" ]; then
    ok "parser keeps the official apk"
  else
    bad "parser output $_u $_s"
  fi
else
  bad "parser rejected a good release"
fi

EVIL='{"tag_name":"v30.7","prerelease":false,"draft":false,"assets":[{"name":"Magisk-v30.7.apk","browser_download_url":"https://evil.example/Magisk-v30.7.apk","size":11613864}]}'
if printf '%s' "$EVIL" | python3 "$PARSER" >"$TMP/parsed" 2>"$TMP/perr"; then
  bad "parser accepted a non-github url"
else
  ok "parser rejects a non-github url"
fi

PRE='{"tag_name":"v30.8","prerelease":true,"draft":false,"assets":[{"name":"Magisk-v30.8.apk","browser_download_url":"https://github.com/topjohnwu/Magisk/releases/download/v30.8/Magisk-v30.8.apk","size":11613864}]}'
if printf '%s' "$PRE" | python3 "$PARSER" >/dev/null 2>"$TMP/perr"; then
  bad "parser accepted a prerelease"
else
  ok "parser rejects a prerelease"
fi

if [ "$fail" -ne 0 ]; then
  printf '\n%d failure(s)\n' "$fail"
  exit 1
fi
printf '\nall root-helper checks passed\n'
