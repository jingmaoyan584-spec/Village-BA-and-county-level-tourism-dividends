version 17.0
clear all
set more off

* Re-estimate the frozen baseline log-SCM specification and convert its fit path
* back to RMB-billion levels. The source variable is in 100 million yuan, so
* level amounts are divided by 10. This is contextualization, not a new estimator.
local root "`c(pwd)'"
local outdir "`root'/output"
local rundir "`outdir'/level_revenue_sensitivity"

* The master replication may start from a clean output folder.
cap mkdir "`rundir'"

use "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta", clear
xtset county_id year
capture confirm variable ln_rev
if _rc gen ln_rev = ln_tour_rev
capture confirm variable ln_vis
if _rc gen ln_vis = ln_tour_vis
capture confirm variable ln_pcgdp
if _rc gen ln_pcgdp = ln(pcgdp)
capture confirm variable ln_pop
if _rc gen ln_pop = ln(pop_10k)
capture confirm variable ln_budrev
if _rc gen ln_budrev = ln(bud_rev_10k)
capture confirm variable ln_budexp
if _rc gen ln_budexp = ln(bud_exp_10k)
tempfile scm_log_final
synth ln_rev ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
    ln_rev(2015) ln_rev(2016) ln_rev(2017) ln_rev(2018) ///
    ln_rev(2019) ln_rev(2020) ln_rev(2021), ///
    trunit(6) trperiod(2022) xperiod(2015(1)2021) ///
    mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
    keep("`scm_log_final'") replace

use "`scm_log_final'", clear
capture confirm variable _time
if !_rc rename _time year
rename _Y_treated actual_log_revenue
rename _Y_synthetic synthetic_log_revenue
keep if inrange(year, 2022, 2024)
gen actual_revenue_rmb_billion = exp(actual_log_revenue) / 10
gen synthetic_revenue_rmb_billion = exp(synthetic_log_revenue) / 10
gen absolute_gap_rmb_billion = actual_revenue_rmb_billion - synthetic_revenue_rmb_billion
gen gap_log_points = actual_log_revenue - synthetic_log_revenue
gen implied_percentage_effect = 100 * (exp(gap_log_points) - 1)
keep year actual_revenue_rmb_billion synthetic_revenue_rmb_billion absolute_gap_rmb_billion ///
    gap_log_points implied_percentage_effect
format actual_revenue_rmb_billion synthetic_revenue_rmb_billion absolute_gap_rmb_billion %9.3f
format gap_log_points %9.3f
format implied_percentage_effect %9.2f
export delimited using "`rundir'/table_l2_baseline_log_scm_absolute_revenue_gaps.csv", replace
export excel using "`rundir'/table_l2_baseline_log_scm_absolute_revenue_gaps.xlsx", firstrow(variables) replace

mkmat actual_revenue_rmb_billion synthetic_revenue_rmb_billion absolute_gap_rmb_billion gap_log_points implied_percentage_effect, matrix(abs_scm_mat)
matrix rownames abs_scm_mat = year_2022 year_2023 year_2024
cap which esttab
if _rc ssc install estout, replace
esttab matrix(abs_scm_mat, fmt(3 3 3 3 2)) using ///
    "`rundir'/table_l2_baseline_log_scm_absolute_revenue_gaps.rtf", replace ///
    title("Baseline log-SCM revenue gaps in absolute terms (RMB billion)") ///
    collabels("Actual revenue" "Synthetic revenue" "Absolute gap" "Log gap" "Effect (%)") ///
    nomtitles varlabels(year_2022 "2022" year_2023 "2023" year_2024 "2024") noobs nonumber
