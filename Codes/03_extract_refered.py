#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
03_extract_refered.py —— 从 law_env.dta 的 content 中抽取「立法依据」提到的上级法律名称

输出：Codes/_refered.csv（id, refered, n_refered），供 Codes/03_refered.do 合并回 dta

抽取规则（只认“制定依据”句，不认罚则/执法引用）：
  1. 按 。；; 换行 切句；
  2. 保留同时满足下列条件的句子：
       - 含《…》且含「根据」或「依据」
       - 含「制定／制订／授权／作出／决定如下／如下决定」，或含「结合…实际」
       - 不含「作相应修改／重新公布／根据本决定／修正案」
  3. 句内所有《X》作为候选，再过滤：
       - 长度 4–60 字；以 法/法典/条例/规定/办法/决定/解释/规则/细则 结尾
       - 不含 〈〉<> （《关于修改〈X〉的决定》这类嵌套）
       - 不含「修改／废止／修正」
       - 不是文件自身的名称（排除自引）
  4. 去掉被同一文件内更长法名包含的残名（如「矿山安全法」⊂「中华人民共和国矿山安全法」）
  5. 同一文件内去重、按出现顺序用「；」连接
  6. 「修改、废止的决定」类文件不抽取（其正文引用的是被修改的法规，不构成制定依据）

用法：python3 Codes/03_extract_refered.py
"""
import os, re, sys
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))   # …/Codes
ROOT = os.path.dirname(HERE)                        # 项目根目录
SRC = os.path.join(ROOT, 'law_env.dta')
OUT = os.path.join(HERE, '_refered.csv')            # 同时生成同名 .dta 供 Stata 合并

TITLE = re.compile(r'《([^《》]{2,60})》')
SPLIT = re.compile(r'[。；;\n]+')
COMBO = re.compile(r'结合[^，。；、]{0,8}实际')
CUE   = ('制定', '制订', '授权', '作出', '决定如下', '如下决定')
DROP  = ('作相应修改', '重新公布', '根据本决定', '修正案')
KEYW  = ('根据', '依据')
ENDS  = ('法', '法典', '条例', '规定', '办法', '决定', '解释', '规则', '细则')

# 法名勘误：地方立法文本里的错写/误称，统一改为正式名称
NAME_FIX = {
    '中华人民共和国防汛法': '中华人民共和国防洪法',
    '中华人民共和国森林法实施细则': '中华人民共和国森林法实施条例',
    '渔业法细则': '中华人民共和国渔业法实施细则',
    '中华人民共和国野生植物保护法': '中华人民共和国野生植物保护条例',
    '中华民族共和国野生植物保护条例': '中华人民共和国野生植物保护条例',
}
PREFIX_TYPO = {'中华民族共和国': '中华人民共和国', '中国人民共和国': '中华人民共和国'}


def clean_title(t):
    return re.sub(r'\s+', '', str(t or '')).replace('《', '').replace('》', '')


LIB = set()


def key(s):
    s = str(s or '')
    for ch in '《》＜＞<>': s = s.replace(ch, '')
    s = re.sub(r'\s+', '', s)
    return re.sub(r'[（(][^）)]*[）)]$', '', s)


def load_lib(path):
    """记录库内已有法名（归一化），供"去多余前缀"判断使用"""
    df = pd.read_stata(path, columns=['title'])
    for t in df['title'].astype(str):
        LIB.add(key(t))


def fix_name(name):
    name = name.replace('＜', '《').replace('＞', '》')   # 全角尖括号统一为书名号
    name = NAME_FIX.get(name, name)
    for bad, good in PREFIX_TYPO.items():
        if name.startswith(bad):
            name = good + name[len(bad):]
            break
    # 多写了"中华人民共和国"前缀，而库里确有去掉前缀的名称时，按库内正式名记
    if key(name) not in LIB and name.startswith('中华人民共和国'):
        short = name[len('中华人民共和国'):]
        if key(short) in LIB:
            return short
    return name


def extract(text, own_title, doc_type):
    if not isinstance(text, str) or '《' not in text:
        return []
    if '修改' in str(doc_type) or '废止' in str(doc_type):
        return []
    hits = []
    for sent in SPLIT.split(text):
        if '《' not in sent or not any(k in sent for k in KEYW):
            continue
        if any(d in sent for d in DROP):
            continue
        if not (any(c in sent for c in CUE) or COMBO.search(sent)):
            continue
        for m in TITLE.finditer(sent):
            name = re.sub(r'\s+', '', m.group(1))   # 法规名内不应含空白/换行
            if not (4 <= len(name) <= 60):
                continue
            if re.search(r'[〈〉<>]', name):
                continue
            if any(w in name for w in ('修改', '废止', '修正')):
                continue
            if not name.endswith(ENDS):
                continue
            name = fix_name(name)
            if own_title and own_title in name:
                continue
            hits.append(name)
    # 去掉被更长法名包含的残名
    kept = [n for n in hits if not any(n != o and n in o for o in hits)]
    seen, uniq = set(), []
    for n in kept:
        if n not in seen:
            seen.add(n)
            uniq.append(n)
    return uniq


def main():
    df = pd.read_stata(SRC, columns=['id', 'title', 'content', 'type'])
    load_lib(SRC)
    assert df['id'].is_unique, 'id 不唯一，无法按 id 合并'
    lists = [extract(t, clean_title(ti), ty)
             for t, ti, ty in zip(df['content'], df['title'], df['type'])]
    out = pd.DataFrame({
        'id': df['id'],
        'refered': ['；'.join(v) for v in lists],
        'n_refered': [len(v) for v in lists],
    })
    out.to_csv(OUT, index=False, encoding='utf-8')
    out.to_stata(OUT.replace('.csv', '.dta'), write_index=False, version=118)

    n = out['n_refered']
    print(f'记录数 {len(out)}；有具名依据的 {int((n > 0).sum())} 条（{(n > 0).mean():.1%}）')
    print(f'每篇平均 {n.mean():.2f} 部，最多 {n.max()} 部；共抽到 {int(n.sum())} 次引用')
    print(f'已写出 {OUT} 与 {OUT.replace(".csv", ".dta")}')

    from collections import Counter
    cnt = Counter(x for v in lists for x in v)
    print('\n被引用最多的 15 部：')
    for k, v in cnt.most_common(15):
        print(f'  {v:5d}  {k}')


if __name__ == '__main__':
    sys.exit(main())
