"""Disassemble CHudHintDisplay::Paint in client.dll and find how the
background box width is derived (text extent vs. panel m_flWide).

Usage: python -I re_hintdisplay.py [start_va] [count]
"""

import sys

import capstone
import pefile

DLL = r"F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\client.dll"

pe = pefile.PE(DLL, fast_load=True)
data = open(DLL, "rb").read()
base = pe.OPTIONAL_HEADER.ImageBase

secs = []
for s in pe.sections:
    secs.append((s.Name.rstrip(b"\0").decode(), base + s.VirtualAddress,
                 s.Misc_VirtualSize, s.PointerToRawData, s.SizeOfRawData))


def va_to_off(va):
    for n, sva, vsize, rptr, rsize in secs:
        if sva <= va < sva + max(vsize, rsize):
            return rptr + (va - sva)
    return None


def off_to_va(off):
    for n, sva, vsize, rptr, rsize in secs:
        if rptr <= off < rptr + rsize:
            return sva + (off - rptr)
    return None


def dis(va, count, label=""):
    off = va_to_off(va)
    if off is None:
        print("!! %#x not mapped" % va)
        return
    print("\n=== %s %#x ===" % (label, va))
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = False
    for ins in md.disasm(data[off:off + count * 8], va):
        print("  %#010x  %-24s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))
        count -= 1
        if count <= 0:
            break


if __name__ == "__main__":
    start = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x1015a3c0
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    dis(start, n, "hint display")
