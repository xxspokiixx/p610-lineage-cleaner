# P610 Lean

A reversible speed profile for the **Galaxy Tab S6 Lite Wi-Fi** on **LineageOS 23.2**.

| | |
|---|---|
| Model | SM-P610 only |
| Codename | `gta4xlwifi` |
| SoC | Exynos 9611 (4× A73 + 4× A53), Mali-G72 MP3 |
| RAM | 4 GB |
| ROM | LineageOS 23.2 (Android 16) |
| Does not support | SM-P615 / `gta4xl` (LTE) |

Lineage already ships a small system. The project wiki asks you not to uninstall its system apps, because that can break the install. This module does not delete anything, and it does not touch CPU clocks. The Exynos 9611 gets slower, not faster, once it thermal-throttles.

What you should feel: shorter animations, no window blur on a weak GPU, a bit less background radio work, and apps that stay compiled after a one-time ART pass.

## Install

You need Magisk 20.4+ (KernelSU and APatch can load the same zip). Lineage does not include root. Installing Magisk is separate, and it is the risky part. This zip does not touch the bootloader, vbmeta, or recovery.

1. Download [p610-lean-v1.0.0.zip](https://github.com/xxspokiixx/p610-lineage-cleaner/releases/download/v1.0.0/p610-lean-v1.0.0.zip) from the release. Do not flash GitHub's "Download ZIP" of the source. That archive is not a module.
2. Check the file:

   ```
   sha256sum p610-lean-v1.0.0.zip
   ```

   ```
   759d1a7b222aace99f20e081d7f0c7334861685414c519eeb402e4565d0aa54e
   ```

3. Magisk → Modules → Install from storage → the zip → reboot.

The installer aborts if `ro.product.device` is not `gta4xlwifi`.

On first boot the module waits until Android is up, then applies the profile. The ART pass can take several minutes and the tablet may feel warm. It runs once.

## What it changes

| Change | Default | Why |
|---|---|---|
| Window, transition, and animator scale | `0.5` | The UI finishes moving sooner. Stock is `1`. |
| `disable_window_blurs` | on | Mali-G72 MP3 wastes frames on Android 16 blur. |
| Always-on Wi-Fi scan | off | Less radio work. Network location is a little worse. |
| `fstrim` on `/data` and `/cache` | weekly | This tablet's storage is eMMC. Trimming every boot only wears it. |
| `cmd package bg-dexopt-job` | once | Android's own background optimizer. Not `speed` compile-everything, which bloats a 64 GB disk. |
| System Tracing (`com.android.traceur`) | disabled for user 0 | Debug tool. Not used day to day. |
| Easter egg (`com.android.egg`) | disabled for user 0 | Nothing you need. |
| SIM toolkit (`com.android.stk`) | disabled for user 0 | SM-P610 has no modem. Skipped if the package is not installed. |

Packages are disabled with `pm disable-user`. They stay on disk. Reboot into Android and remove the module to turn them back on.

## What it will not do

- Delete or uninstall `/system` apps
- Change zram size, LMK, or the dalvik heap (Lineage already sets these for 4 GB)
- Set `ro.config.low_ram` (that makes a 4 GB tablet throw apps out of memory)
- Pin a performance governor or raise clocks
- Drop caches (that makes the next launch slower)
- Disable the launcher, Settings, SystemUI, keyboard, camera (Aperture), or the Lineage updater
- Run on the LTE Tab S6 Lite

## Optional switches

Edit `/data/adb/p610-lean/config.prop` with a root file manager, or:

```
adb shell su -c "vi /data/adb/p610-lean/config.prop"
```

Reboot after saving. `1` disables that package. `0` leaves it, and re-enables it if this module was the thing that disabled it.

| Key | Package | Ships as |
|---|---|---|
| `DISABLE_JELLY` | `org.lineageos.jelly` | 0 |
| `DISABLE_TWELVE` | `org.lineageos.twelve` | 0 |
| `DISABLE_ETAR` | `org.lineageos.etar` | 0 |
| `DISABLE_RECORDER` | `org.lineageos.recorder` | 0 |
| `DISABLE_CALCULATOR` | `com.android.calculator2` | 0 |
| `DISABLE_PRINT_SPOOLER` | `com.android.printspooler` | 0 |
| `DISABLE_LIVE_WALLPAPER` | `com.android.wallpaper.livepicker` | 0 |

`EXTRA_DISABLE` is a comma-separated list for other package names. Protected names are ignored. Delete `/data/adb/p610-lean/dexopt.done` and reboot if you want the ART pass again.

`ANIMATION_SCALE` accepts `0`, `0.25`, `0.5`, `0.75`, `1`, `1.5`. Anything else becomes `0.5`.

## Undo

1. Boot the tablet normally.
2. Magisk → Modules → remove P610 Lean.
3. Reboot.

The removal script turns animations back to `1`, turns blur and Wi-Fi scanning back on, and re-enables only the packages this module disabled. It does not remember a custom scale you had before installing.

If the tablet will not boot, use Android Safe Mode (hold Volume Down once the boot animation starts). Magisk disables modules in Safe Mode. From recovery you can also delete `/data/adb/modules/p610-lean`. A recovery removal cannot run `pm enable`; boot again and enable anything still disabled, or reinstall the module and then remove it while booted.

## Build the zip yourself

```
python3 build-zip.py
sha256sum dist/p610-lean-v1.0.0.zip
```

The hash above is what that command prints. `tests/test-apply.sh` mocks `pm`, `settings`, `cmd`, and `fstrim` and checks the device gate, the denylist, the weekly trim, and restore.

## After a Lineage update

The module lives in `/data`, so it survives a ROM update as long as Magisk itself survives. If an update restores the stock boot image, reinstall Magisk. The module directory will still be there.

## License

MIT. No warranty. Read the installer output before you reboot.
