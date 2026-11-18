# -*- coding: utf-8 -*-
"""核实新 server.dll 里 CBlackMesaPlayer 的 suit 字节偏移 0x94d 是否仍在(布局未变)。

旧结论(见 memory bms-suit-charge-byte):
  字节 player+0x94d = 'suit charged' 门; 属于 player+0x8bc 处子对象(0x940-0x960 数据块)。
  子对象 vtable 初始化形如 `mov [reg+0x8bc], <vtable>`(旧 0x326c0b: mov [edi+0x8bc], 0x1064be28)。
  两个 setter: set-1(幂等) / set-0(死代码)。
这里只在新 DLL 里找这两类 disp32 访问, 看偏移是否仍是 0x8bc / 0x94d。
"""
import sys, io, struct
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

DLL = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\server.dll'
raw = open(DLL, 'rb').read()
pe = pefile.PE(DLL, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase

secs = []
for s in pe.sections:
    name = s.Name.rstrip(b'\x00').decode('latin1')
    va = s.VirtualAddress
    vsize = max(s.Misc_VirtualSize, s.SizeOfRawData)
    raw_off = s.PointerToRawData
    secs.append((name, va, va + vsize, raw_off, s.Characteristics))


def va2off(va):
    rva = va - base
    for name, v0, v1, raw_off, ch in secs:
        if v0 <= rva < v1:
            return raw_off + (rva - v0)
    return None


def off2va(off):
    for name, v0, v1, raw_off, ch in secs:
        if raw_off <= off < raw_off + (v1 - v0):
            return base + v0 + (off - raw_off)
    return None


md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True


def disasm_at(va, n=24):
    off = va2off(va)
    if off is None:
        return []
    return list(md.disasm(raw[off:off + n], va))


# 方法 1: 在 .text 里线性反汇编, 找 disp==0x8bc / 0x94d 的访存。
# 只扫可执行节, 且只记录 mem 操作数带这两个 disp 的指令。
TARGETS = {0x8BC: 'sub-object vtable (player+0x8bc)', 0x94D: 'suit byte (player+0x94d)'}

found = {0x8BC: [], 0x94D: []}
for name, v0, v1, raw_off, ch in secs:
    if not (ch & 0x20000000):  # IMAGE_SCN_MEM_EXECUTE
        continue
    code = raw[raw_off: raw_off + (v1 - v0)]
    va0 = base + v0
    for insn in md.disasm(code, va0):
        ops = insn.operands
        hit = None
        for op in ops:
            if op.type == 3:  # X86_OP_MEM
                disp = op.mem.disp
                if disp in TARGETS:
                    hit = disp
                    break
        if hit is not None:
            found[hit].append(insn)
            if len(found[hit]) > 12:
                # 提前终止? 不行, 还是要扫完以知总数, 但先收集
                pass

for disp in (0x8BC, 0x94D):
    lst = found[disp]
    print('\n===== disp 0x%X (%s): %d 处 =====' % (disp, TARGETS[disp], len(lst)))
    for insn in lst[:12]:
        print('  0x%08X  %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
    if len(lst) > 12:
        print('  ... 共 %d 处, 只显示前 12' % len(lst))
