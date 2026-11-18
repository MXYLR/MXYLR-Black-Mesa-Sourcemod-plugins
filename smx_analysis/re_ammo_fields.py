# -*- coding: utf-8 -*-
"""定位当前 server.dll 里玩家 m_iAmmo* 具名字段的 datamap 条目(名字指针 -> offset/type),
再扫 .text 里对这些 offset 的 32 位读写, 看是哪些函数在使用。"""
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
    secs.append((s.Name.rstrip(b'\x00').decode('latin1'), s.VirtualAddress,
                 s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData))

def va2off(va):
    rva = va - base
    for n, v0, v1, ro in secs:
        if v0 <= rva < v1:
            return ro + (rva - v0)
    return None

def off2va(off):
    for n, v0, v1, ro in secs:
        if ro <= off < ro + (v1 - v0):
            return base + v0 + (off - ro)
    return None

names = ["m_iAmmoGlock","m_iAmmoMp5","m_iAmmo357","m_iAmmoBolt","m_iAmmoBuckshot",
         "m_iAmmoEnergy","m_iAmmoMp5Grenade","m_iAmmoRPG","m_iAmmoFrag","m_iAmmoSnark",
         "m_iAmmoTripmine","m_iAmmoSatchel"]

strva = {}
for n in names:
    i = raw.find(n.encode() + b'\x00')
    if i >= 0:
        strva[n] = off2va(i)

print("== datamap 条目 (name_ptr 引用点) ==")
offsets = {}
for n, va in strva.items():
    pat = struct.pack('<I', va)
    hits = []
    i = raw.find(pat)
    while i >= 0:
        hits.append(i)
        i = raw.find(pat, i + 1)
    print("\n%s  str=%s  refs=%d" % (n, hex(va), len(hits)))
    for h in hits[:4]:
        refva = off2va(h)
        # Source 的 datamap_t 条目: { const char* szName; int offset; int type; ... }
        try:
            off, typ = struct.unpack('<ii', raw[h+4:h+12])
        except Exception:
            continue
        print("   ref@%s -> offset=0x%X type=%d" % (hex(refva), off & 0xFFFFFFFF, typ))
        if 0 < off < 0x2000 and typ in (0,1):
            offsets[n] = off
print("\n== 采用 offset ==")
for n,o in offsets.items():
    print("  %-18s 0x%x" % (n,o))
