# -*- coding: utf-8 -*-
"""扫 .text, 找出所有对玩家 m_iAmmo* 字段的 32 位内存访问, 打印反汇编。"""
import sys, io
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
DLL = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\server.dll'
raw = open(DLL,'rb').read()
pe = pefile.PE(DLL, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
text = [s for s in pe.sections if s.Name.rstrip(b'\x00')==b'.text'][0]
tva = text.VirtualAddress
tsz = max(text.Misc_VirtualSize, text.SizeOfRawData)
code = raw[text.PointerToRawData:text.PointerToRawData+tsz]

OFFS = {0x4e4:'Glock',0x4e8:'Mp5',0x4ec:'357',0x4f0:'Bolt',0x4f4:'Buckshot',
        0x4f8:'Energy',0x4fc:'Mp5Grenade',0x500:'RPG',0x504:'Frag',0x508:'Snark',
        0x50c:'Tripmine',0x510:'Satchel'}

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True
hits = []
CH = 0x40000
for st in range(0, len(code), CH):
    blob = code[st:st+CH]
    for ins in md.disasm(blob, base + tva + st):
        for op in ins.operands:
            if op.type == 3:  # X86_OP_MEM
                d = op.mem.disp & 0xFFFFFFFF
                if d in OFFS and op.size == 4:
                    hits.append((ins.address, OFFS[d], ins.mnemonic+' '+ins.op_str))
# group by field
from collections import defaultdict
g = defaultdict(list)
for a,f,t in hits: g[f].append((a,t))
for f in sorted(g, key=lambda x: list(OFFS.values()).index(x)):
    print("\n== %s (%d) ==" % (f, len(g[f])))
    for a,t in g[f][:14]:
        print("  0x%X  %s" % (a,t))
