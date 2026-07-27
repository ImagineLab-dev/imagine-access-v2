#!/usr/bin/env python3
"""
Build de producción de la PWA.

Hace tres cosas que `flutter build web` no hace:

1. Inyecta las credenciales por --dart-define (nunca como asset: en web los
   assets de Flutter se sirven por HTTP y un .env empaquetado queda público).
2. Reescribe el precache manifest de `sw.js` con la lista real de archivos del
   build y un hash de su contenido. Ese hash es el nombre del caché, así que un
   deploy nuevo invalida el anterior automáticamente.
3. Borra el `flutter_service_worker.js` que genera Flutter, que desde 3.29 es
   una lápida que se auto-desinstala y pisaría al nuestro.

Uso:
    python tool/build_web.py --url https://xxx.supabase.co --key eyJ...
    python tool/build_web.py --env-file ruta/al/.env
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD_DIR = ROOT / "build" / "web"

PRECACHE_SUFFIXES = {".js", ".json", ".html", ".css", ".wasm", ".png", ".svg",
                     ".otf", ".ttf", ".bin"}
PRECACHE_EXCLUDE = {"NOTICES", "flutter_service_worker.js", "version.json"}
PRECACHE_EXCLUDE_SUFFIXES = {".map", ".symbols"}

# canvaskit/ NO se precachea, aunque sí se sirve.
#
# Flutter empaqueta seis variantes del renderer (canvaskit, chromium, skwasm,
# skwasm_heavy, wimp, experimental_webparagraph) y suman ~28 MB, pero el
# navegador descarga UNA sola. Precachearlas todas haría que la primera visita
# baje 34 MB en vez de ~6 MB — inaceptable en un teléfono con 4G en la puerta.
#
# En su lugar, el handler cache-first del service worker guarda la variante que
# el navegador realmente pida, en la primera carga. La consecuencia es que la
# app funciona offline recién después de una carga online exitosa, que es
# exactamente el flujo real: se instala en el local con wifi y sigue andando
# cuando la señal se cae.
PRECACHE_EXCLUDE_DIRS = ("canvaskit/",)

# Símbolos de depuración: ~8 MB inútiles en producción.
STRIP_SUFFIXES = {".symbols"}


def find_flutter() -> str:
    exe = shutil.which("flutter")
    if exe:
        return exe
    candidate = Path(os.environ.get("USERPROFILE", "")) / "flutter" / "bin" / "flutter.bat"
    if candidate.exists():
        return str(candidate)
    sys.exit("No se encontró el ejecutable de Flutter. Agregalo al PATH.")


def read_env_file(path: Path) -> dict:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        values[key.strip()] = val.strip()
    return values


def run_flutter_build(url: str, key: str) -> None:
    cmd = [
        find_flutter(), "build", "web", "--release",
        f"--dart-define=SUPABASE_URL={url}",
        f"--dart-define=SUPABASE_ANON_KEY={key}",
    ]
    # No se imprime cmd: lleva el anon key.
    print("Compilando (flutter build web --release)…")
    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode != 0:
        sys.exit(f"El build de Flutter falló con código {result.returncode}")


def strip_debug_symbols() -> int:
    """Borra los .symbols del build: son símbolos de depuración, no se sirven."""
    freed = 0
    for path in BUILD_DIR.rglob("*"):
        if path.is_file() and path.suffix in STRIP_SUFFIXES:
            freed += path.stat().st_size
            path.unlink()
    if freed:
        print(f"  eliminados símbolos de depuración ({freed / 1048576:.1f} MB)")
    return freed


def collect_precache_files() -> list:
    files = []
    for path in sorted(BUILD_DIR.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(BUILD_DIR).as_posix()
        if path.name in PRECACHE_EXCLUDE:
            continue
        if path.suffix in PRECACHE_EXCLUDE_SUFFIXES:
            continue
        if path.suffix not in PRECACHE_SUFFIXES:
            continue
        if rel.startswith(PRECACHE_EXCLUDE_DIRS):
            continue
        files.append(rel)

    # index.html se precachea como '/' para que el fallback de navegación del
    # service worker pueda resolver cualquier ruta del router estando offline.
    files = [f for f in files if f != "index.html"]
    files.insert(0, "/")
    return files


def compute_version(files: list) -> str:
    digest = hashlib.sha256()
    for rel in files:
        source = BUILD_DIR / ("index.html" if rel == "/" else rel)
        if not source.exists():
            continue
        digest.update(rel.encode("utf-8"))
        digest.update(source.read_bytes())
    return digest.hexdigest()[:12]


def inject_manifest(files: list, version: str) -> None:
    sw_path = BUILD_DIR / "sw.js"
    if not sw_path.exists():
        sys.exit("No se encontró build/web/sw.js — ¿web/sw.js está en su lugar?")

    manifest = json.dumps({"version": version, "files": files},
                          ensure_ascii=False, separators=(",", ":"))
    source = sw_path.read_text(encoding="utf-8")
    replacement = f"const PRECACHE_MANIFEST = {manifest};"
    new_source, count = re.subn(
        r"const PRECACHE_MANIFEST = \{.*?\};",
        lambda _: replacement,
        source,
        count=1,
        flags=re.DOTALL,
    )
    if count != 1:
        sys.exit("No se pudo inyectar el precache manifest en sw.js")
    sw_path.write_text(new_source, encoding="utf-8")


def remove_flutter_service_worker() -> None:
    """
    Flutter genera un `flutter_service_worker.js` que solo se auto-desinstala.
    Nada lo referencia en nuestro index.html, pero si quedara de un deploy
    anterior podría desregistrar el nuestro. Se elimina del build.
    """
    stale = BUILD_DIR / "flutter_service_worker.js"
    if stale.exists():
        stale.unlink()
        print("  eliminado flutter_service_worker.js (lápida de Flutter)")


def copy_htaccess(supabase_url: str) -> None:
    """
    Copia el .htaccess sustituyendo el host de Supabase en la CSP.

    Sin esta sustitución el connect-src queda apuntando a PROJECT.supabase.co y
    el navegador bloquea TODAS las llamadas al backend: la app carga pero no
    hace nada, con errores de CSP en consola que no son obvios de leer.
    """
    source = ROOT / "deploy" / ".htaccess"
    if not source.exists():
        print("  aviso: no se encontró deploy/.htaccess")
        return

    host = supabase_url.split("://", 1)[-1].strip("/")
    content = source.read_text(encoding="utf-8").replace("PROJECT.supabase.co", host)

    if "PROJECT.supabase.co" in content:
        sys.exit("No se pudo sustituir el host de Supabase en la CSP")

    (BUILD_DIR / ".htaccess").write_text(content, encoding="utf-8", newline="\n")
    print(f"  copiado .htaccess (CSP apuntando a {host})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build de producción de la PWA")
    parser.add_argument("--url", help="SUPABASE_URL")
    parser.add_argument("--key", help="SUPABASE_ANON_KEY")
    parser.add_argument("--env-file", help="Archivo con SUPABASE_URL y SUPABASE_ANON_KEY")
    args = parser.parse_args()

    url, key = args.url, args.key
    if args.env_file:
        values = read_env_file(Path(args.env_file))
        url = url or values.get("SUPABASE_URL")
        key = key or values.get("SUPABASE_ANON_KEY")

    if not url or not key:
        sys.exit("Faltan credenciales: pasá --url y --key, o --env-file")
    if len(key) < 20:
        sys.exit("SUPABASE_ANON_KEY parece inválida (demasiado corta)")

    run_flutter_build(url, key)

    print("Preparando la PWA…")
    remove_flutter_service_worker()
    strip_debug_symbols()
    files = collect_precache_files()
    version = compute_version(files)
    inject_manifest(files, version)
    copy_htaccess(url)

    total = sum((BUILD_DIR / ("index.html" if f == "/" else f)).stat().st_size
                for f in files
                if (BUILD_DIR / ("index.html" if f == "/" else f)).exists())

    print(f"\nListo. Versión {version}")
    print(f"  {len(files)} archivos en precache, {total / 1048576:.1f} MB")
    print(f"  Salida: {BUILD_DIR}")


if __name__ == "__main__":
    main()
