#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""09_fetch_round2.py —— 对 08 抓取失败的法名做第二轮尝试（放宽检索）

与 08 的区别：
  - 检索词去掉 site: 限制，依次尝试 "名称" / "名称 全文" / 去前缀后的名称
  - 仍只接受 .gov.cn 页面，且需含法名、条文数≥5
  - 结果合并回 Codes/_missing_laws.json（覆盖原 fail 记录）
"""
import json, os, re, sys, html, time, urllib.parse, warnings
import requests
warnings.filterwarnings('ignore')

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(HERE, '_missing_laws.json')
UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9'}
ART = re.compile(r'^第[一二三四五六七八九十百零]+条')
JUNK = re.compile(r'^(\[?[大中小]\]?|日期[:：].*|文号[:：]|浏览量.*|来\s*源[:：].*|编\s*辑[:：].*|责\s*编[:：].*|\d{4}年\d{2}月\d{2}日\s+\d{2}:\d{2})$')

def lines_of(txt):
    t = re.sub(r'<script.*?</script>', '', txt, flags=re.S|re.I)
    t = re.sub(r'<style.*?</style>', '', t, flags=re.S|re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '\n', t))
    return [l.replace('\xa0',' ').strip() for l in t.split('\n') if l.strip()]

def bing(q):
    try:
        r = requests.get('https://cn.bing.com/search?q=' + urllib.parse.quote(q), headers=UA, timeout=20)
        return re.findall(r'<li class="b_algo".*?<h2><a[^>]+href="([^"]+)"', r.text, flags=re.S)
    except Exception:
        return []

def try_page(name, u):
    if '.gov.cn' not in u: return None
    try:
        r = requests.get(u, headers=UA, timeout=20, verify=False)
        if r.status_code != 200: return None
        txt = r.content.decode('utf-8', 'ignore')
        if txt.count('�') > 50: txt = r.content.decode('gb18030', 'ignore')
        L = lines_of(txt)
        j = '\n'.join(L)
        key = re.sub(r'^中华人民共和国', '', name)
        if key not in j: return None
        arts = len([l for l in L if ART.match(l)])
        if arts < 5: return None
        body = [l for l in L if not JUNK.match(l)]
        return {'url': u, 'paras': body, 'arts': arts, 'chars': len('\n'.join(body))}
    except Exception:
        return None

def fetch(name):
    queries = [f'"{name}"', f'{name} 全文', f'"{re.sub(r"^中华人民共和国", "", name)}" 全文']
    seen = set()
    for q in queries:
        for u in bing(q)[:4]:
            if u in seen: continue
            seen.add(u)
            r = try_page(name, u)
            if r: return r
            time.sleep(0.5)
        time.sleep(0.8)
    return None

def main():
    done = json.load(open(OUT))
    todo = [k for k, v in done.items() if v.get('fail')]
    if '--limit' in sys.argv:
        todo = todo[:int(sys.argv[sys.argv.index('--limit')+1])]
    print(f'第二轮待尝试 {len(todo)} 个', flush=True)
    for i, n in enumerate(todo, 1):
        r = fetch(n)
        if r:
            done[n] = r
            print(f'  [{i}/{len(todo)}] ✓ {n}', flush=True)
        else:
            print(f'  [{i}/{len(todo)}] ✗ {n}', flush=True)
        if i % 5 == 0: json.dump(done, open(OUT, 'w'), ensure_ascii=False)
    json.dump(done, open(OUT, 'w'), ensure_ascii=False)
    ok = sum(1 for v in done.values() if 'url' in v)
    print(f'第二轮结束：成功累计 {ok}/{len(done)}', flush=True)

if __name__ == '__main__':
    main()
