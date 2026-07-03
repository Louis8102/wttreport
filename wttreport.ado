*! version 0.2.0-preview  03jul2026
program define wttreport, rclass
    version 19.5

    syntax varlist(numeric min=1) [if] [in], ///
        OUTDIR(string) ///
        [ BY(varname) BYVARS(varlist) ///
          REPLACE ALPHA(real 0.05) ///
          OUTPUT(string) ///
          BLOCKFILE(string) BLOCKFROMLABEL BLOCKFROMCHAR ///
          SHOW(string) SHOWDF AVAILABLECASE SHOWBLOCK ///
          SUMMARYSTYLE(string) TOP(integer 5) ///
          GRAPHBY(string) PLOTCOMBINE(integer 6) PLOTLAYOUT(string) ///
          PLOTLABELMODE(string) TABLELABELMODE(string) ///
          FORMATS(string) PNGWidth(integer 3200) ///
          NOTABLE NOPLOT NOSUMMARY NOMAPPING ///
          MINCELL(integer 2) ]

    if `alpha' <= 0 | `alpha' >= 1 {
        di as err "alpha() must be strictly between 0 and 1"
        exit 198
    }
    if `top' < 0 {
        di as err "top() must be 0 or a positive integer"
        exit 198
    }
    if `mincell' < 2 {
        di as err "mincell() must be at least 2"
        exit 198
    }
    if `"`notable'"' != "" & `"`noplot'"' != "" & `"`nosummary'"' != "" {
        di as err "at least one report component must be requested; do not specify notable, noplot, and nosummary together"
        exit 198
    }

    local output = lower(strtrim(`"`output'"'))
    if `"`output'"' == "" local output "report"
    if !inlist(`"`output'"', "report", "component") {
        di as err "output() must be report or component"
        exit 198
    }

    local n_by = (`"`by'"' != "") + (`"`byvars'"' != "")
    if `n_by' != 1 {
        di as err "specify exactly one of by() or byvars()"
        exit 198
    }
    if `"`by'"' != "" local bylist `"`by'"'
    else local bylist `"`byvars'"'

    local n_block_sources = (`"`blockfile'"' != "") + (`"`blockfromlabel'"' != "") + (`"`blockfromchar'"' != "")
    if `n_block_sources' > 1 {
        di as err "only one of blockfile(), blockfromlabel, or blockfromchar may be specified"
        exit 198
    }
    local blockopt ""
    if `"`blockfile'"' != "" local blockopt `"blockfile(`"`blockfile'"')"'
    if `"`blockfromlabel'"' != "" local blockopt `"blockfromlabel"'
    if `"`blockfromchar'"' != "" local blockopt `"blockfromchar"'

    local show = lower(strtrim(`"`show'"'))
    if `"`show'"' == "" local show "significant"
    if !inlist(`"`show'"', "significant", "all") {
        di as err "invalid display option"
        exit 198
    }

    local summarystyle = lower(strtrim(`"`summarystyle'"'))
    if `"`summarystyle'"' == "" local summarystyle "brief"
    if !inlist(`"`summarystyle'"', "brief", "academic") {
        di as err "summarystyle() must be brief or academic"
        exit 198
    }
    if `"`summarystyle'"' == "brief" & `top' != 5 {
        di as txt "note: top() affects summarystyle(academic) only; it is ignored for summarystyle(brief)."
    }

    local graphby = lower(strtrim(`"`graphby'"'))
    if `"`graphby'"' == "" local graphby "block"
    if !inlist(`"`graphby'"', "block", "all") {
        di as err "graphby() must be block or all"
        exit 198
    }

    local plotlayout = lower(strtrim(`"`plotlayout'"'))
    if `"`plotlayout'"' == "" local plotlayout "vertical"
    if !inlist(`"`plotlayout'"', "auto", "horizontal", "vertical") {
        di as err "plotlayout() must be auto, horizontal, or vertical"
        exit 198
    }

    if `plotcombine' < 1 | `plotcombine' > 6 {
        di as err "plotcombine() must be between 1 and 6"
        exit 198
    }

    if `"`formats'"' == "" local formats "png"

    if `"`tablelabelmode'"' == "" local tablelabelmode "item"
    local plotlabelopt ""
    if `"`plotlabelmode'"' != "" local plotlabelopt `"labelmode(`plotlabelmode')"'

    marksample touse, novarlist
    foreach g of local bylist {
        capture confirm variable `g'
        if _rc {
            di as err "by variable `g' not found"
            exit 111
        }
    }
    if `"`availablecase'"' == "" {
        markout `touse' `varlist'
        markout `touse' `bylist', strok
    }
    foreach g of local bylist {
        quietly levelsof `g' if `touse' & !missing(`g'), local(__levs)
        local __nlev : word count `__levs'
        if `__nlev' != 2 {
            di as err "by variable `g' must have exactly two nonmissing levels in the analysis sample; found `__nlev'"
            exit 198
        }
    }

    capture mkdir `"`outdir'"'
    capture mkdir `"`outdir'/results"'
    capture mkdir `"`outdir'/tables"'
    capture mkdir `"`outdir'/summaries"'
    capture mkdir `"`outdir'/figures_raw"'

    local manifest `"`outdir'/wttreport_manifest.txt"'
    capture quietly confirm new file `"`manifest'"'
    if _rc & `"`replace'"' == "" {
        di as err `"file `manifest' already exists; specify replace"'
        exit 602
    }

    tempname mf
    quietly file open `mf' using `"`manifest'"', write replace text
    file write `mf' "wttreport manifest" _n
    file write `mf' "created: `c(current_date)' `c(current_time)'" _n
    file write `mf' "outcomes: `varlist'" _n
    file write `mf' "by variables: `bylist'" _n _n

    local table_files ""
    local summary_files ""
    local result_files ""
    local figure_dirs ""
    local report_files ""
    local report_labels ""
    local gsafes ""
    local i = 0
    local first = 1

    foreach g of local bylist {
        local ++i
        local gsafe = strtoname("`g'")
        local gtitle : variable label `g'
        local gtitle = strtrim(`"`gtitle'"')
        if `"`gtitle'"' == "" {
            local gtitle = strproper(subinstr("`g'", "_", " ", .))
        }
        else {
            local gtitle = strproper(`"`gtitle'"')
        }
        local gsafes "`gsafes' `gsafe'"
        local gdir `"`outdir'/`gsafe'"'
        capture mkdir `"`gdir'"'
        capture mkdir `"`gdir'/figures"'

        local tabledoc `"`outdir'/tables/table_`i'_`gsafe'.docx"'
        local resultdta `"`outdir'/results/results_`i'_`gsafe'.dta"'
        local summarydoc `"`outdir'/summaries/summary_`i'_`gsafe'.docx"'
        local summarydata `"`outdir'/results/block_summary_`i'_`gsafe'.dta"'
        local figdir `"`outdir'/figures_raw/figures_`i'_`gsafe'"'
        local figuredoc `"`gdir'/figures_`gsafe'.docx"'
        local reportdoc `"`outdir'/`gsafe'.docx"'
        capture mkdir `"`figdir'"'

        local mapdocopt ""
        if `first' & `"`nomapping'"' == "" {
            local mapdocopt `"mapdoc(`"`outdir'/mapping.docx"')"'
        }

        if `"`notable'"' == "" {
            preserve
            capture quietly _wttreport_table `varlist' if `touse', by(`g') ///
                saving(`"`tabledoc'"') results(`"`resultdta'"') ///
                alpha(`alpha') show(`show') mincell(`mincell') ///
                `blockopt' `showdf' `availablecase' `showblock' ///
                labelmode(`tablelabelmode') ///
                title("Welch Independent Sample t-Test Results by `gtitle'") ///
                tablenumber("Table `i'") ///
                `mapdocopt' replace
            local __rc = _rc
            if `__rc' == 2000 & `"`show'"' == "significant" {
                
                quietly _wttreport_table `varlist' if `touse', by(`g') ///
                    saving(`"`tabledoc'"') results(`"`resultdta'"') ///
                    alpha(`alpha') show(all) mincell(`mincell') ///
                    `blockopt' `showdf' `availablecase' `showblock' ///
                    labelmode(`tablelabelmode') ///
                    title("Welch Independent Sample t-Test Results by `gtitle'") ///
                    tablenumber("Table `i'") ///
                    `mapdocopt' replace
            }
            else if `__rc' {
                exit `__rc'
            }
            restore
        }
        else {
            preserve
            capture quietly _wttreport_table `varlist' if `touse', by(`g') ///
                saving(`"`tabledoc'"') results(`"`resultdta'"') ///
                alpha(`alpha') show(`show') mincell(`mincell') ///
                `blockopt' `showdf' `availablecase' `showblock' ///
                labelmode(`tablelabelmode') ///
                title("Welch Independent Sample t-Test Results by `gtitle'") ///
                tablenumber("Table `i'") ///
                `mapdocopt' replace
            local __rc = _rc
            if `__rc' == 2000 & `"`show'"' == "significant" {
                quietly _wttreport_table `varlist' if `touse', by(`g') ///
                    saving(`"`tabledoc'"') results(`"`resultdta'"') ///
                    alpha(`alpha') show(all) mincell(`mincell') ///
                    `blockopt' `showdf' `availablecase' `showblock' ///
                    labelmode(`tablelabelmode') ///
                    title("Welch Independent Sample t-Test Results by `gtitle'") ///
                    tablenumber("Table `i'") ///
                    `mapdocopt' replace
            }
            else if `__rc' {
                exit `__rc'
            }
            restore
            capture erase `"`tabledoc'"'
        }

        if `"`noplot'"' == "" {
            if `"`replace'"' != "" {
                local __oldimgs : dir `"`figdir'"' files "*.png"
                foreach __oldimg of local __oldimgs {
                    capture erase `"`figdir'/`__oldimg'"'
                }
                local __oldpdfs : dir `"`figdir'"' files "*.pdf"
                foreach __oldpdf of local __oldpdfs {
                    capture erase `"`figdir'/`__oldpdf'"'
                }
            }
            preserve
            local __figtitle `"Figure `i'||Effect Size Comparison by `gtitle'"'
            if `"`show'"' == "all" {
                local __figtitle `"Figure `i'||Effect Size Comparison by `gtitle' for All Items"'
            }
            quietly _wttreport_plot `varlist' if `touse', by(`g') ///
                graphdir(`"`figdir'"') alpha(`alpha') show(`show') ///
                mincell(`mincell') `blockopt' graphby(`graphby') ///
                combine(`plotcombine') layout(`plotlayout') ///
                `plotlabelopt' `availablecase' formats(`formats') ///
                pngwidth(`pngwidth') ///
                title(`"`__figtitle'"') ///
                replace
            restore
        }

        if `"`nosummary'"' == "" {
            preserve
            local appletter = char(64 + `i')
            quietly _wttreport_summary using `"`resultdta'"', ///
                saving(`"`summarydoc'"') summarydata(`"`summarydata'"') ///
                style(`summarystyle') top(`top') alpha(`alpha') ///
                appendixletter(`"`appletter'"') replace
            restore
        }

        if `"`output'"' == "report" {
            local __n_parts = 0
            if `"`notable'"' == "" {
                capture confirm file `"`tabledoc'"'
                if !_rc {
                    local ++__n_parts
                    local __part`__n_parts' `"`tabledoc'"'
                }
            }
            if `"`noplot'"' == "" {
                local __n_png = 0
                putdocx clear
                putdocx begin, pagesize(letter) landscape font("Times New Roman", 12)
                local __first_png = 1
                local __pngs : dir `"`figdir'"' files "combined_*.png"
                foreach __png of local __pngs {
                    local ++__n_png
                    if !`__first_png' {
                        putdocx pagebreak
                    }
                    putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 0pt)
                    putdocx image `"`figdir'/`__png'"', width(9)
                    local __first_png = 0
                }
                if `__n_png' > 0 {
                    capture quietly putdocx save `"`figuredoc'"', replace
                    if !_rc {
                        local ++__n_parts
                        local __part`__n_parts' `"`figuredoc'"'
                    }
                    local __allimgs : dir `"`figdir'"' files "*.png"
                    foreach __img of local __allimgs {
                        capture erase `"`figdir'/`__img'"'
                    }
                    local __allpdfs : dir `"`figdir'"' files "*.pdf"
                    foreach __pdf of local __allpdfs {
                        capture erase `"`figdir'/`__pdf'"'
                    }
                }
                else {
                    putdocx paragraph, halign(center) spacing(before, 150pt) spacing(after, 12pt)
                    putdocx text ("Two-Group Effect-Size Comparisons by `gtitle'"), font("Times New Roman", 16, black)
                    putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 0pt)
                    putdocx text ("No FDR-significant group differences were found for any outcome in any block; therefore, no effect-size comparison plot was produced."), font("Times New Roman", 12, black)
                    capture quietly putdocx save `"`figuredoc'"', replace
                    if !_rc {
                        local ++__n_parts
                        local __part`__n_parts' `"`figuredoc'"'
                    }
                }
            }
            if `"`nosummary'"' == "" {
                capture confirm file `"`summarydoc'"'
                if !_rc {
                    local ++__n_parts
                    local __part`__n_parts' `"`summarydoc'"'
                }
            }

            if `__n_parts' > 0 {
                if `__n_parts' == 1 {
                    local __only_part `"`__part1'"'
                    capture copy `"`__only_part'"' `"`reportdoc'"', replace
                    if _rc {
                        di as err "wttreport could not create the combined report for `g'"
                        exit _rc
                    }
                    if `"`__only_part'"' == `"`figuredoc'"' {
                        capture erase `"`figuredoc'"'
                    }
                }
                else {
                    local __current_part `"`__part1'"'
                    local __merge_tmps ""
                    forvalues __p = 2/`__n_parts' {
                        local __next_part `"`__part`__p''"'
                        local __merged_part `"`outdir'/_wttreport_merge_`i'_`gsafe'_`__p'.docx"'
                        capture quietly putdocx append "`__current_part'" "`__next_part'", saving("`__merged_part'", replace) pagebreak headsrc(first) stylesrc(own) nomsg
                        if _rc {
                            di as err "wttreport could not create the combined report for `g'"
                            foreach __tmp of local __merge_tmps {
                                capture erase "`__tmp'"
                            }
                            exit _rc
                        }
                        if `__p' > 2 {
                            capture erase "`__current_part'"
                        }
                        local __merge_tmps `"`__merge_tmps' "`__merged_part'""'
                        local __current_part `"`__merged_part'"'
                    }
                    capture copy "`__current_part'" "`reportdoc'", replace
                    if _rc {
                        di as err "wttreport could not create the combined report for `g'"
                        foreach __tmp of local __merge_tmps {
                            capture erase "`__tmp'"
                        }
                        exit _rc
                    }
                    foreach __tmp of local __merge_tmps {
                        capture erase "`__tmp'"
                    }
                    capture erase `"`figuredoc'"'
                }
                local report_files `"`report_files' `"`reportdoc'"'"'
                local __display_title = lower(`"`gtitle'"')
                local report_labels `"`report_labels' `"`__display_title'.docx"'"'
            }
        }

        file write `mf' "by variable `i': `g'" _n
        if `"`output'"' == "report" file write `mf' "  report: `reportdoc'" _n
        file write `mf' "  table: `tabledoc'" _n
        file write `mf' "  results: `resultdta'" _n
        file write `mf' "  summary: `summarydoc'" _n
        file write `mf' "  figures: `figdir'" _n _n

        local table_files `"`table_files' `"`tabledoc'"'"'
        local summary_files `"`summary_files' `"`summarydoc'"'"'
        local result_files `"`result_files' `"`resultdta'"'"'
        local figure_dirs `"`figure_dirs' `"`figdir'"'"'
        local first = 0
    }
    file close `mf'

    local combined_tables `"`outdir'/wttreport_tables.docx"'
    local combined_summaries `"`outdir'/wttreport_summaries.docx"'
    local combined_figures `"`outdir'/wttreport_figures.docx"'

    if `"`output'"' == "component" & `"`notable'"' == "" & `i' > 1 {
        tempfile __append_tables
        tempname __taf
        quietly file open `__taf' using `"`__append_tables'"', write replace text
        file write `__taf' `"putdocx append"'
        local __k = 0
        foreach __g of local gsafes {
            local ++__k
            local __f `"`outdir'/tables/table_`__k'_`__g'.docx"'
            file write `__taf' `" "`__f'""'
        }
        file write `__taf' `", saving("`combined_tables'", replace)"' _n
        file close `__taf'
        capture quietly do `"`__append_tables'"'
        if _rc {
            di as txt "note: component table files were created, but wttreport could not merge them into one Word file."
            local combined_tables ""
        }
    }
    else if `"`output'"' == "component" & `"`notable'"' == "" & `i' == 1 {
        local combined_tables : word 1 of `table_files'
    }
    else if `"`output'"' == "report" {
        local combined_tables ""
    }

    if `"`output'"' == "component" & `"`nosummary'"' == "" & `i' > 1 {
        tempfile __append_summaries
        tempname __saf
        quietly file open `__saf' using `"`__append_summaries'"', write replace text
        file write `__saf' `"putdocx append"'
        local __k = 0
        foreach __g of local gsafes {
            local ++__k
            local __f `"`outdir'/summaries/summary_`__k'_`__g'.docx"'
            file write `__saf' `" "`__f'""'
        }
        file write `__saf' `", saving("`combined_summaries'", replace)"' _n
        file close `__saf'
        capture quietly do `"`__append_summaries'"'
        if _rc {
            di as txt "note: component summary files were created, but wttreport could not merge them into one Word file."
            local combined_summaries ""
        }
    }
    else if `"`output'"' == "component" & `"`nosummary'"' == "" & `i' == 1 {
        local combined_summaries : word 1 of `summary_files'
    }
    else if `"`output'"' == "report" {
        local combined_summaries ""
    }

    if `"`output'"' == "component" & `"`noplot'"' == "" {
        local __n_png = 0
        putdocx clear
        putdocx begin, pagesize(letter) landscape font("Times New Roman", 12)
        local __first_png = 1
        local __j = 0
        foreach __d of local figure_dirs {
            local ++__j
            local __g : word `__j' of `bylist'
            local __pngs : dir `"`__d'"' files "combined_*.png"
            local __this_n_png = 0
            foreach __png of local __pngs {
                local ++__n_png
                local ++__this_n_png
                if !`__first_png' {
                    putdocx pagebreak
                }
                putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 0pt)
                putdocx image `"`__d'/`__png'"', width(9)
                local __first_png = 0
            }
            if `__this_n_png' == 0 {
                local ++__n_png
                if !`__first_png' {
                    putdocx pagebreak
                }
                local __gtitle `"`__g'"'
                capture local __glabel : variable label `__g'
                if !_rc & `"`__glabel'"' != "" local __gtitle `"`__glabel'"'
                local __gtitle = strproper(`"`__gtitle'"')
                putdocx paragraph, halign(center) spacing(before, 150pt) spacing(after, 12pt)
                putdocx text ("Two-Group Effect-Size Comparisons by `__gtitle'"), font("Times New Roman", 16, black)
                putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 0pt)
                putdocx text ("No FDR-significant group differences were found for any outcome in any block; therefore, no effect-size comparison plot was produced."), font("Times New Roman", 12, black)
                local __first_png = 0
            }
        }
        if `__n_png' > 0 {
            capture quietly putdocx save `"`combined_figures'"', replace
            if _rc {
                di as txt "note: figure PNG files were created, but wttreport could not collect them into one Word file."
                local combined_figures ""
            }
            else {
                foreach __d of local figure_dirs {
                    local __allimgs : dir `"`__d'"' files "*.png"
                    foreach __img of local __allimgs {
                        capture erase `"`__d'/`__img'"'
                    }
                    local __allpdfs : dir `"`__d'"' files "*.pdf"
                    foreach __pdf of local __allpdfs {
                        capture erase `"`__d'/`__pdf'"'
                    }
                }
            }
        }
        else {
            putdocx clear
            local combined_figures ""
        }
    }
    if `"`output'"' == "report" {
        local combined_figures ""
    }

    if `i' == 1 {
        local __first_result : word 1 of `result_files'
        capture confirm file `"`__first_result'"'
        if !_rc {
            preserve
            quietly use `"`__first_result'"', clear
            capture confirm variable n1
            if !_rc {
                quietly summarize n1, meanonly
                local __n1min = r(min)
                local __n1max = r(max)
                quietly summarize n2, meanonly
                local __n2min = r(min)
                local __n2max = r(max)
                quietly count
                local __rows = r(N)
                quietly levelsof group1 in 1, local(__g1_label) clean
                quietly levelsof group2 in 1, local(__g2_label) clean
                if `__n1min' == `__n1max' & `__n2min' == `__n2max' {
                    local __n1txt : display %9.0f `__n1min'
                    local __n2txt : display %9.0f `__n2min'
                    local __n1txt = strtrim("`__n1txt'")
                    local __n2txt = strtrim("`__n2txt'")
                    local __ntotal = `__n1min' + `__n2min'
                    local __ntotaltxt : display %9.0f `__ntotal'
                    local __ntotaltxt = strtrim("`__ntotaltxt'")
                }
                else {
                    local __n1txt = ""
                    local __n2txt = ""
                    local __ntotaltxt = ""
                }
            }
            restore
        }
    }
    else if `"`output'"' == "report" {
        local combined_figures ""
    }

    di as txt "wttreport complete"
    if `i' == 1 & `"`__ntotaltxt'"' != "" {
        di as txt "Complete-case sample: " as result "`__ntotaltxt'"
        di as txt "Group sizes: " as result "G1=`__n1txt', G2=`__n2txt'"
    }
    else if `i' > 1 {
        di as txt "Grouping variables processed: " as result "`i'"
    }
    if `"`nomapping'"' == "" {
        local __mapping_file `"`outdir'/mapping.docx"'
        capture confirm file `"`__mapping_file'"'
        if !_rc {
            local __mapping_abs `"`__mapping_file'"'
            if strpos(`"`__mapping_abs'"', ":") == 0 & substr(`"`__mapping_abs'"', 1, 1) != "/" {
                local __mapping_abs `"`c(pwd)'/`__mapping_abs'"'
            }
            local __mapping_abs = subinstr(`"`__mapping_abs'"', "\", "/", .)
            local __mapping_uri `"file:///`__mapping_abs'"'
            local __mapping_label `"mapping.docx"'
            di as txt "Mapping document saved to:"
            di as smcl `"  {browse "`__mapping_uri'":`__mapping_label'}"'
        }
    }
    if `"`output'"' == "report" & `"`report_files'"' != "" {
        if `i' == 1 di as txt "Report saved to:"
        else di as txt "Reports saved to:"
        local __ridx = 0
        foreach __report of local report_files {
            local ++__ridx
            local __report_abs `"`__report'"'
            if strpos(`"`__report_abs'"', ":") == 0 & substr(`"`__report_abs'"', 1, 1) != "/" {
                local __report_abs `"`c(pwd)'/`__report_abs'"'
            }
            local __report_abs = subinstr(`"`__report_abs'"', "\", "/", .)
            local __report_uri `"file:///`__report_abs'"'
            local __report_label : word `__ridx' of `report_labels'
            if `"`__report_label'"' == "" {
                local __report_label `"`__report'"'
                while strpos(`"`__report_label'"', "\") > 0 {
                    local __p = strpos(`"`__report_label'"', "\")
                    local __report_label = substr(`"`__report_label'"', `__p' + 1, .)
                }
                while strpos(`"`__report_label'"', "/") > 0 {
                    local __p = strpos(`"`__report_label'"', "/")
                    local __report_label = substr(`"`__report_label'"', `__p' + 1, .)
                }
            }
            di as smcl `"  {browse "`__report_uri'":`__report_label'}"'
        }
    }
    if `"`combined_tables'"' != "" & `"`notable'"' == "" {
        local __tables_abs `"`combined_tables'"'
        if strpos(`"`__tables_abs'"', ":") == 0 & substr(`"`__tables_abs'"', 1, 1) != "/" {
            local __tables_abs `"`c(pwd)'/`__tables_abs'"'
        }
        local __tables_abs = subinstr(`"`__tables_abs'"', "\", "/", .)
        local __tables_uri `"file:///`__tables_abs'"'
        local __tables_label `"`combined_tables'"'
        while strpos(`"`__tables_label'"', "\") > 0 {
            local __p = strpos(`"`__tables_label'"', "\")
            local __tables_label = substr(`"`__tables_label'"', `__p' + 1, .)
        }
        while strpos(`"`__tables_label'"', "/") > 0 {
            local __p = strpos(`"`__tables_label'"', "/")
            local __tables_label = substr(`"`__tables_label'"', `__p' + 1, .)
        }
        di as txt "Word table saved to:"
        di as smcl `"  {browse "`__tables_uri'":`__tables_label'}"'
    }
    if `"`combined_figures'"' != "" & `"`noplot'"' == "" {
        local __figures_abs `"`combined_figures'"'
        if strpos(`"`__figures_abs'"', ":") == 0 & substr(`"`__figures_abs'"', 1, 1) != "/" {
            local __figures_abs `"`c(pwd)'/`__figures_abs'"'
        }
        local __figures_abs = subinstr(`"`__figures_abs'"', "\", "/", .)
        local __figures_uri `"file:///`__figures_abs'"'
        local __figures_label `"`combined_figures'"'
        while strpos(`"`__figures_label'"', "\") > 0 {
            local __p = strpos(`"`__figures_label'"', "\")
            local __figures_label = substr(`"`__figures_label'"', `__p' + 1, .)
        }
        while strpos(`"`__figures_label'"', "/") > 0 {
            local __p = strpos(`"`__figures_label'"', "/")
            local __figures_label = substr(`"`__figures_label'"', `__p' + 1, .)
        }
        di as txt "Figure document saved to:"
        di as smcl `"  {browse "`__figures_uri'":`__figures_label'}"'
    }
    if `"`combined_summaries'"' != "" & `"`nosummary'"' == "" {
        local __summaries_abs `"`combined_summaries'"'
        if strpos(`"`__summaries_abs'"', ":") == 0 & substr(`"`__summaries_abs'"', 1, 1) != "/" {
            local __summaries_abs `"`c(pwd)'/`__summaries_abs'"'
        }
        local __summaries_abs = subinstr(`"`__summaries_abs'"', "\", "/", .)
        local __summaries_uri `"file:///`__summaries_abs'"'
        local __summaries_label `"`combined_summaries'"'
        while strpos(`"`__summaries_label'"', "\") > 0 {
            local __p = strpos(`"`__summaries_label'"', "\")
            local __summaries_label = substr(`"`__summaries_label'"', `__p' + 1, .)
        }
        while strpos(`"`__summaries_label'"', "/") > 0 {
            local __p = strpos(`"`__summaries_label'"', "/")
            local __summaries_label = substr(`"`__summaries_label'"', `__p' + 1, .)
        }
        di as txt "Summary saved to:"
        di as smcl `"  {browse "`__summaries_uri'":`__summaries_label'}"'
    }

    return scalar n_byvars = `i'
    return local outdir `"`outdir'"'
    return local manifest `"`manifest'"'
    return local combined_tables `"`combined_tables'"'
    return local combined_figures `"`combined_figures'"'
    return local combined_summaries `"`combined_summaries'"'
    return local output `"`output'"'
    return local report_files `"`report_files'"'
    return local table_files `"`table_files'"'
    return local summary_files `"`summary_files'"'
    return local result_files `"`result_files'"'
    return local figure_dirs `"`figure_dirs'"'
end


program define _wttreport_table, rclass
    version 19.5

    syntax varlist(numeric min=1) [if] [in], ///
        BY(varname) SAVing(string) ///
        [ REPLACE ALPHA(real 0.05) ///
          SHOW(string) SHOWDF AVAILABLECASE ///
          BLOCKFILE(string) BLOCKFROMLABEL BLOCKFROMCHAR SHOWBLOCK ///
          RESULTS(string) EXCEL(string) MAPDOC(string) LABELMODE(string) ///
          MINCELL(integer 2) ///
          TITLE(string) TABLENUMber(string) ///
          NOTE(string) ]

    if `alpha' <= 0 | `alpha' >= 1 {
        di as err "alpha() must be strictly between 0 and 1"
        exit 198
    }
    if `mincell' < 2 {
        di as err "mincell() must be at least 2"
        exit 198
    }

    local show = lower(strtrim(`"`show'"'))
    if `"`show'"' == "" local show "significant"
    if !inlist(`"`show'"', "significant", "all") {
        di as err "invalid display option"
        exit 198
    }

    if `"`title'"' == "" local title "Welch Two-Group Test Results"
    if `"`tablenumber'"' == "" local tablenumber "Table 1"

    local labelmode = lower(strtrim(`"`labelmode'"'))
    if `"`labelmode'"' == "" local labelmode "label"
    if !inlist(`"`labelmode'"', "label", "item") {
        di as err "labelmode() must be label or item"
        exit 198
    }

    local n_block_sources = (`"`blockfile'"' != "") + (`"`blockfromlabel'"' != "") + (`"`blockfromchar'"' != "")
    if `n_block_sources' > 1 {
        di as err "only one of blockfile(), blockfromlabel, or blockfromchar may be specified"
        exit 198
    }

    capture confirm new file `"`saving'"'
    if _rc & `"`replace'"' == "" {
        di as err `"file `saving' already exists; specify replace"'
        exit 602
    }
    if `"`results'"' != "" {
        capture confirm new file `"`results'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `results' already exists; specify replace"'
            exit 602
        }
    }
    if `"`excel'"' != "" {
        capture confirm new file `"`excel'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `excel' already exists; specify replace"'
            exit 602
        }
    }
    if `"`mapdoc'"' != "" {
        capture confirm new file `"`mapdoc'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `mapdoc' already exists; specify replace"'
            exit 602
        }
    }

    marksample touse, novarlist
    markout `touse' `by', strok
    if `"`availablecase'"' == "" markout `touse' `varlist'

    quietly count if `touse'
    if r(N) == 0 {
        di as err "no observations in the analysis sample"
        exit 2000
    }
    local sample_N = r(N)

    preserve
        keep if `touse'

        tempvar gid
        capture confirm numeric variable `by'
        if !_rc {
            quietly egen `gid' = group(`by') if !missing(`by'), label
        }
        else {
            quietly egen `gid' = group(`by') if !missing(`by'), label
        }
        quietly levelsof `gid', local(gids)
        local ngroups : word count `gids'
        if `ngroups' != 2 {
            di as err "by() must identify exactly two observed groups in the analysis sample"
            restore
            exit 198
        }
        local g1 : word 1 of `gids'
        local g2 : word 2 of `gids'

        quietly levelsof `by' if `gid' == `g1', local(orig1) clean
        quietly levelsof `by' if `gid' == `g2', local(orig2) clean
        local group_name1 "`orig1'"
        local group_name2 "`orig2'"
        capture confirm numeric variable `by'
        if !_rc {
            local vallab : value label `by'
            if `"`vallab'"' != "" {
                local first1 : word 1 of `orig1'
                local first2 : word 1 of `orig2'
                local lab1 : label `vallab' `first1'
                local lab2 : label `vallab' `first2'
                if `"`lab1'"' != "" local group_name1 `"`lab1'"'
                if `"`lab2'"' != "" local group_name2 `"`lab2'"'
            }
        }

        if `"`availablecase'"' == "" {
            quietly count if `gid' == `g1'
            local group_N1 = r(N)
            quietly count if `gid' == `g2'
            local group_N2 = r(N)
        }

        tempfile blockmapclean rawresults prefdr fdrvalues fullresults displayresults tabledata
        tempname rawpost

        if `"`blockfile'"' != "" {
            capture confirm file `"`blockfile'"'
            if _rc {
                di as err `"blockfile() not found: `blockfile'"'
                restore
                exit 601
            }
            preserve
                quietly use `"`blockfile'"', clear
                foreach needed in varname blockid blocklabel {
                    capture confirm variable `needed'
                    if _rc {
                        di as err "blockfile() must contain variable `needed'"
                        restore
                        restore
                        exit 111
                    }
                }
                capture confirm string variable varname
                if _rc {
                    di as err "varname in blockfile() must be a string variable"
                    restore
                    restore
                    exit 109
                }
                capture confirm string variable blocklabel
                if _rc {
                    di as err "blocklabel in blockfile() must be a string variable"
                    restore
                    restore
                    exit 109
                }
                keep varname blockid blocklabel
                quietly replace varname = strtrim(varname)
                quietly replace blocklabel = strtrim(blocklabel)
                quietly count if missing(varname) | missing(blockid) | missing(blocklabel)
                if r(N) > 0 {
                    di as err "blockfile() contains missing varname, blockid, or blocklabel"
                    restore
                    restore
                    exit 459
                }
                quietly save `"`blockmapclean'"', replace
            restore
        }

        quietly postfile `rawpost' int item_no ///
            str32 variable str32 label_blockcode str244 label_blocklabel str244 rowlabel ///
            str80 group1 str80 group2 ///
            double n1 mean1 sd1 n2 mean2 sd2 t df p gav se_gav lb_gav ub_gav ///
            using `"`rawresults'"', replace

        local item = 0
        foreach y of varlist `varlist' {
            local ++item
            local ylab : variable label `y'
            local rowlab `"`ylab'"'
            if `"`rowlab'"' == "" local rowlab "`y'"
            local label_blockcode ""
            local label_blocklabel ""

            if `"`blockfromchar'"' != "" {
                local label_blockcode : char `y'[owatable_blockid]
                local label_blocklabel : char `y'[owatable_blocklabel]
                local char_rowlab : char `y'[owatable_label]
                local label_blockcode = strtrim(`"`label_blockcode'"')
                local label_blocklabel = strtrim(`"`label_blocklabel'"')
                if `"`ylab'"' == "" & `"`char_rowlab'"' != "" local rowlab `"`char_rowlab'"'
                if `"`label_blockcode'"' == "" | `"`label_blocklabel'"' == "" {
                    di as err "blockfromchar requires variable characteristics:"
                    di as err `"char `y'[owatable_blockid] "B01""'
                    di as err `"char `y'[owatable_blocklabel] "Block label""'
                    restore
                    exit 198
                }
            }
            else if `"`blockfromlabel'"' != "" {
                local closepos = strpos(`"`ylab'"', "]")
                local pipepos = strpos(`"`ylab'"', "|")
                if substr(`"`ylab'"', 1, 1) == "[" & `closepos' > 0 & `pipepos' > 0 & `pipepos' < `closepos' {
                    local label_blockcode = strtrim(substr(`"`ylab'"', 2, `pipepos' - 2))
                    local label_blocklabel = strtrim(substr(`"`ylab'"', `pipepos' + 1, `closepos' - `pipepos' - 1))
                    local rowlab = strtrim(substr(`"`ylab'"', `closepos' + 1, .))
                    if `"`rowlab'"' == "" local rowlab "`y'"
                }
                else {
                    di as err "blockfromlabel requires variable labels to follow:"
                    di as err "[block_id | block_label] display_label"
                    di as err "variable `y' has label: `ylab'"
                    restore
                    exit 198
                }
            }

            quietly summarize `y' if `gid' == `g1'
            local n1 = r(N)
            local mean1 = r(mean)
            local sd1 = r(sd)
            quietly summarize `y' if `gid' == `g2'
            local n2 = r(N)
            local mean2 = r(mean)
            local sd2 = r(sd)

            local t = .
            local df = .
            local p = .
            local gav = .
            local se_gav = .
            local lb_gav = .
            local ub_gav = .
            if `n1' >= `mincell' & `n2' >= `mincell' & `sd1' > 0 & `sd2' > 0 {
                local v1 = `sd1'^2
                local v2 = `sd2'^2
                local se = sqrt(`v1'/`n1' + `v2'/`n2')
                local t = (`mean1' - `mean2') / `se'
                local df = (`v1'/`n1' + `v2'/`n2')^2 / ((`v1'/`n1')^2/(`n1'-1) + (`v2'/`n2')^2/(`n2'-1))
                local p = 2 * ttail(`df', abs(`t'))
                local sdav = sqrt((`v1' + `v2') / 2)
                local esdf = `n1' + `n2' - 2
                local J = 1 - 3/(4 * `esdf' - 1)
                local gav = `J' * ((`mean1' - `mean2') / `sdav')
                local se_gav = sqrt((`n1' + `n2') / (`n1' * `n2') + (`gav'^2) / (2 * (`n1' + `n2' - 2)))
                local zcrit = invnormal(1 - `alpha'/2)
                local lb_gav = `gav' - `zcrit' * `se_gav'
                local ub_gav = `gav' + `zcrit' * `se_gav'
            }

            post `rawpost' (`item') (`"`y'"') (`"`label_blockcode'"') (`"`label_blocklabel'"') ///
                (`"`rowlab'"') (`"`group_name1'"') (`"`group_name2'"') ///
                (`n1') (`mean1') (`sd1') (`n2') (`mean2') (`sd2') ///
                (`t') (`df') (`p') (`gav') (`se_gav') (`lb_gav') (`ub_gav')
        }
        quietly postclose `rawpost'

        quietly use `"`rawresults'"', clear

        if `"`blockfile'"' != "" {
            quietly drop label_blockcode label_blocklabel
            quietly merge 1:1 variable using `"`blockmapclean'"', keep(master match)
            quietly count if _merge == 1
            if r(N) > 0 {
                di as err "blockfile() does not map all variables in varlist"
                restore
                exit 459
            }
            quietly drop _merge
            capture confirm numeric variable blockid
            if _rc quietly encode blockid, gen(blockid_num)
            else quietly generate double blockid_num = blockid
            quietly drop blockid
            quietly rename blockid_num blockid
            quietly generate str32 blockcode = string(blockid)
        }
        else if `"`blockfromlabel'"' != "" | `"`blockfromchar'"' != "" {
            quietly generate str32 blockcode = label_blockcode
            quietly generate str244 blocklabel = label_blocklabel
            quietly count if missing(blockcode) | missing(blocklabel)
            if r(N) > 0 {
                di as err "could not parse block information for all variables"
                restore
                exit 198
            }
            capture destring blockcode, generate(blockid) ignore("B b _-") force
            quietly count if missing(blockid)
            if r(N) > 0 {
                quietly encode blockcode, generate(blockid2)
                quietly drop blockid
                quietly rename blockid2 blockid
            }
            quietly drop label_blockcode label_blocklabel
        }
        else {
            quietly generate double blockid = 1
            quietly generate str32 blockcode = ""
            quietly generate str244 blocklabel = ""
            quietly drop label_blockcode label_blocklabel
        }

        quietly generate long result_id = _n
        quietly save `"`prefdr'"', replace

        quietly keep result_id p
        quietly keep if !missing(p)
        quietly sort p result_id
        quietly generate long fdr_rank = _n
        quietly count
        quietly generate long fdr_m = r(N)
        quietly generate double q = p * fdr_m / fdr_rank
        quietly gsort -fdr_rank
        quietly replace q = min(q, q[_n-1]) if _n > 1
        quietly replace q = min(q, 1)
        quietly keep result_id q
        quietly save `"`fdrvalues'"', replace

        quietly use `"`prefdr'"', clear
        quietly merge 1:1 result_id using `"`fdrvalues'"', nogen

        quietly generate byte showrow = 1
        if `"`show'"' == "significant" {
            quietly replace showrow = !missing(q) & q < `alpha'
        }

        quietly generate str12 mean_txt1 = cond(missing(mean1), ".", strtrim(string(mean1, "%9.2f")))
        quietly generate str14 sd_txt1 = cond(missing(sd1), "(.)", "(" + strtrim(string(sd1, "%9.2f")) + ")")
        quietly generate str12 mean_txt2 = cond(missing(mean2), ".", strtrim(string(mean2, "%9.2f")))
        quietly generate str14 sd_txt2 = cond(missing(sd2), "(.)", "(" + strtrim(string(sd2, "%9.2f")) + ")")

        quietly generate str18 t_txt = cond(missing(t), ".", strtrim(string(t, "%9.2f")))
        quietly generate str18 df_txt = cond(missing(df), ".", strtrim(string(df, "%9.2f")))
        quietly generate str12 p_txt = cond(missing(p), ".", cond(p < .001, "<.001", subinstr(strtrim(string(p, "%9.3f")), "0.", ".", 1)))
        quietly generate str12 q_txt = cond(missing(q), ".", cond(q < .001, "<.001", subinstr(strtrim(string(q, "%9.3f")), "0.", ".", 1)))
        quietly generate double abs_gav = abs(gav)
        quietly generate double abs_lb_gav = min(abs(lb_gav), abs(ub_gav)) if !missing(lb_gav) & !missing(ub_gav) & lb_gav * ub_gav > 0
        quietly generate double abs_ub_gav = max(abs(lb_gav), abs(ub_gav)) if !missing(lb_gav) & !missing(ub_gav) & lb_gav * ub_gav > 0
        quietly replace abs_lb_gav = 0 if !missing(lb_gav) & !missing(ub_gav) & lb_gav * ub_gav <= 0
        quietly replace abs_ub_gav = max(abs(lb_gav), abs(ub_gav)) if !missing(lb_gav) & !missing(ub_gav) & lb_gav * ub_gav <= 0
        quietly generate str8 gav_num_txt = ""
        quietly replace gav_num_txt = string(abs_gav, "%4.2f") if !missing(abs_gav)
        quietly generate str4 star_txt = ""
        quietly replace star_txt = "***" if !missing(q) & q < .001
        quietly replace star_txt = "**" if !missing(q) & q < .01 & q >= .001
        quietly replace star_txt = "*" if !missing(q) & q < `alpha' & q >= .01
        quietly generate str16 gav_txt = gav_num_txt + star_txt if gav_num_txt != ""
        quietly generate str32 ci_txt = ""
        quietly replace ci_txt = "[" + string(abs_lb_gav, "%4.2f") + ", " + string(abs_ub_gav, "%4.2f") + "]" if !missing(lb_gav) & !missing(ub_gav)
        quietly count
        local item_digits = max(2, length(string(r(N))))
        local item_fmt "%0`item_digits'.0f"
        quietly generate str16 itemcode = "Item" + string(item_no, "`item_fmt'")
        quietly generate str244 displaylabel = rowlabel
        if `"`labelmode'"' == "item" {
            quietly replace displaylabel = itemcode
        }

        if `"`results'"' != "" {
            quietly save `"`results'"', replace
        }

        quietly keep if showrow
        quietly count
        local n_display = r(N)
        if `n_display' == 0 {
            di as err "no analyzable rows selected for display"
            restore
            exit 2000
        }

        quietly sort blockid item_no
        quietly save `"`tabledata'"', replace

        quietly generate int label_chars = ustrlen(displaylabel)
        quietly generate int block_chars = ustrlen(blocklabel)
        quietly generate int display_chars = max(label_chars, block_chars)
        quietly summarize display_chars
        local max_label_chars = r(max)
        quietly drop label_chars block_chars display_chars

        quietly levelsof blockid if blocklabel != "", local(blocks_shown)
        local nblocks_shown : word count `blocks_shown'
        local use_blocks = ((`"`blockfile'"' != "" | `"`blockfromlabel'"' != "" | `"`blockfromchar'"' != "") & (`nblocks_shown' > 1 | `"`showblock'"' != ""))

        local doc_font "Times New Roman"
        local doc_font_size = 10
        local sub1 = uchar(8321)
        local sub2 = uchar(8322)

        if `"`mapdoc'"' != "" {
            quietly use `"`tabledata'"', clear
            local map_rows = _N + 1
            quietly generate int map_item_chars = max(ustrlen(itemcode), ustrlen("Item"))
            quietly generate int map_var_chars = max(ustrlen(variable), ustrlen("Variable"))
            quietly generate int map_label_chars = max(ustrlen(rowlabel), ustrlen("Item label"))
            quietly generate int map_block_chars = max(ustrlen(blocklabel), ustrlen("Block"))
            quietly summarize map_item_chars
            local map_item_width = min(0.80, max(0.55, r(max) * 0.070 + 0.16))
            quietly summarize map_var_chars
            local map_var_width = min(1.20, max(0.75, r(max) * 0.065 + 0.18))
            quietly summarize map_label_chars
            local map_label_width = min(5.75, max(1.60, r(max) * 0.072 + 0.22))
            quietly summarize map_block_chars
            local map_block_width = min(2.35, max(1.10, r(max) * 0.072 + 0.22))
            quietly drop map_item_chars map_var_chars map_label_chars map_block_chars
            local map_no_width = 0.45
            local map_total_width = `map_no_width' + `map_item_width' + `map_var_width' + `map_label_width' + `map_block_width'
            local map_total_txt : display %6.3f `map_total_width'
            local map_total_txt = strtrim("`map_total_txt'") + "in"
            local map_item_txt : display %6.3f `map_item_width'
            local map_item_txt = strtrim("`map_item_txt'") + "in"
            local map_var_txt : display %6.3f `map_var_width'
            local map_var_txt = strtrim("`map_var_txt'") + "in"
            local map_label_txt : display %6.3f `map_label_width'
            local map_label_txt = strtrim("`map_label_txt'") + "in"
            local map_block_txt : display %6.3f `map_block_width'
            local map_block_txt = strtrim("`map_block_txt'") + "in"
            putdocx clear
            putdocx begin, pagesize(letter) landscape margin(left, .55) margin(right, .55) font("`doc_font'", 12)
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text ("Appendix A"), bold
            putdocx paragraph, spacing(before, 0pt) spacing(after, 4pt)
            putdocx text ("Item Labels and Subscale Mapping"), italic
            putdocx table maptbl = (`map_rows', 5), width(`map_total_txt') halign(left) ///
                border(all, nil) cellmargin(top, 2pt) cellmargin(bottom, 2pt) ///
                cellmargin(left, 2pt) cellmargin(right, 2pt)
            putdocx table maptbl(1,1) = ("No.")
            putdocx table maptbl(1,2) = ("Item")
            putdocx table maptbl(1,3) = ("Variable")
            putdocx table maptbl(1,4) = ("Item label")
            putdocx table maptbl(1,5) = ("Block")
            putdocx table maptbl(1,.), bold halign(center) border(top, single, black, 1.25pt) border(bottom, single, black, .5pt)
            forvalues i = 1/`=_N' {
                local r = `i' + 1
                putdocx table maptbl(`r',1) = (item_no[`i'])
                putdocx table maptbl(`r',2) = (itemcode[`i'])
                putdocx table maptbl(`r',3) = (variable[`i'])
                putdocx table maptbl(`r',4) = (rowlabel[`i'])
                putdocx table maptbl(`r',5) = (blocklabel[`i'])
            }
            putdocx table maptbl(`map_rows',.), border(bottom, single, black, 1.25pt)
            putdocx table maptbl(.,.), font("`doc_font'", 12) valign(top)
            putdocx table maptbl(2/`map_rows',1), halign(center)
            putdocx table maptbl(2/`map_rows',2), halign(center)
            putdocx table maptbl(2/`map_rows',3), halign(left)
            putdocx table maptbl(2/`map_rows',4), halign(left)
            putdocx table maptbl(2/`map_rows',5), halign(left)
            putdocx table maptbl(.,1), width(.45in)
            putdocx table maptbl(.,2), width(`map_item_txt')
            putdocx table maptbl(.,3), width(`map_var_txt')
            putdocx table maptbl(.,4), width(`map_label_txt')
            putdocx table maptbl(.,5), width(`map_block_txt')
            putdocx save `"`mapdoc'"', replace nomsg
            quietly use `"`tabledata'"', clear
        }

        if `"`excel'"' != "" {
            quietly putexcel set `"`excel'"', replace
            quietly putexcel A1 = (`"`tablenumber'"'), bold font("Times New Roman", 12)
            quietly putexcel A2 = (`"`title'"'), italic font("Times New Roman", 12)

            quietly putexcel A3 = ("Variable"), hcenter
            if `"`availablecase'"' == "" {
                quietly putexcel B3:C3 = (`"G`sub1' (n`sub1'=`group_N1')"'), merge hcenter border(bottom)
                quietly putexcel D3:E3 = (`"G`sub2' (n`sub2'=`group_N2')"'), merge hcenter border(bottom)
            }
            else {
                quietly putexcel B3:C3 = (`"G`sub1'"'), merge hcenter border(bottom)
                quietly putexcel D3:E3 = (`"G`sub2'"'), merge hcenter border(bottom)
            }
            quietly putexcel F3 = ("t"), italic hcenter
            quietly putexcel G3 = ("df"), italic hcenter
            quietly putexcel H3 = ("p"), italic hcenter
            quietly putexcel I3 = ("FDR q"), italic hcenter
            quietly putexcel J3 = ("Effect Size"), hcenter
            quietly putexcel K3 = ("95% CI"), hcenter

            quietly putexcel B4 = ("M"), italic hcenter
            quietly putexcel C4 = ("SD"), italic hcenter
            quietly putexcel D4 = ("M"), italic hcenter
            quietly putexcel E4 = ("SD"), italic hcenter
            quietly putexcel J4 = (`"G`sub1'-G`sub2'"'), hcenter

            quietly putexcel A3:K3, border(top) font("Times New Roman", 12)
            quietly putexcel A4:K4, border(bottom) font("Times New Roman", 12)

            local xrow = 4
            quietly use `"`tabledata'"', clear
            if `use_blocks' {
                foreach b of local blocks_shown {
                    local ++xrow
                    quietly levelsof blocklabel if blockid == `b', local(thisblock) clean
                    quietly putexcel A`xrow' = (`"`thisblock'"'), bold italic font("Times New Roman", 12)
                    forvalues i = 1/`=_N' {
                        if blockid[`i'] == `b' {
                            local ++xrow
                            local thislabel `"`=displaylabel[`i']'"'
                            quietly putexcel A`xrow' = (`"   `thislabel'"')
                            quietly putexcel B`xrow' = (mean_txt1[`i'])
                            quietly putexcel C`xrow' = (sd_txt1[`i'])
                            quietly putexcel D`xrow' = (mean_txt2[`i'])
                            quietly putexcel E`xrow' = (sd_txt2[`i'])
                            quietly putexcel F`xrow' = (t_txt[`i'])
                            quietly putexcel G`xrow' = (df_txt[`i'])
                            quietly putexcel H`xrow' = (p_txt[`i'])
                            quietly putexcel I`xrow' = (q_txt[`i'])
                            quietly putexcel J`xrow' = (gav_txt[`i'])
                            quietly putexcel K`xrow' = (ci_txt[`i'])
                            if `"`show'"' == "all" {
                                if !missing(q[`i']) & q[`i'] < `alpha' {
                                    quietly putexcel A`xrow':K`xrow', bold
                                }
                            }
                        }
                    }
                }
            }
            else {
                forvalues i = 1/`=_N' {
                local ++xrow
                local thislabel `"`=displaylabel[`i']'"'
                quietly putexcel A`xrow' = (`"`thislabel'"')
                quietly putexcel B`xrow' = (mean_txt1[`i'])
                quietly putexcel C`xrow' = (sd_txt1[`i'])
                quietly putexcel D`xrow' = (mean_txt2[`i'])
                quietly putexcel E`xrow' = (sd_txt2[`i'])
                quietly putexcel F`xrow' = (t_txt[`i'])
                quietly putexcel G`xrow' = (df_txt[`i'])
                quietly putexcel H`xrow' = (p_txt[`i'])
                quietly putexcel I`xrow' = (q_txt[`i'])
                quietly putexcel J`xrow' = (gav_txt[`i'])
                quietly putexcel K`xrow' = (ci_txt[`i'])
                if `"`show'"' == "all" {
                    if !missing(q[`i']) & q[`i'] < `alpha' {
                        quietly putexcel A`xrow':K`xrow', bold
                    }
                }
            }
        }

        local note_row = `xrow' + 1
        quietly putexcel A`note_row':K`note_row', border(top)
            quietly putexcel A`note_row' = ("Note. G1 = `group_name1'; G2 = `group_name2'. Effect sizes are absolute Hedges' g_av values for FDR-significant tests. CIs are approximate 95% confidence intervals for absolute Hedges' g_av. Signed effect sizes and signed CIs are saved in results().")
        quietly putexcel A1:K`note_row', font("Times New Roman", 12)
        quietly putexcel A5:A`xrow', left
        quietly putexcel B5:K`xrow', right
        quietly putexcel A1:K`note_row', txtwrap
            capture quietly _wtttable_xlsx_widths `"`excel'"'
            quietly use `"`tabledata'"', clear
        }

        local var_width_min = 1.250
        local var_width_max = 4.100
        local char_width = 0.070
        local var_padding = 0.200
        local var_width = min(`var_width_max', max(`var_width_min', (`max_label_chars' * `char_width') + `var_padding'))
        local mean_width = 0.430
        local sd_width = 0.520
        local stat_width = 0.420
        local df_width = 0.500
        local p_width = 0.420
        local q_width = 0.520
        local es_width = 0.620
        local ci_width = 0.980
        local gap_width = 0.045
        local width_total = `var_width' + 2*`mean_width' + 2*`sd_width' + 6*`gap_width' + `stat_width' + `df_width' + `p_width' + `q_width' + `es_width' + `ci_width'
        local width_total_txt : display %6.3f `width_total'
        local width_total_txt = strtrim("`width_total_txt'") + "in"

        local ncols = 16
        local header_rows = 2
        local note_rows = 1
        local nrows = `header_rows' + `n_display' + `note_rows'
        if `use_blocks' local nrows = `nrows' + `nblocks_shown'

        local var_col = 1
        local g1_m = 2
        local g1_sd = 3
        local gap1 = 4
        local g2_m = 5
        local g2_sd = 6
        local gap2 = 7
        local t_col = 8
        local df_col = 9
        local gap3 = 10
        local p_col = 11
        local gap4 = 12
        local q_col = 13
        local gap5 = 14
        local es_col = 15
        local ci_col = 16
        local gap_cols "`gap1' `gap2' `gap3' `gap4' `gap5'"

        putdocx clear
        putdocx begin, pagesize(letter) landscape margin(left, .55) margin(right, .55) font("`doc_font'", `doc_font_size')
        putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
        putdocx text (`"`tablenumber'"'), bold
        putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
        putdocx text (`"`title'"'), italic
        putdocx table owatbl = (`nrows', `ncols'), width(`width_total_txt') halign(left) ///
            border(all, nil) cellmargin(top, .5pt) cellmargin(bottom, 0pt) ///
            cellmargin(left, 2pt) cellmargin(right, 2pt)

        local c = 1
        foreach w in `var_width' `mean_width' `sd_width' `gap_width' `mean_width' `sd_width' `gap_width' `stat_width' `df_width' `gap_width' `p_width' `gap_width' `q_width' `gap_width' `es_width' `ci_width' {
            local cw : display %6.3f `w'
            local cw = strtrim("`cw'") + "in"
            putdocx table owatbl(.,`c'), width(`cw')
            local ++c
        }

        putdocx table owatbl(1,`var_col') = ("Variable")
        foreach c of local gap_cols {
            putdocx table owatbl(1,`c') = ("")
            putdocx table owatbl(2,`c') = ("")
            putdocx table owatbl(1,`c'), border(bottom, nil)
        }
        putdocx table owatbl(1,`t_col') = ("t")
        putdocx table owatbl(1,`t_col'), italic
        putdocx table owatbl(1,`df_col') = ("df")
        putdocx table owatbl(1,`df_col'), italic
        putdocx table owatbl(1,`p_col') = ("p")
        putdocx table owatbl(1,`p_col'), italic
        putdocx table owatbl(1,`q_col') = ("FDR q")
        putdocx table owatbl(1,`q_col'), italic
        putdocx table owatbl(1,`es_col') = ("Hedges' g")
        putdocx table owatbl(1,`ci_col') = ("95% CI")
        forvalues c = 1/`ncols' {
            putdocx table owatbl(1,`c'), border(bottom, nil)
        }

        if `"`availablecase'"' == "" {
            putdocx table owatbl(1,`g2_m'), colspan(2) halign(center) border(bottom, single, black, .5pt)
            putdocx table owatbl(1,`g2_m') = (`"G`sub2' (n`sub2'=`group_N2')"')
            putdocx table owatbl(1,`g1_m'), colspan(2) halign(center) border(bottom, single, black, .5pt)
            putdocx table owatbl(1,`g1_m') = (`"G`sub1' (n`sub1'=`group_N1')"')
        }
        else {
            putdocx table owatbl(1,`g2_m'), colspan(2) halign(center) border(bottom, single, black, .5pt)
            putdocx table owatbl(1,`g2_m') = ("G`sub2'")
            putdocx table owatbl(1,`g1_m'), colspan(2) halign(center) border(bottom, single, black, .5pt)
            putdocx table owatbl(1,`g1_m') = ("G`sub1'")
        }

        foreach c in `g1_m' `g2_m' {
            putdocx table owatbl(2,`c') = ("M")
            putdocx table owatbl(2,`c'), italic
        }
        foreach c in `g1_sd' `g2_sd' {
            putdocx table owatbl(2,`c') = ("SD")
            putdocx table owatbl(2,`c'), italic
        }
        foreach c in `var_col' `t_col' `df_col' `p_col' `q_col' `es_col' `ci_col' {
            putdocx table owatbl(2,`c') = ("")
        }
        putdocx table owatbl(2,`es_col') = ("")
        local row = `header_rows'
        local section_rows ""
        quietly use `"`tabledata'"', clear
        if `use_blocks' {
            foreach b of local blocks_shown {
                local ++row
                local section_rows `"`section_rows' `row'"'
                quietly levelsof blocklabel if blockid == `b', local(thisblock) clean
                putdocx table owatbl(`row',`var_col') = (`"`thisblock'"')
                forvalues c = 2/`ncols' {
                    putdocx table owatbl(`row',`c') = ("")
                }
                forvalues i = 1/`=_N' {
                    if blockid[`i'] == `b' {
                        local ++row
                        local thislabel `"`=displaylabel[`i']'"'
                        putdocx table owatbl(`row',`var_col') = (`"   `thislabel'"')
                        putdocx table owatbl(`row',`g1_m') = (mean_txt1[`i'])
                        putdocx table owatbl(`row',`g1_sd') = (sd_txt1[`i'])
                        putdocx table owatbl(`row',`g2_m') = (mean_txt2[`i'])
                        putdocx table owatbl(`row',`g2_sd') = (sd_txt2[`i'])
                        putdocx table owatbl(`row',`t_col') = (t_txt[`i'])
                        putdocx table owatbl(`row',`df_col') = (df_txt[`i'])
                        putdocx table owatbl(`row',`p_col') = (p_txt[`i'])
                        putdocx table owatbl(`row',`q_col') = (q_txt[`i'])
                        putdocx table owatbl(`row',`es_col') = (gav_txt[`i'])
                        putdocx table owatbl(`row',`ci_col') = (ci_txt[`i'])
                        if `"`show'"' == "all" {
                            if !missing(q[`i']) & q[`i'] < `alpha' {
                                putdocx table owatbl(`row',.), bold
                            }
                        }
                        foreach c of local gap_cols {
                            putdocx table owatbl(`row',`c') = ("")
                        }
                    }
                }
            }
        }
        else {
            forvalues i = 1/`=_N' {
                local ++row
                local thislabel `"`=displaylabel[`i']'"'
                putdocx table owatbl(`row',`var_col') = (`"`thislabel'"')
                putdocx table owatbl(`row',`g1_m') = (mean_txt1[`i'])
                putdocx table owatbl(`row',`g1_sd') = (sd_txt1[`i'])
                putdocx table owatbl(`row',`g2_m') = (mean_txt2[`i'])
                putdocx table owatbl(`row',`g2_sd') = (sd_txt2[`i'])
                putdocx table owatbl(`row',`t_col') = (t_txt[`i'])
                putdocx table owatbl(`row',`df_col') = (df_txt[`i'])
                putdocx table owatbl(`row',`p_col') = (p_txt[`i'])
                putdocx table owatbl(`row',`q_col') = (q_txt[`i'])
                putdocx table owatbl(`row',`es_col') = (gav_txt[`i'])
                putdocx table owatbl(`row',`ci_col') = (ci_txt[`i'])
                if `"`show'"' == "all" {
                    if !missing(q[`i']) & q[`i'] < `alpha' {
                        putdocx table owatbl(`row',.), bold
                    }
                }
                foreach c of local gap_cols {
                    putdocx table owatbl(`row',`c') = ("")
                }
            }
        }

        local note_row = `nrows'
        putdocx table owatbl(`note_row',1), colspan(`ncols') halign(left) valign(top) border(top, single, black, 1.25pt)
        putdocx table owatbl(`note_row',1) = ("Note. "), italic
        putdocx table owatbl(`note_row',1) = ("G"), append
        putdocx table owatbl(`note_row',1) = ("1"), append script(sub)
        putdocx table owatbl(`note_row',1) = (`" = `group_name1'; "'), append
        putdocx table owatbl(`note_row',1) = ("G"), append
        putdocx table owatbl(`note_row',1) = ("2"), append script(sub)
        putdocx table owatbl(`note_row',1) = (`" = `group_name2'. *"'), append
        putdocx table owatbl(`note_row',1) = ("p"), append italic
        putdocx table owatbl(`note_row',1) = (" < .05. **"), append
        putdocx table owatbl(`note_row',1) = ("p"), append italic
        putdocx table owatbl(`note_row',1) = (" < .01. ***"), append
        putdocx table owatbl(`note_row',1) = ("p"), append italic
        putdocx table owatbl(`note_row',1) = (" < .001."), append
        if `"`note'"' != "" putdocx table owatbl(`note_row',1) = (`" `note'"'), append

        putdocx table owatbl(.,.), font("`doc_font'", `doc_font_size') valign(center)
        putdocx table owatbl(1/2,.), halign(center)
        putdocx table owatbl(1,`g1_m'), halign(center)
        putdocx table owatbl(1,`g2_m'), halign(center)
        putdocx table owatbl(2,`g1_m'), halign(center)
        putdocx table owatbl(2,`g1_sd'), halign(center)
        putdocx table owatbl(2,`g2_m'), halign(center)
        putdocx table owatbl(2,`g2_sd'), halign(center)
        putdocx table owatbl(2,`es_col'), halign(center)
        putdocx table owatbl(1,`ci_col'), halign(center)

        putdocx table owatbl(1,.), border(top, single, black, 1.25pt)
        putdocx table owatbl(2,.), border(bottom, single, black, .5pt)

        putdocx table owatbl(3/`=`nrows'-1',1), halign(left)
        foreach sr of local section_rows {
            putdocx table owatbl(`sr',1), bold italic halign(left)
        }
        putdocx table owatbl(3/`=`nrows'-1',`g1_m'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`g1_sd'), halign(left)
        putdocx table owatbl(3/`=`nrows'-1',`g2_m'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`g2_sd'), halign(left)
        putdocx table owatbl(3/`=`nrows'-1',`t_col'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`df_col'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`p_col'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`q_col'), halign(right)
        putdocx table owatbl(3/`=`nrows'-1',`es_col'), halign(left)
        putdocx table owatbl(3/`=`nrows'-1',`ci_col'), halign(center)
        putdocx table owatbl(`note_row',1), halign(left)

        putdocx save `"`saving'"', replace nomsg

        di as txt "wttreport table step complete"
        di as txt "Complete-case sample: " as result `sample_N'
        if `"`availablecase'"' == "" {
            di as txt "Group sizes: " as result "G1=`group_N1', G2=`group_N2'"
        }
        di as txt "Word table saved to:"
        di as result `"  {browse `saving'}"'
        if `"`excel'"' != "" {
            di as txt "Excel results saved to:"
            di as result `"  {browse `excel'}"'
        }
        if `"`mapdoc'"' != "" {
            di as txt "Mapping document saved to:"
            di as result `"  {browse `mapdoc'}"'
        }

        return scalar N = `sample_N'
        if `"`availablecase'"' == "" {
            return scalar N_g1 = `group_N1'
            return scalar N_g2 = `group_N2'
        }
        return local saving `"`saving'"'
        if `"`excel'"' != "" return local excel `"`excel'"'
        if `"`mapdoc'"' != "" return local mapdoc `"`mapdoc'"'
    restore
end

program define _wtttable_xlsx_widths
    version 19.5
    args xlsx
    mata: _wtttable_xlsx_widths_mata(`"`xlsx'"')
end

mata:
void _wtttable_xlsx_widths_mata(string scalar xlsx)
{
    class xl scalar B
    B = xl()
    B.load_book(xlsx)
    B.set_sheet("Sheet1")
    B.set_column_width(1, 1, 36)
    B.set_column_width(2, 2, 10)
    B.set_column_width(3, 3, 12)
    B.set_column_width(4, 4, 10)
    B.set_column_width(5, 5, 12)
    B.set_column_width(6, 6, 9)
    B.set_column_width(7, 7, 9)
    B.set_column_width(8, 8, 9)
    B.set_column_width(9, 9, 10)
    B.set_column_width(10, 10, 20)
    B.set_column_width(11, 11, 22)
    B.close_book()
}
end


program define _wttreport_plot, rclass
    version 19.5

    syntax varlist(numeric min=1) [if] [in], ///
        BY(varname) GRAPHDIR(string) ///
        [ REPLACE ALPHA(real 0.05) ///
          BLOCKFILE(string) BLOCKFROMLABEL BLOCKFROMCHAR ///
          SHOW(string) AVAILABLECASE ///
          MINCELL(integer 2) ///
          GRAPHBY(string) COMBINE(integer 1) COLumns(integer 0) LAYOUT(string) ///
          LABELMODE(string) MAPFILE(string) ///
          FORMATS(string) ///
          ORIENTation(string) PNGWidth(integer 3200) ///
          RESULTS(string) ///
          TITLE(string) XTITLE(string) NOTE(string) ///
          TITLESIZE(string) BLOCKSIZE(string) ///
          LABELSIZE(string) XLABSIZE(string) XTITLESIZE(string) NOTESIZE(string) ]

    if `alpha' <= 0 | `alpha' >= 1 {
        di as err "alpha() must be strictly between 0 and 1"
        exit 198
    }
    if `mincell' < 2 {
        di as err "mincell() must be at least 2"
        exit 198
    }

    local show = lower(strtrim(`"`show'"'))
    if `"`show'"' == "" local show "significant"
    if !inlist(`"`show'"', "significant", "all") {
        di as err "invalid display option"
        exit 198
    }

    local graphby = lower(strtrim(`"`graphby'"'))
    if `"`graphby'"' == "" local graphby "block"
    if !inlist(`"`graphby'"', "block", "all") {
        di as err "graphby() must be block or all"
        exit 198
    }
    if `combine' > 1 & `"`graphby'"' == "all" {
        di as err "combine() may not be combined with graphby(all)"
        exit 198
    }
    if `combine' < 1 | `combine' > 6 {
        di as err "combine() must be between 1 and 6"
        exit 198
    }
    if `columns' < 0 | `columns' > 4 {
        di as err "columns() must be between 0 and 4"
        exit 198
    }
    local layout = lower(strtrim(`"`layout'"'))
    if `"`layout'"' == "" local layout "vertical"
    if !inlist(`"`layout'"', "auto", "horizontal", "vertical") {
        di as err "layout() must be auto, horizontal, or vertical"
        exit 198
    }

    local labelmode = lower(strtrim(`"`labelmode'"'))
    if `"`labelmode'"' == "" {
        if `combine' > 1 & `"`layout'"' == "vertical" local labelmode "item"
        else local labelmode "full"
    }
    if !inlist(`"`labelmode'"', "full", "item", "varname") {
        di as err "labelmode() must be full, item, or varname"
        exit 198
    }

    local formats = lower(strtrim(`"`formats'"'))
    if `"`formats'"' == "" local formats "png"
    foreach fmt of local formats {
        if !inlist(`"`fmt'"', "pdf", "png") {
            di as err "formats() may contain only pdf and/or png"
            exit 198
        }
    }

    local orientation = lower(strtrim(`"`orientation'"'))
    if `"`orientation'"' == "" local orientation "auto"
    if !inlist(`"`orientation'"', "landscape", "portrait", "auto") {
        di as err "orientation() must be landscape, portrait, or auto"
        exit 198
    }

    if `pngwidth' < 1200 {
        di as err "pngwidth() must be at least 1200"
        exit 198
    }

    if `"`title'"' == "" local title "Two-Group Effect-Size Comparisons"
    if `"`xtitle'"' == "" local xtitle "Signed Hedges' {it:g}{sub:av}"
    local title_line1 `"`title'"'
    local title_line2 ""
    local __title_sep = strpos(`"`title'"', "||")
    if `__title_sep' > 0 {
        local title_line1 = substr(`"`title'"', 1, `__title_sep' - 1)
        local title_line2 = substr(`"`title'"', `__title_sep' + 2, .)
    }
    local graph_title `"`"`title_line1'"'"'
    if `"`title_line2'"' != "" {
        local graph_title `"`"`title_line1'"' `"{it:`title_line2'}"'"'
    }
    local graph_title_main `"`title_line1'"'
    local graph_title_sub ""
    if `"`title_line2'"' != "" {
        local graph_title_sub `"{it:`title_line2'}"'
    }
    if `"`titlesize'"' == "" local titlesize "medsmall"
    if `"`blocksize'"' == "" local blocksize "medsmall"
    if `"`labelsize'"' == "" local labelsize "small"
    if `"`xlabsize'"' == "" local xlabsize "small"
    if `"`xtitlesize'"' == "" local xtitlesize "small"
    if `"`notesize'"' == "" local notesize "vsmall"
    local legendopt "legend(off)"
    if `"`show'"' == "all" {
        local legendopt `"legend(order(3 "FDR-significant" 2 "Not FDR-significant") rows(1) size(vsmall) position(6) ring(1) region(lstyle(none)))"'
    }
    local usernote `"`note'"'

    local n_block_sources = (`"`blockfile'"' != "") + (`"`blockfromlabel'"' != "") + (`"`blockfromchar'"' != "")
    if `n_block_sources' > 1 {
        di as err "only one of blockfile(), blockfromlabel, or blockfromchar may be specified"
        exit 198
    }

    capture mkdir `"`graphdir'"'
    capture confirm file `"`graphdir'"'

    if `"`results'"' != "" {
        capture confirm new file `"`results'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `results' already exists; specify replace"'
            exit 602
        }
    }
    if `"`mapfile'"' != "" {
        capture confirm new file `"`mapfile'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `mapfile' already exists; specify replace"'
            exit 602
        }
    }

    marksample touse, novarlist
    markout `touse' `by', strok
    if `"`availablecase'"' == "" markout `touse' `varlist'

    quietly count if `touse'
    if r(N) == 0 {
        di as err "no observations in the analysis sample"
        exit 2000
    }

    preserve
        keep if `touse'

        tempvar gid
        quietly egen `gid' = group(`by') if !missing(`by'), label
        quietly levelsof `gid', local(gids)
        local ngroups : word count `gids'
        if `ngroups' != 2 {
            di as err "by() must identify exactly two observed groups in the analysis sample"
            restore
            exit 198
        }
        local g1 : word 1 of `gids'
        local g2 : word 2 of `gids'

        quietly levelsof `by' if `gid' == `g1', local(orig1) clean
        quietly levelsof `by' if `gid' == `g2', local(orig2) clean
        local group_name1 "`orig1'"
        local group_name2 "`orig2'"
        capture confirm numeric variable `by'
        if !_rc {
            local vallab : value label `by'
            if `"`vallab'"' != "" {
                local first1 : word 1 of `orig1'
                local first2 : word 1 of `orig2'
                local lab1 : label `vallab' `first1'
                local lab2 : label `vallab' `first2'
                if `"`lab1'"' != "" local group_name1 `"`lab1'"'
                if `"`lab2'"' != "" local group_name2 `"`lab2'"'
            }
        }

        if `"`usernote'"' == "" {
            local g1note = lower(`"`group_name1'"')
            local g2note = lower(`"`group_name2'"')
            local note1 `"{it:Note.} Positive values indicate that the `g1note' mean is greater than the `g2note' mean; negative values indicate the reverse."'
            local note2 `"Bars show approximate `=100*(1-`alpha')'% CIs for signed Hedges' {it:g}{sub:av}."'
            if `"`show'"' == "all" {
                local note2 `"`note2' Items are displayed regardless of FDR-adjusted statistical significance."'
            }
            else {
                local note2 `"`note2' Only items with statistically significant FDR-adjusted {it:q} values are displayed."'
            }
            local note3 ""
        }
        else {
            local note1 `"{it:Note.} `usernote'"'
            local note2 ""
            local note3 ""
        }

        tempfile blockmapclean rawresults prefdr fdrvalues plotdata
        tempname rawpost

        if `"`blockfile'"' != "" {
            capture confirm file `"`blockfile'"'
            if _rc {
                di as err `"blockfile() not found: `blockfile'"'
                restore
                exit 601
            }
            preserve
                quietly use `"`blockfile'"', clear
                foreach needed in varname blockid blocklabel {
                    capture confirm variable `needed'
                    if _rc {
                        di as err "blockfile() must contain variable `needed'"
                        restore
                        restore
                        exit 111
                    }
                }
                capture confirm string variable varname
                if _rc {
                    di as err "varname in blockfile() must be a string variable"
                    restore
                    restore
                    exit 109
                }
                capture confirm string variable blocklabel
                if _rc {
                    di as err "blocklabel in blockfile() must be a string variable"
                    restore
                    restore
                    exit 109
                }
                keep varname blockid blocklabel
                quietly replace varname = strtrim(varname)
                quietly replace blocklabel = strtrim(blocklabel)
                quietly count if missing(varname) | missing(blockid) | missing(blocklabel)
                if r(N) > 0 {
                    di as err "blockfile() contains missing varname, blockid, or blocklabel"
                    restore
                    restore
                    exit 459
                }
                quietly save `"`blockmapclean'"', replace
            restore
        }

        quietly postfile `rawpost' int item_no ///
            str32 variable str32 label_blockcode str244 label_blocklabel str244 rowlabel ///
            str80 group1 str80 group2 ///
            double n1 mean1 sd1 n2 mean2 sd2 t df p gav se_gav lb_gav ub_gav ///
            using `"`rawresults'"', replace

        local item = 0
        foreach y of varlist `varlist' {
            local ++item
            local ylab : variable label `y'
            local rowlab `"`ylab'"'
            if `"`rowlab'"' == "" local rowlab "`y'"
            local label_blockcode ""
            local label_blocklabel ""

            if `"`blockfromchar'"' != "" {
                local label_blockcode : char `y'[owatable_blockid]
                local label_blocklabel : char `y'[owatable_blocklabel]
                local char_rowlab : char `y'[owatable_label]
                local label_blockcode = strtrim(`"`label_blockcode'"')
                local label_blocklabel = strtrim(`"`label_blocklabel'"')
                if `"`ylab'"' == "" & `"`char_rowlab'"' != "" local rowlab `"`char_rowlab'"'
                if `"`label_blockcode'"' == "" | `"`label_blocklabel'"' == "" {
                    di as err "blockfromchar requires variable characteristics:"
                    di as err `"char `y'[owatable_blockid] "B01""'
                    di as err `"char `y'[owatable_blocklabel] "Block label""'
                    restore
                    exit 198
                }
            }
            else if `"`blockfromlabel'"' != "" {
                local closepos = strpos(`"`ylab'"', "]")
                local pipepos = strpos(`"`ylab'"', "|")
                if substr(`"`ylab'"', 1, 1) == "[" & `closepos' > 0 & `pipepos' > 0 & `pipepos' < `closepos' {
                    local label_blockcode = strtrim(substr(`"`ylab'"', 2, `pipepos' - 2))
                    local label_blocklabel = strtrim(substr(`"`ylab'"', `pipepos' + 1, `closepos' - `pipepos' - 1))
                    local rowlab = strtrim(substr(`"`ylab'"', `closepos' + 1, .))
                    if `"`rowlab'"' == "" local rowlab "`y'"
                }
                else {
                    di as err "blockfromlabel requires variable labels to follow:"
                    di as err "[block_id | block_label] display_label"
                    di as err "variable `y' has label: `ylab'"
                    restore
                    exit 198
                }
            }

            quietly summarize `y' if `gid' == `g1'
            local n1 = r(N)
            local mean1 = r(mean)
            local sd1 = r(sd)
            quietly summarize `y' if `gid' == `g2'
            local n2 = r(N)
            local mean2 = r(mean)
            local sd2 = r(sd)

            local t = .
            local df = .
            local p = .
            local gav = .
            local se_gav = .
            local lb_gav = .
            local ub_gav = .
            if `n1' >= `mincell' & `n2' >= `mincell' & `sd1' > 0 & `sd2' > 0 {
                local v1 = `sd1'^2
                local v2 = `sd2'^2
                local se = sqrt(`v1'/`n1' + `v2'/`n2')
                local t = (`mean1' - `mean2') / `se'
                local df = (`v1'/`n1' + `v2'/`n2')^2 / ((`v1'/`n1')^2/(`n1'-1) + (`v2'/`n2')^2/(`n2'-1))
                local p = 2 * ttail(`df', abs(`t'))
                local sdav = sqrt((`v1' + `v2') / 2)
                local esdf = `n1' + `n2' - 2
                local J = 1 - 3/(4 * `esdf' - 1)
                local gav = `J' * ((`mean1' - `mean2') / `sdav')
                local se_gav = sqrt((`n1' + `n2') / (`n1' * `n2') + (`gav'^2) / (2 * (`n1' + `n2' - 2)))
                local zcrit = invnormal(1 - `alpha'/2)
                local lb_gav = `gav' - `zcrit' * `se_gav'
                local ub_gav = `gav' + `zcrit' * `se_gav'
            }

            post `rawpost' (`item') (`"`y'"') (`"`label_blockcode'"') (`"`label_blocklabel'"') ///
                (`"`rowlab'"') (`"`group_name1'"') (`"`group_name2'"') ///
                (`n1') (`mean1') (`sd1') (`n2') (`mean2') (`sd2') ///
                (`t') (`df') (`p') (`gav') (`se_gav') (`lb_gav') (`ub_gav')
        }
        quietly postclose `rawpost'

        quietly use `"`rawresults'"', clear

        if `"`blockfile'"' != "" {
            quietly drop label_blockcode label_blocklabel
            quietly merge 1:1 variable using `"`blockmapclean'"', keep(master match)
            quietly count if _merge == 1
            if r(N) > 0 {
                di as err "blockfile() does not map all variables in varlist"
                restore
                exit 459
            }
            quietly drop _merge
            capture confirm numeric variable blockid
            if _rc quietly encode blockid, gen(blockid_num)
            else quietly generate double blockid_num = blockid
            quietly drop blockid
            quietly rename blockid_num blockid
            quietly generate str32 blockcode = string(blockid)
        }
        else if `"`blockfromlabel'"' != "" | `"`blockfromchar'"' != "" {
            quietly generate str32 blockcode = label_blockcode
            quietly generate str244 blocklabel = label_blocklabel
            quietly count if missing(blockcode) | missing(blocklabel)
            if r(N) > 0 {
                di as err "could not parse block information for all variables"
                restore
                exit 198
            }
            capture destring blockcode, generate(blockid) ignore("B b _-") force
            quietly count if missing(blockid)
            if r(N) > 0 {
                quietly encode blockcode, generate(blockid2)
                quietly drop blockid
                quietly rename blockid2 blockid
            }
            quietly drop label_blockcode label_blocklabel
        }
        else {
            quietly generate double blockid = 1
            quietly generate str32 blockcode = "B01"
            quietly generate str244 blocklabel = "All outcomes"
            quietly drop label_blockcode label_blocklabel
        }

        quietly generate long result_id = _n
        quietly save `"`prefdr'"', replace

        quietly keep result_id p
        quietly keep if !missing(p)
        quietly sort p result_id
        quietly generate long fdr_rank = _n
        quietly count
        quietly generate long fdr_m = r(N)
        quietly generate double q = p * fdr_m / fdr_rank
        quietly gsort -fdr_rank
        quietly replace q = min(q, q[_n-1]) if _n > 1
        quietly replace q = min(q, 1)
        quietly keep result_id q
        quietly save `"`fdrvalues'"', replace

        quietly use `"`prefdr'"', clear
        quietly merge 1:1 result_id using `"`fdrvalues'"', nogen
        quietly generate byte fdr_sig = !missing(q) & q < `alpha'
        quietly sort blockid item_no

        if `"`results'"' != "" {
            quietly save `"`results'"', replace
        }
        quietly save `"`plotdata'"', replace

        if `"`mapfile'"' != "" {
            quietly keep if !missing(gav)
            if `"`show'"' == "significant" quietly keep if fdr_sig
            quietly sort blockid gav item_no
            quietly generate long No = _n
            quietly generate str32 Item = variable
            quietly replace Item = "item" + string(real(substr(variable, 5, .)), "%02.0f") if regexm(variable, "^item[0-9]+$")
            quietly generate str244 Item_label = rowlabel
            quietly generate str244 Block = blocklabel
            quietly keep No Item Item_label Block
            quietly label variable No "No."
            quietly label variable Item "Item"
            quietly label variable Item_label "Item label"
            quietly label variable Block "Block"
            tempvar maplen
            quietly generate double `maplen' = length(Item)
            quietly summarize `maplen', meanonly
            local w_item = min(18, max(length("Item"), r(max)) + 1)
            quietly replace `maplen' = length(Item_label)
            quietly summarize `maplen', meanonly
            local w_label = min(80, max(length("Item label"), r(max)) + 1)
            quietly replace `maplen' = length(Block)
            quietly summarize `maplen', meanonly
            local w_block = min(40, max(length("Block"), r(max)) + 1)
            quietly count
            local maprows = r(N) + 1
            local maxno = r(N)
            local w_no = min(8, max(length("No."), length("`maxno'")) + 1)
            quietly drop `maplen'
            quietly export excel using `"`mapfile'"', firstrow(varlabels) replace
            putexcel set `"`mapfile'"', modify
            quietly putexcel A1:D`maprows', font("Times New Roman", 12)
            quietly putexcel A1:D1, bold hcenter font("Times New Roman", 12)
            capture noisily _wttplot_xlsx_widths `"`mapfile'"' `w_no' `w_item' `w_label' `w_block'
            quietly use `"`plotdata'"', clear
        }

        quietly count if missing(gav)
        if r(N) > 0 {
            di as txt "warning: one or more outcomes had too few observations or zero variance; effect sizes were not plotted for those rows"
        }

        if `"`graphby'"' == "all" {
            quietly generate double plotblock = 1
            local blocks "1"
        }
        else {
            quietly generate double plotblock = blockid
            quietly levelsof plotblock, local(blocks)
        }

        local nblocks_total : word count `blocks'
        if 1 {
            local effective_panels = `combine'
            quietly use `"`plotdata'"', clear
            quietly keep if !missing(gav)
            if `"`show'"' == "significant" quietly keep if fdr_sig
            quietly generate double rowlabel_len = ustrlen(rowlabel)
            quietly summarize rowlabel_len
            local combine_labwidth = r(max)
            quietly summarize lb_gav
            local panel_xmin = min(r(min), 0)
            quietly summarize ub_gav
            local panel_xmax = max(r(max), 0)
            local panel_xpad = (`panel_xmax' - `panel_xmin') * .10
            if `panel_xpad' <= 0 | missing(`panel_xpad') local panel_xpad = .25
            local panel_xmin = `panel_xmin' - `panel_xpad'
            local panel_xmax = `panel_xmax' + `panel_xpad'
            local panel_xabs = max(abs(`panel_xmin'), abs(`panel_xmax'))
            if `panel_xabs' <= .8 {
                local panel_xstep = .2
            }
            else if `panel_xabs' <= 1.5 {
                local panel_xstep = .5
            }
            else {
                local panel_xstep = 1
            }
            local panel_xbound = ceil(`panel_xabs' / `panel_xstep') * `panel_xstep'
            if `panel_xbound' <= 0 | missing(`panel_xbound') local panel_xbound = .5
            local panel_xmin = -`panel_xbound'
            local panel_xmax = `panel_xbound'
            local panel_xmin_txt : display %5.2f `panel_xmin'
            local panel_xmax_txt : display %5.2f `panel_xmax'
            local panel_xstep_txt : display %5.2f `panel_xstep'
            local panel_xticks `"`panel_xmin_txt'(`panel_xstep_txt')`panel_xmax_txt'"'
            if `columns' > 0 {
                local panel_cols = `columns'
            }
            else if `"`layout'"' == "vertical" {
                local panel_cols = 1
            }
            else if `"`layout'"' == "horizontal" {
                local panel_cols = `effective_panels'
            }
            else if `effective_panels' <= 3 {
                local panel_cols = `effective_panels'
            }
            else {
                local panel_cols = 2
            }
            local panel_page = 1
            local panel_count = 0
            local panel_graphs ""
        }

        local exported ""
        local graphcount = 0
        local outcount = 0
        local blocknum = 0
        if `combine' > 1 & `"`layout'"' == "vertical" {
            local panel_page = 1
            while `blocknum' < `nblocks_total' {
                local page_blocks ""
                local panel_count = 0
                while `panel_count' < `combine' & `blocknum' < `nblocks_total' {
                    local ++blocknum
                    local b : word `blocknum' of `blocks'
                    local page_blocks `"`page_blocks' `b'"'
                    local ++panel_count
                }

                local page_title_max = 0
                quietly use `"`plotdata'"', clear
                foreach pb of local page_blocks {
                    quietly levelsof blocklabel if blockid == `pb', local(__page_blocktitle) clean
                    local __page_title_len = ustrlen(`"`__page_blocktitle'"')
                    if `__page_title_len' > `page_title_max' local page_title_max = `__page_title_len'
                }
                if `page_title_max' < 10 local page_title_max = 10

                local left_blocks ""
                local right_blocks ""
                local split = ceil(`panel_count' / 2)
                local j = 0
                foreach pb of local page_blocks {
                    local ++j
                    if `j' <= `split' local left_blocks `"`left_blocks' `pb'"'
                    else local right_blocks `"`right_blocks' `pb'"'
                }

                local vstack_graphs ""
                forvalues side = 1/2 {
                    if `side' == 1 local side_blocks `"`left_blocks'"'
                    else local side_blocks `"`right_blocks'"'
                    if `"`side_blocks'"' == "" continue

                    quietly use `"`plotdata'"', clear
                    quietly keep if !missing(gav)
                    if `"`show'"' == "significant" quietly keep if fdr_sig
                    quietly generate byte __sidekeep = 0
                    foreach pb of local side_blocks {
                        quietly replace __sidekeep = 1 if blockid == `pb'
                    }
                    quietly keep if __sidekeep
                    quietly drop __sidekeep
                    quietly count
                    if r(N) == 0 continue

                    local ++graphcount
                    quietly sort blockid gav item_no
                    quietly generate double yaxis = .
                    local ylabels ""
                    local y = 0
                    foreach pb of local side_blocks {
                        quietly count if blockid == `pb'
                        if r(N) == 0 continue
                        quietly levelsof blocklabel if blockid == `pb', local(blocktitle) clean
                        local __blocktitle_len = ustrlen(`"`blocktitle'"')
                        local __blocktitle_pad = `page_title_max' - `__blocktitle_len'
                        if `__blocktitle_pad' < 0 local __blocktitle_pad = 0
                        local __blocktitle_lab `"{bf:`blocktitle'}{space `__blocktitle_pad'}"'
                        local ++y
                        local ylabels `"`ylabels' `y' `"`__blocktitle_lab'"'"'
                        local ++y
                        quietly count
                        local nobs = r(N)
                        forvalues i = 1/`nobs' {
                            if blockid[`i'] == `pb' {
                                local ++y
                                quietly replace yaxis = `y' in `i'
                                if `"`labelmode'"' == "full" {
                                    local lab = rowlabel[`i']
                                }
                                else if `"`labelmode'"' == "varname" {
                                    local lab = variable[`i']
                                }
                                else {
                                    local lab = "Item " + string(item_no[`i'], "%02.0f")
                                }
                                local ylabels `"`ylabels' `y' `"`lab'"'"'
                            }
                        }
                        local y = `y' + 2
                    }
                    local ymax = `y'
                    local graphname "wttplot_vstack_`panel_page'_`side'"
                    local thislegend "legend(off)"
                    if 0 & `"`show'"' == "all" & `side' == 2 {
                        local thislegend `"legend(order(3 "FDR Significant" 2 "Non-FDR Significant") rows(2) size(vsmall) position(8) ring(0) region(lstyle(none)))"'
                    }

                    twoway ///
                        (rcap lb_gav ub_gav yaxis if !missing(yaxis), horizontal lcolor(gs7) lwidth(medthin)) ///
                        (scatter yaxis gav if !missing(yaxis) & fdr_sig == 0, msymbol(D) mfcolor(white) mlcolor(gs8) msize(small)) ///
                        (scatter yaxis gav if !missing(yaxis) & fdr_sig == 1, msymbol(O) mcolor(black) msize(small)), ///
                        yscale(reverse range(.5 `ymax')) ///
                        ylabel(`ylabels', angle(0) labsize(`labelsize') noticks nogrid) ///
                        xlabel(`panel_xticks', labsize(`xlabsize') nogrid) ///
                        xline(0, lcolor(gs10) lwidth(thin)) ///
                        xscale(range(`panel_xmin' `panel_xmax')) ///
                        xtitle("") ///
                        ytitle("") ///
                        `thislegend' ///
                        graphregion(color(white)) plotregion(color(white)) ///
                        name(`graphname', replace) ///
                        xsize(6.10) ysize(7.20) nodraw
                    local vstack_graphs `"`vstack_graphs' `graphname'"'
                }

                if `"`vstack_graphs'"' == "" continue
                local page_suffix : display %02.0f `panel_page'
                local vstack_xtitle "{space 14}`xtitle'"
                if `"`show'"' == "all" {
                    local vstack_xtitle `"`"● FDR-significant"' `"◇ Not FDR-significant"'"'
                }
                if `"`show'"' == "all" {
                    local vstack_xtitle `"`"● FDR Significant"' `"◇ Non- FDR Significant"'"'
                }
                if `"`show'"' == "all" {
                    local vstack_xtitle `"`"{space 20}● FDR Significant"' `"{space 20}◇ Non- FDR Significant"'"'
                }
                if `"`show'"' == "all" {
                    local vstack_xtitle " "
                }
                if `"`show'"' == "all" {
                    local vstack_xtitle `"`"● FDR Significant"' `"◇ Non-FDR Significant"'"'
                }
                graph combine `vstack_graphs', col(2) xcommon imargin(zero) ///
                    title(`graph_title', size(`titlesize') margin(small) justification(left) linegap(1.5)) ///
                    b1title(`vstack_xtitle', size(vsmall)) ///
                    note(`"`note1'"' `"`note2'"' `"`note3'"', size(`notesize') margin(medsmall)) ///
                    graphregion(color(white) margin(zero)) ///
                    name(wttplot_vstack, replace) ///
                    xsize(12.20) ysize(9.40)
                foreach fmt of local formats {
                    local outfile `"`graphdir'/combined_`page_suffix'.`fmt'"'
                    capture confirm new file `"`outfile'"'
                    if _rc & `"`replace'"' == "" {
                        di as err `"file `outfile' already exists; specify replace"'
                        restore
                        exit 602
                    }
                    graph display wttplot_vstack
                    if `"`fmt'"' == "png" {
                        quietly graph export `"`outfile'"', width(`pngwidth') replace
                    }
                    else {
                        quietly graph export `"`outfile'"', as(pdf) replace
                    }
                    local exported `"`exported' `"`outfile'"'"'
                }
                capture graph drop wttplot_vstack
                capture graph drop `vstack_graphs'
                local ++outcount
                local ++panel_page
            }
        }
        else if 0 {
            local panel_page = 1
            while `blocknum' < `nblocks_total' {
                local page_blocks ""
                local panel_count = 0
                while `panel_count' < `combine' & `blocknum' < `nblocks_total' {
                    local ++blocknum
                    local b : word `blocknum' of `blocks'
                    local page_blocks `"`page_blocks' `b'"'
                    local ++panel_count
                }

                quietly use `"`plotdata'"', clear
                quietly keep if !missing(gav)
                if `"`show'"' == "significant" quietly keep if fdr_sig
                quietly generate byte __pagekeep = 0
                foreach pb of local page_blocks {
                    quietly replace __pagekeep = 1 if blockid == `pb'
                }
                quietly keep if __pagekeep
                quietly drop __pagekeep
                quietly count
                if r(N) == 0 continue

                local ++graphcount
                quietly sort blockid gav item_no
                quietly generate double yaxis = .
                local ylabels ""
                local y = 0
                foreach pb of local page_blocks {
                    quietly count if blockid == `pb'
                    if r(N) == 0 continue
                    quietly levelsof blocklabel if blockid == `pb', local(blocktitle) clean
                    local ++y
                    local ylabels `"`ylabels' `y' `"{bf:`blocktitle'}"'"'
                    quietly count
                    local nobs = r(N)
                    forvalues i = 1/`nobs' {
                        if blockid[`i'] == `pb' {
                            local ++y
                            quietly replace yaxis = `y' in `i'
                            if `"`labelmode'"' == "item" {
                                local lab = "Item " + string(item_no[`i'], "%02.0f")
                            }
                            else if `"`labelmode'"' == "varname" {
                                local lab = variable[`i']
                            }
                            else {
                                local lab = rowlabel[`i']
                            }
                            local ylabels `"`ylabels' `y' `"{space 4}`lab'"'"'
                        }
                    }
                    local ++y
                }
                local ymax = `y'
                quietly count if !missing(yaxis)
                local nplot = r(N)
                local height = max(5.20, min(8.20, 1.60 + .17 * `ymax'))
                local gx = 11.20
                local gxtxt : display %4.2f `gx'
                local heighttxt : display %4.2f `height'
                local page_suffix : display %02.0f `panel_page'
                local vert_labelsize `"`labelsize'"'
                if `"`labelsize'"' == "small" local vert_labelsize "vsmall"

                twoway ///
                    (rcap lb_gav ub_gav yaxis if !missing(yaxis), horizontal lcolor(gs7) lwidth(medthin)) ///
                    (scatter yaxis gav if !missing(yaxis) & fdr_sig == 0, msymbol(D) mfcolor(white) mlcolor(gs8) msize(small)) ///
                    (scatter yaxis gav if !missing(yaxis) & fdr_sig == 1, msymbol(O) mcolor(black) msize(small)), ///
                    yscale(reverse range(.5 `ymax')) ///
                    ylabel(`ylabels', angle(0) labsize(`vert_labelsize') noticks nogrid) ///
                    xlabel(`panel_xticks', labsize(`xlabsize') nogrid) ///
                    xline(0, lcolor(gs10) lwidth(thin)) ///
                    xscale(range(`panel_xmin' `panel_xmax')) ///
                    xtitle(`"`xtitle'"', size(`xtitlesize')) ///
                    ytitle("") ///
                    title(`graph_title', size(`titlesize') color(black) margin(medlarge) justification(left) linegap(1.5)) ///
                    note(" " " " " " `"`note1'"' `"`note2'"' `"`note3'"', size(`notesize') margin(large)) ///
                    `legendopt' ///
                    graphregion(color(white)) plotregion(color(white)) ///
                    name(wttplot_combined, replace) ///
                    xsize(`gxtxt') ysize(`heighttxt')

                foreach fmt of local formats {
                    local outfile `"`graphdir'/combined_`page_suffix'.`fmt'"'
                    capture confirm new file `"`outfile'"'
                    if _rc & `"`replace'"' == "" {
                        di as err `"file `outfile' already exists; specify replace"'
                        restore
                        exit 602
                    }
                    if `"`fmt'"' == "png" {
                        quietly graph export `"`outfile'"', width(`pngwidth') replace
                    }
                    else {
                        quietly graph export `"`outfile'"', as(pdf) replace
                    }
                    local exported `"`exported' `"`outfile'"'"'
                }
                local ++outcount
                local ++panel_page
            }
        }
        else {
        foreach b of local blocks {
            local ++blocknum
            quietly use `"`plotdata'"', clear
            if `"`graphby'"' == "all" {
                quietly keep if !missing(gav)
                if `"`show'"' == "significant" quietly keep if fdr_sig
                local blocktitle `"`title'"'
                local filesuffix "all"
            }
            else {
                quietly keep if blockid == `b' & !missing(gav)
                if `"`show'"' == "significant" quietly keep if fdr_sig
                quietly levelsof blocklabel, local(blocktitle) clean
                local filesuffix : display %02.0f `blocknum'
                local filesuffix "block_`filesuffix'"
            }

            quietly count
            if r(N) == 0 continue

            local ++graphcount
            quietly sort gav item_no
            quietly generate double yaxis = _n
            quietly count
            local nplot = r(N)
            local ylabels ""
            forvalues i = 1/`nplot' {
                local yy = yaxis[`i']
                if `"`labelmode'"' == "item" {
                    local lab = "Item " + string(item_no[`i'], "%02.0f")
                }
                else if `"`labelmode'"' == "varname" {
                    local lab = variable[`i']
                }
                else {
                    local lab = rowlabel[`i']
                }
                if `combine' > 1 {
                    local lablen = ustrlen(`"`lab'"')
                    local labpad = `combine_labwidth' - `lablen'
                    if `labpad' > 0 {
                        local lab `"{space `labpad'}`lab'"'
                    }
                }
                local ylabels `"`ylabels' `yy' `"`lab'"'"'
            }

            quietly summarize lb_gav
            local xmin = min(r(min), 0)
            quietly summarize ub_gav
            local xmax = max(r(max), 0)
            local xpad = (`xmax' - `xmin') * .10
            if `xpad' <= 0 | missing(`xpad') local xpad = .25
            local xmin = `xmin' - `xpad'
            local xmax = `xmax' + `xpad'
            local xmin = `panel_xmin'
            local xmax = `panel_xmax'

            if `"`orientation'"' == "portrait" {
                local gx = 5.80
                local height = max(3.00, min(10.50, 1.55 + .25 * `nplot'))
            }
            else if `"`orientation'"' == "auto" {
                if `nplot' > 24 {
                    local gx = 6.20
                    local height = max(5.00, min(10.50, 1.45 + .22 * `nplot'))
                }
                else if `nplot' <= 4 {
                    local gx = 5.80
                    local height = max(2.15, min(3.10, 1.55 + .16 * `nplot'))
                }
                else {
                    local gx = 6.20
                    local height = max(2.70, min(6.80, 1.55 + .20 * `nplot'))
                }
            }
            else {
                local gx = 6.20
                local height = max(2.30, min(6.80, 1.55 + .22 * `nplot'))
            }
            local gxtxt : display %4.2f `gx'
            local heighttxt : display %4.2f `height'

            if `combine' > 1 {
                local graphname "wttplot_panel_`blocknum'"
                local thistitle `"`blocktitle'"'
                local thissubtitle ""
                local thisnote ""
                local thisxtitle ""
                local thismsize = cond(`"`show'"' == "all", "small", "vsmall")
                local thislabsize `"`labelsize'"'
                local thistitlesize `"`blocksize'"'
                local thissubtitlesize `"`blocksize'"'
            }
            else {
                local graphname "wttplot_graph"
                local thistitle `"`title'"'
                local thissubtitle `"`blocktitle'"'
                local thisnote `"`note1'"' `"`note2'"' `"`note3'"'
                local thisxtitle `"`xtitle'"'
                local thismsize "small"
                local thislabsize `"`labelsize'"'
                local thistitlesize `"`titlesize'"'
                local thissubtitlesize `"`blocksize'"'
            }
            local drawopt ""
            if `combine' > 1 local drawopt "nodraw"

            twoway ///
                (rcap lb_gav ub_gav yaxis, horizontal lcolor(gs7) lwidth(medthin)) ///
                (scatter yaxis gav if fdr_sig == 0, msymbol(D) mcolor(gs8) msize(`thismsize')) ///
                (scatter yaxis gav if fdr_sig == 1, msymbol(O) mcolor(black) msize(`thismsize')), ///
                yscale(reverse) ///
                ylabel(`ylabels', angle(0) labsize(`thislabsize') noticks nogrid) ///
                xlabel(`panel_xticks', labsize(`xlabsize') nogrid) ///
                xline(0, lcolor(gs10) lwidth(thin)) ///
                xscale(range(`xmin' `xmax')) ///
                xtitle(`"`thisxtitle'"', size(`xtitlesize')) ///
                ytitle("") ///
                title(`"`thistitle'"', size(`thistitlesize') color(black) margin(small)) ///
                subtitle(`"`thissubtitle'"', size(`thissubtitlesize') color(black) margin(medsmall)) ///
                note(`"`thisnote'"', size(`notesize')) ///
                `legendopt' ///
                graphregion(color(white)) plotregion(color(white)) ///
                name(`graphname', replace) ///
                xsize(`gxtxt') ysize(`heighttxt') ///
                `drawopt'

            if `combine' > 1 {
                local panel_graphs `"`panel_graphs' `graphname'"'
                local ++panel_count
                if `panel_count' == `effective_panels' | `blocknum' == `nblocks_total' {
                    local page_suffix : display %02.0f `panel_page'
                    local panel_rows = ceil(`panel_count' / `panel_cols')
                    local panel_xsize = cond(`panel_cols' == 1, 6.2, cond(`panel_cols' == 2, 8.0, 9.5))
                    local panel_ysize = min(10.5, max(4.2, 2.70 * `panel_rows' + 1.45))
                    local panel_xsizetxt : display %4.2f `panel_xsize'
                    local panel_ysizetxt : display %4.2f `panel_ysize'
                    graph combine `panel_graphs', col(`panel_cols') xcommon ///
                        title(`graph_title', size(`titlesize') margin(medlarge) justification(left) linegap(1.5)) ///
                        note(`"`note1'"' `"`note2'"' `"`note3'"', size(`notesize')) ///
                        graphregion(color(white)) ///
                        name(wttplot_combined, replace) ///
                        xsize(`panel_xsizetxt') ysize(`panel_ysizetxt')
                    foreach fmt of local formats {
                        local outfile `"`graphdir'/combined_`page_suffix'.`fmt'"'
                        capture confirm new file `"`outfile'"'
                        if _rc & `"`replace'"' == "" {
                            di as err `"file `outfile' already exists; specify replace"'
                            restore
                            exit 602
                        }
                        if `"`fmt'"' == "png" {
                            quietly graph export `"`outfile'"', width(`pngwidth') replace
                        }
                        else {
                            quietly graph export `"`outfile'"', as(pdf) replace
                        }
                        local exported `"`exported' `"`outfile'"'"'
                    }
                    capture graph drop wttplot_combined
                    capture graph drop `panel_graphs'
                    local ++outcount
                    local ++panel_page
                    local panel_count = 0
                    local panel_graphs ""
                }
            }
            else {
                foreach fmt of local formats {
                    local outfile `"`graphdir'/wttplot_`filesuffix'.`fmt'"'
                    capture confirm new file `"`outfile'"'
                    if _rc & `"`replace'"' == "" {
                        di as err `"file `outfile' already exists; specify replace"'
                        restore
                        exit 602
                    }
                    if `"`fmt'"' == "png" {
                        quietly graph export `"`outfile'"', width(`pngwidth') replace
                    }
                    else {
                        quietly graph export `"`outfile'"', as(pdf) replace
                    }
                    local exported `"`exported' `"`outfile'"'"'
                }
                capture graph drop `graphname'
                local ++outcount
            }
        }
        }

        if `graphcount' == 0 {
            if `"`show'"' == "significant" {
                di as txt "No FDR-significant outcomes were found; no plots were exported."
                
                return scalar n_graphs = 0
                return local graphdir `"`graphdir'"'
                return local files ""
                restore
                exit
            }
            di as err "no plottable effect sizes were produced"
            restore
            exit 2000
        }

        di as txt "wttreport plot step complete"
        di as txt "Graphs exported to:"
        foreach f of local exported {
            local flabel `"`f'"'
            if regexm(`"`f'"', "[/\\]([^/\\]+)$") local flabel = regexs(1)
            local ftarget `"`f'"'
            if !regexm(`"`ftarget'"', "^([A-Za-z]:|/|\\)") local ftarget `"`c(pwd)'/`ftarget'"'
            local ftarget = subinstr(`"`ftarget'"', "\", "/", .)
            if regexm(`"`ftarget'"', "^[A-Za-z]:") local ftarget `"file:///`ftarget'"'
            else if substr(`"`ftarget'"', 1, 1) == "/" local ftarget `"file://`ftarget'"'
            di as result `"  {browse "`ftarget'":`flabel'}"'
        }
        if `"`mapfile'"' != "" {
            local mlabel `"`mapfile'"'
            if regexm(`"`mapfile'"', "[/\\]([^/\\]+)$") local mlabel = regexs(1)
            local mtarget `"`mapfile'"'
            if !regexm(`"`mtarget'"', "^([A-Za-z]:|/|\\)") local mtarget `"`c(pwd)'/`mtarget'"'
            local mtarget = subinstr(`"`mtarget'"', "\", "/", .)
            if regexm(`"`mtarget'"', "^[A-Za-z]:") local mtarget `"file:///`mtarget'"'
            else if substr(`"`mtarget'"', 1, 1) == "/" local mtarget `"file://`mtarget'"'
            di as txt "Mapping file saved to:"
            di as result `"  {browse "`mtarget'":`mlabel'}"'
        }

        return scalar n_graphs = `outcount'
        return local graphdir `"`graphdir'"'
        return local files `"`exported'"'
    restore
end

program define _wttplot_xlsx_widths
    version 19.5
    args xlsx w1 w2 w3 w4

    mata: _wttplot_xlsx_widths_mata(`"`xlsx'"', `w1', `w2', `w3', `w4')
end

mata:
void _wttplot_xlsx_widths_mata(string scalar xlsx, real scalar w1, real scalar w2, real scalar w3, real scalar w4)
{
    class xl scalar B
    B = xl()
    B.load_book(xlsx)
    B.set_sheet("Sheet1")
    B.set_column_width(1, 1, w1)
    B.set_column_width(2, 2, w2)
    B.set_column_width(3, 3, w3)
    B.set_column_width(4, 4, w4)
    B.close_book()
}
end


program define _wttreport_summary, rclass
    version 19.5

    syntax using/, SAVING(string) ///
        [ SUMMARYDATA(string) STYLE(string) TOP(integer 5) ALPHA(real 0.05) ///
          REPLACE ESIZEWORDS TITLE(string) RQ(string) HYPOTHESIS(string) ///
          IMPLICATION(string) APPENDIXLETTER(string) ]

    if `alpha' <= 0 | `alpha' >= 1 {
        di as err "alpha() must be strictly between 0 and 1"
        exit 198
    }
    if `top' < 0 {
        di as err "top() must be 0 or a positive integer"
        exit 198
    }

    local style = lower(strtrim(`"`style'"'))
    if `"`style'"' == "" local style "brief"
    if !inlist(`"`style'"', "brief", "academic") {
        di as err "style() must be brief or academic"
        exit 198
    }
    local default_title = (`"`title'"' == "")
    if `"`title'"' == "" local title "Welch Independent Samples t-Test Analysis Summary"
    if `"`appendixletter'"' == "" local appendixletter "A"

    local saving_l = lower(`"`saving'"')
    local slen = strlen(`"`saving_l'"')
    local ext = substr(`"`saving_l'"', max(1, `slen' - 4), 5)
    local ext4 = substr(`"`saving_l'"', max(1, `slen' - 3), 4)
    if !inlist(`"`ext'"', ".docx") & !inlist(`"`ext4'"', ".txt", ".md") {
        di as err "saving() must end in .docx, .txt, or .md"
        exit 198
    }
    capture confirm new file `"`saving'"'
    if _rc & `"`replace'"' == "" {
        di as err `"file `saving' already exists; specify replace"'
        exit 602
    }
    if `"`summarydata'"' != "" {
        capture confirm new file `"`summarydata'"'
        if _rc & `"`replace'"' == "" {
            di as err `"file `summarydata' already exists; specify replace"'
            exit 602
        }
    }

    preserve
        quietly use `"`using'"', clear

        foreach needed in variable rowlabel mean1 mean2 p q gav n1 n2 blockid blocklabel {
            capture confirm variable `needed'
            if _rc {
                di as err `"results file is missing required variable `needed'"'
                di as err "Use a results() dataset produced by the current version of wttreport."
                restore
                exit 198
            }
        }

        capture confirm variable item_no
        if _rc quietly generate long item_no = _n
        capture confirm numeric variable q
        if _rc {
            di as err "q must be numeric in the results dataset"
            restore
            exit 198
        }
        capture confirm numeric variable gav
        if _rc {
            di as err "gav must be numeric in the results dataset"
            restore
            exit 198
        }
        capture confirm numeric variable n1
        if _rc {
            di as err "n1 must be numeric in the results dataset"
            restore
            exit 198
        }
        capture confirm numeric variable n2
        if _rc {
            di as err "n2 must be numeric in the results dataset"
            restore
            exit 198
        }

        local warn_group ""
        capture confirm variable group1
        if !_rc {
            quietly levelsof group1, local(g1levels) clean
            local g1nlevels : word count `g1levels'
            if `g1nlevels' > 1 local warn_group `"group1 contains more than one value in the results dataset; the first value was used in the summary."'
            quietly levelsof group1 in 1, local(g1name) clean
        }
        else {
            local g1name "G1"
            local warn_group `"group labels were not found; G1 and G2 were used."'
        }
        capture confirm variable group2
        if !_rc {
            quietly levelsof group2, local(g2levels) clean
            local g2nlevels : word count `g2levels'
            if `g2nlevels' > 1 local warn_group `"group2 contains more than one value in the results dataset; the first value was used in the summary."'
            quietly levelsof group2 in 1, local(g2name) clean
        }
        else {
            local g2name "G2"
            local warn_group `"group labels were not found; G1 and G2 were used."'
        }
        if `"`g1name'"' == "" local g1name "G1"
        if `"`g2name'"' == "" local g2name "G2"

        quietly count
        local nout = r(N)
        if `nout' == 0 {
            di as err "results file has no observations"
            restore
            exit 2000
        }
        quietly count if missing(q)
        local nmissq = r(N)
        if `nmissq' == `nout' {
            di as err "all q-values are missing; wttreport cannot identify FDR-significant outcomes"
            restore
            exit 459
        }
        quietly count if missing(gav)
        local nmissgav = r(N)
        local warn_q ""
        if `nmissq' > 0 local warn_q `"`nmissq' q-values were missing and were treated as not FDR-significant."'
        local warn_gav ""
        if `nmissgav' > 0 local warn_gav `"`nmissgav' Hedges' g_av values were missing; effect-size summaries exclude those missing values."'
        if `nmissgav' == `nout' local warn_gav `"all Hedges' g_av values were missing; effect-size ranges and largest effects are reported as unavailable."'
        quietly count if missing(n1) | missing(n2)
        local nmissn = r(N)
        if `nmissn' > 0 {
            di as err "n1 and n2 must be nonmissing for every outcome"
            restore
            exit 459
        }

        quietly summarize n1, meanonly
        local n1min = r(min)
        local n1max = r(max)
        quietly summarize n2, meanonly
        local n2min = r(min)
        local n2max = r(max)
        local n1min_s : display %9.0f `n1min'
        local n1max_s : display %9.0f `n1max'
        local n2min_s : display %9.0f `n2min'
        local n2max_s : display %9.0f `n2max'
        local n1min_s = strtrim(`"`n1min_s'"')
        local n1max_s = strtrim(`"`n1max_s'"')
        local n2min_s = strtrim(`"`n2min_s'"')
        local n2max_s = strtrim(`"`n2max_s'"')
        if `n1min' == `n1max' & `n2min' == `n2max' {
            local ntotal = `n1min' + `n2min'
            local ntotal_s : display %9.0f `ntotal'
            local ntotal_s = strtrim(`"`ntotal_s'"')
            local sample_text `"The analytic sample included `ntotal_s' complete cases (`g1name' = `n1min_s', `g2name' = `n2min_s') across all summarized outcomes."'
            local sample_design `""'
            local warn_n ""
        }
        else {
            local sample_text `"Analytic sample varied across outcomes: `g1name' = `n1min_s'-`n1max_s'; `g2name' = `n2min_s'-`n2max_s'."'
            local sample_design `"Outcome-specific analytic samples were used because group sizes varied across summarized outcomes."'
            local warn_n `"group sizes varied across outcomes; this usually means outcome-level samples were not identical."'
        }
        local g1note = lower("`g1name'")
        local g2note = lower("`g2name'")

        foreach __v in sig abs_gav sig_eff direction itemcode abs_gav_txt {
            capture drop `__v'
        }
        quietly generate byte sig = !missing(q) & q < `alpha'
        quietly generate double abs_gav = abs(gav)
        quietly generate byte sig_eff = sig & !missing(gav)
        quietly generate byte direction = cond(mean1 > mean2, 1, cond(mean2 > mean1, -1, 0))
        quietly generate str16 itemcode = "Item" + string(item_no, "%02.0f")
        quietly generate str20 abs_gav_txt = cond(missing(abs_gav), ".", string(abs_gav, "%4.2f"))

        quietly count if sig
        local nsig = r(N)
        local pctsig : display %4.1f 100 * `nsig' / `nout'
        local pctsig = strtrim(`"`pctsig'"')
        quietly count if sig & direction == 1
        local ng1 = r(N)
        quietly count if sig & direction == -1
        local ng2 = r(N)

        tempfile full blocksum
        quietly save `"`full'"', replace

        quietly sort blockid item_no
        quietly by blockid: egen outcomes = count(variable)
        quietly by blockid: egen sig_n = total(sig)
        quietly by blockid: egen g1_higher = total(sig & direction == 1)
        quietly by blockid: egen g2_higher = total(sig & direction == -1)
        quietly by blockid: egen min_eff = min(cond(sig_eff, gav, .))
        quietly by blockid: egen max_eff = max(cond(sig_eff, gav, .))

        quietly gsort blockid -sig -sig_eff -abs_gav item_no
        quietly by blockid: generate str32 largest_item = itemcode[1] if sig_n > 0
        quietly by blockid: generate double largest_eff = gav[1] if sig_n > 0
        quietly by blockid: keep if _n == 1
        quietly sort blockid

        quietly generate double sig_pct = 100 * sig_n / outcomes
        quietly generate str12 g1_higher_text = ""
        quietly generate str12 g2_higher_text = ""
        quietly replace g1_higher_text = strtrim(string(g1_higher, "%9.0f")) if sig_n > 0
        quietly replace g2_higher_text = strtrim(string(g2_higher, "%9.0f")) if sig_n > 0
        quietly generate str80 direction_text = g1_higher_text + " / " + g2_higher_text if sig_n > 0
        quietly replace direction_text = "/" if sig_n == 0

        quietly generate str20 min_eff_txt = cond(min_eff >= 0, "+" + strtrim(string(min_eff, "%9.2f")), strtrim(string(min_eff, "%9.2f"))) if sig_n > 0
        quietly generate str20 max_eff_txt = cond(max_eff >= 0, "+" + strtrim(string(max_eff, "%9.2f")), strtrim(string(max_eff, "%9.2f"))) if sig_n > 0
        quietly generate str20 largest_eff_txt = cond(largest_eff >= 0, "+" + strtrim(string(largest_eff, "%9.2f")), strtrim(string(largest_eff, "%9.2f"))) if sig_n > 0
        quietly generate str20 largest_eff_mag_txt = cond(largest_eff >= 0, "+" + strtrim(string(largest_eff, "%9.2f")), strtrim(string(largest_eff, "%9.2f"))) if sig_n > 0
        quietly generate str40 effect_range = ""
        quietly replace effect_range = "/" if sig_n == 0
        quietly replace effect_range = "[" + min_eff_txt + ", " + max_eff_txt + "]" if sig_n > 0 & !missing(min_eff)
        quietly replace effect_range = "effect size missing" if sig_n > 0 & missing(min_eff)
        quietly generate str80 largest_text = cond(sig_n == 0, "/", cond(missing(largest_eff), "effect size missing", largest_item + " (" + largest_eff_txt + ")"))
        quietly generate str20 sig_text = string(sig_n, "%9.0f") + " of " + string(outcomes, "%9.0f")
        quietly generate str12 sig_n_text = strtrim(string(sig_n, "%9.0f"))
        quietly generate str12 outcomes_text = strtrim(string(outcomes, "%9.0f"))

        quietly save `"`blocksum'"', replace
        if `"`summarydata'"' != "" {
            quietly save `"`summarydata'"', replace
        }

        quietly count
        local nblocks_total = r(N)
        quietly count if sig_n > 0
        local nblocks_sig = r(N)
        quietly count if sig_n == 0
        local nblocks_nosig = r(N)
        quietly count if sig_n == outcomes
        local nblocks_all_sig = r(N)

        local sigblocks ""
        local nosigblocks ""
        local consistentblocks ""
        local mixedblocks ""
        local onlynosig ""
        quietly levelsof blockid, local(blocks)
        foreach b of local blocks {
            quietly levelsof blocklabel if blockid == `b', local(blab) clean
            quietly summarize sig_n if blockid == `b', meanonly
            local bsig = r(mean)
            quietly summarize sig_pct if blockid == `b', meanonly
            local bpct = r(mean)
            if `bsig' > 0 local sigblocks `"`sigblocks'`sep1'`blab'"'
            if `bsig' == 0 local nosigblocks `"`nosigblocks'`sep2'`blab'"'
            if `bsig' > 0 & `bpct' >= 70 local consistentblocks `"`consistentblocks'`sep3'`blab'"'
            if `bsig' > 0 local sep1 ", "
            if `bsig' == 0 local sep2 ", "
            if `bsig' > 0 & `bpct' >= 70 local sep3 ", "
            if `bsig' == 0 & `nblocks_nosig' == 1 local onlynosig `"`blab'"'
        }
        if `"`sigblocks'"' == "" local sigblocks "none"
        if `"`nosigblocks'"' == "" local nosigblocks "none"
        if `"`consistentblocks'"' == "" local consistentblocks "none"
        if `"`mixedblocks'"' == "" local mixedblocks "none"

        quietly use `"`blocksum'"', clear
        quietly keep if sig_n > 0
        quietly gsort -sig_n blockid
        local nstrong = min(3, _N)
        local strong1 ""
        local strong2 ""
        local strong3 ""
        if `nstrong' > 0 {
            forvalues i = 1/`nstrong' {
                local strong`i' = blocklabel[`i']
            }
        }
        local strongest_tail ""
        if `nstrong' == 1 {
            local strongest_tail `"with the strongest pattern in `strong1'."'
        }
        else if `nstrong' == 2 {
            local strongest_tail `"with the strongest pattern in `strong1', followed by `strong2'."'
        }
        else if `nstrong' >= 3 {
            local strongest_tail `"with the strongest pattern in `strong1', followed by `strong2' and `strong3'."'
        }

        quietly use `"`full'"', clear
        quietly keep if sig_eff
        quietly gsort -abs_gav item_no
        quietly count
        local nefftop = r(N)
        local ntop = min(`top', `nefftop')
        local top_phrase ""
        forvalues i = 1/`ntop' {
            local ti = itemcode[`i']
            local tb = blocklabel[`i']
            local te : display %9.2f gav[`i']
            local te = strtrim(`"`te'"')
            if gav[`i'] >= 0 local te "+`te'"
            local td = cond(direction[`i'] == 1, "`g1name' higher", cond(direction[`i'] == -1, "`g2name' higher", "no clear direction"))
            local piece "`ti' (`tb', signed g=`te', `td')"
            if `i' == 1 local top_phrase `"`piece'"'
            else local top_phrase `"`top_phrase'; `piece'"'
        }
        if `"`top_phrase'"' == "" local top_phrase "No FDR-significant effects were available."

        local rq_user = (`"`rq'"' != "")
        if !`rq_user' {
            local rq_intro `"This analysis addressed the following three related questions."'
            local rq1 `"Do the two groups show systematically mean differences across a set of outcome variables?"'
            local rq2 `"After controlling the false discovery rate, which outcomes show statistically significant differences?"'
            local rq3 `"Which blocks contain the strongest patterns, what is the direction of the differences, how large are the effects, and do the observed effects appear substantively meaningful?"'
            local rq `"`rq_intro' `rq1' `rq2' `rq3'"'
        }
        local method1 `"`sample_text' `sample_design'"'
        local method2 `"Welch independent samples t-test examined `nout' outcomes across `nblocks_total' subdomains."'
        local method3 `"Benjamini-Hochberg FDR-adjusted q values evaluated statistical significance across the `nout' outcomes."'
        local method4 `"Signed Hedges' g_av values were used to summarize effect-size direction and magnitude."'
        local method_brief `"`method1' `method2' `method3'"'
        local approach `"`method1' `method2' `method3' `method4'"'
        local overall `"After FDR correction, `nsig' outcomes (`pctsig'%) remained statistically significant."'
        if `nsig' == 0 {
            local pattern `"No outcomes remained statistically significant after FDR correction. The summary therefore does not interpret block-level differences."'
            local direction `"No direction of FDR-significant differences is reported because no outcomes met the FDR criterion."'
            local toptext `"No top effects are reported because no outcomes were FDR-significant."'
            local appendixtext `"Block-level counts, directions, effect-size ranges, and largest effects are summarized in Appendix `appendixletter'."'
        }
        else {
            local pattern_base `"FDR-significant differences appeared in `nblocks_sig' blocks, "'
            local pattern `"`pattern_base'`strongest_tail'"'
            local direction `"Among FDR-significant outcomes, `ng1' had higher means for `g1name' and `ng2' had higher means for `g2name'. Block-level direction counts are reported in Appendix `appendixletter'."'
            if `ntop' == 0 {
                local toptext `"No largest effects are reported because effect sizes were unavailable for FDR-significant outcomes."'
            }
            else {
                local toptext `"The largest signed Hedges' g_av effects by absolute magnitude were: `top_phrase'."'
            }
            local appendixtext `"Block-level counts, directions, effect-size ranges, and largest effects are summarized in Appendix `appendixletter'."'
        }
        if `"`style'"' == "brief" {
            local methodp `"`method_brief'"'
            local findings_heading "Key Findings"
            local f1 `"`overall'"'
            local f2 `"`pattern'"'
            local f3 `"`appendixtext'"'
            local f4 ""
        }
        else {
            local methodp `"`approach'"'
            local findings_heading "Results summary"
            local f1 `"`overall'"'
            local f2 `"`pattern'"'
            local f3 `"`direction'"'
            local f4 `"`toptext' `appendixtext'"'
        }
        if `"`implication'"' == "" & `"`style'"' == "academic" {
            local implication `"These findings identify outcome domains that may warrant closer substantive or model-based follow-up."'
        }

        if `"`ext'"' == ".docx" {
            quietly putdocx clear
            quietly putdocx begin, pagesize(letter) margin(top, .55) margin(bottom, .55) margin(left, 1) margin(right, 1) font("Times New Roman", 10)
            local bullet = uchar(8226)
            forvalues __blank = 1/4 {
                putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
                putdocx text (" "), font("Times New Roman", 10, black)
            }
            putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 2pt)
            if `default_title' {
                putdocx text ("Welch Independent Samples "), font("Times New Roman", 14, black)
                putdocx text ("t"), italic font("Times New Roman", 14, black)
                putdocx text ("-Test Analysis Summary"), font("Times New Roman", 14, black)
            }
            else {
                putdocx text (`"`title'"'), font("Times New Roman", 14, black)
            }
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text (" "), font("Times New Roman", 10, black)
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text (" "), font("Times New Roman", 10, black)

            putdocx paragraph, spacing(before, 0pt) spacing(after, 1pt)
            putdocx text ("Research Questions"), bold
            if `rq_user' {
                putdocx paragraph, spacing(before, 0pt) spacing(after, 2pt)
                putdocx text (`"`rq'"')
            }
            else {
                putdocx paragraph, spacing(before, 0pt) spacing(after, 1pt)
                putdocx text (`"`rq_intro'"')
                putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
                putdocx text (`"`bullet' `rq1'"')
                putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
                putdocx text (`"`bullet' `rq2'"')
                putdocx paragraph, spacing(before, 0pt) spacing(after, 2pt) indent(left, .25) indent(hanging, .25)
                putdocx text (`"`bullet' `rq3'"')
            }
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text (" "), font("Times New Roman", 10, black)

            if `"`hypothesis'"' != "" {
                putdocx paragraph, spacing(before, 4pt) spacing(after, 1pt)
                putdocx text ("Hypothesis"), bold
                putdocx paragraph, spacing(before, 0pt) spacing(after, 2pt)
                putdocx text (`"`hypothesis'"')
            }

            putdocx paragraph, spacing(before, 0pt) spacing(after, 1pt)
            putdocx text ("Methods"), bold
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
            putdocx text (`"`bullet' `method1'"')
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
            putdocx text (`"`bullet' Welch independent samples "')
            putdocx text ("t"), italic
            putdocx text (`"-test examined `nout' outcomes across `nblocks_total' subdomains."')
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
            putdocx text (`"`bullet' Benjamini-Hochberg FDR-adjusted "')
            putdocx text ("q"), italic
            putdocx text (`" values evaluated statistical significance across the `nout' outcomes."')
            if `"`style'"' == "academic" {
                putdocx paragraph, spacing(before, 0pt) spacing(after, 2pt) indent(left, .25) indent(hanging, .25)
                putdocx text (`"`bullet' Signed Hedges' "')
                putdocx text ("g_av"), italic
                putdocx text (`" values were used to summarize effect-size direction and magnitude."')
            }
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text (" "), font("Times New Roman", 10, black)

            putdocx paragraph, spacing(before, 0pt) spacing(after, 1pt)
            putdocx text (`"`findings_heading'"'), bold
            putdocx paragraph, spacing(before, 0pt) spacing(after, 3pt) indent(left, .25) indent(hanging, .25)
            putdocx text (`"`bullet' `f1'"')
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
            if `"`style'"' == "brief" & `nsig' > 0 & `nstrong' > 0 {
                putdocx text (`"`bullet' `pattern_base'with the strongest pattern in "')
                putdocx text (`"`strong1'"'), italic
                if `nstrong' == 2 {
                    putdocx text (", followed by ")
                    putdocx text (`"`strong2'"'), italic
                }
                else if `nstrong' >= 3 {
                    putdocx text (", followed by ")
                    putdocx text (`"`strong2'"'), italic
                    putdocx text (" and ")
                    putdocx text (`"`strong3'"'), italic
                }
                putdocx text (".")
            }
            else {
                putdocx text (`"`bullet' `f2'"')
            }
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt) indent(left, .25) indent(hanging, .25)
            putdocx text (`"`bullet' `f3'"')
            if `"`f4'"' != "" {
                putdocx paragraph, spacing(before, 0pt) spacing(after, 3pt) indent(left, .25) indent(hanging, .25)
                putdocx text (`"`bullet' `f4'"')
            }

            if `"`implication'"' != "" {
                putdocx paragraph, spacing(before, 4pt) spacing(after, 1pt)
                putdocx text ("Implication"), bold
                putdocx paragraph, spacing(before, 0pt) spacing(after, 3pt)
                putdocx text (`"`implication'"')
            }

            putdocx sectionbreak, pagesize(letter) landscape margin(top, 1) margin(bottom, 1) margin(left, .55) margin(right, .55)
            quietly use `"`blocksum'"', clear
            local rows = _N + 3
            local note_row = `rows'
            local data_bottom = `rows' - 1
            putdocx paragraph, halign(center) spacing(before, 0pt) spacing(after, 0pt)
            putdocx text ("Appendix `appendixletter'.")
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text ("")
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text ("Table"), italic
            putdocx paragraph, spacing(before, 0pt) spacing(after, 0pt)
            putdocx text ("Block-Level Summary of Welch Independent Samples ")
            putdocx text ("t"), italic
            putdocx text ("-Test Analysis")
            putdocx table bsum = (`rows', 12), width(9.40in) halign(left) ///
                border(all, nil) layout(fixed) ///
                cellmargin(top, .5pt) cellmargin(bottom, 0pt) ///
                cellmargin(left, 2pt) cellmargin(right, 2pt)
            putdocx table bsum(.,1), width(1.54in)
            putdocx table bsum(.,2), width(.90in)
            putdocx table bsum(.,3), width(.46in)
            putdocx table bsum(.,4), width(.18in)
            putdocx table bsum(.,5), width(1.25in)
            putdocx table bsum(.,6), width(1.22in)
            putdocx table bsum(.,7), width(.18in)
            putdocx table bsum(.,8), width(.80in)
            putdocx table bsum(.,9), width(.90in)
            putdocx table bsum(.,10), width(.18in)
            putdocx table bsum(.,11), width(.75in)
            putdocx table bsum(.,12), width(.75in)
            putdocx table bsum(1,1) = ("Block Name")
            putdocx table bsum(1,2) = ("# of Outcomes")
            putdocx table bsum(2,2) = ("FDR Q-Sig.")
            putdocx table bsum(2,3) = ("Total")
            putdocx table bsum(1,5) = ("Mean Difference Direction")
            putdocx table bsum(2,5) = ("# Higher in `g1name'")
            putdocx table bsum(2,6) = ("# Higher in `g2name'")
            putdocx table bsum(1,8) = ("Effect-Size Range")
            putdocx table bsum(2,8) = ("Minimum")
            putdocx table bsum(2,9) = ("Maximum")
            putdocx table bsum(1,11) = ("Largest Effect Size")
            putdocx table bsum(2,11) = ("Location")
            putdocx table bsum(2,12) = ("Magnitude")
            putdocx table bsum(1,11), colspan(2)
            putdocx table bsum(1,8), colspan(2)
            putdocx table bsum(1,5), colspan(2)
            putdocx table bsum(1,2), colspan(2)
            putdocx table bsum(1,.), border(top, single, black, 1.5pt)
            putdocx table bsum(2,2), border(top)
            putdocx table bsum(2,3), border(top)
            putdocx table bsum(2,5), border(top)
            putdocx table bsum(2,6), border(top)
            putdocx table bsum(2,8), border(top)
            putdocx table bsum(2,9), border(top)
            putdocx table bsum(2,11), border(top)
            putdocx table bsum(2,12), border(top)
            putdocx table bsum(2,.), border(bottom)
            putdocx table bsum(1,.), halign(center)
            putdocx table bsum(2,.), halign(center)
            putdocx table bsum(.,2), halign(center)
            putdocx table bsum(.,3), halign(center)
            putdocx table bsum(.,5), halign(center)
            putdocx table bsum(.,6), halign(center)
            putdocx table bsum(.,8), halign(center)
            putdocx table bsum(.,9), halign(center)
            putdocx table bsum(.,11), halign(center)
            putdocx table bsum(.,12), halign(center)
            forvalues i = 1/`=_N' {
                local r = `i' + 2
                local location = largest_item[`i']
                local magnitude = largest_eff_mag_txt[`i']
                local minrange = min_eff_txt[`i']
                local maxrange = max_eff_txt[`i']
                local g1higher = g1_higher_text[`i']
                local g2higher = g2_higher_text[`i']
                if sig_n[`i'] == 0 {
                    local location = "/"
                    local magnitude = "/"
                    local minrange = "/"
                    local maxrange = "/"
                    local g1higher = "/"
                    local g2higher = "/"
                }
                if sig_n[`i'] > 0 & missing(min_eff[`i']) {
                    local minrange = "/"
                    local maxrange = "/"
                }
                if sig_n[`i'] > 0 & missing(largest_eff[`i']) {
                    local location = "/"
                    local magnitude = "/"
                }
                putdocx table bsum(`r',1) = (blocklabel[`i'])
                putdocx table bsum(`r',2) = (sig_n_text[`i'])
                putdocx table bsum(`r',3) = (outcomes_text[`i'])
                putdocx table bsum(`r',5) = ("`g1higher'")
                putdocx table bsum(`r',6) = ("`g2higher'")
                putdocx table bsum(`r',8) = ("`minrange'")
                putdocx table bsum(`r',9) = ("`maxrange'")
                putdocx table bsum(`r',11) = ("`location'")
                putdocx table bsum(`r',12) = ("`magnitude'")
            }
            putdocx table bsum(.,2), halign(center)
            putdocx table bsum(.,3), halign(center)
            putdocx table bsum(.,5), halign(center)
            putdocx table bsum(.,6), halign(center)
            putdocx table bsum(.,8), halign(center)
            putdocx table bsum(.,9), halign(center)
            putdocx table bsum(.,11), halign(center)
            putdocx table bsum(.,12), halign(center)
            putdocx table bsum(`note_row',1) = ("Note. "), italic
            putdocx table bsum(`note_row',1) = ("Effect-size ranges are signed Hedges' g_av intervals among FDR-significant outcomes within each block; positive values indicate higher means for `g1note' and negative values indicate higher means for `g2note'."), append
            putdocx table bsum(`note_row',1), colspan(12)
            putdocx table bsum(`note_row',.), border(top, single, black, 1.5pt)
            putdocx table bsum(`note_row',.), font("Times New Roman", 10)
            quietly putdocx save `"`saving'"', replace
        }
        else {
            tempname fh
            file open `fh' using `"`saving'"', write replace text
            file write `fh' `"`title'"' _n _n
            file write `fh' `"Research question"' _n
            if `rq_user' {
                file write `fh' `"`rq'"' _n _n
            }
            else {
                file write `fh' `"`rq_intro'"' _n
                file write `fh' `"* `rq1'"' _n
                file write `fh' `"* `rq2'"' _n
                file write `fh' `"* `rq3'"' _n _n
            }
            if `"`hypothesis'"' != "" {
                file write `fh' `"Hypothesis"' _n
                file write `fh' `"`hypothesis'"' _n _n
            }
            file write `fh' `"Methods"' _n
            file write `fh' `"* `method1'"' _n
            file write `fh' `"* `method2'"' _n
            file write `fh' `"* `method3'"' _n
            if `"`style'"' == "academic" file write `fh' `"* `method4'"' _n
            file write `fh' _n
            file write `fh' `"`findings_heading'"' _n
            file write `fh' `"* `f1'"' _n
            file write `fh' `"* `f2'"' _n
            file write `fh' `"* `f3'"' _n
            if `"`f4'"' != "" file write `fh' `"* `f4'"' _n
            file write `fh' _n
            if `"`implication'"' != "" {
                file write `fh' `"Implication"' _n
                file write `fh' `"`implication'"' _n _n
            }
            file write `fh' `"Appendix A. Block Summary Table"' _n
            file write `fh' `"Block	Sig. Outcomes	Direction	Effect-Size Range	Largest Effect"' _n
            quietly use `"`blocksum'"', clear
            forvalues i = 1/`=_N' {
                file write `fh' `"`=blocklabel[`i']'	`=sig_text[`i']'	`=direction_text[`i']'	`=effect_range[`i']'	`=largest_text[`i']'"' _n
            }
            file write `fh' _n `"Note. Signed Hedges' g_av values are reported in the effect-size range; positive values indicate higher means for `g1name' and vice versa for negative values."' _n
            file close `fh'
        }

        return scalar outcomes = `nout'
        return scalar significant = `nsig'
        return scalar n1_min = `n1min'
        return scalar n1_max = `n1max'
        return scalar n2_min = `n2min'
        return scalar n2_max = `n2max'
        return local saving `"`saving'"'
        if `"`summarydata'"' != "" return local summarydata `"`summarydata'"'
    restore

    di as txt "wttreport summary step complete"
    di as txt "Outcomes summarized: " as res `nout'
    if `n1min' == `n1max' & `n2min' == `n2max' {
        di as txt "Group sizes: " as res "`g1name' n=`n1min_s', `g2name' n=`n2min_s'"
    }
    else {
        di as txt "Group size ranges: " as res "`g1name' n=`n1min_s'-`n1max_s', `g2name' n=`n2min_s'-`n2max_s'"
    }
    di as txt "FDR-significant outcomes: " as res `nsig'
    if `"`warn_group'"' != "" di as txt "warning: `warn_group'"
    if `"`warn_n'"' != "" di as txt "warning: `warn_n'"
    if `"`warn_q'"' != "" di as txt "warning: `warn_q'"
    if `"`warn_gav'"' != "" di as txt "warning: `warn_gav'"
    local saving_abs `"`saving'"'
    if strpos(`"`saving_abs'"', ":") == 0 & substr(`"`saving_abs'"', 1, 1) != "/" {
        local saving_abs `"`c(pwd)'/`saving_abs'"'
    }
    local saving_abs = subinstr(`"`saving_abs'"', "\", "/", .)
    local saving_uri `"file:///`saving_abs'"'
    local saving_label `"`saving'"'
    while strpos(`"`saving_label'"', "\") > 0 {
        local p = strpos(`"`saving_label'"', "\")
        local saving_label = substr(`"`saving_label'"', `p' + 1, .)
    }
    while strpos(`"`saving_label'"', "/") > 0 {
        local p = strpos(`"`saving_label'"', "/")
        local saving_label = substr(`"`saving_label'"', `p' + 1, .)
    }
    di as txt "Summary saved to:"
    di as smcl `"  {browse "`saving_uri'":`saving_label'}"'
    if `"`summarydata'"' != "" {
        local sdata_abs `"`summarydata'"'
        if strpos(`"`sdata_abs'"', ":") == 0 & substr(`"`sdata_abs'"', 1, 1) != "/" {
            local sdata_abs `"`c(pwd)'/`sdata_abs'"'
        }
        local sdata_abs = subinstr(`"`sdata_abs'"', "\", "/", .)
        local sdata_uri `"file:///`sdata_abs'"'
        local sdata_label `"`summarydata'"'
        while strpos(`"`sdata_label'"', "\") > 0 {
            local p = strpos(`"`sdata_label'"', "\")
            local sdata_label = substr(`"`sdata_label'"', `p' + 1, .)
        }
        while strpos(`"`sdata_label'"', "/") > 0 {
            local p = strpos(`"`sdata_label'"', "/")
            local sdata_label = substr(`"`sdata_label'"', `p' + 1, .)
        }
        di as txt "Block summary data saved to:"
        di as smcl `"  {browse "`sdata_uri'":`sdata_label'}"'
    }
end


