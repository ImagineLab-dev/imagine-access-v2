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
    "js/lector.js",        # sin esto el escaner cae al decodificador lento
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

    purgar_viejos(dest_dir)
    print("\n  Listo para subir.")


# Cuántos paquetes se conservan: el que está desplegado y uno para volver
# atrás. Más que eso no sirve para nada — el zip se reconstruye entero desde
# el código con `build_web.py` + este script.
CONSERVAR = 2


def purgar_viejos(dest_dir: Path) -> None:
    """Borra los paquetes viejos de la carpeta de salida.

    Nada limpiaba esta carpeta, así que quedaba un zip de ~14 MB por cada
    deploy. En dos días de iteración se habían juntado 31: 416 MB de copias
    del mismo sitio, ninguna reconstruible a partir de la otra pero todas
    reconstruibles a partir del código.

    Se conservan los más recientes por fecha de modificación, que es el orden
    en que se generan.
    """
    paquetes = sorted(
        dest_dir.glob("imagineaccess_*.zip"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    sobrantes = paquetes[CONSERVAR:]
    if not sobrantes:
        return

    liberado = 0
    for viejo in sobrantes:
        liberado += viejo.stat().st_size
        viejo.unlink()

    print(f"\n  purgados {len(sobrantes)} paquetes viejos "
          f"({liberado / 1048576:.0f} MB); se conservan los {CONSERVAR} últimos")


if __name__ == "__main__":
    main()
