# Sourced by the Magisk installer. Do not exit from this file.

ui_print " "
ui_print "  P610 Lean"
ui_print "  Galaxy Tab S6 Lite Wi-Fi"
ui_print "  SM-P610  ·  gta4xlwifi  ·  LineageOS 23.2"
ui_print " "

device="$(getprop ro.product.device)"
[ -z "$device" ] && device="$(getprop ro.product.vendor.device)"
[ -z "$device" ] && device="$(getprop ro.product.system.device)"
model="$(getprop ro.product.model)"
[ -z "$model" ] && model="$(getprop ro.product.vendor.model)"

ui_print "- Device: ${device:-unknown}"
ui_print "- Model:  ${model:-unknown}"

allowed=0
if [ -f /data/adb/p610-lean/ALLOW_OTHER_DEVICE ]; then
  allowed=1
  ui_print "! ALLOW_OTHER_DEVICE is present. Device check bypassed."
fi

if [ "$allowed" != "1" ]; then
  ok=0
  if [ "$device" = "gta4xlwifi" ]; then
    ok=1
  elif [ -z "$device" ]; then
    case "$model" in
      *SM-P610*) ok=1 ;;
    esac
  fi
  if [ "$ok" != "1" ]; then
    abort "! Refusing to install. P610 Lean is only for the Wi-Fi Tab S6 Lite (SM-P610 / gta4xlwifi). Detected ${device:-unknown} / ${model:-unknown}. The LTE tablet (SM-P615) is a different device."
  fi
fi

los="$(getprop ro.lineage.version)"
ui_print "- Lineage: ${los:-unknown}"
case "$los" in
  23.*|"") ;;
  *) ui_print "! Target is LineageOS 23.x. Found $los. The same conservative tweaks will still be used." ;;
esac

mkdir -p /data/adb/p610-lean
if [ ! -f /data/adb/p610-lean/config.prop ]; then
  cp -f "$MODPATH/config.prop.default" /data/adb/p610-lean/config.prop
  ui_print "- Wrote /data/adb/p610-lean/config.prop"
else
  ui_print "- Kept your existing config.prop"
fi
chmod 0644 /data/adb/p610-lean/config.prop
chmod 0755 /data/adb/p610-lean

ui_print "- Nothing is deleted. CPU clocks are not changed."
ui_print "- Reboot to apply. Remove the module while booted to undo."
