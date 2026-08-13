* SDPYFUNC.H
* SD Python Functions  
* Copyright (c)2025 The SD Developers, All Rights Reserved
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 3, or (at your option)
* any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software Foundation,
* Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*
* START-HISTORY:
* rev 0.9-2 Apr 25 mab 
* END-HISTORY
*
* START-DESCRIPTION:
*
* END-DESCRIPTION
*
* START-CODE
deffun PY_INITIALIZE() calling '!PY_INITIALIZE'
deffun PY_IS_INITIALIZED() calling '!PY_IS_INITIALIZED'
deffun PY_FINALIZE() calling '!PY_FINALIZE'
deffun PY_GETATTR(objname) calling '!PY_GETATTR'
deffun PY_RUNFILE(py_script_file) calling '!PY_RUNFILE'
deffun PY_RUNSTRING(py_script) calling '!PY_RUNSTRING'
deffun PY_OBJTYPE(objname) calling '!PY_OBJTYPE'
deffun PY_OBJLEN(objname) calling '!PY_OBJLEN'
*
deffun PY_CREATEDICT(dictname) calling '!PY_CREATEDICT'
deffun PY_CLEARDICT(dictname) calling '!PY_CLEARDICT'
deffun PY_DICTVALGETS(dictname,key) calling '!PY_DICTVALGETS'
deffun PY_DICTVALSETS(dictname,key,value) calling '!PY_DICTVALSETS'
deffun PY_DICTIDEL(dictname,key) calling '!PY_DICTIDEL'
deffun PY_DICTGETKEYS(dictname) calling '!PY_DICTGETKEYS'
deffun PY_DICTGETVALUES(dictname) calling '!PY_DICTGETVALUES'
*
deffun PY_STRSET(strname,value) calling '!PY_STRSET'
deffun PY_STRGET(strname) calling '!PY_STRGET'
*
deffun PY_LISTAPPD(listname,objname) calling '!PY_LISTAPPD'
deffun PY_LISTGETS(listname) calling '!PY_LISTGETS'
deffun PY_LISTCLR(listname) calling '!PY_LISTCLR'
*
