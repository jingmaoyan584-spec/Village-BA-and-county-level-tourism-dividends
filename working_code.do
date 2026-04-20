version 17.0
clear all
set more off
set linesize 255

********************************************************************************
* One-click replication for Taijiang 2022 design
* This script uses the prepared .dta directly and reproduces all main results
* No raw-data cleaning steps are included here
*
* Recommended structure:
*   ./taijiang_2022_one_click_replication_from_dta.do
*   ./output/qiandongnan_county_panel_2015_2024_analysis_ready.dta
********************************************************************************

local datadir "output"
local outdir  "output/one_click_replication_from_dta"
local figdir  "`outdir'/ssci_figures"
cap mkdir "`outdir'"
cap mkdir "`figdir'"

local paneldta "qiandongnan_county_panel_2015_2024_analysis_ready.dta"
capture confirm file "`paneldta'"
if _rc local paneldta "`datadir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local mainlog  "`outdir'/taijiang_2022_one_click_replication_from_dta.log"

capture log close
log using "`mainlog'", text replace

********************************************************************************
* 0. Packages
********************************************************************************

cap which synth
if _rc ssc install synth, replace

cap which sdid
if _rc ssc install sdid, replace

cap which esttab
if _rc ssc install estout, replace

cap which eststo
if _rc ssc install estout, replace

cap which synth
if _rc {
    di as error "Package synth is not available."
    exit 601
}

cap which sdid
if _rc {
    di as error "Package sdid is not available."
    exit 601
}

********************************************************************************
* 1. Load .dta panel
********************************************************************************

capture confirm file "`paneldta'"
if _rc {
    di as error "Panel file not found: `paneldta'"
    exit 601
}

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
xtset county_id year

* Ensure short analysis names exist
capture confirm variable ln_rev
if _rc gen ln_rev = ln_tour_rev
capture confirm variable ln_vis
if _rc gen ln_vis = ln_tour_vis
capture confirm variable ln_pcgdp
if _rc gen ln_pcgdp = ln_pcgdp
capture confirm variable ln_pop
if _rc gen ln_pop = ln_pop
capture confirm variable ln_budrev
if _rc gen ln_budrev = ln_bud_rev
capture confirm variable ln_budexp
if _rc gen ln_budexp = ln_bud_exp

tempfile panel_ready county_lookup
save `panel_ready', replace
global TAIJIANG_PANEL_READY "`panel_ready'"

preserve
keep county county_id
duplicates drop
sort county_id
save `county_lookup', replace
restore

* Fixed IDs from prepared .dta
local trid        6
local kaili_id    4
local leishan_id 13
local zhenyuan_id 12
local cengong_id  8
local jinping_id 11
local majiang_id 14
global TAIJIANG_TRID "`trid'"
global TAIJIANG_TRPERIOD "2022"

local prefirst = 2015
local prelast  = 2021
local trperiod = 2022

********************************************************************************
* 2. Matching weights for weighted DID
********************************************************************************

use `panel_ready', clear
keep if inrange(year, `prefirst', `prelast')
statsby slope_rev=_b[year], by(county_id) clear: regress ln_rev year
tempfile slope_rev
save `slope_rev', replace

use `panel_ready', clear
keep if inrange(year, `prefirst', `prelast')
statsby slope_vis=_b[year], by(county_id) clear: regress ln_vis year
tempfile slope_vis
save `slope_vis', replace

use `panel_ready', clear
keep if inrange(year, `prefirst', `prelast')
collapse ///
    (mean) mean_ln_rev=ln_rev ///
           mean_ln_vis=ln_vis ///
           mean_ln_pcgdp=ln_pcgdp ///
           mean_ln_pop=ln_pop ///
           mean_ln_budrev=ln_budrev ///
           mean_ln_budexp=ln_budexp, ///
    by(county_id)

merge 1:1 county_id using `slope_rev', nogen
merge 1:1 county_id using `slope_vis', nogen
merge 1:1 county_id using `county_lookup', nogen

foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
    egen z_`v' = std(`v')
    replace z_`v' = 0 if missing(z_`v')
}

foreach v in z_mean_ln_rev z_slope_rev z_mean_ln_vis z_slope_vis z_mean_ln_pcgdp z_mean_ln_pop z_mean_ln_budrev z_mean_ln_budexp {
    quietly summarize `v' if county_id == `trid', meanonly
    scalar tr_`v' = r(mean)
}

gen sqdist = ///
    (z_mean_ln_rev    - tr_z_mean_ln_rev)^2    + ///
    (z_slope_rev      - tr_z_slope_rev)^2      + ///
    (z_mean_ln_vis    - tr_z_mean_ln_vis)^2    + ///
    (z_slope_vis      - tr_z_slope_vis)^2      + ///
    (z_mean_ln_pcgdp  - tr_z_mean_ln_pcgdp)^2  + ///
    (z_mean_ln_pop    - tr_z_mean_ln_pop)^2    + ///
    (z_mean_ln_budrev - tr_z_mean_ln_budrev)^2 + ///
    (z_mean_ln_budexp - tr_z_mean_ln_budexp)^2

gen distance = sqrt(sqdist)
gen matching_weight = exp(-distance)
replace matching_weight = . if county_id == `trid'
quietly summarize matching_weight, meanonly
replace matching_weight = matching_weight / r(sum)

keep county county_id matching_weight
sort county_id
export delimited using "`outdir'/taijiang_2022_matching_weights_stata.csv", replace
tempfile matching_weights
save `matching_weights', replace

********************************************************************************
* 3. SCM helper
********************************************************************************

capture program drop run_scm_spec
program define run_scm_spec, rclass
    syntax , Outcome(name) Keepfile(string) [Exclude(numlist integer)]

    preserve
    use "$TAIJIANG_PANEL_READY", clear
    gen byte keep_unit = 1
    if "`exclude'" != "" {
        foreach ex of numlist `exclude' {
            replace keep_unit = 0 if county_id == `ex' & county_id != $TAIJIANG_TRID
        }
    }
    keep if keep_unit == 1 | county_id == $TAIJIANG_TRID
    xtset county_id year

    synth `outcome' ///
        ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
        `outcome'(2015) `outcome'(2016) `outcome'(2017) `outcome'(2018) ///
        `outcome'(2019) `outcome'(2020) `outcome'(2021), ///
        trunit($TAIJIANG_TRID) trperiod($TAIJIANG_TRPERIOD) ///
        xperiod(2015(1)2021) mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
        nested keep("`keepfile'") replace

    matrix W = e(W_weights)
    return scalar donors_n = max(rowsof(W), colsof(W))
    restore

    preserve
    use "`keepfile'", clear
    capture confirm variable _time
    if !_rc rename _time year
    gen gap = _Y_treated - _Y_synthetic
    gen sqgap = gap^2
    quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
    return scalar pre_rmspe = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
    return scalar post_rmspe = sqrt(r(mean))
    quietly summarize gap if year == 2022, meanonly
    return scalar gap_2022 = r(mean)
    quietly summarize gap if inlist(year, 2023, 2024), meanonly
    return scalar gap_post = r(mean)
    restore
end

********************************************************************************
* 4. Baseline SCM figures
********************************************************************************

tempfile scm_base
quietly run_scm_spec, outcome(ln_rev) keepfile(`scm_base')
scalar scm_pre_rmspe  = r(pre_rmspe)

preserve
use `scm_base', clear
capture confirm variable _time
if !_rc rename _time year
gen gap = _Y_treated - _Y_synthetic

twoway ///
    (line _Y_treated year, lcolor(black) lwidth(medthick) msymbol(O) mcolor(black)) ///
    (line _Y_synthetic year, lcolor(gs8) lpattern(dash) lwidth(medthick) msymbol(S) mcolor(gs8)), ///
    xline(2022, lpattern(shortdash) lcolor(black)) ///
    xlabel(2015(1)2024, angle(45) labsize(small)) xscale(range(2015 2024)) ///
    xtitle("Year") ytitle("Log tourism revenue") ///
    title("Figure 1. SCM Fit Path", size(medsmall)) ///
    legend(order(1 "Taijiang" 2 "Synthetic Taijiang") ring(0) pos(11) col(1)) ///
    graphregion(color(white)) plotregion(color(white))
graph export "`figdir'/figure1_scm_fit_path_revenue.png", width(2400) replace
graph export "`figdir'/figure1_scm_fit_path_revenue.pdf", replace

twoway ///
    (line gap year, lcolor(black) lwidth(medthick) msymbol(O) mcolor(black)), ///
    yline(0, lcolor(gs10)) xline(2022, lpattern(shortdash) lcolor(black)) ///
    xlabel(2015(1)2024, angle(45) labsize(small)) xscale(range(2015 2024)) ///
    xtitle("Year") ytitle("Log-point gap") ///
    title("Figure 2. SCM Gap", size(medsmall)) ///
    legend(off) graphregion(color(white)) plotregion(color(white))
graph export "`figdir'/figure2_scm_gap_revenue.png", width(2400) replace
graph export "`figdir'/figure2_scm_gap_revenue.pdf", replace
restore

********************************************************************************
* 5. Placebo paths and RMSPE ratios
********************************************************************************

use `panel_ready', clear
qui levelsof county_id, local(all_ids)

tempfile placebo_paths placebo_ratios
tempname pathpost ratiopost
postfile `pathpost' int county_id int year double gap pre_rmspe byte keep_for_plot byte is_target using `placebo_paths', replace
postfile `ratiopost' int county_id double rmspe_ratio using `placebo_ratios', replace

foreach pid of local all_ids {
    tempfile placebo_keep
    preserve
    use `panel_ready', clear
    xtset county_id year
    capture noisily synth ln_rev ///
        ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
        ln_rev(2015) ln_rev(2016) ln_rev(2017) ln_rev(2018) ln_rev(2019) ln_rev(2020) ln_rev(2021), ///
        trunit(`pid') trperiod(`trperiod') ///
        xperiod(2015(1)2021) mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
        nested keep("`placebo_keep'") replace
    local synth_rc = _rc
    restore
    if `synth_rc' != 0 continue

    preserve
    use "`placebo_keep'", clear
    capture confirm variable _time
    if !_rc rename _time year
    gen gap = _Y_treated - _Y_synthetic
    gen sqgap = gap^2
    quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
    scalar pre_rmspe_tmp = sqrt(r(mean))
    quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
    scalar post_rmspe_tmp = sqrt(r(mean))
    scalar ratio_tmp = post_rmspe_tmp / pre_rmspe_tmp
    scalar keepflag = (`pid' == `trid') | (pre_rmspe_tmp <= 5 * scm_pre_rmspe)
    forvalues yy = 2015/2024 {
        quietly summarize gap if year == `yy', meanonly
        post `pathpost' (`pid') (`yy') (r(mean)) (pre_rmspe_tmp) (keepflag) (`pid' == `trid')
    }
    post `ratiopost' (`pid') (ratio_tmp)
    restore
}

postclose `pathpost'
postclose `ratiopost'

use `placebo_paths', clear
merge m:1 county_id using `county_lookup', nogen
save `placebo_paths', replace

use `placebo_ratios', clear
merge m:1 county_id using `county_lookup', nogen
sort rmspe_ratio
gen rank = _n
gen target = county_id == `trid'
quietly summarize rmspe_ratio if target == 1, meanonly
scalar target_ratio = r(mean)
count if rmspe_ratio >= target_ratio
scalar placebo_p = r(N) / _N
local placebo_p_txt : display %4.3f placebo_p
save `placebo_ratios', replace

use `placebo_paths', clear
twoway ///
    (line gap year if keep_for_plot == 1 & is_target == 0, lcolor(gs12) lwidth(vthin) cmissing(n)) ///
    (line gap year if is_target == 1, lcolor(black) lwidth(medthick) msymbol(O) mcolor(black)), ///
    yline(0, lcolor(gs10)) xline(2022, lpattern(shortdash) lcolor(black)) ///
    xlabel(2015(1)2024, angle(45) labsize(small)) xscale(range(2015 2024)) ///
    xtitle("Year") ytitle("Log-point gap") ///
    title("Figure 3. SCM Placebo Paths", size(medsmall)) ///
    legend(order(2 "Taijiang") ring(0) pos(11)) ///
    graphregion(color(white)) plotregion(color(white))
graph export "`figdir'/figure3_scm_placebo_paths_revenue.png", width(2400) replace
graph export "`figdir'/figure3_scm_placebo_paths_revenue.pdf", replace

use `placebo_ratios', clear
capture confirm variable rank
if _rc {
    sort rmspe_ratio
    gen rank = _n
}
else {
    sort rank
}
capture confirm variable target
if _rc gen target = county_id == `trid'
twoway ///
    (scatter rmspe_ratio rank if target == 0, mcolor(gs8) msymbol(O) msize(small)) ///
    (scatter rmspe_ratio rank if target == 1, mcolor(black) msymbol(O) msize(medlarge)), ///
    yline(`=target_ratio', lcolor(black) lpattern(shortdash)) ///
    xtitle("Placebo rank") ytitle("Post/Pre RMSPE ratio") ///
    title("Figure 4. RMSPE Ratio Distribution", size(medsmall)) ///
    note("Taijiang placebo p = `placebo_p_txt'", size(small)) ///
    legend(off) graphregion(color(white)) plotregion(color(white))
graph export "`figdir'/figure4_scm_rmspe_ratio_revenue.png", width(2400) replace
graph export "`figdir'/figure4_scm_rmspe_ratio_revenue.pdf", replace

********************************************************************************
* 6. SCM donor sensitivity
********************************************************************************

tempname senspost
tempfile donor_sens
postfile `senspost' str40 spec int donors_n double pre_rmspe post_rmspe ratio gap2022 gap_post using `donor_sens', replace

tempfile sens1 sens2 sens3 sens4 sens5 sens6
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens1')
post `senspost' ("Baseline SCM") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens2') exclude(`kaili_id')
post `senspost' ("Exclude Kaili") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens3') exclude(`kaili_id' `leishan_id' `zhenyuan_id')
post `senspost' ("Exclude high-tourism counties") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens4') exclude(`cengong_id')
post `senspost' ("Leave-one-out: Cengong") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens5') exclude(`jinping_id')
post `senspost' ("Leave-one-out: Jinping") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
quietly run_scm_spec, outcome(ln_rev) keepfile(`sens6') exclude(`majiang_id')
post `senspost' ("Leave-one-out: Majiang") (r(donors_n)) (r(pre_rmspe)) (r(post_rmspe)) (r(post_rmspe)/r(pre_rmspe)) (r(gap_2022)) (r(gap_post))
postclose `senspost'

use `donor_sens', clear
gen gap2022_pct = 100 * (exp(gap2022) - 1)
gen gap_post_pct = 100 * (exp(gap_post) - 1)
order spec donors_n pre_rmspe post_rmspe ratio gap2022 gap2022_pct gap_post gap_post_pct
export delimited using "`outdir'/taijiang_2022_scm_donor_sensitivity_stata.csv", replace
export excel using "`outdir'/taijiang_2022_scm_donor_sensitivity_stata.xlsx", firstrow(variables) replace

mkmat donors_n pre_rmspe post_rmspe ratio gap2022_pct gap_post_pct, matrix(donor_sens_mat)
matrix rownames donor_sens_mat = baseline_scm exclude_kaili exclude_high_tourism loo_cengong loo_jinping loo_majiang
matrix colnames donor_sens_mat = donors_n pre_rmspe post_rmspe rmspe_ratio effect_2022_pct effect_post_pct

esttab matrix(donor_sens_mat, fmt(0 3 3 3 2 2)) using ///
    "`outdir'/taijiang_2022_scm_donor_sensitivity_esttab.rtf", replace ///
    title("SCM Donor Sensitivity") ///
    varlabels( ///
        baseline_scm          "Baseline SCM" ///
        exclude_kaili         "Exclude Kaili" ///
        exclude_high_tourism  "Exclude High-Tourism" ///
        loo_cengong           "Leave-one-out: Cengong" ///
        loo_jinping           "Leave-one-out: Jinping" ///
        loo_majiang           "Leave-one-out: Majiang") ///
    eqlabels( ///
        donors_n              "Donors" ///
        pre_rmspe             "Pre RMSPE" ///
        post_rmspe            "Post RMSPE" ///
        rmspe_ratio           "Post/Pre RMSPE ratio" ///
        effect_2022_pct       "2022 effect (%)" ///
        effect_post_pct       "2023-2024 effect (%)") ///
    noobs nonumber

esttab matrix(donor_sens_mat, fmt(0 3 3 3 2 2)) using ///
    "`outdir'/taijiang_2022_scm_donor_sensitivity_esttab.csv", replace ///
    plain

********************************************************************************
* 7. SDID main results
********************************************************************************

tempname sdidpost
tempfile sdid_tbl
postfile `sdidpost' str18 outcome str18 window double att se pvalue using `sdid_tbl', replace

use `panel_ready', clear
keep if inrange(year, 2015, 2022)
gen treated_event = county_id == `trid' & year >= 2022
sdid ln_rev county_id year treated_event, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Revenue") ("2022") (e(ATT)) (e(se)) (p_sdid)

use `panel_ready', clear
keep if inrange(year, 2015, 2024) & year != 2022
egen t_sub = group(year)
gen treated_full = county_id == `trid' & year >= 2023
sdid ln_rev county_id t_sub treated_full, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Revenue") ("2023-2024") (e(ATT)) (e(se)) (p_sdid)

use `panel_ready', clear
gen treated_all = county_id == `trid' & year >= 2022
sdid ln_rev county_id year treated_all, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Revenue") ("2022-2024") (e(ATT)) (e(se)) (p_sdid)

use `panel_ready', clear
keep if inrange(year, 2015, 2022)
gen treated_event = county_id == `trid' & year >= 2022
sdid ln_vis county_id year treated_event, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Visitors") ("2022") (e(ATT)) (e(se)) (p_sdid)

use `panel_ready', clear
keep if inrange(year, 2015, 2024) & year != 2022
egen t_sub = group(year)
gen treated_full = county_id == `trid' & year >= 2023
sdid ln_vis county_id t_sub treated_full, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Visitors") ("2023-2024") (e(ATT)) (e(se)) (p_sdid)

use `panel_ready', clear
gen treated_all = county_id == `trid' & year >= 2022
sdid ln_vis county_id year treated_all, vce(placebo) seed(20260415) reps(200)
scalar p_sdid = 2 * (1 - normal(abs(e(ATT) / e(se))))
post `sdidpost' ("Visitors") ("2022-2024") (e(ATT)) (e(se)) (p_sdid)

postclose `sdidpost'
use `sdid_tbl', clear
gen att_pct = 100 * (exp(att) - 1)
export delimited using "`outdir'/taijiang_2022_sdid_main_results_stata.csv", replace
export excel using "`outdir'/taijiang_2022_sdid_main_results_stata.xlsx", firstrow(variables) replace

********************************************************************************
* 8. Weighted DID + esttab
********************************************************************************

use `panel_ready', clear
merge m:1 county_id using `matching_weights', nogen
replace matching_weight = 1 if county_id == `trid'
replace matching_weight = 0 if missing(matching_weight)

capture drop treated
capture drop event2022
capture drop post_full
capture drop did_2022
capture drop did_post
gen treated   = county_id == `trid'
gen event2022 = year == 2022
gen post_full = year >= 2023
gen did_2022  = treated * event2022
gen did_post  = treated * post_full

label variable did_2022  "Treatment x 2022"
label variable did_post  "Treatment x Post(2023-2024)"
label variable ln_pcgdp  "ln(Per capita GDP)"
label variable ln_pop    "ln(Resident population)"
label variable ln_budrev "ln(Budget revenue)"
label variable ln_budexp "ln(Budget expenditure)"

eststo clear

quietly regress ln_rev did_2022 did_post [aw=matching_weight], vce(cluster county_id)
eststo rev_m1
estadd local CountyFE "No"
estadd local YearFE   "No"
estadd local Controls "No"

quietly regress ln_rev did_2022 did_post i.county_id i.year [aw=matching_weight], vce(cluster county_id)
eststo rev_m2
estadd local CountyFE "Yes"
estadd local YearFE   "Yes"
estadd local Controls "No"

quietly regress ln_rev did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp i.county_id i.year [aw=matching_weight], vce(cluster county_id)
eststo rev_m3
estadd local CountyFE "Yes"
estadd local YearFE   "Yes"
estadd local Controls "Yes"

quietly regress ln_vis did_2022 did_post [aw=matching_weight], vce(cluster county_id)
eststo vis_m1
estadd local CountyFE "No"
estadd local YearFE   "No"
estadd local Controls "No"

quietly regress ln_vis did_2022 did_post i.county_id i.year [aw=matching_weight], vce(cluster county_id)
eststo vis_m2
estadd local CountyFE "Yes"
estadd local YearFE   "Yes"
estadd local Controls "No"

quietly regress ln_vis did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp i.county_id i.year [aw=matching_weight], vce(cluster county_id)
eststo vis_m3
estadd local CountyFE "Yes"
estadd local YearFE   "Yes"
estadd local Controls "Yes"

local rtf_rev      "`outdir'/taijiang_weighted_did_revenue.rtf"
local rtf_vis      "`outdir'/taijiang_weighted_did_visitors.rtf"
local rtf_main     "`outdir'/taijiang_weighted_did_main_two_cols.rtf"
local rtf_rev_alt  "`outdir'/taijiang_weighted_did_revenue_alt.rtf"
local rtf_vis_alt  "`outdir'/taijiang_weighted_did_visitors_alt.rtf"
local rtf_main_alt "`outdir'/taijiang_weighted_did_main_two_cols_alt.rtf"

local rtf_rev_win  = subinstr("`rtf_rev'",  "/", "\", .)
local rtf_vis_win  = subinstr("`rtf_vis'",  "/", "\", .)
local rtf_main_win = subinstr("`rtf_main'", "/", "\", .)

capture noisily shell attrib -R "`rtf_rev_win'"
capture noisily shell attrib -R "`rtf_vis_win'"
capture noisily shell attrib -R "`rtf_main_win'"

capture noisily esttab rev_m1 rev_m2 rev_m3 using "`rtf_rev'", replace ///
    title("Weighted DID Results: Tourism Revenue") ///
    mtitles("M1" "M2" "M3") ///
    b(%5.3f) se(%5.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
    labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
    keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    compress nogaps label
if _rc {
    esttab rev_m1 rev_m2 rev_m3 using "`rtf_rev_alt'", replace ///
        title("Weighted DID Results: Tourism Revenue") ///
        mtitles("M1" "M2" "M3") ///
        b(%5.3f) se(%5.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
        labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
        keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        compress nogaps label
    di as txt "Primary revenue RTF was locked or read-only; wrote alternate file instead."
}

capture noisily esttab vis_m1 vis_m2 vis_m3 using "`rtf_vis'", replace ///
    title("Weighted DID Results: Tourism Visitors") ///
    mtitles("M1" "M2" "M3") ///
    b(%5.3f) se(%5.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
    labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
    keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    compress nogaps label
if _rc {
    esttab vis_m1 vis_m2 vis_m3 using "`rtf_vis_alt'", replace ///
        title("Weighted DID Results: Tourism Visitors") ///
        mtitles("M1" "M2" "M3") ///
        b(%5.3f) se(%5.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
        labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
        keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        compress nogaps label
    di as txt "Primary visitors RTF was locked or read-only; wrote alternate file instead."
}

capture noisily esttab rev_m3 vis_m3 using "`rtf_main'", replace ///
    title("Weighted DID Main Results") ///
    mtitles("Log Revenue" "Log Visitors") ///
    b(%5.3f) se(%5.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
    labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
    keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
    compress nogaps label
if _rc {
    esttab rev_m3 vis_m3 using "`rtf_main_alt'", replace ///
        title("Weighted DID Main Results") ///
        mtitles("Log Revenue" "Log Visitors") ///
        b(%5.3f) se(%5.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        stats(r2 r2_a N CountyFE YearFE Controls, fmt(%9.3f %9.3f %9.0f %9s %9s %9s) ///
        labels("R-squared" "Adj. R-squared" "N" "County FE" "Year FE" "Controls")) ///
        keep(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        order(did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp) ///
        compress nogaps label
    di as txt "Primary two-column RTF was locked or read-only; wrote alternate file instead."
}

tempname didpost didcoefpost
tempfile didsum didcoef
postfile `didpost' str18 outcome double coef_2022 se_2022 p_2022 coef_post se_post p_post r2 N using `didsum', replace
postfile `didcoefpost' str18 outcome str40 variable double coef se pvalue using `didcoef', replace

foreach yvar in ln_rev ln_vis {
    quietly regress `yvar' did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp i.county_id i.year [aw=matching_weight], vce(cluster county_id)
    local p2022 = 2 * ttail(e(df_r), abs(_b[did_2022] / _se[did_2022]))
    local ppost = 2 * ttail(e(df_r), abs(_b[did_post] / _se[did_post]))
    post `didpost' ("`yvar'") (_b[did_2022]) (_se[did_2022]) (`p2022') (_b[did_post]) (_se[did_post]) (`ppost') (e(r2)) (e(N))
    foreach v in did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp {
        local pv = 2 * ttail(e(df_r), abs(_b[`v'] / _se[`v']))
        post `didcoefpost' ("`yvar'") ("`v'") (_b[`v']) (_se[`v']) (`pv')
    }
}
postclose `didpost'
postclose `didcoefpost'

use `didsum', clear
export delimited using "`outdir'/taijiang_2022_weighted_did_results_stata.csv", replace
export excel using "`outdir'/taijiang_2022_weighted_did_results_stata.xlsx", firstrow(variables) replace
use `didcoef', clear
export delimited using "`outdir'/taijiang_2022_weighted_did_full_controls_stata.csv", replace
export excel using "`outdir'/taijiang_2022_weighted_did_full_controls_stata.xlsx", firstrow(variables) replace

********************************************************************************
* 9. Direct workbook
********************************************************************************

local tablebook "`outdir'/taijiang_2022_stata_direct_tables.xlsx"

use `donor_sens', clear
gen gap2022_pct = 100 * (exp(gap2022) - 1)
gen gap_post_pct = 100 * (exp(gap_post) - 1)
putexcel set "`tablebook'", sheet("SCM_donor") replace
putexcel A1 = "Table A1. SCM donor sensitivity (tourism revenue)"
putexcel A3 = "Specification" B3 = "Donors" C3 = "Pre RMSPE" D3 = "Post RMSPE" E3 = "RMSPE ratio" F3 = "2022 effect" G3 = "2022 pct" H3 = "2023-2024 effect" I3 = "2023-2024 pct"
forvalues i = 1/`=_N' {
    local r = `i' + 3
    putexcel A`r' = spec[`i'] B`r' = donors_n[`i'] C`r' = pre_rmspe[`i'] D`r' = post_rmspe[`i'] E`r' = ratio[`i'] F`r' = gap2022[`i'] G`r' = gap2022_pct[`i'] H`r' = gap_post[`i'] I`r' = gap_post_pct[`i']
}
putexcel A3:I3, bold border(bottom)
putexcel B4:I20, nformat(number_d3)

use `sdid_tbl', clear
gen att_pct = 100 * (exp(att) - 1)
putexcel set "`tablebook'", sheet("SDID_main") modify
putexcel A1 = "Table 2. SDID main results"
putexcel A3 = "Outcome" B3 = "Window" C3 = "ATT" D3 = "SE" E3 = "p-value" F3 = "Effect pct"
forvalues i = 1/`=_N' {
    local r = `i' + 3
    putexcel A`r' = outcome[`i'] B`r' = window[`i'] C`r' = att[`i'] D`r' = se[`i'] E`r' = pvalue[`i'] F`r' = att_pct[`i']
}
putexcel A3:F3, bold border(bottom)
putexcel C4:F20, nformat(number_d3)

use `didsum', clear
putexcel set "`tablebook'", sheet("WDID_main") modify
putexcel A1 = "Table 3. Weighted DID main results"
putexcel A3 = "Outcome" B3 = "did_2022" C3 = "SE(2022)" D3 = "p(2022)" E3 = "did_post" F3 = "SE(post)" G3 = "p(post)" H3 = "R-squared" I3 = "N"
forvalues i = 1/`=_N' {
    local r = `i' + 3
    putexcel A`r' = outcome[`i'] B`r' = coef_2022[`i'] C`r' = se_2022[`i'] D`r' = p_2022[`i'] E`r' = coef_post[`i'] F`r' = se_post[`i'] G`r' = p_post[`i'] H`r' = r2[`i'] I`r' = N[`i']
}
putexcel A3:I3, bold border(bottom)
putexcel B4:I20, nformat(number_d3)

use `didcoef', clear
gen stars = ""
replace stars = "***" if pvalue < 0.01
replace stars = "**"  if pvalue >= 0.01 & pvalue < 0.05
replace stars = "*"   if pvalue >= 0.05 & pvalue < 0.10
gen coef_show = string(coef, "%9.3f") + stars
gen se_show   = "(" + string(se, "%9.3f") + ")"
putexcel set "`tablebook'", sheet("WDID_controls") modify
putexcel A1 = "Weighted DID control-variable results"
putexcel A3 = "Outcome" B3 = "Variable" C3 = "Coefficient" D3 = "SE" E3 = "p-value"
forvalues i = 1/`=_N' {
    local r = `i' + 3
    putexcel A`r' = outcome[`i'] B`r' = variable[`i'] C`r' = coef_show[`i'] D`r' = se_show[`i'] E`r' = pvalue[`i']
}
putexcel A3:E3, bold border(bottom)
putexcel E4:E40, nformat(number_d3)

********************************************************************************
* 10. Manifest
********************************************************************************

file open mf using "`figdir'/manifest_stata_only.txt", write replace
file write mf "Pure Stata outputs for Taijiang 2022 design" _n
file write mf "figure1_scm_fit_path_revenue.png" _n
file write mf "figure2_scm_gap_revenue.png" _n
file write mf "figure3_scm_placebo_paths_revenue.png" _n
file write mf "figure4_scm_rmspe_ratio_revenue.png" _n
file write mf "taijiang_2022_scm_donor_sensitivity_stata.xlsx" _n
file write mf "taijiang_2022_scm_donor_sensitivity_esttab.rtf" _n
file write mf "taijiang_2022_scm_donor_sensitivity_esttab.csv" _n
file write mf "taijiang_2022_sdid_main_results_stata.xlsx" _n
file write mf "taijiang_2022_weighted_did_results_stata.xlsx" _n
file write mf "taijiang_2022_weighted_did_full_controls_stata.xlsx" _n
file write mf "taijiang_2022_stata_direct_tables.xlsx" _n
file write mf "taijiang_weighted_did_revenue.rtf" _n
file write mf "taijiang_weighted_did_visitors.rtf" _n
file write mf "taijiang_weighted_did_main_two_cols.rtf" _n
file close mf

di as txt "One-click Stata replication finished."
di as txt "Main do-file: taijiang_2022_one_click_replication_from_dta.do"
di as txt "Graph folder: `figdir'"

log close
