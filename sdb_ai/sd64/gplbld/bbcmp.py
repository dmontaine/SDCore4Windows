#
# bbcmp.py - BootStrap Basic Compiler 
# command line: bbcmp.py sdsys sfp binfp
# eg sudo python3 bbcmp.py /usr/local/sdsys GPL.BP/BBPROC GPL.BP.OUT/BBPROC
# note - need root privilege to 
# sdsys - path to sdsys, most likely "/usr/local/sdsys"
# sfp -   directory and file name of source, appended to sdsys to resolve full path
#         ie) GPL.BP/BCOMP for BCOMP source
# binfn - directory and file name of pcode object file, appended to sdsys to resolve full path
#         ie) GPL.BP.OUT/BCOMP.OUT
# If $catlog directive found in source  bbcmp will also write the pcode object file to the global catalog file
#         ie) for BCOMP,  $catalog $BCOMP is found in source.  bbcmp will write the pcode object file to
#         sdsys/gcat/$BCOMP
#        
# Used for initial install only!
# The intent is to create a stripped down basic compiler to generate the
# pcode files to get the system up and running.
#
#   - conditional compile $ifdef $ifndef - not supported
#   - EQUATE - not supported (simple version support could be added, treat like $define)
#   - DEFFUN - not supported at this time, tbd
#   - Nested $include files - not supported
#   - voc $BASIC.OPTIONS - not supported
#   - ONLY compiler directives $DEFINE and $INCLUDE are supported
#   - See "handlers for intrinsic functions" to determine if  a function is supported or not
#   - OBJECTS - not supported
#   - no $MODE compiler directives (running as native qm)
#
# bbcmp.py maybe slow and ungly, but the intended use is to do away with "binary" files
#   in the GitHub repository........
#
# The assumption is we need at a minimum:
# CPROC LOGIN BASIC BCOMP PTERM CATALOG
# Along with certain of the recursive programs - tbd
#   --or--
# Create a stripped down command processor (see APISRVR)
# That basically calls BCOMP to compile 
# CPROC LOGIN BASIC BCOMP PTERM CATALOG
# Along with certain of the recursive programs - tbd
# Requires a special startup of SD that does not load the pcode file (does not exist yet)
#   sudo sd -b for bootstrap ?????
#
# Notes - using dictionarys to replace btree
#       - lists for dynamic arrays
#       - object created as bytearray
#       - max object file CODE_SIZE = 128000 should be enough for what we need to do
#       - using python array module to speed up integer arrays
#
# It appears BCOMP processes include files recursively, allowing a 10 deep layer.
#  This most likely is due to program size restrictions on earlier versions of QM or
#   Give the abiltiy to produce program listings with the include files broken out?
# Regardless, plan where is to:
# Pass 1:
#   Create a program source file (python list) with all include files "included"
#   bbcmp DOES NOT support nested includes.  I don't need it for the programs we plan process!
#   This pass also re joins lines with the continuation line marker (~)
#   This pass also rejects source with pre processor commands $IFDEF, $IFNDEF
#     At this time bbcmp does not support conditional compile
#     This is an issue with opcodes.h as supplied by Ladybridge Systems (there is $IFDEF)
#     But if you regenerate opcodes.h with OPGEN, this is not included, nor can I find any reference to the
#     use of simple.modes or  secondary.modes in the source.  For our purpose we will just remove from opcodes.h
#   Also remove any trailing blank lines for source
# Pass 2:
#   Store all define symbols and values as a dictionary item in defines dictionary
#   remove $define line (or just don't add to source)
#   
# Pass 3:
#   compile the program
#
# Other design notes:
#
#  Unfortunately BCOMP makes (extreme) use of gotos.  
#  There are moudles (subs?) with multiple entry points used by gosubs
#  Breaking this down to a python function is going to be difficult to say the least.
#  One of the main uses is for error processing.  In order to keep it simple, bbcmp will simply abort when it hits
#    an error condition,  via the function error() (hopefully with enough info to point you to the problem).
#  Remember bbcmp.py is NOT intended to be used for development.  It's intent is to boot strap build a system without an original 
#    op code binary
#
#  Testing:
#  The intent is to create p-code object files that are binary identical to what BCOMP produces with the NOXREF option (bbcmp does not create the xref maps).
#  The only difference between a bbcmp.py processed source and a BCOMP should be the time date stamp of the compile.
#  Currently comparing binaries with program vbindiff
#  Also note during the development phase the source code file processed is hardcoded to:
#   /usr/local/sdsys/BP/BTEST
#  And the output p-code object is written to:
#   /usr/local/sdsys/BP.OUT/PTEST
#  Run the object with RUN BP PTEST
#  
#  Once bbcmp.py can compile BCOMP, the plan is to add argument line parsing
#
# 
#
# Based on: 
# BCOMP
# BASIC compiler
# Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
# 
# 
# START-HISTORY:
# 19 Jan 04  0.6.1 SD launch. Earlier history details suppressed.
# END-HISTORY
#
#
# START-DESCRIPTION:
#
# Note for GPL developers:
# This compiler uses a simple single pass approach. No doubt a clever compiler
# could produce better code but it just didn't seem worth the effort and
# experiment suggests that fancy optimisation doesn't produce the benefits
# that it does with languages where opcodes are simple actions.
# The only horrible bit is the resolution of the syntactic ambiguity of the
# < and > characters. We have been unable to find any written specification
# that sets out how these should be processed but our implementation works
# for every real program that we have tried.
#
# Adding new statements requires an entry in the STATEMENTS list and a
# corresponding entry in the ON GOSUB that uses this list.
#
# Adding a new intrinsic function requires entries in the INTRINSICS and
# INTRINSIC.OPCODES lists and a corresponding entry in that ON GOSUB.
#
# New opcodes should be defined in the C opcodes.h include file. The equivalent
# SDBasic include record is generated using the OPGEN program.
#
# The compiler uses a few internal features of SD, especially the binary tree
# variable type. We kept this type private because it is a bit weird to use
# and we thought it highly likely that we would change its implementation
# from time to time.
#
#
# Hidden variable names:
# _xxx        Direct call to subroutine xxx
# ~xxx        {xxx} object code
# __n         Temporary variable n (n is numeric)
# __name      File variable for file opened using FILE statement
# *n          Argument n to object routine. These will always end up as local
#             variables 0 upwards but must be in the symbol table
#             for the compiler to function correctly.
# *VARS       Pseudo-common for persistent variable array in object.
#
# Other special name formats:
# sss:xxx     Local variable xxx for LOCAL SUB sss
#
# Internally generated label names:
# *n          Get/Set/method routine n
#
# Defined token table
   # Data part of element is:
   #    string : 0ssssss
   #    number : 1nnnnnn
   #    matref : 2name index1 index2
   #    char(n): 3n
   #    var    : 4name
   #    @var   : 5name (excluding @ character)
   #    dfield : 6name fieldno subno valueno (dynamic var ref) gdw001
   # defined.tokens = btree(1, btree.keys) 
   # label.tree = btree(1, btree.keys)
#
# END-DESCRIPTION
#
# START-CODE
import array  
import sys
import struct
import os
import datetime
import shutil 

debug_jumps = 4   # used in set_label to dump jump chain
debug_detail = 3  # print the debug info to terminal
debug_log = 2     # log to a file
no_debug = 0
debugging = no_debug # all important debug flag

#include "tokens.h"
TKN_END     =  0           ##/* MUST BE ZERO (Assumed by compiler) */
TKN_NAME    =  1  
TKN_NUM     =  2  
TKN_LABEL   =  3  
TKN_STRING  =  4  
TKN_LSQBR   =  5  
TKN_RSQBR   =  6  
TKN_LBR     =  7  
TKN_RBR     =  8  
# The tokens below don't really exist but are used in the compiler to handle
# special cases. They must be less than TKN_HIGH.OPERATOR so that there is an
# entry in the compiler operator tables for them.
#

TKN_FIELD_REF =   9 # < symbol identified as a field reference
TKN_COMMA    =  10 # Comma may be used in field reference
TKN_FMT      =  11 # SMA format expression
TKN_LOW_OPERATOR = 12
TKN_LT      =  12  # <
TKN_LTX     =  13  # LT
TKN_GT      =  14  # >
TKN_GTX     =  15  # GT
TKN_EQ      =  16  # =     EQ
TKN_NE      =  17  # #     <>     NE
TKN_NEX     =  18  # ><
TKN_LE      =  19  # <=    =<     #>     LE
TKN_GE      =  20  # >=
TKN_GEX     =  21  # =>     #<     GE
TKN_AND     =  22  # &     AND
TKN_OR      =  23  # !     OR
TKN_PLUS    =  24  # +
TKN_MINUS   =  25  # -
TKN_DIV     =  26  # /
TKN_IDIV    =  27  # /
TKN_MULT    =  28  # *
TKN_PWR     =  29  # **    ^
TKN_COLON   =  30  # :     CAT
TKN_MATCHES =  31  # MATCHES
TKN_HIGH_OPERATOR = 31
TKN_ADDEQ     = 32
TKN_SUBEQ     = 33
TKN_SEMICOLON = 34
TKN_NAME_LBR  = 35
TKN_CATEQ     = 36
TKN_DOLLAR    = 37
TKN_AT        = 38
TKN_UNDERSCORE= 39
TKN_MULTEQ    = 40
TKN_DIVEQ     = 41
TKN_FLOAT     = 42
TKN_AT_NAME   = 43     # @ followed by letter with no intervening space
TKN_LCBR      = 44  # {
TKN_RCBR      = 45  # }
TKN_HEXNUM    = 46  # Hexadecimal number
TKN_OBJREF    = 47  # -> (Object reference)
TKN_UNCLOSED  = 62  # Unclosed string
TKN_UNKNOWN   = 63
TKN_END_FIELD = 99  # Pseudo-token for ">" of dynamic array reference


#
#  N O T E - init_tokens needs to be sized to compile the largest program we expect bbcomp to compile
#            I know we could play games with resizing (allocate and copy) as we go along, but not doing it.
INIT_TOKENS = 400          # Initial size of token tables (tokens per line)

   #dim btree.keys(1)
   
op = array.array('i',(0 for i in range(0,TKN_HIGH_OPERATOR+1)))           # Operator token / opcodes relationship
op_priority = array.array('i',(0 for i in range(0,TKN_HIGH_OPERATOR+1)))  # Operator priorities.  Operators with
                                                                          # low priority values are applied first.
                                                                          # Values are (N * 10) + 1 where N is the
                                                                          # priority as shown in the user
                                                                          # documentation.  The + 1 is used to
                                                                          # allow the ** operator to be treated
                                                                          # as a special case in EXPR.
                                                            # ! ! !  N O T E these lists setup in init_stuff():
                                       
#define int_stack  (init_tokens / 2)      # Worst possible case (may resize later)
# expression processing stuff 
# With most of the conversions of "stack" structures we went from dynamic arrays in BCOMP to lists in bbcmp
# But with the following two (operator and priority) there is an inter dependance of one on the other
# To simplify things we are going to use arrays, and to further simply things we are going to treat them as 1 based (just ignore element 0)
operator_stack = array.array('i',(0 for i in range(0,INIT_TOKENS)))        # Infix - postfix operator stack...
op_stack_depth = 0 # pointer into operator_stack, treat as 1 based to keep  inc / dec  lodgic the same
priority_stack = array.array('i',(0 for i in range(0,INIT_TOKENS)))       # ...and associated priority stack
unary_minus = False
STACK_MARK =   9999                     #  Marks start of sub-expression
priority_stack[0] = STACK_MARK
format_allowed_stack = []               # use to stack format_qualifier_allowed flags (T/F)
#/* ===============================================================================================================================  */
# vars used in function comp, all global
# source parsing
    #
    # tokens        - list of token_types parsed from source line
    # token_strings - corresponding list of text string of the token
    # num_tokens    - current number of tokens in the above lists
    #  a note worth mentioning here: BCOMP allows for the token arrays to grow, Not doing it here
    #  if we max out (INIT_TOKENS defined as 100), we bomb out.
    #  just upsize INIT_TOKENS and there by the array lists that use INIT_TOKENS.
    #  token_index   - index into lists of the token being process, points to the "look_ahead_token".  rem theses are global, accessed all thoughout bbcmp
    #                  incremented in get_token
    # look_ahead_token - token type of look ahead token 
    # look_ahead_token_string - as above but the actual string text of the token

tokens = array.array('i',(TKN_END for i in range(0,INIT_TOKENS)))
token_strings = []
defined_tokens ={}    # all important $define tokens dictionary, value is a list [value, type] Upper Cased!!
# where type is:
is_string = 0
is_number = 1
is_charfunct = 3

#
num_tokens = 0
token = -1          # current token (numeric id) being processed in compile process
token_string = ''   # current token text name of above
u_token_string = '' # upper case version of above
look_ahead_token = -1
look_ahead_token_string = ''
u_look_ahead_token_string = ''

label_dict = {}     # label dictionary to mimic btree label.tree key = label name, value is object_code location marked by label
label_name = ''     # label name text for current label being processed jump processing


MAX_FILE_PATH =  256


gtlog = []

# Compiler control

name_set = False             # Not seen PROGRAM or SUBROUTINE
recursive = False
catalog_name = ''            # value found on $catalog directive
greatest_call_arg_count = 0
final_end_seen = False

is_local_function = False 
format_qualifier_allowed = False 
ifr_index = 0 
# note we do not support objects, object_state will always be zero
object_state = 0    # 0 = Not an object
                    # 1 = Is object. First Get/Set/Public still to be found
                    # 2 = Is object but not in property/method routine
                    # 3 = In Get routine / public function
                    # 4 = In Set routine / public subroutine
                    # 5 = In public function
                    # 6 = In public subroutine


gbl_src_ln_cnt = 0         # current soource line (from ..pass2 file) being processed
# code generation control
CODE_SIZE = 128000    # Note in BCOMP code size can expand, in bbcomp this will not be the case, size for worst case!
                      # currently BCOMP comes in at the largest (87KB)
                          
code_image = bytearray(CODE_SIZE)   # code_image is a byte array Creates an array of CODE_SIZE, all initialized to null 
opcode_byte = code_image[0]         # op code output to code_image   
start_pc =0                # appears to be the start of actual op codes (after all common is setup) 
pc = 0                     # offsets into code_image for location of next byte to "write"  Program Counter??   
statement_start_pc = 0     # not sure purpose, tbd
end_source = False         # read end source file    

# these next 3 lists are used by back_end()  -  Common paths for ON ERROR / LOCKED / THEN / ELSE clauses
onerror_stack = []
testlock_stack = []
thenelse_stack = []
lock_opcode = 0




#  * Symbol table (local variables and common block entries)
# symbols = ''   # Names dyn array in BCOMP used to find symbol entry in symbol.info 
#                we use a dictionary for symbol_info so not necessary in bbcmp.py
symbol_info = {}  # value will be a list [v1,v2,v3,v4]
                     # V1 : Local variable number
                     #      -ve for matrix until first referenced
                     # V2 : Common offset (-ve if local)
                     # V3 : Dimensions (0, 1 or 2. -1 if not known)
                     # V4 = Value index into COMMONS for common variable
# I think the following is used for checking if a defined variable is actually used,
# Not sure we need it, tbd
symbol_refs = {}     # Associated keys to various routines... dyn array in bcomp
                     # here it is a dictionary, value is a list [V1,V2,V3,V4] as defined below
SYM_CHK =  0 # Just checking, don't record reference (must be 0)
SYM_SET = 1 # V1 : Line set
SYM_USE = 2 # V2 : Line used
SYM_ARG = 3 # V3 : Line used as subroutine argument
SYM_DIM = 4 # V4 : Line dimensioned
symbol_mode = SYM_USE
#
# vars used / set  in find_var() & make_var() ?
symbol_name = ''
saved_symbol_mode = '' 
symbol_var_no = 0
symbol_dim = 0
symbol_common_offset = -1    # init to local var, BCOMP does not do this, but we need something for Global vars
symbol_common_index = 0

symbol_table = []  # Ordered version for emission to object code
matrix_stack = []  # Used to handle nested array references

# Common block table (block names and sizes)
# in bcomp its a dyn array with F1 holding name                  0  1   2    3    4   5  6  7  
# in bbcmp its a dictionary with key = name and value = list of [F2,F3,[F4],[F5],[F6],F7,F8,F9]
# we also have common_idx, a list of common names with newest assigned appended to the end
# We use this to replace common.index (used by BCOMP when finding  relevant common data in dyn array)
# BCOMP also uses common.index when setting labels (set.label) and jumps (emit.addr) for the relevant 
# common block.  Because we want out opcode image to match what BCOMP produces, we must mimic this behavior 
common_idx = []                                                               
commons = {}                       # F1 = Names (Blank common is //) actually '$'  ??
                                   # F2 = Local variable number for common
                                   # F3 = Current size
                                   # F4 = Element names (list) names of vars in this common block
                                   # F5 = Matrix rows   (list) (zero if scalar) 
                                   # F6 = Matrix cols   (list) (zero if not 2 dims)
                                   # F7 = Pick matrix local var no, else null (always null, not supported)
                                   # F8 = VARSET arg? (true/null)   (always null, not supported)
                                   # F9 = Leave uninitialised? (true/null)
                                  

# vars set by st_local (local subroutine / function)
lsub_var_no = -1
lsub_name = ''

jump_no = 0          # Next available jump number
jump_stack = []      # Nested construct stack list of lists [v1,v2,v3]
# V1 : Type  (must not use zero - see st.while)
J_LOOP =  1  # LOOP / REPEAT
J_FOR  =  2  # FOR / NEXT
J_BACK_END =  3  # ON ERROR / LOCKED / THEN / ELSE
J_CASE =  4  # CASE
J_IF   =  5  # IF / THEN / ELSE
J_IF_EXPR =  6  # IF / THEN / ELSE in expression
J_TXN     =  7  # TRANSACTION
# V2 : Jump number
# V3 : Element number for CASE

#* Function table dyn array in bcomp, dictionary in bbcmp
# appears that this data is created when processing a  DEFFUN statement
# It d
#
functions = {}      # key  = function name value is list [v0,v1,v2,v3]
#                    # v0 = (F2) call name, null for local function
#                    # v1 = (F3)arg types (S or M, scalar/matrix)
#                    # v2 = (F4) function key
#                    # v3 = (F5)var args?
#
# not sure how stack is used, need to investigate
func_stack = [] 

# Internal subroutine tables looks like BCOMP does insert before <1> on all three of these

int_subs = []        # list of sub names  ;* Names, FM separated...
int_sub_args = []    # list of ->  ;* ...arg types (S or M, scalar/matrix)...
int_sub_is_lsub = [] # list of ->  ;* ...Seen as local subroutine/function?
int_sub_call_args = [] # need global for st_gosub , and process_int_sub_args()

# Direct call table

direct_calls = []     #   ;* Subroutine names and...
direct_call_vars = {} #   ;* ...local variable number key is sub name value is local var number

arg_count_stack = []  # stack used by get_args

for_var = []  # list (stack) of for do token indexes [symbol_name,token_index, token_index] 
              # Saves position of current control value (symbol_name) in the token list

# Release 2.1-10 introduced the STORSYS opcode so that CLEAR did not
# wipe out CALL indirection variables for direct calls. Because this is
# not backwards compatible, only use STORSYS if CLEAR is used in the
# program. Otherwise, stay with the old STOR.

clear_used = False

#
# Object header information

program_name = ''                 # set by main as basename of file to compile path?
subr_arg_count = 0                # Subroutine arguments
var_count = 0                     # Number of local variables
symbol_table_offset = 0           # Symbol table position
line_table_offset = 0             # Line table position


# Common block table (block names and sizes)

#   commons = ""                   ;* F1 = Names (Blank common is //)
#                                   * F2 = Local variable number for common
#                                   * F3 = Current size
#                                   * F4 = Element names (subvalued)
#                                   * F5 = Matrix rows (zero if scalar)
#                                   * F6 = Matrix cols (zero if not 2 dims)
#                                   * F7 = Pick matrix local var no, else null
#                                   * F8 = VARSET arg? (true/null)
#                                   * F9 = Leave uninitialised? (true/null)
# create common list item references 
COM_F2 = 0
COM_F3 = 1
COM_F4 = 2
COM_F5 = 3
COM_F6 = 4
COM_F7 = 5
COM_F8 = 6
COM_F9 = 7
commons = {}    # dictionary with key = common name values list of [f2 - f9] as defined above

# TOKEN_TABLE as defined in op_str3.c
# Note in op_rmvtkn() TOKEN_TABLE is an array of charactes from space to del.
# The upper level bits contain flags COPY_CHAR and DONE_AFTER
# Here we mimic this in our table as a list of lists.
#
COPY_CHAR = 1
DONE_AFTER = 1

TOKEN_TABLE = [
    [TKN_UNKNOWN , 0 , 0],                  # Space 
    [TKN_OR , COPY_CHAR , DONE_AFTER],      #  ! 
    [TKN_STRING , 0 , 0],                   #  " 
    [TKN_NE , COPY_CHAR , DONE_AFTER],      #  # 
    [TKN_DOLLAR , COPY_CHAR , DONE_AFTER],  #  $ 
    [TKN_UNKNOWN , 0 , DONE_AFTER],         #  % 
    [TKN_AND , COPY_CHAR , DONE_AFTER],     #  & 
    [TKN_STRING , 0 , 0],                   #  ' 
    [TKN_LBR , COPY_CHAR , DONE_AFTER],     #  ( 
    [TKN_RBR , COPY_CHAR , DONE_AFTER],     #  ) 
    [TKN_MULT , COPY_CHAR , 0],             #  * 
    [TKN_PLUS , COPY_CHAR , 0],             #  + 
    [TKN_COMMA , COPY_CHAR , DONE_AFTER],   #  ],
    [TKN_MINUS , COPY_CHAR , 0],            #  - 
    [TKN_FLOAT , COPY_CHAR , 0],            #  . 
    [TKN_DIV , COPY_CHAR , 0],              #  / 
    [TKN_NUM , COPY_CHAR , 0],              #  0 
    [TKN_NUM , COPY_CHAR , 0],              #  1 
    [TKN_NUM , COPY_CHAR , 0],              #  2 
    [TKN_NUM , COPY_CHAR , 0],              #  3 
    [TKN_NUM , COPY_CHAR , 0],              #  4 
    [TKN_NUM , COPY_CHAR , 0],              #  5 
    [TKN_NUM , COPY_CHAR , 0],              #  6 
    [TKN_NUM , COPY_CHAR , 0],              #  7 
    [TKN_NUM , COPY_CHAR , 0],              #  8 
    [TKN_NUM , COPY_CHAR , 0],              #  9 
    [TKN_COLON , COPY_CHAR , 0],            #  : 
    [TKN_SEMICOLON , COPY_CHAR , DONE_AFTER], #  ; 
    [TKN_LT , COPY_CHAR , 0],               #  < 
    [TKN_EQ , COPY_CHAR , 0],               #  = 
    [TKN_GT , COPY_CHAR , 0],               #  > 
    [TKN_UNKNOWN , 0 , DONE_AFTER],         #  ? 
    [TKN_AT , COPY_CHAR , 0],               #  @ 
    [TKN_NAME , COPY_CHAR , 0],             #  A 
    [TKN_NAME , COPY_CHAR , 0],             #  B 
    [TKN_NAME , COPY_CHAR , 0],             #  C 
    [TKN_NAME , COPY_CHAR , 0],             #  D 
    [TKN_NAME , COPY_CHAR , 0],             #  E 
    [TKN_NAME , COPY_CHAR , 0],             #  F 
    [TKN_NAME , COPY_CHAR , 0],             #  G 
    [TKN_NAME , COPY_CHAR , 0],             #  H 
    [TKN_NAME , COPY_CHAR , 0],             #  I 
    [TKN_NAME , COPY_CHAR , 0],             #  J 
    [TKN_NAME , COPY_CHAR , 0],             #  K 
    [TKN_NAME , COPY_CHAR , 0],             #  L 
    [TKN_NAME , COPY_CHAR , 0],             #  M 
    [TKN_NAME , COPY_CHAR , 0],             #  N 
    [TKN_NAME , COPY_CHAR , 0],             #  O 
    [TKN_NAME , COPY_CHAR , 0],             #  P 
    [TKN_NAME , COPY_CHAR , 0],             #  Q 
    [TKN_NAME , COPY_CHAR , 0],             #  R 
    [TKN_NAME , COPY_CHAR , 0],             #  S 
    [TKN_NAME , COPY_CHAR , 0],             #  T 
    [TKN_NAME , COPY_CHAR , 0],             #  U 
    [TKN_NAME , COPY_CHAR , 0],             #  V 
    [TKN_NAME , COPY_CHAR , 0],             #  W 
    [TKN_NAME , COPY_CHAR , 0],             #  X 
    [TKN_NAME , COPY_CHAR , 0],             #  Y 
    [TKN_NAME , COPY_CHAR , 0],             #  Z 
    [TKN_LSQBR , COPY_CHAR , DONE_AFTER],   #  [ 
    [TKN_STRING , 0 , 0],                   #  \ 
    [TKN_RSQBR , COPY_CHAR , DONE_AFTER],   #  ] 
    [TKN_PWR , COPY_CHAR , DONE_AFTER],     #  ^ 
    [TKN_UNDERSCORE , COPY_CHAR , DONE_AFTER], #  _ 
    [TKN_UNKNOWN , 0 , DONE_AFTER],         #  ` 
    [TKN_NAME , COPY_CHAR , 0],             #  a 
    [TKN_NAME , COPY_CHAR , 0],             #  b 
    [TKN_NAME , COPY_CHAR , 0],             #  c 
    [TKN_NAME , COPY_CHAR , 0],             #  d 
    [TKN_NAME , COPY_CHAR , 0],             #  e 
    [TKN_NAME , COPY_CHAR , 0],             #  f 
    [TKN_NAME , COPY_CHAR , 0],             #  g 
    [TKN_NAME , COPY_CHAR , 0],             #  h 
    [TKN_NAME , COPY_CHAR , 0],             #  i 
    [TKN_NAME , COPY_CHAR , 0],             #  j 
    [TKN_NAME , COPY_CHAR , 0],             #  k 
    [TKN_NAME , COPY_CHAR , 0],             #  l 
    [TKN_NAME , COPY_CHAR , 0],             #  m 
    [TKN_NAME , COPY_CHAR , 0],             #  n 
    [TKN_NAME , COPY_CHAR , 0],             #  o 
    [TKN_NAME , COPY_CHAR , 0],             #  p 
    [TKN_NAME , COPY_CHAR , 0],             #  q 
    [TKN_NAME , COPY_CHAR , 0],             #  r 
    [TKN_NAME , COPY_CHAR , 0],             #  s 
    [TKN_NAME , COPY_CHAR , 0],             #  t 
    [TKN_NAME , COPY_CHAR , 0],             #  u 
    [TKN_NAME , COPY_CHAR , 0],             #  v 
    [TKN_NAME , COPY_CHAR , 0],             #  w 
    [TKN_NAME , COPY_CHAR , 0],             #  x 
    [TKN_NAME , COPY_CHAR , 0],             #  y 
    [TKN_NAME , COPY_CHAR , 0],             #  z 
    [TKN_LCBR , COPY_CHAR , DONE_AFTER],    #  { 
    [TKN_UNKNOWN , 0 , DONE_AFTER],         #  , 
    [TKN_RCBR , COPY_CHAR , DONE_AFTER],    #  } 
    [TKN_UNKNOWN , 0 , DONE_AFTER],         #  ~ 
    [TKN_UNKNOWN , 0 , DONE_AFTER]          #  Del 
]

# our CHAR_TYPES table
CT_ALPHA = 1
CT_DIGIT = 2
#

CHAR_TYPES = [
0,      # 0
0,      # 1
0,      # 2
0,      # 3
0,      # 4
0,      # 5
0,      # 6
0,      # 7
0,      # 8
0,      # 9
0,      # 10
0,      # 11
0,      # 12
0,      # 13
0,      # 14
0,      # 15
0,      # 16
0,      # 17
0,      # 18
0,      # 19
0,      # 20
0,      # 21
0,      # 22
0,      # 23
0,      # 24
0,      # 25
0,      # 26
0,      # 27
0,      # 28
0,      # 29
0,      # 30
0,      # 31
0,      # 32
0,      # 33
0,      # 34
0,      # 35
0,      # 36
0,      # 37
0,      # 38
0,      # 39
0,      # 40
0,      # 41
0,      # 42
0,      # 43
0,      # 44
0,      # 45
0,      # 46
0,      # 47
CT_DIGIT,      # 48 0
CT_DIGIT,      # 49 1
CT_DIGIT,      # 50 2
CT_DIGIT,      # 51 3
CT_DIGIT,      # 52 4
CT_DIGIT,      # 53 5
CT_DIGIT,      # 54 6
CT_DIGIT,      # 55 7
CT_DIGIT,      # 56 8
CT_DIGIT,      # 57 9
0,      # 58
0,      # 59
0,      # 60
0,      # 61
0,      # 62
0,      # 63
0,      # 64
CT_ALPHA,      # 65 A
CT_ALPHA,      # 66 B
CT_ALPHA,      # 67 C
CT_ALPHA,      # 68 D
CT_ALPHA,      # 69 E
CT_ALPHA,      # 70 F
CT_ALPHA,      # 71 G
CT_ALPHA,      # 72 H
CT_ALPHA,      # 73 I
CT_ALPHA,      # 74 J
CT_ALPHA,      # 75 K
CT_ALPHA,      # 76 L
CT_ALPHA,      # 77 M
CT_ALPHA,      # 78 N
CT_ALPHA,      # 79 O
CT_ALPHA,      # 80 P
CT_ALPHA,      # 81 Q
CT_ALPHA,      # 82 R
CT_ALPHA,      # 83 S
CT_ALPHA,      # 84 T
CT_ALPHA,      # 85 U
CT_ALPHA,      # 86 V
CT_ALPHA,      # 87 W
CT_ALPHA,      # 88 X
CT_ALPHA,      # 89 Y
CT_ALPHA,      # 90 Z
0,      # 91
0,      # 92
0,      # 93
0,      # 94
0,      # 95
0,      # 96
CT_ALPHA,      # 97 a
CT_ALPHA,      # 98 b
CT_ALPHA,      # 99 c
CT_ALPHA,      # 100 d
CT_ALPHA,      # 101 e
CT_ALPHA,      # 102 f
CT_ALPHA,      # 103 g
CT_ALPHA,      # 104 h
CT_ALPHA,      # 105 i
CT_ALPHA,      # 106 j
CT_ALPHA,      # 107 k
CT_ALPHA,      # 108 l
CT_ALPHA,      # 109 m
CT_ALPHA,      # 110 n
CT_ALPHA,      # 111 o
CT_ALPHA,      # 112 p
CT_ALPHA,      # 113 q
CT_ALPHA,      # 114 r
CT_ALPHA,      # 115 s
CT_ALPHA,      # 116 t
CT_ALPHA,      # 117 u
CT_ALPHA,      # 118 v
CT_ALPHA,      # 119 w
CT_ALPHA,      # 120 x
CT_ALPHA,      # 121 y
CT_ALPHA,      # 122 z
0,      # 123
0,      # 124
0,      # 125
0,      # 126
0,      # 127
0,      # 128
0,      # 129
0,      # 130
0,      # 131
0,      # 132
0,      # 133
0,      # 134
0,      # 135
0,      # 136
0,      # 137
0,      # 138
0,      # 139
0,      # 140
0,      # 141
0,      # 142
0,      # 143
0,      # 144
0,      # 145
0,      # 146
0,      # 147
0,      # 148
0,      # 149
0,      # 150
0,      # 151
0,      # 152
0,      # 153
0,      # 154
0,      # 155
0,      # 156
0,      # 157
0,      # 158
0,      # 159
0,      # 160
0,      # 161
0,      # 162
0,      # 163
0,      # 164
0,      # 165
0,      # 166
0,      # 167
0,      # 168
0,      # 169
0,      # 170
0,      # 171
0,      # 172
0,      # 173
0,      # 174
0,      # 175
0,      # 176
0,      # 177
0,      # 178
0,      # 179
0,      # 180
0,      # 181
0,      # 182
0,      # 183
0,      # 184
0,      # 185
0,      # 186
0,      # 187
0,      # 188
0,      # 189
0,      # 190
0,      # 191
0,      # 192
0,      # 193
0,      # 194
0,      # 195
0,      # 196
0,      # 197
0,      # 198
0,      # 199
0,      # 200
0,      # 201
0,      # 202
0,      # 203
0,      # 204
0,      # 205
0,      # 206
0,      # 207
0,      # 208
0,      # 209
0,      # 210
0,      # 211
0,      # 212
0,      # 213
0,      # 214
0,      # 215
0,      # 216
0,      # 217
0,      # 218
0,      # 219
0,      # 220
0,      # 221
0,      # 222
0,      # 223
0,      # 224
0,      # 225
0,      # 226
0,      # 227
0,      # 228
0,      # 229
0,      # 230
0,      # 231
0,      # 232
0,      # 233
0,      # 234
0,      # 235
0,      # 236
0,      # 237
0,      # 238
0,      # 239
0,      # 240
0,      # 241
0,      # 242
0,      # 243
0,      # 244
0,      # 245
0,      # 246
0,      # 247
0,      # 248
0,      # 249
0,      # 250
0,      # 251
0,      # 252
0,      # 253
0,      # 254
0,      # 255
]

label_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.%$"

opname_strings = ["CAT", "LT",  "GT", "EQ",    "NE",     "LE",
                                  "GE",  "AND", "OR", "MATCH", "MATCHES"]
opname_codes = [TKN_COLON, TKN_LTX,     TKN_GTX,    TKN_EQ,
                                    TKN_NE,    TKN_LE,      TKN_GEX,    TKN_AND,
                                    TKN_OR,    TKN_MATCHES, TKN_MATCHES]
LONGEST_OPNAME = 7


#include OPCODES_H

MODE_OPCODE_BYTE      =  0
MODE_JUMP_ADDR        =  1
MODE_ONE_BYTE_VALUE   =  2
MODE_FOUR_BYTE_VALUE  =  3
MODE_LOCAL_VAR        =  4
MODE_STRING_VALUE     =  5
MODE_FLOAT_VALUE      =  6
MODE_COMMON_VAR       =  7
MODE_COMMON_DCL       =  8
MODE_DEBUG_REF        =  9
MODE_OPCODE_PREFIX    =  10
MODE_MV_OPCODE        =  11
MODE_ADDR_LIST        =  12
MODE_SHORT_LOCAL      =  13
MODE_PMATDATA         =  14
MODE_TWO_BYTE_VALUE   =  15
MODE_LOCAL_DCL        =  16
MODE_OBJMAP_DATA      =  17
MODE_LONG_STRING_VALUE =  18
OP_STOP        =    0  # 00
OP_ABORT       =    1  # 1
OP_RETURN      =    2  # 2
OP_JMP         =    3  # 3
OP_JPO         =    4  # 4
OP_JPZ         =    5  # 5
OP_JNG         =    6  # 6
OP_JZE         =    7  # 7
OP_JNZ         =    8  # 8
OP_GOSUB       =   10  # A
OP_RETURNTO    =   11  # B
OP_CALL        =   12  # C
OP_ONGOTO      =   13  # D
OP_ONGOSUB     =   14  # E
OP_RUN         =   15  # F
OP_LDSINT      =   16  # 10
OP_LDLINT      =   17  # 11
OP_LDSTR       =   18  # 12
OP_LDNULL      =   19  # 13
OP_LDLCL       =   20  # 14
OP_LDCOM       =   21  # 15
OP_STOR        =   22  # 16
OP_POP         =   23  # 17
OP_DUP         =   24  # 18
OP_LDSLCL      =   25  # 19
OP_LDSYS       =   26  # 1A
OP_LD0         =   27  # 1B
OP_LD1         =   28  # 1C
OP_NULL        =   29  # 1D
OP_EXCH        =   30  # 1E
OP_VALUE       =   31  # 1F
OP_ADD         =   32  # 20
OP_SUB         =   33  # 21
OP_MUL         =   34  # 22
OP_DIV         =   35  # 23
OP_NEG         =   36  # 24
OP_INT         =   37  # 25
OP_INC         =   38  # 26
OP_DEC         =   39  # 27
OP_MOD         =   40  # 28
OP_PWR         =   41  # 29
OP_ABS         =   42  # 2A
OP_REM         =   43  # 2B
OP_LN          =   44  # 2C
OP_EXP         =   45  # 2D
OP_REUSE       =   46  # 2E
OP_IDIV        =   47  # 2F
OP_DSP         =   48  # 30
OP_DSPNL       =   49  # 31
OP_LDUNASS     =   50  # 32
OP_AT          =   51  # 33
OP_PROFF       =   52  # 34
OP_PRON        =   53  # 35
OP_PAGE        =   54  # 36
OP_BREAKCT     =   55  # 37
OP_KEYRDY      =   56  # 38
OP_KEYIN       =   57  # 39
OP_PRINTERR    =   58  # 3A
OP_PROMPT      =   59  # 3B
OP_GETPROMPT   =   60  # 3C
OP_KEYINC      =   61  # 3D
OP_BREAK       =   62  # 3E
OP_LOCATE      =   63  # 3F
OP_LEN         =   64  # 40
OP_SUBSTR      =   65  # 41
OP_SUBSTRE     =   66  # 42
OP_CAT         =   67  # 43
OP_REMOVE      =   68  # 44
OP_CHAR        =   69  # 45
OP_SEQ         =   70  # 46
OP_EXTRACT     =   71  # 47
OP_REPLACE     =   72  # 48
OP_INS         =   73  # 49
OP_DEL         =   74  # 4A
OP_LOCATES     =   75  # 4B
OP_SPACE       =   76  # 4C
OP_STR         =   77  # 4D
OP_DNCASE      =   78  # 4E
OP_UPCASE      =   79  # 4F
OP_RMVTKN      =   80  # 50
OP_INSERT      =   81  # 51
OP_FIELD       =   82  # 52
OP_COL1        =   83  # 53
OP_COL2        =   84  # 54
OP_FLDSTOR     =   85  # 55
OP_FMT         =   86  # 56
OP_ICONV       =   87  # 57
OP_OCONV       =   88  # 58
OP_SUBSTRA     =   89  # 59
OP_TRIM        =   90  # 5A
OP_TRIMF       =   91  # 5B
OP_TRIMB       =   92  # 5C
OP_COUNT       =   93  # 5D
OP_DCOUNT      =   94  # 5E
OP_INDEX       =   95  # 5F
OP_EQ          =   96  # 60
OP_NE          =   97  # 61
OP_GT          =   98  # 62
OP_LT          =   99  # 63
OP_NOT         =  100  # 64
OP_AND         =  101  # 65
OP_OR          =  102  # 66
OP_BITAND      =  103  # 67
OP_BITOR       =  104  # 68
OP_BITNOT      =  105  # 69
OP_GE          =  106  # 6A
OP_LE          =  107  # 6B
OP_SHIFT       =  108  # 6C
OP_BITXOR      =  109  # 6D
OP_BITSET      =  110  # 6E
OP_BITRESET    =  111  # 6F
OP_OPEN        =  112  # 70
OP_READ        =  113  # 71
OP_READV       =  114  # 72
OP_WRITEV      =  115  # 73
OP_DELETE      =  116  # 74
OP_WRITE       =  117  # 75
OP_CLOSE       =  118  # 76
OP_QUOTIENT    =  119  # 77
OP_FORLOOPS    =  120  # 78
OP_FOR1S       =  121  # 79
OP_KEYINR      =  122  # 7A
OP_OPENPATH    =  123  # 7B
OP_SYSDIR      =  124  # 7C
OP_KEYINT      =  125  # 7D
OP_KEYINCT     =  126  # 7E
OP_TRANS       =  127  # 7F
OP_DIMLCL      =  128  # 80
OP_DIMCOM      =  129  # 81
OP_INDX1       =  130  # 82
OP_INDX2       =  131  # 83
OP_INMAT       =  132  # 84
OP_INMATA      =  133  # 85
OP_KEYINRT     =  134  # 86
OP_MATCOPY     =  135  # 87
OP_MATFILL     =  136  # 88
OP_MATPARSE    =  137  # 89
OP_MATBUILD    =  138  # 8A
OP_DELCOM      =  139  # 8B
OP_MATREAD     =  140  # 8C
OP_GETREM      =  141  # 8D
OP_SETREM      =  142  # 8E
OP_COMMON      =  143  # 8F
OP_STATUS      =  144  # 90
OP_ONERROR     =  145  # 91
OP_NOWAIT      =  146  # 92
OP_SETMODE     =  147  # 93
OP_CLRMODE     =  148  # 94
OP_SETSTAT     =  149  # 95
OP_SWAP        =  150  # 96
OP_FOLD3       =  151  # 97
OP_FILEINFO    =  152  # 98
OP_OSPATH      =  153  # 99
OP_TIME        =  154  # 9A
OP_DATE        =  155  # 9B
OP_TIMEDATE    =  156  # 9C
OP_EXECUTE     =  157  # 9D
OP_ITYPE       =  159  # 9F
OP_ALPHA       =  160  # A0
OP_NUM         =  161  # A1
OP_APPEND      =  162  # A2
OP_TRIMX       =  163  # A3
OP_SOUNDEX     =  164  # A4
OP_MATCHES     =  165  # A5
OP_RAISE       =  166  # A6
OP_LOWER       =  167  # A7
OP_SUM         =  168  # A8
OP_CONVERT     =  169  # A9
OP_FCONVERT    =  170  # AA
OP_COMPARE     =  171  # AB
OP_FLDSTORF    =  172  # AC
OP_MATCHFLD    =  173  # AD
OP_QUOTE       =  174  # AE
OP_RMVF        =  175  # AF
OP_SELECT      =  176  # B0
OP_CLEARSEL    =  177  # B1
OP_CLEARALL    =  178  # B2
OP_SLCTINFO    =  179  # B3
OP_READNEXT    =  180  # B4
OP_RDNXEXP     =  181  # B5
OP_RDNXPOS     =  182  # B6
OP_SSELECT     =  183  # B7
OP_FORMLIST    =  184  # B8
OP_READLIST    =  185  # B9
OP_SYSMSG      =  186  # BA
OP_JFALSE      =  190  # BE
OP_JTRUE       =  191  # BF
OP_ACOS        =  192  # C0
OP_ASIN        =  193  # C1
OP_ATAN        =  194  # C2
OP_COS         =  195  # C3
OP_SIN         =  196  # C4
OP_TAN         =  197  # C5
OP_SQRT        =  198  # C6
OP_RND         =  199  # C7
OP_LDFLOAT     =  200  # C8
OP_REP         =  201  # C9
OP_STZ         =  202  # CA
OP_STNULL      =  203  # CB
OP_LDSYSV      =  204  # CC
OP_UNASS       =  205  # CD
OP_BITTEST     =  206  # CE
OP_PREFIX      =  207  # CF
OP_FORINIT     =  208  # D0
OP_FORLOOP     =  209  # D1
OP_FOR1        =  210  # D2
OP_SLEEP       =  211  # D3
OP_CLRFILE     =  212  # D4
OP_QUIT        =  213  # D5
OP_LOCK        =  214  # D6
OP_UNLOCK      =  215  # D7
OP_RELEASE     =  216  # D8
OP_RECLCKD     =  217  # D9
OP_FILELOCK    =  218  # DA
OP_FLUNLOCK    =  219  # DB
OP_LOCKREC     =  220  # DC
OP_RLSALL      =  221  # DD
OP_GETLOCKS    =  222  # DE
OP_FOLD        =  223  # DF
OP_SAVESCRN    =  224  # E0
OP_RSTSCRN     =  225  # E1
OP_TRACE       =  226  # E2
OP_PRECISION   =  227  # E3
OP_CHKCAT      =  228  # E4
OP_CLEAR       =  229  # E5
OP_CLRCOM      =  230  # E6
OP_CHAIN       =  231  # E7
OP_ULOCK       =  232  # E8
OP_LLOCK       =  233  # E9
OP_MVD         =  234  # EA
OP_MVDS        =  235  # EB
OP_MVDSS       =  236  # EC
OP_MVDSSS      =  237  # ED
OP_ASS         =  238  # EE
OP_MVDD        =  239  # EF
OP_CLRINPUT    =  240  # F0
OP_HUSH        =  241  # F1
OP_DATA        =  242  # F2
OP_TESTLOCK    =  243  # F3
OP_HEADING     =  244  # F4
OP_FOOTING     =  245  # F5
OP_PRNT        =  246  # F6
OP_PRNL        =  247  # F7
OP_PSET        =  248  # F8
OP_PRCLOSE     =  249  # F9
OP_PRFILE      =  250  # FA
OP_SH          =  251  # FB
OP_DEBUG       =  252  # FC
OP_DBGINF      =  253  # FD
OP_DBGBRK      =  254  # FE
OP_KERNEL      =  255  # FF
# Secondary opcodes, prefix CF (PREFIX)
OP_PABORT    =  52992  # CF00
OP_NAP       =  52993  # CF01
OP_TOTAL     =  52994  # CF02
OP_IFS       =  52995  # CF03
OP_SETNLS    =  52996  # CF04
OP_GETNLS    =  52997  # CF05
OP_ITYPE2    =  52998  # CF06
OP_CALLV     =  52999  # CF07
OP_ABORTMSG  =  53000  # CF08
OP_PWCRYPT   =  53001  # CF09
OP_LOGIN     =  53002  # CF0A
OP_UMASK     =  53003  # CF0B
OP_TERMINFO  =  53004  # CF0C
OP_KEYCODE   =  53005  # CF0D
OP_ERRMSG    =  53006  # CF0E
OP_VARTYPE   =  53007  # CF0F
OP_CROP      =  53008  # CF10
OP_FIND      =  53009  # CF11
OP_CHANGE    =  53010  # CF12
OP_VSLICE    =  53011  # CF13
OP_FINDSTR   =  53012  # CF14
OP_SUBSTRNG  =  53013  # CF15
OP_SWAPCASE  =  53014  # CF16
OP_REPADD    =  53015  # CF17
OP_REPSUB    =  53016  # CF18
OP_REPMUL    =  53017  # CF19
OP_REPDIV    =  53018  # CF1A
OP_REPCAT    =  53019  # CF1B
OP_MAXIMUM   =  53020  # CF1C
OP_MINIMUM   =  53021  # CF1D
OP_CHANGED   =  53022  # CF1E
OP_REPSUBST  =  53023  # CF1F
OP_DBGON     =  53024  # CF20
OP_DBGOFF    =  53025  # CF21
OP_UNLOAD    =  53026  # CF22
OP_CAPTURE   =  53027  # CF23
OP_PHANTOM   =  53028  # CF24
OP_RTNLIST   =  53029  # CF25
OP_SYSTEM    =  53030  # CF26
OP_ABTCAUSE  =  53031  # CF27
OP_LOGOUT    =  53032  # CF28
OP_USERNO    =  53033  # CF29
OP_ISSUBR    =  53034  # CF2A
OP_LISTCOM   =  53035  # CF2B
OP_DBGWATCH  =  53036  # CF2C
OP_EVENTS    =  53037  # CF2D
OP_DBGSET    =  53038  # CF2E
OP_PCONFIG   =  53039  # CF2F
OP_TTYGET    =  53040  # CF30
OP_TTYSET    =  53041  # CF31
OP_INPUTAT   =  53042  # CF32
OP_INPUT     =  53043  # CF33
OP_PRNAME    =  53044  # CF34
OP_PRDISP    =  53045  # CF35
OP_COMO      =  53046  # CF36
OP_PTERM     =  53047  # CF37
OP_HEADINGN  =  53048  # CF38
OP_PRRESET   =  53049  # CF39
OP_EBCDIC    =  53050  # CF3A
OP_ASCII     =  53051  # CF3B
OP_DTX       =  53052  # CF3C
OP_GETLIST   =  53053  # CF3D
OP_SAVELIST  =  53054  # CF3E
OP_GETPU     =  53055  # CF3F
OP_RDIV      =  53056  # CF40
OP_SUMMATION =  53057  # CF41
OP_SEED      =  53058  # CF42
OP_SETPU     =  53059  # CF43
OP_OPTION    =  53060  # CF44
OP_ENV       =  53061  # CF45
OP_CONFIG    =  53062  # CF46
OP_SENDMAIL  =  53063  # CF47
OP_SQUOTE    =  53064  # CF48
OP_DELLIST   =  53065  # CF49
OP_SORTDATA  =  53066  # CF4A
OP_SELECTV   =  53067  # CF4B
OP_SELECTE   =  53068  # CF4C
OP_PASSLIST  =  53069  # CF4D
OP_BINDKEY   =  53070  # CF4E
OP_CHECKSUM  =  53071  # CF4F
OP_SEEK      =  53072  # CF50
OP_READBLK   =  53073  # CF51
OP_WRITEBLK  =  53074  # CF52
OP_ANALYSE   =  53075  # CF53
OP_CONFIGFL  =  53076  # CF54
OP_FLUSH     =  53077  # CF55
OP_CREATESQ  =  53078  # CF56
OP_UNLK      =  53079  # CF57
OP_UNLKFL    =  53080  # CF58
OP_OSRENAME  =  53081  # CF59
OP_GRPSTAT   =  53082  # CF5A
OP_SETTRIG   =  53083  # CF5B
OP_KEYCODET  =  53084  # CF5C
OP_KEYEDIT   =  53085  # CF5D
OP_KEYEXIT   =  53086  # CF5E
OP_KEYTRAP   =  53087  # CF5F
OP_OPENSEQ   =  53088  # CF60
OP_READSEQ   =  53089  # CF61
OP_WRITESEQ  =  53090  # CF62
OP_WEOFSEQ   =  53091  # CF63
OP_WRITESEQF =  53092  # CF64
OP_OPENSEQP  =  53093  # CF65
OP_CREATEAK  =  53094  # CF66
OP_AKRELEASE =  53095  # CF67
OP_AKWRITE   =  53096  # CF68
OP_AKREAD    =  53097  # CF69
OP_AKDELETE  =  53098  # CF6A
OP_DELETEAK  =  53099  # CF6B
OP_SELINDX   =  53100  # CF6C
OP_SELINDXV  =  53101  # CF6D
OP_AKCLEAR   =  53102  # CF6E
OP_AKENABLE  =  53103  # CF6F
OP_CREATEDH  =  53104  # CF70
OP_CREATET1  =  53105  # CF71
OP_MAPMARKS  =  53106  # CF72
OP_SELLEFT   =  53107  # CF73
OP_SELRIGHT  =  53108  # CF74
OP_SETLEFT   =  53109  # CF75
OP_SETRIGHT  =  53110  # CF76
OP_INDICES1  =  53111  # CF77
OP_INDICES2  =  53112  # CF78
OP_TXNBGN    =  53113  # CF79
OP_TXNCMT    =  53114  # CF7A
OP_TXNEND    =  53115  # CF7B
OP_TXNRBK    =  53116  # CF7C
OP_OSERROR   =  53117  # CF7D
OP_NOBUF     =  53118  # CF7E
OP_XTD       =  53119  # CF7F
OP_BTINIT    =  53120  # CF80
OP_BTADD     =  53121  # CF81
OP_BTSCAN    =  53122  # CF82
OP_BTRESET   =  53123  # CF83
OP_BTADDA    =  53124  # CF84
OP_BTMODIFY  =  53125  # CF85
OP_BTFIND    =  53126  # CF86
OP_BTSCANA   =  53127  # CF87
OP_LOADOBJ   =  53128  # CF88
OP_LOADED    =  53129  # CF89
OP_SPLICE    =  53130  # CF8A
OP_PACKAGE   =  53131  # CF8B
OP_LOCATEF   =  53132  # CF8C
OP_LISTINDX  =  53133  # CF8D
OP_MIN       =  53134  # CF8E
OP_MAX       =  53135  # CF8F
OP_SORTINIT  =  53136  # CF90
OP_SORTADD   =  53137  # CF91
OP_SORTNEXT  =  53138  # CF92
OP_SORTCLR   =  53139  # CF93
OP_RLSFILE   =  53140  # CF94
OP_DIR       =  53141  # CF95
OP_PMATRIX   =  53142  # CF96
OP_DIMLCLP   =  53143  # CF97
OP_LOGMSG    =  53144  # CF98
OP_SHCAP     =  53145  # CF99
OP_PROCREAD  =  53146  # CF9A
OP_DEREF     =  53147  # CF9B
OP_IADD      =  53148  # CF9C
OP_ISUB      =  53149  # CF9D
OP_IMUL      =  53150  # CF9E
OP_SCALE     =  53151  # CF9F
OP_READPKT   =  53152  # CFA0
OP_WRITEPKT  =  53153  # CFA1
OP_CHGPHANT  =  53154  # CFA2
OP_ONGOTOP   =  53155  # CFA3
OP_ONGOSUBP  =  53156  # CFA4
OP_READONLY  =  53157  # CFA5
OP_PICKREAD  =  53158  # CFA6
OP_STORSYS   =  53159  # CFA7
OP_SUBST     =  53160  # CFA8
OP_PSUBSTRA  =  53161  # CFA9
OP_SAVEADDR  =  53162  # CFAA
OP_COMPREP   =  53163  # CFAB
OP_COMPINS   =  53164  # CFAC
OP_COMPINSRT =  53165  # CFAD
OP_COMPREPLC =  53166  # CFAE
OP_FCONTROL  =  53167  # CFAF
OP_GETPORT   =  53168  # CFB0
OP_SETPORT   =  53169  # CFB1
OP_CCALL     =  53170  # CFB2
OP_ENTER     =  53171  # CFB3
OP_SETFLAGS  =  53172  # CFB4
OP_GETMSG    =  53173  # CFB5
OP_CSVDQ     =  53174  # CFB6
OP_OJOIN     =  53175  # CFB7
OP_EXPANDHF  =  53176  # CFB8
OP_LOCAL     =  53177  # CFB9
OP_DELLCL    =  53178  # CFBA
OP_AKMAP     =  53179  # CFBB
OP_SRVRADDR  =  53180  # CFBC
OP_OBJECT    =  53181  # CFBD
OP_OBJMAP    =  53182  # CFBE
OP_OBJREF    =  53183  # CFBF
OP_OPENSKT   =  53184  # CFC0
OP_CLOSESKT  =  53185  # CFC1
OP_READSKT   =  53186  # CFC2
OP_WRITESKT  =  53187  # CFC3
OP_SRVRSKT   =  53188  # CFC4
OP_ACCPTSKT  =  53189  # CFC5
OP_SKTINFO   =  53190  # CFC6
OP_SETSKT    =  53191  # CFC7
OP_FORMCSV   =  53192  # CFC8
OP_ISMV      =  53193  # CFC9
OP_SETUNASS  =  53194  # CFCA
OP_TIMEOUT   =  53195  # CFCB
OP_IN        =  53196  # CFCC
OP_ME        =  53197  # CFCD
OP_GET       =  53198  # CFCE
OP_SET       =  53199  # CFCF
OP_ARGCT     =  53200  # CFD0
OP_ARG       =  53201  # CFD1
OP_RTRANS    =  53202  # CFD2
OP_PAUSE     =  53203  # CFD3
OP_WAKE      =  53204  # CFD4
OP_PSUBSTRB  =  53205  # CFD5
OP_DELSEQ    =  53206  # CFD6
OP_CNCTPORT  =  53207  # CFD7
OP_LGNPORT   =  53208  # CFD8
OP_OBJINFO   =  53209  # CFD9
OP_INHERIT   =  53210  # CFDA
OP_DISINH    =  53211  # CFDB
OP_CREATESH  =  53212  # CFDC
OP_LDLSTR    =  53213  # CFDD
OP_RDNXINT   =  53214  # CFDE
OP_ENCRYPT   =  53215  # CFDF
OP_DECRYPT   =  53216  # CFE0
OP_CRYPT     =  53217  # CFE1
OP_INPUTBLK  =  53218  # CFE2
# Secondary opcodes, prefix EA (MVD)
OP_ABSS      =  59946  # EA2A
OP_LENS      =  59968  # EA40
OP_NEGS      =  59940  # EA24
OP_NOTS      =  60004  # EA64
OP_NUMS      =  60065  # EAA1
OP_SOUNDEXS  =  60068  # EAA4
OP_SPACES    =  59980  # EA4C
OP_TRIMBS    =  59996  # EA5C
OP_TRIMFS    =  59995  # EA5B
OP_TRIMS     =  59994  # EA5A
# Secondary opcodes, prefix EF (MVDD)
OP_ANDS      =  61285  # EF65
OP_CATS      =  61251  # EF43
OP_EQS       =  61280  # EF60
OP_GES       =  61290  # EF6A
OP_GTS       =  61282  # EF62
OP_LES       =  61291  # EF6B
OP_LTS       =  61283  # EF63
OP_MODS      =  61224  # EF28
OP_NES       =  61281  # EF61
OP_ORS       =  61286  # EF66
# Secondary opcodes, prefix EB (MVDS)
OP_STRS      =  60237  # EB4D
OP_COUNTS    =  60253  # EB5D
OP_FMTS      =  60246  # EB56
OP_ICONVS    =  60247  # EB57
OP_OCONVS    =  60248  # EB58
OP_FOLDS     =  60383  # EBDF
# Secondary opcodes, prefix EC (MVDSS)
OP_FOLDS3    =  60567  # EC97
OP_INDEXS    =  60511  # EC5F
OP_TRIMXS    =  60579  # ECA3
# Secondary opcodes, prefix ED (MVDSSS)
OP_FIELDS    =  60754  # ED52

#include "syscom.h"
SYSCOM_ITYPE_MODE          =  1
SYSCOM_COMMAND             =  2
SYSCOM_SENTENCE            =  3
SYSCOM_PARASENTENCE        =  4
SYSCOM_VOC                 =  5
SYSCOM_XEQ_COMMAND         =  6
SYSCOM_SYSTEM_RETURN_CODE  =  8
SYSCOM_DATA_QUEUE          =  9
SYSCOM_COMMAND_STACK       = 10
SYSCOM_SELECT_LIST         = 12
SYSCOM_SELECT_COUNT        = 13
SYSCOM_LOGNAME             = 14
SYSCOM_ECHO_INPUT          = 15
SYSCOM_OPTION              = 16
SYSCOM_CPROC_DATE          = 17
SYSCOM_CPROC_TIME          = 18
SYSCOM_QPROC_FILE_NAME     = 19
SYSCOM_QPROC_ID            = 20
SYSCOM_QPROC_RECORD        = 21
SYSCOM_QPROC_NI            = 22
SYSCOM_QPROC_BREAK_LEVEL   = 23
SYSCOM_BELL                = 24
SYSCOM_USER_RETURN_CODE    = 25
SYSCOM_ACCOUNT_PATH        = 26
SYSCOM_WHO                 = 27
SYSCOM_IPC                 = 29
SYSCOM_BREAK_VALUE         = 30
SYSCOM_LAST_COMMAND        = 31
SYSCOM_ABORT_CODE          = 32
SYSCOM_SELECTED            = 39
SYSCOM_CONV                = 40
SYSCOM_TTY                 = 41
SYSCOM_QPROC_ND            = 46
SYSCOM_USER0               = 49
SYSCOM_USER1               = 50
SYSCOM_USER2               = 51
SYSCOM_USER3               = 52
SYSCOM_USER4               = 53
SYSCOM_QPROC_TOTALS        = 54
SYSCOM_TRIGGER_RETURN_CODE = 55
SYSCOM_ABORT_MESSAGE       = 56
SYSCOM_DS                  = 57
SYSCOM_QPROC_NV            = 61
SYSCOM_QPROC_NS            = 62
SYSCOM_QPROC_LPV           = 63
SYSCOM_PROC_IBUF_0         = 67.0
SYSCOM_PROC_IBUF_1         = 67.1
SYSCOM_PROC_OBUF_0         = 68.0
SYSCOM_PROC_OBUF_1         = 68.1
SYSCOM_PROC_ACTI           = 73
SYSCOM_PROC_ACTO           = 74
SYSCOM_AT_ANS              = 75
SYSCOM_SYS0                = 76

#include "header.h"

INCLUDE_SUFFIX    =        "H"
SCREEN_DEFINITION_SUFFIX = "SCR"
LISTING_SUFFIX    =        ".LIS"
RECURSIVE_SUFFIX  =        ".rcr"

# opcode_inage Header field offsets (from 1) (from 0)
#define hdr.magic                  1 0
#define hdr.rev                    2 1
#define hdr.id                     3 2   ;* Used after loading to memory
#define hdr.start.offset           7 6
#define hdr.args                  11 10
#define hdr.no.vars               13 12
#define hdr.stack.depth           15 14
#define hdr.sym.tab.offset        17 16
#define hdr.lin.tab.offset        21 20
#define hdr.object.size           25 24
#define hdr.flags                 29 28
#define hdr.compile.time          31 30   ;* 4 bytes: = SYSTEM(1005)
# opcode_inage Header field offsets (from 0)
HDR_MAGIC          =   0
HDR_REV            =   1
HDR_ID             =   2 # Used after loading to memory
HDR_START_OFFSET   =   6
HDR_ARGS           =  10
HDR_NO_VARS        =  12
HDR_STACK_DEPTH    =  14
HDR_SYM_TAB_OFFSET =  16
HDR_LIN_TAB_OFFSET =  20
HDR_OBJECT_SIZE    =  24
HDR_FLAGS          =  28
HDR_COMPILE_TIME   =  30 # 4 bytes: = SYSTEM(1005)

#Later items differ depending on object type

# Programs and subroutines
HDR_REFS              =   34
HDR_PROGRAM_NAME      =   36
HDR_PROGRAM_NAME_LEN  =  128
OBJECT_HEADER_SIZE    =  165

# I-types
HDR_TOTALS               =  35    # NUMBER OF TOTAL() FUNCTIONS (1 BYTE)
ITYPE_OBJECT_HEADER_SIZE =  36

# Inline code
INLINE_OBJECT_HEADER_SIZE = 35

# Magic number and revision
HDR_MAGIC_NO_L   =   100    # FOR LITTLE ENDIAN MACHINES
HDR_MAGIC_NO_B   =   101    # FOR BIG ENDIAN MACHINES
HDR_REVISION     =     0

# Header flags bit values
HDR_IS_CPROC       = 0x0001  # Command processor
HDR_INTERNAL       = 0x0002  # Internal mode program
HDR_DEBUG          = 0x0004  # Compiled in debug mode
HDR_IS_DEBUGGER    = 0x0008  # Debugger
HDR_NOCASE         = 0x0010  # Case insensitive string operations
HDR_IS_FUNCTION    = 0x0020  # Basic function
HDR_VAR_ARGS       = 0x0040  # Variable arg count (hdr_args = max)
HDR_RECURSIVE      = 0x0080  # Is a recursive program
HDR_ITYPE          = 0x0100  # Is an A/S/C/I-type
HDR_ALLOW_BREAK    = 0x0200  # Allow break in recursive
HDR_IS_TRUSTED     = 0x0400  # Trusted program
HDR_NETFILES       = 0x0800  # Allow remote files by NFS
HDR_CASE_SENSITIVE = 0x1000  # Program uses case sensitive names
HDR_SDCALL_ALLOWED = 0x2000  # Can be called using SDCall()
HDR_CTYPE          = 0x4000  # Is a C-type
HDR_IS_CLASS       = 0x8000  # Is CLASS module

# Flag bits not in header but in process_program_flags
# (see kernel_h for full list)
#
HDR_IS_EXECUTE    = 0x00010000 # Started from an EXECUTE
HDR_IGNORE_ABORTS = 0x00040000 # Ignore aborts from EXECUTEd sentence

header_flags = 0   # option flags

 # KERNEL() function action keys
K_INTERNAL    =   0       # Set/clear internal mode
K_SECURE      =   1       # Secure system (login required)?
K_LPTRHIGH    =   2       # @LPTRHIGH
K_LPTRWIDE    =   3       # @LPTRWIDE
K_PAGINATE    =   4       # Pagination active?
K_FLAGS       =   5       # Check/return header flags
K_DATE_FORMAT =   6       # European date format?
K_CRTHIGH     =   7       # @CRTHIGH
K_CRTWIDE     =   8       # @CRTWIDE
K_SET_DATE    =   9       # Set current date
K_IS_PHANTOM  =  10       # Phantom process?
K_TERM_TYPE   =  11       # Terminal type name
K_USERNAME    =  12       # User name
K_DATE_CONV   =  13       # Set default date conversion
K_PPID        =  14       # Get parent process id
K_USERS       =  15       # User id/ip_addr list
K_CPROC_LEVEL =  22       # Get/set command processor level

####
# $include err.h
ER_LCK        =  3011    # ER$LCK Lock is held by another process


#/* Declare opcode functions */

##define _opc_(code, key, name, func, format, stack_use) void func(void);
##include "opcodes.h"
##undef _opc_

#/* Build dispatch table */
##define _opc_(code, key, name, func, format, stack_use) func,
#void (*dispatch[])(void) = {
##include "opcodes.h"
#};
##undef _opc_

 # Initialise constant data

 # Characters that are allowed in a SDBasic name

#/* The internal representation of the mark characters uses the last five characters of the ASCII character set:
ITEM_MARK  = chr(255)  # FF
FIELD_MARK = chr(254)  # FE 
VALUE_MARK = chr(253)  # FD
SUBVALUE_MARK = chr(252) #FC
TEXT_MARK  = chr(251)    #FB

#/* mark charactes, see EMIT_AT_VAR_LOAD for use */
# mark_chars FIELD_MARK(FM)  VALUE_MARK(VM)  SUBVALUE_MARK(SM)  TEXT_MARK(TM)  ITEM_MARK(IM)  FIELD_MARK(AM)  SUBVALUE_MARK(SVM)
mark_chars = '\xfe\xfd\xfc\xfb\xff\xfe\xfc'              # this needs to be defined as a string for at_mark():
name_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.$%_"

#
# Below we define a bunch of field separated lists
# Used in locates as indexes, case statement to output correct pcode ....


###################################################################################################
# @variable names and called funtion.  
# we must define the functions prior to referencing them in the via calling at_constants_func lists
###################################################################################################
def at_mark():          # FM, VM, SM, TM, IM, AM, SVM
    if u_token_string in at_constants:
        idx = at_constants.index(u_token_string)  # kind of screw whats going on here, we are using at_constants as an index
                                                  # into the string mark_chars, but I guess this works??
        emit_string_load(mark_chars[idx])
    return

def at_false():
    emit_numeric_load(0)
    return

def at_true():
    emit_numeric_load(1)
    return

def at_sdsys():                         # @SDSYS  -  SDSYS pathname
    emit_simple(OP_SYSDIR)
    return

def at_userno():                        # @USERNO
    emit_simple(OP_USERNO)
    return

def at_day():                           # @DAY
    emit_ldsysv(SYSCOM_CPROC_DATE)
    emit_string_load("DD")
    emit_simple(OP_OCONV)
    return

def at_month():                         # @MONTH
    emit_ldsysv(SYSCOM_CPROC_DATE)
    emit_string_load("DM[2]")
    emit_simple(OP_OCONV)
    return

def at_year():                          # @YEAR
    emit_ldsysv(SYSCOM_CPROC_DATE)
    emit_string_load("D2Y")
    emit_simple(OP_OCONV)
    return

def at_year4():                         # @YEAR4
    emit_ldsysv(SYSCOM_CPROC_DATE)
    emit_string_load("D4Y")
    emit_simple(OP_OCONV)
    return

def at_lptrhigh():
    emit_numeric_load(K_LPTRHIGH)
    emit_numeric_load(0)
    emit_simple(OP_KERNEL)
    return

def at_lptrwide():
    emit_numeric_load(K_LPTRWIDE)
    emit_numeric_load(0)
    emit_simple(OP_KERNEL)
    return

def at_crthigh():
    emit_numeric_load(K_CRTHIGH)
    emit_numeric_load(0)
    emit_simple(OP_KERNEL)
    return

def at_crtwide():
    emit_numeric_load(K_CRTWIDE)
    emit_numeric_load(0)
    emit_simple(OP_KERNEL)
    return

def at_level():
    emit_numeric_load(K_CPROC_LEVEL)
    emit_numeric_load(0)
    emit_simple(OP_KERNEL)
    return

def at_term_type():
    emit_numeric_load(K_TERM_TYPE)
    emit_simple(OP_LDNULL)
    emit_simple(OP_KERNEL)
    return

def at_transaction_id():
    emit_numeric_load(1007)
    emit_simple(OP_SYSTEM)
    return

def at_transaction_level():
    emit_numeric_load(1008)
    emit_simple(OP_SYSTEM)
    return

def at_ip_addr():
    emit_numeric_load(42)
    emit_simple(OP_SYSTEM)
    return

def at_hostname():
    emit_numeric_load(1015)
    emit_simple(OP_SYSTEM)
    return

def at_gid():
    emit_numeric_load(29)
    emit_simple(OP_SYSTEM)
    return

def at_uid():
    emit_numeric_load(27)
    emit_simple(OP_SYSTEM)
    return
# 
# DO NOT MESS WITH  ORDER OF THE LISTS  
#
#/* !!ATVAR!!  <- tag for atvar editing (make sure all spots get changed in mult source files)*/
at_constants = ["FM" , "VM" , "SM" , "TM" , "IM" , "AM" , "SVM" , "FALSE" , "TRUE" ,
 "SDSYS" , "USERNO" , "USER.NO" , "DAY" , "MONTH" , "YEAR" , "YEAR4" , "LPTRHIGH" , "LPTRWIDE" , "CRTHIGH" , "CRTWIDE" ,
 "LEVEL" , "TERM.TYPE" , "TRANSACTION.ID" , "TRANSACTION.LEVEL" , "IP.ADDR" , "HOSTNAME" , "GID" , "UID" , "SDSYS"]
at_constants_func = [
at_mark,
at_mark,
at_mark,
at_mark,
at_mark,
at_mark,
at_mark,
at_false,
at_true,
at_sdsys,
at_userno,
at_userno,
at_day,
at_month,
at_year,
at_year4,
at_lptrhigh,
at_lptrwide,
at_crthigh,
at_crtwide,
at_level,
at_term_type,
at_transaction_id,
at_transaction_level,
at_ip_addr,
at_hostname,
at_gid,
at_uid,
at_sdsys    
]

#/*
   # The AT.SYSCOM.VARS list contains @ variables which correspond to data
   # in the SYSCOM common block. The offset of the common variable is in
   # the AT.SYSCOM.OFFSETS list.
#/

at_syscom_vars = [
   "ABORT.CODE"         ,
   "ABORT.MESSAGE"      ,
   "ANS"                ,
   "COMMAND"            ,
   "COMMAND.STACK"      ,
   "CONV"               ,
   "DATA.PENDING"       ,
   "DATE"               ,
   "DS"                 ,
   "FILE.NAME"          ,
   "FILENAME"           ,
   "ID"                 ,
   "ITYPE.MODE"         ,
   "LOGNAME"            ,
   "ND"                 ,
   "NI"                 ,
   "NS"                 ,
   "NV"                 ,
   "LPV"                ,
   "OPTION"             ,
   "PARASENTENCE"       ,
   "PATH"               ,
   "PIB"                ,
   "POB"                ,
   "RECORD"             ,
   "SELECTED"           ,
   "SENTENCE"           ,
   "SIB"                ,
   "SOB"                ,
   "SYS.BELL"           ,
   "SYS0"               ,
   "SYSTEM.RETURN.CODE" ,
   "SYSTEM.SET"         ,
   "TIME"               ,
   "TTY"                ,
   "TRIGGER.RETURN.CODE",
   "USER.RETURN.CODE"   ,
   "USER"               ,
   "USER0"              ,
   "USER1"              ,
   "USER2"              ,
   "USER3"              ,
   "USER4"              ,
   "VOC"                ,
   "WHO"                ]

#/* NOTE: in BCOMP at.syscom.offsets we have: 
#  PIB  SYSCOM.PROC.IBUF:'.0'  The PROC primary input buffer.
#  POB  SYSCOM.PROC.IBUF:'.0'  The PROC primary output buffer.
#  SIB  SYSCOM.PROC.IBUF:'.1'  The PROC secondary input buffer.
#  SOB  SYSCOM.PROC.IBUF:'.1'  The PROC secondary output buffer
#   these appear to be numberic offsets, so not sure what this means?
# Regardless these appear to deal with proc which hopefully we can ignore?
#  */ 
at_syscom_offsets = [
    SYSCOM_ABORT_CODE           ,
    SYSCOM_ABORT_MESSAGE        ,
    SYSCOM_AT_ANS               ,
    SYSCOM_COMMAND              ,
    SYSCOM_COMMAND_STACK        ,
    SYSCOM_CONV                 ,
    SYSCOM_DATA_QUEUE           ,
    SYSCOM_CPROC_DATE           ,
    SYSCOM_DS                   ,
    SYSCOM_QPROC_FILE_NAME      ,
    SYSCOM_QPROC_FILE_NAME      ,
    SYSCOM_QPROC_ID             ,
    SYSCOM_ITYPE_MODE           ,
    SYSCOM_LOGNAME              ,
    SYSCOM_QPROC_ND             ,
    SYSCOM_QPROC_NI             ,
    SYSCOM_QPROC_NS             ,
    SYSCOM_QPROC_NV             ,
    SYSCOM_QPROC_LPV            ,
    SYSCOM_OPTION               ,
    SYSCOM_PARASENTENCE         ,
    SYSCOM_ACCOUNT_PATH         ,
    SYSCOM_PROC_IBUF_0          ,
    SYSCOM_PROC_OBUF_0          ,
    SYSCOM_QPROC_RECORD         ,
    SYSCOM_SELECTED             ,
    SYSCOM_SENTENCE             ,
    SYSCOM_PROC_IBUF_1          ,
    SYSCOM_PROC_OBUF_1          ,
    SYSCOM_BELL                 ,
    SYSCOM_SYS0                 ,
    SYSCOM_SYSTEM_RETURN_CODE   ,
    SYSCOM_SYSTEM_RETURN_CODE   ,
    SYSCOM_CPROC_TIME           ,
    SYSCOM_TTY                  ,
    SYSCOM_TRIGGER_RETURN_CODE  ,
    SYSCOM_USER_RETURN_CODE    ,
    SYSCOM_LOGNAME             ,
    SYSCOM_USER0               ,
    SYSCOM_USER1               ,
    SYSCOM_USER2               ,
    SYSCOM_USER3               ,
    SYSCOM_USER4               ,
    SYSCOM_VOC                 ,
    SYSCOM_WHO]

# /*
# * The following @variables, also in the AT.SYSCOM.VARS list above, may be
# * used as lvalues in non-internal mode code.
# */
# 
at_syscom_lvars = [
   "USER.RETURN.CODE" ,
   "DATE"   ,
   "TIME"   ,
   "ID"     ,
   "RECORD" ,
   "SELECTED" ,
   "TRIGGER.RETURN.CODE" ,
   "USER0" ,
   "USER1" ,
   "USER2" ,
   "USER3" ,
   "USER4" ,
   "ANS" ,
   "PIB" ,
   "SIB" ,
   "POB" ,
   "SOB"]

#  #/*
#  * Reserved names
#  * This list starts out as the list of names that are reserved in all
#  * usages. Individual statement processing routines can add a local
#  * list of reserved names for that statement as field 2 but it is
#  * essential that these are removed again. As a sanity check, the
#  * error handler removes field 2 if it is present. Therefore, it is
#  * not necessary to tidy up in error paths.
#  */

reserved_names = [ 
"BEFORE"  ,     
"BY"      ,
"DO"      ,
"ELSE"    ,
"FROM"    ,
"GO"      ,
"IN"      ,
"LOCKED"  ,
"NEXT"    ,
"ON"      ,
"REPEAT"  ,
"SETTING" ,
"THEN"    ,
"TO"      ,
"UNTIL"   ,
"WHILE"
]

######################################################################################################
#   def functions prior to use
######################################################################################################

def error(msg):
    """print error message and exit script"""
    print(msg + ' at pass2 ln ' + str(gbl_src_ln_cnt) )

    if debugging == debug_log:
        sfn = os.getcwd() + os.sep + 'get_line_db.txt'
        print('writing gtlog to ' + sfn)
        with open(sfn, 'w')  as wf:
            for ln in  gtlog:
                    wf.write(f"{ln.rstrip()}\n")

    sys.exit('abort')

def isAlpaNumberic(c):
    """Is character AlphaNumberic"""
    if (CHAR_TYPES[ord(c)] == CT_ALPHA) or (CHAR_TYPES[ord(c)] == CT_DIGIT):
        return True
    else:
        return False 
    
def check_comma():
    if look_ahead_token != TKN_COMMA:
        error('Comma not found where expected') 
    get_token()
    return  

def int_or_float(val):
    # returns integer or float value of string, if not able to convert, error
    try:
        # all int like strings can be converted to float so int tries first    
        return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except:
        error('int_or_float - Expecting Float or Integer')
        return
    
#
# Our version of BASIC statement REMOVE.TOKEN (or call to op_rmbtkn)
# Note: within the string desciptor structure, there is var "n1" which is:
#      Remove pointer offset into chunk pointed to by
#      rmv_saddr element of the descriptor. Using Q_MBasic
#      character position numbers, this points to the
#      character before the next one to be extracted.
#      When the end of the string is reached, it points
#      one character off the end of the string.
#
#
#  token_str, token_type, new_src = remove_token(srcr)
#


def remove_token(src_str):
    """ get next token from src_str, return [token_data, token_type]"""
    global token_strings
    
    done = False        # /* End of token - current char is next token */
    done_after = False  # /* End of token - current char part of this token */
    delimiter = ''      # /* String constant delimiter */
    copy_char = True

    token_type = TKN_UNKNOWN
    token_data = ''                   # token string text, called tgt_str->data in c code
    tkn_start_idx = 0                 # character index of first character of token_data in src_str
    bytes = 0                         # bytes copied into token_data
    char_idx = 0
     # mimic do while (!done) outer most loop of op_rmvtkn.c
    while True:
        tst_str = src_str.strip()
        # the following is a kludge test to see if we are done. 
        # we could have a remnant '"' or "'" that does not get processed properly
        # if this is the case simply emit the TKN_END token
        #if (tst_str == '') or ((tst_str == "'") and (token_strings[-1] != '=')):   # nothing on source line but spaces
        if (tst_str == '') or (tst_str == "'") or (tst_str == '"')  :   # nothing on source line but quote character(s) or empty
            token_type = TKN_END 
            token_data = ''
            done = True 
            break
        #
        while (char_idx < len(src_str)) and (not done_after):
        #while (len(str) > 0) and (not done_after):
            copy_char = True
            c = src_str[char_idx]      # get next character
            char_idx +=1           
            ord_c = ord(c)  # int value of char c
            if token_type == TKN_UNKNOWN:
                if (ord_c > 0x1f) and (ord_c < 0x80):    # value of c is within token_table 
                    tt_idx = ord_c - 0x20   # calc index into TOKEN_TABLE
                    delimiter = c
                    token_type = TOKEN_TABLE[tt_idx][0]
                    copy_char  = TOKEN_TABLE[tt_idx][1]
                    done_after = TOKEN_TABLE[tt_idx][2]
                else:
                    if (ord(c) < 0x20):
                        # control code, ignor
                        copy_char = 0
                    else:
                        # Unrecognised token 
                        done_after = 1

            else:    # Token type is already known

                if token_type == TKN_NAME:
                    if c == '_':
                        # 1.2-16 Special case for an underscore. This is valid
                        # but not as the last character in the name so we need to
                        # look at the next character to see what it is.  
                        if (char_idx < len(src_str)):   # rem char_idx already points to next char
                            xc = src_str[char_idx]
                        else:
                            xc = ''
                        # if xc is not any of ( alpha numberic, '.', '%', '$') set done flag 
                        done = (not isAlpaNumberic(xc))  and (xc != '.') and (xc != '%') and (xc != '$')
                    else:
                        done = (not isAlpaNumberic(c)) and (c != '.') and (c != '%') and (c != '$')  

                    if done: 
                        token_assigned = False    # need to get rid of goto in original logic
                        if len(token_data) <= LONGEST_OPNAME:   #* Could be an operator name 
                            # dont really understand why the size test, but keeping the logic the saem
                        #   Check for reserved names corresponding to operators  
                            if token_data in opname_strings:
                                token_type = opname_codes[opname_strings.index(token_data)]
                                token_assigned = True

                    # We need to distinguish between
                    #    xyz(             Eg N(5) = 99
                    # and
                    #     xyz (            Eg INS (I + 3) * 2 BEFORE S<1>
                    # To do this, we return TKN_NAME_LBR if the name is
                    # immediately followed by a left bracket.                 
                        
                        if not token_assigned:
                            if c == '(':
                                token_type = TKN_NAME_LBR

                                
                elif token_type == TKN_NUM:
                    if CHAR_TYPES[ord(c)] != CT_DIGIT:
                        if c =='.':
                            token_type = TKN_FLOAT
                        elif c.upper() == 'X' and bytes == 1 and token_data[0] == '0':
                        #  It's a hex number
                        #   We will ulimately end up with a stray leading zero
                        #    but that should cause no problems.
                            token_type = TKN_HEXNUM
                            copy_char = False
                        else:
                            done = True   

                elif token_type == TKN_LABEL:
                    if c == ':':
                        done_after = True
                    elif label_chars.find(c) == -1:    # if character not in label_chars
                        done = True                    # we are done
                
                elif token_type == TKN_STRING:
                    if c == delimiter:
                        copy_char = False    # do not copy to target string
                        done_after = True

                elif token_type == TKN_FLOAT:
                    if c == '.':
                        token_type = TKN_LABEL
                    elif  CHAR_TYPES[ord(c)] != CT_DIGIT:
                        done = True


                elif token_type == TKN_LT:

                    if c == '>':    # <>
                        token_type = TKN_NE
                        done_after = True

                    elif c == '=':   # <=
                        token_type = TKN_LE
                        done_after = True 

                    else:

                        done = True

                elif token_type == TKN_GT:    #   
                    #print ('start at line  473') 
                    if c == '<':  # <>
                        # 0465 We might have a nasty construct such as
                        #   A<B><>C  or A<B><=C
                        #  To handle this, we need to look ahead one further
                        #  character. If it is > or =, treat this as < followed
                        #    by <> or <=.                                         */
                        if char_idx < len(src_str):      # rem char_idx is already pointing to next char
                            xc = src_str[char_idx]
                        else:
                            xc = ''

                        if ((xc == '>') or (xc == '=')):
                            done = True
                        else:
                            token_type = TKN_NEX
                            done_after = True

                    elif c == '=':
                        token_type = TKN_GE
                        done_after = True

                    else:
                        done = True

                elif token_type == TKN_EQ:    #   

                    if c == '<':   # =<
                        token_type = TKN_LE
                        done_after = True    

                    elif c == '>':   # =>
                        token_type = TKN_GEX
                        done_after = True 

                    else:
                        done = True 

                elif token_type == TKN_PLUS:    #  

                    if c == '=':        # +=
                        token_type = TKN_ADDEQ
                        done_after = True
                    else:
                        done = True

                elif token_type == TKN_MINUS:    #                      
                    if c == '=':        # -=
                        token_type = TKN_SUBEQ
                        done_after = True
                    elif c == '>':    # ->
                        token_type = TKN_OBJREF
                        done_after = True
                    else:
                        done = True 
                
                elif token_type == TKN_DIV:    # 
                    if c == '=':        # /=
                        token_type = TKN_DIVEQ
                        done_after = True
                    elif c == '/':   # //
                        token_type = TKN_IDIV
                        done_after = True
                    else:
                        done = True 

                elif token_type == TKN_COLON:    #
                    if c == '=':   # :=
                        token_type = TKN_CATEQ
                        done_after = True
                    else:
                        done = True  

                elif token_type == TKN_MULT:    #
                    if c == '*':   # **
                        token_type = TKN_PWR
                        done_after = True 
                    elif c == '=':  # *=
                        token_type = TKN_MULTEQ
                        done_after = True
                    else:
                        done = True        

                elif token_type == TKN_AT:    #
                    if CHAR_TYPES[ord(c)] == CT_ALPHA:
                        token_type = TKN_AT_NAME
                    done = True

                elif token_type == TKN_HEXNUM: 
                    #
                    if  "0123456789ABCDEF".find(c.upper()) == -1:
                        done = True
            # if token_type unknown                                                                                                         

                else:

                    sys.exit(" Failed to id Token ")

            if  done:
                break

            if (copy_char):    # ln 603
                if token_type == TKN_NAME:
                     c = c.upper()
                if len(token_data) ==0:
                    tkn_start_idx = char_idx - 1   # rem we already point to next character     
                token_data = token_data + c   # add character to string
                bytes += 1


        if (done_after): # break out of do while (!done) loop
            break
         
        if not done:

            if char_idx >= len(src_str):     # end of string 
                if token_type == TKN_UNKNOWN:
                    token_type = TKN_END
                    break
                elif token_type == TKN_STRING:
                    #  We have run off the end of the source while collecting a
                    #  string. Set the token type as TKN_UNCLOSED.               */
                    token_type = TKN_UNCLOSED
                    break

                done = True

        # mimic do while (!done) outer most loop of op_rmvtkn.c
        if done:
            break
  
    # return the parsed token text, its type and the string less the token text
    # remove this token from source string
    # rem tkn_start_idx set on first character append to token_data+
    #   N O T E
    #     It is possible that no token_data has been save, for example:
    #     rec = ''
    #     the last pass will come here with src_str = " ''"
    #     and the quote character may be set to not copy
    #     handle this possiblily with the tkn_len test and look for '""' or "''"
    tkn_len = len(token_data)
    if tkn_len > 0:
        # we also need to handle the trailing delimeter for TKN_STRING
         if token_type == TKN_STRING:
            tkn_len +=1  # also remove the trailing delimiter
         elif token_type == TKN_HEXNUM:
            # src_str has the 'x' from the hex designation of the hex number
            # however it is not included in the token_str
            # so our slice will not work as expected
            # solution is to remove the 'x' from the src_str 
            if '0x' in src_str: 
               src_str = src_str.replace('x','',1) 
            elif '0X' in src_str:
               src_str = src_str.replace('X','',1) 

         new_src = src_str[tkn_len+tkn_start_idx:].strip()
    else:
         new_src = src_str.strip()
         if new_src[:2] == '""' or new_src[:2] == "''":
            new_src = src_str[2:].strip()
    
    #if len(token_data.strip()) > 0:
    #    new_src = re.sub(re.escape(token_data),'', src_str, count=1, flags=re.IGNORECASE)
    #else:
    #    token_data = ''
    #    new_src = ''

    return token_data, token_type, new_src


def get_line(src_list):
    """Get next source line from src_list and parse into TOKENS and TOKEN_STRINGS arrays (list)"""
    global tokens, token_strings, end_source, num_tokens, look_ahead_token,  look_ahead_token_string, u_look_ahead_token_string, token_index, debugging, gbl_src_ln_cnt
    if debugging:
        global gtlog
    # these are global because I basically tried to convert BCOMP from basic to python (and a little laziness on
    #  my part)
    #
    # tokens        - list of token_types parsed from source line
    # token_strings - corresponding list of text string of the token
    # num_tokens    - current number of tokens in the above lists
    #  a note worth mentioning here: BCOMP allows for the token arrays to grow, Not doing it here
    #  if we max out (INIT_TOKENS defined as 100), we bomb out.
    #  just upsize INIT_TOKENS and there by the array lists that use INIT_TOKENS.
    # token_index   - index into lists of the token being processed, points to the look_ahead_token. rem theses are global, accessed all thoughout bbcmp
    #                 incremented in get_token
    # look_ahead_token - token type of look ahead token 
    # look_ahead_token_string - as above but the actual string text of the token
    # 
    # debugging - all important debug flag
    src_cnt = len(src_list)


    while True:   # Until we have a non-blank line to process    
        num_tokens = 0
        token_strings = []
        tokens = array.array('i',(TKN_END for i in range(0,INIT_TOKENS)))

        while True:  # Until no further continuation lines

            continue_on_next_line = False

            if len(src_list) == 0:   # end of source?
                end_source = True
                tokens[0] = TKN_END
                token_strings.append('')

            else:                    # not end, get next line
                src = src_list[0].strip()
                gbl_src_ln_cnt +=1
                src_list.pop(0)      # and remove from src_list
                # NOTE at this point in BCOMP, get.line checks for continuation line
                #      and pre processor directives $IFDEF / $IFNDEF and so on
                #      Continuation lines (~) where already appended in pass 1
                #      Pre processor directives are not supported

                   
                # parse statement into tokens
                # Fetch first token
            
                token_str, token_type, src = remove_token(src)
                if debugging == debug_detail:
                  print('pass2 ln: ' +str(gbl_src_ln_cnt))
                  print ('1st - token_str~' + token_str + '~    token_type: ' + str(token_type))
                elif debugging == debug_log:
                  gtlog.append('1st - token_str~' + token_str + '~    token_type: ' + str(token_type)) 

                if len(token_str) == 0:   # empty line sent to remove.token, skip
                    continue

                c = token_str[0]  # get first character of token

                if c == '*' or c == '!':     # line is a comment
                    continue
                else:
                    while True:   # needed to mimic loop structure of BASIC
                        num_tokens += 1
                        if num_tokens >= INIT_TOKENS:
                            # BCOMP allows for resizing of token table, we are not doing this
                            # Python really does not care about list size, but I choose to use
                            # array.array to speed things up, this may have been a bad idea?
                            sys.exit('Reached max tokens, must increase INIT_TOKENS value')


                        token_strings.append(token_str)
                        tokens[num_tokens-1] = token_type

                        if token_type == TKN_END: # needed to mimic loop structure of BASIC
                            break

                        #  If the token was a semicolon, look ahead to the next token
                        #  to see if the rest of the line is a comment
                        
                        if token_type == TKN_SEMICOLON:
                           token_str, token_type, src = remove_token(src)
                           if debugging == debug_detail:
                              print (';   - token_str~' + token_str + '~    token_type: ' + str(token_type))
                           elif debugging == debug_log:   
                              gtlog.append(';   - token_str~' + token_str + '~    token_type: ' + str(token_type))

                           if len(token_str) == 0:   # empty line sent to remove.token, skip
                              continue
                           c = token_str[0]
                           if token_type != TKN_STRING and (c == '*' or c == '!'):
                              # rest of line a comment
                              # replace semi token by end token and exit loop

                              # special code for ;* at begining of line (num_tokens == 1)
                              # will leave us with a mess on the parsing of the following src line
                              # if this is the case reset our lists
                              #if num_tokens == 1:
                              #  tokens = array.array('i',(TKN_END for i in range(0,INIT_TOKENS)))
                              #  token_strings = []
                              #else:
                              # actually moving tokens and token_string init into frist while loop fixed
                              tokens[num_tokens-1] = TKN_END
                              token_strings[-1] = ''
                              break
                        else:
                            token_str, token_type, src = remove_token(src)
                            if debugging  == debug_detail:
                              print ('!;  - token_str~' + token_str + '~    token_type: ' + str(token_type))
                            elif debugging  == debug_log:
                              gtlog.append('!;  - token_str~' + token_str + '~    token_type: ' + str(token_type))  
            
            if num_tokens > 1:
                if tokens[num_tokens-2] == TKN_COMMA:
                    # The final token on this line is a comma. The following
                    # line is therefore a continuation unless this line begins with
                    # a label immediately followed by a comment introducer.  

                    if tokens[0] == TKN_NAME and tokens[1] == TKN_COLON:
                        n = 3
                    elif tokens[0] == TKN_LABEL:
                        n = 2
                    elif tokens[0] == TKN_NUM or tokens[0] == TKN_FLOAT:
                        if tokens[1] == TKN_COLON:
                            n = 3
                        else:
                            n = 2
                    else:
                        n = 0
                    
                    if n != 0:
                        #
                        n -= 1  # always remember indexing in BASIC is 1 based, Python 0
                        if token_strings[n] == '*':
                            pass
                        elif token_strings[n] == '!':
                            pass
                        elif tokens[n] == TKN_NAME and any(x in token_strings[n].upper() for x in ['REM','REMARK'] ):
                            pass
                        else:
                            continue_on_next_line = True
                    else:
                        continue_on_next_line = True

            if continue_on_next_line:
                num_tokens -= 1
                del token_strings[-1]       # note to keep token_strings in sync with tokens, we must remove
                                            # last string appended when processing continued line

            else:
                break

        # this loop continues until there is a non blank line to compile
        if end_source:
            break
        if num_tokens > 1:   # line is not blank
            break  

    if debugging == debug_detail:
        print (token_strings)

    look_ahead_token = tokens[0]    # all important look ahead tokens
    look_ahead_token_string = token_strings[0]
    u_look_ahead_token_string =  look_ahead_token_string.upper()
    token_index = 0    # rem we are zero based indexing, incremented in get_token                       
           
    return src_list # return source lines not processed            



def get_nxt_line():
    global end_source, lines

    if len(lines) > 0:
        lines = get_line(lines)
    else:
        end_source = True 
    return      

def get_token():
    """get next token from pre-parsed source token array"""
    global token, token_string, look_ahead_token, u_token_string, look_ahead_token_string, u_look_ahead_token_string, token_index
    
    if debugging == debug_detail:
        print('get_token() - entry')
        print('get_token() tokens[0:10]: ', tokens[0:10]) 
        print('get_token() token_strings: ' , token_strings)   
        print('get_token() token_index: ' + str(token_index))
    
    token = look_ahead_token
    token_string = look_ahead_token_string
    u_token_string = u_look_ahead_token_string

    if token > 0:
        token_index += 1
        look_ahead_token = tokens[token_index]
        look_ahead_token_string = token_strings[token_index]
        u_look_ahead_token_string = look_ahead_token_string.upper()
    else:
        get_nxt_line()
        token_string = token_strings[0]

    if debugging == debug_detail:
        print('get_token() - exit')
        print('get_token() tokens[0:10]: ', tokens[0:10]) 
        print('get_token() token_strings: ' , token_strings)   
        print('get_token() token_index: ' + str(token_index))

    return

def check_for_label():
    global label_name, token_string

    if debugging == debug_detail:
        print ('check_for_label() token:' + str(token))
        print ('check_for_label() look_ahead_token:' + str(look_ahead_token))
        print ('check_for_label() token_string:' + token_string)

    if token == TKN_NAME:
        if look_ahead_token == TKN_COLON:
            label_name = token_string
            if lsub_var_no >= 0:
                label_name = lsub_name+label_name   # note lsub_name will be set in st_local() once we get there
            
            set_label()
            get_token()     # Read colon token
            get_token()       # Get next token
            c = token_string[0]
            if c == '*' or c == '!':
                st_remark()


    elif token == TKN_LABEL:
        if token_string[-1] == ':':
            token_string = token_string[:-1]  # remove ':' from token
        label_name = token_string
        if lsub_var_no >= 0:
            label_name = lsub_name + label_name
        set_label()
        get_token()     #* Get next token
        c = token_string[0]
        if c == '*' or c == '!':
            st_remark()

    elif token ==  TKN_NUM or token ==  TKN_FLOAT:
        label_name = token_string
        if lsub_var_no >= 0:
            label_name = lsub_name + label_name
        set_label()
        get_token()     #* Get next token
        if token == TKN_COLON:
            get_token()
        c = token_string[0]
        if c == '*' or c == '!':
            st_remark()

    return

##############################################################################################
# handlers for  statement / functions 
# N O T E  - this is where we set supported / unsupported  functions and statements
############################################################################################## 
#
# There is no on gosub in python, so what we are going to do is call via a dictionary
#
#def p1(args):
#    whatever
#
#def p2(more args):
#    whatever
#
#myDict = {
#    "P1": p1,
#    "P2": p2,
#    ...
#    "Pn": pn
#}
#
#def myMain(name):
#    myDict[name]()
#
# in the case of intrinsics we have a list item for each function name
# [ op.code, function_name]
# so the call is x.symbol.name - text name of function to emit
# 
# if x.symbol.name in intrinsics:
#    op_code = intrinsics[x.symbol.name][0]  # list element 0 is the actaul op code to emit
#    intrinsics[x.symbol.name][1]()          # list element 1 is the python function object 
# else:
#    # if we have looked in statements non_debug_statements restricted_statements internal_intrinsics
#    # error out with unknown statement
# 

####################################################################################
# Statement names and called funtion.  
# we must define the functions prior to referencing them in the calling dictionaries
####################################################################################

def st_abort():
    error(token_string + ' statement not coded')
    return

def st_aborte():
    error(token_string + ' statement not coded')
    return

def st_abortm():
    error(token_string + ' statement not coded')
    return

def st_begin():
    """B EGIN CASE statement (Entered from keyword BEGIN) """
    global jump_no, jump_stack, label_name

    get_token()          #  Get next token

    #begin case
    if u_token_string == "CASE":
        if look_ahead_token > 0: 
            error(' Begin - Unexpected text after BEGIN CASE')


        get_token()
    
        # Add new entry to jump stack

        jmp_val = [J_CASE,jump_no,0]
        jump_stack.insert(0,jmp_val)

        jump_no += 1

        # Process CASE statements

        # loop
        while True:
            # If this is not the first CASE, emit a jump to the exit label
            # and then label this CASE statement.

            if jump_stack[0][2] != 0:    # element # of case
               label_name = "_" + str(jump_stack[0][1]) +  "X"
               emit_jump(OP_JMP)

               # Emit a label for this CASE group

               label_name = "_" + str(jump_stack[0][1]) + "C" + str(jump_stack[0][2])
               set_label()


            jump_stack[0][2] += 1       

        # until (u_look_ahead_token_string = "END") or end.source
            if (u_look_ahead_token_string == "END") or (end_source == True):
                break

            # emit_xref_entry() no cross ref table being generated, don't need to code

            # The next statement should be a CASE
      
            if u_look_ahead_token_string != "CASE":
               error(' Begin -  CASE statement not found where expected')

            get_token()

            exprf()            #   Process the conditional expression

            # Check that the top of the jump stack is a CASE statement

            if jump_stack[0][0] != J_CASE:
               error(' Begin - Incorrectly formed CASE expression')

            # Emit a jump to the next CASE element if the condition is not met

            label_name = "_" + str(jump_stack[0][1]) + "C" + str(jump_stack[0][2])
            emit_jump(OP_JFALSE)

            # Process source lines to the next that begins CASE or END

            if look_ahead_token ==  TKN_SEMICOLON:
               get_token()         #  Skip semicolon
               if look_ahead_token > 0:
                  get_token()
                  proc_statement_group()
            else:
               if look_ahead_token > 0:
                  error(' Begin - Incorrectly formed CASE expression')
 
            if look_ahead_token == TKN_END:
                get_token()   #  0219

            #loop
            while True:
            #until u_look_ahead_token_string = "CASE"
                if u_look_ahead_token_string == "CASE":
                    break
            #until u_look_ahead_token_string = "END"
                if u_look_ahead_token_string == "END":
                    break           
            #until end.source
                if end_source == True:
                    break

                proc_line()
            
                if look_ahead_token == TKN_END:
                    get_token()
            #repeat
              
        # until end.source
            if end_source == True:
                break
        # repeat

        # Flag an error if we are at the end of the source

        if end_source == True:
            error('Begin -  Unterminated CASE construct')

         # Check that the END token is followed by CASE

        get_token()             #  Skip END token

        if u_look_ahead_token_string != "CASE":
            error(' Begin - Expected CASE after END')

        get_token()              #  Skip CASE token

        # Emit the exit label
        label_name = "_"+ str(jump_stack[0][1]) + "X"
        set_label()


        jump_stack.pop(0)

      #case TRANSACTION not supported

    # case 1
    else:
         error(' Begin - Expected CASE or TRANSACTION after BEGIN')
    
    #end case
    return

def st_break():
    error(token_string + ' statement not coded')
    return

def st_call():
    """ call statement """
    global symbol_name, symbol_mode, symbol_common_offset, symbol_dim

    if look_ahead_token == TKN_AT_NAME:   # Indirect call
        get_token()    # Skip @ token

      # We cannot always use simple.var.reference to emit the indirection
      # variable as this will see a subroutine with arguments as being a
      # reference to an as yet undimensioned matrix. To minimise the impact
      # of a syntax ambiguity we look the name up in the symbol table here.
      # If we find it as a matrix, we let simple.var.reference do the rest
      # of the job as this will sort out indexing. If we do not find the
      # symbol or it is defined but not as a matrix, we do all the processing
      # here.

        if look_ahead_token_string in symbol_info:
            var_data = symbol_info[look_ahead_token_string]
            if var_data[2] > 0: # It's a matrix
                simple_var_reference()

            else:  # Known, but not a matrix
                get_token()
                symbol_name = token_string
                symbol_mode = SYM_USE
                find_var()   
                emit_var_load()

        else:  # Symbol not already known
            get_token() 

            # 0464 Check to see if it is a defined token.
            if token_string in defined_tokens:
                t_type = defined_tokens[token_string][1]   # get type
            # BCOMP there is code to handle different type of defined_tokens from EQUATE statements.
            # We don't support EQUATES, so you are not going to see it here ......
            # only $define types of Number and String
                error('Call - Name not found where expected')


            symbol_name = token_string
            symbol_mode = SYM_USE
            symbol_common_offset = -1
            symbol_dim = 0
            make_var()
            emit_var_load()

    elif (look_ahead_token == TKN_NAME) or (look_ahead_token == TKN_NAME_LBR) or (look_ahead_token_string == '!')  or (look_ahead_token_string == '*') or (look_ahead_token == TKN_DOLLAR): 
        # Direct call

        sname = get_call_name()     # Read name token
        emit_direct_call_reference(sname)
    else:
      error(' Call - Expected direct or indirect subroutine reference')

    st_call_args()

    return


def st_call_args():
    """Process Call  arguments (if any)""" 
    global symbol_name, symbol_mode, symbol_var_no, symbol_dim, greatest_call_arg_count

    call_arg_count = 0

    if look_ahead_token == TKN_LBR:   # Arguments present
        get_token()

        #loop
        while look_ahead_token != TKN_RBR:
            if u_look_ahead_token_string == "MAT":
                get_token()
                if look_ahead_token != TKN_NAME:
                    error('call_args  Matrix name required')


                get_token()
                symbol_name = token_string
                symbol_mode = SYM_ARG
                find_var()

                if (symbol_var_no < 0) or (symbol_dim == 0):
                    error('Call Args -  Matrix name required')

                emit_var_load()

            elif u_look_ahead_token_string == "VARSET": 
                #gosub get_token()
                #if look_ahead_token # TKN.NAME then
                error(' Call Arg - VARSET not supported ')

            else:
                if look_ahead_token == TKN_LBR:
                    deref = True
                else:
                    deref = False

                symbol_mode = SYM_ARG
                exprf()
                symbol_mode = SYM_USE  

                if deref:
                    emit_simple(OP_VALUE)

            call_arg_count += 1

        #while look_ahead_token = TKN.COMMA
            if look_ahead_token != TKN_COMMA:
                break

            get_token()
        #repeat

        if call_arg_count > 255:
            error('Call Arg - Too many arguments in CALL')

        if look_ahead_token != TKN_RBR:
            error('Call Arg - Right bracket not found where expected') 

        get_token() # Skip close bracket


    if call_arg_count > greatest_call_arg_count:
        greatest_call_arg_count = call_arg_count



    emit(OP_CALL)
    emit(call_arg_count)


    return

def st_case():
    error(token_string + ' statement not coded')
    return

def st_chain():
    error(token_string + ' statement not coded')
    return

def st_clear():
    error(token_string + ' statement not coded')
    return

def st_clearcommon():
    error(token_string + ' statement not coded')
    return

def st_cleardata():
    emit_ldsys(SYSCOM_DATA_QUEUE)
    emit_string_load('')
    emit_simple(OP_STOR)
    return

def st_clearfile():
    error(token_string + ' statement not coded')
    return


def st_clearselect():

    if u_look_ahead_token_string == "ALL":
        get_token()

        emit_simple(OP_CLEARALL)
    else:
        #find u.look.ahead.token.string in reserved.names setting n else n = 0 ;* 0417
        if u_look_ahead_token_string in reserved_names:
            name_found = True
        else:
            name_found = False

        if (name_found) or (look_ahead_token == TKN_END) or (look_ahead_token == TKN_SEMICOLON):
            emit_numeric_load(0)
        else:
            exprf()

        emit_simple(OP_CLEARSEL)

    return

def st_close():
    """Close Statement (and CLOSESEQ)"""
    global thenelse_stack, testlock_stack, onerror_stack

    if look_ahead_token != TKN_NAME and look_ahead_token != TKN_NAME_LBR:
        error('Close - Variable name not found where expected') 

    # gosub convert.pick.file.reference
    get_token()
    emit_var_reference() #            ;* Emit file variable

    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>     #* No THEN or ELSE clause
    thenelse_stack.insert(0,0)
    back_end(OP_CLOSE)
    return

def st_close_socket():
    error(token_string + ' statement not coded')
    return

def st_commit():
    error(token_string + ' statement not coded')
    return

def st_continue():
    global label_name
    label_name = "R"
    continue_exit_common()
    return

def st_convert():
    error(token_string + ' statement not coded')
    return

def st_create():
    error(token_string + ' statement not coded')
    return

def st_create_file():
    """ CREATE.FILE statement"""
#
#     CREATE.FILE path {DIRECTORY
#                      {DYNAMIC 
#                               {GROUP.SIZE group size}
#                               {BIG.REC.SIZE big rec size}
#                               {MIN.MODULUS min modulus}
#                               {SPLIT.LOAD split load}
#                               {MERGE.LOAD merge load}
#                               {FLAGS flags}
#                               {VERSION vno}
    global onerror_stack, testlock_stack, thenelse_stack
    expr()                      # Emit file path name expression

  
    #begin case
    if u_look_ahead_token_string == "DIRECTORY":
        get_token()

        opcode = OP_CREATET1

    elif u_look_ahead_token_string == "DYNAMIC":
        get_token()

        dh_params = ["GROUP.SIZE","BIG.REC.SIZE","MIN.MODULUS","SPLIT.LOAD","MERGE.LOAD","FLAGS","VERSION"]

        #loop
        while True:
            #remove z from dh.params setting param.delimiter
            param = dh_params.pop(0)
            if u_look_ahead_token_string == param:
                get_token()
                expr()
            else:      # Use default
                emit_numeric_load(-1)

        #while param.delimiter
            if len(dh_params) == 0:
                break
        #repeat

        opcode = OP_CREATEDH

    else:
        error('Create_file - Expected DIRECTORY or DYNAMIC after path name')

    #ins '1' before onerror.stack<1>     ;* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>    ;* No LOCKED clause allowed
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>    ;* No THEN / ELSE clause allowed
    thenelse_stack.insert(0,0)

    back_end(opcode)
    return

def st_crt():
    st_display()
    return

def st_data():
    error(token_string + ' statement not coded')
    return

def st_debug():
    error(token_string + ' statement not coded')
    return

def st_del():
    """Del statement"""
    global format_qualifier_allowed

    simple_lvar_reference()
    emit_simple(OP_DUP)

    if look_ahead_token != TKN_LT:
        error('Del - Field reference not found where expected')

    format_qualifier_allowed = False
    is_field_ref()  # Find matching >

    get_token()

    emit_field_reference()
    emit_simple(OP_DEL)
    emit_simple(OP_STOR)

    return

def st_deleteu():
    global lock_opcode
    lock_opcode = OP_ULOCK
    st_delete()
    return

def st_delete():
    global onerror_stack, testlock_stack, thenelse_stack
    # Emit file var

    #gosub convert.pick.file.reference
    exprf()
    check_comma()
    exprf()           # Emit record id expresssion

    # Perform common back-end processing

    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>     #* No THEN or ELSE clause
    thenelse_stack.insert(0,0) 

    back_end(OP_DELETE)

    return

def st_deletelist():
    error(token_string + ' statement not coded')
    return

def st_deleteseq():
    error(token_string + ' statement not coded')
    return

def st_dim():

    global symbol_name, symbol_mode, symbol_dim, symbol_common_offset, symbol_info
    
    #loop
    while True:
        # Get name of array variable

        get_token()
        if token != TKN_NAME_LBR:
            error('Dim -  Matrix dimensions required')


        # Save the symbol name as the dimension processing may overwrite it
        dim_symbol_name = token_string

        symbol_name = token_string
        symbol_mode = SYM_DIM
        find_var()
        if symbol_var_no >= 0: # Exists
            pass
        else:                      #  Make new variable
            symbol_dim = -1        # Indicate not yet known
            symbol_common_offset = -1
            symbol_mode = SYM_DIM
            make_var()


        emit_var_load()  #  Emit LDLCL
        get_token()      #  Skip over left bracket
        exprf()          #  Load first dimension

        if look_ahead_token == TKN_COMMA:   # Two dimensions
            dim_dimensions = 2

            get_token()          # Skip over comma
            exprf()              # Load second dimension
        else:                    # Single dimension
            dim_dimensions = 1

            # Emit load of zero for second dimension

            emit_numeric_load(0)


        # Skip over right bracket
        get_token()

        # Find symbol table entry again

        symbol_name = dim_symbol_name
        symbol_mode = SYM_CHK
        find_var()

        # Check number of dimensions is correct
        # we need to restore the correct symbol key based on
        # lsub_var_no - just like find_var does
        if lsub_var_no >= 0:
            key = lsub_name+symbol_name
        else:
            key = symbol_name

        if symbol_dim < 0:
            var_data = [symbol_var_no , symbol_common_offset, dim_dimensions, -1]
            symbol_info[key] = var_data
        else:
            if symbol_dim != dim_dimensions:
                error('Dim - Number of dimensions differs from previous use')
 

        if symbol_var_no < subr_arg_count:
            # Ignore actual redimensioning by popping ADDR and subscripts
            # Much as we'd like simply to ignore the values of the subscripts,
            # these could feasibly be expressions and it is easier just to let
            # the system evaulate them and then throw the result away than to try
            # to do anything clever to skip the expressions.

            emit_simple(OP_POP)
            emit_simple(OP_POP)
            emit_simple(OP_POP)
        else:
            # Emit DIMLCL or DIMLCLP opcode
            emit_simple(OP_DIMLCL)


    #while look.ahead.token = TKN.COMMA
        if look_ahead_token != TKN_COMMA:
            break
        get_token() # 0084
   #repeat

    return

def st_disinherit():
    error(token_string + ' statement not coded')
    return

def st_display():
    emit_print_list(OP_DSP)
    return

def st_do():
    error(token_string + ' statement not coded')
    return

def st_dparse():
    error(token_string + ' statement not coded')
    return

def st_dparse_csv():
    error(token_string + ' statement not coded')
    return

def st_echo():
    error(token_string + ' statement not coded')
    return

def st_misplaced():
    error(token_string + ' statement not coded')
    return

def st_end():
    global lsub_var_no, final_end_seen

    if lsub_var_no >= 0:  # In a local function/subroutine
        emit_simple(OP_STOP)
        lsub_var_no = -1

    #case object.state = 3  ;* GET or PUBLIC FUNCTION
    #   opcode.byte = OP.LDUNASS ; gosub emit.simple
    #   opcode.byte = OP.RETURN ; gosub emit.simple
    #   object.state = 2
    #   object.arg.names = ''

    #case object.state = 4  ;* SET or PUBLIC SUBROUTINE
    #   opcode.byte = OP.RETURN ; gosub emit.simple
    #   object.state = 2
    #   object.arg.names = ''

    else:
        #* All other uses of END except the end of the program are trapped
        #* elsewhere. There must be nothing but comments (hence blank lines as
        #* returned by the parser) to the end of the source.

        final_end_seen = True

        #loop
        #until end.source
        while not end_source:
            if look_ahead_token > 0:
                error('Non-comment text found after final END statement')
            get_token()
        #repeat

    return

def st_enter():
    error(token_string + ' statement not coded')
    return

def st_errmsg():
    error(token_string + ' statement not coded')
    return

def st_execute():
    """EXECUTE statement"""
    global reserved_names
    # EXECUTE xxx {TRAPPING ABORTS}        Options may be in any order
#             {CAPTURING var}
#             {PASSLIST var}
#             {RTNLIST var}
#             {SETTING | RETURNING var}
#             {CURRENT.LEVEL}            (restricted)


    emit_ldsys(SYSCOM_XEQ_COMMAND)

   # 0265 Add local reserved names

    reserved_names.append("CAPTURING")
    reserved_names.append("PASSLIST")
    reserved_names.append("RETURNING")
    reserved_names.append("RTNLIST")
    reserved_names.append("TRAPPING")
    reserved_names.append("CURRENT.LEVEL")

    exprf()
    emit_simple(OP_STOR)

    execute_flags = 0

   # Look for options

    #loop
    while True:
        #begin case
        if u_look_ahead_token_string == "CURRENT.LEVEL":
            get_token()
            execute_flags = (execute_flags | 0x20)

        elif u_look_ahead_token_string == "TRAPPING":

            if (execute_flags & 1) > 0:
               error('Execute -  Multiple instances of TRAPPING clause')

            get_token()
            if u_look_ahead_token_string != "ABORTS":
               error('Execute -  Expected ABORTS after TRAPPING')

            get_token()
            execute_flags = (execute_flags | 1)

        elif  u_look_ahead_token_string == "CAPTURING":
            if (execute_flags & 2) > 0:
               error('Execute -   Multiple instances of CAPTURING clause')


            get_token()
            simple_lvar_reference()   # Emit LDLCL etc for target
            emit_simple(OP_DUP)
            emit_simple(OP_LDNULL)
            emit_simple(OP_STOR)
            execute_flags = (execute_flags | 2)

            if (execute_flags & 4) > 0:
               # We have found a CAPTURING after a RTNLIST. The addresses
               # on the stack must be swapped to be in the order that
               # op_execute() expects them.
               emit_simple(OP_SWAP)


        elif u_look_ahead_token_string == "PASSLIST":
            get_token()

            # 2.2-13 For compatibility with other systems, the PASSLIST option
            # can be used without a qualifying name. This implies that list 0
            # is to be passed in to the executed command. Given that this is
            # the default behaviour of SD anyway, we simply ignore the PASSLIST
            # if there is no qualifier.

            if (look_ahead_token != TKN_END) and (look_ahead_token != TKN_SEMICOLON):
                #find u_look_ahead_token_string in reserved.names setting i else
                if u_look_ahead_token_string in reserved_names:
                    if (execute_flags & 8) > 0:
                        error('Execute - Multiple instances of PASSLIST clause')
 
                    simple_var_reference()   # Emit LDLCL etc for source
                    emit_simple(OP_PASSLIST)
                    execute_flags = (execute_flags | 8)

        elif (u_look_ahead_token_string == "SETTING") or (u_look_ahead_token_string == "RETURNING"):
            if (execute_flags & 16) >0:
               error('Execute - Multiple instances of SETTING/RETURNING clause')

            emit_temp_ref(1)
            get_token()
            simple_lvar_reference()   # Emit LDLCL etc for target
            emit_simple(OP_SAVEADDR)
            execute_flags = (execute_flags | 16)

        elif u_look_ahead_token_string == "RTNLIST":
            if (execute_flags & 4) > 0:
               error('Execute - Multiple instances of RTNLIST clause')

            get_token()
            simple_lvar_reference()   # Emit LDLCL etc for target
            emit_simple(OP_DUP)
            emit_simple(OP_LDNULL)
            emit_simple(OP_STOR)
            execute_flags = (execute_flags | 4)

        else:
            break
        #end case
    #repeat

    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)


    emit(OP_EXECUTE)
    emit(execute_flags)

    if (execute_flags & 4):  # Transfer select list 0 to var
        emit_simple(OP_RTNLIST)
  

    if (execute_flags & 2):  # Transfer captured command output
        emit_simple(OP_CAPTURE)
  

    if (execute_flags & 16):  # Transfer @system.return.code
        emit_temp_ref(1)
        emit_ldsys(SYSCOM_SYSTEM_RETURN_CODE)      
        emit_simple(OP_STOR)


    return

def st_exit():
    global label_name
    label_name = "X"
    continue_exit_common()
    return

def st_file():
    error(token_string + ' statement not coded')
    return

def st_filelock():
    error(token_string + ' statement not coded')
    return

def st_fileunlock():
    error(token_string + ' statement not coded')
    return

def st_find():
    find_common(OP_FIND)
    return

def st_findstr():
    find_common(OP_FINDSTR)
    return


def st_flush():
    error(token_string + ' statement not coded')
    return

def st_footing():
    error(token_string + ' statement not coded')
    return

def st_for():
    """For Statement"""
       # Add new entry to jump stack
    global jump_no, jump_stack, label_name, for_var
    global token_index, look_ahead_token, look_ahead_token_string, u_look_ahead_token_string 

    jmp_val = [J_FOR,jump_no,0]
    jump_stack.insert(0,jmp_val)

    jump_no += 1

    # Read and hold on to loop control variable name

    if look_ahead_token != TKN_NAME and look_ahead_token != TKN_NAME_LBR:
        error('For loop control variable name not found where expected')

    # Save control variable name and its position in the token list

    #ins look_ahead_token_string:@vm:token.index:@vm:token.index before for.var<1>
    for_val = [look_ahead_token_string,token_index,token_index]
    for_var.insert(0,for_val)
    get_token()

   # If this is a dimensioned array reference, remember start of index
   # expression

    if look_ahead_token == TKN_LBR:
        get_token()

        # Skip forwards to a corresponding right bracket
        n = 1
        #loop
        while True:
            get_token()
            if token == TKN_END:
                error('For do - Right bracket not found where expected')
            if token == TKN_LBR:
                n += 1
            if token == TKN_RBR:
                n -= 1
            if  n <= 0:
                break
        #repeat
        for_val[2] = token_index - 1  # Points to right bracket
        for_var[0] = for_val          # update for current control value

    # Check for "=" token

    if look_ahead_token != TKN_EQ:
        error('For do - Expected = after FOR loop control variable name')

    get_token()            # Skip "="
    expr()                 # Emit initial value

    # Emit FORINIT opcode

    emit_simple(OP_FORINIT)

    # Generate repeat label
    label_name = "_"  + str(jump_no - 1) + "R"
    set_label()
    
    # Check for TO
    # This is done here because the emit.var.reference call below would go
    # wrong if the look-ahead token was a left bracket.

    if u_look_ahead_token_string != "TO":
        error('For do - TO not found where expected')

   # Emit load of control variable
   # This is nasty. Because we need to allow for complex expression such as
   #  FOR A(B+2) = 1 TO 10
   # we cannot just grab hold of the index item above. Instead, we must now
   # process the index expression that we skipped over earlier by rewinding
   # the token processing position, generating the expression and then putting
   # it all back as it was.

    for_pos = token_index
    token_index = for_var[0][1]
    tokens[for_var[0][2] + 1] = TKN_END  # Replace = with end marker
    look_ahead_token = tokens[token_index]
    look_ahead_token_string = token_strings[token_index]
    u_look_ahead_token_string = look_ahead_token_string.upper()
    get_token()
    
    emit_lvar_reference()

    token_index = for_pos
    look_ahead_token = tokens[token_index]
    look_ahead_token_string = token_strings[token_index]
    u_look_ahead_token_string = look_ahead_token_string.upper()

   # Emit final value

    get_token()           # Skip TO
    reserved_names.append("STEP")
    expr()
    reserved_names.pop(-1)

    # Emit step value   

    if u_look_ahead_token_string == "STEP":
        get_token()         ;# Skip STEP
        expr()
        # if bittest(mode, M.FOR.STORE.BEFORE.TEST) then opcode.byte = OP.FORLOOPS NOT SUPPORTED!
        #else opcode.byte = OP.FORLOOP
        emit_simple(OP_FORLOOP)
    else:
        # if bittest(mode, M.FOR.STORE.BEFORE.TEST) then opcode.byte = OP.FOR1S
        #else opcode.byte = OP.FOR1
        emit_simple(OP_FOR1)


    label_name = "_" +str(jump_stack[0][1]) + "X"
    emit_jump_addr()

    if look_ahead_token == TKN_NAME:
        #begin case
        if u_look_ahead_token_string == 'WHILE':
            pass
        elif u_look_ahead_token_string == 'UNTIL':
            pass
        else:
            error('For do - Syntax error')

    return

def st_formlist():
    error(token_string + ' statement not coded')
    return

def st_getlist():
    error(token_string + ' statement not coded')
    return

def st_go():
    if u_look_ahead_token_string == "TO":
        get_token()
    
    st_goto()
    return

def st_goto():
    get_label_name()
    if lsub_var_no >= 0:
        label_name = lsub_name + label_name
    #opcode.byte = OP.JMP ; gosub emit.jump
    emit_jump(OP_JMP)
    return

def st_gosub():
    """GOSUB Statement"""
    global int_subs, int_sub_args, int_sub_is_lsub, int_sub_call_args
    
    get_label_name()

    int_sub_call_args = []     # we are treating as a list, BCOMP treats as a string! Watch for compares!
    if look_ahead_token == TKN_LBR: # Arguments present
        process_int_sub_args()

    
    #locate label.name in int.subs<1> setting pos then
    if label_name in int_subs:
        pos = int_subs.index(label_name)
        if int_sub_call_args == int_sub_args[pos]: 
            pass
        else:        
            error('gosub - Inconsistent argument lists in internal subroutine reference')

    else:
        int_subs.insert(0,label_name)            # Insert at front so that...
        int_sub_args.insert(0,int_sub_call_args) # ...null entries work
        int_sub_is_lsub.insert(0,False)

    emit_jump(OP_GOSUB)

    if look_ahead_token != TKN_END and look_ahead_token != TKN_SEMICOLON:
        #find u.look.ahead.token.string in reserved.names setting n else
        if u_look_ahead_token_string in reserved_names:
            pass
        else:
            error('Gosub - Syntax error')

    return

def process_int_sub_args():
    global symbol_name, symbol_mode, symbol_var_no, symbol_dim, greatest_call_arg_count,  int_sub_call_args      


    call_arg_count = 0
    get_token() #   ;* Skip left bracket

    #loop
    while look_ahead_token != TKN_RBR:

        if u_look_ahead_token_string == "MAT":
            get_token()
            if look_ahead_token != TKN_NAME:
                error('Gosub - Matrix name required')

            get_token()
            symbol_name = token_string
            symbol_mode = SYM_ARG
            find_var()

            if (symbol_var_no < 0) or (symbol_dim == 0):
                error(' Gosub -  Matrix name required')

            emit_var_load()
            int_sub_call_args.append('M')
        else:
            if look_ahead_token == TKN_LBR:
                deref = True
            else:
                deref = False

            symbol_mode = SYM_ARG
            exprf()
            symbol_mode = SYM_USE

            if deref:
                emit_simple(OP_VALUE)

            int_sub_call_args.append('S')

        call_arg_count += 1

        #while look.ahead.token = TKN.COMMA
        if look_ahead_token != TKN_COMMA:
            break
        
        get_token()
    # repeat

    if call_arg_count > 255:
        error('Gosub -  Too many arguments in CALL')

    if look_ahead_token != TKN_RBR:
        error('Gosub - Right bracket not found where expected') 

    get_token() # Skip close bracket

    if call_arg_count > greatest_call_arg_count:
        greatest_call_arg_count = call_arg_count

    return

def st_heading():
    error(token_string + ' statement not coded')
    return

def st_hush():
    error(token_string + ' statement not coded')
    return

def st_if():
    exprf()
    if_back_end()
    return

def st_in():
    error(token_string + ' statement not coded')
    return

def st_include():
    error(token_string + ' statement not coded')
    return

def st_inherit():
    error(token_string + ' statement not coded')
    return

def st_input():
    error(token_string + ' statement not coded')
    return

def st_clearinput():
    emit_simple(OP_CLRINPUT)
    return

def st_inputcsv():
    error(token_string + ' statement not coded')
    return

def st_printerr():
    common_path(OP_PRINTERR)
    return

def st_inputfield():
    error(token_string + ' statement not coded')
    return

def st_ins():
    """Ins Statement"""
    global format_qualifier_allowed
    exprf()

    if u_look_ahead_token_string != "BEFORE":
        error('Ins - BEFORE not found where expected')

    get_token()  # Skip BEFORE

    simple_lvar_reference()

    if look_ahead_token != TKN_LT:
        error('Ins -  Field reference not found where expected')

    format_qualifier_allowed = False
    is_field_ref() #  Find matching >

    get_token()

    emit_field_reference()

    emit_simple(OP_INS)

    return

def st_keyedit():
    error(token_string + ' statement not coded')
    return

def st_keyexit():
    error(token_string + ' statement not coded')
    return

def st_keytrap():
    error(token_string + ' statement not coded')
    return

def st_local():
    """LOCAL SUBROUTINE / FUNCTION statement"""
#
# Note PRIVATE statement for private sub vars is handled in this routine
#   not in st_private (for objects)
#
#    OP_LOCAL
#    Reference variable number  (2 bytes)
#    Number of local variables  (2 bytes)
#    Number of args (1 byte)
#    Number of matrices (2 bytes)
#       Variable number (2 bytes)   } Repeated for
#       Rows (2 bytes)              } each matrix to
#       Cols (2 bytes)              } be dimensioned

    global symbol_name, symbol_dim, symbol_common_offset, symbol_mode, symbol_table, var_count, common_idx
    global int_subs, int_sub_is_lsub, lsub_var_no, lsub_name
    #begin case
    if lsub_var_no >= 0:
        error('Local - Previous local function/subroutine requires END')
    #    case object.state > 2
    #        err.msg = sysmsg(3445) # Previous public function/subroutine requires END
    #        gosub warning
    #        object.state = 2
    #end case

    #begin case
    if u_look_ahead_token_string  == 'FUNCTION':
        is_local_function = True
    elif u_look_ahead_token_string == 'SUBROUTINE':
        is_local_function = False
    elif u_look_ahead_token_string == 'SUB':
        is_local_function = False
    else:
        error(' Local - Expected FUNCTION or SUBROUTINE after LOCAL')
    #end case
    get_token()

    # Emit a STOP so that it is impossible to fall into the subroutine

    emit_simple(OP_STOP)

    # Get name of subroutine/function

    get_label_name()
    lsub_name = label_name +':'
    set_label()

    # Reserve a variable to link to the local pool. This looks just like
    # a common block.

    lvar_no = var_count 
    var_count += 1

    symbol_table.append(lsub_name)
    lsub_var_no = lvar_no

    # create common block entry for lsub
    com_vals = []
    com_vals.append(lvar_no) #0  Local variable number for common  
    com_vals.append(1)             #1 Current size (1 var in common block)
    com_vals.append([])            #2 Element names (list) names of vars in this common block
    com_vals.append([])            #3 Matrix rows   (list) (zero if scalar) 
    com_vals.append([])            #4 Matrix cols   (list) (zero if not 2 dims)
    com_vals.append('')            #5 Pick matrix local var no, else null (always null, not supported)
    com_vals.append(False)         #6 VARSET arg? (true/false)   (always false, not supported)
    com_vals.append(False)         #7 Leave uninitialised? (true/false)
    commons[lsub_name] = com_vals

    common_idx.append(lsub_name)       # save key in our list of commons, ordered by creation 


    symbol_common_offset = 0

    function_args = []
    deref_arg_list = []     # List of variable numbers

    if is_local_function:
        # Insert implicit return argument

        function_args.append('S')
        symbol_name = lsub_name + ':_FUNCRET'
        symbol_dim = 0
        symbol_common_offset += 1
        symbol_mode = SYM_SET
        
        common_index = len(common_idx)
        var_data = [lvar_no, symbol_common_offset, symbol_dim, common_index]
        symbol_info[symbol_name] = var_data


    if look_ahead_token == TKN_LBR:  # Arguments present
        get_token()

        if look_ahead_token != TKN_RBR:   # Arguments present
            #loop
            while True:
                deref_argument = False

                if u_look_ahead_token_string == "MAT":
                    function_args.append('M')
                    symbol_dim = -1   # Indicates not yet known
                    get_token()
                    if look_ahead_token != TKN_NAME:
                        error('Local - Variable name not found where expected')
                else:
                    function_args.append('S')
                    symbol_dim = 0

                    if look_ahead_token == TKN_LBR:
                        deref_argument = True
                        get_token()

                get_var_name()              # Get argument variable name

            # until err # error kills script so redundant
                symbol_name = lsub_name + token_string

                # Make new symbol table entry, checking for duplicate definitions

                if symbol_name in symbol_info:
                    error('Local - Duplicate symbol ' + symbol_name)

                symbol_common_offset += 1
                
                common_index = len(common_idx)
                var_data = [lvar_no, symbol_common_offset, symbol_dim, common_index]
                symbol_info[symbol_name] = var_data

                if deref_argument:
                # Need to dereference this argument
                # We cannot do this at this stage because it must happen
                # after we dimension the pseudo-common block that holds
                # the local variables. Just remember the argument name.

                    deref_arg_list.append(symbol_name)

                    if look_ahead_token != TKN_RBR:
                        error('Local - Right bracket not found where expected') 

                    get_token()

            #while look_ahead_token = TKN.COMMA
                if look_ahead_token != TKN_COMMA:
                    break

                get_token()
                if look_ahead_token == TKN_END:
                    get_token()
            #repeat

            if len(function_args) > 255:
                error('Local -  Too many arguments...')

            if look_ahead_token != TKN_RBR:
                error('Local - Right bracket not found where expected') 


        get_token()     # Skip close bracket


    #locate label.name in int.subs<1> setting pos then
    if label_name in int_subs:
        pos = int_subs.index(label_name)
        if int_sub_args[pos] == function_args: 
            pass
        else:        
            error('Local - Inconsistent argument lists in internal subroutine reference')
        int_sub_is_lsub[pos] = True

    else:
      int_subs.insert(0,label_name)         # Insert at front so that...
      int_sub_args.insert(0,function_args)  # ...null entries work (in bbcmp empty list)
      int_sub_is_lsub.insert(0,True)


    emit_simple(OP_LOCAL)

    # Emit reference variable number
    emit_multibyte_value(lvar_no,2)

    opcode_string = []  # Use this to build the matrix information
                        # is a list of lists [symbol_common_offset,rows,cols]

    # Process PRIVATE local variable declarations

    #loop
    while True:
        #loop
        while look_ahead_token == TKN_END:
            get_token()  # Wrap to next line
        #repeat

    #while u_look_ahead_token_string = 'PRIVATE'
        if u_look_ahead_token_string != 'PRIVATE':
            break

        get_token()  # Skip PRIVATE

        rows = 0
        cols = 0

        #loop
        while True:
            symbol_common_offset += 1
            #begin case
            if look_ahead_token == TKN_NAME:       # Scalar variable
                get_token()
                symbol_name = lsub_name + token_string
                symbol_dim = 0

            elif look_ahead_token == TKN_NAME_LBR:   # Matrix
                get_token()
                symbol_name = lsub_name + token_string

                get_token()             # Skip over left bracket

                rows = get_numeric_constant()

                if rows < 1:
                    error('Local - Illegal row dimension in LOCAL matrix')

                if look_ahead_token == TKN_COMMA:     # Two dimensions
                    get_token()          # Skip over comma

                    cols = get_numeric_constant()

                    if cols < 1:
                        error('Local -  Illegal column dimension in LOCAL matrix')

                    symbol_dim = 2
                else:                                 # Single dimension
                    cols = 0
                    symbol_dim = 1

                opcode_string.append([symbol_common_offset,rows,cols])

                if look_ahead_token != TKN_RBR:
                    error('Local - Right bracket not found where expected') 

                get_token()   # Skip over right bracket

            else:
                error('Local - Local variable name not found where expected')

            #end case

            # Make new symbol table entry, checking for duplicate definitions

            if symbol_name in symbol_info:
                error('Duplicate symbol: ' + symbol_name)

            # update common block entry for variable      
            com_vals[2].append(symbol_name)        # Element names (list) names of vars in this common block
            com_vals[3].append(rows)               # Matrix rows   (list) (zero if scalar) 
            com_vals[4].append(cols)               # Matrix cols   (list) (zero if not 2 dims) 
            commons[lsub_name] = com_vals    
            # create entry in symbol dict for variable
            common_index = len(common_idx)
            var_data = [lvar_no, symbol_common_offset, symbol_dim, common_index]
            symbol_info[symbol_name] = var_data

        #while look_ahead_token = TKN.COMMA
            if look_ahead_token != TKN_COMMA:
                break

            get_token()  # Skip comma
        #repeat

    #repeat

    # Emit local variable count
    emit_multibyte_value(symbol_common_offset,2)

    # Emit argument count
    n = len(function_args)
    emit_multibyte_value(n,1)

    # Emit matrix count
    n = len(opcode_string)
    emit_multibyte_value(n,2)

    for i in range(n):
        # Emit matrix variable number
        #code.value = opcode.string<i,1> ; code.bytes = 2 ; gosub emit.multibyte.value
        n = opcode_string[i][0]
        emit_multibyte_value(n,2)

        # Emit matrix rows
        #code.value = opcode.string<i,2> ; code.bytes = 2 ; gosub emit.multibyte.value
        n = opcode_string[i][1]
        emit_multibyte_value(n,2) 

        # Emit matrix columns
        #code.value = opcode.string<i,3> ; code.bytes = 2 ; gosub emit.multibyte.value
        n = opcode_string[i][2]
        emit_multibyte_value(n,2) 

   # Finally, insert code to dereference any arguments that need it

    if len(deref_arg_list) > 0:
        for i in range(len(deref_arg_list)):
            symbol_name = deref_arg_list[i]
            symbol_mode = SYM_CHK
            find_var()
            emit_var_load()
            emit_simple(OP_DEREF)

    return

def st_locate():
    """Locate Statement"""
    global format_qualifier_allowed
    # note not supporting pick style

    # Emit search expression

    exprf()

    if u_look_ahead_token_string != "IN":
        error('Locate - IN not found where expected')

    get_token()          # Skip IN

    simple_var_reference() 

      # if bittest(mode, M.UV.LOCATE) then standard QM only!


    if look_ahead_token != TKN_LT:
        error('Locate - Field reference not found where expected')

    get_token()                # Skip < token

    format_qualifier_allowed = False
    is_field_ref()
    if ifr_index  == 0:
        error('Locate - Incorrectly formed field reference')

    emit_field_reference()
   

    if u_look_ahead_token_string == "BY":
        get_token()          # Skip BY
        exprf()               # Emit ordering expression
    else:
        emit_string_load('')

    if u_look_ahead_token_string != "SETTING":
        error('Locate - SETTING not found where expected')

    get_token()          # Skip SETTING
    simple_lvar_reference()

    emit_simple(OP_LOCATE)

    if_back_end()           # Join IF statement for THEN / ELSE
    return

def st_lock():
    error(token_string + ' statement not coded')
    return

def st_logmsg():
    error(token_string + ' statement not coded')
    return

def st_loop():
    """LOOP Statement"""
    global jump_stack, jump_no, label_name

    # Add new entry to jump stack
    #ins j.loop:@vm:jump_no before jump.stack<1>
    jmp_val = [J_LOOP,jump_no,0]
    jump_stack.insert(0,jmp_val)

    # Generate label
    label_name = "_" + str(jump_no) + "R"
    set_label()
                
    # Increment JUMP.NO
    jump_no += 1

    return

def st_mark_mapping():
    """ MARK.MAPPING Statement"""
    #gosub convert.pick.file.reference
    exprf()
    check_comma()

    if look_ahead_token ==  TKN_END:
        error('MARK.MAPPING - Expected ON, OFF or expression')


    #begin case
    if (u_look_ahead_token_string == "ON"):
        get_token()
        emit_numeric_load(1)

    elif (u_look_ahead_token_string == "OFF"):
        get_token()
        emit_numeric_load(0)

    else:
        expr()
        emit_simple(OP_INT)
    #end case

    emit_simple(OP_MAPMARKS)
    return

def st_mat():
    """MAT statement"""
    global symbol_name, symbol_mode
    # Get name of target variable
    get_token()

    # Check it is a matrix

    symbol_name = token_string
    symbol_mode = SYM_SET
    find_var()
    if (symbol_var_no < 0) or (symbol_dim <= 0):   # Not a matrix
        error('Mat - Target for MAT must be DIMensioned as a matrix')

    emit_var_load()           # Emit LDLCL or LDCOM for target matrix

    if look_ahead_token != TKN_EQ:
        error('Mat - Expected = after MAT target variable')

    get_token()               # Skip equals sign

    if u_look_ahead_token_string == "MAT":   # Matrix to matrix copy
        get_token()            # Skip MAT
        
        # Get name of source variable

        get_token()

        # Check it is a matrix

        symbol_name = token_string
        find_var()
        if (symbol_var_no < 0) or (symbol_dim == 0):   # Not a matrix
            error('Mat - Dimensioned matrix required')

        emit_var_load()        # Emit LDLCL or LDCOM for target matrix
        emit_simple(OP_MATCOPY)
    else:                                  # Scalar to matrix copy
        exprf()
        emit_simple(OP_MATFILL)
    
    return

def st_matbuild():
    error(token_string + ' statement not coded')
    return

def st_matparse():
    error(token_string + ' statement not coded')
    return

def st_matread():
    error(token_string + ' statement not coded')
    return

def st_matreadcsv():
    error(token_string + ' statement not coded')
    return

def st_matreadl():
    error(token_string + ' statement not coded')
    return

def st_matreadu():
    error(token_string + ' statement not coded')
    return

def st_matwrite():
    error(token_string + ' statement not coded')
    return

def st_matwriteu():
    error(token_string + ' statement not coded')
    return

def st_nap():
    error(token_string + ' statement not coded')
    return

def st_next():
    """NEXT statement"""
    global jump_no, jump_stack, label_name, for_var, symbol_name, symbol_mode
    # Check control variable name
    if look_ahead_token > 0:
        get_token()
        symbol_name = for_var[0][0]
        if token_string != symbol_name:
            error('Next -  Mismatched FOR / NEXT control variables')


    # Look up variable simply to set use flag
    symbol_mode = SYM_USE
    find_var()

    for_var.pop(0)

    # The item at the top of the jump stack must be a FOR construct

    if jump_stack[0][0] != J_FOR:
        error('NEXT not matched by FOR')
              

    # Set up label name for jump to head of loop
    label_name = "_" + str(jump_stack[0][1]) + "R"
    emit_jump(OP_JMP)

    # Generate loop exit label
    label_name = "_" + str(jump_stack[0][1]) + "X"
    set_label()
    jump_stack.pop(0)

   # Skip forwards to end of line or semicolon so that we ignore any subscript
   # on the control variable.

    #loop
    while True:
        if  look_ahead_token == TKN_END:
            break
        if look_ahead_token == TKN_SEMICOLON:
            break
        get_token()
    #repeat

    return

def st_nobuf():
    error(token_string + ' statement not coded')
    return

def st_null():
    # null does nothing
    return

def st_on():
    """ON GOSUB and ON GOTO statements"""
    global int_subs, int_sub_args, int_sub_is_lsub, reserved_names, label_name
    
    # Emit value expression

    reserved_names.append("GOSUB")
    reserved_names.append("GOTO")
    reserved_names.append("GO")
    exprf()
    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)

    #begin case
    if u_look_ahead_token_string == "GOSUB":
        get_token()
        opcode = OP_ONGOSUB
        is_on_gosub = True

    elif u_look_ahead_token_string == "GOTO":
        get_token()
        opcode = OP_ONGOTO
        is_on_gosub = False

    elif u_look_ahead_token_string == "GO":
        get_token()
        if u_look_ahead_token_string == "TO":
            get_token()  # 0503
        opcode = OP_ONGOTO
        is_on_gosub = False

    else:
        error('ON - Expected GOSUB, GOTO or GO')

    #end case

    emit_simple(opcode)


    # Emit jump list

    jump_list = []
    #loop
    while True:
        get_label_name()

        if lsub_var_no >= 0:
            label_name = lsub_name + label_name

        if is_on_gosub:
            if label_name in int_subs:
            #locate label.name in int.subs<1> setting pos then
                pos = int_subs.index(label_name)
                if len(int_sub_args[pos]) > 0:
                    error('ON - Inconsistent argument lists in internal subroutine reference')
            else:

                int_subs.insert(0,label_name)        # Insert at front so that...
                int_sub_args.insert(0,[])            # ...null entries work
                int_sub_is_lsub.insert(0,False)

        jump_list.append(label_name)
    #until look.ahead.token # TKN_COMMA
        if look_ahead_token != TKN_COMMA:
            break
        get_token()      # Skip comma token
        if look_ahead_token == TKN_END:
            get_token()

    #repeat

   # Now that we have the list of labels, we can work out whether we need
   # an extended label count.

    jump_count = len(jump_list)
    if jump_count <= 255:
        emit(jump_count)
    else:
        emit(0)
        emit_multibyte_value(jump_count,2)


   # Emit the jump addresses

    #loop
    while True:
        label_name = jump_list.pop(0)
        emit_jump_addr()
    #while more
        if len(jump_list) <= 0:
            break
    #repeat

 
    return

def st_open():
    reserved_names.append("READONLY")
    
    # Emit first expresssion (file or dict flag)
    exprf()

    if look_ahead_token == TKN_COMMA:
        get_token()      # Skip comma

        # Emit filename expresssion
        exprf()
    else:
        # There was only one expression. Therefore it was the filename. We
        # must emit a null string load and exchange the top two items on
        # the evaluation stack.

        emit_string_load('')
        emit_simple(OP_EXCH)
    open_common(OP_OPEN)
    return

def st_openpath():
    reserved_names.append("READONLY")
    exprf()               # Emit file name expression
    open_common(OP_OPENPATH)
    return

def st_openseq():
    """OPENSEQ statement"""
    global reserved_names, testlock_stack, onerror_stack, thenelse_stack

    opcode = OP_OPENSEQ
    reserved_names.append("APPEND")
    reserved_names.append("OVERWRITE")
    reserved_names.append("READONLY")

    # Emit file expresssion
    exprf()
        
    if look_ahead_token == TKN_COMMA:
        get_token()      # Skip comma
        exprf()          # Emit record expresssion
    else:
        opcode = OP_OPENSEQP

    reserved_names.pop(-1)
    reserved_names.pop(-1)
    reserved_names.pop(-1)

    #begin case
    if u_look_ahead_token_string == 'APPEND':
        get_token()
        emit_simple(OP_SETFLAGS)
        #code.value = 0x100 ; code.bytes = 2 ; 
        emit_multibyte_value(0x100,2)

    elif u_look_ahead_token_string == 'OVERWRITE':
        get_token()
        emit_simple(OP_SETFLAGS)
        # code.value = 0x200 ; code.bytes = 2 ; gosub emit.multibyte.value
        emit_multibyte_value(0x200,2)

    elif u_look_ahead_token_string == 'READONLY':
        get_token()
        emit_simple(OP_READONLY)

         
    if u_look_ahead_token_string != "TO":
        error('Openseq - TO not found where expected')

    get_token()      # Skip "TO"

    # Emit file variable 
    if (look_ahead_token != TKN_NAME) and (look_ahead_token != TKN_NAME.LBR):
        error('Openseq - File variable name not found where expected')


    get_token()
    emit_lvar_reference()

    # Emit a NULL opcode which may be replaced by a TESTLOCK later
    testlock_stack.insert(0,pc)
    emit_simple(OP_NULL)

    # Perform common back-end processing
    #ins '1' before onerror.stack<1>      ;* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE required
    thenelse_stack.insert(0,1)

    back_end(opcode)

    return

def st_os_execute():
    error(token_string + ' statement not coded')
    return

def st_page():
    error(token_string + ' statement not coded')
    return

def st_pause():
    error(token_string + ' statement not coded')
    return

def st_precision():
    error(token_string + ' statement not coded')
    return

def st_print():
    if look_ahead_token == TKN_NAME and u_look_ahead_token_string == "ON":
      get_token()            # Skip "ON"
      expr()
    else:
      emit_numeric_load(0)

    emit_print_list(OP_PRNT)
    return

def st_printer():
    error(token_string + ' statement not coded')
    return

def st_printcsv():
    error(token_string + ' statement not coded')
    return


def st_procread():
    error(token_string + ' statement not coded')
    return

def st_procwrite():
    error(token_string + ' statement not coded')
    return

def st_prompt():
    error(token_string + ' statement not coded')
    return

def st_randomize():
    error(token_string + ' statement not coded')
    return

def st_read():
    read_common(OP_READ)
    return

def st_readblk():
    read_common(OP_READBLK)
    return

def st_readcsv():
    error(token_string + ' statement not coded')
    return

def st_readl():
    global lock_opcode
    lock_opcode = OP_LLOCK
    st_read()
    return

def st_readlist():
    global onerror_stack, testlock_stack, thenelse_stack

    # Emit file variable

    simple_lvar_reference()

    if u_look_ahead_token_string == "FROM":
        get_token()       # Skip FROM
        exprf()            # Emit list number expression
    else:     # Use default select list
        emit_numeric_load(0)

    # Perform common back-end processing

    #ins '0' before onerror.stack<1>        ;* No ON ERROR clause
    onerror_stack.insert(0,0)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>       ;* THEN / ELSE clause required
    thenelse_stack.insert(0,1)

    
    back_end(OP_READLIST)

    return

def st_readnext():
    """readnext statement"""

    global onerror_stack, testlock_stack, thenelse_stack
    # Emit target variable
    simple_lvar_reference()

    if look_ahead_token == TKN_COMMA:      # Exploded form
        opcode = OP_RDNXEXP
        get_token()
        simple_lvar_reference()            # Value position variable
        if look_ahead_token == TKN_COMMA:
            get_token()
            simple_lvar_reference()         # Subvalue position variable
            if look_ahead_token == TKN_COMMA:
                opcode = OP_RDNXINT
                get_token()
                simple_lvar_reference()      # Internal data variable

        else:
            emit_simple(OP_LDUNASS)
        
    else:
        opcode = OP_READNEXT

    if u_look_ahead_token_string == "FROM":
        get_token()       # Skip FROM
        exprf()            # Emit list number expression
    else:     # Use default select list
        emit_numeric_load(0)

    # Perform common back-end processing
   
    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>
    thenelse_stack.insert(0,1)
    back_end(opcode)

    return

def st_readseq():
    error(token_string + ' statement not coded')
    return

def st_readu():
    global lock_opcode
    lock_opcode = OP_ULOCK
    st_read()
    return

def st_readv():
    error(token_string + ' statement not coded')
    return

def st_readvl():
    error(token_string + ' statement not coded')
    return

def st_readvu():
    error(token_string + ' statement not coded')
    return

def st_recordlockl():
    record_lock_common(OP_LLOCK)
    return

def st_recordlocku():
    record_lock_common(OP_ULOCK)
    return

def st_release():
    global onerror_stack, testlock_stack, thenelse_stack
    # gosub convert.pick.file.reference
    #find u_look_ahead_token_string in reserved.names setting i else i = 0 ;* 0303
    if u_look_ahead_token_string in reserved_names:
        not_reserved = False
    else:
        not_reserved = True    

    if (look_ahead_token > 0) and (look_ahead_token != TKN_SEMICOLON) and (u_look_ahead_token_string != "ON") and not_reserved:
        # File variable and/or record id present

        simple_var_reference()  # Emit file variable

        if look_ahead_token == TKN_COMMA:     # Record id supplied
            get_token()
            exprf()
            opcode = OP_RELEASE
        else:
            opcode = OP_RLSFILE    

    else:
        opcode = OP_RLSALL

    # Perform common back-end processing
   
    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>
    thenelse_stack.insert(0,0)            #* No THEN or ELSE clause

    back_end(opcode)
    return


def st_remark():
    """burn off remark tokens """
    while token > 0:
        get_token()

def st_remove():
    remove_common(OP_REMOVE)
    return

def st_remove_break_handler():
    error(token_string + ' statement not coded')
    return

def st_repeat():
    """REPEAT statement"""
    global label_name, jump_stack
    # The item at the top of the jump stack must be a loop construct
    if jump_stack[0][0] == J_LOOP:

        # Set up label name for loop repeat jump
        label_name = "_" + str(jump_stack[0][1]) + "R"
        emit_jump(OP_JMP)

        # Generate loop exit label
        label_name = "_" + str(jump_stack[0][1]) + "X"
        set_label()
        jump_stack.pop(0)

    else:
        error('REPEAT not matched by LOOP')

    return

def st_restore_screen():
    simple_var_reference()   # Screen image variable
    check_comma()
    exprf()                  # Full or partial restore?
    emit_simple(OP_RSTSCRN) 
    return

def st_return():
    """return statement"""
    global symbol_name, symbol_mode
#*****************************************************************************
# ST.RETURN  -  RETURN statement
#    Variants:
#       RETURN                      Return from GOSUB or CALL
#       RETURN TO label             Jump to label, removing call level
#                                   Acts as RETURN if not in GOSUB
#       RETURN VALUE expression     Leave value on e-stack (restricted)

    if u_look_ahead_token_string in reserved_names:
        res_name = True
    else:
        res_name = False
   
    #begin case
    if u_look_ahead_token_string == "TO":
        if lsub_var_no >= 0:
            error('Return - Statement not allowed inside a LOCAL subroutine or function')
 
        get_token()
        get_label_name()
        emit_jump(OP_RETURNTO)
        return

    elif u_look_ahead_token_string == "VALUE":
        get_token()  # Read VALUE token
        exprf()
        emit_simple(OP_VALUE)

    elif res_name or (look_ahead_token == TKN_END) or (look_ahead_token == TKN_SEMICOLON):
        pass

    else:
        # begin case
        if is_local_function:
            symbol_name = lsub_name + ':_FUNCRET'

        elif header_flags & HDR_IS_FUNCTION:    # set by st_function
            symbol_name = "_FUNCRET"

        else:
            error('Return - Return value only allowed in functions')

        symbol_mode = SYM_SET
        find_var()
        emit_var_load()
        exprf()
        emit_simple(OP_STOR)
    #end case

    if lsub_var_no >= 0:
        emit_simple(OP_DELLCL)
        emit_multibyte_value(lsub_var_no,2)

#exit.st.return:
    emit_simple(OP_RETURN)

    return

def st_rollback():
    error(token_string + ' statement not coded')
    return

def st_sleep():
    error(token_string + ' statement not coded')
    return

def st_savelist():
    error(token_string + ' statement not coded')
    return

def st_seek():
    error(token_string + ' statement not coded')
    return

def st_select():
    select_common(OP_SELECT)
    return

def st_selecte():
    error(token_string + ' statement not coded')
    return

def st_selectindex():
    opcode = OP_SELINDX
    expr()                  # Emit index name

    if look_ahead_token == TKN_COMMA:
        opcode = OP_SELINDXV
        get_token()          # Skip comma
        expr()               # Emit indexed value

    if u_look_ahead_token_string != 'FROM':
        error(' Selectindex - FROM not found where expected')
    
    get_token()

    #gosub convert.pick.file.reference
    simple_var_reference()  # Emit file variable

    if u_look_ahead_token_string == "TO":
        get_token()          # Skip TO
        exprf()              # Emit list number expression
    else:                    # Use default select list
        emit_numeric_load(0)

    emit_simple(opcode)

    return

def st_selectleft():
    error(token_string + ' statement not coded')
    return

def st_selectn():
    select_common(OP_SELECT)
    return

def st_selectright():
    error(token_string + ' statement not coded')
    return

def st_selectv():
    select_common(OP_SELECTV)
    return

def st_sendmail():
    error(token_string + ' statement not coded')
    return

def st_set_arg():
    error(token_string + ' statement not coded')
    return

def st_set_break_handler():
    error(token_string + ' statement not coded')
    return

def st_set_exit_status():
    error(token_string + ' statement not coded')
    return

def st_setleft():
    error(token_string + ' statement not coded')
    return

def st_setnls():
    error(token_string + ' statement not coded')
    return

def st_setpu():
    error(token_string + ' statement not coded')
    return

def st_setright():
    error(token_string + ' statement not coded')
    return

def st_setrem():
    """SETREM - set remove pointer"""
    exprf()  # Process remove pointer position expression

    if u_look_ahead_token_string != "ON":
        error('Setrem - not found where expected')

    get_token()  # Skip "ON"

    get_token()
    emit_lvar_reference()  # Emit target variable reference

    emit_simple(OP_SETREM)
    
    return

def st_sleep():
    error(token_string + ' statement not coded')
    return

def st_sselect():
    select_common(OP_SSELECT)
    return

def st_status():
    error(token_string + ' statement not coded')
    return

def st_stop():
    stop_common()
    return

def st_stope():
    error(token_string + ' statement not coded')
    return

def st_stopm():
    error(token_string + ' statement not coded')
    return

def st_tclread():
    error(token_string + ' statement not coded')
    return

def st_timeout():
    error(token_string + ' statement not coded')
    return

def st_transaction():
    error(token_string + ' statement not coded')
    return

def st_ttyset():
    error(token_string + ' statement not coded')
    return

def st_unlock():
    error(token_string + ' statement not coded')
    return

def st_until():
    st_while_until_common(OP_JTRUE)
    return

def st_void():
    error(token_string + ' statement not coded')
    return

def st_wake():
    error(token_string + ' statement not coded')
    return

def st_weofseq():
    error(token_string + ' statement not coded')
    return

def st_while():
    st_while_until_common(OP_JFALSE)
    return

def st_while_until_common(opcode):
    # Work down jump stack until we find a LOOP or FOR construct
    global label_name
    j_index = 0

    jmp_stack_items = len(jump_stack)
    #loop
    while True:
        if j_index >= jmp_stack_items:     # add this test (dyn array ref will return null if not defined, lists will overflow)
            error('While / Until - Misplaced ' + token_string)

        jmp_type = jump_stack[j_index][0]
    #until (n = j.loop) or (n = j.for)
        if (jmp_type == J_LOOP) or (jmp_type == J_FOR):
            break
        if jmp_type ==  0:
            error('While / Until - Misplaced ' + token_string)
        j_index += 1
    # repeat

    exprf()
    label_name = "_" + str(jump_stack[j_index][1]) + "X"
    emit_jump(opcode)

    if u_look_ahead_token_string == "DO":
        get_token()

    return

def st_write():
    st_write_common(OP_WRITE)
    return

def st_write_common(opcode):
    """Common routine for all write operations"""
    global onerror_stack, testlock_stack, thenelse_stack
    # skipping FILE statement code
    exprf()    #Get record to write

    if (u_look_ahead_token_string != "TO") and (u_look_ahead_token_string != "ON"):
        error('write_common - TO or ON not found where expected') 
    
    get_token()   # Skip TO/ON token

    # Emit file variable

    simple_var_reference()
    check_comma()
    exprf()           # Get record id

    if opcode == OP_WRITEV:
        check_comma()
        exprf()  # Emit field number expression

    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>     #* No THEN or ELSE clause
    thenelse_stack.insert(0,0)    
    back_end(opcode)
    return

def st_writeblk():
    error(token_string + ' statement not coded')
    return

def st_writecsv():
    error(token_string + ' statement not coded')
    return

def st_writeseq():
    write_seq_common(OP_WRITESEQ)
    return

def st_writeseqf():
    error(token_string + ' statement not coded')
    return

def st_writeu():
    global lock_opcode
    lock_opcode = OP_ULOCK
    st_write()
    return

def st_writev():
    st_write_common(OP_WRITEV)
    return

def st_writevu():
    error(token_string + ' statement not coded')
    return

def st_class():
    error('class statement not coded')
    return
    
def st_common():
    # varset.arg.no = -1  for varset unknow statement, not coding
    common_name = ""

    if look_ahead_token == TKN_IDIV:    # 0182  Allow for COMMON // A,B,C        
        get_token()
    elif look_ahead_token == TKN_DIV:   #  Named common
        get_token()
        common_name = get_name()

        if look_ahead_token != TKN_DIV:
            error('Expected / after common block name')

        get_token()

    st_common_common(common_name)

    return
   
def st_common_common(common_name):
    global symbol_var_no, commons, var_count, symbol_common_offset, symbol_table, symbol_name, symbol_dim, symbol_info, common_idx 
    # loop
    while True:
        # Find common block

        if len(common_name) > 0:
            s = common_name
        else:
            s = "$"

        # 0397 commons array was scanned with AL sort but symbol table relied
        #* on position not changing. Removed the sort clause.
        #
        # locate s in commons<1,1> setting common.index then
        #
        # in BCOMP we used DYN arrays, the locate would find the common name in 
        # array s, setting common.index OR set common.index such that its info would 
        # be appended to the end of the DYN array
        # For an unordered LOCATE this will be such that it would be appended.
        #
        # we mimic the common.index value by counting the number of items in 
        # commons each time we create a new entry (below)
       

        if s in commons:
            com_vals = commons[s]
            symbol_var_no = com_vals[0]             # 0/F2 = Local variable number for common
            symbol_common_offset = com_vals[1] + 1  # 1/F3 = Current size + 1 for the one we are adding
            com_vals[1] = symbol_common_offset      # and update for this common
            commons[s] = com_vals

        else:
            # Make new common block
            #if varset.arg.no >= 0 then           # not supporting varset
            #    symbol.var.no = varset.arg.no
            #end else
            symbol_var_no = var_count
            var_count += 1
            #end

            symbol_common_offset = 1      # Offset 0 holds common block name
            symbol_table.append(s)
            
            com_vals = []
            com_vals.append(symbol_var_no) #0  Local variable number for common  
            com_vals.append(1)             #1 Current size (1 var in common block)
            com_vals.append([])            #2 Element names (list) names of vars in this common block
            com_vals.append([])            #3 Matrix rows   (list) (zero if scalar) 
            com_vals.append([])            #4 Matrix cols   (list) (zero if not 2 dims)
            com_vals.append('')            #5 Pick matrix local var no, else null (always null, not supported)
            com_vals.append(False)         #6 VARSET arg? (true/false)   (always false, not supported)
            com_vals.append(False)         #7 Leave uninitialised? (true/false)

            common_idx.append(s)       # save key in our list of commons, ordered by creation 

        # Process variables

        rows = 0
        cols = 0

        #begin case
        if look_ahead_token == TKN_NAME:     # Scalar variable
            get_token()
            symbol_name = token_string
            symbol_dim = 0

        elif look_ahead_token == TKN_NAME_LBR:   #* Matrix
            get_token()
            symbol_name = token_string

            get_token()      # Skip over left bracket

            n = get_numeric_constant()

            rows = n

            if rows < 1: 
                error('Illegal row dimension in common matrix')

            if look_ahead_token == TKN_COMMA:   #  Two dimensions
                get_token()    # Skip over comma

                n = get_numeric_constant()
                cols = n

                if cols < 1: 
                    error('Illegal column dimension in common matrix')

                symbol_dim = 2

            else:   # Single dimension
                cols = 0
                symbol_dim = 1


            if look_ahead_token != TKN_RBR:
                error('Right bracket not found where expected') 

            get_token()  # Skip over right bracket

        else:
            error('Common variable name not found where expected')

        # Make new symbol table entry, checking for duplicate definitions

 
        if symbol_name in symbol_info:
            error('Duplicate symbol: ' + symbol_name)

    
        com_vals[2].append(symbol_name)        # Element names (list) names of vars in this common block
        com_vals[3].append(rows)               # Matrix rows   (list) (zero if scalar) 
        com_vals[4].append(cols)               # Matrix cols   (list) (zero if not 2 dims) 
        commons[s] = com_vals

        common_index = len(common_idx)

        var_data = [symbol_var_no, symbol_common_offset, symbol_dim, common_index]


        symbol_info[symbol_name] = var_data
 
    #While look.ahead.token = TKN.COMMA

        if look_ahead_token != TKN_COMMA:
            break

        get_token()  # Read comma token
    #repeat

    return
   
def st_deffun():
    """ DEFFUN statement """
    global functions, greatest_call_arg_count, int_subs, int_sub_args, int_sub_is_lsub

    get_token()
    if token != TKN_NAME and token != TKN_NAME_LBR:
        error('Deffun - Expected function name after DEFFUN')

    function_name = token_string
    #locate function.name in functions<1,1> by 'AL' setting func.index then
    if function_name in functions:
        error('Deffun - Duplicate function name ' + function_name)


    function_call_name = function_name
    function_args = []
    function_key = ''
    var_args = False

    st_work = 0   # 1 = external feature used, 2 = internal feature used

    if look_ahead_token == TKN_LBR:
        get_token()  # Skip bracket
        if look_ahead_token == TKN_NAME:
            #loop
            while True:
                get_token()

                if u_token_string == 'MAT':
                    function_args.append('M')
                    get_token()
                else:
                    function_args.append('S')

                if token != TKN_NAME:
                    error('Deffun - Function argument name not found where expected')

            #while look_ahead_token = TKN_COMMA
                if look_ahead_token != TKN_COMMA:
                    break
                get_token()
            #repeat

        get_token()
        if token != TKN_RBR:
            error('Deffun - Right bracket not found where expected')


    #loop
    while True:
        #begin case
        if  u_look_ahead_token_string == "CALLING":
            get_token()  # Skip CALLING
            get_token()
            if token != TKN_STRING:
                error('Deffun - Expected quoted call name after CALLING')

            function_call_name = u_token_string
            st_work =  (st_work | 1)

        elif u_look_ahead_token_string == "KEY":
            get_token()  # Skip KEY
            get_token()
            if (token != TKN_NUM) and (token != TKN_STRING):
                error('Deffun - Expected function key after KEY')

            if len(token_string) == 0:
                error('Deffun - Function key cannot be a null string')

            function_key = token_string

        elif u_look_ahead_token_string == "LOCAL":
            get_token()  # Skip LOCAL
            function_call_name = ''
            st_work = (st_work | 2)

        elif u_look_ahead_token_string == "VAR.ARGS":
            get_token()  # Skip VAR.ARGS
            var_args = True
            st_work = (st_work | 1)

        else:
            break
        #end case
    #repeat

    if (look_ahead_token != TKN_END) or (st_work == 3):
        error('Deffun - Misformed DEFFUN')

    if len(function_args) > 254:
        error('Deffun - Too many arguments is function definition')

    if len(function_args) > greatest_call_arg_count:
        greatest_call_arg_count = len(function_args)

    fun_val = [function_call_name, function_args, function_key,var_args]
    functions[function_name] = fun_val

    if len(function_call_name) == 0:   # Internal function
        function_args.insert(0,'S')    # Insert return argument

        #locate function.name in int.subs<1> setting pos then
        if function_name in int_subs:
            pos = int_subs.index(function_name)
            if function_args == int_sub_args[pos]:
                pass
            else:
                error('Deffun - Inconsistent argument lists in internal subroutine reference')
        else:
            #ins function.name before int.subs<1>     # Insert at front so that...
            #ins function.args before int.sub.args<1> # ...null entries work
            #ins @false before int.sub.is.lsub<1>
            int_subs.insert(0,function_name)          # Insert at front so that...
            int_sub_args.insert(0,function_args)      # ...null entries work
            int_sub_is_lsub.insert(0,False)

    return

def st_equate():
    """minimal support for equate"""
    global defined_tokens
    # for now support equate to number and char function only!
    if look_ahead_token != TKN_NAME:
         error('Equate - token name not found where expected')
    get_token()
    define_key = token_string

    if define_key in defined_tokens:
        error('Equate - Duplicate EQUATE / $DEFINE token: ' + define_key)

    if u_look_ahead_token_string != "TO":
        error('Equate - "TO" not found where expected')
    
    get_token()
    get_token()

    if token == TKN_NUM:
        defined_tokens[define_key] = [int(token_string), is_number]   

    elif token == TKN_STRING:
         defined_tokens[define_key] = [token_string, is_string] 

    elif token == TKN_NAME_LBR:
        if u_token_string == 'CHAR':
            get_token()
            get_token()
            if token != TKN_NUM:
                error('Equate - Expected character number for Char()')
            if int(token_string) < 0 or int(token_string) > 255:
                error('Equate - Character number must be in range 0 to 255')
            defined_tokens[define_key] = [int(token_string), is_charfunct]
    else:
        error('Equate - unsupprted equate statement:' + token_string)

    if look_ahead_token != TKN_RBR:
        error('Equate - Right bracket not found were expected')
    
    get_token()

    return
   
def st_function():
    global name_set, program_name, symbol_name, symbol_dim, symbol_mode, symbol_common_offset, header_flags, subr_arg_count

    if name_set:
        error('Function - A PROGRAM, SUBROUTINE, FUNCTION or CLASS statement has already been processed') 

    if pc != start_pc:
        error('Function - FUNCTION must appear before any executable statements')


    # Get name of function

    if look_ahead_token != TKN_LBR:
        program_name = get_call_name()
        if len(program_name) > HDR_PROGRAM_NAME_LEN:
            error('Function - FUNCTION Name exceeds HDR_PROGRAM_NAME_LEN')

    name_set = True
    
    #Insert implicit return argument

    symbol_name = "_FUNCRET"
    symbol_dim = 0
    symbol_common_offset = -1
    symbol_mode = SYM_SET
    make_var()

    header_flags = (header_flags | HDR_IS_FUNCTION)  

    subr_arg_count = 1

   # Process any further arguments

    if look_ahead_token == TKN_LBR:
        get_token()

        if look_ahead_token != TKN_RBR:   # Arguments present
            #loop
            while True:
                deref_argument = False

                if u_look_ahead_token_string == "MAT":
                    dim_dimensions = -1   # Indicates not yet known
                    get_token()
                    #if err then return
                    if look_ahead_token != TKN_NAME:
                        error('Function - Variable name not found where expected')
                else:
                    dim_dimensions = 0

                    if look_ahead_token == TKN_LBR:
                        # Need to dereference this argument
                        deref_argument = True
                        get_token()

                get_var_name()              # Get argument variable name
            #until err

                # Check that variable is not present twice in argument list

                symbol_name = token_string
                symbol_mode = SYM_ARG
                find_var()

                if symbol_var_no >= 0:
                    error('Function - Duplicate argument name ' +  symbol_name)


                if look_ahead_token ==  TKN_LBR:  # Matrix dimensions
                    get_arg_mat_dimensions()

                # Make variable for argument

                symbol_common_offset = -1
                symbol_dim = dim_dimensions
                symbol_mode = SYM_ARG
                make_var()

                if deref_argument:
                    if look_ahead_token != TKN_RBR:
                        error('Function - Right bracket not found where expected')

                    get_token()
                    emit_var_load()
                    emit_simple(OP_DEREF)

                subr_arg_count += 1

            #while look_ahead_token = TKN.COMMA
                if look_ahead_token != TKN_COMMA:
                    break

                get_token()
                if look_ahead_token == TKN_END:
                    get_token()
            #repeat

            if subr_arg_count > 255:
                error('Function - Too many arguments in function definition')
                 

            if look_ahead_token != TKN_RBR:
                error('Function - Right bracket not found where expected')
      

        get_token()     # Skip close bracket
 
    if u_look_ahead_token_string == 'VAR.ARGS':
        get_token()
        header_flags = (header_flags | HDR_VAR_ARGS)  # set function has var nbr of args flag 

    return

def st_get():
    error(token_string + ' statement not coded')
    return

def st_private():
    error(token_string + ' statement not coded')
    return

def st_program():
    """PROGRAM statement"""
    global name_set, program_name

    if name_set:
        error('A PROGRAM, SUBROUTINE, FUNCTION or CLASS statement has already been processed')

    if pc != start_pc:
        error('PROGRAM must appear before any executable statements')

    # Get name of program

    s = get_name()
    program_name = s[:HDR_PROGRAM_NAME_LEN]
    if len(s) > HDR_PROGRAM_NAME_LEN:
        error(' Program name exceeds max lenght')

    name_set = True

    return  


def st_public():
    error(token_string + ' statement not coded')
    return

def st_set():
    error(token_string + ' statement not coded')
    return

def st_subroutine():
    """SUBROUTINE statement"""
    global program_name, name_set, symbol_name, symbol_mode, symbol_dim, symbol_common_offset, subr_arg_count

    if name_set:
        error('A PROGRAM, SUBROUTINE or FUNCTION statement has already been processed') 

    if pc != start_pc:
        error('SUBROUTINE must appear before any executable statements')

    # Get name of subroutine

    if look_ahead_token != TKN_END and look_ahead_token != TKN_SEMICOLON:
        if look_ahead_token != TKN_LBR:
            program_name = get_call_name()
            if len(program_name) > HDR_PROGRAM_NAME_LEN:
                error(' Name exceeds HDR_PROGRAM_NAME_LEN')

    name_set = True

    if look_ahead_token == TKN_LBR:
        get_token()

        if look_ahead_token != TKN_RBR: #  Arguments present
            
            #loop
            while True:
                deref_argument = False

                if u_look_ahead_token_string == "MAT":
                    dim_dimensions = -1  # Indicates not yet known
                    get_token()
                    if look_ahead_token != TKN_NAME:
                        error('Variable name not found where expected') 
                    # end else u_look_ahead_token_string =  varset - not supported
                else:
                    dim_dimensions = 0

                    if look_ahead_token == TKN_LBR:
                        # Need to dereference this argument
                        deref_argument = True
                        get_token()


                get_var_name()  # Get argument variable name
            # until err (if we have an error script terminates, redundant)

                # Check that variable is not present twice in argument list

                symbol_name = token_string
                symbol_mode = SYM_ARG
                find_var()

                if symbol_var_no >= 0:
                    error('Subroutine -  Duplicate argument name ' + symbol_name)


                if look_ahead_token == TKN_LBR: # Matrix dimensions
                    dim_dimensions = get_arg_mat_dimensions()

                # Make variable for argument

                symbol_common_offset = -1
                symbol_dim = dim_dimensions
                symbol_mode = SYM_ARG
                make_var()

                if deref_argument:
                    if look_ahead_token != TKN_RBR:
                        error('Subroutine - Right bracket not found where expected') 
                    get_token()
                    emit_var_load()
                    emit_simple(OP_DEREF)
  

#    st.subroutine.varset.continue:
                subr_arg_count += 1

            #while look_ahead_token = TKN.COMMA
                if look_ahead_token != TKN_COMMA:
                    break

                get_token()
                if look_ahead_token == TKN_END:
                    get_token()
            #repeat

            if subr_arg_count > 255:
                error('Subroutine - Too many arguments')


            if look_ahead_token != TKN_RBR:
                error('Subroutine - Right bracket not found where expected') 
 

        get_token()     # Skip close bracket


    if u_look_ahead_token_string == 'VAR.ARGS':
        get_token()
        header_flags = (header_flags | HDR_VAR_ARGS)  # set subroutine has var nbr of args flag 


    return

def st_add():
    """ ADD statement (restricted) """
    # ADD keys {,data} TO btree
    global symbol_name

    if look_ahead_token == TKN_NAME:
        get_token()
        symbol_name = token_string
        find_var()

        if symbol_var_no < 0:
            error('Add -  Key variable symbol must be defined before ADD statement')

        #begin case
        if  symbol_dim == 0:
            opcode = OP_BTADD

        elif symbol_dim == 1:
            opcode = OP_BTADDA

        else:
            error('Add - Scalar or one dimensional matrix name required')

        #end case

        emit_var_load()
    else:
        exprf()
        opcode = OP_BTADD


    if look_ahead_token == TKN_COMMA:
        get_token()       # Skip comma
        exprf()           # Process data expression
    else:
        emit_string_load('')

    if u_look_ahead_token_string != 'TO':
        error('Add - TO not found where expected')

    get_token()             #Skip 'TO'

    simple_lvar_reference()  # BTree variable
    emit_simple(opcode)
 
    return

def st_akclear():
    error(token_string + ' statement not coded')
    return

def st_akdelete():
    global onerror_stack, testlock_stack, thenelse_stack 

    if u_look_ahead_token_string == "FROM":
        get_token()      # Skip FROM token
        expr()            # Get file
        check_comma()
    else:

        emit_simple(OP_LDUNASS)


    exprf()           # Get AK number
    check_comma()
    exprf()           # Get record id

  
    opcode = OP_AKDELETE
    #ins '0' before onerror.stack<1>      ;* No ON ERROR clause
    onerror_stack.insert(0,0)
    #ins '0' before testlock.stack<1>     ;* No LOCKED clause allowed
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE required
    thenelse_stack.insert(0,1)

    back_end(opcode)
    return

def st_akenable():
    error(token_string + ' statement not coded')
    return

def st_akread():
    global onerror_stack, testlock_stack, thenelse_stack
    
    simple_lvar_reference()   # Emit target variable
    if u_look_ahead_token_string == "FROM":
        get_token()      # Skip FROM token
        expr()            # Get file
        check_comma()
    else:
        emit_simple(OP_LDUNASS)


    exprf()          # Get AK number
    check_comma()
    exprf()          #Get record id

    opcode = OP_AKREAD
    #ins '0' before onerror.stack<1>      ;* No ON ERROR clause
    onerror_stack.insert(0,0)
    #ins '0' before testlock.stack<1>     ;* No LOCKED clause allowed
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE required
    thenelse_stack.insert(0,1)

    back_end(opcode)
    return

def st_akrelease():
    emit_simple(OP_AKRELEASE)
    return

def st_akwrite():
    global onerror_stack, testlock_stack, thenelse_stack
    expr()            # Get record to write

    if (u_look_ahead_token_string == "TO") or (u_look_ahead_token_string == "ON"):
        get_token()      # Skip TO/ON token
        expr()            # Get file
        check_comma()
    else:
        emit_simple(OP_LDUNASS)

    exprf()           # Get AK number
    check_comma()
    exprf()           # Get record id

    opcode = OP_AKWRITE
    #ins '0' before onerror.stack<1>      ;* No ON ERROR clause
    onerror_stack.insert(0,0)
    #ins '0' before testlock.stack<1>     ;* No LOCKED clause allowed
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE required
    thenelse_stack.insert(0,1)
   
    back_end(opcode)
    return

def st_breakpoint():
    error(token_string + ' statement not coded')
    return

def st_callv():
    error(token_string + ' statement not coded')
    return

def st_como():
    error(token_string + ' statement not coded')
    return

def st_configure_file():
    error(token_string + ' statement not coded')
    return

def st_create_ak():
    error(token_string + ' statement not coded')
    return

def st_debug_off():
    error(token_string + ' statement not coded')
    return

def st_debug_on():
    error(token_string + ' statement not coded')
    return

def st_debug_set():
    error(token_string + ' statement not coded')
    return

def st_delete_ak():
    error(token_string + ' statement not coded')
    return

def st_delete_common():
    common_path(OP_DELCOM)
    return

def st_keyboard_input():
    error(token_string + ' statement not coded')
    return

def st_modify():
    """ ST.MODIFY  -  MODIFY statement (restricted) """
    # MODIFY btree, data
    simple_lvar_reference() # BTree variable
    check_comma()
    exprf()
    emit_simple(OP_BTMODIFY)

    return

def st_quit():
    error(token_string + ' statement not coded')
    return

def st_release_lock():
    error(token_string + ' statement not coded')
    return

def st_remove_token():
    remove_common(OP_RMVTKN)
    return

def st_reset_modes():
    error(token_string + ' statement not coded')
    return

def st_rewind():
    """ ST.REWIND  -  REWIND statement (restricted)"""

    simple_var_reference()  # BTree variable
    emit_simple(OP_BTRESET)

    return

def st_run():
    error(token_string + ' statement not coded')
    return

def st_set_modes():
    error(token_string + ' statement not coded')
    return

def st_set_status():
    common_path(OP_SETSTAT)
    return

def st_set_trigger():
    error(token_string + ' statement not coded')
    return

def st_set_unassigned():
    error(token_string + ' statement not coded')
    return

def st_sortadd():
    global symbol_name
    if look_ahead_token != TKN_NAME:
        error('Sortadd - Variable name not found where expected') 
    
    get_token()
    symbol_name = token_string
    find_var()
    if (symbol_var_no < 0) or (symbol_dim != 1):
        error('Sortadd - One dimensional matrix name required')
 
    emit_var_load()    # Emit key array
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()            # Emit data
    else:
        emit_simple(OP_LDUNASS)
 
    emit_simple(OP_SORTADD)
    return

def st_sortclear():
    emit_simple(OP_SORTCLR)
    return

def st_sortinit():
    global symbol_name

    expr()    # Emit key count

    check_comma()
    if look_ahead_token != TKN_NAME:
        error('SortInit - Variable name not found where expected') 

    get_token()
    symbol_name = token_string
    find_var()
    if (symbol_var_no < 0) or (symbol_dim != 1):
        error('SortInit - One dimensional matrix name required')

    emit_var_load()    # Emit key array

    emit_simple(OP_SORTINIT)

    return

def st_trace():
    error(token_string + ' statement not coded')
    return

def st_unload_object():
    emit_simple(OP_UNLOAD)
    return

def st_varset():
    error(token_string + ' statement not coded')
    return

def st_watch():
    error(token_string + ' statement not coded')
    return

def st_writepkt():
    error(token_string + ' statement not coded')
    return

STATEMENTS = {
"ABORT":  st_abort,
"ABORTE":  st_aborte,
"ABORTM":  st_abortm,
"BEGIN":  st_begin,
"BREAK":  st_break,
"CALL":  st_call,
"CASE":  st_case,
"CHAIN":  st_chain,
"CLEAR":  st_clear,
"CLEARCOMMON":  st_clearcommon,
"CLEARDATA":  st_cleardata,
"CLEARFILE":  st_clearfile,
"CLEARINPUT":  st_clearinput,
"CLEARSELECT":  st_clearselect,
"CLOSE":  st_close,
"CLOSESEQ":  st_close,                
"CLOSE.SOCKET":  st_close_socket,
"COMMIT":  st_commit,
"CONTINUE":  st_continue,
"CONVERT":  st_convert,
"CREATE":  st_create,
"CREATE.FILE":  st_create_file,
"CRT":  st_crt,
"DATA":  st_data,
"DEBUG":  st_debug,
"DEL":  st_del,
"DELETE":  st_delete,
"DELETELIST":  st_deletelist,
"DELETESEQ":  st_deleteseq,
"DELETEU":  st_deleteu,
"DIM":  st_dim,
"DIMENSION":  st_dim,                  
"DISINHERIT":  st_disinherit,
"DISPLAY":  st_display,
"DO":  st_do,
"DPARSE":  st_dparse,
"DPARSE.CSV":  st_dparse_csv,
"ECHO":  st_echo,
"ELSE":  st_misplaced,            
"END":  st_end,
"ENTER":  st_enter,
"ERRMSG":  st_errmsg,
"EXECUTE":  st_execute,
"EXIT":  st_exit,
"FILE":  st_file,
"FILELOCK":  st_filelock,
"FILEUNLOCK":  st_fileunlock,
"FIND":  st_find,
"FINDSTR":  st_findstr,
"FLUSH":  st_flush,
"FOOTING":  st_footing,
"FOR":  st_for,
"FORMLIST":  st_formlist,
"GETLIST":  st_getlist,
"GO":  st_go,
"GOSUB":  st_gosub,
"GOTO":  st_goto,
"HEADING":  st_heading,
"HUSH":  st_hush,
"IF":  st_if,
"IN":  st_in,
"INCLUDE":  st_include,
"INHERIT":  st_inherit,
"INPUT":  st_input,
"INPUTCLEAR":  st_clearinput,           
"INPUTCSV":  st_inputcsv,
"INPUTERR":  st_printerr,             
"INPUTFIELD":  st_inputfield,
"INS":  st_ins,
"KEYEDIT":  st_keyedit,
"KEYEXIT":  st_keyexit,
"KEYTRAP":  st_keytrap,
"LOCAL":  st_local,
"LOCATE":  st_locate,
"LOCK":  st_lock,
"LOGMSG":  st_logmsg,
"LOOP":  st_loop,
"MARK.MAPPING":  st_mark_mapping,
"MAT":  st_mat,
"MATBUILD":  st_matbuild,
"MATPARSE":  st_matparse,
"MATREAD":  st_matread,
"MATREADCSV":  st_matreadcsv,
"MATREADL":  st_matreadl,
"MATREADU":  st_matreadu,
"MATWRITE":  st_matwrite,
"MATWRITEU":  st_matwriteu,
"NAP":  st_nap,
"NEXT":  st_next,
"NOBUF":  st_nobuf,
"NULL":  st_null,
"ON":  st_on,
"OPEN":  st_open,
"OPENPATH":  st_openpath,
"OPENSEQ":  st_openseq,
"OS.EXECUTE":  st_os_execute,
"PAGE":  st_page,
"PAUSE":  st_pause,
"PERFORM":  st_execute,              
"PRECISION":  st_precision,
"PRINT":  st_print,
"PRINTER":  st_printer,
"PRINTCSV":  st_printcsv,
"PRINTERR":  st_printerr,
"PROCREAD":  st_procread,
"PROCWRITE":  st_procwrite,
"PROMPT":  st_prompt,
"RANDOMIZE":  st_randomize,
"READ":  st_read,
"READBLK":  st_readblk,
"READCSV":  st_readcsv,
"READL":  st_readl,
"READLIST":  st_readlist,
"READNEXT":  st_readnext,
"READSEQ":  st_readseq,
"READU":  st_readu,
"READV":  st_readv,
"READVL":  st_readvl,
"READVU":  st_readvu,
"RECORDLOCKL":  st_recordlockl,
"RECORDLOCKU":  st_recordlocku,
"RELEASE":  st_release,
"REM":  st_remark,               
"REMARK":  st_remark,
"REMOVE":  st_remove,
"REMOVE.BREAK.HANDLER":  st_remove_break_handler,
"REPEAT":  st_repeat,
"RESTORE.SCREEN":  st_restore_screen,
"RETURN":  st_return,
"ROLLBACK":  st_rollback,
"RQM":  st_sleep,                
"SAVELIST":  st_savelist,
"SEEK":  st_seek,
"SELECT":  st_select,
"SELECTE":  st_selecte,
"SELECTINDEX":  st_selectindex,
"SELECTLEFT":  st_selectleft,
"SELECTN":  st_selectn,
"SELECTRIGHT":  st_selectright,
"SELECTV":  st_selectv,
"SENDMAIL":  st_sendmail,
"SET.ARG":  st_set_arg,
"SET.BREAK.HANDLER":  st_set_break_handler,
"SET.EXIT.STATUS":  st_set_exit_status,
"SETLEFT":  st_setleft,
"SETNLS":  st_setnls,
"SETPU":  st_setpu,
"SETRIGHT":  st_setright,
"SETREM":  st_setrem,
"SLEEP":  st_sleep,
"SSELECT":  st_sselect,
"STATUS":  st_status,
"STOP":  st_stop,
"STOPE":  st_stope,
"STOPM":  st_stopm,
"TCLREAD":  st_tclread,
"TIMEOUT":  st_timeout,
"TRANSACTION":  st_transaction,
"TTYSET":  st_ttyset,
"UNLOCK":  st_unlock,
"UNTIL":  st_until,
"VOID":  st_void,
"WAKE":  st_wake,
"WEOFSEQ":  st_weofseq,
"WHILE":  st_while,
"WRITE":  st_write,
"WRITEBLK":  st_writeblk,
"WRITECSV":  st_writecsv,
"WRITESEQ":  st_writeseq,
"WRITESEQF":  st_writeseqf,
"WRITEU":  st_writeu,
"WRITEV":  st_writev,
"WRITEVU":  st_writevu
}

# Statements which do not generate DEBUG calls when debugging

non_debug_statements = {
"CLASS"   :  st_class,    
"COM"   :  st_common,   
"COMMON"   :  st_common,   
"DEFFUN"   :  st_deffun,
"EQU"   :  st_equate,   
"EQUATE"   :  st_equate,
"FUNCTION"   :  st_function,
"GET"   :  st_get,
"PRIVATE"   :  st_private,
"PROGRAM"   :  st_program,
"PUBLIC"   :  st_public,
"SET"   :  st_set,
"SUB"   :  st_subroutine,
"SUBROUTINE"   :  st_subroutine
}

# Internal (restricted) statements

restricted_statements = {
"ADD"   :  st_add,
"AKCLEAR"   :  st_akclear,
"AKDELETE"   :  st_akdelete,
"AKENABLE"   :  st_akenable,
"AKREAD"   :  st_akread,
"AKRELEASE"   :  st_akrelease,
"AKWRITE"   :  st_akwrite,
"BREAKPOINT"   :  st_breakpoint,
"CALLV"   :  st_callv,
"COMO"   :  st_como,
"CONFIGURE.FILE"   :  st_configure_file,
"CREATE.AK"   :  st_create_ak,
"DEBUG.OFF"   :  st_debug_off,
"DEBUG.ON"   :  st_debug_on,
"DEBUG.SET"   :  st_debug_set,
"DELETE.AK"   :  st_delete_ak,
"DELETE.COMMON"   :  st_delete_common,
"KEYBOARD.INPUT"   :  st_keyboard_input,
"MODIFY"   :  st_modify,
"QUIT"   :  st_quit,
"RELEASE.LOCK"   :  st_release_lock,
"REMOVE.TOKEN"   :  st_remove_token,
"RESET.MODES"   :  st_reset_modes,
"REWIND"   :  st_rewind,
"RUN"   :  st_run,
"SET.MODES"   :  st_set_modes,
"SET.STATUS"   :  st_set_status,
"SET.TRIGGER"   :  st_set_trigger,
"SET.UNASSIGNED"   :  st_set_unassigned,
"SORTADD"   :  st_sortadd,
"SORTCLEAR"   :  st_sortclear,
"SORTINIT"   :  st_sortinit,
"TRACE"   :  st_trace,
"UNLOAD.OBJECT"   :  st_unload_object,
"VARSET"   :  st_varset,
"WATCH"   :  st_watch,
"WRITEPKT"   :  st_writepkt
}
##############################################################################################
# handlers for intrinsic functions
# N O T E  - this is where we set supported / unsupported  functions
############################################################################################## 
def in_none():
    intrinsic_common()
    return
	
def in_one():
    exprf()
    intrinsic_common()
    return
       
def in_two():
    get_args(2)
    intrinsic_common()
    return
       
def in_three():
    get_args(3)
    intrinsic_common()
    return
        
def in_four():
    get_args(4)
    intrinsic_common()
    return
  
def in_five():
    get_args(5)
    intrinsic_common()
    return

def in_six():
    get_args(6)
    intrinsic_common()
    return

def in_seven():
    get_args(7)
    intrinsic_common()
    return

def in_btree():
    # BTREE()  First is key count, second is one dimensional array
    global symbol_name
    expr()
    check_comma()
    if look_ahead_token != TKN_NAME:
        error('Variable name not found where expected')
    get_token()
    symbol_name = token_string
    find_var()
    if (symbol_var_no < 0) or (symbol_dim != 1):
        error('One dimensional matrix name required')

    emit_var_load()
    intrinsic_common()
    return
       
def in_change():
    #  CHANGE()   3, 4 or 5 arguments. Arg 4 defaults to -1, arg 5 to 1
    get_args(3)

    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(-1)

    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(1)
    
    intrinsic_common()

    return
    
def in_compare():
    # COMPARE()   2 or 3 arguments, absent arg defaults to "L"
    get_args(2)
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_string_load("L")

    intrinsic_common()

    return

def in_create_socket_server():
    error('create_socket_server not supported')
    return
   
def in_csvdq():
    error('csvdq not supported')
    return
     
def in_delete():
    """ handled by in_extract"""
    in_extract()
    return
    
def in_dtx():
    #  DTX()  1 or 2 arguments. Second defaults to 0 if omitted.
    expr()        # Value to convert

    if look_ahead_token == TKN_COMMA:
        get_token()
        expr()
    else:
        emit_numeric_load(0)

    intrinsic_common()
    return
       
def in_enter_package():
    error('enter_package() function not supported')
    return

def in_exit_package():
    error('exit_package() function not supported')
    return

def in_extract():
    # *** DELETE()   2, 3 or 4 arguments. Absent args default to zero
    # *** EXTRACT()   2, 3 or 4 arguments. Absent args default to zero

    get_args(2)

    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(0)
    
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(0)

    intrinsic_common()
    return
   
def in_field():
    # FIELD()   3 or 4 arguments, absent arg defaults to 1
    get_args(3)
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(1)

    intrinsic_common()
    return
     
def in_fvar_two():
    # FILEINFO()       } Two args, first is file variable
    # RECORDLOCKED()   }
        # bcomp has this for FILES statement which we do not support gosub convert.pick.file.reference
    expr()
    check_comma()
    exprf()
    intrinsic_common()
    return
  
def in_fold():
    # FOLD()/FOLDS()  Two or three arguments
    error('FOLD()/FOLDS() function not supported')
    return
      
def in_indices():
    # INDICES()  One or two args (different opcode required)
    error('INDICES() function not supported')
    return
   
def in_inmat():
    #  INMAT()  No args or one arg as matrix name (different opcode required)
    global symbol_name, opcode_byte
    if look_ahead_token != TKN_NAME:
        intrinsic_common()

    get_token()
    symbol_name = token_string
    find_var()
    if (symbol_var_no < 0) or (symbol_dim == 0):
        error('Matrix name required')

    emit_var_load()

    emit_simple(OP_INMATA)
    intrinsic_end()
    return

def in_ins_rep():
    """ common insert() and replace() function"""
  
    get_args(2) # Source string and field number

    if look_ahead_token == TKN_COMMA:  #  Value number present
        get_token()
        exprf()
    else:
        emit_numeric_load(0)


    if look_ahead_token == TKN_COMMA: # Subvalue number present
        get_token()
        exprf()
    else:
        emit_numeric_load(0)

    if (look_ahead_token != TKN_COMMA) and (look_ahead_token != TKN_SEMICOLON):
        error('Expected comma or semicolon')

    get_token()
    exprf()                # New string value
    intrinsic_common()
    return
     
def in_insert():
    #  INSERT()  3, 4 or 5 args, args 2 and 4 default to zero
    #  final arg may have semicolon delimiter.
    in_ins_rep()
    return
    
def in_itype():
    """itype expression"""
    global intrinsic_stack
    expr()
    if look_ahead_token == TKN_COMMA:
        intrinsic_stack[0] = OP_ITYPE2

        # Process second argument (TOTAL() function count)
        get_token()
        expr()
    intrinsic_common()
    return
     
def in_keyin():
    # KEYIN()  No args or one arg as timeout value (different opcode required)
    # KEYINC()
    # KEYCODE()
    global intrinsic_stack

    if look_ahead_token == TKN_RBR:
        intrinsic_common()
        return

    expr()

    i = intrinsic_stack[0]
    
    if  i == OP_KEYIN:
        intrinsic_stack[0] = OP_KEYINT
    elif i == OP_KEYINC:
        intrinsic_stack[0] = OP_KEYINCT
    elif i == OP_KEYCODE:
        intrinsic_stack[0] = OP_KEYCODET
    elif i == OP_KEYINR:
        intrinsic_stack[0] = OP_KEYINRT
    
    intrinsic_common()
    return
     
def in_locate():
    # LOCATE()  3, 4 or 5 args. Final arg may have semicolon delimiter.
    # Search string, dynamic array, field pos
    get_args(3)

    if look_ahead_token == TKN_COMMA:  #  Value number present
        get_token()
        exprf()
    else:
        emit_numeric_load(0)

    if look_ahead_token == TKN_COMMA:  # Subvalue number present
        get_token()
        exprf()
    else:
       emit_numeric_load(0)

    if (look_ahead_token == TKN_COMMA) or (look_ahead_token == TKN_SEMICOLON):
        get_token()
        exprf()                # Order code
    else:
        emit_string_load('')


    intrinsic_common()
    return
    
def in_object():
    error('OBJECTs not supported')
    return
    
def in_open_socket():
    error('open_socket() function not supported')
    return

def in_remove():
    # REMOVE()   2 args, second must be simple var reference
    exprf()            # Source item
    check_comma()
    simple_lvar_reference()  # Emit delimiter variable reference
    intrinsic_common()
    return

def in_removef():
    # REMOVEF()   1 or 2 args, second defaults to one
    exprf()      # Source item

    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_numeric_load(1)

    intrinsic_common()
    return
    
def in_replace():
    # REPLACE()  3, 4 or 5 args, args 2 and 4 default to zero
    # final arg may have semicolon delimiter.    
    in_ins_rep()
    return
   
def in_scan():
    #  SCAN()  Two variants:
    #           SCAN(var)            Use OP.BTSCAN
    #           SCAN(var, matrix)    Use OP.BTSCANA
    global symbol_name, opcode_byte

    exprf()
    if look_ahead_token != TKN_COMMA:
        intrinsic_common()
    get_token()     # Skip comma
    if look_ahead_token !=  TKN_NAME:
        error('Variable name not found where expected')

    get_token()
    symbol_name = token_string
    find_var()
    if (symbol_var_no < 0) or (symbol_dim != 1):
        error('One dimensional matrix name required')

    emit_var_load()
    emit_simple(OP_BTSCANA)
    intrinsic_end()
    return
     
def in_sentence():
    #  SENTENCE()
    emit_ldsysv(SYSCOM_SENTENCE)
    intrinsic_end()
    return

def in_sortnext():
    error('sortnext() function not supported')
    return
  
def in_subr():
    # SUBR(name [, arg1 [,arg2...]])
    global func_stack

    expr()   #  Subroutine name expression

    emit_function_return_argument()   # Emit return argument

    func_stack.insert(0,1) #* Track arg count
 
    while look_ahead_token == TKN_COMMA:
        func_stack[0] = func_stack[0] + 1
        get_token()  # Skip comma
        exprf()

    # Emit call

    func_arg_count = func_stack[0]
    func_stack.pop(0)

 
    emit(OP_CALL)
 
    emit(func_arg_count)

    emit_function_result_load()  # Load result
    intrinsic_end()
    return
      
def in_subst():
    # SUBSTITUTE()   3 or 4 arguments, absent arg defaults to @vm
    get_args(3)
    if look_ahead_token == TKN_COMMA:
        get_token()
        expr()
    else:
        emit_string_load(VALUE_MARK)

    intrinsic_common()
    return

def in_sysmsg_end(arg_cnt):
    emit(OP_SYSMSG)
    emit(arg_cnt)
    intrinsic_end()
    return
     
def in_sysmsg():
    # SYSMSG()  1 to 4 arguments
    expr()         #  Emit message number
    if look_ahead_token != TKN_COMMA:
        in_sysmsg_end(0)
        return

    # *Much as a loop look attractive, we must allow for the
    #  unlikely case of recursive SYSMSG() usage.

    get_token()     #  Skip comma
    expr()          #  Emit first substitution parameter
    if look_ahead_token != TKN_COMMA:
        in_sysmsg_end(1)
        return

    get_token()     # Skip comma
    expr()          # Emit second substitution parameter
    if look_ahead_token != TKN_COMMA:
        in_sysmsg_end(2)
        return

    get_token()     # Skip comma
    expr()          # Emit third substitution parameter
    if look_ahead_token != TKN_COMMA:
        in_sysmsg_end(3)
        return

    get_token()     # Skip comma
    expr()          # Emit fourth substitution parameter
    in_sysmsg_end(4)
    return
    
def in_terminfo():
    # TERMINFO()  No args or one arg (terminfo capability name)
    if look_ahead_token != TKN_RBR:
        get_args(1)
    else:
        emit_string_load('')

    intrinsic_common()
    return
  
def in_trans():
    if (look_ahead_token == TKN_NAME) and (u_look_ahead_token_string == "DICT"):
        get_token()
        emit_string_load('DICT')
        exprf()                     # Process file name expression
        emit_simple(OP_CAT)
    else:
        exprf()                     # Process file name expression

    check_comma()
    exprf()                     # ID expression
    check_comma()
    exprf()                     # Field number expression
    check_comma()
    exprf()                          # Code expression
    intrinsic_common()
    return
     
def in_trim():
    #  TRIM()   1, 2 or 3 args
    global intrinsic_stack
    exprf()                # Source item

    if look_ahead_token != TKN_COMMA: # TRIM(s)
        intrinsic_common()
        return
  
    if intrinsic_stack[0] == OP_TRIM:  # TRIM -> TRIMX
        intrinsic_stack[0] = OP_TRIMX
    else:  #                            TRIMS -> TRIMXS
        intrinsic_stack[0] = OP_TRIMXS

    #  Process second argument (trim character)
    get_token()
    exprf()

    #  Look for optional third argument, defaulting to null string
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        emit_string_load('')

    intrinsic_common()
    return

def intrinsic_common():
    global opcode_byte, intrinsic_stack

    opcode_byte = intrinsic_stack[0]
    emit_simple(opcode_byte)

    intrinsic_stack.pop(0)

    if look_ahead_token != TKN_RBR:
        error('Right bracket not found where expected')

    get_token()

    return

def intrinsic_end():
    global intrinsic_stack

    intrinsic_stack.pop(0)

    if look_ahead_token != TKN_RBR:
        error('Right bracket not found where expected')

    get_token()

    return

def intrinsic_end_check():

    if look_ahead_token != TKN_RBR:
        error('Right bracket not found where expected')

    get_token()

    return   

def get_args(arg_count):
    """ GET.ARGS  -  Emit multiple comma separated expressions ARG_COUNT holds required number of expressions"""
    global arg_count_stack

    arg_count_stack.insert(0,arg_count)
    while True:
        exprf()
        arg_count = arg_count_stack[0] - 1
        if arg_count > 0:
            arg_count_stack[0] = arg_count
            check_comma()
        else:
            break

    arg_count_stack.pop(0)

    return
               

# Intrinsic function names with  associated opcodes, and called python function to process.
# note this dictionary is utilized in emit.var.refernece.common (at least thats what it is called in BCOMP)
# with functional allowed = True, which is called via:
# expr.common:
#    .
#    .
#   gosub get.expr.item 
#
# get.expr.item:
#    .
#    .
#  case token = TKN.NAME.LBR  # token in '('
#         gosub emit.var.reference
# 
intrinsic_stack = []     # intrinsic stack, looks like we append (insert) the most recently emitted function to this stack, not sure why??

intrinsics = {
   "ABS"             : [OP_ABS        ,in_one],         # ABS
   "ABSS"            : [OP_ABSS       ,in_one],         # ABSS
   "ACCEPT.SOCKET.CONNECTION" : [OP_ACCPTSKT   ,in_two],         # ACCEPT_SOCKET
   "ACOS"            : [OP_ACOS       ,in_one],         # ACOS
   "ALPHA"           : [OP_ALPHA      ,in_one],         # ALPHA
   "ANDS"            : [OP_ANDS       ,in_two],         # ANDS
   "ARG"             : [OP_ARG        ,in_one],         # ARG
   "ARG.COUNT"       : [OP_ARGCT      ,in_none],        # ARGCT
   "ASCII"           : [OP_ASCII      ,in_one],         # ASCII
   "ASIN"            : [OP_ASIN       ,in_one],         # ASIN
   "ASSIGNED"        : [OP_ASS        ,in_one],         # ASSIGNED
   "ATAN"            : [OP_ATAN       ,in_one],         # ATAN
   "BINDKEY"         : [OP_BINDKEY    ,in_two],         # BINDKEY
   "BITAND"          : [OP_BITAND     ,in_two],         # BITAND
   "BITNOT"          : [OP_BITNOT     ,in_one],         # BITNOT
   "BITOR"           : [OP_BITOR      ,in_two],         # BITOR
   "BITRESET"        : [OP_BITRESET   ,in_two],         # BITRESET
   "BITSET"          : [OP_BITSET     ,in_two],         # BITSET
   "BITTEST"         : [OP_BITTEST    ,in_two],         # BITTEST
   "BITXOR"          : [OP_BITXOR     ,in_two],         # BITXOR
   "CATALOGUED"      : [OP_CHKCAT     ,in_one],         # CATALOGUED
   "CATS"            : [OP_CATS       ,in_two],         # CATS
   "CCALL"           : [OP_CCALL      ,in_two],         # CCALL
   "CHANGE"          : [OP_CHANGE     ,in_change],      # CHANGE
   "CHAR"            : [OP_CHAR       ,in_one],         # CHAR
   "CHECKSUM"        : [OP_CHECKSUM   ,in_one],         # CHECKSUM
   "CHGPHANT"        : [OP_CHGPHANT   ,in_none],        # CHGPHANT
   "COL1"            : [OP_COL1       ,in_none],        # COL1
   "COL2"            : [OP_COL2       ,in_none],        # COL2
   "COMPARE"         : [OP_COMPARE    ,in_compare],     # COMPARE
   "CONFIG"          : [OP_CONFIG     ,in_one],         # CONFIG
   "CONNECT.PORT"    : [OP_CNCTPORT   ,in_five],        # CONNECT_PORT
   "CONVERT"         : [OP_FCONVERT   ,in_three],       # CONVERT
   "COS"             : [OP_COS        ,in_one],         # COS
   "COUNT"           : [OP_COUNT      ,in_two],         # COUNT
   "COUNTS"          : [OP_COUNTS     ,in_two],         # COUNTS
   "CREATE.SERVER.SOCKET": [OP_SRVRSKT    ,in_create_socket_server], # CREA
   "CROP"            : [OP_CROP       ,in_one],         # CROP
   "CSVDQ"           : [OP_CSVDQ      ,in_csvdq],       # CSVDQ
   "DATE"            : [OP_DATE       ,in_none],        # DATE
   "DCOUNT"          : [OP_DCOUNT     ,in_two],         # DCOUNT
   "DECRYPT"         : [OP_DECRYPT    ,in_two],         # DECRYPT
   "DELETE"          : [OP_DEL        ,in_delete],      # DELETE
   "DIR"             : [OP_DIR        ,in_one],         # DIR
   "DIV"             : [OP_QUOTIENT   ,in_two],         # DIV
   "DOWNCASE"        : [OP_DNCASE     ,in_one],         # DOWNCASE
   "DQUOTE"          : [OP_QUOTE      ,in_one],         # DQUOTE
   "DTX"             : [OP_DTX        ,in_dtx],         # DTX
   "EBCDIC"          : [OP_EBCDIC     ,in_one],         # EBCDIC
   "ENCRYPT"         : [OP_ENCRYPT    ,in_two],         # ENCRYPT
   "ENTER.PACKAGE"   : [OP_PACKAGE    ,in_enter_package], # ENTER_PACKA
   "ENV"             : [OP_ENV        ,in_one],         # ENV
   "EQS"             : [OP_EQS        ,in_two],         # EQS
   "EXIT.PACKAGE"    : [OP_PACKAGE    ,in_exit_package],# EXIT_PACKAGE
   "EXP"             : [OP_EXP        ,in_one],         # EXP
   "EXTRACT"         : [OP_EXTRACT    ,in_extract],     # EXTRACT
   "FIELD"           : [OP_FIELD      ,in_field],       # FIELD
   "FIELDS"          : [OP_FIELDS     ,in_field],       # FIELDS
   "FIELDSTORE"      : [OP_FLDSTORF   ,in_five],        # FIELDSTORE
   "FILEINFO"        : [OP_FILEINFO   ,in_fvar_two],    # FILEINFO
   "FMT"             : [OP_FMT        ,in_two],         # FMT
   "FMTS"            : [OP_FMTS       ,in_two],         # FMTS
   "FOLD"            : [OP_FOLD       ,in_fold],        # FOLD
   "FOLDS"           : [OP_FOLDS      ,in_fold],        # FOLDS
   "GES"             : [OP_GES        ,in_two],         # GES
   "GET.MESSAGES"    : [OP_GETMSG     ,in_none],        # GET_MESSAGES
   "GET.PORT.PARAMS" : [OP_GETPORT    ,in_one],         # GET_PORT_PARA
   "GETNLS"          : [OP_GETNLS     ,in_one],         # GETNLS
   "GETPU"           : [OP_GETPU      ,in_two],         # GETPU
   "GETREM"          : [OP_GETREM     ,in_one],         # GETREM
   "GTS"             : [OP_GTS        ,in_two],         # GTS
   "ICONV"           : [OP_ICONV      ,in_two],         # ICONV
   "ICONVS"          : [OP_ICONVS     ,in_two],         # ICONVS
   "IDIV"            : [OP_IDIV       ,in_two],         # IDIV
   "IFS"             : [OP_IFS        ,in_three],       # IFS
   "INDEX"           : [OP_INDEX      ,in_three],       # INDEX
   "INDEXS"          : [OP_INDEXS     ,in_three],       # INDEXS
   "INDICES"         : [OP_INDICES1   ,in_indices],     # INDICES
   "INMAT"           : [OP_INMAT      ,in_inmat],       # INMAT      (S
   "INPUTBLK"        : [OP_INPUTBLK   ,in_one],         # INPUTBLK
   "INSERT"          : [OP_INSERT     ,in_insert],      # INSERT
   "INT"             : [OP_INT        ,in_one],         # INT
   "ITYPE"           : [OP_ITYPE      ,in_itype],       # ITYPE
   "KEYCODE"         : [OP_KEYCODE    ,in_keyin],       # KEYCODE
   "KEYIN"           : [OP_KEYIN      ,in_keyin],       # KEYIN
   "KEYINC"          : [OP_KEYINC     ,in_keyin],       # KEYINC
   "KEYINR"          : [OP_KEYINR     ,in_keyin],       # KEYINR
   "KEYREADY"        : [OP_KEYRDY     ,in_none],        # KEYREADY
   "LEN"             : [OP_LEN        ,in_one],         # LEN
   "LENS"            : [OP_LENS       ,in_one],         # LENS
   "LES"             : [OP_LES        ,in_two],         # LES
   "LISTINDEX"       : [OP_LISTINDX   ,in_three],       # LISTINDEX
   "LN"              : [OP_LN         ,in_one],         # LN
   "LOCATE"          : [OP_LOCATEF    ,in_locate],      # LOCATE
   "LOWER"           : [OP_LOWER      ,in_one],         # LOWER
   "LTS"             : [OP_LTS        ,in_two],         # LTS
   "MATCHFIELD"      : [OP_MATCHFLD   ,in_three],       # MATCHFIELD
   "MAX"             : [OP_MAX        ,in_two],         # MAX
   "MAXIMUM"         : [OP_MAXIMUM    ,in_one],         # MAXIMUM
   "MIN"             : [OP_MIN        ,in_two],         # MIN
   "MINIMUM"         : [OP_MINIMUM    ,in_one],         # MINIMUM
   "MOD"             : [OP_MOD        ,in_two],         # MOD
   "MODS"            : [OP_MODS       ,in_two],         # MODS
   "NEG"             : [OP_NEG        ,in_one],         # NEG
   "NEGS"            : [OP_NEGS       ,in_one],         # NEGS
   "NES"             : [OP_NES        ,in_two],         # NES
   "NOT"             : [OP_NOT        ,in_one],         # NOT
   "NOTS"            : [OP_NOTS       ,in_one],         # NOTS
   "NUM"             : [OP_NUM        ,in_one],         # NUM
   "NUMS"            : [OP_NUMS       ,in_one],         # NUMS
   "OBJECT"          : [OP_OBJECT     ,in_object],      # OBJECT
   "OBJINFO"         : [OP_OBJINFO    ,in_two],         # OBJINFO
   "OCONV"           : [OP_OCONV      ,in_two],         # OCONV
   "OCONVS"          : [OP_OCONVS     ,in_two],         # OCONVS
   "OPEN.SOCKET"     : [OP_OPENSKT    ,in_open_socket], # OPEN_SOCKET
   "ORS"             : [OP_ORS        ,in_two],         # ORS
   "OS.ERROR"        : [OP_OSERROR    ,in_none],        # OS_ERROR
   "OUTERJOIN"       : [OP_OJOIN      ,in_three],       # OUTERJOIN
   "PRINTER.SETTING" : [OP_PSET       ,in_three],       # PRINTER_SETTI
   "PWR"             : [OP_PWR        ,in_two],         # PWR
   "QUOTE"           : [OP_QUOTE      ,in_one],         # QUOTE
   "RAISE"           : [OP_RAISE      ,in_one],         # RAISE
   "RDIV"            : [OP_RDIV       ,in_two],         # RDIV
   "READ.SOCKET"     : [OP_READSKT    ,in_four],        # READ_SOCKET
   "RECORDLOCKED"    : [OP_RECLCKD    ,in_fvar_two],    # RECORDLOCKED
   "REM"             : [OP_REM        ,in_two],         # REM
   "REMOVE"          : [OP_REMOVE     ,in_remove],      # REMOVE
   "REPLACE"         : [OP_REPLACE    ,in_replace],     # REPLACE
   "REUSE"           : [OP_REUSE      ,in_one],         # REUSE
   "RND"             : [OP_RND        ,in_one],         # RND
   "RTRANS"          : [OP_RTRANS     ,in_trans],       # RTRANS
   "SAVE.SCREEN"     : [OP_SAVESCRN   ,in_four],        # SAVE_SCREEN
   "SELECTINFO"      : [OP_SLCTINFO   ,in_two],         # SELECTINFO
   "SENTENCE"        : [OP_NULL       ,in_sentence],    # SENTENCE
   "SEQ"             : [OP_SEQ        ,in_one],         # SEQ
   "SERVER.ADDR"     : [OP_SRVRADDR   ,in_one],         # SERVER_ADDR
   "SET.PORT.PARAMS" : [OP_SETPORT    ,in_two],         # SET_PORT_PARA
   "SET.SOCKET.MODE" : [OP_SETSKT     ,in_three],       # SET_SOCKET_MO
   "SHIFT"           : [OP_SHIFT      ,in_two],         # SHIFT
   "SIN"             : [OP_SIN        ,in_one],         # SIN
   "SOCKET.INFO"     : [OP_SKTINFO    ,in_two],         # SOCKETINFO
   "SOUNDEX"         : [OP_SOUNDEX    ,in_one],         # SOUNDEX
   "SOUNDEXS"        : [OP_SOUNDEXS   ,in_one],         # SOUNDEXS
   "SPACE"           : [OP_SPACE      ,in_one],         # SPACE
   "SPACES"          : [OP_SPACES     ,in_one],         # SPACES
   "SPLICE"          : [OP_SPLICE     ,in_three],       # SPLICE
   "SQRT"            : [OP_SQRT       ,in_one],         # SQRT
   "SQUOTE"          : [OP_SQUOTE     ,in_one],         # SQUOTE
   "STATUS"          : [OP_STATUS     ,in_none],        # STATUS
   "STR"             : [OP_STR        ,in_two],         # STR
   "STRS"            : [OP_STRS       ,in_two],         # STRS
   "SUBR"            : [0             ,in_subr],        # SUBR
   "SUBSTITUTE"      : [OP_SUBST      ,in_subst],       # SUBSTITUTE
   "SUBSTRINGS"      : [OP_SUBSTRNG   ,in_three],       # SUBSTRINGS
   "SUM"             : [OP_SUM        ,in_one],         # SUM
   "SUMMATION"       : [OP_SUMMATION  ,in_one],         # SUMMATION
   "SWAP"            : [OP_CHANGE     ,in_change],      # SWAP
   "SWAPCASE"        : [OP_SWAPCASE   ,in_one],         # SWAPCASE
   "SYSMSG"          : [OP_SYSMSG     ,in_sysmsg],      # SYSMSG
   "SYSTEM"          : [OP_SYSTEM     ,in_one],         # SYSTEM
   "TAN"             : [OP_TAN        ,in_one],         # TAN
   "TERMINFO"        : [OP_TERMINFO   ,in_terminfo],    # TERMINFO
   "TIME"            : [OP_TIME       ,in_none],        # TIME
   "TIMEDATE"        : [OP_TIMEDATE   ,in_none],        # TIMEDATE
   "TRANS"           : [OP_TRANS      ,in_trans],       # TRANS
   "TRIM"            : [OP_TRIM       ,in_trim],        # TRIM
   "TRIMB"           : [OP_TRIMB      ,in_one],         # TRIMB
   "TRIMBS"          : [OP_TRIMBS     ,in_one],         # TRIMBS
   "TRIMF"           : [OP_TRIMF      ,in_one],         # TRIMF
   "TRIMFS"          : [OP_TRIMFS     ,in_one],         # TRIMFS
   "TRIMS"           : [OP_TRIMS      ,in_trim],        # TRIMS
   "TTYGET"          : [OP_TTYGET     ,in_none],        # TTYGET
   "UMASK"           : [OP_UMASK      ,in_one],         # UMASK
   "UNASSIGNED"      : [OP_UNASS      ,in_one],         # UNASSIGNED
   "UPCASE"          : [OP_UPCASE     ,in_one],         # UPCASE
   "VARTYPE"         : [OP_VARTYPE    ,in_one],         # VARTYPE
   "VSLICE"          : [OP_VSLICE     ,in_two],         # VSLICE
   "WRITE.SOCKET"    : [OP_WRITESKT   ,in_four],        # WRITE_SOCKET
   "XLATE"           : [OP_TRANS      ,in_trans],       # XLATE
   "XTD"             : [OP_XTD        , in_one]         # XTD
} 

# internal Intrinsic function names with  associated opcodes, called python function to process  

int_intrinsics = {
"ABORT.CAUSE": [OP_ABTCAUSE , in_none],       # ABORT.CAUSE
"AKMAP"      : [OP_AKMAP    , in_two],        # AKMAP
"ANALYSE"    : [OP_ANALYSE  , in_one],        # ANALYSE
"BREAK.COUNT": [OP_BREAKCT  , in_none],       # BREAK.COUNT
"BTREE"      : [OP_BTINIT   , in_btree],      # BTREE
"CHANGED"    : [OP_CHANGED  , in_one],        # CHANGED
"DEBUG.INFO" : [OP_DBGINF   , in_two],        # DEBUG.INFO
"EVENTS"     : [OP_EVENTS   , in_two],        # EVENTS
"EXPAND.HF"  : [OP_EXPANDHF , in_three],      # EXPANDHF
"FCONTROL"   : [OP_FCONTROL , in_three],      # FCONTROL
"FIND"       : [OP_BTFIND   , in_two],        # FIND
"FORMCSV"    : [OP_FORMCSV  , in_one],        # FORMCSV
"GETLOCKS"   : [OP_GETLOCKS , in_two],        # GETLOCKS
"GRPSTAT"    : [OP_GRPSTAT  , in_two],        # GRPSTAT
"IS.SUBR"    : [OP_ISSUBR   , in_one],        # IS.SUBR
"ISMV"       : [OP_ISMV     , in_one],        # ISMV
"KERNEL"     : [OP_KERNEL   , in_two],        # KERNEL
"LIST.COMMON": [OP_LISTCOM  , in_none],       # LIST.COMMON
"LOAD.OBJECT": [OP_LOADOBJ  , in_one],        # LOAD.OBJECT
"LOADED"     : [OP_LOADED   , in_one],        # LOADED
"LOGIN"      : [OP_LOGIN    , in_two],        # LOGIN
"LOGIN.PORT" : [OP_LGNPORT  , in_two],        # LOG, in_PORT
"LOGOUT"     : [OP_LOGOUT   , in_two],        # LOGOUT
"OPTION"     : [OP_OPTION   , in_one],        # OPTION
"OSPATH"     : [OP_OSPATH   , in_two],        # OSPATH
"OSRENAME"   : [OP_OSRENAME , in_two],        # OSRENAME
"PACKAGE"    : [OP_PACKAGE  , in_three],      # PACKAGE
"PCONFIG"    : [OP_PCONFIG  , in_two],        # PCONFIG
"PHANTOM"    : [OP_PHANTOM  , in_none],       # PHANTOM
"PROMPT"     : [OP_GETPROMPT, in_none],       # PROMPT
"PTERM"      : [OP_PTERM    , in_two],        # PTERM
"PWCRYPT"    : [OP_PWCRYPT  , in_one],        # PWCRYPT
"READPKT"    : [OP_READPKT  , in_none],       # READPKT
"REMOVEF"    : [OP_RMVF     , in_removef],    # REMOVEF
"SCAN"       : [OP_BTSCAN   , in_scan],       # SCAN
"SORTDATA"   : [OP_SORTDATA , in_none],       # SORTDATA
"SORTNEXT"   : [OP_SORTNEXT , in_sortnext],   # SORTNEXT
"TESTLOCK"   : [OP_TESTLOCK , in_one]         # TESTLOCK
}



#/* ================================================================================================================================ */ 

#/* ================================================================================================================================ */ 
#/* ================================================================================================================================ */ 

#/* all important init routine */
def init_stuff():
# Operator token / opcodes relationship
# Operator priorities.  Operators with
# low priority values are applied first.
# Values are (N * 10) + 1 where N is the
# priority as shown in the user
# documentation.  The + 1 is used to
# allow the ** operator to be treated
# as a special case in EXPR.
   op[TKN_PWR] = OP_PWR 
   op_priority[TKN_PWR] = 21
   op[TKN_DIV] = OP_DIV 
   op_priority[TKN_DIV] = 31
   op[TKN_IDIV] = OP_IDIV       
   op_priority[TKN_IDIV] = 31
   op[TKN_MULT] = OP_MUL
   op_priority[TKN_MULT] = 31
   op[TKN_PLUS] = OP_ADD
   op_priority[TKN_PLUS] = 41
   op[TKN_MINUS] = OP_SUB       
   op_priority[TKN_MINUS] = 41
   op[TKN_FMT] = OP_FMT 
   op_priority[TKN_FMT] = 51
   op[TKN_COLON] = OP_CAT       
   op_priority[TKN_COLON] = 61
   op[TKN_MATCHES] = OP_MATCHES 
   op_priority[TKN_MATCHES] = 71
   op[TKN_LT] = OP_LT   
   op_priority[TKN_LT] = 71
   op[TKN_LTX] = OP_LT  
   op_priority[TKN_LTX] = 71
   op[TKN_GT] = OP_GT   
   op_priority[TKN_GT] = 71
   op[TKN_GTX] = OP_GT  
   op_priority[TKN_GTX] = 71
   op[TKN_EQ] = OP_EQ   
   op_priority[TKN_EQ] = 71
   op[TKN_NE] = OP_NE   
   op_priority[TKN_NE] = 71
   op[TKN_NEX] = OP_NE  
   op_priority[TKN_NEX] = 71
   op[TKN_LE] = OP_LE   
   op_priority[TKN_LE] = 71   
   op[TKN_GE] = OP_GE   
   op_priority[TKN_GE] = 71
   op[TKN_GEX] = OP_GE  
   op_priority[TKN_GEX] = 71
   op[TKN_AND] = OP_AND 
   op_priority[TKN_AND] = 81
   op[TKN_OR] = OP_OR   
   op_priority[TKN_OR] = 81

   priority_stack[0] = STACK_MARK

def insert_inc(incf,src_list):
    """ append include file incf at end of src_list"""
    global defined_tokens     # all important tokens dictionary (sloppy programming but too bad!)
    src_list.append('* >>>>>>>>>>>> include file: '+ incf)
    ln_cnt = 0
    skipcode = False
    print('Inserting: ' + incf)
    with open(incf, encoding='ISO-8859-1') as f:
        for ln in f:
            ln_cnt += 1
            ln = ln.strip()    # get rid of white space (and cr / lf) at end of line 
            uln = ln.upper()    # upper case copy for compare
            if len(ln) > 0:

                if uln[0] == '*':      # comment, skip
                    continue
                if uln[:2] == ';*':   # comment, skip
                    continue
                if uln[:5] =="$LIST":   # $LIST directive, skip it
                    continue

                #if "DEFINE " in uln:   # define statement, add to dictionary
                #    tokens = ln.split() 
                #    if len(tokens) >= 3:
                #       defined_tokens[tokens[1]] = tokens[2] 
                #       continue
                #    else:
                #        print('Bad $define statement, ln ' + str(ln_cnt) + ' file ' + incf )
                #        sys.exit('-' + ln + '- ' + 'abort!')    
                if uln[:8] == "$INCLUDE":
                    sys.exit('Nested Include in ' + incf + ' abort!')  

                if uln[:6] == "$IFDEF":
                    # we are not supporting conditional defines
                    print ('$IFDEF in ' + incf)
                    print (ln)
                    sys.exit('abort!') 
                    # warn and just skip until $ENDIF
                   # print(' Warning $IFDEF found in:  ' + incf)
                   # print(' Skipping block!')
                   # skipcode = True
                   # continue
                if uln[:7] == "$IFNDEF":
                    print ('$IFNDEF in ' + incf)
                    print (ln)
                    sys.exit('abort!') 
                   # skipcode = False
                   # continue

            # looks ok, add to pass 1 source
                if not(skipcode):
                    src_list.append(ln) 

        #inc_lns = f.readlines()
       # src_list.extend(inc_lns)

    return   



def pass1(sfn):
    """ pass 1, resolve include files"""
    global header_flags, catalog_name
    sdir = os.path.dirname(sfn)
    print('pass 1 - resolve include files in: '+ sfn)
    cnt_ln_flg = False  # continuation of current line?
    with open(sfn,encoding='ISO-8859-1') as f:
    #
        pss1src = []   # list to hold pass1 source
        ln_cnt = 0
        #print('Line Count: ' + str(len(slist)))
    #
        # parse all the source lines, expanding include commands
        for ln in f:
            ln_cnt += 1
            ln = ln.strip()    # get rid of the crlf (of lf) at end of line 
            uln = ln.upper()    # upper case copy for compare

            if len(uln) == 0:   # blank line?
                pss1src.append(ln)     # append as is
            
            elif uln[0] == '*' or uln[0] == '!':
               # comment line, add as is
               pss1src.append(ln)     # append as is

            elif uln[:8] == "$INCLUDE":
                tokens = ln.split()
                match len(tokens):
                    case 1:
                        print('bad formed $include'  ' ln: ' + str(ln_cnt))
                        print(ln)
                        sys.exit('abort!')

                    case 2:
                        # second item should be file in this directory or syscom

                        incfn = sdir + os.sep + tokens[1].upper()
                        if os.path.isfile(incfn):
                            insert_inc(incfn,pss1src)
                        else:
                            # look in syscom
                            incfn = os.path.dirname(sdir) + os.sep + 'SYSCOM' + os.sep + tokens[1].upper()
                            if os.path.isfile(incfn):
                                insert_inc(incfn,pss1src)
                            else:   
                                print('not found: ' +  tokens[1] + ' ln: ' + str(ln_cnt))
                                sys.exit('abort!')
                    # there is the third case include file_name rec_name 
                    case 3:
                            incfn = os.path.dirname(sdir) + os.sep + tokens[1].upper()+ os.sep + tokens[2].upper()
                            if os.path.isfile(incfn):
                                insert_inc(incfn,pss1src)
                            else:   
                                print('not found: ' +  tokens[1] + ' ln: ' + str(ln_cnt))
                                sys.exit('abort!')

                    case _:
                        print('bad formed $include'  ' ln: ' + str(ln_cnt))
                        print(ln)
                        sys.exit('abort!')
                        
            elif uln[:6] == "$IFDEF":
               # we are not supporting conditional defines
               print ('$IFDEF in ' + sfn)
               print (ln)
               sys.exit('abort!') 
 
            elif uln[:7] == "$IFNDEF":
                sys.exit('$IFNDEF in ' + sfn + 'abort!')  

            elif uln[:8] == "$CATALOG":
                tokens = ln.split()
                if len(tokens) == 2:
                    catalog_name = tokens[1].upper()
                    print ('$CATALOG Found: ' + catalog_name)
                else:
                    catalog_name = ''
                
                continue

            elif uln[:9] == "$INTERNAL":
                print ('$INTERNAL Found, HDR.FLAGS updated !')
                header_flags = (header_flags | HDR_INTERNAL)  # set internal flag
                continue

            elif uln[:10] == "$RECURSIVE":
                print ('$RECURSIVE Found, HDR.FLAGS updated !')
                header_flags = (header_flags | HDR_RECURSIVE)  # set  flag
                continue

            elif uln[:6] == "$FLAGS":
                tokens = uln.split()
                if len(tokens) == 2:
                    flag = tokens[1]
                    print ('$FLAG: ' + flag + ', HDR.FLAGS updated !')
                    if flag == "ALLOW.BREAK":
                        header_flags = (header_flags | HDR_ALLOW_BREAK)  # set break flag    
                    elif flag == "CPROC":
                        header_flags = (header_flags | HDR_IS_CPROC)  # set cproc flag
                    elif flag == "TRUSTED":
                        header_flags = (header_flags | HDR_IS_TRUSTED)  # set trusted flag
                    else:
                        print ('$FLAG: ' + flag + ', Unknown!')
                continue 

            elif uln[:7] == "$DEFINE":
                # process in pass2, add to source
                pss1src.append(ln)

            elif uln[:1] == "$":
                print('Unknown Directive: ' + uln + ' Skipped!') 
                continue

            else:
                if cnt_ln_flg == True: # last line had continuation char, so do it!
                    ln = con_ln + ln
                    cnt_ln_flg = False
                if ln[-1] == '~':     # a continuation? , add to next source line 
                    cnt_ln_flg = True
                    con_ln = ln[:-1]
                    continue    

                # not include, or continued line,  add to new source file
                pss1src.append(ln)
      
    # get rid of trailing empty lines
    while len(pss1src[-1].strip()) == 0:
             pss1src.pop()  
    return pss1src


def pass2(sfn):
    """ Store all define symbols and values as a dictionary item in defines dictionary
        remove $define line (or just don't add to source)"""
    global defined_tokens     # all important tokens dictionary (sloppy programming but too bad!)
    pss2src = []   # list to hold pass1 source
    ln_cnt = 0
    print('pass 2 - build token dictionary for: '+ sfn)
    with open(sfn, encoding='ISO-8859-1') as f:
        for ln in f:
            ln_cnt += 1
            ln = ln.rstrip()    # get rid of white space (and cr / lf) at end of line 
            uln = ln.upper()    # upper case copy for compare
            if len(ln) > 0:
                if uln[:7] == "$DEFINE" or uln[:7] == "#DEFINE":   # define statement, add to dictionary
                    tokens = uln.split() 
                    if len(tokens) >= 3:
                       # we need to determine the type of the $DEFINE value
                       # BCOMP has:
                       # is_string = 0
                       # is_number = 1
                       # all int like strings can be converted to float so int tries first
                        if '"' in tokens[2] or "'" in tokens[2]:
                            defined_tokens[tokens[1]] = [tokens[2], is_string]  
                            continue

                         # kludge fix for ';' adjacent number string
                        if ';' in tokens[2]:
                            tokens[2] = tokens[2].replace(";", "")   
                    
                        try:
                            val = int(tokens[2])
                            defined_tokens[tokens[1]] = [val, is_number]
                            
                        except ValueError:
                            # float?    
                            try:
                                val = float(tokens[2])
                                defined_tokens[tokens[1]] = [val, is_number]
                              
                            except ValueError:
                                # hex?
                                try:
                                    val = int(tokens[2],16)
                                    defined_tokens[tokens[1]] = [val, is_number]

                                except:
                                    print('Bad $define statement, ln ' + str(ln_cnt) + ' file ' + sfn )
                                    sys.exit('-' + ln + '- ' + 'abort!')
                        
                        continue
 

                    else:
                        print('Bad $define statement, ln ' + str(ln_cnt) + ' file ' + sfn )
                        sys.exit('-' + ln + '- ' + 'abort!') 
                pss2src.append(ln)
            else:
                pss2src.append(' ')   # keep the blank lines, makes compare of output from bcomp easier 
    return pss2src


def wpass(sfn,sf_list):
    """ write pass intermediate file sf_list to sfn"""                        
    with open(sfn, 'w', encoding='ISO-8859-1' )  as wf:
        for ln in sf_list:
            wf.write(f"{ln.rstrip()}\n")

def open_common(opcode):
    global reserved_names, onerror_stack, testlock_stack, thenelse_stack

    # only item to remove from reserved_names
    reserved_names.pop(-1)

    if u_look_ahead_token_string == 'READONLY':
        get_token()
        emit_simple(OP_READONLY)


    if u_look_ahead_token_string != "TO":
        error('open_common - TO not found where expected')
    get_token()      # Skip "TO"

    if (look_ahead_token != TKN_NAME) and (look_ahead_token != TKN_NAME_LBR):
        error('open_common - File variable name not found where expected')

    get_token()
    emit_lvar_reference()

    # Perform common back-end processing

    #ins '1' before onerror.stack<1>       ;* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>      ;* No LOCKED clause allowed
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>      ;* Requires THEN or ELSE
    thenelse_stack.insert(0,1)
    back_end(opcode)
    return
   
def record_lock_common(opcode):
    global onerror_stack, testlock_stack, thenelse_stack, lock_opcode
    lock_opcode = opcode
    #gosub convert.pick.file.reference
    simple_var_reference()
    check_comma()
    exprf()           # Emit record id expresssion

    # Perform common back-end processing

    #ins '1' before onerror.stack<1>       ;* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '1' before testlock.stack<1>      ;* Optional LOCKED clause
    testlock_stack.insert(0,1)
    #ins '0' before thenelse.stack<1>      ;* No THEN or ELSE clause
    thenelse_stack.insert(0,0)

    back_end(OP_LOCKREC)
    return          

def read_common(opcode):
    global onerror_stack, testlock_stack, thenelse_stack, symbol_name, symbol_mode

    # BCOMP has test for file statement   -- file not supported!  

    # Emit target variable

    simple_lvar_reference()

    if u_look_ahead_token_string != "FROM":
        error('read_common - FROM not found where expected') 

    get_token()      # Skip FROM token

    # Emit file variable

    simple_var_reference()
    check_comma()

    # Emit record key expression (block size for readblk)
    exprf()

    if opcode == OP_READV:
        check_comma()
        exprf()  # Emit field number expression


    #ins '1' before onerror.stack<1>      ;* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    # ins (lock.opcode # 0) before testlock.stack<1>  ;* LOCKED clause allowed?
    if lock_opcode > 0:
        n = 1
    else:
        n = 0
    testlock_stack.insert(0,n)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE required
    thenelse_stack.insert(0,1)
    
    back_end(opcode)
    return


def if_back_end():
    global jump_no, jump_stack, label_name

    jmp_val = [J_IF,jump_no,0]
    jump_stack.insert(0,jmp_val)

    jump_no += 1

    # Look for a THEN token on the current line

    if look_ahead_token ==  TKN_END:  # Nothing further on this line
        get_token()
        #emit.xref.entry


    get_token()
    if u_token_string != "THEN": #* No THEN clause
        if u_token_string != "ELSE":
            error('Expected THEN or ELSE clause')

        # ELSE clause present without THEN clause. 
        # Generate jump to exit label
        jmp_val = jump_stack[0]
        label_name = "_" + str(jmp_val[1]) +"X"
        emit_jump(OP_JTRUE)
        if_else_clause()
        jump_stack.pop(0)
        return


    # Generate jump to ELSE clause (or end if no ELSE)
    jmp_val = jump_stack[0]
    label_name = "_" + str(jmp_val[1]) +"E"
    emit_jump(OP_JFALSE)

    if look_ahead_token == TKN_END:  # THEN / END construct
        get_token()
        while True:
            if end_source:
                error('Unterminated THEN clause')

            # 0336 Check for a label
            # We must treat these as a special case here as otherwise a labelled
            # END will not be trapped below and will cause the END to be paired
            # up incorrectly

            get_token()
            check_for_label()

            if u_token_string == "END":
                break

            proc_line_prefetched()
        # repeat

    else:                        # Conditional statement on same line
        get_token()
        proc_statement_group()


   # Look for an ELSE clause

    if look_ahead_token ==  TKN_END:   #  Nothing further on this line
        get_token()
 
    if u_look_ahead_token_string == "ELSE":  #   ELSE clause present
        get_token()    # Skip ELSE token

        # Check that the top of the jump stack is an IF construct
        jmp_val = jump_stack[0]
        if jmp_val[0] != J_IF:
            error('Misplaced ELSE')

        # Emit jump to exit label
        label_name = "_" + str(jmp_val[1]) + "X"
        emit_jump(OP_JMP)

        # Set label for head of ELSE clause
        label_name = "_"+ str(jmp_val[1]) + "E"
        set_label()

        if_else_clause()
        jump_stack.pop(0)
        return

    else:        #  No ELSE clause present
        # Check that the top of the jump stack is an IF construct
        jmp_val = jump_stack[0]
        if jmp_val[0] != J_IF:
            error('Incorrectly formed THEN clause')

        # Set "E" label at end of construct
        label_name = "_" + str(jmp_val[1]) + "E"
        set_label()

    jump_stack.pop(0)
    
    return

def if_else_clause():
    global label_name

    if look_ahead_token ==  TKN_END:    #  ELSE / END construct
        get_token()
        #loop
        while True:
            if end_source:
                error('Unterminated ELSE clause')

            # 0336 Check for a label
            get_token()
            check_for_label()

        #until u_token_string = "END"
            if u_token_string == "END":
                break

            proc_line_prefetched()
        #repeat
    else:       #  Conditional statement on same line
        get_token()
        proc_statement_group()


    # Check that the top of the jump stack is an IF construct
    jmp_val = jump_stack[0]
    if jmp_val[0] != J_IF:
        error('Incorrectly formed ELSE clause')

    # Set "X" label at end of construct
    label_name = "_" + str(jmp_val[1]) + "X"
    set_label()

    return

def back_end(opcode):
    """back.end  -  Common paths for ON ERROR / LOCKED / THEN / ELSE clauses"""

    global jump_stack, jump_no, testlock_stack, onerror_stack, thenelse_stack, label_name, lock_opcode, code_image
    #The opcode we are to emit is in OPCODE as we need to know if we have
    #an ONERROR opcode to emit first.

    #Entry from statements that test only for THEN and ELSE clauses can emit
    #the opcode before entry, setting OPCODE to -1.

    #LOCK.OPCODE will be non-zero if a ULOCK or LLOCK opcode is to be emitted.

    #Add new entry to jump stack
    jmp_val = [J_BACK_END,jump_no,0]
    jump_stack.insert(0,jmp_val)

    jump_no += 1

    #Emit lock opcode if required

    if lock_opcode > 0:
        emit_simple(lock_opcode)
        lock_opcode = 0

   #If this opcode takes an optional LOCKED clause, emit a NULL opcode which
   #will overwritten later with the TESTLOCK opcode if we find a LOCKED clause.

    if testlock_stack[0] != 0:
        emit_simple(OP_NULL)
        testlock_stack[0] = pc - 1    # Save address for possible overwrite

   #Look for ON ERROR clause
   
    if onerror_stack[0] == 1:
        if look_ahead_token == TKN_END:
            get_token()

        #0074  Need to check for ON ERROR, not just ON otherwise a WRITE
        #followed by an ON GOTO is misinterpretted.

        if u_look_ahead_token_string == "ON" and (token_strings[token_index + 1].upper()) == "ERROR":
            get_token()    # Skip "ON"
            get_token()    # Skip "ERROR"

            #Emit        ONERROR
            #            opcode
            #            DUP
            #            JPZ    L1
            #            POP
            #            Conditioned statements
            #        L1

            emit_simple(OP_ONERROR)
            emit_simple(opcode)
            emit_simple(OP_DUP)

            #Generate jump around ON ERROR clause
            label_name = "_" + str(jump_stack[0][1]) + "A"
            emit_jump(OP_JPZ)

            emit_simple(OP_POP)

            if look_ahead_token == TKN_END:     # ON ERROR / END construct
                get_token()
                #loop
                while True:
                    if end_source:
                        error('back_end - Unterminated ON ERROR clause')

                    #0336 Check for a label
                    get_token()
                    check_for_label()

                #until u_token_string = "END"
                    if u_token_string == "END":
                        break

                    proc_line_prefetched()
                #repeat

            else:                        # Conditional statement on same line
                get_token()
                proc_statement_group()


            #Check that the top of the jump stack is a back end jump
            if jump_stack[0][0] != J_BACK_END:
                error('back_end - Incorrectly formed ON ERROR clause')

            #Generate jump to end of entire construct
            label_name = "_" + str(jump_stack[0][1]) + "X"
            emit_jump(OP_JMP)

            #Set label at end of construct
            label_name = "_" + str(jump_stack[0][1]) + "A"
            set_label()

        else:        # No ON ERROR clause present
            emit_simple(opcode)
        

    else:        # No ON ERROR clause alowed
        if opcode >= 0:
            emit_simple(opcode)


   #Look for LOCKED clause

    if testlock_stack[0] > 0:

        if look_ahead_token == TKN_END:
            get_token()

        if u_look_ahead_token_string == "LOCKED":
            get_token()    # Skip "LOCKED"

            #Go back and insert a NOWAIT opcode at the address on the stack
            #update.addr = testlock.stack<1>
            #code.value = OP.NOWAIT
            #code.bytes = 1
            #gosub update.code
            # just a single byte and it appears update.code is not called by anyone else??
            code_image[testlock_stack[0]] = OP_NOWAIT

            #Emit        DUP
            #            LDLINT ER$LCK
            #            EQ
            #            JZE    L1
            #            POP
            #            Conditioned statements
            #        L1

            emit_simple(OP_DUP)
            emit_numeric_load(ER_LCK)     # ER$LCK
            emit_simple(OP_EQ)

            #Generate jump around LOCKED clause
            label_name = "_" + str(jump_stack[0][1]) + "B"
            emit_jump(OP_JZE)

            emit_simple(OP_POP)
            if look_ahead_token == TKN_END:     # LOCKED / END construct
                get_token()
                #loop
                while True:
                    if end_source:
                        error('back_end - Unterminated LOCKED clause')
                    #0336 Check for a label
                    get_token()
                    check_for_label()
                #until u_token_string = "END"
                    if u_token_string == "END":
                        break
                    proc_line_prefetched()
                #repeat
            else:                        # Conditional statement on same line
                get_token()
                proc_statement_group()

            #Check that the top of the jump stack is a back end jump
            if jump_stack[0][0] != J_BACK_END:
                error('back_end - Incorrectly formed LOCKED clause')

            #Generate jump to end of entire construct
            label_name = "_" + str(jump_stack[0][1]) + "X"
            emit_jump(OP_JMP)

            #Set label at end of construct
            label_name = "_" + str(jump_stack[0][1]) + "B"
            set_label()
 
    if thenelse_stack[0] > 0:

      #Look for THEN and ELSE clauses
      #If thenelse.stack entry = 1 at least one of which must be present
      #If thenelse.stack entry = 2 THEN and ELSE are optional

        if look_ahead_token == TKN_END:
            get_token()

        if thenelse_stack[0] == 2:   # THEN/ELSE is optional
            if (u_look_ahead_token_string != "THEN") and (u_look_ahead_token_string != "ELSE"):
                # goto no.then.or.else.clause
                emit_simple(OP_POP)
                exit_back_end()
                return

        if u_look_ahead_token_string == "ELSE":   # ELSE without THEN
            get_token()              # Skip the ELSE token

            #Generate jump to exit point if would have taken THEN clause
            label_name = "_" + str(jump_stack[0][1]) + "X"
            emit_jump(OP_JZE)

            process_else_clause()
            #Set the exit label here for use by ON ERROR or LOCKED
            label_name = "_" + str(jump_stack[0][1]) + "X"
            set_label()

            exit_back_end()
            return

        if u_look_ahead_token_string != "THEN":          # No THEN clause
            error('back_end - Expected THEN or ELSE')

        get_token()           # Skip "THEN" token

        #Generate jump to ELSE clause (or end if no ELSE)
        label_name = "_" + str(jump_stack[0][1]) + "E"
        emit_jump(OP_JNZ)

        if look_ahead_token == TKN_END:     # THEN / END construct
            get_token()
            #loop
            while True:
                if end_source:
                    error('back_end - Unterminated THEN clause')

                #0336 Check for a label
                get_token()
                check_for_label()
            #until u_token_string = "END"
                if u_token_string == "END":
                    break

                proc_line_prefetched()
            #repeat
        else:                          # Conditional statement on same line
            get_token()
            proc_statement_group()

        #Look for an ELSE clause

        if look_ahead_token == TKN_END:
            get_token()

        if u_look_ahead_token_string == "ELSE":   # ELSE clause present
            get_token()        # Skip ELSE token

            #Check that the top of the jump stack is a back end jump
            if jump_stack[0][0] != J_BACK_END:
                error('back_end - Misplaced ELSE')

            #Emit jump to exit label
            label_name = "_" + str(jump_stack[0][1]) + "X"
            emit_jump(OP_JMP)

            #Set label for head of ELSE clause
            label_name = "_" + str(jump_stack[0][1]) + "E"
            set_label()

#    process.else.clause:
            process_else_clause()
 

        else:                          # No ELSE clause present
            #Check that the top of the jump stack is a back end jump
            if jump_stack[0][0] != J_BACK_END:
                error('back_end - Incorrectly formed THEN clause')

            #Set "E" label at end of construct
            label_name = "_" + str(jump_stack[0][1]) + "E"
            set_label()

    else:       # Statement does not take a THEN or ELSE clause
#no.then.or.else.clause: 
        #Pop the status from the stack
        emit_simple(OP_POP)


    #Set the exit label here for use by ON ERROR or LOCKED
    label_name = "_" + str(jump_stack[0][1]) + "X"
    set_label()

    exit_back_end()


    return

def process_else_clause():
    # needed to correct nasty goto process_else_clause

    if look_ahead_token == TKN_END:     # ELSE / END construct
        get_token()
        #loop
        while True:
            if end_source:
                error('back_end - Unterminated ELSE clause')

            #0336 Check for a label
            get_token()
            check_for_label()
        #until u_token_string = "END"
            if u_token_string == "END":
                break
            proc_line_prefetched()
        #repeat
    else:                        # Conditional statement on same line
        get_token()
        proc_statement_group()

    #Check that the top of the jump stack is a back end jump
    if jump_stack[0][0] != J_BACK_END:
        error('back_end - Incorrectly formed ELSE clause')

    return


def exit_back_end():
    # this is here to handle messy goto in back_end
    #Pop the status from the stack
    global jump_stack, onerror_stack, testlock_stack, thenelse_stack
    #del jump.stack<1>
    #del onerror.stack<1>
    #del testlock.stack<1>
    #del thenelse.stack<1>
    jump_stack.pop(0)
    onerror_stack.pop(0)
    testlock_stack.pop(0)
    thenelse_stack.pop(0)
    return

def continue_exit_common():
    # common routine for st_continue and st_exit
    # Work down jump stack until we find a LOOP or FOR construct
    global label_name
    i = 0
    #loop
    while True:
        n = jump_stack[i][0]
    #until (n = J.LOOP) or (n = J.FOR)
        if (n == J_LOOP) or (n == J_FOR):
            break
        if n == 0:
            error('continue_exit_common -Misplaced ' + token_string)

        i += 1
    #repeat

    label_name = "_" + str(jump_stack[i][1]) + label_name
    emit_jump(OP_JMP)
    return

def write_seq_common(opcode):
   exprf()   # Get record to write
   write_seq_common2(opcode)
   return

def write_seq_common2(opcode):
    global onerror_stack, testlock_stack, thenelse_stack
   
    if (u_look_ahead_token_string != "TO") and (u_look_ahead_token_string != "ON"):
        error('write_seq_common2 - TO or ON not found where expected') 

    get_token()   # Skip TO / ON

    # Emit file variable 

    simple_var_reference()
    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '1' before thenelse.stack<1>     ;* THEN / ELSE clause required
    thenelse_stack.insert(0,1)
    back_end(opcode)

    return

def select_common(opcode):
    """common code for Select statments"""
    global onerror_stack, testlock_stack, thenelse_stack
    # Emit file variable / dynamic array reference

    #gosub convert.pick.file.reference
    expr()    # 0208

    if u_look_ahead_token_string == "TO":
        get_token()       # Skip TO
        if opcode == OP_SELECTV:
            simple_lvar_reference()
        else:
            exprf()            # Emit list number expression

    else:     # Use default select list
        if opcode == OP_SELECTV:
            error('select_common -TO not found where expected') 

        emit_numeric_load(0)
        
    # Perform common back-end processing

    #ins '1' before onerror.stack<1>      #* Optional ON ERROR clause
    onerror_stack.insert(0,1)
    #ins '0' before testlock.stack<1>     #* No LOCKED clause
    testlock_stack.insert(0,0)
    #ins '0' before thenelse.stack<1>     #* No THEN or ELSE clause
    thenelse_stack.insert(0,0) 

    back_end(opcode)
    return
   



def emit_skeleton_header():   # ln 12562
   """   Emit skeleton object header """
   global start_pc, pc
   for i in range(0,OBJECT_HEADER_SIZE):
      emit(0) 

   # setup pointers to next byte to write in code_image
   pc = OBJECT_HEADER_SIZE   
   start_pc = pc     # start_pc is the actual start of op_codes for vm to process?
   return

def emit(bcode):           
    """  Emit byte from OPCODE_BYTE """ 
    global pc, code_image

    if debugging == debug_detail:
        print('emit() byte: ' + hex(bcode) + ' pc b16: ' + hex(pc) )

    # test for neg value, must convert to bytes then to int to get correct value
    # ie if bcode = -1, need 255 if -2 need 254
    if bcode < 0:
        byte_form = bcode.to_bytes(1, byteorder='little', signed=True )
        bcode = int.from_bytes(byte_form, 'little', signed=False)
 
    code_image[pc] = bcode
    pc += 1   # index to next byte for code.image

def emit_simple(bcode):
    """Emit a simple opcode"""
    if bcode > 256:
        # if extended opcode, must emit prefix
        prefixed_opcode = bcode >> 8 # right shift 8 bits
        emit(prefixed_opcode)

        opcode = bcode & 255
        emit(opcode)
    
    else:
        emit(bcode)

    return

def emit_var_load():
    """Emit LDLCL or LDCOM for var in SYMBOL.VAR.NO etc"""
    # Note global vars symbol_var_no, symbol_common_offset, symbol_dim, symbol_common_index  set by find_var()
    if symbol_common_offset >= 0:  # Common variable
        # rem in bcomp  symbol.common.offset is a flag to indicate local var (-1) or
        # common var.  Appears to be set whenever this routine is called

        emit(OP_LDCOM)

        code_value = symbol_var_no
        code_bytes = 2
        emit_multibyte_value(code_value,code_bytes)

        code_value = symbol_common_offset
        code_bytes = 2
        emit_multibyte_value(code_value,code_bytes)
        return


   #  Local variable

    if symbol_var_no < 256: # Use LDSLCL
        emit(OP_LDSLCL)
        emit(symbol_var_no)
    else:                   #  Use LDLCL
        emit(OP_LDLCL)
        code_value = symbol_var_no
        code_bytes = 2
        emit_multibyte_value(code_value,code_bytes)

    return

def emit_string_load(opcode_string):
    """ emit_STRING_LOAD  -  Emit string in OPCODE.STRING """
    global code_image, pc 

    if len(opcode_string) == 0:
        emit_simple(OP_LDNULL)
    else:
        # If the string is less than 256 characters long we can load it in
        #* one go. Otherwise we must concatenate short chunks.

        k = False          # K is true for second and subsequent fragments
        
        while True:
            n = len(opcode_string)
            if n > 255:
                n = 255

            emit(OP_LDSTR)
            emit(n)

            for i in range(n):
                    code_image[pc+i] = ord(opcode_string[i])

            pc += n

            if k:
                # Emit a CAT opcode
                emit_simple(OP_CAT)
           
            k = True
            opcode_string = opcode_string[n:]

            if  len(opcode_string) <= 0:
                break

    return    

def emit_numeric_load(n):
    global pc, code_image
    if isinstance(n, float):
        emit(OP_LDFLOAT)
        ba = bytearray(struct.pack("d", n))  # convert float to bytes
        for i in range(8):
            code_image[pc+i] = ba[i]
        pc += 8

        return

    if (n > -129) and (n < 128): #* Use LDSINT or LD0/LD1
        if n == 0:
            emit_simple(OP_LD0)
            return

        if n == 1:
            emit_simple(OP_LD1)
            return

        # * Emit LDSINT opcode
        emit(OP_LDSINT)
        emit(n)

    else:  # Use LDLINT
        # Emit LDLINT opcode
        emit(OP_LDLINT)
        emit_multibyte_value(n,4)

    return  

def emit_ldsysv(n):
    # Emit LDSYSV opcode, offset is in n
    # Emit LDSYS opcode, offset is in n
    emit_ldsys_common(OP_LDSYSV,n)
    return

def emit_ldsys(n):
    emit_ldsys_common(OP_LDSYS,n)
    return

def emit_ldsys_common(opcode,val):
    sval = str(val)
    # check for dec value ie 1.1
    if '.' in sval:
        sval_list = sval.split('.')
        sval_int = sval_list[0]
        sval_dec = sval_list[1]
        sysv_index = int(sval_dec)
        n = int(sval_int)

    else:
        sysv_index = 0
        n = val

    emit(opcode)
    emit(n)

    # Is this a reference to an array element?
    if sysv_index != 0:
        emit_numeric_load(sysv_index)
        emit_simple(OP_INDX1)

    return  

def emit_function_return_argument():
    """ Emit return argument"""
    global symbol_name, symbol_mode, symbol_dim
    symbol_name = "_FUNC"
    symbol_mode = SYM_SET
    find_var()
    if symbol_var_no < 0:
      symbol_dim = 0
      make_var()
    emit_var_load()

    return

def emit_function_result_load():
    """ Load function result """
    symbol_name = "_FUNC"
    find_var()
    emit_var_load()

    #* 0258 Dereference so that _FUNC can be used again for any later arguments.
    emit_simple(OP_VALUE)
    return  

def emit_multibyte_value(code_value,code_bytes):
    global pc, code_image
    #  EMIT.MULTIBYTE.VALUE  -  Emit multi-byte value
    #  CODE.VALUE   = Value to emit
    #  CODE_BYTES   = Number of bytes
    while code_bytes > 0:
        opcode_byte = (code_value & 255)
        code_value = (code_value >> 8)
        code_image[pc] = opcode_byte
        pc += 1
        code_bytes -= 1

    return    


def emit_at_var_load():
    if u_token_string in at_constants:
        idx = at_constants.index(u_token_string)
        at_constants_func[idx]()
  
    else:
        emit_at_value(u_token_string) # Not a constant @ token, try the SYSCOM variables.

    return

def emit_jump(opcode):
    """ EMIT.JUMP  -  Emit a jump opcode"""
    # LABEL_NAME holds target label

    # Emit the jump opcode
    emit(opcode)
    emit_jump_addr()

    return

def emit_jump_addr():
    """Emit 3 byte jump address"""
    # LABEL_NAME holds target label
    # Find label in symbol table
    
    if label_name in label_dict:
        label_found = True
        jump_addr = label_dict[label_name]
    else:
        label_found = False
        jump_addr = 0

    if label_found: # Label found 
        
        if jump_addr < 0:
            # This is a forward reference. Update the label table to point to
            # this jump to build a chain through all forward references.

            #modify label.tree, -pc
            label_dict[label_name] = -pc
            jump_addr = -jump_addr

    else:    # Label not found - add it as forward reference

        label_dict[label_name] = -pc
        jump_addr = 0


    # Emit the jump address
    code_value = jump_addr
    code_bytes = 3
    emit_multibyte_value(code_value,code_bytes)

    return    

def emit_direct_call_reference(sname):
    """emit call to sname"""
    global symbol_common_offset, symbol_var_no, symbol_name, symbol_mode, symbol_dim, direct_calls, direct_call_vars
    # Check to see if we already know this subroutine name. If not, add it
    # to the list of direct calls and create a local variable for it.

    symbol_common_offset = -1     #;* Local variable

    #locate sname in direct.calls<1> setting i then
    if sname in direct_calls: 
        symbol_var_no = direct_call_vars[sname] # Variable number
        symbol_name = "_" + sname
    else:
        symbol_name = "_" +  sname
        symbol_dim = 0
        symbol_mode = SYM_SET
        make_var()

        direct_calls.insert(0,sname)
        direct_call_vars[sname] = symbol_var_no

    emit_var_load()

    return



def emit_function_return_argument():
    """Emit return argument"""
    global symbol_name, symbol_mode, symbol_dim

    symbol_name = "_FUNC"
    symbol_mode = SYM_SET
    find_var()
    if symbol_var_no < 0:
        symbol_dim = 0
        make_var()

    emit_var_load()

    return


def emit_function_result_load():
    """Load function result"""
    global symbol_name
    symbol_name = "_FUNC"
    find_var()
    emit_var_load()

   # 0258 Dereference so that _FUNC can be used again for any later arguments.
    emit_simple(OP_VALUE)

    return

def emit_temp_ref(n):
    """Emit load of temporary variable N"""
    global symbol_name, symbol_mode, symbol_dim
    symbol_name = '__' + str(n)
    symbol_mode = SYM_SET
    find_var()
    if symbol_var_no < 0:
        symbol_dim = 0
        make_var()
    
    emit_var_load()
    return



def proc_line():
   """mimic proc.line at 1866 in bcomp source"""
   get_token()  # get first token
   #  note BCOMP likes to have "subroutines" layered into one and other
   #  hopefully we can break them apart like here with proc_line_prefetched()
   proc_line_prefetched()
   return

def proc_line_prefetched():
    #  emit_xref_entry() no cross ref table being generated, don't need to code

    check_for_label()   # Check for a label at the start of the line

    proc_statement_group()

    if look_ahead_token == TKN_END:
        get_token()       #* Skip end of line token

    return

def proc_statement_group():
    """ PROC.STATEMENT.GROUP  -  Process statements delimited by semicolons"""
    while True:
        proc_statement()
        if look_ahead_token != TKN_SEMICOLON:
            break
        get_token()       # Skip semicolon
        get_token()       # Get next token
    return


def proc_statement():
    """Version of proc.statement from bcomp"""

    start_again = True      # proc.statement uses goto's to start at top for sub, need to mimc
    
    while start_again:
        start_again = False

        if debugging == debug_detail:
            print('proc_statement token#: ' + str(token) + ' token string: ' + u_token_string ) 
            print('   look_ahead_token#: ' + str(look_ahead_token)  + ' look ahead token string: ' + u_look_ahead_token_string)

        if token == TKN_NAME:

            if look_ahead_token == TKN_NAME:
                is_statement()

            elif look_ahead_token == TKN_EQ:        # Assignment
                is_assignment()
            elif look_ahead_token == TKN_ADDEQ:     # += Assignment
                is_assignment()
            elif look_ahead_token == TKN_SUBEQ:     # -= Assignment
                is_assignment()
            elif look_ahead_token == TKN_CATEQ:     # := Assignment
                is_assignment()
            elif look_ahead_token == TKN_LSQBR:     # Substring assignment
                is_assignment()
            elif look_ahead_token == TKN_LT:        # Field assignment
                is_assignment()
            elif look_ahead_token == TKN_MULTEQ:    # *= Assignment
                is_assignment()
            elif look_ahead_token == TKN_DIVEQ:     # /= Assignment
                is_assignment()
            elif look_ahead_token == TKN_OBJREF:    # Object reference            
                error(' Object() not supported  ')
            else:     # statement
                is_statement()

        
        elif token == TKN_NAME_LBR:
    #        Handle special cases: RETURN(value), LOCATE(...), RANDOMIZE(n)
            if u_token_string == 'RETURN':
                is_statement()
            elif u_token_string == 'LOCATE':
                is_statement()
            elif u_token_string == 'RANDOMIZE':
                is_statement()
            elif u_token_string == 'SUB':
                is_statement()
            elif u_token_string == 'SUBROUTINE':
                is_statement()
            else:
                is_assignment()

        elif token == TKN_AT_NAME:          
            get_token()   # Get @variable name
            emit_at_lvalue(u_token_string)
            process_operator()

        elif token == TKN_END:
            pass

        elif token == TKN_SEMICOLON:
            get_token()
            start_again = True      # start again for leading semicolon (mimic goto)

        else:
            if (token_string == '$' or token_string == '#') and (token_index == 2):
                # appears to be a compilier directive which should have already been processed
                error('compilier directive found at compile stage, error')

            error('proc_statment - Unrecognized statement, token_string: ' + token_string + ' number: ' + str(token))

    return

def is_statement():
    """call function to process token as statement name"""
# There is no on gosub in python, so what we are going to do is call via a dictionary
# if token in STATEMENTS:
#    STATEMENTS[token]()          # dictionary references python function object 
# elif:  
#    and so on
    if u_token_string in STATEMENTS:
        STATEMENTS[u_token_string]()          # dictionary references python function object 

    elif u_token_string in non_debug_statements:
        non_debug_statements[u_token_string]()

    elif u_token_string in restricted_statements:
        restricted_statements[u_token_string]()
    else:
        error('Unrecognised statement: ' + u_token_string)
    return

def is_assignment():
    """ process assignment """
    # note in bcomp there is a block of code at is.assignment for handling the FILE command, we are not supporting
    # so you do not see it here!
    if debugging == debug_detail:
        print('is_assignment, token: ' + token_string)

    emit_lvar_reference()       # Set up a reference to the target variable

    # note in bcomp there is a block of code at is.assignment for handling objects, we are not supporting
    # so you do not see it here!

    process_operator()

    return

def process_operator():
    """ process assignment operator """
    global opcode_byte, format_qualifier_allowed

    if look_ahead_token == TKN_EQ:
        get_token()
        if look_ahead_token == TKN_NUM:
            if look_ahead_token_string == "0":  # zero
                if tokens[token_index + 1] == TKN_END:
                    emit_simple(OP_STZ)
                    get_token()
                    return

        if look_ahead_token == TKN_STRING:
            if look_ahead_token_string == '':  # null string
                if tokens[token_index + 1] == TKN_END:
                    emit_simple(OP_STNULL)
                    get_token()
                    return

        exprf()  # Process expression format.qualifier.allowed

        emit_simple(OP_STOR) 

    elif look_ahead_token == TKN_ADDEQ:     # += Assignment  
        get_token()
        if look_ahead_token == TKN_NUM:
            if look_ahead_token_string == "1":
                if tokens[token_index + 1] == TKN_END:
                    emit_simple(OP_INC)
                    get_token()
                    return                             

        emit_simple(OP_DUP)
        exprf()  # Process expression format.qualifier.allowed
        emit_simple(OP_ADD)        
        emit_simple(OP_STOR)

    elif look_ahead_token == TKN_SUBEQ:     # -= Assignment 
        get_token()
        if look_ahead_token == TKN_NUM:
            if look_ahead_token_string == "1":     
                if tokens[token_index + 1] == TKN_END:
                    emit_simple(OP_DEC)
                    get_token()
                    return

        emit_simple(OP_DUP)
        exprf()  # Process expression format.qualifier.allowed
        emit_simple(OP_SUB)        
        emit_simple(OP_STOR) 

    elif look_ahead_token == TKN_CATEQ:     # := Assignment  
        get_token()
        exprf()  # Process expression format.qualifier.allowed  
        emit_simple(OP_APPEND) 

    elif look_ahead_token == TKN_MULTEQ:     #* /= Assignment
        get_token()
        emit_simple(OP_DUP)
        exprf()  # Process expression format.qualifier.allowed 
        emit_simple(OP_MUL)
        emit_simple(OP_STOR)

    elif look_ahead_token == TKN_DIVEQ:     #* /= Assignment
        get_token()
        emit_simple(OP_DUP)
        exprf()  # Process expression format.qualifier.allowed 
        emit_simple(OP_DIV)
        emit_simple(OP_STOR)

    elif look_ahead_token == TKN_LSQBR:  #  Substring assignment
      # This may be substring assignment s[x,y] = sss
      # or delimited substring assignment s[d,x,y] = sss

        get_token()     #* Skip [ token
        expr()     #* Process start position / delimiter 
        check_comma()
        expr()     #* Process length expresssion / position

        if look_ahead_token == TKN_RSQBR:     # Substring asssignment
            get_token()   # skip bracket
            if look_ahead_token != TKN_EQ:
                error('Expected equals after substring lvalue expression')
            get_token()

            # process rvalue expression
            exprf()  # Process expression format.qualifier.allowed   

            # store the results
            # note there is some PICK mode bs we are skipping
            emit_simple(OP_SUBSTRA)

        else:  # Delimited substring assignment
            check_comma()
            expr()     #* Process length expresssion / position

            if look_ahead_token != TKN_RSQBR:
                error('Right square bracket not found where expected')

            get_token() # Skip bracket
            if look_ahead_token != TKN_EQ:
                error('Expected equals after substring lvalue expression') 
            
            get_token()
            exprf()  # Process expression format.qualifier.allowed 

            emit_simple(OP_FLDSTOR)

    elif look_ahead_token == TKN_LT:   # Field assignment    
        format_qualifier_allowed = False        
        is_field_ref()
        if ifr_index == 0:
            error('Improperly formed field assignment')

        get_token()   # skip "<" token
        emit_field_reference()

        # fetch process operator
        if look_ahead_token == TKN_EQ:
            get_token()
            exprf()        # Process the rvalue expression  
            emit_simple(OP_REP)

        elif look_ahead_token == TKN_ADDEQ:  # += Assignment
            get_token()
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPADD)
               
        elif look_ahead_token == TKN_SUBEQ:  # -= Assignment
            get_token()
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPSUB)

        elif look_ahead_token == TKN_CATEQ:  # := Assignment
            get_token()
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPCAT)

        elif look_ahead_token == TKN_MULTEQ:  # *= Assignment
            get_token()
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPMUL)    

        elif look_ahead_token == TKN_DIVEQ:  # /= Assignment
            get_token()
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPDIV)       

        elif look_ahead_token == TKN_LSQBR:  # Substring assignment
            # The only valid style is var<f,v,s>[p,q] = xxx
            get_token()    # skip '['
            expr()        # Process start position
            check_comma()
            expr()        # Process start position
            
            if look_ahead_token != TKN_RSQBR:
                error('Right square bracket not found where expected')    
            
            get_token()   # skip bracket
            if look_ahead_token != TKN_EQ:
                error('Illegal operator')

            get_token()    # skip '='
            exprf()        # Process the rvalue expression
            emit_simple(OP_REPSUBST)

        else:
            error('Illegal operator after field expression')

    return

def is_field_ref():
    """Establish the role of a < token"""  
    global num_tokens, ifr_index
#*****************************************************************************
# IS.FIELD.REF  -  Establish the role of a < token
#
# On entry, the < token is in the look-ahead.  Examine subsequent tokens
# to establish whether this is a field reference or not.
#
# It is a field reference if
#    we find a matching > taking into account pairing of other < tokens
#    and round brackets found on the way
# unless
#    the > token is followed by
#      a name except for reserved tokens (THEN, ELSE, SETTING, BY, GO, GOTO,
#      GOSUB, BEFORE)
#      a name.lbr
#      a number
#      a string
#    or the enclosed expression includes the THEN, AND or OR keywords
#
# If it is a field reference, the > token is replaced by TKN.END.FIELD and
# its position is returned in IFR.INDEX. Otherwise, IFR.INDEX is set to zero.
#

    ifr_first = token_index + 1  # Point after < token
    i = 0                        # Current bracket depth
    j = 1                        # Current field depth
    ifr_index = 0

    n = ifr_first
    #loop
    # mimic goto exit.is.field.ref
    exit_is_field_ref = False
    while True:
        k = tokens[n]

        # begin case
        if k == TKN_END:  # End of source line
           exit_is_field_ref = True
           break

        elif k == TKN_LT:
            if i == 0:
                j += 1

        elif k == TKN_GT:
            if i == 0:
                j -= 1

        elif k == TKN_GE or k == TKN_NEX:
            if i == 0:
                j -= 1

        elif k == TKN_LBR:
            i += 1

        elif k == TKN_RBR:
            i -= 1
            if i < 0:
                exit_is_field_ref = True
                break

        elif k == TKN_AND:
            if i == 0:
                exit_is_field_ref = True
                break

        elif k == TKN_OR:
            if i == 0:
                exit_is_field_ref = True
                break                

        elif token_strings[n].upper() == 'THEN':
            if i == 0:
                exit_is_field_ref = True
                break

        #end case

        if (i == 0) and (j == 0):
            break

        n += 1
    # repeat

    #mimic goto 
    if not exit_is_field_ref: 
   
        # We have found a matching > token. Now look to see what follows it.

        
        if k == TKN_GE:
            pass
        elif k == TKN_NEX:
            pass
        else:
            k = tokens[n + 1]
        

        i = n - ifr_first   # Number of tokens between < and >
        if i != 1:
            #begin case
            if k == TKN_NAME:
                if not format_qualifier_allowed:
                    #find upcase(token.strings(n + 1)) in reserved.names setting z ;* 0265
                    if token_strings[n+1].upper() in reserved_names:
                        pass
                    else:
                        exit_is_field_ref = True

            elif k == TKN_NAME_LBR:
                if not format_qualifier_allowed:
                    exit_is_field_ref = True

            elif k == TKN_NUM:
                exit_is_field_ref = True

            elif k == TKN_HEXNUM:
                exit_is_field_ref = True

            elif k == TKN_FLOAT:
                exit_is_field_ref = True

            elif k == TKN_STRING:
                if not format_qualifier_allowed:
                    exit_is_field_ref = True
            #end case

        #mimic goto 
        if not exit_is_field_ref: 

            ifr_index = n

            #begin case
            if tokens[n] == TKN_GE:
                if num_tokens >= INIT_TOKENS:
                    error('is_field_ref: expand token tables')   

                for k in range(num_tokens, n, -1):     
                    tokens[k+1] = tokens[k]
                    token_strings[k+1] = token_strings[k]

                tokens[n+1] = TKN_EQ
                token_strings[n+1] = '='
                num_tokens += 1

            elif tokens[n] == TKN_NEX:           # ><
                if token_strings[n+1] == '=': # a<b><=c  ->  a<b> <= c
                    tokens[n+1] = TKN_LE
                    token_strings[n+1] = '<='
                else:                         # a<b><c (etc)
                    if num_tokens >= INIT_TOKENS: # Must expand tables
                        error('is_field_ref:: expand token tables') 

                    for k in range(num_tokens, n, -1):
                        tokens[k+1] = tokens[k]
                        token_strings[k+1] = token_strings[k]

                    tokens[n+1] = TKN_LT
                    token_strings[n+1] = '<'
                    num_tokens += 1
            #end case

            tokens[n] = TKN_END_FIELD

# exit.is.field.ref:
    return      

def expr():
    global format_qualifier_allowed
    """expr_common format.qualifier.allowed not allowed """
    format_qualifier_allowed = False
    expr_common()
    return

def exprf():
    global format_qualifier_allowed   
    """expr_common format.qualifier.allowed allowed """
    format_qualifier_allowed = True
    expr_common()
    return

#****************************************************************************
# EXPR  -  Process expression
#
# ------  +  ----------  (  ---  expr  ---  )  ---|
#   |---  -  ---|   |-------  var  -------------------  op  ---  expr  ---
#   |-----------|   |-------  const  -------------| |-------------------|
#
def expr_common():
    global unary_minus, op_stack_depth, token, format_qualifier_allowed
    # op_stack_depth starts out = -1, python zero index based, keeps inc lodgic remains the same 

    get_token()

    if unary_minus:
        op_stack_depth += 1
        operator_stack[op_stack_depth] = OP_NEG
        priority_stack[op_stack_depth] = 1
        unary_minus = False
    

    op_stack_depth += 1
    priority_stack[op_stack_depth] = STACK_MARK

    
    # loop
    while True:   
        get_expr_item()
        
        if format_qualifier_allowed:
            # Check for a format qualifier

            if look_ahead_token == TKN_NAME:
                if u_look_ahead_token_string in reserved_names:
                    pass
                elif look_ahead_token != TKN_NAME_LBR and look_ahead_token != TKN_STRING and look_ahead_token != TKN_LBR:
                    pass
                else:
                    # Insert a pseudo operator at this point

                    token = TKN_FMT
                    insert_pseudo_operator() 
                    continue   # bcomp code does a goto insert_pseudo_operator:
                            # and falls thru to repeat, this should mimic lodgic                

        # Check for other operators using look ahead

    #until look_ahead_token < TKN.LOW.OPERATOR
    #until look_ahead_token > TKN.HIGH.OPERATOR
        if look_ahead_token < TKN_LOW_OPERATOR:
            break
        if look_ahead_token > TKN_HIGH_OPERATOR:
            break
        
        # Special case for colon operator.
        # Because the colon has special meaning in DISPLAY and INPUT, we need to
        # try to identify if this colon is an operator or a special use (or a
        # syntax error).  As a best guess, we check to see if what follows it
        # looks like a valid expression element.

        if look_ahead_token == TKN_COLON:
            i = token_index + 1
            j = tokens[i]

            # begin case
            if j == TKN_NAME:
                k = token_strings[i].upper()
                if k in reserved_names:
                    break
            elif j == TKN_NAME_LBR:
                pass
            elif j == TKN_NUM:
                pass
            elif j == TKN_HEXNUM:
                pass
            elif j == TKN_STRING:
                pass         
            elif j == TKN_FLOAT:
                pass         
            elif j == TKN_AT_NAME:
                pass         
            elif j == TKN_AT:
                pass        
            elif j == TKN_LBR:
                pass         
            elif j == TKN_PLUS:               # Unary plus
                pass         
            elif j == TKN_MINUS:              # Unary minus
                pass         
            elif j == TKN_LCBR:
                pass         
            else:
                # Does not appear to be followed by an expression item.
                break

        get_token()   # Read operator token

        insert_pseudo_operator()

    # repeat end of while loop

    # Apply remaining operators from stack


    while priority_stack[op_stack_depth] != STACK_MARK:
        opcode = operator_stack[op_stack_depth]
        emit_simple(opcode)
        op_stack_depth -= 1  

    # if op.stack.depth then op.stack.depth -= 1    ;* Remove STACK.MARK
    # rem treating stack is 1 based based
    if op_stack_depth > 0:
        op_stack_depth -= 1    # Remove STACK.MARK

    return
   
def insert_pseudo_operator():
    global op_stack_depth

    if debugging == debug_detail:
        print ('insert_pseudo_operator()')
        print ('op_stack_depth: ' + str(op_stack_depth) )
        print ('operator_stack[0:5]: ', operator_stack[0:5] )

    priority = op_priority[token]

    #loop
    while priority >= priority_stack[op_stack_depth]:
        opcode = operator_stack[op_stack_depth]
        emit_simple(opcode)
        op_stack_depth -= 1
    #repeat

    op_stack_depth += 1
    operator_stack[op_stack_depth] =  op[token] #  Opcode from Operator token / opcodes relationship list
    if look_ahead_token == TKN_PWR: 
        # The ** operator associates right to left. Save a slightly higher
        # priority on the stack to force this action.
        priority_stack[op_stack_depth] = priority + 1            #* Priority

    else:
        priority_stack[op_stack_depth] = priority                # Priority

    get_token()  # Get next data item token
    
    return

def get_expr_item():
   global format_allowed_stack, format_qualifier_allowed, unary_minus
   format_allowed_stack.insert(0,format_qualifier_allowed)
   unary_minus = False
   get_expr_item_again()
   return

def get_expr_item_again():
    global jump_no, jump_stack, format_allowed_stack, format_qualifier_allowed, unary_minus, label_name
    # mimic goto start of function
    get_expr_item_again_jmp = True
    while get_expr_item_again_jmp:
        get_expr_item_again_jmp = False
        #begin case
        if token == TKN_NAME:
            if u_token_string == "IF":
                exprf()         # Process condition

                # Add new entry to jump stack

                jmp_val = [J_IF_EXPR,jump_no,0]
                jump_stack.insert(0,jmp_val)
                label_name = "_" + str(jump_no) + "E"
                jump_no += 1
                emit_jump(OP_JFALSE)

                # Emit THEN clause

                if u_look_ahead_token_string != "THEN": 
                    error('THEN not found where expected in conditional expression')

                get_token()

                exprf()  # Process THEN clause

                # Emit jump to exit label

                label_name = "_" + str(jump_stack[0][1]) + "X"
                emit_jump(OP_JMP)

                # Emit ELSE clause

                label_name = "_" + str(jump_stack[0][1]) + "E"
                set_label()

                if u_look_ahead_token_string != "ELSE":
                    error('ELSE not found where expected in conditional expression')

                get_token()

                exprf()        # Process ELSE clause

                # Emit exit label
                label_name = "_" + str(jump_stack[0][1]) + "X"
                set_label()

        # if.then.else.expr.abort:
                jump_stack.pop(0)
            else:
                emit_var_reference()

                #loop
                #while look_ahead_token = TKN.OBJREF
                if look_ahead_token ==  TKN_OBJREF:
                    error('Objects not supported')
                    #gosub expr.item.is.objref ; if err then goto exit.get.expr.item
                #repeat
        
        elif token == TKN_NAME_LBR:
            emit_var_reference()

            #loop
            #while look.ahead.token = TKN.OBJREF
            if look_ahead_token ==  TKN_OBJREF:
                error('Objects not supported')
            #gosub expr.item.is.objref ; if err then goto exit.get.expr.item
            #repeat

        elif token == TKN_NUM or token == TKN_FLOAT:
            n =int_or_float(token_string)
            if unary_minus:
                n = -n
                unary_minus = False

            emit_numeric_load(n)

        elif token == TKN_HEXNUM:
            n = int(token_string,16)
            if unary_minus:
                n = -n
                unary_minus = False
            emit_numeric_load(n)

        elif token == TKN_STRING:
            emit_string_load(token_string)

        elif token == TKN_AT_NAME:
            get_token()
            emit_at_var_load()

        elif token == TKN_AT:

            #begin case
            if look_ahead_token == TKN_LBR:  # @(n) function
                get_token()      # Skip left bracket
                exprf()          # Load first argument
                if look_ahead_token == TKN_COMMA:  # Two arguments
                    get_token()
                    if look_ahead_token == TKN_END:
                        error('Argument missing in @ function')
    
                    exprf() # Load second argument
                else:       # Single argument - Set second as -1
                    emit_numeric_load(-1)

                emit_simple(OP_AT)

                if look_ahead_token !=  TKN_RBR:
                    error('Right bracket not found where expected') 

                get_token()         # Skip close bracket

            # case 1
            else:
                error('Unrecognised @ function')

            #end case

        elif token == TKN_LBR:
            # Call EXPR recursively to process the content of the brackets

            exprf()

            # Check that the next token is a close bracket

            get_token()
            if token != TKN_RBR:
                error('Mismatched brackets')

        elif token == TKN_PLUS:  # Unary plus
            get_token()
            # mimic goto get_expr_item_again
            get_expr_item_again_jmp = True

        elif token == TKN_MINUS:   # Unary minus
            unary_minus = not unary_minus
            get_token()
            # mimic goto get_expr_item_again
            get_expr_item_again_jmp = True

        elif token == TKN_LCBR: # {name}
            # there is a bunch of code we are skipping here, this is not supported
            error(' {name} requires use of $DICT compiler directive, not supported')

                
           # case 1
        else:
            error(' Data item or constant not found where expected')
        #end case

   # Check for field / substring extractions in any order, possibly repeated

    # loop
    # begin case
    while True:
        if look_ahead_token == TKN_LT:  # Field extraction
            is_field_ref()
            if not ifr_index:
                break

            get_token()   # Skip < token
            emit_field_reference()
            # if err then goto exit.get.expr.item
            emit_simple(OP_EXTRACT)

        elif look_ahead_token == TKN_LSQBR:  # Substring or group extraction
            get_token()   # Skip [ token
            exprf()       # Process first (or only) bound
            if look_ahead_token == TKN_COMMA:   # Two bounds present
                get_token()  # Skip comma
                exprf()      # Get substring length
                if look_ahead_token == TKN_COMMA:  # Three items, group extraction
                    get_token()  # Skip comma
                    exprf()      # Get field count
                    emit_simple(OP_FIELD)
                else:
                    emit_simple(OP_SUBSTR)
            else:  #   Trailing substring extraction
                emit_simple(OP_SUBSTRE)

            if look_ahead_token != TKN_RSQBR:
                error('Right square bracket not found where expected')

            get_token()    # Skip bracket

        else:
            break
    # end case
    #repeat

    if unary_minus:
        emit_simple(OP_NEG)
        unary_minus = False


    format_qualifier_allowed = format_allowed_stack[0]
    format_allowed_stack.pop(0)

    return

def simple_lvar_reference():
    simple_var_reference_common(True)
    return

def simple_var_reference():
    simple_var_reference_common(False)
    return    

def simple_var_reference_common(is_lvar):     # note in BCOMP lvar not is_lvar
   # The reference must be a scalar or array element, not an expression,
   # substring or dynamic array field extraction

    if look_ahead_token == TKN_AT or look_ahead_token == TKN_AT_NAME:
        get_token()            #* Skip @ token
        if look_ahead_token != TKN_NAME:
            error('Incorrectly formed @ variable name ')

        get_token()
        emit_at_var_load()
        return
 
    get_var_name()
    emit_var_reference_common(is_lvar,False) 
    return

def emit_lvar_reference():
    emit_var_reference_common(True,False)
    return

def emit_var_reference():
    emit_var_reference_common(False,True)
    return   

def emit_var_reference_common(is_lvar,funcion_allowed):
    global symbol_mode, symbol_name, symbol_dim, symbol_common_offset, saved_symbol_mode, intrinsic_stack,matrix_stack, opcode_byte 

    if debugging == debug_detail:
        print('emit_var_reference_common, token: ' + token_string)
    
    # check if token is in defined_tokens
    if u_token_string in defined_tokens:
        t_type = defined_tokens[u_token_string][1]   # get type
        if t_type == is_string:
            if is_lvar:
                error ('emit_var_reference_common - Variable name not found where expected')   # cannot have this on the left side of the =
            else:
                opcode_string = defined_tokens[u_token_string][0]
                # remove qoute marks
                if opcode_string[0] == '"' and opcode_string[-1] == '"':
                    opcode_string = opcode_string.replace('"', '')
                elif opcode_string[0] == "'" and opcode_string[-1] == "'":
                    opcode_string = opcode_string.replace("'", '')
                emit_string_load(opcode_string)  
                return  

        elif t_type == is_number:
            if is_lvar:
                error ('emit_var_reference_common - Variable name not found where expected')   # cannot have this on the left side of the =
            else:
                emit_numeric_load(defined_tokens[u_token_string][0])
                return
            
        elif t_type == is_charfunct:
            if is_lvar:
                error ('emit_var_reference_common - Variable name not found where expected')   # cannot have this on the left side of the =
            else:
                opcode_string = chr(defined_tokens[u_token_string][0])
                emit_string_load(opcode_string)
                return 
            
        # note in emit.var.reference.common there is code to handle different type of defined_tokens from EQUATE statements.
        # We don't support EQUATES, so you are not going to see it here ......

    # not a $DEFINE token

    if is_lvar:
        symbol_mode = SYM_SET
    if token == TKN_NAME_LBR:
        possible_function = True
    else:
        possible_function = False

    symbol_name = token_string
    saved_symbol_mode = symbol_mode
    find_var()
    if symbol_var_no < 0 or symbol_dim == 0:
        # not known as a matrix

        if possible_function:
            if funcion_allowed:
                #  Check for functions. Any array should have been mentioned
                # in a DIM statement by now.

                #  Try as a user declared function. These may be case sensitive
                if symbol_name in functions:
                    user_declared_function(symbol_name)
                    return
                #
                #
                #
                #  Try as an intrinsic function.  If we don't recognise it
                #  we will jump to not.an.intrinsic.
                if symbol_name in intrinsics:
                    get_token()
                    op_code = intrinsics[symbol_name][0]  # list element 0 is the actaul op code to emit
                    intrinsic_stack.insert(0,op_code)        # add to intrinsic_stack for ??
                    intrinsics[symbol_name][1]()          # list element 1 is the python function object 
                    # we have executed the function that handles the intrinsic function
                    # which will call intrinsic.common() and wrap up the emit process, return to caller
                    return                    
                
                elif symbol_name in int_intrinsics:
                    get_token()
                    op_code = int_intrinsics[symbol_name][0]  # list element 0 is the actaul op code to emit
                    intrinsic_stack.insert(0,op_code)        # add to intrinsic_stack for ??
                    int_intrinsics[symbol_name][1]()          # list element 1 is the python function object
                    # we have executed the function that handles the intrinsic function
                    # which will call intrinsic.common() and wrap up the emit process, return to caller
                    return  
                else:
                    # bcomp checks for the FILE statement here, we do not support therefore:
                    error('emit_var_reference_common - Unrecognised function: ' + symbol_name)
                
                # The symbol doesn't seem to be a function so assume that it
                # is a yet to be dimensioned matrix.

            if is_lvar:
                symbol_mode = SYM_SET
            else:
                symbol_mode = SYM_USE
            symbol_dim = -1          # Indicate not yet known
            symbol_common_offset = -1
            make_var()
    
    if symbol_var_no < 0: # don't know this variable
        # create new one
        symbol_mode = saved_symbol_mode   # Restore for variable creation
        symbol_common_offset = -1
        symbol_dim = 0
        if is_lvar:
            symbol_mode = SYM_SET
        make_var() 

    # generate LDLCL or LDCOM
    emit_var_load()    

    # Is it an array reference?
    if symbol_dim != 0:
        if look_ahead_token == TKN_LBR:  # Subscript present?
            get_token()     # Skip left bracket

            # Generate indexing code and check right number of dimensions

            matrix_stack.insert(0,symbol_dim)   # 0181  Stack dimension...
            exprf()
            symbol_dim = matrix_stack[0]        # 0181  ...and restore
            matrix_stack.pop(0)   

            if look_ahead_token == TKN_COMMA:   # two indices present
                get_token()                     # skip comma
                exprf()
                emit_simple(OP_INDX2)
            else:                              # only one indec present
                emit_simple(OP_INDX1)  

            if look_ahead_token != TKN_RBR:
                error('emit_var_reference_common - Right bracket not found where expected')  

            get_token()

        else:     # No subscript present
            error('emit_var_reference_common - Matrix reference requires index, token: ' + u_token_string + ' ' )

    return

def emit_at_lvalue(val):
    """Emit LDSYS for @variable as lvalue (name in token)"""
    # val is u_token_string
    # use token (at_syscom_var) to lookup position in at_syscom_vars
    #  and use that index to grab actual offset from at_syscom_offsets
    #
    # also note offsets can be of the form 67.0 eg SYSCOM_PROC_IBUF_0
    if val in at_syscom_vars:
        sysvar_idx =  at_syscom_vars.index(val)
        sysvar_off =  at_syscom_offsets[sysvar_idx]

        # check for x.y

        if isinstance(sysvar_off, float):
            sval = str(sysvar_off)
            sval_list = sval.split('.')
            sval_int = sval_list[0]
            sval_dec = sval_list[1]
            sysv_index = int(sval_dec)
            n = int(sval_int)
        else:
            sysv_index = 0
            n = sysvar_off   
        
        emit_ldsys(n)

        # Is this a reference to an array element?
        if sysv_index != 0:
            emit_numeric_load(sysv_index)
            emit_simple(OP_INDX1)

    else: 
        error('Unrecognised @ variable')

    return

def emit_at_value(val):
    """Emit LDSYS or LDSYSV for @variable (name in token)"""
    # val is u_token_string
    if val in at_syscom_vars:
        # in BCOMP there is a difference between internal mode here
        # in bbcmp we are always internal mode so just hitting that branch

        # must look up offset value in syscom for passed string value
        # rem at_syscom_vars list and at_syscom_offsets list are "linked"
        idx = at_syscom_vars.index(val)
        emit_val = at_syscom_offsets[idx]
        emit_ldsys(emit_val)
    else:
        error('Unrecognised @ variable')        

    return

def emit_field_reference():
    """EMIT.FIELD.REFERENCE  -  Process <f,v,s> construct"""
    # On entry, we are positioned after the < token
    # On exit, we will be positioned after the > token 

    exprf()     # Get field position

    #  Get value position
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        # Emit a zero value position reference
        emit_numeric_load(0)

    # Get subvalue position
    if look_ahead_token == TKN_COMMA:
        get_token()
        exprf()
    else:
        # Emit a zero subvalue position reference
        emit_numeric_load(0)

    if look_ahead_token != TKN_END_FIELD:
        error('Incorrectly formed field reference')

    get_token()      # Skip > token
    
    return

def emit_print_list(print_opcode):
    """Emit a list of print items and opcode to print it"""
    # PRINT_OPCODE contains either OP.DSP or OP.PRNT.  The related "with newline"
    # opcode can be found by adding one to this opcode value.
    n = 0
    if look_ahead_token == TKN_NAME:
        # find u.look.ahead.token.string in reserved.names setting n else null ;*0303
        if u_look_ahead_token_string in reserved_names:
            n = 1

    if look_ahead_token == TKN_END or look_ahead_token == TKN_SEMICOLON or n > 0:
        emit_string_load('')
        emit_simple(print_opcode + 1)
    else:
        exprf()   # Emit first expression

        #loop        
        while look_ahead_token == TKN_COMMA:
        #until look_ahead_token = TKN.END or look_ahead_token = TKN.SEMICOLON
            if look_ahead_token == TKN_END or look_ahead_token == TKN_SEMICOLON:
                break


            get_token()

            # Emit code to append a tab to the string
            emit_string_load(chr(9))
            emit_simple(OP_CAT)
            exprf()
            emit_simple(OP_CAT)
        #repeat

        if look_ahead_token == TKN_COLON:
            get_token()
        else:
            print_opcode = print_opcode + 1

        emit_simple(print_opcode)
    return    


def emit_final_header():
    """ Update object header at end of compilation """
    global code_image

    # Magic number. Offset 0, 1 byte
    #i = if system(1009) then HDR.MAGIC.NO.B else HDR.MAGIC.NO.L
    # its 100 for For little endian machines
    code_image[HDR_MAGIC] = HDR_MAGIC_NO_L

    # Object revision. 1 byte
    code_image[HDR_REV] = HDR_REVISION

    # Start PC. 4 bytes
    #code_image[HDR.START.OFFSET,4] = iconv(start.pc, 'IL')
    str_pc = start_pc.to_bytes(4, byteorder='little')
    for i in range(4):
        code_image[HDR_START_OFFSET+i] = str_pc[i]
 
    # Argument count. 2 bytes
    # code_image[HDR_ARGS,2] = iconv(subr.arg.count, 'IS')
    arg_cnt = subr_arg_count.to_bytes(2, byteorder='little')
    code_image[HDR_ARGS]   = arg_cnt[0]
    code_image[HDR_ARGS+1] = arg_cnt[1]

    # Local variable count. 2 bytes
    # code_image[HDR.NO.VARS,2] = iconv(var.count, 'IS')
    var_cnt = var_count.to_bytes(2, byteorder='little')
    code_image[HDR_NO_VARS]   = var_cnt[0]
    code_image[HDR_NO_VARS+1] = var_cnt[1]


    # Stack depth. 2 bytes
    call_arg_cnt = greatest_call_arg_count + 100
    arg_cnt = call_arg_cnt.to_bytes(2, byteorder='little')
    code_image[HDR_STACK_DEPTH] = arg_cnt[0]
    code_image[HDR_STACK_DEPTH+1] = arg_cnt[1]

    # Symbol table offset. 4 bytes
    # code_image[HDR_SYM_TAB_OFFSET] = iconv(symbol.table.offset, 'IL')
    table_offset = symbol_table_offset.to_bytes(4, byteorder='little')
    for i in range(4):
        code_image[HDR_SYM_TAB_OFFSET+i] = table_offset[i]

    # Line table offset. 4 bytes
    # code_image[HDR.LIN.TAB.OFFSET,4] = iconv(line.table.offset, 'IL')
    table_offset = line_table_offset.to_bytes(4, byteorder='little')
    for i in range(4):
        code_image[HDR_LIN_TAB_OFFSET+i] = table_offset[i]

    # Object size. 4 bytes
    # code_image[HDR.OBJECT.SIZE,4] = iconv(pc, 'IL')
    pcb = pc.to_bytes(4, byteorder='little')
    for i in range(4):
        code_image[HDR_OBJECT_SIZE+i] = pcb[i]

    # Flags. 2 bytes
    # code_image[HDR.FLAGS,2] = iconv(header.flags, 'IS')
    hdr_flags = header_flags.to_bytes(2, byteorder='little')
    code_image[HDR_FLAGS] = hdr_flags[0]
    code_image[HDR_FLAGS+1] = hdr_flags[1]

    # Compile time. 2 bytes
    # 1005 Returns the combined date and time value as DATE() * 86400 + TIME().
    # date 31 December 1967 is day zero. 
    # time number of seconds since midnight.
    # code_image[HDR.COMPILE.TIME,4] = iconv(system(1005), 'IL')
    stdate = datetime.date(1967, 12, 31)
    today  = datetime.date.today()
    numdays = (today - stdate).days
#
    now = datetime.datetime.now()
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    seconds = (now - midnight).seconds

    c_date_time = numdays * 86400 + seconds
    dtb = c_date_time.to_bytes(4, byteorder='little')
    for i in range(4):
        code_image[HDR_COMPILE_TIME+i] = dtb[i]

 
    # Program name
    # code_image[HDR.PROGRAM.NAME, len(program.name)] = program.name
    n = len(program_name)
    if n > 0:
        for i in range(n):
            code_image[HDR_PROGRAM_NAME+i] = ord(program_name[i])
    
    return


def find_var():
    """ find_var()  -  Search symbol table for variable"""
    global symbol_var_no, symbol_common_offset, symbol_dim, symbol_common_index, symbol_mode

    if debugging == debug_detail:
        print('find_var, symbol_name: ' + symbol_name)
#
# Input:
#    SYMBOL_NAME = symbol to find
#    SYMBOL_MODE = What are we doing with this symbol?
# Output:
#    SYMBOL_VAR_NO         -ve if not found
#    SYMBOL_COMMON_OFFSET  -ve if local variable, else common offset
#    SYMBOL_DIM            Dimensions (0 if scalar, 1 or 2 for array,
#                                      -1 if array but dimensions not yet known)
#    SYMBOL_COMMON_INDEX   Index into COMMONS for common variable
# Note in BCOMP a dyn array named symbols is used to find the location of symbol.name's info
#  in the dyn array symbol.info.  In bbcmp we use dictionary for symbol_info, symbols is not necessary

# rem lsub stuff set by st_local
    if lsub_var_no >= 0:   # Try local symbols first
        if lsub_name+symbol_name in symbol_info:
            var_data = symbol_info[lsub_name+symbol_name]
            symbol_var_no = var_data[0]
            symbol_common_offset = var_data[1]
            symbol_dim = var_data[2]
            symbol_common_index = var_data[3]
            #if symbol.mode then symbol.refs<sympos,symbol.mode,symsv> = line.no(1)
            return
    
    if symbol_name in symbol_info:
        var_data = symbol_info[symbol_name]
        symbol_var_no = var_data[0]
        symbol_common_offset = var_data[1]
        symbol_dim = var_data[2]
        symbol_common_index = var_data[3]
        #if symbol.mode then symbol.refs<sympos,symbol.mode,symsv> = line.no(1)
    else:
        symbol_var_no = -1
        symbol_common_offset = -1
        symbol_dim = 0
        symbol_common_index = -1  

    symbol_mode = SYM_USE 

    if debugging == debug_detail:
        print('find_var exit, symbol_var_no: ' + str(symbol_var_no))

    return    

def make_var():
    """Add new symbol table entry for variable"""
    global symbol_var_no, symbol_info, var_count, symbol_table, symbol_mode

    if debugging == debug_detail:
        print('make_var, symbol_name: ' + symbol_name)  
# Input:
#    SYMBOL.NAME = symbol to add (must not exist)
#    SYMBOL.COMMON.OFFSET  -ve if local variable, else common offset
#    SYMBOL.DIM            Dimensions (0 if scalar, 1 or 2 for array
#                                      -1 if array dimensions nt yet known)
#    SYMBOL.MODE = What are we doing with this symbol?
# Output:
#    SYMBOL.VAR.NO         Local variable number
#    var_count  inc on new variable
# Note in BCOMP a dyn array named symbols is used to find the location of symbol.name's info
#  in the dyn array symbol.info.  In bbcmp we use dictionary for symbol_info, symbols is not necessary    
    if symbol_name in symbol_info:
        pass
    else:  
        symbol_var_no = var_count
        var_count += 1
        var_data = [symbol_var_no,symbol_common_offset,symbol_dim,symbol_common_index]
        symbol_info[symbol_name] = var_data
        symbol_table.append(symbol_name)
        # the following is used for cross ref checking and var defined but not used, we are not supporting
        # if symbol.mode then symbol.refs<sympos,symbol.mode,symsv> = line.no(1)

    symbol_mode = SYM_USE

    return

def get_arg_mat_dimensions():
    """ Process function/subroutine dimensioned argument"""

    get_token()  #* Skip bracket
    get_token()  #* Get first dimension
    if token != TKN_NUM:
        error('get_arg_mat_dimensions - Matrix dimensions required')

    if look_ahead_token == TKN_COMMA:
        get_token()  #* Skip comma
        get_token()  #* Get second dimension
        if token != TKN_NUM:
            error('get_arg_mat_dimensions - Matrix dimensions required')
        dim_dimensions = 2
    else:
        dim_dimensions = 1

 
    if look_ahead_token != TKN_RBR:
        error('get_arg_mat_dimensions - Right bracket not found where expected')

    get_token()

    return dim_dimensions 


def get_var_name():
    """Read variable name from source"""
    if (look_ahead_token != TKN_NAME) and (look_ahead_token != TKN_NAME_LBR):
        error('Variable name not found where expected')

    get_token()    

    return

#*****************************************************************************
# GET.NAME, GET.CALL.NAME  -  Get a name with possible prefix character.
# GET.NAME       Used for PROGRAM and COMMON names
# GET.CALL.NAME  Used for CALL and SUBROUTINE statements

def get_call_name():
    s = ""

    if look_ahead_token_string == '!' or look_ahead_token_string == '*':
        s = look_ahead_token_string()
        get_token()
        s = get_name_common_path(s)
        return s
    else:
        s = get_name()
        return s

def get_name():
    s = ""
    #if internal then
    if (look_ahead_token == TKN_DOLLAR) or (look_ahead_token == TKN_UNDERSCORE) or (look_ahead_token == TKN_OR):
        s = look_ahead_token_string
        get_token()
    s = get_name_common_path(s)
    return s   


def get_numeric_constant():
    """Returns numeric value"""
    global unary_minus

    unary_minus = False
    get_token()
    
    gnc_again = True     # fake goto
    #gnc.again:
    while gnc_again:
        gnc_again = False
        #begin case
        if token == TKN_NAME:

            if u_token_string in defined_tokens:
                # found
                t_type = defined_tokens[u_token_string][1]   # get type
                #begin case
                if t_type == is_string:  # String
                    strval = defined_tokens[u_token_string][0]
                    # can it be evaluated as a number?
                    numval = int_or_float(strval) # this either works or calls error(), no need to test

                elif t_type == is_number:   # Number token
                    numval = defined_tokens[u_token_string][0]

                else:
                    error('Numeric constant required')


        elif token == TKN_NUM:
            numval = int_or_float(token_string) # this either works or calls error(), no need to test
            if unary_minus:
                numval  = -numval
                unary_minus = False

        elif token ==  TKN_HEXNUM:
            numval = int(token_string,16)
            if unary_minus:
                numval = -numval
                unary_minus = False


        elif token == TKN_STRING:
            strval = token_string
            # can it be evaluated as a number?
            numval = int_or_float(strval) # this either works or calls error(), no need to test

        elif token == TKN_PLUS:    # Unary plus
            get_token()
            gnc_again = True

        elif token == TKN_MINUS:    # Unary minus
            unary_minus = not unary_minus
            get_token()
            gnc_again = True

        else:
            error('Numeric constant required')
 
    return numval 


def get_name_common_path(s):
    if look_ahead_token == TKN_STRING:
         error('Name not found where expected')

    get_token()

    # Because we need to allow for operator names used as call names
    # (e.g. !MATCHES), simply check that the token string contains only
    # characters that are permissible in SDBasic call names.

    #are all the characters in our name string valid (found in name_chars)?
    for c in u_token_string:
        if c not in name_chars:
            error('Name contain invalid character: ' + c)

    s = s + u_token_string    #* Call names are always uppercase

    return s

def get_label_name():
    """ Read a label name from the source stream """
    global label_name, token_string
    #begin case
    if look_ahead_token == TKN_LABEL:
        get_token()
        if token_string[0] == ":":
            token_string = token_string[1:]   # remove the ':'
        label_name = token_string

    elif (look_ahead_token == TKN_NAME) or (look_ahead_token == TKN_NUM)  or (look_ahead_token == TKN_FLOAT) or (look_ahead_token == TKN_NAME_LBR):
        get_token()
        label_name = token_string
        #  1.1-1 Was testing TKN.SEMICOLON.  This doesn't seem to make sense
        if look_ahead_token == TKN_COLON:
            get_token()
    else:
        error('Label name not found where expected')
    #end case

    return

def set_label():
    #
    # Route needs LOTS of testing
    #   I think I got the conversion correct ??
    # Search label table (label_dict) for this label_name
    #
    # So I think this is how this works (between emit.jump.addr: and set.label:)
    # Given program:
    # Program Example
    #  .
    #  .
    # 10 gosub (or someother jump ie goto) label1 at pc 100
    #  .
    #  .
    # 20 gosub label1  at pc 200
    #  .
    #  .
    # 30 gosub label1 at pc 300
    #  .
    #  .
    # 40 label1:  at pc 400
    #
    # on definition of label1 (ie label1:)
    #  if label not previously defined  (not in  label_dict /btree label.tree in BCOMP)
    #    set.label adds label definition to label_dict /btree label.tree with the 
    #    with data value = pc (program/object_code address of this reference)
    #  else (label previously defined via one of the jump emits ie emit.jump.addr)
    #    In this case the data value found in label_dict / label.btree  must be negative
    #    AND the abs value of the data value is the program/object_code address of the last reference
    #    reference to the label (ie 3 byte jump address of the last jump instr).
    #    At that address we find the program/object_code address of the next previous reference.
    #    This repeats until we find zero in the 3 byte jump address, indicating end of the "chain"
    #    This is the "chain" talked about in the comments below.
    #
    #    Example:
    #    at ln 10 we find label1 with pc = 100
    #    emit.jump.addr:
    #      label_dict{label1} = -100 (forward jump)
    #      At pc 100 place 3 byte jump address =  0 0 0 
    #
    #    at ln 20 we again have label1 with pc = 200
    #    emit.jump.addr:
    #      label_dict{label1} = -200 (forward jump)
    #      At pc 200 place 3 byte jump address =  100
    #    
    #    at ln 30 we again have label1 with pc = 300
    #    emit.jump.addr:
    #      label_dict{label1} = -300 (forward jump)
    #      At pc 300 place 3 byte jump address =  200
    #
    #    at ln 40 we define label1 with pc = 400
    #    set.label:
    #       prev_addr_in_chain = dict{label1} * -1
    #       label_dict{label1} = 400 (actaul address of label1) 
    #       Now we traverse the chain starting at location 300
    #         save 3 byte address found at 300, call it next_addr = 200
    #         replace with 3 byte address of label1 (400)
    #
    #         save 3 byte address found at 200, next_addr = 100
    #         replace with 3 byte address of label1 (400)
    #         
    #         save 3 byte address found at 100, next_addr = 000
    #         replace with 3 byte address of label1 (400)  
    #
    #         chain complete  next_addr = 000      
    #      

    global label_dict
    if label_name in label_dict:
        jump_addr = label_dict[label_name]
        if jump_addr < 0: #* It is a forward reference 
                          #  jump_addr * -1 gives us the starting location 
                          #  of this jump address to correct
            update_addr = -jump_addr
            label_dict[label_name] = pc     #  Correct the label table entry_

            if debugging == debug_jumps:
                print ('Resolving label: ' + label_name)
                print ('set_label, 24 bit jump address starting: code_image[' + str(update_addr) + ']')
                print (hex(code_image[update_addr]), hex(code_image[update_addr+1]), hex(code_image[update_addr+2]))

            # Go back and fill in the jump chain

            prev_addr_in_chain  = update_addr	
            while prev_addr_in_chain > 0:
                
                # save update_address
                # then save the "next" prev_addr in the chain
                update_addr = prev_addr_in_chain                                                # save address to update with label address
                prev_addr_bytes    = bytes(code_image[prev_addr_in_chain:prev_addr_in_chain+3]) # get next previous address, rem slice does not include ending value
                prev_addr_in_chain = int.from_bytes(prev_addr_bytes, "little")                  # convert 3 byte address to integer
                

                # now update with correct label address Not elegant  but straight forward
                label_addr = pc
                label_addr_bytes = label_addr.to_bytes(3, byteorder='little')
                code_image[update_addr]   = label_addr_bytes[0]
                code_image[update_addr+1] = label_addr_bytes[1]
                code_image[update_addr+2] = label_addr_bytes[2]



        else:            #* It is not a forward reference_ Flag an error_
            error('Duplicate label: ' + label_name)
            sys.exit('Abort')


    else:  # not there, add it    
        label_dict[label_name] = pc     # save current program counter location for this label

    return

def user_declared_function(func_name):
    """ process user declared function (DEFFUN)"""
    global func_stack, symbol_name, symbol_mode
    #ins func.index : @vm : 0 before func.stack<1>
    stk_val = [func_name,0]
    func_stack.insert(0,stk_val)
    
    get_token()           # Skip left bracket

    func_vals = functions[func_name]

    call_name = func_vals[0]
    if len(call_name) > 0:   # External function
        emit_direct_call_reference(call_name)

    emit_function_return_argument()  # Emit return argument

    # If this function has a key, emit it as the second argument

    if len(func_vals[2]) > 0:
        n = func_vals[2]
        if n.isdigit():  # number?
            n = int(n)
            emit_numeric_load(n)
        else:            # string
            emit_string_load(n)

   # Emit function arguments

    if look_ahead_token != TKN_RBR:
        #loop
        while True:
            if look_ahead_token == TKN_END:
                func_stack.pop(0)
                error('user_declared_function - Function argument not found where expected')

            #func.index = func.stack<1,1>
            #i = func.stack<1,2> + 1
            #func.stack<1,2> = i
            # looks like we are incrementing the number of arguments found in call
            i = func_stack[0][1] + 1
            func_stack[0][1] = i
            function_args = func_vals[1]
            # parse thru arg types, rem we are zero based, i is one off
            if function_args[i-1] == 'M': # Expect MAT
                if look_ahead_token_string.upper() != 'MAT':
                    error('user_declared_function - Argument type mismatch in function call')

                get_token()  # Skip MAT

                if look_ahead_token != TKN_NAME:
                    error('user_declared_function - Matrix name required')

                get_token()
                symbol_name = token_string
                symbol_mode = SYM_ARG
                find_var()

                if (symbol_var_no < 0) or (symbol_dim == 0):
                    error('user_declared_function -  Matrix name required')

                emit_var_load()

            else:   # Not a matrix argument
                if look_ahead_token_string.upper() == 'MAT':
                    error('user_declared_function -  Argument type mismatch in function call')


                symbol_mode = SYM_ARG
                exprf()


        #while look_ahead_token = TKN.COMMA
            if look_ahead_token != TKN_COMMA:
                break

            get_token()
        #repeat

        if look_ahead_token != TKN_RBR:
            error('user_declared_function - Right bracket not found where expected') 


    get_token()  # Skip bracket

   # Check argument count

    #func.index = func.stack<1,1>
    func_arg_count = func_stack[0][1]
    func_stack.pop(0)

    if not func_vals[3]:    # var args?? if so we skip this test
        function_args = func_vals[1]
        if len(function_args) != func_arg_count:
            error('user_declared_function - Argument count mismatch in function call')


    if len(func_vals[2]) > 0:  # allow for key
        func_arg_count += 1

    func_arg_count += 1  # Allow for return argument

    if len(func_vals[0]) > 0:  # External function (there is a call name)
        # Emit call
        emit(OP_CALL)
        emit(func_arg_count)
    else:                               # Internal function
        label_name = func_name
        emit_jump(OP_GOSUB)

    emit_function_result_load()

    return 

def remove_common(opcode):

   # Emit target variable reference

    simple_lvar_reference()
    if u_look_ahead_token_string != "FROM":
        error('remove_common - FROM not found where expected')
    
    get_token()  # Skip FROM token

    # Emit source variable reference

    simple_var_reference()

    if u_look_ahead_token_string != "SETTING":
        error('remove_common - SETTING not found where expected')

    get_token()   # Skip token

    # Emit delimiter or offset variable reference

    simple_lvar_reference()

    # Emit REMOVE or RMVTKN opcode

    emit_simple(opcode)

    # Store result substring

    emit_simple(OP_STOR)
    return

def find_common(opcode):
    """ find and findstr common"""

    exprf()                         # Emit search expression

    if u_look_ahead_token_string != "IN":
        error('Find_common - IN not found where expected')
        
    get_token()                    # Skip IN

    exprf()                         # Emit dynamic array reference

    if look_ahead_token == TKN_COMMA:
        get_token()                  # Skip comma
        exprf()                      # Emit occurrence expression
    else:
        emit_numeric_load(1)  # Default occurrence = 1

    if u_look_ahead_token_string != "SETTING":
        error('Find_common - SETTING not found where expected')

    get_token()                     # Skip SETTING

    simple_lvar_reference()         # Field variable


    if look_ahead_token == TKN_COMMA:
        get_token()
        simple_lvar_reference()      # Value variable

    else:
        emit_simple(OP_LD0)

    if look_ahead_token == TKN_COMMA:
      get_token()
      simple_lvar_reference()      # Subvalue variable
    else:
        emit_simple(OP_LD0)

    emit_simple(opcode)

    if_back_end()           # Join IF statement for THEN / ELSE

    return

def stop_common():

    if recursive:
        error('Stop - Statement/function not allowed in a recursive program')

   # The STOP statement may optionally have an associated text message.
   # Check the next token to see if we have a message.

    in_reserved = False

    if (look_ahead_token > 0) and (look_ahead_token != TKN_SEMICOLON):
        if look_ahead_token == TKN_NAME:  
            #find u_look_ahead_token_string in reserved.names setting n else null
            if u_look_ahead_token_string in reserved_names:
                in_reserved = True
             
        if not in_reserved:
            # Emit code to print the string by merging with PRINT opcode
            emit_print_list(OP_DSP)

    emit_simple(OP_STOP)

    return

def common_path(opcode):
    exprf()
    emit_simple(opcode)
    return

def comp():
    """ compile process """ 
    global end_source, lines, gbl_src_ln_cnt

    print('compile: ' + os.getcwd() + os.sep + 'pass2')

    pass2fn = os.getcwd() + os.sep + 'pass2'

    end_source = False


    emit_skeleton_header()    # * Emit skeleton object header 948
    end_source = False

    try:
        with open(pass2fn, encoding='ISO-8859-1') as f:
            lines = [line.rstrip() for line in f]
            print (str(len(lines)) + ' to  process')

    except Exception as excpt:
        print("file open error")
        print(excpt)
        sys.exit()
    
    
    gbl_src_ln_cnt = 0
    get_nxt_line()

    while not end_source:
        proc_line()


    comp_finish()

    print('comp finish')

    return


def comp_finish():
    global pc, start_pc, code_image, symbol_common_offset, symbol_name, symbol_var_no, symbol_mode, label_name
   # Emit a STOP or RETURN opcode to kill the program
   # If we are in a local subroutine, we do a stop as this really is a bug.
   # In other cases, SD has always emitted a return.     
    if (lsub_var_no >= 0):
        emit_simple(OP_STOP) 
    else:
        emit_simple(OP_RETURN)
#
#
# notes:
#  emit.symbol.table = False
#  emit.line.table   = False
#  emit.xref.tables  = False
   # Check for unclosed constructs

    if len(jump_stack) > 0:
        n = jump_stack[0][0]     # jump type for jump at top of stack


        if n == J_IF:
            error('Unterminated IF statement')

        elif n == J_LOOP:
            error('Unterminated LOOP statement')

        elif n == J_BACK_END:
            error('Unterminated ON ERROR, LOCKED, THEN or ELSE clause')

        elif n == J_CASE:
            error('Unterminated CASE statement')

        elif n == J_FOR:
            error('Unterminated FOR statement')

        elif n == J_IF_EXPR:
            error('Unterminated IF clause in expression')

        elif n == J_TXN:
            error('Unterminated TRANSACTION statement')



    # Check for undimensioned matrices

    for key in symbol_info:
        sym_values = symbol_info[key]
        if sym_values[2] < 0:
            error('Matrix ' + str(key) + '  is not referenced in a DIM statement')

    # Check for undefined labels
    for key in label_dict:
    #
        s = label_dict[key]
        if s < 0: # Undefined label
            if str(key)[0] != "_":
                error('Label ' + str(key) + ' referenced but not defined')
            #else:
                #if not(errors) then errors = 1 ;* Ensure error set



   # Emit prelude if program has:
   #   common block references
   #   direct calls

    new_start_pc = 0

   # ---------- Bind common blocks
   # The unnamed common has a name(!) of $.

    num_commons = len(commons)
    for c_idx in range(len(common_idx)):
        key = common_idx[c_idx]
  
        val_list = commons[key]

        if val_list[6]:  # is this a VARSET arg?
            continue  # VARSET argument
        if new_start_pc == 0:
            new_start_pc = pc

        common_name = str(key)
        if common_name[-1] == ':':
            continue   # Not really a common at all...
                       # ...it's a local variable pool

        symbol_var_no = val_list[0]

        # Emit COMMON opcode

        emit(OP_COMMON)

        
        emit_multibyte_value(symbol_var_no,2) # Local variable number
        emit_multibyte_value(val_list[1],2)   # size

        opcode = len(common_name) # Block name length
        # Do we need to set "uninitialised common" flag?
        if val_list[7]:
            opcode = opcode | 0x80
        emit(opcode)

        n = len(common_name)
        if n > 0:
            for i in range(n):
                code_image[pc+i] = ord(common_name[i])
               
            pc += n

        # Emit skip address for jump round dimcoms

        label_name = '_COM' + str(c_idx + 1)
        emit_jump_addr()

        # Dimension common matrices

        num_com_var = len(val_list[2]) # num of var names in common block
        #for common.var.idx = 1 to num.com.var
        for common_var_idx in range(num_com_var):
            #if commons<5, common.index, common.var.idx> > 0 then
            if val_list[3][common_var_idx] > 0:     # matx rows?
                symbol_name = val_list[2][common_var_idx]
                symbol_mode = SYM_CHK
                find_var()
                emit_var_load()

                # n = commons<5, common.index, common.var.idx> + 0  ;* Rows
                n = val_list[3][common_var_idx]
                emit_numeric_load(n)

                #n = commons<6, common.index, common.var.idx> + 0  ;* Cols
                n = val_list[4][common_var_idx]
                emit_numeric_load(n)

                emit_simple(OP_DIMCOM)

        # Emit skip label for BINDCOM

        label_name = '_COM' + str(c_idx + 1)
        set_label()


    # ---------- Set up links for direct calls

    if len(direct_calls):
        # Generate local variable initialization for direct calls
        # For each direct called subroutine, generate 
        #           LDLCL  var
        #           LDSTR  name
        #           STOR

        if new_start_pc == 0:
            new_start_pc = pc

        symbol_common_offset = -1      #* flag to emit_var_load() Local variables

        #loop
        for i in range(len(direct_calls)):
            opcode_str    = direct_calls[i]
            symbol_var_no = direct_call_vars[opcode_str]
            

            emit_var_load()

            emit_string_load(opcode_str)

            if clear_used:
                opcode = OP_STORSYS
            else:
                opcode = OP_STOR
            emit_simple(opcode)
  

   
    if new_start_pc > 0:
        # Generate a jump to the original entry point of the program and then
        # replace the header start address by the address of the code just
        # emitted.

        emit(OP_JMP)
        emit_multibyte_value(start_pc,3)

        start_pc = new_start_pc
   

    # Check for unset / unreferenced variables
    #  not supporting this error checking!

    #   n = dcount(symbols, @fm)
#   for i = 1 to n
#      if symbol.info<i,2> >= 0 then continue        ;* Ignore common
#      if symbol.refs<i,SYM.ARG> # '' then continue  ;* Used as argument
#      s = symbols<i>
#      c = s[1,1]
#      if c = '_' then continue    ;* Ignore internal symbols
#      if c = '~' then continue    ;* Ignore internal symbols
#
#      if symbol.refs<i,SYM.SET> = '' then
#         if symbol.info<i,3> and symbol.refs<i,SYM.USE> = '' then
#            err.msg = sysmsg(2988, s) ;* Matrix %1 is not referenced
#            gosub warning
#         end else
#            err.msg = sysmsg(2825, s) ;* %1 is not assigned a value
#            gosub warning
#         end
#      end else if symbol.refs<i,SYM.USE> = '' then
#         if internal or bittest(mode, M.TRAP.UNUSED) then
#            err.msg = sysmsg(2826, s) ;* %1 is assigned a value but never used
#            gosub warning
#         end
#      end
#   next i

    # Check that all internal subroutines with arguments have been
    # found as local subroutines/functions
    # not doing this

    #n = dcount(int.subs, @fm)
    #for i in range(len(int_subs)):
    #    if int_sub_args[i] != None and  not int_sub_is_lsub[i]:
    #        err.msg = sysmsg(3427, int.subs<i>) ;* Arguments supplied in GOSUB to internal subroutine %1
    #        gosub error
    #    end
    #next i

  



    # Emit the symbol table with value marks between items
    # nameVMnameVMname...FMnVMnameSMname...FMnVMnameSMname...NULL
    # <--local vars-->   <----Common--->   <----Common--->   End
    # rem not doing this !!!
#	  if emit.symbol.table then
#         if symbol.table # "" then
#            symbol.table.offset = pc
#
#            loop
#               remove s from symbol.table setting i
#               s := @vm
#
#               if pc + len(s) >= code.size then
#                  code.size += len(s)
#                  code.image := str(char(0), len(s))
#               end
#
#               code.image[pc+1,len(s)] = s
#               pc += len(s)
#            while i
#            repeat
#
#            setrem 0 on symbol.table
#         end
#
#         * Emit information for common blocks
#         * @fm localvarno @vm name @sm name @sm name...
#
#         common.index = 1
#         loop
#            n = commons<2,common.index>  ;* Local variable number
#         while len(n)
#            opcode.string = @fm : n : @vm : commons<4,common.index>
#
#            if pc + len(opcode.string) >= code.size then
#               code.size += len(opcode.string)
#               code.image := str(char(0), len(opcode.string))
#            end
#
#            code.image[pc+1, len(opcode.string)] = opcode.string
#            pc += len(opcode.string)
#            common.index += 1
#         repeat
#
#         * Emit a zero byte to terminate the table
#
#         code.image[pc+1,1] = char(0)
#         pc += 1
#      end
    # Go back and fill in the object header

    emit_final_header()

    return

def main():

    global gtlog, program_name
    # command line: bbcmp.py sfp, binfp
    # sfp - source file path including file name
    # binfn - pcode object file path including name
    print(sys.argv[1:])
    sdsys = sys.argv[1]
    sfp = os.path.join(sdsys, sys.argv[2])
    binfn = os.path.join(sdsys, sys.argv[3])

    init_stuff()
    

    program_name = os.path.basename(sfp)

    #   pass 1
    pss_src = pass1(sfp)

    # save each pass for use by the next
    rsltfn = os.getcwd() + os.sep + 'pass1'
    wpass(rsltfn,pss_src)

    # pass 2
    pss_src = pass2(rsltfn)

    # save each pass for use by the next
    pass2fn = os.getcwd() + os.sep + 'pass2'
    wpass(pass2fn,pss_src)

    # print('token dictionary size: ' + str(len(defined_tokens)))   # number of $define tokens saved in dictionary

    gtlog = []
    
    comp()

    print('saving code_image to: ' + binfn)
    # cast Bytearray code_image to bytes
    immutable_bytes = bytes(code_image[:pc])   # truncate code_image to length actaully populated
 
    # Write bytes to file
    with open(binfn, "wb") as binary_file:
        binary_file.write(immutable_bytes)

    if len(catalog_name) > 0:
        print('saving code_image to gcat as: ' + catalog_name)
        gcatpn = "gcat" + os.sep + catalog_name
        gcatfn = os.path.join(sdsys, gcatpn)
        with open(gcatfn, "wb") as binary_file:
            binary_file.write(immutable_bytes)
 

    if debugging == debug_log:
        sfn=os.getcwd() + os.sep + 'get_line_db.txt'
        print('writing gtlog to ' + sfn)
        with open(sfn, 'w')  as wf:
            for ln in  gtlog:
                    wf.write(f"{ln.rstrip()}\n")


    print('complete')
    return 0



# __name__ 
if __name__=="__main__": 
    main()