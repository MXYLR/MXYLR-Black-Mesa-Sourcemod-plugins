# -*- coding: utf-8 -*-
"""核对新 server.dll 里 tau 的两处 IsMultiplayer 分支语义是否未变。

新 DLL = F:/SteamLibrary/steamapps/common/Black Mesa/bms/bin/server.dll (2026-11-17 更新)。
旧结论见 campaign/tau_mp/REVERSE_TAU.md。这里只做只读反汇编核对。
"""
import sys, io, struct, hashlib
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

DLL = r'F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\server.dll'

raw = open(DLL, 'rb').read()
pe = pefile.PE(DLL, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase

print('md5      = %s' % hashlib.md5(raw).hexdigest())
print('size     = %d' % len(raw))
print('ImageBase= 0x%X' % base)

# section list
secs = []
for s in pe.sections:
    name = s.Name.rstrip(b'\x00').decode('latin1')
    va = s.VirtualAddress
    vsize = max(s.Misc_VirtualSize, s.SizeOfRawData)
    raw_off = s.PointerToRawData
    secs.append((name, va, va + vsize, raw_off))


def va2off(va):
    rva = va - base
    for name, v0, v1, raw_off in secs:
        if v0 <= rva < v1:
            return raw_off + (rva - v0)
    return None


def find_bytes(bs):
    """返回所有命中的文件偏移(只在 .text 内)。"""
    hits = []
    start = 0
    while True:
        i = raw.find(bs, start)
        if i < 0:
            break
        # 只算落在某节内、且能换算成 VA 的
        for name, v0, v1, raw_off in secs:
            if raw_off <= i < raw_off + (v1 - v0):
                hits.append(base + v0 + (i - raw_off))
                break
        start = i + 1
    return hits


md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True


def disasm(va, nbytes):
    off = va2off(va)
    if off is None:
        return []
    code = raw[off: off + nbytes]
    out = []
    for insn in md.disasm(code, va):
        out.append('0x%08X  %-7s %s' % (insn.address, insn.mnemonic, insn.op_str))
    return out


# 1) 函数入口(旧签名, 看是否还唯一命中、地址移了多少)
FIRE_PROLOGUE = bytes.fromhex('558BEC83EC5C56578BF9')
CHARGE_PROLOGUE = bytes.fromhex('558BEC83EC0856578BF1E8')

fire_starts = find_bytes(FIRE_PROLOGUE)
charge_starts = find_bytes(CHARGE_PROLOGUE)
print('\n=== FireBeam prologue 55 8B EC 83 EC 5C 56 57 8B F9 ===')
print('  hits:', [hex(x) for x in fire_starts])
print('=== ChargeFire prologue 55 8B EC 83 EC 08 56 57 8B F1 E8 ===')
print('  hits:', [hex(x) for x in charge_starts])

# 2) 旧 gamedata 签名命中点(已由 sig_check 得到新地址, 这里反汇编核对语义)
FIRE_JE = 0x1048DEF8
CHARGE_JE = 0x1048EE60

print('\n=== FireBeam: 反汇编 je 附近(0x1048DEB0 .. 0x1048E000) ===')
for ln in disasm(0x1048DEB0, 0x360):
    print('  ' + ln)

print('\n=== ChargeFire: 反汇编 je 附近(0x1048EE20 .. 0x1048EF40) ===')
for ln in disasm(0x1048EE20, 0x130):
    print('  ' + ln)

# 3) ConVar 字符串是否还在
print('\n=== ConVar 字符串 ===')
for name in [b'sk_weapon_tau_charge_max_velocity\x00',
             b'sk_weapon_tau_full_charge_time\x00',
             b'sk_weapon_tau_full_charge_required_ammo\x00',
             b'sk_weapon_tau_beam_charged_dmg\x00',
             b'sk_weapon_tau_beam_dmg_radius\x00']:
    hits = find_bytes(name)
    print('  %-42s -> %s' % (name.rstrip(b'\x00').decode(), [hex(x) for x in hits]))

# 4) IsMultiplayer 派发特征: mov ecx,[abs]; mov eax,[ecx]; mov eax,[eax+0x88]; call eax
#    也就是 8B 0D ?? ?? ?? ??  8B 01  8B 80 88 00 00 00  FF D0
print('\n=== IsMultiplayer 派发(8B 0D xx 8B 01 8B 80 88 00 00 00 FF D0) ===')
ISP = bytes.fromhex('8B0D')  # 用更宽的方式扫：mov eax,[eax+0x88] 后跟 call eax
pat = bytes.fromhex('8B8088000000FFD0')
hits = find_bytes(pat)
print('  mov eax,[eax+0x88]; call eax 命中 %d 处' % len(hits))
for h in hits[:20]:
    print('    0x%08X' % h)
