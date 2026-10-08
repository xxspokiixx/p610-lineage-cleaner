#!/usr/bin/env python3
"""Build a Magisk-flashable zip. Stored (uncompressed), fixed timestamps."""

import os
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "dist" / "p610-lean-v1.0.0.zip"

FILES = [
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "apply.sh",
    "config.prop.default",
    "customize.sh",
    "module.prop",
    "service.sh",
    "system.prop",
    "uninstall.sh",
]


def main() -> None:
    missing = [name for name in FILES if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit("missing: " + ", ".join(missing))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w") as zf:
        for name in FILES:
            data = (ROOT / name).read_bytes().replace(b"\r\n", b"\n")
            info = zipfile.ZipInfo(filename=name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_STORED
            mode = 0o755 if name.endswith(".sh") or name.endswith("update-binary") else 0o644
            info.external_attr = (mode & 0xFFFF) << 16
            info.external_attr |= stat.S_IFREG << 16
            zf.writestr(info, data)
    print(OUT)


if __name__ == "__main__":
    main()
