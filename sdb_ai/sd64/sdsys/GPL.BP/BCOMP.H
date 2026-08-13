* BCOMP.H
* Basic compiler tokens.
* Copyright (c) 2004 Ladybridge Systems, All Rights Reserved
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
* 
* START-HISTORY:
* 19 Jan 04  0.6.1 SD launch. Earlier history details suppressed.
* END-HISTORY
*
* START-DESCRIPTION:
*
* END-DESCRIPTION
*
* START-CODE

* Bit settings for compiler.flags argument to $BCOMP

$define BCOMP.RECURSIVE.BACKUP  1  ;* Set after pcode has been backed up
$define BCOMP.DEBUG             2  ;* Compile in debug mode
$define BCOMP.NO.XREF.TABLES    4  ;* Suppress cross-reference tables
$define BCOMP.LIST.XREF         8  ;* Cross-references in listing file?
$define BCOMP.LISTING          16  ;* Generate listing record?
$define BCOMP.WARN.AS.ERROR    32  ;* Warnings treated as errors

* END-CODE
