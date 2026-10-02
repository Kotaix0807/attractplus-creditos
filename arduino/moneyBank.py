#!/usr/bin/env python3
import subprocess
import os
import time
import datetime 
import serial
import glob

MONEYBANK_STATE_PATH = os.path.expanduser("~/.attract/monedero_switch")
ARDUINO_PATH = "/dev/serial/by-id/"
ARDUINO_ID = 'usb-1a86_USB2.0-Serial-if00-port0'
PORT = ARDUINO_PATH + ARDUINO_ID
BAUD_RATE = 9600
LOG_NAME = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")
UPDATE_TIME = 0.1
ARDUINO_TIME = 3
RETRY_TIME = 5

isActive = 0
conection = None
lastError = None
lastCredit = None

def find_port():
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
     with open(f"log{LOG_NAME}.txt", "a") as file:
            file.write(datetime.datetime.now().strftime("%H:%M:%S\t") + castedString)

def logOk():
     global lastError
     if lastError is None:
            return
     log("recuperado")
     lastError = None

def initArduino():
    global conection
    global lastError

    if conection is not None:
        return True

    PORT = find_port()

    try:
        conection = serial.Serial(PORT, BAUD_RATE)
        time.sleep(ARDUINO_TIME)
        logOk()
        return True
    except (serial.SerialException, serial.SerialTimeoutException) as e:
        log(str(e))
        return False

def getFileData(path):
    with open(str(path), "r") as file:
        data = file.read()
    return data

def getMoneyBankState():
    global isActive

    try:
        fileData = getFileData(MONEYBANK_STATE_PATH)
        isActive = fileData
        return isActive
    except (FileNotFoundError, PermissionError, UnicodeDecodeError, OSError, ValueError, IndexError) as e:
         log(e)
         return None

def mameRunning():
    return subprocess.run(["pgrep","-x","mame"], stdout=subprocess.DEVNULL).returncode == 0

def sendToArduino(data):
    global conection
    stringData = str(data) + '\n'
    try:
        conection.write(stringData.encode())
    except (serial.SerialException, serial.SerialTimeoutException, OSError) as e:
        log(e)
        conection = None
        return False

    logOk()
    return True

# main


while True:

    time.sleep(UPDATE_TIME)

    if initArduino() is False:
        time.sleep(RETRY_TIME)
        continue

    if not mameRunning():
        with open(MONEYBANK_STATE_PATH, "w") as f:
            f.write("0")
        sendToArduino(0)
        if isActive != 0:
            sendToArduino(0)
            isActive = 0
        continue

        
    isActiveBuffer = getMoneyBankState()
    if isActiveBuffer is None:
        continue

    if sendToArduino(isActive) is True:
        print("State: ", isActive)
