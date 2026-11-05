*=============================================================================
* 06_merge_national.do
* 目的：把 law_env_national.dta（120 条国家级）合并回 law_env.dta
*
* 处理要点：
*   1) 新补入的 8 部国家级法律当初用 30505–30512 编号，与地方库 id 冲突
*      （如 30510 = 长沙市城市供水用水管理条例），合并前重新编号；
*   2) 合并后 id 必须唯一，否则报错不保存；
*   3) 备份：脚本开头把当前 law_env.dta 复制为 law_env_premerge.dta
*
* 输入：law_env.dta（3,635）、law_env_national.dta（120）
* 输出：law_env.dta（3,755）、law_env_national.dta（id 已重排）
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/06_merge_national.log", replace text

*-----------------------------------------------------------------------------
* 1. 备份
*-----------------------------------------------------------------------------
capture confirm file "$root/law_env.dta"
copy "$root/law_env.dta" "$root/law_env_premerge.dta", replace
di as txt "已备份：law_env_premerge.dta"

*-----------------------------------------------------------------------------
* 2. 给 national 中与地方库冲突的 id 重新编号
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
keep id
tempfile locids
save `locids'
quietly summarize id
local maxid = r(max)
di as txt "地方库 id 最大值：" `maxid'

use "$root/law_env_national.dta", clear
merge m:1 id using `locids', keep(master match) gen(inloc)
quietly count if inloc == 3
local nconf = r(N)
di as txt "national 中与地方库冲突的 id：" `nconf' " 个"

if `nconf' > 0 {
    sort inloc id
    local next = `maxid' + 1
    quietly levelsof id if inloc == 3, local(oldids)
    foreach o of local oldids {
        replace id = `next' if id == `o' & inloc == 3
        di as txt "  id `o' -> `next'"
        local ++next
    }
}
drop inloc

* 自检：national 内部 id 唯一
duplicates report id
quietly duplicates report id
if r(unique_value) != r(N) {
    di as err "national 内部 id 不唯一，未保存。"
    log close
    exit
}
save "$root/law_env_national.dta", replace

*-----------------------------------------------------------------------------
* 3. 合并
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
quietly count
local nloc = r(N)
append using "$root/law_env_national.dta"
quietly count
local nall = r(N)
di as txt _n "合并：`nloc' + " `nall' - `nloc' " = `nall' 条"

* 4. 校验
duplicates report id
quietly duplicates report id
if r(unique_value) != r(N) {
    di as err "合并后 id 不唯一，未保存。"
    log close
    exit
}

tab region_level, m
save "$root/law_env.dta", replace
di as res _n "已保存：law_env.dta 共 " r(N) " 条，id 唯一"

log close
*=============================================================================
