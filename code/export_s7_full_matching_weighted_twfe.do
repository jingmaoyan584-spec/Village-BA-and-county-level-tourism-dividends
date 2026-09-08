version 17.0
clear all
set more off
set linesize 255

********************************************************************************
* S7 Table. Full matching-weighted TWFE regression results.
* Panel A: baseline (2015-2024; weights estimated from 2015-2021 features).
* Panel B: COVID-excluded (2015-2019 and 2022-2024; weights from 2015-2019).
* Webb wild-cluster bootstrap p-values are reported for treatment terms only.
********************************************************************************

args reps
if "`reps'" == "" local reps 9999

local root "`c(pwd)'"
local outdir "`root'/output"
local tabdir "`outdir'/supplementary_tables_final_rtf"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local trid 6

cap mkdir "`tabdir'"
capture confirm file "`paneldta'"
if _rc {
    di as error "Required analysis data not found: `paneldta'"
    exit 601
}

cap which esttab
if _rc ssc install estout, replace
cap which boottest
if _rc ssc install boottest, replace

capture log close
log using "`tabdir'/S7_full_matching_weighted_TWFE.log", text replace

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
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
tempfile panel
save `panel', replace

capture program drop make_kernel_weights
program define make_kernel_weights
    syntax , Paneldata(string) Firstyear(integer) Lastyear(integer) Treatid(integer) Saveas(string)

    tempfile slope_rev slope_vis
    use "`paneldata'", clear
    keep if inrange(year, `firstyear', `lastyear')
    statsby slope_rev=_b[year], by(county_id) clear: regress ln_rev year
    save `slope_rev', replace

    use "`paneldata'", clear
    keep if inrange(year, `firstyear', `lastyear')
    statsby slope_vis=_b[year], by(county_id) clear: regress ln_vis year
    save `slope_vis', replace

    use "`paneldata'", clear
    keep if inrange(year, `firstyear', `lastyear')
    collapse (mean) mean_ln_rev=ln_rev mean_ln_vis=ln_vis mean_ln_pcgdp=ln_pcgdp ///
        mean_ln_pop=ln_pop mean_ln_budrev=ln_budrev mean_ln_budexp=ln_budexp, by(county_id)
    merge 1:1 county_id using `slope_rev', nogen
    merge 1:1 county_id using `slope_vis', nogen

    foreach v in mean_ln_rev slope_rev mean_ln_vis slope_vis mean_ln_pcgdp mean_ln_pop mean_ln_budrev mean_ln_budexp {
        egen z_`v' = std(`v')
        quietly summarize z_`v' if county_id == `treatid', meanonly
        scalar tr_`v' = r(mean)
    }
    gen double distance = sqrt( ///
        (z_mean_ln_rev-tr_mean_ln_rev)^2 + (z_slope_rev-tr_slope_rev)^2 + ///
        (z_mean_ln_vis-tr_mean_ln_vis)^2 + (z_slope_vis-tr_slope_vis)^2 + ///
        (z_mean_ln_pcgdp-tr_mean_ln_pcgdp)^2 + (z_mean_ln_pop-tr_mean_ln_pop)^2 + ///
        (z_mean_ln_budrev-tr_mean_ln_budrev)^2 + (z_mean_ln_budexp-tr_mean_ln_budexp)^2)
    gen double matching_weight = exp(-distance)
    replace matching_weight = . if county_id == `treatid'
    quietly summarize matching_weight, meanonly
    replace matching_weight = matching_weight / r(sum)
    keep county_id matching_weight
    save "`saveas'", replace
end

tempfile weights_baseline weights_covid results
make_kernel_weights, paneldata("`panel'") firstyear(2015) lastyear(2021) treatid(`trid') saveas("`weights_baseline'")
make_kernel_weights, paneldata("`panel'") firstyear(2015) lastyear(2019) treatid(`trid') saveas("`weights_covid'")

tempname resultpost
postfile `resultpost' str20 panel str24 outcome str32 term double coefficient clustered_se ///
    ci_lower ci_upper clustered_p webb_p N r2 adj_r2 using `results', replace

foreach specification in baseline covid_excluded {
    if "`specification'" == "baseline" {
        local panel_label "Panel A: Baseline"
        local weightfile `weights_baseline'
        local sample_condition "inrange(year, 2015, 2024)"
    }
    else {
        local panel_label "Panel B: COVID-excluded"
        local weightfile `weights_covid'
        local sample_condition "!inlist(year, 2020, 2021)"
    }

    foreach yvar in ln_rev ln_vis {
        use `panel', clear
        keep if `sample_condition'
        merge m:1 county_id using `weightfile', nogen
        replace matching_weight = 1 if county_id == `trid'
        assert !missing(matching_weight)
        capture drop treated did_2022 did_post
        gen byte treated = county_id == `trid'
        gen byte did_2022 = treated * (year == 2022)
        gen byte did_post = treated * (year >= 2023)

        quietly regress `yvar' did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp ///
            i.county_id i.year [aw=matching_weight], vce(cluster county_id)

        if "`yvar'" == "ln_rev" local outcome_label "Log tourism revenue"
        else local outcome_label "Log tourist visitors"
        foreach term in did_2022 did_post ln_pcgdp ln_pop ln_budrev ln_budexp {
            scalar b = _b[`term']
            scalar se = _se[`term']
            scalar crit = invttail(e(df_r), .025)
            scalar lo = b - crit * se
            scalar hi = b + crit * se
            scalar p_cluster = 2 * ttail(e(df_r), abs(b / se))
            scalar p_webb = .
            if inlist("`term'", "did_2022", "did_post") {
                quietly boottest `term', cluster(county_id) reps(`reps') seed(20260820) weight(webb) nograph
                scalar p_webb = r(p)
                display as result "S7 `specification' `outcome_label' `term': Webb wild-cluster p = " %9.6f p_webb
            }
            local term_label ""
            if "`term'" == "did_2022" local term_label "Treatment x 2022"
            if "`term'" == "did_post"  local term_label "Treatment x Post (2023-2024)"
            if "`term'" == "ln_pcgdp"  local term_label "Log per-capita GDP"
            if "`term'" == "ln_pop"    local term_label "Log resident population"
            if "`term'" == "ln_budrev" local term_label "Log budget revenue"
            if "`term'" == "ln_budexp" local term_label "Log budget expenditure"
            post `resultpost' ("`specification'") ("`outcome_label'") ("`term_label'") ///
                (b) (se) (lo) (hi) (p_cluster) (p_webb) (e(N)) (e(r2)) (e(r2_a))
        }
    }
}
postclose `resultpost'

use `results', clear
order panel outcome term coefficient clustered_se ci_lower ci_upper clustered_p webb_p N r2 adj_r2
gen byte term_order = cond(term == "Treatment x 2022", 1, ///
    cond(term == "Treatment x Post (2023-2024)", 2, ///
    cond(term == "Log per-capita GDP", 3, ///
    cond(term == "Log resident population", 4, ///
    cond(term == "Log budget revenue", 5, 6)))))
sort panel outcome term_order
drop term_order
export delimited using "`tabdir'/S7_full_matching_weighted_TWFE_results.csv", replace
export excel using "`tabdir'/S7_full_matching_weighted_TWFE_results.xlsx", firstrow(variables) replace

* Two long-form panels retain every requested statistic for every covariate.
* Webb p-values are intentionally blank for controls because the sensitivity is
* defined only for the two treatment coefficients.
foreach specification in baseline covid_excluded {
    preserve
    keep if panel == "`specification'"
    gen rowid = _n
    mkmat coefficient clustered_se ci_lower ci_upper clustered_p webb_p N r2 adj_r2, matrix(s7mat)
    local rownames ""
    forvalues i = 1/`=_N' {
        local outcome = outcome[`i']
        local term = term[`i']
        local outcome = subinstr("`outcome'", " ", "_", .)
        local term = subinstr("`term'", " ", "_", .)
        local term = subinstr("`term'", "(", "", .)
        local term = subinstr("`term'", ")", "", .)
        local term = subinstr("`term'", "-", "_", .)
        local rownames "`rownames' R`i'"
        local label`i' "`outcome': `term'"
    }
    matrix rownames s7mat = `rownames'
    matrix colnames s7mat = coefficient clustered_SE ci_lower ci_upper clustered_p webb_p N R2 adjusted_R2
    if "`specification'" == "baseline" {
        local title "S7 Table. Full matching-weighted TWFE regression results. Panel A: Baseline (2015-2024)."
        local mode replace
    }
    else {
        local title "Panel B: COVID-excluded (2015-2019 and 2022-2024)."
        local mode append
    }
    esttab matrix(s7mat, fmt(3 3 3 3 3 3 0 3 3)) using ///
        "`tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf", `mode' ///
        title("`title'") ///
        collabels("Coefficient" "Clustered SE" "95% CI lower" "95% CI upper" "Clustered p-value" "Webb p-value" "N" "R-squared" "Adjusted R-squared") ///
        nomtitles nonumber ///
        addnotes("County fixed effects: Yes. Year fixed effects: Yes. Standard errors are clustered by county.", ///
                 "Webb wild-cluster bootstrap p-values use `reps' replications, seed 20260820, and are reported only for treatment coefficients.", ///
                 "Panel A weights use 2015-2021 features; Panel B weights use 2015-2019 features and excludes 2020-2021 for every county.")
    forvalues i = `=_N'(-1)1 {
        tempfile clean`i'
        filefilter "`tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf" "`clean`i''", ///
            from("R`i'") to("`label`i''") replace
        copy "`clean`i''" "`tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf", replace
    }
    restore
}

* Convert legal Stata-name separators in matrix row labels back to display text.
tempfile s7clean
filefilter "`tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf" "`s7clean'", ///
    from("_") to(" ") replace
copy "`s7clean'" "`tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf", replace

file open readme using "`tabdir'/S7_README.txt", write replace
file write readme "S7 is generated from the final 2015-2024 analysis .dta using matching-weighted TWFE." _n
file write readme "Both panels include county and year fixed effects and county-clustered standard errors." _n
file write readme "Webb wild-cluster bootstrap p-values are calculated only for treatment coefficients, with `reps' replications." _n
file close readme

log close
display as result "S7 RTF table created: `tabdir'/S7_Table_full_matching_weighted_TWFE_regression_results.rtf"
