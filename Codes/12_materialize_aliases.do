*=============================================================================
* 12_materialize_aliases.do
* 目的：把此前用"别名"处理的 5 个引用写法，落成 law_env 中的独立记录，
*       使库内名称与 refered 中的写法完全一致，不再依赖别名表
*
*   中华人民共和国城市供水条例   → 复制《城市供水条例》正文
*   中华人民共和国基本农田保护条例 → 复制《基本农田保护条例》正文
*   中华民族共和国森林法         → 复制《中华人民共和国森林法》正文
*   中国人民共和国森林法         → 复制《中华人民共和国森林法》正文
*   中国人民共和国水污染防治法   → 复制《中华人民共和国水污染防治法》正文
*
* 说明：这些是同一部法在地方立法文本中的不同写法（错字、多前缀）。
*       按要求不再做映射，而是各建一条记录，正文与原文一致，
*       source_id 标注来源记录，便于核对。
*
* 输入：law_env.dta
* 输出：law_env.dta（+5 条）、Logs/12_materialize_aliases.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/12_materialize_aliases.log", replace text

use "$root/law_env.dta", clear
quietly count
local n0 = r(N)
gen long _row = _n
quietly summarize id
local nextid = r(max) + 1

local pairs "中华人民共和国城市供水条例=城市供水条例 中华人民共和国基本农田保护条例=基本农田保护条例 中华民族共和国森林法=中华人民共和国森林法 中国人民共和国森林法=中华人民共和国森林法 中国人民共和国水污染防治法=中华人民共和国水污染防治法"

local added = 0
foreach p of local pairs {
    local alias = substr("`p'", 1, strpos("`p'","=")-1)
    local canon = substr("`p'", strpos("`p'","=")+1, .)

    quietly count if title == "`alias'"
    if r(N) > 0 {
        di as txt "  已存在，跳过：`alias'"
        continue
    }
    quietly count if title == "`canon'"
    if r(N) == 0 {
        di as err "  未找到母本，跳过：`canon'"
        continue
    }

    quietly levelsof _row if title == "`canon'", local(crow)
    quietly count
    local new = r(N) + 1
    set obs `new'

    foreach v of varlist _all {
        capture confirm numeric variable `v'
        if _rc == 0 {
            quietly replace `v' = `v'[`crow'] in `new'
        }
        else {
            quietly replace `v' = `v'[`crow'] in `new'
        }
    }
    quietly replace id       = `nextid'          in `new'
    quietly replace title    = "`alias'"         in `new'
    quietly replace source_id = source_id[`crow'] + "｜按引用写法单列" in `new'
    quietly replace create_time = "2026-11-06 00:05:00" in `new'
    quietly replace _row     = `new'             in `new'
    local ++nextid
    local ++added
    di as txt "  + `alias'（母本 id " id[`new'] "）"
}

drop _row
quietly count
di as txt _n "新增 " `added' " 条；现共 " r(N) " 条"
duplicates report id
quietly duplicates report id
if r(unique_value) != r(N) {
    di as err "id 不唯一，未保存。"
    log close
    exit
}
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta"

list id title source_id if id > `nextid' - `added' - 1, clean noobs
log close
*=============================================================================
