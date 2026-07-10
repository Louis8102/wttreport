# smartload V0.2.1 Notes

`smartload` is an SSC-style Stata command by Hao Ma.  It lets users load a data file by file name without remembering the folder path.

Version 0.2.1 uses a pure Stata indexing system.  It does not call `shell`, PowerShell, Everything, Windows Search, or any non-Stata search tool.

## Installation

V0.2.0 is SSC-style, but it is not yet official SSC unless submitted to and accepted by SSC.

Install from GitHub:

```stata
net install smartload, from("https://raw.githubusercontent.com/Louis8102/smartload/main") replace
help smartload
```

No SSC dependency is required.

## Basic Use

First build or refresh the file index:

```stata
smartload, refresh
```

Then load files by name:

```stata
smartload Indicator.dta, clear
smartload city.sas7bdat, clear
smartload survey.sav, clear
smartload workbook.xlsx, firstrow clear
smartload mydata.csv, clear
```

If `Indicator.dta` exists on both `C:` and `F:` or in multiple folders, `smartload` lists all indexed matches on screen:

```text
Found multiple indexed files named Indicator.dta:
1. C:/some/folder/Indicator.dta
2. F:/another/folder/Indicator.dta
```

In interactive Stata, type the Arabic numeral for the file to import.  In batch mode, use `choice(#)`:

```stata
smartload Indicator.dta, choice(2) clear
```

## Refresh Scope

By default, `smartload, refresh` indexes available drive roots from `C:` through `Z:` using Stata code only.

For faster testing or a restricted index:

```stata
smartload, refresh roots("C:\ANOVA;F:\Project") replace
smartload, refresh drives(C F) replace
```

The index is stored as `smartload_index.dta` in the user PERSONAL ado directory.

## Supported Imports

V0.2.1 indexes supported Stata-readable files and recognized data/document container formats.  It imports only formats Stata can load reliably:

- `.dta` via `use`
- `.xlsx` and `.xls` via `import excel`
- `.csv`, `.txt`, `.tsv`, and text-like `.dat` via `import delimited`
- `.sav` and `.por` via `import spss`
- `.sas7bdat` via `import sas`
- `.xpt` via `import sasxport`

The index records all files it can see under indexed roots, including files in hidden folders.  Loading is implemented for the supported Stata-readable formats above, not only `.dta`.

PDF, Word, PowerPoint, R, Python, GIS, database, and archive files are detected but not falsely imported.

## Files

Recommended GitHub layout:

```text
smartload/
  README.md
  LICENSE
  smartload.ado
  smartload.sthlp
  smartload.pkg
  stata.toc
  test_smartload.do
  example_data/
```

`stata.toc` is the Stata package-directory index used by `net install`.  `smartload.pkg` is the install manifest.

## Version

- Version: 0.2.1
- Date: 2026-07-09
- Author: Hao Ma
- License: MIT
- Tested with: StataNow/MP 19.5
