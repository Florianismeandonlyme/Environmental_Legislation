*=============================================================================
* 07_build_law_refered.do
* 目的：由 law_env.dta 的 refered 字段生成"法规—被引法律"的引用关系长表
*       law_refered.dta，含 4 个字段：
*         raw_law         引用方（做出引用的法规）名称
*         raw_law_id      引用方 id
*         refered_law     被引用的法律名称（原始提取文本）
*         refered_law_id  被引法律在 law_env.dta 中的 id；库中无对应记录则缺失
*
* 规则：
*   1) refered 以「；」分隔，拆成多行：引用 n 部法律 = n 条记录
*   2) 名称匹配前先归一化：去《》、去空白、去尾部括注（如"（2018年修正）"）
*   3) 同一法名在库中有多条记录时，只保留一个 id：
*      优先 publish_year 最新，若同年取 id 最小者（保证 name→id 唯一）
*   4) 匹配不上的引用保留在表中，refered_law_id 缺失，便于后续补充
*
* 前置：law_env.dta 已包含国家级与地方级全部记录，且已有 refered 字段
* 输出：law_refered.dta、Logs/07_build_law_refered.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/07_build_law_refered.log", replace text

*-----------------------------------------------------------------------------
* 1. 构建"归一化法名 → 唯一 id"查询表
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
quietly count
local nrec = r(N)
keep id title publish_year
gen str244 ntitle = ustrregexra(title, "[《》＜＞<>]", "")
replace ntitle = ustrregexra(ntitle, "\s", "")
replace ntitle = ustrregexra(ntitle, "[（(][^）)]*[）)]$", "")

gsort ntitle -publish_year id
by ntitle: gen byte seq = _n

quietly count if seq == 1
di as txt "库内记录 " `nrec' " 条 → 归一化后不同法名 " r(N) " 个"
quietly count if seq > 1
di as txt "同名多记录（已按 最新年份→最小id 保留其一）：" r(N) " 条"

keep if seq == 1
keep ntitle id
rename id refered_law_id
tempfile lookup
save `lookup'

* 1b. 并入名称变体别名（错字、多余前缀等），避免重复入库
capture confirm file "$root/Codes/_law_aliases.csv"
if _rc == 0 {
    import delimited "$root/Codes/_law_aliases.csv", clear ///
        varnames(1) encoding("utf-8") stringcols(1)
    append using `lookup'
    bysort ntitle: keep if _n == 1     // 别名行在前，优先保留
    quietly count
    di as txt "并入别名后查表条目：" r(N)
    save `lookup', replace
}

*-----------------------------------------------------------------------------
* 2. 拆开 refered，生成引用关系
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
keep id title refered          // 只保留所需变量，避免把 strL 正文带进边表
keep if refered != ""
quietly count
di as txt "有具名依据的记录：" r(N) " 条"

split refered, parse("；") gen(r)
reshape long r, i(id) j(k)
drop if r == ""
quietly count
local nedge = r(N)
di as txt "共生成引用关系 " `nedge' " 条"

rename id raw_law_id
rename title raw_law
rename r refered_law
drop k refered

gen str244 ntitle = ustrregexra(refered_law, "[《》＜＞<>]", "")
replace ntitle = ustrregexra(ntitle, "\s", "")
replace ntitle = ustrregexra(ntitle, "[（(][^）)]*[）)]$", "")

merge m:1 ntitle using `lookup', keep(master match) nogen
drop ntitle

*-----------------------------------------------------------------------------
* 3. 整理与标注
*-----------------------------------------------------------------------------
order raw_law raw_law_id refered_law refered_law_id
label variable raw_law        "引用方法规名称"
label variable raw_law_id     "引用方 id"
label variable refered_law    "被引用的法律名称"
label variable refered_law_id "被引法律 id（库中无则缺失）"
label data "法规引用关系长表：一行 = 一条引用"

sort raw_law_id refered_law
save "$root/law_refered.dta", replace
di as res "已保存：law_refered.dta（" _N " 条）"

*-----------------------------------------------------------------------------
* 4. 复核
*-----------------------------------------------------------------------------
quietly count if !missing(refered_law_id)
di as txt _n "能匹配到 id 的引用：" r(N) " / " _N "（" %4.1f 100*r(N)/_N "%）"
quietly count if refered_law_id == raw_law_id
di as txt "自引（被引 id 与引用方相同）：" r(N) " 条"

di as res _n "== 被引次数前十（按被引法律名称） =="
preserve
    keep refered_law refered_law_id
    contract refered_law, freq(f)
    gsort -f
    list refered_law f in 1/10, clean noobs
restore

di as res _n "== 前 5 条记录 =="
list in 1/5, clean noobs
log close
*=============================================================================
