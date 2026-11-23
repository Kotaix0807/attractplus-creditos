#!/usr/bin/env python3
# Demonio del Arduino de la cabina. Unico dueno del puerto serie: multiplexa
# todos los canales en el protocolo de una-letra-por-linea de arduino/Arcade.ino
# (a 115200). Antes manejaba el display de 7 segmentos (cabina.ino); eso se
# descarto y ahora maneja los LEDs de los botones + el rele del monedero.
#
# Que manda, segun el estado (lo decide este demonio; la placa obedece el ultimo):
#
#   MINIJUEGO  el frontend SDL reclamo el panel por el FIFO -> se reenvian sus
#              lineas P/X crudas; no se manda A ni B. Rele cerrado (no hay MAME).
#   EN MAME    corre mame o hypseus -> M1 y B<mascara> con los botones del juego.
#   ATRACCION  ni lo uno ni lo otro -> M0 y A8 (show de animaciones).
#   siempre    si cambio el brillo -> L<n>.
#
# Ficheros vigilados en ~/.attract/ (los escribe creditos.lua / el panel):
#   monedero_switch  -> M   (1 = partida en marcha, acepta monedas)
#   botones_juego    -> B   (botones de P1 que usa el juego; aqui se traducen a LEDs)
#   brillo_leds      -> L   (brillo global 0..255)
#   arduino_fifo     -> FIFO en tiempo real: lineas P/X del minijuego + '['/']'
#                      para reclamar/soltar el panel.
#
# Tiene que ser un solo proceso: el puerto solo lo puede tener abierto uno, y
# abrirlo reinicia la placa. Detalle a fondo: docs/minijuegos.md.
import os
import time
import datetime
import serial
import glob
import select

MONEYBANK_STATE_PATH = os.path.expanduser("~/.attract/monedero_switch")
BOTONES_PATH = os.path.expanduser("~/.attract/botones_juego")
AVISO_LED_PATH = os.path.expanduser("~/.attract/aviso_led")
BRILLO_PATH = os.path.expanduser("~/.attract/brillo_leds")
FIFO_PATH = os.path.expanduser("~/.attract/arduino_fifo")
# El panel escribe este fichero para reiniciar la placa: cerrar y reabrir el
# puerto la resetea por DTR y re-sincroniza todo el estado.
RESET_PATH = os.path.expanduser("~/.attract/arduino_reset")
# El panel escribe este para reiniciar el MONEDERO (no la placa): corta y
# restaura su alimentacion con el solenoide activado, para que calibre bien.
MONEDERO_RESET_PATH = os.path.expanduser("~/.attract/monedero_reiniciar")
BAUD_RATE = 115200
LOG_NAME = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")
UPDATE_TIME = 0.1
ARDUINO_TIME = 3
RETRY_TIME = 5
PUERTO_TIME = 5        # cada cuanto se comprueba que el puerto sigue existiendo
ANIM_ATRACCION = "8"   # show rotatorio de animaciones

# Mapa provisional: boton de accion de P1 (1..6) -> canal de LED del panel.
# PENDIENTE de confirmar en la cabina (es cableado del panel). Ver docs/minijuegos.md.
MAPA_BOTONES = {1: 1, 2: 8, 3: 6, 4: 2, 5: 7, 6: 5}
# P2: segunda mitad de la grilla 2x6 (de ledArcadeTest.ino): arriba 3,10,12 /
# abajo 4,9,11. creditos.lua manda los botones de P2 como 'p2:N'. PENDIENTE de
# confirmar en la placa, igual que el de P1.
MAPA_BOTONES_P2 = {1: 3, 2: 10, 3: 12, 4: 4, 5: 9, 6: 11}

conection = None
lastError = None
# Lo ultimo que se mando con exito. None = la placa no sabe nada todavia (se
# acaba de abrir el puerto, que la reinicia), asi que se manda todo otra vez.
lastSwitch = None
lastLed = None
lastAviso = None   # estado anterior del aviso de salida ('off'/'salir'/None)
lastBrillo = None
minijuego = False     # el PC reclamo el panel por el FIFO
fifoBuf = ""
puertoAbierto = None  # ruta del puerto abierto (para ver si desaparece)
ultimaRevision = 0.0

def find_port():
    forzado = os.environ.get("ARDUINO_PORT")                   # util para pruebas / montajes raros
    if forzado:
        return forzado
    for c in sorted(glob.glob("/dev/serial/by-id/*1a86*")):   # cualquier CH340
        return c
    for c in sorted(glob.glob("/dev/ttyUSB*")):               # respaldo
        return c
    return None

def log(logString):
     global lastError
     castedString = str(logString) + '\n'
     if lastError == castedString:
            return
     lastError = castedString
     # Un fallo al escribir el log (disco lleno, permisos) NO puede tumbar el
     # demonio: systemd lo relanzaria, reabriria el puerto y eso reinicia la placa.
     try:
            with open(f"log{LOG_NAME}.txt", "a") as file:
                   file.write(datetime.datetime.now().strftime("%H:%M:%S\t") + castedString)
     except OSError:
            pass

def logOk():
     global lastError
     if lastError is None:
            return
     log("recuperado")
     lastError = None

def initArduino():
    global conection, lastSwitch, lastLed, lastBrillo, lastAviso, puertoAbierto

    if conection is not None:
        return True

    port = find_port()
    if port is None:
        log("no encuentro el Arduino (ni /dev/serial/by-id/*1a86* ni /dev/ttyUSB*)")
        return False

    try:
        # write_timeout: una escritura a una placa colgada/desenchufada falla en
        # vez de bloquear el demonio para siempre.
        conection = serial.Serial(port, BAUD_RATE, write_timeout=2)
        puertoAbierto = port
        # Abrir el puerto reinicia la placa: esperar a que arranque y volver a
        # mandarle todo, porque ha vuelto a su estado inicial.
        time.sleep(ARDUINO_TIME)
        lastSwitch = None
        lastLed = None
        lastBrillo = None
        lastAviso = None   # la placa reinicio: re-mandar tambien el estado del aviso de salida
        logOk()
        return True
    except (serial.SerialException, serial.SerialTimeoutException, OSError) as e:
        log(str(e))
        return False

def getFileData(path):
    # Se abre en cada lectura: los ficheros se reemplazan enteros (temporal +
    # rename), y con el descriptor abierto se leeria el viejo.
    with open(str(path), "r") as file:
        return file.read()

_partida = {"hay": False, "visto": 0.0}

def mameRunning():
    # Recorrer /proc entero cuesta CPU en el i3 (medido: ~8% a 10 veces por
    # segundo). Basta con mirarlo una vez por segundo: el rele de verdad lo manda
    # monedero_switch, que escribe creditos.lua; esto solo decide atraccion/juego.
    if time.monotonic() - _partida["visto"] < 1.0:
        return _partida["hay"]
    _partida["visto"] = time.monotonic()
    _partida["hay"] = _buscarPartida()
    return _partida["hay"]

def _buscarPartida():
    # "Hay partida": MAME o Hypseus (laserdisc). En Hypseus no corre creditos.lua:
    # botones_juego lo escribe su lanzador (creditos/lanzar_hypseus.sh) y
    # monedero_switch=1 el propio Hypseus parcheado cuando la placa esta lista.
    #
    # Se mira /proc/<pid>/comm (el nombre exacto, como pgrep -x) en vez de lanzar
    # pgrep: esto corre 10 veces por segundo y cada pgrep era un proceso nuevo,
    # y en el i3 los forks dan tirones al juego.
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() in ("mame", "hypseus"):
                    return True
        except OSError:
            pass   # el proceso termino mientras se miraba
    return False

def getMoneyBankState(running):
    # Sin MAME no hay partida: monedero cerrado, diga lo que diga el fichero
    # (creditos.lua no puede escribir el 0 al salir, MAME no le da un ultimo frame).
    if not running:
        # Solo se escribe si hace falta: antes se reescribia 10 veces por segundo.
        try:
            if getFileData(MONEYBANK_STATE_PATH).strip() != "0":
                with open(MONEYBANK_STATE_PATH, "w") as f:
                    f.write("0")
        except FileNotFoundError:
            pass   # sin fichero = monedero cerrado, que es lo que se quiere
        except OSError as e:
            log(e)
        return 0

    try:
        return 1 if getFileData(MONEYBANK_STATE_PATH).strip() == "1" else 0
    except (FileNotFoundError, PermissionError, UnicodeDecodeError, OSError) as e:
        log(e)
        return None

def getBrillo():
    # None = no hay fichero o error -> no se manda nada (la placa queda a 255).
    try:
        return max(0, min(255, int(getFileData(BRILLO_PATH).strip())))
    except FileNotFoundError:
        return None
    except (PermissionError, UnicodeDecodeError, OSError, ValueError) as e:
        log(e)
        return None

def getBotonesMask():
    # creditos.lua escribe los botones de P1 que usa el juego; aqui se traducen
    # a una mascara de 13 bits de canales de LED. 0 = ninguno.
    try:
        txt = getFileData(BOTONES_PATH)
    except FileNotFoundError:
        return 0    # todavia no corrio creditos.lua que lo escriba
    except (PermissionError, UnicodeDecodeError, OSError) as e:
        log(e)
        return None
    mask = 0
    for tok in txt.replace(",", " ").split():
        if tok.startswith("p2:"):
            try:
                canal = MAPA_BOTONES_P2.get(int(tok[3:]))
            except ValueError:
                continue
        else:
            try:
                canal = MAPA_BOTONES.get(int(tok))
            except ValueError:
                continue
        if canal is not None:
            mask |= (1 << canal)
    return mask

def getAvisoLed():
    # Cuadro de salida con creditos dentro (lo escribe creditos.lua):
    #   'off'   -> apaga todos los botones; 'salir' -> parpadea el de salir (canal 0);
    #   None    -> no hay cuadro (LEDs normales).
    try:
        v = getFileData(AVISO_LED_PATH).strip()
    except FileNotFoundError:
        return None
    except (PermissionError, UnicodeDecodeError, OSError) as e:
        log(e)
        return None
    return v if v in ("off", "salir") else None

def enviarCrudo(texto):
    global conection
    if conection is None:
        return False
    try:
        conection.write((texto + "\n").encode())
    except (serial.SerialException, serial.SerialTimeoutException, OSError) as e:
        log(e)
        try:
            conection.close()   # cierra el handle muerto para poder reabrir limpio
        except Exception:
            pass
        conection = None
        return False
    logOk()
    return True

def sendToArduino(tipo, valor):
    return enviarCrudo(tipo + str(valor))

def abrirFifo():
    # O_RDWR (no solo O_RDONLY) mantiene un extremo escritor abierto, asi el
    # read nunca da EOF cuando el frontend no esta conectado y no hay que reabrir.
    try:
        if not os.path.exists(FIFO_PATH):
            os.mkfifo(FIFO_PATH)
        return os.open(FIFO_PATH, os.O_RDWR | os.O_NONBLOCK)
    except OSError as e:
        log(e)
        return None

# main

fifoFd = abrirFifo()

while True:

    if initArduino() is False:
        time.sleep(RETRY_TIME)
        continue

    # Si el puerto desaparece (cable flojo, la placa se re-enumera por USB), la
    # placa ha vuelto a su estado de fabrica y no nos enteramos: solo se detecta al
    # fallar un write, y en atraccion estable no se escribe nada. Se cierra para
    # que initArduino la reabra y le re-mande todo.
    if time.monotonic() - ultimaRevision > PUERTO_TIME:
        ultimaRevision = time.monotonic()
        if puertoAbierto and not os.path.exists(puertoAbierto):
            try:
                conection.close()
            except Exception:
                pass
            conection = None
            log("el puerto %s desaparecio: reabro" % puertoAbierto)
            continue

    # Reinicio manual de la placa (el panel escribe ~/.attract/arduino_reset):
    # cerrar y reabrir el puerto la resetea por DTR, y initArduino re-manda todo.
    if os.path.exists(RESET_PATH):
        try:
            os.remove(RESET_PATH)
        except OSError:
            pass
        try:
            conection.close()
        except Exception:
            pass
        conection = None
        log("reinicio del Arduino pedido")
        continue

    # Reinicio del MONEDERO (el panel escribe ~/.attract/monedero_reiniciar):
    # corta y restaura su alimentacion (R) con el solenoide ACTIVADO (M1), para
    # que calibre al encender; luego apaga el solenoide. Al terminar se deja
    # lastSwitch=None para que la vuelta siguiente re-mande la M correcta (segun
    # haya partida o no) y no quede desincronizado.
    if os.path.exists(MONEDERO_RESET_PATH):
        try:
            os.remove(MONEDERO_RESET_PATH)
        except OSError:
            pass
        RELE_ON_S = 2.030          # rele/solenoide vivo EXACTAMENTE esto (medido por Eloy);
                                   # mas rato dejaba aceptar monedas de mas
        CORTE_S = 1.5              # alimentacion cortada para que recalibre al volver
        assert CORTE_S < RELE_ON_S, "el corte no cabe en la ventana del rele"
        enviarCrudo("M1")          # solenoide ON (si no, no calibra)
        t0 = time.monotonic()      # el rele queda vivo desde aqui
        enviarCrudo("R0")          # corta alimentacion del monedero
        time.sleep(CORTE_S)
        enviarCrudo("R1")          # la restaura: calibra con el solenoide activo
        resto = RELE_ON_S - (time.monotonic() - t0)
        if resto > 0:
            time.sleep(resto)      # apaga a los 2.030 s EXACTOS del M1, ni uno mas
        enviarCrudo("M0")          # solenoide OFF
        lastSwitch = None          # re-sincroniza la M en la proxima vuelta
        log("monedero reiniciado (pulso de calibracion del solenoide)")
        continue

    # Despertar en cuanto el FIFO tenga datos (minijuego: latencia de un write),
    # o cada UPDATE_TIME para la ronda de ficheros.
    if fifoFd is not None:
        try:
            select.select([fifoFd], [], [], UPDATE_TIME)
        except OSError:
            fifoFd = None
            time.sleep(UPDATE_TIME)
    else:
        time.sleep(UPDATE_TIME)
        fifoFd = abrirFifo()

    # Drenar el FIFO y reenviar lo del minijuego
    if fifoFd is not None:
        try:
            data = os.read(fifoFd, 4096)
        except (BlockingIOError, OSError):
            data = b""
        if data:
            fifoBuf += data.decode(errors="ignore")
            while "\n" in fifoBuf:
                linea, fifoBuf = fifoBuf.split("\n", 1)
                linea = linea.strip()
                if linea == "[":
                    minijuego = True
                    lastLed = None   # al salir habra que re-mandar A/B
                elif linea == "]":
                    minijuego = False
                    lastLed = None
                elif linea in ("R0", "R1"):
                    enviarCrudo(linea)   # alimentacion del monedero (canal 13): el panel lo reinicia
                elif linea and minijuego:
                    enviarCrudo(linea)   # P<ch>,<v> / X crudos del frontend

    running = mameRunning()

    switch = getMoneyBankState(running)
    if switch is not None and switch != lastSwitch:
        if sendToArduino("M", switch) is True:
            lastSwitch = switch
            print("Monedero:", switch)

    if conection is None:
        continue

    brillo = getBrillo()
    if brillo is not None and brillo != lastBrillo:
        if sendToArduino("L", brillo) is True:
            lastBrillo = brillo
            print("Brillo:", brillo)

    # Los LEDs: en minijuego manda el PC (ya reenviado arriba). Si no: el aviso de
    # salida (apagar todo / parpadear el boton de salir) manda sobre el juego; si no
    # lo hay, A (atraccion) o B (botones del juego).
    if not minijuego:
        aviso = getAvisoLed() if running else None
        if aviso != lastAviso:
            # cambio de estado del aviso: limpia (X) y fuerza re-mandar lo que toque
            enviarCrudo("X")
            lastLed = None
            lastAviso = aviso
            if aviso is not None:
                print("Aviso salida:", aviso)
        if aviso == "salir":
            # parpadeo llamativo del boton de salir (canal 0), ~3 Hz por reloj
            on = int(time.time() * 6) % 2
            enviarCrudo("P0,%d" % (255 if on else 0))
        elif aviso == "off":
            pass   # ya se mando X al entrar: todos los botones apagados
        else:
            if running:
                mask = getBotonesMask()
                cmd = None if mask is None else ("B%X" % mask)
            else:
                cmd = "A" + ANIM_ATRACCION
            if cmd is not None and cmd != lastLed:
                if enviarCrudo(cmd) is True:
                    lastLed = cmd
                    print("LEDs:", cmd)
