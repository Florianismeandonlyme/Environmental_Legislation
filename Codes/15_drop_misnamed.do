*=============================================================================
* 15_drop_misnamed.do
* 目的：删除先前为"引用中的错名/多前缀写法"建立的 8 条记录
*
* 这些记录不是真实法律：其名称与正式名称不符（错字、多写"中华人民共和国"），
* 正文或为空壳、或复制自同一部法。保留它们会：
*   1) 违反"库内名称必须与正式名称一致"的要求；
*   2) 使 03 抽取脚本的"去多余前缀"规则失效（库里已有同名记录就不再改写）。
*
* 删除后，引用写法由 03 脚本统一更正为正式名称，指向真实记录。
*
* 输入/输出：law_env.dta
*=============================================================================
version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/15_drop_misnamed.log", replace text

use "$root/law_env.dta", clear
quietly count
local n0 = r(N)

local bad "中华人民共和国野生植物保护法 中华民族共和国民族区域自治法 中华民族共和国野生植物保护条例 中华民族共和国森林法 中国人民共和国森林法 中国人民共和国水污染防治法 中华人民共和国城市供水条例 中华人民共和国基本农田保护条例"

local dropped = 0
foreach t of local bad {
    quietly count if title == "`t'"
    if r(N) == 1 {
        quietly drop if title == "`t'"
        local ++dropped
        di as txt "  已删除：`t'"
    }
    else if r(N) > 1 {
        di as err "  同名多条，跳过待查：`t'"
    }
    else di as txt "  不存在：`t'"
}
quietly count
di as txt _n "删除 `dropped' 条；`n0' → " r(N) " 条"
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta"
log close
*=============================================================================
