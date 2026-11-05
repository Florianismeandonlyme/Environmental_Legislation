*=============================================================================
* 02_LineChart.do
* 目的：分地区（东部 / 中部 / 西部）绘制省级环境立法的「增量」与「存量」
*
*   增量 inc  ：当年新公布的法规件数（flow）
*   存量 stock：截至当年累计公布的法规件数（stock），由逐年增量累加得到
*               —— 即「累计制定量」，不扣减已废止/已修改的法规。
*               数据中的 expiry 字段不能当作废止日期使用（1,073 条"有效"法规
*               中有 850 条也带 expiry），因此无法可靠构造"净存量"。
*
* 口径：与 01_Map.do 完全一致 —— region_level==2（省级立法），
*       剔除"修改、废止的决定"（避免同一部法规重复计数）
*
* 输入：law_env.dta
* 输出：Figures/fig2a_east.png / .pdf      东部（左：增量，右：存量）
*       Figures/fig2b_central.png / .pdf   中部
*       Figures/fig2c_west.png / .pdf      西部
*       Figures/fig2d_all.png / .pdf       三地区对比（左：增量，右：存量）
*       Figures/tab_nlaw_region_year.csv   年份 × 地区 增量/存量明细
*       Logs/02_LineChart.log
*
* 运行：在项目根目录执行  do Codes/02_LineChart.do
*=============================================================================

version 17
clear all
set more off
set linesize 120
set scheme s2color          // 统一模板：左/下两条轴线（半包围）+ 浅灰虚线网格

*-----------------------------------------------------------------------------
* 0. 路径与开关
*-----------------------------------------------------------------------------
global root "/Users/florian/Desktop/博士研究计划"
capture mkdir "$root/Logs"
capture mkdir "$root/Figures"
capture log close
log using "$root/Logs/02_LineChart.log", replace text

local lvl        = 2          // 2 = 省级立法
local drop_amend = 1          // 1 = 剔除"修改、废止的决定"
local envcore    = 0          // 1 = 只保留 env_level==1（核心环保）
local y0         = 2010       // 作图窗口起点（存量仍从最早年份起累计）
local y1         = 2024       // 2025 年数据不完整（仅 4 件），不纳入

*-----------------------------------------------------------------------------
* 1. 构造 "年份 × 地区" 的增量与存量
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear

* 1.1 与地图一致的口径
keep if region_level == `lvl'
if `drop_amend' == 1  drop if strpos(type,"修改") | strpos(type,"废止")
if `envcore'    == 1  keep if env_level == 1

* 1.2 国家统计局"三大地带"划分（31 个省级单位，不含港澳台）
gen prov2 = floor(province_code/10000)
gen byte region = .
replace region = 1 if inlist(prov2,11,12,13,21,31,32,33,35,37,44,46)      // 东部(11)
replace region = 2 if inlist(prov2,14,22,23,34,36,41,42,43)                // 中部(8)
replace region = 3 if inlist(prov2,15,45,50,51,52,53,54,61,62,63,64,65)    // 西部(12)
assert !missing(region)     // 有未归类省份时在此报错

quietly count
di as txt "纳入统计的法规共 " r(N) " 条"
quietly count if missing(publish_year)
di as txt "其中缺失公布年份、无法进入时间序列的 " r(N) " 条"
drop if missing(publish_year)

* 1.3 计数 → 补零 → 转宽 → 累计
gen byte one = 1
collapse (sum) inc = one, by(publish_year region)
fillin publish_year region
replace inc = 0 if missing(inc)
drop _fillin
reshape wide inc, i(publish_year) j(region)
rename inc1 inc_east
rename inc2 inc_central
rename inc3 inc_west
sort publish_year
gen stock_east    = sum(inc_east)       // 存量：从数据最早年份(1988)起累计
gen stock_central = sum(inc_central)
gen stock_west    = sum(inc_west)

label variable publish_year   "公布年份"
label variable inc_east       "东部：当年增量"
label variable inc_central    "中部：当年增量"
label variable inc_west       "西部：当年增量"
label variable stock_east     "东部：累计存量"
label variable stock_central  "中部：累计存量"
label variable stock_west     "西部：累计存量"

* 1.4 只保留作图窗口（存量已含窗口之前的历史积累，故数值不是从 0 起）
keep if inrange(publish_year, `y0', `y1')

*-----------------------------------------------------------------------------
* 2. 导出明细
*-----------------------------------------------------------------------------
export delimited publish_year ///
    inc_east inc_central inc_west ///
    stock_east stock_central stock_west ///
    using "$root/Figures/tab_nlaw_region_year.csv", replace

list, clean noobs sep(0)

*-----------------------------------------------------------------------------
* 3. 分地区作图：每个地区一张图，左「增量」右「存量」
*-----------------------------------------------------------------------------
local regs "east central west"
local cn   "东部 中部 西部"
local cols "navy maroon dkgreen"
local tags "a b c"

local note_inc   "增量：当年新公布的省级环境法规件数"
local note_stock "存量：自 1988 年起累计公布件数（不扣减废止、修改）"

forvalues k = 1/3 {
    local r  : word `k' of `regs'
    local nm : word `k' of `cn'
    local cl : word `k' of `cols'
    local tg : word `k' of `tags'
    if `k' == 1  local npr = 11
    if `k' == 2  local npr = 8
    if `k' == 3  local npr = 12

    * 左面板：增量
    twoway (connected inc_`r' publish_year, ///
                lcolor(`cl') lwidth(medthick) msymbol(O) msize(small) mcolor(`cl')) ///
        , name(gi, replace) ///
        title("当年增量") subtitle("`note_inc'") ///
        ytitle("") ylabel(#5, angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
        xtitle("") xlabel(`y0'(2)`y1', angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
        graphregion(color(white))

    * 右面板：存量
    twoway (connected stock_`r' publish_year, ///
                lcolor(`cl') lwidth(medthick) msymbol(O) msize(small) mcolor(`cl')) ///
        , name(gs, replace) ///
        title("累计存量") subtitle("`note_stock'") ///
        ytitle("") ylabel(#5, angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
        xtitle("") xlabel(`y0'(2)`y1', angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
        graphregion(color(white))

    graph combine gi gs, cols(2) ///
        title("`nm'地区环境立法的增量与存量（`y0'—`y1'）") ///
        subtitle("省级立法，已剔除“修改、废止的决定”（单位：件）") ///
        note("注：2025 年数据不完整未纳入；`nm'含 `npr' 个省级单位；" ///
             "数据来源：law_env.dta", size(vsmall)) ///
        graphregion(color(white)) xsize(10) ysize(4.4)

    graph export "$root/Figures/fig2`tg'_`r'.png", as(png) width(4000) replace
    graph export "$root/Figures/fig2`tg'_`r'.pdf", as(pdf) replace
    graph drop _all
}

*-----------------------------------------------------------------------------
* 4. 三地区对比图：左「增量」三条线，右「存量」三条线
*-----------------------------------------------------------------------------
twoway ///
    (connected inc_east    publish_year, lcolor(navy)    lwidth(medthick) msymbol(O) msize(small) mcolor(navy)) ///
    (connected inc_central publish_year, lcolor(maroon)  lwidth(medthick) msymbol(O) msize(small) mcolor(maroon)) ///
    (connected inc_west    publish_year, lcolor(dkgreen) lwidth(medthick) msymbol(O) msize(small) mcolor(dkgreen)) ///
    , name(gainc, replace) ///
    title("当年增量") ///
    ytitle("") ylabel(#5, angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
    xtitle("公布年份") xlabel(`y0'(2)`y1', angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
    legend(order(1 "东部" 2 "中部" 3 "西部") position(6) rows(1) size(small) ///
           region(lcolor(none) fcolor(none))) ///
    graphregion(color(white))

twoway ///
    (connected stock_east    publish_year, lcolor(navy)    lwidth(medthick) msymbol(O) msize(small) mcolor(navy)) ///
    (connected stock_central publish_year, lcolor(maroon)  lwidth(medthick) msymbol(O) msize(small) mcolor(maroon)) ///
    (connected stock_west    publish_year, lcolor(dkgreen) lwidth(medthick) msymbol(O) msize(small) mcolor(dkgreen)) ///
    , name(gastk, replace) ///
    title("累计存量") ///
    ytitle("") ylabel(#5, angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
    xtitle("公布年份") xlabel(`y0'(2)`y1', angle(0) grid glcolor(gs14) glwidth(vthin) glpattern(dash)) ///
    legend(order(1 "东部" 2 "中部" 3 "西部") position(6) rows(1) size(small) ///
           region(lcolor(none) fcolor(none))) ///
    graphregion(color(white))

graph combine gainc gastk, cols(2) ///
    title("三大地区环境立法的增量与存量（`y0'—`y1'）") ///
    subtitle("省级立法，已剔除“修改、废止的决定”（单位：件）") ///
    note("注：存量自 1988 年起累计，不扣减已废止/已修改法规；2025 年数据不完整未纳入", ///
         size(vsmall)) ///
    graphregion(color(white)) xsize(10) ysize(4.6)

graph export "$root/Figures/fig2d_all.png", as(png) width(4000) replace
graph export "$root/Figures/fig2d_all.pdf", as(pdf) replace
graph drop _all

*-----------------------------------------------------------------------------
* 5. 关键数字
*-----------------------------------------------------------------------------
di as res _n "== 窗口末年（`y1'）各地区增量与存量 =="
list publish_year inc_east inc_central inc_west stock_east stock_central stock_west ///
    if publish_year == `y1', clean noobs

local rn "东部 中部 西部"
local kk = 0
foreach r in east central west {
    local ++kk
    local nm : word `kk' of `rn'
    quietly summarize inc_`r', meanonly
    local peak = r(max)
    quietly summarize publish_year if inc_`r' == `peak'
    local yr = r(min)
    di as txt "`nm'：增量峰值 `peak' 件，出现在 `yr' 年"
}

di as res _n "全部完成：分地区图见 Figures/fig2a_east、fig2b_central、fig2c_west，对比图见 fig2d_all"
log close
*=============================================================================
