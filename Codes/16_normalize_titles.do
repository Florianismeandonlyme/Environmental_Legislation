*=============================================================================
* 16_normalize_titles.do
* 目的：统一 law_env 标题中的书名号写法
*   库内部分记录用全角尖括号"＜…＞"，部分用书名号"《…》"，
*   导致同一部法在 refered 与 title 之间无法逐字一致。
*   本脚本把 title 中的 ＜＞ 统一替换为 《》。
*=============================================================================
version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/16_normalize_titles.log", replace text

use "$root/law_env.dta", clear
quietly count if strpos(title, "＜") > 0 | strpos(title, "＞") > 0
di as txt "含全角尖括号的标题：" r(N) " 条"
list title if strpos(title, "＜") > 0 | strpos(title, "＞") > 0, clean noobs

replace title = subinstr(title, "＜", "《", .)
replace title = subinstr(title, "＞", "》", .)
quietly count if strpos(title, "＜") > 0 | strpos(title, "＞") > 0
di as txt "替换后仍含尖括号：" r(N) " 条"

duplicates report title
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta"
log close
*=============================================================================
