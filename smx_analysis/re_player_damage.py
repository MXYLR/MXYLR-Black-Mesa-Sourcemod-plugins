"""Locate CBasePlayer/CBlackMesaPlayer RTTI vtables and dump OnTakeDamage (slot 68).

Usage: python re_player_damage.py [dll] [--dump N] [--class NAME]
"""
import sys, struct, re
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

PATH = sys.argv[1] if len(sys.argv) > 1 else r"F:/SteamLibrary/steamapps/common/Black Mesa/bms/bin/server.dll"
WANT = None
DUMP = 160
args = sys.argv[2:]
if "--class" in args:
    WANT = args[args.index("--class") + 1]
if "--dump" in args:
    DUMP = int(args[args.index("--dump") + 1])

pe = pefile.PE(PATH, fast_load=True)
BASE = pe.OPTIONAL_HEADER.ImageBase
SECS = [(s.Name.rstrip(b"\0").decode(), s.VirtualAddress, s.Misc_VirtualSize,
         s.PointerToRawData, s.SizeOfRawData) for s in pe.sections]
data = open(PATH, "rb").read()


def va2off(va):
    rva = va - BASE
    for _n, vs, size, pr, rs in SECS:
        if vs <= rva < vs + max(size, rs):
            return pr + (rva - vs)
    return None


def off2va(off):
    for _n, vs, size, pr, rs in SECS:
        if pr <= off < pr + rs:
            return BASE + vs + (off - pr)
    return None


def u32(off):
    return struct.unpack_from("<I", data, off)[0]


def sec_range(name):
    for n, vs, size, pr, rs in SECS:
        if n == name:
            return pr, rs
    return None


rdata = sec_range(".rdata")
text = sec_range(".text")
text_lo, text_hi = BASE + [s for s in SECS if s[0] == ".text"][0][1], \
                   BASE + [s for s in SECS if s[0] == ".text"][0][1] + [s for s in SECS if s[0] == ".text"][0][2]


def find_vtable(cls):
    name = ("." + "?AV" + cls + "@@").encode()
    hits = [m.start() for m in re.finditer(re.escape(name) + b"\x00", data)]
    out = []
    for h in hits:
        td_off = h - 0x10
        if td_off < 0:
            continue
        if u32(td_off) < BASE:  # TD vftable ptr should be an image address
            continue
        td_va = off2va(td_off)
        td_rva = td_va - BASE
        # complete object locator referencing this TD (relative RVA at +12)
        lo, size = rdata
        for p in range(lo, lo + size - 20, 4):
            if u32(p + 12) == td_rva and u32(p) in (0, 1) and u32(p + 4) == 0:
                col_va = off2va(p)
                # find pointer to COL (vtable[-1])
                for q in range(lo, lo + size - 4, 4):
                    if u32(q) == col_va:
                        vt_va = off2va(q + 4)
                        out.append((vt_va, col_va))
    return out


if WANT:
    classes = [WANT]
else:
    classes = ["CBlackMesaPlayer", "CBaseMultiplayerPlayer", "CBasePlayer"]

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = False


def dis(va, n):
    off = va2off(va)
    if off is None:
        return []
    return list(md.disasm(data[off:off + n], va))


for cls in classes:
    vts = find_vtable(cls)
    print(f"== {cls}: {len(vts)} vtable(s)")
    for vt_va, col_va in vts:
        slot = lambda i: u32(va2off(vt_va) + 4 * i)
        print(f"   vtable {vt_va:#x} (COL {col_va:#x})  slot68(OnTakeDamage)={slot(68):#x}  slot69={slot(69):#x}")
        f = slot(68)
        if not (text_lo <= f < text_hi):
            continue
        ins = dis(f, DUMP)
        print(f"   --- {f:#x} ---")
        for i in ins:
            print(f"   {i.address:#010x}  {i.mnemonic:<7} {i.op_str}")
