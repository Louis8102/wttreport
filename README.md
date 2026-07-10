# wttreport

`wttreport` is a report suite for Welch independent-samples t-test screening
across many outcomes and one or more two-category grouping variables. The table, figure, and summary routines are integrated inside the single `wttreport` command.

## Installation

If an older version is already installed, first clear Stata's program cache:

```stata
discard
```

The simplest way to refresh an existing installation is to reinstall with
`replace`:

```stata
net install wttreport, from("https://raw.githubusercontent.com/Louis8102/wttreport/main/") replace
```

Copy the example dataset and example do-file into the current working directory:

```stata
net get wttreport, from("https://raw.githubusercontent.com/Louis8102/wttreport/main/") replace
```

Check the installed version:

```stata
which wttreport
```

The current version should display:

```stata
*! version 0.2.0-preview  03jul2026
```

## Basic use

Single grouping variable, full report:

```stata
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(report_gender) ///
    replace
```

By default, `wttreport` displays FDR-significant outcomes only. To display all
outcomes in the table, plots, and summary inputs, add `show(all)`:

```stata
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(report_gender_all) ///
    show(all) ///
    replace
```

When `show(all)` is used, effect-size figures display FDR-significant items
with filled circles and non-FDR-significant items with hollow diamonds.

### Single grouping variable: selected report components

Create only the Welch t-test table:

```stata
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(gender_table_only) ///
    noplot nosummary ///
    replace
```

Create only the effect-size figure section:

```stata
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(gender_plot_only) ///
    notable nosummary ///
    plotcombine(6) plotlayout(vertical) plotlabelmode(item) ///
    replace
```

Create only the narrative summary and appendix:

```stata
wttreport item1-item60, ///
    by(gender) ///
    blockfromchar ///
    outdir(gender_summary_only) ///
    notable noplot ///
    summarystyle(brief) ///
    replace
```

### Multiple grouping variables

Create one complete Word report for each grouping variable:

```stata
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work) ///
    blockfromchar ///
    outdir(report_all) ///
    summarystyle(brief) ///
    replace
```

Create only tables for multiple grouping variables:

```stata
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work) ///
    blockfromchar ///
    outdir(report_tables_only) ///
    noplot nosummary ///
    replace
```

Create only figures for multiple grouping variables:

```stata
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work) ///
    blockfromchar ///
    outdir(report_figures_only) ///
    notable nosummary ///
    plotcombine(6) plotlayout(vertical) plotlabelmode(item) ///
    replace
```

Create only summaries for multiple grouping variables:

```stata
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work) ///
    blockfromchar ///
    outdir(report_summaries_only) ///
    notable noplot ///
    summarystyle(brief) ///
    replace
```

Plots are generated quietly. By default, `wttreport` combines up to six block
panels into one vertically arranged figure and inserts the figure into the Word
report on a landscape page. The summary section begins on a portrait page, and
the appendix block-level table is placed on a landscape page. Intermediate
image files are removed after they are inserted. Users can request fewer panels
per figure, for example `plotcombine(4)`,
`plotcombine(3)`, or `plotcombine(2)`.

If no outcome is FDR-significant for a grouping variable, the plot section is
not omitted. Instead, `wttreport` inserts a short note explaining that no
effect-size comparison plot was produced.

The default output organization is `output(report)`: each grouping variable
gets one complete Word report.

```text
report_all/
  mapping.docx
  gender.docx
  company_site.docx
  high_workload.docx
  remote_work.docx
  tables/
  summaries/
  results/
```

Each grouping-variable report can contain the table, plot pages, and summary
for that specific comparison. This default is designed for human reading: open
`gender.docx` for the gender comparison, `company_site.docx` for the company
site comparison, and so on.

If you prefer one file for all tables, one file for all figures, and one file
for all summaries, use `output(component)`:

```stata
wttreport item1-item60, ///
    byvars(gender company_site high_workload remote_work) ///
    blockfromchar ///
    outdir(report_components) ///
    output(component) ///
    replace
```

## Current output structure

With `output(component)`, the main outputs are:

```text
report_components/
  mapping.docx
  wttreport_tables.docx
  wttreport_figures.docx
  wttreport_summaries.docx
  wttreport_manifest.txt
  tables/
  summaries/
  results/
```

For each grouping variable, `wttreport` creates:

- an APA-style Welch t-test table and results dataset;
- effect-size figures;
- brief or academic narrative summaries.

The component files are retained in their subfolders for checking or later
editing.

## Important design note

This is an early report-controller release. It preserves the table, figure, and summary styles developed for this reporting system and organizes them into a single workflow.

## Grouping variables

Each variable in `by()` or `byvars()` must have exactly two nonmissing levels in
the analysis sample.

By default, `wttreport` uses a common complete-case analytic sample. With
`by()`, the sample is defined by the grouping variable and all requested
outcomes. With `byvars()`, the sample is defined by all listed grouping
variables and all requested outcomes, so all grouping-variable reports are based
on the same analytic sample. Specify `availablecase` only when missingness is
substantial and outcome- or grouping-variable-specific samples are preferred.

## Author

Hao Ma

