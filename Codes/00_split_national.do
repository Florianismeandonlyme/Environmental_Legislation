*=============================================================================
* 00_split_national.do
* 目的：把 law_env.dta 中国家级（region_level==1）的记录拆出来，
*       单独存为 law_env_national.dta，并从 law_env.dta 中删除这部分记录
*
* 说明：
*   1) 拆出的 112 条记录 province_name 均为"全国"，是中央层级的法律法规，
*      与省级立法（region_level==2）属于不同层次的观测，混在一起会干扰
*      分省计数，因此单列。
*   2) 本脚本可重复运行：若 law_env.dta 中已无 region_level==1 的记录，
*      会提示"已拆分过"并直接退出，不会清空 law_env_national.dta。
*   3) 运行前请确认已有原文件备份（law_env_backup_full.dta）。
*   4) 脚本不对变量重压缩（未用 compress），保持与原始文件完全一致的类型定义。
*
* 输入：law_env.dta
* 输出：law_env_national.dta（国家级）
*       law_env.dta        （已剔除国家级，保留其余 3,635 条）
*       Logs/00_split_national.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
* global root "`c(pwd)'"   // 若始终从项目根目录运行，可改用当前工作目录
capture mkdir "$root/Logs"
capture log close
log using "$root/Logs/00_split_national.log", replace text

*-----------------------------------------------------------------------------
* 1. 体检：确认是否已经拆分过
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
quietly count
local n0 = r(N)
quietly count if region_level == 1
local n1 = r(N)
di as txt "law_env.dta 现有记录：" `n0' " 条"
di as txt "其中 region_level==1（国家级）：" `n1' " 条"

if `n1' == 0 {
    di as err _n "law_env.dta 中已无国家级记录，可能已经拆分过；本脚本不做修改。"
    log close
    exit
}
* 拆完后应有的省级及以下记录数
local n2 = `n0' - `n1'

*-----------------------------------------------------------------------------
* 2. 抽出国家级 → law_env_national.dta
*-----------------------------------------------------------------------------
keep if region_level == 1
save "$root/law_env_national.dta", replace
quietly count
di as res "law_env_national.dta 已生成：" r(N) " 条"

*-----------------------------------------------------------------------------
* 3. 从原始文件中删除国家级 → law_env.dta（覆盖）
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
drop if region_level == 1
quietly count
if r(N) != `n2' {
    di as err "记录数校验失败：应为 `n2' 条，实际 " r(N) " 条；未覆盖原文件。"
    log close
    exit
}
save "$root/law_env.dta", replace
di as res "law_env.dta 已更新：剩余 " r(N) " 条（其中国家级记录已移出）"

*-----------------------------------------------------------------------------
* 4. 复核
*-----------------------------------------------------------------------------
di as res _n "== law_env.dta（已剔除国家级） =="
tab region_level, m

use "$root/law_env_national.dta", clear
di as res _n "== law_env_national.dta =="
quietly count
di as txt "记录数：" r(N)
tab region_level, m
tab type, sort
quietly summarize publish_year
di as txt "公布年份：" r(min) " — " r(max)

log close
*=============================================================================
