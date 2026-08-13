# sdguitest.py
import sys
sys.path.append('/home/xyz/python_stuff')   <=== directory that contains FreeSimpleGUI.py
import FreeSimpleGUI as sg


SDME_FM  = chr(254)
SDME_VM  = chr(253)
SDME_SVM = chr(252)
#

layout = [ 
            [sg.Text('User Name', size=(12)), sg.Input(key='-UNAME-', size=(25))],
            [sg.Text('DOB', size=(12)), sg.Input(key='-DOB-', size=(25))],
            [ sg.Text('Account', size=(12)), sg.Input(key='-ACCOUNT-', size=(25))],
            [sg.Button('Ok')]
            ]

window = sg.Window('Simple Inputs', layout, element_justification='r')

while True:
    event, values = window.read()
    if event == sg.WIN_CLOSED:
        break
    elif event == 'Ok':
        break
# rem  values['-UNAME-'] to access info
window.close()
