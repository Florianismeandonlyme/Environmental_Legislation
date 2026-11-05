*=============================================================================
* 17_reclassify_local.do
* 目的：纠正 5 条被误标为"国家级"的地方性法规
*   这些是按名称规则自动推断 type/region_level 时出错的（见 10_build_missing_csv.py），
*   名称里带"经济特区/自由贸易港/开发区/地方性法规"等地方标识，实为省级人大立法。
*   若不纠正，按 region_level==1 取"国家立法"样本时会被误纳入。
*=============================================================================
version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/17_reclassify_local.log", replace text

use "$root/law_env.dta", clear

local t1 "海南经济特区水条例"
local t2 "海南自由贸易港海口江东新区条例"
local t3 "天津经济技术开发区管理条例"
local t4 "关于取消或调整部分地方性法规设定的行政审批等项目的决定"
local t5 "关于取消部分地方性法规中行政许可项目的决定"

* 海南省（460000）
foreach t in "`t1'" "`t2'" {
    replace type = "地方性法规" if title == "`t'"
    replace region_level = 2 if title == "`t'"
    replace province_name = "海南省" if title == "`t'"
    replace province_code = 460000 if title == "`t'"
}
* 天津市（120000）
replace type = "地方性法规" if title == "`t3'"
replace region_level = 2 if title == "`t3'"
replace province_name = "天津市" if title == "`t3'"
replace province_code = 120000 if title == "`t3'"
* 重庆市（500000）
foreach t in "`t4'" "`t5'" {
    replace type = "地方性法规" if title == "`t'"
    replace region_level = 2 if title == "`t'"
    replace province_name = "重庆市" if title == "`t'"
    replace province_code = 500000 if title == "`t'"
}

list id title type region_level province_name ///
    if inlist(title, "`t1'", "`t2'", "`t3'", "`t4'", "`t5'"), clean noobs
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta"
log close
*=============================================================================
