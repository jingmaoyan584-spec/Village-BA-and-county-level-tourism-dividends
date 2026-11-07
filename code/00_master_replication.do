version 17.0
clear all
set more off
set linesize 255

********************************************************************************
* Village BA replication package
* May be run from the package top folder or directly from Stata's Do-file Editor.
* The code below automatically locates the package root when this file is saved
* in the code/ subfolder.
*
* Input:  data/qiandongnan_county_panel_2015_2024_analysis_ready.dta
* Output: output/supplementary_tables_final_rtf/S1_Table_*.rtf through S6_Table_*.rtf
********************************************************************************

local datafile "qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local root "`c(pwd)'"
local input "`root'/data/`datafile'"

* If Stata's current directory is not the package root, derive the root from
* this do-file's own path (the parent of code/).
capture confirm file "`input'"
if _rc {
    capture confirm file "`root'/../data/`datafile'"
    if !_rc local root "`root'/.."
}

local input "`root'/data/`datafile'"
capture confirm file "`input'"
if _rc {
    local thisfile = subinstr("`c(filename)'", char(92), "/", .)
    local slash = strrpos("`thisfile'", "/")
    if `slash' > 0 {
        local codedir = substr("`thisfile'", 1, `slash' - 1)
        local parentslash = strrpos("`codedir'", "/")
        if `parentslash' > 0 {
            local candidate = substr("`codedir'", 1, `parentslash' - 1)
            capture confirm file "`candidate'/data/`datafile'"
            if !_rc local root "`candidate'"
        }
    }
}

local input "`root'/data/`datafile'"
local output "`root'/output/`datafile'"

capture confirm file "`input'"
if _rc {
    di as error "Replication package root could not be located."
    di as error "Required input data not found: `input'"
    exit 601
}

cd "`root'"

cap mkdir "`root'/output"
copy "`input'" "`output'", replace

capture log close
log using "`root'/output/00_master_replication.log", text replace

* Required community-contributed commands. Existing installations are retained.
foreach package in synth sdid estout {
    capture which `package'
    if _rc ssc install `package', replace
}

* Data integrity: balanced 16-county x 10-year panel, corrected Kaili values,
* and the final 2024 tourism-revenue observations for all 16 counties.
do "code/audit_final_analysis_data.do"

* Main-manuscript baseline SDID with placebo-based standard errors and CIs.
do "code/run_baseline_sdid_placebo_1000.do"

* Formal baseline non-nested SCM. Produces predictor V-weights for S1.
do "code/lock_formal_nonnested_scm_outputs.do"

* Matching-weighted TWFE diagnostics. Produces the balance data for S2 and
* regenerates the full-procedure donor bootstrap with 1,000 replications.
do "code/run_weighted_twfe_generated_weight_bootstrap.do" 1000

* Log-SCM monetary context for S3.
do "code/build_baseline_scm_absolute_revenue_table.do"

* Complete 15-donor leave-one-out revenue-SCM sensitivity for S4.
do "code/run_full_leave_one_out_revenue_scm.do"

* COVID holdout SCM diagnostics for S5, plus COVID-excluded SDID/TWFE checks.
do "code/taijiang_covid_robustness_and_inference.do"

* Level-outcome SDID sensitivity for S6.
do "code/run_level_revenue_baseline_check.do"

* Export all manuscript supplementary tables as submission-ready RTF files.
do "code/export_final_supplementary_tables_rtf.do"

* Full matching-weighted TWFE regression table with Webb wild-cluster p-values.
do "code/export_s7_full_matching_weighted_twfe.do" 9999

capture log close
display as result "Replication completed. Final tables are in output/supplementary_tables_final_rtf/."
