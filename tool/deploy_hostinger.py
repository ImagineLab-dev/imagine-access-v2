#!/usr/bin/env python3
"""
Sube el zip del build a Hostinger y dispara el deploy del sitio estático.

Reimplementa el flujo que usa el MCP oficial de Hostinger, para poder
desplegar sin depender de que el MCP esté cargado en la sesión:

  1. POST /api/hosting/v1/files/upload-urls    -> credenciales del file manager
  2. POST {upload_url}/{archivo}?override=true -> crea el upload (TUS), espera 201
  3. PATCH sobre esa misma URL                 -> sube el contenido en chunks
  4. POST /api/hosting/v1/accounts/{user}/websites/{domain}/deploy

OJO: el paso 4 REEMPLAZA el contenido de public_html. No es reversible.

Uso:
    python tool/deploy_hostinger.py --token TOKEN --domain dominio.com \\
        --username uXXXXXXXX --archive dist/archivo.zip [--dry-run]
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_BASE = "https://developers.hostinger.com"
CHUNK_SIZE = 10 * 1024 * 1024  # 10 MB, igual que el cliente oficial


# Cloudflare, delante de la API, rechaza con error 1010 el User-Agent por
# defecto de urllib ("Python-urllib/3.x"). Hay que mandar uno normal.
DEFAULT_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36")


def request(method, url, *, headers=None, data=None, timeout=180):
    req = urllib.request.Request(url, data=data, method=method)
    merged = {"User-Agent": DEFAULT_UA, "Accept": "*/*"}
    merged.update(headers or {})
    for key, value in merged.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            return response.status, dict(response.headers), body
    except urllib.error.HTTPError as err:
        return err.code, dict(err.headers), err.read()


def fetch_upload_credentials(token, username, domain):
    url = f"{API_BASE}/api/hosting/v1/files/upload-urls"
    payload = json.dumps({"username": username, "domain": domain}).encode()
    status, _, body = request(
        "POST", url,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        data=payload,
    )
    if status != 200:
        sys.exit(f"No se pudieron obtener credenciales de upload ({status}): {body[:400].decode(errors='replace')}")
    return json.loads(body)


def upload(archive, upload_url, auth_key, rest_auth_key):
    size = archive.stat().st_size
    name = archive.name
    target = f"{upload_url.rstrip('/')}/{name}?override=true"

    headers = {
        "X-Auth": auth_key,
        "X-Auth-Rest": rest_auth_key,
        "upload-length": str(size),
        "upload-offset": "0",
    }

    print(f"  creando upload de {name} ({size / 1048576:.1f} MB)…")
    status, _, body = request("POST", target, headers=headers, data=b"")
    if status != 201:
        sys.exit(f"La creación del upload falló ({status}): {body[:400].decode(errors='replace')}")

    offset = 0
    with archive.open("rb") as handle:
        while offset < size:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            patch_headers = dict(headers)
            patch_headers.update({
                "Content-Type": "application/offset+octet-stream",
                "Tus-Resumable": "1.0.0",
                "Upload-Offset": str(offset),
                "Content-Length": str(len(chunk)),
            })
            status, resp_headers, body = request("PATCH", target, headers=patch_headers, data=chunk)
            if status not in (200, 204):
                sys.exit(f"El chunk en offset {offset} falló ({status}): {body[:400].decode(errors='replace')}")
            new_offset = resp_headers.get("Upload-Offset") or resp_headers.get("upload-offset")
            offset = int(new_offset) if new_offset else offset + len(chunk)
            print(f"    {offset / 1048576:6.1f} / {size / 1048576:.1f} MB")

    if offset < size:
        sys.exit(f"El upload quedó incompleto: {offset} de {size} bytes")
    print("  upload completo")
    return name


def trigger_deploy(token, username, domain, archive_name):
    url = f"{API_BASE}/api/hosting/v1/accounts/{username}/websites/{domain}/deploy"
    payload = json.dumps({"archive_path": archive_name}).encode()
    status, _, body = request(
        "POST", url,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        data=payload,
        timeout=600,
    )
    text = body.decode(errors="replace")
    if status not in (200, 201, 202):
        sys.exit(f"El deploy falló ({status}): {text[:600]}")
    print(f"  deploy aceptado ({status}): {text[:300]}")


def main():
    parser = argparse.ArgumentParser(description="Deploy estático a Hostinger")
    parser.add_argument("--token", default=os.environ.get("HOSTINGER_API_TOKEN"))
    parser.add_argument("--domain", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--dry-run", action="store_true",
                        help="Sube el archivo pero no dispara el deploy")
    args = parser.parse_args()

    if not args.token:
        sys.exit("Falta el token: pasá --token o seteá HOSTINGER_API_TOKEN")

    archive = Path(args.archive)
    if not archive.is_file():
        sys.exit(f"No existe el archivo {archive}")

    print(f"Destino: {args.domain} (cuenta {args.username})")
    creds = fetch_upload_credentials(args.token, args.username, args.domain)
    upload_url = creds.get("url")
    auth_key = creds.get("auth_key")
    rest_auth_key = creds.get("rest_auth_key")
    if not (upload_url and auth_key and rest_auth_key):
        sys.exit(f"Respuesta de credenciales inesperada: {json.dumps(creds)[:400]}")

    name = upload(archive, upload_url, auth_key, rest_auth_key)

    if args.dry_run:
        print("\n  --dry-run: el archivo quedó subido, NO se disparó el deploy.")
        return

    print("  disparando deploy (reemplaza public_html)…")
    trigger_deploy(args.token, args.username, args.domain, name)
    print(f"\nListo. Verificá https://{args.domain}/")


if __name__ == "__main__":
    main()
