#!/system/bin/sh
# Runs when the module is removed. Best done from the Magisk app while Android is booted.
MODDIR=${0%/*}
sh "$MODDIR/apply.sh" restore
