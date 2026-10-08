#!/system/bin/sh
# P610 Lean boot/restore script. POSIX sh (Magisk BusyBox ash).
# State lives in /data/adb/p610-lean so it survives module updates.

STATE_DIR="${P610_STATE_DIR:-/data/adb/p610-lean}"

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *) MODDIR=. ;;
esac

LOG="$STATE_DIR/last.log"
CFG="$STATE_DIR/config.prop"
LIST="$STATE_DIR/disabled.list"

log() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

get_cfg() {
  _key=$1
  _def=$2
  _val=""
  if [ -f "$CFG" ]; then
    _val=$(grep -E "^${_key}=" "$CFG" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d ' \t\r')
  fi
  if [ -z "$_val" ]; then
    printf '%s\n' "$_def"
  else
    printf '%s\n' "$_val"
  fi
}

flag_on() {
  [ "$(get_cfg "$1" "$2")" = "1" ]
}

is_protected() {
  case "$1" in
    android | \
      com.android.systemui | \
      com.android.settings | \
      com.android.providers.settings | \
      com.android.providers.media | \
      com.android.providers.media.module | \
      com.android.providers.telephony | \
      com.android.packageinstaller | \
      com.android.permissioncontroller | \
      com.android.shell | \
      com.android.bluetooth | \
      com.android.nfc | \
      com.android.networkstack | \
      com.android.networkstack.tethering | \
      com.android.phone | \
      com.android.server.telecom | \
      com.android.inputmethod.latin | \
      com.android.launcher3 | \
      com.android.documentsui | \
      android.ext.services | \
      org.lineageos.updater | \
      org.lineageos.aperture | \
      org.lineageos.lineageparts | \
      org.lineageos.overlay | \
      lineageos.platform)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

valid_pkg() {
  case "$1" in
    "" | .* | *[!A-Za-z0-9_.]*)
      return 1
      ;;
    *.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

device_ok() {
  [ -f "$STATE_DIR/ALLOW_OTHER_DEVICE" ] && return 0
  _d=$(getprop ro.product.device)
  [ -z "$_d" ] && _d=$(getprop ro.product.vendor.device)
  [ -z "$_d" ] && _d=$(getprop ro.product.system.device)
  _m=$(getprop ro.product.model)
  [ -z "$_m" ] && _m=$(getprop ro.product.vendor.model)
  if [ "$_d" = "gta4xlwifi" ]; then
    return 0
  fi
  if [ -z "$_d" ]; then
    case "$_m" in
      *SM-P610*) return 0 ;;
    esac
  fi
  return 1
}

is_disabled() {
  pm list packages -d --user 0 2>/dev/null | grep -qx "package:$1"
}

put_setting() {
  settings put global "$1" "$2" >/dev/null 2>&1 || log "settings failed: $1=$2"
}

disable_pkg() {
  _pkg=$1
  if is_protected "$_pkg"; then
    log "refusing protected package $_pkg"
    return 0
  fi
  if ! valid_pkg "$_pkg"; then
    log "ignoring invalid package name"
    return 0
  fi
  if ! pm path "$_pkg" >/dev/null 2>&1; then
    return 0
  fi
  if is_disabled "$_pkg"; then
    return 0
  fi
  if pm disable-user --user 0 "$_pkg" >/dev/null 2>&1; then
    if ! grep -qx "$_pkg" "$LIST" 2>/dev/null; then
      printf '%s\n' "$_pkg" >> "$LIST"
    fi
    log "disabled $_pkg"
  else
    log "could not disable $_pkg"
  fi
}

enable_if_ours() {
  _pkg=$1
  if ! grep -qx "$_pkg" "$LIST" 2>/dev/null; then
    return 0
  fi
  if pm enable --user 0 "$_pkg" >/dev/null 2>&1; then
    log "re-enabled $_pkg"
  else
    log "could not re-enable $_pkg"
  fi
  if [ -f "$LIST" ]; then
    grep -vx "$_pkg" "$LIST" > "$LIST.tmp" 2>/dev/null || true
    mv "$LIST.tmp" "$LIST" 2>/dev/null || true
  fi
}

apply_toggle() {
  # key package default(1=disable)
  if flag_on "$1" "$3"; then
    disable_pkg "$2"
  else
    enable_if_ours "$2"
  fi
}

trim_log() {
  if [ ! -f "$LOG" ]; then
    return 0
  fi
  _lines=$(wc -l < "$LOG" | tr -d ' ')
  case "$_lines" in
    '' | *[!0-9]*) return 0 ;;
  esac
  if [ "$_lines" -gt 400 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

wait_for_boot() {
  if [ "${P610_SKIP_BOOT_WAIT:-0}" = "1" ]; then
    return 0
  fi
  _i=0
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    _i=$((_i + 1))
    if [ "$_i" -gt 90 ]; then
      log "boot_completed never arrived; applying anyway"
      return 0
    fi
    sleep 2
  done
  sleep "${P610_SETTLE_SECS:-12}"
}

apply_animations() {
  _scale=$(get_cfg ANIMATION_SCALE 0.5)
  case "$_scale" in
    0 | 0.0 | 0.25 | 0.5 | 0.75 | 1 | 1.0 | 1.5) ;;
    *)
      log "invalid ANIMATION_SCALE '$_scale', using 0.5"
      _scale=0.5
      ;;
  esac
  put_setting window_animation_scale "$_scale"
  put_setting transition_animation_scale "$_scale"
  put_setting animator_duration_scale "$_scale"
  printf '%s\n' "$_scale"
}

trim_one() {
  if [ -d "$1" ]; then
    if fstrim -v "$1" >> "$LOG" 2>&1; then
      log "fstrim $1 ok"
    else
      log "fstrim $1 skipped"
    fi
    return 0
  fi
  return 1
}

do_fstrim() {
  if ! flag_on WEEKLY_FSTRIM 1; then
    return 0
  fi
  _now=$(date +%s)
  case "$_now" in
    '' | *[!0-9]*) return 0 ;;
  esac
  _last=0
  if [ -f "$STATE_DIR/last_fstrim" ]; then
    _last=$(tr -d ' \t\r\n' < "$STATE_DIR/last_fstrim")
  fi
  case "$_last" in
    '' | *[!0-9]*) _last=0 ;;
  esac
  if [ $((_now - _last)) -lt 604800 ]; then
    log "fstrim not due"
    return 0
  fi
  _did=0
  if [ -n "${P610_TRIM_MOUNTS:-}" ]; then
    for _mp in $P610_TRIM_MOUNTS; do
      if trim_one "$_mp"; then
        _did=1
      fi
    done
  else
    if trim_one /data; then
      _did=1
    fi
    if trim_one /cache; then
      _did=1
    fi
  fi
  if [ "$_did" = "1" ]; then
    printf '%s\n' "$_now" > "$STATE_DIR/last_fstrim"
  else
    log "fstrim found no mounted data or cache"
  fi
}

do_dexopt() {
  if ! flag_on DEXOPT_ONCE 1; then
    return 0
  fi
  if [ -f "$STATE_DIR/dexopt.done" ]; then
    return 0
  fi
  log "ART background optimize starting (once). The tablet may feel warm."
  if cmd package bg-dexopt-job >> "$LOG" 2>&1; then
    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/dexopt.done"
    log "ART background optimize finished"
  else
    log "ART background optimize did not run. It will be tried again next boot."
  fi
}

apply_extras() {
  _extra=$(get_cfg EXTRA_DISABLE "")
  [ -n "$_extra" ] || return 0
  while read -r _pkg; do
    _pkg=$(printf '%s' "$_pkg" | tr -d ' \t\r')
    [ -n "$_pkg" ] || continue
    if ! valid_pkg "$_pkg"; then
      log "ignoring invalid EXTRA_DISABLE entry"
      continue
    fi
    disable_pkg "$_pkg"
  done <<EOF
$(printf '%s\n' "$_extra" | tr ',' '\n')
EOF
}

do_apply() {
  mkdir -p "$STATE_DIR" || {
    printf '%s\n' "P610 Lean: cannot create $STATE_DIR" >&2
    exit 0
  }
  trim_log
  wait_for_boot
  if ! device_ok; then
    _d=$(getprop ro.product.device)
    _m=$(getprop ro.product.model)
    log "refusing to run: not SM-P610 / gta4xlwifi (${_d:-unknown} / ${_m:-unknown})"
    exit 0
  fi
  if [ ! -f "$CFG" ] && [ -f "$MODDIR/config.prop.default" ]; then
    cp "$MODDIR/config.prop.default" "$CFG" || exit 0
    chmod 0644 "$CFG" 2>/dev/null || true
    log "seeded config from module"
  fi
  if [ ! -f "$CFG" ]; then
    log "no config.prop, nothing to do"
    exit 0
  fi
  touch "$LIST"

  _los=$(getprop ro.lineage.version)
  log "apply device=$(getprop ro.product.device) model=$(getprop ro.product.model) lineage=${_los:-unknown}"
  case "$_los" in
    23.* | "") ;;
    *) log "warning: expected LineageOS 23.x, found $_los" ;;
  esac

  _scale=$(apply_animations)
  if flag_on DISABLE_WINDOW_BLUR 1; then
    put_setting disable_window_blurs 1
  else
    put_setting disable_window_blurs 0
  fi
  if flag_on DISABLE_WIFI_SCAN_ALWAYS 1; then
    put_setting wifi_scan_always_enabled 0
  else
    put_setting wifi_scan_always_enabled 1
  fi

  apply_toggle DISABLE_TRACEUR com.android.traceur 1
  apply_toggle DISABLE_EASTER_EGG com.android.egg 1
  apply_toggle DISABLE_SIM_TOOLKIT com.android.stk 1
  apply_toggle DISABLE_JELLY org.lineageos.jelly 0
  apply_toggle DISABLE_TWELVE org.lineageos.twelve 0
  apply_toggle DISABLE_ETAR org.lineageos.etar 0
  apply_toggle DISABLE_RECORDER org.lineageos.recorder 0
  apply_toggle DISABLE_CALCULATOR com.android.calculator2 0
  apply_toggle DISABLE_PRINT_SPOOLER com.android.printspooler 0
  apply_toggle DISABLE_LIVE_WALLPAPER com.android.wallpaper.livepicker 0
  apply_extras

  do_fstrim
  do_dexopt

  {
    printf '%s\n' "P610 Lean v1.0.0"
    printf '%s\n' "animation=$_scale"
    printf '%s\n' "blur=$(get_cfg DISABLE_WINDOW_BLUR 1)"
    printf '%s\n' "wifi_scan_disabled=$(get_cfg DISABLE_WIFI_SCAN_ALWAYS 1)"
    printf '%s\n' "disabled:"
    if [ -f "$LIST" ]; then
      cat "$LIST"
    fi
  } > "$STATE_DIR/last-summary.txt"
  log "apply done"
  sync
}

do_restore() {
  mkdir -p "$STATE_DIR" || exit 0
  log "restore requested"
  if [ -f "$LIST" ]; then
    while read -r _pkg; do
      [ -n "$_pkg" ] || continue
      if pm enable --user 0 "$_pkg" >/dev/null 2>&1; then
        log "restored $_pkg"
      else
        log "could not restore $_pkg (boot into Android and remove the module again)"
      fi
    done < "$LIST"
    : > "$LIST"
  fi
  put_setting window_animation_scale 1
  put_setting transition_animation_scale 1
  put_setting animator_duration_scale 1
  put_setting disable_window_blurs 0
  put_setting wifi_scan_always_enabled 1
  printf '%s\n' "restored" > "$STATE_DIR/last-summary.txt"
  log "restore done"
  sync
}

mode=${1:-apply}
case "$mode" in
  apply) do_apply ;;
  restore) do_restore ;;
  *)
    printf '%s\n' "usage: apply.sh [apply|restore]" >&2
    exit 2
    ;;
esac
