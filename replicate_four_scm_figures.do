version 17.0
clear all
set more off
set linesize 255
set varabbrev off

* Reproduce Figures 1-4 using the formal uniform non-nested SCM specification.
* The same predictors, fitting period, treatment year, and optimization rule are
* used for Taijiang and every placebo-treated county.

* Resolve the package root when this file is run directly from the code
* subdirectory rather than from the package top folder.
local root "`c(pwd)'"
capture confirm file "`root'/data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
if _rc {
    capture confirm file "`root'/../data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
    if !_rc local root "`root'/.."
}
local thisfile "`c(filename)'"
local slash = max(strrpos("`thisfile'", "/"), strrpos("`thisfile'", char(92)))
if `slash' > 0 {
    local thisdir = substr("`thisfile'", 1, `slash' - 1)
    capture confirm file "`thisdir'/../data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
    if !_rc local root "`thisdir'/.."
}
cd "`root'"
local outdir   "`root'/output"
local figdir   "`outdir'/figures"
local proofdir "`figdir'/high_resolution_proof"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
capture confirm file "`paneldta'"
if _rc local paneldta "`root'/data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid     6
local trperiod 2022

cap mkdir "`figdir'"
cap mkdir "`proofdir'"
capture log close
log using "`figdir'/replicate_four_scm_figures.log", text replace

cap which synth
if _rc ssc install synth, replace
capture graph set window fontface "Arial"

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
xtset county_id year
capture confirm variable ln_rev
if _rc gen double ln_rev = ln_tour_rev
capture confirm variable ln_vis
if _rc gen double ln_vis = ln_tour_vis
capture confirm variable ln_pcgdp
if _rc gen double ln_pcgdp = ln(pcgdp)
capture confirm variable ln_pop
if _rc gen double ln_pop = ln(pop_10k)
capture confirm variable ln_budrev
if _rc gen double ln_budrev = ln(bud_rev_10k)
capture confirm variable ln_budexp
if _rc gen double ln_budexp = ln(bud_exp_10k)
assert !missing(ln_rev, ln_vis, ln_pcgdp, ln_pop, ln_budrev, ln_budexp)

tempfile panel_ready lookup paths
save `panel_ready', replace
preserve
keep county county_id
duplicates drop
isid county_id
save `lookup', replace
restore

********************************************************************************
* 1. Figures 1 and 2: baseline actual/synthetic paths and log gaps.
********************************************************************************
tempfile scm_rev scm_vis

quietly synth ln_rev ln_vis ln_pcgdp ln_pop ln_budrev ln_budexp ///
    ln_rev(2015) ln_rev(2016) ln_rev(2017) ln_rev(2018) ///
    ln_rev(2019) ln_rev(2020) ln_rev(2021), ///
    trunit(`trid') trperiod(`trperiod') xperiod(2015(1)2021) ///
    mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
    keep("`scm_rev'") replace

quietly synth ln_vis ln_rev ln_pcgdp ln_pop ln_budrev ln_budexp ///
    ln_vis(2015) ln_vis(2016) ln_vis(2017) ln_vis(2018) ///
    ln_vis(2019) ln_vis(2020) ln_vis(2021), ///
    trunit(`trid') trperiod(`trperiod') xperiod(2015(1)2021) ///
    mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
    keep("`scm_vis'") replace

use `scm_rev', clear
capture confirm variable _time
if !_rc rename _time year
keep if inrange(year, 2015, 2024)
keep year _Y_treated _Y_synthetic
rename _Y_treated revenue_actual
rename _Y_synthetic revenue_synthetic
gen double revenue_gap = revenue_actual - revenue_synthetic
save `paths', replace

use `scm_vis', clear
capture confirm variable _time
if !_rc rename _time year
keep if inrange(year, 2015, 2024)
keep year _Y_treated _Y_synthetic
rename _Y_treated visitors_actual
rename _Y_synthetic visitors_synthetic
gen double visitors_gap = visitors_actual - visitors_synthetic
merge 1:1 year using `paths', nogen
sort year
export delimited using "`figdir'/scm_actual_synthetic_gaps.csv", replace

twoway ///
    (line revenue_actual year, lcolor(black) lwidth(medthick)) ///
    (line revenue_synthetic year, lcolor(gs8) lpattern(dash) lwidth(medthick)), ///
    xline(2022, lcolor(black) lpattern(shortdash) lwidth(thin)) ///
    xlabel(2015(1)2024, angle(45) labsize(medsmall)) ylabel(, labsize(medsmall)) ///
    xscale(range(2015 2024)) xtitle("Year", size(medsmall)) ///
    ytitle("Log tourism revenue", size(medsmall)) ///
    title("A. Tourism revenue", size(medium)) ///
    legend(order(1 "Taijiang" 2 "Synthetic Taijiang") pos(6) rows(1) size(medsmall)) ///
    graphregion(color(white)) plotregion(color(white)) xsize(3.75) ysize(3.6) ///
    name(fig1a, replace)

twoway ///
    (line visitors_actual year, lcolor(black) lwidth(medthick)) ///
    (line visitors_synthetic year, lcolor(gs8) lpattern(dash) lwidth(medthick)), ///
    xline(2022, lcolor(black) lpattern(shortdash) lwidth(thin)) ///
    xlabel(2015(1)2024, angle(45) labsize(medsmall)) ylabel(, labsize(medsmall)) ///
    xscale(range(2015 2024)) xtitle("Year", size(medsmall)) ///
    ytitle("Log tourist visitors", size(medsmall)) ///
    title("B. Tourist visitors", size(medium)) ///
    legend(order(1 "Taijiang" 2 "Synthetic Taijiang") pos(6) rows(1) size(medsmall)) ///
    graphregion(color(white)) plotregion(color(white)) xsize(3.75) ysize(3.6) ///
    name(fig1b, replace)

graph combine fig1a fig1b, cols(2) imargin(2 2 2 2) ///
    iscale(1) xsize(7.5) ysize(3.6) graphregion(color(white)) name(fig1, replace)
graph export "`figdir'/figure1_actual_synthetic_trajectories_ab.pdf", replace
graph export "`figdir'/figure1_actual_synthetic_trajectories_ab.png", width(4200) replace
graph export "`proofdir'/Fig1.tif", width(4500) replace
graph export "`proofdir'/Fig1.pdf", replace

twoway ///
    (line revenue_gap year, lcolor(black) lpattern(solid) lwidth(medthick)) ///
    (line visitors_gap year, lcolor(black) lpattern(longdash) lwidth(medthick)), ///
    yline(0, lcolor(gs10) lwidth(thin)) ///
    xline(2022, lcolor(black) lpattern(shortdash) lwidth(thin)) ///
    xlabel(2015(1)2024, angle(45) labsize(medsmall)) ylabel(, labsize(medsmall)) ///
    xscale(range(2015 2024)) xtitle("Year", size(medsmall)) ///
    ytitle("Log-point gap", size(medsmall)) ///
    legend(order(1 "Tourism revenue" 2 "Tourist visitors") pos(6) rows(1) size(medsmall)) ///
    graphregion(color(white)) plotregion(color(white)) xsize(7.5) ysize(4.5) ///
    name(fig2, replace)
graph export "`figdir'/figure2_scm_treatment_gaps_both_outcomes.pdf", replace
graph export "`figdir'/figure2_scm_treatment_gaps_both_outcomes.png", width(3000) replace
graph export "`proofdir'/Fig2.tif", width(4500) replace
graph export "`proofdir'/Fig2.pdf", replace

********************************************************************************
* 2. Figures 3 and 4: complete in-space placebo paths and RMSPE rankings.
********************************************************************************
use `panel_ready', clear
quietly levelsof county_id, local(all_ids)
tempname rankpost
tempfile permutation_summary
postfile `rankpost' str24 outcome int assignments target_rank ///
    double target_ratio exact_p using `permutation_summary', replace

foreach yvar in ln_rev ln_vis {
    local short "revenue"
    local outcome "Tourism revenue"
    local paneltitle "A. Tourism revenue"
    local ylabel "Log-point gap"
    local other "ln_vis"
    if "`yvar'" == "ln_vis" {
        local short "visitors"
        local outcome "Tourist visitors"
        local paneltitle "B. Tourist visitors"
        local other "ln_rev"
    }

    tempfile paths_placebo ratios_placebo
    tempname pathpost ratiopost
    postfile `pathpost' int county_id int year double gap ///
        byte is_target using `paths_placebo', replace
    postfile `ratiopost' int county_id double rmspe_ratio using ///
        `ratios_placebo', replace

    foreach pid of local all_ids {
        tempfile placebo_keep
        use `panel_ready', clear
        capture noisily synth `yvar' `other' ln_pcgdp ln_pop ln_budrev ln_budexp ///
            `yvar'(2015) `yvar'(2016) `yvar'(2017) `yvar'(2018) ///
            `yvar'(2019) `yvar'(2020) `yvar'(2021), ///
            trunit(`pid') trperiod(`trperiod') xperiod(2015(1)2021) ///
            mspeperiod(2015(1)2021) resultsperiod(2015(1)2024) ///
            keep("`placebo_keep'") replace
        local rc = _rc
        if `rc' != 0 continue

        use `placebo_keep', clear
        capture confirm variable _time
        if !_rc rename _time year
        gen double gap = _Y_treated - _Y_synthetic
        gen double sqgap = gap^2
        quietly summarize sqgap if inrange(year, 2015, 2021), meanonly
        scalar pre_rmspe = sqrt(r(mean))
        quietly summarize sqgap if inrange(year, 2022, 2024), meanonly
        scalar post_rmspe = sqrt(r(mean))
        scalar ratio = post_rmspe / pre_rmspe
        forvalues yy = 2015/2024 {
            quietly summarize gap if year == `yy', meanonly
            post `pathpost' (`pid') (`yy') (r(mean)) (`pid' == `trid')
        }
        post `ratiopost' (`pid') (ratio)
    }
    postclose `pathpost'
    postclose `ratiopost'

    use `paths_placebo', clear
    merge m:1 county_id using `lookup', nogen
    save "`figdir'/scm_placebo_paths_`short'.dta", replace

    twoway ///
        (line gap year if is_target == 0, lcolor(gs12) lwidth(thin) cmissing(n)) ///
        (line gap year if is_target == 1, lcolor(black) lpattern(solid) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lwidth(thin)) ///
        xline(2022, lcolor(black) lpattern(shortdash) lwidth(thin)) ///
        xlabel(2015(1)2024, angle(45) labsize(medsmall)) ylabel(, labsize(medsmall)) ///
        xscale(range(2015 2024)) xtitle("Year", size(medsmall)) ///
        ytitle("`ylabel'", size(medsmall)) ///
        title("`paneltitle'", size(medium)) ///
        legend(order(1 "Placebo counties" 2 "Taijiang") pos(6) rows(1) size(medsmall)) ///
        graphregion(color(white)) plotregion(color(white)) xsize(3.75) ysize(3.6) ///
        name(placebo_`short', replace)

    use `ratios_placebo', clear
    gen byte is_target = county_id == `trid'
    quietly summarize rmspe_ratio if is_target == 1, meanonly
    scalar target_ratio = r(mean)
    quietly count if rmspe_ratio >= target_ratio
    scalar target_rank = r(N)
    scalar assignments = _N
    scalar exact_p = target_rank / assignments
    gsort -rmspe_ratio
    gen rank_desc = _n
    save "`figdir'/scm_rmspe_ratios_`short'.dta", replace
    local ranktxt : display %2.0f target_rank
    local ntxt : display %2.0f assignments
    local ptxt : display %4.3f exact_p

    twoway ///
        (scatter rmspe_ratio rank_desc if is_target == 0, ///
            mcolor(gs9) mfcolor(white) msymbol(O) msize(medium)) ///
        (scatter rmspe_ratio rank_desc if is_target == 1, ///
            mcolor(black) mfcolor(black) msymbol(O) msize(large)), ///
        xlabel(, labsize(medsmall)) ylabel(, labsize(medsmall)) ///
        xtitle("Placebo rank", size(medsmall)) ///
        ytitle("Post/pre-RMSPE ratio", size(medsmall)) ///
        title("`paneltitle'", size(medium)) ///
        note("Taijiang rank = `ranktxt'/`ntxt'; exact p = `ptxt'", size(small)) ///
        legend(order(1 "Donor counties" 2 "Taijiang") pos(6) rows(1) size(medsmall)) ///
        graphregion(color(white)) plotregion(color(white)) xsize(3.75) ysize(3.6) ///
        name(rmspe_`short', replace)

    post `rankpost' ("`outcome'") (assignments) (target_rank) ///
        (target_ratio) (exact_p)
}
postclose `rankpost'

graph combine placebo_revenue placebo_visitors, cols(2) imargin(2 2 2 2) ///
    iscale(1) xsize(7.5) ysize(3.6) graphregion(color(white)) name(fig3, replace)
graph export "`figdir'/figure3_inspace_placebo_paths_ab.pdf", replace
graph export "`figdir'/figure3_inspace_placebo_paths_ab.png", width(4200) replace
graph export "`proofdir'/Fig3.tif", width(4500) replace
graph export "`proofdir'/Fig3.pdf", replace

graph combine rmspe_revenue rmspe_visitors, cols(2) imargin(2 2 2 2) ///
    iscale(1) xsize(7.5) ysize(3.6) graphregion(color(white)) name(fig4, replace)
graph export "`figdir'/figure4_rmspe_ratio_placebo_ab.pdf", replace
graph export "`figdir'/figure4_rmspe_ratio_placebo_ab.png", width(4200) replace
graph export "`proofdir'/Fig4.tif", width(4500) replace
graph export "`proofdir'/Fig4.pdf", replace

use `permutation_summary', clear
format target_ratio exact_p %9.3f
export delimited using "`figdir'/table_f1_scm_permutation_both_outcomes.csv", replace
export excel using "`figdir'/table_f1_scm_permutation_both_outcomes.xlsx", firstrow(variables) replace

file open note using "`figdir'/figure_captions.txt", write replace
file write note "Figure 1. Actual and synthetic trajectories for tourism revenue and tourist visitors. Panel A reports log tourism revenue and Panel B reports log tourist visitors. The vertical dashed line marks the 2022 Village BA breakout." _n
file write note "Figure 2. SCM treatment gaps for tourism revenue and tourist visitors. Both series are treated-minus-synthetic gaps on the same log-point scale. The vertical dashed line marks 2022." _n
file write note "Figure 3. In-space placebo paths. Thin grey lines denote all placebo counties; the thick black line denotes Taijiang. The vertical dashed line marks 2022." _n
file write note "Figure 4. Post/pre-RMSPE ratios from in-space placebo tests. The note in each panel reports Taijiang's rank and exact finite-sample permutation p-value." _n
file close note

log close
foreach required in figure1_actual_synthetic_trajectories_ab.pdf ///
    figure2_scm_treatment_gaps_both_outcomes.pdf ///
    figure3_inspace_placebo_paths_ab.pdf ///
    figure4_rmspe_ratio_placebo_ab.pdf {
    capture confirm file "`figdir'/`required'"
    if _rc {
        di as error "Expected figure was not created: `figdir'/`required'"
        exit 601
    }
}
display as result "Figures 1-4 reproduced in `figdir'."
