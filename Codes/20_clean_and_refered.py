#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""20_clean_and_refered.py —— 清理错名记录 → 重算 refered → 重建引用边表

处理内容：
  1) 删除"同法异写"的占位记录（名称在全网查无、对应的正式名记录已有正文）：
     呼和浩特市大气污染防治管理条例 / 云南省风景名胜区管理条例 / 城市供水管理条例 /
     河北省城市市容和环境卫生管理条例 / 浙江省风景名胜区管理条例 / 黑龙江省草原管理条例 /
     中华人民共和国森林法实施细则
     删除后由 lawlib.NAME_FIX 把引用写法解析到正式名称。
  2) 用 lawlib 重算全部记录的 refered / n_ref / has_ref
  3) 输出 law_env.dta（保留变量标签、值标签、%tc 格式）与 law_refered.dta
"""
import os, sys
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import lawlib

ENV = os.path.join(ROOT, 'law_env.dta')
EDG = os.path.join(ROOT, 'law_refered.dta')

TO_DROP = [
    '呼和浩特市大气污染防治管理条例',
    '云南省风景名胜区管理条例',
    '城市供水管理条例',
    '河北省城市市容和环境卫生管理条例',
    '浙江省风景名胜区管理条例',
    '黑龙江省草原管理条例',
    '中华人民共和国森林法实施细则',
    '中华人民共和国防汛法',
    '渔业法细则',
]

df, meta = lawlib.read_dta(ENV)
print(f'读入 law_env：{len(df)} 条')

drop_mask = df['title'].isin(TO_DROP)
print(f'待删除的同法异写记录：{int(drop_mask.sum())} 条')
for t, n in df.loc[drop_mask, 'title'].value_counts().items():
    print(f'   - {t} × {n}')
df = df[~drop_mask].reset_index(drop=True)
print(f'删除后：{len(df)} 条')

# 国家级记录没有对应省级区划代码，0 不是合法代码，统一置缺失
nat_mask = (df['region_level'] == 1) & (df['province_code'].fillna(0) == 0)
print(f'国家级记录 province_code=0 → 缺失：{int(nat_mask.sum())} 条')
df.loc[nat_mask, 'province_code'] = pd.NA

print('重算 refered ...')
df = lawlib.add_refered_columns(df)
print(f'   有具名依据：{int(df.has_ref.sum())} 条；引用提及 {int(df.n_ref.sum())} 次')

lawlib.write_dta(df, ENV, meta=meta, formats={'publish': '%tc'})
print(f'已保存 {ENV}')

edges = lawlib.build_edges(df)
print(f'边表：{len(edges)} 条；未匹配 id {int(edges.refered_law_id.isna().sum())} 条')

LEVEL_LBL = {1: '国家级', 2: '省级', 3: '市级', 4: '县级'}
edges.to_stata(
    EDG, version=118, write_index=False,
    variable_labels={
        'raw_law': '引用方法规名称', 'raw_law_id': '引用方 id',
        'refered_law': '被引用的法律名称', 'refered_law_id': '被引法律 id（库中无则缺失）',
        'raw_year': '引用方公布年份', 'raw_level': '引用方行政层级',
        'raw_type': '引用方法规类型', 'raw_province': '引用方所属省份',
        'raw_province_code': '引用方省级区划代码', 'raw_city': '引用方地级行政区',
        'raw_env_level': '引用方环保程度(1核心环保 2资源生态 3能源气候)',
        'raw_env_topic': '引用方环保主题',
        'refered_year': '被引法律公布年份', 'refered_level': '被引法律行政层级',
        'refered_type': '被引法律类型', 'refered_province': '被引法律所属省份',
        'refered_province_code': '被引法律省级区划代码',
    },
    value_labels={'raw_level': LEVEL_LBL, 'refered_level': LEVEL_LBL},
    data_label='法规引用关系（含引用方/被引方属性）')
print(f'已保存 {EDG}')

# 一致性检查
names = set(edges.refered_law.astype(str))
titles = set(df.title.astype(str))
print(f'被引法名 {len(names)} 个，与 title 逐字一致 {len(names & titles)} 个')
if names - titles:
    print('   仍未对上：', sorted(names - titles)[:5])
