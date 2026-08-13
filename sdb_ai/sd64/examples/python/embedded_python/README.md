**********************
Embedding Python in SD
**********************

PY_GUI_TEST

Program creates a simple gui dialog via a script file executed from with in SD.
User populates fields, hits ok, program prints entered data back out.

Uses FreeSimpleGUI which must be installed prior to running the program.

Install FreeSimpleGUI:    https://pypi.org/project/FreeSimpleGUI/#files    download freesimplegui-5.1.1.tar.gz 
	Extract and copy the FreeSimpleGUI folder into the folder containing the sdguitest.py script.
	Installation of FreeSimpleGUI is done in this manner (not with pip) on Ubuntu systems
	because python on Ubuntu is an  “externally-managed-environment”
see:
https://askubuntu.com/questions/1465218/pip-error-on-ubuntu-externally-managed-environment-%C3%97-this-environment-is-extern

Script file can be found in example/python/embedded_python/BP/sdguitest.py. 

edit PY_GUI_TEST line for correct location of python script file.

    script_file = "/home/xyz/python_stuff/sdguitest.py"

This program cannot be run from root unless you have played with your systems default settings.
Either copy the program to your BP directory and compile, or compile and catalog global, running from
your user account.

    
