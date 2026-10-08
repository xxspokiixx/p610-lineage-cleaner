#!/system/bin/sh
# Magisk late_start. Return immediately so boot is not held for fstrim or dexopt.
MODDIR=${0%/*}
(
  sh "$MODDIR/apply.sh"
) &
