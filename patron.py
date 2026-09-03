#!/usr/bin/env python3
"""Patron de ajuste para el CRT. Responde a dos preguntas de una vez.

    ./patron.py            genera el patron y lo enseña en el CRT
    ./patron.py --solo     solo lo genera, no lo enseña

1. GEOMETRIA. El circulo tiene que salir REDONDO y los cuadros CUADRADOS.
   Si el circulo es un ovalo tumbado, el tubo esta estirando a lo ancho y eso
   se arregla en el menu del propio monitor (H-SIZE / H-WIDTH), no por
   software: MAME ya dibuja la proporcion correcta.

2. LINEAS DE BARRIDO. Las tres bandas llevan lineas de 1, 2 y 3 pixeles.
   Si la banda de 1 px se ve gris uniforme, el tubo NO resuelve 768 lineas y
   ningun shader va a enseñar scanlines finas a esta resolucion: hay que
   subirlas de grosor (spot_size) o bajar la resolucion del escritorio.
"""

import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont

ANCHO, ALTO = 1024, 768
SALIDA = os.path.expanduser("~/.attract/patron_crt.png")

BLANCO = (255, 255, 255)
GRIS = (128, 128, 128)
VERDE = (0, 255, 0)


def fuente(tam):
    for r in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(r):
            return ImageFont.truetype(r, tam)
    return ImageFont.load_default()


def dibujar():
    im = Image.new("RGB", (ANCHO, ALTO), (0, 0, 0))
    d = ImageDraw.Draw(im)
    chica, media = fuente(15), fuente(19)

    # --- rejilla de 64 px: cuadrada si la geometria es correcta ---
    for x in range(0, ANCHO + 1, 64):
        d.line([(x, 0), (x, ALTO)], fill=(0, 0, 80))
    for y in range(0, ALTO + 1, 64):
        d.line([(0, y), (ANCHO, y)], fill=(0, 0, 80))

    # --- marco doble: si no se ve entero, el tubo se come los bordes ---
    d.rectangle([0, 0, ANCHO - 1, ALTO - 1], outline=VERDE)
    d.rectangle([1, 1, ANCHO - 2, ALTO - 2], outline=VERDE)

    # --- arriba: lineas de 1, 2 y 3 px. Sin tocar el circulo de abajo ---
    d.text((24, 12), "LINEAS DE BARRIDO -- si la de 1 px se ve gris lisa, "
                     "el tubo no resuelve 768 lineas", font=chica, fill=VERDE)
    y0 = 36
    for grosor in (1, 2, 3):
        alto_banda = 56
        for y in range(y0, y0 + alto_banda, grosor * 2):
            d.rectangle([150, y, ANCHO - 150, y + grosor - 1], fill=BLANCO)
        d.text((36, y0 + alto_banda // 2 - 10), f"{grosor} px",
               font=media, fill=VERDE)
        d.text((ANCHO - 120, y0 + alto_banda // 2 - 10), f"{grosor} px",
               font=media, fill=VERDE)
        y0 += alto_banda + 18

    # --- abajo: geometria. Circulo redondo y cuadro cuadrado ---
    cx, cy, r = ANCHO // 2, 500, 220
    d.text((24, 262), "GEOMETRIA -- el circulo tiene que salir REDONDO y el "
                      "cuadro CUADRADO", font=chica, fill=VERDE)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=BLANCO, width=2)
    d.rectangle([cx - r, cy - r, cx + r, cy + r], outline=GRIS)
    d.line([(cx, cy - 30), (cx, cy + 30)], fill=BLANCO)
    d.line([(cx - 30, cy), (cx + 30, cy)], fill=BLANCO)
    # las cuatro esquinas, para ver alabeo (pincushion)
    for ex, ey in ((16, 16), (ANCHO - 16, 16), (16, ALTO - 16), (ANCHO - 16, ALTO - 16)):
        d.line([(ex - 14, ey), (ex + 14, ey)], fill=VERDE)
        d.line([(ex, ey - 14), (ex, ey + 14)], fill=VERDE)

    d.text((24, ALTO - 34), "ovalado tumbado = el TUBO estira; se arregla en "
                            "H-SIZE del monitor, no por software",
           font=chica, fill=VERDE)
    d.text((ANCHO - 200, ALTO - 34), "salir: Escape", font=chica, fill=VERDE)

    im.save(SALIDA)
    return SALIDA


if __name__ == "__main__":
    ruta = dibujar()
    print(f"patron en {ruta}  ({ANCHO}x{ALTO})")
    if "--solo" in sys.argv:
        sys.exit(0)

    aqui = os.path.dirname(os.path.abspath(__file__))
    subprocess.run([os.path.join(aqui, "pantalla.py"), "cabina"], check=False)
    try:
        subprocess.run(["eog", "--fullscreen", ruta], check=False)
    finally:
        subprocess.run([os.path.join(aqui, "pantalla.py"), "escritorio"],
                       check=False)
