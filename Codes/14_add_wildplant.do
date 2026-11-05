*=============================================================================
* 14_add_wildplant.do
* 目的：补入《中华人民共和国野生植物保护条例》（行政法规）
* 来源：国家林业和草原局 https://www.forestry.gov.cn/main/3950/20170314/459881.html
*       1996-09-30 国务院令第204号发布，2017-10-07 国务院令第687号修正，共 32 条
* 说明：地方立法多引用此条例；此前被误记为"野生植物保护法"，由 03 抽取脚本
*       的 NAME_FIX 统一更正为正式名称，故不需要别名记录
*=============================================================================
version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/14_add_wildplant.log", replace text

use "$root/law_env.dta", clear
quietly count if title == "中华人民共和国野生植物保护条例"
if r(N) > 0 {
    di as err "已存在，未做修改。"
    log close
    exit
}
quietly count
local n0 = r(N)
quietly summarize id
local newid = r(max) + 1

frame create wp
frame wp {
    import delimited "$root/Codes/_wildplant.csv", clear varnames(1) ///
        stringcols(_all) bindquote(strict) maxquotedrows(1000) encoding("utf-8") case(preserve)
    gen long k1 = 1
}
frame wp: local pd = publish[1]
frame wp: local el = env_level[1]
frame wp: local et = env_topic[1]
frame wp: local su = source_id[1]

set obs `=`n0' + 1'
local new = _N
replace id = `newid' in `new'
replace title = "中华人民共和国野生植物保护条例" in `new'
replace category = "行政法规" in `new'
replace type = "行政法规" in `new'
replace status = "有效" in `new'
replace publish = cofd(date("`pd'","YMD")) in `new'
replace publish_year = year(date("`pd'","YMD")) in `new'
replace expiry = "" in `new'
replace file_path = "" in `new'
replace source_id = "`su'" in `new'
replace env_level = real("`el'") in `new'
replace env_topic = "`et'" in `new'
replace env_keywords = "" in `new'
replace region_level = 1 in `new'
replace province_name = "全国" in `new'
replace province_code = . in `new'
replace city_name = "" in `new'
replace city_code = . in `new'
replace county_name = "" in `new'
replace county_code = . in `new'
replace dup_count = 1 in `new'
replace create_time = "2026-11-06 00:20:00" in `new'
format publish %tc

gen long k1 = .
replace k1 = 1 in `new'
frlink m:1 k1, frame(wp)
frget txt = content, from(wp)
replace content = txt if !missing(k1)
drop k1 txt wp

quietly count
di as txt "总条数：" r(N)
save "$root/law_env.dta", replace
list id title type publish env_level in `new', clean noobs
log close
*=============================================================================
