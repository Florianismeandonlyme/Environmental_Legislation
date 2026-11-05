*=============================================================================
* 04_add_national.do
* 目的：向 law_env_national.dta 补入《中华人民共和国水法》
*
* 来源：生态环境部「法律」栏目
*       https://www.mee.gov.cn/ywgz/fgbz/fl/201610/t20161008_365107.shtml
*       页面为现行有效文本（1988 年通过，2002 年修订，2009、2016 年两次修正），
*       正文已由 Codes/_shuifa.csv 保存（提取时间 2026-11-05）
*
* 字段填写说明：
*   type=法律、status=有效、region_level=1、province_name=全国
*   publish=2016-07-02（最近一次修正通过日）；publish_year=2016
*   env_level=2（资源与生态保护）、env_topic=水污染与水资源
*   source_id 记录来源网址，便于回溯
*   province_code、city_*、county_* 置为缺失（国家级记录无对应行政区划）
*
* 输入：law_env_national.dta、Codes/_shuifa.csv
* 输出：law_env_national.dta（新增 1 条）、Logs/04_add_national.log
*=============================================================================

version 17
clear all
set more off
global root "/Users/florian/Desktop/博士研究计划"
capture mkdir "$root/Logs"
capture log close
log using "$root/Logs/04_add_national.log", replace text

*-----------------------------------------------------------------------------
* 1. 查重：已有《中华人民共和国水法》则不做任何修改
*-----------------------------------------------------------------------------
use "$root/law_env_national.dta", clear
quietly count
local n0 = r(N)
quietly count if title == "中华人民共和国水法"
if r(N) > 0 {
    di as err _n "law_env_national.dta 中已存在《中华人民共和国水法》，未做修改。"
    log close
    exit
}
quietly summarize id
local newid = r(max) + 1
di as txt "原有 " `n0' " 条；新记录 id = " `newid'

*-----------------------------------------------------------------------------
* 2. 读入正文（单独存放在一个 frame 里，避免与主数据冲突）
*-----------------------------------------------------------------------------
confirm file "$root/Codes/_shuifa.csv"
frame create sftxt
frame sftxt {
    import delimited "$root/Codes/_shuifa.csv", clear varnames(1) ///
        stringcols(1) bindquote(strict) maxquotedrows(1000) encoding("utf-8") case(preserve)
    gen byte k1 = 1
    quietly count
    di as txt "正文行数：" r(N)
}
frame sftxt: local nchars = length(content[1])
di as txt "正文字符数：" `nchars'

*-----------------------------------------------------------------------------
* 3. 追加一条记录
*-----------------------------------------------------------------------------
use "$root/law_env_national.dta", clear
set obs `=`n0' + 1'
local new = _N

replace id     = `newid'                          in `new'
replace title  = "中华人民共和国水法"              in `new'
replace category = "法律"                          in `new'
replace type   = "法律"                            in `new'
replace status = "有效"                            in `new'
replace publish = cofd(mdy(7, 2, 2016))             in `new'
replace publish_year = 2016                        in `new'
replace expiry = ""                                in `new'
replace file_path = ""                             in `new'
replace source_id = "https://www.mee.gov.cn/ywgz/fgbz/fl/201610/t20161008_365107.shtml" in `new'
replace env_level = 2                              in `new'
replace env_topic = "水污染与水资源"               in `new'
replace env_keywords = ""                          in `new'
replace region_level = 1                           in `new'
replace province_name = "全国"                     in `new'
replace province_code = .                          in `new'
replace city_name = ""                             in `new'
replace city_code = .                              in `new'
replace county_name = ""                           in `new'
replace county_code = .                            in `new'
replace dup_count = 1                              in `new'
replace create_time = "2026-11-05 22:35:00"        in `new'
format publish %tc

* 正文：从 sftxt 框架取过来（内容约 1 万字，用 frlink/frget 避免宏长度限制）
gen byte k1 = 1
frlink m:1 k1, frame(sftxt)
frget txt = content, from(sftxt)
replace content = txt in `new'
drop k1 txt
frame drop sftxt

*-----------------------------------------------------------------------------
* 4. 校验并保存
*-----------------------------------------------------------------------------
quietly count
if r(N) != `n0' + 1 {
    di as err "条数异常，未保存。"
    log close
    exit
}
local n1 = _N
quietly count if missing(content) & id == `newid'
if r(N) > 0 {
    di as err "正文未成功写入，未保存。"
    log close
    exit
}
label data ""
save "$root/law_env_national.dta", replace
di as res "已保存：law_env_national.dta 现有 `n1' 条"

*-----------------------------------------------------------------------------
* 5. 复核
*-----------------------------------------------------------------------------
use "$root/law_env_national.dta", clear
quietly count
di as txt "总条数：" r(N)
list id title type status publish publish_year env_level env_topic in L, clean noobs
di as txt _n "正文首段：" 
di as txt substr(content[`=_N'], 1, 120)
di as txt _n "正文末段："
local L = length(content[_N])
di as txt substr(content[_N], max(1, `L'-60), 80)

tab type, sort
log close
*=============================================================================
