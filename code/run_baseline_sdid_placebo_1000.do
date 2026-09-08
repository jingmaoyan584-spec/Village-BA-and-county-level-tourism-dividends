version 17.0
clear all
set more off
set linesize 255

* Baseline SDID placebo inference for the main manuscript results.
* Uses the final analysis-ready .dta; no CSV input is used.
local root "`c(pwd)'"
local paneldta "`root'/output/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
local outdir "`root'/output/baseline_sdid"
local trid 6
local seed 20260820
local reps 1000

cap mkdir "`outdir'"
capture log close
log using "`outdir'/baseline_sdid_placebo_1000.log", text replace

use "`paneldta'", clear
keep if inrange(year, 2015, 2024)
capture confirm variable ln_rev
if _rc gen ln_rev = ln_tour_rev
capture confirm variable ln_vis
if _rc gen ln_vis = ln_tour_vis
xtset county_id year

tempfile panel results
save `panel', replace

tempname posth
postfile `posth' str24 outcome str12 period ///
    double att placebo_se ci_lo_95 ci_hi_95 pvalue effect_pct reps ///
    using `results', replace

foreach yvar in ln_rev ln_vis {
    local label "Tourism revenue"
    if "`yvar'" == "ln_vis" local label "Tourist visitors"

    * Immediate breakout year: 2015-2022, with treatment in 2022.
    use `panel', clear
    keep if inrange(year, 2015, 2022)
    gen treated_2022 = county_id == `trid' & year == 2022
    sdid `yvar' county_id year treated_2022, ///
        vce(placebo) reps(`reps') seed(`seed')
    scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
    scalar lo = e(ATT) - invnormal(.975) * e(se)
    scalar hi = e(ATT) + invnormal(.975) * e(se)
    post `posth' ("`label'") ("2022") (e(ATT)) (e(se)) ///
        (lo) (hi) (p) (100 * (exp(e(ATT)) - 1)) (`reps')

    * Institutional-expansion stage: omit 2022 and treat 2023-2024 as post.
    use `panel', clear
    drop if year == 2022
    egen time_id = group(year)
    gen treated_post = county_id == `trid' & year >= 2023
    sdid `yvar' county_id time_id treated_post, ///
        vce(placebo) reps(`reps') seed(`seed')
    scalar p = 2 * (1 - normal(abs(e(ATT) / e(se))))
    scalar lo = e(ATT) - invnormal(.975) * e(se)
    scalar hi = e(ATT) + invnormal(.975) * e(se)
    post `posth' ("`label'") ("2023-2024") (e(ATT)) (e(se)) ///
        (lo) (hi) (p) (100 * (exp(e(ATT)) - 1)) (`reps')
}
postclose `posth'

use `results', clear
format att placebo_se ci_lo_95 ci_hi_95 pvalue effect_pct %9.3f
export delimited using "`outdir'/table_main_baseline_sdid_placebo_1000.csv", replace
export excel using "`outdir'/table_main_baseline_sdid_placebo_1000.xlsx", ///
    firstrow(variables) replace

mkmat att placebo_se ci_lo_95 ci_hi_95 pvalue effect_pct, matrix(main_sdid)
matrix rownames main_sdid = ///
    revenue_2022 revenue_2023_2024 visitors_2022 visitors_2023_2024
matrix colnames main_sdid = ATT placebo_SE CI_lower CI_upper p_value effect_pct
esttab matrix(main_sdid, fmt(3 3 3 3 3 2)) using ///
    "`outdir'/table_main_baseline_sdid_placebo_1000.rtf", replace ///
    title("Baseline SDID placebo inference") ///
    nonumber nomtitles noobs compress ///
    addnotes("Placebo standard errors use `reps' replications and seed `seed'." ///
             "Confidence intervals and p-values use normal approximation based on placebo standard errors." ///
             "Effects are 100*[exp(ATT)-1].")

file open note using "`outdir'/README.txt", write replace
file write note "Baseline SDID placebo inference for the main manuscript." _n
file write note "Both outcomes use the final .dta, vce(placebo), 1,000 repetitions, and seed 20260820." _n
file write note "Treatment periods: 2022 and 2023-2024, matching the manuscript specifications." _n
file close note

log close
