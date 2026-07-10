*! smartload 0.2.1 09jul2026 Hao Ma
program define smartload, rclass
    version 19.5
    syntax [anything(name=fname id="file name")] [, REFRESH ROOTS(string) ///
        DRIVES(string) CHOICE(integer -1) CLEAR SHEET(string) FIRSTROW ///
        ENCODING(string) TABLE(string) OBJECT(string) LAYER(string) ///
        MEMBER(string) SLIDE(integer -1) TABLEINDEX(integer -1) ///
        DOCTABLE(integer -1) PDFTABLE(integer -1) PPTTABLE(integer -1) ///
        CLOUD(string) CLOUDROOT(string) OCR LOG REPLACE]

    smartload__indexpath
    loc indexfile `"`r(indexfile)'"'

    if "`refresh'" != "" {
        smartload__refresh, indexfile(`"`indexfile'"') roots(`"`roots'"') drives(`"`drives'"') replace(`"`replace'"')
        return local indexfile `"`indexfile'"'
        exit
    }

    loc filename `"`fname'"'
    local filename = subinstr(`"`filename'"', char(34), "", .)
    mata: st_local("filename", pathbasename(st_local("filename")))
    if `"`filename'"' == "" {
        di as err "Please specify a file name, or run {cmd:smartload, refresh} to build the index."
        exit 198
    }

    loc cmdline `"smartload `filename'"'
    loc logrequested = "`log'" != ""
    loc logfile "smartload_log.txt"
    tempname lh
    if `logrequested' {
        if "`replace'" != "" file open `lh' using "`logfile'", write text replace
        else file open `lh' using "`logfile'", write text append
        file write `lh' "Command: `cmdline'" _n
        file write `lh' "Date/time: `c(current_date)' `c(current_time)'" _n
    }

    cap confirm file `"`indexfile'"'
    if _rc {
        di as err "smartload index was not found."
        di as txt "Run this once to build a pure Stata file index:"
        di as txt "{cmd:. smartload, refresh}"
        if `logrequested' {
            file write `lh' "Result: failure - index not found" _n _n
            file close `lh'
        }
        exit 601
    }

    preserve
    qui use `"`indexfile'"', clear
    cap confirm var filename
    if _rc {
        restore
        di as err "smartload index is invalid. Rebuild it with {cmd:smartload, refresh}."
        exit 459
    }

    qui keep if lower(filename) == lower(`"`filename'"')

    if `"`roots'"' != "" {
        gen str2045 __rootfilter = ""
        loc rest `"`roots'"'
        while `"`rest'"' != "" {
            loc semi = strpos(`"`rest'"', ";")
            if `semi' > 0 {
                loc root = substr(`"`rest'"', 1, `semi' - 1)
                loc rest = substr(`"`rest'"', `semi' + 1, strlen(`"`rest'"'))
            }
            else {
                loc root `"`rest'"'
                loc rest ""
            }
            loc root = strtrim(`"`root'"')
            if `"`root'"' == "" continue
            loc root = subinstr(`"`root'"', char(92), "/", .)
            replace __rootfilter = "1" if strpos(lower(filepath), lower(`"`root'"')) == 1
        }
        qui keep if __rootfilter == "1"
        drop __rootfilter
    }

    qui count
    loc nmatch = r(N)
    if `nmatch' == 0 {
        restore
        di as err "No indexed file named `filename' was found."
        di as txt "If the file was added or moved recently, run: {cmd:smartload, refresh}"
        if `logrequested' {
            file write `lh' "Result: failure - no indexed match" _n _n
            file close `lh'
        }
        exit 601
    }
    qui duplicates drop filepath, force
    qui count
    loc nmatch = r(N)

    if `nmatch' > 1 {
        di as err "Found multiple indexed files named `filename':"
        forvalues i = 1/`nmatch' {
            loc p = filepath[`i']
            di as txt "`i'. `p'"
        }

        if `choice' >= 1 {
            loc selected = `choice'
        }
        else {
            if c(mode) == "batch" {
                di as err "File name is not unique. Batch mode cannot prompt for a choice."
                di as txt "Use {cmd:choice(#)} or run interactively and choose a number."
                if `logrequested' {
                    file write `lh' "Result: failure - multiple matches in batch mode" _n _n
                    file close `lh'
                }
                restore
                exit 459
            }
            di as txt "Type the number of the file to import, then press Enter."
            cap macro drop SMARTLOAD_CHOICE
            display _request(SMARTLOAD_CHOICE)
            loc selected = strtrim("$SMARTLOAD_CHOICE")
        }

        cap confirm integer number `selected'
        if _rc | real("`selected'") < 1 | real("`selected'") > `nmatch' {
            di as err "Invalid selection. No file was imported."
            if `logrequested' {
                file write `lh' "Result: failure - invalid multiple-match selection" _n _n
                file close `lh'
            }
            restore
            exit 198
        }
        qui keep in `selected'
    }

    loc filepath = filepath[1]
    loc storage = storage[1]
    restore
    loc loadpath = subinstr(`"`filepath'"', char(92), "/", .)

    mata: st_local("ext", strlower(pathsuffix(st_local("filepath"))))
    loc ext : subinstr loc ext "." "", all
    loc sourcekind "indexed"
    loc importcmd ""

    if `logrequested' {
        file write `lh' "Matched file: `filepath'" _n
        file write `lh' "Storage location: `storage'" _n
        file write `lh' "Detected extension: `ext'" _n
    }

    if "`ext'" == "dta" {
        if "`clear'" != "" use `"`loadpath'"', clear
        else use `"`loadpath'"'
        loc importcmd "use"
    }
    else if inlist("`ext'", "xlsx", "xls") {
        loc opts ""
        if "`firstrow'" != "" loc opts "`opts' firstrow"
        if `"`sheet'"' != "" loc opts `"`opts' sheet(`"`sheet'"')"'
        if "`clear'" != "" loc opts "`opts' clear"
        if `"`opts'"' != "" import excel `"`loadpath'"', `opts'
        else import excel `"`loadpath'"'
        loc importcmd "import excel"
    }
    else if inlist("`ext'", "csv", "txt") {
        loc opts ""
        if `"`encoding'"' != "" loc opts `"`opts' encoding(`"`encoding'"')"'
        if "`clear'" != "" loc opts "`opts' clear"
        if `"`opts'"' != "" import delimited `"`loadpath'"', `opts'
        else import delimited `"`loadpath'"'
        loc importcmd "import delimited"
    }
    else if "`ext'" == "tsv" {
        loc opts "delimiters(tab)"
        if `"`encoding'"' != "" loc opts `"`opts' encoding(`"`encoding'"')"'
        if "`clear'" != "" loc opts "`opts' clear"
        import delimited `"`loadpath'"', `opts'
        loc importcmd "import delimited"
    }
    else if "`ext'" == "dat" {
        loc opts ""
        if "`clear'" != "" loc opts "clear"
        if "`opts'" != "" cap noi import delimited `"`loadpath'"', `opts'
        else cap noi import delimited `"`loadpath'"'
        if _rc {
            di as err "Detected .dat file, but it could not be imported as a delimited rectangular text dataset."
            di as err ".dat is a generic extension and may require user-specified parsing rules."
            return local filepath `"`filepath'"'
            return local filename `"`filename'"'
            return local extension "`ext'"
            return local status "detected_not_imported"
            if `logrequested' {
                file write `lh' "Result: detected_not_imported - .dat import failed" _n _n
                file close `lh'
            }
            exit 459
        }
        loc importcmd "import delimited"
    }
    else if inlist("`ext'", "sav", "por") {
        if "`clear'" != "" import spss using "`loadpath'", clear
        else import spss using "`loadpath'"
        loc importcmd "import spss"
    }
    else if "`ext'" == "sas7bdat" {
        if "`clear'" != "" import sas using "`loadpath'", clear
        else import sas using "`loadpath'"
        loc importcmd "import sas"
    }
    else if "`ext'" == "xpt" {
        if "`clear'" != "" import sasxport using "`loadpath'", clear
        else import sasxport using "`loadpath'"
        loc importcmd "import sasxport"
    }
    else {
        smartload__detected `"`filepath'"' "`filename'" "`ext'" "`lh'" "`logrequested'" "`ocr'"
        return local filepath `"`filepath'"'
        return local filename `"`filename'"'
        return local extension "`ext'"
        return local status "detected_not_imported"
        exit 0
    }

    return local filepath `"`filepath'"'
    return local filename `"`filename'"'
    return local extension "`ext'"
    return local importcmd "`importcmd'"
    return local storage "`storage'"
    return local sourcekind "`sourcekind'"
    return local indexfile `"`indexfile'"'
    qui ds
    loc k : word count `r(varlist)'
    loc N = _N
    return scalar N = `N'
    return scalar k = `k'

    di as res "Successfully imported file:"
    di as txt `"`filepath'"'
    loc typename "Recognized data file"
    if "`ext'" == "dta" loc typename "Stata dataset"
    else if inlist("`ext'", "xlsx", "xls") loc typename "Excel workbook"
    else if inlist("`ext'", "csv", "txt", "tsv", "dat") loc typename "Delimited text candidate"
    else if inlist("`ext'", "sav", "por") loc typename "SPSS data file"
    else if inlist("`ext'", "sas7bdat", "xpt") loc typename "SAS data file"
    di as txt "Detected type: `typename'"
    di as txt "Command used: `importcmd'"
    di as txt "Storage location: `storage'"
    di as txt "Observations: " as res `N'
    di as txt "Variables: " as res `k'

    if `logrequested' {
        file write `lh' "Import command used: `importcmd'" _n
        file write `lh' "Result: success" _n
        file write `lh' "Observations: `N'" _n
        file write `lh' "Variables: `k'" _n _n
        file close `lh'
    }
end

program define smartload__indexpath, rclass
    version 19.5
    loc base `"`c(sysdir_personal)'"'
    if `"`base'"' == "" loc base `"`c(tmpdir)'"'
    cap mkdir `"`base'"'
    mata: st_local("idx", pathjoin(st_local("base"), "smartload_index.dta"))
    return local indexfile `"`idx'"'
end

program define smartload__refresh, rclass
    version 19.5
    syntax , INDEXFILE(string) [ROOTS(string) DRIVES(string) REPLACE(string)]

    tempfile newindex
    tempname posth
    postfile `posth' str2045 filepath str255 filename str2045 dirname str32 ext str20 storage using `"`newindex'"', replace

    loc scanned 0
    if `"`roots'"' != "" {
        smartload__scanroots, roots(`"`roots'"') post(`posth') storage(local)
        loc scanned = `scanned' + r(nroots)
    }
    else {
        loc drives_l = lower(strtrim(`"`drives'"'))
        if `"`drives_l'"' == "" | `"`drives_l'"' == "all" {
            loc drvlist ""
            forvalues i = 67/90 {
                loc d = char(`i')
                loc drvlist "`drvlist' `d'"
            }
        }
        else loc drvlist `"`drives'"'

        foreach d of local drvlist {
            loc d = upper(strtrim("`d'"))
            local d : subinstr local d ":" "", all
            if length("`d'") != 1 continue
            loc root "`d':/"
            mata: st_local("direx", strofreal(direxists(st_local("root"))))
            if "`direx'" != "1" continue
            di as txt "Indexing `root'"
            smartload__scanroot, root(`"`root'"') post(`posth') storage(local)
            loc ++scanned
        }
    }

    postclose `posth'
    preserve
    qui use `"`newindex'"', clear
    qui duplicates drop filepath, force
    qui compress
    save `"`indexfile'"', replace
    qui count
    loc n = r(N)
    restore

    di as res "smartload index refreshed."
    di as txt "Index file: `indexfile'"
    di as txt "Files indexed: " as res `n'
    return local indexfile `"`indexfile'"'
    return scalar N = `n'
end

program define smartload__scanroots, rclass
    version 19.5
    syntax , ROOTS(string) POST(string) STORAGE(string)
    loc rest `"`roots'"'
    loc nroots 0
    while `"`rest'"' != "" {
        loc semi = strpos(`"`rest'"', ";")
        if `semi' > 0 {
            loc root = substr(`"`rest'"', 1, `semi' - 1)
            loc rest = substr(`"`rest'"', `semi' + 1, strlen(`"`rest'"'))
        }
        else {
            loc root `"`rest'"'
            loc rest ""
        }
        loc root = strtrim(`"`root'"')
        if `"`root'"' == "" continue
        smartload__scanroot, root(`"`root'"') post(`post') storage(`storage')
        loc ++nroots
    }
    return scalar nroots = `nroots'
end

program define smartload__scanroot, rclass
    version 19.5
    syntax , ROOT(string) POST(string) STORAGE(string)
    loc root = subinstr(`"`root'"', char(92), "/", .)
    mata: st_local("direx", strofreal(direxists(st_local("root"))))
    if "`direx'" != "1" exit

    loc root_l = lower(`"`root'"')
    foreach bad in "/windows" "/program files" "/program files (x86)" "/programdata" "/$recycle.bin" "/system volume information" "/recovery" {
        if strpos(`"`root_l'"', `"`bad'"') exit
    }

    loc posth "`post'"
    loc nfiles 0
    preserve
    qui clear
    qui set obs 1
    qui gen str2045 dirname = `"`root'"'
    qui gen byte done = 0

    qui count if done == 0
    while r(N) > 0 {
        sort done dirname
        loc cur = dirname[1]
        qui replace done = 1 in 1

        loc cur_l = lower(`"`cur'"')
        loc skip 0
        foreach bad in "/windows" "/program files" "/program files (x86)" "/programdata" "/$recycle.bin" "/system volume information" "/recovery" {
            if strpos(`"`cur_l'"', `"`bad'"') loc skip 1
        }
        if `skip' {
            qui count if done == 0
            continue
        }

        cap local files : dir `"`cur'"' files "*"
        if !_rc {
            foreach f of local files {
                mata: st_local("full", pathjoin(st_local("cur"), st_local("f")))
                mata: st_local("ext", strlower(pathsuffix(st_local("full"))))
                loc ext : subinstr loc ext "." "", all
                loc extok 0
                foreach ok in dta xlsx xls csv txt tsv dat sav por sas7bdat xpt pdf docx doc pptx ppt rds rdata r parquet feather pkl pickle arrow h5 hdf5 json jsonl sql sqlite db duckdb accdb mdb shp geojson gpkg kml kmz gdb zip gz 7z tar {
                    if "`ext'" == "`ok'" loc extok 1
                }
                if `extok' {
                    post `posth' (`"`full'"') (`"`f'"') (`"`cur'"') (`"`ext'"') ("`storage'")
                    loc ++nfiles
                }
            }
        }

        cap local dirs : dir `"`cur'"' dirs "*"
        if !_rc {
            foreach sub of local dirs {
                if `"`sub'"' == "." | `"`sub'"' == ".." continue
                mata: st_local("child", pathjoin(st_local("cur"), st_local("sub")))
                loc child = subinstr(`"`child'"', char(92), "/", .)
                mata: st_local("childex", strofreal(direxists(st_local("child"))))
                if "`childex'" != "1" continue
                loc child_l = lower(`"`child'"')
                loc badchild 0
                foreach bad in "/windows" "/program files" "/program files (x86)" "/programdata" "/$recycle.bin" "/system volume information" "/recovery" {
                    if strpos(`"`child_l'"', `"`bad'"') loc badchild 1
                }
                if `badchild' continue
                qui set obs `=_N + 1'
                qui replace dirname = `"`child'"' in L
                qui replace done = 0 in L
            }
        }

        qui count if done == 0
    }
    restore
    return scalar nfiles = `nfiles'
end

program define smartload__detected, rclass
    args filepath filename ext lh logrequested ocr
    loc kind "unsupported"
    if inlist("`ext'", "pdf") loc kind "PDF/document-table"
    else if inlist("`ext'", "docx", "doc") loc kind "Word/document-table"
    else if inlist("`ext'", "pptx", "ppt") loc kind "PowerPoint/presentation-table"
    else if inlist("`ext'", "zip", "gz", "7z", "tar") loc kind "archive"
    else if inlist("`ext'", "sqlite", "db", "duckdb", "accdb", "mdb", "sql") loc kind "database"
    else if inlist("`ext'", "shp", "geojson", "gpkg", "kml", "kmz", "gdb") loc kind "GIS"
    else if inlist("`ext'", "rds", "rdata", "r") loc kind "R"
    else if inlist("`ext'", "parquet", "feather", "pkl", "pickle", "arrow", "h5", "hdf5", "json", "jsonl") loc kind "Python/data-science"
    di as txt "Detected `kind' file: .`ext'"
    if inlist("`ext'", "pdf") {
        di as err "PDF files are document files, not ordinary Stata datasets."
        di as txt "smartload does not import PDF tables in the current version unless a tested external extraction engine is added."
        di as txt "This includes PDFs that visually contain Excel-like tables."
        if "`ocr'" == "" {
            di as txt "Scanned or image-based PDFs require OCR and are not imported automatically."
        }
    }
    else if inlist("`ext'", "docx", "doc") {
        di as err "Word files require table extraction before Stata can import them."
        di as txt "Current version detects this file but does not claim a successful table import."
    }
    else if inlist("`ext'", "pptx", "ppt") {
        di as err "PowerPoint files require extraction of real table objects before Stata can import them."
        di as txt "Images, screenshots, charts, and table-like pictures are not treated as reliable tables."
    }
    else if inlist("`ext'", "zip", "gz", "7z", "tar") {
        di as err "Archive inspection/extraction is reserved for a tested conversion path."
        di as txt "No files were extracted."
    }
    else if inlist("`ext'", "sqlite", "db", "duckdb", "accdb", "mdb", "sql") {
        di as err "Database files require table inspection through ODBC, Python, R, or another tested bridge."
        if "`ext'" == "sql" di as txt ".sql is usually a script or dump, not a rectangular dataset."
    }
    else if inlist("`ext'", "shp", "geojson", "gpkg", "kml", "kmz", "gdb") {
        di as err "GIS files require a tested GIS conversion workflow before import."
        if "`ext'" == "shp" di as txt "A shapefile also requires companion files such as .shx and .dbf."
    }
    else if inlist("`ext'", "rds", "rdata", "r") {
        di as err "R data files require R/Rscript conversion before Stata can import them."
    }
    else if inlist("`ext'", "parquet", "feather", "pkl", "pickle", "arrow", "h5", "hdf5", "json", "jsonl") {
        di as err "Python/data-science files require inspected conversion before Stata can import them."
        if inlist("`ext'", "pkl", "pickle") di as txt "Pickle files are not imported automatically because they may be unsafe and may not contain rectangular data."
    }
    else {
        di as err "This file type is not safely importable by smartload."
    }
    if "`logrequested'" == "1" {
        file write `lh' "Result: detected_not_imported" _n _n
        file close `lh'
    }
end
