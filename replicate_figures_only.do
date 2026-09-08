version 17.0
clear all
set more off
set linesize 255

* Fast figure-only entry point. It is useful for checking Figures 1-4 without
* waiting for the 1,000-replication generated-weight bootstrap and 9,999-rep
* Webb bootstrap used by the complete replication.
local root "`c(pwd)'"
local thisfile "`c(filename)'"
local slash = max(strrpos("`thisfile'", "/"), strrpos("`thisfile'", char(92)))
if `slash' > 0 {
    local thisdir = substr("`thisfile'", 1, `slash' - 1)
    capture confirm file "`thisdir'/data/qiandongnan_county_panel_2015_2024_analysis_ready.dta"
    if !_rc local root "`thisdir'"
}
cd "`root'"
do "code/replicate_four_scm_figures.do"
display as result "Figure-only replication completed: `root'/output/figures/"
