"""Disassemble the HudMsg path in client.dll.

Question: the BM HudMsg wire format carries two RGBA quads.  The engine's own
sender writes the same value into both, which says nothing about how the client
uses them.  This dumps the parser entry (0x101741a0) and the function it calls
with the parsed message (0x101736f0) so we can see whether the second quad is
stored separately (-> shadow/outline, safe to colour) or ignored.
"""

import struct
import sys

import capstone

DLL = r"F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\client.dll"


def pe_sections(data):
    e = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, e + 6)[0]
    optsz = struct.unpack_from("<H", data, e + 20)[0]
    opt = e + 24
    base = struct.unpack_from("<I", data, opt + 28)[0]
    secs = []
    s = opt + optsz
    for _ in range(nsec):
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, s + 8)
        secs.append((vaddr, vsize, rawptr, rawsize))
        s += 40
    return base, secs


def to_offset(secs, va):
    for vaddr, vsize, rawptr, rawsize in secs:
        if vaddr <= va < vaddr + max(vsize, rawsize):
            return rawptr + (va - vaddr)
    raise SystemExit("VA 0x%x not mapped" % va)


def dump(data, secs, base, va, count):
    off = to_offset(secs, va - base)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    print("--- 0x%08x ---" % va)
    for ins in md.disasm(data[off:off + count * 16], va):
        print("0x%08x  %-24s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))


def main():
    with open(DLL, "rb") as f:
        data = f.read()
    base, secs = pe_sections(data)
    print("image base 0x%08x" % base)
    for va in (0x101736f0, 0x10173c00, 0x10173d00, 0x10173e00):
        dump(data, secs, base, va, 45)


if __name__ == "__main__":
    sys.exit(main())
