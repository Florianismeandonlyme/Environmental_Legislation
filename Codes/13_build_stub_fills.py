#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""13_build_stub_fills.py —— 为仍缺正文的既有记录生成"补正文"清单

从 _missing_laws.json 中取已抓到原文的条目，筛出：
  · 该法名在 law_env 中已有记录（空壳）
  · 该记录 content 仍为空
输出 Codes/_stub_fills.csv（title, url, publish, content）
"""
import json, os, re
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

def pub_of(paras):
    txt = '\n'.join(paras[:3]) if paras else ''
    ds = re.findall(r'(\d{4})年(\d{1,2})月(\d{1,2})日', txt)
    if not ds: return ''
    y, m, d = max(ds, key=lambda x: (int(x[0]), int(x[1]), int(x[2])))
    return f'{y}-{int(m):02d}-{int(d):02d}'

d = json.load(open(os.path.join(HERE, '_missing_laws.json')))
env = pd.read_stata(os.path.join(ROOT, 'law_env.dta'), columns=['id', 'title', 'content'])
empty = set(env.loc[env.content.fillna('') == '', 'title'].astype(str))

rows = []
for name, v in d.items():
    if 'url' not in v: continue
    if name not in empty: continue
    rows.append({'title': name, 'url': v['url'], 'publish': pub_of(v['paras']),
                 'content': '\n'.join(v['paras'])})
df = pd.DataFrame(rows)
df.to_csv(os.path.join(HERE, '_stub_fills.csv'), index=False, encoding='utf-8')
print(f'可补正文的空壳记录：{len(df)} 条')
print(f'（law_env 中仍为空壳的记录共 {len(empty)} 条）')
