# -*- coding: utf-8 -*-
"""对比新旧 server.dll 里 suit 字节(玩家+0x94d / 子对象+0x91)的访问。

目的: 新二进制(2026-11-17)是否仍把 suit 字节放在 player+0x94d。
BMAG.smx 在 SP 环境(新二进制)每次重生 SetEntData(player, 0x94d, 1), 偏移若漂了会写错字段。
"""
import sys, io
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

OLD = r'F:\BMServer\bms\bin\server.dll'
NEW = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\server.dll'


def load(path):
    raw = open(path, 'rb').read()
    pe = pefile.PE(path, fast_load=True)
    base = pe.OPTIONAL_HEADER.ImageBase
    secs = []
    for s in pe.sections:
        name = s.Name.rstrip(b'\x00').decode('latin1')
        va = s.VirtualAddress
        vsize = max(s.Misc_VirtualSize, s.SizeOfRawData)
        raw_off = s.PointerToRawData
        secs.append((name, va, va + vsize, raw_off, s.Characteristics))
    return raw, pe, base, secs


def va2off(secs, base, va):
    rva = va - base
    for name, v0, v1, raw_off, ch in secs:
        if v0 <= rva < v1:
            return raw_off + (rva - v0)
    return None


def scan_disp(path, label):
    raw, pe, base, secs = load(path)
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True
    res = {0x8BC: [], 0x94D: [], 0x91: []}
    for name, v0, v1, raw_off, ch in secs:
        if not (ch & 0x20000000):
            continue
        code = raw[raw_off: raw_off + (v1 - v0)]
        va0 = base + v0
        for insn in md.disasm(code, va0):
            for op in insn.operands:
                if op.type == 3 and op.mem.disp in res:
                    res[op.mem.disp].append(insn)
                    break
    print('\n===== %s (%s) =====' % (label, path))
    for disp in (0x8BC, 0x94D, 0x91):
        lst = res[disp]
        print('  disp 0x%X: %d 处' % (disp, len(lst)))
        for insn in lst[:6]:
            print('      0x%08X  %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))


scan_disp(OLD, '旧 server.dll (68278cc0)')
scan_disp(NEW, '新 server.dll (421fee30)')


# 旧 charger Use() 反汇编, 看它到底怎么读 suit 字节
print('\n===== 旧 charger Use() @0x411880 / @0x42a1ce =====')
raw, pe, base, secs = load(OLD)
md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True
for va in (0x411880, 0x42a1ce):
    off = va2off(secs, base, va)
    if off is None:
        print(' 0x%X: 无此 VA' % va)
        continue
    print(' --- 0x%X ---' % va)
    for insn in md.disasm(raw[off:off + 0x60], va):
        print('   0x%08X  %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
