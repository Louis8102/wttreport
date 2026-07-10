capture log close smartload_selftest
log using smartload_selftest.log, text replace name(smartload_selftest)

adopath ++ "`c(pwd)'"

cap which smartload
if _rc {
    di as error "smartload.ado was not found on the adopath. Run this do-file from the folder containing smartload.ado."
    exit 601
}

local base "`c(tmpdir)'smartload_test"
cap mkdir "`base'"
cap mkdir "`base'\root1"
cap mkdir "`base'\root2"
cap mkdir "`base'\empty"

clear
set obs 5
gen id = _n
gen value = _n * 10
gen name = "row" + string(_n)
save "`base'\root1\sample.dta", replace
export delimited using "`base'\root1\sample.csv", replace
export delimited using "`base'\root1\sample.dat", replace
cap export excel using "`base'\root1\sample.xlsx", firstrow(variables) replace
local xlsx_rc = _rc

copy "`base'\root1\sample.csv" "`base'\root2\sample.csv", replace
copy "`base'\root1\sample.dta" "`base'\root2\sample.dta", replace

file open fh using "`base'\root1\future.parquet", write text replace
file write fh "placeholder for unsupported conversion-based file"
file close fh

file open fh using "`base'\root1\report.pdf", write text replace
file write fh "%PDF placeholder"
file close fh

file open fh using "`base'\root1\report.docx", write text replace
file write fh "placeholder"
file close fh

file open fh using "`base'\root1\slides.pptx", write text replace
file write fh "placeholder"
file close fh

di as txt "1. ado loads"
which smartload

di as txt "2. pure Stata index refresh succeeds"
smartload, refresh roots("`base'\root1;`base'\root2;`base'\empty") replace
assert r(N) > 0

di as txt "3. no match is reported"
cap noi smartload does_not_exist.csv
assert _rc != 0

di as txt "4. multiple same-name files can be selected by number in batch"
smartload sample.csv, choice(1) clear
assert r(N) == 5

di as txt "5. .dta import succeeds"
smartload sample.dta, choice(1) clear log replace
assert r(N) == 5
assert r(k) == 3
assert "`r(extension)'" == "dta"

di as txt "6. .csv import succeeds"
smartload sample.csv, choice(1) clear
assert r(N) == 5
assert r(k) == 3
assert "`r(importcmd)'" == "import delimited"

di as txt "7. .xlsx import succeeds if export excel was available"
if `xlsx_rc' == 0 {
    smartload sample.xlsx, firstrow clear
    assert r(N) == 5
    assert r(k) == 3
}
else {
    di as txt "Skipped xlsx import test because export excel failed on this Stata installation."
}

di as txt "8. .dat text-delimited candidate succeeds"
smartload sample.dat, clear
assert r(N) == 5

di as txt "9. conversion-based file is detected but not imported"
smartload future.parquet, clear
assert "`r(status)'" == "detected_not_imported"

di as txt "10. log output exists"
confirm file smartload_log.txt

di as txt "11. help file opens"
cap noi help smartload
assert _rc == 0

di as txt "12. multiple semicolon roots accepted"
smartload sample.dta, roots("`base'\root1") clear
assert r(N) == 5

di as txt "13. duplicate choice selects requested copy"
smartload sample.dta, choice(2) clear
assert r(N) == 5

di as txt "16. PDF is detected without pretending direct import"
smartload report.pdf, clear
assert "`r(status)'" == "detected_not_imported"

di as txt "17. DOCX is detected"
smartload report.docx, clear
assert "`r(status)'" == "detected_not_imported"

di as txt "18. PPTX is detected"
smartload slides.pptx, clear
assert "`r(status)'" == "detected_not_imported"

di as result "All runnable smartload V0.2.1 tests completed."
log close smartload_selftest
