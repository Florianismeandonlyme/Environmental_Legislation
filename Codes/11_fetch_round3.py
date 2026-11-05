#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""11_fetch_round3.py —— 第三轮抓取：换搜索引擎 + 跟随跳转

前两轮只用 Bing 且要求 site:gov.cn，很多省级/自治州条例没搜到。
本轮依次尝试 搜狗 → Bing → 360，并且：
  · 跟随搜狗的 /link?url= 跳转，取最终落点
  · 仅接受最终域名含 gov.cn 的页面
  · 页面需含法名、条文行 ≥5
只处理仍为空壳（_missing_laws.json 中 fail 或缺失）的法名。
"""
import json, os, re, sys, html, time, urllib.parse, warnings
import requests
warnings.filterwarnings('ignore')

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, '_missing_laws.json')
UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9'}
ART = re.compile(r'^第[一二三四五六七八九十百零]+条')
JUNK = re.compile(r'^(\[?[大中小]\]?|日期[:：].*|文号[:：]|浏览量.*|来\s*源[:：].*|编\s*辑[:：].*|责\s*编[:：].*|\d{4}年\d{2}月\d{2}日\s+\d{2}:\d{2})$')

def get(u, **kw):
    return requests.get(u, headers=UA, timeout=kw.get('timeout', 20), verify=False, allow_redirects=True)

def sogou(q):
    try:
        r = get('https://www.sogou.com/web?query=' + urllib.parse.quote(q), timeout=15)
        links = re.findall(r'<h3[^>]*>\s*<a[^>]*href="([^"]+)"', r.text)
        out = []
        for l in links[:8]:
            u = 'https://www.sogou.com' + l if l.startswith('/') else l
            try:
                rr = requests.head(u, headers=UA, timeout=12, allow_redirects=True, verify=False)
                out.append(rr.url)
            except Exception:
                pass
        return out
    except Exception:
        return []

def bing(q):
    try:
        r = get('https://cn.bing.com/search?q=' + urllib.parse.quote(q))
        return re.findall(r'<li class="b_algo".*?<h2><a[^>]+href="([^"]+)"', r.text, flags=re.S)
    except Exception:
        return []

def so360(q):
    try:
        r = get('https://www.so.com/s?q=' + urllib.parse.quote(q))
        return re.findall(r'<h3[^>]*>\s*<a[^>]*href="([^"]+)"', r.text)
    except Exception:
        return []

def lines_of(txt):
    t = re.sub(r'<script.*?</script>', '', txt, flags=re.S|re.I)
    t = re.sub(r'<style.*?</style>', '', t, flags=re.S|re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '\n', t))
    return [l.replace('\xa0',' ').strip() for l in t.split('\n') if l.strip()]

def try_page(name, u):
    if 'gov.cn' not in u: return None
    try:
        r = get(u)
        if r.status_code != 200 or 'gov.cn' not in r.url: return None
        txt = r.content.decode('utf-8', 'ignore')
        if txt.count('�') > 50: txt = r.content.decode('gb18030', 'ignore')
        L = lines_of(txt); j = '\n'.join(L)
        key = re.sub(r'^中华人民共和国', '', name)
        if key not in j: return None
        arts = len([l for l in L if ART.match(l)])
        if arts < 5: return None
        return {'url': r.url, 'paras': [l for l in L if not JUNK.match(l)],
                'arts': arts, 'chars': len(j)}
    except Exception:
        return None

def fetch(name):
    short = re.sub(r'^中华人民共和国', '', name)
    queries = [f'{name} 全文', f'"{name}"', f'{short} 条例 全文']
    for q in queries:
        for engine in (sogou, bing, so360):
            for u in engine(q)[:6]:
                r = try_page(name, u)
                if r: return r
        time.sleep(0.6)
    return None

def main():
    done = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    todo = [k for k, v in done.items() if v.get('fail')]
    if '--limit' in sys.argv:
        todo = todo[:int(sys.argv[sys.argv.index('--limit')+1])]
    print(f'第三轮待尝试 {len(todo)} 个', flush=True)
    hits = 0
    for i, n in enumerate(todo, 1):
        r = fetch(n)
        if r:
            done[n] = r; hits += 1
            print(f'  [{i}/{len(todo)}] ✓ {n}', flush=True)
        else:
            print(f'  [{i}/{len(todo)}] ✗ {n}', flush=True)
        if i % 5 == 0: json.dump(done, open(CACHE, 'w'), ensure_ascii=False)
    json.dump(done, open(CACHE, 'w'), ensure_ascii=False)
    print(f'第三轮新增 {hits} 条；累计成功 {sum(1 for v in done.values() if "url" in v)}/{len(done)}', flush=True)

if __name__ == '__main__':
    main()
