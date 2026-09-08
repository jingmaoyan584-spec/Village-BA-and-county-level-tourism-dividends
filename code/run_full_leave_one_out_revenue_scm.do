version 17.0
clear all
set more off
set linesize 255

* Complete leave-one-out sensitivity for the formal non-nested revenue SCM.
* Each specification removes exactly one of the 15 donor counties and otherwise
* retains the frozen predictor set, 2015-2021 fitting period, and 2022 treatment date.

local root "`c(pwd)'"
local outdir "`root'/output/full_leave_one_out_revenue_scm"
local paneldta "`root'/output/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid 6

cap mkdir "`outdir'"
capture log close
log using "`outdir'/full_leave_one_out_revenue_scm.log", text replace

cap which synth
if _rc ssc install synth, replace
cap which esttab
if _rc ssc install estout, replace

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
xtset county_id year

capture confirm variable ln_rev
if _rc gen double ln_rev = ln(tour_rev_bn)
capture confirm variable ln_vis
if _rc gen double ln_vis = ln(tour_vis_10k)
capture confirm variable ln_pcgdp
if _rc gen double ln_pcgdp = ln(pcgdp)
capture confirm variable ln_pop
if _rc gen double ln_pop = ln(pop_10k)
capture confirm variable ln_budrev
if _rc gen double ln_budrev = ln(bud_rev_10k)
capture confirm variable ln_budexp
if _rc gen double ln_budexp = ln(bud_exp_10k)
assert !missing(ln_rev, ln_vis, ln_pcgdp, ln_pop, ln_budrev, ln_budexp)

tempfile panel lookup baseline_weights loo_results
save `panel', replace
preserve
keep county_id county
duplicates drop
save `lookup', replace
restore

* Baseline formal non-nested SCM and its donor weights.
tempfile baseline_fit
quietly synth ln_rev ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
    ln_rev(2015) ln_rev(2016) ln_rev(2017) ln_rev(2018) ///
    ln_rev(2019) ln_rev(2020) ln_rev(2021), ///
    trunit(`trid') trperiod(2022) xperiod(2015(1)2021) ///
    mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
    keep("`baseline_fit'") replace

matrix W = e(W_weights)
clear
svmat double W
rename W1 county_id
rename W2 baseline_weight
merge 1:1 county_id using `lookup', nogen keep(match)
keep if county_id != `trid'
quietly summarize baseline_weight, meanonly
replace baseline_weight = baseline_weight / r(sum)
keep county_id county baseline_weight
gsort -baseline_weight county
save `baseline_weights', replace
export delimited using "`outdir'/table_s6a_baseline_revenue_scm_donor_weights.csv", replace
export excel using "`outdir'/table_s6a_baseline_revenue_scm_donor_weights.xlsx", firstrow(variables) replace

use `panel', clear
quietly levelsof county_id if county_id != `trid', local(donor_ids)

tempname results_post
postfile `results_post' long excluded_county_id str9 excluded_county ///
    double baseline_weight pre_rmspe post_rmspe rmspe_ratio ///
    gap_2022 gap_2023 gap_2024 mean_gap_2023_2024 ///
    effect_2022_pct effect_2023_2024_pct using `loo_results', replace

foreach did of local donor_ids {
    use `baseline_weights', clear
    quietly summarize baseline_weight if county_id == `did', meanonly
    local weight = r(mean)
    quietly levelsof county if county_id == `did', local(dname) clean

    tempfile fit
    use `panel', clear
    drop if county_id == `did'
    quietly synth ln_rev ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
        ln_rev(2015) ln_rev(2016) ln_rev(2017) ln_rev(2018) ///
        ln_rev(2019) ln_rev(2020) ln_rev(2021), ///
        trunit(`trid') trperiod(2022) xperiod(2015(1)2021) ///
        mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
        keep("`fit'") replace

    use `fit', clear
    capture confirm variable year
    if _rc rename _time year
    gen double gap = _Y_treated - _Y_synthetic
    gen double sqgap = gap^2
    quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
    local pre = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
    local post = sqrt(r(mean))
    quietly summarize gap if year == 2022, meanonly
    local g22 = r(mean)
    quietly summarize gap if year == 2023, meanonly
    local g23 = r(mean)
    quietly summarize gap if year == 2024, meanonly
    local g24 = r(mean)
    local gpost = (`g23' + `g24') / 2
    post `results_post' (`did') ("`dname'") (`weight') (`pre') (`post') ///
        (`post'/`pre') (`g22') (`g23') (`g24') (`gpost') ///
        (100 * (exp(`g22') - 1)) (100 * (exp(`gpost') - 1))
}
postclose `results_post'

use `loo_results', clear
gsort -baseline_weight excluded_county
rename excluded_county excluded_donor
label variable excluded_donor "Excluded donor"
label variable excluded_county_id "Excluded donor ID"
order excluded_donor excluded_county_id baseline_weight pre_rmspe post_rmspe rmspe_ratio ///
    gap_2022 gap_2023 gap_2024 mean_gap_2023_2024 effect_2022_pct effect_2023_2024_pct
format baseline_weight pre_rmspe post_rmspe rmspe_ratio gap_* mean_gap_* %9.3f
format effect_* %9.2f
export delimited using "`outdir'/table_s6_full_leave_one_out_revenue_scm.csv", replace
export excel using "`outdir'/table_s6_full_leave_one_out_revenue_scm.xlsx", firstrow(variables) replace
save "`outdir'/table_s6_full_leave_one_out_revenue_scm.dta", replace

mkmat baseline_weight pre_rmspe post_rmspe rmspe_ratio effect_2022_pct effect_2023_2024_pct, matrix(loo_mat)
local rownames ""
forvalues r = 1/`=_N' {
    local rn = strtoname(excluded_donor[`r'])
    local rownames "`rownames' `rn'"
}
matrix rownames loo_mat = `rownames'
matrix colnames loo_mat = baseline_weight pre_rmspe post_rmspe rmspe_ratio effect_2022_pct effect_2023_2024_pct
local rtf_raw "`outdir'/table_s6_full_leave_one_out_revenue_scm_raw.rtf"
esttab matrix(loo_mat, fmt(3 3 3 3 2 2)) using "`rtf_raw'", replace ///
    title("Supplementary Table S6. Complete leave-one-out sensitivity: revenue SCM") ///
    varlabels(, lhs("Excluded donor")) ///
    collabels("Baseline weight" "Pre-treatment RMSPE" "Post-treatment RMSPE" ///
        "RMSPE ratio" "2022 effect (%)" "2023-2024 effect (%)") ///
    nomtitles nonumber ///
    addnotes("Each row excludes one donor county from the formal non-nested revenue SCM.", ///
        "All specifications retain the 2015-2021 fitting period, 2022 treatment date, and frozen predictor set.", ///
        "Percentage effects equal 100*[exp(log gap)-1]; 2023-2024 uses the mean log gap before transformation.")

* esttab leaves the matrix stub heading blank; make its meaning explicit in the final RTF.
capture erase "`outdir'/table_s6_full_leave_one_out_revenue_scm_final.rtf"
filefilter "`rtf_raw'" "`outdir'/table_s6_full_leave_one_out_revenue_scm_final.rtf", ///
    from("\BSpard\BSintbl\BSql {}\BScell") to("\BSpard\BSintbl\BSql {Excluded donor}\BScell") replace

count if effect_2022_pct > 0 & effect_2023_2024_pct > 0
local positive_both = r(N)
count
local total = r(N)

file open note using "`outdir'/readme.txt", write replace
file write note "Complete leave-one-out sensitivity for the formal non-nested tourism-revenue SCM." _n
file write note "Each of the `total' donor counties is excluded once; Taijiang remains the treated unit." _n
file write note "Positive 2022 and 2023-2024 effects after exclusion: `positive_both' of `total' donor deletions." _n
file close note

display as result "Complete leave-one-out SCM completed: `positive_both' of `total' deletions retain positive effects in both periods."
log close
