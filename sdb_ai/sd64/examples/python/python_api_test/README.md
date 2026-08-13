Simple python test script for API.

Requires:

FreeSimpleGUI https://github.com/spyoungtech/FreeSimpleGUI

python3 -m pip install FreeSimpleGUI <- does not work on Ubuntu after 22.?
 
just download from https://pypi.org/project/FreeSimpleGUI/#files 
  
and save FreeSimpleGUI.py in directory containing this example
  
you may also need to install tkinter: sudo apt install python3-tk

Script expects to find the API library:

Windows: LIBRARY_PATH = 'sdclilib.dll'

Linux: LIBRARY_PATH = os.getcwd() +"/sdclilib.so"

sdclilib.dll is built from gplsrc/sdclilib and installed into sd64/bin. It must
be on the DLL search path, so either run from that directory or copy the DLL
alongside the script.
  

From windows 11 pc I use the following ssh command to create the tunnel to my linux box Z400:

  ssh -L 4245:/tmp/sdsys/sdclient.socket -N myuser@Z400
 
This allows me to connect to the APISRVR with the sdconnect method
  sdconnect('127.0.0.1',4245,<username>,<password>,<account>)  
 
Tested from linux:  

    myuser@Z400:~$ ssh -L 4245:/tmp/sdsys/sdclient.socket -N myuser@Z400
    The authenticity of host 'z400 (127.0.1.1)' can't be established.
    ED25519 key fingerprint is SHA256:+uvamVBTjIN0OF4loZUAPgtgYxV5bCbwASBbZZTZR4g.
    This key is not known by any other names.
    Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
    Warning: Permanently added 'z400' (ED25519) to the list of known hosts.
    myuser@z400's password: 

Note! had to use sdconnect('127.0.1.1',4243,<username>,<password>,<account>)

Double check local host ip with ip a
