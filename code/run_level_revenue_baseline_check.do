version 17.0
clear all
set more off
set linesize 255

* Level-outcome sensitivity for the low-baseline concern. The source variable
* tour_rev_bn is measured in 100 million yuan; reported monetary results below
* are converted to RMB billion by dividing by 10.
local root "`c(pwd)'"
local outdir "`root'/output"
local rundir "`outdir'/level_revenue_sensitivity"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid 6
cap mkdir "`rundir'"
capture log close
log using "`rundir'/level_revenue_sensitivity.log", text replace

cap which synth
if _rc ssc install synth, replace
cap which sdid
if _rc ssc install sdid, replace
cap which esttab
if _rc ssc install estout, replace

use "`paneldta'", clear
xtset county_id year
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

* 1. Baseline comparison: county-level 2015-2021 mean revenue in RMB billion.
preserve
keep if inrange(year, 2015, 2021)
gen tour_rev_rmb_billion = tour_rev_bn / 10
collapse (mean) mean_rev_rmbbn = tour_rev_rmb_billion, by(county county_id)
quietly summarize mean_rev_rmbbn if county_id != `trid', detail
scalar donor_mean = r(mean)
scalar donor_median = r(p50)
quietly summarize mean_rev_rmbbn if county_id == `trid', meanonly
scalar taijiang_pre_mean = r(mean)
keep if county_id == `trid'
gen donor_mean_rmbbn = donor_mean
gen donor_median_rmbbn = donor_median
gen taijiang_to_donor_mean = mean_rev_rmbbn / donor_mean
gen taijiang_to_donor_median = mean_rev_rmbbn / donor_median
rename mean_rev_rmbbn taijiang_mean_rmbbn
export delimited using "`rundir'/table_l1_pre_treatment_revenue_base.csv", replace
export excel using "`rundir'/table_l1_pre_treatment_revenue_base.xlsx", firstrow(variables) replace
restore

* 2. SCM in levels. Predictors match the baseline specification except that
* revenue history is retained in original billion-yuan units.
tempfile scm_level
synth tour_rev_bn ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
    tour_rev_bn(2015) tour_rev_bn(2016) tour_rev_bn(2017) tour_rev_bn(2018) ///
    tour_rev_bn(2019) tour_rev_bn(2020) tour_rev_bn(2021), ///
    trunit(`trid') trperiod(2022) xperiod(2015(1)2021) ///
    mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
    keep("`scm_level'") replace

preserve
use "`scm_level'", clear
capture confirm variable _time
if !_rc rename _time year
rename _Y_treated actual_revenue_100m_yuan
rename _Y_synthetic synthetic_revenue_100m_yuan
gen actual_revenue_rmb_billion = actual_revenue_100m_yuan / 10
gen synthetic_revenue_rmb_billion = synthetic_revenue_100m_yuan / 10
gen absolute_gap_rmb_billion = actual_revenue_rmb_billion - synthetic_revenue_rmb_billion
gen percentage_gap = 100 * absolute_gap_rmb_billion / synthetic_revenue_rmb_billion
gen sqgap = absolute_gap_rmb_billion^2
quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
scalar scm_level_pre_rmspe = sqrt(r(mean))
quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
scalar scm_level_post_rmspe = sqrt(r(mean))
keep if inrange(year, 2022, 2024)
export delimited using "`rundir'/table_l2_scm_revenue_levels_post.csv", replace
export excel using "`rundir'/table_l2_scm_revenue_levels_post.xlsx", firstrow(variables) replace
restore

* 3. SDID in levels: report absolute ATTs in billion yuan, placebo VCE.
tempname levelpost
tempfile level_sdid
postfile `levelpost' str12 period double att_rmb_billion placebo_se_rmb_billion ci_lo_95_rmb_billion ci_hi_95_rmb_billion pvalue reps using `level_sdid', replace

preserve
keep if inrange(year, 2015, 2022)
gen treated_2022 = county_id == `trid' & year >= 2022
sdid tour_rev_bn county_id year treated_2022, vce(placebo) reps(1000) seed(20260820)
scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
scalar lo = e(ATT) - invnormal(.975) * e(se)
scalar hi = e(ATT) + invnormal(.975) * e(se)
post `levelpost' ("2022") (e(ATT)/10) (e(se)/10) (lo/10) (hi/10) (p) (1000)
restore

preserve
keep if inrange(year, 2015, 2024) & year != 2022
egen time_id = group(year)
gen treated_post = county_id == `trid' & year >= 2023
sdid tour_rev_bn county_id time_id treated_post, vce(placebo) reps(1000) seed(20260820)
scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
scalar lo = e(ATT) - invnormal(.975) * e(se)
scalar hi = e(ATT) + invnormal(.975) * e(se)
post `levelpost' ("2023-2024") (e(ATT)/10) (e(se)/10) (lo/10) (hi/10) (p) (1000)
restore
postclose `levelpost'

use `level_sdid', clear
export delimited using "`rundir'/table_l3_sdid_revenue_levels.csv", replace
export excel using "`rundir'/table_l3_sdid_revenue_levels.xlsx", firstrow(variables) replace
mkmat att_rmb_billion placebo_se_rmb_billion ci_lo_95_rmb_billion ci_hi_95_rmb_billion pvalue, matrix(sdid_level_mat)
matrix rownames sdid_level_mat = effect_2022 effect_2023_2024
esttab matrix(sdid_level_mat, fmt(3 3 3 3 3)) using ///
    "`rundir'/table_l3_sdid_revenue_levels.rtf", replace ///
    title("Level-outcome SDID sensitivity: tourism revenue (RMB billion)") ///
    collabels("ATT" "Placebo SE" "95% CI lower" "95% CI upper" "p-value") ///
    nomtitles varlabels(effect_2022 "2022" effect_2023_2024 "2023-2024") noobs nonumber

file open note using "`rundir'/readme.txt", write replace
file write note "Source tourism revenue is measured in 100 million yuan; outputs are converted to RMB billion." _n
file write note "SCM levels uses the formal non-nested implementation and gives observed revenue, synthetic revenue, and absolute gaps for each post-treatment year." _n
file write note "SDID levels uses vce(placebo), reps(1000), seed(20260820)." _n
file close note

display as result "Level-revenue sensitivity completed: `rundir'"
log close
