*=============================================================================
* 01_Map.do
* 目的：绘制「各省环境立法数量」地图（分省填色图 / choropleth map）
* 思路：参考 连享会 No.1401《Stata 绘图：用 geoplot 绘制中国地图》
*       (https://www.lianxh.cn/details/1401.html)
*       1) spshape2dta 把 shapefile 转成两个 dta（属性文件 + 坐标文件）
*       2) geoframe + geoplot 叠加图层绘图（主图，见第 4 节）
*       3) grmap 作为备选方案（见第 5 节，用法同推文 1.3 节）
*
* 输入：law_env.dta                       （环境立法原始数据库，逐条法规）
*       Maps/province.shp                 （省级边界，见下方“地图数据说明”）
* 输出：Figures/fig1_nlaw_province.png     （主图：分省填色图，geoplot）
*       Figures/fig1_nlaw_province_grmap.png（备选图：grmap）
*       Figures/tab_nlaw_province.csv     （分省计数明细）
* 说明：分地区的增量/存量折线图已独立为 Codes/02_LineChart.do
*       Logs/01_Map.log                   （运行日志）
*
* 地图数据说明：
*   Maps/map.shp 是地级市/区县级边界（直辖市为市辖区），不能直接画省级图。
*   已按其 6 位行政区划代码（adcode）聚合（dissolve）为 34 个省级单元，
*   另存为 Maps/province.shp（字段：adcode 省级代码、name 省名、ncity 单元数）。
*   聚合规则：prov_adcode = floor(adcode/10000)*10000，同一省级代码的多边形合并。
*   这样做的好处是：下面完全用“数字代码”匹配，不依赖 dbf 里的中文字符编码。
*
* 作者：<你的名字>          最后更新：2026-11-05
*=============================================================================

version 17
clear all
set more off
set linesize 120

*-----------------------------------------------------------------------------
* 0. 路径与开关
*-----------------------------------------------------------------------------
* 建议：把本 do 文件放在项目根目录，运行前 cd 到该目录；
*       若用 Stata 的 “Do-file Editor” 直接点击运行，可用下面第一种写法。
* global root "`c(pwd)'"
global root "/Users/florian/Desktop/博士研究计划"   // 需要时改为绝对路径

capture mkdir "$root/Logs"
capture mkdir "$root/Figures"
capture log close
log using "$root/Logs/01_Map.log", replace text

* --- 统计口径开关（按需修改）--------------------------------------------
* 立法层级：2 = 省级立法（地方性法规 + 省级政府规章）
*           若想统计“该省辖区内各级立法”，改成 2/3/4 的组合，见第 2 节注释
local lvl       = 2          // 主要口径：省级立法
local drop_amend = 1         // 1 = 剔除“修改、废止的决定”，只保留新立法规
local envcore    = 0         // 1 = 只保留 env_level==1（核心环保），0 = 全部
local palette   "Blues"      // 配色：Blues / Greens / Reds / Oranges ...
local ncl       = 5          // 分档数（quantile 分位）
local showlab    = 0         // 1 = 在地图上标注数值（东部小省会重叠，默认关闭）

*-----------------------------------------------------------------------------
* 1. 安装/检查所需命令（首次运行时联网安装一次即可）
*    geoplot 依赖 palettes、colrspace、moremata；grmap 随 Stata 自带
*-----------------------------------------------------------------------------
/*
foreach p in geoplot palettes colrspace moremata {
    capture which `p'
    if _rc ssc install `p', replace
}
*/
*-----------------------------------------------------------------------------
* 2. 由 Shapefile 生成绘图用的 dta
*    spshape2dta 是 Stata 自带命令，会生成两个文件：
*      province.dta      —— 属性数据（adcode name ncity _ID _CX _CY）
*      province_shp.dta  —— 坐标数据（_ID _X _Y）
*-----------------------------------------------------------------------------
confirm file "$root/Maps/province.shp"
cd "$root/Maps"
spshape2dta province, replace
cd "$root"

*-----------------------------------------------------------------------------
* 3. 构造“分省环境立法数量”
*-----------------------------------------------------------------------------
use "$root/law_env.dta", clear

* 3.1 只保留目标行政层级
keep if region_level == `lvl'
* 【备选口径】若要把该省省以下（市、县）立法也算进来，把上面一行换成：
*   keep if inlist(region_level, 2, 3, 4)

* 3.2 可选：剔除“修改、废止的决定”，避免同一部法规被重复计数
if `drop_amend' == 1 {
    drop if strpos(type, "修改") | strpos(type, "废止")
}
* 3.3 可选：只保留核心环保（env_level==1）
if `envcore' == 1 {
    keep if env_level == 1
}

* 3.4 记录样本量
quietly count
di as txt "纳入统计的法规共 " r(N) " 条"

* 3.5 按省级行政区划代码汇总（province_code 为 6 位代码，如 110000）
collapse (count) nlaw = region_level, by(province_code)
rename province_code adcode
label variable nlaw "环境立法数量"
tempfile cnt
save `cnt'

* 3.6 记录时间跨度，用于图标题
use "$root/law_env.dta", clear
keep if region_level == `lvl'
quietly summarize publish_year
local y0 : display %4.0f r(min)
local y1 : display %4.0f r(max)
di as txt "样本年份跨度：`y0' — `y1'"

*-----------------------------------------------------------------------------
* 4. 主图：geoframe + geoplot
*-----------------------------------------------------------------------------
* 4.1 把属性文件声明为“地理框架”（geoframe 会自动在同一文件夹中
*     找到 province_shp.dta 作为配套的坐标/形状框架）
geoframe create prov using "$root/Maps/province.dta", replace

* 4.2 在框架内合并计数（geoframe create 后当前框架即为 prov）
frame prov {
    merge 1:1 adcode using `cnt', nogen keep(master match)
    label variable nlaw "环境立法数量"
}

* 4.3 绘图：三个图层 —— 填色区（area）、省界（line）、可选数值标注（label）
local lab_layer ""
if `showlab' == 1 {
    local lab_layer `"(label prov nlaw, color(black) size(vsmall))"'
}

geoplot ///
    (area prov nlaw, ///
        color(`palette') ///
        level(`ncl', quantile weight(nlaw)) ///
        missing(color(gs13))) ///
    (line prov, lwidth(vthin) lcolor(white)) ///
    `lab_layer' ///
    , ///
    title("省级环境立法数量（`y0'—`y1'）") ///
    subtitle("按 6 位省级行政区划代码汇总；灰色为无数据的港澳台地区") ///
    note("数据来源：law_env.dta；图形：Stata geoplot（连享会 No.1401）", size(vsmall)) ///
    legend(position(6) rows(1) size(small)) ///
    graphregion(color(white)) ///
    xsize(8) ysize(6.2)
/*
graph export "$root/Figures/fig1_nlaw_province.png", as(png) ///
    width(4000) replace
graph export "$root/Figures/fig1_nlaw_province.pdf", as(pdf) replace
graph drop _all
*/
*-----------------------------------------------------------------------------
* 5. 备选方案：grmap（推文 1.3 节的写法）
*    注意：grmap 用的是属性文件 province.dta 与坐标文件 province_shp.dta
*-----------------------------------------------------------------------------
use "$root/Maps/province.dta", clear
merge 1:1 adcode using `cnt', nogen keep(master match)

grmap, activate
grmap nlaw using "$root/Maps/province_shp.dta", id(_ID) ///
    fcolor(`palette') ///
    clmethod(quantile) clnumber(`ncl') ///
    ndfcolor(gs13) ///
    ocolor(white) osize(vthin) ///
    title("省级环境立法数量（`y0'—`y1'）") ///
    subtitle("灰色为无数据的港澳台地区") ///
    legend(size(small)) ///
    graphregion(color(white)) ///
    xsize(8) ysize(6.2)
/*
graph export "$root/Figures/fig1_nlaw_province_grmap.png", as(png) ///
    width(4000) replace
graph drop _all
*/
*-----------------------------------------------------------------------------
* 6. 导出分省计数明细（写作时核对数字、做正文表格用）
*-----------------------------------------------------------------------------
rename nlaw nlaw_prov_level
label variable adcode "省级行政区划代码(6位)"
label variable nlaw_prov_level "省级环境立法数量"
gsort -nlaw_prov_level
list adcode name nlaw_prov_level if !missing(nlaw_prov_level), clean noobs

export delimited adcode name nlaw_prov_level ///
    using "$root/Figures/tab_nlaw_province.csv", replace

summarize nlaw_prov_level, detail

di as res _n "全部完成：图形见 Figures/，明细见 Figures/tab_nlaw_province.csv"
log close
*=============================================================================
