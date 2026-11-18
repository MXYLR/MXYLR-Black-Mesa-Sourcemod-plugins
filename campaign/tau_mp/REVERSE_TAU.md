# BM weapon_tau（Tau 高斯炮）逆向笔记

> 目标：让 `hl1tau.smx` 全量重写 BM 原生 tau 开火，还原 HL1 `weapon_gauss` 行为。
> 本文件固化上一轮会话 + 本轮补的逆向结论，避免重启即丢。
> 工具：`smx_analysis/re_dll.py` / `re_tau_new.py` / `sig_check.py`（镜像基址 0x10000000）。

> ⚠ **地址版本**：**§1–§10 的地址全部取自旧 build**
> （`F:\BMServer\bms\bin\server.dll`，9,509,376 bytes，md5 `68278cc0c3a1e23d96c2b9d722ae7670`）。
> 2026-11-17 Steam 更新后的新 build（9,530,984 bytes，md5
> `421fee309fdc22f3dc7b5207a4810c3e`）地址对照见 **§11**。
> 两版之间**不是整体平移**（tau 区域 +0x1620、`CTauBeam` 区域 +0x10C0、
> `TakeDamage` 只有 +0xF0、摔伤函数 +0xE40），所以别拿某个固定 delta 去换算别处。
> 两处补丁的 gamedata 签名对两版都唯一命中，**插件侧无需按版本分支**。

## 1. 类结构与地址（VA @ 0x10000000 优选基址）

- `CWeapon_Tau`：TypeDescriptor @ `0x1082df20`，COL @ `0x1079aab8`，**vtable @ `0x1072d6b8`**。
- `CWeapon_Tau` vtable 覆写（其余槽位继承自基础武器类）：
  - `[0]`  = `0x1048c580` 构造
  - `[11]` = `0x1048cb70` GetDataDescMap
  - `[12]` = `0x1048d8c0`
  - `[13]` = `0x1048cb50`
  - `[25]` = `0x1048d4d0` **Precache**
  - `[235]`= `0x1048cb80`
- **主/副攻未在覆写表里 → 开火逻辑继承自基础武器类**，tau 专属部分在 `CTauBeam`（普通 C++ 类，非 CBaseEntity）。
- `CTauBeam` 方法（连续区间 `0x10350540`–`0x10351530`）：
  - `0x10350640` damage（伤害函数）
  - `0x10350d40` **ProgressBeam**（推进/穿墙/分裂；日志串 `0x106a9248` `"CTauBeam::ProgressBeam: Perform penetration and split tau beam.."`，push 点在 `0x10350e19`，已复核）
  - `0x10351200` penetrate
  - `0x10351530` reflect
  - `0x10350540` dir

## 2. 伤害函数（`0x10350640`）内部常量（上一轮）

- 伤害类型：`0x500`（未蓄满）/ `0x1500`（蓄满，含 `DMG_BULLET` 0x2 之类组合）。
- float 常量：threshold `0.45`、dmg_base `0.20`、scale `1.25`、RandomFloat 范围 `200.0`–`400.0`。
- 开火时内联读 ConVar `GetFloat()`（对象 `0x110f9e40`/`0x110f9eb8`）→ **实时读，非地图缓存**。
- 蓄力→伤害的精确映射公式**未完全解码**（0.45/0.20/1.25 的确切语义待补）；但对插件无影响——本插件是**替换**这条逻辑，用 HL1 公式 `伤害 = 200×(t/1.5)`。

## 3. 全量 ConVar 清单（`sk_weapon_tau_*`，默认值）

| ConVar | 默认 |
|---|---|
| `sk_weapon_tau_overcharge_bais` | 0.9 |
| `sk_weapon_tau_overcharge_damage` | 75 |
| `sk_weapon_tau_overcharge_radius` | 200 |
| `sk_weapon_tau_beam_undercharged_dmg` | 20 |
| `sk_weapon_tau_beam_charged_dmg` | 120 |
| **`sk_weapon_tau_beam_dmg_radius`** | **64**（固定溅射半径，HL1 为动态 dmg×2.5）|
| `sk_weapon_tau_beam_penetration_bias` | 0.9 |
| `sk_weapon_tau_beam_penetration_depth` | 48 |
| `sk_weapon_tau_charge_max_velocity` | 500 |
| `sk_weapon_tau_primary_attack_delay` | 0.3 |
| `sk_weapon_tau_full_charge_required_ammo` | 12.0 |
| `sk_weapon_tau_full_charge_time` | 1.5 |
| `sk_weapon_tau_min_charge_time` | 0.3 |
| `sk_weapon_tau_overcharge_time` | 7.5 |
| `sk_weapon_tau_max_coil_speed` | 1200 |
| `sk_weapon_tau_idle_spin_speed` | 1700 |
| `sk_weapon_tau_beam_spread_min` | 32 |
| `sk_weapon_tau_beam_spread_max` | 128 |

ConVar 字符串在 `0x1072d444`–`0x1072d694`。flags `0x2100`（NOTIFY|REPLICATED，无 CHEAT）→ server.cfg 可设。

## 4. 资源（Precache @ `0x1048d4d0`，统一走 `0x1019f0a0` 通用 precache）

- 声音：`tau_fire`、`tau_charge`、`tau_charge_fire`、**`tau_charge_explode`**（← 证明 BM 过载是**爆炸**，非 HL1 自伤）、`electrical_zap`（`0x1069f5ac`）。
- 光束 sprite：`tau_beam_glow`、`tau_beam`、`tau_beam_view`、`tau_wave`（`0x1072dd80`–`0x1072ddac`）。
- 通用光束材质候选（备用视觉）：`sprites/laserbeam.vmt`（`0x105f6bc9`）、`effects/blueblacklargebeam.vmt`（`0x1073905c`）、`sprites/redlaserbeam.vmt`（`0x1073e4f4`）。

## 5. 弹药

- BM tau 用 **`energy` 弹药**（`item_ammo_energy` @ `0x1061c100`；`sk_ammo_energy_max` @ `0x10677e0c`），与 gluon 共用。世界模型 `models/weapons/w_gaussammo.mdl`（`0x10692b18`）。
- HL1 对应物是 `uranium`（gauss 与 egon 共用）→ BM 把名字换成了 `energy`，语义等价。
- 插件侧消费：读 `m_iPrimaryAmmoType` 得索引，`FindSendPropInfo("m_iAmmo")` + `SetEntData` 裸写（同 `bms_match.sp` `Bms_ResetAmmo`），**不硬编码名字**。

## 6. 已知 datamap/netprop（复用自二进制插件 `bms_weapon_tauStuckFix`）

- 实体类名：`weapon_tau`（另有 `item_weapon_tau` 拾取物）。
- 属性：`m_hActiveWeapon`（玩家当前武器）、`m_bInTauAttack`（tau 蓄力/攻击态，**本 server.dll 字符串表未搜到该名，可能命名不同或仅客户端 dll 有，运行时以 FindSendPropOffs 实测为准**）、`m_iAmmo`、`m_iPrimaryAmmoType`。

## 7. 待运行时实测（spike 解决，静态无法定）

- **光束是否客户端预测**：决定 `buttons=0` 抑制是否干净（最大风险）。
- 原生是否自带击退（副攻开火反冲）。
- 原生过载爆炸的确切触发与伤害路径（已能通过 `sk_weapon_tau_overcharge_time` 拉大禁用）。
- `m_bInTauAttack` 的真实可用名/偏移（`FindSendPropOffs` 实测）。

## 8. 与 HL1 对照（本插件要还原的差异）

| 项 | BM 原生 | HL1 gauss |
|---|---|---|
| 主攻伤害 | 20（undercharged）| 20 |
| 满蓄伤害 | 120 | 200 |
| 溅射半径 | 固定 64 | 动态 dmg×2.5 |
| 穿墙 | 固定深度 48，**不减伤**（bias 死 ConVar）| 线性扣伤 dmg−墙厚，门槛 n<dmg |
| 过载 | 爆炸 75/200 | 自伤 50 DMG_SHOCK |
| 蓄力时长 | 1.5s | 1.5s（MP）|
| 弹药 | energy（原生扣法）| 主攻2发 / 副攻1发起转+0.1s/发 |

## 9. 穿墙逆向实锤（2026-08-27）

- **`sk_weapon_tau_beam_penetration_depth`（48）实时读**：`CTauBeam::penetrate`（0x10351200）内 GetFloat 内联读对象 `0x110fa020` 值字段 `0x110fa04c`。语义 =「墙厚 ≤ depth 才穿透」。
- **`sk_weapon_tau_beam_penetration_bias`（0.9）是死 ConVar**：对象 `0x110f9fa8` 全镜像仅 2 处 dword 引用（静态初始化器 0x1002d140 + 注册表区 0x105bf831），穿透/伤害代码**零引用** → BM 穿透**不衰减伤害**。
- **穿透不减伤**：`penetrate` 递归 `ProgressBeam`（0x103514fc）时伤害参数 `[ebp+0x10]` 原样传递，无 `−= 墙厚`、无 `×bias`。
- **墙厚算法**：入口点 `[esi+0xc/0x10/0x14]` 与出口点 `[ebp-0x58]`（trace 出口）的欧氏距离；取绝对值后与 depth 比较。
- **穿透次数限制**：`penetrate` 开头 byte `[esi+0x36]`/`[esi+0x37]` 门控（未全解码，疑似「已反射/已穿透次数」标志）。

ConVar 对象地址（静态初始化器 0x1002d0d0–0x1002d184 实锤）：
- `sk_weapon_tau_beam_charged_dmg` → 0x110f9eb8
- `sk_weapon_tau_beam_dmg_radius` → 0x110f9f30
- `sk_weapon_tau_beam_penetration_bias` → 0x110f9fa8（死）
- `sk_weapon_tau_beam_penetration_depth` → 0x110fa020（实时读，运行期可改）

damage 函数 `0x10350640` 常量（伤害映射/过载，**非穿墙衰减**）：threshold 0.45(0x105f1bcc)、dmg_base 0.2(0x105d660c)、0.5(0x105d6618)、scale 1.25(0x1061e2a4)、RandomFloat 200–400(0x105daa9c/0x105daaac)。ProgressBeam 开头伤害下限 0.1(0x105d6600)。

## 10. 单人/多人分支逆向实锤（2026-09-13，tau_mp 插件）

**SP/MP 共用同一份 server.dll**（md5 68278cc0c3a1e23d96c2b9d722ae7670，gameinfo type "both"），
差异来自 cfg（skill.cfg vs config_deathmatch.cfg）+ 代码里的
**`CMultiplayRules::IsMultiplayer()`** 分支。

- **分发方式**：`mov ecx,[0x1086c5cc]`（全局 g_pGameRules）→ `mov eax,[ecx]` →
  `call [eax+0x88]`。即 **vtable 字节偏移 0x88 = 索引 34**（gamedata windows "34"）。
- **`CWeapon_Tau::FireBeam` = 0x1048c780**（签名与 SourceCoop 一致，本地复核唯一命中：
  `55 8B EC 83 EC 5C 56 57 8B F9`）。函数内 IsMultiplayer 判定在 **0x1048c8ad**：
  - 多人分支（0x1048c9ab–0x1048c9b5）保留击退三轴分量；
  - 单人分支执行 `mov dword ptr [ebp-0x18], 0`（**0x1048ca18**）把**垂直分量清零**
    → **单人高斯跳被代码级禁用，纯 ConVar 改不出来**。
- **蓄力副攻函数 = 0x1048d6e0**（BM 未导出名字，本仓库称 `CWeapon_Tau::ChargeFire`；
  签名 `55 8B EC 83 EC 08 56 57 8B F1 E8`，唯一命中；唯一调用者 0x1048d1ae，
  在函数 0x1048d0b0 内）。函数内 IsMultiplayer 判定在 **0x1048d82c**：
  - 多人 → `call 0x1048fc50`（写 `this+0x4a0`）：把副攻冷却设成 curtime = **立即可再射**；
  - 单人 → `call 0x1048fa80`（写 `this+0x49c`）：`time = SequenceDuration(开火动画)`
    → `nextAttack = curtime + 动画时长` = **真实硬直**。
  两条分支随后都调用 `FireBeam`。
- 该函数读 `sk_weapon_tau_full_charge_time`（对象 **0x110fa200**，值字段 0x110fa21c）
  —— **运行期实时读**，故插件可直接改 ConVar 生效。
- FireBeam 的 E8 调用点：0x1048d64a / 0x1048d672 / 0x1048d86e / 0x1048d893
  （后两个在 ChargeFire 尾部）。

### tau ConVar 对象（静态初始化器实锤）
| ConVar | 对象地址 | SP 值 | MP 值 |
|---|---|---|---|
| `sk_weapon_tau_charge_max_velocity` | 0x110fa098（索引 9）| 650 | 850 |
| `sk_weapon_tau_full_charge_required_ammo` | 0x110fa188（索引 11）| 12 | 11 |
| `sk_weapon_tau_full_charge_time` | 0x110fa200（索引 12）| 1.5 | 1.25 |
| `sk_weapon_tau_beam_charged_dmg` | 0x110f9eb8（索引 5）| 120 | 120 |

对象排布：`sk_weapon_tau_beam_undercharged_dmg` = 0x110f9e40 起，**stride 0x78**。

### 落地
`plugins/tau_mp.smx` + `gamedata/tau_mp.games.txt`：DHooks 挂钩
`CMultiplayRules::IsMultiplayer`（gamerules 虚函数，默认不干预）+ detour
`FireBeam` 与 `ChargeFire`（pre 强制 true / post 复位），仅 tau 生效。
gamedata 模板取自 SourceCoop（ampreeT/SourceCoop）`gamedata/srccoop.games.txt`，
DHooks 用 v2 API（`DynamicHook.FromConf` / `DynamicDetour.FromConf`，**不是**
SourceCoop 用的 `LoadDHookVirtual`/`LoadDHookDetour` —— 本机 dhooks.inc 无这两个 native）。

## 11. 2026-11-17 游戏更新复核（Steam 自动更新）

Steam 今日更新 Black Mesa：

- 新 build `F:\SteamLibrary\steamapps\common\Black Mesa\bms\bin\server.dll`
  = 9,530,984 bytes，md5 **`421fee309fdc22f3dc7b5207a4810c3e`**
  （旧 9,509,376 / `68278cc0…`）。`client.dll` 同时更新。
- 生产 DM 服 `F:/BMServer` 是独立安装、**仍是旧二进制** → 现在两台机器不再同 md5。
- 节表：`.text` VA 0x10001000，VSize **0x5C27F8**（旧 0x5C1188，+0x1670）；
  ImageBase 0x10000000 / SizeOfImage 0x1212000；`.rdata` 0x105C4000、`.data` 0x107A4000、
  `.reloc` 0x1112D000。

### 11.1 这次更新改了什么（`.rdata` 字符串差集：新增 33 / 删除 9）

只有单人战役内容和地图构建工具，**死斗侧零改动**：

- 新实体类 `CLogicSkill` / `CLogicSkillPuzzle`（类名 `logic_skill` / `logic_skill_puzzle`；
  inputs `GetSkill` / `SetFrameRate`，outputs `m_OnSkill1/2/3`，keyvalue `skill_puzzle`）。
- 新的地图工具串：`rebuildparallaxcubemapvolumes`、`building_parallaxcubemapvolumes`、
  `maps/%s.pcv`、`parallax`、`boxmin` / `boxmax`。
- 新字段 `m_flLastMovementTagTime`（datamap 偏移 **0x1488**，追加在类尾 → 低于它的字段不受影响）。
- **零 ConVar 变化**：`sk_*` / `mp_*` / `sv_*` / `weapon_*` 前缀的字符串一个没多、一个没少。
- 删掉的 9 条全是相邻字符串前后缀位移造成的假阳性（如 `DCRotorWashShooter` → `CRotorWashShooter`），
  不是真的删了类。

### 11.2 我们依赖的东西：全部未变

| 依赖 | 结论 |
|---|---|
| tau 两条补丁签名 | **仍唯一命中**（磁盘镜像 + 模拟 ASLR 各 1 处），落在 `0x1048DEF8` / `0x1048EE60`；签名串一个字节没改 |
| `IsMultiplayer` 槽位 | 仍是 `[eax+0x88]`（索引 34） |
| SDKHooks `OnTakeDamage` | 仍是槽 68 = `[eax+0x110]`；`TakeDamage` 内派发点 `0x1011C48C` |
| SDKHooks `OnTakeDamage_Alive` | 仍是槽 292 = `[eax+0x490]`，5 处派发点形状一致 |
| 其它查过的虚槽 | AcceptInput 39 / Teleport 118 / EyeAngles 141 / Ignite 227 / Extinguish 231 / Weapon_GetSlot 288 / RemovePlayerItem 290 —— 派发点数两版完全相同 |
| BMAG 裸偏移 `player+0x94d`（suit charged） | 两版各 21 处位移引用；置 1 / 清 0 两个写点形状一致 |
| BMAG 的 24 个 datamap 属性名 | 全部存在；能静态解出偏移的那些（`m_iRoundTime` 0x35C、`m_bRemoveable` 0x4C4、`m_iPrimaryAmmoType` 0x4D8、`m_flNextPrimaryAttack` 0x49C、`m_flNextSecondaryAttack` 0x4A0、`m_iClip1/2` 0x4E0/0x4E4 等）**两版完全一致** |
| sdktools `FireOutput` 签名 | 仍唯一命中（`0x101460E0`） |

⇒ **tau_mp 与 BMAG 都不用改代码、不用重编译**，只有注释里的地址要跟着更新。

### 11.3 一个看着吓人但其实无关的变化：gamerules 虚表整体 +0x10

`FlPlayerFallDamage` 的虚调用从 `[eax+0x100]` 挪到 `[eax+0x110]`，摔伤函数里另一处
从 `[eax+0x118]` 挪到 `[eax+0x128]`，而 `IsMultiplayer` 仍在 `[eax+0x88]`
→ 即 vtable 在槽 34 与槽 64 之间插入了 4 个槽。

**不影响我们**：BMAG 的 `m_iRoundTime` 走 datamap / Prop_Data 按名取；
tau_mp 的跌落封顶走 `SDKHook_OnTakeDamage`（**实体** vtable 槽 68，不是 gamerules vtable）；
DHooks 那条路早已弃用（原因见 §10 末尾）。`CMultiplayRules::IsMultiplayer` 槽也没动，
所以 `IsMultiplayer` 判定点本身不受影响。

### 11.4 新旧地址对照（本节是权威表）

| 项 | 旧 build | 新 build |
|---|---|---|
| `CWeapon_Tau` TypeDescriptor | 0x1082DF20 | 0x1082F2A0 |
| `CWeapon_Tau` [0] ctor | 0x1048C580 | 0x1048DBA0 |
| `CWeapon_Tau` [11] GetDataDescMap | 0x1048CB70 | 0x1048E190 |
| `CWeapon_Tau` [13] | 0x1048CB50 | 0x1048E170 |
| `CWeapon_Tau` [235] | 0x1048CB80 | 0x1048E1A0 |
| **`FireBeam` 入口** | 0x1048C780 | **0x1048DDA0** |
| ├ IsMultiplayer 判定点 | 0x1048C8AD | 0x1048DECD |
| ├ 单人 `je` | 0x1048C8D8 | **0x1048DEF8** |
| ├ 多人路径起点 | 0x1048C8DE | 0x1048DEFE |
| ├ 单人 Z 清零 `mov [ebp-0x18],0` | 0x1048CA18 | 0x1048E038 |
| └ 两路合流点 | 0x1048CA3B | 0x1048E05B |
| **`ChargeFire` 入口** | 0x1048D6E0 | **0x1048ED00** |
| ├ 唯一调用者 / 所在函数 | 0x1048D1AE / 0x1048D0B0 | 0x1048E7CE / 0x1048E6D0 |
| ├ IsMultiplayer 判定点 | 0x1048D82C | 0x1048EE4C |
| ├ 单人 `je` | 0x1048D840 | **0x1048EE60** |
| └ MP 冷却 / SP 动画冷却调用 | 0x1048FC50 / 0x1048FA80 | 0x10491270 / 0x104910A0 |
| `FireBeam` 的 4 个 E8 调用点 | D64A / D672 / D86E / D893 | EC6A / EC92 / EE8E / EEB3 |
| `CTauBeam::dir` | 0x10350540 | 0x10351600 |
| `CTauBeam::damage` | 0x10350640 | 0x10351700 |
| `CTauBeam::ProgressBeam` | 0x10350D40 | 0x10351E00 |
| ├ 日志 push 点 | 0x10350E19 | 0x10351ED9 |
| └ 递归 penetrate 点 | 0x103514FC | 0x103525BC |
| `CTauBeam::penetrate` | 0x10351200 | 0x103522C0 |
| `CTauBeam::reflect` | 0x10351530 | 0x103525F0 |
| 通用 precache | 0x1019F0A0 | 0x1019F190 |
| `PlayerFallingDamage` | 0x101D1FA0 | 0x101D2DE0 |
| `CBaseEntity::TakeDamage` | 0x1011C1A0 | 0x1011C290 |
| └ `OnTakeDamage` 派发点 | 0x1011C39C | 0x1011C48C |
| `CTakeDamageInfo` ctor | 0x10292D90 | 0x10293E50 |
| `g_pGameRules` 全局 | 0x1086C5CC | 0x1086D94C |

`.rdata` 常量同步漂移：`0.45` 0x105F1BCC→0x105F2BF4、`dmg_base 0.2` 0x105D660C→0x105D762C、
`0.5` 0x105D6618→0x105D7638、`scale 1.25` 0x1061E2A4→0x1061F2CC、
RandomFloat 200/400 0x105DAA9C/0x105DAAAC→0x105DBABC/0x105DBACC、
ProgressBeam 伤害下限 0.1 0x105D6600→0x105D7620。

`.data` 里的 tau ConVar 对象（§9/§10 那批 `0x110f9e40`–`0x110fa21c`）整块平移，
新 build 里 `FireBeam` 引用的同类对象是 **0x110FB5E0** 系。这些地址只在运行时内存操作时才需要；
插件一律用 `FindConVar("sk_weapon_tau_…")` 按名取，与地址无关。
（`sk_weapon_tau_*` 的 name 字符串新 build 在 `0x1072EE34` 起，全部还在。）

§1 里另有两项用序言字节匹配不出来（`vtable @ 0x1072D6B8`、`COL @ 0x1079AAB8`）：
vtable 内部全是重定位后的代码指针、COL 是 .data 结构，都要按槽/按类名反查；
插件不读它们，暂不重算。

### 11.5 `GiveNamedItem` 派发点数 24→22（记录一下，无需处理）

`call dword [reg+0x698]`（槽 422）的调用点从 24 降到 22。同批核对的其它热门槽
（68 / 292 / 39 / 118 / 141 / 227 / 231 / 288 / 290）两版完全一致，所以这**不是** vtable 位移，
而是两处调用被重构。**本仓库没有任何插件用 `GivePlayerItem` / `GiveNamedItem`**，可忽略。
