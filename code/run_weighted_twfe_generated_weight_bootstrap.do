version 17.0
clear all
set more off
set seed 20260820
args reps
if "`reps'" == "" local reps 1000

* Generated-weight inference for the exponential-kernel weighted TWFE.
* Each donor bootstrap draw recomputes feature standardization, distances,
* lambda=1 kernel weights, and the second-stage fixed-effects regression.
local root "`c(pwd)'"
local outdir "`root'/output"
local rundir "`outdir'/weighted_twfe_inference"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid 6
cap mkdir "`rundir'"
capture log close
log using "`rundir'/weighted_twfe_generated_weight_bootstrap.log", text replace

cap which esttab
if _rc ssc install estout, replace

use "`paneldta'", clear
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
tempfile basepanel slopes_r slopes_v features weights
save `basepanel', replace
global TAIJIANG_BOOT_PANEL "`basepanel'"
global TAIJIANG_BOOT_TRID `trid'

********************************************************************************
* 1. Pre-treatment balance: treated, unweighted donors, weighted donors.
********************************************************************************
use `basepanel', clear
keep if inrange(year, 2015, 2021)
statsby slope_rev=_b[year], by(county_id) clear: regress ln_rev year
save `slopes_r', replace

use `basepanel', clear
keep if inrange(year, 2015, 2021)
statsby slope_vis=_b[year], by(county_id) clear: regress ln_vis year
save `slopes_v', replace

use `basepanel', clear
keep if inrange(year, 2015, 2021)
collapse (mean) mean_ln_rev=ln_rev mean_ln_vis=ln_vis mean_ln_pcgdp=ln_pcgdp ///
    mean_ln_pop=ln_pop mean_ln_budrev=ln_budrev mean_ln_budexp=ln_budexp, by(county_id)
merge 1:1 county_id using `slopes_r', nogen
merge 1:1 county_id using `slopes_v', nogen

foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
    egen z_`v' = std(`v')
    quietly summarize z_`v' if county_id == `trid', meanonly
    scalar target_`v' = r(mean)
}
gen distance = sqrt((z_mean_ln_rev-target_mean_ln_rev)^2 + ///
    (z_slope_rev-target_slope_rev)^2 + (z_mean_ln_vis-target_mean_ln_vis)^2 + ///
    (z_slope_vis-target_slope_vis)^2 + (z_mean_ln_pcgdp-target_mean_ln_pcgdp)^2 + ///
    (z_mean_ln_pop-target_mean_ln_pop)^2 + (z_mean_ln_budrev-target_mean_ln_budrev)^2 + ///
    (z_mean_ln_budexp-target_mean_ln_budexp)^2)
gen matching_weight = exp(-distance)
replace matching_weight = . if county_id == `trid'
quietly summarize matching_weight, meanonly
replace matching_weight = matching_weight / r(sum)
save `weights', replace

tempname balpost
tempfile balance
postfile `balpost' str32 feature double taijiang_value donor_mean weighted_donor_mean ///
    donor_sd standardized_gap_before standardized_gap_after using `balance', replace
foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
    quietly summarize `v' if county_id == `trid', meanonly
    scalar tval = r(mean)
    quietly summarize `v' if county_id != `trid', detail
    scalar dmean = r(mean)
    scalar dsd = r(sd)
    quietly summarize `v' [aw=matching_weight] if county_id != `trid', meanonly
    scalar wdmean = r(mean)
    post `balpost' ("`v'") (tval) (dmean) (wdmean) (dsd) ///
        (abs(tval-dmean)/dsd) (abs(tval-wdmean)/dsd)
}
postclose `balpost'
use `balance', clear
gen decay_parameter_lambda = 1
export delimited using "`rundir'/table_w1_pre_treatment_balance.csv", replace
export excel using "`rundir'/table_w1_pre_treatment_balance.xlsx", firstrow(variables) replace
mkmat taijiang_value donor_mean weighted_donor_mean standardized_gap_before standardized_gap_after, matrix(balance_mat)
matrix rownames balance_mat = mean_revenue revenue_trend mean_arrivals arrivals_trend pc_gdp population budget_revenue budget_expenditure
esttab matrix(balance_mat, fmt(3 3 3 3 3)) using ///
    "`rundir'/table_w1_pre_treatment_balance.rtf", replace ///
    title("Pre-treatment balance before and after exponential-kernel weighting") ///
    collabels("Taijiang" "Unweighted donor mean" "Weighted donor mean" "Std. gap before" "Std. gap after") ///
    nomtitles varlabels( ///
        mean_revenue "Mean log tourism revenue" revenue_trend "Log revenue trend" ///
        mean_arrivals "Mean log tourist arrivals" arrivals_trend "Log arrivals trend" ///
        pc_gdp "Mean log per-capita GDP" population "Mean log resident population" ///
        budget_revenue "Mean log budget revenue" budget_expenditure "Mean log budget expenditure") noobs nonumber

********************************************************************************
* 2. Full-procedure donor bootstrap, including regenerated matching weights.
********************************************************************************
capture program drop kernel_twfe_boot
program define kernel_twfe_boot, rclass
    syntax , Outcome(name)
    tempfile donor_draw bootpanel br bv bf bw
    use "$TAIJIANG_BOOT_PANEL", clear
    keep if county_id != $TAIJIANG_BOOT_TRID
    bsample, cluster(county_id) idcluster(panel_id)
    save `donor_draw', replace

    use "$TAIJIANG_BOOT_PANEL", clear
    keep if county_id == $TAIJIANG_BOOT_TRID
    gen long panel_id = 0
    append using `donor_draw'
    save `bootpanel', replace

    use `bootpanel', clear
    keep if inrange(year, 2015, 2021)
    statsby slope_rev=_b[year], by(panel_id) clear: regress ln_rev year
    save `br', replace
    use `bootpanel', clear
    keep if inrange(year, 2015, 2021)
    statsby slope_vis=_b[year], by(panel_id) clear: regress ln_vis year
    save `bv', replace

    use `bootpanel', clear
    keep if inrange(year, 2015, 2021)
    collapse (mean) mean_ln_rev=ln_rev mean_ln_vis=ln_vis mean_ln_pcgdp=ln_pcgdp ///
        mean_ln_pop=ln_pop mean_ln_budrev=ln_budrev mean_ln_budexp=ln_budexp, by(panel_id)
    merge 1:1 panel_id using `br', nogen
    merge 1:1 panel_id using `bv', nogen
    foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
        egen z_`v' = std(`v')
        quietly summarize z_`v' if panel_id == 0, meanonly
        scalar target_`v' = r(mean)
    }
    gen distance = sqrt((z_mean_ln_rev-target_mean_ln_rev)^2 + ///
        (z_slope_rev-target_slope_rev)^2 + (z_mean_ln_vis-target_mean_ln_vis)^2 + ///
        (z_slope_vis-target_slope_vis)^2 + (z_mean_ln_pcgdp-target_mean_ln_pcgdp)^2 + ///
        (z_mean_ln_pop-target_mean_ln_pop)^2 + (z_mean_ln_budrev-target_mean_ln_budrev)^2 + ///
        (z_mean_ln_budexp-target_mean_ln_budexp)^2)
    gen weight = exp(-distance)
    replace weight = . if panel_id == 0
    quietly summarize weight, meanonly
    replace weight = weight/r(sum)
    keep panel_id weight
    save `bw', replace

    use `bootpanel', clear
    merge m:1 panel_id using `bw', nogen
    replace weight = 1 if panel_id == 0
    capture drop treated did_2022 did_post
    gen treated = panel_id == 0
    gen did_2022 = treated * (year == 2022)
    gen did_post = treated * (year >= 2023)
    quietly regress `outcome' did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp ///
        i.panel_id i.year [aw=weight]
    return scalar b_2022 = _b[did_2022]
    return scalar b_post = _b[did_post]
end

use `basepanel', clear
simulate b_2022=r(b_2022) b_post=r(b_post), reps(`reps') seed(20260820) nodots: ///
    kernel_twfe_boot, outcome(ln_rev)
gen outcome = "Log revenue"
tempfile boot_rev
save `boot_rev', replace

use `basepanel', clear
simulate b_2022=r(b_2022) b_post=r(b_post), reps(`reps') seed(20260820) nodots: ///
    kernel_twfe_boot, outcome(ln_vis)
gen outcome = "Log visitors"
append using `boot_rev'
export delimited using "`rundir'/generated_weight_bootstrap_draws.csv", replace

tempname infpost
tempfile inference
postfile `infpost' str16 outcome str12 period double baseline_beta bootstrap_se ci_lo_95 ci_hi_95 using `inference', replace
foreach out in "Log revenue" "Log visitors" {
    preserve
    keep if outcome == "`out'"
    foreach term in 2022 post {
        quietly summarize b_`term', detail
        scalar bse = r(sd)
        quietly centile b_`term', centile(2.5 97.5)
        scalar clo = r(c_1)
        scalar chi = r(c_2)
        if "`out'" == "Log revenue" & "`term'" == "2022" scalar base = .1752433374
        if "`out'" == "Log revenue" & "`term'" == "post" scalar base = .4134956598
        if "`out'" == "Log visitors" & "`term'" == "2022" scalar base = .2086167976
        if "`out'" == "Log visitors" & "`term'" == "post" scalar base = .4566026916
        if "`term'" == "2022" post `infpost' ("`out'") ("2022") (base) (bse) (clo) (chi)
        else post `infpost' ("`out'") ("2023-2024") (base) (bse) (clo) (chi)
    }
    restore
}
postclose `infpost'
use `inference', clear
export delimited using "`rundir'/table_w2_full_procedure_bootstrap.csv", replace
export excel using "`rundir'/table_w2_full_procedure_bootstrap.xlsx", firstrow(variables) replace
mkmat baseline_beta bootstrap_se ci_lo_95 ci_hi_95, matrix(inference_mat)
matrix rownames inference_mat = revenue_2022 revenue_2023_2024 visitors_2022 visitors_2023_2024
esttab matrix(inference_mat, fmt(3 3 3 3)) using ///
    "`rundir'/table_w2_full_procedure_bootstrap.rtf", replace ///
    title("Weighted TWFE: full-procedure donor-bootstrap inference") ///
    collabels("Baseline beta" "Bootstrap SE" "Percentile CI lower" "Percentile CI upper") ///
    nomtitles varlabels(revenue_2022 "Tourism revenue, 2022" ///
        revenue_2023_2024 "Tourism revenue, 2023-2024" ///
        visitors_2022 "Tourist arrivals, 2022" ///
        visitors_2023_2024 "Tourist arrivals, 2023-2024") noobs nonumber

file open note using "`rundir'/readme.txt", write replace
file write note "Kernel weights: exp(-lambda*distance), lambda=1; donor weights normalized to sum to one." _n
file write note "Distance is Euclidean distance in the eight-dimensional standardized pre-treatment feature space." _n
file write note "Bootstrap: `reps' donor-county resamples with replacement; all feature construction, standardization, weighting, and TWFE estimation repeated each draw." _n
file close note
log close
