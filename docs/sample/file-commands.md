Title: File commands
Subtitle: Creating, emptying and deleting SD files.

Three commands cover the life of an SD file. `create.file` makes one, together
with the VOC record that names it. `clear.file` empties a file but leaves it in
place. `delete.file` removes it and tidies away the VOC record behind it.

SD folds case, so a command may be typed in either case. Commands and keywords
are shown here in lower case. Braces mark the optional parts of a command; in
the tables below, *italics* mark something you supply and **bold** marks a word
typed as it stands.

## create.file

`create.file` creates an SD file.

### Format

```
create.file {portion} file.name {,subfile} {type} {configuration}
            {using dict other.file} {no.query}
```

where

| Argument | Meaning |
|---|---|
| *portion* | identifies the part of the file to create. This may be **data** to create just the data portion, **dict** to create just the dictionary portion, or omitted to create both. |
| *file.name* | is the name of the VOC record to be created to refer to the file. The operating system name used for the data file is the same as *file.name*. The directory holding the dictionary component of a file takes a `.dic` suffix. |
| *subfile* | is the name of the subfile to be created in a multifile. |
| *type* | specifies the file type as **directory** or **dynamic**. If omitted, a dynamic file is created by default. Dictionaries are always created as dynamic files regardless of any *type* argument. |

### Configuration options

The *configuration* options are available only when creating a dynamic file,
and specify the file's configuration and location.

| Option | Effect |
|---|---|
| **pathname** *path* | names an existing operating system directory under which the file is to be created. |
| **minimum.modulus** *n* | sets the minimum modulus for the file. Any positive non-zero value may be used. The default is 1. |
| **group.size** *size* | sets the group size as a multiple of 1024 bytes. This must be in the range 1 to 8. If omitted, the default group size is taken from the `GRPSIZE` configuration parameter. |
| **large.record** *bytes* | sets the large record size in bytes. The default is 80% of the group size. |
| **split.load** *pct* | sets the split load factor for the file. The default is 80%. |
| **merge.load** *pct* | sets the merge load factor for the file. The default is 50%. |
| **version** *vno* | allows creation of files with internal formats compatible with older releases of SD. |
| **no.case** | creates a file whose record ids are treated as case insensitive. SD writes records preserving the casing given by whatever performs the write, and reads locate records regardless of casing. |
| **no.resize** | creates the file with resizing disabled. See `configure.file` for more information. |

> **The directory named by `pathname` must already exist.** `create.file` does
> not create it, and stops with *Directory path name does not exist* if it is
> missing. On Windows this is an ordinary path — `d:\apps`, or a UNC path — and
> the file is created as a directory *underneath* it.

The **using dict** clause creates a data file that shares the dictionary of an
existing file. Field 3 of the VOC entry for *other.file* is copied into field 3
of the new entry rather than a new dictionary being set up.

The **no.query** option suppresses any confirmation prompts associated with the
requested action.

### Multifiles

A multifile is a collection of data files that share a common dictionary.
Commands and application software refer to an individual subfile within the
multifile by a name made of the file name and the subfile name, separated by a
comma.

When creating a multifile element, the default action of `create.file` is to
create a subdirectory named *file.name* under the account, and to create the
element within that directory as *subfile*. An alternative location can be
given with **pathname**.

`create.file` can convert an existing simple file into a multifile. The
existing data becomes a subfile with the same name as the file.

### Examples

```
create.file stock minimum.modulus 150 group.size 4
```

Creates a dynamic file named `stock` with a minimum modulus of 150 and a group
size of 4.

```
create.file data programs directory pathname d:\apps
```

Creates the data portion of a directory file named `programs`. Its full path is
`d:\apps\programs` rather than the default location under the account.

```
create.file accounts,north
```

Creates a multifile component named `north` within the `accounts` file.

### See also

[`clear.file`](#clearfile), [`delete.file`](#deletefile), `configure.file`,
`listf`, `listfl`, `listfr`.

## clear.file

`clear.file` deletes all records from a file, leaving the file itself in place.

### Format

```
clear.file {data | dict} file.name
```

If neither **data** nor **dict** is given, only the data portion of the file is
cleared. If **dict** is given, only the dictionary portion is cleared.

In the case of a dynamic file, the file returns to its minimum modulus and all
overflow space is released.

### See also

[`create.file`](#createfile), [`delete.file`](#deletefile).

## delete.file

`delete.file` deletes one or both portions of a file.

### Format

```
delete.file {data | dict} file.name {,subfile} {options}
```

where

| Argument | Meaning |
|---|---|
| *file.name* | is the VOC name of the file to be deleted. The **data** prefix deletes only the data portion; the **dict** prefix deletes only the dictionary portion. |
| *subfile* | is the subfile to be deleted from a multifile. If it is omitted and *file.name* refers to a multifile, the entire multifile is deleted. Naming a subfile implies **data**, leaving the dictionary in place. |
| **force** | deletes files with non-default names. |
| **no.query** | suppresses the confirmation prompt when using a select list. |

If no file name is given and the default select list is active, `delete.file`
uses that list to determine the files to delete.

Deleting the data portion of a file deletes the associated operating system
directory and clears field 2 of the VOC record describing the file. Deleting
the dictionary portion deletes the directory representing the dictionary and
clears field 3.

If the deletion leaves fields 2 and 3 of the VOC record both null, the VOC
record is deleted as well. So deleting both portions of a file, the data
portion of a file that had no dictionary, or the dictionary portion of a file
that had no data portion, all remove the VOC record too.

> **When the name on disk is not the default name, `delete.file` asks first.**
> The default names are *file.name* for the data portion and *file.name*`.dic`
> for the dictionary portion. Where the VOC entry records anything else, the
> command prompts for confirmation unless **force** is given. This traps the
> accidental deletion of files that are remote to the account, or for which
> *file.name* is not the primary VOC reference.

### Example

```
delete.file dict inventory
```

Deletes the dictionary part of the file named `inventory`.

### See also

[`create.file`](#createfile), [`clear.file`](#clearfile), `listf`, `listfl`,
`listfr`.
