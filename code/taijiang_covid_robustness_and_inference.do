version 17.0
clear all
set more off
set linesize 255

********************************************************************************
* COVID robustness and estimator-specific inference
* Design: 2015-2019 SCM training; 2020-2021 untreated holdout; 2022-2024 post
* Data: corrected analysis panel with Kaili 2021 budget values
********************************************************************************

local root "`c(pwd)'"
local outdir "`root'/output"
local rundir "`outdir'/covid_robustness_and_inference"
cap mkdir "`rundir'"
capture log close
log using "`rundir'/covid_robustness_and_inference.log", text replace

local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
capture confirm file "`paneldta'"
if _rc {
    di as error "Required .dta file not found: `paneldta'"
    exit 601
}

cap which synth
if _rc ssc install synth, replace
cap which sdid
if _rc ssc install sdid, replace

local trid 6
local seed 20260820

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

tempfile panel
save `panel', replace

********************************************************************************
* 1. SCM: train on 2015-2019, hold out 2020-2021, evaluate 2022-2024
********************************************************************************

tempname scmpost
tempfile scm_results
postfile `scmpost' str16 outcome str9 training_period str9 holdout_period ///
    double train_rmspe holdout_rmspe post_rmspe gap_2022 gap_2023_2024 ///
    gap_2022_pct gap_2023_2024_pct using `scm_results', replace

foreach yvar in ln_rev ln_vis {
    tempfile scmkeep
    use `panel', clear
    synth `yvar' ///
        ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
        `yvar'(2015) `yvar'(2016) `yvar'(2017) `yvar'(2018) `yvar'(2019), ///
        trunit(`trid') trperiod(2022) ///
        xperiod(2015(1)2019) mspeperiod(2015(1)2019) resultsperiod(2015(1)2024) ///
        keep("`scmkeep'") replace

    use `scmkeep', clear
    capture confirm variable _time
    if !_rc rename _time year
    gen gap = _Y_treated - _Y_synthetic
    gen sqgap = gap^2
    quietly summarize sqgap if inrange(year, 2015, 2019), meanonly
    local train_rmspe = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2020, 2021), meanonly
    local holdout_rmspe = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
    local post_rmspe = sqrt(r(mean))
    quietly summarize gap if year == 2022, meanonly
    local gap_2022 = r(mean)
    quietly summarize gap if inlist(year, 2023, 2024), meanonly
    local gap_post = r(mean)
    post `scmpost' ("`yvar'") ("2015-2019") ("2020-2021") ///
        (`train_rmspe') (`holdout_rmspe') (`post_rmspe') (`gap_2022') (`gap_post') ///
        (100*(exp(`gap_2022')-1)) (100*(exp(`gap_post')-1))

    twoway ///
        (line _Y_treated year, lcolor(black) lwidth(medthick)) ///
        (line _Y_synthetic year, lcolor(gs8) lpattern(dash) lwidth(medthick)), ///
        xline(2020 2022, lpattern(shortdash) lcolor(gs8 black)) ///
        xlabel(2015(1)2024, angle(45) labsize(small)) xscale(range(2015 2024)) ///
        xtitle("Year") ytitle("Log outcome") ///
        title("SCM trained 2015-2019: `yvar'", size(medsmall)) ///
        note("2020-2021: untreated COVID holdout; 2022-2024: treatment period", size(vsmall)) ///
        legend(order(1 "Taijiang" 2 "Synthetic Taijiang") ring(0) pos(11) col(1)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "`rundir'/scm_holdout_`yvar'.png", width(2400) replace
    graph export "`rundir'/scm_holdout_`yvar'.pdf", replace
}
postclose `scmpost'
use `scm_results', clear
export delimited using "`rundir'/table_c1_scm_covid_holdout.csv", replace
export excel using "`rundir'/table_c1_scm_covid_holdout.xlsx", firstrow(variables) replace

********************************************************************************
* 2. SDID: remove 2020-2021 for every county; placebo inference, 1,000 reps
********************************************************************************

tempname sdidpost
tempfile sdid_results
postfile `sdidpost' str16 outcome str18 period double att se ci_lo_95 ci_hi_95 pvalue reps using `sdid_results', replace

foreach yvar in ln_rev ln_vis {
    * Immediate-breakout window: 2015-2019 pre-treatment plus 2022.
    use `panel', clear
    keep if inrange(year, 2015, 2019) | year == 2022
    gen treated_2022 = county_id == `trid' & year == 2022
    sdid `yvar' county_id year treated_2022, vce(placebo) reps(1000) seed(`seed')
    scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
    scalar lo = e(ATT) - invnormal(.975) * e(se)
    scalar hi = e(ATT) + invnormal(.975) * e(se)
    post `sdidpost' ("`yvar'") ("2022") (e(ATT)) (e(se)) (lo) (hi) (p) (1000)

    * Institutionalized-expansion window: pre-2019 plus 2023-2024.
    use `panel', clear
    keep if inrange(year, 2015, 2019) | inrange(year, 2023, 2024)
    egen time_id = group(year)
    gen treated_post = county_id == `trid' & year >= 2023
    sdid `yvar' county_id time_id treated_post, vce(placebo) reps(1000) seed(`seed')
    scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
    scalar lo = e(ATT) - invnormal(.975) * e(se)
    scalar hi = e(ATT) + invnormal(.975) * e(se)
    post `sdidpost' ("`yvar'") ("2023-2024") (e(ATT)) (e(se)) (lo) (hi) (p) (1000)
}
postclose `sdidpost'
use `sdid_results', clear
gen att_pct = 100 * (exp(att) - 1)
export delimited using "`rundir'/table_c2_sdid_covid_excluded_placebo_inference.csv", replace
export excel using "`rundir'/table_c2_sdid_covid_excluded_placebo_inference.xlsx", firstrow(variables) replace

********************************************************************************
* 3. Weighted TWFE: remove 2020-2021 for every county; weights use 2015-2019
********************************************************************************

use `panel', clear
keep if inrange(year, 2015, 2019)
statsby slope_rev=_b[year], by(county_id) clear: regress ln_rev year
tempfile slope_rev
save `slope_rev', replace

use `panel', clear
keep if inrange(year, 2015, 2019)
statsby slope_vis=_b[year], by(county_id) clear: regress ln_vis year
tempfile slope_vis
save `slope_vis', replace

use `panel', clear
keep if inrange(year, 2015, 2019)
collapse (mean) mean_ln_rev=ln_rev mean_ln_vis=ln_vis mean_ln_pcgdp=ln_pcgdp ///
    mean_ln_pop=ln_pop mean_ln_budrev=ln_budrev mean_ln_budexp=ln_budexp, by(county_id)
merge 1:1 county_id using `slope_rev', nogen
merge 1:1 county_id using `slope_vis', nogen

foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
    egen z_`v' = std(`v')
    quietly summarize z_`v' if county_id == `trid', meanonly
    scalar tr_z_`v' = r(mean)
}
gen sqdist = (z_mean_ln_rev-tr_z_mean_ln_rev)^2 + (z_slope_rev-tr_z_slope_rev)^2 + ///
    (z_mean_ln_vis-tr_z_mean_ln_vis)^2 + (z_slope_vis-tr_z_slope_vis)^2 + ///
    (z_mean_ln_pcgdp-tr_z_mean_ln_pcgdp)^2 + (z_mean_ln_pop-tr_z_mean_ln_pop)^2 + ///
    (z_mean_ln_budrev-tr_z_mean_ln_budrev)^2 + (z_mean_ln_budexp-tr_z_mean_ln_budexp)^2
gen matching_weight = exp(-sqrt(sqdist))
replace matching_weight = . if county_id == `trid'
quietly summarize matching_weight, meanonly
replace matching_weight = matching_weight / r(sum)
keep county_id matching_weight
tempfile weights
save `weights', replace

use `panel', clear
drop if inlist(year, 2020, 2021)
merge m:1 county_id using `weights', nogen
replace matching_weight = 1 if county_id == `trid'
capture drop did_2022 did_post
gen did_2022 = county_id == `trid' & year == 2022
gen did_post = county_id == `trid' & year >= 2023

tempname twfepost
tempfile twfe_results
postfile `twfepost' str16 outcome str18 term double coefficient se pvalue N r2 using `twfe_results', replace
foreach yvar in ln_rev ln_vis {
    quietly regress `yvar' did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp ///
        i.county_id i.year [aw=matching_weight], vce(cluster county_id)
    post `twfepost' ("`yvar'") ("Treatment x 2022") (_b[did_2022]) (_se[did_2022]) ///
        (2*ttail(e(df_r),abs(_b[did_2022]/_se[did_2022]))) (e(N)) (e(r2))
    post `twfepost' ("`yvar'") ("Treatment x 2023-24") (_b[did_post]) (_se[did_post]) ///
        (2*ttail(e(df_r),abs(_b[did_post]/_se[did_post]))) (e(N)) (e(r2))
}
postclose `twfepost'
use `twfe_results', clear
export delimited using "`rundir'/table_c3_weighted_twfe_covid_excluded.csv", replace
export excel using "`rundir'/table_c3_weighted_twfe_covid_excluded.xlsx", firstrow(variables) replace

file open note using "`rundir'/readme.txt", write replace
file write note "COVID robustness and inference outputs" _n
file write note "SCM uses the formal non-nested implementation; training period: 2015-2019; untreated COVID holdout: 2020-2021; treatment evaluation: 2022-2024." _n
file write note "SDID removes 2020-2021 for every county and uses placebo VCE with 1,000 repetitions." _n
file write note "SCM uncertainty should be reported as exact permutation/rank evidence, not a conventional sampling CI." _n
file close note

display as result "COVID robustness and inference analysis completed: `rundir'"
log close
