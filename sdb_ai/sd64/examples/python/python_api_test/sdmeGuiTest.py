#  Note requires FreeSimpleGUI https://github.com/spyoungtech/FreeSimpleGUI
#   python3 -m pip install FreeSimpleGUI <- does not work on Ubuntu after 22.?
#   just download from https://pypi.org/project/FreeSimpleGUI/#files 
#     and save FreeSimpleGUI.py in directory containing this example
#   you may also need to install tkinter: sudo apt install python3-tk
#
#
#  
#  Ussage:
#
#  Upper Memo will display responses and status codes, lower Memo is used for read / write actions.
#
#  Remote connections require ssh tunnel to SD server
#
# Example:
#  ssh -L 4245:/tmp/sdsys/sdclient.socket -N <username>@<servername>
#
# With the above tunnel, enter:
#  Address: 127.0.0.1
#  User Name: <username>
#  Password:  username's password
#  Account: <username>
#
# NOTE This is assuming <username> is setup to use SD! 
#
#    
#  Enter Address, User Name, Password and Account (next to login button) in associated fields, click login to connect.
#  (Note I have my default info in these fields to speed up testing)
#  
#  You will hopefull see something like:
#  
#
#  In the upper memo.
#
#  Enter a known file name in the field next to the Open button (in my test case the file name is TESTDATA).
#  Click the Open button.
#   
#  Response in the upper memo:
#  
#	Open successful: TESTDATA FileNbr: 1
#	
#  Note: Open populates the File Number file for both the Close and Read / Write test.
#  
#  Enter a known Record Id in the field Record Id and click Read.
#  
#  Response in upper memo is a bunch of debug info, Response in lower memo should be the actual record with field markers converted to line endings.
#  
#  Using the lower memo change the record, and click Write.
#  
#  The record should be updated, verify via terminal logged into SD.
#
#  The QMExecute button will execute the command selected from the drop down list.
#  
#  Response should show up in upper memo.
#  
#  The Call button test callx, and GetArg by executing the BASIC subroutine found in BP testsub, code below.
#  This subroutine must be compiled and cataloged in the account.
#  
#  Response in upper memo:
#  
#    Attempt to call testsub
#    Attempt retrieve arg 2
#    arg 2: and arg2 Plus we added TIMEDATE 09:30:55 19 DEC 2023
#
#  BP testsub 
# 
# * very simple test of SDCallx
# *  open TESTDATA
# *  create a record made up of passed values
# *  add a field with a time date stamp
# *  write the record as TESTSUB
# *  return the field with the time date stamp to the caller
# subroutine testsub(a1, a2, a3)
# open 'TESTDATA' to TS ELSE ABORT
# a2rtn = a2:  ' Plus we added TIMEDATE ':TIMEDATE()
# rec = ''
# Rec = a1
# rec<2> = a2
# rec<3> = a3
# rec<4> = a2rtn
# write rec on TS, "TESTSUB"
# a2 = a2rtn
# Return
# End
# 
#   Click Logout to disconnect.
#
import FreeSimpleGUI as sg
import sdclilibwrap as sdmelib 

SDME_FM  = chr(254)
SDME_VM  = chr(253)
SDME_SVM = chr(252)
#
# need to load the library
sdmelib.sdmeInitialize() 

layout_l = [[sg.Checkbox("Connect Local",key='clocal')], 
            [sg.Text('IP Address', size=(12)), sg.Input(key='-ADDRESS-', size=(25))],
            [sg.Text('User Name', size=(12)), sg.Input(key='-UNAME-', size=(25))],
            [sg.Text('Password', size=(12)), sg.Input(key='-PWD-', size=(25))],
            [ sg.Text('Account', size=(12)), sg.Input(key='-ACCOUNT-', size=(25))],
            [sg.Button('Connect'), sg.Button('Disconnect')],
            [sg.Button('Logto'), sg.Text('Account'),sg.Input(key='-LOGTO-',size=(15))],
            [sg.Button('Open'),sg.Text('File Name'),sg.Input(key='-FILENAME-', size=(15))],
            [sg.Button('Close'),sg.Text('File Nbr'),sg.Input('0',key='-FILENBR-', size=(5))],
            [sg.Button('Read'),sg.Text('Rec Id'),sg.Input(key='-RECID-', size=(15))],
            [sg.Button('Write')],
            [sg.Button('Execute'),sg.Combo(['listu','where','who','who.am.i'],key='-EXE-')],
            [sg.Button('Callx')],
            [sg.Text('Rem: ctrl+X - Cut  | ctrl+C - Copy | ctrl+V - Paste ')]]

layout_r = [[sg.Multiline(size=(80,10),font=('Consolas', 12), key='-STATUS-')],
            [sg.Multiline(default_text='',font=('Consolas', 12),size=(80,10),  key='-EDITOR-')],
            [sg.Text('Editor Window Buttons: '),sg.Button('Cut',size=(10,1)),sg.Button('Copy',size=(10,1)),sg.Button('Paste',size=(10,1))]
           ]

layout = [ [sg.Col(layout_l, p=0), sg.Col(layout_r, p=0)]]

#
# functions that insert text into our editors
def insert_status_text(text):
    '''append text to status Mulitline'''
    tkwidget = window['-STATUS-']
    tkwidget.Widget.insert('end', text+'\n')

def insert_editor_text(text):
    '''append code text to editor'''
    tkwidget = window['-EDITOR-']
    tkwidget.Widget.insert('end', text+'\n')

# copy and paste functionality
def cut_text():
    tkwidget = window['-EDITOR-']
    if tkwidget.Widget.selection_get():  
        sg.clipboard_set(tkwidget.Widget.selection_get()) # copy selected text to clipboard 
        tkwidget.Widget.delete('sel.first','sel.last')    # delete selected text

def copy_text():
    tkwidget = window['-EDITOR-']
    if tkwidget.Widget.selection_get():  
        sg.clipboard_set(tkwidget.Widget.selection_get()) # copy selected text to clipboard            

def paste_text():
    tkwidget = window['-EDITOR-']
    tkwidget.Widget.insert('insert', sg.clipboard_get())   


def Connect():
    # test for all fields filled in
    if values['clocal']==True:
        if not values['-ACCOUNT-']:
            sg.popup('Account Reqd')
            return  
      
        insert_status_text('Attempting to connect')
        status =   sdmelib.sdmeConnectLocal(str(values['-ACCOUNT-'])) 
        insert_status_text('Connect Status: ' + str(status))
    else:   
        if not values['-ADDRESS-']:
            sg.popup('IP Address Reqd')
            return
        if not values['-UNAME-']:
            sg.popup('User Name Reqd')
            return 
        if not values['-PWD-']:
            sg.popup('Passowrd Reqd')
            return 
        if not values['-ACCOUNT-']:
            sg.popup('Account Reqd')
            return
        insert_status_text('Attempting to connect')
        status =   sdmelib.sdmeConnect(str(values['-ADDRESS-']), 4245, str(values['-UNAME-']), str(values['-PWD-']), str(values['-ACCOUNT-'])) 
        insert_status_text('Connect Status: ' + str(status))
    
    if sdmelib.sdmeConnected() == 1:
        insert_status_text('Connected')
    else:
        insert_status_text('Connection Failed')   

def Disconnect():
    if sdmelib.sdmeConnected() == 1:
        sdmelib.sdmeDisconnect()
        insert_status_text('Disconnected') 
    else:
        insert_status_text('Not Connected') 
        
def Logto():
    # test for all fields filled in
    if not values['-LOGTO-']:
        sg.popup('Logto Account Reqd')
        return  
      
    insert_status_text('Attempting to logto')
    status =   sdmelib.sdmeLogto(str(values['-LOGTO-'])) 
    insert_status_text('Logto Status: ' + str(status))
    if not(status):
        insert_status_text('Logto Status Msg: ' + sdmelib.sdmeError())  
     
def Open():
    if not values['-FILENAME-']:
        sg.popup('File Name Reqd')
        return
    fnbr = sdmelib.sdmeOpen(str(values['-FILENAME-']))
    if int(fnbr) > 0:
        insert_status_text(str(values['-FILENAME-']) + ' Opened to File Number: ' + str(fnbr)   ) 
        window['-FILENBR-'].update(value=str(fnbr))
    else:
        insert_status_text('Open Error')  
        insert_status_text('Status Code: ' + str(sdmelib.sdmeStatus()))  

def Close():
    fnbr = int(values['-FILENBR-'])
    if fnbr > 0:
        sdmelib.sdmeClose(fnbr)    
        window['-FILENBR-'].update(value='0')
        insert_status_text('File Closed') 
    else:
        insert_status_text('No File Open')

def Read():
    fnbr = int(values['-FILENBR-'])
    if fnbr > 0:
        if not values['-RECID-']:
            sg.popup('Record Id Reqd')
            return
        data, err = sdmelib.sdmeRead(fnbr, str(values['-RECID-'])) 
        insert_status_text('Read Status: ' + str(err))
        if err == 0:
            lns = sdmelib.sdmeDcount(data,SDME_FM)
            insert_status_text(str(lns) + ' Fields in Record')
            for i in range(lns):
                field = sdmelib.sdmeExtract(data,i+1,0,0) 
                insert_editor_text(field)
        else:
            insert_status_text('Status Code: ' + str(sdmelib.sdmeStatus()))         
    else:
        insert_status_text('No File Open')    

def Write():
    fnbr = int(values['-FILENBR-'])
    if fnbr > 0:
        if not values['-RECID-']:
            sg.popup('Record Id Reqd')
            return
        data = values['-EDITOR-']
        rec = ''
        lncnt = 0
        datalns = data.splitlines()
        for ln in datalns:
            if rec:
                rec+= SDME_FM
            rec += str(ln).rstrip()
            lncnt += 1

        insert_status_text(str(lncnt) + ' Lines To Write')    
        status = sdmelib.sdmeWrite(fnbr,str(values['-RECID-']),rec) 
        insert_status_text('Write Status: ' + str(status))
 
    else:
        insert_status_text('No File Open')    

def Execute():
    cmd = str(values['-EXE-']) 
    if cmd: 
        insert_status_text('attempt to execute: ' + str(cmd)) 
        results, err = sdmelib.sdmeExecute(cmd)
        insert_status_text('execute results: ')
        insert_status_text(' Status: ' + str(err))
        insert_status_text(str(results))

def Callx():
    insert_status_text('Attempt Callx of subroutine:  TESTSUB: ')        
    arg1  = "this is arg 1"
    arg2  = "and arg 2"
    arg3  = "last arg 3"
    insert_status_text('with arg1: ' + arg1) 
    insert_status_text('with arg2: ' + arg2)
    insert_status_text('with arg3: ' + arg3)
    sdmelib.sdmeCallx("TESTSUB",3,arg1,arg2,arg3)
    insert_status_text('back from Callx of subroutine:  TESTSUB: ')
    insert_status_text('Attempt GetArg(2)')
    argr = sdmelib.sdmeGetArg(2)
    insert_status_text('GetArg(2):')
    insert_status_text(argr)


window = sg.Window('Simple Inputs', layout, element_justification='r')

while True:
    event, values = window.read()
    if event == sg.WIN_CLOSED:
        if sdmelib.sdmeConnected() == 1:  # if we use the desconnect function we will error on attempt to write to our multiline widget (timing issue)
            sdmelib.sdmeDisconnect()   
        break
    elif event == 'Connect':
        Connect()
    elif event == 'Disconnect':
        Disconnect()
    elif event == 'Logto' and sdmelib.sdmeConnected():
        Logto()    
    elif event == 'Open'   and sdmelib.sdmeConnected():
        Open()
    elif event == 'Close'  and sdmelib.sdmeConnected():
        Close()   
    elif event == 'Read'   and sdmelib.sdmeConnected():
        Read()
    elif event == 'Write'  and sdmelib.sdmeConnected():
        Write()               
    elif event == 'Execute' and sdmelib.sdmeConnected():
        Execute()
    elif event == 'Callx'   and sdmelib.sdmeConnected(): 
        Callx()       
    # cut copy paste
    elif event == 'Cut':
        cut_text()
    elif event == 'Copy':
        copy_text()
    elif event == 'Paste':
        paste_text() 

window.close()
