{smcl}
{* *! version 0.2.0-preview  03jul2026}{...}
{title:Title}

{p2colset 5 20 22 2}{...}
{p2col:{hi:wttreport} {hline 2}}Batch Welch independent-samples t-test reporting pipeline{p_end}
{p2colreset}{...}

{title:Syntax}

{p 8 17 2}
{cmd:wttreport} {it:outcomes}
{ifin}{cmd:,}
{cmd:outdir(}{it:folder}{cmd:)}
[{cmd:by(}{it:groupvar}{cmd:)} | {cmd:byvars(}{it:groupvars}{cmd:)}]
[{it:options}]

{synoptset 30 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt by(varname)}}run the report for one two-category grouping variable{p_end}
{synopt:{opt byvars(varlist)}}run the report for multiple two-category grouping variables{p_end}
{synopt:{opt outdir(folder)}}save all report outputs in {it:folder}{p_end}
{synopt:{opt output(report|component)}}output organization; default is {cmd:report}{p_end}
{synopt:{opt blockfromchar}}read block metadata from variable characteristics{p_end}
{synopt:{opt blockfromlabel}}read block metadata from variable labels{p_end}
{synopt:{opt blockfile(filename)}}read block metadata from an external block map{p_end}
{synopt:{opt summarystyle(brief|academic)}}summary-writing style; default is {cmd:brief}{p_end}
{synopt:{opt top(#)}}number of largest effects mentioned in academic summaries only{p_end}
{synopt:{opt show(significant|all)}}display FDR-significant outcomes only by default; use {cmd:show(all)} to display all outcomes{p_end}
{synopt:{opt availablecase}}relax the common-sample rule and use available cases by outcome/grouping variable{p_end}
{synopt:{opt plotcombine(#)}}number of plot panels combined per graph; default is 6{p_end}
{synopt:{opt plotlayout(auto|horizontal|vertical)}}combined-plot layout; default is {cmd:vertical}{p_end}
{synopt:{opt tablelabelmode(label|item)}}table row labels; default is {cmd:item}{p_end}
{synopt:{opt plotlabelmode(full|item|varname)}}plot y-axis labels{p_end}
{synopt:{opt notable}}do not retain table output; results are still computed internally{p_end}
{synopt:{opt noplot}}skip plots{p_end}
{synopt:{opt nosummary}}skip summaries{p_end}
{synopt:{opt nomapping}}skip the Word mapping file{p_end}
{synopt:{opt replace}}overwrite generated files{p_end}
{synoptline}

{title:Description}

{pstd}
{cmd:wttreport} is a controller for the {cmd:wtttable}, {cmd:wttplot}, and
{cmd:wttsummary} workflow.  It allows one or more two-category grouping
variables to be processed in a single command.  For each grouping variable,
it creates a table, a results dataset, effect-size graphs, and a summary from the single wttreport command.

{pstd}
The command supports both single-question and batch-question workflows.
Use {cmd:by()} for one grouping variable and {cmd:byvars()} for multiple
grouping variables.  By default, {cmd:wttreport} uses a common complete-case
analytic sample.  With {cmd:by()}, the sample includes observations with
nonmissing values on the grouping variable and all requested outcomes.  With
{cmd:byvars()}, the sample includes observations with nonmissing values on all
listed grouping variables and all requested outcomes.  Thus, all reported
Welch tests are based on the same analytic sample unless {cmd:availablecase}
is specified.

{pstd}
Version 0.2.0-preview creates one complete Word report per grouping variable by
default.  Each report can contain the table, plot pages, and summary for that
grouping variable.  A unified Word mapping file is also created.  Specify
{cmd:output(component)} to instead create combined Table, Figure, and Summary
documents across all grouping variables.

{pstd}
When {cmd:plotlayout(vertical)} is used, vertically arranged combined figures
are inserted on landscape Word pages; the summary section starts on a portrait
page and the appendix block-level table is placed on a landscape page.

{pstd}
If no outcomes are FDR-significant for a grouping variable, the plot section
contains a note explaining that no effect-size comparison plot was produced.

{title:Examples}

{phang2}{cmd:. wttreport item1-item60, by(gender) blockfromchar outdir(report_gender) replace}{p_end}

{phang2}{cmd:. wttreport item1-item60, byvars(gender company_site high_workload remote_work) blockfromchar outdir(report_all) summarystyle(brief) plotcombine(2) plotlayout(vertical) replace}{p_end}

{phang2}{cmd:. wttreport item1-item60, byvars(gender company_site) blockfromchar outdir(report_components) output(component) replace}{p_end}

{title:Remarks}

{pstd}
The {cmd:top()} option affects {cmd:summarystyle(academic)} only.  Brief
summaries remain concise and point readers to the appendix/block-level
summary rather than listing top effects.

{title:Author}

{pstd}
Hao Ma

