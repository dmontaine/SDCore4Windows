SD, the Multivalue String Database

SD is a multivalue database in the Pr1me Information tradition.  It contains open source code from the Open Source databases openQM and ScarletDME and open source code developed by the SD developers after the fork from ScarletDME.  While it shares many of the same features, it was forked to explore some new ideas as to what a modern multivalue database should contain.

SD is 64 bit only and runs only on Linux.  Releases are tested on Debian, Ubuntu, Mint, CachyOS, Fedora and OpenSUSE. The installer has also installed the database successfully on Ubuntu running under the Windows Subsystem for Linux, and Ubuntu on the Raspberry Pi 5.

SD should cohabit peacefully with existing openQM and ScarletDME installations as it creates and uses a System V shared memory segment that will not conflict with OpenQM or ScarletDME.

The current version of the SD repository contains no binary bits.  All features are available for auditing.  Binary files are only created during the install.

To install on one of the supported systems, use the installsd.sh script found at https://codeberg.org/stringdatabase/sd-scripts/archive/refs/heads/main.zip or, if git is installed on your computer enter in a terminal session - "git clone https://codeberg.org/stringdatabase/sd-scripts", cd to the newly created sd-scripts directory, enter - "chmod 774 *.sh", and then run the installsd.sh script.

To install SD, just download and extract the scripts, make the scripts executable if needed and then run installsd.sh. The installer will handle installation of required packages, downloading and compiling of source, installation of SD into the proper directories and deletion of the temporary files. 

See the sd64/sdsys/changelog file for changes in each version release.
