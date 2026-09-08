version 17.0
clear all
set more off
set linesize 255
set varabbrev off

********************************************************************************
* Village BA: complete Stata replication file for journal submission
*
* Run this file from the top folder of the replication package:
*   cd ".../village_ba_replication_package"
*   do "replication_all_results.do"
*
* The file reads only the final analysis-ready .dta in data/. It does not
* import CSV files for estimation and does not use absolute local paths.
*
* Main estimators and outputs regenerated:
*   - data audit and corrected 16 x 10 panel check
*   - baseline SDID: 1,000 placebo replications
*   - formal non-nested SCM and annual paths
*   - in-space placebo and RMSPE diagnostics under the same SCM specification
*   - matching-weighted TWFE and generated-weight donor bootstrap: 1,000 reps
*   - Webb wild-cluster p-values for S7: 9,999 reps
*   - S1-S7 supplementary RTF tables
*   - complete 15-donor leave-one-out, COVID, and level-outcome sensitivity
*
* Fixed seed used by all stochastic procedures: 20260820.
********************************************************************************

local root "`c(pwd)'"
local input "`root'/data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local output "`root'/output/qiandongnan_county_panel_2015_2024_analysis_ready.dta"

capture confirm file "`input'"
if _rc {
    di as error "Required input not found: `input'"
    di as error "Change Stata's working directory to the replication package top folder."
    exit 601
}

cap mkdir "`root'/output"
copy "`input'" "`output'", replace

capture log close
log using "`root'/output/replication_all_results.log", text replace

* Install only if absent; no package is reinstalled when already available.
foreach package in synth sdid estout {
    capture which `package'
    if _rc {
        quietly ssc install `package', replace
    }
}

* 1. Data integrity and final-data audit.
do "code/audit_final_analysis_data.do"

* 2. Main-manuscript baseline SDID, both outcomes and both stages.
do "code/run_baseline_sdid_placebo_1000.do"

* 3. Formal uniform non-nested SCM, both outcomes, annual gaps, weights,
*    predictor V-weights, and in-space placebo diagnostics.
do "code/lock_formal_nonnested_scm_outputs.do"

* 4. Matching-weighted TWFE, balance diagnostics, and full-procedure donor
*    bootstrap that re-estimates features, weights, and TWFE in every draw.
do "code/run_weighted_twfe_generated_weight_bootstrap.do" 1000

* 5. Baseline log-SCM monetary conversion and level-SCM context.
do "code/build_baseline_scm_absolute_revenue_table.do"

* 6. Complete leave-one-out sensitivity for all 15 donors.
do "code/run_full_leave_one_out_revenue_scm.do"

* 7. COVID sensitivity: 2015-2019 SCM fitting, 2020-2021 untreated holdout,
*    COVID-excluded SDID, and COVID-excluded matching-weighted TWFE.
do "code/taijiang_covid_robustness_and_inference.do"

* 8. Level-outcome SCM and SDID sensitivity for tourism revenue.
do "code/run_level_revenue_baseline_check.do"

* 9. Submission-ready supplementary RTF tables S1-S6.
do "code/export_final_supplementary_tables_rtf.do"

* 10. Full matching-weighted TWFE regression table S7, including Webb
*     wild-cluster p-values for treatment coefficients.
do "code/export_s7_full_matching_weighted_twfe.do" 9999

capture log close
display as result "Complete replication finished successfully."
display as result "Main results: `root'/output/baseline_sdid/"
display as result "Supplementary tables S1-S7: `root'/output/supplementary_tables_final_rtf/"
