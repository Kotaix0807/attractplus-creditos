import os
import time
import datetime 
import serial

FILE_PATH = os.path.expanduser("~/.attract/creditos.txt")
PORT = '/dev/ttyUSB0'
BAUD_RATE = 9600

global userCredits
global conection
global lastError
global lastCredit

conection = None
lastError = None
lastCredit = None


userCredits = 0
timeNow = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")

def initArduino():
    global conection
    global lastError
    global lastCredit

    try:
        conection = serial.Serial(PORT, BAUD_RATE)
        lastCredit = None
    except (serial.SerialException, serial.SerialTimeoutException) as e:
        with open(f"logError{timeNow}.txt", "a") as file:
            if lastError != str(e):
                file.write(datetime.datetime.now().strftime("%H:%M:%S\t") + str(e) + '\n')
                lastError = str(e)
            return 
    time.sleep(3)

    return

def openFile():
    with open(FILE_PATH, "r") as file:
        data = file.read()
    return data



def getUserCredits():
    global lastError
    try:
        fileData = openFile()
        dataLines = fileData.split("\n") 
        for line in dataLines:
            if line.startswith("saldo"):
                parsedData = line.split(" ") 
                return int(parsedData[1])
    except (FileNotFoundError, PermissionError, UnicodeDecodeError, OSError, ValueError) as e:
        with open(f"logError{timeNow}.txt", "a") as file:
            if lastError != str(e):
                file.write(datetime.datetime.now().strftime("%H:%M:%S\t") + str(e) + '\n')
                lastError = str(e)
            return None


def sendToArduino(credits):
    global conection
    stringData = str(userCredits) + '\n'
    try:
        conection.write(stringData.encode())
    except (serial.SerialException, serial.SerialTimeoutException) as e:
        conection = None
        return False

    return True

# main

initArduino()

while True:




    if conection is not None:
        time.sleep(0.1)
        userCredits = getUserCredits()
        if userCredits is None or lastCredit == -1 or userCredits == lastCredit:
            continue
        else:
            print("User Credits: ", userCredits)
            if sendToArduino(userCredits) is False:
                lastCredit = -1
                continue
            lastCredit = userCredits
    else:
        print("Conection failed, retrying...\n")
        time.sleep(5)
        initArduino()
        
