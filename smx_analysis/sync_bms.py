# -*- coding: utf-8 -*-
"""把 DM 服的游戏内容同步到 Steam 新版:只拷 server.dll + 变更/新增的 .vpk。

跳过 gameinfo.txt / mapcycle.txt(DM 服自定义:含 metamod 搜索路径 + 官方 DM 地图表),
跳过 client.dll / *.log / *.cache / *.tmp / *.cfg 等运行期/客户端文件。
每文件拷贝后校验 md5。
"""
import os, sys, io, hashlib, shutil

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

STEAM = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms'
DM = r'F:\BMServer\bms'


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()


def top_files(base):
    out = {}
    for name in os.listdir(base):
        p = os.path.join(base, name)
        if os.path.isfile(p):
            out[name] = p
    bindir = os.path.join(base, 'bin')
    for name in os.listdir(bindir):
        p = os.path.join(bindir, name)
        if os.path.isfile(p):
            out['bin/' + name] = p
    return out


steam = top_files(STEAM)
dm = top_files(DM)

sync = []
for name, sp in steam.items():
    dp = dm.get(name)
    if name == 'bin/server.dll':
        sync.append(name)
    elif name.endswith('.vpk'):
        if dp is None or os.path.getsize(sp) != os.path.getsize(dp):
            sync.append(name)

sync.sort(key=lambda n: (0 if n == 'bin/server.dll' else 1, n))

total = sum(os.path.getsize(steam[n]) for n in sync)
print('需同步 %d 个文件, 共 %.2f GB' % (len(sync), total / 1e9))
print()

ok = fail = 0
for name in sync:
    sp = steam[name]
    dp = os.path.join(DM, name.replace('/', os.sep))
    os.makedirs(os.path.dirname(dp), exist_ok=True)
    src_md5 = md5(sp)
    shutil.copyfile(sp, dp)
    dst_md5 = md5(dp)
    if dst_md5 == src_md5:
        ok += 1
        print('  OK   %-42s %.2f MB' % (name, os.path.getsize(dp) / 1e6))
    else:
        fail += 1
        print('  FAIL %-42s (md5 mismatch: %s vs %s)' % (name, dst_md5, src_md5))

print()
print('完成: ok=%d fail=%d' % (ok, fail))
