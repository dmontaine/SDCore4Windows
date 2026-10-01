@echo off
rem sd-full.cmd - start SD Core for Windows, the full product, by name.
rem
rem 01 Oct 26 - THE OWNER'S COMMAND NAMES.  "sd" and "sd-full" start the full
rem product when it and SD Core Solo are both installed; "sd-solo" starts Solo;
rem with only one of them installed, "sd" starts that one.
rem
rem This is a second name for the sd.exe BESIDE THIS FILE, so it cannot reach
rem another product's install.  Plain "sd" is not decided here: it is whichever
rem sd.exe comes first on the PATH, and this product is on the system PATH,
rem which Windows searches before the user's one (Solo's).  It is a text file
rem and not a copy of the program on purpose: this repository ships no binary,
rem and a second sd.exe would be a second thing for the installer to keep current.
"%~dp0sd.exe" %*
exit /b %ERRORLEVEL%
