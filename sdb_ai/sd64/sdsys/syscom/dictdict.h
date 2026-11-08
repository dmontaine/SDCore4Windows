* DICTDICT.H
* Dictionary file layout keys
* Copyright (c) 2004, Ladybridge Systems, All Rights Reserved

$define DICT.TYPE            1  ;* C, D, I, PH, X
$define DICT.LOC             2  ;* Field number for D type items
$define DICT.ITYPE.SOURCE    2  ;* Expression for C and I type items
$define DICT.CONV            3  ;* Conversion code (optional)
$define DICT.DISPLAY.NAME    4  ;* Report column heading (optional)
$define DICT.FORMAT          5  ;* Report format specification
$define DICT.S.M             6  ;* Single/Multivalued
$define DICT.ASSOC           7  ;* Association name (optional)
$define DICT.USER            8  ;* For user use - Not processed by SD
* Fields 9 - 14 are not currently assigned but should not be used by users
* as they may be assigned in future releases.
$define DICT.SYS.INFO       15  ;* For internal use by SD
$define DICT.ITYPE.OBJECT   16  ;* Compiled I-type code (multiple fields)

* 31 Oct 26: the A and S type dictionary layouts (DICT.A.LOC, DICT.A.CORRELATIVE and the rest) are gone with the types.
