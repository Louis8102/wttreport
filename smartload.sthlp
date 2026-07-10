{smcl}
{* *! version 0.2.1 09jul2026}{...}
{vieweralsosee "[D] import" "help import"}{...}
{vieweralsosee "[D] use" "help use"}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col:{hi:smartload} {hline 2}}Load a named data file using a pure Stata file index{p_end}
{p2colreset}{...}

{title:Syntax}

{p 8 17 2}
{cmd:smartload} {it:filename}
[{cmd:,}
{cmd:clear}
{cmd:choice(}{it:#}{cmd:)}
{cmd:roots(}{it:roots}{cmd:)}
{cmd:sheet(}{it:sheetname}{cmd:)}
{cmd:firstrow}
{cmd:encoding(}{it:encoding}{cmd:)}
{cmd:ocr}
{cmd:log}
{cmd:replace}]

{p 8 17 2}
{cmd:smartload, refresh}
[{cmd:roots(}{it:roots}{cmd:)}
{cmd:drives(}{it:drive-list|all}{cmd:)}
{cmd:replace}]

{title:Description}

{pstd}
{cmd:smartload} loads a data file by exact file name.  Version 0.2.1 uses a
pure Stata index stored in the user's PERSONAL ado directory.  It does not call
{cmd:shell}, PowerShell, Everything, Windows Search, or external search tools.

{pstd}
Build or refresh the index first:

{phang2}{cmd:. smartload, refresh}{p_end}

{pstd}
Then load by file name:

{phang2}{cmd:. smartload Indicator.dta, clear}{p_end}

{title:Options}

{phang}
{cmd:refresh} rebuilds the pure Stata file index.  Without {cmd:roots()} or
{cmd:drives()}, available drive roots from C through Z are indexed.

{phang}
{cmd:roots(}{it:roots}{cmd:)} restricts either an index refresh or an indexed
lookup to one or more roots.  Separate multiple roots with semicolons.

{phang}
{cmd:drives(}{it:drive-list|all}{cmd:)} controls which drive roots are indexed
when used with {cmd:refresh}.

{phang}
{cmd:choice(}{it:#}{cmd:)} selects a file when several indexed files have the
same name.  Interactive Stata users can instead type the displayed number when
prompted.

{phang}
{cmd:clear}, {cmd:sheet()}, {cmd:firstrow}, and {cmd:encoding()} are passed to
relevant Stata import commands.

{title:Duplicate File Names}

{pstd}
If the same file name is indexed in multiple locations, {cmd:smartload} displays
all matching paths with Arabic numerals:

{p 8 12 2}
1. C:/folder/Indicator.dta{break}
2. F:/folder/Indicator.dta
{p_end}

{pstd}
In interactive Stata, type the number to import.  In batch mode, use
{cmd:choice(#)}.

{title:Supported Native Formats}

{pstd}
{cmd:.dta} via {cmd:use}; {cmd:.xlsx} and {cmd:.xls} via {cmd:import excel};
{cmd:.csv}, {cmd:.txt}, {cmd:.tsv}, and text-like {cmd:.dat} via
{cmd:import delimited}; {cmd:.sav} and {cmd:.por} via {cmd:import spss};
{cmd:.sas7bdat} via {cmd:import sas}; {cmd:.xpt} via {cmd:import sasxport}.

{pstd}
The index records all files it can see under indexed roots, including files in
hidden folders.  Loading is implemented for the supported Stata-readable formats
above, not only {cmd:.dta}.

{title:Recognized But Not Imported}

{pstd}
PDF, Word, PowerPoint, R, Python/data-science, GIS, database, and archive files
are detected but not falsely imported.

{title:Examples}

{phang2}{cmd:. smartload, refresh}{p_end}
{phang2}{cmd:. smartload Indicator.dta, clear}{p_end}
{phang2}{cmd:. smartload Indicator.dta, choice(2) clear}{p_end}
{phang2}{cmd:. smartload city.sas7bdat, clear}{p_end}
{phang2}{cmd:. smartload workbook.xlsx, sheet("Sheet1") firstrow clear}{p_end}
{phang2}{cmd:. smartload, refresh roots("C:\ANOVA;F:\Project") replace}{p_end}

{title:Returned Results}

{pstd}
After successful import, {cmd:smartload} returns {cmd:r(filepath)},
{cmd:r(filename)}, {cmd:r(extension)}, {cmd:r(importcmd)}, {cmd:r(storage)},
{cmd:r(sourcekind)}, {cmd:r(indexfile)}, {cmd:r(N)}, and {cmd:r(k)}.

{title:License}

{pstd}
MIT License.  See {cmd:LICENSE}.

{title:Author}

{pstd}
Hao Ma.
