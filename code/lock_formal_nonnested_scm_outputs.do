version 17.0
clear all
set more off
set linesize 255

* Locks all baseline SCM objects from the formal uniform non-nested specification.
local root     "`c(pwd)'"
local outdir   "`root'/output"
local lockdir  "`outdir'/formal_nonnested_scm_locked"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid     6

cap mkdir "`lockdir'"
capture log close
log using "`lockdir'/lock_formal_nonnested_scm_outputs.log", text replace
cap which synth
if _rc ssc install synth, replace
cap which esttab
if _rc ssc install estout, replace

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
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
assert !missing(ln_rev, ln_vis, ln_pcgdp, ln_pop, ln_budrev, ln_budexp)
tempfile panel lookup paths summary donorweights predictorweights
save `panel', replace
preserve
keep county county_id
duplicates drop
isid county_id
save `lookup', replace
restore

tempname pathpost sumpost donorpost predpost
postfile `pathpost' str20 outcome int year double actual synthetic gap using `paths', replace
postfile `sumpost' str20 outcome double pre_rmspe post_rmspe rmspe_ratio gap_2022 ///
    mean_gap_2023_2024 pct_2022 pct_2023_2024 using `summary', replace
postfile `donorpost' str20 outcome int county_id double donor_weight using `donorweights', replace
postfile `predpost' str20 outcome str32 predictor double predictor_weight_raw predictor_weight_normalized using `predictorweights', replace

foreach yvar in ln_rev ln_vis {
    if "`yvar'" == "ln_rev" {
        local other "ln_vis"
        local outcome "Tourism revenue"
        local predictors "ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ln_rev_2015 ln_rev_2016 ln_rev_2017 ln_rev_2018 ln_rev_2019 ln_rev_2020 ln_rev_2021"
    }
    else {
        local other "ln_rev"
        local outcome "Tourist visitors"
        local predictors "ln_rev ln_pcgdp ln_pop ln_budrev ln_budexp ln_vis_2015 ln_vis_2016 ln_vis_2017 ln_vis_2018 ln_vis_2019 ln_vis_2020 ln_vis_2021"
    }
    tempfile fit
    use `panel', clear
    quietly synth `yvar' `other' ln_pcgdp ln_pop ln_budrev ln_budexp ///
        `yvar'(2015) `yvar'(2016) `yvar'(2017) `yvar'(2018) ///
        `yvar'(2019) `yvar'(2020) `yvar'(2021), ///
        trunit(`trid') trperiod(2022) xperiod(2015(1)2021) ///
        mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
        keep("`fit'") replace

    matrix W = e(W_weights)
    clear
    svmat double W
    rename W1 county_id
    rename W2 donor_weight
    quietly levelsof county_id, local(donorids)
    foreach did of local donorids {
        quietly summarize donor_weight if county_id == `did', meanonly
        post `donorpost' ("`outcome'") (`did') (r(mean))
    }

    * synth returns a symmetric V matrix. Its diagonal contains the predictor
    * weights, whose scale is arbitrary; report both raw and sum-normalized values.
    matrix Vdiag = vecdiag(e(V_matrix))'
    clear
    svmat double Vdiag
    rename Vdiag1 predictor_weight_raw
    quietly summarize predictor_weight_raw, meanonly
    gen double predictor_weight_normalized = predictor_weight_raw / r(sum)
    gen str32 predictor = ""
    local p = 0
    foreach pname of local predictors {
        local ++p
        replace predictor = "`pname'" in `p'
    }
    assert _N == `p'
    forvalues j = 1/`=_N' {
        post `predpost' ("`outcome'") (predictor[`j']) ///
            (predictor_weight_raw[`j']) (predictor_weight_normalized[`j'])
    }

    use `fit', clear
    capture confirm variable year
    if _rc rename _time year
    gen double gap = _Y_treated - _Y_synthetic
    gen double sqgap = gap^2
    quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
    scalar pre = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
    scalar post = sqrt(r(mean))
    quietly summarize gap if year == 2022, meanonly
    scalar g22 = r(mean)
    quietly summarize gap if inrange(year, 2023, 2024), meanonly
    scalar gpost = r(mean)
    post `sumpost' ("`outcome'") (pre) (post) (post/pre) (g22) (gpost) ///
        (100*(exp(g22)-1)) (100*(exp(gpost)-1))
    forvalues yy = 2015/2024 {
        quietly summarize _Y_treated if year == `yy', meanonly
        scalar actual = r(mean)
        quietly summarize _Y_synthetic if year == `yy', meanonly
        scalar synthetic = r(mean)
        quietly summarize gap if year == `yy', meanonly
        post `pathpost' ("`outcome'") (`yy') (actual) (synthetic) (r(mean))
    }
}
postclose `pathpost'
postclose `sumpost'
postclose `donorpost'
postclose `predpost'

use `summary', clear
format pre_rmspe post_rmspe rmspe_ratio gap_2022 mean_gap_2023_2024 pct_2022 pct_2023_2024 %9.3f
export delimited using "`lockdir'/table_m1_scm_summary.csv", replace
export excel using "`lockdir'/table_m1_scm_summary.xlsx", firstrow(variables) replace
mkmat pre_rmspe post_rmspe rmspe_ratio gap_2022 mean_gap_2023_2024 pct_2022 pct_2023_2024, matrix(main_summary)
matrix rownames main_summary = tourism_revenue tourist_visitors
esttab matrix(main_summary, fmt(3 3 3 3 3 2 2)) using "`lockdir'/table_m1_scm_summary.rtf", replace ///
    title("Formal non-nested SCM estimates") ///
    collabels("Pre-RMSPE" "Post-RMSPE" "RMSPE ratio" "2022 gap" "2023-2024 mean gap" "2022 effect (%)" "2023-2024 effect (%)") ///
    nomtitles nonumber varlabels(tourism_revenue "Tourism revenue" tourist_visitors "Tourist visitors") ///
    addnotes("Gaps are treated-minus-synthetic log points. Percentage effects equal 100*[exp(gap)-1].")

use `paths', clear
format actual synthetic gap %9.6f
export delimited using "`lockdir'/table_m2_actual_synthetic_annual_paths.csv", replace
export excel using "`lockdir'/table_m2_actual_synthetic_annual_paths.xlsx", firstrow(variables) replace

use `donorweights', clear
merge m:1 county_id using `lookup', keep(master match)
count if _merge != 3
if r(N) > 0 {
    list county_id donor_weight county _merge if _merge != 3, noobs abbreviate(24)
    di as error "SCM donor-weight IDs did not map cleanly to county names."
    exit 459
}
drop _merge
gsort outcome -donor_weight
format donor_weight %9.6f
export delimited using "`lockdir'/table_m3_donor_weights.csv", replace
export excel using "`lockdir'/table_m3_donor_weights.xlsx", firstrow(variables) replace

use `predictorweights', clear
format predictor_weight_raw predictor_weight_normalized %12.6f
export delimited using "`lockdir'/table_m4_predictor_weights.csv", replace
export excel using "`lockdir'/table_m4_predictor_weights.xlsx", firstrow(variables) replace

file open note using "`lockdir'/readme.txt", write replace
file write note "Formal SCM specification: non-nested synth; predictors and fitting period match the original baseline." _n
file write note "Fitting period: 2015-2021. Intervention year: 2022. Results period: 2015-2024." _n
file close note
log close
display as result "Formal non-nested SCM outputs locked."
