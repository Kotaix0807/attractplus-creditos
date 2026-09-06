#!/usr/bin/env python3
"""Dice en que segundo conviene empezar el video de muestra de un juego.

El problema que resuelve: de los juegos instalados, la mayoria no tiene linea
propia en arranque.dat, asi que videos.sh les aplicaba un salto ciego de 8 s y
muchos vídeos empezaban en la PANTALLA DE TEST de la placa.

No se puede usar 'segundos=' de arranque.dat para esto, aunque lo parezca: esa
clave dice cuando la placa acepta monedas, no cuando empieza algo que merezca
la pena grabar. Contra esta lista a los 7 y su demo empieza a los 16.

COMO LO DECIDE, en dos pasos:

1. FIN DEL ARRANQUE. El test de RAM/ROM se reconoce porque la pantalla se va a
   negro y pega saltos de brillo enormes. Se busca el ULTIMO de esos sucesos y
   se da el arranque por terminado justo despues. Es deliberadamente
   conservador: pasarse un poco no estropea nada, quedarse corto mete la
   pantalla de test en el video, que es justo el fallo que hay que arreglar.

2. LA MEJOR VENTANA. De ahi en adelante se puntua cada comienzo posible por lo
   que pasa en los 'dura' segundos siguientes: cuanto se mueve la imagen y
   cuanto brillo tiene. Las dos cosas hacen falta y se vio por que:

     - Solo movimiento elige mal en Mappy: sus rotulos ("NAMCO PRESENTS",
       "STARRING") parpadean mas que su demo, que son sprites pequenos sobre
       un fondo quieto. Ganaria el rotulo.
     - Solo brillo elige mal en New Rally-X: su lista de personajes es una
       pantalla FIJA y clarisima, y ganaria a la partida de demostracion.

   Con las dos juntas, los tres juegos de los que hay medida a mano caen en
   contenido de verdad.

NO sustituye a mirarlo. Lo que decide de verdad si una eleccion es buena es
verla, que es la regla de este proyecto para todo lo demas. Por eso videos.sh
guarda una hoja de contactos con el fotograma elegido de cada juego, y por eso
el resultado se escribe en arranque.dat como 'video=N': para poder corregirlo
a mano cuando no acierte.
"""

import os
import subprocess
import sys

ANCHO = ALTO = 96          # a lo que se reduce cada fotograma para medirlo
POR_SEGUNDO = 2            # muestras por segundo
UMBRAL_PIXEL = 12          # cuanto tiene que cambiar un pixel para contarlo
NEGRO = 6.0                # por debajo de esto la pantalla esta apagada
SALTO_BRUSCO = 45.0        # salto de brillo que delata el test de la placa
PESO_BRILLO = 0.30         # cuanto pesa el brillo frente al movimiento
LIMITE_ARRANQUE = 30       # segundos: mas alla de esto ya no es arranque


def muestrear(avi):
    """-> [(brillo, % de pixeles que cambian)] por muestra."""
    n = ANCHO * ALTO
    orden = ["ffmpeg", "-v", "error", "-i", avi,
             "-vf", "fps=%d,scale=%d:%d:flags=bilinear,format=gray"
                    % (POR_SEGUNDO, ANCHO, ALTO),
             "-f", "rawvideo", "-pix_fmt", "gray", "-"]
    crudo = subprocess.run(orden, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL).stdout
    fotos = [crudo[i * n:(i + 1) * n] for i in range(len(crudo) // n)]
    serie, previo = [], None
    for f in fotos:
        brillo = sum(f) / n
        if previo is None:
            cambio = 0.0
        else:
            cambio = 100.0 * sum(1 for k in range(n)
                                 if abs(f[k] - previo[k]) > UMBRAL_PIXEL) / n
        serie.append((brillo, cambio))
        previo = f
    return serie


def fin_del_arranque(serie):
    """La ultima muestra que huele a test de placa, +1.

    Solo se mira el PRINCIPIO. Buscar en toda la grabacion no vale y costo una
    pasada averiguarlo: el modo de atraccion de casi cualquier juego funde a
    negro entre pantalla y pantalla, y cada fundido reseteaba la cuenta. En
    Contra el arranque salia "terminando" en el segundo 55 de 60, o sea que el
    detector se quedaba sin sitio para elegir nada.
    """
    tope = min(int(LIMITE_ARRANQUE * POR_SEGUNDO), len(serie) // 2)
    ultima = 0
    for i in range(min(tope, len(serie))):
        brillo = serie[i][0]
        salto = abs(brillo - serie[i - 1][0]) if i else 0.0
        if brillo < NEGRO or salto > SALTO_BRUSCO:
            ultima = i
    return ultima + 1


def medir(avi, dura, minimo=0):
    """-> (segundo elegido, fin del arranque, cuantos segundos se miraron)."""
    serie = muestrear(avi)
    if not serie:
        return None, None, 0
    total = len(serie) / float(POR_SEGUNDO)
    ancho = int(dura * POR_SEGUNDO)
    desde = max(fin_del_arranque(serie), int(minimo * POR_SEGUNDO))

    # Hay que dejar sitio para la ventana entera; si no cabe, se recorta.
    ultimo = len(serie) - ancho
    if ultimo <= desde:
        return round(desde / float(POR_SEGUNDO)), \
               round(fin_del_arranque(serie) / float(POR_SEGUNDO)), total

    mejor, mejor_punto = None, desde
    for inicio in range(desde, ultimo + 1):
        trozo = serie[inicio:inicio + ancho]
        movimiento = sum(c for _, c in trozo) / len(trozo)
        brillo = sum(b for b, _ in trozo) / len(trozo)
        nota = movimiento + PESO_BRILLO * brillo
        if mejor is None or nota > mejor:
            mejor, mejor_punto = nota, inicio
    return (round(mejor_punto / float(POR_SEGUNDO)),
            round(fin_del_arranque(serie) / float(POR_SEGUNDO)), total)


def main():
    if len(sys.argv) < 2:
        sys.exit("uso: medir_video.py <fichero.avi> [duracion] [minimo]")
    avi = sys.argv[1]
    dura = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
    minimo = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    if not os.path.isfile(avi):
        sys.exit("no encuentro %s" % avi)
    punto, arranque, total = medir(avi, dura, minimo)
    if punto is None:
        sys.exit("no pude leer fotogramas de %s" % avi)
    # La primera linea es la que lee videos.sh; el resto, para mirarlo.
    print(punto)
    print("# arranque termina en %ss, medidos %ss" % (arranque, total),
          file=sys.stderr)


if __name__ == "__main__":
    main()
