*=============================================================================
* 13_fill_stubs.do
* 目的：把 11 抓到的原文回填到 law_env 中仍为空的记录（不动 id、不动名称）
*
* 输入：law_env.dta、Codes/_stub_fills.csv
* 输出：law_env.dta、Logs/13_fill_stubs.log
*=============================================================================
version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/13_fill_stubs.log", replace text

confirm file "$root/Codes/_stub_fills.csv"
frame create fills
frame fills {
    import delimited "$root/Codes/_stub_fills.csv", clear varnames(1) ///
        stringcols(_all) bindquote(strict) maxquotedrows(3000) ///
        encoding("utf-8") case(preserve)
    gen long k1 = _n
    quietly count
    di as txt "待回填：" r(N) " 条"
}
frame fills: quietly count
local nf = r(N)

use "$root/law_env.dta", clear
gen long k1 = .
local hit = 0
forvalues i = 1/`nf' {
    frame fills: local t = title[`i']
    quietly count if title == "`t'" & content == ""
    if r(N) == 1 {
        quietly replace k1 = `i' if title == "`t'" & content == ""
        local ++hit
    }
}
di as txt "匹配到空壳记录：" `hit' " 条"

frlink m:1 k1, frame(fills)
frget newcontent = content, from(fills)
quietly replace content = newcontent if !missing(k1)
quietly count if !missing(k1)
di as txt "已回填正文：" r(N) " 条"

* 来源与日期
tempfile f2
frame fills: save `f2', replace
quietly count if !missing(k1)
drop k1 newcontent
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta"

quietly count if content == ""
di as txt "仍无正文的记录：" r(N) " 条"
log close
*=============================================================================
