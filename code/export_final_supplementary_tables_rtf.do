version 17.0
clear all
set more off

* Creates the six final PLOS ONE supplementary tables from freshly reproduced outputs.
* No machine-specific path is required: run from the replication-package folder.
local root "`c(pwd)'"
local outdir "`root'/output/supplementary_tables_final_rtf"
capture mkdir "`outdir'"

cap which esttab
if _rc ssc install estout, replace

program define save_rtf_with_stub
    args matrix_name rawfile outfile table_title stub_label col_labels note_text fmt_spec
    tempfile cleanedfile

    esttab matrix(`matrix_name', fmt(`fmt_spec')) using "`rawfile'", replace ///
        title(`"`table_title'"') ///
        collabels(`col_labels') ///
        nomtitles nonumber ///
        addnotes(`"`note_text'"')

    capture erase "`outfile'"
    filefilter "`rawfile'" "`outfile'", ///
        from("\BSpard\BSintbl\BSql {}\BScell") ///
        to("\BSpard\BSintbl\BSql {`stub_label'}\BScell") replace
    erase "`rawfile'"

    * Matrix row names must be legal Stata names; make their display labels readable.
    filefilter "`outfile'" "`cleanedfile'", from("_") to(" ") replace
    copy "`cleanedfile'" "`outfile'", replace
end

* S1. SCM predictor V-weights.
import delimited using "`root'/output/formal_nonnested_scm_locked/table_m4_predictor_weights.csv", clear varnames(1)
mkmat predictor_weight_normalized, matrix(s1)
matrix colnames s1 = normalized_v_weight
local s1rows ""
forvalues i = 1/`=_N' {
    local outcome = outcome[`i']
    local predictor = predictor[`i']
    local label ""
    if "`predictor'" == "ln_vis"    local label "Log tourist visitors"
    if "`predictor'" == "ln_rev"    local label "Log tourism revenue"
    if "`predictor'" == "ln_pcgdp"  local label "Log per-capita GDP"
    if "`predictor'" == "ln_pop"    local label "Log resident population"
    if "`predictor'" == "ln_budrev" local label "Log budget revenue"
    if "`predictor'" == "ln_budexp" local label "Log budget expenditure"
    if regexm("`predictor'", "ln_rev_20") {
        local yr = substr("`predictor'", -4, 4)
        local label "Log tourism revenue, `yr'"
    }
    if regexm("`predictor'", "ln_vis_20") {
        local yr = substr("`predictor'", -4, 4)
        local label "Log tourist visitors, `yr'"
    }
    local s1label`i' "`outcome': `label'"
    local s1rows "`s1rows' R`i'"
}
matrix rownames s1 = `s1rows'
local s1labels `""Normalized V-weight""'
save_rtf_with_stub s1 ///
    "`outdir'/S1_Table_raw.rtf" ///
    "`outdir'/S1_Table_SCM_predictor_V_weights.rtf" ///
    "S1 Table. SCM predictor V-weights." ///
    "Outcome and predictor" ///
    `"`s1labels'"' ///
    "V-weights are from the formal non-nested SCM. Values close to zero indicate negligible relative predictor weight." ///
    "6"
forvalues i = 24(-1)1 {
    tempfile s1clean`i'
    filefilter "`outdir'/S1_Table_SCM_predictor_V_weights.rtf" "`s1clean`i''", ///
        from("R`i'") to("`s1label`i''") replace
    copy "`s1clean`i''" "`outdir'/S1_Table_SCM_predictor_V_weights.rtf", replace
}

* S2. Pre-treatment balance before and after matching.
import delimited using "`root'/output/weighted_twfe_inference/table_w1_pre_treatment_balance.csv", clear varnames(1)
gen reduction_pct = 100 * (standardized_gap_before - standardized_gap_after) / standardized_gap_before
mkmat taijiang_value donor_mean weighted_donor_mean standardized_gap_before standardized_gap_after reduction_pct, matrix(s2)
matrix colnames s2 = taijiang unweighted_donor weighted_donor std_gap_before std_gap_after reduction_pct
matrix rownames s2 = ///
    Mean_log_tourism_revenue Trend_log_tourism_revenue ///
    Mean_log_tourist_visitors Trend_log_tourist_visitors ///
    Mean_log_percapita_GDP Mean_log_resident_population ///
    Mean_log_budget_revenue Mean_log_budget_expenditure
local s2labels `""Taijiang" "Unweighted donor mean" "Weighted donor mean" "Standardized gap before" "Standardized gap after" "Reduction (%)""'
save_rtf_with_stub s2 ///
    "`outdir'/S2_Table_raw.rtf" ///
    "`outdir'/S2_Table_pre_treatment_balance_before_and_after_matching.rtf" ///
    "S2 Table. Pre-treatment balance before and after matching." ///
    "Pre-treatment characteristic" ///
    `"`s2labels'"' ///
    "Standardized gaps use the unweighted donor standard deviation. Matching uses the exponential kernel with lambda = 1." ///
    "3 3 3 3 3 1"

* S3. Absolute monetary context for the baseline log-SCM.
import delimited using "`root'/output/level_revenue_sensitivity/table_l2_baseline_log_scm_absolute_revenue_gaps.csv", clear varnames(1)
mkmat actual_revenue_rmb_billion synthetic_revenue_rmb_billion absolute_gap_rmb_billion gap_log_points implied_percentage_effect, matrix(s3)
matrix colnames s3 = actual synthetic absolute_gap log_gap effect_pct
matrix rownames s3 = Y2022 Y2023 Y2024
local s3labels `""Actual revenue (RMB billion)" "Synthetic revenue (RMB billion)" "Absolute gap (RMB billion)" "Log gap" "Effect (%)""'
save_rtf_with_stub s3 ///
    "`outdir'/S3_Table_raw.rtf" ///
    "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf" ///
    "S3 Table. Baseline log-SCM absolute monetary context." ///
    "Year" ///
    `"`s3labels'"' ///
    "Effects equal 100*[exp(log gap)-1]. Monetary amounts are reported in RMB billion." ///
    "3 3 3 3 2"
tempfile s3clean
filefilter "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf" "`s3clean'", ///
    from("Y2022") to("2022") replace
copy "`s3clean'" "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf", replace
tempfile s3clean2
filefilter "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf" "`s3clean2'", ///
    from("Y2023") to("2023") replace
copy "`s3clean2'" "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf", replace
tempfile s3clean3
filefilter "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf" "`s3clean3'", ///
    from("Y2024") to("2024") replace
copy "`s3clean3'" "`outdir'/S3_Table_baseline_log_SCM_absolute_monetary_context.rtf", replace

* S4. Complete 15-donor leave-one-out sensitivity analysis.
import delimited using "`root'/output/full_leave_one_out_revenue_scm/table_s6_full_leave_one_out_revenue_scm.csv", clear varnames(1)
gen excluded_donor_en = ""
replace excluded_donor_en = "Sansui" if excluded_county_id == 1
replace excluded_donor_en = "Danzhai" if excluded_county_id == 2
replace excluded_donor_en = "Congjiang" if excluded_county_id == 3
replace excluded_donor_en = "Kaili" if excluded_county_id == 4
replace excluded_donor_en = "Jianhe" if excluded_county_id == 5
replace excluded_donor_en = "Tianzhu" if excluded_county_id == 7
replace excluded_donor_en = "Cengong" if excluded_county_id == 8
replace excluded_donor_en = "Shibing" if excluded_county_id == 9
replace excluded_donor_en = "Rongjiang" if excluded_county_id == 10
replace excluded_donor_en = "Jinping" if excluded_county_id == 11
replace excluded_donor_en = "Zhenyuan" if excluded_county_id == 12
replace excluded_donor_en = "Leishan" if excluded_county_id == 13
replace excluded_donor_en = "Majiang" if excluded_county_id == 14
replace excluded_donor_en = "Huangping" if excluded_county_id == 15
replace excluded_donor_en = "Liping" if excluded_county_id == 16
mkmat baseline_weight pre_rmspe post_rmspe rmspe_ratio effect_2022_pct effect_2023_2024_pct, matrix(s4)
matrix colnames s4 = baseline_weight pre_rmspe post_rmspe rmspe_ratio effect_2022_pct effect_2023_2024_pct
local s4rows ""
forvalues i = 1/`=_N' {
    local donor = excluded_donor_en[`i']
    local s4rows "`s4rows' `donor'"
}
matrix rownames s4 = `s4rows'
local s4labels `""Baseline weight" "Pre-treatment RMSPE" "Post-treatment RMSPE" "RMSPE ratio" "2022 effect (%)" "2023-2024 effect (%)""'
save_rtf_with_stub s4 ///
    "`outdir'/S4_Table_raw.rtf" ///
    "`outdir'/S4_Table_complete_leave_one_out_revenue_SCM.rtf" ///
    "S4 Table. Complete leave-one-out sensitivity analysis for tourism-revenue SCM." ///
    "Excluded donor" ///
    `"`s4labels'"' ///
    "Each row excludes the named donor from the formal non-nested revenue SCM. All specifications retain the 2015-2021 fitting period and 2022 treatment date. Effects equal 100*[exp(log gap)-1]." ///
    "3 3 3 3 2 2"

* S5. COVID-period fitting, untreated holdout, and post-treatment diagnostics.
import delimited using "`root'/output/covid_robustness_and_inference/table_c1_scm_covid_holdout.csv", clear varnames(1)
mkmat train_rmspe holdout_rmspe post_rmspe gap_2022 gap_2022_pct gap_2023_2024 gap_2023_2024_pct, matrix(s5)
matrix colnames s5 = fitting_rmspe holdout_rmspe post_rmspe gap_2022 effect_2022_pct gap_2023_2024 effect_2023_2024_pct
matrix rownames s5 = Tourism_revenue Tourist_visitors
local s5labels `""2015-2019 fitting RMSPE" "2020-2021 untreated holdout RMSPE" "2022-2024 post-treatment RMSPE" "2022 log gap" "2022 effect (%)" "2023-2024 average log gap" "2023-2024 effect (%)""'
save_rtf_with_stub s5 ///
    "`outdir'/S5_Table_raw.rtf" ///
    "`outdir'/S5_Table_COVID_period_SCM_diagnostics.rtf" ///
    "S5 Table. COVID-period SCM fitting, untreated holdout, and post-treatment diagnostics." ///
    "Outcome" ///
    `"`s5labels'"' ///
    "SCM weights are estimated using 2015-2019 only. The 2020-2021 COVID-affected years are an untreated holdout period. Effects equal 100*[exp(log gap)-1]." ///
    "3 3 3 3 2 3 2"

* S6. Level-outcome SDID sensitivity for tourism revenue.
import delimited using "`root'/output/level_revenue_sensitivity/table_l3_sdid_revenue_levels.csv", clear varnames(1)
mkmat att_rmb_billion placebo_se_rmb_billion ci_lo_95_rmb_billion ci_hi_95_rmb_billion pvalue, matrix(s6)
matrix colnames s6 = ATT placebo_SE CI_lower CI_upper p_value
matrix rownames s6 = Y2022 Y2023_2024
local s6labels `""ATT (RMB billion)" "Placebo SE (RMB billion)" "95% CI lower" "95% CI upper" "p-value""'
save_rtf_with_stub s6 ///
    "`outdir'/S6_Table_raw.rtf" ///
    "`outdir'/S6_Table_level_outcome_SDID_sensitivity_tourism_revenue.rtf" ///
    "S6 Table. Level-outcome SDID sensitivity analysis for tourism revenue." ///
    "Period" ///
    `"`s6labels'"' ///
    "Placebo standard errors use 1,000 replications. Confidence intervals and p-values use normal approximation based on the placebo standard errors." ///
    "3 3 3 3 3"
tempfile s6clean
filefilter "`outdir'/S6_Table_level_outcome_SDID_sensitivity_tourism_revenue.rtf" "`s6clean'", ///
    from("Y2022") to("2022") replace
copy "`s6clean'" "`outdir'/S6_Table_level_outcome_SDID_sensitivity_tourism_revenue.rtf", replace
tempfile s6clean2
filefilter "`outdir'/S6_Table_level_outcome_SDID_sensitivity_tourism_revenue.rtf" "`s6clean2'", ///
    from("Y2023 2024") to("2023-2024") replace
copy "`s6clean2'" "`outdir'/S6_Table_level_outcome_SDID_sensitivity_tourism_revenue.rtf", replace

file open readme using "`outdir'/README.txt", write replace
file write readme "Final supplementary tables for the Village BA manuscript." _n
file write readme "Numbering and titles follow the manuscript's S1-S7 citations." _n
file write readme "S1-S6 are exported directly from locked analysis-result CSV files using Stata; S7 is generated from the final analysis-ready .dta." _n
file close readme

display as result "Seven final supplementary-table RTF files created in: `outdir'"
