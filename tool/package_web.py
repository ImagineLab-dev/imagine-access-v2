#!/usr/bin/env python3
"""
Empaqueta build/web en un zip listo para subir a Hostinger.

El nombre sigue el patrón que espera `hosting_deployStaticWebsite`:
    <directorio>_YYYYMMDD_HHMMSS.zip

Uso:
    python tool/package_web.py [carpeta-destino]
"""

import os
import sys
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD_DIR = ROOT / "build" / "web"

# Deben estar sí o sí; si falta alguno, el deploy queda roto de formas sutiles.
REQUIRED = [
    ".htaccess",          # sin esto, refrescar en /scanner da 404
    "index.html",
    "sw.js",              # sin esto no hay offline
    "manifest.json",      # sin esto no es instalable
    "js/pwa.js",
    "js/zxing-0.21.3.min.js",
    "icons/Icon-512.png",
    "main.dart.js",
]


def main() -> None:
    if not BUILD_DIR.is_dir():
        sys.exit(f"No existe {BUILD_DIR}. Corré primero: python tool/build_web.py")

    dest_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dist"
    dest_dir.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    zip_path = dest_dir / f"imagineaccess_{stamp}.zip"

    count = 0
    raw_bytes = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(BUILD_DIR.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(BUILD_DIR).as_posix()
            archive.write(path, rel)
            count += 1
            raw_bytes += path.stat().st_size

    names = set(zipfile.ZipFile(zip_path).namelist())
    missing = [f for f in REQUIRED if f not in names]

    print(f"  {count} archivos, {raw_bytes / 1048576:.1f} MB sin comprimir")
    print(f"  zip: {zip_path.stat().st_size / 1048576:.1f} MB")
    print(f"  ruta: {zip_path}")
    print()
    for required in REQUIRED:
        print(f"  {required:30} {'OK' if required in names else 'FALTA'}")

    if missing:
        sys.exit(f"\nFaltan archivos críticos: {', '.join(missing)}")
    print("\n  Listo para subir.")


if __name__ == "__main__":
    main()
