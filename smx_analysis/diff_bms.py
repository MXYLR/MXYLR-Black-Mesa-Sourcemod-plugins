# -*- coding: utf-8 -*-
"""对比 Steam(新版)与 DM 服(旧版)的 bms 游戏内容, 列出需要同步的文件。

只关心游戏内容(server.dll + *.vpk + 顶层 txt), 忽略 DM 专用目录(addons/cfg/configs)。
按 (存在性, 大小, md5) 判定变更; md5 只对大小不同或大小相同的可疑文件算。
"""
import sys, io, os, hashlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

STEAM = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms'
DM = r'F:\BMServer\bms'


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def collect(base):
    out = {}
    # 顶层文件(vpk + txt 等)
    for name in os.listdir(base):
        p = os.path.join(base, name)
        if os.path.isfile(p):
            out[name] = (os.path.getsize(p), None)
    # bin/
    bindir = os.path.join(base, 'bin')
    if os.path.isdir(bindir):
        for name in os.listdir(bindir):
            p = os.path.join(bindir, name)
            if os.path.isfile(p):
                out['bin/' + name] = (os.path.getsize(p), None)
    return out


steam = collect(STEAM)
dm = collect(DM)

only_steam = sorted(set(steam) - set(dm))
only_dm = sorted(set(dm) - set(steam))
changed = []
unchanged = []
for name in sorted(set(steam) & set(dm)):
    ss, _ = steam[name]
    ds, _ = dm[name]
    if ss != ds:
        changed.append(name)
    else:
        unchanged.append(name)

print('=== 仅 Steam 有(新增文件): %d ===' % len(only_steam))
for n in only_steam:
    print('  + %s  (%d B)' % (n, steam[n][0]))

print('\n=== 仅 DM 服有(DM 专用/多余): %d ===' % len(only_dm))
for n in only_dm:
    print('  - %s  (%d B)' % (n, dm[n][0]))

print('\n=== 大小不同(需同步): %d ===' % len(changed))
total = 0
for n in changed:
    ss, ds = steam[n][0], dm[n][0]
    total += ss
    print('  ~ %-45s  Steam %10d  ->  DM %10d  (%+d)' % (n, ss, ds, ss - ds))
print('  需同步总大小: %.2f GB' % (total / 1e9))

print('\n=== 大小相同(不变): %d ===' % len(unchanged))
for n in unchanged:
    print('  = %s' % n)
