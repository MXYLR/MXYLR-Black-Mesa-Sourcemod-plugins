# -*- coding: utf-8 -*-
"""同步 DM 服 bin/ 引擎 DLL 到 Steam 新版。

只同步 DM 服 bin/ 里已有、且客户端里版本更新(尺寸不同)的 DLL;
先备份旧 DLL 到 bin/backup_20260823/, 拷贝后校验 md5。
"""
import os, sys, io, hashlib, shutil

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

STEAM_BIN = r'F:\SteamLibrary\steamapps\common\Black Mesa\bin'
DM_BIN = r'F:\BMServer\bin'
BAK = os.path.join(DM_BIN, 'backup_20260823')


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()


os.makedirs(BAK, exist_ok=True)

# 列出 DM 服 bin/ 里的 DLL
dm_dlls = sorted(n for n in os.listdir(DM_BIN) if n.lower().endswith('.dll'))

sync = []
for name in dm_dlls:
    sp = os.path.join(STEAM_BIN, name)
    dp = os.path.join(DM_BIN, name)
    if not os.path.exists(sp):
        print('  跳过(客户端无此文件): %s' % name)
        continue
    if os.path.getsize(sp) != os.path.getsize(dp) or md5(sp) != md5(dp):
        sync.append(name)
    else:
        print('  相同: %s' % name)

print()
print('需同步 %d 个引擎 DLL:' % len(sync))

ok = fail = 0
for name in sync:
    sp = os.path.join(STEAM_BIN, name)
    dp = os.path.join(DM_BIN, name)
    # 备份
    bak = os.path.join(BAK, name)
    if not os.path.exists(bak):
        shutil.copy2(dp, bak)
    # 拷贝 + 校验
    src_md5 = md5(sp)
    shutil.copyfile(sp, dp)
    dst_md5 = md5(dp)
    if dst_md5 == src_md5:
        ok += 1
        print('  OK   %-28s %.2f MB' % (name, os.path.getsize(dp) / 1e6))
    else:
        fail += 1
        print('  FAIL %s' % name)

print()
print('完成: ok=%d fail=%d (旧 DLL 备份在 %s)' % (ok, fail, BAK))
