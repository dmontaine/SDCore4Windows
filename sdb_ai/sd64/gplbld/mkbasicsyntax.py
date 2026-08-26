#
# mkbasicsyntax.py - build micro's SD BASIC syntax file FROM BCOMP.
#
#   python mkbasicsyntax.py <gpl.bp/BCOMP> <out.yaml>
#
# THE WORD LISTS ARE NOT TYPED OUT.  BCOMP is the compiler: its own tables say
# what a statement is, what a reserved word is and what an intrinsic function
# is.  Reading them means the highlighting cannot drift from the language, and
# it means nobody has to proof-read 400 names.
#
# It prints what it extracted and refuses a list that came back empty - a
# syntax file built from nothing would highlight nothing and look like a
# working file.
#
import re
import sys

BCOMP = sys.argv[1]
OUT = sys.argv[2]

with open(BCOMP, 'r', encoding='latin-1', newline='') as f:
    src = f.read()

# The tables are built as   name = "A" : @fm : "B"   or   name<-1> = "C"
# across many lines.  Collect every quoted word on a line that assigns to the
# table, which is exactly what the compiler will later split on @fm.
TABLES = {
    'statements': ['statements'],
    'non.debug.statements': ['non.debug.statements'],
    'restricted.statements': ['restricted.statements'],
    'reserved.names': ['reserved.names'],
    'intrinsics': ['intrinsics'],
}

WORD = re.compile(r'"([A-Z][A-Z0-9.$]*)"')

collected = {}
for label, names in TABLES.items():
    words = set()
    for line in src.split('\n'):
        stripped = line.strip()
        if stripped.startswith('*'):
            continue
        for n in names:
            # "name = ", "name := ", "name<-1> = ", "name<1,-1> = "
            if re.match(re.escape(n) + r'\s*(<[^>]*>)?\s*:?=', stripped):
                words.update(WORD.findall(stripped))
    collected[label] = sorted(words)
    print('  %-24s %d word(s)' % (label, len(words)))
    if not words:
        sys.exit('mkbasicsyntax: %s came back empty - refusing to write' % label)

statements = sorted(set(collected['statements']) |
                    set(collected['non.debug.statements']) |
                    set(collected['restricted.statements']))
reserved = collected['reserved.names']
intrinsics = collected['intrinsics']

# A name containing "." or "$" must have its dot escaped, and \b does not work
# where a word ends in "$" - so the alternation is sorted LONGEST FIRST and
# anchored by hand.
def alt(words):
    esc = [re.escape(w) for w in sorted(words, key=lambda w: (-len(w), w))]
    joined = '|'.join(esc)
    # ***AND THEN ESCAPED AGAIN FOR YAML.*** These go inside a double-quoted
    # YAML scalar, where "\." is not a legal escape at all - the file would
    # fail to parse, and micro would report no syntax rather than a bad one.
    # micro's own c.yaml writes "\\." for the same reason.
    return joined.replace('\\', '\\\\')


YAML = '''filetype: sdbasic

# SD BASIC, for the EDIT and MICRO verbs of SD Core for Windows.
#
# GENERATED FROM THE COMPILER'S OWN TABLES by gplbld/mkbasicsyntax.py, which
# reads sdsys/gpl.bp/BCOMP.  Do not hand-edit: regenerate it, or the
# highlighting and the language drift apart.  Counts at generation time are in
# the comment above each rule.
#
# DETECTION IS ON THE WORKING COPY'S NAME, not on the record's.  gpl.bp/EDIT
# writes a BP record to $hold as "<record>.editing.sdbasic" precisely so that
# this can match; a record edited from any other file gets ".editing" and no
# highlighting, which is the honest answer for a VOC or data record.

detect:
    filename: "\\\\.sdbasic$"

rules:
    # Statements: BCOMP's "statements", "non.debug.statements" and
    # "restricted.statements" tables - @COUNT_STATEMENTS@ names.
    - statement: "(?i)\\\\b(@STATEMENTS@)\\\\b"

    # Reserved words inside statements - @COUNT_RESERVED@ names.
    - special: "(?i)\\\\b(@RESERVED@)\\\\b"

    # Intrinsic functions - @COUNT_INTRINSICS@ names.
    - identifier: "(?i)\\\\b(@INTRINSICS@)\\\\b"

    # @VARIABLES, @FM and the rest.  One rule: the compiler treats them as
    # names and so does this.
    - constant: "@[A-Za-z][A-Za-z0-9.]*"

    # $INCLUDE, $CATALOG, $INTERNAL - the compiler directives.
    - preproc: "^\\\\s*\\\\$[A-Za-z][A-Za-z0-9.]*"

    # Labels: a name at the start of a line followed by a colon.
    - identifier.class: "^\\\\s*[A-Za-z][A-Za-z0-9.$]*:"

    - constant.number: "\\\\b[0-9]+(\\\\.[0-9]+)?\\\\b"

    - symbol.operator: "([:=<>!+*/-]|#)"

    - constant.string:
        start: "\\""
        end: "\\""
        skip: "\\\\\\\\."

    - constant.string:
        start: "'"
        end: "'"
        skip: "\\\\\\\\."

    # A comment is a "*" or "!" in column 1, or ";*" anywhere after code.
    # REM and * are the language's two forms and both are here.
    - comment:
        start: "^\\\\s*(\\\\*|!)"
        end: "$"
        rules:
            - todo: "(TODO|FIXME|XXX):?"

    - comment:
        start: ";\\\\s*\\\\*"
        end: "$"
        rules:
            - todo: "(TODO|FIXME|XXX):?"

    - comment:
        start: "(?i)^\\\\s*REM\\\\b"
        end: "$"
        rules:
            - todo: "(TODO|FIXME|XXX):?"
'''

out = (YAML
       .replace('@STATEMENTS@', alt(statements))
       .replace('@RESERVED@', alt(reserved))
       .replace('@INTRINSICS@', alt(intrinsics))
       .replace('@COUNT_STATEMENTS@', str(len(statements)))
       .replace('@COUNT_RESERVED@', str(len(reserved)))
       .replace('@COUNT_INTRINSICS@', str(len(intrinsics))))

with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)

print('mkbasicsyntax: %s' % OUT)
print('mkbasicsyntax: %d statement(s), %d reserved word(s), %d intrinsic(s), %d bytes'
      % (len(statements), len(reserved), len(intrinsics), len(out)))
