#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""10_build_missing_csv.py —— 把 08/09 抓取结果整理成待补入记录表

输出 Codes/_missing_laws.csv，字段与 law_env 的 23 个变量对应：
  title, type, category, status, publish, region_level, province_name, source_id, content
未被抓到的法名也生成一条记录（content 为空、source_id 标注），
以保证 law_refered 里每条引用都能落到唯一 id。
"""
import json, os, re
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(HERE, '_missing_laws.csv')

PROV = ['北京市','天津市','河北省','山西省','内蒙古自治区','辽宁省','吉林省','黑龙江省',
        '上海市','江苏省','浙江省','安徽省','福建省','江西省','山东省','河南省','湖北省',
        '湖南省','广东省','广西壮族自治区','海南省','重庆市','四川省','贵州省','云南省',
        '西藏自治区','陕西省','甘肃省','青海省','宁夏回族自治区','新疆维吾尔自治区']

def infer(name):
    t = str(name)
    if t.startswith('中华人民共和国') and (t.endswith('法') or t.endswith('法典')):
        typ, lvl = '法律', 1
    elif any(t.startswith(p) or p in t[:6] for p in PROV) or t.startswith(('内蒙古','广西','西藏','宁夏','新疆')):
        typ, lvl = '地方性法规', 2
    elif re.search(r'自治州|市', t):
        typ, lvl = '地方性法规', 3
    elif re.search(r'自治县|县|旗', t):
        typ, lvl = '地方性法规', 4
    else:
        typ, lvl = '行政法规', 1
    return typ, lvl

def prov_of(name):
    for p in PROV:
        if name.startswith(p): return p
        short = {'内蒙古自治区':'内蒙古','广西壮族自治区':'广西','西藏自治区':'西藏',
                 '宁夏回族自治区':'宁夏','新疆维吾尔自治区':'新疆'}[p] if p in \
                ('内蒙古自治区','广西壮族自治区','西藏自治区','宁夏回族自治区','新疆维吾尔自治区') else p[:-1]
        if name.startswith(short): return p
    return ''

def pub_of(paras):
    txt = '\n'.join(paras[:3]) if paras else ''
    ds = re.findall(r'(\d{4})年(\d{1,2})月(\d{1,2})日', txt)
    if not ds: return ''
    y, m, d = max(ds, key=lambda x: (int(x[0]), int(x[1]), int(x[2])))
    return f'{y}-{int(m):02d}-{int(d):02d}'

ALIAS = set(pd.read_csv(os.path.join(HERE, '_law_aliases.csv'))['ntitle'].astype(str)) \
    if os.path.exists(os.path.join(HERE, '_law_aliases.csv')) else set()

def _norm(s):
    s = str(s or '')
    for ch in '《》＜＞<>': s = s.replace(ch, '')
    import re as _re
    s = _re.sub(r'\s+', '', s)
    return _re.sub(r'[（(][^）)]*[）)]$', '', s)

existing = set(pd.read_stata(os.path.join(ROOT, 'law_env.dta'), columns=['title'])['title'].map(_norm))
alias_names = set(json.load(open(os.path.join(HERE, '_must_skip.json')))) if os.path.exists(os.path.join(HERE, '_must_skip.json')) else set()

d = json.load(open(os.path.join(HERE, '_missing_laws.json')))
rows = []
skipped_exist = skipped_alias = 0
for name in sorted(d):
    if _norm(name) in existing:
        skipped_exist += 1; continue
    if _norm(name) in ALIAS:
        skipped_alias += 1; continue
    v = d[name]
    typ, lvl = infer(name)
    if 'url' in v:
        rows.append({'title': name, 'type': typ, 'category': typ, 'status': '未知',
                     'publish': pub_of(v['paras']), 'region_level': lvl,
                     'province_name': prov_of(name), 'source_id': v['url'],
                     'content': '\n'.join(v['paras'])})
    else:
        rows.append({'title': name, 'type': typ, 'category': typ, 'status': '未知',
                     'publish': '', 'region_level': lvl,
                     'province_name': prov_of(name), 'source_id': '未获取原文',
                     'content': ''})
df = pd.DataFrame(rows)
df.to_csv(OUT, index=False, encoding='utf-8')
print(f'跳过（库内已有）{skipped_exist} 条；跳过（别名映射）{skipped_alias} 条')
print(f'待补入 {len(df)} 条 | 有原文 {int((df.content.str.len()>0).sum())} | 空壳 {int((df.content.str.len()==0).sum())}')
print(df['type'].value_counts().to_string())
print('\n按层级:', df['region_level'].value_counts().sort_index().to_dict())
