*=============================================================================
* 03_refered.do
* 目的：把 Codes/03_extract_refered.py 抽出的「立法依据」法律名称写回数据集，
*       新增变量 refered（多个法名用「；」分隔）
*
* 前置：先运行  python3 Codes/03_extract_refered.py
*       生成 Codes/_refered.dta（含 id、refered、n_refered）
*
* 字段说明：
*   refered  —— 法规正文「立法依据」句中提到的上级法律、行政法规名称，
*               按出现顺序去重后以「；」连接；无具名依据的为空字符串
*   例："……根据《中华人民共和国土壤污染防治法》等有关法律、法规，结合本市
*        实际，制定本条例" → refered = "中华人民共和国土壤污染防治法"
*   n_ref    —— 引用上级法律的部数（refered 中「；」分隔的项数）
*   has_ref  —— 是否有具名立法依据（0/1）
*
* 输入：law_env.dta、Codes/_refered.dta
* 输出：law_env.dta（新增 refered、n_ref、has_ref）、Logs/03_refered.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
* global root "`c(pwd)'"   // 若始终从项目根目录运行，可改用当前工作目录
capture mkdir "$root/Logs"
capture log close
log using "$root/Logs/03_refered.log", replace text

*-----------------------------------------------------------------------------
* 1. 读入抽取结果
*-----------------------------------------------------------------------------
confirm file "$root/Codes/_refered.dta"
use "$root/Codes/_refered.dta", clear
rename n_refered n_ref
quietly count
di as txt "抽取结果：" r(N) " 条"
tempfile refs
save `refs'

*-----------------------------------------------------------------------------
* 2. 合并回主数据
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
capture drop refered n_ref has_ref      // 允许脚本重复运行
quietly count
local nmain = r(N)
merge 1:1 id using `refs', nogen keep(master match)
quietly count if missing(refered)
di as txt "未匹配到抽取结果：" r(N) " 条"

* 3. 校验后保存
quietly count
if r(N) != `nmain' {
    di as err "合并后记录数异常（`nmain' → " r(N) "），未保存。"
    log close
    exit
}
replace refered = "" if missing(refered)
gen byte has_ref = (refered != "")
label variable refered "立法依据涉及的上级法律（；分隔）"
label variable n_ref   "引用上级法律数量"
label variable has_ref "是否有具名立法依据"

save "$root/law_env.dta", replace
di as res "已保存：law_env.dta 新增 refered、n_ref、has_ref"

*-----------------------------------------------------------------------------
* 4. 复核
*-----------------------------------------------------------------------------
describe refered n_ref has_ref
tab has_ref, m
summarize n_ref, detail

di as res _n "== 示例：前 5 条有具名依据的记录 =="
list id title refered if has_ref == 1 in 1/5, clean noobs

di as res _n "== 抽查：随机 5 条无具名依据的记录（看其依据句是否确实无具名法） =="
preserve
    keep if has_ref == 0
    set seed 20261105
    gen double u = runiform()
    sort u
    list title in 1/5, clean noobs
restore

log close
*=============================================================================
