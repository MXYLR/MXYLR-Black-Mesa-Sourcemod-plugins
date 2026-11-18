"""Locate the client.dll slotN command handler and its input gate.

Step 1: find the "slot0".."slot10" string VAs and every code site that
references them, so we can identify the shared ConCommand callback.
"""

import struct
import sys

import capstone
import pefile

DLL = r"F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\client.dll"

pe = pefile.PE(DLL, fast_load=True)
data = open(DLL, "rb").read()
image_base = pe.OPTIONAL_HEADER.ImageBase

sections = []
for s in pe.sections:
    sections.append((s.Name.rstrip(b"\0").decode(), image_base + s.VirtualAddress,
                     s.VirtualAddress, s.Misc_VirtualSize, s.PointerToRawData, s.SizeOfRawData))


def va_to_off(va):
    for name, sva, rva, vsize, rptr, rsize in sections:
        if sva <= va < sva + max(vsize, rsize):
            return rptr + (va - sva)
    return None


text = [s for s in sections if s[0] == ".text"][0]
_, text_va, _, text_vsize, text_ptr, text_rsize = text
text_bytes = data[text_ptr:text_ptr + text_rsize]

names = ["slot%d" % i for i in range(0, 11)]
found = {}

for n in names:
    needle = n.encode() + b"\0"
    start = 0
    while True:
        i = data.find(needle, start)
        if i < 0:
            break
        start = i + 1
        # skip hits that are part of a longer identifier (e.g. "slot1_foo")
        if i > 0 and (data[i - 1:i][0:1].isalnum() or data[i - 1:i] == b"_"):
            continue
        va = None
        for name, sva, rva, vsize, rptr, rsize in sections:
            if rptr <= i < rptr + rsize:
                va = sva + (i - rptr)
                break
        if va is not None:
            found.setdefault(n, []).append((i, va))

for n in names:
    for off, va in found.get(n, []):
        print("%-6s file=%#x va=%#x" % (n, off, va))

# xref scan: any 4-byte immediate in .text equal to one of those VAs
print("\n-- code references --")
for n in names:
    for off, va in found.get(n, []):
        pat = struct.pack("<I", va)
        start = 0
        while True:
            j = text_bytes.find(pat, start)
            if j < 0:
                break
            start = j + 1
            print("%-6s va=%#x  ref at text+%#x (va %#x)" % (n, va, j, text_va + j))
