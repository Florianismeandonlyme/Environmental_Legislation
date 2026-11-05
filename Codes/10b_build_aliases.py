#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""10b_build_aliases.py —— 生成"名称变体 → 已有记录 id"别名表

用于修正三类问题，避免把变体当新法律重复入库：
  · OCR/录入错字：中华民族共和国森林法、中国人民共和国森林法 等
  · 多写了"中华人民共和国"前缀：中华人民共和国城市供水条例
  · 全角书名号 ＜＞ 的写法差异
输出 Codes/_law_aliases.csv（ntitle, refered_law_id），供 07 合并进匹配表。
"""
import os, re
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ALIASES = {
    '中华民族共和国森林法': '中华人民共和国森林法',
    '中国人民共和国森林法': '中华人民共和国森林法',
    '中国人民共和国水污染防治法': '中华人民共和国水污染防治法',
    '中华人民共和国城市供水条例': '城市供水条例',
    '中华人民共和国基本农田保护条例': '基本农田保护条例',
    '青海省实施＜中华人民共和国野生动物保护法＞办法': '青海省实施《中华人民共和国野生动物保护法》办法',
}

def norms(s):
    s = str(s or '')
    for ch in '《》＜＞<>': s = s.replace(ch, '')
    s = re.sub(r'\s+', '', s)
    s = re.sub(r'[（(][^）)]*[）)]$', '', s)
    return s

env = pd.read_stata(os.path.join(ROOT, 'law_env.dta'), columns=['id', 'title'])
by_title = {}
for i, t in zip(env.id, env.title):
    by_title.setdefault(norms(t), int(i))

rows, miss = [], []
for a, canonical in ALIASES.items():
    cid = by_title.get(norms(canonical))
    if cid is None:
        miss.append((a, canonical)); continue
    rows.append({'ntitle': norms(a), 'refered_law_id': cid})

pd.DataFrame(rows).to_csv(os.path.join(HERE, '_law_aliases.csv'), index=False, encoding='utf-8')
print(f'别名 {len(rows)} 条已写出；目标缺失 {len(miss)}')
for m in miss: print('  未找到目标:', m)
