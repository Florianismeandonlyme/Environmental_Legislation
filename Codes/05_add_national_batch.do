*=============================================================================
* 05_add_national_batch.do
* 目的：把 7 部被地方性法规高频援引、但不在国家级库中的法律法规补入
*       law_env_national.dta
*
*   法律（6）：
*     中华人民共和国民族区域自治法   npc.gov.cn
*     中华人民共和国城乡规划法       npc.gov.cn
*     中华人民共和国防洪法           mwr.gov.cn
*     中华人民共和国农业法           npc.gov.cn（2026 年第二次修订，2027-01-01 施行）
*     中华人民共和国长江保护法       mee.gov.cn
*     中华人民共和国黄河保护法       mee.gov.cn
*   行政法规（1）：
*     城市供水条例                   国务院令第158号（原文见福建省住建厅转载页）
*
* 字段填写说明：
*   publish 取文本括注中的最后一个日期（最近一次修订/修正通过日）；
*   env_level / env_topic 为人工归类：
*      长江保护法、黄河保护法 → 1 核心环保
*      城乡规划法 → 2 资源与生态 / 环境综合管理
*      防洪法、城市供水条例、农业法 → 2 资源与生态
*      民族区域自治法非环保专项法 → env_level 置缺失、env_topic 留空
*   source_id 记录原文网址，便于回溯
*
* 输入：law_env_national.dta、Codes/_laws_batch.csv
* 输出：law_env_national.dta、Logs/05_add_national_batch.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture mkdir "$root/Logs"
capture log close
log using "$root/Logs/05_add_national_batch.log", replace text

*-----------------------------------------------------------------------------
* 1. 读入待补入清单
*-----------------------------------------------------------------------------
confirm file "$root/Codes/_laws_batch.csv"
frame create laws
frame laws {
    import delimited "$root/Codes/_laws_batch.csv", clear varnames(1) ///
        stringcols(_all) bindquote(strict) maxquotedrows(3000) ///
        encoding("utf-8") case(preserve)
    gen long k1 = _n
    quietly count
    di as txt "待补入：" r(N) " 条"
}
frame laws: quietly count
local nadd = r(N)

*-----------------------------------------------------------------------------
* 2. 查重：任一标题已存在则整体不执行
*-----------------------------------------------------------------------------
use "$root/law_env_national.dta", clear
quietly count
local n0 = r(N)
local dup = 0
forvalues i = 1/`nadd' {
    frame laws: local t = title[`i']
    quietly count if title == "`t'"
    if r(N) > 0 {
        di as err "  已存在：`t'"
        local ++dup
    }
}
if `dup' > 0 {
    di as err _n "存在重复记录，未做任何修改。请先核对 Codes/_laws_batch.csv。"
    log close
    exit
}
di as txt "原有 `n0' 条，无重复，开始补入。"

*-----------------------------------------------------------------------------
* 3. 追加记录
*-----------------------------------------------------------------------------
quietly summarize id
local base = r(max)
gen long k1 = .
set obs `=`n0' + `nadd''
forvalues i = 1/`nadd' {
    local o = `n0' + `i'
    frame laws: local t  = title[`i']
    frame laws: local ty = type[`i']
    frame laws: local pd = publish[`i']
    frame laws: local el = env_level[`i']
    frame laws: local et = env_topic[`i']
    frame laws: local su = url[`i']

    replace id           = `base' + `i'        in `o'
    replace title        = "`t'"               in `o'
    replace category     = "`ty'"              in `o'
    replace type         = "`ty'"              in `o'
    replace status       = "有效"              in `o'
    replace publish      = cofd(date("`pd'","YMD"))  in `o'
    replace publish_year = year(date("`pd'","YMD"))  in `o'
    replace expiry       = ""                  in `o'
    replace file_path    = ""                  in `o'
    replace source_id    = "`su'"              in `o'
    if "`el'" != "." replace env_level = real("`el'") in `o'
    replace env_topic    = "`et'"              in `o'
    replace env_keywords = ""                  in `o'
    replace region_level = 1                   in `o'
    replace province_name = "全国"             in `o'
    replace province_code = .                  in `o'
    replace city_name    = ""                  in `o'
    replace city_code    = .                   in `o'
    replace county_name  = ""                  in `o'
    replace county_code  = .                   in `o'
    replace dup_count    = 1                   in `o'
    replace create_time  = "2026-11-05 23:05:00" in `o'
    replace k1           = `i'                 in `o'
}
format publish %tc

* 正文通过框架链接取过来（避免把上万字塞进宏）
frlink m:1 k1, frame(laws)
frget txt = content, from(laws)
replace content = txt if !missing(k1)
drop k1 txt
frame drop laws

*-----------------------------------------------------------------------------
* 4. 校验后保存
*-----------------------------------------------------------------------------
quietly count
if r(N) != `n0' + `nadd' {
    di as err "条数异常，未保存。"
    log close
    exit
}
quietly count if missing(content)
if r(N) > 0 {
    di as err "有 " r(N) " 条正文为空，未保存。"
    log close
    exit
}
local n1 = _N
save "$root/law_env_national.dta", replace
di as res "已保存：law_env_national.dta 现有 `n1' 条"

*-----------------------------------------------------------------------------
* 5. 复核
*-----------------------------------------------------------------------------
use "$root/law_env_national.dta", clear
quietly count
di as txt "总条数：" r(N)
gsort -publish_year
list id title type status publish env_level env_topic if id > `base', ///
    clean noobs
tab type, sort
tab env_level, m
log close
*=============================================================================
