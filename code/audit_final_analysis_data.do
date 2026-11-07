version 17.0
clear all
set more off

* Audit final data used in all freeze-version analyses.
local root "`c(pwd)'"
local outdir "`root'/output"
local auditdir "`outdir'/final_data_audit"
cap mkdir "`auditdir'"
local paneldta "`outdir'/qiandongnan_county_panel_2015_2024_analysis_ready.dta"

capture log close
log using "`auditdir'/audit_final_analysis_data.log", text replace
use "`paneldta'", clear
xtset county_id year
assert _N == 160
quietly levelsof county_id, local(ids)
assert `: word count `ids'' == 16
quietly tab year
assert year >= 2015 & year <= 2024
by county_id: assert _N == 10

* Audit the correction that is part of the frozen final data file.
assert bud_rev_10k == 191019 if county == "凯里市" & year == 2021
assert bud_exp_10k == 659265 if county == "凯里市" & year == 2021
assert abs(ln_bud_rev - ln(191019)) < 1e-12 if county == "凯里市" & year == 2021
assert abs(ln_bud_exp - ln(659265)) < 1e-12 if county == "凯里市" & year == 2021

* Audit the final 2024 tourism-revenue values (RMB 100 million).
assert abs(tour_rev_bn - 24.98)  < 1e-6 if county_id == 1  & year == 2024
assert abs(tour_rev_bn - 31.14)  < 1e-6 if county_id == 2  & year == 2024
assert abs(tour_rev_bn - 59.28)  < 1e-6 if county_id == 3  & year == 2024
assert abs(tour_rev_bn - 337.45) < 1e-6 if county_id == 4  & year == 2024
assert abs(tour_rev_bn - 35.68)  < 1e-6 if county_id == 5  & year == 2024
assert abs(tour_rev_bn - 43.66)  < 1e-6 if county_id == 6  & year == 2024
assert abs(tour_rev_bn - 30.14)  < 1e-6 if county_id == 7  & year == 2024
assert abs(tour_rev_bn - 18.53)  < 1e-6 if county_id == 8  & year == 2024
assert abs(tour_rev_bn - 33.80)  < 1e-6 if county_id == 9  & year == 2024
assert abs(tour_rev_bn - 108.03) < 1e-6 if county_id == 10 & year == 2024
assert abs(tour_rev_bn - 31.67)  < 1e-6 if county_id == 11 & year == 2024
assert abs(tour_rev_bn - 117.94) < 1e-6 if county_id == 12 & year == 2024
assert abs(tour_rev_bn - 144.76) < 1e-6 if county_id == 13 & year == 2024
assert abs(tour_rev_bn - 21.77)  < 1e-6 if county_id == 14 & year == 2024
assert abs(tour_rev_bn - 25.03)  < 1e-6 if county_id == 15 & year == 2024
assert abs(tour_rev_bn - 71.07)  < 1e-6 if county_id == 16 & year == 2024
assert abs(ln_tour_rev - ln(tour_rev_bn)) < 1e-6

* Main outcomes/covariates are complete in the final balanced estimation file.
foreach v in ln_tour_rev ln_tour_vis ln_pcgdp ln_pop ln_bud_rev ln_bud_exp {
    assert !missing(`v')
}

preserve
keep if (county == "台江县" & year == 2016) | ///
        (county == "镇远县" & year == 2017) | ///
        (county == "天柱县" & year == 2016) | ///
        (county == "麻江县" & year == 2017)
keep county year tour_rev_bn tour_vis_10k ln_tour_rev ln_tour_vis
sort county year
export delimited using "`auditdir'/table_a1_reconstructed_tourism_observations.csv", replace
export excel using "`auditdir'/table_a1_reconstructed_tourism_observations.xlsx", firstrow(variables) replace
restore

file open note using "`auditdir'/data_audit_note.txt", write replace
file write note "Final analysis data audit" _n
file write note "Panel: 16 counties x 10 years (2015-2024) = 160 county-year observations." _n
file write note "Kaili 2021 general-budget revenue: 191019 (10k yuan); expenditure: 659265 (10k yuan)." _n
file write note "All 16 final 2024 tourism-revenue values were verified in RMB 100 million; log revenue was recomputed consistently." _n
file write note "Eight tourism outcomes reconstructed arithmetically from official reported levels and growth rates:" _n
file write note "Taijiang 2016 revenue and arrivals; Zhenyuan 2017 revenue and arrivals; Tianzhu 2016 revenue and arrivals; Majiang 2017 revenue and arrivals." _n
file write note "No KNN or statistical interpolation is used for tourism outcomes or covariates in the causal estimators." _n
file close note
log close
