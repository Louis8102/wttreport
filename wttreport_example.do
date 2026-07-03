clear all
set more off

* Example data:
*   wtt_example.dta contains 60 item outcomes and multiple two-category
*   organizational grouping variables.

use "wtt_example.dta", clear

* Single grouping variable report.
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(report_gender) ///
    summarystyle(brief) ///
    replace

* Multiple grouping variable report.
* Default output(report): one complete Word report per grouping variable.
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work union_member) ///
    blockfromchar ///
    outdir(report_all) ///
    summarystyle(brief) ///
    replace

* Alternative output(component): one combined Table document, one Figure
* document, and one Summary document.
wttreport item1-item60, ///
    byvars(gender company_site) ///
    blockfromchar ///
    outdir(report_components) ///
    output(component) ///
    summarystyle(brief) ///
    replace

* Optional: request fewer block panels per figure.
* For example:
*   plotcombine(4)
*   plotcombine(3)
*   plotcombine(2)
