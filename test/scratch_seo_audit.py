import os, re

files = [
    'index.html',
    'how-it-works.html',
    '90-ball-bingo.html',
    'pricing.html',
    'how-to-play-tambola.html',
    'how-to-play-housie.html',
    'privacy-policy.html',
    'terms-conditions.html'
]

for f in files:
    path = os.path.join('web', f)
    if not os.path.exists(path):
        continue
    with open(path, 'r', encoding='utf-8') as fh:
        c = fh.read()
    print(f"==================================================")
    print(f"FILE: {f}")
    print(f"==================================================")
    m_title = re.search(r'<title>([^<]+)</title>', c, re.IGNORECASE)
    print("Title:      ", m_title.group(1) if m_title else "MISSING")
    
    m_meta = re.search(r'<meta\s+name=["\']description["\']\s+content=["\']([^"\']+)["\']', c, re.IGNORECASE)
    if not m_meta:
        m_meta = re.search(r'<meta\s+content=["\']([^"\']+)["\']\s+name=["\']description["\']', c, re.IGNORECASE)
    print("Meta Desc:  ", m_meta.group(1) if m_meta else "MISSING")
    
    m_canon = re.search(r'<link\s+rel=["\']canonical["\']\s+href=["\']([^"\']+)["\']', c, re.IGNORECASE)
    if not m_canon:
        m_canon = re.search(r'<link\s+href=["\']([^"\']+)["\']\s+rel=["\']canonical["\']', c, re.IGNORECASE)
    print("Canonical:  ", m_canon.group(1) if m_canon else "MISSING")
    
    h1s = re.findall(r'<h1[^>]*>(.*?)</h1>', c, re.IGNORECASE | re.DOTALL)
    print(f"H1 Count:    {len(h1s)}")
    for idx, h1 in enumerate(h1s, 1):
        clean_h1 = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', h1)).strip()
        print(f"  H1 #{idx}:    {clean_h1}")
    print()
