"""Disassemble around the slotN ConCommand registration table (client.dll)."""

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


def off_to_va(off):
    for n, va, vsize, rptr, rsize in secs:
        if rptr <= off < rptr + rsize:
            return va + (off - rptr)
    return None


def va_to_off(va):
    for n, sva, vsize, rptr, rsize in secs:
        if sva <= va < sva + max(vsize, rsize):
            return rptr + (va - sva)
    return None


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
md.detail = False


def dis(va, count=40, label=""):
    off = va_to_off(va)
    print("\n=== %s %#x ===" % (label, va))
    code = data[off:off + count * 8]
    for ins in md.disasm(code, va):
        print("  %#010x  %-28s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))
        count -= 1
        if count <= 0:
            break


dis(0x10047c30, 60, "slot registration table")
