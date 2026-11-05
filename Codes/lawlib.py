#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lawlib.py —— 法规数据处理的公共函数（读写 .dta、法名归一化、引用抽取、边表构建）

设计原则：
  · 数据读写用 pyreadstat，保留 Stata 的变量标签、值标签与 publish 的 %tc 格式
  · 法名归一化与勘误集中在此，任何脚本都从 lawlib 调用，避免规则分散
"""
import re
import pandas as pd
import pyreadstat

# ---------------------------------------------------------------- 读写 ----
def read_dta(path):
    df, meta = pyreadstat.read_dta(path, apply_value_formats=False)
    return df, meta


INT_CAST = {
    'id': 'int32', 'region_level': 'int32', 'publish_year': 'Int32',
    'env_level': 'Int8', 'dup_count': 'int32', 'n_ref': 'Int32',
    'has_ref': 'Int8', 'province_code': 'Int32', 'city_code': 'Int32',
    'county_code': 'Int32',
}


def _cast_ints(df):
    """还原 Stata 的整型列，避免 pyreadstat 写成 double"""
    for c, t in INT_CAST.items():
        if c in df.columns:
            df[c] = pd.array(df[c], dtype=t)
    return df


def write_dta(df, path, meta=None, formats=None):
    """写出 .dta：用 pandas 的 writer（支持 strL 且 Stata 可正常读取）

    注意：pyreadstat 写含 strL 的数据会产生 Stata 无法打开的损坏文件，
    因此统一改用 pandas.to_stata(version=118, convert_strl=[...])。
    """
    df = _cast_ints(df.copy())
    if 'publish' in df.columns and str(df['publish'].dtype).startswith('datetime'):
        convert_dates = {'publish': 'tc'}
    else:
        convert_dates = None
    labels = dict(zip(df.columns, meta.column_labels)) if meta is not None else None
    vlabels = meta.variable_value_labels if meta is not None else None
    df.to_stata(path, version=118, write_index=False,
                convert_strl=[c for c in ('content', 'refered') if c in df.columns],
                convert_dates=convert_dates,
                data_label=(meta.file_label if meta is not None and meta.file_label else ''),
                variable_labels=labels, value_labels=vlabels)


# ------------------------------------------------------------ 法名规则 ----
ENDS = ('法', '法典', '条例', '规定', '办法', '决定', '解释', '规则', '细则')

# 明确勘误：引用写法 → 正式名称（都是同一部法的不同写法）
NAME_FIX = {
    '中华人民共和国防汛法': '中华人民共和国防洪法',
    '中华人民共和国森林法实施细则': '中华人民共和国森林法实施条例',
    '渔业法细则': '中华人民共和国渔业法实施细则',
    '中华人民共和国野生植物保护法': '中华人民共和国野生植物保护条例',
    '中华民族共和国野生植物保护条例': '中华人民共和国野生植物保护条例',
    '呼和浩特市大气污染防治管理条例': '呼和浩特市大气污染防治条例',
    '云南省风景名胜区管理条例': '云南省风景名胜区条例',
    '城市供水管理条例': '城市供水条例',
    '河北省城市市容和环境卫生管理条例': '河北省城市市容和环境卫生条例',
    '浙江省风景名胜区管理条例': '浙江省风景名胜区条例',
    '黑龙江省草原管理条例': '黑龙江省草原条例',
}
PREFIX_TYPO = {'中华民族共和国': '中华人民共和国', '中国人民共和国': '中华人民共和国'}

_TITLE = re.compile(r'《([^《》]{2,60})》')
_SPLIT = re.compile(r'[。；;\n]+')
_COMBO = re.compile(r'结合[^，。；、]{0,8}实际')
_CUE = ('制定', '制订', '授权', '作出', '决定如下', '如下决定')
_DROP = ('作相应修改', '重新公布', '根据本决定', '修正案')
_KEYW = ('根据', '依据')


def key(s):
    """法名归一化键：去书名号/尖括号、去空白、去尾部括注"""
    s = str(s or '')
    for ch in '《》＜＞<>':
        s = s.replace(ch, '')
    s = re.sub(r'\s+', '', s)
    return re.sub(r'[（(][^）)]*[）)]$', '', s)


class NameResolver:
    """把引用里的法名解析为库内正式名称"""

    def __init__(self, titles):
        self.lib = {key(t) for t in titles}

    def __call__(self, name):
        name = name.replace('＜', '《').replace('＞', '》')
        name = NAME_FIX.get(name, name)
        for bad, good in PREFIX_TYPO.items():
            if name.startswith(bad):
                name = good + name[len(bad):]
                break
        if key(name) not in self.lib and name.startswith('中华人民共和国'):
            short = name[len('中华人民共和国'):]
            if key(short) in self.lib:
                return short
        return name


def extract_refered(text, own_title, doc_type, resolve):
    """从正文抽取"立法依据"句中的法律名称（已按 resolve 归一化）"""
    if not isinstance(text, str) or '《' not in text:
        return []
    if '修改' in str(doc_type) or '废止' in str(doc_type):
        return []
    hits = []
    for sent in _SPLIT.split(text):
        if '《' not in sent or not any(k in sent for k in _KEYW):
            continue
        if any(d in sent for d in _DROP):
            continue
        if not (any(c in sent for c in _CUE) or _COMBO.search(sent)):
            continue
        for m in _TITLE.finditer(sent):
            name = re.sub(r'\s+', '', m.group(1))
            if not (4 <= len(name) <= 60):
                continue
            if re.search(r'[〈〉<>]', name):
                continue
            if any(w in name for w in ('修改', '废止', '修正')):
                continue
            if not name.endswith(ENDS):
                continue
            name = resolve(name)
            if own_title and own_title in name:
                continue
            hits.append(name)
    kept = [n for n in hits if not any(n != o and n in o for o in hits)]
    seen, uniq = set(), []
    for n in kept:
        if n not in seen:
            seen.add(n)
            uniq.append(n)
    return uniq


def add_refered_columns(df):
    """为 dataframe 计算 refered / n_ref / has_ref 三列"""
    resolve = NameResolver(df['title'].astype(str))
    lists = [extract_refered(c, str(t), ty, resolve)
             for c, t, ty in zip(df['content'], df['title'], df['type'])]
    df['refered'] = ['；'.join(v) for v in lists]
    df['n_ref'] = [len(v) for v in lists]
    df['has_ref'] = (df['n_ref'] > 0).astype('int8')
    return df


def build_edges(df):
    """由 refered 列生成引用关系边表，并附上引用方/被引方的原始属性

    引用方属性（raw_*）：年份、行政层级、法规类型、省份、城市、环保分类
    被引方属性（refered_*）：年份、行政层级、法规类型
    """
    # 名称 → 唯一 id：同年取最小 id；跨年取最新 publish_year
    tmp = df[['id', 'title', 'publish_year']].copy()
    tmp['k'] = tmp['title'].map(key)
    tmp['py'] = tmp['publish_year'].fillna(-1)
    tmp = tmp.sort_values(['k', 'py', 'id'], ascending=[True, False, True])
    lookup = tmp.drop_duplicates('k').set_index('k')['id'].to_dict()

    rows = []
    for rid, rtitle, ref in zip(df['id'], df['title'], df['refered'].fillna('')):
        for name in str(ref).split('；'):
            name = name.strip()
            if name:
                rows.append((rtitle, int(rid), name, lookup.get(key(name))))
    edges = pd.DataFrame(rows, columns=['raw_law', 'raw_law_id', 'refered_law', 'refered_law_id'])
    edges['refered_law_id'] = pd.array(edges['refered_law_id'], dtype='Int64')

    # ---- 附加属性 ----
    attrs = ['id', 'publish_year', 'region_level', 'type', 'province_name',
             'province_code', 'city_name', 'env_level', 'env_topic']
    a = df[attrs].copy()
    raw = a.rename(columns={
        'id': 'raw_law_id', 'publish_year': 'raw_year', 'region_level': 'raw_level',
        'type': 'raw_type', 'province_name': 'raw_province',
        'province_code': 'raw_province_code', 'city_name': 'raw_city',
        'env_level': 'raw_env_level', 'env_topic': 'raw_env_topic'})
    ref = a.rename(columns={
        'id': 'refered_law_id', 'publish_year': 'refered_year',
        'region_level': 'refered_level', 'type': 'refered_type',
        'province_name': 'refered_province', 'province_code': 'refered_province_code'})
    ref = ref[['refered_law_id', 'refered_year', 'refered_level', 'refered_type',
               'refered_province', 'refered_province_code']]

    edges = edges.merge(raw, on='raw_law_id', how='left')
    edges = edges.merge(ref, on='refered_law_id', how='left')
    edges['refered_law_id'] = pd.array(edges['refered_law_id'], dtype='Int64')
    for c in ('raw_year', 'refered_year', 'raw_level', 'refered_level',
              'raw_province_code', 'refered_province_code'):
        if c in edges.columns:
            edges[c] = pd.array(edges[c], dtype='Int32')
    if 'raw_env_level' in edges.columns:
        edges['raw_env_level'] = pd.array(edges['raw_env_level'], dtype='Int8')
    return edges
