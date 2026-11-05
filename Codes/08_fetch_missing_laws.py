#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""08_fetch_missing_laws.py —— 为 law_refered 中未匹配的法律抓取原文

流程：Bing 站内检索 → 取候选页 → 校验（含法名、条文数≥5）→ 截取正文
结果存 Codes/_missing_laws.json，可按名称断点续跑。
用法：python3 Codes/08_fetch_missing_laws.py [--limit N]
"""
import json, os, re, sys, html, time, urllib.parse, warnings
import requests
warnings.filterwarnings('ignore')

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(HERE, '_missing_laws.json')
UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9'}
ART  = re.compile(r'^第[一二三四五六七八九十百零]+条')
CHAP = re.compile(r'^第[一二三四五六七八九十]+章')
JUNK = re.compile(r'^(\[?[大中小]\]?|日期[:：].*|文号[:：]|浏览量.*|来\s*源[:：].*|编\s*辑[:：].*|责\s*编[:：].*|\d{4}年\d{2}月\d{2}日\s+\d{2}:\d{2})$')
FOOT = ('责任编辑','责       编','编       辑','版权所有','主办：','承办：','ICP','京公网','-->','网站地图','联系我们','扫一扫','打印本页')
TYPO = {'中华民族共和国森林法':'中华人民共和国森林法',
        '中国人民共和国森林法':'中华人民共和国森林法',
        '中国人民共和国水污染防治法':'中华人民共和国水污染防治法'}

def norms(s):
    return re.sub(r'[（(][^）)]*[）)]$','', re.sub(r'\s+','', str(s or '').replace('《','').replace('》','')))

def bing(q):
    try:
        r = requests.get('https://cn.bing.com/search?q=' + urllib.parse.quote(q), headers=UA, timeout=20)
        return [u for u in re.findall(r'<li class="b_algo".*?<h2><a[^>]+href="([^"]+)"', r.text, flags=re.S) if 'gov.cn' in u]
    except Exception:
        return []

def lines_of(txt):
    t = re.sub(r'<script.*?</script>', '', txt, flags=re.S|re.I)
    t = re.sub(r'<style.*?</style>', '', t, flags=re.S|re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '\n', t))
    return [l.replace('\xa0',' ').strip() for l in t.split('\n') if l.strip()]

def build(name, lines):
    arts = [i for i,l in enumerate(lines) if ART.match(l)]
    if len(arts) < 5: return None
    start = next((i for i,l in enumerate(lines)
                  if (l == name or (l.startswith(name) and len(l) <= len(name)+30 and '_' not in l)) and arts[0] > i), arts[0])
    last = arts[-1]
    end = last + (2 if re.fullmatch(r'第[一二三四五六七八九十百零]+条', lines[last]) else 1)
    seg = [l for l in lines[start:end] if not JUNK.match(l)]
    seg[0] = name
    merged = []
    for l in seg:
        if re.fullmatch(r'第[一二三四五六七八九十百零]+条', l): merged.append(l + '　')
        elif merged and merged[-1].endswith('　'): merged[-1] += l
        else: merged.append(l)
    return merged

def fetch(name):
    for q in (f'"{name}" site:gov.cn', f'{name} 全文'):
        for u in bing(q)[:3]:
            try:
                r = requests.get(u, headers=UA, timeout=20, verify=False)
            except Exception as ex:
                continue
            if r.status_code != 200: continue
            txt = r.content.decode('utf-8', 'ignore')
            if txt.count('�') > 50: txt = r.content.decode('gb18030', 'ignore')
            b = build(name, lines_of(txt))
            if b and name in '\n'.join(b[:2]):
                return {'url': u, 'paras': b, 'arts': len([l for l in b if ART.match(l)]), 'chars': len('\n'.join(b))}
        time.sleep(1)
    return None

def main():
    import pandas as pd
    e = pd.read_stata(os.path.join(ROOT, 'law_refered.dta'))
    names = [n for n in sorted(set(e.loc[e.refered_law_id.isna(), 'refered_law'])) if n not in TYPO]
    done = json.load(open(OUT)) if os.path.exists(OUT) else {}
    todo = [n for n in names if n not in done]
    limit = None
    if '--limit' in sys.argv: limit = int(sys.argv[sys.argv.index('--limit')+1]); todo = todo[:limit]
    print(f'待抓取 {len(todo)} 个（已完成 {len(done)}/{len(names)}）', flush=True)
    for i, n in enumerate(todo, 1):
        res = fetch(n)
        done[n] = res if res else {'fail': True}
        if i % 5 == 0 or i == len(todo):
            json.dump(done, open(OUT,'w'), ensure_ascii=False)
            ok = sum(1 for v in done.values() if v and not v.get('fail'))
            print(f'  [{i}/{len(todo)}] 成功 {ok}/{len(done)}', flush=True)
    json.dump(done, open(OUT,'w'), ensure_ascii=False)
    ok = [k for k,v in done.items() if v and not v.get('fail')]
    print(f'完成：成功 {len(ok)}，失败 {len(done)-len(ok)}', flush=True)

if __name__ == '__main__':
    main()
