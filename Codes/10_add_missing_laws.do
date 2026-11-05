*=============================================================================
* 10_add_missing_laws.do
* 目的：把 law_refered 中未匹配到 id 的法律补入 law_env.dta
*
* 来源：Codes/10_build_missing_csv.py 整理的网络抓取结果
*   · 抓到原文的：写入 content，source_id 记原文网址
*   · 未抓到的：仍建记录（content 为空，source_id="未获取原文"），
*     使引用关系能落到唯一 id，后续补原文后重跑即可
*
* 字段处理：
*   type / region_level / province_name 由法名规则推断（见 10_build_missing_csv.py）
*   status 统一记为"未知"（无法逐一核实效力）
*   env_level 留空（不臆断环保归类）
*   publish 取自正文括注中的最晚日期，取不到则留空
*
* 输入：law_env.dta、Codes/_missing_laws.csv
* 输出：law_env.dta、Logs/10_add_missing_laws.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture log close
log using "$root/Logs/10_add_missing_laws.log", replace text

*-----------------------------------------------------------------------------
* 1. 读入待补入清单
*-----------------------------------------------------------------------------
confirm file "$root/Codes/_missing_laws.csv"
frame create miss
frame miss {
    import delimited "$root/Codes/_missing_laws.csv", clear varnames(1) ///
        stringcols(_all) bindquote(strict) maxquotedrows(3000) ///
        encoding("utf-8") case(preserve)
    gen long k1 = _n
    quietly count
    di as txt "待补入记录：" r(N) " 条"
}
frame miss: quietly count
local nadd = r(N)

*-----------------------------------------------------------------------------
* 2. 省级名称 → 区划代码（沿用库内已有对照）
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear
quietly levelsof province_code, local(codes)
tempfile provmap
preserve
    keep province_name province_code
    drop if province_name == "" | missing(province_code)
    bysort province_name (province_code): keep if _n == 1
    save `provmap'
restore

*-----------------------------------------------------------------------------
* 3. 查重与追加
*-----------------------------------------------------------------------------
quietly count
local n0 = r(N)
local dup = 0
forvalues i = 1/`nadd' {
    frame miss: local t = title[`i']
    quietly count if title == "`t'"
    if r(N) > 0 {
        di as txt "  已存在，跳过：`t'"
        local ++dup
    }
}
di as txt "原有 `n0' 条；与库内重复 `dup' 条"

quietly summarize id
local base = r(max)
gen long k1 = .
set obs `=`n0' + `nadd''

forvalues i = 1/`nadd' {
    local o = `n0' + `i'
    frame miss: local t  = title[`i']
    frame miss: local ty = type[`i']
    frame miss: local ca = category[`i']
    frame miss: local st = status[`i']
    frame miss: local pd = publish[`i']
    frame miss: local rl = region_level[`i']
    frame miss: local pn = province_name[`i']
    frame miss: local su = source_id[`i']

    replace id           = `base' + `i'   in `o'
    replace title        = "`t'"          in `o'
    replace type         = "`ty'"         in `o'
    replace category     = "`ca'"         in `o'
    replace status       = "`st'"         in `o'
    if "`pd'" != "" {
        replace publish      = cofd(date("`pd'","YMD")) in `o'
        replace publish_year = year(date("`pd'","YMD")) in `o'
    }
    replace expiry       = ""             in `o'
    replace file_path    = ""             in `o'
    replace source_id    = "`su'"         in `o'
    replace env_topic    = ""             in `o'
    replace env_keywords = ""             in `o'
    replace region_level = `rl'           in `o'
    replace province_name = "`pn'"        in `o'
    replace city_name    = ""             in `o'
    replace city_code    = .              in `o'
    replace county_name  = ""             in `o'
    replace county_code  = .              in `o'
    replace dup_count    = 1              in `o'
    replace create_time  = "2026-11-05 23:55:00" in `o'
    replace k1           = `i'            in `o'
}
format publish %tc

* 正文
frlink m:1 k1, frame(miss)
frget txt = content, from(miss)
replace content = txt if !missing(k1)
drop k1 txt miss
frame drop miss

* 省级代码：逐省赋值（不用 merge，避免行数意外变化）
levelsof province_name if province_name != "", local(pns) clean
foreach p of local pns {
    quietly summarize province_code if province_name == "`p'" & !missing(province_code), meanonly
    if r(N) > 0 {
        replace province_code = r(mean) if province_name == "`p'"
    }
}
quietly count
di as txt "赋值后条数：" r(N)

*-----------------------------------------------------------------------------
* 4. 校验后保存
*-----------------------------------------------------------------------------
quietly count
if r(N) != `n0' + `nadd' {
    di as err "条数异常，未保存。"
    log close
    exit
}
duplicates report id
quietly duplicates report id
if r(unique_value) != r(N) {
    di as err "id 不唯一，未保存。"
    log close
    exit
}
local n1 = _N
save "$root/law_env.dta", replace
di as res "已保存：law_env.dta 共 `n1' 条（新增 `nadd'）"

*-----------------------------------------------------------------------------
* 5. 复核
*-----------------------------------------------------------------------------
quietly count
di as txt "总条数：" r(N)
tab region_level, m
tab type, sort
quietly count if content == ""
di as txt "其中的空壳记录（暂无原文）：" r(N) " 条"
log close
*=============================================================================
