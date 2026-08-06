#!/usr/bin/env python3
"""
Recorta las fuentes de marca a los caracteres que la landing realmente usa.

POR QUE EXISTE

La landing tenía una regla explícita de "cero webfonts", puesta por peso: el
público la abre en 4G desde el teléfono y Space Grotesk completa pesa 133 KB.
Pero una página de venta usa ciento y pico de caracteres, no los tres mil que
trae la fuente. Recortada a esos, y en WOFF2, queda en 12 KB — menos que
cualquiera de las fotos de la página.

O sea: la regla se puso por un problema que se puede eliminar, y eliminarlo deja
la landing con la misma tipografía que el producto. Que el sitio y la app se
vean distinto es peor que 25 KB.

CUANDO CORRERLO

Cada vez que cambie el TEXTO de `landing/index.html`. Si se agrega un carácter
que no está en el recorte, el navegador lo dibuja con la fuente de reserva y se
nota en el medio de una palabra.

    python tool/recortar_fuentes.py

Necesita `fonttools` y `brotli`:

    pip install fonttools brotli
"""

import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
LANDING = RAIZ / "landing" / "index.html"
ORIGEN = RAIZ / "assets" / "fonts"
DESTINO = RAIZ / "landing" / "fonts"

FUENTES = ["SpaceGrotesk", "JetBrainsMono"]

# Además del texto de la página. Recortar tan al hueso que agregar una coma
# rompa la tipografía sería una trampa para quien edite el copy mañana.
COLCHON = (
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "áéíóúüñÁÉÍÓÚÜÑ"
    "¿?¡!.,;:()[]{}\"'«»—–-_/|@#$%&*+=<>°ºª€ "
)


def caracteres_de_la_landing() -> str:
    html = LANDING.read_text(encoding="utf-8")
    # Se saca lo que no se dibuja como texto: estilos, scripts y las etiquetas.
    visible = re.sub(r"<style.*?</style>", " ", html, flags=re.S)
    visible = re.sub(r"<script.*?</script>", " ", visible, flags=re.S)
    visible = re.sub(r"<[^>]+>", " ", visible)

    juego = {c for c in set(visible) | set(COLCHON) if c.isprintable() or c == " "}
    return "".join(sorted(juego))


def main() -> None:
    if not LANDING.is_file():
        sys.exit(f"No existe {LANDING}")

    texto = caracteres_de_la_landing()
    DESTINO.mkdir(parents=True, exist_ok=True)
    print(f"Caracteres a conservar: {len(texto)}\n")

    total_antes = total_despues = 0
    for nombre in FUENTES:
        origen = ORIGEN / f"{nombre}.ttf"
        if not origen.is_file():
            sys.exit(f"Falta {origen}")
        salida = DESTINO / f"{nombre}.woff2"

        resultado = subprocess.run(
            [
                sys.executable, "-m", "fontTools.subset", str(origen),
                "--text=" + texto,
                "--flavor=woff2",
                # `kern` y `liga` se conservan: sin kerning, un titular grande
                # en grotesca se ve con los huecos mal repartidos.
                "--layout-features=kern,liga",
                "--output-file=" + str(salida),
            ],
            capture_output=True, text=True,
        )
        if resultado.returncode != 0:
            sys.exit(f"fontTools falló con {nombre}:\n{resultado.stderr[-600:]}")

        antes = origen.stat().st_size
        despues = salida.stat().st_size
        total_antes += antes
        total_despues += despues
        print(f"  {nombre:15} {antes/1024:6.0f} KB -> {despues/1024:5.1f} KB"
              f"   ({100 - despues / antes * 100:.0f}% menos)")

    print(f"\n  TOTAL           {total_antes/1024:6.0f} KB -> "
          f"{total_despues/1024:5.1f} KB")
    print(f"\nListo. Salida en {DESTINO}")


if __name__ == "__main__":
    main()
