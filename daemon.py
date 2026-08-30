import os
import time
import datetime 
import serial

CREDITS_PATH = os.path.expanduser("~/.attract/creditos.txt")
ARDUINO_PATH = "/dev/serial/by-id/"
ARDUINO_ID = 'usb-1a86_USB2.0-Serial-if00-port0'
PORT = ARDUINO_PATH + ARDUINO_ID
BAUD_RATE = 9600
LOG_NAME = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")
UPDATE_TIME = 0.1
ARDUINO_TIME = 3
RETRY_TIME = 5

userCredits = 0
conection = None
lastError = None
lastCredit = None

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
    global lastCredit

    if conection is not None:
        return True

    try:
        conection = serial.Serial(PORT, BAUD_RATE)
        time.sleep(ARDUINO_TIME)
        lastCredit = None
        logOk()
        return True
    except (serial.SerialException, serial.SerialTimeoutException) as e:
            log(str(e))
            return False

def getFileData(path):
    with open(str(path), "r") as file:
        data = file.read()
    return data



def getUserCredits():
    try:
        fileData = getFileData(CREDITS_PATH)
        dataLines = fileData.split("\n") 
        for line in dataLines:
            if line.startswith("saldo"):
                parsedData = line.split(" ")
                credits = int(parsedData[1])
                logOk()
                return credits
            
    except (FileNotFoundError, PermissionError, UnicodeDecodeError, OSError, ValueError, IndexError) as e:
            log(e)
            return None


def sendToArduino(credits):
    global conection
    stringData = str(credits) + '\n'
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
        
    userCredits = getUserCredits()
    if userCredits == lastCredit or userCredits is None:
        continue

    if sendToArduino(userCredits) is True:
        lastCredit = userCredits
        print("Creditos:", userCredits)
