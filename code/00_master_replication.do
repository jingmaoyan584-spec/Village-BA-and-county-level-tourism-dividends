version 17.0
clear all
set more off
set linesize 255

********************************************************************************
* Village BA replication package
* Run after changing Stata's working directory to this package's top folder.
* Example:
*   cd ".../village_ba_replication_package"
*   do "code/00_master_replication.do"
*
* Input:  data/qiandongnan_county_panel_2015_2024_analysis_ready.dta
* Output: output/supplementary_tables_final_rtf/S1_Table_*.rtf through S6_Table_*.rtf
********************************************************************************

local root "`c(pwd)'"
local input "`root'/data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local output "`root'/output/qiandongnan_county_panel_2015_2024_analysis_ready.dta"

capture confirm file "`input'"
if _rc {
    di as error "Run this file from the replication package top folder."
    di as error "Required input data not found: `input'"
    exit 601
}

cap mkdir "`root'/output"
copy "`input'" "`output'", replace

capture log close
log using "`root'/output/00_master_replication.log", text replace

* Required community-contributed commands. Existing installations are retained.
foreach package in synth sdid estout {
    capture which `package'
    if _rc ssc install `package', replace
}

* Data integrity: balanced 16-county x 10-year panel and corrected Kaili values.
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
